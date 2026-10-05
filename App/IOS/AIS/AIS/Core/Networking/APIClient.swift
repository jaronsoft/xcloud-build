import Foundation

enum AISErrorClassifier {
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
            || (error as? URLError)?.code == .cancelled
    }
}

enum AISRequestResultGuard {
    static func ensureCurrent(isCancelled: Bool = Task.isCancelled) throws {
        if isCancelled {
            throw CancellationError()
        }
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case server(status: Int, message: String)
    case business(code: AISBusinessErrorCode, message: String, details: JSONValue?)
    case rejected(message: String)
    case missingData

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "network.invalid_response")
        case let .server(_, message), let .rejected(message),
             let .business(_, message, _):
            return message
        case .missingData:
            return String(localized: "network.missing_data")
        }
    }
}

enum AISBusinessErrorCode: String, Sendable {
    case priceChanged = "PRICE_CHANGED"
    case insufficientPoints = "INSUFFICIENT_POINTS"
    case quoteExpired = "QUOTE_EXPIRED"
    case contentRejected = "CONTENT_REJECTED"
    case capabilityDisabled = "CAPABILITY_DISABLED"
    case unknown = "UNKNOWN"

    init(serverValue: String?) {
        guard let serverValue else {
            self = .unknown
            return
        }
        self = AISBusinessErrorCode(rawValue: serverValue.uppercased())
            ?? .unknown
    }
}

