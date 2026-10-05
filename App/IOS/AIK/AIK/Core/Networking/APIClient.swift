import Foundation

struct APIRequestContext: Sendable {
    var accessToken: String?
    var tenantID: String?
    var inviteCode: String?
    var language: String

    static var anonymous: APIRequestContext {
        APIRequestContext(
            accessToken: nil,
            tenantID: nil,
            inviteCode: nil,
            language: Locale.current.language.languageCode?.identifier == "zh"
                ? "zh-CN"
                : "en"
        )
    }
}

struct APIClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = AppEnvironment.current.apiBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func get<Response: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        context: APIRequestContext = .anonymous,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let request = try makeRequest(
            path: path,
            method: "GET",
            queryItems: queryItems,
            context: context
        )
        return try await send(request, as: type)
    }

    func getOptional<Response: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        context: APIRequestContext = .anonymous,
        as type: Response.Type = Response.self
    ) async throws -> Response? {
        let request = try makeRequest(
            path: path,
            method: "GET",
            queryItems: queryItems,
            context: context
        )
        let data = try await rawData(for: request)
        do {
            let envelope = try JSONDecoder().decode(
                MessageEnvelope<Response>.self,
                from: data
            )
            guard envelope.success else {
                throw APIError.server(
                    envelope.msg ?? String(localized: "error.request_failed")
                )
            }
            return envelope.response
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    func getLegacyResponse<Response: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        context: APIRequestContext = .anonymous,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let request = try makeRequest(
            path: path,
            method: "GET",
            queryItems: queryItems,
            context: context
        )
        let data = try await rawData(for: request)
        do {
            let envelope = try JSONDecoder().decode(
                MessageEnvelope<Response>.self,
                from: data
            )
            guard let response = envelope.response else {
                throw APIError.server(
                    envelope.msg ?? String(localized: "error.request_failed")
                )
            }
            return response
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        context: APIRequestContext = .anonymous,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        var request = try makeRequest(
            path: path,
            method: "POST",
            context: context
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request, as: type)
    }

    func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        context: APIRequestContext
    ) throws -> URLRequest {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(normalizedPath),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(context.language, forHTTPHeaderField: "x-lang")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        request.setValue(AppEnvironment.releaseLabel, forHTTPHeaderField: "X-Client-Version")
        if let token = context.accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let tenantID = context.tenantID, !tenantID.isEmpty {
            request.setValue(tenantID, forHTTPHeaderField: "X-Knowledge-Tenant-Id")
            request.setValue(tenantID, forHTTPHeaderField: "x-tenantid")
        }
        if let inviteCode = context.inviteCode, !inviteCode.isEmpty {
            request.setValue(inviteCode, forHTTPHeaderField: "x-code")
        }
        return request
    }

    func rawData(for request: URLRequest) async throws -> Data {
        let startedAt = Date.now
        var responseStatus: Int?
        do {
            let (data, response) = try await session.data(for: request)
            responseStatus = (response as? HTTPURLResponse)?.statusCode
            try validate(response: response, data: data)
            Task { @MainActor in
                AIKDiagnosticsStore.shared.record(
                    startedAt: startedAt,
                    request: request,
                    statusCode: responseStatus,
                    message: "OK"
                )
            }
            return data
        } catch let error as APIError {
            Task { @MainActor in
                AIKDiagnosticsStore.shared.record(
                    startedAt: startedAt,
                    request: request,
                    statusCode: responseStatus,
                    message: error.localizedDescription
                )
            }
            throw error
        } catch {
            Task { @MainActor in
                AIKDiagnosticsStore.shared.record(
                    startedAt: startedAt,
                    request: request,
                    statusCode: nil,
                    message: error.localizedDescription
                )
            }
            throw APIError.network(error.localizedDescription)
        }
    }

    func bytes(for request: URLRequest) async throws -> (
        URLSession.AsyncBytes,
        URLResponse
    ) {
        let startedAt = Date.now
        var responseStatus: Int?
        do {
            let result = try await session.bytes(for: request)
            responseStatus = (result.1 as? HTTPURLResponse)?.statusCode
            try validate(response: result.1, data: nil)
            Task { @MainActor in
                AIKDiagnosticsStore.shared.record(
                    startedAt: startedAt,
                    request: request,
                    statusCode: responseStatus,
                    message: "SSE connected"
                )
            }
            return result
        } catch let error as APIError {
            Task { @MainActor in
                AIKDiagnosticsStore.shared.record(
                    startedAt: startedAt,
                    request: request,
                    statusCode: responseStatus,
                    message: error.localizedDescription
                )
            }
            throw error
        } catch {
            Task { @MainActor in
                AIKDiagnosticsStore.shared.record(
                    startedAt: startedAt,
                    request: request,
                    statusCode: nil,
                    message: error.localizedDescription
                )
            }
            throw APIError.network(error.localizedDescription)
        }
    }

    private func send<Response: Decodable>(
        _ request: URLRequest,
        as type: Response.Type
    ) async throws -> Response {
        let data = try await rawData(for: request)
        do {
            let envelope = try JSONDecoder().decode(
                MessageEnvelope<Response>.self,
                from: data
            )
            guard envelope.success else {
                throw APIError.server(
                    envelope.msg ?? String(localized: "error.request_failed")
                )
            }
            guard let response = envelope.response else {
                if Response.self == EmptyResponse.self {
                    return EmptyResponse() as! Response
                }
                throw APIError.invalidResponse
            }
            return response
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func validate(response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            if let data,
               let envelope = try? JSONDecoder().decode(
                   MessageEnvelope<EmptyResponse>.self,
                   from: data
               ),
               let message = envelope.msg {
                throw APIError.httpStatus(http.statusCode, message)
            }
            throw APIError.httpStatus(
                http.statusCode,
                String(
                    format: String(localized: "error.http_status"),
                    http.statusCode
                )
            )
        }
    }
}
