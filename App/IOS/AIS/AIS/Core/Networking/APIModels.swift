import CoreGraphics
import Foundation

extension Notification.Name {
    static let aisTaskSubmitted = Notification.Name("AIS.TaskSubmitted")
}

struct AISGenerationModelOption: Codable, Identifiable {
    var id: String { displayModelKey }
    let displayModelKey: String
    let nameZh: String
    let nameEn: String
    let descriptionZh: String?
    let descriptionEn: String?
    let requiredMembershipCode: String?
    let isRecommended: Bool
    let canSelect: Bool
    let canUse: Bool
    let upgradePromptZh: String?
    let upgradePromptEn: String?
    let modelMarkupRate: Decimal

    var localizedName: String {
        AISLocalization.value(zh: nameZh, en: nameEn)
    }

    var localizedDescription: String? {
        AISLocalization.optional(zh: descriptionZh, en: descriptionEn)
    }

    var localizedUpgradePrompt: String? {
        AISLocalization.optional(
            zh: upgradePromptZh,
            en: upgradePromptEn
        )
    }

    private enum CodingKeys: String, CodingKey {
        case displayModelKey = "DisplayModelKey"
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case descriptionZh = "DescriptionZh"
        case descriptionEn = "DescriptionEn"
        case requiredMembershipCode = "RequiredMembershipCode"
        case isRecommended = "IsRecommended"
        case canSelect = "CanSelect"
        case canUse = "CanUse"
        case upgradePromptZh = "UpgradePromptZh"
        case upgradePromptEn = "UpgradePromptEn"
        case modelMarkupRate = "ModelMarkupRate"
    }
}

struct APIEnvelope<Value: Decodable>: Decodable {
    let success: Bool
    let status: Int?
    let code: String?
    let message: String?
    let details: JSONValue?
    let extra: APIMessageExtra?
    let response: Value?

    private enum CodingKeys: String, CodingKey {
        case success
        case successUpper = "Success"
        case status
        case statusUpper = "Status"
        case code
        case codeUpper = "Code"
        case message = "msg"
        case messageUpper = "Msg"
        case details
        case detailsUpper = "Details"
        case extra
        case extraUpper = "Extra"
        case response
        case responseUpper = "Response"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
            ?? container.decodeIfPresent(Bool.self, forKey: .successUpper)
            ?? true
        status = try container.decodeIfPresent(Int.self, forKey: .status)
            ?? container.decodeIfPresent(Int.self, forKey: .statusUpper)
        code = try container.decodeFlexibleString(forKey: .code)
            ?? container.decodeFlexibleString(forKey: .codeUpper)
        message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .messageUpper)
        details = try container.decodeIfPresent(JSONValue.self, forKey: .details)
            ?? container.decodeIfPresent(JSONValue.self, forKey: .detailsUpper)
        extra = try container.decodeIfPresent(APIMessageExtra.self, forKey: .extra)
            ?? container.decodeIfPresent(APIMessageExtra.self, forKey: .extraUpper)
        response = try container.decodeIfPresent(Value.self, forKey: .response)
            ?? container.decodeIfPresent(Value.self, forKey: .responseUpper)
    }
}

struct APIMessageExtra: Decodable {
    let messageCode: String?
    let messageParams: [String: JSONValue]
    let details: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case messageCode, messageParams, details
        case messageCodeUpper = "MessageCode"
        case messageParamsUpper = "MessageParams"
        case detailsUpper = "Details"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageCode = try container.decodeIfPresent(String.self, forKey: .messageCode)
            ?? container.decodeIfPresent(String.self, forKey: .messageCodeUpper)
        messageParams = try container.decodeIfPresent([String: JSONValue].self, forKey: .messageParams)
            ?? container.decodeIfPresent([String: JSONValue].self, forKey: .messageParamsUpper)
            ?? [:]
        details = try container.decodeIfPresent(JSONValue.self, forKey: .details)
            ?? container.decodeIfPresent(JSONValue.self, forKey: .detailsUpper)
    }
}

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法解析业务错误详情"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var messageParameterText: String {
        switch self {
        case let .string(value): return value
        case let .number(value): return NSDecimalNumber(decimal: value).stringValue
        case let .bool(value): return value ? "true" : "false"
        case .null: return ""
        case .object, .array:
            guard let data = try? JSONEncoder().encode(self),
                  let value = String(data: data, encoding: .utf8) else { return "" }
            return value
        }
    }
}

struct EmptyResponse: Decodable {}

struct AISVisualPresetOptions: Codable {
    let directions: [AISVisualPreset]
    let effects: [AISVisualPreset]

    init(
        directions: [AISVisualPreset],
        effects: [AISVisualPreset]
    ) {
        self.directions = directions
        self.effects = effects
    }

    private enum CodingKeys: String, CodingKey {
        case directions
        case directionsUpper = "Directions"
        case effects
        case effectsUpper = "Effects"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        directions = try container.decodeIfPresent(
            [AISVisualPreset].self,
            forKey: .directions
        ) ?? container.decodeIfPresent(
            [AISVisualPreset].self,
            forKey: .directionsUpper
        ) ?? []
        effects = try container.decodeIfPresent(
            [AISVisualPreset].self,
            forKey: .effects
        ) ?? container.decodeIfPresent(
            [AISVisualPreset].self,
            forKey: .effectsUpper
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(directions, forKey: .directions)
        try container.encode(effects, forKey: .effects)
    }
}

struct AISVisualPreset: Codable, Identifiable, Hashable {
    let id: String
    let nameZh: String
    let nameEn: String
    let descriptionZh: String?
    let descriptionEn: String?
    let icon: String?
    let sort: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case idUpper = "Id"
        case nameZh
        case nameZhUpper = "NameZh"
        case nameEn
        case nameEnUpper = "NameEn"
        case descriptionZh
        case descriptionZhUpper = "DescriptionZh"
        case descriptionEn
        case descriptionEnUpper = "DescriptionEn"
        case icon
        case iconUpper = "Icon"
        case sort
        case sortUpper = "Sort"
    }

