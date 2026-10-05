import Foundation

struct AISHomeCopyOptions: Codable, Sendable {
    let items: [AISHomeCopyItem]

    private enum CodingKeys: String, CodingKey {
        case items
        case itemsUpper = "Items"
    }

    init(items: [AISHomeCopyItem]) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent(
            [AISHomeCopyItem].self,
            forKey: .items
        ) ?? container.decodeIfPresent(
            [AISHomeCopyItem].self,
            forKey: .itemsUpper
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
    }
}

struct AISHomeCopyItem: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let sort: Int
    let localizations: [AISHomeCopyLocalization]

    private enum CodingKeys: String, CodingKey {
        case id
        case idUpper = "Id"
        case sort
        case sortUpper = "Sort"
        case localizations
        case localizationsUpper = "Localizations"
    }

    init(
        id: String,
        sort: Int,
        localizations: [AISHomeCopyLocalization]
    ) {
        self.id = id
        self.sort = sort
        self.localizations = localizations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .idUpper)
        sort = try container.decodeIfPresent(Int.self, forKey: .sort)
            ?? container.decodeIfPresent(Int.self, forKey: .sortUpper)
            ?? 0
        localizations = try container.decodeIfPresent(
            [AISHomeCopyLocalization].self,
            forKey: .localizations
        ) ?? container.decodeIfPresent(
            [AISHomeCopyLocalization].self,
            forKey: .localizationsUpper
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sort, forKey: .sort)
        try container.encode(localizations, forKey: .localizations)
    }
}

struct AISHomeCopyLocalization: Codable, Sendable, Equatable {
    let locale: String
    let eyebrow: String
    let title: String
    let subtitle: String

    private enum CodingKeys: String, CodingKey {
        case locale
        case localeUpper = "Locale"
        case eyebrow
        case eyebrowUpper = "Eyebrow"
        case title
        case titleUpper = "Title"
        case subtitle
        case subtitleUpper = "Subtitle"
    }

    init(locale: String, eyebrow: String, title: String, subtitle: String) {
        self.locale = locale
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        locale = try container.decodeIfPresent(String.self, forKey: .locale)
            ?? container.decode(String.self, forKey: .localeUpper)
        eyebrow = try container.decodeIfPresent(String.self, forKey: .eyebrow)
            ?? container.decodeIfPresent(String.self, forKey: .eyebrowUpper)
            ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .titleUpper)
            ?? ""
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
            ?? container.decodeIfPresent(String.self, forKey: .subtitleUpper)
            ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(locale, forKey: .locale)
        try container.encode(eyebrow, forKey: .eyebrow)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
    }
}

struct AISResolvedHomeCopy: Equatable, Sendable {
    let id: String
    let eyebrow: String
    let title: String
    let subtitle: String
}

enum AISHomeCopyPolicy {
    static func isValid(_ options: AISHomeCopyOptions) -> Bool {
        guard !options.items.isEmpty else { return false }
        var ids = Set<String>()
        for item in options.items {
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, ids.insert(id.lowercased()).inserted else {
                return false
            }
            let localizations = item.localizations.filter(isComplete)
            guard localizations.contains(where: {
                $0.locale.caseInsensitiveCompare("zh-Hans") == .orderedSame
            }), localizations.contains(where: {
                $0.locale.caseInsensitiveCompare("en") == .orderedSame
            }) else {
                return false
            }
        }
        return true
    }

