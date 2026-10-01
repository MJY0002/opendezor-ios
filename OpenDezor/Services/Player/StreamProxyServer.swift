import Foundation

// MARK: - Playlist rewriting (platform-neutral, unit-tested)

/// Pure helpers for the stream proxy, kept free of Network.framework so `swift test`
/// covers them on the macOS host.
public enum StreamProxyPaths {
    /// `/<stream id>/<base64url(upstream)>/<file name>`. The file name is cosmetic: AVPlayer
    /// picks a demuxer from the extension when a host sends `application/octet-stream`.
    public static func path(streamId: String, upstream: URL) -> String {
        let encoded = Data(upstream.absoluteString.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let name = upstream.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ".-_"))) ?? ""
        return "/\(streamId)/\(encoded)/\(name.isEmpty || name == "/" ? "stream" : name)"
    }

    /// Inverse of `path`: the stream id and the upstream URL, or nil for anything else.
    public static func parse(_ path: String) -> (streamId: String, upstream: URL)? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let string = String(data: data, encoding: .utf8),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return (String(parts[0]), url)
    }

    public static func isPlaylist(contentType: String?, url: URL) -> Bool {
        let type = contentType?.lowercased() ?? ""
        return type.contains("mpegurl") || url.pathExtension.lowercased() == "m3u8"
    }

    /// Points every URI in an HLS playlist — segment lines, variant streams and the
    /// `URI="…"` attributes of keys, maps and media renditions — back at the proxy, so
    /// AVPlayer never reaches a host directly. Relative URIs resolve against `base`.
    public static func rewritePlaylist(_ text: String, base: URL, map: (URL) -> String) -> String {
        func proxied(_ raw: String) -> String {
            guard let resolved = URL(string: raw, relativeTo: base)?.absoluteURL,
                  let scheme = resolved.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return raw }
            return map(resolved)
        }
        let uriAttribute = try? NSRegularExpression(pattern: #"URI="([^"]+)""#)
        return text.components(separatedBy: .newlines).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return line }
            if !trimmed.hasPrefix("#") { return proxied(trimmed) }
            guard let regex = uriAttribute else { return line }
            var result = line
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed()
            for match in matches {
                guard let range = Range(match.range(at: 1), in: result) else { continue }
                result.replaceSubrange(range, with: proxied(String(result[range])))
            }
            return result
        }.joined(separator: "\n")
    }
}

#if canImport(Network)
import Network

// MARK: - Stream proxy

/// A loopback HTTP server AVPlayer plays films and series from, so the video itself goes
/// through the VPN.
///
/// AVFoundation has its own networking stack and ignores app proxy settings, so pointing
/// the player at a stream URL always used the device's real connection. Here the player
/// asks `127.0.0.1` instead; each request is re-issued through a URLSession bound to the
/// Shadowsocks tunnel (`VPNRoute`), with the stream's headers, and playlists are rewritten
/// so segments and keys come back through this server too. When the tunnel is down every
/// request is answered 503 — the stream stops rather than leaking the real IP.
public final class StreamProxyServer: NSObject, URLSessionDataDelegate {
    public static let shared = StreamProxyServer()

    private let queue = DispatchQueue(label: "org.opendezor.stream-proxy")
    private var listener: NWListener?
    private var port: UInt16?
    private var pendingStarts: [(Result<UInt16, Error>) -> Void] = []
    /// Headers per stream id. Nested playlist/segment URLs reuse their stream's id.
    private var streams: [String: [String: String]] = [:]
    private var session: URLSession?
    private var sessionProxy: NSDictionary?
    private var exchanges: [Int: Exchange] = [:]

    private static let highWater = 4 * 1024 * 1024
    private static let lowWater = 1 * 1024 * 1024

    /// One client request and the upstream task serving it.
    private final class Exchange {
        let connection: NWConnection
        let upstream: URL
        let streamId: String
        let isHead: Bool
        var task: URLSessionDataTask?
        var playlist: Data?
        var headersSent = false
        var pendingBytes = 0
        var suspended = false
        var finished = false