    init(
        id: String,
        nameZh: String,
        nameEn: String,
        descriptionZh: String?,
        descriptionEn: String?,
        icon: String? = nil,
        sort: Int
    ) {
        self.id = id
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.descriptionZh = descriptionZh
        self.descriptionEn = descriptionEn
        self.icon = icon
        self.sort = sort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .idUpper)
        nameZh = try container.decodeIfPresent(String.self, forKey: .nameZh)
            ?? container.decodeIfPresent(String.self, forKey: .nameZhUpper)
            ?? ""
        nameEn = try container.decodeIfPresent(String.self, forKey: .nameEn)
            ?? container.decodeIfPresent(String.self, forKey: .nameEnUpper)
            ?? nameZh
        descriptionZh = try container.decodeIfPresent(
            String.self,
            forKey: .descriptionZh
        ) ?? container.decodeIfPresent(
            String.self,
            forKey: .descriptionZhUpper
        )
        descriptionEn = try container.decodeIfPresent(
            String.self,
            forKey: .descriptionEn
        ) ?? container.decodeIfPresent(
            String.self,
            forKey: .descriptionEnUpper
        )
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
            ?? container.decodeIfPresent(String.self, forKey: .iconUpper)
        sort = try container.decodeIfPresent(Int.self, forKey: .sort)
            ?? container.decodeIfPresent(Int.self, forKey: .sortUpper)
            ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nameZh, forKey: .nameZh)
        try container.encode(nameEn, forKey: .nameEn)
        try container.encodeIfPresent(descriptionZh, forKey: .descriptionZh)
        try container.encodeIfPresent(descriptionEn, forKey: .descriptionEn)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encode(sort, forKey: .sort)
    }

    var localizedName: String {
        AISLocalization.value(zh: nameZh, en: nameEn)
    }

    var localizedDescription: String? {
        AISLocalization.optional(zh: descriptionZh, en: descriptionEn)
    }
}

struct PageResponse<Value: Codable>: Codable {
    let items: [Value]
    let total: Int
    let page: Int
    let pageSize: Int

    private enum CodingKeys: String, CodingKey {
        case data
        case dataUpper = "Data"
        case total = "dataCount"
        case totalUpper = "DataCount"
        case page
        case pageUpper = "Page"
        case pageSize = "PageSize"
        case pageSizeLower = "pageSize"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Value].self, forKey: .data)
            ?? container.decodeIfPresent([Value].self, forKey: .dataUpper)
            ?? []
        total = try container.decodeIfPresent(Int.self, forKey: .total)
            ?? container.decodeIfPresent(Int.self, forKey: .totalUpper)
            ?? items.count
        page = try container.decodeIfPresent(Int.self, forKey: .page)
            ?? container.decodeIfPresent(Int.self, forKey: .pageUpper)
            ?? 1
        pageSize = try container.decodeIfPresent(Int.self, forKey: .pageSize)
            ?? container.decodeIfPresent(Int.self, forKey: .pageSizeLower)
            ?? items.count
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .data)
        try container.encode(total, forKey: .total)
        try container.encode(page, forKey: .page)
        try container.encode(pageSize, forKey: .pageSize)
    }
}

extension PageResponse: Sendable where Value: Sendable {}

enum StyleTemplateMarketRegion: String, CaseIterable, Identifiable {
    case china = "CN"
    case global = "GLOBAL"

    var id: String { rawValue }

    static var current: StyleTemplateMarketRegion {
        resolve(languageIdentifier: AISLocalization.languageIdentifier)
    }

    static func resolve(languageIdentifier: String) -> StyleTemplateMarketRegion {
        AISLocalization.isChinese(languageIdentifier: languageIdentifier)
            ? .china
            : .global
    }
}

struct StyleTemplate: Codable, Identifiable, Hashable {
    let id: String
    let templateKey: String
    let templateType: String
    let nameZh: String
    let nameEn: String
    let descriptionZh: String?
    let descriptionEn: String?
    let resolvedName: String?
    let resolvedDescription: String?
    let publishRegions: [String]
    let coverAssetURL: String?
    let sampleAssetURL: String?
    let aspectRatios: [String]
    let defaultAspectRatio: String?
    let resolutions: [String]
    let defaultResolution: String?
    let requiredMembershipCode: String?
    let defaultDisplayModelKey: String?
    let defaultModelReasonZh: String?
    let defaultModelReasonEn: String?
    let allowUserOverrideModel: Bool
    let fallbackDisplayModelKey: String?
    let basePointCost: Int
    let usageCount: Int
    let imageSlots: [StyleTemplateImageSlot]
    let textFields: [StyleTemplateTextField]
    let attributes: [StyleTemplateAttribute]

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case templateKey = "TemplateKey"
        case templateType = "TemplateType"
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case descriptionZh = "DescriptionZh"
        case descriptionEn = "DescriptionEn"
        case resolvedName = "Name"
        case resolvedDescription = "Description"
        case publishRegions = "PublishRegions"
        case coverAssetURL = "CoverAssetUrl"
        case sampleAssetURL = "SampleAssetUrl"
        case aspectRatios = "AspectRatios"
        case defaultAspectRatio = "DefaultAspectRatio"
        case resolutions = "Resolutions"
        case defaultResolution = "DefaultResolution"
        case requiredMembershipCode = "RequiredMembershipCode"
        case defaultDisplayModelKey = "DefaultDisplayModelKey"
        case defaultModelReasonZh = "DefaultModelReasonZh"
        case defaultModelReasonEn = "DefaultModelReasonEn"
        case allowUserOverrideModel = "AllowUserOverrideModel"
        case fallbackDisplayModelKey = "FallbackDisplayModelKey"
        case basePointCost = "BasePointCost"
        case usageCount = "UsageCount"
        case imageSlots = "ImageSlots"
        case textFields = "TextFields"
        case attributes = "Attributes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        templateKey = try container.decodeIfPresent(String.self, forKey: .templateKey) ?? id
        templateType = try container.decodeIfPresent(String.self, forKey: .templateType) ?? "image"
        nameZh = try container.decodeIfPresent(String.self, forKey: .nameZh) ?? ""
        nameEn = try container.decodeIfPresent(String.self, forKey: .nameEn) ?? nameZh
        descriptionZh = try container.decodeIfPresent(String.self, forKey: .descriptionZh)
        descriptionEn = try container.decodeIfPresent(String.self, forKey: .descriptionEn)
        resolvedName = try container.decodeIfPresent(String.self, forKey: .resolvedName)
        resolvedDescription = try container.decodeIfPresent(String.self, forKey: .resolvedDescription)
        publishRegions = try container.decodeIfPresent(
            [String].self,
            forKey: .publishRegions
        ) ?? ["CN"]
        coverAssetURL = try container.decodeIfPresent(String.self, forKey: .coverAssetURL)
        sampleAssetURL = try container.decodeIfPresent(String.self, forKey: .sampleAssetURL)
        aspectRatios = try container.decodeIfPresent(
            [String].self,
            forKey: .aspectRatios
        ) ?? []
        defaultAspectRatio = try container.decodeIfPresent(
            String.self,
            forKey: .defaultAspectRatio
        )
        resolutions = try container.decodeIfPresent(
            [String].self,
            forKey: .resolutions
        ) ?? []
        defaultResolution = try container.decodeIfPresent(
            String.self,
            forKey: .defaultResolution
        )
        requiredMembershipCode = try container.decodeIfPresent(
            String.self,
            forKey: .requiredMembershipCode
        )
        defaultDisplayModelKey = try container.decodeIfPresent(
            String.self,
            forKey: .defaultDisplayModelKey
        )
        defaultModelReasonZh = try container.decodeIfPresent(
            String.self,
            forKey: .defaultModelReasonZh
        )
        defaultModelReasonEn = try container.decodeIfPresent(
            String.self,
            forKey: .defaultModelReasonEn
        )
        allowUserOverrideModel = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowUserOverrideModel
        ) ?? true
        fallbackDisplayModelKey = try container.decodeIfPresent(
            String.self,
            forKey: .fallbackDisplayModelKey
        )
        basePointCost = try container.decodeIfPresent(Int.self, forKey: .basePointCost) ?? 0
        usageCount = try container.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
        imageSlots = try container.decodeIfPresent(
            [StyleTemplateImageSlot].self,
            forKey: .imageSlots
        ) ?? []
        textFields = try container.decodeIfPresent(
            [StyleTemplateTextField].self,
            forKey: .textFields
        ) ?? []
        attributes = try container.decodeIfPresent(
            [StyleTemplateAttribute].self,
            forKey: .attributes
        ) ?? []
    }

    var localizedName: String {
        if let resolvedName, !resolvedName.isEmpty { return resolvedName }
        return AISLocalization.value(zh: nameZh, en: nameEn)
    }

    var localizedDescription: String? {
        if let resolvedDescription, !resolvedDescription.isEmpty { return resolvedDescription }
        return AISLocalization.optional(
            zh: descriptionZh,
            en: descriptionEn
        )
    }

    var imageURL: URL? {
        let value = coverAssetURL ?? sampleAssetURL
        guard let value, !value.isEmpty else { return nil }
        if let absoluteURL = URL(string: value), absoluteURL.scheme != nil {
            return absoluteURL
        }
        return URL(string: value, relativeTo: AppEnvironment.current.apiBaseURL)?.absoluteURL
    }

    var displayAspectRatio: CGFloat {
        let value = defaultAspectRatio ?? aspectRatios.first ?? "4:5"
        let components = value.split(separator: ":")
        guard components.count == 2,
              let width = Double(components[0]),
              let height = Double(components[1]),
              width > 0,
              height > 0 else {
            return 4 / 5
        }
        return CGFloat(width / height)
    }

    func validationIssues(
        filledSlotKeys: Set<String>,
        textValues: [String: String]
    ) -> [StyleTemplateValidationIssue] {
        var issues: [StyleTemplateValidationIssue] = imageSlots.compactMap { slot in
            slot.required && !filledSlotKeys.contains(slot.slotKey)
                ? StyleTemplateValidationIssue.requiredSlot(slot.slotKey)
                : nil
        }
        for field in textFields where field.enabled {
            let value = textValues[field.fieldKey, default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if field.isRequired && value.isEmpty {
                issues.append(.requiredText(field.fieldKey))
            } else if value.count > field.maxLength {
                issues.append(
                    .textTooLong(field.fieldKey, maximum: field.maxLength)
                )
            }
        }
        return issues
    }
}

