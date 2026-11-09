import Foundation
import Security
import CryptoKit
import UIKit

struct NativeActivityRegistrationAttempt {
    let exists: Bool
    let requestKey: String?
    // nil 表示旧版标记没有保存场次；空字符串表示整体活动。
    let sessionID: String?
}
struct TourismSession: Sendable {
    let accessToken: String
    let refreshToken: String
    let userName: String
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var session: TourismSession?
    private let account = "jhcti-tourism-session"

    private func merchantStaffMutationRecoveryKey(_ merchantID: String) -> String? {
        guard merchantID.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil else { return nil }
        return "jhcti.native.merchant-staff-write-unknown.v1.\(merchantID)"
    }

    func hasUnknownMerchantStaffMutation(for merchantID: String) -> Bool {
        guard let recoveryKey = merchantStaffMutationRecoveryKey(merchantID) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
            kSecAttrAccount as String: recoveryKey, kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) != errSecItemNotFound
    }

    @discardableResult func markUnknownMerchantStaffMutation(for merchantID: String) -> Bool {
        guard let recoveryKey = merchantStaffMutationRecoveryKey(merchantID) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
            kSecAttrAccount as String: recoveryKey]
        var attributes = query
        attributes[kSecValueData as String] = Data("pending".utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess || (status == errSecDuplicateItem && hasUnknownMerchantStaffMutation(for: merchantID))
    }

    @discardableResult func clearUnknownMerchantStaffMutation(for merchantID: String) -> Bool {
        guard let recoveryKey = merchantStaffMutationRecoveryKey(merchantID) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
            kSecAttrAccount as String: recoveryKey]
        let status = SecItemDelete(query as CFDictionary)
        return (status == errSecSuccess || status == errSecItemNotFound)
            && !hasUnknownMerchantStaffMutation(for: merchantID)
    }

    init() {
        guard let data = read(),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let token = value["AccessToken"], let refresh = value["RefreshToken"] else { return }
        session = TourismSession(accessToken: token, refreshToken: refresh, userName: value["UserName"] ?? "")
    }

    @discardableResult func save(_ value: TourismSession) -> Bool {
        let body = ["AccessToken": value.accessToken, "RefreshToken": value.refreshToken, "UserName": value.userName]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { return false }
        session = value
        return true
    }

    @discardableResult func saveTicketOrderAttempt(_ data: Data, for recoveryKey: String) -> Bool {
        guard recoveryKey.hasPrefix("jhcti.native.ticket-order-attempt.v1."), !data.isEmpty else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
                                    kSecAttrAccount as String: recoveryKey]
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return (status == errSecSuccess || status == errSecDuplicateItem)
            && readTicketOrderAttempt(for: recoveryKey) == data
    }

    func readTicketOrderAttempt(for recoveryKey: String) -> Data? {
        guard recoveryKey.hasPrefix("jhcti.native.ticket-order-attempt.v1.") else { return nil }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
                                    kSecAttrAccount as String: recoveryKey,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func hasTicketOrderAttempt(for recoveryKey: String) -> Bool {
        guard recoveryKey.hasPrefix("jhcti.native.ticket-order-attempt.v1.") else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
                                    kSecAttrAccount as String: recoveryKey,
                                    kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status != errSecItemNotFound
    }

    @discardableResult func clearTicketOrderAttempt(for recoveryKey: String, expected data: Data) -> Bool {
        guard recoveryKey.hasPrefix("jhcti.native.ticket-order-attempt.v1."),
              readTicketOrderAttempt(for: recoveryKey) == data else { return false }
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
                       kSecAttrAccount as String: recoveryKey] as CFDictionary)
        return status == errSecSuccess && !hasTicketOrderAttempt(for: recoveryKey)
    }

    @discardableResult func saveActivityRegistrationAttempt(_ requestKey: String, sessionID: String, for recoveryKey: String) -> Bool {
        guard recoveryKey.hasPrefix("jhcti.native.activity-registration-attempt.v1."),
              requestKey.range(of: "^[A-Za-z0-9._:-]{8,80}$", options: .regularExpression) != nil,
              sessionID.isEmpty || (Int64(sessionID).map { $0 > 0 && String($0) == sessionID } ?? false) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti", kSecAttrAccount as String: recoveryKey]
        let marker: [String: Any] = ["RequestKey": requestKey, "SessionId": sessionID.isEmpty ? NSNull() as Any : sessionID as Any]
        guard let data = try? JSONSerialization.data(withJSONObject: marker) else { return false }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        // 原子占用恢复槽位，另一页面的待确认请求不能被新请求覆盖。
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess || (status == errSecDuplicateItem
            && activityRegistrationAttempt(for: recoveryKey).requestKey == requestKey
            && activityRegistrationAttempt(for: recoveryKey).sessionID == sessionID)
    }

    func activityRegistrationAttempt(for recoveryKey: String) -> NativeActivityRegistrationAttempt {
        guard recoveryKey.hasPrefix("jhcti.native.activity-registration-attempt.v1.") else { return NativeActivityRegistrationAttempt(exists: false, requestKey: nil, sessionID: nil) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti", kSecAttrAccount as String: recoveryKey,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            return NativeActivityRegistrationAttempt(exists: status != errSecItemNotFound, requestKey: nil, sessionID: nil)
        }
        if let marker = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let key = marker["RequestKey"] as? String,
           key.range(of: "^[A-Za-z0-9._:-]{8,80}$", options: .regularExpression) != nil,
           marker.keys.contains("SessionId"),
           let sessionID = marker["SessionId"] as? String ?? (marker["SessionId"] is NSNull ? "" : nil),
           sessionID.isEmpty || (Int64(sessionID).map { $0 > 0 && String($0) == sessionID } ?? false) {
            return NativeActivityRegistrationAttempt(exists: true, requestKey: key, sessionID: sessionID)
        }
        // 向后兼容：仅解码旧版请求号，调用方不会据此自动认领服务端回执。
        let legacyKey = value.range(of: "^[A-Za-z0-9._:-]{8,80}$", options: .regularExpression) != nil ? value : nil
        return NativeActivityRegistrationAttempt(exists: true, requestKey: legacyKey, sessionID: nil)
    }

    @discardableResult func clearActivityRegistrationAttempt(for recoveryKey: String) -> Bool {
        guard recoveryKey.hasPrefix("jhcti.native.activity-registration-attempt.v1.") else { return false }
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti", kSecAttrAccount as String: recoveryKey] as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func afterSaleRequestAttempt(for recoveryKey: String) -> Data? {
        guard recoveryKey.hasPrefix("jhcti.native.buyer-aftersale-attempt.v1.") else { return nil }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
            kSecAttrAccount as String: recoveryKey, kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult func saveAfterSaleRequestAttempt(_ data: Data, for recoveryKey: String) -> Bool {
        guard recoveryKey.hasPrefix("jhcti.native.buyer-aftersale-attempt.v1."), !data.isEmpty else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
            kSecAttrAccount as String: recoveryKey]
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess || (status == errSecDuplicateItem && afterSaleRequestAttempt(for: recoveryKey) == data)
    }

    @discardableResult func updateAfterSaleRequestAttempt(_ data: Data, replacing expected: Data, for recoveryKey: String) -> Bool {
        guard recoveryKey.hasPrefix("jhcti.native.buyer-aftersale-attempt.v1."),
              afterSaleRequestAttempt(for: recoveryKey) == expected else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
            kSecAttrAccount as String: recoveryKey]
        return SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess
            && afterSaleRequestAttempt(for: recoveryKey) == data
    }

    @discardableResult func clearAfterSaleRequestAttempt(_ expected: Data, for recoveryKey: String) -> Bool {
        guard recoveryKey.hasPrefix("jhcti.native.buyer-aftersale-attempt.v1."),
              afterSaleRequestAttempt(for: recoveryKey) == expected else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
            kSecAttrAccount as String: recoveryKey]
        let status = SecItemDelete(query as CFDictionary)
        return (status == errSecSuccess || status == errSecItemNotFound) && afterSaleRequestAttempt(for: recoveryKey) == nil
    }

    func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
                       kSecAttrAccount as String: account] as CFDictionary)
        session = nil
    }

    private func read() -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jaronsoft.jhcti",
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