struct APIClient: Sendable {
    private let environment: AppEnvironment
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        environment: AppEnvironment = .current,
        session: URLSession = .shared
    ) {
        self.environment = environment
        self.session = session
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds
            ]
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            let serverDate = DateFormatter()
            serverDate.locale = Locale(identifier: "en_US_POSIX")
            serverDate.calendar = Calendar(identifier: .gregorian)
            serverDate.timeZone = TimeZone(secondsFromGMT: 0)
            serverDate.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let serverDateWithFraction = DateFormatter()
            serverDateWithFraction.locale = Locale(identifier: "en_US_POSIX")
            serverDateWithFraction.calendar = Calendar(identifier: .gregorian)
            serverDateWithFraction.timeZone = TimeZone(secondsFromGMT: 0)
            serverDateWithFraction.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSS"
            guard let date = fractional.date(from: value)
                    ?? standard.date(from: value)
                    ?? serverDateWithFraction.date(from: value)
                    ?? serverDate.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "无法解析服务端日期"
                )
            }
            return date
        }
        encoder = JSONEncoder()
    }

    func get<Value: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        accessToken: String? = nil
    ) async throws -> Value {
        try await send(
            path,
            method: "GET",
            query: query,
            body: Optional<EmptyBody>.none,
            accessToken: accessToken
        )
    }

    func post<Body: Encodable, Value: Decodable>(
        _ path: String,
        body: Body,
        accessToken: String? = nil,
        headers: [String: String] = [:]
    ) async throws -> Value {
        try await send(
            path,
            method: "POST",
            query: [],
            body: body,
            accessToken: accessToken,
            headers: headers
        )
    }

    func patch<Body: Encodable, Value: Decodable>(
        _ path: String,
        body: Body,
        accessToken: String? = nil
    ) async throws -> Value {
        try await send(
            path,
            method: "PATCH",
            query: [],
            body: body,
            accessToken: accessToken
        )
    }

    func put<Body: Encodable, Value: Decodable>(
        _ path: String,
        body: Body,
        accessToken: String? = nil
    ) async throws -> Value {
        try await send(
            path,
            method: "PUT",
            query: [],
            body: body,
            accessToken: accessToken
        )
    }

    func delete<Value: Decodable>(
        _ path: String,
        accessToken: String? = nil
    ) async throws -> Value {
        try await send(
            path,
            method: "DELETE",
            query: [],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken
        )
    }

    func upload<Value: Decodable>(
        _ path: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        accessToken: String,
        fields: [String: String] = [:]
    ) async throws -> Value {
        await AppAPIRouter.shared.waitForInitialSelection()
        let boundary = "AIS-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.appendMultipart(
                "--\(boundary)\r\n"
                    + "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                    + "\(value)\r\n"
            )
        }
        body.appendMultipart("--\(boundary)\r\n")
        body.appendMultipart(
            "Content-Disposition: form-data; name=\"file\"; "
                + "filename=\"\(fileName)\"\r\n"
        )
        body.appendMultipart("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.appendMultipart("\r\n--\(boundary)--\r\n")

        var request = try makeRequest(
            path: path,
            method: "POST",
            query: [],
            accessToken: accessToken
        )
        request.timeoutInterval = 120
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        return try await decode(request)
    }

    func download(
        _ url: URL,
        accessToken: String? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if let accessToken, !accessToken.isEmpty {
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              !data.isEmpty else {
            throw APIError.invalidResponse
        }
        return data
    }

    func downloadFile(
        _ url: URL,
        accessToken: String? = nil
    ) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if let accessToken, !accessToken.isEmpty {
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        }
        let (temporaryURL, response) = try await session.download(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw APIError.invalidResponse
        }

        let responseExtension = response.suggestedFilename
            .flatMap { URL(fileURLWithPath: $0).pathExtension.nilIfEmpty }
        let sourceExtension = url.pathExtension.nilIfEmpty
        let suggestedExtension = [responseExtension, sourceExtension]
            .compactMap { $0 }
            .first { $0.lowercased() != "bin" }
            ?? Self.fileExtension(forMIMEType: response.mimeType)
            ?? responseExtension
            ?? sourceExtension
            ?? "bin"
        let destination = FileManager.default.temporaryDirectory
            .appending(
                path: "AIS-\(UUID().uuidString).\(suggestedExtension)"
            )
        do {
            try FileManager.default.moveItem(
                at: temporaryURL,
                to: destination
            )
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func fileExtension(forMIMEType mimeType: String?) -> String? {
        switch mimeType?.lowercased() {
        case "video/mp4": "mp4"
        case "video/quicktime": "mov"
        case "video/x-m4v": "m4v"
        case "image/jpeg": "jpg"
        case "image/png": "png"
        case "image/heic", "image/heif": "heic"
        default: nil
        }
    }

    private func send<Body: Encodable, Value: Decodable>(
        _ path: String,
        method: String,
        query: [URLQueryItem],
        body: Body?,
        accessToken: String?,
        headers: [String: String] = [:]
    ) async throws -> Value {
        if method == "POST" && (path == "/api/ais/images/jobs"
            || path == "/api/ais/images/edit/jobs"
            || path == "/api/ais/videos/jobs"
            || path == "/api/ais/agent/runs/confirm"
            || path == "/api/ais/prompts/optimize"
            || path == "/api/ais/prompts/optimize-video"
            || path == "/api/ais/analysis/jobs"
            || path == "/api/ais/assets/understand"
            || (path.hasPrefix("/api/ais/style-templates/") && path.hasSuffix("/generate"))) {
            if let status = await AISMaintenanceService.checkGeneration() {
                await MainActor.run {
                    NotificationCenter.default.post(name: .aisMaintenanceBlocked, object: status)
                }
                throw APIError.rejected(message: status.notice)
            }
        }
        if method != "GET" && method != "HEAD" {
            await AppAPIRouter.shared.waitForInitialSelection()
        }
        var request = try makeRequest(
            path: path,
            method: method,
            query: query,
            accessToken: accessToken
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body {
            request.httpBody = try encoder.encode(body)
        }

        return try await decode(request)
    }

    private func makeRequest(
        path: String,
        method: String,
        query: [URLQueryItem],
        accessToken: String?
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: environment.apiBaseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidResponse
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            AISLocalization.apiValue,
            forHTTPHeaderField: "Accept-Language"
        )
        request.setValue(
            AISLocalization.apiValue,
            forHTTPHeaderField: "X-AIS-Language"
        )
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        request.setValue(
            AISMediaRegionRequestContext.headerValue,
            forHTTPHeaderField: "X-AIS-Media-Region"
        )
        if let accessToken, !accessToken.isEmpty {
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        }
        return request
    }

    private func decode<Value: Decodable>(
        _ request: URLRequest
    ) async throws -> Value {
        let startedAt = Date.now
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Task.isCancelled || AISErrorClassifier.isCancellation(error) {
                throw CancellationError()
            }
            if let retry = await AppAPIRouter.shared.retryRequestIfNeeded(
                request,
                statusCode: nil,
                error: error
            ) {
                return try await decode(retry)
            }
            await NetworkDiagnosticsStore.shared.record(
                startedAt: startedAt,
                request: request,
                statusCode: nil,
                succeeded: false,
                message: error.localizedDescription
            )
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            await NetworkDiagnosticsStore.shared.record(
                startedAt: startedAt,
                request: request,
                statusCode: nil,
                succeeded: false,
                message: String(localized: "network.invalid_response")
            )
            throw APIError.invalidResponse
        }
        if let retry = await AppAPIRouter.shared.retryRequestIfNeeded(
            request,
            statusCode: httpResponse.statusCode,
            error: nil
        ) {
            return try await decode(retry)
        }
        if httpResponse.statusCode == 401,
           request.value(forHTTPHeaderField: "X-AIS-Auth-Retry") == nil,
           let authorization = request.value(
               forHTTPHeaderField: "Authorization"
           ),
           authorization.hasPrefix("Bearer ") {
            let rejectedToken = String(
                authorization.dropFirst("Bearer ".count)
            )
            if let refreshedToken = await AISCredentialRecovery.shared.recover(
                rejectedAccessToken: rejectedToken,
                baseURL: environment.apiBaseURL,
                urlSession: session
            ) {
                var retryRequest = request
                retryRequest.setValue(
                    "Bearer \(refreshedToken)",
                    forHTTPHeaderField: "Authorization"
                )
                retryRequest.setValue(
                    "1",
                    forHTTPHeaderField: "X-AIS-Auth-Retry"
                )
                return try await decode(retryRequest)
            }
        }

        let envelope: APIEnvelope<Value>
        do {
            envelope = try decoder.decode(APIEnvelope<Value>.self, from: data)
        } catch {
            await NetworkDiagnosticsStore.shared.record(
                startedAt: startedAt,
                request: request,
                statusCode: httpResponse.statusCode,
                succeeded: false,
                message: String(localized: "diagnostics.decode_failed")
            )
            throw APIError.server(
                status: httpResponse.statusCode,
                message: String(localized: "network.invalid_response")
            )
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let parsed = Self.businessError(from: envelope)
            let message = parsed.message
                ?? String(localized: "network.request_failed")
            await NetworkDiagnosticsStore.shared.record(
                startedAt: startedAt,
                request: request,
                statusCode: httpResponse.statusCode,
                succeeded: false,
                message: String(localized: "network.request_failed")
            )
            if parsed.code != .unknown {
                throw APIError.business(
                    code: parsed.code,
                    message: message,
                    details: parsed.details
                )
            }
            throw APIError.server(status: httpResponse.statusCode, message: message)
        }
        guard envelope.success else {
            let parsed = Self.businessError(from: envelope)
            let message = parsed.message
                ?? String(localized: "network.request_failed")
            await NetworkDiagnosticsStore.shared.record(
                startedAt: startedAt,
                request: request,
                statusCode: httpResponse.statusCode,
                succeeded: false,
                message: String(localized: "network.request_failed")
            )
            if parsed.code != .unknown {
                throw APIError.business(
                    code: parsed.code,
                    message: message,
                    details: parsed.details
                )
            }
            throw APIError.rejected(message: message)
        }
        guard let value = envelope.response else {
            await NetworkDiagnosticsStore.shared.record(
                startedAt: startedAt,
                request: request,
                statusCode: httpResponse.statusCode,
                succeeded: false,
                message: String(localized: "network.missing_data")
            )
            throw APIError.missingData
        }
        await NetworkDiagnosticsStore.shared.record(
            startedAt: startedAt,
            request: request,
            statusCode: httpResponse.statusCode,
            succeeded: true,
            message: String.localizedStringWithFormat(
                String(localized: "diagnostics.success"),
                Int64(data.count)
            )
        )
        await AppAPIRouter.shared.reportSuccess()
        return value
    }

    static func businessError<Value>(
        from envelope: APIEnvelope<Value>
    ) -> (
        code: AISBusinessErrorCode,
        message: String?,
        details: JSONValue?
    ) {
        let extraMessageCode = envelope.extra?.messageCode
        let messageCode = extraMessageCode ?? envelope.code
        let explicitCode = AISBusinessErrorCode(serverValue: messageCode)
        if explicitCode != .unknown {
            return (
                explicitCode,
                extraMessageCode == nil
                    ? envelope.message
                    : localizedMessage(
                        code: extraMessageCode,
                        params: envelope.extra?.messageParams ?? [:],
                        fallback: envelope.message
                    ),
                envelope.extra?.details ?? envelope.details
            )
        }
        guard let message = envelope.message,
              let separator = message.firstIndex(of: "|") else {
            return (
                .unknown,
                localizedMessage(
                    code: messageCode,
                    params: envelope.extra?.messageParams ?? [:],
                    fallback: envelope.message
                ),
                envelope.extra?.details ?? envelope.details
            )
        }
        let code = String(message[..<separator])
        let payload = String(message[message.index(after: separator)...])
        let businessCode = AISBusinessErrorCode(serverValue: code)
        let localizedMessage: String
        switch businessCode {
        case .priceChanged:
            localizedMessage = String(localized: "creation.price_changed")
        case .insufficientPoints:
            localizedMessage = String(localized: "creation.insufficient_points")
        case .quoteExpired:
            localizedMessage = String(localized: "creation.pricing_expired")
        case .contentRejected:
            localizedMessage = String(localized: "creation.content_rejected")
        default:
            localizedMessage = payload.isEmpty ? message : payload
        }
        let details = payload.data(using: .utf8).flatMap {
            try? JSONDecoder().decode(JSONValue.self, from: $0)
        }
        return (
            businessCode,
            localizedMessage,
            details ?? envelope.details
        )
    }

    private static func localizedMessage(
        code: String?,
        params: [String: JSONValue],
        fallback: String?
    ) -> String? {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else { return fallback }
        let key = "api.\(code.uppercased())"
        let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        guard localized != key else { return fallback }
        return params.reduce(localized) { message, entry in
            message.replacingOccurrences(
                of: "{\(entry.key)}",
                with: entry.value.messageParameterText
            )
        }
    }
}

private struct EmptyBody: Encodable {}

private extension Data {
    mutating func appendMultipart(_ value: String) {
        append(Data(value.utf8))
    }
}
