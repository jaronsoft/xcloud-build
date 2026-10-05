import Foundation

extension Notification.Name {
    static let aisCredentialRejected = Notification.Name(
        "com.wekarepartners.studio.auth.credential-rejected"
    )
}

enum AISAuthenticationProvider: String, Codable, Sendable {
    case email
    case apple
}

struct AISStoredSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser
    let refreshedAt: Date
    let lastOpenedAt: Date
    let authenticationProvider: AISAuthenticationProvider?
    let appleUserIdentifier: String?

    init(
        accessToken: String,
        refreshToken: String,
        user: AuthUser,
        refreshedAt: Date,
        lastOpenedAt: Date,
        authenticationProvider: AISAuthenticationProvider? = nil,
        appleUserIdentifier: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.user = user
        self.refreshedAt = refreshedAt
        self.lastOpenedAt = lastOpenedAt
        self.authenticationProvider = authenticationProvider
        self.appleUserIdentifier = appleUserIdentifier
    }
}

enum AISCredentialStore {
    static let sessionAccount = "ais.auth.session.v2"

    static func load() -> AISStoredSession? {
        guard let value = KeychainStore.read(account: sessionAccount),
              let data = value.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AISStoredSession.self, from: data)
    }

    static func save(_ session: AISStoredSession) throws {
        let data = try JSONEncoder().encode(session)
        guard let value = String(data: data, encoding: .utf8) else {
            throw AISCredentialStoreError.encodingFailed
        }
        try KeychainStore.save(value, account: sessionAccount)
    }

    static func clear() {
        KeychainStore.delete(account: sessionAccount)
    }
}

enum AISCredentialRefreshOutcome: Sendable, Equatable {
    case available(String)
    case preserved
    case rejected
}

actor AISCredentialRecovery {
    static let shared = AISCredentialRecovery()

    typealias SessionLoader = @Sendable () async -> AISStoredSession?
    typealias SessionSaver = @Sendable (AISStoredSession) async throws -> Void
    typealias SessionClearer = @Sendable () async -> Void
    typealias DiagnosticRecorder = @Sendable (String) async -> Void
    typealias RequestExecutor = @Sendable (
        URLRequest,
        URLSession
    ) async throws -> (Data, URLResponse)

    private let loadSession: SessionLoader
    private let saveSession: SessionSaver
    private let clearSession: SessionClearer
    private let recordDiagnostic: DiagnosticRecorder
    private let executeRequest: RequestExecutor
    private var refreshTask: Task<AISCredentialRefreshOutcome, Never>?

    init(
        loadSession: @escaping SessionLoader = {
            AISCredentialStore.load()
        },
        saveSession: @escaping SessionSaver = {
            try AISCredentialStore.save($0)
        },
        clearSession: @escaping SessionClearer = {
            AISCredentialStore.clear()
        },
        executeRequest: @escaping RequestExecutor = { request, session in
            try await session.data(for: request)
        },
        recordDiagnostic: @escaping DiagnosticRecorder = { message in
            NetworkDiagnosticsStore.shared.recordSystemLog(
                tag: "AUTH_REFRESH",
                message
            )
        }
    ) {
        self.loadSession = loadSession
        self.saveSession = saveSession
        self.clearSession = clearSession
        self.executeRequest = executeRequest
        self.recordDiagnostic = recordDiagnostic
    }

    func recover(
        rejectedAccessToken: String,
        baseURL: URL,
        urlSession: URLSession
    ) async -> String? {
        let outcome = await refreshAccessToken(
            rejectedAccessToken: rejectedAccessToken,
            baseURL: baseURL,
            urlSession: urlSession
        )
        if case let .available(token) = outcome {
            return token
        }
        return nil
    }

    func refreshAccessToken(
        rejectedAccessToken: String?,
        baseURL: URL,
        urlSession: URLSession
    ) async -> AISCredentialRefreshOutcome {
        if let stored = await loadSession(),
           let rejectedAccessToken,
           stored.accessToken != rejectedAccessToken,
           isUsable(stored.accessToken) {
            await recordDiagnostic("复用其他请求已刷新的访问令牌")
            return .available(stored.accessToken)
        }

        if let refreshTask {
            await recordDiagnostic("复用正在执行的刷新任务")
            return await refreshTask.value
        }

        let task = Task<AISCredentialRefreshOutcome, Never> {
            await refresh(baseURL: baseURL, urlSession: urlSession)
        }
        refreshTask = task
        let outcome = await task.value
        refreshTask = nil
        return outcome
    }

    private func refresh(
        baseURL: URL,
        urlSession: URLSession
    ) async -> AISCredentialRefreshOutcome {
        guard let stored = await loadSession(),
              let url = URL(
                string: "/api/ais/auth/refresh",
                relativeTo: baseURL
              )?.absoluteURL else {
            await recordDiagnostic("本地刷新会话不存在")
            return .rejected
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        request.httpBody = try? JSONEncoder().encode(
            ["refreshToken": stored.refreshToken]
        )

        do {
            let (data, response) = try await executeRequest(
                request,
                urlSession
            )
            guard let httpResponse = response as? HTTPURLResponse else {
                await recordDiagnostic("刷新响应无有效 HTTP 状态，保留本地会话")
                return .preserved
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401
                    || httpResponse.statusCode == 403 {
                    await clearSession()
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .aisCredentialRejected,
                            object: nil
                        )
                    }
                    await recordDiagnostic(
                        "服务端刷新会话不存在、已失效或被拒绝，状态码 \(httpResponse.statusCode)"
                    )
                    return .rejected
                }
                await recordDiagnostic(
                    "刷新服务暂时不可用，状态码 \(httpResponse.statusCode)，保留本地会话"
                )
                return .preserved
            }
            let envelope = try JSONDecoder().decode(
                APIEnvelope<AuthToken>.self,
                from: data
            )
            guard envelope.success, let token = envelope.response,
                  let refreshToken = token.refreshToken,
                  !refreshToken.isEmpty else {
                await recordDiagnostic("刷新响应缺少有效令牌，保留本地会话")
                return .preserved
            }
            try await saveSession(
                AISStoredSession(
                    accessToken: token.accessToken,
                    refreshToken: refreshToken,
                    user: stored.user,
                    refreshedAt: .now,
                    lastOpenedAt: .now,
                    authenticationProvider: stored.authenticationProvider,
                    appleUserIdentifier: stored.appleUserIdentifier
                )
            )
            await recordDiagnostic("登录会话刷新成功")
            return .available(token.accessToken)
        } catch {
            // 网络和解析异常不代表凭据失效，保留会话等待下次重试。
            await recordDiagnostic("刷新请求失败，保留本地会话")
            return .preserved
        }
    }

    private func isUsable(_ token: String) -> Bool {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return !token.isEmpty }
        var value = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder > 0 {
            value += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: value),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let expiration = object["exp"] as? NSNumber else {
            return true
        }
        return expiration.doubleValue
            > Date.now.timeIntervalSince1970 + 90
    }
}

private enum AISCredentialStoreError: Error {
    case encodingFailed
}
