import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class KnowledgeRegistrationStore {
    private(set) var isWorking = false
    private(set) var isLoadingCaptcha = false
    private(set) var captchaImage: UIImage?
    private(set) var status: KnowledgeRegistrationStatus?
    var errorMessage: String?
    var warningMessage: String?

    private let client: APIClient
    private let keychain: KeychainStore
    private let encryptor: PasswordEncryptor
    private var captchaKey: String?
    private var applicationID: String?
    private var queryToken: String?

    init(
        client: APIClient = APIClient(),
        keychain: KeychainStore = KeychainStore(),
        encryptor: PasswordEncryptor = PasswordEncryptor()
    ) {
        self.client = client
        self.keychain = keychain
        self.encryptor = encryptor
        applicationID = try? keychain.value(for: Keys.applicationID)
        queryToken = try? keychain.value(for: Keys.queryToken)
    }

    var hasSavedApplication: Bool {
        applicationID?.isEmpty == false && queryToken?.isEmpty == false
    }

    var canResubmit: Bool {
        status?.Status == "Rejected" || status?.Status == "Cancelled"
    }

    var canCancel: Bool {
        guard let value = status?.Status else { return false }
        return ["Pending", "Contacted", "AwaitingPayment", "ProvisionFailed"]
            .contains(value)
    }

    func loadCaptcha() async {
        isLoadingCaptcha = true
        errorMessage = nil
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
            errorMessage = String(localized: "registration.captcha_load_failed")
        }
    }

    func restoreStatus() async {
        guard let credential = credentialRequest else { return }
        isWorking = true
        errorMessage = nil
        warningMessage = nil
        defer { isWorking = false }
        do {
            status = try await client.post(
                "/KnowledgeRegistration/Status",
                body: credential,
                as: KnowledgeRegistrationStatus.self
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submit(
        userName: String,
        password: String,
        email: String,
        mobile: String,
        companyName: String,
        captcha: String,
        privacyAccepted: Bool,
        termsAccepted: Bool
    ) async -> Bool {
        let normalizedUserName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMobile = mobile.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCompanyName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCaptcha = captcha.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedUserName.range(
            of: #"^[A-Za-z0-9._-]{3,20}$"#,
            options: .regularExpression
        ) != nil else {
            errorMessage = String(localized: "registration.username_invalid")
            return false
        }
        guard password.count >= 8, password.count <= 64 else {
            errorMessage = String(localized: "registration.password_invalid")
            return false
        }
        guard normalizedEmail.contains("@"), !normalizedMobile.isEmpty,
              normalizedCompanyName.count >= 2 else {
            errorMessage = String(localized: "registration.contact_invalid")
            return false
        }
        guard privacyAccepted, termsAccepted else {
            errorMessage = String(localized: "registration.agreement_required")
            return false
        }
        guard let captchaKey, !normalizedCaptcha.isEmpty else {
            errorMessage = String(localized: "registration.captcha_required")
            return false
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let encrypted = try await encryptor.encrypt(password, client: client)
            let common = KnowledgeRegistrationApplyRequest(
                UserName: normalizedUserName,
                EncryptedPassword: encrypted.value,
                NonceId: encrypted.nonceID,
                Email: normalizedEmail,
                Mobile: normalizedMobile,
                CompanyName: normalizedCompanyName,
                AppVersion: AppEnvironment.releaseLabel,
                DeviceFingerprint: try deviceFingerprint(),
                CaptchaKey: captchaKey,
                Captcha: normalizedCaptcha,
                PrivacyAccepted: privacyAccepted,
                TermsAccepted: termsAccepted
            )
            let result: KnowledgeRegistrationApplyResult
            if canResubmit, let credential = credentialRequest {
                let request = KnowledgeRegistrationResubmitRequest(
                    ApplicationId: credential.ApplicationId,
                    QueryToken: credential.QueryToken,
                    UserName: common.UserName,
                    EncryptedPassword: common.EncryptedPassword,
                    NonceId: common.NonceId,
                    Email: common.Email,
                    Mobile: common.Mobile,
                    CompanyName: common.CompanyName,
                    AppVersion: common.AppVersion,
                    DeviceFingerprint: common.DeviceFingerprint,
                    CaptchaKey: common.CaptchaKey,
                    Captcha: common.Captcha,
                    PrivacyAccepted: common.PrivacyAccepted,
                    TermsAccepted: common.TermsAccepted
                )
                result = try await client.post(
                    "/KnowledgeRegistration/Resubmit",
                    body: request,
                    as: KnowledgeRegistrationApplyResult.self
                )
            } else {
                result = try await client.post(
                    "/KnowledgeRegistration/Apply",
                    body: common,
                    as: KnowledgeRegistrationApplyResult.self
                )
            }
            applicationID = result.ApplicationId.rawValue
            queryToken = result.QueryToken
            do {
                try saveCredential(result)
            } catch {
                warningMessage = String(localized: "registration.credential_save_failed")
            }
            await restoreStatus()
            return true
        } catch {
            errorMessage = error.localizedDescription
            await loadCaptcha()
            return false
        }
    }

    func cancel() async {
        guard let credential = credentialRequest else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            status = try await client.post(
                "/KnowledgeRegistration/Cancel",
                body: credential,
                as: KnowledgeRegistrationStatus.self
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var credentialRequest: KnowledgeRegistrationCredentialRequest? {
        guard let applicationID, let queryToken,
              !applicationID.isEmpty, !queryToken.isEmpty else {
            return nil
        }
        return KnowledgeRegistrationCredentialRequest(
            ApplicationId: FlexibleStringID(applicationID),
            QueryToken: queryToken
        )
    }

    private func saveCredential(_ result: KnowledgeRegistrationApplyResult) throws {
        do {
            try keychain.set(result.ApplicationId.rawValue, for: Keys.applicationID)
            try keychain.set(result.QueryToken, for: Keys.queryToken)
        } catch {
            try? keychain.remove(Keys.applicationID)
            try? keychain.remove(Keys.queryToken)
            throw error
        }
    }

    private func deviceFingerprint() throws -> String {
        if let saved = try keychain.value(for: Keys.deviceFingerprint), !saved.isEmpty {
            return saved
        }
        let value = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        try keychain.set(value, for: Keys.deviceFingerprint)
        return value
    }

    private enum Keys {
        static let applicationID = "knowledge-registration-application-id"
        static let queryToken = "knowledge-registration-query-token"
        static let deviceFingerprint = "knowledge-registration-device-id"
    }
}
