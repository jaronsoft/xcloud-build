import Foundation
import Observation

enum TemplateFilter: String, CaseIterable, Identifiable {
    case recommended
    case latest
    case popular
    case portrait
    case landscape

    var id: String { rawValue }
    var title: String {
        switch self {
        case .recommended: AppLanguage.localized("home.recommended")
        case .latest: AppLanguage.localized("home.latest")
        case .popular: AppLanguage.localized("home.popular")
        case .portrait: AppLanguage.localized("home.portrait")
        case .landscape: AppLanguage.localized("home.landscape")
        }
    }
    var sort: String {
        switch self {
        case .latest: "latest"
        case .popular: "popular"
        default: "recommended"
        }
    }
    var orientation: String {
        switch self {
        case .portrait: "portrait"
        case .landscape: "landscape"
        default: ""
        }
    }
}

enum TemplateSurface: Equatable {
    case home
    case creation
}

@MainActor
@Observable
final class TemplateStore {
    private struct ImpressionBatch {
        let key: String
        let templateIDs: [String]
        let entry: String
    }

    private let api = APIClient()
    private let surface: TemplateSurface
    private(set) var templates: [StyleTemplate] = []
    private(set) var total = 0
    private(set) var isLoading = true
    private(set) var isLoadingMore = false
    private(set) var loadingFilter: TemplateFilter?
    private(set) var filterGroups: [StyleTemplateFilterGroup] = []
    private(set) var isLoadingFilters = false
    var errorMessage: String?
    var query = ""
    private(set) var filter: TemplateFilter = .recommended
    private(set) var sort = "recommended"
    private(set) var orientation = ""
    private(set) var platform = ""
    private(set) var selectedTags: [String: Set<String>] = [:]
    private var page = 0
    private var canLoadMore = true
    private var shouldLoadMoreAfterCurrentRequest = false
    private var requestRevision = 0
    private var seenImpressions: Set<String> = []
    private var pendingImpressionIDsByEntry: [String: Set<String>] = [:]
    private var queuedImpressionBatches: [ImpressionBatch] = []
    private var impressionFlushTask: Task<Void, Never>?
    private var isSendingImpressions = false

    init(surface: TemplateSurface = .home) {
        self.surface = surface
    }

    var hasMore: Bool {
        canLoadMore && templates.count < total
    }

    var activeFilterCount: Int {
        (orientation.isEmpty ? 0 : 1)
            + (platform.isEmpty ? 0 : 1)
            + selectedTags.values.reduce(0) { $0 + $1.count }
    }

    var platformGroup: StyleTemplateFilterGroup? {
        filterGroups.first { $0.groupKey == "platform" }
    }

    var tagGroups: [StyleTemplateFilterGroup] {
        filterGroups
            .filter { $0.groupKey != "platform" }
            .sorted { $0.sort < $1.sort }
    }

    func select(_ filter: TemplateFilter) async {
        self.filter = filter
        sort = filter.sort
        orientation = filter.orientation
        loadingFilter = filter
        await load()
        if !isLoading, self.filter == filter {
            loadingFilter = nil
        }
    }

    func applyFilters(
        sort: String,
        orientation: String,
        platform: String,
        selectedTags: [String: Set<String>]
    ) async {
        self.sort = sort
        self.orientation = orientation
        self.platform = platform
        self.selectedTags = selectedTags.filter { !$0.value.isEmpty }
        filter = sort == "latest"
            ? .latest
            : sort == "popular"
                ? .popular
            : orientation == "portrait"
                ? .portrait
                : orientation == "landscape" ? .landscape : .recommended
        await load(forceRefresh: true)
    }

    func resetFilters() async {
        await applyFilters(
            sort: sort,
            orientation: "",
            platform: "",
            selectedTags: [:]
        )
    }

