import CoreGraphics
import Foundation

struct APIEnvelope<Value: Decodable>: Decodable {
    let success: Bool
    let status: Int?
    let message: String?
    let extra: APIMessageExtra?
    let response: Value?

    private enum CodingKeys: String, CodingKey {
        case success, response
        case successUpper = "Success"
        case status
        case statusUpper = "Status"
        case message = "msg"
        case messageUpper = "Msg"
        case extra
        case extraUpper = "Extra"
        case responseUpper = "Response"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        success = try box.decodeIfPresent(Bool.self, forKey: .success)
            ?? box.decodeIfPresent(Bool.self, forKey: .successUpper) ?? true
        status = try box.decodeIfPresent(Int.self, forKey: .status)
            ?? box.decodeIfPresent(Int.self, forKey: .statusUpper)
        message = try box.decodeIfPresent(String.self, forKey: .message)
            ?? box.decodeIfPresent(String.self, forKey: .messageUpper)
        extra = try box.decodeIfPresent(APIMessageExtra.self, forKey: .extra)
            ?? box.decodeIfPresent(APIMessageExtra.self, forKey: .extraUpper)
        response = try box.decodeIfPresent(Value.self, forKey: .response)
            ?? box.decodeIfPresent(Value.self, forKey: .responseUpper)
    }
}

struct APIMessageExtra: Decodable {
    let messageCode: String?
    let messageParams: [String: APIMessageValue]
    let details: APIMessageValue?

    private enum CodingKeys: String, CodingKey {
        case messageCode, messageParams, details
        case messageCodeUpper = "MessageCode"
        case messageParamsUpper = "MessageParams"
        case detailsUpper = "Details"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        messageCode = try box.decodeIfPresent(String.self, forKey: .messageCode)
            ?? box.decodeIfPresent(String.self, forKey: .messageCodeUpper)
        messageParams = try box.decodeIfPresent([String: APIMessageValue].self, forKey: .messageParams)
            ?? box.decodeIfPresent([String: APIMessageValue].self, forKey: .messageParamsUpper)
            ?? [:]
        details = try box.decodeIfPresent(APIMessageValue.self, forKey: .details)
            ?? box.decodeIfPresent(APIMessageValue.self, forKey: .detailsUpper)
    }
}

enum APIMessageValue: Decodable {
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case object([String: APIMessageValue])
    case array([APIMessageValue])
    case null

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Decimal.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([String: APIMessageValue].self) { self = .object(value) }
        else if let value = try? box.decode([APIMessageValue].self) { self = .array(value) }
        else {
            throw DecodingError.dataCorruptedError(in: box, debugDescription: "无法解析消息参数")
        }
    }

    var text: String {
        switch self {
        case let .string(value): return value
        case let .number(value): return NSDecimalNumber(decimal: value).stringValue
        case let .bool(value): return value ? "true" : "false"
        case .null: return ""
        case .object, .array: return ""
        }
    }
}

struct PageResponse<Value: Decodable>: Decodable {
    let items: [Value]
    let total: Int

    private enum CodingKeys: String, CodingKey {
        case items, total, data, dataCount
        case itemsUpper = "Items"
        case totalUpper = "Total"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        items = try box.decodeIfPresent([Value].self, forKey: .items)
            ?? box.decodeIfPresent([Value].self, forKey: .itemsUpper)
            ?? box.decodeIfPresent([Value].self, forKey: .data) ?? []
        total = try box.decodeIfPresent(Int.self, forKey: .total)
            ?? box.decodeIfPresent(Int.self, forKey: .totalUpper)
            ?? box.decodeIfPresent(Int.self, forKey: .dataCount) ?? items.count
    }
}

struct StyleTemplateFilterGroup: Decodable, Identifiable, Hashable {
    var id: String { groupKey }
    let groupKey: String
    let nameZh: String
    let nameEn: String
    let sort: Int
    let items: [StyleTemplateFilterItem]

    private enum CodingKeys: String, CodingKey {
        case groupKey = "GroupKey"
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case sort = "Sort"
        case items = "Items"
    }

    var name: String { AppLanguage.value(zh: nameZh, en: nameEn) }
}

struct StyleTemplateFilterItem: Decodable, Identifiable, Hashable {
    var id: String { "\(groupKey):\(itemKey)" }
    let groupKey: String
    let itemKey: String
    let nameZh: String
    let nameEn: String
    let sort: Int

    private enum CodingKeys: String, CodingKey {
        case groupKey = "GroupKey"
        case itemKey = "ItemKey"
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case sort = "Sort"
    }

    var name: String { AppLanguage.value(zh: nameZh, en: nameEn) }
}

struct StyleTemplate: Decodable, Identifiable, Hashable {
    let id: String
    let templateKey: String
    let nameZh: String
    let nameEn: String
    let descriptionZh: String?
    let descriptionEn: String?
    let resolvedName: String?
    let resolvedDescription: String?
    let publicPromptZh: String?
    let publicPromptEn: String?
    var coverAssetURL: String?
    var sampleAssetURL: String?
    let aspectRatios: [String]
    let defaultAspectRatio: String?
    let resolutions: [String]
    let defaultResolution: String?
    let defaultDisplayModelKey: String?
    let fallbackDisplayModelKey: String?
    let basePointCost: Int
    let usageCount: Int
    let viewCount: Int
    let heatScore: Int
    let imageSlots: [TemplateImageSlot]
    let textFields: [TemplateTextField]