enum StyleTemplateValidationIssue: Equatable {
    case requiredSlot(String)
    case requiredText(String)
    case textTooLong(String, maximum: Int)
}

struct StyleTemplateImageSlot: Codable, Identifiable, Hashable {
    var id: String { slotKey }
    let slotKey: String
    let nameZh: String
    let nameEn: String?
    let descriptionZh: String?
    let descriptionEn: String?
    let required: Bool
    let sort: Int

    private enum CodingKeys: String, CodingKey {
        case slotKey = "SlotKey"
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case descriptionZh = "DescriptionZh"
        case descriptionEn = "DescriptionEn"
        case required = "Required"
        case sort = "Sort"
    }

    var localizedName: String {
        AISLocalization.value(zh: nameZh, en: nameEn)
    }

    var localizedDescription: String? {
        AISLocalization.optional(zh: descriptionZh, en: descriptionEn)
    }
}

struct StyleTemplateTextField: Codable, Identifiable, Hashable {
    var id: String { fieldKey }
    let fieldKey: String
    let fieldType: String
    let nameZh: String
    let nameEn: String
    let placeholderZh: String?
    let placeholderEn: String?
    let isRequired: Bool
    let maxLength: Int
    let defaultValue: String?
    let sort: Int
    let enabled: Bool
    let regionX: Double?
    let regionY: Double?
    let regionWidth: Double?
    let regionHeight: Double?

    private enum CodingKeys: String, CodingKey {
        case fieldKey = "FieldKey"
        case fieldType = "FieldType"
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case placeholderZh = "PlaceholderZh"
        case placeholderEn = "PlaceholderEn"
        case isRequired = "IsRequired"
        case maxLength = "MaxLength"
        case defaultValue = "DefaultValue"
        case sort = "Sort"
        case enabled = "Enabled"
        case regionX = "RegionX"
        case regionY = "RegionY"
        case regionWidth = "RegionWidth"
        case regionHeight = "RegionHeight"
    }

    var localizedName: String {
        AISLocalization.value(zh: nameZh, en: nameEn)
    }

    var localizedPlaceholder: String {
        AISLocalization.value(zh: placeholderZh, en: placeholderEn)
    }

    var hasRegion: Bool {
        guard let regionX, let regionY, let regionWidth, let regionHeight else {
            return false
        }
        return regionX >= 0 && regionY >= 0
            && regionWidth > 0 && regionHeight > 0
    }
}

struct StyleTemplateAttribute: Codable, Identifiable, Hashable {
    var id: String { "\(groupKey):\(itemKey)" }
    let groupKey: String
    let itemKey: String
    let nameZh: String?
    let nameEn: String?
    let sort: Int?

    private enum CodingKeys: String, CodingKey {
        case groupKey = "GroupKey"
        case itemKey = "ItemKey"
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case sort = "Sort"
    }
}

struct StyleTemplateApplyRequest: Encodable {
    let sourceAssetId: String?
    let referenceAssetIds: [String]
    let textValues: [String: String]
    let entry: String
    let language: String
    let aspectRatio: String
    let resolution: String
    let additionalRequirement: String
    let recommendToGallery: Bool
    let promoMarkEnabled: Bool
    let selectedDisplayModelKey: String?
    let clientSnapshot: StyleTemplateClientSnapshot?
    var pricingRulesVersion: String? = nil
    var localCalculatedPoints: Int? = nil
}

struct StyleTemplateClientSnapshot: Encodable {
    let templateKey: String
    let templateName: String
    let imageSlots: [StyleTemplateSlotSnapshot]
    let textValues: [String: String]
    let selectedAspectRatio: String
    let selectedResolution: String
    let additionalRequirement: String
    let recommendToGallery: Bool
    let promoMarkEnabled: Bool
    let selectedDisplayModelKey: String?
}

struct StyleTemplateSlotSnapshot: Encodable {
    let slotKey: String
    let slotIndex: Int
    let name: String
    let description: String?
    let assetId: String
}

struct StyleTemplatePointQuote: Decodable {
    let points: Int
    let originalPoints: Int
    let savedPoints: Int
    let effectiveDiscountPercent: Decimal?
    let effectiveBenefitName: String?
    let effectiveBenefitSource: String?
    let discountPolicy: String?
    let promoMarkEnabled: Bool?
    let promoMarkSuppressedReason: String?

