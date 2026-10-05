import Foundation

struct AISProjectListItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let status: String
    let runCount: Int
    let deliverableCount: Int
    let previewUrls: [String]
    let memoryCount: Int
    let latestRunStatus: String?
    let latestRunAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case description = "Description"
        case status = "Status"
        case runCount = "RunCount"
        case deliverableCount = "DeliverableCount"
        case previewUrls = "PreviewUrls"
        case memoryCount = "MemoryCount"
        case latestRunStatus = "LatestRunStatus"
        case latestRunAt = "LatestRunAt"
    }
}

struct AISProjectInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let status: String
    let referenceAssetIds: String?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case description = "Description"
        case status = "Status"
        case referenceAssetIds = "ReferenceAssetIds"
    }
}

struct AISProjectMessage: Codable, Identifiable, Hashable {
    let id: String
    let role: String
    let content: String
    let createTime: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case role = "Role"
        case content = "Content"
        case createTime = "CreateTime"
    }
}

struct AISProjectMemory: Codable, Identifiable, Hashable {
    let id: String
    let content: String
    let status: String
    let memoryType: String

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case content = "Content"
        case status = "Status"
        case memoryType = "MemoryType"
    }
}

struct AISProjectRun: Codable, Identifiable, Hashable {
    let id: String
    let status: String
    let generationPoints: Int?
    let serviceFeePoints: Int?
    let quoteExpiresAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case status = "Status"
        case generationPoints = "GenerationPoints"
        case serviceFeePoints = "ServiceFeePoints"
        case quoteExpiresAt = "QuoteExpiresAt"
    }
}

struct AISProjectAsset: Codable, Identifiable, Hashable {
    let id: String
    let fileUrl: String?
    let title: String?
    let originalFileName: String?
    let mimeType: String?
    let fileSize: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case fileUrl = "FileUrl"
        case title = "Title"
        case originalFileName = "OriginalFileName"
        case mimeType = "MimeType"
        case fileSize = "FileSize"
    }

    var resolvedURL: URL? {
        guard let fileUrl else { return nil }
        if let url = URL(string: fileUrl), url.scheme != nil {
            return url
        }
        return URL(
            string: fileUrl,
            relativeTo: AppEnvironment.current.apiBaseURL
        )?.absoluteURL
    }
}

struct AISProjectDetail: Codable {
    let project: AISProjectInfo
    let messages: [AISProjectMessage]
    let memories: [AISProjectMemory]
    let runs: [AISProjectRun]
    let referenceAssets: [AISProjectAsset]
}

struct AISSkillSummary: Codable, Identifiable, Hashable {
    let id: String
    let nameZh: String
    let nameEn: String?
    let descriptionZh: String?
    let descriptionEn: String?
    let category: String?
    let isOfficial: Bool
    let coverAssetUrl: String?
    let serviceFeePoints: Int
    let outputCount: Int
    let outputs: [AISSkillOutput]

    private enum CodingKeys: String, CodingKey {
        case id
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case descriptionZh = "DescriptionZh"
        case descriptionEn = "DescriptionEn"
        case category = "Category"
        case isOfficial = "IsOfficial"
        case coverAssetUrl = "CoverAssetUrl"
        case serviceFeePoints
        case outputCount
        case outputs
    }

    var localizedName: String {
        AISLocalization.isChinese
            ? nameZh
            : (nameEn?.nilIfEmpty ?? nameZh)
    }

    var localizedDescription: String? {
        AISLocalization.isChinese
            ? (descriptionZh ?? descriptionEn)
            : (descriptionEn ?? descriptionZh)
    }
}

struct AISSkillOutput: Codable, Identifiable, Hashable {
    var id: String { key }
    let key: String
    let titleZh: String?
    let titleEn: String?
    let count: Int
    let required: Bool
    let aspectRatio: String?
    let resolution: String?

    private enum CodingKeys: String, CodingKey {
        case key = "Key"
        case titleZh = "TitleZh"
        case titleEn = "TitleEn"
        case count
        case required = "Required"
        case aspectRatio = "AspectRatio"
        case resolution = "Resolution"
    }

    var localizedTitle: String {
        AISLocalization.isChinese
            ? (titleZh ?? titleEn ?? key)
            : (titleEn ?? titleZh ?? key)
    }
}

struct AISSkillQuote: Codable, Identifiable {
    var id: String { runId }
    let runId: String
    let quoteToken: String
    let expiresAt: Date
    let generationPoints: Int
    let serviceFeePoints: Int
    let totalPoints: Int
    let estimatedMinutes: Int
    let steps: [AISSkillQuoteStep]
}

struct AISSkillQuoteStep: Codable, Identifiable {
    var id: String { key }
    let key: String
    let titleZh: String?
    let titleEn: String?
    let required: Bool
    let count: Int
    let pointCost: Int

    private enum CodingKeys: String, CodingKey {
        case key = "Key"
        case titleZh = "TitleZh"
        case titleEn = "TitleEn"
        case required = "Required"
        case count = "Count"
        case pointCost = "PointCost"
    }

    var localizedTitle: String {
        AISLocalization.isChinese
            ? (titleZh ?? titleEn ?? key)
            : (titleEn ?? titleZh ?? key)
    }
}

struct AISSkillRunConfirmation: Codable {
    let runId: String
    let status: String
    let jobIds: [String]?
}

struct AISSkillRunDetail: Codable {
    let run: AISProjectRun
    let jobs: [AISTaskJob]
}

struct AISCreateProjectRequest: Encodable {
    let name: String
    let description: String
    let brandKey: String?
    let productKey: String?
    let referenceAssetIds: [String]
    let context: [String: String]
}

struct AISProjectAssetsRequest: Encodable {
    let referenceAssetIds: [String]
}

struct AISProjectMessageRequest: Encodable {
    let content: String
    let proposeMemory: Bool
    let memoryType: String
}

struct AISProjectMessageResult: Decodable {
    let messageId: String
    let memoryProposal: AISProjectMemory?
}

struct AISSkillQuoteRequest: Encodable {
    let requirement: String
    let language: String
    let referenceAssetIds: [String]
    let selectedStepKeys: [String]
    let isFollowUp: Bool
    let inputs: [String: String]
}

struct AISSkillConfirmRequest: Encodable {
    let quoteToken: String
}

struct AISMemoryStatusRequest: Encodable {
    let content: String?
    let status: String
}
