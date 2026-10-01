import XCTest
import CryptoKit
#if canImport(Network)
import Network
#endif
@testable import OpenDezor

/// Shadowsocks is the protocol Dezor's VPN actually speaks, so the crypto is pinned to
/// known-answer vectors computed with an independent implementation (Python
/// hashlib/hmac). A silent change here would not fail loudly — it would just produce
/// traffic the server rejects — so these vectors matter.
final class ShadowsocksTests: XCTestCase {

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func bytes(fromHex hex: String) -> Data {
        var out = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    // MARK: - Key derivation

    func testEvpBytesToKeyMatchesReferenceVector() {
        // The 16-byte case is plain MD5("password"), a value that is independently known.
        XCTAssertEqual(
            hex(SSCrypto.deriveMasterKey(password: "password", keySize: 16)),
            "5f4dcc3b5aa765d61d8327deb882cf99"
        )
        XCTAssertEqual(
            hex(SSCrypto.deriveMasterKey(password: "password", keySize: 32)),
            "5f4dcc3b5aa765d61d8327deb882cf992b95990a9151374abd8ff8c5a7a0fe08"
        )
    }

    func testHkdfSubkeyMatchesReferenceVector() {
        let master = SSCrypto.deriveMasterKey(password: "password", keySize: 32)
        let salt = Data((0..<32).map { UInt8($0) })
        let subkey = SSCrypto.deriveSubkey(masterKey: master, salt: salt, keySize: 32)
        let raw = subkey.withUnsafeBytes { Data($0) }
        XCTAssertEqual(
            hex(raw),
            "ee187aed3f87574907a39db98606f60a526114831288097cac66054b33a9464f"
        )
    }

    func testMethodSizesAndUnsupportedCiphers() {
        XCTAssertEqual(SSMethod(rawValue: "aes-256-gcm")?.keySize, 32)
        XCTAssertEqual(SSMethod(rawValue: "aes-128-gcm")?.keySize, 16)
        XCTAssertEqual(SSMethod(rawValue: "chacha20-ietf-poly1305")?.keySize, 32)
        // BLAKE3 is not in CryptoKit; the cipher must be refused, not approximated.
        XCTAssertNil(SSMethod(rawValue: "2022-blake3-aes-256-gcm"))
        XCTAssertNil(SSMethod(rawValue: "rc4-md5"))
    }

    // MARK: - AEAD framing

    /// The nonce is a little-endian counter that advances after *every* AEAD operation,
    /// including the length header. Resetting or sharing it across directions is the
    /// classic Shadowsocks bug, so decryption is checked to be order-dependent.
    func testChunkRoundTripAndNonceOrdering() throws {
        for method in SSMethod.allCases {
            let master = SSCrypto.deriveMasterKey(password: "pw", keySize: method.keySize)
            let salt = SSCrypto.randomSalt(size: method.saltSize)
            let key = SSCrypto.deriveSubkey(masterKey: master, salt: salt, keySize: method.keySize)

            var sender = SSCipher(key: key, method: method)
            var receiver = SSCipher(key: key, method: method)

            let payloads = [Data("first".utf8), Data("second".utf8), Data("third".utf8)]
            var wire = Data()
            for payload in payloads {
                wire.append(try sender.sealChunk(payload))
            }

            // Read them back in order: length chunk, then payload chunk, repeatedly.
            var cursor = 0
            for expected in payloads {
                let header = Data(wire[cursor..<(cursor + SSMethod.lengthChunkSize)])
                cursor += SSMethod.lengthChunkSize
                let lengthBytes = [UInt8](try receiver.open(header))
                let length = (Int(lengthBytes[0]) << 8) | Int(lengthBytes[1])
                XCTAssertEqual(length, expected.count)

                let body = Data(wire[cursor..<(cursor + length + SSMethod.tagSize)])
                cursor += length + SSMethod.tagSize
                XCTAssertEqual(try receiver.open(body), expected, "\(method.rawValue)")
            }
            XCTAssertEqual(cursor, wire.count)
        }
    }

    func testOutOfOrderChunkFailsAuthentication() throws {
        let method = SSMethod.aes256gcm
        let master = SSCrypto.deriveMasterKey(password: "pw", keySize: method.keySize)
        let salt = SSCrypto.randomSalt(size: method.saltSize)
        let key = SSCrypto.deriveSubkey(masterKey: master, salt: salt, keySize: method.keySize)

        var sender = SSCipher(key: key, method: method)
        let first = try sender.seal(Data("a".utf8))
        let second = try sender.seal(Data("b".utf8))

        // A receiver at counter 0 must not be able to open the *second* chunk.
        var receiver = SSCipher(key: key, method: method)
        XCTAssertThrowsError(try receiver.open(second))

        // The same receiver opens the first chunk fine.
        var fresh = SSCipher(key: key, method: method)
        XCTAssertEqual(try fresh.open(first), Data("a".utf8))
    }

    func testOversizedChunkIsRejected() {
        let method = SSMethod.aes256gcm
        let key = SSCrypto.deriveSubkey(
            masterKey: SSCrypto.deriveMasterKey(password: "pw", keySize: 32),
            salt: SSCrypto.randomSalt(size: 32),
            keySize: 32
        )
        var cipher = SSCipher(key: key, method: method)
        XCTAssertThrowsError(try cipher.sealChunk(Data(count: SSMethod.maxPayloadSize + 1)))
    }

    // MARK: - Target address

    func testAddressEncodingRoundTrip() {
        let cases: [SSAddress] = [
            SSAddress(host: .domain("example.com"), port: 443),
            SSAddress(host: .ipv4(Data([141, 95, 102, 126])), port: 8388),
            SSAddress(host: .ipv6(Data(repeating: 0x20, count: 16)), port: 80)
        ]
        for address in cases {
            let encoded = address.encoded
            guard let (parsed, consumed) = SSAddress.parse(encoded, from: 0) else {
                XCTFail("could not parse \(address)")
                continue
            }
            XCTAssertEqual(parsed, address)
            XCTAssertEqual(consumed, encoded.count)
        }
    }

    func testAddressParseWaitsForCompleteBuffer() {
        let full = SSAddress(host: .domain("example.com"), port: 443).encoded
        // A truncated buffer must report "not yet", not a wrong address.
        XCTAssertNil(SSAddress.parse(Data(full.prefix(4)), from: 0))
        XCTAssertNotNil(SSAddress.parse(full, from: 0))
    }

    func testDomainAddressKeepsHostnameForRemoteResolution() {
        // Sending the hostname (ATYP 0x03) rather than a resolved IP is what keeps DNS
        // lookups on the proxy instead of leaking them locally.
        let encoded = SSAddress(host: .domain("example.com"), port: 443).encoded
        XCTAssertEqual(encoded.first, 0x03)
        XCTAssertEqual(SSAddress(host: .domain("example.com"), port: 443).hostString, "example.com")
    }

    // MARK: - End to end

    #if canImport(Network)
    /// Proves the whole chain without touching the network: a fake Shadowsocks server in
    /// this process, the real `LocalProxyServer` in front of it, and a raw SOCKS5 client
    /// driving it. Exercises the SOCKS5 handshake, the target header, both cipher
    /// directions and chunk reassembly at once.
    func testLoopbackThroughLocalProxyServer() throws {
        let method = SSMethod.aes256gcm
        let password = "loopback-secret"

        let serverReady = expectation(description: "fake shadowsocks server listening")
        let fakeServer = FakeShadowsocksServer(method: method, password: password)
        var serverPort: UInt16 = 0
        fakeServer.start { port in
            serverPort = port
            serverReady.fulfill()
        }
        wait(for: [serverReady], timeout: 10)
        defer { fakeServer.stop() }

        let proxy = LocalProxyServer()
        defer { proxy.stop() }

        let proxyReady = expectation(description: "local socks5 proxy listening")
        var proxyPort: UInt16 = 0
        proxy.start(
            config: SSServerConfig(host: "127.0.0.1", port: serverPort, method: method, password: password)
        ) { result in
            if case .success(let port) = result {
                proxyPort = port
                proxyReady.fulfill()
            }
        }
        wait(for: [proxyReady], timeout: 10)

        let echoed = expectation(description: "payload echoed back through the tunnel")
        let client = RawSocks5Client(port: proxyPort)
        client.connect(to: SSAddress(host: .domain("example.com"), port: 80), sending: Data("PING".utf8)) { response in
            XCTAssertEqual(response, Data("PING".utf8))
            echoed.fulfill()
        }
        wait(for: [echoed], timeout: 15)
        client.stop()
    }

    /// A connection that cannot be established must report failure exactly once and
    /// promptly. Found the hard way: on a filtered network the TCP connect neither
    /// succeeded nor failed, and the VPN sat on "connecting" forever.
    func testUnreachableServerFailsOnceAndPromptly() {
        let failed = expectation(description: "start reports failure")
        var completionCount = 0

        // Port 1 on loopback has nothing listening.
        let connection = SSConnection(
            config: SSServerConfig(host: "127.0.0.1", port: 1, method: .aes256gcm, password: "x"),
            target: SSAddress(host: .domain("example.com"), port: 80),
            queue: DispatchQueue(label: "test.ss.unreachable")
        )
        connection.start(timeout: 3) { error in
            completionCount += 1
            XCTAssertNotNil(error)
            failed.fulfill()
        }

        wait(for: [failed], timeout: 10)
        connection.cancel()
        // Cancelling after a failure must not deliver a second completion.
        XCTAssertEqual(completionCount, 1)
    }
    #endif
}

#if canImport(Network)

// MARK: - Test doubles

/// A minimal Shadowsocks server: reads the salt, decrypts the target header, then echoes
/// every payload chunk back over its own encrypted stream.
private final class FakeShadowsocksServer {
    private let method: SSMethod
    private let masterKey: Data
    private let queue = DispatchQueue(label: "test.fake.ss")
    private var listener: NWListener?
    private var connections: [NWConnection] = []

