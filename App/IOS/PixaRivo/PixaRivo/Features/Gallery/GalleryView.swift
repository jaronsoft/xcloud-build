import SwiftUI

@MainActor @Observable
private final class GalleryStore {
    private let api = APIClient()
    var items: [GalleryJob] = []
    var categories: [GalleryCategory] = []
    var isLoading = false
    var errorMessage: String?
    private var requestID = UUID()

    func load(categoryKey: String = "", forceRefresh: Bool = false) async {
        let currentRequestID = UUID()
        requestID = currentRequestID
        isLoading = true
        defer {
            if requestID == currentRequestID { isLoading = false }
        }
        let queries = requestQueries(categoryKey: categoryKey)
        if !forceRefresh,
           items.isEmpty {
            var cachedPages: [PageResponse<GalleryJob>] = []
            for query in queries {
                if let cached: PageResponse<GalleryJob> = await api.cachedValue(
                    PageResponse<GalleryJob>.self,
                    path: "/api/ais/jobs/gallery",
                    query: query
                ) {
                    cachedPages.append(cached)
                }
            }
            if !cachedPages.isEmpty {
                guard requestID == currentRequestID else { return }
                items = visibleItems(cachedPages)
            }
        }
        do {
            let pages = try await loadPages(queries: queries, forceRefresh: forceRefresh)
            guard requestID == currentRequestID else { return }
            items = visibleItems(pages)
            errorMessage = nil
        } catch {
            guard requestID == currentRequestID, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadCategories(forceRefresh: Bool = false) async {
        do {
            let response: GalleryCategoryResponse = try await api.get(
                "/api/ais/gallery-categories",
                forceRefresh: forceRefresh
            )
            categories = response.categories
                .filter(\.enabled)
                .sorted { $0.sort < $1.sort }
        } catch {
            // 分类加载失败时仍保留“精选”和“最新”，不阻断案例内容。
        }
    }

    private func requestQueries(categoryKey: String) -> [[URLQueryItem]] {
        let primary = requestQuery(categoryKey: categoryKey, language: AppLanguage.apiValue)
        guard !AppLanguage.isChinese else { return [primary] }
        return [primary, requestQuery(categoryKey: categoryKey, language: "zh")]
    }

    private func requestQuery(categoryKey: String, language: String) -> [URLQueryItem] {
        var query: [URLQueryItem] = [
            .init(name: "page", value: "1"),
            .init(name: "size", value: "40"),
            .init(name: "language", value: language),
            .init(name: "jobType", value: "style_template_generate")
        ]
        if !categoryKey.isEmpty {
            query.append(.init(name: "categoryKey", value: categoryKey))
        }
        return query
    }

    private func loadPages(
        queries: [[URLQueryItem]],
        forceRefresh: Bool
    ) async throws -> [PageResponse<GalleryJob>] {
        guard queries.count > 1 else {
            let page: PageResponse<GalleryJob> = try await api.getCached(
                "/api/ais/jobs/gallery",
                query: queries[0],
                forceRefresh: forceRefresh
            )
            return [page]
        }

        async let preferredPage: PageResponse<GalleryJob>? = try? api.getCached(
            "/api/ais/jobs/gallery",
            query: queries[0],
            forceRefresh: forceRefresh
        )
        async let fallbackPage: PageResponse<GalleryJob>? = try? api.getCached(
            "/api/ais/jobs/gallery",
            query: queries[1],
            forceRefresh: forceRefresh
        )
        let pages = await [preferredPage, fallbackPage].compactMap { $0 }
        guard !pages.isEmpty else { throw APIError.invalidResponse }
        return pages
    }

    private func visibleItems(_ pages: [PageResponse<GalleryJob>]) -> [GalleryJob] {
        var seen = Set<String>()
        return pages
            .flatMap(\.items)
            .filter { $0.mediaURL != nil && seen.insert($0.id).inserted }
    }
}
struct GalleryView: View {
    @Environment(PixaMediaRegionStore.self) private var mediaRegion
    @Environment(PixaLanguageStore.self) private var language
    @Environment(PixaNavigationStore.self) private var navigation
    @State private var store = GalleryStore()
    @State private var sharePayload: PixaSharePayload?
    @State private var preparingShareID: String?
    @State private var showsShareError = false
    @State private var selectedFilterID = "featured"
    @State private var selectedCategoryKey = ""
    @State private var filterTask: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    compactHeader
                    discoveryStrip
                    if store.isLoading && store.items.isEmpty {
                        PixaLoadingStateView(
                            title: "loading.gallery.title",
                            message: "loading.gallery.message",
                            minHeight: 260
                        )
                    } else if let error = store.errorMessage, store.items.isEmpty {
                        ContentUnavailableView {
                            Label("common.error", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("common.retry") {
                                Task {
                                    await store.load(
                                        categoryKey: selectedCategoryKey,
                                        forceRefresh: true
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(PixaTheme.accent)
                        }
                    }
                    else {
                        MasonryLayout(columns: 2, spacing: 12) {
                            ForEach(store.items) { item in
                                ZStack(alignment: .topTrailing) {
                                    NavigationLink {
                                        GalleryDetailView(item: item)
                                    } label: {
                                        GalleryCard(item: item)
                                    }
                                    .buttonStyle(.plain)

                                    PixaShareButton(isPreparing: preparingShareID == item.id) {
                                        Task { await share(item) }
                                    }
                                    .padding(9)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(PixaTheme.paper.ignoresSafeArea())
            .background(
                PixaNavigationPopObserver(
                    revision: navigation.popRevision(for: .gallery)
                )
            )
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                async let categoriesLoad: Void = store.loadCategories(forceRefresh: true)
                await store.load(categoryKey: selectedCategoryKey, forceRefresh: true)
                await categoriesLoad
            }
            .task(id: "\(mediaRegion.revision):\(language.locale.identifier)") {
                async let categoriesLoad: Void = store.loadCategories(
                    forceRefresh: mediaRegion.revision > 0
                )
                await store.load(
                    categoryKey: selectedCategoryKey,
                    forceRefresh: mediaRegion.revision > 0
                )
                await categoriesLoad
            }
            .sheet(item: $sharePayload) { payload in
                PixaActivityView(items: payload.items)
            }
            .alert("share.failed.title", isPresented: $showsShareError) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text("share.failed.message")
            }
        }
    }

    @MainActor
    private func share(_ item: GalleryJob) async {
        guard preparingShareID == nil else { return }
        preparingShareID = item.id
        defer { preparingShareID = nil }
        sharePayload = await PixaShareService.prepare(
            title: item.title.nilIfEmpty ?? AppLanguage.localized("gallery.untitled"),
            description: item.description,
            imageURL: item.mediaURL,
            source: .gallery
        )
        showsShareError = sharePayload == nil
    }

    private var compactHeader: some View {
        PixaSectionHeader(eyebrow: "gallery.eyebrow", title: "gallery.title") {
            if !store.items.isEmpty {
                Text(String.localizedStringWithFormat(
                    AppLanguage.localized("gallery.count"),
                    store.items.count
                ))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private var discoveryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton(
                    id: "featured",
                    title: AppLanguage.localized("gallery.editor_pick"),
                    categoryKey: "",
                    systemImage: "seal.fill"
                )
                filterButton(
                    id: "latest",
                    title: AppLanguage.localized("gallery.latest"),
                    categoryKey: ""
                )
                ForEach(store.categories) { category in
                    filterButton(
                        id: "category:\(category.categoryKey)",
                        title: category.name,
                        categoryKey: category.categoryKey
                    )
                }
            }
            .font(.caption.bold())
        }
    }

    private func filterButton(
        id: String,
        title: String,
        categoryKey: String,
        systemImage: String? = nil
    ) -> some View {
        let isSelected = selectedFilterID == id
        return Button {
            guard !isSelected else { return }
            selectedFilterID = id
            selectedCategoryKey = categoryKey
            filterTask?.cancel()
            filterTask = Task { await store.load(categoryKey: categoryKey) }
        } label: {
            HStack(spacing: 6) {
                if isSelected && store.isLoading {
                    ProgressView().controlSize(.mini).tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .foregroundStyle(isSelected ? .white : PixaTheme.ink)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                isSelected ? PixaTheme.accent : Color.white.opacity(0.62),
                in: Capsule()
            )
            .overlay { Capsule().stroke(isSelected ? .clear : PixaTheme.line) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct GalleryCategoryResponse: Decodable {
    let categories: [GalleryCategory]

    private enum CodingKeys: String, CodingKey {
        case categories = "Categories"
    }
}

struct GalleryCategory: Decodable, Identifiable {
    var id: String { categoryKey }
    let categoryKey: String
    let nameZh: String
    let nameEn: String
    let sort: Int
    let enabled: Bool

    private enum CodingKeys: String, CodingKey {
        case categoryKey = "CategoryKey"
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case sort = "Sort"
        case enabled = "Enabled"
    }

    var name: String { AppLanguage.value(zh: nameZh, en: nameEn) }
}

private struct GalleryCard: View {
    let item: GalleryJob

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteArtwork(
                url: item.mediaURL,
                aspectRatio: item.displayAspectRatio,
                contentMode: .fit,
                usesIntrinsicAspectRatio: true
            )
            .background(Color.white.opacity(0.72))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "info.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(8)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.nilIfEmpty ?? AppLanguage.localized("gallery.untitled"))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .lineSpacing(1)
                HStack(spacing: 8) {
                    creatorIdentity
                    Spacer(minLength: 4)
                    Label(item.heatScore.formatted(.number.notation(.compactName)), systemImage: "flame")
                    Label(item.viewCount.formatted(.number.notation(.compactName)), systemImage: "eye")
                }
                .padding(.trailing, 2)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .padding(8)
        }.background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 13)).clipShape(RoundedRectangle(cornerRadius: 13)).overlay { RoundedRectangle(cornerRadius: 13).stroke(PixaTheme.line) }
    }

    private var creatorIdentity: some View {
        HStack(spacing: 5) {
            if let url = resolvedAccountURL(item.creatorAvatarURL) {
                RemoteArtwork(
                    url: url,
                    aspectRatio: 1,
                    preset: .thumbnail,
                    maximumPixelWidth: 80
                )
                .frame(width: 18, height: 18)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 17))
            }
            Text(item.creatorName?.nilIfEmpty ?? AppLanguage.localized("gallery.creator.anonymous"))
                .lineLimit(1)
        }
    }
}