    private enum CodingKeys: String, CodingKey {
        case points
        case pointsUpper = "Points"
        case originalPoints
        case originalPointsUpper = "OriginalPoints"
        case savedPoints
        case savedPointsUpper = "SavedPoints"
        case effectiveDiscountPercent
        case effectiveDiscountPercentUpper = "EffectiveDiscountPercent"
        case effectiveBenefitName
        case effectiveBenefitNameUpper = "EffectiveBenefitName"
        case effectiveBenefitSource
        case effectiveBenefitSourceUpper = "EffectiveBenefitSource"
        case discountPolicy
        case discountPolicyUpper = "DiscountPolicy"
        case promoMarkEnabled
        case promoMarkEnabledUpper = "PromoMarkEnabled"
        case promoMarkSuppressedReason
        case promoMarkSuppressedReasonUpper = "PromoMarkSuppressedReason"
    }

    init(
        points: Int,
        originalPoints: Int,
        savedPoints: Int,
        effectiveDiscountPercent: Decimal? = nil,
        effectiveBenefitName: String? = nil,
        effectiveBenefitSource: String? = nil,
        discountPolicy: String? = nil,
        promoMarkEnabled: Bool? = nil,
        promoMarkSuppressedReason: String? = nil
    ) {
        self.points = points
        self.originalPoints = originalPoints
        self.savedPoints = savedPoints
        self.effectiveDiscountPercent = effectiveDiscountPercent
        self.effectiveBenefitName = effectiveBenefitName
        self.effectiveBenefitSource = effectiveBenefitSource
        self.discountPolicy = discountPolicy
        self.promoMarkEnabled = promoMarkEnabled
        self.promoMarkSuppressedReason = promoMarkSuppressedReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = try container.decodeIfPresent(Int.self, forKey: .points)
            ?? container.decode(Int.self, forKey: .pointsUpper)
        originalPoints = try container.decodeIfPresent(Int.self, forKey: .originalPoints)
            ?? container.decodeIfPresent(Int.self, forKey: .originalPointsUpper)
            ?? points
        savedPoints = try container.decodeIfPresent(Int.self, forKey: .savedPoints)
            ?? container.decodeIfPresent(Int.self, forKey: .savedPointsUpper)
            ?? 0
        effectiveDiscountPercent = try container.decodeIfPresent(Decimal.self, forKey: .effectiveDiscountPercent)
            ?? container.decodeIfPresent(Decimal.self, forKey: .effectiveDiscountPercentUpper)
        effectiveBenefitName = try container.decodeIfPresent(String.self, forKey: .effectiveBenefitName)
            ?? container.decodeIfPresent(String.self, forKey: .effectiveBenefitNameUpper)
        effectiveBenefitSource = try container.decodeIfPresent(String.self, forKey: .effectiveBenefitSource)
            ?? container.decodeIfPresent(String.self, forKey: .effectiveBenefitSourceUpper)
        discountPolicy = try container.decodeIfPresent(String.self, forKey: .discountPolicy)
            ?? container.decodeIfPresent(String.self, forKey: .discountPolicyUpper)
        promoMarkEnabled = try container.decodeIfPresent(Bool.self, forKey: .promoMarkEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .promoMarkEnabledUpper)
        promoMarkSuppressedReason = try container.decodeIfPresent(String.self, forKey: .promoMarkSuppressedReason)
            ?? container.decodeIfPresent(String.self, forKey: .promoMarkSuppressedReasonUpper)
    }
}

struct StyleTemplateGenerationResult: Decodable {
    let jobId: String
    let status: String
    let pointCost: Int
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case jobId
        case jobIdUpper = "JobId"
        case status
        case statusUpper = "Status"
        case pointCost
        case pointCostUpper = "PointCost"
        case message
        case messageUpper = "Message"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decodeIfPresent(String.self, forKey: .jobId)
            ?? container.decode(String.self, forKey: .jobIdUpper)
        status = try container.decodeIfPresent(String.self, forKey: .status)
            ?? container.decodeIfPresent(String.self, forKey: .statusUpper)
            ?? "queued"
        pointCost = try container.decodeIfPresent(Int.self, forKey: .pointCost)
            ?? container.decodeIfPresent(Int.self, forKey: .pointCostUpper)
            ?? 0
        message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .messageUpper)
    }
}

enum AISCreationKind: String, Hashable {
    case image
    case imageEdit
    case video
    case template
    case other

    init(jobType: String) {
        switch jobType.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased() {
        case "image_generate", "image":
            self = .image
        case "image_edit":
            self = .imageEdit
        case "video_generate", "video":
            self = .video
        case "style_template_generate":
            self = .template
        default:
            self = .other
        }
    }
}