    static func resolved(
        item: AISHomeCopyItem,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AISResolvedHomeCopy? {
        let values = item.localizations.filter(isComplete)
        guard !values.isEmpty else { return nil }

        for preferred in preferredLanguages {
            let normalized = preferred.replacingOccurrences(of: "_", with: "-")
            if let exact = values.first(where: {
                $0.locale.caseInsensitiveCompare(normalized) == .orderedSame
            }) {
                return resolved(item.id, exact)
            }

            let languageCode = normalized
                .split(separator: "-", maxSplits: 1)
                .first
                .map(String.init)?
                .lowercased()
            if let languageCode,
               let languageMatch = values.first(where: {
                   $0.locale
                       .split(separator: "-", maxSplits: 1)
                       .first
                       .map(String.init)?
                       .lowercased() == languageCode
               }) {
                return resolved(item.id, languageMatch)
            }
        }

        if let english = values.first(where: {
            $0.locale.caseInsensitiveCompare("en") == .orderedSame
        }) {
            return resolved(item.id, english)
        }
        if let simplifiedChinese = values.first(where: {
            $0.locale.caseInsensitiveCompare("zh-Hans") == .orderedSame
        }) {
            return resolved(item.id, simplifiedChinese)
        }
        return resolved(item.id, values[0])
    }

    static func select(
        from items: [AISHomeCopyItem],
        excluding previousID: String?,
        preferredLanguages: [String] = Locale.preferredLanguages,
        randomIndex: ((Int) -> Int)? = nil
    ) -> AISResolvedHomeCopy? {
        let resolvedItems = items
            .sorted {
                $0.sort == $1.sort ? $0.id < $1.id : $0.sort < $1.sort
            }
            .compactMap {
                resolved(item: $0, preferredLanguages: preferredLanguages)
            }
        guard !resolvedItems.isEmpty else { return nil }

        let candidates: [AISResolvedHomeCopy]
        if resolvedItems.count > 1, let previousID {
            candidates = resolvedItems.filter { $0.id != previousID }
        } else {
            candidates = resolvedItems
        }
        guard !candidates.isEmpty else { return resolvedItems[0] }
        let index = randomIndex?(candidates.count)
            ?? Int.random(in: 0 ..< candidates.count)
        return candidates[max(0, min(index, candidates.count - 1))]
    }

    static func dayKey(
        for date: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func isComplete(_ value: AISHomeCopyLocalization) -> Bool {
        !value.locale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.eyebrow.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            && !value.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            && !value.subtitle.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }

    private static func resolved(
        _ id: String,
        _ value: AISHomeCopyLocalization
    ) -> AISResolvedHomeCopy {
        AISResolvedHomeCopy(
            id: id,
            eyebrow: value.eyebrow,
            title: value.title,
            subtitle: value.subtitle
        )
    }
}

enum AISHomeCopyPersistence {
    private struct Envelope: Codable {
        let version: Int
        let savedAt: Date
        let options: AISHomeCopyOptions
    }

    static func load(
        fileManager: FileManager = .default
    ) -> AISHomeCopyOptions? {
        guard let data = try? Data(contentsOf: fileURL(fileManager)),
              let envelope = try? JSONDecoder().decode(
                  Envelope.self,
                  from: data
              ),
              envelope.version == 1,
              AISHomeCopyPolicy.isValid(envelope.options) else {
            return nil
        }
        return envelope.options
    }

    static func save(
        _ options: AISHomeCopyOptions,
        fileManager: FileManager = .default
    ) throws {
        guard AISHomeCopyPolicy.isValid(options) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let directory = directoryURL(fileManager)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
        let data = try JSONEncoder().encode(
            Envelope(version: 1, savedAt: .now, options: options)
        )
        try data.write(to: fileURL(fileManager), options: .atomic)
    }

    private static func directoryURL(_ fileManager: FileManager) -> URL {
        fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appending(path: "AIS", directoryHint: .isDirectory)
    }

    private static func fileURL(_ fileManager: FileManager) -> URL {
        directoryURL(fileManager)
            .appending(path: "HomeCopies.json", directoryHint: .notDirectory)
    }
}

actor AISHomeCopyRefreshStore {
    static let shared = AISHomeCopyRefreshStore()

    private let api = APIClient()
    private let defaults = UserDefaults.standard
    private let lastCheckDayKey = "ais.home_copies.last_check_day"
    private var isRefreshing = false

    func refreshIfNeeded(
        now: Date = .now,
        calendar: Calendar = .current
    ) async {
        let today = AISHomeCopyPolicy.dayKey(for: now, calendar: calendar)
        guard !isRefreshing,
              defaults.string(forKey: lastCheckDayKey) != today else {
            return
        }

        isRefreshing = true
        defaults.set(today, forKey: lastCheckDayKey)
        defer { isRefreshing = false }

        do {
            let options: AISHomeCopyOptions = try await api.get(
                "/api/ais/home-copies"
            )
            try AISHomeCopyPersistence.save(options)
        } catch {
            // 静默更新失败时保留最后有效文案，下一个自然日再尝试。
        }
    }
}
