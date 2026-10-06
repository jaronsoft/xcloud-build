import Foundation

enum APIClientError: LocalizedError {
    case invalidBaseURL
    case invalidRequestPath
    case unacceptableStatusCode(Int)
    case invalidResponse
    case secureStorageUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Meroli API 地址未配置或无效。"
        case .invalidRequestPath:
            "API 请求路径无效。"
        case let .unacceptableStatusCode(statusCode):
            "Meroli API 返回 HTTP \(statusCode)。"
        case .invalidResponse:
            "Meroli API 返回了无法读取的响应。"
        case .secureStorageUnavailable:
            "无法安全保存 Meroli 登录状态。"
        }
    }

    var statusCode: Int? {
        guard case let .unacceptableStatusCode(code) = self else { return nil }
        return code
    }
}

struct APIClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL? = AppConfiguration.apiBaseURL, session: URLSession = .shared) throws {
        guard let baseURL,
              let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              baseURL.host != nil,
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.query == nil,
              baseURL.fragment == nil,
              baseURL.path.isEmpty || baseURL.path == "/" else {
            throw APIClientError.invalidBaseURL
        }
        self.baseURL = baseURL
        self.session = session
    }

    func request(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        authorization: String? = nil,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> Data {
        let relativePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty,
              !relativePath.split(separator: "/").contains(".."),
              !relativePath.hasPrefix("api/") else {
            throw APIClientError.invalidRequestPath
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/v1/\(relativePath)"
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw APIClientError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if relativePath == "calendar" || relativePath == "events" || relativePath.hasPrefix("events/") {
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let authorization {
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIClientError.unacceptableStatusCode(httpResponse.statusCode)
        }
        return data
    }
}