    private enum CodingKeys: String, CodingKey {
        case id = "Id", templateKey = "TemplateKey", nameZh = "NameZh", nameEn = "NameEn"
        case descriptionZh = "DescriptionZh", descriptionEn = "DescriptionEn"
        case resolvedName = "Name", resolvedDescription = "Description"
        case publicPromptZh = "PublicPromptZh", publicPromptEn = "PublicPromptEn"
        case coverAssetURL = "CoverAssetUrl", sampleAssetURL = "SampleAssetUrl"
        case aspectRatios = "AspectRatios", defaultAspectRatio = "DefaultAspectRatio"
        case resolutions = "Resolutions", defaultResolution = "DefaultResolution"
        case defaultDisplayModelKey = "DefaultDisplayModelKey"
        case fallbackDisplayModelKey = "FallbackDisplayModelKey"
        case basePointCost = "BasePointCost", usageCount = "UsageCount", viewCount = "ViewCount", heatScore = "HeatScore"
        case imageSlots = "ImageSlots", textFields = "TextFields"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decodeFlexibleString(forKey: .id) ?? UUID().uuidString
        templateKey = try box.decodeIfPresent(String.self, forKey: .templateKey) ?? id
        nameZh = try box.decodeIfPresent(String.self, forKey: .nameZh) ?? ""
        nameEn = try box.decodeIfPresent(String.self, forKey: .nameEn) ?? nameZh
        descriptionZh = try box.decodeIfPresent(String.self, forKey: .descriptionZh)
        descriptionEn = try box.decodeIfPresent(String.self, forKey: .descriptionEn)
        resolvedName = try box.decodeIfPresent(String.self, forKey: .resolvedName)
        resolvedDescription = try box.decodeIfPresent(String.self, forKey: .resolvedDescription)
        publicPromptZh = try box.decodeIfPresent(String.self, forKey: .publicPromptZh)
        publicPromptEn = try box.decodeIfPresent(String.self, forKey: .publicPromptEn)
        coverAssetURL = try box.decodeIfPresent(String.self, forKey: .coverAssetURL)
        sampleAssetURL = try box.decodeIfPresent(String.self, forKey: .sampleAssetURL)
        aspectRatios = try box.decodeIfPresent([String].self, forKey: .aspectRatios) ?? []
        defaultAspectRatio = try box.decodeIfPresent(String.self, forKey: .defaultAspectRatio)
        resolutions = try box.decodeIfPresent([String].self, forKey: .resolutions) ?? []
        defaultResolution = try box.decodeIfPresent(String.self, forKey: .defaultResolution)
        defaultDisplayModelKey = try box.decodeIfPresent(String.self, forKey: .defaultDisplayModelKey)
        fallbackDisplayModelKey = try box.decodeIfPresent(String.self, forKey: .fallbackDisplayModelKey)
        basePointCost = try box.decodeIfPresent(Int.self, forKey: .basePointCost) ?? 0
        usageCount = try box.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
        viewCount = try box.decodeIfPresent(Int.self, forKey: .viewCount) ?? 0
        heatScore = try box.decodeIfPresent(Int.self, forKey: .heatScore) ?? viewCount + usageCount * 5
        imageSlots = try box.decodeIfPresent([TemplateImageSlot].self, forKey: .imageSlots) ?? []
        textFields = try box.decodeIfPresent([TemplateTextField].self, forKey: .textFields) ?? []
    }

    var name: String {
        if let resolvedName = resolvedName?.nilIfEmpty { return resolvedName }
        if !AppLanguage.isChinese, isGenericEnglishName {
            return nameZh
        }
        return AppLanguage.value(zh: nameZh, en: nameEn)
    }

    private var isGenericEnglishName: Bool {
        switch nameEn.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ais visual template", "ai visual template", "ais style template",
             "ai style template", "style template", "template":
            true
        default:
            false
        }
    }
    var description: String {
        resolvedDescription?.nilIfEmpty
            ?? AppLanguage.value(zh: descriptionZh, en: descriptionEn)
    }
    var publicPrompt: String { AppLanguage.value(zh: publicPromptZh, en: publicPromptEn) }
    var aspectRatioText: String { defaultAspectRatio ?? aspectRatios.first ?? "4:5" }
    var displayAspectRatio: CGFloat {
        let parts = aspectRatioText.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[1] > 0 else { return 0.8 }
        return CGFloat(parts[0] / parts[1])
    }
    var imageURL: URL? {
        resolvedMediaURL(coverAssetURL) ?? resolvedMediaURL(sampleAssetURL)
    }

    mutating func preserveMissingMedia(from fallback: StyleTemplate) {
        // 详情接口偶发未解析出素材地址时，保留列表已经成功展示的地址，避免有效图片被空值覆盖。
        if resolvedMediaURL(coverAssetURL) == nil {
            coverAssetURL = fallback.coverAssetURL
        }
        if resolvedMediaURL(sampleAssetURL) == nil {
            sampleAssetURL = fallback.sampleAssetURL
        }
    }
}

