import Foundation

struct APIError: LocalizedError, Sendable {
    let message: String
    let code: String?
    let statusCode: Int
    let retryAfterSeconds: Int?

    var errorDescription: String? { message }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        encodeValue = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

actor APIClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let sessionStore: any SessionStoring
    private let developerLogs: DeveloperNetworkLogStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var refreshTask: Task<Void, Error>?

    init(
        baseURL: URL = AppConfiguration.apiBaseURL,
        urlSession: URLSession = .shared,
        sessionStore: any SessionStoring,
        developerLogs: DeveloperNetworkLogStore
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.sessionStore = sessionStore
        self.developerLogs = developerLogs
    }

    func sendEmailCode(email: String, purpose: String) async throws -> String {
        try await request(
            path: "v1/mosa/auth/email/code",
            method: "POST",
            body: ["Email": email, "Purpose": purpose]
        )
    }

    func register(email: String, code: String, password: String, displayName: String) async throws -> AuthResult {
        try await request(
            path: "v1/mosa/auth/email/register",
            method: "POST",
            body: ["Email": email, "Code": code, "Password": password, "DisplayName": displayName]
        )
    }

    func login(email: String, password: String) async throws -> AuthResult {
        try await request(
            path: "v1/mosa/auth/email/password-login",
            method: "POST",
            body: ["Email": email, "Password": password]
        )
    }

    func resetPassword(email: String, code: String, password: String) async throws -> String {
        try await request(
            path: "v1/mosa/auth/email/password-reset",
            method: "POST",
            body: ["Email": email, "Code": code, "Password": password]
        )
    }

    func logout() async {
        guard let session = sessionStore.load() else { return }
        let _: String? = try? await request(
            path: "v1/mosa/auth/logout",
            method: "POST",
            body: ["RefreshToken": session.refreshToken]
        )
        sessionStore.save(nil)
    }

    func deleteAccount(password: String) async throws -> String {
        guard let session = sessionStore.load() else {
            throw APIError(message: "Sign in before deleting your account.", code: nil, statusCode: 401, retryAfterSeconds: nil)
        }
        return try await request(
            path: "v1/mosa/auth/account",
            method: "DELETE",
            body: ["Password": password, "RefreshToken": session.refreshToken]
        )
    }

    func getProfile() async throws -> CloudProfile {
        try await request(path: "v1/mosa/profile")
    }

    func saveProfile(_ profile: LocalProfile) async throws -> CloudProfile {
        try await request(
            path: "v1/mosa/profile",
            method: "PUT",
            body: ProfileSaveBody(profile: profile)
        )
    }

    func getRecords(from: String, to: String) async throws -> [CloudRecord] {
        try await request(
            path: "v1/mosa/records",
            queryItems: [
                URLQueryItem(name: "from", value: from),
                URLQueryItem(name: "to", value: to),
                URLQueryItem(name: "includeDeleted", value: "true")
            ]
        )
    }

    func getRecord(date: String) async throws -> CloudRecord {
        try await request(path: "v1/mosa/records/\(date)")
    }

    func createInvitation(source: String = "PROFILE") async throws -> CloudInvitation {
        try await request(
            path: "v1/mosa/invitations",
            method: "POST",
            body: ["Source": source]
        )
    }

    func uploadPendingDiagnostics() async {
        guard sessionStore.load() != nil else { return }
        let events = await DiagnosticsReporter.shared.pendingBatch()
        guard !events.isEmpty else { return }
        do {
            let result: CloudDiagnosticBatch = try await request(
                path: "v1/mosa/diagnostics/batch",
                method: "POST",
                body: DiagnosticBatchBody(events: events),
                reportsFailure: false
            )
            await DiagnosticsReporter.shared.remove(
                eventIds: result.acceptedEventIds + result.duplicateEventIds
            )
        } catch {
            // 诊断上报失败不能影响用户业务；保留有界队列等待下次前台同步。
        }
    }

