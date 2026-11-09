import Foundation
import Security
import CryptoKit
import UIKit

enum NativePublicFeatureAccessState: Equatable {
    case open
    case closed
    case pendingConfirmation
    case unavailable

    func message(featureName: String, action: String) -> String {
        switch self {
        case .open:
            return ""
        case .closed:
            return "\(featureName)暂未开放；\(action)"
        case .pendingConfirmation:
            return "\(featureName)开放状态待确认；\(action)"
        case .unavailable:
            return "暂时无法确认\(featureName)开放状态，请检查网络后重新读取。"
        }
    }
}


enum MobileAPIError: LocalizedError {
    case unavailable(String)
    case forbidden(String)
    case rejected(statusCode: Int, message: String)

    var httpStatusCode: Int? {
        switch self {
        case .unavailable: return nil
        case .forbidden: return 403
        case let .rejected(statusCode, _): return statusCode
        }
    }

    var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .forbidden(message), let .rejected(_, message): return message
        }
    }
}

@MainActor
final class MobileAPI {
    let store: SessionStore
    let baseURL: URL
    private let transport: URLSession
    private struct RefreshFlight {
        let id: UUID
        let token: String
        let task: Task<TourismSession, Error>
    }
    private static var refreshFlights: [ObjectIdentifier: RefreshFlight] = [:]
    private struct RefreshRejected: Error {}

