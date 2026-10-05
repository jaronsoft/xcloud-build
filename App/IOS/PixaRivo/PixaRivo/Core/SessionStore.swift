import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import StoreKit

private struct PixaActivityPingResponse: Decodable {
    let dailyVisitGiftGranted: Bool

    private enum CodingKeys: String, CodingKey {
        case dailyVisitGiftGranted
        case dailyVisitGiftGrantedUpper = "DailyVisitGiftGranted"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        dailyVisitGiftGranted = try box.decodeIfPresent(
            Bool.self,
            forKey: .dailyVisitGiftGranted
        ) ?? box.decodeIfPresent(
            Bool.self,
            forKey: .dailyVisitGiftGrantedUpper
        ) ?? false
    }
}

enum PixaAppleRegistrationRegionResolver {
    static func resolve(
        storefrontCountryCode: String?,
        localeCountryCode: String?
    ) -> String? {
        [storefrontCountryCode, localeCountryCode]
            .compactMap { value in
                let normalized = value?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).uppercased()
                return normalized?.isEmpty == false ? normalized : nil
            }
            .first
    }
}

enum PixaAppleDisplayNameFormatter {
    static func format(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let name = PersonNameComponentsFormatter.localizedString(
            from: components,
            style: .default,
            options: []
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

@MainActor
enum PixaAppleAuthorizationErrorPresenter {
    static func message(for error: Error) -> String? {
        let nsError = error as NSError
        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            return nil
        }

        NetworkDiagnosticsStore.shared.recordSystemLog(
            tag: "APPLE_AUTH",
            "\(nsError.domain) (\(nsError.code)): \(error.localizedDescription)"
        )

        if containsNetworkError(nsError) {
            return AppLanguage.localized("auth.apple.network_failed")
        }
        guard let authorizationError = error as? ASAuthorizationError else {
            return AppLanguage.localized("auth.apple.failed")
        }
        switch authorizationError.code {
        case .invalidResponse:
            return AppLanguage.localized("auth.apple.invalid_response")
        case .notInteractive:
            return AppLanguage.localized("auth.apple.retry")
        default:
            return AppLanguage.localized("auth.apple.failed")
        }
    }

    private static func containsNetworkError(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain { return true }
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return false
        }
        return containsNetworkError(underlying)
    }
}

@MainActor
@Observable
final class SessionStore {
    private let api = APIClient()
    private let maximumInactiveInterval: TimeInterval = 30 * 24 * 60 * 60
    private let proactiveRefreshInterval: TimeInterval = 24 * 60 * 60
    private(set) var user: AuthUser?
    private(set) var accessToken: String?
    private(set) var isWorking = false
    private(set) var appleBindingStatus: AppleBindingStatus?
    private(set) var appleBindingStatusError: String?
    private(set) var isLoadingAppleBindingStatus = false
    private(set) var hasResolvedAppleBindingStatus = false
    private(set) var complianceConsentStatus: ComplianceConsentStatus?
    private(set) var isLoadingComplianceConsent = false
    private(set) var isAcceptingComplianceConsent = false
    private(set) var hasResolvedComplianceConsent = false
    var complianceConsentError: String?
    var errorMessage: String?

    var isAuthenticated: Bool { user != nil && accessToken?.isEmpty == false }
    var needsComplianceConsent: Bool {
        isAuthenticated
            && hasResolvedComplianceConsent
            && complianceConsentStatus?.isAccepted != true
    }

    init() {
        restore()
        restoreAppleBindingStatus()
        isLoadingComplianceConsent = isAuthenticated
    }

    func validAccessToken() async -> String? {
        let stored = PixaCredentialStore.load()
        let needsProactiveRefresh = stored.map {
            Date.now.timeIntervalSince($0.refreshedAt) >= proactiveRefreshInterval
        } ?? true
        if PixaJWT.isUsable(accessToken), !needsProactiveRefresh {
            return accessToken
        }
        let outcome = await PixaCredentialRecovery.shared.refreshAccessToken(
            rejectedAccessToken: accessToken
        )
        if case let .available(token) = outcome {
            accessToken = token
            return token
        }
        return PixaJWT.isUsable(accessToken) ? accessToken : nil
    }

    func resume() async {
        guard isAuthenticated else { return }
        _ = await validAccessToken()
        persistLastOpened()
    }

    /// 前台心跳只用于维持服务端在线窗口，不读取余额或其他业务数据。
    func pingActivity() async {
        guard let token = await validAccessToken() else { return }
        let response: PixaActivityPingResponse? = try? await api.get(
            "/api/ais/session/ping",
            token: token
        )
        if response?.dailyVisitGiftGranted == true {
            NotificationCenter.default.post(name: .pixaBalanceDidChange, object: nil)
        }
    }

