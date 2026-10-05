import Foundation
import Observation

struct AISPromptAttributeSettings: Codable {
    let mediaType: String
    let groups: [AISPromptAttributeGroup]
    let modelOutputSpecs: [AISModelOutputSpec]
    let effectiveMembershipLevel: String?
    let version: String?

    private enum CodingKeys: String, CodingKey {
        case mediaType = "MediaType"
        case groups = "Groups"
        case modelOutputSpecs = "ModelOutputSpecs"
        case effectiveMembershipLevel = "EffectiveMembershipLevel"
        case version = "Version"
    }
}

struct AISPromptAttributeGroup: Codable, Identifiable, Hashable {
    let id: String
    let mediaType: String
    let nameZh: String
    let nameEn: String
    let type: String
    let maxSelected: Int
    let sort: Int
    let items: [AISPromptAttributeItem]

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case mediaType = "MediaType"
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case type = "Type"
        case maxSelected = "MaxSelected"
        case sort = "Sort"
        case items = "Items"
    }

    var localizedName: String {
        AISLocalization.value(zh: nameZh, en: nameEn)
    }
}

struct AISPromptAttributeItem: Codable, Identifiable, Hashable {
    let id: String
    let nameZh: String
    let nameEn: String
    let descriptionZh: String?
    let descriptionEn: String?
    let sort: Int
    let multiplier: Decimal
    let requiredMembershipCode: String?
    let requiredMembershipName: String?
    let isAvailable: Bool

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case descriptionZh = "DescriptionZh"
        case descriptionEn = "DescriptionEn"
        case sort = "Sort"
        case multiplier = "Multiplier"
        case requiredMembershipCode = "RequiredMembershipCode"
        case requiredMembershipName = "RequiredMembershipName"
        case isAvailable = "IsAvailable"
    }

    var localizedName: String {
        AISLocalization.value(zh: nameZh, en: nameEn)
    }

    var localizedDescription: String? {
        AISLocalization.optional(zh: descriptionZh, en: descriptionEn)
    }

    var membershipLabel: String? {
        AISMembershipLabelFormatter.availabilityLabel(
            code: requiredMembershipCode,
            configuredName: requiredMembershipName
        )
    }
}

enum AISVisualPresetMapper {
    static func presets(
        from settings: AISPromptAttributeSettings,
        groupID: String
    ) -> [AISVisualPreset] {
        guard let group = settings.groups.first(where: {
            $0.id.caseInsensitiveCompare(groupID) == .orderedSame
        }) else {
            return []
        }

        return group.items
            .filter(\.isAvailable)
            .sorted {
                if $0.sort == $1.sort {
                    return $0.id < $1.id
                }
                return $0.sort < $1.sort
            }
            .map {
                AISVisualPreset(
                    id: $0.id,
                    nameZh: $0.nameZh,
                    nameEn: $0.nameEn,
                    descriptionZh: $0.descriptionZh,
                    descriptionEn: $0.descriptionEn,
                    sort: $0.sort
                )
            }
    }
}

struct AISModelOutputSpec: Codable, Identifiable, Hashable {
    var id: String { "\(specType):\(value)" }
    let provider: String
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
        case provider = "Provider"
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

    var localizedName: String {
        let configured = AISLocalization.value(zh: nameZh, en: nameEn)
        return configured.isEmpty ? value : configured
    }

    var membershipLabel: String? {
        AISMembershipLabelFormatter.availabilityLabel(
            code: requiredMembershipCode,
            configuredName: requiredMembershipName
        )
    }
}

enum AISMembershipLabelFormatter {
    static func displayName(
        code: String?,
        configuredName: String?
    ) -> String? {
        let normalizedCode = code?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let configured = configuredName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let knownNamesZh = [
            "normal": "普通用户",
            "student": "学生",
            "vip": "VIP",
            "plus": "Plus",
            "pro": "Pro",
            "max": "Max",
            "enterprise": "企业"
        ]
        let knownNamesEn = [
            "normal": "Standard",
            "student": "Student",
            "vip": "VIP",
            "plus": "Plus",
            "pro": "Pro",
            "max": "Max",
            "enterprise": "Enterprise"
        ]
        let knownName = normalizedCode.flatMap {
            (AISLocalization.isChinese ? knownNamesZh : knownNamesEn)[$0]
        }
        let name = knownName
            ?? configured?.nilIfEmpty
            ?? normalizedCode?.nilIfEmpty
        return name
    }

