import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case rejected(String)
    case networkAccessDenied
    case offline
    case connectionInterrupted
    case serverUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse: AppLanguage.localized("network.invalid_response")
        case let .rejected(message): message
        case .networkAccessDenied: AppLanguage.localized("network.access_denied")
        case .offline: AppLanguage.localized("network.offline")
        case .connectionInterrupted: AppLanguage.localized("network.connection_interrupted")
        case .serverUnavailable: AppLanguage.localized("network.server_unavailable")
        }
    }
}

struct APIClient: Sendable {
    private static let visitorID: String = {
        let key = "pixarivo.analytics.visitor_id"
        if let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty {
            return stored
        }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: key)
        return value
    }()
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) { self.session = session }

    func get<Value: Decodable>(_ path: String, query: [URLQueryItem] = [], token: String? = nil, forceRefresh: Bool = false) async throws -> Value {
        try await send(path, method: "GET", query: query, body: Optional<[String: String]>.none, token: token, forceRefresh: forceRefresh)
    }

    /// 仅供公开列表使用：先由页面读取磁盘快照，网络成功后再原子更新快照。
    func getCached<Value: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        token: String? = nil,
        forceRefresh: Bool = false,
        cacheScope: String? = nil
    ) async throws -> Value {
        let key = PixaResponseCache.key(path: path, query: query, scope: cacheScope)
        return try await send(
            path,
            method: "GET",
            query: query,
            body: Optional<[String: String]>.none,
            token: token,
            forceRefresh: forceRefresh,
            responseCacheKey: key
        )
    }

    func cachedValue<Value: Decodable>(
        _ type: Value.Type,
        path: String,
        query: [URLQueryItem] = [],
        cacheScope: String? = nil
    ) async -> Value? {
        let key = PixaResponseCache.key(path: path, query: query, scope: cacheScope)
        guard let data = await PixaResponseCache.shared.read(key: key) else {
            return nil
        }
        return try? decodePayload(data)
    }

    func post<Body: Encodable, Value: Decodable>(
        _ path: String,
        body: Body,
        token: String? = nil,
        headers: [String: String] = [:]
    ) async throws -> Value {
        try await send(path, method: "POST", query: [], body: body, token: token, headers: headers)
    }

    func delete<Value: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        token: String? = nil
    ) async throws -> Value {
        try await send(
            path,
            method: "DELETE",
            query: query,
            body: Optional<[String: String]>.none,
            token: token
        )
    }

    func upload<Value: Decodable>(_ path: String, data: Data, fileName: String, mimeType: String, token: String, fields: [String: String]) async throws -> Value {
        await AppAPIRouter.shared.waitForInitialSelection()
        let boundary = "PixaRivo-\(UUID().uuidString)"
        var body = Data()
        for (key, value) in fields {
            body.appendString("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
        }
        body.appendString("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.appendString("\r\n--\(boundary)--\r\n")
        var request = try request(path, method: "POST", query: [], token: token)
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await decode(request)
    }

    private func send<Body: Encodable, Value: Decodable>(_ path: String, method: String, query: [URLQueryItem], body: Body?, token: String?, headers: [String: String] = [:], forceRefresh: Bool = false, responseCacheKey: String? = nil) async throws -> Value {
        if method != "GET" && method != "HEAD" {
            await AppAPIRouter.shared.waitForInitialSelection()
        }
        var request = try request(path, method: method, query: query, token: token)
        if forceRefresh { request.cachePolicy = .reloadIgnoringLocalCacheData }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body { request.httpBody = try encoder.encode(body) }
        return try await decode(request, responseCacheKey: responseCacheKey)
    }

    private func request(_ path: String, method: String, query: [URLQueryItem], token: String?) throws -> URLRequest {
        guard var components = URLComponents(url: AppConfiguration.apiBaseURL.appending(path: path), resolvingAgainstBaseURL: false) else { throw APIError.invalidResponse }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppLanguage.apiValue, forHTTPHeaderField: "Accept-Language")
        request.setValue(AppLanguage.apiValue, forHTTPHeaderField: "X-AIS-Language")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        request.setValue("pixarivo", forHTTPHeaderField: "X-AIS-App-Code")
        request.setValue(Self.visitorID, forHTTPHeaderField: "X-AIS-Visitor-Id")
        request.setValue(PixaMediaRegion.headerValue, forHTTPHeaderField: "X-AIS-Media-Region")
        request.setValue(PixaMediaRegion.preferenceHeaderValue, forHTTPHeaderField: "X-AIS-Media-Region-Preference")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func decode<Value: Decodable>(
        _ request: URLRequest,
        responseCacheKey: String? = nil,
        allowsMalformedJSONRetry: Bool = true
    ) async throws -> Value {
        let startedAt = Date.now
        var receivedResponse: HTTPURLResponse?
        var receivedData: Data?
        var receivedStatusCode: Int?
        var recordedAuthenticationFailure = false
        var recordedMalformedJSONFailure = false
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            receivedResponse = response
            receivedData = data
            let logicalStatus = (try? decoder.decode(APIEnvelope<EmptyResponse>.self, from: data))?.status
            receivedStatusCode = logicalStatus ?? response.statusCode
            if (response.statusCode == 401 || response.statusCode == 403
                || logicalStatus == 401 || logicalStatus == 403),
               request.value(forHTTPHeaderField: "X-PixaRivo-Auth-Retry") == nil,
               let authorization = request.value(forHTTPHeaderField: "Authorization"),
               authorization.hasPrefix("Bearer ") {
                recordedAuthenticationFailure = true
                await NetworkDiagnosticsStore.shared.record(
                    startedAt: startedAt,
                    request: request,
                    statusCode: receivedStatusCode,
                    succeeded: false,
                    message: HTTPURLResponse.localizedString(
                        forStatusCode: receivedStatusCode ?? response.statusCode
                    ),
                    details: diagnosticDetails(
                        request: request,
                        response: response,
                        data: data,
                        error: APIError.rejected(HTTPURLResponse.localizedString(
                            forStatusCode: receivedStatusCode ?? response.statusCode
                        ))
                    )
                )
                let rejectedToken = String(authorization.dropFirst("Bearer ".count))
                let outcome = await PixaCredentialRecovery.shared.refreshAccessToken(
                    rejectedAccessToken: rejectedToken,
                    session: session
                )
                if case let .available(token) = outcome {
                    var retry = request
                    retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    retry.setValue("1", forHTTPHeaderField: "X-PixaRivo-Auth-Retry")
                    return try await decode(retry, responseCacheKey: responseCacheKey)
                }
            }
            guard (200..<300).contains(response.statusCode) else {
                let envelope = try? decoder.decode(APIEnvelope<EmptyResponse>.self, from: data)
                throw APIError.rejected(Self.localizedMessage(
                    code: envelope?.extra?.messageCode,
                    params: envelope?.extra?.messageParams ?? [:],
                    fallback: envelope?.message ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
                ))
            }
            let value: Value
            do {
                value = try decodePayload(data)
            } catch {
                if allowsMalformedJSONRetry,
                   Self.isSafeToRetry(request),
                   Self.usesCompressedContentEncoding(response),
                   Self.isMalformedJSON(data) {
                    // 边缘压缩链路偶发返回缺字节的 2xx JSON 时，仅以 identity 编码重试一次，避免无限重试掩盖真实模型错误。
                    recordedMalformedJSONFailure = true
                    await NetworkDiagnosticsStore.shared.record(
                        startedAt: startedAt,
                        request: request,
                        statusCode: response.statusCode,
                        succeeded: false,
                        message: error.localizedDescription,
                        details: diagnosticDetails(
                            request: request,
                            response: response,
                            data: data,
                            error: error
                        )
                    )
                    var retry = request
                    retry.cachePolicy = .reloadIgnoringLocalCacheData
                    retry.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                    return try await decode(
                        retry,
                        responseCacheKey: responseCacheKey,
                        allowsMalformedJSONRetry: false
                    )
                }
                throw error
            }
            if let responseCacheKey {
                await PixaResponseCache.shared.write(data, key: responseCacheKey)
            }
            await AppAPIRouter.shared.reportSuccess()
            await NetworkDiagnosticsStore.shared.record(
                startedAt: startedAt,
                request: request,
                statusCode: response.statusCode,
                succeeded: true,
                message: "OK",
                details: diagnosticDetails(request: request, response: response, data: data, error: nil)
            )
            return value
        } catch {
            if Self.isCancellation(error) {
                throw error
            }
            if let retry = await AppAPIRouter.shared.retryRequestIfNeeded(
                request,
                statusCode: receivedResponse?.statusCode,
                error: receivedResponse == nil ? error : nil
            ) {
                return try await decode(
                    retry,
                    responseCacheKey: responseCacheKey,
                    allowsMalformedJSONRetry: allowsMalformedJSONRetry
                )
            }
            if !recordedAuthenticationFailure && !recordedMalformedJSONFailure {
                await NetworkDiagnosticsStore.shared.record(
                    startedAt: startedAt,
                    request: request,
                    statusCode: receivedStatusCode ?? receivedResponse?.statusCode,
                    succeeded: false,
                    message: error.localizedDescription,
                    details: diagnosticDetails(
                        request: request,
                        response: receivedResponse,
                        data: receivedData,
                        error: error
                    )
                )
            }
            throw Self.classifiedError(
                error,
                statusCode: receivedStatusCode ?? receivedResponse?.statusCode
            )
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private static func classifiedError(_ error: Error, statusCode: Int?) -> Error {
        if let statusCode, (500..<600).contains(statusCode) {
            return APIError.serverUnavailable
        }
        if AppNetworkPathSnapshot.state == .accessDenied {
            return APIError.networkAccessDenied
        }
        guard let code = urlErrorCode(in: error) else { return error }
        switch code {
        case .dataNotAllowed:
            return APIError.networkAccessDenied
        case .notConnectedToInternet, .internationalRoamingOff:
            return APIError.offline
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .networkConnectionLost, .secureConnectionFailed:
            return APIError.connectionInterrupted
        default:
            return error
        }
    }

    private static func urlErrorCode(in error: Error) -> URLError.Code? {
        if let error = error as? URLError { return error.code }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return URLError.Code(rawValue: nsError.code)
        }
        guard let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error else {
            return nil
        }
        return urlErrorCode(in: underlying)
    }

    private static func isMalformedJSON(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) == nil
    }

    private static func isSafeToRetry(_ request: URLRequest) -> Bool {
        request.httpMethod == "GET" || request.httpMethod == "HEAD"
    }

    private static func usesCompressedContentEncoding(_ response: HTTPURLResponse) -> Bool {
        guard let encoding = response.value(forHTTPHeaderField: "Content-Encoding")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else { return false }
        return !encoding.isEmpty && encoding != "identity"
    }

    private func diagnosticDetails(
        request: URLRequest,
        response: HTTPURLResponse?,
        data: Data?,
        error: Error?
    ) -> String {
        var sections = [
            "Request",
            "\(request.httpMethod ?? "GET") \(NetworkDiagnosticsStore.sanitizedAddress(for: request.url))",
            formattedHeaders(request.allHTTPHeaderFields ?? [:]),
        ]

        if let body = request.httpBody {
            sections += ["", "Request Body", NetworkDiagnosticsStore.sanitizedBody(body)]
        }

        if let error {
            let nsError = error as NSError
            sections += ["", "Error", "\(nsError.domain) (\(nsError.code))", error.localizedDescription]
        }

        if let response {
            sections += [
                "",
                "Response",
                "HTTP \(response.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode))",
                formattedHeaders(response.allHeaderFields.reduce(into: [String: String]()) { result, item in
                    result[String(describing: item.key)] = String(describing: item.value)
                })
            ]
        }

        if let data, !data.isEmpty {
            sections += ["", "Response Body", NetworkDiagnosticsStore.sanitizedBody(data)]
        }
        return sections.joined(separator: "\n")
    }

    private func formattedHeaders(_ headers: [String: String]) -> String {
        let sensitiveNames = Set(["authorization", "cookie", "set-cookie", "x-api-key"])
        return headers
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { name, value in
                sensitiveNames.contains(name.lowercased()) ? "\(name): [REDACTED]" : "\(name): \(value)"
            }
            .joined(separator: "\n")
    }

    private func decodePayload<Value: Decodable>(_ data: Data) throws -> Value {
        if let envelope = try? decoder.decode(APIEnvelope<Value>.self, from: data) {
            guard envelope.success, let responseValue = envelope.response else {
                throw APIError.rejected(
                    Self.localizedMessage(
                        code: envelope.extra?.messageCode,
                        params: envelope.extra?.messageParams ?? [:],
                        fallback: envelope.message ?? AppLanguage.localized("network.invalid_response")
                    )
                )
            }
            return responseValue
        }
        return try decoder.decode(Value.self, from: data)
    }

    private static func localizedMessage(
        code: String?,
        params: [String: APIMessageValue],
        fallback: String
    ) -> String {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else { return fallback }
        let key = "api.\(code.uppercased())"
        let localized = AppLanguage.localized(key)
        guard localized != key else { return fallback }
        return params.reduce(localized) { message, entry in
            message.replacingOccurrences(of: "{\(entry.key)}", with: entry.value.text)
        }
    }
}

struct EmptyResponse: Decodable {}

private extension Data {
    mutating func appendString(_ value: String) {
        if let data = value.data(using: .utf8) { append(data) }
    }
}
