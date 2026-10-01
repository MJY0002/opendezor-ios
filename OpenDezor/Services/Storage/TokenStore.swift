import Foundation
import Security

/// The single home for the Dezor device token.
///
/// The token authenticates every addon and stream request and carries the account's
/// entitlements, so it is credential material. It used to live in `UserDefaults`, which
/// writes a plain plist inside the app container — readable by anything that can reach
/// the container and included verbatim in unencrypted backups. The Keychain is the place
/// iOS provides for exactly this, and `kSecAttrAccessibleAfterFirstUnlock` keeps the token
/// readable for the background refresh while still requiring the device to have been
/// unlocked once since boot.
///
/// Reads and writes go through here from all three call sites (`DezorAuthService`,
/// `MediaHubClient`, `CustomResourceLoader`) so the header logic cannot drift apart.
public enum TokenStore {
    private static let service = "org.opendezor.app"
    private static let account = "opendezor_user_token"
    /// The old plaintext location, emptied on first read.
    private static let legacyDefaultsKey = "opendezor_user_token"

    public static var token: String? {
        get { read() }
        set { write(newValue) }
    }

    private static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }

        // Migrate a token written by an older build, then remove the plaintext copy.
        if let legacy = UserDefaults.standard.string(forKey: legacyDefaultsKey), !legacy.isEmpty {
            write(legacy)
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            return legacy
        }
        return nil
    }

    private static func write(_ value: String?) {
        // Never leave a stale plaintext copy behind, whatever happens below.
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)

        guard let value, !value.isEmpty else {
            SecItemDelete(baseQuery() as CFDictionary)
            return
        }

        let data = Data(value.utf8)
        let updates: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(baseQuery() as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            var insert = baseQuery()
            insert.merge(updates) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
