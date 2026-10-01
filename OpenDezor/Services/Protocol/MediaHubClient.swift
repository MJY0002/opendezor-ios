import Foundation

// MARK: - MediaHub Errors
public enum MediaHubError: LocalizedError, Equatable {
    case invalidUrl(String)
    case discoveryFailed(String)
    case httpError(statusCode: Int, message: String)
    case decodingError(String)
    case noSourcesFound
    case resolveFailed(String)
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidUrl(let url):
            return "\(L("Ungültige URL")): \(url)"
        case .discoveryFailed(let reason):
            return "\(L("Addon konnte nicht erkannt werden")): \(reason)"
        case .httpError(let code, let msg):
            return "\(L("HTTP-Fehler")) \(code): \(msg)"
        case .decodingError(let msg):
            return "\(L("Fehler beim Parsen der Server-Antwort")): \(msg)"
        case .noSourcesFound:
            return L("Keine Videoquellen für diesen Titel gefunden.")
        case .resolveFailed(let msg):
            return "\(L("Stream-URL konnte nicht aufgelöst werden")): \(msg)"
        case .networkError(let msg):
            return "\(L("Netzwerkfehler")): \(msg)"
        }
    }
}

// MARK: - MediaHub Client Implementation
//
// Every action method below carries its own Swift default arguments, so callers can omit
// the optional ones. There is deliberately no protocol: nothing ever had a second
// implementation, and the tests inject a mock `URLSession` rather than a mock client.
public class MediaHubClient {
    public static let shared = MediaHubClient()
    
    public static let defaultUserAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 OpenDezor/1.0"
    
    public let session: URLSession
    public var userLanguage: String = "de"
    public var userRegion: String = "DE"
    public var customUserAgent: String = defaultUserAgent
    
    public init(session: URLSession? = nil) {
        if let customSession = session {
            self.session = customSession
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 30
            config.waitsForConnectivity = false
            config.httpAdditionalHeaders = [
                "User-Agent": Self.defaultUserAgent,
                "Accept": "application/json, text/plain, */*"
            ]
            self.session = URLSession(configuration: config)
        }
    }
    
    // MARK: - Addon Discovery Helper
    public func detectAndLoadAddon(from inputUrl: String) async throws -> (manifest: AddonManifest, endpoint: String) {
        let detector = AddonDetector(client: self)
        return try await detector.detect(from: inputUrl)
    }

    // MARK: - Retry
    //
    // Addon hosts are frequently flaky, and a single dropped connection used to leave a
    // catalog row empty for the whole session. Only transport failures and 5xx are
    // retried — a 4xx or a validation error would just be re-sent verbatim.

    private static let maxAttempts = 3

    /// Base for the exponential backoff. Tests set this to 0 so a deliberate failure case
    /// does not spend seconds sleeping.
    public var retryBaseDelay: TimeInterval = 0.4

    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 0..<Self.maxAttempts {
            do {
                return try await operation()
            } catch let error as MediaHubError {
                guard Self.isRetryable(error), attempt < Self.maxAttempts - 1 else { throw error }
                lastError = error
            } catch {
                throw error
            }
            // 0.4s, then 0.8s — enough for a blip, short enough not to feel stuck.
            guard retryBaseDelay > 0 else { continue }
            let delay = UInt64(retryBaseDelay * pow(2.0, Double(attempt)) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
        }
        throw lastError ?? MediaHubError.networkError("unknown")
    }

    private static func isRetryable(_ error: MediaHubError) -> Bool {
        switch error {
        case .networkError:
            return true
        case .httpError(let statusCode, _):
            return statusCode >= 500 || statusCode == -1 || statusCode == 429
        default:
            return false
        }
    }

    // MARK: - Endpoint / Action URL Construction
    //
    // Mirrors `stripAddonUrl` / `getCleanAddonUrl` from the official MediaHubMX SDK:
    // an addon lives at `<base>/<engine>.json`, and every action is a POST to
    // `<base>/<engine>-<action>.json` — NOT to `<base>/<action>`.
    // `engine` is either `mediahubmx` or `mediaurl`, decided by the manifest that was found.

