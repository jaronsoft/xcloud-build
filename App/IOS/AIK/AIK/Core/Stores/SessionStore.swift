import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class SessionStore {
    enum Mode: Equatable {
        case signedOut
        case system
        case guest
    }

    private(set) var mode: Mode = .signedOut
    private(set) var user: SystemUser?
    private(set) var accessToken: String?
    private(set) var refreshToken: String?
    private(set) var inviteCode: String?
    private(set) var isRestoring = true
    private(set) var requiresCaptcha = false
    private(set) var captchaImage: UIImage?
    private(set) var isLoadingCaptcha = false
    var isWorking = false
    var errorMessage: String?
    var captchaErrorMessage: String?

    let client: APIClient
    private let keychain: KeychainStore
    private let encryptor: PasswordEncryptor
    private var captchaKey: String?
    private var loginFailureCount = 0

    init(
        client: APIClient = APIClient(),
        keychain: KeychainStore = KeychainStore(),
        encryptor: PasswordEncryptor = PasswordEncryptor()
    ) {
        self.client = client
        self.keychain = keychain
        self.encryptor = encryptor
    }

    var isAuthenticated: Bool {
        mode != .signedOut && accessToken?.isEmpty == false
    }

    var context: APIRequestContext {
        var context = APIRequestContext.anonymous
        context.accessToken = accessToken
        context.inviteCode = inviteCode
        return context
    }

    func restore() async {
        defer { isRestoring = false }
        do {
            guard let token = try keychain.value(for: Keys.accessToken),
                  !token.isEmpty else {
                return
            }
            accessToken = token
            refreshToken = try keychain.value(for: Keys.refreshToken)
            inviteCode = try keychain.value(for: Keys.inviteCode)
            if let userData = try keychain.value(for: Keys.user)?
                .data(using: .utf8) {
                user = try? JSONDecoder().decode(SystemUser.self, from: userData)
            }
            mode = user == nil ? .guest : .system
        } catch {
            clearLocalSession()
        }
    }

    func login(
        account: String,
        password: String,
        keepLogin: Bool,
        captcha: String
    ) async {
        guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty else {
            errorMessage = String(localized: "login.required")
            return
        }
        if requiresCaptcha {
            guard !captcha.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = String(localized: "login.captcha_required")
                return
            }
            guard captchaKey != nil else {
                errorMessage = String(localized: "login.captcha_load_failed")
                await refreshCaptcha()
                return
            }
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let encrypted = try await encryptor.encrypt(password, client: client)
            let request = AuthLoginRequest(
                LoginId: account.trimmingCharacters(in: .whitespacesAndNewlines),
                UserPassword: "",
                DeviceInfo: deviceDescription,
                KeepLogin: keepLogin,
                Captcha: requiresCaptcha ? captcha : nil,
                CaptchaKey: requiresCaptcha ? captchaKey : nil,
                EncryptedPassword: encrypted.value,
                NonceId: encrypted.nonceID
            )
            let response: AuthLoginResponse = try await client.post(
                "/auth/v2/login",
                body: request,
                as: AuthLoginResponse.self
            )
            try persist(response)
            user = response.User
            accessToken = response.Token.authToken
            refreshToken = response.Token.refreshToken
            inviteCode = nil
            mode = .system
            loginFailureCount = 0
            clearCaptcha()
        } catch {
            errorMessage = error.localizedDescription
            loginFailureCount += 1
            if loginFailureCount >= 3 || Self.isCaptchaError(error) {
                requiresCaptcha = true
                await refreshCaptcha()
            }
        }
    }

    func refreshCaptcha() async {
        isLoadingCaptcha = true
        captchaErrorMessage = nil
        defer { isLoadingCaptcha = false }
        do {
            let key: String = try await client.get(
                "/auth/snowflake",
                as: String.self
            )
            let base64: String = try await client.getLegacyResponse(
                "/auth/generate-captcha",
                queryItems: [URLQueryItem(name: "keyid", value: key)],
                as: String.self
            )
            guard let data = Data(base64Encoded: base64),
                  let image = UIImage(data: data) else {
                throw APIError.invalidResponse
            }
            captchaKey = key
            captchaImage = image
        } catch {
            captchaKey = nil
            captchaImage = nil
            captchaErrorMessage = String(localized: "login.captcha_load_failed")
        }
    }

    func establishGuest(token: String, inviteCode: String?) {
        clearLocalSession()
        do {
            try keychain.set(token, for: Keys.accessToken)
            if let inviteCode {
                try keychain.set(inviteCode, for: Keys.inviteCode)
            }
            accessToken = token
            self.inviteCode = inviteCode
            mode = .guest
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func establishKnowledgeAccess(_ response: KnowledgeAccessSession, inviteCode: String?) {
        establishGuest(token: response.AccessToken, inviteCode: inviteCode)
    }

    func logout() {
        clearLocalSession()
    }

    private func persist(_ response: AuthLoginResponse) throws {
        try keychain.set(response.Token.authToken, for: Keys.accessToken)
        try keychain.set(response.Token.refreshToken, for: Keys.refreshToken)
        let userData = try JSONEncoder().encode(response.User)
        try keychain.set(
            String(decoding: userData, as: UTF8.self),
            for: Keys.user
        )
        try? keychain.remove(Keys.inviteCode)
    }

    private func clearLocalSession() {
        try? keychain.remove(Keys.accessToken)
        try? keychain.remove(Keys.refreshToken)
        try? keychain.remove(Keys.user)
        try? keychain.remove(Keys.inviteCode)
        accessToken = nil
        refreshToken = nil
        inviteCode = nil
        user = nil
        mode = .signedOut
    }

    private func clearCaptcha() {
        requiresCaptcha = false
        captchaKey = nil
        captchaImage = nil
        captchaErrorMessage = nil
    }

    static func isCaptchaError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("验证码") || message.contains("captcha")
    }

    private var deviceDescription: String {
        "\(UIDevice.current.model) / \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    private enum Keys {
        static let accessToken = "access-token"
        static let refreshToken = "refresh-token"
        static let user = "user"
        static let inviteCode = "invite-code"
    }
}
