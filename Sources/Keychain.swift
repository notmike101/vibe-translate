import Foundation
import Security

/// One generic-password item holding the provider API key. Small enough not to
/// need a dependency, private enough not to belong in UserDefaults.
enum Keychain {
    private static let service = "xyz.ignoresolutions.vibetranslate"
    private static let account = "provider.apiKey"

    static func apiKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }

        return value
    }

    static func setAPIKey(_ value: String) {
        let query = baseQuery()

        guard !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]

        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
