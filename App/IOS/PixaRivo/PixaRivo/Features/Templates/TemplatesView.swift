import SwiftUI
import UIKit

struct TemplatesView: View {
    private struct ActiveFilterChip: Identifiable {
        let id: String
        let label: String
    }

    @Environment(PixaMediaRegionStore.self) private var mediaRegion
    @Environment(PixaLanguageStore.self) private var language
    @Environment(SessionStore.self) private var session
    @Environment(PixaNavigationStore.self) private var navigation
    @Environment(PixaNotificationStore.self) private var notifications
    @State private var store = TemplateStore(surface: .creation)
    @State private var sharePayload: PixaSharePayload?
    @State private var preparingShareID: String?
    @State private var showsShareError = false
    @State private var showsFilters = false
    @State private var notificationTemplate: StyleTemplate?
    @State private var showsNotificationLogin = false
    @State private var showsUnavailableTemplate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                compactHeader
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("home.search", text: $store.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { reload() }
                    Button {
                        showsFilters = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3")
                            Text("templates.filter.action")
                                .font(.caption.bold())
                            if store.activeFilterCount > 0 {
                                Text("\(store.activeFilterCount)")
                                    .font(.caption2.bold().monospacedDigit())
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 20, minHeight: 20)
                                    .background(PixaTheme.accent, in: Circle())
                            }
                        }
                        .foregroundStyle(PixaTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("templates.filter.action")
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 13))
                .overlay { RoundedRectangle(cornerRadius: 13).stroke(PixaTheme.line) }
                sortBar
                if !activeFilterLabels.isEmpty {
                    activeFilterBar
                }
                if store.isLoading && store.templates.isEmpty {
                    PixaLoadingStateView(
                        title: "loading.templates.title",
                        message: "loading.templates.message"
                    )
                } else if let error = store.errorMessage, store.templates.isEmpty {
                    ContentUnavailableView {
                        Label("common.error", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("common.retry") { reload() }
                            .buttonStyle(.borderedProminent)
                            .tint(PixaTheme.accent)
                    }
                } else {
                    MasonryLayout(columns: 2, spacing: 12) {
                        ForEach(store.templates) { template in
                            ZStack(alignment: .topTrailing) {
                                NavigationLink { TemplateDetailView(template: template) } label: {
                                    TemplateCard(template: template)
                                }
                                .buttonStyle(.plain)
                                PixaShareButton(isPreparing: preparingShareID == template.id) {
                                    Task { await share(template) }
                                }
                                .padding(8)
                            }
                            .pixaTemplateImpression(templateID: template.id) {
                                store.recordImpression(templateID: template.id)
                            }
                        }
                    }
                }
                if store.hasMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task { await store.load(reset: false) }
                        }
                }
                paginationFooter
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(PixaTheme.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.load(forceRefresh: true) }
        .task(id: "\(mediaRegion.revision):\(language.locale.identifier)") {
            await store.loadFilterGroups(forceRefresh: mediaRegion.revision > 0)
            await store.load(forceRefresh: mediaRegion.revision > 0)
        }
        .sheet(item: $sharePayload) { payload in
            PixaActivityView(items: payload.items)
        }
        .sheet(isPresented: $showsFilters) {
            TemplateAdvancedFilterSheet(
                groups: store.filterGroups,
                initialOrientation: store.orientation,
                initialPlatform: store.platform,
                initialTags: store.selectedTags
            ) { orientation, platform, tags in
                Task {
                    await store.applyFilters(
                        sort: store.sort,
                        orientation: orientation,
                        platform: platform,
                        selectedTags: tags
                    )
                }
            }
        }
        .sheet(isPresented: $showsNotificationLogin) { LoginView() }
        .sheet(item: $notificationTemplate) { template in
            TemplateEditorView(template: template)
        }
        .alert("share.failed.title", isPresented: $showsShareError) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("share.failed.message")
        }
        .alert("common.error", isPresented: $showsUnavailableTemplate) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("notification.template_unavailable")
        }
        .task(id: navigation.pendingTemplateID) {
            await openPendingNotificationTemplate()
        }
        .onChange(of: session.isAuthenticated) { _, authenticated in
            guard authenticated, navigation.pendingTemplateID != nil else { return }
            showsNotificationLogin = false
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await openPendingNotificationTemplate()
            }
        }
    }

    private var sortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                sortButton("recommended", title: "home.recommended")
                sortButton("latest", title: "home.latest")
                sortButton("popular", title: "home.popular")
                if store.isLoading {
                    ProgressView().controlSize(.small).padding(.leading, 4)
                }
            }
        }
    }

    private func sortButton(_ value: String, title: LocalizedStringKey) -> some View {
        Button {
            Task { await store.selectSort(value) }
        } label: {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(store.sort == value ? .white : PixaTheme.ink)
                .padding(.horizontal, 15)
                .frame(height: 34)
                .background(store.sort == value ? PixaTheme.accent : .white.opacity(0.72), in: Capsule())
                .overlay { Capsule().stroke(store.sort == value ? .clear : PixaTheme.line) }
        }
        .buttonStyle(.plain)
        .disabled(store.isLoading && store.sort == value)
    }

    @MainActor
    private func openPendingNotificationTemplate() async {
        guard let templateID = navigation.pendingTemplateID else { return }
        guard session.isAuthenticated else {
            showsNotificationLogin = true
            return
        }
        guard let token = await session.validAccessToken() else {
            showsNotificationLogin = true
            return
        }
        do {
            let template = try await store.detail(id: templateID, token: token)
            if let notificationID = navigation.pendingNotificationID {
                await notifications.markRead(id: notificationID, session: session)
            }
            navigation.consumePendingTemplate()
            notificationTemplate = template
        } catch {
            navigation.consumePendingTemplate()
            showsUnavailableTemplate = true
        }
    }

    private var compactHeader: some View {
        PixaSectionHeader(eyebrow: "templates.eyebrow", title: "templates.title") {
            if store.total > 0 {
                Text(String.localizedStringWithFormat(
                    AppLanguage.localized("templates.count_progress"),
                    store.templates.count,
                    store.total
                ))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(.white.opacity(0.64), in: Capsule())
                .overlay { Capsule().stroke(PixaTheme.line) }
            }
        }
    }

    private var activeFilterLabels: [ActiveFilterChip] {
        var labels: [ActiveFilterChip] = []
        if store.orientation == "portrait" {
            labels.append(ActiveFilterChip(
                id: "orientation:portrait",
                label: AppLanguage.localized("home.portrait")
            ))
        } else if store.orientation == "landscape" {
            labels.append(ActiveFilterChip(
                id: "orientation:landscape",
                label: AppLanguage.localized("home.landscape")
            ))
        }
        if let platform = store.platformGroup?.items.first(
            where: { $0.itemKey == store.platform }
        ) {
            labels.append(ActiveFilterChip(
                id: platform.id,
                label: platform.name
            ))
        }
        for group in store.tagGroups {
            let selected = store.selectedTags[group.groupKey, default: []]
            labels.append(contentsOf: group.items
                .filter { selected.contains($0.itemKey) }
                .sorted { $0.sort < $1.sort }
                .map { ActiveFilterChip(id: $0.id, label: $0.name) })
        }
        return labels
    }

    private var activeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activeFilterLabels) { chip in
                    Text(chip.label)
                        .font(.caption.bold())
                        .foregroundStyle(PixaTheme.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(.white.opacity(0.72), in: Capsule())
                        .overlay { Capsule().stroke(PixaTheme.line) }
                }
                Button {
                    Task { await store.resetFilters() }
                } label: {
                    Label("templates.filter.reset", systemImage: "xmark")
                        .font(.caption.bold())
                }
                .buttonStyle(.plain)
                .foregroundStyle(PixaTheme.accent)
            }
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if store.isLoadingMore {
            ProgressView("templates.loading_more")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else if !store.isLoading, store.hasMore, store.errorMessage != nil {
            Button {
                Task { await store.load(reset: false) }
            } label: {
                Label("common.retry", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(PixaTheme.ink)
            .padding(.vertical, 8)
        } else if !store.isLoading, !store.hasMore,
                  !store.templates.isEmpty, store.templates.count >= store.total {
            Text(String.localizedStringWithFormat(
                AppLanguage.localized("templates.loaded_all"),
                store.total
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func reload() { Task { await store.load(forceRefresh: true) } }

    @MainActor
    private func share(_ template: StyleTemplate) async {
        guard preparingShareID == nil else { return }
        preparingShareID = template.id
        defer { preparingShareID = nil }
        sharePayload = await PixaShareService.prepare(
            title: template.name,
            description: template.description,
            imageURL: template.imageURL,
            source: .template
        )
        showsShareError = sharePayload == nil
    }
}

struct PixaTemplateVisibilityPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PixaTemplateImpressionModifier: ViewModifier {
    let templateID: String
    let onQualifiedImpression: () -> Void
    @State private var qualificationTask: Task<Void, Never>?
    @State private var hasQualified = false

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    let visible = frame.intersection(UIScreen.main.bounds)
                    let area = max(1, frame.width * frame.height)
                    Color.clear.preference(
                        key: PixaTemplateVisibilityPreferenceKey.self,
                        value: max(0, visible.width * visible.height) / area
                    )
                }
            }
            .onPreferenceChange(PixaTemplateVisibilityPreferenceKey.self) { fraction in
                guard !hasQualified else { return }
                if fraction >= 0.5 {
                    guard qualificationTask == nil else { return }
                    qualificationTask = Task {
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            hasQualified = true
                            onQualifiedImpression()
                        }
                    }
                } else {
                    qualificationTask?.cancel()
                    qualificationTask = nil
                }
            }
            .onDisappear {
                qualificationTask?.cancel()
                qualificationTask = nil
            }
    }
}

extension View {
    func pixaTemplateImpression(
        templateID: String,
        onQualifiedImpression: @escaping () -> Void
    ) -> some View {
        modifier(PixaTemplateImpressionModifier(
            templateID: templateID,
            onQualifiedImpression: onQualifiedImpression
        ))
    }
}

private struct TemplateAdvancedFilterSheet: View {
    let groups: [StyleTemplateFilterGroup]
    let onApply: (String, String, [String: Set<String>]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var orientation: String
    @State private var platform: String
    @State private var selectedTags: [String: Set<String>]

    init(
        groups: [StyleTemplateFilterGroup],
        initialOrientation: String,
        initialPlatform: String,
        initialTags: [String: Set<String>],
        onApply: @escaping (String, String, [String: Set<String>]) -> Void
    ) {
        self.groups = groups
        self.onApply = onApply
        _orientation = State(initialValue: initialOrientation)
        _platform = State(initialValue: initialPlatform)
        _selectedTags = State(initialValue: initialTags)
    }

    private var platformGroup: StyleTemplateFilterGroup? {
        groups.first { $0.groupKey == "platform" }
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
                            title: AppLanguage.localized("filter.all"),
                            systemImage: "rectangle.on.rectangle",
                            isSelected: orientation.isEmpty
                        ) { orientation = "" }
                        choiceButton(
                            title: AppLanguage.localized("home.portrait"),
                            systemImage: "rectangle.portrait",
                            isSelected: orientation == "portrait"
                        ) { orientation = "portrait" }
                        choiceButton(
                            title: AppLanguage.localized("home.landscape"),
                            systemImage: "rectangle",
                            isSelected: orientation == "landscape"
                        ) { orientation = "landscape" }
                    }
                }

                if let platformGroup, !platformGroup.items.isEmpty {
                    Section(platformGroup.name) {
                        filterGrid {
                            choiceButton(
                                title: AppLanguage.localized(
                                    "templates.filter.all_channels"
                                ),
                                systemImage: "globe",
                                isSelected: platform.isEmpty
                            ) { platform = "" }
                            ForEach(
                                platformGroup.items.sorted { $0.sort < $1.sort }
                            ) { item in
                                choiceButton(
                                    title: item.name,
                                    systemImage: nil,
                                    isSelected: platform == item.itemKey
                                ) { platform = item.itemKey }
                            }
                        }
                    }
                }

                ForEach(tagGroups) { group in
                    Section(group.name) {
                        filterGrid {
                            ForEach(group.items.sorted { $0.sort < $1.sort }) {
                                item in
                                choiceButton(
                                    title: item.name,
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("templates.filter.apply") {
                        onApply(orientation, platform, selectedTags)
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
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? PixaTheme.accent : .primary)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                isSelected
                    ? PixaTheme.accent.opacity(0.10)
                    : Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected
                            ? PixaTheme.accent.opacity(0.45)
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