    static func availabilityLabel(
        code: String?,
        configuredName: String?
    ) -> String? {
        guard let name = displayName(
            code: code,
            configuredName: configuredName
        ) else {
            return nil
        }
        return String.localizedStringWithFormat(
            String(localized: "creation.membership.available"),
            name
        )
    }
}

struct AISAssetLibraryItem: Codable, Identifiable, Hashable {
    let id: String
    let fileURL: String?
    let title: String
    let displayName: String?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case fileURL = "FileUrl"
        case title = "Title"
        case displayName = "DisplayName"
        case description = "Description"
    }

    var resolvedURL: URL? {
        guard let fileURL, !fileURL.isEmpty else { return nil }
        if let url = URL(string: fileURL), url.scheme != nil {
            return url
        }
        return URL(
            string: fileURL,
            relativeTo: AppEnvironment.current.apiBaseURL
        )?.absoluteURL
    }

    var resolvedName: String {
        let value = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : title
    }
}

enum AISLocalization {
    static var languageIdentifier: String {
        Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
    }

    static var isChinese: Bool {
        isChinese(languageIdentifier: languageIdentifier)
    }

    static var apiValue: String {
        apiValue(languageIdentifier: languageIdentifier)
    }

    static func isChinese(languageIdentifier: String) -> Bool {
        Locale(identifier: languageIdentifier)
            .language.languageCode?.identifier == "zh"
    }

    static func apiValue(languageIdentifier: String) -> String {
        isChinese(languageIdentifier: languageIdentifier) ? "zh-CN" : "en-US"
    }

    static func value(zh: String?, en: String?) -> String {
        let primary = isChinese ? zh : en
        let fallback = isChinese ? en : zh
        return primary?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? fallback?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            ?? ""
    }

    static func optional(zh: String?, en: String?) -> String? {
        value(zh: zh, en: en).nilIfEmpty
    }
}

@MainActor
@Observable
final class AISCreationConfigurationStore {
    private let api = APIClient()

    private(set) var promptSettings: AISPromptAttributeSettings?
    private(set) var visualPresets = AISVisualPresetOptions(
        directions: [],
        effects: []
    )
    private(set) var models: [AISGenerationModelOption] = []
    private(set) var isLoading = false
    private(set) var hasFreshConfiguration = false
    var errorMessage: String?

    var attributeGroups: [AISPromptAttributeGroup] {
        (promptSettings?.groups ?? [])
            .filter { $0.mediaType.lowercased() == "image" }
            .filter { $0.id != "reference_role" }
            .sorted { $0.sort < $1.sort }
    }

    var effectSelectionLimit: Int {
        Self.resolveEffectSelectionLimit(in: attributeGroups)
    }

    static func resolveEffectSelectionLimit(
        in groups: [AISPromptAttributeGroup]
    ) -> Int {
        guard let configured = groups.first(where: {
            $0.id.lowercased() == "effect"
        })?.maxSelected else {
            return 3
        }
        return min(20, max(1, configured))
    }

    func specs(_ type: String) -> [AISModelOutputSpec] {
        (promptSettings?.modelOutputSpecs ?? [])
            .filter {
                $0.mediaType.lowercased() == "image"
                    && $0.specType.lowercased() == type.lowercased()
            }
            .sorted { $0.sort < $1.sort }
    }

    var canSubmit: Bool {
        hasFreshConfiguration
            && !specs("aspect_ratio").isEmpty
            && !specs("resolution").isEmpty
    }

    func reset() {
        promptSettings = nil
        visualPresets = AISVisualPresetOptions(
            directions: [],
            effects: []
        )
        models = []
        isLoading = false
        hasFreshConfiguration = false
        errorMessage = nil
    }

    func load(
        userID: String?,
        accessToken: String?,
        templateID: String? = nil,
        force: Bool = false
    ) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let scope = "user:\(userID ?? "guest")"
        let promptKey = AISResponseCache.key(
            scope: scope,
            resource: "prompt-attributes-image"
        )
        let visualKey = AISResponseCache.key(
            scope: "public",
            resource: "visual-presets"
        )
        let modelKey = AISResponseCache.key(
            scope: scope,
            resource: "generation-models-image-\(templateID ?? "default")"
        )

