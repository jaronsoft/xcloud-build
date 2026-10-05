import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import StoreKit

enum AISAppleCredentialStateAction: Equatable {
    case keepSession
    case clearSession
}

enum AISAppleCredentialStatePolicy {
    static func resolve(
        authenticationProvider: AISAuthenticationProvider?,
        credentialState: ASAuthorizationAppleIDProvider.CredentialState
    ) -> AISAppleCredentialStateAction {
        guard authenticationProvider == .apple else {
            return .keepSession
        }
        switch credentialState {
        case .authorized:
            return .keepSession
        case .revoked, .notFound, .transferred:
            return .clearSession
        @unknown default:
            return .clearSession
        }
    }
}

enum AISAppleRegistrationRegionResolver {
    static func resolve(
        storefrontCountryCode: String?,
        localeCountryCode: String?
    ) -> String? {
        [storefrontCountryCode, localeCountryCode]
            .compactMap(normalizeCountryCode)
            .first
    }

    private static func normalizeCountryCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).uppercased()
        return normalized.isEmpty ? nil : normalized
    }
}

@MainActor
@Observable
final class SessionStore {
    private enum StorageKey {
        static let accessToken = "accessToken"
        static let refreshToken = "refreshToken"
        static let user = "currentUser"
    }

    private let maximumInactiveInterval: TimeInterval = 30 * 24 * 60 * 60
    private let proactiveRefreshInterval: TimeInterval = 24 * 60 * 60
    private let api = APIClient()
    private var didRestore = false
    private(set) var user: AuthUser?
    private(set) var accessToken: String?
    private(set) var isWorking = false
    private(set) var isRestoring = true
    private(set) var appleBindingStatus: AppleBindingStatus?
    var errorMessage: String?

    var isAuthenticated: Bool {
        accessToken?.isEmpty == false && user != nil
    }

    func restore() async {
        guard !didRestore else { return }
        didRestore = true

        let storedSession = AISCredentialStore.load() ?? migrateLegacySession()
        guard let storedSession else {
            clearStoredSession()
            isRestoring = false
            return
        }

        guard Date.now.timeIntervalSince(storedSession.lastOpenedAt)
                <= maximumInactiveInterval else {
            clearStoredSession()
            isRestoring = false
            return
        }

        user = storedSession.user
        accessToken = storedSession.accessToken
        guard await validateAppleCredentialStateIfNeeded(storedSession) else {
            isRestoring = false
            return
        }
        isRestoring = false

        if !isAccessTokenUsable(storedSession.accessToken)
            || Date.now.timeIntervalSince(storedSession.refreshedAt)
                >= proactiveRefreshInterval {
            await refreshSession(
                clearsInvalidSession: true
            )
        } else {
            persistLastOpened()
        }
    }

    func resume() async {
        guard didRestore, !isRestoring else { return }
        synchronizeStoredSession()
        guard let stored = AISCredentialStore.load() else {
            if isAuthenticated {
                clearStoredSession()
            }
            return
        }
        guard await validateAppleCredentialStateIfNeeded(stored) else {
            return
        }
        if !isAccessTokenUsable(accessToken)
            || Date.now.timeIntervalSince(stored.refreshedAt)
                >= proactiveRefreshInterval {
            await refreshSession(
                clearsInvalidSession: true
            )
        } else {
            persistLastOpened()
        }
    }

    func validAccessToken() async -> String? {
        synchronizeStoredSession()
        guard AISCredentialStore.load() != nil else {
            if isAuthenticated {
                clearStoredSession()
            }
            return nil
        }
        if !isAccessTokenUsable(accessToken) {
            await refreshSession(
                clearsInvalidSession: true
            )
        }
        return isAccessTokenUsable(accessToken) ? accessToken : nil
    }

    func sendEmailCode(email: String, purpose: String = "register") async -> Bool {
        var success = false
        await perform {
            let _: String = try await api.post(
                "/api/ais/auth/email/code",
                body: ["email": email, "purpose": purpose]
            )
            success = true
        }
        return success
    }

    func signInWithCode(email: String, code: String) async {
        await perform {
            let result: AuthResult = try await api.post(
                "/api/ais/auth/email/login",
                body: ["email": email, "code": code]
            )
            try persist(result, authenticationProvider: .email)
        }
    }

    func register(
        email: String,
        code: String,
        nickname: String,
        country: String = "CN",
        mobile: String? = nil,
        inviteCode: String? = nil
    ) async {
        await perform {
            var body: [String: String] = [
                "email": email,
                "code": code,
                "nickname": nickname,
                "country": country
            ]
            if let mobile = mobile, !mobile.isEmpty {
                body["mobile"] = mobile
            }
            if let inviteCode = inviteCode, !inviteCode.isEmpty {
                body["inviteCode"] = inviteCode
            }
            let result: AuthResult = try await api.post(
                "/api/ais/auth/email/register",
                body: body
            )
            try persist(result, authenticationProvider: .email)
        }
    }

