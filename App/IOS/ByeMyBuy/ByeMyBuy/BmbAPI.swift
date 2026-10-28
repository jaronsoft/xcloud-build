import CryptoKit
import Foundation
import Security

struct BmbEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let status: Int?
    let msg: String?
    let response: T?
}

struct BmbAuth: Decodable {
    let UserId: String
    let AccessToken: String
    let RefreshToken: String?
    let Email: String?
    let Phone: String?
    let DisplayName: String?
    let AvatarUrl: String?
    let DefaultCurrency: String?
    let CountryCode: String?
}

struct BmbNonce: Decodable { let Nonce: String }
struct BmbAcknowledgement: Decodable { let Recorded: Bool?; let Sent: Bool?; let Set: Bool?; let Bound: Bool?; let Deleted: Bool?; let PendingReview: Bool?; let Reported: Bool? }

struct BmbProduct: Codable, Identifiable {
    var Id: String? = nil
    var Title: String = ""
    var Model: String? = nil
    var Tags: [String]? = nil
    var Url: String? = nil
    var ImageUrl: String? = nil
    var Price: Double? = nil
    var Currency: String? = nil
    var TargetPrice: Double? = nil
    var Source: String? = "user"
    var CapturedAt: String? = nil
    var id: String { Id ?? Url ?? Title }
}

struct BmbComment: Decodable, Identifiable {
    let Id: String
    let Body: String
    let SuggestedUrl: String?
    let Status: String
    let CreateTime: String?
    var id: String { Id }
}

struct BmbPriceOffer: Decodable, Identifiable {
    let Model: String?
    let NeedsReconfirmation: Bool?
    let Id: String
    let ProductId: String
    let SiteName: String
    let CountryCode: String
    let Price: Double
    let Currency: String
    let MeetsTarget: Bool
    let Url: String?
    let Note: String?
    let Status: String
    let CreateTime: String
    var id: String { Id }
}

struct BmbDecision: Decodable, Identifiable {
    let Language: String?
    let PromoLinks: [BmbPromoLink]?
    let IsWaiting: Bool?
    let ReviewAt: String?
    let Hesitation: String?
    let SelectedOption: String?
    let IsFollowing: Bool?
    let VoteReasons: [String: [String: Int]]?
    let Feedback: [BmbFeedback]?
    let Id: String
    let ShareToken: String
    let ShareUrl: String
    let Mode: String
    let Question: String
    let Status: String
    let Visibility: String?
    let PublicReviewStatus: String?
    let FinalChoice: String?
    let IsOwner: Bool
    let Products: [BmbProduct]
    let Votes: [String: Int]
    let VoteCount: Int
    let Comments: [BmbComment]
    let PriceOffers: [BmbPriceOffer]
    var id: String { Id }
}

struct BmbPromoLink: Decodable, Identifiable {
    let Id: String
    let ProductId: String
    let Url: String
    let Note: String
    let Status: String
    var id: String { Id }
}

struct BmbDecisionSummary: Decodable, Identifiable {
    let Id: String
    let ShareToken: String
    let Question: String
    let Mode: String
    let Status: String
    let Visibility: String?
    let PublicReviewStatus: String?
    let FinalChoice: String?
    let CreateTime: String
    let ImageUrl: String?
    let Votes: [String: Int]
    let CommentCount: Int
    var id: String { Id }
}

struct BmbPublicDecision: Decodable, Identifiable {
    let Language: String?
    let IsWaiting: Bool?
    let FinalChoice: String?
    let VoteCount: Int?
    let Hesitation: String?
    let Id: String
    let ShareToken: String
    let Mode: String
    let Question: String
    let Status: String
    let Products: [BmbProduct]
    var id: String { Id }
}

struct BmbPublicPage: Decodable {
    let Items: [BmbPublicDecision]
    let Total: Int
    let Snapshot: Int64?
    let Page: Int
    let HasMore: Bool
}