    func selectSort(_ value: String) async {
        guard ["recommended", "latest", "popular"].contains(value), value != sort else { return }
        await applyFilters(
            sort: value,
            orientation: orientation,
            platform: platform,
            selectedTags: selectedTags
        )
    }

    func loadFilterGroups(forceRefresh: Bool = false) async {
        isLoadingFilters = true
        defer { isLoadingFilters = false }
        let query = [
            URLQueryItem(name: "templateType", value: "image"),
            URLQueryItem(name: "region", value: PixaMediaRegion.templateRegionValue)
        ]
        do {
            let groups: [StyleTemplateFilterGroup] = try await api.getCached(
                "/api/ais/style-templates/categories",
                query: query,
                forceRefresh: forceRefresh
            )
            filterGroups = groups.sorted { $0.sort < $1.sort }
            reconcileSelectedFilters()
        } catch {
            if filterGroups.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func load(reset: Bool = true, forceRefresh: Bool = false) async {
        if !reset, isLoading || isLoadingMore {
            // 缓存数据可能在首轮请求结束前让末尾卡片出现，保留这次翻页意图，避免第二页永久漏载。
            shouldLoadMoreAfterCurrentRequest = canLoadMore
            return
        }
        guard reset || canLoadMore else { return }
        if reset {
            shouldLoadMoreAfterCurrentRequest = false
        }
        requestRevision += 1
        let revision = requestRevision
        if reset { isLoading = true } else { isLoadingMore = true }
        errorMessage = nil
        defer {
            if revision == requestRevision {
                isLoading = false
                isLoadingMore = false
                let shouldContinue = shouldLoadMoreAfterCurrentRequest && canLoadMore
                shouldLoadMoreAfterCurrentRequest = false
                if shouldContinue {
                    Task { await self.load(reset: false) }
                }
            }
        }
        let targetPage = reset ? 1 : page + 1
        let queryItems = requestQuery(page: targetPage)
        if !forceRefresh,
           (reset ? templates.isEmpty : true),
           let cached: PageResponse<StyleTemplate> = await api.cachedValue(
               PageResponse<StyleTemplate>.self,
               path: "/api/ais/style-templates",
               query: queryItems
           ) {
            guard revision == requestRevision else { return }
            apply(cached, page: targetPage, reset: reset)
        }
        do {
            let result: PageResponse<StyleTemplate> = try await api.getCached(
                "/api/ais/style-templates",
                query: queryItems,
                forceRefresh: forceRefresh
            )
            guard revision == requestRevision else { return }
            apply(result, page: targetPage, reset: reset)
            errorMessage = nil
        } catch {
            guard revision == requestRevision else { return }
            errorMessage = error.localizedDescription
        }
    }

    func detail(id: String, token: String? = nil) async throws -> StyleTemplate {
        try await api.get(
            "/api/ais/style-templates/\(id)",
            query: [
                URLQueryItem(name: "region", value: PixaMediaRegion.templateRegionValue),
                URLQueryItem(name: "language", value: AppLanguage.apiValue)
            ],
            token: token,
            forceRefresh: true
        )
    }

    func recordImpression(templateID: String) {
        let entry = "\(surface == .home ? "home" : "templates")_\(sort)"
        let identity = "\(entry):\(templateID)"
        guard seenImpressions.insert(identity).inserted else { return }
        pendingImpressionIDsByEntry[entry, default: []].insert(templateID)
        impressionFlushTask?.cancel()
        impressionFlushTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            impressionFlushTask = nil
            await flushImpressions(entry: entry)
        }
    }

    private func flushImpressions(entry: String) async {
        if let pending = pendingImpressionIDsByEntry[entry], !pending.isEmpty {
            let ids = Array(pending.prefix(100))
            pendingImpressionIDsByEntry[entry]?.subtract(ids)
            if pendingImpressionIDsByEntry[entry]?.isEmpty == true {
                pendingImpressionIDsByEntry.removeValue(forKey: entry)
            }
            queuedImpressionBatches.append(ImpressionBatch(
                key: UUID().uuidString,
                templateIDs: ids,
                entry: entry
            ))
        }
        guard !isSendingImpressions, let batch = queuedImpressionBatches.first else { return }
        isSendingImpressions = true
        do {
            let _: PixaTemplateImpressionResponse = try await api.post(
                "/api/ais/style-templates/impressions",
                body: PixaTemplateImpressionRequest(
                    batchKey: batch.key,
                    templateIDs: batch.templateIDs,
                    entry: batch.entry,
                    region: PixaMediaRegion.templateRegionValue
                )
            )
            queuedImpressionBatches.removeFirst()
            isSendingImpressions = false
            if let nextBatch = queuedImpressionBatches.first {
                await flushImpressions(entry: nextBatch.entry)
            } else if let nextEntry = pendingImpressionIDsByEntry.keys.first {
                await flushImpressions(entry: nextEntry)
            }
        } catch {
            isSendingImpressions = false
            impressionFlushTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                impressionFlushTask = nil
                await flushImpressions(entry: entry)
            }
        }
    }

