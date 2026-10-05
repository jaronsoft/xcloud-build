import Foundation
import XCTest
@testable import AIK

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var requestedPaths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            Self.requestedPaths.append(request.url?.path ?? "")
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class MockServiceTests: XCTestCase {
    private lazy var client: APIClient = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIClient(
            baseURL: URL(string: "https://mock.aik.test/api")!,
            session: URLSession(configuration: configuration)
        )
    }()

    func testLoginFailureEnvelope() async {
        MockURLProtocol.handler = { _ in
            (
                200,
                Data(#"{"status":400,"success":false,"msg":"账号或密码错误","response":null}"#.utf8)
            )
        }
        let body = AuthLoginRequest(
            LoginId: "tester",
            UserPassword: "",
            DeviceInfo: "test",
            KeepLogin: true,
            EncryptedPassword: "encrypted",
            NonceId: "nonce"
        )

        do {
            let _: AuthLoginResponse = try await client.post(
                "/auth/v2/login",
                body: body,
                as: AuthLoginResponse.self
            )
            XCTFail("登录失败响应不应被当作成功")
        } catch {
            XCTAssertEqual(error as? APIError, .server("账号或密码错误"))
        }
    }

    func testExpiredTokenMapsToUnauthorized() async {
        MockURLProtocol.handler = { _ in
            (401, Data())
        }

        do {
            let _: TenantPage = try await client.get(
                "/KnowledgeTenant/GetList",
                as: TenantPage.self
            )
            XCTFail("401 不应被当作成功")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }

    func testCaptchaErrorDetectionAndRefresh() async {
        let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/auth/snowflake":
                return (200, Data(#"{"status":200,"success":true,"response":"login-key"}"#.utf8))
            case "/api/auth/generate-captcha":
                return (
                    200,
                    Data(#"{"status":200,"success":false,"msg":"","response":"\#(pixel)"}"#.utf8)
                )
            default:
                return (404, Data())
            }
        }
        let service = "com.wekarepartners.aik.tests.\(UUID().uuidString)"
        let session = SessionStore(
            client: client,
            keychain: KeychainStore(service: service)
        )

        XCTAssertTrue(
            SessionStore.isCaptchaError(APIError.server("验证码不能为空"))
        )
        XCTAssertTrue(
            SessionStore.isCaptchaError(APIError.server("Captcha is required"))
        )
        await session.refreshCaptcha()
        XCTAssertNotNil(session.captchaImage)
        XCTAssertNil(session.captchaErrorMessage)
    }

    func testEmptyTenantListDecodes() async throws {
        MockURLProtocol.handler = { _ in
            (
                200,
                Data(#"{"status":200,"success":true,"response":{"data":[],"dataCount":0}}"#.utf8)
            )
        }

        let page: TenantPage = try await client.get(
            "/KnowledgeTenant/GetList",
            as: TenantPage.self
        )
        XCTAssertTrue(page.data.isEmpty)
        XCTAssertEqual(page.dataCount, 0)
    }

    func testExpiredActivationCode() async {
        MockURLProtocol.handler = { _ in
            (
                200,
                Data(#"{"status":200,"success":true,"response":{"IsValid":false,"Token":null,"Tenant":null}}"#.utf8)
            )
        }
        let suite = "com.wekarepartners.aik.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = SessionStore(
            client: client,
            keychain: KeychainStore(service: suite)
        )
        let tenants = TenantStore(client: client, defaults: defaults)
        let model = InviteAccessModel()

        let accepted = await model.resolve(
            "ABCDEFGH",
            session: session,
            tenants: tenants
        )
        XCTAssertFalse(accepted)
        XCTAssertNotNil(model.errorMessage)
    }

    func testAnonymousCaptchaAccess() async {
        let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/KnowledgeMember/GetTenantPublicInfo":
                return (
                    200,
                    Data(
                        """
                        {"status":200,"success":true,"response":{
                          "TenantId":"785106753826885",
                          "TenantName":"匿名空间",
                          "AgentName":"助手",
                          "AgentLogo":null,
                          "WelcomeMessage":"欢迎",
                          "EnableVoice":false,
                          "IsAnonymousAllowed":true
                        }}
                        """.utf8
                    )
                )
            case "/api/auth/snowflake":
                return (200, Data(#"{"status":200,"success":true,"response":"captcha-key"}"#.utf8))
            case "/api/auth/generate-captcha":
                return (
                    200,
                    Data(#"{"status":200,"success":true,"response":"\#(pixel)"}"#.utf8)
                )
            case "/api/auth/validate-captcha":
                return (200, Data(#"{"status":200,"success":true,"response":true}"#.utf8))
            default:
                return (404, Data())
            }
        }
        let suite = "com.wekarepartners.aik.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = SessionStore(
            client: client,
            keychain: KeychainStore(service: suite)
        )
        let tenants = TenantStore(client: client, defaults: defaults)
        let model = InviteAccessModel()

        let enteredWithoutCaptcha = await model.resolve(
            "785106753826885",
            session: session,
            tenants: tenants
        )
        XCTAssertFalse(enteredWithoutCaptcha)
        XCTAssertNotNil(model.captchaImage)
        let entered = await model.validateCaptcha(
            "1234",
            session: session,
            tenants: tenants
        )
        XCTAssertTrue(entered)
        XCTAssertEqual(tenants.selectedTenant?.TenantName, "匿名空间")
        XCTAssertEqual(session.mode, .guest)
    }

    func testRatingAndClearHistoryRequests() async {
        MockURLProtocol.requestedPaths = []
        MockURLProtocol.handler = { _ in
            (
                200,
                Data(#"{"status":200,"success":true,"msg":"历史记录已清空"}"#.utf8)
            )
        }
        let suite = "com.wekarepartners.aik.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = SessionStore(
            client: client,
            keychain: KeychainStore(service: suite)
        )
        session.establishGuest(token: "guest", inviteCode: nil)
        let tenant = TenantSummary(
            TenantId: FlexibleStringID("785106753826885"),
            TenantName: "测试企业",
            AgentName: nil,
            AgentLogo: nil,
            WelcomeMessage: nil,
            EnableVoice: false,
            IsAnonymousAllowed: true
        )
        let tenants = TenantStore(client: client, defaults: defaults)
        tenants.selectGuest(tenant)
        let model = ChatViewModel(
            session: session,
            tenantStore: tenants,
            tenant: tenant,
            client: client,
            defaults: defaults
        )

        await model.rate(
            ChatMessage(
                id: "9007199254740993",
                role: .assistant,
                content: "答案",
                userRating: 0
            ),
            value: -1
        )
        await model.clearHistory()

        XCTAssertTrue(
            MockURLProtocol.requestedPaths.contains("/api/KnowledgeChat/SubmitRating")
        )
        XCTAssertTrue(
            MockURLProtocol.requestedPaths.contains("/api/KnowledgeChat/ClearHistory")
        )
    }

    func testInterruptedSSEPacketIsFlushed() {
        var parser = SSEParser()
        XCTAssertTrue(parser.feed(Data("data: partial answer".utf8)).isEmpty)
        XCTAssertEqual(parser.finish(), [.content("partial answer")])
    }
}