struct BmbProfile: Decodable {
    let UserId: String
    let Email: String?
    let Phone: String?
    let DisplayName: String?
    let AvatarUrl: String?
    let DefaultCurrency: String?
    let CountryCode: String?
    let NicknameReviewPending: Bool?
    let AvatarReviewPending: Bool?
}

struct BmbError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum BmbKeychain {
    private static let service = "com.wekarepartners.byemybuy"
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ account: String, value: String?) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

actor BmbAuthRenewal {
    static let shared = BmbAuthRenewal()
    private var task: Task<String, Error>?

    func refresh(rejected: String?) async throws -> String {
        if let current = BmbKeychain.read("access"), current != rejected { return current }
        if let task { return try await task.value }
        let newTask = Task<String, Error> {
            guard let refresh = BmbKeychain.read("refresh") else { throw BmbError(message: "Please sign in again.") }
            var request = URLRequest(url: URL(string: "/api/byemybuy/auth/refresh", relativeTo: BmbAPI.baseURL)!.absoluteURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["RefreshToken": refresh])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BmbError(message: "Session refresh unavailable.") }
            let result = try? JSONDecoder().decode(BmbEnvelope<BmbAuth>.self, from: data)
            if http.statusCode == 401 || result?.status == 401 {
                BmbKeychain.write("access", value: nil)
                BmbKeychain.write("refresh", value: nil)
                NotificationCenter.default.post(name: Notification.Name("BmbAuthChanged"), object: nil)
                throw BmbError(message: "Please sign in again.")
            }
            guard http.statusCode < 400, result?.success == true,
                  let auth = result?.response, let next = auth.RefreshToken else {
                throw BmbError(message: result?.msg ?? "Session refresh unavailable.")
            }
            BmbKeychain.write("access", value: auth.AccessToken)
            BmbKeychain.write("refresh", value: next)
            NotificationCenter.default.post(name: Notification.Name("BmbAuthChanged"), object: nil)
            return auth.AccessToken
        }
        task = newTask
        defer { task = nil }
        return try await newTask.value
    }
}

struct BmbAPI {
    static let baseURL = URL(string: "https://byemybuy.get-free.net")!

    private func cacheKey(_ path: String, token: String?) -> String { "GET:/api/byemybuy\(path):\(token ?? "public")" }

    func cached<T: Decodable>(_ path: String, token: String? = nil) async -> T? {
        guard let data = await BmbCache.shared.data(for: cacheKey(path, token: token)),
              let envelope = try? JSONDecoder().decode(BmbEnvelope<T>.self, from: data), envelope.success else { return nil }
        return envelope.response
    }