        init(connection: NWConnection, upstream: URL, streamId: String, isHead: Bool) {
            self.connection = connection
            self.upstream = upstream
            self.streamId = streamId
            self.isHead = isHead
        }
    }

    // MARK: Public API

    /// The loopback URL AVPlayer should play instead of `upstream`.
    public func proxiedURL(for upstream: URL, headers: [String: String]) async throws -> URL {
        let port = try await ensureRunning()
        let streamId = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        queue.sync {
            // A new playback replaces the old one; stale ids simply stop resolving.
            streams = [String(streamId): headers]
        }
        guard let url = URL(string: "http://127.0.0.1:\(port)\(StreamProxyPaths.path(streamId: String(streamId), upstream: upstream))") else {
            throw MediaHubError.invalidUrl(upstream.absoluteString)
        }
        return url
    }

    private func ensureRunning() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else { return }
                if let port = self.port, self.listener != nil {
                    continuation.resume(returning: port)
                    return
                }
                self.pendingStarts.append { continuation.resume(with: $0) }
                guard self.pendingStarts.count == 1 else { return }
                self.startListener()
            }
        }
    }

    private func startListener() {
        do {
            let parameters = NWParameters.tcp
            // Loopback only — this server must never be reachable from the network.
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.port = listener.port?.rawValue
                    self.flushStarts(self.port.map { .success($0) } ?? .failure(MediaHubError.networkError("port")))
                case .failed(let error):
                    self.listener = nil
                    self.port = nil
                    self.flushStarts(.failure(error))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
        } catch {
            flushStarts(.failure(error))
        }
    }

    private func flushStarts(_ result: Result<UInt16, Error>) {
        let waiting = pendingStarts
        pendingStarts = []
        waiting.forEach { $0(result) }
    }

    // MARK: Requests

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(on: connection, buffer: Data())
    }

    private func readRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.handle(String(decoding: buffer[..<end.lowerBound], as: UTF8.self), on: connection)
            } else if error != nil || isComplete || buffer.count > 32 * 1024 {
                connection.cancel()
            } else {
                self.readRequest(on: connection, buffer: buffer)
            }
        }
    }

    private func handle(_ head: String, on connection: NWConnection) {
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return respond(400, on: connection) }
        let method = String(requestLine[0]).uppercased()
        guard method == "GET" || method == "HEAD" else { return respond(405, on: connection) }

        var clientHeaders: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            clientHeaders[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        guard let (streamId, upstream) = StreamProxyPaths.parse(String(requestLine[1])),
              let streamHeaders = streams[streamId] else { return respond(404, on: connection) }

        // Fail closed: without a verified tunnel nothing is fetched at all.
        guard let proxy = VPNRoute.proxyDictionary else { return respond(503, on: connection) }

        var request = URLRequest(url: upstream)
        request.httpMethod = method
        request.timeoutInterval = 30
        for (key, value) in streamHeaders { request.setValue(value, forHTTPHeaderField: key) }
        if let range = clientHeaders["range"] { request.setValue(range, forHTTPHeaderField: "Range") }
        // Byte ranges and Content-Length must describe the bytes the player receives.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let exchange = Exchange(connection: connection, upstream: upstream, streamId: streamId, isHead: method == "HEAD")
        let task = urlSession(for: proxy).dataTask(with: request)
        exchange.task = task
        exchanges[task.taskIdentifier] = exchange

        connection.stateUpdateHandler = { [weak self, weak task] state in
            switch state {
            case .failed, .cancelled:
                // The player moved on (seek, stop): stop pulling bytes it will never read.
                task?.cancel()
                if let id = task?.taskIdentifier { self?.exchanges.removeValue(forKey: id) }
            default:
                break
            }
        }
        task.resume()
    }

    private func urlSession(for proxy: [AnyHashable: Any]) -> URLSession {
        let key = NSDictionary(dictionary: proxy)
        if let session, sessionProxy == key { return session }
        session?.invalidateAndCancel()
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = proxy
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegateQueue = OperationQueue()
        delegateQueue.underlyingQueue = queue
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        self.session = session
        self.sessionProxy = key
        return session
    }

    // MARK: URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let exchange = exchanges[dataTask.taskIdentifier], let http = response as? HTTPURLResponse else {
            return completionHandler(.cancel)
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        if StreamProxyPaths.isPlaylist(contentType: contentType, url: http.url ?? exchange.upstream), (200...299).contains(http.statusCode) {
            exchange.playlist = Data()
            return completionHandler(.allow)
        }

        var headers: [String] = []
        if let contentType { headers.append("Content-Type: \(contentType)") }
        if http.expectedContentLength >= 0 { headers.append("Content-Length: \(http.expectedContentLength)") }
        if let range = http.value(forHTTPHeaderField: "Content-Range") { headers.append("Content-Range: \(range)") }
        headers.append("Accept-Ranges: \(http.value(forHTTPHeaderField: "Accept-Ranges") ?? "bytes")")
        sendHead(status: http.statusCode, headers: headers, on: exchange)

        if exchange.isHead {
            completionHandler(.cancel)
            close(exchange)
        } else {
            completionHandler(.allow)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let exchange = exchanges[dataTask.taskIdentifier] else { return }
        if exchange.playlist != nil {
            exchange.playlist?.append(data)
            return
        }
        // Back-pressure: the network can outrun the player by far, and a whole film
        // must not pile up in memory.
        exchange.pendingBytes += data.count
        if exchange.pendingBytes > Self.highWater, !exchange.suspended {
            exchange.suspended = true
            dataTask.suspend()
        }
        exchange.connection.send(content: data, completion: .contentProcessed { [weak exchange] _ in
            guard let exchange else { return }
            exchange.pendingBytes -= data.count
            if exchange.suspended, exchange.pendingBytes < Self.lowWater {
                exchange.suspended = false
                exchange.task?.resume()
            }
        })
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let exchange = exchanges.removeValue(forKey: task.taskIdentifier) else { return }
        if let playlist = exchange.playlist, error == nil {
            let base = task.response?.url ?? exchange.upstream
            let port = self.port ?? 0
            let rewritten = StreamProxyPaths.rewritePlaylist(String(decoding: playlist, as: UTF8.self), base: base) { url in
                "http://127.0.0.1:\(port)\(StreamProxyPaths.path(streamId: exchange.streamId, upstream: url))"
            }
            let body = Data(rewritten.utf8)
            sendHead(status: 200, headers: [
                "Content-Type: application/vnd.apple.mpegurl",
                "Content-Length: \(body.count)"
            ], on: exchange)
            if !exchange.isHead { exchange.connection.send(content: body, completion: .contentProcessed { _ in }) }
        } else if error != nil, !exchange.headersSent {
            sendHead(status: 502, headers: ["Content-Length: 0"], on: exchange)
        }
        close(exchange)
    }

    // MARK: Writing

    private func sendHead(status: Int, headers: [String], on exchange: Exchange) {
        guard !exchange.headersSent else { return }
        exchange.headersSent = true
        let reason = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        let head = (["HTTP/1.1 \(status) \(reason)"] + headers + ["Connection: close", "", ""]).joined(separator: "\r\n")
        exchange.connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
    }

    private func respond(_ status: Int, on connection: NWConnection) {
        let reason = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8), isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Ends the response once everything queued before it has been written.
    private func close(_ exchange: Exchange) {
        guard !exchange.finished else { return }
        exchange.finished = true
        exchange.connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                                 completion: .contentProcessed { [connection = exchange.connection] _ in
            connection.cancel()
        })
    }
}
#endif