    private static func allowsAPIURL(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        #if DEBUG
        return url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased() ?? "")
        #else
        return false
        #endif
    }

    func performNetworkRequest<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            guard let urlError = error as? URLError else { throw error }
            let message = urlError.code == .timedOut
                ? "请求超时，请稍后重试。"
                : "暂时无法连接服务，请检查网络后重试。"
            throw MobileAPIError.unavailable(message)
        }
    }

    init(store: SessionStore, transport: URLSession = .shared) {
        self.store = store
        self.transport = transport
        let configured = Bundle.main.object(forInfoDictionaryKey: "JHCTIAPIBaseURL") as? String ?? ""
        guard let url = URL(string: configured), Self.allowsAPIURL(url) else {
            preconditionFailure("正式环境须配置 HTTPS JHCTIAPIBaseURL；Debug 仅可使用 HTTPS 或本机回环 HTTP")
        }
        baseURL = url
    }

    func nativeTourismPrincipal(_ token: String) -> String {
        let parts = token.split(separator: ".")
        if parts.count == 3 {
            var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            if let data = Data(base64Encoded: payload),
               let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let subject = claims["sub"] as? String, !subject.isEmpty,
               let sessionId = claims["sid"] as? String, !sessionId.isEmpty {
                return subject + ":" + sessionId
            }
        }
        return SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func get(_ path: String, authenticated: Bool = false, expectedPrincipal: String? = nil) async throws -> Any {
        try await request(path, method: "GET", body: nil, authenticated: authenticated, canRefresh: true,
                          expectedPrincipal: expectedPrincipal)
    }

    func hasPublicCachedData(_ path: String) -> Bool {
        NativePublicCache.shared.publicData(for: baseURL.absoluteString + path, allowStale: true) != nil
    }

    func getPublicCached(_ path: String, forceRefresh: Bool = false, allowStale: Bool = false) async throws -> Any {
        let key = baseURL.absoluteString + path
        if !forceRefresh, let cached = NativePublicCache.shared.publicData(for: key, allowStale: allowStale) { return cached }
        let value = try await get(path)
        NativePublicCache.shared.savePublicData(value, for: key)
        return value
    }

    func post(_ path: String, body: [String: Any], authenticated: Bool = false,
              expectedPrincipal: String? = nil) async throws -> Any {
        try await request(path, method: "POST", body: body, authenticated: authenticated,
                          canRefresh: true, expectedPrincipal: expectedPrincipal)
    }

    func postJSON(_ path: String, body: Any, authenticated: Bool = false,
                  expectedPrincipal: String? = nil) async throws -> Any {
        try await request(path, method: "POST", body: body, authenticated: authenticated, canRefresh: true,
                          expectedPrincipal: expectedPrincipal)
    }

    func delete(_ path: String, authenticated: Bool = false, expectedPrincipal: String? = nil) async throws -> Any {
        try await request(path, method: "DELETE", body: nil, authenticated: authenticated, canRefresh: true,
                          expectedPrincipal: expectedPrincipal)
    }

    func featureAccessState(_ id: String, allowStale: Bool = false, forceRefresh: Bool = false) async -> NativePublicFeatureAccessState {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let status = try? await getPublicCached("/api/JHCTIFeatureAccess/GetPublicStatus?featureId=\(encoded)",
                                                       forceRefresh: forceRefresh, allowStale: allowStale) as? [String: Any] else {
            return .unavailable
        }
        guard let configured = status["IsConfigured"] as? Bool,
              let enabled = status["IsEnabled"] as? Bool else { return .unavailable }
        switch status["Status"] as? String {
        case "Open": return configured && enabled ? .open : .unavailable
        case "Closed": return configured && !enabled ? .closed : .unavailable
        case "PendingConfirmation": return !configured ? .pendingConfirmation : .unavailable
        default: return .unavailable
        }
    }

    func featureEnabled(_ id: String, allowStale: Bool = false, forceRefresh: Bool = false) async -> Bool {
        await featureAccessState(id, allowStale: allowStale, forceRefresh: forceRefresh) == .open
    }

    func passwordLoginEnabled() async throws -> Bool {
        try await get("/api/JHCTITourismAuth/GetLoginAvailability") as? Bool == true
    }

    func smsLoginEnabled() async throws -> Bool {
        try await get("/api/JHCTITourismAuth/GetH5SmsLoginAvailability") as? Bool == true
    }

    func passwordRecoveryEnabled() async throws -> Bool {
        try await get("/api/JHCTITourismAuth/GetPasswordRecoveryAvailability") as? Bool == true
    }

    func captcha() async throws -> (key: String, image: Data) {
        guard let key = try await get("/api/auth/snowflake") as? String,
              let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let value = try await get("/api/auth/generate-captcha?keyid=\(encoded)") as? String,
              let image = Data(base64Encoded: value) else {
            throw MobileAPIError.unavailable("图形验证码加载失败，请刷新重试")
        }
        return (key, image)
    }

    func sendPhoneCode(phone: String, captchaKey: String, captcha: String) async throws -> String? {
        try await post("/api/JHCTITourismAuth/SendPhoneVerificationCode",
                       body: ["PhoneNumber": phone, "CaptchaKey": captchaKey, "Captcha": captcha]) as? String
    }

    func sendPasswordRecoveryCode(phone: String, captchaKey: String, captcha: String) async throws -> String? {
        try await post("/api/JHCTITourismAuth/SendPasswordRecoveryCode",
                       body: ["PhoneNumber": phone, "CaptchaKey": captchaKey, "Captcha": captcha]) as? String
    }

    func resetPasswordWithPhoneCode(phone: String, code: String, password: String) async throws {
        _ = try await post("/api/JHCTITourismAuth/ResetPasswordWithPhoneCode",
                           body: ["PhoneNumber": phone, "SmsCode": code, "Password": password])
    }

    func mediaURL(_ path: String?) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty,
              path.utf8.count <= 2048, !path.hasPrefix("//"), !path.contains("\\"),
              path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              Self.allowsAPIURL(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil else { return nil }
        return url
    }

    func refreshSession(_ old: TourismSession) async throws -> TourismSession {
        let principal = nativeTourismPrincipal(old.accessToken)
        guard let current = store.session, nativeTourismPrincipal(current.accessToken) == principal else {
            throw MobileAPIError.unavailable("登录账号已变化，请重新操作")
        }
        if current.accessToken != old.accessToken { return current }
        let key = ObjectIdentifier(store)
        if let flight = Self.refreshFlights[key], flight.token == old.accessToken {
            return try await flight.task.value
        }
        let id = UUID()
        // 刷新令牌只能轮换一次，共享任务独立于单个页面取消，避免丢失已轮换的登录态。
        let task = Task { @MainActor in
            defer { if Self.refreshFlights[key]?.id == id { Self.refreshFlights[key] = nil } }
            do {
                let result = try await request("/api/JHCTITourismAuth/Refresh", method: "POST",
                    body: ["RefreshToken": old.refreshToken], authenticated: false, canRefresh: false)
                guard let value = result as? [String: Any],
                      let token = value["AccessToken"] as? String, !token.isEmpty,
                      let refresh = value["RefreshToken"] as? String, !refresh.isEmpty,
                      nativeTourismPrincipal(token) == principal else {
                    throw MobileAPIError.unavailable("登录续期响应无效，请重新核对登录状态")
                }
                guard store.session?.accessToken == old.accessToken else {
                    throw MobileAPIError.unavailable("登录账号已变化，请重新操作")
                }
                let next = TourismSession(accessToken: token, refreshToken: refresh, userName: old.userName)
                guard store.save(next) else { throw MobileAPIError.unavailable("登录状态保存失败，请重试") }
                return next
            } catch is RefreshRejected {
                if store.session?.accessToken == old.accessToken { store.clear() }
                throw MobileAPIError.unavailable("登录已失效，请重新登录")
            }
        }
        Self.refreshFlights[key] = RefreshFlight(id: id, token: old.accessToken, task: task)
        return try await task.value
    }

    private func request(_ path: String, method: String, body: Any?, authenticated: Bool, canRefresh: Bool,
                         expectedPrincipal: String? = nil) async throws -> Any {
        guard path.hasPrefix("/api/"), let url = URL(string: path, relativeTo: baseURL) else {
            throw MobileAPIError.unavailable("请求路径无效")
        }
        let requestSession = store.session
        try Task.checkCancellation()
        let principal = authenticated ? expectedPrincipal ?? requestSession.map({ nativeTourismPrincipal($0.accessToken) }) : nil
        if authenticated && requestSession == nil { throw MobileAPIError.unavailable("请先登录后继续") }
        if let expectedPrincipal, requestSession.map({ nativeTourismPrincipal($0.accessToken) }) != expectedPrincipal {
            throw MobileAPIError.unavailable("登录账号已变化，请重新操作")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = 12
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated, let token = requestSession?.accessToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await performNetworkRequest {
            try await transport.data(for: urlRequest)
        }
        try Task.checkCancellation()
        if let principal, store.session.map({ nativeTourismPrincipal($0.accessToken) }) != principal {
            throw MobileAPIError.unavailable("登录账号已变化，请重新操作")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let apiStatus = envelope["status"] as? Int ?? envelope["Status"] as? Int
        if authenticated && (status == 401 || apiStatus == 401) {
            if canRefresh, let old = requestSession {
                _ = try await refreshSession(old)
                try Task.checkCancellation()
                return try await request(path, method: method, body: body, authenticated: true,
                                         canRefresh: false, expectedPrincipal: principal)
            }
            if store.session?.accessToken == requestSession?.accessToken { store.clear() }
            throw MobileAPIError.unavailable("登录已失效，请重新登录")
        }
        if status == 401 || apiStatus == 401 {
            if path == "/api/JHCTITourismAuth/Refresh" { throw RefreshRejected() }
            throw MobileAPIError.rejected(statusCode: apiStatus ?? status, message: "登录已失效，请重新登录")
        }
        if !(200..<300).contains(status) || (envelope["Success"] as? Bool == false) || (envelope["success"] as? Bool == false) {
            let message = (envelope["Msg"] ?? envelope["msg"] ?? envelope["Message"] ?? envelope["message"]) as? String
            if status == 403 || apiStatus == 403 {
                throw MobileAPIError.forbidden(message ?? "当前账号无权执行此操作")
            }
            throw MobileAPIError.rejected(statusCode: apiStatus ?? status,
                                           message: message ?? "请求失败，请稍后重试")
        }
        return envelope["Response"] ?? envelope["response"] ?? envelope["Data"] ?? envelope["data"] ?? NSNull()
    }

    func login(phone: String, password: String, agreementIDs: [String]) async throws {
        guard let value = try await post("/api/JHCTITourismAuth/LoginWithPhonePassword",
                                         body: ["PhoneNumber": phone, "Password": password, "AgreementIds": agreementIDs]) as? [String: Any],
              let token = value["AccessToken"] as? String,
              let refresh = value["RefreshToken"] as? String else {
            throw MobileAPIError.unavailable("登录响应无效")
        }
        let user = value["User"] as? [String: Any]
        guard store.save(TourismSession(accessToken: token, refreshToken: refresh,
                                        userName: user?["NickName"] as? String ?? "")) else {
            throw MobileAPIError.unavailable("登录状态保存失败，请重试")
        }
    }

    func loginWithPhoneCode(phone: String, code: String, agreementIDs: [String]) async throws {
        guard let value = try await post("/api/JHCTITourismAuth/LoginWithPhoneCode",
                                         body: ["PhoneNumber": phone, "SmsCode": code, "AgreementIds": agreementIDs]) as? [String: Any],
              let token = value["AccessToken"] as? String,
              let refresh = value["RefreshToken"] as? String else {
            throw MobileAPIError.unavailable("登录响应无效")
        }
        let user = value["User"] as? [String: Any]
        guard store.save(TourismSession(accessToken: token, refreshToken: refresh,
                                        userName: user?["NickName"] as? String ?? "")) else {
            throw MobileAPIError.unavailable("登录状态保存失败，请重试")
        }
    }

    func logout() async {
        let principal = store.session.map { nativeTourismPrincipal($0.accessToken) }
        defer {
            if let principal, store.session.map({ nativeTourismPrincipal($0.accessToken) }) == principal { store.clear() }
        }
        _ = try? await post("/api/JHCTITourismAuth/Logout", body: [:], authenticated: true,
                            expectedPrincipal: principal)
    }
}
