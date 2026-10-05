import Foundation
import Security

enum KeychainStore {
    static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.wekarepartners.studio.session",
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(updateStatus)
        }

        var insertQuery = query
        for (key, value) in attributes {
            insertQuery[key] = value
        }
        let status = SecItemAdd(insertQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.wekarepartners.studio.session",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.wekarepartners.studio.session",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func loadOrCreateKey(account: String, byteCount: Int = 32) throws -> Data {
        if let encoded = read(account: account),
           let key = Data(base64Encoded: encoded),
           key.count == byteCount {
            return key
        }

        var key = Data(count: byteCount)
        let status = key.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, byteCount, $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
        try save(key.base64EncodedString(), account: account)
        return key
    }
}

private enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        String(localized: "auth.secure_storage.error")
    }
}
