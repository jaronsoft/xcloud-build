import XCTest
@testable import AIS

final class APIEnvelopeTests: XCTestCase {
    func testDecodesMessageCodeFromExtraWithoutChangingLegacyMessage() throws {
        let data = Data(#"{"success":false,"status":500,"code":200,"msg":"登录失败","extra":{"messageCode":"LOGIN_FAILED","messageParams":{}},"response":null}"#.utf8)

        let envelope = try JSONDecoder().decode(APIEnvelope<EmptyResponse>.self, from: data)

        XCTAssertEqual(envelope.message, "登录失败")
        XCTAssertEqual(envelope.extra?.messageCode, "LOGIN_FAILED")
    }
    func testDecodesNumericCodeWithAuthResult() throws {
        let json = """
        {
          "status": 200,
          "success": true,
          "msg": "登录成功",
          "response": {
            "User": {
              "Id": "123456789012345678",
              "Email": "user@example.com",
              "DisplayName": "AIS User",
              "CountryCode": "US"
            },
            "Token": {
              "token": "header.payload.signature",
              "RefreshToken": "refresh-token"
            }
          },
          "code": 200
        }
        """

        let envelope = try JSONDecoder().decode(
            APIEnvelope<AuthResult>.self,
            from: Data(json.utf8)
        )

        XCTAssertTrue(envelope.success)
        XCTAssertEqual(envelope.code, "200")
        XCTAssertEqual(envelope.response?.user.id, "123456789012345678")
        XCTAssertEqual(
            envelope.response?.token.accessToken,
            "header.payload.signature"
        )
    }

    func testDecodesUppercaseNumericCodeWithFailureMessage() throws {
        let json = """
        {
          "Status": 500,
          "Success": false,
          "Msg": "用户名或密码错误",
          "Response": null,
          "Code": 200
        }
        """

        let envelope = try JSONDecoder().decode(
            APIEnvelope<String>.self,
            from: Data(json.utf8)
        )

        XCTAssertFalse(envelope.success)
        XCTAssertEqual(envelope.code, "200")
        XCTAssertEqual(envelope.message, "用户名或密码错误")
        XCTAssertNil(envelope.response)

        let parsed = APIClient.businessError(from: envelope)
        XCTAssertEqual(parsed.code, .unknown)
        XCTAssertEqual(parsed.message, "用户名或密码错误")
    }

    func testKeepsStringBusinessCode() throws {
        let json = """
        {
          "success": false,
          "msg": "报价已变化",
          "response": null,
          "code": "PRICE_CHANGED"
        }
        """

        let envelope = try JSONDecoder().decode(
            APIEnvelope<String>.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(envelope.code, "PRICE_CHANGED")
        XCTAssertEqual(envelope.message, "报价已变化")

        let parsed = APIClient.businessError(from: envelope)
        XCTAssertEqual(parsed.code, .priceChanged)
        XCTAssertEqual(parsed.message, "报价已变化")
    }

    func testParsesLegacyPriceChangeWhenEnvelopeCodeIsNumeric() throws {
        let json = """
        {
          "success": false,
          "msg": "PRICE_CHANGED|{\\"points\\":200,\\"originalPoints\\":250,\\"savedPoints\\":50}",
          "response": null,
          "code": 200
        }
        """

        let envelope = try JSONDecoder().decode(
            APIEnvelope<String>.self,
            from: Data(json.utf8)
        )
        let parsed = APIClient.businessError(from: envelope)
        let quote = try XCTUnwrap(
            AISPointQuote(priceChangeDetails: parsed.details)
        )

        XCTAssertEqual(parsed.code, .priceChanged)
        XCTAssertEqual(
            parsed.message,
            String(localized: "creation.price_changed")
        )
        XCTAssertEqual(quote.points, 200)
        XCTAssertEqual(quote.originalPoints, 250)
        XCTAssertEqual(quote.savedPoints, 50)
    }
}
