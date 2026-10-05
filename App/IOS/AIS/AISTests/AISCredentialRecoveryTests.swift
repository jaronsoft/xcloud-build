import Foundation
import XCTest
@testable import AIS

final class AISCredentialRecoveryTests: XCTestCase {
    func testConcurrentRefreshRequestsShareOneRotation() async {
        let backend = CredentialTestBackend(statusCode: 200, delayNanoseconds: 50_000_000)
        let recovery = makeRecovery(backend: backend)
        let baseURL = URL(string: "https://example.com")!

        async let first = recovery.refreshAccessToken(
            rejectedAccessToken: "old-access",
            baseURL: baseURL,
            urlSession: .shared
        )
        async let second = recovery.refreshAccessToken(
            rejectedAccessToken: "old-access",
            baseURL: baseURL,
            urlSession: .shared
        )

        let outcomes = await [first, second]
        XCTAssertEqual(outcomes, [
            .available("new-access"),
            .available("new-access")
        ])
        let requestCount = await backend.requestCount()
        let storedSession = await backend.currentSession()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(storedSession?.refreshToken, "new-refresh")
    }

    func testAuthenticationRejectionClearsStoredSession() async {
        let backend = CredentialTestBackend(statusCode: 401)
        let recovery = makeRecovery(backend: backend)

        let outcome = await recovery.refreshAccessToken(
            rejectedAccessToken: "old-access",
            baseURL: URL(string: "https://example.com")!,
            urlSession: .shared
        )

        XCTAssertEqual(outcome, .rejected)
        let storedSession = await backend.currentSession()
        let clearCount = await backend.clearCount()
        XCTAssertNil(storedSession)
        XCTAssertEqual(clearCount, 1)
    }

    func testServerFailurePreservesStoredSession() async {
        let backend = CredentialTestBackend(statusCode: 500)
        let recovery = makeRecovery(backend: backend)

        let outcome = await recovery.refreshAccessToken(
            rejectedAccessToken: "old-access",
            baseURL: URL(string: "https://example.com")!,
            urlSession: .shared
        )

        XCTAssertEqual(outcome, .preserved)
        let storedSession = await backend.currentSession()
        let clearCount = await backend.clearCount()
        XCTAssertEqual(storedSession?.refreshToken, "old-refresh")
        XCTAssertEqual(clearCount, 0)
    }

    private func makeRecovery(
        backend: CredentialTestBackend
    ) -> AISCredentialRecovery {
        AISCredentialRecovery(
            loadSession: {
                await backend.currentSession()
            },
            saveSession: { session in
                await backend.save(session)
            },
            clearSession: {
                await backend.clear()
            },
            executeRequest: { request, _ in
                try await backend.execute(request)
            },
            recordDiagnostic: { _ in }
        )
    }
}

private actor CredentialTestBackend {
    private var session: AISStoredSession?
    private var requests = 0
    private var clears = 0
    private let statusCode: Int
    private let delayNanoseconds: UInt64

    init(statusCode: Int, delayNanoseconds: UInt64 = 0) {
        self.statusCode = statusCode
        self.delayNanoseconds = delayNanoseconds
        session = AISStoredSession(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            user: AuthUser(
                id: "1",
                email: nil,
                displayName: "Tester",
                countryCode: "CN"
            ),
            refreshedAt: .distantPast,
            lastOpenedAt: .now
        )
    }

    func currentSession() -> AISStoredSession? {
        session
    }

    func save(_ value: AISStoredSession) {
        session = value
    }

    func clear() {
        clears += 1
        session = nil
    }

    func requestCount() -> Int {
        requests
    }

    func clearCount() -> Int {
        clears
    }

    func execute(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        let data: Data
        if statusCode == 200 {
            data = Data(
                """
                {
                  "success": true,
                  "response": {
                    "token": "new-access",
                    "RefreshToken": "new-refresh"
                  }
                }
                """.utf8
            )
        } else {
            data = Data("{}".utf8)
        }
        return (data, response)
    }
}