struct TemplateImageSlot: Decodable, Identifiable, Hashable {
    var id: String { slotKey }
    let slotKey: String
    let nameZh: String
    let nameEn: String?
    let descriptionZh: String?
    let descriptionEn: String?
    let required: Bool
    let sort: Int

    private enum CodingKeys: String, CodingKey {
        case slotKey = "SlotKey", nameZh = "NameZh", nameEn = "NameEn"
        case descriptionZh = "DescriptionZh", descriptionEn = "DescriptionEn"
        case required = "Required", sort = "Sort"
    }
    var name: String { AppLanguage.value(zh: nameZh, en: nameEn) }
}

struct TemplateTextField: Decodable, Identifiable, Hashable {
    var id: String { fieldKey }
    let fieldKey: String
    let nameZh: String
    let nameEn: String
    let placeholderZh: String?
    let placeholderEn: String?
    let isRequired: Bool
    let maxLength: Int
    let defaultValue: String?
    let sort: Int
    let enabled: Bool

    private enum CodingKeys: String, CodingKey {
        case fieldKey = "FieldKey", nameZh = "NameZh", nameEn = "NameEn"
        case placeholderZh = "PlaceholderZh", placeholderEn = "PlaceholderEn"
        case isRequired = "IsRequired", maxLength = "MaxLength"
        case defaultValue = "DefaultValue", sort = "Sort", enabled = "Enabled"
    }
    var name: String { AppLanguage.value(zh: nameZh, en: nameEn) }
    var placeholder: String { AppLanguage.value(zh: placeholderZh, en: placeholderEn) }
}

struct GalleryJob: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let styleTemplateID: String?
    let outputJSON: String?
    let resultAssetID: String?
    let inputJSON: String?
    let creatorName: String?
    let creatorAvatarURL: String?
    let resultURL: String?
    let aspectRatio: String?
    let resolution: String?
    let fileSizeBytes: Int64?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let generationDurationSeconds: Int64?
    let keywords: [String]
    let viewCount: Int
    let heatScore: Int

    private enum CodingKeys: String, CodingKey {
        case id = "Id", title = "Title", legacyTitle = "GalleryTitle"
        case description = "Description", legacyDescription = "GalleryDescription"
        case styleTemplateID = "StyleTemplateId", outputJSON = "OutputJson"
        case resultAssetID = "ResultAssetId", inputJSON = "InputJson"
        case creatorName = "CreatorName", creatorAvatarURL = "CreatorAvatarUrl"
        case resultURL = "ResultUrl", aspectRatio = "AspectRatio", resolution = "Resolution"
        case fileSizeBytes = "FileSizeBytes", pixelWidth = "PixelWidth", pixelHeight = "PixelHeight"
        case generationDurationSeconds = "GenerationDurationSeconds", keywords = "GalleryKeywords"
        case viewCount = "ViewCount"
        case heatScore = "HeatScore"
    }
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decodeFlexibleString(forKey: .id) ?? UUID().uuidString
        title = try box.decodeIfPresent(String.self, forKey: .title)
            ?? box.decodeIfPresent(String.self, forKey: .legacyTitle) ?? ""
        description = try box.decodeIfPresent(String.self, forKey: .description)
            ?? box.decodeIfPresent(String.self, forKey: .legacyDescription) ?? ""
        styleTemplateID = try box.decodeFlexibleString(forKey: .styleTemplateID)
        outputJSON = try box.decodeIfPresent(String.self, forKey: .outputJSON)
        resultAssetID = try box.decodeFlexibleString(forKey: .resultAssetID)
        inputJSON = try box.decodeIfPresent(String.self, forKey: .inputJSON)
        creatorName = try box.decodeIfPresent(String.self, forKey: .creatorName)
        creatorAvatarURL = try box.decodeIfPresent(String.self, forKey: .creatorAvatarURL)
        resultURL = try box.decodeIfPresent(String.self, forKey: .resultURL)
        aspectRatio = try box.decodeIfPresent(String.self, forKey: .aspectRatio)
        resolution = try box.decodeIfPresent(String.self, forKey: .resolution)
        fileSizeBytes = try box.decodeIfPresent(Int64.self, forKey: .fileSizeBytes)
        pixelWidth = try box.decodeIfPresent(Int.self, forKey: .pixelWidth)
        pixelHeight = try box.decodeIfPresent(Int.self, forKey: .pixelHeight)
        generationDurationSeconds = try box.decodeIfPresent(Int64.self, forKey: .generationDurationSeconds)
        keywords = try box.decodeIfPresent([String].self, forKey: .keywords) ?? []
        viewCount = try box.decodeIfPresent(Int.self, forKey: .viewCount) ?? 0
        heatScore = try box.decodeIfPresent(Int.self, forKey: .heatScore) ?? viewCount
    }
    var mediaURL: URL? {
        if let url = resolvedMediaURL(resultURL) { return url }
        if let outputJSON,
           let data = outputJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["fileUrl", "FileUrl", "resultUrl", "ResultUrl", "generatedImageUrl", "GeneratedImageUrl"] {
                if let value = object[key] as? String, let url = resolvedMediaURL(value) { return url }
            }
        }
        return nil
    }
    var displayAspectRatio: CGFloat {
        if let aspectRatio = aspectRatio?.nilIfEmpty { return ratioValue(aspectRatio) }
        guard let inputJSON,
              let data = inputJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ratio = (object["aspectRatio"] ?? object["AspectRatio"]) as? String else { return 0.8 }
        return ratioValue(ratio)
    }
}

