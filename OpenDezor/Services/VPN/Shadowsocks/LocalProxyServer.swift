import Foundation
#if canImport(Network)
import Network

/// A SOCKS5 proxy bound to `127.0.0.1`, backing every connection with a Shadowsocks
/// stream to a Dezor server.
///
/// A local Shadowsocks client endpoint. WKWebView
/// (`ProxyConfiguration(socksv5Proxy:)`, iOS 17+) and `URLSession`
/// (`kCFStreamPropertySOCKSProxy*`) both point here, so app traffic — and only app
/// traffic — is tunnelled. Nothing outside the app is affected.
///
/// SOCKS5 rather than HTTP CONNECT because the SOCKS5 request body is byte-identical to
/// the Shadowsocks target header, one listener serves http and https uniformly, and
/// sending the hostname onward (rather than resolving it here) keeps DNS off the local
/// network.
///
/// Deliberately not `@MainActor`: the listener, every connection and every relay run on
/// one private serial queue. Readiness is reported back through a callback that the
/// caller hops to the main actor itself.
public final class LocalProxyServer {
    private let queue = DispatchQueue(label: "org.opendezor.ss.proxy")
    private var listener: NWListener?
    private var config: SSServerConfig?
    private var sessions: [ObjectIdentifier: ProxySession] = [:]

    public init() {}

    /// Starts listening on an ephemeral loopback port. `completion` delivers that port
    /// once the listener is ready.
    public func start(config: SSServerConfig, completion: @escaping (Result<UInt16, Error>) -> Void) {
        // Weak throughout: the listener's handlers outlive this block and hold self, so a
        // strong capture here would keep the server alive after it is released.
        queue.async { [weak self] in
            guard let self else { return }
            self.config = config
            if let listener = self.listener, listener.state == .ready, let port = listener.port {
                completion(.success(port.rawValue))
                return
            }
            self.stopLocked()

            do {
                let parameters = NWParameters.tcp
                // Loopback only — this proxy must never be reachable from the network.
                parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
                let listener = try NWListener(using: parameters)
                self.listener = listener

                var reported = false
                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        guard !reported, let port = listener.port else { return }
                        reported = true
                        completion(.success(port.rawValue))
                    case .failed(let error):
                        if !reported {
                            reported = true
                            completion(.failure(error))
                        }
                        self?.stop()
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.start(queue: self.queue)
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func stop() {
        queue.async { self.stopLocked() }
    }

    private func stopLocked() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for session in sessions.values { session.cancel() }
        sessions.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        guard let config else {
            connection.cancel()
            return
        }
        let session = ProxySession(local: connection, config: config, queue: queue)
        sessions[ObjectIdentifier(session)] = session
        session.onFinish = { [weak self, weak session] in
            guard let self, let session else { return }
            self.sessions.removeValue(forKey: ObjectIdentifier(session))
        }
        session.start()
    }
}

// MARK: - One client connection

/// Drives a single local socket: SOCKS5 greeting, CONNECT request, then a byte pump
/// between the client and its Shadowsocks stream.
private final class ProxySession {
    private enum Phase {
        case greeting
        case request
        case relaying
    }

    private let local: NWConnection
    private let config: SSServerConfig
    private let queue: DispatchQueue
    private var phase: Phase = .greeting
    private var buffer = Data()
    private var remote: SSConnection?
    private var finished = false

    var onFinish: (() -> Void)?

    init(local: NWConnection, config: SSServerConfig, queue: DispatchQueue) {
        self.local = local
        self.config = config
        self.queue = queue
    }

    func start() {
        local.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.finish()
            default:
                break
            }
        }
        local.start(queue: queue)
        receiveLocal()
    }

    private func receiveLocal() {
        local.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                self.finish()
                return
            }
            if let data, !data.isEmpty {
                switch self.phase {
                case .relaying:
                    self.remote?.send(data)
                case .greeting, .request:
                    self.buffer.append(data)
                    self.advanceHandshake()
                }
            }
            if isComplete {
                self.finish()
                return
            }
            guard !self.finished else { return }
            self.receiveLocal()
        }
    }

    /// Consumes the SOCKS5 greeting and CONNECT request as they arrive.
    private func advanceHandshake() {
        if phase == .greeting {
            // [VER, NMETHODS, METHODS...]
            guard buffer.count >= 2 else { return }
            let bytes = [UInt8](buffer)
            guard bytes[0] == 0x05 else { finish(); return }
            let methodCount = Int(bytes[1])
            let total = 2 + methodCount
            guard buffer.count >= total else { return }
            buffer.removeFirst(total)
            phase = .request
            // No authentication — the proxy is loopback-only.
            send(Data([0x05, 0x00]))
        }

        guard phase == .request else { return }
        // [VER, CMD, RSV, ATYP, ADDR, PORT]
        guard buffer.count >= 4 else { return }
        let bytes = [UInt8](buffer)
        guard bytes[0] == 0x05, bytes[2] == 0x00 else { finish(); return }
        guard bytes[1] == 0x01 else {
            // Only CONNECT is supported; BIND and UDP ASSOCIATE are refused.
            send(Data([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]))
            finish()
            return
        }
        guard let (address, consumed) = SSAddress.parse(buffer, from: 3) else { return }
        buffer.removeFirst(3 + consumed)
        openRemote(to: address)
    }

    private func openRemote(to address: SSAddress) {
        let remote = SSConnection(config: config, target: address, queue: queue)
        self.remote = remote

        remote.onReceive = { [weak self] data in
            self?.send(data)
        }
        remote.onClose = { [weak self] _ in
            self?.finish()
        }
        remote.start { [weak self] error in
            guard let self else { return }
            if error != nil {
                // General SOCKS server failure.
                self.send(Data([0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]))
                self.finish()
                return
            }
            self.phase = .relaying
            // Success. The bound address is ignored by every client we serve.
            self.send(Data([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]))
            // Anything the client pipelined behind the request goes out immediately.
            if !self.buffer.isEmpty {
                let pending = self.buffer
                self.buffer.removeAll()
                remote.send(pending)
            }
        }
    }

    private func send(_ data: Data) {
        local.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.finish() }
        })
    }

    func cancel() {
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        local.stateUpdateHandler = nil
        local.cancel()
        remote?.cancel()
        remote = nil
        let handler = onFinish
        onFinish = nil
        handler?()
    }
}
#endif
