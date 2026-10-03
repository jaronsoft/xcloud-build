import Foundation

enum SyncState: String, Codable, Sendable {
    case localOnly = "LOCAL_ONLY"
    case syncing = "SYNCING"
    case syncFailed = "SYNC_FAILED"
    case synced = "SYNCED"
}

enum EmotionCode: String, Codable, CaseIterable, Sendable {
    case joy = "JOY", excitement = "EXCITEMENT", anger = "ANGER", sadness = "SADNESS"
    case fear = "FEAR", calm = "CALM", love = "LOVE", disgust = "DISGUST"
}

enum EmotionRole: String, Codable, Sendable { case primary = "PRIMARY", secondary = "SECONDARY" }
enum EmotionIntensity: String, Codable, CaseIterable, Sendable { case mild = "MILD", clear = "CLEAR", strong = "STRONG" }

struct ArtworkImageDownloadProgress: Equatable, Sendable {
    let receivedBytes: Int64
    let expectedBytes: Int64?

    var fractionCompleted: Double? {
        guard let expectedBytes, expectedBytes > 0 else { return nil }
        return min(1, max(0, Double(receivedBytes) / Double(expectedBytes)))
    }
}

enum ArtworkImageShareFile {
    // 分享文件只包含重新编码后的 PNG 像素，不附加标题、链接或用户数据。
    static func write(pngData: Data, year: Int, directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        guard !pngData.isEmpty else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let fileURL = directory
            .appendingPathComponent("MOSA-Share-Card-\(year)-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try pngData.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

enum ArtworkTheme: String, Codable, CaseIterable, Sendable {
    case mountain = "Mountain"
    case forest = "Forest"
    case ocean = "Ocean"
    case lake = "Lake"
    case desert = "Desert"
    case abstractPortrait = "AbstractPortrait"

    var title: String {
        self == .abstractPortrait ? "Abstract" : rawValue
    }

    var detail: String {
        switch self {
        case .mountain: return "Valleys, rivers and distant peaks"
        case .forest: return "Ancient trees, creek and soft mist"
        case .ocean: return "Open sea, cliffs and horizon"
        case .lake: return "Still water, reflections and quiet space"
        case .desert: return "Dunes, stone and long natural shadows"
        case .abstractPortrait: return "A natural abstract composition, without people"
        }
    }
}

struct LocalEmotion: Codable, Equatable, Hashable, Sendable {
    var emotionCode: EmotionCode
    var role: EmotionRole
    var colorCode: String
    var paletteVersion = "1.0"

    enum CodingKeys: String, CodingKey {
        case emotionCode = "EmotionCode"
        case role = "Role"
        case colorCode = "ColorCode"
        case paletteVersion = "PaletteVersion"
    }
}

struct LocalProfile: Codable, Equatable, Sendable {
    var displayName: String
    var locale: String
    var timezone: String
    var startYear: Int
    var initializedAt: Date
}

struct LocalRecord: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var recordDate: String
    var note: String
    var isIntentionalBlank: Bool
    var colorCodes: [String]
    var emotions: [LocalEmotion]? = nil
    var emotionIntensity: EmotionIntensity? = nil
    var blankSource: String? = nil
    var hasLegacyUnmappedColors: Bool? = nil
    var tagNames: [String]
    var version: Int
    var serverVersion: Int?
    var syncState: SyncState
    var deleted: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct LocalLifeStage: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var name: String
    var startMonth: String
    var endMonth: String
    var colorCode: String
    var colorCodes: [String]? = nil
    var presetCode: String? = nil
    var version: Int
    var serverVersion: Int?
    var syncState: SyncState
    var deleted: Bool
    var createdAt: Date
    var updatedAt: Date
}

extension LocalLifeStage {
    var resolvedColorCodes: [String] {
        let values = (colorCodes?.isEmpty == false ? colorCodes! : [colorCode])
        return Array(values.prefix(3))
    }

    var displayTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(startMonth) — \(endMonth)" : trimmed
    }
}

struct LocalAnnualWork: Codable, Identifiable, Equatable, Sendable {
    var year: Int
    var cloudID: String?
    var title: String
    var version: Int
    var serverVersion: Int?
    var syncState: SyncState
    var updatedAt: Date
    var generationStatus: String? = "NOT_GENERATED"
    var taskID: String? = nil
    var imageURL: String? = nil
    var includeNotes: Bool? = nil
    var inputHash: String? = nil
    var worldDnaVersion: String? = nil
    var errorCode: String? = nil
    var themeType: ArtworkTheme? = nil
    var promptFingerprint: String? = nil
    var isYearToDate: Bool? = nil
    var periodEnd: String? = nil
    var workflowID: String? = nil
    var workflowStatus: String? = "NOT_STARTED"
    var currentStage: String? = nil
    var failedStage: String? = nil
    var retryable: Bool? = nil
    var shareCardAvailable: Bool? = nil
    var shareCardURL: String? = nil
    var id: Int { year }
}

struct ArtworkGenerationPolicy: Codable, Equatable, Sendable {
    let enabled: Bool
    let monthlyLimit: Int
    let used: Int
    let remaining: Int?
    let quotaMonth: String
    let nextResetAt: String?
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case enabled = "Enabled"
        case monthlyLimit = "MonthlyLimit"
        case used = "Used"
        case remaining = "Remaining"
        case quotaMonth = "QuotaMonth"
        case nextResetAt = "NextResetAt"
        case timezone = "Timezone"
    }