struct PublicViewCountResponse: Decodable {
    let viewCount: Int
    let counted: Bool
    let windowSeconds: Int
    let usageCount: Int
    let heatScore: Int

    private enum CodingKeys: String, CodingKey {
        case viewCount = "ViewCount", counted = "Counted", windowSeconds = "WindowSeconds"
        case usageCount = "UsageCount", heatScore = "HeatScore"
    }
}

struct TaskJob: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let jobType: String
    let status: String
    let progress: Int
    let title: String
    let galleryDescription: String?
    let pointCost: Int
    let outputJSON: String?
    let resultAssetID: String?
    let resultURL: String?
    let aspectRatio: String?
    let resolution: String?
    let fileSizeBytes: Int64?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let generationDurationSeconds: Int64?
    let errorMessage: String?
    let isGallery: Bool
    let createTime: String?
    let startedAt: String?
    let finishedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id = "Id", idLower = "id", jobType = "JobType", jobTypeLower = "jobType"
        case status = "Status", statusLower = "status", progress = "Progress", progressLower = "progress"
        case displayTitle = "DisplayTitle", displayTitleLower = "displayTitle"
        case title = "GalleryTitle", titleLower = "galleryTitle"
        case galleryDescription = "GalleryDescription", galleryDescriptionLower = "galleryDescription"
        case pointCost = "PointCost", pointCostLower = "pointCost"
        case outputJSON = "OutputJson", outputJSONLower = "outputJson"
        case resultAssetID = "DisplayResultAssetId", resultAssetIDLower = "displayResultAssetId"
        case fallbackResultAssetID = "ResultAssetId", fallbackResultAssetIDLower = "resultAssetId"
        case resultURL = "ResultUrl", resultURLLower = "resultUrl"
        case aspectRatio = "AspectRatio", aspectRatioLower = "aspectRatio"
        case resolution = "Resolution", resolutionLower = "resolution"
        case fileSizeBytes = "FileSizeBytes", fileSizeBytesLower = "fileSizeBytes"
        case pixelWidth = "PixelWidth", pixelWidthLower = "pixelWidth"
        case pixelHeight = "PixelHeight", pixelHeightLower = "pixelHeight"
        case generationDurationSeconds = "GenerationDurationSeconds"
        case generationDurationSecondsLower = "generationDurationSeconds"
        case errorMessage = "ErrorMessage", errorMessageLower = "errorMessage"
        case isGallery = "IsGallery", isGalleryLower = "isGallery"
        case createTime = "CreateTime", createTimeLower = "createTime"
        case startedAt = "StartedAt", startedAtLower = "startedAt"
        case finishedAt = "FinishedAt", finishedAtLower = "finishedAt"
    }
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decodeFlexibleString(forKey: .id) ?? box.decodeFlexibleString(forKey: .idLower) ?? UUID().uuidString
        jobType = try box.decodeIfPresent(String.self, forKey: .jobType) ?? box.decodeIfPresent(String.self, forKey: .jobTypeLower) ?? ""
        status = try box.decodeIfPresent(String.self, forKey: .status) ?? box.decodeIfPresent(String.self, forKey: .statusLower) ?? ""
        progress = try box.decodeIfPresent(Int.self, forKey: .progress) ?? box.decodeIfPresent(Int.self, forKey: .progressLower) ?? 0
        title = try box.decodeIfPresent(String.self, forKey: .displayTitle)
            ?? box.decodeIfPresent(String.self, forKey: .displayTitleLower)
            ?? box.decodeIfPresent(String.self, forKey: .title)
            ?? box.decodeIfPresent(String.self, forKey: .titleLower)
            ?? ""
        galleryDescription = try box.decodeIfPresent(String.self, forKey: .galleryDescription)
            ?? box.decodeIfPresent(String.self, forKey: .galleryDescriptionLower)
        pointCost = try box.decodeIfPresent(Int.self, forKey: .pointCost) ?? box.decodeIfPresent(Int.self, forKey: .pointCostLower) ?? 0
        outputJSON = try box.decodeIfPresent(String.self, forKey: .outputJSON) ?? box.decodeIfPresent(String.self, forKey: .outputJSONLower)
        resultAssetID = try box.decodeFlexibleString(forKey: .resultAssetID)
            ?? box.decodeFlexibleString(forKey: .resultAssetIDLower)
            ?? box.decodeFlexibleString(forKey: .fallbackResultAssetID)
            ?? box.decodeFlexibleString(forKey: .fallbackResultAssetIDLower)
        resultURL = try box.decodeIfPresent(String.self, forKey: .resultURL)
            ?? box.decodeIfPresent(String.self, forKey: .resultURLLower)
        aspectRatio = try box.decodeIfPresent(String.self, forKey: .aspectRatio) ?? box.decodeIfPresent(String.self, forKey: .aspectRatioLower)
        resolution = try box.decodeIfPresent(String.self, forKey: .resolution)
            ?? box.decodeIfPresent(String.self, forKey: .resolutionLower)
        fileSizeBytes = try box.decodeIfPresent(Int64.self, forKey: .fileSizeBytes)
            ?? box.decodeIfPresent(Int64.self, forKey: .fileSizeBytesLower)
        pixelWidth = try box.decodeIfPresent(Int.self, forKey: .pixelWidth)
            ?? box.decodeIfPresent(Int.self, forKey: .pixelWidthLower)
        pixelHeight = try box.decodeIfPresent(Int.self, forKey: .pixelHeight)
            ?? box.decodeIfPresent(Int.self, forKey: .pixelHeightLower)
        generationDurationSeconds = try box.decodeIfPresent(Int64.self, forKey: .generationDurationSeconds)
            ?? box.decodeIfPresent(Int64.self, forKey: .generationDurationSecondsLower)
        errorMessage = try box.decodeIfPresent(String.self, forKey: .errorMessage)
            ?? box.decodeIfPresent(String.self, forKey: .errorMessageLower)
        isGallery = try box.decodeIfPresent(Bool.self, forKey: .isGallery)
            ?? box.decodeIfPresent(Bool.self, forKey: .isGalleryLower)
            ?? false
        createTime = try box.decodeIfPresent(String.self, forKey: .createTime)
            ?? box.decodeIfPresent(String.self, forKey: .createTimeLower)
        startedAt = try box.decodeIfPresent(String.self, forKey: .startedAt)
            ?? box.decodeIfPresent(String.self, forKey: .startedAtLower)
        finishedAt = try box.decodeIfPresent(String.self, forKey: .finishedAt)
            ?? box.decodeIfPresent(String.self, forKey: .finishedAtLower)
    }
    var isTemplate: Bool { jobType.lowercased() == "style_template_generate" }
    var mediaURL: URL? {
        // 摘要列表不会返回 OutputJson，必须优先采用服务端解析好的 CDN 结果地址。
        if let url = resolvedMediaURL(resultURL) { return url }
        if let outputJSON, let data = outputJSON.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["fileUrl", "FileUrl", "resultUrl", "ResultUrl", "generatedImageUrl", "GeneratedImageUrl"] {
                if let value = object[key] as? String, let url = resolvedMediaURL(value) { return url }
            }
        }
        return nil
    }
    var displayAspectRatio: CGFloat { ratioValue(aspectRatio ?? "4:5") }
    var shareDescription: String? {
        guard let value = galleryDescription?.nilIfEmpty,
              !value.localizedCaseInsensitiveContains("AI 正在整理"),
              !value.localizedCaseInsensitiveContains("awaiting AI summary") else {
            return nil
        }
        return value
    }
    var isActive: Bool {
        ["queued", "pending", "processing", "running"].contains(status.lowercased())
    }
    var startedDate: Date? {
        Self.parseServerDate(startedAt)
    }
    var createdDate: Date? {
        Self.parseServerDate(createTime)
    }
    var finishedDate: Date? {
        Self.parseServerDate(finishedAt)
    }

    private static func parseServerDate(_ rawValue: String?) -> Date? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        let hasExplicitTimeZone = value.hasSuffix("Z")
            || value.range(
                of: #"[+-]\d{2}:?\d{2}$"#,
                options: .regularExpression
            ) != nil
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if hasExplicitTimeZone,
           let date = fractional.date(from: value) ?? standard.date(from: value) {
            return date
        }
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSSSSSS",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss"
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            // 后端使用 DateTime.Now，未携带偏移量的时间按服务端中国时区解释。
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    func isCreated(before other: TaskJob) -> Bool {
        if let createTime, let otherCreateTime = other.createTime,
           createTime != otherCreateTime {
            return createTime < otherCreateTime
        }
        return id.compare(other.id, options: .numeric) == .orderedAscending
    }
}

