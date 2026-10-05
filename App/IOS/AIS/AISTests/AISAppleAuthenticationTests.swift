import AuthenticationServices
import Foundation
import Testing
@testable import AIS

struct AISAppleAuthenticationTests {
    @Test("Apple 注册地区优先使用 Storefront")
    func registrationRegionPrefersStorefront() {
        #expect(
            AISAppleRegistrationRegionResolver.resolve(
                storefrontCountryCode: "cn",
                localeCountryCode: "US"
            ) == "CN"
        )
    }

    @Test("Apple 注册地区在 Storefront 缺失时回退 Locale")
    func registrationRegionFallsBackToLocale() {
        #expect(
            AISAppleRegistrationRegionResolver.resolve(
                storefrontCountryCode: nil,
                localeCountryCode: "cn"
            ) == "CN"
        )
    }

    @Test("Apple 登录请求携带国家或地区代码")
    func nativeLoginRequestEncodesCountryCode() throws {
        let request = AppleNativeLoginRequest(
            identityToken: "identity-token",
            authorizationCode: "authorization-code",
            nonce: "nonce",
            givenName: nil,
            familyName: nil,
            email: nil,
            locale: "zh_CN",
            countryCode: "CN"
        )

        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request))
                as? [String: Any]
        )
        #expect(object["countryCode"] as? String == "CN")
    }

    @Test("旧版 Keychain 会话缺少 Apple 字段时仍可解码")
    func legacyStoredSessionRemainsDecodable() throws {
        struct LegacyStoredSession: Codable {
            let accessToken: String
            let refreshToken: String
            let user: AuthUser
            let refreshedAt: Date
            let lastOpenedAt: Date
        }

        let legacy = LegacyStoredSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            user: AuthUser(
                id: "1001",
                email: "user@example.com",
                displayName: "AIS User",
                countryCode: "US"
            ),
            refreshedAt: .now,
            lastOpenedAt: .now
        )
        let data = try JSONEncoder().encode(legacy)

        let session = try JSONDecoder().decode(
            AISStoredSession.self,
            from: data
        )

        #expect(session.authenticationProvider == nil)
        #expect(session.appleUserIdentifier == nil)
        #expect(session.user.id == "1001")
    }

    @Test("只有 Apple 登录会话会因授权失效而退出")
    func credentialStatePolicyRespectsAuthenticationProvider() {
        #expect(
            AISAppleCredentialStatePolicy.resolve(
                authenticationProvider: .apple,
                credentialState: .authorized
            ) == .keepSession
        )
        #expect(
            AISAppleCredentialStatePolicy.resolve(
                authenticationProvider: .apple,
                credentialState: .revoked
            ) == .clearSession
        )
        #expect(
            AISAppleCredentialStatePolicy.resolve(
                authenticationProvider: .apple,
                credentialState: .notFound
            ) == .clearSession
        )
        #expect(
            AISAppleCredentialStatePolicy.resolve(
                authenticationProvider: .apple,
                credentialState: .transferred
            ) == .clearSession
        )
        #expect(
            AISAppleCredentialStatePolicy.resolve(
                authenticationProvider: .email,
                credentialState: .revoked
            ) == .keepSession
        )
    }

    @Test("Apple 绑定状态兼容后端 PascalCase")
    func appleBindingStatusDecodesPascalCase() throws {
        let data = Data(
            #"{"IsBound":true,"Email":"private@privaterelay.appleid.com"}"#.utf8
        )

        let status = try JSONDecoder().decode(
            AppleBindingStatus.self,
            from: data
        )

        #expect(status.isBound)
        #expect(status.email == "private@privaterelay.appleid.com")
    }
}