    /// Splits an endpoint into its base URL and protocol engine. An endpoint that still
    /// carries its manifest filename determines the engine; anything else defaults to
    /// `mediahubmx`.
    public static func splitEndpoint(_ endpoint: String) -> (base: String, engine: String) {
        var clean = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.lowercased().hasPrefix("http://") && !clean.lowercased().hasPrefix("https://") {
            clean = "https://" + clean
        }

        var engine = "mediahubmx"
        if let match = clean.range(
            of: "/(mediahubmx|mediaurl)[^/]*\\.json$",
            options: [.regularExpression, .caseInsensitive]
        ) {
            engine = clean[match].lowercased().contains("mediaurl") ? "mediaurl" : "mediahubmx"
            clean = String(clean[clean.startIndex..<match.lowerBound])
        }
        while clean.hasSuffix("/") {
            clean = String(clean.dropLast())
        }
        return (clean, engine)
    }

    /// Full URL for one protocol action, e.g. `https://host/mediahubmx-catalog.json`.
    public static func actionUrl(endpoint: String, action: String) -> String {
        let (base, engine) = splitEndpoint(endpoint)
        return action == "addon"
            ? "\(base)/\(engine).json"
            : "\(base)/\(engine)-\(action).json"
    }

    // MARK: - Transport