    func signIn(email: String, password: String) async {
        await perform {
            let result: AuthResult = try await api.post(
                "/api/ais/auth/email/password-login",
                body: ["email": email, "password": password]
            )
            try persist(result, authenticationProvider: .email)
        }
    }

    func signInWithApple(
        credential: ASAuthorizationAppleIDCredential,
        rawNonce: String
    ) async {
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let codeData = credential.authorizationCode,
              let authorizationCode = String(data: codeData, encoding: .utf8) else {
            errorMessage = String(localized: "auth.apple.incomplete")
            return
        }

        let countryCode = AISAppleRegistrationRegionResolver.resolve(
            storefrontCountryCode: await Storefront.current?.countryCode,
            localeCountryCode: Locale.current.region?.identifier
        )

        let request = AppleNativeLoginRequest(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: rawNonce,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName,
            email: credential.email,
            locale: Locale.current.identifier,
            countryCode: countryCode
        )
        await perform {
            let result: AuthResult = try await api.post(
                "/api/ais/auth/apple/native",
                body: request
            )
            try persist(
                result,
                authenticationProvider: .apple,
                appleUserIdentifier: credential.user
            )
        }
    }

    func refreshAppleBindingStatus() async {
        guard let accessToken = await validAccessToken() else {
            appleBindingStatus = nil
            return
        }
        do {
            appleBindingStatus = try await api.get(
                "/api/ais/account/apple/status",
                accessToken: accessToken
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func bindAppleIdentity(
        credential: ASAuthorizationAppleIDCredential,
        rawNonce: String
    ) async {
        guard let accessToken = await validAccessToken() else { return }
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let codeData = credential.authorizationCode,
              let authorizationCode = String(data: codeData, encoding: .utf8) else {
            errorMessage = String(localized: "auth.apple.incomplete")
            return
        }

        let countryCode = AISAppleRegistrationRegionResolver.resolve(
            storefrontCountryCode: await Storefront.current?.countryCode,
            localeCountryCode: Locale.current.region?.identifier
        )

        let request = AppleNativeLoginRequest(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: rawNonce,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName,
            email: credential.email,
            locale: Locale.current.identifier,
            countryCode: countryCode
        )
        await perform {
            let status: AppleBindingStatus = try await api.post(
                "/api/ais/account/apple/bind",
                body: request,
                accessToken: accessToken
            )
            appleBindingStatus = status
        }
    }

    func requestAccountDeletion() async {
        guard let accessToken = await validAccessToken() else { return }
        await perform {
            let _: String = try await api.post(
                "/api/ais/account/deletion/confirm",
                body: ["confirmation": "DELETE"],
                accessToken: accessToken
            )
            signOut()
        }
    }

    func applyAccountProfile(
        email: String?,
        displayName: String?,
        countryCode: String?
    ) {
        guard let currentUser = user else { return }
        let updatedUser = AuthUser(
            id: currentUser.id,
            email: email ?? currentUser.email,
            displayName: displayName ?? currentUser.displayName,
            countryCode: countryCode ?? currentUser.countryCode
        )
        user = updatedUser
        guard let stored = AISCredentialStore.load() else { return }
        try? AISCredentialStore.save(
            AISStoredSession(
                accessToken: stored.accessToken,
                refreshToken: stored.refreshToken,
                user: updatedUser,
                refreshedAt: stored.refreshedAt,
                lastOpenedAt: stored.lastOpenedAt,
                authenticationProvider: stored.authenticationProvider,
                appleUserIdentifier: stored.appleUserIdentifier
            )
        )
    }

    func signOut() {
        let cacheScope = user.map { "user:\($0.id)" }
        Task {
            if let cacheScope {
                await AISResponseCache.shared.remove(scope: cacheScope)
            }
        }
        clearStoredSession()
        isRestoring = false
    }

    private func clearStoredSession() {
        user = nil
        accessToken = nil
        appleBindingStatus = nil
        errorMessage = nil
        KeychainStore.delete(account: StorageKey.accessToken)
        KeychainStore.delete(account: StorageKey.refreshToken)
        AISCredentialStore.clear()
        UserDefaults.standard.removeObject(forKey: StorageKey.user)
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persist(
        _ result: AuthResult,
        authenticationProvider: AISAuthenticationProvider,
        appleUserIdentifier: String? = nil
    ) throws {
        try persistToken(
            result.token,
            user: result.user,
            authenticationProvider: authenticationProvider,
            appleUserIdentifier: appleUserIdentifier
        )
        accessToken = result.token.accessToken
        user = result.user
    }

    private func persistToken(
        _ token: AuthToken,
        user persistedUser: AuthUser? = nil,
        authenticationProvider: AISAuthenticationProvider,
        appleUserIdentifier: String? = nil
    ) throws {
        let finalUser = persistedUser ?? user
        let refreshToken = token.refreshToken
            ?? AISCredentialStore.load()?.refreshToken
            ?? KeychainStore.read(account: StorageKey.refreshToken)
            ?? token.accessToken
        guard let finalUser, !refreshToken.isEmpty else {
            throw APIError.missingData
        }
        try AISCredentialStore.save(
            AISStoredSession(
                accessToken: token.accessToken,
                refreshToken: refreshToken,
                user: finalUser,
                refreshedAt: .now,
                lastOpenedAt: .now,
                authenticationProvider: authenticationProvider,
                appleUserIdentifier: appleUserIdentifier
            )
        )
        try KeychainStore.save(
            token.accessToken,
            account: StorageKey.accessToken
        )
        if let refreshToken = token.refreshToken,
           !refreshToken.isEmpty {
            try KeychainStore.save(
                refreshToken,
                account: StorageKey.refreshToken
            )
        }
        accessToken = token.accessToken
    }

    private func refreshSession(
        clearsInvalidSession: Bool
    ) async {
        let outcome = await AISCredentialRecovery.shared.refreshAccessToken(
            rejectedAccessToken: accessToken,
            baseURL: AppEnvironment.current.apiBaseURL,
            urlSession: .shared
        )
        switch outcome {
        case .available:
            synchronizeStoredSession()
        case .rejected:
            if clearsInvalidSession {
                clearStoredSession()
            }
        case .preserved:
            break
        }
    }

    private func validateAppleCredentialStateIfNeeded(
        _ storedSession: AISStoredSession
    ) async -> Bool {
        guard storedSession.authenticationProvider == .apple,
              let appleUserIdentifier = storedSession.appleUserIdentifier,
              !appleUserIdentifier.isEmpty else {
            return true
        }
        do {
            let state = try await ASAuthorizationAppleIDProvider()
                .credentialState(forUserID: appleUserIdentifier)
            let action = AISAppleCredentialStatePolicy.resolve(
                authenticationProvider: storedSession.authenticationProvider,
                credentialState: state
            )
            guard action == .keepSession else {
                clearStoredSession()
                errorMessage = String(localized: "auth.apple.revoked")
                return false
            }
        } catch {
            // 系统状态查询暂时失败时保留现有会话，后端仍会继续校验 JWT。
            return true
        }
        return true
    }

    private func isAccessTokenUsable(_ token: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        let segments = token.split(separator: ".")
        guard segments.count == 3,
              let payload = decodeBase64URL(String(segments[1])),
              let object = try? JSONSerialization.jsonObject(with: payload),
              let dictionary = object as? [String: Any],
              let expiration = dictionary["exp"] as? NSNumber else {
            // 兼容非 JWT 令牌；是否有效交由服务器在请求时判断。
            return true
        }
        return expiration.doubleValue
            > Date().timeIntervalSince1970 + 90
    }

    private func migrateLegacySession() -> AISStoredSession? {
        guard let userData = UserDefaults.standard.data(
            forKey: StorageKey.user
        ),
        let restoredUser = try? JSONDecoder().decode(
            AuthUser.self,
            from: userData
        ),
        let storedAccessToken = KeychainStore.read(
            account: StorageKey.accessToken
        ),
        let storedRefreshToken = KeychainStore.read(
            account: StorageKey.refreshToken
        ) else {
            return nil
        }
        let session = AISStoredSession(
            accessToken: storedAccessToken,
            refreshToken: storedRefreshToken,
            user: restoredUser,
            refreshedAt: .distantPast,
            lastOpenedAt: .now
        )
        try? AISCredentialStore.save(session)
        return session
    }

    private func synchronizeStoredSession() {
        guard let stored = AISCredentialStore.load() else { return }
        if stored.accessToken != accessToken {
            accessToken = stored.accessToken
        }
        if stored.user.id != user?.id {
            user = stored.user
        }
    }

    private func persistLastOpened() {
        guard let stored = AISCredentialStore.load() else { return }
        try? AISCredentialStore.save(
            AISStoredSession(
                accessToken: stored.accessToken,
                refreshToken: stored.refreshToken,
                user: stored.user,
                refreshedAt: stored.refreshedAt,
                lastOpenedAt: .now,
                authenticationProvider: stored.authenticationProvider,
                appleUserIdentifier: stored.appleUserIdentifier
            )
        )
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: normalized)
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
