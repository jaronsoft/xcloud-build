import Foundation
import XCTest
@testable import AIK

final class APIModelTests: XCTestCase {
    func testMessageEnvelopeAndStringSnowflakeIDDecode() throws {
        let json = """
        {
          "status": 200,
          "success": true,
          "msg": "ok",
          "response": {
            "TenantId": 9223372036854775806,
            "TenantName": "示例企业",
            "AgentName": "知识助手",
            "AgentLogo": null,
            "WelcomeMessage": "欢迎",
            "EnableVoice": true,
            "IsAnonymousAllowed": false
          },
          "code": 0
        }
        """
        let envelope = try JSONDecoder().decode(
            MessageEnvelope<TenantSummary>.self,
            from: Data(json.utf8)
        )

        XCTAssertTrue(envelope.success)
        XCTAssertEqual(envelope.response?.TenantId.rawValue, "9223372036854775806")
        XCTAssertEqual(envelope.response?.TenantName, "示例企业")
    }

    func testStringSnowflakeIDRemainsString() throws {
        let data = Data(#""922337203685477580799""#.utf8)
        let value = try JSONDecoder().decode(FlexibleStringID.self, from: data)
        XCTAssertEqual(value.rawValue, "922337203685477580799")
    }

    func testTenantHeadersAreAddedTogether() throws {
        let client = APIClient(baseURL: URL(string: "https://example.com/api")!)
        let context = APIRequestContext(
            accessToken: "jwt-token",
            tenantID: "9007199254740993",
            inviteCode: nil,
            language: "zh-CN"
        )
        let request = try client.makeRequest(
            path: "/KnowledgeChat/GetHistory",
            method: "GET",
            context: context
        )

        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer jwt-token"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Knowledge-Tenant-Id"),
            "9007199254740993"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "x-tenantid"),
            "9007199254740993"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-lang"), "zh-CN")
    }

    func testLoginRequestCarriesCaptchaChallenge() throws {
        let request = AuthLoginRequest(
            LoginId: "tester",
            UserPassword: "",
            DeviceInfo: "iPhone",
            KeepLogin: true,
            Captcha: "1234",
            CaptchaKey: "captcha-key",
            EncryptedPassword: "encrypted",
            NonceId: "nonce"
        )
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(request)
        ) as? [String: Any]

        XCTAssertEqual(object?["Captcha"] as? String, "1234")
        XCTAssertEqual(object?["CaptchaKey"] as? String, "captcha-key")
        XCTAssertEqual(object?["EncryptedPassword"] as? String, "encrypted")
    }

    func testKnowledgeAccessSessionKeepsTenantAndMemberIDsAsStrings() throws {
        let data = Data(
            """
            {
              "AccessToken":"token",
              "ExpiresAt":"2026-07-27T12:00:00Z",
              "AccessMode":"member",
              "MemberId":"987654321012345678",
              "Tenant":{
                "TenantId":"887654321012345678",
                "TenantName":"企业",
                "AgentName":"助手",
                "AgentLogo":null,
                "WelcomeMessage":"欢迎",
                "EnableVoice":true,
                "IsAnonymousAllowed":false
              }
            }
            """.utf8
        )

        let session = try JSONDecoder().decode(
            KnowledgeAccessSession.self,
            from: data
        )
        XCTAssertEqual(session.MemberId?.rawValue, "987654321012345678")
        XCTAssertEqual(session.Tenant.id, "887654321012345678")
    }

    func testKnowledgeRegistrationResultKeepsApplicationIDAsString() throws {
        let data = Data(
            """
            {
              "ApplicationId":"9223372036854775806",
              "QueryToken":"test-query-token",
              "Status":"Pending",
              "MaskedEmail":"t***@example.com",
              "MaskedMobile":"138****0000"
            }
            """.utf8
        )

        let result = try JSONDecoder().decode(
            KnowledgeRegistrationApplyResult.self,
            from: data
        )

        XCTAssertEqual(result.ApplicationId.rawValue, "9223372036854775806")
        XCTAssertEqual(result.Status, "Pending")
    }

    func testKnowledgeRegistrationRequestDoesNotContainPlaintextPassword() throws {
        let request = KnowledgeRegistrationApplyRequest(
            UserName: "tester",
            EncryptedPassword: "encrypted-value",
            NonceId: "nonce-id",
            Email: "tester@example.com",
            Mobile: "13800000000",
            CompanyName: "测试企业",
            AppVersion: "1.0.3 (103)",
            DeviceFingerprint: "device-fingerprint",
            CaptchaKey: "captcha-key",
            Captcha: "1234",
            PrivacyAccepted: true,
            TermsAccepted: true
        )
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(request)
        ) as? [String: Any]

        XCTAssertNil(object?["Password"])
        XCTAssertNil(object?["UserPassword"])
        XCTAssertEqual(object?["EncryptedPassword"] as? String, "encrypted-value")
        XCTAssertEqual(object?["ClientPlatform"] as? String, "iOS")
    }
}