    /// One round trip, with the transport and status-code error mapping that every caller
    /// shares. Returns the `HTTPURLResponse` so callers that care about the post-redirect
    /// URL can read it.
    private func send(_ request: URLRequest, using transport: URLSession? = nil) async throws -> (data: Data, response: HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await (transport ?? session).data(for: request)
        } catch {
            throw MediaHubError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw MediaHubError.httpError(statusCode: -1, message: L("Keine gültige HTTP-Antwort"))
        }
        guard (200...299).contains(http.statusCode) else {
            throw MediaHubError.httpError(
                statusCode: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return (data, http)
    }

    // MARK: - Fetch Manifest (GET)

    /// Fetches a manifest and reports the URL it was actually served from, so redirects
    /// (an old host redirecting to a new one) do not leave the caller pointing at a stale host.
    public func fetchManifestResolvingRedirects(from urlString: String) async throws -> (manifest: AddonManifest, finalUrl: String) {
        guard let url = URL(string: urlString) else {
            throw MediaHubError.invalidUrl(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(customUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        let (data, http) = try await send(request)

        do {
            let manifest = try JSONDecoder().decode(AddonManifest.self, from: data)
            return (manifest, http.url?.absoluteString ?? urlString)
        } catch {
            throw MediaHubError.decodingError("\(L("Fehler beim Dekodieren des Manifests")): \(error.localizedDescription)")
        }
    }

    public func fetchManifest(from urlString: String) async throws -> AddonManifest {
        try await fetchManifestResolvingRedirects(from: urlString).manifest
    }

    // MARK: - Fetch Addon Info (POST action=addon)
    public func fetchAddonInfo(endpoint: String) async throws -> AddonManifest {
        return try await executeAction(endpoint: endpoint, action: "addon", body: [:], as: AddonManifest.self)
    }
    
    // MARK: - Catalog Action (POST action=catalog)
    public func fetchCatalog(
        endpoint: String,
        catalogId: String,
        id: String? = nil,
        search: String? = nil,
        sort: String? = nil,
        filter: [String: Any]? = nil,
        cursor: String? = nil,
        adult: Bool = false
    ) async throws -> CatalogResponse {
        // CatalogRequest marks id/adult/search/sort/filter/cursor as required, so they are
        // always sent — omitting an empty one makes the addon reject the call with
        // {"error":"Validation error"}.
        let body: [String: Any] = [
            "catalogId": catalogId,
            "id": id ?? "",
            "adult": adult,
            "search": search ?? "",
            "sort": sort ?? "",
            "filter": filter ?? [:],
            "cursor": cursor ?? NSNull()
        ]

        return try await executeAction(endpoint: endpoint, action: "catalog", body: body, as: CatalogResponse.self)
    }
    
    // MARK: - Item Detail Action (POST action=item)
    public func fetchItemDetail(
        endpoint: String,
        itemType: String,
        ids: [String: String],
        name: String
    ) async throws -> MediaItem {
        let body: [String: Any] = [
            "type": itemType,
            "ids": ids,
            "name": name
        ]
        return try await executeAction(endpoint: endpoint, action: "item", body: body, as: MediaItem.self)
    }
    
    // MARK: - Sources Action (POST action=source)
    public func fetchSources(
        endpoint: String,
        item: MediaItem,
        episode: SeriesEpisodeItem? = nil
    ) async throws -> [MediaSource] {
        var body: [String: Any] = [
            "type": item.type ?? "movie",
            "ids": item.ids ?? ["id": item.id],
            "name": item.displayName
        ]
        
        if let ep = episode {
            body["episode"] = [
                "ids": ep.ids ?? ["id": ep.id],
                "name": ep.displayName,
                "season": ep.season,
                "episode": ep.episode
            ]
        }
        
        do {
            // Some addons answer `null` when it has nothing for the title — that is an empty
            // list, not a decoding failure.
            let sources = try await executeAction(endpoint: endpoint, action: "source", body: body, as: [MediaSource]?.self)
            return sources ?? []
        } catch {
            // Some MediaHub addons return a single MediaSource object instead of an array
            if let single = try? await executeAction(endpoint: endpoint, action: "source", body: body, as: MediaSource.self) {
                return [single]
            }
            throw error
        }
    }
    
    // MARK: - Subtitles Action (POST action=subtitle)
    public func fetchSubtitles(
        endpoint: String,
        item: MediaItem,
        episode: SeriesEpisodeItem? = nil
    ) async throws -> [Subtitle] {
        var body: [String: Any] = [
            "type": item.type ?? "movie",
            "ids": item.ids ?? ["id": item.id],
            "name": item.displayName
        ]
        
        if let ep = episode {
            body["episode"] = [
                "ids": ep.ids ?? ["id": ep.id],
                "name": ep.displayName,
                "season": ep.season,
                "episode": ep.episode
            ]
        }
        
        do {
            return try await executeAction(endpoint: endpoint, action: "subtitle", body: body, as: [Subtitle].self)
        } catch {
            if let single = try? await executeAction(endpoint: endpoint, action: "subtitle", body: body, as: Subtitle.self) {
                return [single]
            }
            throw error
        }
    }
    
    // MARK: - Resolve Action (POST action=resolve)
    public func resolveSource(
        endpoint: String,
        sourceUrl: String,
        headers: [String: String]? = nil
    ) async throws -> ResolvedUrl {
        var body: [String: Any] = [
            "url": sourceUrl,
            "region": userRegion
        ]
        if let h = headers, !h.isEmpty {
            body["headers"] = h
        }
        
        // One request, decoded leniently: a resolve can run several addon tasks (hoster
        // page fetches), so retrying it just to try another response shape is expensive.
        let result = try await executeAction(endpoint: endpoint, action: "resolve", body: body, as: ResolveResponse.self)
        guard let resolved = result.first else {
            throw MediaHubError.resolveFailed(sourceUrl)
        }
        return resolved
    }

    /// Resolvers answer with one ResolvedUrl, a list of them, or `null`.
    private struct ResolveResponse: Decodable {
        let first: ResolvedUrl?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                first = nil
            } else if let single = try? container.decode(ResolvedUrl.self) {
                first = single
            } else {
                first = try container.decode([ResolvedUrl].self).first
            }
        }
    }
    
    // MARK: - Generic Action Dispatcher
    public func executeAction<T: Decodable>(
        endpoint: String,
        action: String,
        body: [String: Any],
        as type: T.Type
    ) async throws -> T {
        try await withRetry {
            try await performAction(endpoint: endpoint, action: action, body: body, as: type)
        }
    }

    private func performAction<T: Decodable>(
        endpoint: String,
        action: String,
        body: [String: Any],
        as type: T.Type
    ) async throws -> T {
        let actionUrlString = Self.actionUrl(endpoint: endpoint, action: action)
        guard let url = URL(string: actionUrlString) else {
            throw MediaHubError.invalidUrl(actionUrlString)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(customUserAgent, forHTTPHeaderField: "User-Agent")
        
        // Inject the Dezor device token. Stored in the Keychain via TokenStore, which is
        // also what CustomResourceLoader reads — change the header logic in both or neither.
        if let userToken = TokenStore.token, !userToken.isEmpty {
            request.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
            request.setValue(userToken, forHTTPHeaderField: "x-user-token")
            request.setValue(userToken, forHTTPHeaderField: "x-dezor-token")
        }
        
        var fullPayload = body
        if fullPayload["language"] == nil {
            fullPayload["language"] = userLanguage
        }
        if fullPayload["region"] == nil {
            fullPayload["region"] = userRegion
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: fullPayload, options: [])
        } catch {
            throw MediaHubError.decodingError("\(L("Fehler beim Serialisieren des Payloads")): \(error.localizedDescription)")
        }
        
        // The playback path goes through the VPN: the addon sees the same address the
        // stream is played from, and never the user's own.
        let transport = Self.playbackActions.contains(action) ? vpnSession() : nil
        let (firstResponse, _) = try await send(request, using: transport)
        let data = try await completeTasks(firstResponse, request: request, using: transport)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MediaHubError.decodingError("\(L("Fehler beim Dekodieren von")) \(action) (\(T.self)): \(error.localizedDescription)")
        }
    }

    // MARK: - VPN transport

    /// Actions that are part of starting playback. Browsing (catalog, item) stays direct.
    static let playbackActions: Set<String> = ["source", "resolve", "subtitle"]

    private let vpnSessionLock = NSLock()
    private var cachedVPNSession: (proxy: NSDictionary, session: URLSession)?

    /// A session bound to the verified VPN tunnel, or nil while it is down. Rebuilt only
    /// when the tunnel's proxy settings change (another server, a new local port).
    private func vpnSession() -> URLSession? {
        guard let proxy = VPNRoute.proxyDictionary else { return nil }
        let key = NSDictionary(dictionary: proxy)
        vpnSessionLock.lock()
        defer { vpnSessionLock.unlock() }
        if let cached = cachedVPNSession, cached.proxy == key { return cached.session }
        cachedVPNSession?.session.finishTasksAndInvalidate()
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = proxy
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = session.configuration.httpAdditionalHeaders
        let tunnel = URLSession(configuration: config)
        cachedVPNSession = (key, tunnel)
        return tunnel
    }

    // MARK: - Addon Tasks

    /// MediaHubMX addons may answer an action with a task instead of a result:
    /// `{"kind":"taskRequest","id":…,"data":{"type":"fetch",…}}`. The client runs it and
    /// POSTs `{"kind":"taskResponse","id":…,"data":…}` to the same action URL until a real
    /// result arrives (@mediahubmx/client's `AddonClass.call`). Hoster resolvers do
    /// this for every hoster, because the page has to be fetched from the viewer's IP.
    /// Without it every film fell back to the hoster's HTML page and the player sat black
    /// at 00:00.
    static let maxTaskRounds = 25

    private func completeTasks(_ initial: Data, request: URLRequest, using transport: URLSession?) async throws -> Data {
        var data = initial
        for _ in 0..<Self.maxTaskRounds {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["kind"] as? String == "taskRequest" else { return data }

            let task = object["data"] as? [String: Any] ?? [:]
            let result: [String: Any]
            do {
                result = try await runTask(task)
            } catch {
                // The addon decides what a failed task means; it is told, not skipped.
                result = ["error": error.localizedDescription]
            }

            var reply = request
            reply.httpBody = try JSONSerialization.data(withJSONObject: [
                "kind": "taskResponse",
                "id": object["id"] as? String ?? "",
                "data": result
            ])
            data = try await send(reply, using: transport).data
        }
        throw MediaHubError.resolveFailed(L("Das Addon hat zu viele Aufgaben gestellt"))
    }

    private func runTask(_ task: [String: Any]) async throws -> [String: Any] {
        let type = task["type"] as? String ?? ""
        switch type {
        case "fetch":
            return try await runFetchTask(task)
        case "toast", "notification":
            return ["type": type]
        default:
            // recaptcha needs an interactive challenge this client does not offer.
            throw MediaHubError.resolveFailed("\(L("Nicht unterstützte Addon-Aufgabe")): \(type)")
        }
    }

    /// Follows the MediaHubMX fetch-task contract: cache-busting `_t`, no cookies, the
    /// addon's own method/headers/body, and the body returned as text or base64.
    private func runFetchTask(_ task: [String: Any]) async throws -> [String: Any] {
        let urlString = task["url"] as? String ?? ""
        guard var components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw MediaHubError.invalidUrl(urlString)
        }
        // A task makes the app fetch whatever URL the addon names, from the user's own
        // network. Hoster pages are public, so anything local is refused — otherwise an
        // addon could read the user's router, LAN devices or the VPN's own 127.0.0.1 port.
        guard !Self.isPrivateHost(components.host ?? "") else {
            throw MediaHubError.resolveFailed(L("Addon-Aufgabe auf ein privates Netzwerk abgelehnt"))
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "_t", value: String(Int(Date().timeIntervalSince1970 * 1000)))
        ]
        guard let url = components.url else { throw MediaHubError.invalidUrl(urlString) }