struct GalleryJob: Codable, Identifiable, Hashable {
    let id: String
    let jobType: String
    let title: String
    let description: String
    let userRequirement: String
    let rawStyleTemplateID: String?
    let inputJSON: String?
    let clientSnapshotJSON: String?
    let outputJSON: String?
    let resultAssetId: String?
    let resultURLString: String?
    let posterURLString: String?
    let rawAspectRatio: String?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let pointCost: Int
    let displayModelKey: String?
    let createTime: String?
    let startedAt: Date?
    let finishedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case jobType = "JobType"
        case title = "Title"
        case description = "Description"
        case userRequirement = "UserRequirement"
        case rawStyleTemplateID = "StyleTemplateId"
        case inputJSON = "InputJson"
        case clientSnapshotJSON = "ClientSnapshotJson"
        case outputJSON = "OutputJson"
        case resultAssetId = "ResultAssetId"
        case resultURLString = "ResultUrl"
        case posterURLString = "PosterUrl"
        case rawAspectRatio = "AspectRatio"
        case pixelWidth = "PixelWidth"
        case pixelHeight = "PixelHeight"
        case pointCost = "PointCost"
        case displayModelKey = "DisplayModelKey"
        case createTime = "CreateTime"
        case startedAt = "StartedAt"
        case finishedAt = "FinishedAt"
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case title = "GalleryTitle"
        case description = "GalleryDescription"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(
            keyedBy: LegacyCodingKeys.self
        )
        id = try container.decodeFlexibleString(forKey: .id) ?? UUID().uuidString
        jobType = try container.decodeIfPresent(String.self, forKey: .jobType) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? legacyContainer.decodeIfPresent(String.self, forKey: .title)
            ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description)
            ?? legacyContainer.decodeIfPresent(String.self, forKey: .description)
            ?? ""
        userRequirement = try container.decodeIfPresent(
            String.self,
            forKey: .userRequirement
        ) ?? ""
        rawStyleTemplateID = try container.decodeFlexibleString(
            forKey: .rawStyleTemplateID
        )
        inputJSON = try container.decodeIfPresent(String.self, forKey: .inputJSON)
        clientSnapshotJSON = try container.decodeIfPresent(
            String.self,
            forKey: .clientSnapshotJSON
        )
        outputJSON = try container.decodeIfPresent(String.self, forKey: .outputJSON)
        resultAssetId = try container.decodeFlexibleString(forKey: .resultAssetId)
        resultURLString = try container.decodeIfPresent(
            String.self,
            forKey: .resultURLString
        )
        posterURLString = try container.decodeIfPresent(
            String.self,
            forKey: .posterURLString
        )
        rawAspectRatio = try container.decodeIfPresent(
            String.self,
            forKey: .rawAspectRatio
        )
        pixelWidth = try container.decodeIfPresent(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decodeIfPresent(Int.self, forKey: .pixelHeight)
        pointCost = try container.decodeIfPresent(Int.self, forKey: .pointCost) ?? 0
        displayModelKey = try container.decodeIfPresent(
            String.self,
            forKey: .displayModelKey
        )
        createTime = try container.decodeIfPresent(String.self, forKey: .createTime)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
    }

    var creationKind: AISCreationKind {
        AISCreationKind(jobType: jobType)
    }

    var videoURL: URL? {
        guard creationKind == .video else { return nil }
        if let resultURLString,
           let url = resolvedAISURL(resultURLString) {
            return url
        }
        if let url = outputURL(
            keys: [
                "resultUrl", "ResultUrl", "videoUrl", "VideoUrl",
                "fileUrl", "FileUrl"
            ]
        ) {
            return url
        }
        return nil
    }

    var posterURL: URL? {
        if let posterURLString,
           let url = resolvedAISURL(posterURLString) {
            return url
        }
        return outputURL(
            keys: [
                "posterUrl", "PosterUrl", "generatedImageUrl",
                "GeneratedImageUrl"
            ]
        )
    }

    var mediaURL: URL? {
        if creationKind == .video {
            return posterURL
        }
        if let resultURLString,
           let url = resolvedAISURL(resultURLString) {
            return url
        }
        if let url = outputURL(
            keys: [
                "fileUrl", "FileUrl", "resultUrl", "ResultUrl",
                "generatedImageUrl", "GeneratedImageUrl",
                "posterUrl", "PosterUrl"
            ]
        ) {
            return url
        }
        return nil
    }

    var hasDisplayableMedia: Bool {
        mediaURL != nil || videoURL != nil
    }

    private func outputURL(keys: [String]) -> URL? {
        guard let outputJSON,
              let data = outputJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        for key in keys {
            if let value = dictionary[key] as? String,
               let url = resolvedAISURL(value) {
                return url
            }
        }
        return nil
    }

    var mediaAspectRatio: CGFloat? {
        if let pixelWidth,
           let pixelHeight,
           pixelWidth > 0,
           pixelHeight > 0 {
            return CGFloat(pixelWidth) / CGFloat(pixelHeight)
        }
        if let rawAspectRatio,
           let ratio = Self.aspectRatio(from: rawAspectRatio) {
            return ratio
        }
        for json in [outputJSON, inputJSON, clientSnapshotJSON].compactMap({ $0 }) {
            guard let object = Self.jsonObject(from: json) else { continue }
            if let ratio = Self.mediaAspectRatio(in: object) {
                return ratio
            }
        }
        return nil
    }

    var styleTemplateID: String? {
        if let rawStyleTemplateID,
           !rawStyleTemplateID.isEmpty {
            return rawStyleTemplateID
        }
        for json in [inputJSON, clientSnapshotJSON].compactMap({ $0 }) {
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any] else {
                continue
            }
            if let value = Self.templateID(in: object) {
                return value
            }
        }
        return nil
    }

    private static func templateID(in object: [String: Any]) -> String? {
        for key in [
            "styleTemplateId",
            "StyleTemplateId",
            "templateId",
            "TemplateId"
        ] {
            if let value = object[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
            if let value = object[key] as? NSNumber {
                return value.stringValue
            }
        }
        for key in [
            "clientSnapshot",
            "ClientSnapshot",
            "parameters",
            "Parameters"
        ] {
            if let nested = object[key] as? [String: Any],
               let value = templateID(in: nested) {
                return value
            }
        }
        return nil
    }

    private static func number(
        in object: [String: Any],
        keys: [String]
    ) -> Double {
        for key in keys {
            if let value = object[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = object[key] as? String,
               let number = Double(value) {
                return number
            }
        }
        return 0
    }

    private static func jsonObject(from value: String) -> [String: Any]? {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func mediaAspectRatio(
        in object: [String: Any]
    ) -> CGFloat? {
        let width = number(
            in: object,
            keys: [
                "width", "Width", "targetWidth", "TargetWidth",
                "sourceWidth", "SourceWidth", "contentWidth", "ContentWidth"
            ]
        )
        let height = number(
            in: object,
            keys: [
                "height", "Height", "targetHeight", "TargetHeight",
                "sourceHeight", "SourceHeight", "contentHeight", "ContentHeight"
            ]
        )
        if width > 0, height > 0 {
            return CGFloat(width / height)
        }

        for key in ["aspectRatio", "AspectRatio", "aspect_ratio"] {
            if let value = object[key] as? String,
               let ratio = aspectRatio(from: value) {
                return ratio
            }
        }

        // 图片归一化信息位于 OutputJson.outputSpec 等嵌套对象中，递归读取才能保留真实 Pin 高度。
        for value in object.values {
            if let nested = value as? [String: Any],
               let ratio = mediaAspectRatio(in: nested) {
                return ratio
            }
        }
        return nil
    }

    private static func aspectRatio(from value: String) -> CGFloat? {
        let parts = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width > 0,
              height > 0 else {
            return nil
        }
        return CGFloat(width / height)
    }
}

struct AISSharedJob: Decodable {
    let id: String
    let type: String
    let title: String
    let description: String
    let aspectRatio: String?
    let resolution: String?
    let pointCost: Int
    let fileSizeBytes: Int64?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let startedAt: Date?
    let finishedAt: Date?
    let mediaURL: URL?
    let posterURL: URL?
    let inputMaterials: [AISSharedInputMaterial]

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case type = "Type"
        case title = "Title"
        case description = "Description"
        case aspectRatio = "AspectRatio"
        case resolution = "Resolution"
        case pointCost = "PointCost"
        case fileSizeBytes = "FileSizeBytes"
        case pixelWidth = "PixelWidth"
        case pixelHeight = "PixelHeight"
        case startedAt = "StartedAt"
        case finishedAt = "FinishedAt"
        case mediaURL = "MediaUrl"
        case posterURL = "PosterUrl"
        case inputMaterials = "InputMaterials"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type)
            ?? "image"
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try container.decodeIfPresent(
            String.self,
            forKey: .description
        ) ?? ""
        aspectRatio = try container.decodeIfPresent(
            String.self,
            forKey: .aspectRatio
        )
        resolution = try container.decodeIfPresent(
            String.self,
            forKey: .resolution
        )
        pointCost = try container.decodeIfPresent(Int.self, forKey: .pointCost)
            ?? 0
        fileSizeBytes = try container.decodeIfPresent(
            Int64.self,
            forKey: .fileSizeBytes
        )
        pixelWidth = try container.decodeIfPresent(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decodeIfPresent(
            Int.self,
            forKey: .pixelHeight
        )
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        if let value = try container.decodeIfPresent(
            String.self,
            forKey: .mediaURL
        ) {
            mediaURL = resolvedAISURL(value)
        } else {
            mediaURL = nil
        }
        if let value = try container.decodeIfPresent(
            String.self,
            forKey: .posterURL
        ) {
            posterURL = resolvedAISURL(value)
        } else {
            posterURL = nil
        }
        inputMaterials = try container.decodeIfPresent(
            [AISSharedInputMaterial].self,
            forKey: .inputMaterials
        ) ?? []
    }

    var mediaKind: AISMediaKind {
        AISCreationKind(jobType: type) == .video ? .video : .image
    }

    var displayURL: URL? {
        mediaKind == .video ? posterURL : mediaURL
    }

    var publicMediaProxyURL: URL {
        AppEnvironment.current.apiBaseURL.appending(
            path: "/api/ais/jobs/shared/\(id)/media"
        )
    }
}

struct AISSharedInputMaterial: Decodable, Identifiable {
    let index: Int
    let url: URL?
    let available: Bool
    let kind: String

    var id: String { "\(kind):\(index)" }

    var galleryDisplayName: String {
        switch kind.lowercased() {
        case "source":
            String(localized: "gallery.detail.material.source")
        case "logo":
            "LOGO"
        case "edit_preview":
            String(localized: "gallery.detail.material.edit_preview")
        default:
            String(localized: "gallery.detail.material.reference")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case index = "Index"
        case url = "Url"
        case available = "Available"
        case kind = "Kind"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        if let value = try container.decodeIfPresent(String.self, forKey: .url) {
            url = resolvedAISURL(value)
        } else {
            url = nil
        }
        available = try container.decodeIfPresent(
            Bool.self,
            forKey: .available
        ) ?? false
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
            ?? "input"
    }
}

struct AISPointQuote: Decodable {
    let points: Int
    let originalPoints: Int?
    let savedPoints: Int?
    let effectiveDiscountPercent: Decimal?
    let effectiveBenefitName: String?
    let effectiveBenefitSource: String?
    let discountPolicy: String?
    let promoMarkEnabled: Bool?
    let promoMarkSuppressedReason: String?

    private enum CodingKeys: String, CodingKey {
        case points = "Points"
        case originalPoints = "OriginalPoints"
        case savedPoints = "SavedPoints"
        case effectiveDiscountPercent = "EffectiveDiscountPercent"
        case effectiveBenefitName = "EffectiveBenefitName"
        case effectiveBenefitSource = "EffectiveBenefitSource"
        case discountPolicy = "DiscountPolicy"
        case promoMarkEnabled = "PromoMarkEnabled"
        case promoMarkSuppressedReason = "PromoMarkSuppressedReason"
    }

    init(
        points: Int,
        originalPoints: Int,
        savedPoints: Int,
        effectiveDiscountPercent: Decimal? = nil,
        effectiveBenefitName: String? = nil,
        effectiveBenefitSource: String? = nil,
        discountPolicy: String? = nil,
        promoMarkEnabled: Bool? = nil,
        promoMarkSuppressedReason: String? = nil
    ) {
        self.points = points
        self.originalPoints = originalPoints
        self.savedPoints = savedPoints
        self.effectiveDiscountPercent = effectiveDiscountPercent
        self.effectiveBenefitName = effectiveBenefitName
        self.effectiveBenefitSource = effectiveBenefitSource
        self.discountPolicy = discountPolicy
        self.promoMarkEnabled = promoMarkEnabled
        self.promoMarkSuppressedReason = promoMarkSuppressedReason
    }

    init?(priceChangeDetails: JSONValue?) {
        guard case let .object(values) = priceChangeDetails,
              let points = values.integer(for: "points"),
              points > 0 else {
            return nil
        }
        let originalPoints = values.integer(for: "originalPoints") ?? points
        self.init(
            points: points,
            originalPoints: max(points, originalPoints),
            savedPoints: max(
                0,
                values.integer(for: "savedPoints")
                    ?? (originalPoints - points)
            )
        )
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func integer(for key: String) -> Int? {
        guard let value = first(where: {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        })?.value else {
            return nil
        }
        switch value {
        case let .number(number):
            return NSDecimalNumber(decimal: number).intValue
        case let .string(string):
            return Int(string)
        default:
            return nil
        }
    }
}

struct AISAssetUploadResult: Decodable {
    let id: String

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try container.decodeFlexibleString(forKey: .id) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "缺少素材 ID"
            )
        }
        self.id = id
    }
}