    func call<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, token: String? = nil) async throws -> T {
        guard let url = URL(string: "/api/byemybuy\(path)", relativeTo: Self.baseURL)?.absoluteURL else {
            throw BmbError(message: "Invalid request URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let currentToken = token == nil ? nil : (BmbKeychain.read("access") ?? token)
        if let currentToken { request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization") }
        if let visitor = BmbKeychain.read("visitor") { request.setValue(visitor, forHTTPHeaderField: "X-BMB-Visitor") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let startedAt = Date()
        let initial: (Data, URLResponse)
        do { initial = try await URLSession.shared.data(for: request) }
        catch {
            await BmbDiagnostics.shared.record("API", "\(method) \(Self.diagnosticPath(path)) · network error")
            throw error
        }
        var (data, response) = initial
        await BmbDiagnostics.shared.record("API", "\(method) \(Self.diagnosticPath(path)) · \((response as? HTTPURLResponse)?.statusCode ?? 0) · \(Int(Date().timeIntervalSince(startedAt) * 1000)) ms")
        if let http = response as? HTTPURLResponse, let currentToken,
           (http.statusCode == 401 || (try? JSONDecoder().decode(BmbEnvelope<T>.self, from: data))?.status == 401),
           !["/auth/email/send-code", "/auth/email", "/auth/password", "/auth/apple/nonce", "/auth/apple", "/auth/mini", "/auth/refresh", "/auth/logout"].contains(path) {
            let renewed = try await BmbAuthRenewal.shared.refresh(rejected: currentToken)
            request.setValue("Bearer \(renewed)", forHTTPHeaderField: "Authorization")
            (data, response) = try await URLSession.shared.data(for: request)
            await BmbDiagnostics.shared.record("API", "\(method) \(Self.diagnosticPath(path)) · retry \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard let http = response as? HTTPURLResponse else { throw BmbError(message: "No server response") }
        if http.statusCode == 401, currentToken != nil {
            BmbKeychain.write("access", value: nil)
            BmbKeychain.write("refresh", value: nil)
            NotificationCenter.default.post(name: Notification.Name("BmbAuthChanged"), object: nil)
        }
        guard let envelope = try? JSONDecoder().decode(BmbEnvelope<T>.self, from: data) else {
            throw BmbError(message: "Unexpected server response (\(http.statusCode))")
        }
        guard http.statusCode < 400, envelope.success, let value = envelope.response else {
            throw BmbError(message: envelope.msg ?? "Request failed")
        }
        if method == "POST", path == "/decisions", let decision = value as? BmbDecision {
            Task { await track("create_completed", shareToken: decision.ShareToken, token: token) }
        }
        let segments = path.split(separator: "/")
        if method == "POST", segments.count == 3, segments[0] == "d", segments[2] == "votes" || (segments[2] == "final-choice" && body?["Choice"] as? String != "waiting") {
            let code = segments[2] == "votes" ? "vote_recorded" : "final_choice_recorded"
            let shareToken = String(segments[1])
            Task { await track(code, shareToken: shareToken, token: token) }
        }
        if method == "GET" && path != "/auth/apple/nonce" {
            await BmbCache.shared.storeData(data, for: cacheKey(path, token: token))
        }
        return value
    }

    private static func diagnosticPath(_ path: String) -> String {
        let parts = path.split(separator: "?", maxSplits: 1)
        let route = String(parts.first ?? "")
        return route.hasPrefix("/d/") ? "/d/[decision]" : route
    }

    func resolve(_ url: String) async throws -> BmbProduct {
        try await call("/products/resolve", method: "POST", body: ["Url": url])
    }

    func track(_ code: String, shareToken: String? = nil, token: String? = nil) async {
        let body: [String: Any] = ["EventId": UUID().uuidString, "EventCode": code, "ShareToken": shareToken as Any? ?? NSNull(), "Client": "ios"]
        let _: BmbAcknowledgement? = try? await call("/events", method: "POST", body: body, token: token)
    }

    func uploadProductImage(_ data: Data, token: String) async throws -> String {
        try await uploadImage(data, token: token, path: "/products/image")
    }

    func deleteProductImage(_ imageURL: String, token: String) async throws {
        let _: BmbAcknowledgement = try await call("/products/image", method: "DELETE", body: ["ImageUrl": imageURL], token: token)
    }

    func uploadAvatarImage(_ data: Data, token: String) async throws -> String {
        try await uploadImage(data, token: token, path: "/auth/me/avatar")
    }

    private func uploadImage(_ data: Data, token: String, path: String) async throws -> String {
        let boundary = UUID().uuidString
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"product.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: URL(string: "/api/byemybuy\(path)", relativeTo: Self.baseURL)!.absoluteURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let currentToken = BmbKeychain.read("access") ?? token
        request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")
        var (responseData, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           (http.statusCode == 401 || (try? JSONDecoder().decode(BmbEnvelope<BmbImageUpload>.self, from: responseData))?.status == 401) {
            let renewed = try await BmbAuthRenewal.shared.refresh(rejected: currentToken)
            request.setValue("Bearer \(renewed)", forHTTPHeaderField: "Authorization")
            (responseData, response) = try await URLSession.shared.data(for: request)
        }
        guard let http = response as? HTTPURLResponse,
              let envelope = try? JSONDecoder().decode(BmbEnvelope<BmbImageUpload>.self, from: responseData),
              http.statusCode < 400, envelope.success, let value = envelope.response else {
            throw BmbError(message: "Could not upload this photo.")
        }
        return value.ImageUrl
    }
    func detail(_ shareToken: String, token: String?) async throws -> BmbDecision {
        try await call("/d/\(shareToken)", token: token)
    }
    func vote(_ shareToken: String, choice: String) async throws {
        let _: BmbAcknowledgement = try await call("/d/\(shareToken)/votes", method: "POST", body: ["Choice": choice])
    }
}

struct BmbImageUpload: Decodable { let ImageUrl: String }

@MainActor
final class BmbSession: ObservableObject {
    @Published private(set) var token: String? = BmbKeychain.read("access")
    @Published var profile: BmbProfile?
    @Published var message: String?
    @Published var showLogin = false
    let api = BmbAPI()
    var isLoggedIn: Bool { token != nil || BmbKeychain.read("refresh") != nil }

    init() {
        if BmbKeychain.read("visitor") == nil {
            BmbKeychain.write("visitor", value: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
        }
    }


    func syncAuth() {
        token = BmbKeychain.read("access")
        if token == nil { profile = nil }
    }

    func restoreSession() async {
        guard token == nil, BmbKeychain.read("refresh") != nil else { return }
        do {
            _ = try await BmbAuthRenewal.shared.refresh(rejected: nil)
            syncAuth()
        } catch {
            // 网络中断时保留刷新凭据，下一次进入页面继续尝试恢复。
            syncAuth()
        }
    }

    func adopt(_ result: BmbAuth) {
        token = result.AccessToken
        BmbKeychain.write("access", value: result.AccessToken)
        BmbKeychain.write("refresh", value: result.RefreshToken)
        profile = BmbProfile(UserId: result.UserId, Email: result.Email, Phone: result.Phone, DisplayName: result.DisplayName, AvatarUrl: result.AvatarUrl, DefaultCurrency: result.DefaultCurrency, CountryCode: result.CountryCode, NicknameReviewPending: nil, AvatarReviewPending: nil)
    }

    func sendCode(_ email: String) async throws {
        let _: BmbAcknowledgement = try await api.call("/auth/email/send-code", method: "POST", body: ["Email": email])
    }

    func login(email: String, code: String) async throws {
        let result: BmbAuth = try await api.call("/auth/email", method: "POST", body: ["Email": email, "Code": code])
        adopt(result)
    }

    func login(email: String, password: String) async throws {
        let result: BmbAuth = try await api.call("/auth/password", method: "POST", body: ["Email": email, "Password": password])
        adopt(result)
    }

    func appleNonce() async throws -> String {
        let result: BmbNonce = try await api.call("/auth/apple/nonce")
        return result.Nonce
    }

    func loginApple(identityToken: String, nonce: String, name: String?) async throws {
        let result: BmbAuth = try await api.call("/auth/apple", method: "POST", body: ["IdentityToken": identityToken, "Nonce": nonce, "DisplayName": name ?? ""])
        adopt(result)
    }

    func loadProfile() async {
        guard let token else { return }
        if profile == nil { profile = await api.cached("/auth/me", token: token) }
        do { profile = try await api.call("/auth/me", token: token) }
        catch { message = error.localizedDescription }
    }

    func logout() {
        let refresh = BmbKeychain.read("refresh")
        token = nil; profile = nil; BmbKeychain.write("access", value: nil); BmbKeychain.write("refresh", value: nil)
        if let refresh { Task { let _: BmbAcknowledgement? = try? await api.call("/auth/logout", method: "POST", body: ["RefreshToken": refresh]) } }
        Task { await BmbCache.shared.clearData() }
    }

    func deleteAccount() async throws {
        guard let token else { return }
        let _: BmbAcknowledgement = try await api.call("/auth/me", method: "DELETE", token: token)
        logout()
    }
}