        let params = task["params"] as? [String: Any] ?? [:]
        var request = URLRequest(url: url)
        request.httpMethod = (params["method"] as? String)?.uppercased() ?? "GET"
        request.httpShouldHandleCookies = false
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        for (key, value) in params["headers"] as? [String: Any] ?? [:] {
            if let single = value as? String {
                request.setValue(single, forHTTPHeaderField: key)
            } else if let list = value as? [String] {
                request.setValue(list.joined(separator: ", "), forHTTPHeaderField: key)
            }
        }
        if let body = params["body"] as? String {
            request.httpBody = Data(body.utf8)
        }
        let followRedirects = (params["redirect"] as? String ?? "follow") == "follow"

        // Through the VPN whenever it is up: the hoster ties its stream link to the address
        // that fetched this page, and the stream is played through the VPN.
        let fetchSession = vpnSession() ?? session

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetchSession.data(
                for: request,
                delegate: followRedirects ? nil : RedirectBlocker()
            )
        } catch {
            throw MediaHubError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw MediaHubError.httpError(statusCode: -1, message: L("Keine gültige HTTP-Antwort"))
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }
        // Status codes are reported, not thrown: a 404 or a redirect is information the
        // addon's extractor acts on.
        var result: [String: Any] = [
            "type": "fetch",
            "status": http.statusCode,
            "url": http.url?.absoluteString ?? url.absoluteString,
            "headers": headers
        ]
        if task["body"] as? Bool ?? true {
            let contentType = headers["content-type"]?.lowercased() ?? ""
            if contentType.hasPrefix("text/") || contentType.contains("json") {
                result["text"] = String(decoding: data, as: UTF8.self)
            } else {
                result["data"] = data.base64EncodedString()
            }
        }
        return result
    }
}

extension MediaHubClient {
    /// Loopback, link-local, private (RFC 1918 / ULA) and `.local` hosts. Hostnames that
    /// merely resolve to such an address are not caught; this blocks the direct cases.
    static func isPrivateHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.isEmpty || host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4, host.split(separator: ".").count == 4 {
            switch (octets[0], octets[1]) {
            case (0, _), (10, _), (127, _), (169, 254), (192, 168): return true
            case (172, 16...31): return true
            case (100, 64...127): return true   // carrier-grade NAT
            default: return false
            }
        }
        if host.contains(":") {
            return host == "::1" || host == "::" || host.hasPrefix("fe80:")
                || host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("::ffff:")
        }
        return false
    }
}

/// Stops URLSession from following a redirect when a fetch task asks for
/// `redirect: "manual"` — the addon wants to read the `location` header itself.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