struct AuthResult: Decodable {
    let user: AuthUser
    let token: AuthToken
    private enum CodingKeys: String, CodingKey { case user = "User", userLower = "user", token = "Token", tokenLower = "token" }
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        user = try box.decodeIfPresent(AuthUser.self, forKey: .user) ?? box.decode(AuthUser.self, forKey: .userLower)
        token = try box.decodeIfPresent(AuthToken.self, forKey: .token) ?? box.decode(AuthToken.self, forKey: .tokenLower)
    }
}

struct AppleNativeLoginRequest: Encodable {
    let identityToken: String
    let authorizationCode: String
    let nonce: String
    let givenName: String?
    let familyName: String?
    let displayName: String?
    let email: String?
    let locale: String
    let countryCode: String?
    let inviteCode: String?
    let inviteSourceUrl: String?
    let inviteSourceChannel: String?
    let inviteFirstVisitedAt: String?
}

struct EmailCodeLoginRequest: Encodable {
    let email: String
    let code: String
    let countryCode: String?
    let locale: String
    let inviteCode: String?
    let inviteSourceUrl: String?
    let inviteSourceChannel: String?
    let inviteFirstVisitedAt: String?
}

struct AppleBindingStatus: Decodable, Equatable, Sendable {
    let isBound: Bool
    let email: String?

