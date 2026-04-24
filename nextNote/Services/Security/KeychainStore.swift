import Foundation
import Security

// Tiny wrapper around Keychain generic password items, namespaced under
// a single service. Reads/writes API keys and tokens we don't want
// languishing in UserDefaults plaintext.
enum KeychainStore {
    static let service = "com.nextNote.apiKeys"

    enum Account: String {
        case gemini
        case openai
        case huggingface
    }

    static func set(_ value: String, for account: Account) throws {
        let data = Data(value.utf8)

        // Delete any existing item first to avoid duplicate errors.
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.writeFailed(status)
        }
    }

    static func get(_ account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(_ account: Account) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    enum KeychainError: LocalizedError {
        case writeFailed(OSStatus)
        var errorDescription: String? {
            switch self {
            case .writeFailed(let s): return "Keychain write failed with code \(s)."
            }
        }
    }
}