struct AISCreatedJob: Decodable {
    let id: String

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try container.decodeFlexibleString(forKey: .id) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "缺少任务 ID"
            )
        }
        self.id = id
    }
}

struct AISTaskJob: Codable, Identifiable, Hashable {
    let id: String
    let jobType: String
    var status: String
    var progress: Int
    let pointCost: Int
    let title: String
    let userRequirement: String
    let inputJSON: String?
    let clientSnapshotJSON: String?
    let outputJSON: String?
    var resultAssetId: String?
    var resultURL: String?
    var posterURL: String?
    let errorCode: String?
    var errorMessage: String?
    let createTime: String?
    var startedAt: String?
    var finishedAt: String?
    let aspectRatio: String?
    let resolution: String?
    let fileSizeBytes: Int64?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let generationDurationSeconds: Int64?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case idLower = "id"
        case jobType = "JobType"
        case jobTypeLower = "jobType"
        case status = "Status"
        case statusLower = "status"
        case progress = "Progress"
        case progressLower = "progress"
        case pointCost = "PointCost"
        case pointCostLower = "pointCost"
        case title = "GalleryTitle"
        case titleLower = "galleryTitle"
        case userRequirement = "UserRequirement"
        case userRequirementLower = "userRequirement"
        case inputJSON = "InputJson"
        case inputJSONLower = "inputJson"
        case clientSnapshotJSON = "ClientSnapshotJson"
        case clientSnapshotJSONLower = "clientSnapshotJson"
        case outputJSON = "OutputJson"
        case outputJSONLower = "outputJson"
        case resultAssetId = "DisplayResultAssetId"
        case resultAssetIdLower = "displayResultAssetId"
        case fallbackResultAssetId = "ResultAssetId"
        case fallbackResultAssetIdLower = "resultAssetId"
        case resultURL = "ResultUrl"
        case resultURLLower = "resultUrl"
        case posterURL = "PosterUrl"
        case posterURLLower = "posterUrl"
        case errorCode = "ErrorCode"
        case errorCodeLower = "errorCode"
        case errorMessage = "ErrorMessage"
        case errorMessageLower = "errorMessage"
        case createTime = "CreateTime"
        case createTimeLower = "createTime"
        case startedAt = "StartedAt"
        case startedAtLower = "startedAt"
        case finishedAt = "FinishedAt"
        case finishedAtLower = "finishedAt"
        case aspectRatio = "AspectRatio"
        case aspectRatioLower = "aspectRatio"
        case resolution = "Resolution"
        case resolutionLower = "resolution"
        case fileSizeBytes = "FileSizeBytes"
        case fileSizeBytesLower = "fileSizeBytes"
        case pixelWidth = "PixelWidth"
        case pixelWidthLower = "pixelWidth"
        case pixelHeight = "PixelHeight"
        case pixelHeightLower = "pixelHeight"
        case generationDurationSeconds = "GenerationDurationSeconds"
        case generationDurationSecondsLower = "generationDurationSeconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
            ?? container.decodeFlexibleString(forKey: .idLower)
            ?? UUID().uuidString
        jobType = try container.decodeIfPresent(String.self, forKey: .jobType)
            ?? container.decodeIfPresent(String.self, forKey: .jobTypeLower)
            ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status)
            ?? container.decodeIfPresent(String.self, forKey: .statusLower)
            ?? "queued"
        progress = min(
            100,
            max(
                0,
                try container.decodeIfPresent(Int.self, forKey: .progress)
                    ?? container.decodeIfPresent(Int.self, forKey: .progressLower)
                    ?? 0
            )
        )
        pointCost = try container.decodeIfPresent(Int.self, forKey: .pointCost)
            ?? container.decodeIfPresent(Int.self, forKey: .pointCostLower)
            ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .titleLower)
            ?? ""
        userRequirement = try container.decodeIfPresent(
            String.self,
            forKey: .userRequirement
        )
            ?? container.decodeIfPresent(
                String.self,
                forKey: .userRequirementLower
            )
            ?? ""
        inputJSON = try container.decodeIfPresent(String.self, forKey: .inputJSON)
            ?? container.decodeIfPresent(String.self, forKey: .inputJSONLower)
        clientSnapshotJSON = try container.decodeIfPresent(
            String.self,
            forKey: .clientSnapshotJSON
        )
            ?? container.decodeIfPresent(
                String.self,
                forKey: .clientSnapshotJSONLower
            )
        outputJSON = try container.decodeIfPresent(String.self, forKey: .outputJSON)
            ?? container.decodeIfPresent(String.self, forKey: .outputJSONLower)
        resultAssetId = try container.decodeFlexibleString(forKey: .resultAssetId)
            ?? container.decodeFlexibleString(forKey: .resultAssetIdLower)
            ?? container.decodeFlexibleString(forKey: .fallbackResultAssetId)
            ?? container.decodeFlexibleString(forKey: .fallbackResultAssetIdLower)
        resultURL = try container.decodeIfPresent(String.self, forKey: .resultURL)
            ?? container.decodeIfPresent(String.self, forKey: .resultURLLower)
        posterURL = try container.decodeIfPresent(String.self, forKey: .posterURL)
            ?? container.decodeIfPresent(String.self, forKey: .posterURLLower)
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
            ?? container.decodeIfPresent(String.self, forKey: .errorCodeLower)
        errorMessage = try container.decodeIfPresent(
            String.self,
            forKey: .errorMessage
        )
            ?? container.decodeIfPresent(
                String.self,
                forKey: .errorMessageLower
            )
        createTime = try container.decodeIfPresent(String.self, forKey: .createTime)
            ?? container.decodeIfPresent(String.self, forKey: .createTimeLower)
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
            ?? container.decodeIfPresent(String.self, forKey: .startedAtLower)
        finishedAt = try container.decodeIfPresent(String.self, forKey: .finishedAt)
            ?? container.decodeIfPresent(String.self, forKey: .finishedAtLower)
        aspectRatio = try container.decodeIfPresent(
            String.self,
            forKey: .aspectRatio
        )
            ?? container.decodeIfPresent(
                String.self,
                forKey: .aspectRatioLower
            )
        resolution = try container.decodeIfPresent(
            String.self,
            forKey: .resolution
        )
            ?? container.decodeIfPresent(
                String.self,
                forKey: .resolutionLower
            )
        fileSizeBytes = try container.decodeIfPresent(
            Int64.self,
            forKey: .fileSizeBytes
        )
            ?? container.decodeIfPresent(
                Int64.self,
                forKey: .fileSizeBytesLower
            )
        pixelWidth = try container.decodeIfPresent(
            Int.self,
            forKey: .pixelWidth
        )
            ?? container.decodeIfPresent(
                Int.self,
                forKey: .pixelWidthLower
            )
        pixelHeight = try container.decodeIfPresent(
            Int.self,
            forKey: .pixelHeight
        )
            ?? container.decodeIfPresent(
                Int.self,
                forKey: .pixelHeightLower
            )
        generationDurationSeconds = try container.decodeIfPresent(
            Int64.self,
            forKey: .generationDurationSeconds
        )
            ?? container.decodeIfPresent(
                Int64.self,
                forKey: .generationDurationSecondsLower
            )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(jobType, forKey: .jobType)
        try container.encode(status, forKey: .status)
        try container.encode(progress, forKey: .progress)
        try container.encode(pointCost, forKey: .pointCost)
        try container.encode(title, forKey: .title)
        try container.encode(userRequirement, forKey: .userRequirement)
        try container.encodeIfPresent(inputJSON, forKey: .inputJSON)
        try container.encodeIfPresent(
            clientSnapshotJSON,
            forKey: .clientSnapshotJSON
        )
        try container.encodeIfPresent(outputJSON, forKey: .outputJSON)
        try container.encodeIfPresent(resultAssetId, forKey: .resultAssetId)
        try container.encodeIfPresent(resultURL, forKey: .resultURL)
        try container.encodeIfPresent(posterURL, forKey: .posterURL)
        try container.encodeIfPresent(errorCode, forKey: .errorCode)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try container.encodeIfPresent(createTime, forKey: .createTime)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(finishedAt, forKey: .finishedAt)
        try container.encodeIfPresent(aspectRatio, forKey: .aspectRatio)
        try container.encodeIfPresent(resolution, forKey: .resolution)
        try container.encodeIfPresent(fileSizeBytes, forKey: .fileSizeBytes)
        try container.encodeIfPresent(pixelWidth, forKey: .pixelWidth)
        try container.encodeIfPresent(pixelHeight, forKey: .pixelHeight)
        try container.encodeIfPresent(
            generationDurationSeconds,
            forKey: .generationDurationSeconds
        )
    }

    var isActive: Bool {
        switch status.lowercased() {
        case "queued", "pending", "processing", "running":
            true
        default:
            false
        }
    }

    var isSuccessful: Bool {
        switch status.lowercased() {
        case "succeeded", "completed":
            true
        default:
            false
        }
    }

    var creationDate: Date? {
        Self.parsedDate(createTime)
    }

    var startedDate: Date? {
        Self.parsedDate(startedAt)
    }

    private static func parsedDate(_ rawValue: String?) -> Date? {
        guard let value = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        let hasExplicitTimeZone = value.hasSuffix("Z")
            || value.range(
                of: #"[+-]\d{2}:?\d{2}$"#,
                options: .regularExpression
            ) != nil
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if hasExplicitTimeZone,
           let date = fractional.date(from: value)
            ?? standard.date(from: value) {
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
            // 后端使用 DateTime.Now，未携带偏移量的时间应按服务端中国时区解释。
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    func isNewer(than other: AISTaskJob) -> Bool {
        if let creationDate, let otherDate = other.creationDate,
           creationDate != otherDate {
            return creationDate > otherDate
        }
        if id.count != other.id.count,
           id.allSatisfy(\.isNumber),
           other.id.allSatisfy(\.isNumber) {
            return id.count > other.id.count
        }
        return id > other.id
    }

    var formattedCreationTime: String {
        guard let creationDate else {
            return createTime?.nilIfEmpty
                ?? String(localized: "tasks.date.unknown")
        }
        return creationDate.formatted(
            date: .numeric,
            time: .shortened
        )
    }

    var creationKind: AISCreationKind {
        AISCreationKind(jobType: jobType)
    }

    var resultMediaURL: URL? {
        if let resultURL,
           let url = resolvedAISURL(resultURL) {
            return url
        }
        let keys = creationKind == .video
            ? [
                "videoUrl", "VideoUrl", "resultUrl", "ResultUrl",
                "fileUrl", "FileUrl"
            ]
            : [
                "fileUrl", "FileUrl", "resultUrl", "ResultUrl",
                "generatedImageUrl", "GeneratedImageUrl"
            ]
        if let url = outputURL(keys: keys) {
            return url
        }
        return nil
    }

    var posterMediaURL: URL? {
        if let posterURL,
           let url = resolvedAISURL(posterURL) {
            return url
        }
        return outputURL(
            keys: [
                "posterUrl", "PosterUrl", "generatedImageUrl",
                "GeneratedImageUrl"
            ]
        )
    }

    var mediaURL: URL? {
        creationKind == .video ? posterMediaURL : resultMediaURL
    }

    private func outputURL(keys: [String]) -> URL? {
        guard let outputJSON,
              let data = outputJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        for key in keys {
            if let value = dictionary[key] as? String,
               let url = resolvedAISURL(value) {
                return url
            }
        }
        return nil
    }

    var inputMaterialURLs: [URL] {
        let values = [inputJSON, clientSnapshotJSON].compactMap { $0 }
        var urls: [URL] = []
        for value in values {
            guard let data = value.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            Self.collectImageURLs(from: object, into: &urls)
        }
        return Array(urls.uniqued().prefix(3))
    }

    private static func collectImageURLs(from value: Any, into urls: inout [URL]) {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let normalizedKey = key.lowercased()
                if let string = child as? String,
                   normalizedKey.contains("url"),
                   let url = resolvedAISURL(string),
                   ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    urls.append(url)
                } else {
                    collectImageURLs(from: child, into: &urls)
                }
            }
        } else if let array = value as? [Any] {
            array.forEach { collectImageURLs(from: $0, into: &urls) }
        }
    }
}