        if !force {
            if let cached = await AISResponseCache.shared.read(
                AISPromptAttributeSettings.self,
                key: promptKey,
                allowsStale: true
            ) {
                promptSettings = cached.value
                hasFreshConfiguration = cached.isFresh
            }
            if let cached = await AISResponseCache.shared.read(
                AISVisualPresetOptions.self,
                key: visualKey,
                allowsStale: true
            ) {
                applyVisualPresets(cached.value)
            }
            if let cached = await AISResponseCache.shared.read(
                [AISGenerationModelOption].self,
                key: modelKey,
                allowsStale: true
            ) {
                models = cached.value
            }
        }

        do {
            async let promptRequest: AISPromptAttributeSettings = api.get(
                "/api/ais/prompt-attributes",
                query: [URLQueryItem(name: "mediaType", value: "image")],
                accessToken: accessToken
            )
            async let visualRequest: AISVisualPresetOptions = api.get(
                "/api/ais/visual-presets"
            )
            async let modelRequest: [AISGenerationModelOption] = api.get(
                "/api/ais/generation-models",
                query: [
                    URLQueryItem(name: "capability", value: "image"),
                    URLQueryItem(
                        name: "templateId",
                        value: templateID?.nilIfEmpty
                    )
                ].filter { $0.value != nil },
                accessToken: accessToken
            )
            let (prompt, visual, generationModels) = try await (
                promptRequest,
                visualRequest,
                modelRequest
            )
            promptSettings = prompt
            applyVisualPresets(visual)
            models = generationModels
            hasFreshConfiguration = true
            await AISResponseCache.shared.write(prompt, key: promptKey)
            await AISResponseCache.shared.write(visual, key: visualKey)
            await AISResponseCache.shared.write(
                generationModels,
                key: modelKey
            )
        } catch where AISErrorClassifier.isCancellation(error) {
            NetworkDiagnosticsStore.shared.recordSystemLog(
                tag: "CANCELLED",
                "Creation configuration request was cancelled."
            )
        } catch {
            hasFreshConfiguration = false
            errorMessage = error.localizedDescription
        }
    }

    private func applyVisualPresets(_ legacy: AISVisualPresetOptions) {
        let configuredDirections = promptSettings.map {
            AISVisualPresetMapper.presets(from: $0, groupID: "direction")
        } ?? []
        visualPresets = AISVisualPresetOptions(
            directions: configuredDirections.isEmpty
                ? legacy.directions
                : configuredDirections,
            effects: legacy.effects
        )
    }

    func normalize(
        orientation: inout String,
        aspectRatio: inout String,
        resolution: inout String,
        modelKey: inout String
    ) {
        let availableOrientations = specs("orientation").filter(\.isAvailable)
        if !availableOrientations.contains(where: { $0.value == orientation }) {
            orientation = availableOrientations.first?.value
                ?? orientationForAspect(aspectRatio)
        }

        let ratios = specs("aspect_ratio").filter(\.isAvailable)
        let orientedRatios = ratios.filter {
            orientationForAspect($0.value) == orientation
        }
        if !orientedRatios.contains(where: { $0.value == aspectRatio }) {
            aspectRatio = orientedRatios.first?.value
                ?? ratios.first?.value
                ?? ""
        }

        let resolutions = specs("resolution").filter(\.isAvailable)
        if !resolutions.contains(where: { $0.value == resolution }) {
            resolution = resolutions.first?.value ?? ""
        }

        let usableModels = models.filter {
            $0.canUse && $0.canSelect
        }
        if !usableModels.contains(where: {
            $0.displayModelKey == modelKey
        }) {
            modelKey = usableModels.first(where: \.isRecommended)?
                .displayModelKey
                ?? usableModels.first?.displayModelKey
                ?? ""
        }
    }

    func orientationForAspect(_ value: String) -> String {
        let values = value.split(separator: ":").compactMap {
            Double($0)
        }
        guard values.count == 2 else { return "square" }
        if values[0] == values[1] { return "square" }
        return values[0] > values[1] ? "landscape" : "portrait"
    }
}