    init(isBound: Bool, email: String?) {
        self.isBound = isBound
        self.email = email
    }

    private enum CodingKeys: String, CodingKey {
        case isBound = "IsBound"
        case isBoundLower = "isBound"
        case email = "Email"
        case emailLower = "email"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isBound = try container.decodeIfPresent(Bool.self, forKey: .isBound)
            ?? container.decode(Bool.self, forKey: .isBoundLower)
        email = try container.decodeIfPresent(String.self, forKey: .email)
            ?? container.decodeIfPresent(String.self, forKey: .emailLower)
    }
}
struct ComplianceConsentStatus: Decodable {
    let agreementVersion: String
    let isAccepted: Bool
    let acceptedAt: String?

    private enum CodingKeys: String, CodingKey {
        case agreementVersion = "AgreementVersion"
        case agreementVersionLower = "agreementVersion"
        case isAccepted = "IsAccepted"
        case isAcceptedLower = "isAccepted"
        case acceptedAt = "AcceptedAt"
        case acceptedAtLower = "acceptedAt"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        agreementVersion = try box.decodeIfPresent(String.self, forKey: .agreementVersion)
            ?? box.decode(String.self, forKey: .agreementVersionLower)
        isAccepted = try box.decodeIfPresent(Bool.self, forKey: .isAccepted)
            ?? box.decode(Bool.self, forKey: .isAcceptedLower)
        acceptedAt = try box.decodeIfPresent(String.self, forKey: .acceptedAt)
            ?? box.decodeIfPresent(String.self, forKey: .acceptedAtLower)
    }
}

struct ComplianceConsentRequest: Encodable {
    let agreementVersion: String
    let accepted: Bool
    let clientPlatform: String
    let locale: String
}

struct AuthUser: Codable {
    let id: String
    let email: String?
    let displayName: String?
    let countryCode: String?
    let avatarURL: String?

    private enum CodingKeys: String, CodingKey {
        case id = "Id", idLower = "id"
        case email = "Email", emailLower = "email"
        case displayName = "DisplayName", displayNameLower = "displayName"
        case countryCode = "CountryCode", countryCodeLower = "countryCode"
        case avatarURL = "AvatarUrl", avatarURLLower = "avatarUrl"
    }

    init(
        id: String,
        email: String?,
        displayName: String?,
        countryCode: String?,
        avatarURL: String?
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.countryCode = countryCode
        self.avatarURL = avatarURL
    }

    init(from decoder: Decoder) throws {
        let b = try decoder.container(keyedBy: CodingKeys.self)
        id = try b.decodeFlexibleString(forKey: .id) ?? b.decodeFlexibleString(forKey: .idLower) ?? ""
        email = try b.decodeIfPresent(String.self, forKey: .email) ?? b.decodeIfPresent(String.self, forKey: .emailLower)
        displayName = try b.decodeIfPresent(String.self, forKey: .displayName) ?? b.decodeIfPresent(String.self, forKey: .displayNameLower)
        countryCode = try b.decodeIfPresent(String.self, forKey: .countryCode) ?? b.decodeIfPresent(String.self, forKey: .countryCodeLower)
        avatarURL = try b.decodeIfPresent(String.self, forKey: .avatarURL) ?? b.decodeIfPresent(String.self, forKey: .avatarURLLower)
    }

    func encode(to encoder: Encoder) throws {
        var b = encoder.container(keyedBy: CodingKeys.self)
        try b.encode(id, forKey: .idLower)
        try b.encodeIfPresent(email, forKey: .emailLower)
        try b.encodeIfPresent(displayName, forKey: .displayNameLower)
        try b.encodeIfPresent(countryCode, forKey: .countryCodeLower)
        try b.encodeIfPresent(avatarURL, forKey: .avatarURLLower)
    }
}
struct AuthToken: Decodable { let accessToken: String; let refreshToken: String?
    private enum CodingKeys: String, CodingKey { case accessToken = "token", accessTokenUpper = "Token", refreshToken, refreshTokenUpper = "RefreshToken", refreshTokenSnake = "refresh_token" }
    init(from decoder: Decoder) throws { let b = try decoder.container(keyedBy: CodingKeys.self); accessToken = try b.decodeIfPresent(String.self, forKey: .accessToken) ?? b.decode(String.self, forKey: .accessTokenUpper); refreshToken = try b.decodeIfPresent(String.self, forKey: .refreshToken) ?? b.decodeIfPresent(String.self, forKey: .refreshTokenUpper) ?? b.decodeIfPresent(String.self, forKey: .refreshTokenSnake) }
}
struct AssetUploadResult: Decodable {
    let id: String
    let fileURL: String?
    private enum CodingKeys: String, CodingKey {
        case id = "Id", idLower = "id"
        case fileURL = "FileUrl", fileURLLower = "fileUrl"
    }
    init(from decoder: Decoder) throws {
        let b = try decoder.container(keyedBy: CodingKeys.self)
        id = try b.decodeFlexibleString(forKey: .id) ?? b.decodeFlexibleString(forKey: .idLower) ?? ""
        fileURL = try b.decodeIfPresent(String.self, forKey: .fileURL) ?? b.decodeIfPresent(String.self, forKey: .fileURLLower)
    }
}

