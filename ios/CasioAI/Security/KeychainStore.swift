import Foundation
import Security

/// Minimal Keychain wrapper for the handful of secrets this app holds
/// on-device: the OpenAI API key and the Notion integration token. Both are
/// entered by the user in Settings and never leave the device.
enum KeychainStore {
    enum Key: String {
        case openAIAPIKey = "com.adamodeven.casioai.openai-key"
        case notionToken = "com.adamodeven.casioai.notion-token"
    }

    static func set(_ value: String, for key: Key) {
        let data = Data(value.utf8)
        var query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: Key) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private static func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "CasioAI",
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}
