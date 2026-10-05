import Foundation

struct AISMemorySourceSummary: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let sourceType: String?
    let sourceScene: String?
    let sourceOccurredAt: Date?
    let sourceText: String?
    let extractReason: String?
    let title: String?
    let description: String?
    let keywords: [String]
    let resultURL: URL?
    let mediaType: String?
    let createTime: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case sourceType = "SourceType"
        case sourceScene = "SourceScene"
        case sourceOccurredAt = "SourceOccurredAt"
        case sourceText = "SourceText"
        case extractReason = "ExtractReason"
        case title = "Title"
        case description = "Description"
        case keywords = "Keywords"
        case resultURL = "ResultUrl"
        case mediaType = "MediaType"
        case createTime = "CreateTime"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        sourceScene = try container.decodeIfPresent(String.self, forKey: .sourceScene)
        sourceOccurredAt = try container.decodeIfPresent(Date.self, forKey: .sourceOccurredAt)
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText)
        extractReason = try container.decodeIfPresent(String.self, forKey: .extractReason)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        resultURL = try container.decodeIfPresent(URL.self, forKey: .resultURL)
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        createTime = try container.decodeIfPresent(Date.self, forKey: .createTime)
    }
}

struct AISMemoryItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let projectId: String?
    let scope: String
    let memoryType: String
    let category: String
    let brandKey: String?
    let productKey: String?
    let preferenceKey: String?
    let preferenceValueJson: String?
    let content: String
    let status: String
    let source: String?
    let confidence: Decimal?
    let weight: Int
    let lastAppliedAt: Date?
    let applyCount: Int
    let expireAt: Date?
    let evidenceCount: Int
    let rowVersion: Int64
    let createTime: Date?
    let modifyTime: Date?
    let supersedesMemoryId: String?
    let sourceCount: Int
    let sourceSummary: [AISMemorySourceSummary]

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case projectId = "ProjectId"
        case scope = "Scope"
        case memoryType = "MemoryType"
        case category = "Category"
        case brandKey = "BrandKey"
        case productKey = "ProductKey"
        case preferenceKey = "PreferenceKey"
        case preferenceValueJson = "PreferenceValueJson"
        case content = "Content"
        case status = "Status"
        case source = "Source"
        case confidence = "Confidence"
        case weight = "Weight"
        case lastAppliedAt = "LastAppliedAt"
        case applyCount = "ApplyCount"
        case expireAt = "ExpireAt"
        case evidenceCount = "EvidenceCount"
        case rowVersion = "RowVersion"
        case createTime = "CreateTime"
        case modifyTime = "ModifyTime"
        case supersedesMemoryId = "SupersedesMemoryId"
        case sourceCount = "SourceCount"
        case sourceSummary = "SourceSummary"
    }
}

extension AISMemoryItem {
    var statusLocalizationKey: String {
        switch status {
        case "confirmed": "memory.status.confirmed"
        case "proposed": "memory.status.proposed"
        case "disabled": "memory.status.disabled"
        case "rejected": "memory.status.rejected"
        default: "memory.status.unknown"
        }
    }

    var scopeLocalizationKey: String {
        switch scope {
        case "project": "memory.scope.project"
        case "brand": "memory.scope.brand"
        case "product": "memory.scope.product"
        default: "memory.scope.personal"
        }
    }

    var categoryLocalizationKey: String {
        "memory.category.\(category)"
    }

    var priorityLocalizationKey: String {
        if weight >= 80 { return "memory.priority.essential" }
        if weight >= 60 { return "memory.priority.strong" }
        if weight >= 40 { return "memory.priority.preferred" }
        return "memory.priority.normal"
    }
}

struct AISMemoryExtractionBatch: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let status: String
    let totalCount: Int
    let processedCount: Int
    let candidateCount: Int
    let confirmedMatchCount: Int
    let errorSummary: String?
    let startedAt: Date?
    let finishedAt: Date?
    let createTime: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case status = "Status"
        case totalCount = "TotalCount"
        case processedCount = "ProcessedCount"
        case candidateCount = "CandidateCount"
        case confirmedMatchCount = "ConfirmedMatchCount"
        case errorSummary = "ErrorSummary"
        case startedAt = "StartedAt"
        case finishedAt = "FinishedAt"
        case createTime = "CreateTime"
    }

    var isRunning: Bool {
        status == "queued" || status == "running"
    }
}

struct AISMemoryDraft: Sendable {
    var content = ""
    var scope = "personal"
    var memoryType = "personal_preference"
    var category = "general"
    var brandKey = ""
    var productKey = ""
    var preferenceKey = ""
    var preferenceValueJson = ""
    var weight = 50
    var projectId: String?
    var rowVersion: Int64?
}

struct AISMemoryWriteRequest: Encodable {
    let content: String
    let editMode: String
    let scope: String
    let projectId: String?
    let brandKey: String?
    let productKey: String?
    let category: String
    let memoryType: String
    let preferenceKey: String?
    let preferenceValueJson: String?
    let weight: Int
    let rowVersion: Int64?
    let status = "confirmed"
    let source = "user_manual"
    let confirm = true

    private enum CodingKeys: String, CodingKey {
        case content = "Content"
        case editMode = "EditMode"
        case scope = "Scope"
        case projectId = "ProjectId"
        case brandKey = "BrandKey"
        case productKey = "ProductKey"
        case category = "Category"
        case memoryType = "MemoryType"
        case preferenceKey = "PreferenceKey"
        case preferenceValueJson = "PreferenceValueJson"
        case weight = "Weight"
        case rowVersion = "RowVersion"
        case status = "Status"
        case source = "Source"
        case confirm = "Confirm"
    }
}

struct AISMemoryBulkRequest: Encodable {
    let ids: [String]
    let reason: String?

    private enum CodingKeys: String, CodingKey {
        case ids = "Ids"
        case reason = "Reason"
    }
}

struct AISMemoryExtractionRequest: Encodable {
    let days: Int
    let maxTasks: Int

    private enum CodingKeys: String, CodingKey {
        case days = "Days"
        case maxTasks = "MaxTasks"
    }
}

struct AISMemoryDetail: Decodable, Sendable {
    let memory: AISMemoryItem
    let sources: [AISMemorySourceSummary]

    private enum CodingKeys: String, CodingKey {
        case memory = "Memory"
        case sources = "Sources"
    }
}

struct AISMemoryExtractionDetail: Decodable, Sendable {
    let batch: AISMemoryExtractionBatch
    let candidates: [AISMemoryItem]

    private enum CodingKeys: String, CodingKey {
        case batch = "Batch"
        case candidates = "Candidates"
    }
}

struct AISMemoryEmptyRequest: Encodable {}

struct AISMemoryContextSnapshot: Decodable, Sendable {
    let schemaVersion: String?
    let scene: String?
    let applied: [AISMemoryContextSnapshotItem]
    let overridden: [AISMemoryContextSnapshotItem]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "SchemaVersion"
        case scene = "Scene"
        case applied = "Applied"
        case overridden = "Overridden"
    }
}

struct AISMemoryContextSnapshotItem: Decodable, Identifiable, Sendable {
    let id: String
    let content: String?
    let preferenceKey: String?
    let decisionReason: String?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case content = "Content"
        case preferenceKey = "PreferenceKey"
        case decisionReason = "DecisionReason"
    }
}
