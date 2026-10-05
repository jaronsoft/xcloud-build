import Foundation

struct MessageEnvelope<Response: Decodable>: Decodable {
    let status: Int?
    let success: Bool
    let msg: String?
    let response: Response?
    let code: Int?
}

struct EmptyResponse: Decodable {}

struct FlexibleStringID: Codable, Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            rawValue = value
        } else if let value = try? container.decode(Int64.self) {
            rawValue = String(value)
        } else if let value = try? container.decode(Int.self) {
            rawValue = String(value)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "ID 必须是字符串或整数"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct AuthLoginRequest: Encodable {
    let LoginType = 1
    let LoginId: String
    let UserPassword: String
    let DeviceInfo: String
    let From = "AIK-iOS"
    let KeepLogin: Bool
    let Captcha: String?
    let CaptchaKey: String?
    let EncryptedPassword: String?
    let NonceId: String?

    init(
        LoginId: String,
        UserPassword: String,
        DeviceInfo: String,
        KeepLogin: Bool,
        Captcha: String? = nil,
        CaptchaKey: String? = nil,
        EncryptedPassword: String?,
        NonceId: String?
    ) {
        self.LoginId = LoginId
        self.UserPassword = UserPassword
        self.DeviceInfo = DeviceInfo
        self.KeepLogin = KeepLogin
        self.Captcha = Captcha
        self.CaptchaKey = CaptchaKey
        self.EncryptedPassword = EncryptedPassword
        self.NonceId = NonceId
    }
}

struct AuthLoginResponse: Decodable, Sendable {
    let User: SystemUser
    let Token: AuthToken
}

struct SystemUser: Codable, Sendable {
    let Id: FlexibleStringID
    let UserName: String?
    let RealName: String?
    let RoleNames: [String]?
}

struct AuthToken: Codable, Sendable {
    let authToken: String
    let refreshToken: String
    let expireTime: String?

    enum CodingKeys: String, CodingKey {
        case authToken = "auth_token"
        case refreshToken = "refresh_token"
        case expireTime = "expire_time"
    }
}

struct RefreshTokenRequest: Encodable {
    let ApiToken: String
    let RefreshToken: String
}

struct NonceResponse: Decodable {
    let NonceId: String
    let Nonce: String
}

struct KnowledgeRegistrationApplyRequest: Encodable {
    let UserName: String
    let EncryptedPassword: String
    let NonceId: String
    let Email: String
    let Mobile: String
    let CompanyName: String
    let ClientPlatform = "iOS"
    let AppVersion: String
    let DeviceFingerprint: String
    let CaptchaKey: String
    let Captcha: String
    let PrivacyAccepted: Bool
    let TermsAccepted: Bool
}

struct KnowledgeRegistrationResubmitRequest: Encodable {
    let ApplicationId: FlexibleStringID
    let QueryToken: String
    let UserName: String
    let EncryptedPassword: String
    let NonceId: String
    let Email: String
    let Mobile: String
    let CompanyName: String
    let ClientPlatform = "iOS"
    let AppVersion: String
    let DeviceFingerprint: String
    let CaptchaKey: String
    let Captcha: String
    let PrivacyAccepted: Bool
    let TermsAccepted: Bool
}

struct KnowledgeRegistrationApplyResult: Decodable, Sendable {
    let ApplicationId: FlexibleStringID
    let QueryToken: String
    let Status: String
    let MaskedEmail: String
    let MaskedMobile: String
}

struct KnowledgeRegistrationCredentialRequest: Encodable {
    let ApplicationId: FlexibleStringID
    let QueryToken: String
}

struct KnowledgeRegistrationStatus: Decodable, Sendable {
    let ApplicationId: FlexibleStringID
    let Status: String
    let StatusMessage: String
    let CompanyName: String
    let MaskedEmail: String
    let MaskedMobile: String
    let AppliedAt: String
    let ReviewedAt: String?
}

struct TenantPage: Decodable {
    let data: [TenantSummary]
    let dataCount: Int?
}

struct TenancyPublicContext: Decodable {
    let Mode: String
    let KnowledgeTenantId: String?
    let CanSelectTenant: Bool
}

struct TenantSummary: Codable, Identifiable, Hashable, Sendable {
    let TenantId: FlexibleStringID
    let TenantName: String
    let AgentName: String?
    let AgentLogo: String?
    let WelcomeMessage: String?
    let EnableVoice: Bool?
    let IsAnonymousAllowed: Bool?

    var id: String { TenantId.rawValue }
}

struct TenantPublicInfo: Codable, Sendable {
    let TenantId: FlexibleStringID
    let TenantName: String
    let AgentName: String?
    let AgentLogo: String?
    let WelcomeMessage: String?
    let EnableVoice: Bool?
    let IsAnonymousAllowed: Bool?

    var summary: TenantSummary {
        TenantSummary(
            TenantId: TenantId,
            TenantName: TenantName,
            AgentName: AgentName,
            AgentLogo: AgentLogo,
            WelcomeMessage: WelcomeMessage,
            EnableVoice: EnableVoice,
            IsAnonymousAllowed: IsAnonymousAllowed
        )
    }
}

struct InviteStatus: Decodable {
    let IsValid: Bool?
    let Token: String?
    let Tenant: TenantSummary?
}

struct KnowledgeAccessSessionRequest: Encodable {
    let TenantId: FlexibleStringID
    let Mode: String
    let Account: String?
    let Password: String?
    let InviteCode: String?
    let CaptchaKey: String?
    let Captcha: String?
    let DeviceInfo: String
}

struct SpaceAccessRequest: Encodable {
    let AccessCode: String
}

struct KnowledgeAccessSession: Decodable {
    let AccessToken: String
    let ExpiresAt: String
    let AccessMode: String
    let MemberId: FlexibleStringID?
    let Tenant: TenantSummary
}

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case server(String)
    case httpStatus(Int, String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "error.invalid_url")
        case .invalidResponse:
            String(localized: "error.invalid_response")
        case .unauthorized:
            String(localized: "error.session_expired")
        case let .server(message), let .httpStatus(_, message),
             let .decoding(message), let .network(message):
            message
        }
    }
}
