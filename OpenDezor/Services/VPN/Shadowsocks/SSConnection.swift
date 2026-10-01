import Foundation
#if canImport(Network)
import Network

/// Everything needed to open one Shadowsocks stream. Built by `VPNManager` from the
/// `proxy` object of a Dezor ping response.
public struct SSServerConfig: Equatable {
    public let host: String
    public let port: UInt16
    public let method: SSMethod
    public let password: String

    public init(host: String, port: UInt16, method: SSMethod, password: String) {
        self.host = host
        self.port = port
        self.method = method
        self.password = password
    }
}

/// One outbound Shadowsocks connection: TCP to the Dezor server, salt handshake, then an
/// AEAD-framed byte stream carrying traffic for a single destination.
///
/// Deliberately **not** `@MainActor`. Every instance lives on the owning
/// `LocalProxyServer`'s serial queue; it never touches published UI state.
final class SSConnection {
    private let config: SSServerConfig
    private let target: SSAddress
    private let queue: DispatchQueue
    private let connection: NWConnection

    private let masterKey: Data
    private var sendCipher: SSCipher
    private var recvCipher: SSCipher?

    /// Raw bytes received from the server that have not been decrypted yet. AEAD chunk
    /// boundaries do not line up with TCP segments, so a length header or a payload can
    /// straddle two `receive` callbacks.
    private var inboundBuffer = Data()
    /// Length of the payload chunk we are waiting for, once its header has been decrypted.
    private var pendingPayloadLength: Int?
    private var isClosed = false

    var onReceive: ((Data) -> Void)?
    var onClose: ((Error?) -> Void)?

    private let outboundSalt: Data

    init(config: SSServerConfig, target: SSAddress, queue: DispatchQueue) {
        let key = SSCrypto.deriveMasterKey(password: config.password, keySize: config.method.keySize)
        let salt = SSCrypto.randomSalt(size: config.method.saltSize)
        let subkey = SSCrypto.deriveSubkey(masterKey: key, salt: salt, keySize: config.method.keySize)

        self.config = config
        self.target = target
        self.queue = queue
        self.masterKey = key
        self.outboundSalt = salt
        self.sendCipher = SSCipher(key: subkey, method: config.method)
        self.connection = NWConnection(
            host: NWEndpoint.Host(config.host),
            port: NWEndpoint.Port(rawValue: config.port) ?? 443,
            using: .tcp
        )
    }

    /// Connects and sends the salt plus the encrypted target header. `completion` fires
    /// once the stream is ready to carry payload.
    ///
    /// A filtered network can leave the TCP connect hanging without ever reporting
    /// failure, so the attempt is bounded rather than left to wait forever.
    func start(timeout: TimeInterval = 12, completion: @escaping (Error?) -> Void) {
        var finished = false

        func settle(_ error: Error?) {
            guard !finished else { return }
            finished = true
            completion(error)
        }

        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard !finished else { return }
            settle(SSError.handshakeFailed)
            self?.close(SSError.handshakeFailed)
        }

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard !finished else { return }
                do {
                    try self.sendHandshake()
                    self.receiveLoop()
                    settle(nil)
                } catch {
                    settle(error)
                    self.close(error)
                }
            case .failed(let error):
                settle(error)
                self.close(error)
            case .cancelled:
                settle(SSError.handshakeFailed)
                self.close(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// Salt in the clear, then the target address as the first AEAD-framed payload.
    private func sendHandshake() throws {
        var packet = outboundSalt
        packet.append(try sendCipher.sealChunk(target.encoded))
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error { self?.close(error) }
        })
    }

    /// Encrypts and forwards payload, splitting at the SIP004 chunk limit.
    func send(_ data: Data) {
        guard !isClosed else { return }
        var packet = Data()
        var offset = 0
        do {
            while offset < data.count {
                let end = min(offset + SSMethod.maxPayloadSize, data.count)
                packet.append(try sendCipher.sealChunk(Data(data[data.startIndex + offset ..< data.startIndex + end])))
                offset = end
            }
        } catch {
            close(error)
            return
        }
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error { self?.close(error) }
        })
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.close(error)
                return
            }
            if let data, !data.isEmpty {
                self.inboundBuffer.append(data)
                do {
                    try self.drainInbound()
                } catch {
                    self.close(error)
                    return
                }
            }
            if isComplete {
                self.close(nil)
                return
            }
            guard !self.isClosed else { return }
            self.receiveLoop()
        }
    }

    /// Consumes as many complete AEAD chunks as the buffer currently holds.
    private func drainInbound() throws {
        // The server's salt arrives before anything else and seeds the receive cipher.
        if recvCipher == nil {
            let saltSize = config.method.saltSize
            guard inboundBuffer.count >= saltSize else { return }
            let salt = Data(inboundBuffer.prefix(saltSize))
            inboundBuffer.removeFirst(saltSize)
            let subkey = SSCrypto.deriveSubkey(masterKey: masterKey, salt: salt, keySize: config.method.keySize)
            recvCipher = SSCipher(key: subkey, method: config.method)
        }

        while true {
            if let payloadLength = pendingPayloadLength {
                let needed = payloadLength + SSMethod.tagSize
                guard inboundBuffer.count >= needed else { return }
                let chunk = Data(inboundBuffer.prefix(needed))
                inboundBuffer.removeFirst(needed)
                let plaintext = try recvCipher!.open(chunk)
                pendingPayloadLength = nil
                if !plaintext.isEmpty { onReceive?(plaintext) }
            } else {
                guard inboundBuffer.count >= SSMethod.lengthChunkSize else { return }
                let header = Data(inboundBuffer.prefix(SSMethod.lengthChunkSize))
                inboundBuffer.removeFirst(SSMethod.lengthChunkSize)
                let lengthBytes = try recvCipher!.open(header)
                guard lengthBytes.count == 2 else { throw SSError.truncatedChunk }
                let bytes = [UInt8](lengthBytes)
                let length = (Int(bytes[0]) << 8) | Int(bytes[1])
                guard length > 0, length <= SSMethod.maxPayloadSize else {
                    throw SSError.chunkTooLarge(length)
                }
                pendingPayloadLength = length
            }
        }
    }

    func cancel() {
        close(nil)
    }

    private func close(_ error: Error?) {
        guard !isClosed else { return }
        isClosed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        let handler = onClose
        onClose = nil
        onReceive = nil
        handler?(error)
    }
}
#endif
