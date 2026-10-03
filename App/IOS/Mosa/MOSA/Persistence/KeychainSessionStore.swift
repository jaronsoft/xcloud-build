import Foundation
import Security

protocol SessionStoring: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession?)
}

final class KeychainSessionStore: SessionStoring, @unchecked Sendable {
    private let service: String
    private let account: String

    init(
        service: String = "com.wekarepartners.mosa",
        account: String = "mosa.auth.session"
    ) {
        self.service = service
        self.account = account
    }

    func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let session,
              let data = try? JSONEncoder().encode(session) else { return }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