    var quotaReached: Bool {
        enabled && (remaining ?? 0) <= 0
    }
}

struct AuthSession: Codable, Equatable, Sendable {
    var token: String
    var refreshToken: String
    var email: String
    var refreshedAt: Date?
}

struct APIExtra: Decodable, Sendable {
    let code: String?
    let retryAfterSeconds: Int?
}

struct APIEnvelope<Response: Decodable & Sendable>: Decodable, Sendable {
    let success: Bool
    let msg: String
    let response: Response?
    let extra: APIExtra?
}

struct CloudToken: Codable, Sendable {
    let token: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case token
        case refreshToken = "RefreshToken"
    }
}

struct CloudProfile: Codable, Sendable {
    let id: String
    let email: String
    let displayName: String
    let locale: String
    let timezone: String
    let startYear: Int

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case email = "Email"
        case displayName = "DisplayName"
        case locale = "Locale"
        case timezone = "Timezone"
        case startYear = "StartYear"
    }

    var localValue: LocalProfile {
        LocalProfile(
            displayName: displayName,
            locale: locale.isEmpty ? "en" : locale,
            timezone: timezone.isEmpty ? TimeZone.current.identifier : timezone,
            startYear: startYear,
            initializedAt: .now
        )
    }
}

struct AuthResult: Codable, Sendable {
    let profile: CloudProfile
    let token: CloudToken

    enum CodingKeys: String, CodingKey {
        case profile = "Profile"
        case token = "Token"
    }
}

struct CloudInvitation: Codable, Sendable {
    let id: String
    let expiresAt: Date
    let invitePath: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case expiresAt = "ExpiresAt"
        case invitePath = "InvitePath"
    }
}

struct CloudDiagnosticBatch: Codable, Sendable {
    let acceptedCount: Int
    let duplicateCount: Int
    let acceptedEventIds: [String]
    let duplicateEventIds: [String]

    enum CodingKeys: String, CodingKey {
        case acceptedCount = "AcceptedCount"
        case duplicateCount = "DuplicateCount"
        case acceptedEventIds = "AcceptedEventIds"
        case duplicateEventIds = "DuplicateEventIds"
    }
}

struct CloudTag: Codable, Hashable, Sendable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

