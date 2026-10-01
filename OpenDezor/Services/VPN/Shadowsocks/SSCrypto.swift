import Foundation
import CryptoKit

// MARK: - Shadowsocks AEAD (SIP004)
//
// This is the wire protocol the official Dezor client speaks. On desktop it ships a
// Shadowsocks client and points the browser session at the local
// proxy that binary opens. iOS cannot spawn a helper binary, so the same protocol is
// implemented here directly on CryptoKit:
//
//   master key  = EVP_BytesToKey(MD5, password)          -> Insecure.MD5
//   subkey      = HKDF-SHA1(masterKey, salt, "ss-subkey") -> HKDF<Insecure.SHA1>
//   chunk cipher= AES-GCM | ChaCha20-Poly1305            -> AES.GCM / ChaChaPoly
//
// Everything in this file is pure value types with no platform API, so it compiles and
// is unit-testable on the macOS `swift test` host as well as on iOS.

public enum SSError: Error, Equatable {
    case unsupportedMethod(String)
    case truncatedChunk
    case chunkTooLarge(Int)
    case invalidAddress
    case handshakeFailed
}

/// The AEAD ciphers Shadowsocks defines that CryptoKit can service.
///
/// `init?(rawValue:)` deliberately fails for anything else — notably the
/// `2022-blake3-*` family, whose KDF is BLAKE3 and which CryptoKit cannot do. The
/// caller treats a nil here as "Shadowsocks unavailable" and falls back to a
/// user-supplied plain proxy rather than silently producing traffic that fails the
/// tag check. Dezor's live config uses `aes-256-gcm`.
public enum SSMethod: String, CaseIterable {
    case aes128gcm = "aes-128-gcm"
    case aes256gcm = "aes-256-gcm"
    case chacha20 = "chacha20-ietf-poly1305"

    /// Salt length equals key length for every AEAD method Shadowsocks defines.
    public var keySize: Int {
        switch self {
        case .aes128gcm: return 16
        case .aes256gcm, .chacha20: return 32
        }
    }

    public var saltSize: Int { keySize }

    public static let tagSize = 16
    public static let nonceSize = 12
    /// SIP004 caps a single payload chunk at 0x3FFF bytes.
    public static let maxPayloadSize = 0x3FFF
    /// Encrypted length header: 2 bytes of big-endian length plus its tag.
    public static var lengthChunkSize: Int { 2 + tagSize }
}

public enum SSCrypto {
    /// OpenSSL's `EVP_BytesToKey(MD5, salt: nil, iterations: 1)` — how Shadowsocks turns
    /// the account password into the master key.
    public static func deriveMasterKey(password: String, keySize: Int) -> Data {
        let passwordBytes = Data(password.utf8)
        var result = Data()
        var previous = Data()
        while result.count < keySize {
            var input = Data()
            input.append(previous)
            input.append(passwordBytes)
            previous = Data(Insecure.MD5.hash(data: input))
            result.append(previous)
        }
        return Data(result.prefix(keySize))
    }

    /// Per-connection subkey. The salt is sent in the clear as the first bytes of each
    /// direction of the stream.
    public static func deriveSubkey(masterKey: Data, salt: Data, keySize: Int) -> SymmetricKey {
        HKDF<Insecure.SHA1>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: masterKey),
            salt: salt,
            info: Data("ss-subkey".utf8),
            outputByteCount: keySize
        )
    }

    /// `UInt8.random` draws from the system CSPRNG, which is what a salt needs.
    public static func randomSalt(size: Int) -> Data {
        Data((0..<size).map { _ in UInt8.random(in: .min ... .max) })
    }
}

/// One direction of a Shadowsocks AEAD stream.
///
/// The 96-bit nonce is a little-endian counter that advances after *every* AEAD
/// operation — the length chunk and the payload chunk that follows it each burn one
/// nonce value. Send and receive keep entirely independent counters, both starting at
/// zero. Getting this wrong is the classic Shadowsocks implementation bug, so the
/// increment is covered by its own test.
public struct SSCipher {
    private let key: SymmetricKey
    private let method: SSMethod
    private var nonce = [UInt8](repeating: 0, count: SSMethod.nonceSize)

    public init(key: SymmetricKey, method: SSMethod) {
        self.key = key
        self.method = method
    }

    private mutating func advanceNonce() {
        for i in 0..<nonce.count {
            nonce[i] &+= 1
            if nonce[i] != 0 { break }
        }
    }