struct PixaPromptAttributeSettings: Decodable {
    let modelOutputSpecs: [PixaOutputSpec]
    let effectiveMembershipLevel: String?

    private enum CodingKeys: String, CodingKey {
        case modelOutputSpecs = "ModelOutputSpecs"
        case effectiveMembershipLevel = "EffectiveMembershipLevel"
    }
}

struct PixaOutputSpec: Decodable, Identifiable, Hashable {
    var id: String { "\(specType):\(value)" }
    let mediaType: String
    let specType: String
    let value: String
    let nameZh: String
    let nameEn: String
    let sort: Int
    let multiplier: Decimal
    let requiredMembershipCode: String?
    let requiredMembershipName: String?
    let isAvailable: Bool

    private enum CodingKeys: String, CodingKey {
        case mediaType = "MediaType"
        case specType = "SpecType"
        case value = "Value"
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case sort = "Sort"
        case multiplier = "Multiplier"
        case requiredMembershipCode = "RequiredMembershipCode"
        case requiredMembershipName = "RequiredMembershipName"
        case isAvailable = "IsAvailable"
    }

    init(
        mediaType: String = "image",
        specType: String,
        value: String,
        nameZh: String? = nil,
        nameEn: String? = nil,
        sort: Int = 0,
        multiplier: Decimal = 1,
        requiredMembershipCode: String? = nil,
        requiredMembershipName: String? = nil,
        isAvailable: Bool = true
    ) {
        self.mediaType = mediaType
        self.specType = specType
        self.value = value
        self.nameZh = nameZh ?? value
        self.nameEn = nameEn ?? value
        self.sort = sort
        self.multiplier = multiplier
        self.requiredMembershipCode = requiredMembershipCode
        self.requiredMembershipName = requiredMembershipName
        self.isAvailable = isAvailable
    }

    var localizedName: String {
        AppLanguage.value(zh: nameZh, en: nameEn).nilIfEmpty ?? value
    }

    var membershipLabel: String? {
        guard let code = requiredMembershipCode?.nilIfEmpty else { return nil }
        let configured = requiredMembershipName?.nilIfEmpty
        let fallback: String
        switch code.lowercased() {
        case "normal": fallback = AppLanguage.isChinese ? "普通" : "Standard"
        case "vip": fallback = "VIP"
        case "plus": fallback = "Plus"
        case "pro": fallback = "Pro"
        case "student": fallback = AppLanguage.isChinese ? "学生" : "Student"
        case "max": fallback = "Max"
        case "enterprise": fallback = AppLanguage.isChinese ? "企业" : "Enterprise"
        default: fallback = code
        }
        return configured ?? fallback
    }

    func isSelectable(effectiveMembershipLevel: String?) -> Bool {
        guard isAvailable else { return false }
        guard let required = requiredMembershipCode?.nilIfEmpty else { return true }
        guard let effective = effectiveMembershipLevel?.nilIfEmpty else { return false }
        guard let requiredRank = Self.membershipRank(required),
              let effectiveRank = Self.membershipRank(effective) else {
            return true
        }
        return effectiveRank >= requiredRank
    }

    private static func membershipRank(_ code: String) -> Int? {
        switch code.lowercased() {
        case "normal": 0
        case "vip": 1
        case "plus": 2
        case "pro": 3
        case "student": 4
        case "max": 5
        case "enterprise": 6
        default: nil
        }
    }
}

struct PixaAssetLibraryItem: Decodable, Identifiable, Hashable {
    let id: String
    let fileURL: String?
    let title: String
    let displayName: String?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case fileURL = "FileUrl"
        case title = "Title"
        case displayName = "DisplayName"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decodeFlexibleString(forKey: .id) ?? ""
        fileURL = try box.decodeIfPresent(String.self, forKey: .fileURL)
        title = try box.decodeIfPresent(String.self, forKey: .title) ?? ""
        displayName = try box.decodeIfPresent(String.self, forKey: .displayName)
    }

    var imageURL: URL? { resolvedMediaURL(fileURL) }
    var name: String { displayName?.nilIfEmpty ?? title.nilIfEmpty ?? AppLanguage.localized("editor.library.asset") }
}

struct PixaAccountProfile: Decodable, Sendable {
    let email: String?
    let displayName: String?
    let canChangeDisplayName: Bool
    let mobile: String?
    let companyName: String?
    let taxNo: String?
    let avatarURL: String?
    let countryCode: String?
    let currency: String?

