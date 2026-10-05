import PhotosUI
import SwiftUI

struct TemplatesView: View {
    private static let scrollCoordinateSpace = "templates.scroll"
    private static let paginationPrefetchDistance: CGFloat = 320

    let onCreate: () -> Void

    @Environment(AISAppDataStore.self) private var appData
    @State private var viewModel = TemplatesViewModel()
    @State private var searchText = ""
    @State private var sort = TemplateSort.recommended.rawValue
    @State private var orientation = ""
    @State private var platform = ""
    @State private var selectedTags: [String: Set<String>] = [:]
    @State private var presentsFilters = false
    @State private var presentsPublicShowcase = false
    @State private var selectedShowcaseTemplateRoute: ShowcaseTemplateRoute?

    init(onCreate: @escaping () -> Void = {}) {
        self.onCreate = onCreate
    }

    var body: some View {
        ZStack {
            AISPageBackground()
            Group {
                if viewModel.isLoading && viewModel.templates.isEmpty {
                    ProgressView("common.loading")
                } else if let error = viewModel.errorMessage,
                          viewModel.templates.isEmpty {
                    ContentUnavailableView {
                        Label("common.error", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("common.retry") {
                            Task {
                                await loadTemplates(force: true)
                            }
                        }
                    }
                } else {
                    templateCollection
                }
            }
        }
        .navigationTitle("templates.title")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "templates.search")
        .sheet(isPresented: $presentsFilters) {
            TemplateFilterSheet(
                orientation: $orientation,
                platform: $platform,
                selectedTags: $selectedTags,
                groups: appData.templateCategories.groups
            )
        }
        .navigationDestination(isPresented: $presentsPublicShowcase) {
            GalleryView(
                contentKind: .templateShowcase,
                onCreate: onCreate,
                onUseTemplate: { templateID in
                    selectedShowcaseTemplateRoute = ShowcaseTemplateRoute(
                        id: templateID
                    )
                }
            )
        }
        .navigationDestination(item: $selectedShowcaseTemplateRoute) { route in
            ShowcaseTemplateDetailLoader(templateID: route.id)
        }
        .task(id: templateRegion.rawValue) {
            await appData.templateCategories.load(region: templateRegion)
        }
        .task(id: querySignature) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await loadTemplates()
        }
    }

    private var templateCollection: some View {
        GeometryReader { proxy in
            let horizontalPadding = AISResponsiveLayout.horizontalPadding(
                for: proxy.size.width
            )
            let availableWidth = min(
                AISResponsiveLayout.maximumContentWidth,
                max(proxy.size.width - horizontalPadding * 2, 0)
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    templateSortPicker

                    TemplateCollectionHeader(
                        count: viewModel.total,
                        activeFilterCount: activeFilterCount,
                        onFilter: { presentsFilters = true },
                        onOpenUserCases: { presentsPublicShowcase = true }
                    )

                    if viewModel.templates.isEmpty {
                        ContentUnavailableView {
                            Label(
                                "templates.empty",
                                systemImage: "rectangle.grid.2x2"
                            )
                        } actions: {
                            if hasActiveQuery {
                                Button("templates.filter.reset") {
                                    resetFilters()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        PinterestMasonryLayout(
                            columns: AISResponsiveLayout.templateColumns(
                                for: availableWidth
                            ),
                            spacing: 12
                        ) {
                            ForEach(viewModel.templates) { template in
                                NavigationLink {
                                    TemplateDetailView(template: template)
                                } label: {
                                    TemplateCard(template: template)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("templates.detail.view_hint")
                            }
                        }

                        paginationSentinel(
                            viewportHeight: proxy.size.height
                        )
                    }
                }
                .frame(
                    maxWidth: AISResponsiveLayout.maximumContentWidth,
                    alignment: .leading
                )
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: Self.scrollCoordinateSpace)
            .refreshable {
                await loadTemplates(force: true)
            }
        }
    }

    private var querySignature: String {
        let tags = selectedTags
            .sorted { $0.key < $1.key }
            .map { key, values in
                "\(key)=\(values.sorted().joined(separator: ","))"
            }
            .joined(separator: "&")
        return "\(templateRegion.rawValue)|\(sort)|\(searchText)|\(orientation)|\(platform)|\(tags)"
    }

    private var activeFilterCount: Int {
        (orientation.isEmpty ? 0 : 1)
            + (platform.isEmpty ? 0 : 1)
            + selectedTags.values.reduce(0) { $0 + $1.count }
    }

    private var hasActiveQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || activeFilterCount > 0
    }

    private func loadTemplates(
        force: Bool = false,
        append: Bool = false
    ) async {
        await viewModel.load(
            search: searchText,
            sort: sort,
            orientation: orientation,
            platform: platform,
            region: templateRegion,
            selectedTags: selectedTags,
            queryID: querySignature,
            force: force,
            append: append
        )
    }

    @ViewBuilder
    private func paginationSentinel(viewportHeight: CGFloat) -> some View {
        if viewModel.hasMore {
            VStack(spacing: 8) {
                if viewModel.isLoadingMore {
                    ProgressView()
                    Text("common.loading")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { sentinelProxy in
                    let minY = sentinelProxy.frame(
                        in: .named(Self.scrollCoordinateSpace)
                    ).minY
                    Color.clear
                        .onAppear {
                            loadNextPageIfNeeded(
                                sentinelMinY: minY,
                                viewportHeight: viewportHeight
                            )
                        }
                        .onChange(of: minY) { _, newValue in
                            loadNextPageIfNeeded(
                                sentinelMinY: newValue,
                                viewportHeight: viewportHeight
                            )
                        }
                }
                .frame(height: 1)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .accessibilityElement(children: .combine)
        }
    }

    private func loadNextPageIfNeeded(
        sentinelMinY: CGFloat,
        viewportHeight: CGFloat
    ) {
        guard sentinelMinY <= viewportHeight
                + Self.paginationPrefetchDistance,
              viewModel.hasMore,
              !viewModel.isLoading,
              !viewModel.isLoadingMore else {
            return
        }
        Task {
            await loadTemplates(append: true)
        }
    }

    private func resetFilters() {
        searchText = ""
        orientation = ""
        platform = ""
        selectedTags = [:]
    }

    private var templateRegion: StyleTemplateMarketRegion {
        .current
    }

    private var templateSortPicker: some View {
        Picker("templates.sort.title", selection: $sort) {
            ForEach(TemplateSort.allCases) { option in
                Text(option.localizedKey).tag(option.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("templates.sort.title")
    }
}

private enum TemplateSort: String, CaseIterable, Identifiable {
    case recommended
    case latest
    case popular

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .recommended: "templates.sort.recommended"
        case .latest: "templates.sort.latest"
        case .popular: "templates.sort.popular"
        }
    }
}

struct ShowcaseTemplateRoute: Identifiable, Hashable {
    let id: String
}

struct ShowcaseTemplateDetailLoader: View {
    let templateID: String

    @State private var template: StyleTemplate?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AISPageBackground()
            if let template {
                TemplateDetailView(template: template)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("common.error", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("common.retry") {
                        Task { await load() }
                    }
                }
            } else {
                ProgressView("common.loading")
            }
        }
        .task(id: templateID) {
            await load()
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            template = try await APIClient().get(
                "/api/ais/style-templates/\(templateID)"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
@Observable
private final class TemplatesViewModel {
    private static let pageSize = 12

    private let api = APIClient()
    private(set) var templates: [StyleTemplate] = []
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private var currentPage = 0
    private var loadGeneration = 0
    private var loadedQueryID: String?

    var hasMore: Bool {
        !templates.isEmpty && templates.count < total
    }

    func load(
        search: String,
        sort: String,
        orientation: String,
        platform: String,
        region: StyleTemplateMarketRegion,
        selectedTags: [String: Set<String>],
        queryID: String,
        force: Bool = false,
        append: Bool = false
    ) async {
        if append {
            guard hasMore,
                  !isLoading,
                  !isLoadingMore,
                  loadedQueryID == queryID else {
                return
            }
            isLoadingMore = true
        } else {
            isLoading = true
            isLoadingMore = false
            errorMessage = nil
            loadedQueryID = nil
        }
        loadGeneration += 1
        let generation = loadGeneration
        let requestedPage = append ? currentPage + 1 : 1
        defer {
            if generation == loadGeneration {
                if append {
                    isLoadingMore = false
                } else {
                    isLoading = false
                }
            }
        }
        let keyword = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var parameters = [
            "keyword": keyword,
            "sort": sort,
            "orientation": orientation,
            "platform": platform,
            "region": region.rawValue,
            "page": String(requestedPage),
            "size": String(Self.pageSize)
        ]
        for (key, values) in selectedTags where !values.isEmpty {
            parameters[key] = values.sorted().joined(separator: ",")
        }
        let cacheKey = AISResponseCache.key(
            scope: "public",
            resource: "style-templates",
            parameters: parameters
        )
        if !force, let cached = await AISResponseCache.shared.read(
            PageResponse<StyleTemplate>.self,
            key: cacheKey,
            allowsStale: true
        ) {
            guard !Task.isCancelled,
                  generation == loadGeneration else {
                return
            }
            apply(
                cached.value,
                page: requestedPage,
                append: append,
                queryID: queryID
            )
            if cached.isFresh { return }
        }
        do {
            var query = [
                URLQueryItem(name: "templateType", value: "image"),
                URLQueryItem(name: "page", value: String(requestedPage)),
                URLQueryItem(name: "size", value: String(Self.pageSize)),
                URLQueryItem(name: "region", value: region.rawValue),
                URLQueryItem(name: "sort", value: sort)
            ]
            if !keyword.isEmpty {
                query.append(URLQueryItem(name: "keyword", value: keyword))
            }
            if !orientation.isEmpty {
                query.append(
                    URLQueryItem(name: "orientation", value: orientation)
                )
            }
            if !platform.isEmpty {
                query.append(URLQueryItem(name: "platform", value: platform))
            }
            for (key, values) in selectedTags where !values.isEmpty {
                query.append(
                    URLQueryItem(
                        name: key,
                        value: values.sorted().joined(separator: ",")
                    )
                )
            }
            let page: PageResponse<StyleTemplate> = try await api.get(
                "/api/ais/style-templates",
                query: query
            )
            guard !Task.isCancelled, generation == loadGeneration else {
                return
            }
            apply(
                page,
                page: requestedPage,
                append: append,
                queryID: queryID
            )
            await AISResponseCache.shared.write(page, key: cacheKey)
        } catch is CancellationError {
            return
        } catch {
            if generation == loadGeneration {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(
        _ page: PageResponse<StyleTemplate>,
        page requestedPage: Int,
        append: Bool,
        queryID: String
    ) {
        if append {
            var templatesByID = Dictionary(
                uniqueKeysWithValues: templates.map { ($0.id, $0) }
            )
            page.items.forEach { templatesByID[$0.id] = $0 }
            templates = (templates + page.items).compactMap { item in
                templatesByID.removeValue(forKey: item.id)
            }
        } else {
            templates = page.items
        }
        total = page.total
        currentPage = requestedPage
        loadedQueryID = queryID
    }

}

private struct TemplateCollectionHeader: View {
    let count: Int
    let activeFilterCount: Int
    let onFilter: () -> Void
    let onOpenUserCases: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("templates.collection.title")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "templates.result_count"),
                        count
                    )
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: onOpenUserCases) {
                Label("templates.user_cases", systemImage: "photo.stack")
            }
            .buttonStyle(.bordered)
            Button(action: onFilter) {
                Label(
                    activeFilterCount > 0
                        ? String.localizedStringWithFormat(
                            String(localized: "templates.filter.count"),
                            activeFilterCount
                        )
                        : String(localized: "templates.filter"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }
            .buttonStyle(.bordered)
            .tint(activeFilterCount > 0 ? AISTheme.accent : nil)
        }
        .padding(14)
        .aisSurface(cornerRadius: 18)
    }
}

struct StyleTemplateFilterGroup: Codable, Identifiable {
    let groupKey: String
    let nameZh: String
    let nameEn: String
    let sort: Int
    let items: [StyleTemplateFilterItem]

    var id: String { groupKey }

    private enum CodingKeys: String, CodingKey {
        case groupKey = "GroupKey"
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case sort = "Sort"
        case items = "Items"
    }

    var localizedName: String {
        AISLocalization.value(zh: nameZh, en: nameEn)
    }
}

struct StyleTemplateFilterItem: Codable, Identifiable {
    let groupKey: String
    let itemKey: String
    let nameZh: String
    let nameEn: String
    let sort: Int

    var id: String { "\(groupKey):\(itemKey)" }

    private enum CodingKeys: String, CodingKey {
        case groupKey = "GroupKey"
        case itemKey = "ItemKey"
        case nameZh = "NameZh"
        case nameEn = "NameEn"
        case sort = "Sort"
    }

    var localizedName: String {
        AISLocalization.value(zh: nameZh, en: nameEn)
    }
}

private struct TemplateFilterSheet: View {
    @Binding var orientation: String
    @Binding var platform: String
    @Binding var selectedTags: [String: Set<String>]
    let groups: [StyleTemplateFilterGroup]

    @Environment(\.dismiss) private var dismiss

    private var platformItems: [StyleTemplateFilterItem] {
        groups.first { $0.groupKey == "platform" }?.items ?? []
    }

    private var tagGroups: [StyleTemplateFilterGroup] {
        groups
            .filter { $0.groupKey != "platform" }
            .sorted { $0.sort < $1.sort }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("templates.filter.orientation") {
                    filterGrid {
                        choiceButton(
                            title: String(localized: "templates.filter.all"),
                            systemImage: "rectangle.on.rectangle",
                            isSelected: orientation.isEmpty
                        ) {
                            orientation = ""
                        }
                        choiceButton(
                            title: String(localized: "templates.filter.landscape"),
                            systemImage: "rectangle",
                            isSelected: orientation == "landscape"
                        ) {
                            orientation = "landscape"
                        }
                        choiceButton(
                            title: String(localized: "templates.filter.portrait"),
                            systemImage: "rectangle.portrait",
                            isSelected: orientation == "portrait"
                        ) {
                            orientation = "portrait"
                        }
                    }
                }

                if !platformItems.isEmpty {
                    Section("templates.filter.platform") {
                        filterGrid {
                            choiceButton(
                                title: String(
                                    localized: "templates.filter.all_platforms"
                                ),
                                systemImage: "globe",
                                isSelected: platform.isEmpty
                            ) {
                                platform = ""
                            }
                            ForEach(platformItems.sorted { $0.sort < $1.sort }) {
                                item in
                                choiceButton(
                                    title: item.localizedName,
                                    systemImage: "app",
                                    isSelected: platform == item.itemKey
                                ) {
                                    platform = item.itemKey
                                }
                            }
                        }
                    }
                }

                ForEach(tagGroups) { group in
                    Section(group.localizedName) {
                        filterGrid {
                            ForEach(group.items.sorted { $0.sort < $1.sort }) {
                                item in
                                choiceButton(
                                    title: item.localizedName,
                                    systemImage: nil,
                                    isSelected: selectedTags[
                                        group.groupKey,
                                        default: []
                                    ].contains(item.itemKey)
                                ) {
                                    toggle(item.itemKey, in: group.groupKey)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("templates.filter.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("templates.filter.reset") {
                        orientation = ""
                        platform = ""
                        selectedTags = [:]
                    }
                    .disabled(
                        orientation.isEmpty
                            && platform.isEmpty
                            && selectedTags.values.allSatisfy(\.isEmpty)
                    )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func filterGrid<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10,
            content: content
        )
        .padding(.vertical, 4)
    }

    private func choiceButton(
        title: String,
        systemImage: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? AISTheme.accent : .primary)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                isSelected
                    ? AISTheme.accent.opacity(0.10)
                    : Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected
                            ? AISTheme.accent.opacity(0.45)
                            : Color.clear
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ itemKey: String, in groupKey: String) {
        var values = selectedTags[groupKey, default: []]
        if values.contains(itemKey) {
            values.remove(itemKey)
        } else {
            values.insert(itemKey)
        }
        if values.isEmpty {
            selectedTags.removeValue(forKey: groupKey)
        } else {
            selectedTags[groupKey] = values
        }
    }
}

private struct TemplateCard: View {
    let template: StyleTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TemplateArtwork(
                url: template.imageURL,
                preset: .list,
                fallbackAspectRatio: template.displayAspectRatio
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            Text(template.localizedName)
                .font(.headline)
                .lineLimit(2)
            HStack {
                Label("\(template.basePointCost)", systemImage: "sparkles")
                Spacer()
                Label("\(template.usageCount)", systemImage: "chart.bar.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .aisSurface(cornerRadius: 22, hasShadow: true)
        .accessibilityElement(children: .combine)
    }
}

private struct TemplateDetailView: View {
    let template: StyleTemplate

    @Environment(SessionStore.self) private var session
    @State private var casesModel = TemplateCasesViewModel()
    @State private var selectedCase: GalleryJob?
    @State private var presentsPreparation = false
    @State private var presentsLogin = false
    @State private var imageViewerRoute: AISMediaViewerRoute?

    var body: some View {
        ZStack {
            AISPageBackground()
            GeometryReader { proxy in
                let usesWideLayout = AISResponsiveLayout
                    .usesWideTemplateDetailLayout(for: proxy.size)

                ScrollView {
                    Group {
                        if usesWideLayout {
                            HStack(alignment: .top, spacing: 24) {
                                templateOverview
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .topLeading
                                    )
                                sameTemplateCasesSection
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .topLeading
                                    )
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 18) {
                                templateOverview
                                sameTemplateCasesSection
                            }
                        }
                    }
                    .frame(
                        maxWidth: usesWideLayout
                            ? AISResponsiveLayout.maximumContentWidth
                            : 680,
                        alignment: .leading
                    )
                    .padding(
                        .horizontal,
                        AISResponsiveLayout.horizontalPadding(
                            for: proxy.size.width
                        )
                    )
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("templates.detail.title")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: template.id) {
            await casesModel.load(templateID: template.id)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                if session.isAuthenticated {
                    presentsPreparation = true
                } else {
                    presentsLogin = true
                }
            } label: {
                Label(
                    session.isAuthenticated
                        ? "templates.action.use"
                        : "templates.action.signin",
                    systemImage: session.isAuthenticated
                        ? "wand.and.sparkles"
                        : "person.crop.circle"
                )
                .aisPrimaryButton()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $presentsLogin) {
            LoginView()
        }
        .sheet(isPresented: $presentsPreparation) {
            TemplatePreparationView(template: template)
        }
        .sheet(item: $selectedCase) { job in
            GalleryDetailView(job: job) {
                selectedCase = nil
                presentsPreparation = true
            }
        }
        .fullScreenCover(item: $imageViewerRoute) { route in
            AISMediaGalleryViewer(
                items: templateViewerItems,
                initialItemID: route.id
            )
        }
    }

    private var templateOverview: some View {
        VStack(alignment: .leading, spacing: 18) {
            TemplateArtwork(
                url: template.imageURL,
                preset: .detail,
                fallbackAspectRatio: template.displayAspectRatio
            )
            .frame(maxHeight: 620)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .aisSurface(cornerRadius: 26, hasShadow: true)
            .contentShape(
                RoundedRectangle(cornerRadius: 26)
            )
            .onTapGesture {
                presentTemplateImage()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("image.viewer.open_hint")
            Text(template.localizedName)
                .font(.system(.title2, design: .rounded, weight: .bold))
            if let description = template.localizedDescription {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label(
                    "\(template.basePointCost)",
                    systemImage: "sparkles"
                )
                Spacer()
                Label(
                    "\(template.usageCount)",
                    systemImage: "chart.bar.fill"
                )
            }
            .font(.subheadline)
        }
    }

    private var templateViewerItems: [AISMediaViewerItem] {
        guard let imageURL = template.imageURL else { return [] }
        return [
            AISMediaViewerItem(
                id: "template:\(template.id)",
                originalURL: imageURL,
                title: template.localizedName
            )
        ]
    }

    private func presentTemplateImage() {
        guard let item = templateViewerItems.first else { return }
        imageViewerRoute = AISMediaViewerRoute(id: item.id)
    }

    @ViewBuilder
    private var sameTemplateCasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("templates.detail.cases")
                .font(.title3.bold())

            if casesModel.isLoading && casesModel.jobs.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(minHeight: 120)
            } else if casesModel.jobs.isEmpty {
                ContentUnavailableView(
                    "templates.detail.cases.empty",
                    systemImage: "photo.stack"
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12, alignment: .top),
                        GridItem(.flexible(), spacing: 12, alignment: .top)
                    ],
                    spacing: 12
                ) {
                    ForEach(casesModel.jobs) { job in
                        Button {
                            selectedCase = job
                        } label: {
                            GalleryCard(job: job)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(
                            "templates.detail.cases.view_hint"
                        )
                    }
                }
            }
        }
    }
}

@MainActor
@Observable
private final class TemplateCasesViewModel {
    private let api = APIClient()
    private(set) var jobs: [GalleryJob] = []
    private(set) var isLoading = false

    func load(templateID: String, force: Bool = false) async {
        guard !templateID.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let language = AISLocalization.isChinese ? "zh" : "en"
        let cacheKey = AISResponseCache.key(
            scope: "public",
            resource: "style-template-cases",
            parameters: [
                "templateId": templateID,
                "language": language,
                "size": "12"
            ]
        )
        if !force,
           let cached = await AISResponseCache.shared.read(
               PageResponse<GalleryJob>.self,
               key: cacheKey,
               allowsStale: true
           ) {
            jobs = cached.value.items.filter { $0.mediaURL != nil }
            if cached.isFresh { return }
        }

        do {
            let page: PageResponse<GalleryJob> = try await api.get(
                "/api/ais/jobs/gallery",
                query: [
                    URLQueryItem(name: "styleTemplateId", value: templateID),
                    URLQueryItem(name: "size", value: "12"),
                    URLQueryItem(name: "language", value: language)
                ]
            )
            jobs = page.items.filter { $0.mediaURL != nil }
            await AISResponseCache.shared.write(page, key: cacheKey)
        } catch {
            if jobs.isEmpty {
                jobs = []
            }
        }
    }
}

private struct TemplatePreparationView: View {
    let template: StyleTemplate

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(AISAppDataStore.self) private var appData
    @State private var configuration = AISCreationConfigurationStore()
    @State private var viewModel = TemplatePreparationViewModel()
    @State private var detail: StyleTemplate?
    @State private var aspectRatio = ""
    @State private var resolution = ""
    @State private var selectedModelKey = ""
    @State private var textValues: [String: String] = [:]
    @State private var activeTextFieldKey = ""
    @FocusState private var focusedFieldKey: String?
    @State private var additionalRequirement = ""
    @AppStorage("ais.promo_mark_enabled")
    private var promoMarkEnabled = false
    @AppStorage("ais.recommend_to_gallery")
    private var recommendToGallery = true
    @State private var confirmsGeneration = false
    @State private var selectedReferenceItem: PhotosPickerItem?
    @State private var activeSlotKey = ""
    @State private var librarySlotKey = ""
    @State private var presentsPhotoPicker = false
    @State private var presentsAssetLibrary = false
    @State private var confirmsUploadCompliance = false
    @State private var selectedResultTask: AISTaskJob?
    @AppStorage("ais.upload_agreement.accepted.2026-07")
    private var acceptedUploadCompliance = false

    private var activeTemplate: StyleTemplate { detail ?? template }
    private var pricingRules: AISPricingRulesStore {
        appData.pricingRules
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AISPageBackground()
                if let job = viewModel.activeJob {
                    taskStatus(job)
                } else {
                    preparationForm
                }
            }
            .navigationTitle("templates.creation.title")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if viewModel.activeJob == nil {
                    generationButton
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                }
            }
            .onChange(of: viewModel.activeJob?.status) { _, status in
                if status != nil {
                    focusedFieldKey = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        focusedFieldKey = nil
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("common.done") {
                        focusedFieldKey = nil
                    }
                }
            }
            .task(id: session.user?.id) {
                let token = await session.validAccessToken()
                await configuration.load(
                    userID: session.user?.id,
                    accessToken: token,
                    templateID: template.id
                )
                await viewModel.loadDetail(
                    templateID: template.id,
                    accessToken: token
                )
                detail = viewModel.templateDetail
                applyDefaults()
                await restoreDraft()
                if let jobID = viewModel.activeJobID {
                    await viewModel.monitor(jobID: jobID, accessToken: token)
                }
            }
            .task(id: "pricing|\(session.user?.id ?? "")") {
                let token = await session.validAccessToken()
                await pricingRules.load(
                    userID: session.user?.id,
                    accessToken: token
                )
            }
            .task(id: "\(requestSignature)|\(pricingRules.rules?.version ?? "")") {
                guard detail != nil, !aspectRatio.isEmpty,
                      !resolution.isEmpty, let rules = pricingRules.rules else {
                    viewModel.clearLocalQuote()
                    return
                }
                viewModel.updateLocalQuote(
                    rules: rules,
                    template: activeTemplate,
                    resolution: resolution,
                    selectedModelKey: selectedModelKey,
                    resolutionMultiplier: resolutionSpecs.first {
                        $0.value == resolution
                    }?.multiplier ?? 1,
                    modelMultiplier: configuration.models.first {
                        $0.displayModelKey == selectedModelKey
                    }?.modelMarkupRate ?? 1,
                    promoMarkEnabled: promoMarkEnabled
                )
            }
            .task(id: draftSignature) {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, session.isAuthenticated else { return }
                await saveDraft()
            }
            .onChange(of: selectedReferenceItem) { _, item in
                guard let item, !activeSlotKey.isEmpty else { return }
                Task {
                    await viewModel.loadReference(
                        from: item,
                        slotKey: activeSlotKey
                    )
                    selectedReferenceItem = nil
                }
            }
            .photosPicker(
                isPresented: $presentsPhotoPicker,
                selection: $selectedReferenceItem,
                matching: .images
            )
            .sheet(isPresented: $presentsAssetLibrary) {
                AISAssetLibraryPicker(
                    accessToken: session.accessToken,
                    maximumSelectionCount: 1
                ) { assets in
                    if let asset = assets.first {
                        viewModel.setLibraryReference(
                            asset,
                            slotKey: librarySlotKey
                        )
                    }
                }
            }
            .sheet(item: $selectedResultTask) { task in
                TaskDetailView(
                    job: task,
                    estimateSeconds: nil,
                    onDeleted: {
                        selectedResultTask = nil
                        viewModel.clearActiveJob()
                    },
                    onContinueEditing: nil
                )
            }
            .alert(
                "templates.creation.confirm.title",
                isPresented: $confirmsGeneration
            ) {
                Button("common.cancel", role: .cancel) {}
                Button("templates.creation.confirm.action") {
                    Task { await generate() }
                }
            } message: {
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "templates.creation.confirm.message"),
                        viewModel.quote?.points ?? activeTemplate.basePointCost
                    )
                )
            }
            .alert(
                "upload.compliance.title",
                isPresented: $confirmsUploadCompliance
            ) {
                Button("common.cancel", role: .cancel) {}
                Button("upload.compliance.accept") {
                    acceptedUploadCompliance = true
                    presentsPhotoPicker = true
                }
            } message: {
                Text("upload.compliance.message")
            }
        }
    }

    private var preparationForm: some View {
        GeometryReader { proxy in
            ScrollView {
                preparationContent(availableWidth: proxy.size.width)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private func preparationContent(availableWidth: CGFloat) -> some View {
        let error = validationMessage
            ?? viewModel.errorMessage
            ?? missingSelectionMessage
        if AISResponsiveLayout.usesWideCreationLayout(for: availableWidth) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    templateSummary
                    if !activeTemplate.imageSlots.isEmpty {
                        imageSlotsSection
                    }
                    if !enabledTextFields.isEmpty {
                        copySection
                    }
                    requirementSection
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 18) {
                    outputSettings
                    publishingSection
                    if let error {
                        preparationError(error)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .responsivePreparationFrame(availableWidth: availableWidth)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                templateSummary
                if !activeTemplate.imageSlots.isEmpty {
                    imageSlotsSection
                }
                if !enabledTextFields.isEmpty {
                    copySection
                }
                outputSettings
                requirementSection
                publishingSection
                if let error {
                    preparationError(error)
                }
            }
            .responsivePreparationFrame(availableWidth: availableWidth)
        }
    }

    private func preparationError(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .red.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 16)
            )
    }

    private var templateSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                TemplateArtwork(
                    url: activeTemplate.imageURL,
                    preset: .thumbnail,
                    fallbackAspectRatio: activeTemplate.displayAspectRatio
                )
                .frame(width: 96, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 6) {
                    Text(activeTemplate.localizedName).font(.headline)
                    Text(
                        activeTemplate.localizedDescription
                            ?? String(localized: "templates.creation.sample_reference")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                }
            }
            if enabledTextFields.contains(where: \.hasRegion),
               activeTemplate.imageURL != nil {
                TemplateTextHotspotPreview(
                    template: activeTemplate,
                    fields: enabledTextFields,
                    activeFieldKey: $activeTextFieldKey
                )
            }
        }
        .padding(14)
        .aisSurface(cornerRadius: 20)
    }

    private var imageSlotsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(
                "templates.creation.slots",
                systemImage: "photo.stack"
            )
            ForEach(activeTemplate.imageSlots.sorted { $0.sort < $1.sort }) {
                slot in
                TemplateImageSlotCard(
                    slot: slot,
                    reference: viewModel.slotReferences[slot.slotKey],
                    onPhotos: { beginSelecting(slot.slotKey) },
                    onLibrary: {
                        librarySlotKey = slot.slotKey
                        presentsAssetLibrary = true
                    },
                    onRemove: {
                        viewModel.removeReference(slotKey: slot.slotKey)
                    }
                )
            }
            Text("templates.creation.reference.upload_notice.ai")
                .font(.caption2)
                .foregroundStyle(AISTheme.accentSecondary)
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private var copySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(
                "templates.creation.copy",
                systemImage: "textformat"
            )
            ForEach(enabledTextFields) { field in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(field.localizedName)
                            .font(.caption.weight(.semibold))
                        if field.isRequired {
                            Text("*").foregroundStyle(.red)
                        }
                        Spacer()
                        Text(
                            "\(textValues[field.fieldKey, default: ""].count)/\(field.maxLength)"
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    TextField(
                        field.localizedPlaceholder,
                        text: textBinding(field.fieldKey),
                        axis: .vertical
                    )
                    .focused(
                        $focusedFieldKey,
                        equals: "copy:\(field.fieldKey)"
                    )
                    .lineLimit(2...5)
                    .padding(12)
                    .background(
                        focusedFieldKey == "copy:\(field.fieldKey)"
                            ? AISTheme.accent.opacity(0.08)
                            : Color(uiColor: .tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .onTapGesture {
                        activeTextFieldKey = field.fieldKey
                    }
                }
            }
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private var outputSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(
                "templates.creation.output",
                systemImage: "slider.horizontal.3"
            )
            templateSpecPicker(
                title: String(localized: "templates.creation.aspect_ratio"),
                specs: aspectSpecs,
                selection: $aspectRatio
            )
            templateSpecPicker(
                title: String(localized: "templates.creation.resolution"),
                specs: resolutionSpecs,
                selection: $resolution
            )
            AISGenerationModelPicker(
                models: configuration.models,
                selectedModelKey: $selectedModelKey,
                allowsSelection: activeTemplate.allowUserOverrideModel
            )
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private func templateSpecPicker(
        title: String,
        specs: [AISModelOutputSpec],
        selection: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold))
            AISFlowLayout(spacing: 8) {
                ForEach(specs) { spec in
                    AISChoiceChip(
                        title: spec.localizedName,
                        detail: spec.value,
                        isSelected: selection.wrappedValue == spec.value,
                        isAvailable: spec.isAvailable,
                        badge: spec.membershipLabel,
                        pricingBadge: AISPointMultiplierFormatter.visibleLabel(
                            spec.multiplier
                        )
                    ) {
                        selection.wrappedValue = spec.value
                    }
                }
            }
        }
    }

    private var requirementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(
                "templates.creation.requirement",
                systemImage: "text.alignleft"
            )
            TextField(
                "templates.creation.requirement.placeholder",
                text: $additionalRequirement,
                axis: .vertical
            )
            .focused($focusedFieldKey, equals: "additional-requirement")
            .lineLimit(3...6)
            .padding(14)
            .background(
                Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private var publishingSection: some View {
        VStack(spacing: 14) {
            if let membershipDiscountHelper {
                Label(
                    membershipDiscountHelper,
                    systemImage: "building.2.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            Toggle(isOn: $promoMarkEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("creation.promo.title")
                        .font(.subheadline.weight(.semibold))
                    Text(
                        promoMarkEnabled
                            && viewModel.quote?.promoMarkEnabled == false
                            && viewModel.quote?.promoMarkSuppressedReason != nil
                            ? String(localized: "creation.promo.suppressed")
                            : promoMarkEnabled
                            && (viewModel.promoSavedPoints ?? 0) > 0
                            ? String.localizedStringWithFormat(
                                String(localized: "creation.promo.saved"),
                                viewModel.promoSavedPoints ?? 0
                            )
                            : String(localized: "creation.promo.helper")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .tint(AISTheme.accent)
            Divider()
            Toggle(isOn: $recommendToGallery) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("templates.creation.gallery")
                        .font(.subheadline.weight(.semibold))
                    Text("templates.creation.gallery.helper")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(AISTheme.accent)
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private var membershipDiscountHelper: String? {
        guard let saved = viewModel.quote?.savedPoints,
              saved > 0 else {
            return nil
        }
        let name = viewModel.quote?.effectiveBenefitName
            ?? String(localized: "creation.membership.default")
        return String.localizedStringWithFormat(
            String(localized: "creation.discount.effective"),
            name,
            NSDecimalNumber(
                decimal: viewModel.quote?.effectiveDiscountPercent ?? 0
            ).doubleValue,
            saved
        )
    }

    private func taskStatus(_ job: AISTaskJob) -> some View {
        VStack(spacing: 18) {
            Label(
                job.isSuccessful
                    ? "creation.status.succeeded"
                    : job.status.lowercased() == "failed"
                        ? "creation.status.failed"
                        : "creation.status.processing",
                systemImage: job.isSuccessful
                    ? "checkmark.circle.fill"
                    : "clock.arrow.circlepath"
            )
            .font(.title3.bold())
            .foregroundStyle(AISTheme.accent)
            ProgressView(value: Double(job.progress), total: 100)
                .tint(AISTheme.accent)
            Text("\(job.progress)%").font(.caption.monospacedDigit())
            if let error = job.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if job.isSuccessful {
                Button("creation.view_result") {
                    focusedFieldKey = nil
                    selectedResultTask = job
                }
                .buttonStyle(.borderedProminent)
                .tint(AISTheme.accent)
            }
            Button("templates.creation.done") {
                focusedFieldKey = nil
                dismiss()
            }
            .buttonStyle(.bordered)
            .tint(AISTheme.accent)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .aisSurface(cornerRadius: 24)
        .padding()
    }

    private var generationButton: some View {
        Button {
            focusedFieldKey = nil
            if canRetryPricingRules {
                Task { await retryPricingRules() }
                return
            }
            if validationMessage == nil {
                confirmsGeneration = true
            }
        } label: {
            HStack {
                if viewModel.isGenerating
                    || viewModel.isUploading
                    || configuration.isLoading
                    || (
                        session.isAuthenticated
                            && !appData.isGenerationReady
                            && !appData.generationLoadFailed
                    ) {
                    ProgressView().tint(.white)
                }
                VStack(spacing: 2) {
                    Text(generationButtonTitle)
                    if let subtitle = generationButtonSubtitle {
                        Text(subtitle)
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            .aisPrimaryButton(
                isEnabled: canGenerate || canRetryPricingRules
            )
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate && !canRetryPricingRules)
    }

    private var generationButtonTitle: String {
        if viewModel.isGenerating || viewModel.isUploading {
            return String(localized: "templates.creation.submitting")
        }
        if canRetryPricingRules {
            return String(localized: "creation.pricing.retry")
        }
        return String(localized: "templates.creation.confirm.action")
    }

    private var generationButtonSubtitle: String? {
        guard !viewModel.isGenerating, !viewModel.isUploading else {
            return nil
        }
        if !appData.isGenerationReady {
            return appData.generationLoadFailed
                ? String(localized: "creation.data.reload")
                : String(localized: "creation.data.loading")
        }
        if configuration.isLoading {
            return String(localized: "creation.data.loading")
        }
        if let quote = viewModel.quote {
            if quote.savedPoints > 0 {
                return String.localizedStringWithFormat(
                    String(
                        localized: "creation.generate.estimated_discounted"
                    ),
                    quote.points,
                    quote.originalPoints,
                    quote.savedPoints
                )
            }
            return String.localizedStringWithFormat(
                String(localized: "creation.generate.estimated"),
                quote.points
            )
        }
        return pricingRules.isLoading
            ? String(localized: "creation.quoting")
            : String(localized: "creation.estimate.unavailable")
    }

    private var canGenerate: Bool {
        viewModel.quote != nil
            && appData.isGenerationReady
            && !viewModel.isGenerating
            && !viewModel.isUploading
            && validationMessage == nil
            && !aspectRatio.isEmpty
            && !resolution.isEmpty
            && selectedModelIsUsable
    }

    private var canRetryPricingRules: Bool {
        session.isAuthenticated
            && (
                appData.generationLoadFailed
                    || configuration.errorMessage != nil
            )
            && !appData.isRefreshingUserData
            && !pricingRules.isLoading
            && !configuration.isLoading
    }

    private func retryPricingRules() async {
        let token = await session.validAccessToken()
        async let appDataReload: Void = appData.retryGenerationPrerequisites(
            session: session
        )
        async let templateConfigurationReload: Void = configuration.load(
            userID: session.user?.id,
            accessToken: token,
            templateID: template.id,
            force: true
        )
        _ = await (appDataReload, templateConfigurationReload)
        applyDefaults()
    }

    private var selectedModelIsUsable: Bool {
        configuration.models.contains {
            guard $0.displayModelKey == selectedModelKey, $0.canUse else {
                return false
            }
            return !activeTemplate.allowUserOverrideModel || $0.canSelect
        }
    }

    private var validationMessage: String? {
        guard let issue = activeTemplate.validationIssues(
            filledSlotKeys: Set(viewModel.slotReferences.keys),
            textValues: textValues
        ).first else {
            return nil
        }
        switch issue {
        case let .requiredSlot(slotKey):
            let name = activeTemplate.imageSlots.first {
                $0.slotKey == slotKey
            }?.localizedName ?? slotKey
            return String.localizedStringWithFormat(
                String(localized: "templates.creation.slot.required"),
                name
            )
        case let .requiredText(fieldKey):
            let name = activeTemplate.textFields.first {
                $0.fieldKey == fieldKey
            }?.localizedName ?? fieldKey
            return String.localizedStringWithFormat(
                String(localized: "templates.creation.field.required"),
                name
            )
        case let .textTooLong(fieldKey, maximum):
            let name = activeTemplate.textFields.first {
                $0.fieldKey == fieldKey
            }?.localizedName ?? fieldKey
            return String.localizedStringWithFormat(
                String(localized: "templates.creation.field.too_long"),
                name,
                maximum
            )
        }
    }

    private var missingSelectionMessage: String? {
        if aspectRatio.isEmpty {
            return String(localized: "templates.creation.aspect_ratio.required")
        }
        if resolution.isEmpty {
            return String(localized: "templates.creation.resolution.required")
        }
        if selectedModelKey.isEmpty {
            return String(localized: "templates.creation.model.required")
        }
        return nil
    }

    private var enabledTextFields: [StyleTemplateTextField] {
        activeTemplate.textFields
            .filter(\.enabled)
            .sorted { $0.sort < $1.sort }
    }

    private var aspectSpecs: [AISModelOutputSpec] {
        filteredSpecs(
            configuration.specs("aspect_ratio"),
            allowed: activeTemplate.aspectRatios
        )
    }

    private var resolutionSpecs: [AISModelOutputSpec] {
        filteredSpecs(
            configuration.specs("resolution"),
            allowed: activeTemplate.resolutions
        )
    }

    private func filteredSpecs(
        _ specs: [AISModelOutputSpec],
        allowed: [String]
    ) -> [AISModelOutputSpec] {
        guard !allowed.isEmpty else { return specs }
        return specs.filter { allowed.contains($0.value) }
    }

    private var requestSignature: String {
        "\(aspectRatio)|\(resolution)|\(selectedModelKey)|\(promoMarkEnabled)"
    }

    private var draftSignature: String {
        let slotSignature = viewModel.slotReferences
            .sorted { $0.key < $1.key }
            .map {
                [
                    $0.key,
                    $0.value.id.uuidString,
                    $0.value.remoteAssetID ?? "",
                    String($0.value.data?.count ?? 0)
                ].joined(separator: ":")
            }
            .joined(separator: "|")
        let copySignature = textValues
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return [
            requestSignature,
            copySignature,
            additionalRequirement,
            String(recommendToGallery),
            slotSignature
        ].joined(separator: "||")
    }

    private func applyDefaults() {
        aspectRatio = activeTemplate.defaultAspectRatio
            ?? aspectSpecs.first(where: \.isAvailable)?.value
            ?? ""
        resolution = activeTemplate.defaultResolution
            ?? resolutionSpecs.first(where: \.isAvailable)?.value
            ?? ""
        selectedModelKey = activeTemplate.defaultDisplayModelKey
            ?? configuration.models.first(where: {
                $0.isRecommended && $0.canUse
            })?.displayModelKey
            ?? configuration.models.first(where: \.canUse)?.displayModelKey
            ?? ""
        textValues = Dictionary(
            uniqueKeysWithValues: enabledTextFields.map {
                ($0.fieldKey, $0.defaultValue ?? "")
            }
        )
        activeTextFieldKey = enabledTextFields.first?.fieldKey ?? ""
        activeSlotKey = activeTemplate.imageSlots.sorted { $0.sort < $1.sort }
            .first?.slotKey ?? ""
    }

    private func beginSelecting(_ slotKey: String) {
        activeSlotKey = slotKey
        if acceptedUploadCompliance {
            presentsPhotoPicker = true
        } else {
            confirmsUploadCompliance = true
        }
    }

    private func textBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { textValues[key, default: ""] },
            set: { textValues[key] = $0 }
        )
    }

    private func makeRequest(
        referenceAssetIDs: [String]
    ) -> StyleTemplateApplyRequest {
        let slots = activeTemplate.imageSlots
            .sorted { $0.sort < $1.sort }
            .enumerated()
            .compactMap { index, slot -> StyleTemplateSlotSnapshot? in
                guard let reference = viewModel.slotReferences[slot.slotKey],
                      let assetID = reference.remoteAssetID else { return nil }
                return StyleTemplateSlotSnapshot(
                    slotKey: slot.slotKey,
                    slotIndex: index + 1,
                    name: slot.localizedName,
                    description: slot.localizedDescription,
                    assetId: assetID
                )
            }
        return StyleTemplateApplyRequest(
            sourceAssetId: referenceAssetIDs.first,
            referenceAssetIds: referenceAssetIDs,
            textValues: textValues,
            entry: "ios_native",
            language: AISLocalization.isChinese ? "zh" : "en",
            aspectRatio: aspectRatio,
            resolution: resolution,
            additionalRequirement: additionalRequirement
                .trimmingCharacters(in: .whitespacesAndNewlines),
            recommendToGallery: recommendToGallery,
            promoMarkEnabled: promoMarkEnabled,
            selectedDisplayModelKey: selectedModelKey.nilIfEmpty,
            clientSnapshot: StyleTemplateClientSnapshot(
                templateKey: activeTemplate.templateKey,
                templateName: activeTemplate.localizedName,
                imageSlots: slots,
                textValues: textValues,
                selectedAspectRatio: aspectRatio,
                selectedResolution: resolution,
                additionalRequirement: additionalRequirement,
                recommendToGallery: recommendToGallery,
                promoMarkEnabled: promoMarkEnabled,
                selectedDisplayModelKey: selectedModelKey.nilIfEmpty
            ),
            pricingRulesVersion: pricingRules.rules?.version,
            localCalculatedPoints: viewModel.quote?.points
        )
    }

    private func generate() async {
        focusedFieldKey = nil
        if let status = await AISMaintenanceService.checkGeneration() {
            NotificationCenter.default.post(name: .aisMaintenanceBlocked, object: status)
            return
        }
        guard appData.isGenerationReady else {
            await appData.retryGenerationPrerequisites(session: session)
            return
        }
        let token = await session.validAccessToken()
        let ids = await viewModel.uploadReferences(accessToken: token)
        guard viewModel.errorMessage == nil else { return }
        await viewModel.generate(
            template: activeTemplate,
            request: makeRequest(referenceAssetIDs: ids),
            accessToken: token
        )
        if let latest = viewModel.takePendingPricingRulesUpdate() {
            await pricingRules.replace(
                latest,
                userID: session.user?.id
            )
        }
        await saveDraft()
        if let jobID = viewModel.activeJobID {
            await viewModel.monitor(jobID: jobID, accessToken: token)
        }
    }

    private func saveDraft() async {
        guard let userID = session.user?.id else { return }
        await viewModel.saveDraft(
            userID: userID,
            templateID: activeTemplate.id,
            state: TemplateDraftState(
                aspectRatio: aspectRatio,
                resolution: resolution,
                selectedModelKey: selectedModelKey,
                textValues: textValues,
                additionalRequirement: additionalRequirement,
                recommendToGallery: recommendToGallery
            )
        )
    }

    private func restoreDraft() async {
        guard let userID = session.user?.id,
              let draft = await viewModel.restoreDraft(
                userID: userID,
                templateID: activeTemplate.id
              ) else { return }
        if aspectSpecs.contains(where: {
            $0.value == draft.state.aspectRatio && $0.isAvailable
        }) {
            aspectRatio = draft.state.aspectRatio
        }
        if resolutionSpecs.contains(where: {
            $0.value == draft.state.resolution && $0.isAvailable
        }) {
            resolution = draft.state.resolution
        }
        if activeTemplate.allowUserOverrideModel,
           configuration.models.contains(where: {
               $0.displayModelKey == draft.state.selectedModelKey
                   && $0.canUse
                   && $0.canSelect
           }) {
            selectedModelKey = draft.state.selectedModelKey
        }
        textValues.merge(draft.state.textValues) { _, saved in saved }
        additionalRequirement = draft.state.additionalRequirement
        recommendToGallery = draft.state.recommendToGallery
    }

    private func sectionTitle(
        _ title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

private extension View {
    func responsivePreparationFrame(
        availableWidth: CGFloat
    ) -> some View {
        frame(
            maxWidth: AISResponsiveLayout.maximumContentWidth,
            alignment: .leading
        )
        .padding(
            .horizontal,
            AISResponsiveLayout.horizontalPadding(for: availableWidth)
        )
        .padding(.top, 10)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }
}

private struct TemplateSlotReference {
    let id: UUID
    var data: Data?
    var image: UIImage?
    var remoteAssetID: String?
    var remoteURL: URL?
    var fileName: String
    var mimeType: String
}

struct TemplateDraftState: Codable {
    let aspectRatio: String
    let resolution: String
    let selectedModelKey: String
    let textValues: [String: String]
    let additionalRequirement: String
    let recommendToGallery: Bool
}

private struct TemplateSlotDraft: Codable {
    let slotKey: String
    let id: UUID
    let data: Data?
    let remoteAssetID: String?
    let remoteURL: URL?
    let fileName: String
    let mimeType: String
}

private struct TemplateStoredDraft: Codable {
    let state: TemplateDraftState
    let slots: [TemplateSlotDraft]
    let activeJobID: String?
}

@MainActor
@Observable
private final class TemplatePreparationViewModel {
    private let api = APIClient()

    private(set) var templateDetail: StyleTemplate?
    private(set) var quote: StyleTemplatePointQuote?
    private(set) var membershipSavedPoints: Int?
    private(set) var promoSavedPoints: Int?
    private var pendingPricingRulesUpdate: AISPricingRulesSnapshot?
    private(set) var isGenerating = false
    private(set) var isUploading = false
    private(set) var slotReferences: [String: TemplateSlotReference] = [:]
    private(set) var activeJobID: String?
    private(set) var activeJob: AISTaskJob?
    var errorMessage: String?

    func loadDetail(templateID: String, accessToken: String?) async {
        do {
            templateDetail = try await api.get(
                "/api/ais/style-templates/\(templateID)",
                accessToken: accessToken
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadReference(from item: PhotosPickerItem, slotKey: String) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = String(localized: "templates.creation.reference.invalid")
            return
        }
        let upload = image.aisTemplateUploadPayload(
            preservesPNG: data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        )
        guard let upload else {
            errorMessage = String(localized: "templates.creation.reference.invalid")
            return
        }
        slotReferences[slotKey] = TemplateSlotReference(
            id: UUID(),
            data: upload.data,
            image: upload.image,
            remoteAssetID: nil,
            remoteURL: nil,
            fileName: "\(slotKey).\(upload.fileExtension)",
            mimeType: upload.mimeType
        )
    }

    func setLibraryReference(
        _ asset: AISAssetLibraryItem,
        slotKey: String
    ) {
        slotReferences[slotKey] = TemplateSlotReference(
            id: UUID(),
            data: nil,
            image: nil,
            remoteAssetID: asset.id,
            remoteURL: asset.resolvedURL,
            fileName: asset.resolvedName,
            mimeType: "image/jpeg"
        )
    }

    func removeReference(slotKey: String) {
        slotReferences.removeValue(forKey: slotKey)
    }

    func updateLocalQuote(
        rules: AISPricingRulesSnapshot,
        template: StyleTemplate,
        resolution: String,
        selectedModelKey: String,
        resolutionMultiplier: Decimal,
        modelMultiplier: Decimal,
        promoMarkEnabled: Bool
    ) {
        errorMessage = nil
        let local = AISLocalPricingCalculator.template(
            snapshot: rules,
            basePoints: template.basePointCost,
            defaultResolution: template.defaultResolution,
            resolution: resolution,
            selectedModelKey: selectedModelKey,
            fallbackResolutionMultiplier: resolutionMultiplier,
            fallbackModelMultiplier: modelMultiplier,
            promoMarkEnabled: promoMarkEnabled
        )
        quote = StyleTemplatePointQuote(
            points: local.points,
            originalPoints: local.originalPoints,
            savedPoints: local.savedPoints,
            effectiveDiscountPercent: local.effectiveDiscountPercent,
            effectiveBenefitName: local.effectiveBenefitName,
            effectiveBenefitSource: local.effectiveBenefitSource,
            discountPolicy: "max",
            promoMarkEnabled: local.promoMarkApplied,
            promoMarkSuppressedReason: local.promoMarkSuppressedReason
        )
        membershipSavedPoints = AISLocalPricingCalculator
            .membershipSavedPoints(
                snapshot: rules,
                originalPoints: local.originalPoints
            )
        promoSavedPoints = local.promoMarkApplied ? local.savedPoints : 0
    }

    func clearLocalQuote() {
        quote = nil
        membershipSavedPoints = nil
        promoSavedPoints = nil
    }

    func takePendingPricingRulesUpdate() -> AISPricingRulesSnapshot? {
        defer { pendingPricingRulesUpdate = nil }
        return pendingPricingRulesUpdate
    }

    func uploadReferences(accessToken: String?) async -> [String] {
        guard let accessToken, !isUploading else { return [] }
        isUploading = true
        defer { isUploading = false }
        errorMessage = nil
        do {
            for key in slotReferences.keys.sorted() {
                guard slotReferences[key]?.remoteAssetID == nil,
                      var reference = slotReferences[key] else { continue }
                if let image = reference.image,
                   let normalized = image.aisTemplateUploadPayload(
                       preservesPNG: reference.mimeType == "image/png"
                   ) {
                    reference.data = normalized.data
                    reference.image = normalized.image
                    reference.fileName = "\(key).\(normalized.fileExtension)"
                    reference.mimeType = normalized.mimeType
                    slotReferences[key] = reference
                }
                guard let data = reference.data else { continue }
                let asset: AISAssetUploadResult = try await api.upload(
                    "/api/ais/assets",
                    fileData: data,
                    fileName: reference.fileName,
                    mimeType: reference.mimeType,
                    accessToken: accessToken,
                    fields: [
                        "assetType": "reference",
                        "referenceRole": "template_image_slot",
                        "preserveMode": "reference",
                        "displayName": key,
                        "userNote": key
                    ]
                )
                slotReferences[key]?.remoteAssetID = asset.id
            }
            return slotReferences.keys.sorted().compactMap {
                slotReferences[$0]?.remoteAssetID
            }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func generate(
        template: StyleTemplate,
        request: StyleTemplateApplyRequest,
        accessToken: String?
    ) async {
        guard let accessToken, !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            let result: StyleTemplateGenerationResult = try await api.post(
                "/api/ais/style-templates/\(template.id)/generate",
                body: request,
                accessToken: accessToken
            )
            activeJobID = result.jobId
            NotificationCenter.default.post(
                name: .aisTaskSubmitted,
                object: result.jobId
            )
        } catch let APIError.business(code, _, details)
            where code == .priceChanged {
            let previousPoints = quote?.points ?? request.localCalculatedPoints
            if let change = AISPriceChangePayload(details: details),
               let latestRules = change.latestPricingRules {
                pendingPricingRulesUpdate = latestRules
                let local = AISLocalPricingCalculator.template(
                    snapshot: latestRules,
                    basePoints: template.basePointCost,
                    defaultResolution: template.defaultResolution,
                    resolution: request.resolution,
                    selectedModelKey: request.selectedDisplayModelKey ?? "",
                    promoMarkEnabled: request.promoMarkEnabled
                )
                quote = StyleTemplatePointQuote(
                    points: local.points,
                    originalPoints: local.originalPoints,
                    savedPoints: local.savedPoints,
                    effectiveDiscountPercent: local.effectiveDiscountPercent,
                    effectiveBenefitName: local.effectiveBenefitName,
                    effectiveBenefitSource: local.effectiveBenefitSource,
                    discountPolicy: "max",
                    promoMarkEnabled: local.promoMarkApplied,
                    promoMarkSuppressedReason: local.promoMarkSuppressedReason
                )
                membershipSavedPoints = AISLocalPricingCalculator
                    .membershipSavedPoints(
                        snapshot: latestRules,
                        originalPoints: local.originalPoints
                    )
                promoSavedPoints = local.promoMarkApplied
                    ? local.savedPoints
                    : 0
                errorMessage = String.localizedStringWithFormat(
                    String(localized: "creation.price_changed.detail"),
                    previousPoints ?? change.localCalculatedPoints
                        ?? change.points,
                    local.points
                )
            } else {
                errorMessage = String(localized: "creation.price_changed")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func monitor(jobID: String, accessToken: String?) async {
        guard let accessToken else { return }
        do {
            for _ in 0..<120 {
                try Task.checkCancellation()
                let job: AISTaskJob = try await api.get(
                    "/api/ais/jobs/\(jobID)",
                    accessToken: accessToken
                )
                activeJob = job
                if !job.isActive { return }
                try await Task.sleep(for: .seconds(2))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearActiveJob() {
        activeJob = nil
        activeJobID = nil
    }

    func saveDraft(
        userID: String,
        templateID: String,
        state: TemplateDraftState
    ) async {
        let stored = TemplateStoredDraft(
            state: state,
            slots: slotReferences.map { key, value in
                TemplateSlotDraft(
                    slotKey: key,
                    id: value.id,
                    data: value.data,
                    remoteAssetID: value.remoteAssetID,
                    remoteURL: value.remoteURL,
                    fileName: value.fileName,
                    mimeType: value.mimeType
                )
            },
            activeJobID: activeJobID
        )
        await AISResponseCache.shared.write(
            stored,
            key: Self.draftKey(userID, templateID),
            encrypted: true
        )
    }

    func restoreDraft(
        userID: String,
        templateID: String
    ) async -> TemplateStoredDraft? {
        guard let cached = await AISResponseCache.shared.read(
            TemplateStoredDraft.self,
            key: Self.draftKey(userID, templateID),
            ttl: 7 * 24 * 60 * 60,
            encrypted: true
        ) else { return nil }
        slotReferences = Dictionary(
            uniqueKeysWithValues: cached.value.slots.compactMap { item in
                let image = item.data.flatMap(UIImage.init(data:))
                guard image != nil || item.remoteAssetID != nil else {
                    return nil
                }
                return (
                    item.slotKey,
                    TemplateSlotReference(
                        id: item.id,
                        data: item.data,
                        image: image,
                        remoteAssetID: item.remoteAssetID,
                        remoteURL: item.remoteURL,
                        fileName: item.fileName,
                        mimeType: item.mimeType
                    )
                )
            }
        )
        activeJobID = cached.value.activeJobID
        return cached.value
    }

    private static func draftKey(
        _ userID: String,
        _ templateID: String
    ) -> String {
        AISResponseCache.key(
            scope: "user:\(userID)",
            resource: "template-draft-\(templateID)-v2"
        )
    }
}

private struct AISTemplateUploadPayload {
    let data: Data
    let image: UIImage
    let fileExtension: String
    let mimeType: String
}

private extension UIImage {
    func aisTemplateUploadPayload(
        preservesPNG: Bool,
        maximumDimension: CGFloat = 4096
    ) -> AISTemplateUploadPayload? {
        let width = size.width * scale
        let height = size.height * scale
        guard width > 0, height > 0 else { return nil }
        let resizeScale = min(1, maximumDimension / max(width, height))
        let outputSize = CGSize(
            width: max(1, width * resizeScale),
            height: max(1, height * resizeScale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !preservesPNG
        let normalized = UIGraphicsImageRenderer(
            size: outputSize,
            format: format
        ).image { context in
            if !preservesPNG {
                UIColor.white.setFill()
                context.cgContext.fill(
                    CGRect(origin: .zero, size: outputSize)
                )
            }
            draw(in: CGRect(origin: .zero, size: outputSize))
        }
        if preservesPNG, let data = normalized.pngData() {
            return AISTemplateUploadPayload(
                data: data,
                image: normalized,
                fileExtension: "png",
                mimeType: "image/png"
            )
        }
        guard let data = normalized.jpegData(compressionQuality: 0.88) else {
            return nil
        }
        return AISTemplateUploadPayload(
            data: data,
            image: normalized,
            fileExtension: "jpg",
            mimeType: "image/jpeg"
        )
    }
}

private struct TemplateImageSlotCard: View {
    let slot: StyleTemplateImageSlot
    let reference: TemplateSlotReference?
    let onPhotos: () -> Void
    let onLibrary: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(slot.localizedName).font(.subheadline.weight(.semibold))
                if slot.required { Text("*").foregroundStyle(.red) }
                Spacer()
                if reference != nil {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                    }
                }
            }
            if let reference {
                if let image = reference.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .frame(maxWidth: .infinity)
                } else if let url = reference.remoteURL {
                    AISCachedAsyncImage(
                        url: url,
                        preset: .thumbnail,
                        module: .projectsAssets
                    ) { phase in
                        if case let .success(image) = phase {
                            image.resizable().scaledToFit()
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxHeight: 180)
                    .frame(maxWidth: .infinity)
                }
            }
            if let description = slot.localizedDescription {
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(action: onPhotos) {
                    Label("creation.source.photos", systemImage: "photo")
                }
                Button(action: onLibrary) {
                    Label("creation.source.library", systemImage: "photo.stack")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            Color(uiColor: .tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }
}

private struct TemplateTextHotspotPreview: View {
    let template: StyleTemplate
    let fields: [StyleTemplateTextField]
    @Binding var activeFieldKey: String

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                AISCachedAsyncImage(
                    url: template.imageURL,
                    preset: .detail,
                    module: .galleryTemplates
                ) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                ForEach(fields.filter(\.hasRegion)) { field in
                    Button {
                        activeFieldKey = field.fieldKey
                    } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                activeFieldKey == field.fieldKey
                                    ? AISTheme.accent.opacity(0.28)
                                    : Color.white.opacity(0.18)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(
                                        AISTheme.accent,
                                        style: StrokeStyle(dash: [4])
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(
                        width: proxy.size.width * (field.regionWidth ?? 0),
                        height: proxy.size.height * (field.regionHeight ?? 0)
                    )
                    .offset(
                        x: proxy.size.width * (field.regionX ?? 0),
                        y: proxy.size.height * (field.regionY ?? 0)
                    )
                    .accessibilityLabel(field.localizedName)
                }
            }
        }
        .aspectRatio(template.displayAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct TemplateArtwork: View {
    let url: URL?
    let preset: AISImagePreset
    let fallbackAspectRatio: CGFloat

    var body: some View {
        AISCachedAsyncImage(
            url: url,
            preset: preset,
            module: .galleryTemplates
        ) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failure:
                placeholder
                    .aspectRatio(fallbackAspectRatio, contentMode: .fit)
            default:
                ZStack {
                    placeholder
                    ProgressView()
                }
                .aspectRatio(fallbackAspectRatio, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)
            Image(systemName: "photo")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
        }
    }
}

/// 按卡片实际高度分配到当前最短列，让不同画幅模板保持瀑布流节奏。
private struct PinterestMasonryLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 0
        let columnWidth = resolvedColumnWidth(for: width)
        var heights = Array(
            repeating: CGFloat.zero,
            count: max(columns, 1)
        )

        for subview in subviews {
            let column = shortestColumn(in: heights)
            let size = subview.sizeThatFits(
                ProposedViewSize(width: columnWidth, height: nil)
            )
            heights[column] += size.height + spacing
        }

        return CGSize(
            width: width,
            height: max((heights.max() ?? 0) - spacing, 0)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let columnWidth = resolvedColumnWidth(for: bounds.width)
        var heights = Array(
            repeating: CGFloat.zero,
            count: max(columns, 1)
        )

        for subview in subviews {
            let column = shortestColumn(in: heights)
            let size = subview.sizeThatFits(
                ProposedViewSize(width: columnWidth, height: nil)
            )
            let x = bounds.minX
                + CGFloat(column) * (columnWidth + spacing)
            let y = bounds.minY + heights[column]

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: columnWidth,
                    height: size.height
                )
            )
            heights[column] += size.height + spacing
        }
    }

    private func resolvedColumnWidth(for width: CGFloat) -> CGFloat {
        let count = CGFloat(max(columns, 1))
        return max((width - spacing * (count - 1)) / count, 0)
    }

    private func shortestColumn(in heights: [CGFloat]) -> Int {
        heights.indices.min { heights[$0] < heights[$1] } ?? 0
    }
}

#Preview("TemplatesView") {
    NavigationStack {
        TemplatesView {}
    }
    .environment(SessionStore())
    .environment(AISAppDataStore())
}