    func saveRecord(_ record: LocalRecord) async throws -> CloudRecord {
        var tags: [CloudTag] = try await request(path: "v1/mosa/tags")
        var tagIDs: [String] = []
        for name in record.tagNames {
            if let tag = tags.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                tagIDs.append(tag.id)
            } else {
                let created: CloudTag = try await request(
                    path: "v1/mosa/tags",
                    method: "POST",
                    body: TagSaveBody(name: name)
                )
                tags.append(created)
                tagIDs.append(created.id)
            }
        }
        do {
            return try await putRecord(record, tagIDs: tagIDs, version: record.serverVersion)
        } catch let error as APIError where error.code == "MOSA_RECORD_VERSION_CONFLICT" {
            let cloud = try await getRecord(date: record.recordDate)
            if cloud.hasSameContent(as: record) {
                return cloud
            }
            return try await putRecord(record, tagIDs: tagIDs, version: cloud.version)
        }
    }

    private func putRecord(
        _ record: LocalRecord,
        tagIDs: [String],
        version: Int?
    ) async throws -> CloudRecord {
        try await request(
            path: "v1/mosa/records/\(record.recordDate)",
            method: "PUT",
            body: RecordSaveBody(
                note: record.note,
                isIntentionalBlank: record.isIntentionalBlank,
                colorCodes: record.colorCodes,
                emotions: record.emotions ?? [],
                emotionIntensity: record.emotionIntensity,
                blankSource: record.blankSource,
                tagIDs: tagIDs,
                version: version
            )
        )
    }

    func deleteRecord(date: String) async throws -> CloudRecord {
        try await request(path: "v1/mosa/records/\(date)", method: "DELETE")
    }

    func restoreRecord(date: String) async throws -> CloudRecord {
        try await request(path: "v1/mosa/records/\(date)/restore", method: "POST")
    }

    func getLifeStages() async throws -> [CloudLifeStage] {
        try await request(path: "v1/mosa/life-stages")
    }

    func saveLifeStage(_ stage: LocalLifeStage) async throws -> CloudLifeStage {
        try await request(
            path: stage.serverVersion == nil ? "v1/mosa/life-stages" : "v1/mosa/life-stages/\(stage.id)",
            method: stage.serverVersion == nil ? "POST" : "PUT",
            body: LifeStageSaveBody(stage: stage)
        )
    }

    func deleteLifeStage(_ stage: LocalLifeStage) async throws -> CloudLifeStage {
        try await request(
            path: "v1/mosa/life-stages/\(stage.id)",
            method: "DELETE",
            queryItems: [URLQueryItem(name: "version", value: stage.serverVersion.map { String($0) })]
        )
    }

    func getGallery() async throws -> [CloudGalleryItem] {
        try await request(path: "v1/mosa/gallery")
    }

    func getArtworkGenerationPolicy() async throws -> ArtworkGenerationPolicy {
        try await request(path: "v1/mosa/gallery/generation-policy")
    }

    func saveAnnualTitle(_ work: LocalAnnualWork) async throws -> CloudGalleryItem {
        try await request(path: "v1/mosa/gallery/\(work.year)", method: "PUT", body: GalleryTitleBody(work: work))
    }

    func generateAnnualArtwork(
        year: Int,
        includeNotes: Bool,
        themeType: ArtworkTheme
    ) async throws -> CloudGalleryItem {
        let result: CloudShareCardResult = try await request(
            path: "v1/mosa/gallery/\(year)/share-card/generate",
            method: "POST",
            body: AnnualArtworkGenerateBody(
                includeNotes: includeNotes,
                themeType: themeType
            )
        )
        return result.artwork
    }

    func getAnnualArtworkImage(
        year: Int,
        onProgress: @escaping @MainActor @Sendable (ArtworkImageDownloadProgress) -> Void
    ) async throws -> Data {
        try await downloadAuthenticatedImage(
            path: "v1/mosa/gallery/\(year)/image",
            onProgress: onProgress
        )
    }

    func getShareCardImage(
        year: Int,
        onProgress: @escaping @MainActor @Sendable (ArtworkImageDownloadProgress) -> Void
    ) async throws -> Data {
        try await downloadAuthenticatedImage(
            path: "v1/mosa/gallery/\(year)/share-card/image",
            onProgress: onProgress
        )
    }

    private func downloadAuthenticatedImage(
        path: String,
        onProgress: @escaping @MainActor @Sendable (ArtworkImageDownloadProgress) -> Void,
        canRefresh: Bool = true
    ) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/\(path)"))
        request.timeoutInterval = 30
        if let token = sessionStore.load()?.token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "The image response is invalid.", code: "MOSA_IMAGE_RESPONSE_INVALID", statusCode: 0, retryAfterSeconds: nil)
        }
        if http.statusCode == 401, canRefresh {
            try await refreshSession()
            return try await downloadAuthenticatedImage(path: path, onProgress: onProgress, canRefresh: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(message: "The annual artwork image is unavailable.", code: "MOSA_ARTWORK_IMAGE_UNAVAILABLE", statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, retryAfterSeconds: nil)
        }
        let expectedBytes = http.expectedContentLength > 0 ? http.expectedContentLength : nil
        var receivedBytes: Int64 = 0
        var lastReportedBytes: Int64 = 0
        var data = Data()
        await onProgress(ArtworkImageDownloadProgress(receivedBytes: 0, expectedBytes: expectedBytes))
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            receivedBytes += 1
            if receivedBytes - lastReportedBytes >= 32 * 1024 {
                lastReportedBytes = receivedBytes
                await onProgress(ArtworkImageDownloadProgress(receivedBytes: receivedBytes, expectedBytes: expectedBytes))
            }
        }
        await onProgress(ArtworkImageDownloadProgress(receivedBytes: receivedBytes, expectedBytes: expectedBytes))
        return data
    }

    func importGuestData(profile: LocalProfile, records: [LocalRecord]) async throws -> GuestImportResult {
        let body = GuestImportBody(
            profile: ProfileSaveBody(profile: profile),
            records: records.filter { !$0.deleted }.map(GuestRecordBody.init)
        )
        return try await request(path: "v1/mosa/guest-imports", method: "POST", body: body)
    }

    func refreshSessionIfNeeded(maximumAge: TimeInterval = 24 * 60 * 60) async throws {
        guard let current = sessionStore.load() else {
            throw APIError(message: "Your session has expired.", code: nil, statusCode: 401, retryAfterSeconds: nil)
        }
        if let refreshedAt = current.refreshedAt,
           Date.now.timeIntervalSince(refreshedAt) < maximumAge {
            return
        }
        try await refreshSession()
    }

    private func request<Response: Decodable & Sendable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        canRefresh: Bool = true,
        reportsFailure: Bool = true
    ) async throws -> Response {
        let startedAt = Date.now
        let logPath = Self.developerLogURL(
            baseURL: baseURL,
            path: path,
            queryItems: queryItems
        )
        var components = URLComponents(url: baseURL.appendingPathComponent("api/\(path)"), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfiguration.defaultLocale, forHTTPHeaderField: "Accept-Language")
        if let token = sessionStore.load()?.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            do {
                request.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                await developerLogs.record(
                    startedAt: startedAt,
                    method: method,
                    path: logPath,
                    statusCode: nil,
                    succeeded: false,
                    message: "Request encoding failed: \(error.localizedDescription)"
                )
                if reportsFailure { await DiagnosticsReporter.shared.record(error: error, context: "Request encoding") }
                throw error
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            await developerLogs.record(
                startedAt: startedAt,
                method: method,
                path: logPath,
                statusCode: nil,
                succeeded: false,
                message: "Network error: \(error.localizedDescription)"
            )
            if reportsFailure, (error as? URLError)?.code != .notConnectedToInternet {
                await DiagnosticsReporter.shared.record(error: error, context: "Network request")
            }
            throw error
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope: APIEnvelope<Response>
        do {
            envelope = try decoder.decode(APIEnvelope<Response>.self, from: data)
        } catch {
            await developerLogs.record(
                startedAt: startedAt,
                method: method,
                path: logPath,
                statusCode: statusCode,
                succeeded: false,
                message: "Response decoding failed: \(error.localizedDescription)"
            )
            if reportsFailure { await DiagnosticsReporter.shared.record(error: error, context: "Response decoding") }
            throw error
        }
        if statusCode == 401, canRefresh, !path.hasPrefix("v1/mosa/auth/") {
            await developerLogs.record(
                startedAt: startedAt,
                method: method,
                path: logPath,
                statusCode: statusCode,
                succeeded: false,
                message: "Authentication expired; refreshing the session."
            )
            try await refreshSession()
            return try await self.request(
                path: path,
                method: method,
                queryItems: queryItems,
                body: body,
                canRefresh: false,
                reportsFailure: reportsFailure
            )
        }
        guard (200..<300).contains(statusCode), envelope.success, let value = envelope.response else {
            let apiError = APIError(
                message: envelope.msg.isEmpty ? "The request could not be completed." : envelope.msg,
                code: envelope.extra?.code,
                statusCode: statusCode,
                retryAfterSeconds: envelope.extra?.retryAfterSeconds
            )
            await developerLogs.record(
                startedAt: startedAt,
                method: method,
                path: logPath,
                statusCode: statusCode,
                succeeded: false,
                message: [apiError.code, apiError.message].compactMap { $0 }.joined(separator: " · ")
            )
            if reportsFailure, statusCode >= 500 {
                await DiagnosticsReporter.shared.record(error: apiError, context: "Server response \(statusCode)")
            }
            throw apiError
        }
        await developerLogs.record(
            startedAt: startedAt,
            method: method,
            path: logPath,
            statusCode: statusCode,
            succeeded: true,
            message: "Success · \(data.count) bytes"
        )
        return value
    }

    nonisolated static func developerLogURL(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem]
    ) -> String {
        let allowedNames = Set(["from", "to", "includeDeleted"])
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/\(path)"),
            resolvingAgainstBaseURL: false
        )
        let visible = queryItems.filter { allowedNames.contains($0.name) }
        if !visible.isEmpty { components?.queryItems = visible }
        return components?.url?.absoluteString
            ?? baseURL.appendingPathComponent("api/\(path)").absoluteString
    }

    private func refreshSession() async throws {
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task { try await performRefreshSession() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func performRefreshSession() async throws {
        guard let current = sessionStore.load() else {
            throw APIError(message: "Your session has expired.", code: nil, statusCode: 401, retryAfterSeconds: nil)
        }
        do {
            let token: CloudToken = try await request(
                path: "v1/mosa/auth/refresh",
                method: "POST",
                body: ["RefreshToken": current.refreshToken],
                canRefresh: false
            )
            sessionStore.save(AuthSession(
                token: token.token,
                refreshToken: token.refreshToken,
                email: current.email,
                refreshedAt: .now
            ))
        } catch let error as APIError where error.statusCode == 401 {
            sessionStore.save(nil)
            throw error
        }
    }
}

private struct RecordSaveBody: Encodable {
    let note: String
    let isIntentionalBlank: Bool
    let colorCodes: [String]
    let emotions: [LocalEmotion]
    let emotionIntensity: EmotionIntensity?
    let blankSource: String?
    let tagIDs: [String]
    let version: Int?

    enum CodingKeys: String, CodingKey {
        case note = "Note"
        case isIntentionalBlank = "IsIntentionalBlank"
        case colorCodes = "ColorCodes"
        case emotions = "Emotions"
        case emotionIntensity = "EmotionIntensity"
        case blankSource = "BlankSource"
        case tagIDs = "TagIds"
        case version = "Version"
    }
}

private struct DiagnosticBatchBody: Encodable {
    let events: [ClientDiagnosticEvent]

    enum CodingKeys: String, CodingKey {
        case events = "Events"
    }
}

private struct TagSaveBody: Encodable {
    let name: String
    let isActive = true

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case isActive = "IsActive"
    }
}