    init(method: SSMethod, password: String) {
        self.method = method
        self.masterKey = SSCrypto.deriveMasterKey(password: password, keySize: method.keySize)
    }

    func start(_ onReady: @escaping (UInt16) -> Void) {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let listener = try! NWListener(using: parameters)
        self.listener = listener

        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port {
                onReady(port.rawValue)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func handle(_ connection: NWConnection) {
        connections.append(connection)
        var inbound = Data()
        var recvCipher: SSCipher?
        var sendCipher: SSCipher?
        var pendingLength: Int?
        var sawTargetHeader = false

        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                guard error == nil else { return }
                if let data, !data.isEmpty {
                    inbound.append(data)

                    if recvCipher == nil, inbound.count >= self.method.saltSize {
                        let salt = Data(inbound.prefix(self.method.saltSize))
                        inbound.removeFirst(self.method.saltSize)
                        recvCipher = SSCipher(
                            key: SSCrypto.deriveSubkey(masterKey: self.masterKey, salt: salt, keySize: self.method.keySize),
                            method: self.method
                        )
                    }

                    while recvCipher != nil {
                        if let length = pendingLength {
                            let needed = length + SSMethod.tagSize
                            guard inbound.count >= needed else { break }
                            let chunk = Data(inbound.prefix(needed))
                            inbound.removeFirst(needed)
                            guard let plaintext = try? recvCipher!.open(chunk) else { return }
                            pendingLength = nil

                            if !sawTargetHeader {
                                // First payload is the destination; a real server would
                                // dial it. Here it is simply acknowledged.
                                sawTargetHeader = true
                            } else {
                                // Echo the payload back on a fresh outbound stream.
                                if sendCipher == nil {
                                    let salt = SSCrypto.randomSalt(size: self.method.saltSize)
                                    sendCipher = SSCipher(
                                        key: SSCrypto.deriveSubkey(masterKey: self.masterKey, salt: salt, keySize: self.method.keySize),
                                        method: self.method
                                    )
                                    connection.send(content: salt, completion: .idempotent)
                                }
                                if let framed = try? sendCipher!.sealChunk(plaintext) {
                                    connection.send(content: framed, completion: .idempotent)
                                }
                            }
                        } else {
                            guard inbound.count >= SSMethod.lengthChunkSize else { break }
                            let header = Data(inbound.prefix(SSMethod.lengthChunkSize))
                            inbound.removeFirst(SSMethod.lengthChunkSize)
                            guard let lengthBytes = try? recvCipher!.open(header) else { return }
                            let raw = [UInt8](lengthBytes)
                            pendingLength = (Int(raw[0]) << 8) | Int(raw[1])
                        }
                    }
                }
                if !isComplete { receive() }
            }
        }

        connection.start(queue: queue)
        receive()
    }
}

/// Speaks just enough SOCKS5 to drive `LocalProxyServer` from the outside.
private final class RawSocks5Client {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "test.socks5.client")

    init(port: UInt16) {
        connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
    }

    func connect(to target: SSAddress, sending payload: Data, completion: @escaping (Data) -> Void) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state else { return }
            // Greeting: version 5, one method, "no authentication".
            self.connection.send(content: Data([0x05, 0x01, 0x00]), completion: .idempotent)
            self.expect(2) { _ in
                var request = Data([0x05, 0x01, 0x00])
                request.append(target.encoded)
                self.connection.send(content: request, completion: .idempotent)
                self.expect(10) { _ in
                    self.connection.send(content: payload, completion: .idempotent)
                    self.expect(payload.count) { echoed in
                        completion(echoed)
                    }
                }
            }
        }
        connection.start(queue: queue)
    }

    /// Reads exactly `count` bytes, tolerating short reads.
    private func expect(_ count: Int, _ handler: @escaping (Data) -> Void) {
        var buffer = Data()
        func step() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: count - buffer.count) { data, _, _, error in
                guard error == nil else { return }
                if let data { buffer.append(data) }
                if buffer.count >= count {
                    handler(buffer)
                } else {
                    step()
                }
            }
        }
        step()
    }

    func stop() {
        connection.cancel()
    }
}
#endif
