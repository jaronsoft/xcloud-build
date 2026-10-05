import Foundation
import Security

extension Notification.Name {
    static let pixaCredentialDidRefresh = Notification.Name("PixaCredentialDidRefresh")
    static let pixaCredentialRejected = Notification.Name("PixaCredentialRejected")
}

struct PixaStoredSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser
    let refreshedAt: Date
    let lastOpenedAt: Date

    private enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, user, refreshedAt, lastOpenedAt
    }

    init(
        accessToken: String,
        refreshToken: String,
        user: AuthUser,
        refreshedAt: Date,
        lastOpenedAt: Date
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.user = user
        self.refreshedAt = refreshedAt
        self.lastOpenedAt = lastOpenedAt
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try box.decode(String.self, forKey: .accessToken)
        refreshToken = try box.decode(String.self, forKey: .refreshToken)
        user = try box.decode(AuthUser.self, forKey: .user)
        // 新版本增加会话时间字段时兼容旧数据，避免一次普通更新直接清空登录态。
        refreshedAt = try box.decodeIfPresent(Date.self, forKey: .refreshedAt) ?? .distantPast
        lastOpenedAt = try box.decodeIfPresent(Date.self, forKey: .lastOpenedAt) ?? .now
    }
}

enum PixaCredentialStore {
    private static let account = "auth-session-v2"
    private static let lock = NSLock()

    static func load() -> PixaStoredSession? {
        lock.withLock { loadUnlocked() }
    }

    private static func loadUnlocked() -> PixaStoredSession? {
        guard let data = KeychainStore.loadData(account: account) else { return nil }
        return try? JSONDecoder().decode(PixaStoredSession.self, from: data)
    }

    @discardableResult
    static func save(_ session: PixaStoredSession) -> Bool {
        lock.withLock { saveUnlocked(session) }
    }

    private static func saveUnlocked(_ session: PixaStoredSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        return KeychainStore.save(data, account: account) == errSecSuccess
    }

    @discardableResult
    static func save(
        _ session: PixaStoredSession,
        replacingRefreshToken expectedRefreshToken: String
    ) -> Bool {
        lock.withLock {
            guard loadUnlocked()?.refreshToken == expectedRefreshToken else { return false }
            return saveUnlocked(session)
        }
    }

    @discardableResult
    static func updateLastOpened(
        accessToken: String?,
        user: AuthUser?
    ) -> Bool {
        lock.withLock {
            guard let stored = loadUnlocked() else { return false }
            return saveUnlocked(
                PixaStoredSession(
                    accessToken: accessToken ?? stored.accessToken,
                    refreshToken: stored.refreshToken,
                    user: user ?? stored.user,
                    refreshedAt: stored.refreshedAt,
                    lastOpenedAt: .now
                )
            )
        }
    }

    static func clear() {
        lock.withLock { KeychainStore.delete(account: account) }
    }
}

enum PixaCredentialRefreshOutcome: Sendable {
    case available(String)
    case preserved
    case rejected
}