private struct ProfileSaveBody: Encodable {
    let displayName: String
    let locale: String
    let timezone: String
    let startYear: Int

    init(profile: LocalProfile) {
        displayName = profile.displayName
        locale = profile.locale
        timezone = profile.timezone
        startYear = profile.startYear
    }

    enum CodingKeys: String, CodingKey {
        case displayName = "DisplayName"
        case locale = "Locale"
        case timezone = "Timezone"
        case startYear = "StartYear"
    }
}

private struct LifeStageSaveBody: Encodable {
    let name: String
    let startMonth: String
    let endMonth: String
    let colorCode: String
    let colorCodes: [String]
    let presetCode: String?
    let version: Int?

    init(stage: LocalLifeStage) {
        name = stage.name
        startMonth = stage.startMonth
        endMonth = stage.endMonth
        colorCode = stage.colorCode
        colorCodes = stage.resolvedColorCodes
        presetCode = stage.presetCode
        version = stage.serverVersion
    }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case startMonth = "StartMonth"
        case endMonth = "EndMonth"
        case colorCode = "ColorCode"
        case colorCodes = "ColorCodes"
        case presetCode = "PresetCode"
        case version = "Version"
    }
}

private struct AnnualArtworkGenerateBody: Encodable {
    let includeNotes: Bool
    let themeType: ArtworkTheme
    enum CodingKeys: String, CodingKey {
        case includeNotes = "IncludeNotes"
        case themeType = "ThemeType"
    }
}

private struct GalleryTitleBody: Encodable {
    let title: String
    let version: Int?

    init(work: LocalAnnualWork) {
        title = work.title
        version = work.serverVersion
    }

    enum CodingKeys: String, CodingKey {
        case title = "Title"
        case version = "Version"
    }
}

private struct GuestRecordBody: Encodable {
    let recordDate: String
    let note: String
    let isIntentionalBlank: Bool
    let colorCodes: [String]
    let tagIDs: [String] = []
    let tagNames: [String]

    init(_ record: LocalRecord) {
        recordDate = record.recordDate
        note = record.note
        isIntentionalBlank = record.isIntentionalBlank
        colorCodes = record.colorCodes
        tagNames = record.tagNames
    }

    enum CodingKeys: String, CodingKey {
        case recordDate = "RecordDate"
        case note = "Note"
        case isIntentionalBlank = "IsIntentionalBlank"
        case colorCodes = "ColorCodes"
        case tagIDs = "TagIds"
        case tagNames = "TagNames"
    }
}

private struct GuestImportBody: Encodable {
    let profile: ProfileSaveBody
    let records: [GuestRecordBody]

    enum CodingKeys: String, CodingKey {
        case profile = "Profile"
        case records = "Records"
    }
}