    func fetchProfile() async throws -> PixaAccountProfile {
        guard let token = await validAccessToken() else {
            throw APIError.rejected(AppLanguage.localized("auth.session_invalid"))
        }
        let profile: PixaAccountProfile = try await api.get(
            "/api/ais/account",
            token: token
        )
        applyProfile(profile)
        return profile
    }

    func updateProfile(_ request: PixaUpdateProfileRequest) async throws -> PixaAccountProfile {
        guard let token = await validAccessToken() else {
            throw APIError.rejected(AppLanguage.localized("auth.session_invalid"))
        }
        let profile: PixaAccountProfile = try await api.post(
            "/api/ais/account/profile",
            body: request,
            token: token
        )
        applyProfile(profile)
        return profile
    }

    func uploadAvatar(_ data: Data) async throws -> String {
        guard let token = await validAccessToken() else {
            throw APIError.rejected(AppLanguage.localized("auth.session_invalid"))
        }
        let result: AssetUploadResult = try await api.upload(
            "/api/ais/assets",
            data: data,
            fileName: "avatar.jpg",
            mimeType: "image/jpeg",
            token: token,
            fields: [
                "assetType": "reference",
                "referenceRole": "avatar",
                "preserveMode": "reference",
                "displayName": "PixaRivo Avatar",
                "userNote": "account_avatar"
            ]
        )
        guard let url = result.fileURL?.nilIfEmpty else {
            throw APIError.rejected(AppLanguage.localized("profile.avatar_upload_failed"))
        }
        return url
    }

    func refreshComplianceConsent() async {
        guard let token = await validAccessToken() else {
            complianceConsentStatus = nil
            hasResolvedComplianceConsent = false
            return
        }
        isLoadingComplianceConsent = true
        complianceConsentError = nil
        defer { isLoadingComplianceConsent = false }
        do {
            let status: ComplianceConsentStatus = try await api.get(
                "/api/ais/account/compliance-consent",
                token: token
            )
            guard !Task.isCancelled, isAuthenticated else { return }
            complianceConsentStatus = status
            hasResolvedComplianceConsent = true
        } catch {
            guard !Task.isCancelled, isAuthenticated else { return }
            complianceConsentStatus = nil
            // 首次状态查询失败不属于用户提交错误，底层请求已写入网络诊断，此处继续允许用户确认协议。
            complianceConsentError = nil
            hasResolvedComplianceConsent = true
        }
    }

    func acceptComplianceConsent() async -> Bool {
        guard let token = await validAccessToken() else {
            complianceConsentError = AppLanguage.localized("auth.session_invalid")
            return false
        }
        isAcceptingComplianceConsent = true
        complianceConsentError = nil
        defer { isAcceptingComplianceConsent = false }
        do {
            complianceConsentStatus = try await api.post(
                "/api/ais/account/compliance-consent",
                body: ComplianceConsentRequest(
                    agreementVersion: AppConfiguration.complianceAgreementVersion,
                    accepted: true,
                    clientPlatform: "ios",
                    locale: Locale.current.identifier
                ),
                token: token
            )
            return complianceConsentStatus?.isAccepted == true
        } catch {
            complianceConsentError = error.localizedDescription
            return false
        }
    }

    func applyRefreshedAccessToken(_ token: String) {
        accessToken = token
    }

