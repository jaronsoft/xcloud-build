import Foundation

struct PixaHomeCopyOptions: Codable, Sendable {
    let items: [PixaHomeCopyItem]

    private enum CodingKeys: String, CodingKey {
        case items
        case itemsUpper = "Items"
    }

    init(items: [PixaHomeCopyItem]) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent(
            [PixaHomeCopyItem].self,
            forKey: .items
        ) ?? container.decodeIfPresent(
            [PixaHomeCopyItem].self,
            forKey: .itemsUpper
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
    }
}

struct PixaHomeCopyItem: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let sort: Int
    let localizations: [PixaHomeCopyLocalization]

    private enum CodingKeys: String, CodingKey {
        case id
        case idUpper = "Id"
        case sort
        case sortUpper = "Sort"
        case localizations
        case localizationsUpper = "Localizations"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .idUpper)
        sort = try container.decodeIfPresent(Int.self, forKey: .sort)
            ?? container.decodeIfPresent(Int.self, forKey: .sortUpper)
            ?? 0
        localizations = try container.decodeIfPresent(
            [PixaHomeCopyLocalization].self,
            forKey: .localizations
        ) ?? container.decodeIfPresent(
            [PixaHomeCopyLocalization].self,
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

struct PixaHomeCopyLocalization: Codable, Sendable, Equatable {
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

struct PixaResolvedHomeCopy: Equatable, Sendable {
    let id: String
    let eyebrow: String
    let title: String
    let subtitle: String
}

enum PixaHomeCopyPolicy {
    static func select(
        from items: [PixaHomeCopyItem],
        excluding previousID: String?
    ) -> PixaResolvedHomeCopy? {
        let resolvedItems = items
            .sorted { $0.sort == $1.sort ? $0.id < $1.id : $0.sort < $1.sort }
            .compactMap(resolve)
        guard !resolvedItems.isEmpty else { return nil }

        let candidates: [PixaResolvedHomeCopy]
        if resolvedItems.count > 1, let previousID {
            candidates = resolvedItems.filter { $0.id != previousID }
        } else {
            candidates = resolvedItems
        }
        return candidates.randomElement() ?? resolvedItems[0]
    }

    static func isValid(_ options: PixaHomeCopyOptions) -> Bool {
        !options.items.isEmpty && options.items.allSatisfy { item in
            !item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && resolve(item) != nil
        }
    }

    static func dayKey(for date: Date = .now, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func resolve(_ item: PixaHomeCopyItem) -> PixaResolvedHomeCopy? {
        let preferredLanguage = AppLanguage.isChinese ? "zh" : "en"
        let values = item.localizations.filter(isComplete)
        guard let value = values.first(where: {
            $0.locale
                .split(separator: "-", maxSplits: 1)
                .first?
                .lowercased() == preferredLanguage
        }) ?? values.first else {
            return nil
        }
        return PixaResolvedHomeCopy(
            id: item.id,
            eyebrow: value.eyebrow,
            title: value.title,
            subtitle: value.subtitle
        )
    }

    private static func isComplete(_ value: PixaHomeCopyLocalization) -> Bool {
        !value.locale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.eyebrow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum PixaHomeCopyPersistence {
    private struct Envelope: Codable {
        let version: Int
        let savedAt: Date
        let options: PixaHomeCopyOptions
    }

    static func load(fileManager: FileManager = .default) -> PixaHomeCopyOptions? {
        guard let data = try? Data(contentsOf: fileURL(fileManager)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1,
              PixaHomeCopyPolicy.isValid(envelope.options) else {
            return nil
        }
        return envelope.options
    }

    static func save(
        _ options: PixaHomeCopyOptions,
        fileManager: FileManager = .default
    ) throws {
        guard PixaHomeCopyPolicy.isValid(options) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let directory = directoryURL(fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
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
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "PixaRivo", directoryHint: .isDirectory)
    }

    private static func fileURL(_ fileManager: FileManager) -> URL {
        directoryURL(fileManager)
            .appending(path: "HomeCopies.json", directoryHint: .notDirectory)
    }
}

actor PixaHomeCopyRefreshStore {
    static let shared = PixaHomeCopyRefreshStore()

    private let api = APIClient()
    private let defaults = UserDefaults.standard
    private let lastCheckDayKey = "pixarivo.home_copies.last_check_day"
    private var isRefreshing = false

    func refreshIfNeeded(now: Date = .now, calendar: Calendar = .current) async {
        let today = PixaHomeCopyPolicy.dayKey(for: now, calendar: calendar)
        guard !isRefreshing,
              defaults.string(forKey: lastCheckDayKey) != today else {
            return
        }

        isRefreshing = true
        defaults.set(today, forKey: lastCheckDayKey)
        defer { isRefreshing = false }

        do {
            let options: PixaHomeCopyOptions = try await api.get(
                "/api/ais/home-copies",
                forceRefresh: true
            )
            try PixaHomeCopyPersistence.save(options)
        } catch {
            // 静默刷新失败时继续使用最后一次有效缓存，不打断首页体验。
        }
    }
}