struct CloudRecord: Codable, Sendable {
    let id: String
    let recordDate: String
    let note: String
    let isIntentionalBlank: Bool
    let version: Int
    let isDeleted: Bool
    let colorCodes: [String]
    let emotions: [LocalEmotion]?
    let emotionIntensity: EmotionIntensity?
    let blankSource: String?
    let hasLegacyUnmappedColors: Bool?
    let tags: [CloudTag]
    let createTime: String
    let modifyTime: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case recordDate = "RecordDate"
        case note = "Note"
        case isIntentionalBlank = "IsIntentionalBlank"
        case version = "Version"
        case isDeleted = "IsDeleted"
        case colorCodes = "ColorCodes"
        case emotions = "Emotions"
        case emotionIntensity = "EmotionIntensity"
        case blankSource = "BlankSource"
        case hasLegacyUnmappedColors = "HasLegacyUnmappedColors"
        case tags = "Tags"
        case createTime = "CreateTime"
        case modifyTime = "ModifyTime"
    }

    func localValue(existingID: String? = nil) -> LocalRecord {
        let created = ISO8601DateFormatter().date(from: createTime) ?? .now
        let modified = modifyTime.flatMap { ISO8601DateFormatter().date(from: $0) } ?? created
        return LocalRecord(
            id: existingID ?? id,
            recordDate: String(recordDate.prefix(10)),
            note: note,
            isIntentionalBlank: isIntentionalBlank,
            colorCodes: colorCodes,
            emotions: emotions ?? [],
            emotionIntensity: emotionIntensity,
            blankSource: blankSource,
            hasLegacyUnmappedColors: hasLegacyUnmappedColors ?? false,
            tagNames: tags.map(\.name),
            version: version,
            serverVersion: version,
            syncState: .synced,
            deleted: isDeleted,
            createdAt: created,
            updatedAt: modified
        )
    }

    func hasSameContent(as local: LocalRecord) -> Bool {
        let cloudColors = colorCodes.map { $0.uppercased() }
        let localColors = local.colorCodes.map { $0.uppercased() }
        let cloudTags = Set(tags.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let localTags = Set(local.tagNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let blankSourceMatches = isIntentionalBlank
            || blankSource == local.blankSource

        return !isDeleted
            && note == local.note
            && isIntentionalBlank == local.isIntentionalBlank
            && cloudColors == localColors
            && (emotions ?? []) == (local.emotions ?? [])
            && emotionIntensity == local.emotionIntensity
            && blankSourceMatches
            && cloudTags == localTags
    }
}

struct CloudLifeStage: Codable, Sendable {
    let id: String
    let name: String
    let startMonth: String
    let endMonth: String
    let colorCode: String
    let colorCodes: [String]?
    let presetCode: String?
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case startMonth = "StartMonth"
        case endMonth = "EndMonth"
        case colorCode = "ColorCode"
        case colorCodes = "ColorCodes"
        case presetCode = "PresetCode"
        case version = "Version"
    }

    var localValue: LocalLifeStage {
        LocalLifeStage(id: id, name: name, startMonth: startMonth, endMonth: endMonth, colorCode: colorCode, colorCodes: colorCodes?.isEmpty == false ? colorCodes : [colorCode], presetCode: presetCode, version: version, serverVersion: version, syncState: .synced, deleted: false, createdAt: .now, updatedAt: .now)
    }
}

struct CloudGalleryItem: Codable, Sendable {
    let id: String?
    let year: Int
    let title: String
    let version: Int
    let generationStatus: String?
    let taskID: String?
    let imageURL: String?
    let includeNotes: Bool?
    let inputHash: String?
    let worldDnaVersion: String?
    let errorCode: String?
    let themeType: ArtworkTheme?
    let promptFingerprint: String?
    let isYearToDate: Bool?
    let periodEnd: String?
    let workflowID: String?
    let workflowStatus: String?
    let currentStage: String?
    let failedStage: String?
    let retryable: Bool?
    let shareCardAvailable: Bool?
    let shareCardURL: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case year = "Year"
        case title = "Title"
        case version = "Version"
        case generationStatus = "GenerationStatus"
        case taskID = "TaskId"
        case imageURL = "ImageUrl"
        case includeNotes = "IncludeNotes"
        case inputHash = "InputHash"
        case worldDnaVersion = "WorldDnaVersion"
        case errorCode = "ErrorCode"
        case themeType = "ThemeType"
        case promptFingerprint = "PromptFingerprint"
        case isYearToDate = "IsYearToDate"
        case periodEnd = "PeriodEnd"
        case workflowID = "WorkflowId"
        case workflowStatus = "WorkflowStatus"
        case currentStage = "CurrentStage"
        case failedStage = "FailedStage"
        case retryable = "Retryable"
        case shareCardAvailable = "ShareCardAvailable"
        case shareCardURL = "ShareCardUrl"
    }

    var localValue: LocalAnnualWork {
        LocalAnnualWork(
            year: year,
            cloudID: id,
            title: title,
            version: version,
            serverVersion: version,
            syncState: .synced,
            updatedAt: .now,
            generationStatus: generationStatus ?? "NOT_GENERATED",
            taskID: taskID,
            imageURL: imageURL,
            includeNotes: includeNotes,
            inputHash: inputHash,
            worldDnaVersion: worldDnaVersion,
            errorCode: errorCode,
            themeType: themeType,
            promptFingerprint: promptFingerprint,
            isYearToDate: isYearToDate,
            periodEnd: periodEnd,
            workflowID: workflowID,
            workflowStatus: workflowStatus ?? "NOT_STARTED",
            currentStage: currentStage,
            failedStage: failedStage,
            retryable: retryable,
            shareCardAvailable: shareCardAvailable,
            shareCardURL: shareCardURL
        )
    }
}

struct CloudShareCardResult: Codable, Sendable {
    let artwork: CloudGalleryItem

    enum CodingKeys: String, CodingKey {
        case artwork = "Artwork"
    }
}