    func signIn(email: String, password: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result: AuthResult = try await api.post("/api/ais/auth/email/password-login", body: ["email": email, "password": password])
            try persist(result)
            await PixaAvatarCache.shared.remove(userID: result.user.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func sendEmailCode(email: String, purpose: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let _: String = try await api.post(
                "/api/ais/auth/email/code",
                body: ["email": email, "purpose": purpose]
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signInWithCode(
        email: String,
        code: String,
        inviteAttribution: PixaReferralAttribution? = nil
    ) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let countryCode = PixaAppleRegistrationRegionResolver.resolve(
                storefrontCountryCode: await Storefront.current?.countryCode,
                localeCountryCode: Locale.current.region?.identifier
            )
            let result: AuthResult = try await api.post(
                "/api/ais/auth/email/login",
                body: EmailCodeLoginRequest(
                    email: email,
                    code: code,
                    countryCode: countryCode,
                    locale: Locale.current.identifier,
                    inviteCode: inviteAttribution?.inviteCode,
                    inviteSourceUrl: inviteAttribution?.sourceURL,
                    inviteSourceChannel: inviteAttribution?.sourceChannel,
                    inviteFirstVisitedAt: inviteAttribution.map {
                        ISO8601DateFormatter().string(from: $0.firstVisitedAt)
                    }
                )
            )
            try persist(result)
            await PixaAvatarCache.shared.remove(userID: result.user.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signInWithApple(
        credential: ASAuthorizationAppleIDCredential,
        rawNonce: String,
        inviteAttribution: PixaReferralAttribution? = nil
    ) async -> Bool {
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let codeData = credential.authorizationCode,
              let authorizationCode = String(data: codeData, encoding: .utf8) else {
            errorMessage = AppLanguage.localized("auth.apple.incomplete")
            return false
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let countryCode = PixaAppleRegistrationRegionResolver.resolve(
                storefrontCountryCode: await Storefront.current?.countryCode,
                localeCountryCode: Locale.current.region?.identifier
            )
            let request = AppleNativeLoginRequest(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                nonce: rawNonce,
                givenName: credential.fullName?.givenName,
                familyName: credential.fullName?.familyName,
                displayName: PixaAppleDisplayNameFormatter.format(credential.fullName),
                email: credential.email,
                locale: Locale.current.identifier,
                countryCode: countryCode,
                inviteCode: inviteAttribution?.inviteCode,
                inviteSourceUrl: inviteAttribution?.sourceURL,
                inviteSourceChannel: inviteAttribution?.sourceChannel,
                inviteFirstVisitedAt: inviteAttribution.map {
                    ISO8601DateFormatter().string(from: $0.firstVisitedAt)
                }
            )
            let result: AuthResult = try await api.post(
                "/api/ais/auth/apple/native",
                body: request
            )
            try persist(result)
            await PixaAvatarCache.shared.remove(userID: result.user.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshAppleBindingStatus(force: Bool = false) async {
        guard force || !hasResolvedAppleBindingStatus else { return }
        guard let token = await validAccessToken() else {
            appleBindingStatus = nil
            appleBindingStatusError = AppLanguage.localized("auth.session_invalid")
            hasResolvedAppleBindingStatus = true
            return
        }
        isLoadingAppleBindingStatus = true
        appleBindingStatusError = nil
        defer { isLoadingAppleBindingStatus = false }
        do {
            appleBindingStatus = try await api.get(
                "/api/ais/account/apple/status",
                token: token
            )
            hasResolvedAppleBindingStatus = true
            persistAppleBindingStatus()
        } catch {
            hasResolvedAppleBindingStatus = true
            appleBindingStatusError = error.localizedDescription
        }
    }

    func bindAppleIdentity(
        credential: ASAuthorizationAppleIDCredential,
        rawNonce: String
    ) async {
        guard let token = await validAccessToken() else {
            errorMessage = AppLanguage.localized("auth.session_invalid")
            return
        }
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let codeData = credential.authorizationCode,
              let authorizationCode = String(data: codeData, encoding: .utf8) else {
            errorMessage = AppLanguage.localized("auth.apple.incomplete")
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let countryCode = PixaAppleRegistrationRegionResolver.resolve(
                storefrontCountryCode: await Storefront.current?.countryCode,
                localeCountryCode: Locale.current.region?.identifier
            )
            let request = AppleNativeLoginRequest(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                nonce: rawNonce,
                givenName: credential.fullName?.givenName,
                familyName: credential.fullName?.familyName,
                displayName: PixaAppleDisplayNameFormatter.format(credential.fullName),
                email: credential.email,
                locale: Locale.current.identifier,
                countryCode: countryCode,
                inviteCode: nil,
                inviteSourceUrl: nil,
                inviteSourceChannel: nil,
                inviteFirstVisitedAt: nil
            )
            appleBindingStatus = try await api.post(
                "/api/ais/account/apple/bind",
                body: request,
                token: token
            )
            hasResolvedAppleBindingStatus = true
            appleBindingStatusError = nil
            persistAppleBindingStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func register(
        email: String,
        code: String,
        nickname: String,
        country: String,
        mobile: String?,
        inviteCode: String?,
        inviteAttribution: PixaReferralAttribution? = nil
    ) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            var body = [
                "email": email,
                "code": code,
                "nickname": nickname,
                "country": country
            ]
            if let mobile = mobile?.nilIfEmpty { body["mobile"] = mobile }
            if let inviteCode = inviteCode?.nilIfEmpty { body["inviteCode"] = inviteCode }
            if let inviteAttribution,
               inviteAttribution.inviteCode == PixaReferralAttributionStore.normalize(inviteCode ?? "") {
                body["inviteSourceUrl"] = inviteAttribution.sourceURL
                body["inviteSourceChannel"] = inviteAttribution.sourceChannel
                body["inviteFirstVisitedAt"] = ISO8601DateFormatter().string(
                    from: inviteAttribution.firstVisitedAt
                )
            }
            let result: AuthResult = try await api.post(
                "/api/ais/auth/email/register",
                body: body
            )
            try persist(result)
            await PixaAvatarCache.shared.remove(userID: result.user.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() {
        let signedOutUserID = user?.id
        let signedOutAccessToken = accessToken
        user = nil
        accessToken = nil
        appleBindingStatus = nil
        appleBindingStatusError = nil
        hasResolvedAppleBindingStatus = false
        complianceConsentStatus = nil
        hasResolvedComplianceConsent = false
        isLoadingComplianceConsent = false
        complianceConsentError = nil
        PixaCredentialStore.clear()
        clearAppleBindingStatus()
        removeLegacySession()
        if let signedOutUserID {
            Task { await PixaAvatarCache.shared.remove(userID: signedOutUserID) }
        }
        if let signedOutAccessToken {
            Task { await PixaPushNotificationService.shared.unregister(accessToken: signedOutAccessToken) }
        }
    }

    private func applyProfile(_ profile: PixaAccountProfile) {
        guard let current = user else { return }
        user = AuthUser(
            id: current.id,
            email: profile.email ?? current.email,
            displayName: profile.displayName ?? current.displayName,
            countryCode: profile.countryCode ?? current.countryCode,
            avatarURL: profile.avatarURL ?? current.avatarURL
        )
        persistLastOpened()
    }

    private func persist(_ result: AuthResult) throws {
        guard let refreshToken = result.token.refreshToken?.nilIfEmpty else {
            throw APIError.rejected(AppLanguage.localized("auth.session_invalid"))
        }
        user = result.user
        accessToken = result.token.accessToken
        appleBindingStatus = nil
        appleBindingStatusError = nil
        hasResolvedAppleBindingStatus = false
        clearAppleBindingStatus()
        complianceConsentStatus = nil
        hasResolvedComplianceConsent = false
        isLoadingComplianceConsent = true
        guard PixaCredentialStore.save(
            PixaStoredSession(
                accessToken: result.token.accessToken,
                refreshToken: refreshToken,
                user: result.user,
                refreshedAt: .now,
                lastOpenedAt: .now
            )
        ) else {
            user = nil
            accessToken = nil
            throw APIError.rejected(AppLanguage.localized("auth.session_invalid"))
        }
        removeLegacySession()
    }

    private func restore() {
        guard let stored = PixaCredentialStore.load(),
              Date.now.timeIntervalSince(stored.lastOpenedAt) <= maximumInactiveInterval else {
            PixaCredentialStore.clear()
            removeLegacySession()
            return
        }
        accessToken = stored.accessToken
        user = stored.user
        persistLastOpened()
    }

    private func persistLastOpened() {
        PixaCredentialStore.updateLastOpened(accessToken: accessToken, user: user)
    }

    private func restoreAppleBindingStatus() {
        guard let userID = user?.id,
              UserDefaults.standard.string(forKey: "pixarivo.apple_binding.user_id") == userID,
              UserDefaults.standard.bool(forKey: "pixarivo.apple_binding.is_bound") else {
            return
        }
        appleBindingStatus = AppleBindingStatus(
            isBound: true,
            email: UserDefaults.standard.string(forKey: "pixarivo.apple_binding.email")
        )
        hasResolvedAppleBindingStatus = true
    }

    private func persistAppleBindingStatus() {
        guard let userID = user?.id, let appleBindingStatus else { return }
        UserDefaults.standard.set(userID, forKey: "pixarivo.apple_binding.user_id")
        UserDefaults.standard.set(appleBindingStatus.isBound, forKey: "pixarivo.apple_binding.is_bound")
        if let email = appleBindingStatus.email?.nilIfEmpty {
            UserDefaults.standard.set(email, forKey: "pixarivo.apple_binding.email")
        } else {
            UserDefaults.standard.removeObject(forKey: "pixarivo.apple_binding.email")
        }
    }

    private func clearAppleBindingStatus() {
        UserDefaults.standard.removeObject(forKey: "pixarivo.apple_binding.user_id")
        UserDefaults.standard.removeObject(forKey: "pixarivo.apple_binding.is_bound")
        UserDefaults.standard.removeObject(forKey: "pixarivo.apple_binding.email")
    }

    private func removeLegacySession() {
        KeychainStore.delete(account: "access-token")
        UserDefaults.standard.removeObject(forKey: "pixarivo.user")
    }

    static func makeNonce() -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = 32
        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                preconditionFailure("无法生成安全随机数")
            }
            for byte in bytes where remaining > 0 {
                if byte < alphabet.count {
                    result.append(alphabet[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
enum KeychainStore {
    static let service = "com.wekarepartners.pixarivo"
    @discardableResult
    static func save(_ value: String, account: String) -> OSStatus {
        save(Data(value.utf8), account: account)
    }
    @discardableResult
    static func save(_ value: Data, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: value] as CFDictionary
        )
        guard updateStatus == errSecItemNotFound else { return updateStatus }
        var item = query
        item[kSecValueData as String] = value
        // 后台上传和通知同步需要在设备首次解锁后继续读取登录凭据。
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil)
    }
    static func load(account: String) -> String? {
        guard let data = loadData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func loadData(account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }
    static func delete(account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
