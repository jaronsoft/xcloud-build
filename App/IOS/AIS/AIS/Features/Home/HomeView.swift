import SwiftUI

struct HomeView: View {
    @Binding var selection: AppTab
    @Binding var selectedPreset: AISVisualPreset?
    @Binding var pendingSharedJobID: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(SessionStore.self) private var session
    @Environment(AISAppDataStore.self) private var appData
    @State private var viewModel = HomeViewModel()
    @State private var selectedShowcase: GalleryContentKind?
    @State private var selectedShowcaseTemplateRoute: ShowcaseTemplateRoute?
    @State private var showsPresetPicker = false
    @State private var presentsLogin = false
    @State private var activeStageCopy: AISResolvedHomeCopy?
    @State private var previousStageCopyID: String?

    var body: some View {
        ZStack {
            AISPageBackground()

            ScrollView {
                VStack(spacing: 18) {
                    brandBar
                    stage
                    inspirationRail
                    valuePropositionSection
                }
                .frame(maxWidth: AISResponsiveLayout.maximumContentWidth)
                .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 18)
                .padding(.top, 10)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedShowcase) { contentKind in
            GalleryView(
                initialJobID: contentKind == .imageShowcase
                    ? pendingSharedJobID
                    : nil,
                contentKind: contentKind,
                onCreate: { selection = .create },
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
        .onChange(of: pendingSharedJobID) { _, jobID in
            guard jobID != nil else { return }
            selectedShowcase = .imageShowcase
        }
        .task(id: pendingSharedJobID) {
            if pendingSharedJobID != nil {
                selectedShowcase = .imageShowcase
            }
        }
        .task {
            selectStageCopy()
            await loadDirections()
            await viewModel.loadActiveTaskCount(session: session)
            await AISHomeCopyRefreshStore.shared.refreshIfNeeded()
        }
        .sheet(isPresented: $showsPresetPicker) {
            VisualPresetPickerSheet(
                presets: viewModel.directions,
                selectedPreset: $selectedPreset
            )
        }
        .sheet(isPresented: $presentsLogin) {
            LoginView()
        }
        .onChange(of: selection) { oldValue, newValue in
            guard oldValue != .home, newValue == .home else { return }
            viewModel.reloadHomeCopies()
            selectStageCopy()
        }
    }

    private var brandBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("app.display_name")
                    .font(.headline.weight(.bold))
                Text("home.stage.brand_caption")
                    .font(.caption)
                    .foregroundStyle(AISTheme.muted)
            }

            Spacer()

            if !session.isAuthenticated {
                Button("home.auth.entry") {
                    presentsLogin = true
                }
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(AISTheme.accentGradient, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.72), lineWidth: 1)
                }
                .shadow(
                    color: AISTheme.accent.opacity(0.28),
                    radius: 10,
                    y: 5
                )
                .buttonStyle(.plain)
            }

            if let points = appData.billing.balance?.availablePoints {
                Button {
                    selection = .account
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.bold))
                        Text(points, format: .number)
                            .font(.subheadline.bold().monospacedDigit())
                        if appData.isRefreshingUserData {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(AISTheme.accent)
                        }
                        Text("home.points.unit")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(AISTheme.accent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(
                        AISTheme.accent.opacity(0.10),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                AISTheme.accent.opacity(0.18),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    String.localizedStringWithFormat(
                        String(localized: "home.available_points"),
                        points
                    )
                )
            } else if session.isAuthenticated
                        && appData.isRefreshingUserData {
                ProgressView()
                    .controlSize(.small)
                    .tint(AISTheme.accent)
                    .frame(minWidth: 64, minHeight: 36)
                    .background(
                        AISTheme.accent.opacity(0.10),
                        in: Capsule()
                    )
                    .accessibilityLabel("account.data.loading")
            }

            if viewModel.activeTaskCount > 0 {
                Text(viewModel.activeTaskCount > 99 ? "99+" : "\(viewModel.activeTaskCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 28, minHeight: 24)
                    .background(.red, in: Capsule())
                    .accessibilityLabel(
                        String.localizedStringWithFormat(
                            String(localized: "home.active_tasks"),
                            viewModel.activeTaskCount
                        )
                    )
            }

            Menu {
                Button {
                    selection = .templates
                } label: {
                    Label("tab.templates", systemImage: "square.grid.2x2")
                }

                Button {
                    selectedShowcase = .imageShowcase
                } label: {
                    Label("gallery.title", systemImage: "photo.stack")
                }

                Button {
                    selection = .tasks
                } label: {
                    Label("tab.tasks", systemImage: "list.bullet.clipboard")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(AISTheme.accentSecondary)
                    .frame(width: 42, height: 42)
                    .background(.regularMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.95), lineWidth: 1)
                    }
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        if horizontalSizeClass == .regular {
            HStack(spacing: 30) {
                stageCopy
                    .frame(width: 330, alignment: .leading)

                stageVisual
                    .frame(maxWidth: .infinity)
                    .frame(height: 560)
            }
            .padding(32)
            .background {
                AISBlueprintGrid()
            }
            .clipShape(
                RoundedRectangle(cornerRadius: 38, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .stroke(.white.opacity(0.95), lineWidth: 1.2)
            }
            .shadow(
                color: AISTheme.accentSecondary.opacity(0.13),
                radius: 28,
                y: 16
            )
        } else {
            VStack(spacing: 0) {
                stageCopy
                    .padding(.horizontal, 24)
                    .padding(.top, 26)

                stageVisual
                    .frame(height: compactStageVisualHeight)

                creationCommand
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
            }
            .background {
                AISBlueprintGrid()
            }
            .clipShape(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(.white.opacity(0.95), lineWidth: 1.2)
            }
            .shadow(
                color: AISTheme.accentSecondary.opacity(0.13),
                radius: 24,
                y: 14
            )
        }
    }

    private var compactStageVisualHeight: CGFloat {
        let orbitRows = max((orbitPresets.count + 1) / 2, 1)
        return max(370, CGFloat(orbitRows) * 42 + 160)
    }

    private var orbitPresets: [AISVisualPreset] {
        let presets = viewModel.directions
        guard presets.count > 10 else { return presets }

        let selectedIndex = selectedPreset.flatMap { selected in
            presets.firstIndex(where: { $0.id == selected.id })
        } ?? 0

        // 圆周最多承载 10 个标签；超出时围绕当前项取相邻分类，避免小屏标签重叠。
        return (-4 ... 5).map { offset in
            let index = (
                selectedIndex + offset % presets.count + presets.count
            ) % presets.count
            return presets[index]
        }
    }

    private var stageCopy: some View {
        VStack(
            alignment: horizontalSizeClass == .regular ? .leading : .center,
            spacing: 13
        ) {
            Text(
                activeStageCopy?.eyebrow
                    ?? String(localized: "home.stage.eyebrow")
            )
                .font(.caption.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(AISTheme.muted)

            Text(
                activeStageCopy?.title
                    ?? String(localized: "home.stage.title")
            )
                .font(
                    .system(
                        size: horizontalSizeClass == .regular ? 46 : 34,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .multilineTextAlignment(
                    horizontalSizeClass == .regular ? .leading : .center
                )
                .fixedSize(horizontal: false, vertical: true)

            if horizontalSizeClass == .regular {
                Text(
                    activeStageCopy?.subtitle
                        ?? String(localized: "home.stage.subtitle")
                )
                    .font(.body)
                    .foregroundStyle(AISTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)

                creationCommand
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: horizontalSizeClass == .regular ? .leading : .center
        )
    }

    private var stageVisual: some View {
        GeometryReader { proxy in
            let objectWidth = min(
                horizontalSizeClass == .regular ? 245 : 176,
                proxy.size.width * 0.48
            )
            let visualCenterOffset: CGFloat =
                horizontalSizeClass == .regular ? 0 : -24

            ZStack {
                ZStack {
                    Ellipse()
                        .stroke(AISTheme.line.opacity(0.85), lineWidth: 1.2)
                        .frame(
                            width: min(proxy.size.width * 0.90, 590),
                            height: horizontalSizeClass == .regular ? 205 : 135
                        )

                    Button {
                        showsPresetPicker = true
                    } label: {
                        AISStageProductSymbol()
                            .scaleEffect(objectWidth / 118)
                            .frame(
                                width: objectWidth,
                                height: objectWidth * 1.18
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("home.stage.categories_title")
                }
                .offset(y: visualCenterOffset)

                ZStack {
                    if viewModel.isLoading && viewModel.directions.isEmpty {
                        ProgressView()
                            .tint(AISTheme.accent)
                            .offset(y: objectWidth * 0.78)
                    } else if viewModel.directions.isEmpty {
                        Button {
                            Task { await loadDirections(force: true) }
                        } label: {
                            Label(
                                "home.stage.categories_retry",
                                systemImage: "arrow.clockwise"
                            )
                            .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(AISTheme.accentSecondary)
                        .offset(y: objectWidth * 0.78)
                    } else {
                        ForEach(
                            Array(orbitPresets.enumerated()),
                            id: \.element.id
                        ) { index, preset in
                            presetChip(
                                preset,
                                isSelected: selectedPreset?.id == preset.id
                            )
                            .position(
                                orbitPosition(
                                    at: index,
                                    count: orbitPresets.count,
                                    in: proxy.size
                                )
                            )
                        }
                        allPresetsButton
                            .position(
                                x: proxy.size.width / 2,
                                y: proxy.size.height * 0.92
                            )

                        VStack(spacing: 3) {
                            Text("home.stage.swipe_hint")
                            if let selectedPreset {
                                Text(selectedPreset.localizedName)
                                    .fontWeight(.bold)
                                    .foregroundStyle(AISTheme.accentSecondary)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(AISTheme.muted)
                        .frame(maxWidth: 220)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                            .stroke(Color.white.opacity(0.92), lineWidth: 1)
                        }
                        .shadow(
                            color: AISTheme.accentSecondary.opacity(0.08),
                            radius: 8,
                            y: 5
                        )
                        .position(
                            x: proxy.size.width / 2,
                            y: proxy.size.height * 0.76
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard abs(value.translation.width) > 36 else { return }
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            selectPreset(
                                relativeOffset: value.translation.width < 0 ? 1 : -1
                            )
                        }
                    }
            )
        }
    }

    private var allPresetsButton: some View {
        Button {
            showsPresetPicker = true
        } label: {
            Label(
                String.localizedStringWithFormat(
                    String(localized: "home.stage.all_categories"),
                    viewModel.directions.count
                ),
                systemImage: "square.grid.2x2"
            )
            .font(.caption2.weight(.bold))
            .foregroundStyle(AISTheme.accentSecondary)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.95), lineWidth: 1)
            }
            .shadow(
                color: AISTheme.accentSecondary.opacity(0.10),
                radius: 7,
                y: 5
            )
        }
        .buttonStyle(.plain)
    }

    private func presetChip(
        _ preset: AISVisualPreset,
        isSelected: Bool
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                selectedPreset = preset
            }
        } label: {
            Text(preset.localizedName)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(
                    isSelected ? Color.white : AISTheme.muted
                )
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? AnyShapeStyle(AISTheme.accentGradient)
                        : AnyShapeStyle(Material.regularMaterial),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            isSelected
                                ? AISTheme.accent.opacity(0.72)
                                : Color.white.opacity(0.95),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
                .shadow(
                    color: isSelected
                        ? AISTheme.accent.opacity(0.28)
                        : AISTheme.accentSecondary.opacity(0.10),
                    radius: isSelected ? 12 : 7,
                    y: 5
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func orbitPosition(
        at index: Int,
        count: Int,
        in size: CGSize
    ) -> CGPoint {
        let isLeft = index.isMultiple(of: 2)
        let sideIndex = index / 2
        let sideCount = isLeft ? (count + 1) / 2 : count / 2
        let top = size.height * 0.12
        let bottom = size.height * 0.64
        let progress = sideCount > 1
            ? CGFloat(sideIndex) / CGFloat(sideCount - 1)
            : 0.5
        let horizontalInset = horizontalSizeClass == .regular
            ? min(size.width * 0.17, 96)
            : min(size.width * 0.17, 64)

        return CGPoint(
            x: isLeft ? horizontalInset : size.width - horizontalInset,
            y: top + (bottom - top) * progress
        )
    }

    private func preset(relativeOffset offset: Int) -> AISVisualPreset? {
        guard !viewModel.directions.isEmpty else { return nil }
        let currentIndex = selectedPreset.flatMap { selected in
            viewModel.directions.firstIndex(where: { $0.id == selected.id })
        } ?? 0
        let count = viewModel.directions.count
        let index = (currentIndex + offset % count + count) % count
        return viewModel.directions[index]
    }

    private func selectPreset(relativeOffset offset: Int) {
        selectedPreset = preset(relativeOffset: offset)
    }

    private func loadDirections(force: Bool = false) async {
        await viewModel.load(force: force)
        let selectedStillExists = selectedPreset.map { selected in
            viewModel.directions.contains(where: { $0.id == selected.id })
        } ?? false
        if !selectedStillExists {
            selectedPreset = viewModel.directions.first
        }
    }

    private func selectStageCopy() {
        let selected = AISHomeCopyPolicy.select(
            from: viewModel.homeCopies,
            excluding: previousStageCopyID
        )
        activeStageCopy = selected
        previousStageCopyID = selected?.id
    }

    private var creationCommand: some View {
        Button {
            selection = .create
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        AISTheme.accentGradient,
                        in: RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("home.stage.command")
                        .font(.headline)
                    Text(
                        selectedPreset?.localizedDescription
                            ?? String(localized: "home.stage.command_detail")
                    )
                        .font(.caption)
                        .foregroundStyle(AISTheme.muted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(AISTheme.accentSecondary)
            }
            .foregroundStyle(AISTheme.accentSecondary)
            .padding(12)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 25, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(.white.opacity(0.95), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var inspirationRail: some View {
        HStack(spacing: 10) {
            railButton(
                title: "home.template_cases",
                icon: "diamond",
                action: { selectedShowcase = .templateShowcase }
            )
            railButton(
                title: "home.image_cases",
                icon: "photo.stack",
                action: { selectedShowcase = .imageShowcase }
            )
        }
        .padding(8)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.92), lineWidth: 1)
        }
    }

    private func railButton(
        title: LocalizedStringKey,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AISTheme.accentSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var valuePropositionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("home.value.title")
                    .font(.title3.bold())
                Text("home.value.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(AISTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if horizontalSizeClass == .regular {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(
                            .flexible(),
                            spacing: 12,
                            alignment: .top
                        ),
                        count: 3
                    ),
                    spacing: 12
                ) {
                    valuePropositionCards
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        valuePropositionCards
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var valuePropositionCards: some View {
        ForEach(HomeValueProposition.all) { proposition in
            HomeValuePropositionCard(proposition: proposition)
                .frame(
                    width: horizontalSizeClass == .regular ? nil : 270
                )
        }
    }
}

private struct HomeValueProposition: Identifiable {
    let id: String
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    @MainActor static let all = [
        HomeValueProposition(
            id: "structure",
            icon: "cube.transparent",
            title: "home.value.structure.title",
            detail: "home.value.structure.detail"
        ),
        HomeValueProposition(
            id: "intent",
            icon: "scope",
            title: "home.value.intent.title",
            detail: "home.value.intent.detail"
        ),
        HomeValueProposition(
            id: "specification",
            icon: "slider.horizontal.3",
            title: "home.value.specification.title",
            detail: "home.value.specification.detail"
        ),
        HomeValueProposition(
            id: "delivery",
            icon: "shippingbox",
            title: "home.value.delivery.title",
            detail: "home.value.delivery.detail"
        ),
        HomeValueProposition(
            id: "efficiency",
            icon: "arrow.down.right.circle",
            title: "home.value.efficiency.title",
            detail: "home.value.efficiency.detail"
        ),
        HomeValueProposition(
            id: "guidance",
            icon: "person.crop.circle.badge.checkmark",
            title: "home.value.guidance.title",
            detail: "home.value.guidance.detail"
        )
    ]
}

private struct HomeValuePropositionCard: View {
    let proposition: HomeValueProposition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: proposition.icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AISTheme.accent)
                .frame(width: 38, height: 38)
                .background(
                    AISTheme.accent.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            Text(proposition.title)
                .font(.headline)

            Text(proposition.detail)
                .font(.subheadline)
                .foregroundStyle(AISTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        .padding(18)
        .aisSurface(cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }
}

private struct VisualPresetPickerSheet: View {
    let presets: [AISVisualPreset]
    @Binding var selectedPreset: AISVisualPreset?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredPresets: [AISVisualPreset] {
        let keyword = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !keyword.isEmpty else { return presets }
        return presets.filter {
            $0.localizedName.localizedCaseInsensitiveContains(keyword)
                || ($0.localizedDescription?.localizedCaseInsensitiveContains(
                    keyword
                ) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 148, maximum: 220),
                            spacing: 12
                        )
                    ],
                    spacing: 12
                ) {
                    ForEach(filteredPresets) { preset in
                        presetButton(preset)
                    }
                }
                .padding(16)
            }
            .background {
                AISPageBackground()
            }
            .navigationTitle("home.stage.categories_title")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                prompt: "home.stage.categories_search"
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func presetButton(_ preset: AISVisualPreset) -> some View {
        let isSelected = selectedPreset?.id == preset.id
        return Button {
            selectedPreset = preset
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: isSelected ? "scope" : "circle.dotted")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(
                            isSelected
                                ? AISTheme.accent
                                : AISTheme.accentSecondary
                        )
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AISTheme.accent)
                    }
                }

                Text(preset.localizedName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AISTheme.accentSecondary)
                    .lineLimit(2)

                if let description = preset.localizedDescription,
                   !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(AISTheme.muted)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(14)
            .background(
                isSelected
                    ? AISTheme.accent.opacity(0.11)
                    : AISTheme.elevated.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        isSelected
                            ? AISTheme.accent.opacity(0.70)
                            : Color.white.opacity(0.92),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

@MainActor
@Observable
private final class HomeViewModel {
    private let api = APIClient()

    private(set) var directions: [AISVisualPreset] = []
    private(set) var homeCopies: [AISHomeCopyItem] =
        AISHomeCopyPersistence.load()?.items ?? []
    private(set) var isLoading = false
    private(set) var activeTaskCount = 0

    func reloadHomeCopies() {
        homeCopies = AISHomeCopyPersistence.load()?.items ?? []
    }

    func load(force: Bool = false) async {
        guard !isLoading, force || directions.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let cacheKey = AISResponseCache.key(
            scope: "public",
            resource: "prompt-attributes-image",
            parameters: ["language": AISLocalization.apiValue]
        )
        if !force,
           let cached = await AISResponseCache.shared.read(
               AISPromptAttributeSettings.self,
               key: cacheKey,
               allowsStale: true
           ) {
            apply(cached.value)
            if cached.isFresh { return }
        }

        do {
            let options: AISPromptAttributeSettings = try await api.get(
                "/api/ais/prompt-attributes",
                query: [URLQueryItem(name: "mediaType", value: "image")]
            )
            apply(options)
            await AISResponseCache.shared.write(options, key: cacheKey)
        } catch {
            if directions.isEmpty {
                directions = []
            }
        }
    }

    func loadActiveTaskCount(session: SessionStore) async {
        guard let userID = session.user?.id else {
            activeTaskCount = 0
            return
        }
        let cacheKey = AISResponseCache.key(
            scope: "user:\(userID)",
            resource: "tasks",
            parameters: ["group": "media", "page": "1", "size": "30"]
        )
        if let cached = await AISResponseCache.shared.read(
            PageResponse<AISTaskJob>.self,
            key: cacheKey,
            allowsStale: true
        ) {
            activeTaskCount = cached.value.items.filter(\.isActive).count
        }
    }

    private func apply(_ options: AISPromptAttributeSettings) {
        directions = AISVisualPresetMapper.presets(
            from: options,
            groupID: "direction"
        )
    }
}

#Preview("HomeView") {
    NavigationStack {
        HomeView(
            selection: .constant(.home),
            selectedPreset: .constant(nil),
            pendingSharedJobID: .constant(nil)
        )
    }
    .environment(SessionStore())
    .environment(AISAppDataStore())
}