    /// Encrypts one chunk and returns `ciphertext || tag`.
    public mutating func seal(_ plaintext: Data) throws -> Data {
        let currentNonce = Data(nonce)
        let out: Data
        switch method {
        case .aes128gcm, .aes256gcm:
            let box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: currentNonce))
            out = box.ciphertext + box.tag
        case .chacha20:
            let box = try ChaChaPoly.seal(plaintext, using: key, nonce: ChaChaPoly.Nonce(data: currentNonce))
            out = box.ciphertext + box.tag
        }
        advanceNonce()
        return out
    }

    /// Decrypts one `ciphertext || tag` chunk.
    public mutating func open(_ ciphertextWithTag: Data) throws -> Data {
        guard ciphertextWithTag.count >= SSMethod.tagSize else { throw SSError.truncatedChunk }
        let currentNonce = Data(nonce)
        let split = ciphertextWithTag.count - SSMethod.tagSize
        let ciphertext = Data(ciphertextWithTag.prefix(split))
        let tag = Data(ciphertextWithTag.suffix(SSMethod.tagSize))
        let out: Data
        switch method {
        case .aes128gcm, .aes256gcm:
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: currentNonce), ciphertext: ciphertext, tag: tag
            )
            out = try AES.GCM.open(box, using: key)
        case .chacha20:
            let box = try ChaChaPoly.SealedBox(
                nonce: ChaChaPoly.Nonce(data: currentNonce), ciphertext: ciphertext, tag: tag
            )
            out = try ChaChaPoly.open(box, using: key)
        }
        advanceNonce()
        return out
    }

    /// Frames a payload the way SIP004 wants it: an encrypted 2-byte big-endian length,
    /// then the encrypted payload. Callers must respect `maxPayloadSize`.
    public mutating func sealChunk(_ payload: Data) throws -> Data {
        guard payload.count <= SSMethod.maxPayloadSize else {
            throw SSError.chunkTooLarge(payload.count)
        }
        let length = UInt16(payload.count)
        let lengthBytes = Data([UInt8(length >> 8), UInt8(length & 0xFF)])
        var out = try seal(lengthBytes)
        out.append(try seal(payload))
        return out
    }
}

// MARK: - Target address

/// A SOCKS5-style destination (`ATYP + addr + port`).
///
/// The SOCKS5 CONNECT request body and the Shadowsocks target header use the exact same
/// encoding, which is why the local listener can parse one and forward it as the other
/// without translation. Sending a domain (`ATYP 0x03`) rather than a resolved IP keeps
/// DNS resolution on the Shadowsocks server, so lookups do not leak locally.
public struct SSAddress: Equatable {
    public enum Host: Equatable {
        case ipv4(Data)
        case domain(String)
        case ipv6(Data)
    }

    public let host: Host
    public let port: UInt16

    public init(host: Host, port: UInt16) {
        self.host = host
        self.port = port
    }

    public var encoded: Data {
        var out = Data()
        switch host {
        case .ipv4(let bytes):
            out.append(0x01)
            out.append(bytes)
        case .domain(let name):
            let nameBytes = Data(name.utf8)
            out.append(0x03)
            out.append(UInt8(min(nameBytes.count, 255)))
            out.append(nameBytes.prefix(255))
        case .ipv6(let bytes):
            out.append(0x04)
            out.append(bytes)
        }
        out.append(UInt8(port >> 8))
        out.append(UInt8(port & 0xFF))
        return out
    }

    /// Human-readable host, for logging and for opening the outbound connection.
    public var hostString: String {
        switch host {
        case .ipv4(let bytes):
            return bytes.map { String($0) }.joined(separator: ".")
        case .domain(let name):
            return name
        case .ipv6(let bytes):
            return stride(from: 0, to: bytes.count, by: 2)
                .map { i in String(format: "%02x%02x", bytes[bytes.startIndex + i], bytes[bytes.startIndex + i + 1]) }
                .joined(separator: ":")
        }
    }

    /// Parses `ATYP + addr + port` starting at `offset`.
    /// Returns the address and the total number of bytes consumed, or nil when `data`
    /// does not yet hold the whole field.
    public static func parse(_ data: Data, from offset: Int) -> (address: SSAddress, consumed: Int)? {
        let bytes = [UInt8](data)
        guard offset < bytes.count else { return nil }
        let atyp = bytes[offset]
        var cursor = offset + 1

        let host: Host
        switch atyp {
        case 0x01:
            guard bytes.count >= cursor + 4 else { return nil }
            host = .ipv4(Data(bytes[cursor..<(cursor + 4)]))
            cursor += 4
        case 0x03:
            guard cursor < bytes.count else { return nil }
            let length = Int(bytes[cursor])
            cursor += 1
            guard bytes.count >= cursor + length else { return nil }
            guard let name = String(data: Data(bytes[cursor..<(cursor + length)]), encoding: .utf8) else {
                return nil
            }
            host = .domain(name)
            cursor += length
        case 0x04:
            guard bytes.count >= cursor + 16 else { return nil }
            host = .ipv6(Data(bytes[cursor..<(cursor + 16)]))
            cursor += 16
        default:
            return nil
        }

        guard bytes.count >= cursor + 2 else { return nil }
        let port = (UInt16(bytes[cursor]) << 8) | UInt16(bytes[cursor + 1])
        cursor += 2
        return (SSAddress(host: host, port: port), cursor - offset)
    }
}