actor PixaCredentialRecovery {
    static let shared = PixaCredentialRecovery()

    private var refreshTask: Task<PixaCredentialRefreshOutcome, Never>?

    func refreshAccessToken(
        rejectedAccessToken: String? = nil,
        session: URLSession = .shared
    ) async -> PixaCredentialRefreshOutcome {
        if let stored = PixaCredentialStore.load(),
           let rejectedAccessToken,
           stored.accessToken != rejectedAccessToken,
           PixaJWT.isUsable(stored.accessToken) {
            return .available(stored.accessToken)
        }
        if let refreshTask { return await refreshTask.value }
        let task = Task { await refresh(session: session) }
        refreshTask = task
        let outcome = await task.value
        refreshTask = nil
        return outcome
    }

    private func refresh(session: URLSession) async -> PixaCredentialRefreshOutcome {
        await refresh(session: session, retryRemaining: 1)
    }

    private func refresh(
        session: URLSession,
        retryRemaining: Int
    ) async -> PixaCredentialRefreshOutcome {
        guard let stored = PixaCredentialStore.load() else {
            await rejectCredentials()
            return .rejected
        }
        var request = URLRequest(
            url: AppConfiguration.apiBaseURL.appending(path: "/api/ais/auth/refresh")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        request.setValue(PixaMediaRegion.headerValue, forHTTPHeaderField: "X-AIS-Media-Region")
        request.setValue(PixaMediaRegion.preferenceHeaderValue, forHTTPHeaderField: "X-AIS-Media-Region-Preference")
        request.httpBody = try? JSONEncoder().encode(
            ["refreshToken": stored.refreshToken]
        )
        let startedAt = Date.now
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .preserved }
            let envelope = try? JSONDecoder().decode(APIEnvelope<AuthToken>.self, from: data)
            let statusCode = envelope?.status ?? response.statusCode
            if response.statusCode == 401 || response.statusCode == 403
                || envelope?.status == 401 || envelope?.status == 403 {
                await NetworkDiagnosticsStore.shared.record(
                    startedAt: startedAt,
                    request: request,
                    statusCode: statusCode,
                    succeeded: false,
                    message: "登录会话已失效"
                )
                await rejectCredentials()
                return .rejected
            }
            guard (200..<300).contains(response.statusCode),
                  let envelope,
                  envelope.success,
                  let token = envelope.response,
                  let refreshToken = token.refreshToken?.nilIfEmpty else {
                await NetworkDiagnosticsStore.shared.record(
                    startedAt: startedAt,
                    request: request,
                    statusCode: statusCode,
                    succeeded: false,
                    message: "登录会话刷新失败"
                )
                if retryRemaining > 0,
                   Self.isTransient(statusCode: statusCode) {
                    try? await Task.sleep(for: .milliseconds(800))
                    return await refresh(session: session, retryRemaining: retryRemaining - 1)
                }
                return .preserved
            }
            guard PixaCredentialStore.save(
                PixaStoredSession(
                    accessToken: token.accessToken,
                    refreshToken: refreshToken,
                    user: stored.user,
                    refreshedAt: .now,
                    lastOpenedAt: .now
                ),
                replacingRefreshToken: stored.refreshToken
            ) else {
                await NetworkDiagnosticsStore.shared.recordSystemLog(
                    tag: "AUTH_KEYCHAIN",
                    "登录会话写入系统钥匙串失败，已保留原会话"
                )
                return .preserved
            }
            await NetworkDiagnosticsStore.shared.recordSystemLog(
                tag: "AUTH_REFRESH",
                "登录会话刷新成功"
            )
            await NetworkDiagnosticsStore.shared.record(
                startedAt: startedAt,
                request: request,
                statusCode: response.statusCode,
                succeeded: true,
                message: "OK"
            )
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .pixaCredentialDidRefresh,
                    object: token.accessToken
                )
            }
            return .available(token.accessToken)
        } catch {
            // 网络故障不代表 refresh token 失效，保留会话供下次恢复。
            if !(error is CancellationError) {
                let nsError = error as NSError
                if !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
                    await NetworkDiagnosticsStore.shared.record(
                        startedAt: startedAt,
                        request: request,
                        statusCode: nil,
                        succeeded: false,
                        message: error.localizedDescription
                    )
                }
            }
            if retryRemaining > 0,
               !(error is CancellationError) {
                try? await Task.sleep(for: .milliseconds(800))
                return await refresh(session: session, retryRemaining: retryRemaining - 1)
            }
            return .preserved
        }
    }

    private static func isTransient(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || statusCode >= 500
    }

    private func rejectCredentials() async {
        PixaCredentialStore.clear()
        await MainActor.run {
            NotificationCenter.default.post(name: .pixaCredentialRejected, object: nil)
        }
    }
}

enum PixaJWT {
    static func isUsable(_ token: String?, leeway: TimeInterval = 90) -> Bool {
        guard let token, !token.isEmpty else { return false }
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return true }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 { payload += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiration = object["exp"] as? NSNumber else { return true }
        return expiration.doubleValue > Date.now.timeIntervalSince1970 + leeway
    }
}
