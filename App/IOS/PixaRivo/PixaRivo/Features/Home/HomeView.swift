import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PixaAccountDataStore.self) private var accountData
    @Environment(PixaMediaRegionStore.self) private var mediaRegion
    @Environment(PixaLanguageStore.self) private var language
    @Environment(PixaNavigationStore.self) private var navigation
    @State private var store = TemplateStore(surface: .home)
    @State private var showsLogin = false
    @State private var searchTask: Task<Void, Never>?
    @State private var activeHomeCopy: PixaResolvedHomeCopy?
    @State private var previousHomeCopyID: String?
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    masthead
                    filterBar
                    if store.filter == .recommended, let featured = store.templates.first {
                        featuredCard(featured)
                            .pixaTemplateImpression(templateID: featured.id) {
                                store.recordImpression(templateID: featured.id)
                            }
                    }
                    sectionTitle("home.trending", trailing: "common.view_all")
                    templateGrid
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(PixaTheme.paper.ignoresSafeArea())
            .background(
                PixaNavigationPopObserver(
                    revision: navigation.popRevision(for: .home)
                )
            )
            .refreshable { await store.load(forceRefresh: true) }
            .task(id: "\(mediaRegion.revision):\(language.locale.identifier)") {
                await store.load(forceRefresh: mediaRegion.revision > 0)
            }
            .task(id: language.locale.identifier) {
                selectHomeCopy()
                await PixaHomeCopyRefreshStore.shared.refreshIfNeeded()
            }
            .onChange(of: navigation.selectedTab) { oldValue, newValue in
                guard oldValue != .home, newValue == .home else { return }
                selectHomeCopy()
            }
            .onChange(of: store.query) { _, query in
                searchTask?.cancel()
                searchTask = Task {
                    if !query.isEmpty {
                        try? await Task.sleep(for: .milliseconds(350))
                    }
                    guard !Task.isCancelled else { return }
                    await store.load()
                }
            }
            .onDisappear { searchTask?.cancel() }
            .sheet(isPresented: $showsLogin) { LoginView() }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isSearchPresented {
                expandedSearch
            } else {
                HStack(spacing: 12) {
                    HStack(spacing: 9) {
                        Image("BrandIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("startup.brand")
                            .font(.system(.title2, design: .serif, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 8)
                    accountActions
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            if let activeHomeCopy {
                Text(activeHomeCopy.eyebrow)
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(activeHomeCopy.title)
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(activeHomeCopy.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("home.greeting")
                    .font(.system(.title2, design: .serif, weight: .bold))
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var accountActions: some View {
        if let points = accountData.balance?.availablePoints {
            HStack(spacing: 8) {
                if let membership = accountData.membershipLevelCode {
                    NavigationLink { MembershipView() } label: {
                        PixaMembershipStatusBadge(levelCode: membership)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink { PointsCenterView() } label: {
                    PixaPointsBadge(points: points, isRefreshing: accountData.isRefreshing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    String.localizedStringWithFormat(
                        AppLanguage.localized("home.available_points"),
                        points
                    )
                )
            }
        } else if session.isAuthenticated {
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: 58, minHeight: 36)
                .background(PixaTheme.accent.opacity(0.1), in: Capsule())
        } else {
            Button("auth.login") { showsLogin = true }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .frame(minHeight: 38)
                .background(PixaTheme.accent, in: Capsule())
                .buttonStyle(.plain)
        }
    }

    private func selectHomeCopy() {
        let selected = PixaHomeCopyPolicy.select(
            from: PixaHomeCopyPersistence.load()?.items ?? [],
            excluding: previousHomeCopyID
        )
        activeHomeCopy = selected
        previousHomeCopyID = selected?.id
    }

    private var expandedSearch: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("home.search", text: $store.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit { isSearchFocused = false }
                if !store.query.isEmpty {
                    Button {
                        store.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("home.search.clear")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(PixaTheme.line) }

            Button("common.cancel") {
                searchTask?.cancel()
                isSearchFocused = false
                isSearchPresented = false
                guard !store.query.isEmpty else { return }
                store.query = ""
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PixaTheme.accent)
            .buttonStyle(.plain)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            if !isSearchPresented {
                Button {
                    isSearchPresented = true
                    Task { @MainActor in
                        isSearchFocused = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.6), in: Circle())
                        .overlay { Circle().stroke(PixaTheme.line) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("home.search")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TemplateFilter.allCases) { filter in
                        filterButton(filter)
                    }
                }
            }
        }
    }

    private func filterButton(_ filter: TemplateFilter) -> some View {
        let isSelected = store.filter == filter
        let isLoading = store.loadingFilter == filter
        return Button {
            Task { await store.select(filter) }
        } label: {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(filter.title)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isSelected ? .white : PixaTheme.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(
            isSelected ? PixaTheme.accent : Color.white.opacity(0.58),
            in: Capsule()
        )
        .overlay { Capsule().stroke(isSelected ? PixaTheme.accent : PixaTheme.line) }
        .buttonStyle(.plain)
    }

    private func featuredCard(_ template: StyleTemplate) -> some View {
        let imageWidth = featuredImageWidth(for: template.displayAspectRatio)
        let cardHeight: CGFloat = 154
        let summary = template.description.nilIfEmpty
            ?? AppLanguage.localized("template.detail.summary")
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("home.editor_pick").font(.title3.bold())
                Spacer()
                Label("home.editor_pick.badge", systemImage: "seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PixaTheme.accent)
            }
            NavigationLink { TemplateDetailView(template: template) } label: {
                HStack(spacing: 12) {
                    ZStack {
                        PixaTheme.paper.opacity(0.72)
                        RemoteArtwork(
                            url: template.imageURL,
                            aspectRatio: template.displayAspectRatio,
                            preset: .list,
                            maximumPixelWidth: 600,
                            contentMode: .fit
                        )
                        .padding(5)
                    }
                    .frame(width: imageWidth, height: cardHeight - 16)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(PixaTheme.line)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(template.name)
                            .font(.headline)
                            .foregroundStyle(PixaTheme.ink)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(template.aspectRatioText)
                                .foregroundStyle(PixaTheme.accent)
                            Text(String.localizedStringWithFormat(
                                AppLanguage.localized("template.replace.summary"),
                                template.imageSlots.count,
                                template.textFields.filter(\.enabled).count
                            ))
                            .foregroundStyle(.secondary)
                        }
                        .font(.caption.weight(.semibold))
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 2)
                        HStack(spacing: 8) {
                            Text(String.localizedStringWithFormat(
                                AppLanguage.localized("points.format"),
                                template.basePointCost
                            ))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 13)
                    .padding(.trailing, 13)
                    .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .leading)
                }
                .padding(.leading, 8)
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(PixaTheme.line)
                }
                .shadow(color: Color.black.opacity(0.035), radius: 10, y: 4)
            }.buttonStyle(.plain)
        }
    }

    private func featuredImageWidth(for ratio: CGFloat) -> CGFloat {
        switch ratio {
        case ..<0.78: 108
        case 0.78..<1.18: 132
        default: 174
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey, trailing: LocalizedStringKey) -> some View {
        HStack {
            Text(title)
                .font(.title2.bold())
            Spacer()
            Button(trailing) {
                navigation.selectedTab = .templates
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder private var templateGrid: some View {
        if store.isLoading && store.templates.isEmpty {
            PixaLoadingStateView(
                title: "loading.home.title",
                message: "loading.home.message",
                minHeight: 240
            )
        }
        else if let error = store.errorMessage, store.templates.isEmpty {
            ContentUnavailableView {
                Label("common.error", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("common.retry") {
                    Task { await store.load(forceRefresh: true) }
                }
                .buttonStyle(.borderedProminent)
                .tint(PixaTheme.accent)
            }
        }
        else if store.templates.isEmpty {
            ContentUnavailableView("templates.empty", systemImage: "rectangle.stack")
                .frame(maxWidth: .infinity, minHeight: 220)
        }
        else {
            MasonryLayout(columns: 2, spacing: 12) {
                ForEach(homeGridTemplates) { template in
                    ZStack(alignment: .topTrailing) {
                        NavigationLink { TemplateDetailView(template: template) } label: {
                            TemplateCard(template: template)
                        }
                        .buttonStyle(.plain)
                    }
                    .pixaTemplateImpression(templateID: template.id) {
                        store.recordImpression(templateID: template.id)
                    }
                }
            }
        }
    }

    private var homeGridTemplates: [StyleTemplate] {
        store.filter == .recommended ? Array(store.templates.dropFirst()) : store.templates
    }

}