    private enum CodingKeys: String, CodingKey {
        case email = "Email", emailLower = "email"
        case displayName = "DisplayName", displayNameLower = "displayName"
        case canChangeDisplayName = "CanChangeDisplayName"
        case canChangeDisplayNameLower = "canChangeDisplayName"
        case mobile = "Mobile", mobileLower = "mobile"
        case companyName = "CompanyName", companyNameLower = "companyName"
        case taxNo = "TaxNo", taxNoLower = "taxNo"
        case avatarURL = "AvatarUrl", avatarURLLower = "avatarUrl"
        case countryCode = "CountryCode", countryCodeLower = "countryCode"
        case currency = "Currency", currencyLower = "currency"
    }

    init(from decoder: Decoder) throws {
        let b = try decoder.container(keyedBy: CodingKeys.self)
        email = try b.decodeIfPresent(String.self, forKey: .email) ?? b.decodeIfPresent(String.self, forKey: .emailLower)
        displayName = try b.decodeIfPresent(String.self, forKey: .displayName) ?? b.decodeIfPresent(String.self, forKey: .displayNameLower)
        canChangeDisplayName = try b.decodeIfPresent(Bool.self, forKey: .canChangeDisplayName)
            ?? b.decodeIfPresent(Bool.self, forKey: .canChangeDisplayNameLower)
            ?? true
        mobile = try b.decodeIfPresent(String.self, forKey: .mobile) ?? b.decodeIfPresent(String.self, forKey: .mobileLower)
        companyName = try b.decodeIfPresent(String.self, forKey: .companyName) ?? b.decodeIfPresent(String.self, forKey: .companyNameLower)
        taxNo = try b.decodeIfPresent(String.self, forKey: .taxNo) ?? b.decodeIfPresent(String.self, forKey: .taxNoLower)
        avatarURL = try b.decodeIfPresent(String.self, forKey: .avatarURL) ?? b.decodeIfPresent(String.self, forKey: .avatarURLLower)
        countryCode = try b.decodeIfPresent(String.self, forKey: .countryCode) ?? b.decodeIfPresent(String.self, forKey: .countryCodeLower)
        currency = try b.decodeIfPresent(String.self, forKey: .currency) ?? b.decodeIfPresent(String.self, forKey: .currencyLower)
    }
}

struct PixaUpdateProfileRequest: Encodable {
    let displayName: String?
    let mobile: String?
    let companyName: String?
    let taxNo: String?
    let avatarURL: String?
    let countryCode: String?

    private enum CodingKeys: String, CodingKey {
        case displayName = "DisplayName"
        case mobile = "Mobile"
        case companyName = "CompanyName"
        case taxNo = "TaxNo"
        case avatarURL = "AvatarUrl"
        case countryCode = "CountryCode"
    }
}
struct TemplateQuote: Decodable {
    let points: Int
    let savedPoints: Int
    let effectiveDiscountPercent: Decimal
    let effectiveBenefitName: String?

    private enum CodingKeys: String, CodingKey {
        case points, savedPoints, effectiveDiscountPercent, effectiveBenefitName
        case pointsUpper = "Points"
        case savedPointsUpper = "SavedPoints"
        case effectiveDiscountPercentUpper = "EffectiveDiscountPercent"
        case effectiveBenefitNameUpper = "EffectiveBenefitName"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        points = try box.decodeIfPresent(Int.self, forKey: .points)
            ?? box.decodeIfPresent(Int.self, forKey: .pointsUpper) ?? 0
        savedPoints = try box.decodeIfPresent(Int.self, forKey: .savedPoints)
            ?? box.decodeIfPresent(Int.self, forKey: .savedPointsUpper) ?? 0
        effectiveDiscountPercent = try box.decodeIfPresent(Decimal.self, forKey: .effectiveDiscountPercent)
            ?? box.decodeIfPresent(Decimal.self, forKey: .effectiveDiscountPercentUpper) ?? 0
        effectiveBenefitName = try box.decodeIfPresent(String.self, forKey: .effectiveBenefitName)
            ?? box.decodeIfPresent(String.self, forKey: .effectiveBenefitNameUpper)
    }
}
struct CompositionResult: Decodable { let jobID: String; private enum CodingKeys: String, CodingKey { case jobID = "jobId", jobIDUpper = "JobId" }; init(from decoder: Decoder) throws { let b = try decoder.container(keyedBy: CodingKeys.self); jobID = try b.decodeFlexibleString(forKey: .jobID) ?? b.decodeFlexibleString(forKey: .jobIDUpper) ?? "" } }

private func resolvedURL(_ value: String?) -> URL? {
    guard let value = value?.nilIfEmpty else { return nil }
    if let url = URL(string: value), url.scheme != nil { return url }
    return URL(string: value, relativeTo: AppConfiguration.apiBaseURL)?.absoluteURL
}
private func resolvedMediaURL(_ value: String?) -> URL? {
    guard let url = resolvedURL(value),
          url.scheme?.lowercased() == "https",
          !url.path.lowercased().hasPrefix("/api/") else {
        return nil
    }
    return url
}
private func ratioValue(_ value: String) -> CGFloat {
    let parts = value.split(separator: ":").compactMap { Double($0) }
    guard parts.count == 2, parts[1] > 0 else { return 0.8 }
    return CGFloat(parts[0] / parts[1])
}
extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) throws -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int64.self, forKey: key) { return String(value) }
        return nil
    }
}