struct AISTaskStatusSnapshot: Codable {
    let jobID: String
    let status: String
    let progress: Int
    let resultAssetID: String?
    let resultURL: String?
    let errorMessage: String?
    let startedAt: String?
    let finishedAt: String?

    private enum CodingKeys: String, CodingKey {
        case jobID = "JobId"
        case status = "Status"
        case progress = "Progress"
        case resultAssetID = "ResultAssetId"
        case resultURL = "ResultUrl"
        case errorMessage = "ErrorMessage"
        case startedAt = "StartedAt"
        case finishedAt = "FinishedAt"
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private func resolvedAISURL(_ value: String) -> URL? {
    guard !value.isEmpty else { return nil }
    if let url = URL(string: value), url.scheme != nil {
        return url
    }
    return URL(
        string: value,
        relativeTo: AppEnvironment.current.apiBaseURL
    )?.absoluteURL
}

extension KeyedDecodingContainer {
    func decodeFlexibleString(
        forKey key: Key
    ) throws -> String? {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int64.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

struct AuthResult: Decodable {
    let user: AuthUser
    let token: AuthToken

    private enum CodingKeys: String, CodingKey {
        case user = "User"
        case userLower = "user"
        case token = "Token"
        case tokenLower = "token"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decodeIfPresent(AuthUser.self, forKey: .user)
            ?? container.decode(AuthUser.self, forKey: .userLower)
        token = try container.decodeIfPresent(AuthToken.self, forKey: .token)
            ?? container.decode(AuthToken.self, forKey: .tokenLower)
    }
}

struct AuthUser: Codable, Sendable {
    let id: String
    let email: String?
    let displayName: String?
    let countryCode: String?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case idLower = "id"
        case email = "Email"
        case emailLower = "email"
        case displayName = "DisplayName"
        case displayNameLower = "displayName"
        case realName = "RealName"
        case countryCode = "CountryCode"
        case countryCodeLower = "countryCode"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .idLower)
        email = try container.decodeIfPresent(String.self, forKey: .email)
            ?? container.decodeIfPresent(String.self, forKey: .emailLower)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .displayNameLower)
            ?? container.decodeIfPresent(String.self, forKey: .realName)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
            ?? container.decodeIfPresent(String.self, forKey: .countryCodeLower)
    }

    init(id: String, email: String?, displayName: String?, countryCode: String?) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.countryCode = countryCode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .idLower)
        try container.encodeIfPresent(email, forKey: .emailLower)
        try container.encodeIfPresent(displayName, forKey: .displayNameLower)
        try container.encodeIfPresent(countryCode, forKey: .countryCodeLower)
    }
}

struct AuthToken: Decodable {
    let accessToken: String
    let refreshToken: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "token"
        case accessTokenUpper = "Token"
        case refreshToken = "refreshToken"
        case refreshTokenUpper = "RefreshToken"
        case refreshTokenSnake = "refresh_token"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
            ?? container.decode(String.self, forKey: .accessTokenUpper)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
            ?? container.decodeIfPresent(String.self, forKey: .refreshTokenUpper)
            ?? container.decodeIfPresent(String.self, forKey: .refreshTokenSnake)
    }
}

struct AppleNativeLoginRequest: Encodable {
    let identityToken: String
    let authorizationCode: String
    let nonce: String
    let givenName: String?
    let familyName: String?
    let email: String?
    let locale: String
    let countryCode: String?
}

struct AppleBindingStatus: Decodable, Equatable, Sendable {
    let isBound: Bool
    let email: String?

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