    private func merged(_ current: [StyleTemplate], _ incoming: [StyleTemplate]) -> [StyleTemplate] {
        var seen = Set(current.map(\.id))
        return current + incoming.filter { seen.insert($0.id).inserted }
    }

    private func requestQuery(page: Int) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "templateType", value: "image"),
            URLQueryItem(name: "region", value: PixaMediaRegion.templateRegionValue),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: "24"),
            URLQueryItem(name: "sort", value: sort)
        ]
        if sort == "recommended" {
            items.append(URLQueryItem(name: "placement", value: placement))
        }
        if let value = query.nilIfEmpty {
            items.append(URLQueryItem(name: "keyword", value: value))
        }
        if let value = orientation.nilIfEmpty {
            items.append(URLQueryItem(name: "orientation", value: value))
        }
        if let value = platform.nilIfEmpty {
            items.append(URLQueryItem(name: "platform", value: value))
        }
        for (groupKey, values) in selectedTags where !values.isEmpty {
            items.append(
                URLQueryItem(
                    name: groupKey,
                    value: values.sorted().joined(separator: ",")
                )
            )
        }
        return items
    }

    private var placement: String {
        if surface == .creation {
            return "creation"
        }
        if orientation == "portrait" {
            return "home_portrait"
        }
        if orientation == "landscape" {
            return "home_landscape"
        }
        return "home_recommended"
    }

    private func reconcileSelectedFilters() {
        if !platform.isEmpty,
           platformGroup?.items.contains(where: { $0.itemKey == platform }) != true {
            platform = ""
        }
        let availableItems = Dictionary(
            uniqueKeysWithValues: tagGroups.map { group in
                (group.groupKey, Set(group.items.map(\.itemKey)))
            }
        )
        selectedTags = selectedTags.reduce(into: [:]) { result, entry in
            let retained = entry.value.intersection(
                availableItems[entry.key] ?? []
            )
            if !retained.isEmpty {
                result[entry.key] = retained
            }
        }
    }

    private func apply(
        _ result: PageResponse<StyleTemplate>,
        page targetPage: Int,
        reset: Bool
    ) {
        templates = reset ? result.items : merged(templates, result.items)
        total = result.total
        page = targetPage
        canLoadMore = result.items.count == 24 && templates.count < total
    }
}

private struct PixaTemplateImpressionRequest: Encodable {
    let batchKey: String
    let templateIDs: [String]
    let entry: String
    let region: String

    private enum CodingKeys: String, CodingKey {
        case batchKey = "BatchKey"
        case templateIDs = "TemplateIds"
        case entry = "Entry"
        case region = "Region"
    }
}

private struct PixaTemplateImpressionResponse: Decodable {
    let counted: Int

    private enum CodingKeys: String, CodingKey {
        case counted = "counted"
    }
}