enum CanvasColorSource: String, Equatable, Sendable {
    case none = "NONE"
    case stage = "STAGE"
    case daily = "DAILY"
}

struct CanvasColorResolution: Equatable, Sendable {
    let colorCodes: [String]
    let source: CanvasColorSource
}

enum PortraitYearPagination {
    static func visibleYears(_ years: [Int], count: Int) -> [Int] {
        Array(years.prefix(max(0, count)))
    }
}

struct LifeStageRangeOverride {
    let stages: [LocalLifeStage]
    let touchedIDs: Set<String>
}

enum LifeStageRangeResolver {
    static func override(
        stages: [LocalLifeStage],
        with incoming: LocalLifeStage,
        now: Date,
        syncState: SyncState,
        createID: () -> String = { UUID().uuidString }
    ) -> LifeStageRangeOverride {
        var values: [LocalLifeStage] = []
        var touchedIDs = Set([incoming.id])

        for stage in stages {
            guard !stage.deleted,
                  stage.id != incoming.id,
                  stage.startMonth <= incoming.endMonth,
                  stage.endMonth >= incoming.startMonth else {
                values.append(stage)
                continue
            }

            touchedIDs.insert(stage.id)
            let hasLeft = stage.startMonth < incoming.startMonth
            let hasRight = stage.endMonth > incoming.endMonth

            if hasLeft {
                var left = stage
                left.endMonth = shiftMonth(incoming.startMonth, by: -1)
                left.version += 1
                left.syncState = syncState
                left.updatedAt = now
                values.append(left)
            }
            if hasRight {
                var right = stage
                if hasLeft {
                    right.id = createID()
                    right.version = 1
                    right.serverVersion = nil
                    right.createdAt = now
                    touchedIDs.insert(right.id)
                } else {
                    right.version += 1
                }
                right.startMonth = shiftMonth(incoming.endMonth, by: 1)
                right.syncState = syncState
                right.updatedAt = now
                values.append(right)
            }
        }

        values.append(incoming)
        return LifeStageRangeOverride(
            stages: values.sorted { $0.startMonth < $1.startMonth },
            touchedIDs: touchedIDs
        )
    }

    private static func shiftMonth(_ value: String, by offset: Int) -> String {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return value }
        let index = parts[0] * 12 + parts[1] - 1 + offset
        return String(format: "%04d-%02d", index / 12, index % 12 + 1)
    }
}

enum CanvasResolver {
    static func resolve(
        date: String,
        record: LocalRecord?,
        stages: [LocalLifeStage],
        includeStageBackgrounds: Bool = false
    ) -> CanvasColorResolution {
        if date > DateSupport.key(.now) || record?.isIntentionalBlank == true {
            return CanvasColorResolution(colorCodes: [], source: .none)
        }
        if let record, !record.colorCodes.isEmpty {
            return CanvasColorResolution(colorCodes: Array(record.colorCodes.prefix(3)), source: .daily)
        }
        let month = String(date.prefix(7))
        if includeStageBackgrounds,
           let stage = stages.first(where: { !$0.deleted && $0.startMonth <= month && $0.endMonth >= month }) {
            return CanvasColorResolution(colorCodes: stage.resolvedColorCodes, source: .stage)
        }
        return CanvasColorResolution(colorCodes: [], source: .none)
    }

    static func colors(
        date: String,
        record: LocalRecord?,
        stages: [LocalLifeStage],
        includeStageBackgrounds: Bool = false
    ) -> [String] {
        resolve(
            date: date,
            record: record,
            stages: stages,
            includeStageBackgrounds: includeStageBackgrounds
        ).colorCodes
    }
}

enum GalleryResolver {
    static func years(records: [LocalRecord], stages: [LocalLifeStage], startYear: Int, currentYear: Int) -> [Int] {
        var values: Set<Int> = []
        records.filter { !$0.deleted }.forEach {
            if let year = Int($0.recordDate.prefix(4)) { values.insert(year) }
        }
        return values.filter { $0 >= startYear && $0 <= currentYear }.sorted(by: >)
    }
}

struct GuestImportResult: Codable, Sendable {
    let importedCount: Int
    let conflictCount: Int
    let conflictDates: [String]

    enum CodingKeys: String, CodingKey {
        case importedCount = "ImportedCount"
        case conflictCount = "ConflictCount"
        case conflictDates = "ConflictDates"
    }
}

struct EmptyResponse: Decodable, Sendable {}

enum RecordStatus {
    case empty
    case recorded
    case intentionalBlank
}
