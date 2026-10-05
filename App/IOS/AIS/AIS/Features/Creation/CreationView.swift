import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private enum CreationPlanningPicker: Identifiable {
    case direction
    case effects
    case attribute(String)

    var id: String {
        switch self {
        case .direction:
            "direction"
        case .effects:
            "effects"
        case let .attribute(groupID):
            "attribute:\(groupID)"
        }
    }
}

enum AISCreationSelectionPolicy {
    static let hiddenExtendedAttributeIDs = Set(["direction", "effect"])

    static func requestAttributes(
        from attributes: [String: [String]],
        directionID: String
    ) -> [String: [String]] {
        var result = attributes
        let normalizedDirectionID = directionID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if normalizedDirectionID.isEmpty {
            result["direction"] = nil
        } else {
            result["direction"] = [normalizedDirectionID]
        }
        return result
    }

    static func normalizedEffectIDs(
        _ values: [String],
        availableIDs: Set<String>,
        limit: Int
    ) -> [String] {
        var seen = Set<String>()
        return Array(
            values
                .filter {
                    availableIDs.contains($0) && seen.insert($0).inserted
                }
                .prefix(max(1, limit))
        )
    }
}

struct CreationView: View {
    let selectedPreset: AISVisualPreset?
    let initialTask: AISTaskJob?

    init(
        selectedPreset: AISVisualPreset?,
        initialTask: AISTaskJob? = nil
    ) {
        self.selectedPreset = selectedPreset
        self.initialTask = initialTask
    }

    @Environment(SessionStore.self) private var session
    @Environment(AISAppDataStore.self) private var appData
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isRequirementFocused: Bool
    @State private var viewModel = CreationViewModel()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var prompt = ""
    @State private var optimizedPrompt = ""
    @State private var usesOptimizedPrompt = false
    @State private var orientation = "landscape"
    @State private var aspectRatio = ""
    @State private var resolution = ""
    @State private var selectedModelKey = ""
    @State private var selectedDirectionID = ""
    @State private var selectedEffectIDs: [String] = []
    @State private var selectedAttributes: [String: [String]] = [:]
    @State private var activePlanningPicker: CreationPlanningPicker?
    @AppStorage("ais.promo_mark_enabled")
    private var promoMarkEnabled = false
    @AppStorage("ais.recommend_to_gallery")
    private var recommendToGallery = true
    @State private var presentsLogin = false
    @State private var confirmsGeneration = false
    @State private var presentsPlanningSuggestion = false
    @State private var confirmsPromptOptimization = false
    @State private var promptOptimizationQuote: AISPointQuote?
    @State private var isLoadingPromptOptimizationQuote = false
    @State private var promptOptimizationStartedAt: Date?
    @State private var confirmsUploadCompliance = false
    @State private var presentsPhotoPicker = false
    @State private var presentsAssetLibrary = false
    @State private var editingReferenceID: UUID?
    @State private var selectedResultTask: AISTaskJob?
    @State private var showsReferenceUnderstandingHint = false
    @State private var expandedAttributeGroups: Set<String> = []
    @AppStorage("ais.upload_agreement.accepted.2026-07")
    private var acceptedUploadCompliance = false

    private var configuration: AISCreationConfigurationStore {
        appData.configuration
    }

    private var pricingRules: AISPricingRulesStore {
        appData.pricingRules
    }

    var body: some View {
        ZStack {
            AISPageBackground()
            ScrollViewReader { scrollProxy in
                GeometryReader { proxy in
                    ScrollView {
                        creationContent(availableWidth: proxy.size.width)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: viewModel.activeJob?.status) { _, status in
                        guard status != nil,
                              viewModel.activeJob?.isActive == false else {
                            return
                        }
                        isRequirementFocused = false
                        if reduceMotion {
                            scrollProxy.scrollTo(
                                "creation-job-status",
                                anchor: .bottom
                            )
                        } else {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scrollProxy.scrollTo(
                                    "creation-job-status",
                                    anchor: .bottom
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("creation.title")
        .safeAreaInset(edge: .bottom) {
            if viewModel.isGenerationActive {
                generationProgressFooter
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
            } else if viewModel.activeJob == nil {
                generationButton
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $presentsLogin) {
            LoginView()
        }
        .sheet(item: $activePlanningPicker) { picker in
            planningPickerSheet(picker)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $presentsAssetLibrary) {
            AISAssetLibraryPicker(
                accessToken: session.accessToken,
                maximumSelectionCount: max(0, 3 - viewModel.references.count)
            ) { assets in
                let addedIDs = viewModel.addLibraryReferences(assets)
                handleAddedReferences(addedIDs)
            }
        }
        .sheet(item: $selectedResultTask) { task in
            TaskDetailView(
                job: task,
                estimateSeconds: appData.durationEstimates.seconds(
                    for: task.jobType
                ),
                onDeleted: {
                    selectedResultTask = nil
                    viewModel.createAnother()
                },
                onContinueEditing: { completedTask in
                    selectedResultTask = nil
                    viewModel.createAnother()
                    viewModel.addJobReference(completedTask)
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { editingReference != nil },
                set: { if !$0 { editingReferenceID = nil } }
            )
        ) {
            if let reference = editingReference {
                NavigationStack {
                    CreationReferenceSettingsView(
                        reference: reference,
                        isUnderstanding: viewModel.understandingReferenceID
                            == reference.id,
                        understandingProgress: viewModel
                            .understandingProgress[reference.id],
                        understandingStartedAt: viewModel
                            .understandingStartedAt[reference.id],
                        durationEstimate: appData.durationEstimates.estimate(
                            for: "image_understand"
                        ),
                        onSave: { role, mode, name, note in
                            viewModel.updateReference(
                                reference.id,
                                role: role,
                                preserveMode: mode,
                                displayName: name,
                                userNote: note
                            )
                            editingReferenceID = nil
                        },
                        onUnderstand: { role, note in
                            let token = await session.validAccessToken()
                            return try await viewModel.understand(
                                referenceID: reference.id,
                                role: role,
                                userHint: note,
                                accessToken: token
                            )
                        },
                        onUnderstandQuote: {
                            let token = await session.validAccessToken()
                            return try await viewModel.quote(
                                action: .imageUnderstand,
                                accessToken: token
                            )
                        },
                        onRestoreUnderstanding: {
                            let token = await session.validAccessToken()
                            await viewModel.restoreUnderstanding(
                                referenceID: reference.id,
                                accessToken: token
                            )
                        }
                    )
                }
            }
        }
        .photosPicker(
            isPresented: $presentsPhotoPicker,
            selection: $selectedItems,
            maxSelectionCount: max(1, 3 - viewModel.references.count),
            matching: .images
        )
        .onChange(of: selectedItems) { _, items in
            guard session.isAuthenticated else {
                selectedItems = []
                return
            }
            Task {
                let addedIDs = await viewModel.addReferences(from: items)
                selectedItems = []
                handleAddedReferences(addedIDs)
            }
        }
        .task(id: session.user?.id) {
            let token = await session.validAccessToken()
            await configuration.load(
                userID: session.user?.id,
                accessToken: token
            )
            normalizeConfiguration()
            if selectedDirectionID.isEmpty {
                selectedDirectionID = selectedPreset?.id
                    ?? configuration.visualPresets.directions.first?.id
                    ?? ""
            }
            await restoreDraft()
            if let activeJobID = viewModel.activeJobID {
                await viewModel.monitor(jobID: activeJobID, accessToken: token)
            }
        }
        .task(id: "pricing|\(session.user?.id ?? "")") {
            let token = await session.validAccessToken()
            await pricingRules.load(
                userID: session.user?.id,
                accessToken: token
            )
        }
        .task(id: initialTask?.id) {
            guard let initialTask else { return }
            viewModel.addJobReference(initialTask)
        }
        .task(id: "\(quoteSignature)|\(pricingRules.rules?.version ?? "")") {
            guard session.isAuthenticated, configuration.canSubmit,
                  let rules = pricingRules.rules else {
                viewModel.clearLocalQuote()
                return
            }
            viewModel.updateLocalQuote(
                rules: rules,
                orientation: orientation,
                aspectRatio: aspectRatio,
                resolution: resolution,
                selectedModelKey: selectedModelKey,
                selectedAttributes: requestSelectedAttributes,
                promoMarkEnabled: promoMarkEnabled,
                configuration: configuration
            )
        }
        .task(id: draftSignature) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, session.isAuthenticated else { return }
            await saveDraft()
        }
        .onChange(of: session.isAuthenticated) { _, authenticated in
            if !authenticated {
                selectedItems = []
                viewModel.resetForLogout()
            }
        }
        .alert("creation.confirm.title", isPresented: $confirmsGeneration) {
            Button("common.cancel", role: .cancel) {}
            Button("creation.confirm.action") {
                Task { await submit() }
            }
        } message: {
            Text(
                String.localizedStringWithFormat(
                    String(localized: "creation.confirm.message"),
                    viewModel.quote?.points ?? 0
                )
            )
        }
        .alert(
            "creation.preflight.title",
            isPresented: $presentsPlanningSuggestion
        ) {
            Button("common.cancel", role: .cancel) {}
            Button("creation.preflight.plan") {
                requestPromptOptimization()
            }
            Button("creation.preflight.continue") {
                confirmsGeneration = true
            }
        } message: {
            Text("creation.preflight.message")
        }
        .alert(
            "creation.optimize.confirm.title",
            isPresented: $confirmsPromptOptimization
        ) {
            Button("common.cancel", role: .cancel) {}
            Button("creation.optimize.confirm.action") {
                Task { await optimizePrompt() }
            }
        } message: {
            Text(
                String.localizedStringWithFormat(
                    String(localized: "creation.optimize.confirm.message"),
                    promptOptimizationQuote?.points ?? 0,
                    AISDurationTextFormatter.approximate(
                        seconds: appData.durationEstimates.seconds(
                            for: "prompt_optimize"
                        ) ?? 20
                    )
                )
            )
        }
        .alert("upload.compliance.title", isPresented: $confirmsUploadCompliance) {
            Button("common.cancel", role: .cancel) {}
            Button("upload.compliance.accept") {
                acceptedUploadCompliance = true
                presentsPhotoPicker = true
            }
        } message: {
            Text("upload.compliance.message")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("common.done") {
                    isRequirementFocused = false
                }
            }
        }
    }

    private var editingReference: CreationReference? {
        guard let editingReferenceID else { return nil }
        return viewModel.references.first { $0.id == editingReferenceID }
    }

    @ViewBuilder
    private func creationContent(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            creationHeader
            if AISResponsiveLayout.usesWideCreationLayout(
                for: availableWidth
            ) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) {
                        referenceSection
                        requirementSection
                        planningSection
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 18) {
                        outputSection
                        publishingSection
                        submissionArea
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                referenceSection
                requirementSection
                planningSection
                outputSection
                publishingSection
                submissionArea
            }
        }
        .frame(
            maxWidth: AISResponsiveLayout.maximumContentWidth,
            alignment: .leading
        )
        .padding(
            .horizontal,
            AISResponsiveLayout.horizontalPadding(for: availableWidth)
        )
        .padding(.top, 10)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
    }

    private var creationHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.headline)
                .foregroundStyle(AISTheme.accent)
                .frame(width: 38, height: 38)
                .background(
                    AISTheme.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            Text("creation.product.compact_hint")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let direction = configuration.visualPresets.directions
                .first(where: { $0.id == selectedDirectionID }) {
                Text(direction.localizedName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AISTheme.accentSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AISTheme.accent.opacity(0.10), in: Capsule())
            }
        }
        .padding(14)
        .aisSurface(cornerRadius: 18)
    }

    private var referenceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(
                "creation.references.title",
                systemImage: "photo.on.rectangle.angled"
            )
            if !viewModel.references.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.references) { reference in
                            CreationReferenceCard(
                                reference: reference,
                                understandingState: viewModel
                                    .understandingStates[reference.id],
                                onEdit: { editingReferenceID = reference.id },
                                onUnderstand: {
                                    editingReferenceID = reference.id
                                },
                                onRemove: {
                                    viewModel.removeReference(reference.id)
                                }
                            )
                        }
                    }
                }
            }
            if showsReferenceUnderstandingHint {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(AISTheme.accentSecondary)
                    Text("creation.references.understand_hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showsReferenceUnderstandingHint = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("common.close"))
                }
                .padding(10)
                .background(
                    AISTheme.accentSecondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            Menu {
                Button {
                    beginSelectingReferences()
                } label: {
                    Label("creation.source.photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    addClipboardImage()
                } label: {
                    Label("creation.source.clipboard", systemImage: "doc.on.clipboard")
                }
                Button {
                    guard session.isAuthenticated else {
                        presentsLogin = true
                        return
                    }
                    presentsAssetLibrary = true
                } label: {
                    Label("creation.source.library", systemImage: "photo.stack")
                }
            } label: {
                Label(
                    viewModel.references.isEmpty
                        ? "creation.references.add"
                        : "creation.references.more",
                    systemImage: "plus"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    AISTheme.accent.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .disabled(viewModel.references.count >= 3)
            Text("creation.references.helper")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("creation.references.upload_notice.ai")
                .font(.caption2)
                .foregroundStyle(AISTheme.accentSecondary)
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private var requirementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(
                    "creation.requirement.title",
                    systemImage: "text.alignleft"
                )
                Spacer()
                Button {
                    requestPromptOptimization()
                } label: {
                    if viewModel.isOptimizing,
                       let promptOptimizationStartedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            promptOptimizationLabel(
                                at: context.date,
                                startedAt: promptOptimizationStartedAt
                            )
                        }
                    } else if isLoadingPromptOptimizationQuote {
                        ProgressView()
                    } else {
                        Label("creation.optimize", systemImage: "sparkles")
                    }
                }
                .font(.caption.weight(.semibold))
                .disabled(
                    !canOptimizePrompt
                        || viewModel.isOptimizing
                        || isLoadingPromptOptimizationQuote
                )
            }
            TextField(
                "creation.requirement.placeholder",
                text: $prompt,
                axis: .vertical
            )
            .focused($isRequirementFocused)
            .lineLimit(4...8)
            .padding(14)
            .background(
                Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14)
            )
            if !optimizedPrompt.isEmpty {
                Toggle(isOn: $usesOptimizedPrompt) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("creation.optimize.result")
                            .font(.subheadline.weight(.semibold))
                        Text(optimizedPrompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                    }
                }
                .tint(AISTheme.accent)
            }
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private var planningSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("creation.planning", systemImage: "wand.and.stars")
            compactPlanningPickers
            if !planningAttributeGroups.isEmpty {
                Divider()
                Text("creation.attributes.title")
                    .font(.subheadline.weight(.semibold))
                Text("creation.attributes.helper")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                attributeSummaryRows
            }
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private var planningAttributeGroups: [AISPromptAttributeGroup] {
        let primaryGroupIDs = AISCreationSelectionPolicy
            .hiddenExtendedAttributeIDs
        return configuration.attributeGroups.filter {
            !primaryGroupIDs.contains($0.id.lowercased())
        }
    }

    private var attributeSummaryRows: some View {
        VStack(spacing: 10) {
            ForEach(planningAttributeGroups) { group in
                AISPickerSummaryRow(
                    title: group.localizedName,
                    summary: selectedAttributeSummary(for: group),
                    selectedCount: selectedAttributes[group.id, default: []]
                        .count
                ) {
                    activePlanningPicker = .attribute(group.id)
                }
            }
        }
    }

    private var compactPlanningPickers: some View {
        VStack(spacing: 10) {
            AISPickerSummaryRow(
                title: String(localized: "creation.direction"),
                summary: selectedDirectionSummary,
                selectedCount: selectedDirectionID.isEmpty ? 0 : 1
            ) {
                activePlanningPicker = .direction
            }
            AISPickerSummaryRow(
                title: String(localized: "creation.effects"),
                summary: selectedEffectSummary,
                selectedCount: selectedEffectIDs.count
            ) {
                activePlanningPicker = .effects
            }
        }
    }

    private var selectedDirectionSummary: String {
        configuration.visualPresets.directions
            .first(where: { $0.id == selectedDirectionID })?
            .localizedName
            ?? String(localized: "creation.selection.choose")
    }

    private var selectedEffectSummary: String {
        let names = configuration.visualPresets.effects
            .filter { selectedEffectIDs.contains($0.id) }
            .map(\.localizedName)
        return names.isEmpty
            ? String(localized: "creation.selection.none")
            : names.joined(separator: " / ")
    }

    private func selectedAttributeSummary(
        for group: AISPromptAttributeGroup
    ) -> String {
        let selected = selectedAttributes[group.id, default: []]
        let names = group.items
            .filter { selected.contains($0.id) }
            .sorted { $0.sort < $1.sort }
            .map(\.localizedName)
        return names.isEmpty
            ? String(localized: "creation.selection.none")
            : names.joined(separator: " / ")
    }

    private func planningPickerSheet(
        _ picker: CreationPlanningPicker
    ) -> some View {
        NavigationStack {
            ScrollView {
                planningPickerSheetContent(picker)
                    .padding(16)
            }
            .navigationTitle(planningPickerTitle(picker))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        activePlanningPicker = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func planningPickerSheetContent(
        _ picker: CreationPlanningPicker
    ) -> some View {
        switch picker {
        case .direction:
            planningPickerGrid {
                ForEach(configuration.visualPresets.directions) { value in
                    AISChoiceChip(
                        title: value.localizedName,
                        detail: value.localizedDescription,
                        isSelected: selectedDirectionID == value.id,
                        isAvailable: true,
                        fillsWidth: true
                    ) {
                        selectedDirectionID = value.id
                    }
                }
            }
        case .effects:
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "creation.effects.maximum"),
                        configuration.effectSelectionLimit
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                planningPickerGrid {
                    ForEach(configuration.visualPresets.effects) { value in
                        let isSelected = selectedEffectIDs.contains(value.id)
                        AISChoiceChip(
                            title: value.localizedName,
                            detail: value.localizedDescription,
                            isSelected: isSelected,
                            isAvailable: isSelected
                                || selectedEffectIDs.count
                                    < configuration.effectSelectionLimit,
                            fillsWidth: true
                        ) {
                            toggleEffect(value.id)
                        }
                    }
                }
            }
        case let .attribute(groupID):
            if let group = planningAttributeGroups.first(where: {
                $0.id == groupID
            }) {
                VStack(alignment: .leading, spacing: 12) {
                    if group.type == "multiple" {
                        Text(
                            String.localizedStringWithFormat(
                                String(
                                    localized: "creation.attributes.maximum"
                                ),
                                max(1, group.maxSelected)
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    planningPickerGrid {
                        ForEach(group.items.sorted { $0.sort < $1.sort }) {
                            item in
                            let isSelected = selectedAttributes[
                                group.id,
                                default: []
                            ].contains(item.id)
                            AISChoiceChip(
                                title: item.localizedName,
                                detail: item.localizedDescription,
                                isSelected: isSelected,
                                isAvailable: canSelectAttribute(
                                    item,
                                    in: group,
                                    isSelected: isSelected
                                ),
                                badge: item.requiredMembershipName,
                                fillsWidth: true
                            ) {
                                toggleAttribute(item.id, in: group)
                            }
                        }
                    }
                }
            }
        }
    }

    private func planningPickerTitle(
        _ picker: CreationPlanningPicker
    ) -> String {
        switch picker {
        case .direction:
            String(localized: "creation.direction")
        case .effects:
            String(localized: "creation.effects")
        case let .attribute(groupID):
            planningAttributeGroups.first(where: { $0.id == groupID })?
                .localizedName
                ?? String(localized: "creation.attributes.title")
        }
    }

    private func planningPickerGrid<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible(), alignment: .top)]
                : [
                    GridItem(.flexible(), spacing: 8, alignment: .top),
                    GridItem(.flexible(), spacing: 8, alignment: .top)
                ],
            alignment: .leading,
            spacing: 8,
            content: content
        )
    }

    private func toggleEffect(_ effectID: String) {
        if let index = selectedEffectIDs.firstIndex(of: effectID) {
            selectedEffectIDs.remove(at: index)
        } else if selectedEffectIDs.count
            < configuration.effectSelectionLimit {
            selectedEffectIDs.append(effectID)
        }
    }

    private func canSelectAttribute(
        _ item: AISPromptAttributeItem,
        in group: AISPromptAttributeGroup,
        isSelected: Bool
    ) -> Bool {
        guard item.isAvailable else { return false }
        guard group.type == "multiple", !isSelected else { return true }
        return selectedAttributes[group.id, default: []].count
            < max(1, group.maxSelected)
    }

    private func attributeDisclosure(
        _ group: AISPromptAttributeGroup
    ) -> some View {
        let selected = selectedAttributes[group.id, default: []]
        let selectedNames = group.items
            .filter { selected.contains($0.id) }
            .map(\.localizedName)
            .joined(separator: " / ")
        return DisclosureGroup(
            isExpanded: Binding(
                get: { expandedAttributeGroups.contains(group.id) },
                set: { expanded in
                    if expanded {
                        expandedAttributeGroups.insert(group.id)
                    } else {
                        expandedAttributeGroups.remove(group.id)
                    }
                }
            )
        ) {
            attributePicker(group, showsTitle: false)
                .padding(.top, 10)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.localizedName)
                        .font(.subheadline.weight(.semibold))
                    if !selectedNames.isEmpty {
                        Text(selectedNames)
                            .font(.caption)
                            .foregroundStyle(AISTheme.accent)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !selected.isEmpty {
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "creation.attributes.selected"),
                            selected.count
                        )
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AISTheme.accent)
                }
                if group.type == "multiple" {
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "creation.attributes.maximum"),
                            group.maxSelected
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            Color(uiColor: .tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func presetPicker(
        title: String,
        values: [AISVisualPreset],
        selection: Binding<String>,
        allowsMultiple: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            AISFlowLayout(spacing: 8) {
                ForEach(values) { value in
                    AISChoiceChip(
                        title: value.localizedName,
                        detail: value.localizedDescription,
                        isSelected: selection.wrappedValue == value.id,
                        isAvailable: true
                    ) {
                        selection.wrappedValue = value.id
                    }
                }
            }
        }
    }

    private var effectPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("creation.effects")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "creation.effects.maximum"),
                        configuration.effectSelectionLimit
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            AISFlowLayout(spacing: 8) {
                ForEach(configuration.visualPresets.effects) { value in
                    let isSelected = selectedEffectIDs.contains(value.id)
                    AISChoiceChip(
                        title: value.localizedName,
                        detail: value.localizedDescription,
                        isSelected: isSelected,
                        isAvailable: isSelected
                            || selectedEffectIDs.count
                                < configuration.effectSelectionLimit
                    ) {
                        toggleEffect(value.id)
                    }
                }
            }
        }
    }

    private func attributePicker(
        _ group: AISPromptAttributeGroup,
        showsTitle: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                Text(group.localizedName).font(.subheadline.weight(.semibold))
            }
            AISFlowLayout(spacing: 8) {
                ForEach(group.items.sorted { $0.sort < $1.sort }) { item in
                    AISChoiceChip(
                        title: item.localizedName,
                        detail: item.localizedDescription,
                        isSelected: selectedAttributes[group.id, default: []]
                            .contains(item.id),
                        isAvailable: item.isAvailable,
                        badge: item.membershipLabel
                    ) {
                        toggleAttribute(item.id, in: group)
                    }
                }
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionTitle(
                    "creation.output.title",
                    systemImage: "slider.horizontal.3"
                )
                Spacer()
                if configuration.isLoading {
                    ProgressView()
                }
            }
            if let error = configuration.errorMessage,
               !configuration.canSubmit {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("common.retry") {
                        Task {
                            let token = await session.validAccessToken()
                            await configuration.load(
                                userID: session.user?.id,
                                accessToken: token,
                                force: true
                            )
                            normalizeConfiguration()
                        }
                    }
                }
            }
            specPicker(
                title: String(localized: "creation.orientation"),
                values: configuration.specs("orientation"),
                selection: $orientation,
                columnCount: 3
            )
            specPicker(
                title: String(localized: "creation.aspect_ratio"),
                values: availableRatios,
                selection: $aspectRatio,
                columnCount: 4
            )
            specPicker(
                title: String(localized: "creation.resolution"),
                values: configuration.specs("resolution"),
                selection: $resolution,
                columnCount: 3
            )
            AISGenerationModelPicker(
                models: configuration.models,
                selectedModelKey: $selectedModelKey,
                allowsSelection: true
            )
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
        .onChange(of: orientation) { _, _ in
            normalizeConfiguration()
        }
    }

    private var availableRatios: [AISModelOutputSpec] {
        let matching = configuration.specs("aspect_ratio").filter {
            configuration.orientationForAspect($0.value) == orientation
        }
        return matching.isEmpty
            ? configuration.specs("aspect_ratio")
            : matching
    }

    private func specPicker(
        title: String,
        values: [AISModelOutputSpec],
        selection: Binding<String>,
        columnCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .flexible(minimum: 0),
                        spacing: 8,
                        alignment: .top
                    ),
                    count: dynamicTypeSize.isAccessibilitySize
                        ? 1
                        : columnCount
                ),
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(values) { spec in
                    AISChoiceChip(
                        title: spec.localizedName,
                        detail: spec.value == spec.localizedName
                            ? nil
                            : spec.value,
                        isSelected: selection.wrappedValue == spec.value,
                        isAvailable: spec.isAvailable,
                        badge: spec.membershipLabel,
                        pricingBadge: AISPointMultiplierFormatter.visibleLabel(
                            spec.multiplier
                        ),
                        fillsWidth: true
                    ) {
                        selection.wrappedValue = spec.value
                    }
                }
            }
        }
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
                    Text(promoHelper)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(AISTheme.accent)
            Divider()
            Toggle(isOn: $recommendToGallery) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("creation.gallery.title")
                        .font(.subheadline.weight(.semibold))
                    Text("creation.gallery.helper")
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

    private var promoHelper: String {
        if promoMarkEnabled,
           viewModel.quote?.promoMarkEnabled == false,
           viewModel.quote?.promoMarkSuppressedReason != nil {
            return String(localized: "creation.promo.suppressed")
        }
        if promoMarkEnabled,
           let saved = viewModel.promoSavedPoints,
           saved > 0 {
            return String.localizedStringWithFormat(
                String(localized: "creation.promo.saved"),
                saved
            )
        }
        return String(localized: "creation.promo.helper")
    }

    @ViewBuilder
    private var submissionArea: some View {
        if let notice = viewModel.pricingNoticeMessage {
            Label(notice, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(AISTheme.accentSecondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    AISTheme.accentSecondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 16)
                )
        }
        if let error = viewModel.errorMessage {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
        if let job = viewModel.activeJob, !job.isActive {
            CreationJobStatusCard(
                job: job,
                onViewResult: {
                    isRequirementFocused = false
                    selectedResultTask = job
                },
                onCreateAnother: {
                    isRequirementFocused = false
                    viewModel.createAnother()
                    prompt = ""
                    optimizedPrompt = ""
                    usesOptimizedPrompt = false
                }
            )
            .id("creation-job-status")
        }
    }

    private var generationButton: some View {
        Button {
            isRequirementFocused = false
            if canRetryPricingRules {
                Task { await retryPricingRules() }
                return
            }
            guard session.isAuthenticated else {
                presentsLogin = true
                return
            }
            if AISCreationPreflight.requiresPlanningSuggestion(
                usesOptimizedPrompt: usesOptimizedPrompt,
                optimizedPrompt: optimizedPrompt
            ) {
                presentsPlanningSuggestion = true
            } else {
                confirmsGeneration = true
            }
        } label: {
            HStack {
                if viewModel.isWorking
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

    private var generationProgressFooter: some View {
        Button {
            guard let job = viewModel.activeJob else { return }
            isRequirementFocused = false
            selectedResultTask = job
        } label: {
            VStack(spacing: 8) {
                Label(
                    "creation.status.processing",
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.headline)
                if let job = viewModel.activeJob {
                    ProgressView(value: Double(job.progress), total: 100)
                        .tint(AISTheme.accent)
                    Text("\(job.progress)%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                } else {
                    ProgressView()
                        .tint(AISTheme.accent)
                    Text("creation.status.waiting_progress")
                        .font(.caption)
                }
            }
            .foregroundStyle(AISTheme.accent)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AISTheme.line.opacity(0.55), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(viewModel.activeJob != nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            viewModel.activeJob == nil
                ? Text("")
                : Text("creation.status.open_task")
        )
    }

    private var canRetryPricingRules: Bool {
        session.isAuthenticated
            && appData.generationLoadFailed
            && !appData.isRefreshingUserData
            && !configuration.isLoading
            && !pricingRules.isLoading
    }

    private var canGenerate: Bool {
        !viewModel.isWorking
            && appData.isGenerationReady
            && !viewModel.references.isEmpty
            && !effectivePrompt.isEmpty
            && configuration.canSubmit
            && viewModel.quote != nil
            && configuration.models.contains {
                $0.displayModelKey == selectedModelKey
                    && AISGenerationModelSelection.canSelect(
                        $0,
                        allowsSelection: true
                    )
            }
    }

    private var effectivePrompt: String {
        let value = usesOptimizedPrompt ? optimizedPrompt : prompt
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canOptimizePrompt: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || viewModel.references.contains {
                !$0.userNote.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            }
    }

    private var generationButtonTitle: String {
        if viewModel.isWorking {
            return String(localized: "creation.submitting")
        }
        if !session.isAuthenticated {
            return String(localized: "creation.signin")
        }
        if canRetryPricingRules {
            return String(localized: "creation.pricing.retry")
        }
        return String(localized: "creation.confirm.action")
    }

    private var generationButtonSubtitle: String? {
        guard !viewModel.isWorking, session.isAuthenticated else { return nil }
        if !appData.isGenerationReady {
            return appData.generationLoadFailed
                ? String(localized: "creation.data.reload")
                : String(localized: "creation.data.loading")
        }
        if let quote = viewModel.quote {
            if let original = quote.originalPoints,
               let saved = quote.savedPoints,
               saved > 0 {
                return String.localizedStringWithFormat(
                    String(
                        localized: "creation.generate.estimated_discounted"
                    ),
                    quote.points,
                    original,
                    saved
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

    private var quoteSignature: String {
        let attributes = requestSelectedAttributes
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.sorted().joined(separator: ","))" }
            .joined(separator: "&")
        return [
            String(session.isAuthenticated),
            orientation,
            aspectRatio,
            resolution,
            selectedModelKey,
            attributes,
            String(promoMarkEnabled)
        ].joined(separator: "|")
    }

    private func retryPricingRules() async {
        await appData.retryGenerationPrerequisites(session: session)
    }

    private var draftSignature: String {
        let referenceSignature = viewModel.references.map {
            [
                $0.id.uuidString,
                $0.remoteAssetID ?? "",
                String($0.data?.count ?? 0),
                $0.referenceRole,
                $0.preserveMode,
                $0.displayName,
                $0.userNote
            ].joined(separator: ":")
        }.joined(separator: "|")
        return [
            quoteSignature,
            prompt,
            optimizedPrompt,
            String(usesOptimizedPrompt),
            selectedDirectionID,
            selectedEffectIDs.sorted().joined(separator: ","),
            String(recommendToGallery),
            referenceSignature
        ].joined(separator: "||")
    }

    private func sectionTitle(
        _ title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage).font(.headline)
    }

    private func normalizeConfiguration() {
        configuration.normalize(
            orientation: &orientation,
            aspectRatio: &aspectRatio,
            resolution: &resolution,
            modelKey: &selectedModelKey
        )
        let activeEffectIDs = Set(
            configuration.visualPresets.effects.map(\.id)
        )
        selectedEffectIDs = AISCreationSelectionPolicy.normalizedEffectIDs(
            selectedEffectIDs,
            availableIDs: activeEffectIDs,
            limit: configuration.effectSelectionLimit
        )
        let activeDirectionIDs = Set(
            configuration.visualPresets.directions.map(\.id)
        )
        if !activeDirectionIDs.contains(selectedDirectionID) {
            selectedDirectionID = configuration.visualPresets.directions
                .first?.id ?? ""
        }
        selectedAttributes = selectedAttributes.filter {
            !AISCreationSelectionPolicy.hiddenExtendedAttributeIDs.contains(
                $0.key.lowercased()
            )
        }
    }

    private var requestSelectedAttributes: [String: [String]] {
        AISCreationSelectionPolicy.requestAttributes(
            from: selectedAttributes,
            directionID: selectedDirectionID
        )
    }

    private func toggleAttribute(
        _ itemID: String,
        in group: AISPromptAttributeGroup
    ) {
        var values = selectedAttributes[group.id, default: []]
        if let index = values.firstIndex(of: itemID) {
            values.remove(at: index)
        } else {
            if group.type == "single" || group.type == "toggle" {
                values = [itemID]
            } else {
                let limit = max(1, group.maxSelected)
                if values.count >= limit { values.removeFirst() }
                values.append(itemID)
            }
        }
        selectedAttributes[group.id] = values
    }

    private func beginSelectingReferences() {
        guard session.isAuthenticated else {
            presentsLogin = true
            return
        }
        if acceptedUploadCompliance {
            presentsPhotoPicker = true
        } else {
            confirmsUploadCompliance = true
        }
    }

    private func addClipboardImage() {
        guard session.isAuthenticated else {
            presentsLogin = true
            return
        }
        guard let image = UIPasteboard.general.image,
              let data = image.pngData() else {
            viewModel.errorMessage = String(localized: "creation.clipboard.empty")
            return
        }
        if let id = viewModel.addClipboardReference(data: data, image: image) {
            handleAddedReferences([id])
        }
    }

    private func handleAddedReferences(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        if ids.count == 1 {
            editingReferenceID = ids[0]
        } else {
            showsReferenceUnderstandingHint = true
        }
    }

    private func requestPromptOptimization() {
        guard canOptimizePrompt, !isLoadingPromptOptimizationQuote else {
            return
        }
        isLoadingPromptOptimizationQuote = true
        Task {
            defer { isLoadingPromptOptimizationQuote = false }
            do {
                let token = await session.validAccessToken()
                promptOptimizationQuote = try await viewModel.quote(
                    action: .promptOptimize,
                    accessToken: token
                )
                confirmsPromptOptimization = true
            } catch where AISErrorClassifier.isCancellation(error) {
                NetworkDiagnosticsStore.shared.recordSystemLog(
                    tag: "CANCELLED",
                    "Prompt optimization quote request was cancelled."
                )
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func optimizePrompt() async {
        promptOptimizationStartedAt = .now
        defer { promptOptimizationStartedAt = nil }
        let token = await session.validAccessToken()
        await viewModel.optimizePrompt(
            prompt: prompt,
            directionID: selectedDirectionID,
            effects: selectedEffectIDs,
            effectPresets: configuration.visualPresets.effects,
            selectedAttributes: requestSelectedAttributes,
            aspectRatio: aspectRatio,
            resolution: resolution,
            references: viewModel.references,
            accessToken: token
        )
        if let value = viewModel.optimizedPrompt {
            optimizedPrompt = value
            usesOptimizedPrompt = true
        }
    }

    @ViewBuilder
    private func promptOptimizationLabel(
        at date: Date,
        startedAt: Date
    ) -> some View {
        let estimate = appData.durationEstimates.seconds(
            for: "prompt_optimize"
        ) ?? 20
        HStack(spacing: 6) {
            ProgressView()
            switch AISCountdownPresentation.resolve(
                startedAt: startedAt,
                estimateSeconds: estimate,
                now: date
            ) {
            case let .remaining(remaining):
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "creation.optimize.countdown"),
                        AISDurationTextFormatter.countdown(
                            seconds: remaining
                        )
                    )
                )
            case .overdue:
                Text("creation.optimize.overdue")
            }
        }
    }

    private func submit() async {
        isRequirementFocused = false
        guard appData.isGenerationReady else {
            await appData.retryGenerationPrerequisites(session: session)
            return
        }
        let token = await session.validAccessToken()
        await viewModel.submit(
            prompt: effectivePrompt,
            styleID: selectedDirectionID.nilIfEmpty,
            effects: selectedEffectIDs,
            orientation: orientation,
            aspectRatio: aspectRatio,
            resolution: resolution,
            selectedModelKey: selectedModelKey,
            selectedAttributes: requestSelectedAttributes,
            promoMarkEnabled: promoMarkEnabled,
            recommendToGallery: recommendToGallery,
            configuration: configuration,
            userID: session.user?.id,
            accessToken: token
        )
        if let latest = viewModel.takePendingPricingRulesUpdate() {
            await pricingRules.replace(
                latest,
                userID: session.user?.id
            )
        }
        if let jobID = viewModel.activeJobID {
            await saveDraft()
            await viewModel.monitor(jobID: jobID, accessToken: token)
        }
    }

    private func saveDraft() async {
        guard let userID = session.user?.id else { return }
        await viewModel.saveDraft(
            userID: userID,
            state: CreationDraftState(
                prompt: prompt,
                optimizedPrompt: optimizedPrompt,
                usesOptimizedPrompt: usesOptimizedPrompt,
                orientation: orientation,
                aspectRatio: aspectRatio,
                resolution: resolution,
                selectedModelKey: selectedModelKey,
                selectedDirectionID: selectedDirectionID,
                selectedEffectIDs: selectedEffectIDs,
                selectedAttributes: selectedAttributes,
                recommendToGallery: recommendToGallery
            )
        )
    }

    private func restoreDraft() async {
        guard let userID = session.user?.id,
              let draft = await viewModel.restoreDraft(userID: userID) else {
            return
        }
        prompt = draft.state.prompt
        optimizedPrompt = draft.state.optimizedPrompt
        usesOptimizedPrompt = draft.state.usesOptimizedPrompt
        orientation = draft.state.orientation
        aspectRatio = draft.state.aspectRatio
        resolution = draft.state.resolution
        selectedModelKey = draft.state.selectedModelKey
        selectedDirectionID = draft.state.selectedDirectionID
        selectedEffectIDs = draft.state.selectedEffectIDs
        selectedAttributes = draft.state.selectedAttributes
        recommendToGallery = draft.state.recommendToGallery
        normalizeConfiguration()
    }
}

struct CreationReference: Identifiable {
    let id: UUID
    var data: Data?
    var image: UIImage?
    var remoteAssetID: String?
    var remoteURL: URL?
    var fileName: String
    var mimeType: String
    var referenceRole: String
    var preserveMode: String
    var displayName: String
    var userNote: String
}

private struct CreationQuoteRequest: Encodable {
    let generationType = "image"
    let orientation: String
    let aspectRatio: String
    let resolution: String
    let selectedDisplayModelKey: String
    let selectedAttributes: [String: [String]]
    let promoMarkEnabled: Bool
    let count = 1
}

private struct CreationJobRequest: Encodable {
    let prompt: String
    let style: String?
    let selectedEffects: [String]
    let language: String
    let orientation: String
    let aspectRatio: String
    let resolution: String
    let promoMarkEnabled: Bool
    let recommendToGallery: Bool
    let referenceAssetIds: [String]
    let selectedAttributes: [String: [String]]
    let pricingRulesVersion: String
    let pricingSnapshotToken: String
    let pricingSnapshotVersion: String
    let localCalculatedPoints: Int
    let selectedDisplayModelKey: String?
    let clientSnapshot: CreationClientSnapshot
}

private struct CreationClientSnapshot: Encodable {
    let schemaVersion = 1
    let capturedAt: Date
    let workflow: CreationWorkflowSnapshot
    let image: CreationImageSnapshot
    let references: [CreationReferenceSnapshot]
}

private struct CreationWorkflowSnapshot: Encodable {
    let selectedStyle: String?
    let selectedEffects: [String]
    let imageSelectedAttributes: [String: [String]]
    let recommendToGallery: Bool
    let promoMarkEnabled: Bool
}

private struct CreationImageSnapshot: Encodable {
    let prompt: String
    let orientation: String
    let aspectRatio: String
    let resolution: String
    let selectedDisplayModelKey: String
}

private struct CreationReferenceSnapshot: Encodable {
    let index: Int
    let id: String
    let displayName: String
    let referenceRole: String
    let preserveMode: String
    let userNote: String
}

private struct CreationReferenceMetaRequest: Encodable {
    let assetId: String
    let referenceRole: String
    let preserveMode: String
    let displayName: String
    let userNote: String
}

private struct CreationUnderstandRequest: Encodable {
    let assetId: String
    let referenceRole: String
    let userHint: String
}

enum AISBillableAction: String {
    case imageUnderstand = "image_understand"
    case promptOptimize = "prompt_optimize"
}

struct AISBillableActionQuoteRequest: Encodable, Equatable {
    let generationType: String
    let count: Int

    init(action: AISBillableAction, count: Int = 1) {
        generationType = action.rawValue
        self.count = count
    }
}

enum AISCreationPreflight {
    static func requiresPlanningSuggestion(
        usesOptimizedPrompt: Bool,
        optimizedPrompt: String
    ) -> Bool {
        !usesOptimizedPrompt
            || optimizedPrompt.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }
}

enum AISCreationSubmissionState: Equatable {
    case idle
    case submitting
    case waitingForProgress
    case generating(Int)
    case terminal

    static func resolve(
        isWorking: Bool,
        activeJobID: String?,
        activeJobIsActive: Bool?,
        progress: Int?
    ) -> Self {
        guard activeJobID != nil else {
            return isWorking ? .submitting : .idle
        }
        guard let activeJobIsActive else {
            return .waitingForProgress
        }
        return activeJobIsActive
            ? .generating(min(100, max(0, progress ?? 0)))
            : .terminal
    }
}

private struct CreationAsyncResult: Decodable {
    let jobId: String
    let status: String

    private enum CodingKeys: String, CodingKey {
        case jobId = "JobId"
        case status = "Status"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decodeFlexibleString(forKey: .jobId) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status)
            ?? "queued"
    }
}

private struct CreationUnderstandStatus: Decodable {
    let jobId: String?
    let status: String
    let progress: Int
    let description: String?
    let errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case jobId = "JobId"
        case status = "Status"
        case progress = "Progress"
        case description = "Description"
        case errorMessage = "ErrorMessage"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decodeFlexibleString(forKey: .jobId)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "idle"
        progress = try container.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        description = try container.decodeIfPresent(String.self, forKey: .description)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

private struct CreationPromptReference: Encodable {
    let id: String
    let role: String
    let preserveMode: String
    let displayName: String
    let userNote: String
}

private struct CreationPromptOptimizeRequest: Encodable {
    let prompt: String
    let style: String?
    let language: String
    let aspectRatio: String
    let resolution: String
    let desiredEffect: String
    let effects: [CreationPromptEffect]
    let selectedAttributes: [String: [String]]
    let hasCadReferences: Bool
    let referenceAssets: [CreationPromptReference]
}

private struct CreationPromptEffect: Encodable {
    let id: String
    let name: String
    let prompt: String
}

private struct CreationPromptOptimizeResponse: Decodable {
    let jobId: String
    let status: String
    let imagePrompt: String?

    private enum CodingKeys: String, CodingKey {
        case jobId = "JobId"
        case status = "Status"
        case imagePrompt = "ImagePrompt"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decodeFlexibleString(forKey: .jobId) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status)
            ?? "queued"
        imagePrompt = try container.decodeIfPresent(
            String.self,
            forKey: .imagePrompt
        )
    }
}

struct CreationDraftState: Codable {
    let prompt: String
    let optimizedPrompt: String
    let usesOptimizedPrompt: Bool
    let orientation: String
    let aspectRatio: String
    let resolution: String
    let selectedModelKey: String
    let selectedDirectionID: String
    let selectedEffectIDs: [String]
    let selectedAttributes: [String: [String]]
    let recommendToGallery: Bool
}

private struct CreationReferenceDraft: Codable {
    let id: UUID
    let data: Data?
    let remoteAssetID: String?
    let remoteURL: URL?
    let fileName: String
    let mimeType: String
    let referenceRole: String
    let preserveMode: String
    let displayName: String
    let userNote: String
}

private struct CreationStoredDraft: Codable {
    let state: CreationDraftState
    let references: [CreationReferenceDraft]
    let activeJobID: String?
}

@MainActor
@Observable
private final class CreationViewModel {
    private let api = APIClient()

    private(set) var references: [CreationReference] = []
    private(set) var quote: AISPointQuote?
    private(set) var membershipSavedPoints: Int?
    private(set) var promoSavedPoints: Int?
    private(set) var pricingSnapshot: AISPricingSnapshot?
    private var pendingPricingRulesUpdate: AISPricingRulesSnapshot?
    private(set) var isWorking = false
    private(set) var isOptimizing = false
    private(set) var understandingReferenceID: UUID?
    private(set) var understandingStates:
        [UUID: CreationReferenceUnderstandingState] = [:]
    private(set) var understandingProgress: [UUID: Int] = [:]
    private(set) var understandingStartedAt: [UUID: Date] = [:]
    private(set) var optimizedPrompt: String?
    private(set) var activeJob: AISTaskJob?
    private(set) var activeJobID: String?
    var errorMessage: String?
    var pricingNoticeMessage: String?

    var submissionState: AISCreationSubmissionState {
        .resolve(
            isWorking: isWorking,
            activeJobID: activeJobID,
            activeJobIsActive: activeJob?.isActive,
            progress: activeJob?.progress
        )
    }

    var isGenerationActive: Bool {
        switch submissionState {
        case .waitingForProgress, .generating:
            true
        default:
            false
        }
    }

    func addReferences(from items: [PhotosPickerItem]) async -> [UUID] {
        let available = max(0, 3 - references.count)
        var addedIDs: [UUID] = []
        for (index, item) in items.prefix(available).enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
            let id = UUID()
            references.append(
                CreationReference(
                    id: id,
                    data: data,
                    image: image,
                    remoteAssetID: nil,
                    remoteURL: nil,
                    fileName: "product-\(references.count + index + 1).\(isPNG ? "png" : "jpg")",
                    mimeType: isPNG ? "image/png" : "image/jpeg",
                    referenceRole: "product_photo",
                    preserveMode: "reference",
                    displayName: String(localized: "creation.reference.default_name"),
                    userNote: ""
                )
            )
            addedIDs.append(id)
        }
        return addedIDs
    }

    func addClipboardReference(data: Data, image: UIImage) -> UUID? {
        guard references.count < 3 else { return nil }
        let id = UUID()
        references.append(
            CreationReference(
                id: id,
                data: data,
                image: image,
                remoteAssetID: nil,
                remoteURL: nil,
                fileName: "clipboard-\(references.count + 1).png",
                mimeType: "image/png",
                referenceRole: "product_photo",
                preserveMode: "reference",
                displayName: String(localized: "creation.reference.clipboard"),
                userNote: ""
            )
        )
        return id
    }

    func addLibraryReferences(_ assets: [AISAssetLibraryItem]) -> [UUID] {
        let existing = Set(references.compactMap(\.remoteAssetID))
        var addedIDs: [UUID] = []
        for asset in assets where references.count < 3 && !existing.contains(asset.id) {
            let id = UUID()
            references.append(
                CreationReference(
                    id: id,
                    data: nil,
                    image: nil,
                    remoteAssetID: asset.id,
                    remoteURL: asset.resolvedURL,
                    fileName: asset.resolvedName,
                    mimeType: "image/jpeg",
                    referenceRole: "product_photo",
                    preserveMode: "reference",
                    displayName: asset.resolvedName,
                    userNote: asset.description ?? ""
                )
            )
            addedIDs.append(id)
        }
        return addedIDs
    }

    func addJobReference(_ job: AISTaskJob) {
        guard references.count < 3,
              let assetID = job.resultAssetId,
              !references.contains(where: { $0.remoteAssetID == assetID }) else {
            return
        }
        references.append(
            CreationReference(
                id: UUID(),
                data: nil,
                image: nil,
                remoteAssetID: assetID,
                remoteURL: job.mediaURL,
                fileName: "AIS-\(job.id).jpg",
                mimeType: "image/jpeg",
                referenceRole: "product_photo",
                preserveMode: "reference",
                displayName: String(localized: "tasks.detail.continue_editing"),
                userNote: job.userRequirement
            )
        )
    }

    func removeReference(_ id: UUID) {
        references.removeAll { $0.id == id }
        understandingStates[id] = nil
        understandingProgress[id] = nil
        understandingStartedAt[id] = nil
    }

    func updateReference(
        _ id: UUID,
        role: String,
        preserveMode: String,
        displayName: String,
        userNote: String
    ) {
        guard let index = references.firstIndex(where: { $0.id == id }) else {
            return
        }
        references[index].referenceRole = role
        references[index].preserveMode = preserveMode
        references[index].displayName = displayName
        references[index].userNote = userNote
    }

    func updateLocalQuote(
        rules: AISPricingRulesSnapshot,
        orientation: String,
        aspectRatio: String,
        resolution: String,
        selectedModelKey: String,
        selectedAttributes: [String: [String]],
        promoMarkEnabled: Bool,
        configuration: AISCreationConfigurationStore
    ) {
        pricingNoticeMessage = nil
        pricingSnapshot = rules
        let multipliers = configuration.attributeGroups.flatMap { group in
            group.items.filter {
                selectedAttributes[group.id, default: []].contains($0.id)
            }.map(\.multiplier)
        }
        let local = AISLocalPricingCalculator.image(
            snapshot: rules,
            orientation: orientation,
            aspectRatio: aspectRatio,
            resolution: resolution,
            selectedAttributes: selectedAttributes,
            selectedModelKey: selectedModelKey,
            fallbackOrientationMultiplier: configuration
                .specs("orientation")
                .first {
                    $0.value.caseInsensitiveCompare(orientation)
                        == .orderedSame
                }?.multiplier ?? 1,
            fallbackAspectRatioMultiplier: configuration
                .specs("aspect_ratio")
                .first {
                    $0.value.caseInsensitiveCompare(aspectRatio)
                        == .orderedSame
                }?.multiplier ?? 1,
            fallbackResolutionMultiplier: configuration
                .specs("resolution")
                .first {
                    $0.value.caseInsensitiveCompare(resolution)
                        == .orderedSame
                }?.multiplier ?? 1,
            attributeMultipliers: multipliers,
            modelMultiplier: configuration.models.first {
                $0.displayModelKey == selectedModelKey
            }?.modelMarkupRate ?? 1,
            promoMarkEnabled: promoMarkEnabled
        )
        quote = AISPointQuote(
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
        pricingSnapshot = nil
    }

    func takePendingPricingRulesUpdate() -> AISPricingRulesSnapshot? {
        defer { pendingPricingRulesUpdate = nil }
        return pendingPricingRulesUpdate
    }

    func quote(
        action: AISBillableAction,
        accessToken: String?
    ) async throws -> AISPointQuote {
        guard let accessToken else {
            throw APIError.rejected(
                message: String(localized: "creation.signin")
            )
        }
        return try await api.post(
            "/api/ais/billing/quote",
            body: AISBillableActionQuoteRequest(action: action),
            accessToken: accessToken
        )
    }

    func submit(
        prompt: String,
        styleID: String?,
        effects: [String],
        orientation: String,
        aspectRatio: String,
        resolution: String,
        selectedModelKey: String,
        selectedAttributes: [String: [String]],
        promoMarkEnabled: Bool,
        recommendToGallery: Bool,
        configuration: AISCreationConfigurationStore,
        userID: String?,
        accessToken: String?
    ) async {
        guard let accessToken, let pricingSnapshot, let quote,
              !isWorking else {
            errorMessage = String(localized: "creation.pricing_expired")
            return
        }
        isWorking = true
        errorMessage = nil
        pricingNoticeMessage = nil
        defer { isWorking = false }
        do {
            let assetIDs = try await ensureUploaded(accessToken: accessToken)
            let snapshots = references.enumerated().map {
                CreationReferenceSnapshot(
                    index: $0.offset,
                    id: $0.element.remoteAssetID ?? "",
                    displayName: $0.element.displayName,
                    referenceRole: $0.element.referenceRole,
                    preserveMode: $0.element.preserveMode,
                    userNote: $0.element.userNote
                )
            }
            let nonce: String = try await api.get(
                "/api/ais/nonce",
                accessToken: accessToken
            )
            let job: AISCreatedJob = try await api.post(
                "/api/ais/images/jobs",
                body: CreationJobRequest(
                    prompt: prompt,
                    style: styleID,
                    selectedEffects: effects,
                    language: AISLocalization.isChinese ? "zh" : "en",
                    orientation: orientation,
                    aspectRatio: aspectRatio,
                    resolution: resolution,
                    promoMarkEnabled: promoMarkEnabled,
                    recommendToGallery: recommendToGallery,
                    referenceAssetIds: assetIDs,
                    selectedAttributes: selectedAttributes,
                    pricingRulesVersion: pricingSnapshot.version,
                    pricingSnapshotToken: pricingSnapshot.token ?? "",
                    pricingSnapshotVersion: pricingSnapshot.version,
                    localCalculatedPoints: quote.points,
                    selectedDisplayModelKey: selectedModelKey.nilIfEmpty,
                    clientSnapshot: CreationClientSnapshot(
                        capturedAt: .now,
                        workflow: CreationWorkflowSnapshot(
                            selectedStyle: styleID,
                            selectedEffects: effects,
                            imageSelectedAttributes: selectedAttributes,
                            recommendToGallery: recommendToGallery,
                            promoMarkEnabled: promoMarkEnabled
                        ),
                        image: CreationImageSnapshot(
                            prompt: prompt,
                            orientation: orientation,
                            aspectRatio: aspectRatio,
                            resolution: resolution,
                            selectedDisplayModelKey: selectedModelKey
                        ),
                        references: snapshots
                    )
                ),
                accessToken: accessToken,
                headers: ["X-AIS-Nonce": nonce]
            )
            activeJobID = job.id
            activeJob = nil
            NotificationCenter.default.post(
                name: .aisTaskSubmitted,
                object: job.id
            )
        } catch let APIError.business(code, _, details)
            where code == .priceChanged {
            let previousPoints = quote.points
            if let change = AISPriceChangePayload(details: details),
               let latestRules = change.latestPricingRules {
                pendingPricingRulesUpdate = latestRules
                updateLocalQuote(
                    rules: latestRules,
                    orientation: orientation,
                    aspectRatio: aspectRatio,
                    resolution: resolution,
                    selectedModelKey: selectedModelKey,
                    selectedAttributes: selectedAttributes,
                    promoMarkEnabled: promoMarkEnabled,
                    configuration: configuration
                )
                pricingNoticeMessage = String.localizedStringWithFormat(
                    String(localized: "creation.price_changed.detail"),
                    previousPoints,
                    self.quote?.points ?? change.points
                )
            } else if let latestQuote = AISPointQuote(
                priceChangeDetails: details
            ) {
                self.quote = latestQuote
                self.membershipSavedPoints = nil
                self.promoSavedPoints = nil
                pricingNoticeMessage = String(
                    localized: "creation.price_changed"
                )
            } else {
                self.quote = nil
                self.membershipSavedPoints = nil
                self.promoSavedPoints = nil
                self.pricingSnapshot = nil
                pricingNoticeMessage = String(
                    localized: "creation.price_changed"
                )
            }
        } catch where AISErrorClassifier.isCancellation(error) {
            NetworkDiagnosticsStore.shared.recordSystemLog(
                tag: "CANCELLED",
                "Creation submission was cancelled."
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func understand(
        referenceID: UUID,
        role: String,
        userHint: String,
        accessToken: String?
    ) async throws -> String {
        guard let accessToken, understandingReferenceID == nil else {
            throw APIError.rejected(
                message: String(localized: "creation.understand.unavailable")
            )
        }
        understandingReferenceID = referenceID
        understandingStates[referenceID] = .understanding
        understandingProgress[referenceID] = nil
        understandingStartedAt[referenceID] = nil
        errorMessage = nil
        defer { understandingReferenceID = nil }
        do {
            _ = try await ensureUploaded(
                referenceIDs: [referenceID],
                accessToken: accessToken
            )
            guard let reference = references.first(where: {
                $0.id == referenceID
            }), let assetID = reference.remoteAssetID else {
                throw APIError.missingData
            }
            let result: CreationAsyncResult = try await api.post(
                "/api/ais/assets/understand",
                body: CreationUnderstandRequest(
                    assetId: assetID,
                    referenceRole: role,
                    userHint: userHint
                ),
                accessToken: accessToken
            )
            understandingProgress[referenceID] = 5
            understandingStartedAt[referenceID] = .now
            let job = try await waitForTerminal(
                jobID: result.jobId,
                accessToken: accessToken,
                update: { [weak self] job in
                    self?.understandingProgress[referenceID] = min(
                        100,
                        max(0, job.progress)
                    )
                }
            )
            guard job.status.lowercased() == "succeeded",
                  let description = Self.outputString(
                    job.outputJSON,
                    keys: ["description", "Description"]
                  ) else {
                throw APIError.rejected(
                    message: job.errorMessage
                        ?? String(localized: "creation.understand.failed")
                )
            }
            guard let currentReference = references.first(where: {
                $0.id == referenceID
            }) else {
                throw APIError.missingData
            }
            updateReference(
                referenceID,
                role: currentReference.referenceRole,
                preserveMode: currentReference.preserveMode,
                displayName: currentReference.displayName,
                userNote: description
            )
            understandingProgress[referenceID] = 100
            understandingStates[referenceID] = .completed
            return description
        } catch where AISErrorClassifier.isCancellation(error) {
            understandingProgress[referenceID] = nil
            understandingStates[referenceID] = nil
            throw error
        } catch {
            understandingProgress[referenceID] = nil
            understandingStates[referenceID] = .failed
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func restoreUnderstanding(referenceID: UUID, accessToken: String?) async {
        guard let accessToken,
              understandingReferenceID == nil,
              let reference = references.first(where: { $0.id == referenceID }),
              let assetID = reference.remoteAssetID else { return }
        do {
            let status: CreationUnderstandStatus = try await api.get(
                "/api/ais/assets/\(assetID)/understanding",
                accessToken: accessToken
            )
            let normalizedStatus = status.status.lowercased()
            if normalizedStatus == "succeeded", let description = status.description?.nilIfEmpty {
                updateReference(referenceID, role: reference.referenceRole, preserveMode: reference.preserveMode, displayName: reference.displayName, userNote: description)
                understandingStates[referenceID] = .completed
                understandingProgress[referenceID] = 100
                return
            }
            if normalizedStatus == "failed" {
                understandingStates[referenceID] = .failed
                errorMessage = status.errorMessage
                return
            }
            guard let jobID = status.jobId,
                  ["queued", "running", "pending"].contains(normalizedStatus) else { return }
            understandingReferenceID = referenceID
            understandingStates[referenceID] = .understanding
            understandingProgress[referenceID] = status.progress
            understandingStartedAt[referenceID] = .now
            defer { understandingReferenceID = nil }
            let job = try await waitForTerminal(jobID: jobID, accessToken: accessToken) { [weak self] job in
                self?.understandingProgress[referenceID] = min(100, max(0, job.progress))
            }
            guard job.status.lowercased() == "succeeded",
                  let description = Self.outputString(job.outputJSON, keys: ["description", "Description"]) else {
                understandingStates[referenceID] = .failed
                errorMessage = job.errorMessage ?? String(localized: "creation.understand.failed")
                return
            }
            updateReference(referenceID, role: reference.referenceRole, preserveMode: reference.preserveMode, displayName: reference.displayName, userNote: description)
            understandingProgress[referenceID] = 100
            understandingStates[referenceID] = .completed
        } catch {
            // 网络恢复失败不覆盖服务端仍在运行的任务；下次打开会重新获取状态。
        }
    }

    func optimizePrompt(
        prompt: String,
        directionID: String,
        effects: [String],
        effectPresets: [AISVisualPreset],
        selectedAttributes: [String: [String]],
        aspectRatio: String,
        resolution: String,
        references: [CreationReference],
        accessToken: String?
    ) async {
        guard let accessToken, !isOptimizing else { return }
        isOptimizing = true
        errorMessage = nil
        defer { isOptimizing = false }
        do {
            let result: CreationPromptOptimizeResponse = try await api.post(
                "/api/ais/prompts/optimize",
                body: CreationPromptOptimizeRequest(
                    prompt: prompt,
                    style: directionID.nilIfEmpty,
                    language: AISLocalization.isChinese ? "zh" : "en",
                    aspectRatio: aspectRatio,
                    resolution: resolution,
                    desiredEffect: effects.joined(separator: ","),
                    effects: effectPresets
                        .filter { effects.contains($0.id) }
                        .map {
                            CreationPromptEffect(
                                id: $0.id,
                                name: $0.localizedName,
                                prompt: $0.localizedDescription
                                    ?? $0.localizedName
                            )
                        },
                    selectedAttributes: selectedAttributes,
                    hasCadReferences: references.contains {
                        $0.referenceRole == "cad"
                    },
                    referenceAssets: references.compactMap { reference in
                        guard let id = reference.remoteAssetID else {
                            return nil
                        }
                        return CreationPromptReference(
                            id: id,
                            role: reference.referenceRole,
                            preserveMode: reference.preserveMode,
                            displayName: reference.displayName,
                            userNote: reference.userNote
                        )
                    }
                ),
                accessToken: accessToken
            )
            if let prompt = result.imagePrompt?.nilIfEmpty {
                optimizedPrompt = prompt
                return
            }
            let job = try await waitForTerminal(
                jobID: result.jobId,
                accessToken: accessToken
            )
            guard job.status.lowercased() == "succeeded",
                  let value = Self.outputString(
                    job.outputJSON,
                    keys: ["imagePrompt", "ImagePrompt"]
                  ) else {
                throw APIError.rejected(
                    message: job.errorMessage
                        ?? String(localized: "creation.optimize.failed")
                )
            }
            optimizedPrompt = value
        } catch where AISErrorClassifier.isCancellation(error) {
            NetworkDiagnosticsStore.shared.recordSystemLog(
                tag: "CANCELLED",
                "Prompt optimization request was cancelled."
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func monitor(jobID: String, accessToken: String?) async {
        guard let accessToken else { return }
        do {
            activeJob = try await waitForTerminal(
                jobID: jobID,
                accessToken: accessToken,
                update: { [weak self] job in self?.activeJob = job }
            )
        } catch where AISErrorClassifier.isCancellation(error) {
            NetworkDiagnosticsStore.shared.recordSystemLog(
                tag: "CANCELLED",
                "Creation task monitoring was cancelled."
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createAnother() {
        activeJob = nil
        activeJobID = nil
        optimizedPrompt = nil
        understandingReferenceID = nil
        understandingStates = [:]
        understandingProgress = [:]
        understandingStartedAt = [:]
    }

    func resetForLogout() {
        references = []
        quote = nil
        membershipSavedPoints = nil
        promoSavedPoints = nil
        pricingSnapshot = nil
        activeJob = nil
        activeJobID = nil
        optimizedPrompt = nil
    }

    func saveDraft(userID: String, state: CreationDraftState) async {
        let stored = CreationStoredDraft(
            state: state,
            references: references.map {
                CreationReferenceDraft(
                    id: $0.id,
                    data: $0.data,
                    remoteAssetID: $0.remoteAssetID,
                    remoteURL: $0.remoteURL,
                    fileName: $0.fileName,
                    mimeType: $0.mimeType,
                    referenceRole: $0.referenceRole,
                    preserveMode: $0.preserveMode,
                    displayName: $0.displayName,
                    userNote: $0.userNote
                )
            },
            activeJobID: activeJobID
        )
        await AISResponseCache.shared.write(
            stored,
            key: Self.draftKey(userID),
            encrypted: true
        )
    }

    func restoreDraft(userID: String) async -> CreationStoredDraft? {
        guard let cached = await AISResponseCache.shared.read(
            CreationStoredDraft.self,
            key: Self.draftKey(userID),
            ttl: 7 * 24 * 60 * 60,
            encrypted: true
        ) else { return nil }
        references = cached.value.references.compactMap {
            let image = $0.data.flatMap(UIImage.init(data:))
            guard image != nil || $0.remoteAssetID != nil else { return nil }
            return CreationReference(
                id: $0.id,
                data: $0.data,
                image: image,
                remoteAssetID: $0.remoteAssetID,
                remoteURL: $0.remoteURL,
                fileName: $0.fileName,
                mimeType: $0.mimeType,
                referenceRole: $0.referenceRole,
                preserveMode: $0.preserveMode,
                displayName: $0.displayName,
                userNote: $0.userNote
            )
        }
        activeJobID = cached.value.activeJobID
        return cached.value
    }

    private func ensureUploaded(
        referenceIDs: Set<UUID>? = nil,
        accessToken: String
    ) async throws -> [String] {
        for index in references.indices {
            if let referenceIDs,
               !referenceIDs.contains(references[index].id) {
                continue
            }
            if references[index].remoteAssetID == nil {
                guard let data = references[index].data else {
                    throw APIError.missingData
                }
                let asset: AISAssetUploadResult = try await api.upload(
                    "/api/ais/assets",
                    fileData: data,
                    fileName: references[index].fileName,
                    mimeType: references[index].mimeType,
                    accessToken: accessToken,
                    fields: [
                        "assetType": "reference",
                        "referenceRole": references[index].referenceRole,
                        "preserveMode": references[index].preserveMode,
                        "displayName": references[index].displayName,
                        "userNote": references[index].userNote
                    ]
                )
                references[index].remoteAssetID = asset.id
            } else {
                let _: String = try await api.patch(
                    "/api/ais/assets/drawing-meta",
                    body: CreationReferenceMetaRequest(
                        assetId: references[index].remoteAssetID ?? "",
                        referenceRole: references[index].referenceRole,
                        preserveMode: references[index].preserveMode,
                        displayName: references[index].displayName,
                        userNote: references[index].userNote
                    ),
                    accessToken: accessToken
                )
            }
        }
        return references.compactMap(\.remoteAssetID)
    }

    private func ensureUploaded(
        referenceIDs: [UUID],
        accessToken: String
    ) async throws -> [String] {
        try await ensureUploaded(
            referenceIDs: Set(referenceIDs),
            accessToken: accessToken
        )
    }

    private func waitForTerminal(
        jobID: String,
        accessToken: String,
        update: ((AISTaskJob) -> Void)? = nil
    ) async throws -> AISTaskJob {
        for _ in 0..<120 {
            try Task.checkCancellation()
            let job: AISTaskJob = try await api.get(
                "/api/ais/jobs/\(jobID)",
                accessToken: accessToken
            )
            update?(job)
            if !job.isActive { return job }
            try await Task.sleep(for: .seconds(2))
        }
        throw APIError.rejected(
            message: String(localized: "creation.task.background")
        )
    }

    private static func outputString(
        _ json: String?,
        keys: [String]
    ) -> String? {
        guard let json, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else { return nil }
        for key in keys {
            if let value = object[key] as? String,
               let value = value.trimmingCharacters(
                    in: .whitespacesAndNewlines
               ).nilIfEmpty {
                return value
            }
        }
        return nil
    }

    private static func draftKey(_ userID: String) -> String {
        AISResponseCache.key(
            scope: "user:\(userID)",
            resource: "creation-draft-v2"
        )
    }
}

enum CreationReferenceUnderstandingState: Equatable {
    case understanding
    case completed
    case failed
}

private struct CreationReferenceCard: View {
    let reference: CreationReference
    let understandingState: CreationReferenceUnderstandingState?
    let onEdit: () -> Void
    let onUnderstand: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                referenceImage
                    .frame(width: 112, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.black.opacity(0.62), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
            }
            HStack(spacing: 8) {
                Button(action: onUnderstand) {
                    Label(
                        understandLabel,
                        systemImage: understandingState == .understanding
                            ? "sparkles"
                            : "wand.and.stars"
                    )
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(understandColor)
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("creation.reference.settings"))
            }
            Text(reference.displayName)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)
        }
    }

    private var understandLabel: LocalizedStringKey {
        switch understandingState {
        case .understanding:
            "creation.understand.running.short"
        case .completed:
            "creation.understand.completed"
        case .failed:
            "creation.understand.retry"
        case nil:
            reference.userNote.isEmpty
                ? "creation.understand"
                : "creation.understand.completed"
        }
    }

    private var understandColor: Color {
        switch understandingState {
        case .failed:
            .red
        case .completed:
            .green
        default:
            AISTheme.accent
        }
    }

    @ViewBuilder
    private var referenceImage: some View {
        if let image = reference.image {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let url = reference.remoteURL {
            AISCachedAsyncImage(
                url: url,
                preset: .thumbnail,
                module: .projectsAssets
            ) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    ProgressView()
                }
            }
        } else {
            Image(systemName: "photo")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
        }
    }
}

private struct CreationReferenceSettingsView: View {
    private enum Field {
        case displayName
        case userNote
    }

    let reference: CreationReference
    let isUnderstanding: Bool
    let understandingProgress: Int?
    let understandingStartedAt: Date?
    let durationEstimate: AISDurationEstimate?
    let onSave: (String, String, String, String) -> Void
    let onUnderstand: (String, String) async throws -> String
    let onUnderstandQuote: () async throws -> AISPointQuote
    let onRestoreUnderstanding: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var role: String
    @State private var preserveMode: String
    @State private var displayName: String
    @State private var userNote: String
    @State private var understandQuote: AISPointQuote?
    @State private var isLoadingQuote = false
    @State private var confirmsUnderstanding = false
    @State private var understandingError: String?
    @State private var confirmsBackgroundClose = false
    @State private var backgroundCloseSaves = false

    init(
        reference: CreationReference,
        isUnderstanding: Bool,
        understandingProgress: Int?,
        understandingStartedAt: Date?,
        durationEstimate: AISDurationEstimate?,
        onSave: @escaping (String, String, String, String) -> Void,
        onUnderstand: @escaping (String, String) async throws -> String,
        onUnderstandQuote: @escaping () async throws -> AISPointQuote,
        onRestoreUnderstanding: @escaping () async -> Void
    ) {
        self.reference = reference
        self.isUnderstanding = isUnderstanding
        self.understandingProgress = understandingProgress
        self.understandingStartedAt = understandingStartedAt
        self.durationEstimate = durationEstimate
        self.onSave = onSave
        self.onUnderstand = onUnderstand
        self.onUnderstandQuote = onUnderstandQuote
        self.onRestoreUnderstanding = onRestoreUnderstanding
        _role = State(initialValue: reference.referenceRole)
        _preserveMode = State(initialValue: reference.preserveMode)
        _displayName = State(initialValue: reference.displayName)
        _userNote = State(initialValue: reference.userNote)
    }

    var body: some View {
        Form {
            Section("creation.reference.role") {
                Picker("creation.reference.role", selection: $role) {
                    ForEach(Self.roles, id: \.0) {
                        Text(LocalizedStringKey($0.1)).tag($0.0)
                    }
                }
            }
            Section("creation.reference.preserve") {
                Picker("creation.reference.preserve", selection: $preserveMode) {
                    ForEach(Self.modes, id: \.0) {
                        Text(LocalizedStringKey($0.1)).tag($0.0)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("creation.reference.description") {
                TextField("creation.reference.name", text: $displayName)
                    .focused($focusedField, equals: .displayName)
                TextField(
                    "creation.reference.note",
                    text: $userNote,
                    axis: .vertical
                )
                .focused($focusedField, equals: .userNote)
                .lineLimit(3...7)
                Button {
                    focusedField = nil
                    requestUnderstandingQuote()
                } label: {
                    if isLoadingQuote {
                        HStack {
                            ProgressView()
                            Text("creation.understand.quoting")
                        }
                    } else {
                        Label(
                            isUnderstanding
                                ? "creation.understand.running"
                                : "creation.understand",
                            systemImage: "sparkles"
                        )
                    }
                }
                .disabled(isUnderstanding || isLoadingQuote)
                understandingStatus
                if let understandingError {
                    Text(understandingError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: reference.id) {
            await onRestoreUnderstanding()
        }
        .interactiveDismissDisabled(isUnderstanding)
        .navigationTitle("creation.reference.settings")
        .alert(
            "creation.understand.confirm.title",
            isPresented: $confirmsUnderstanding
        ) {
            Button("common.cancel", role: .cancel) {}
            Button("creation.understand.confirm.action") {
                executeUnderstanding()
            }
        } message: {
            Text(
                String.localizedStringWithFormat(
                    String(localized: "creation.understand.confirm.message"),
                    understandQuote?.points ?? 0
                )
            )
        }
        .alert(
            "creation.understand.background.title",
            isPresented: $confirmsBackgroundClose
        ) {
            Button("creation.understand.background.wait", role: .cancel) {}
            Button("creation.understand.background.close") {
                if backgroundCloseSaves {
                    saveAndDismiss()
                } else {
                    dismiss()
                }
            }
        } message: {
            Text("creation.understand.background.message")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("common.cancel") {
                    focusedField = nil
                    requestDismiss(save: false)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("common.save") {
                    focusedField = nil
                    requestDismiss(save: true)
                }
                .disabled(
                    displayName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("common.done") {
                    focusedField = nil
                }
            }
        }
    }

    @ViewBuilder
    private var understandingStatus: some View {
        if isUnderstanding {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = understandingStartedAt.map {
                    max(0, context.date.timeIntervalSince($0))
                }
                let expectedSeconds = durationEstimate.map {
                    max(1, $0.percentile80Seconds)
                }
                let isOverdue = elapsed.map { elapsed in
                    expectedSeconds.map { elapsed > Double($0) } ?? false
                } ?? false

                VStack(alignment: .leading, spacing: 8) {
                    if let understandingProgress {
                        ProgressView(
                            value: Double(understandingProgress),
                            total: 100
                        )
                        Text(
                            understandingProgress < 20
                                ? "creation.understand.progress.queued"
                                : "creation.understand.progress.running"
                        )
                        .font(.caption.weight(.semibold))
                    } else {
                        ProgressView()
                        Text("creation.understand.progress.submitting")
                            .font(.caption.weight(.semibold))
                    }

                    if isOverdue {
                        Label(
                            "creation.understand.progress.overdue.title",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        Text("creation.understand.progress.overdue.message")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let durationEstimate {
                        Text(
                            String.localizedStringWithFormat(
                                String(
                                    localized: durationEstimate.isFallback
                                        ? "creation.understand.progress.fallback"
                                        : "creation.understand.progress.estimate"
                                ),
                                max(
                                    1,
                                    durationEstimate.percentile80Seconds
                                )
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Text("creation.understand.progress.source")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func requestUnderstandingQuote() {
        guard !isLoadingQuote, !isUnderstanding else { return }
        isLoadingQuote = true
        understandingError = nil
        Task {
            defer { isLoadingQuote = false }
            do {
                understandQuote = try await onUnderstandQuote()
                confirmsUnderstanding = true
            } catch {
                understandingError = error.localizedDescription
            }
        }
    }

    private func requestDismiss(save: Bool) {
        if isUnderstanding {
            backgroundCloseSaves = save
            confirmsBackgroundClose = true
            return
        }
        if save {
            saveAndDismiss()
        } else {
            dismiss()
        }
    }

    private func saveAndDismiss() {
        onSave(
            role,
            preserveMode,
            displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            userNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func executeUnderstanding() {
        understandingError = nil
        Task {
            do {
                userNote = try await onUnderstand(role, userNote)
            } catch {
                understandingError = error.localizedDescription
            }
        }
    }

    private static let roles = [
        ("product_photo", "creation.role.product"),
        ("logo", "creation.role.logo"),
        ("cad", "creation.role.cad"),
        ("background", "creation.role.background"),
        ("scene", "creation.role.scene"),
        ("material", "creation.role.material"),
        ("packaging", "creation.role.packaging"),
        ("other", "creation.role.other")
    ]
    private static let modes = [
        ("strict", "creation.preserve.strict"),
        ("reference", "creation.preserve.reference"),
        ("style_only", "creation.preserve.style")
    ]
}

struct AISAssetLibraryPicker: View {
    let accessToken: String?
    let maximumSelectionCount: Int
    let onSelect: ([AISAssetLibraryItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [AISAssetLibraryItem] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("common.loading")
                } else if let errorMessage {
                    ContentUnavailableView(
                        "common.error",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "creation.library.empty",
                        systemImage: "photo.stack"
                    )
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 120), spacing: 12)
                            ],
                            spacing: 12
                        ) {
                            ForEach(items) { item in
                                Button {
                                    toggle(item.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        AISCachedAsyncImage(
                                            url: item.resolvedURL,
                                            preset: .thumbnail,
                                            module: .projectsAssets
                                        ) { phase in
                                            if case let .success(image) = phase {
                                                image.resizable().scaledToFill()
                                            } else {
                                                ProgressView()
                                            }
                                        }
                                        .frame(height: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        Text(item.resolvedName)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Image(
                                            systemName: selectedIDs.contains(item.id)
                                                ? "checkmark.circle.fill"
                                                : "circle"
                                        )
                                        .foregroundStyle(AISTheme.accent)
                                    }
                                    .padding(8)
                                    .background(
                                        selectedIDs.contains(item.id)
                                            ? AISTheme.accent.opacity(0.08)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("creation.source.library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        onSelect(items.filter { selectedIDs.contains($0.id) })
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .task {
                do {
                    let page: PageResponse<AISAssetLibraryItem> = try await APIClient().get(
                        "/api/ais/assets",
                        query: [
                            URLQueryItem(name: "page", value: "1"),
                            URLQueryItem(name: "size", value: "50"),
                            URLQueryItem(name: "assetType", value: "style_template_source")
                        ],
                        accessToken: accessToken
                    )
                    items = page.items
                } catch {
                    errorMessage = error.localizedDescription
                }
                isLoading = false
            }
        }
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else if selectedIDs.count < maximumSelectionCount {
            selectedIDs.insert(id)
        }
    }
}

struct AISGenerationModelPicker: View {
    let models: [AISGenerationModelOption]
    @Binding var selectedModelKey: String
    let allowsSelection: Bool

    @State private var presentsModels = false

    private var selectedModel: AISGenerationModelOption? {
        models.first { $0.displayModelKey == selectedModelKey }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("creation.model.title")
                .font(.subheadline.weight(.semibold))
            Button {
                if allowsSelection {
                    presentsModels = true
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.headline)
                        .foregroundStyle(AISTheme.accent)
                        .frame(width: 32, height: 32)
                        .background(
                            AISTheme.accent.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(
                                selectedModel?.localizedName
                                    ?? String(localized: "creation.model.select")
                            )
                            .font(.subheadline.weight(.semibold))
                            if selectedModel?.isRecommended == true {
                                Text("creation.model.recommended")
                                    .font(.caption2.bold())
                                    .foregroundStyle(AISTheme.accent)
                            }
                        }
                        if let description = selectedModel?.localizedDescription {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    if let selectedModel,
                       let multiplierLabel = AISPointMultiplierFormatter
                           .visibleLabel(selectedModel.modelMarkupRate) {
                        Text(multiplierLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Image(
                        systemName: allowsSelection
                            ? "chevron.up.chevron.down"
                            : "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .buttonStyle(.plain)
            .disabled(!allowsSelection)
            if !allowsSelection {
                Text("templates.creation.model.fixed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $presentsModels) {
            NavigationStack {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(models) { model in
                            modelButton(model)
                        }
                    }
                    .padding(16)
                }
                .navigationTitle("creation.model.choose")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.done") {
                            presentsModels = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func modelButton(
        _ model: AISGenerationModelOption
    ) -> some View {
        let isAvailable = AISGenerationModelSelection.canSelect(
            model,
            allowsSelection: allowsSelection
        )
        return Button {
            guard isAvailable else { return }
            selectedModelKey = model.displayModelKey
            presentsModels = false
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(
                    systemName: selectedModelKey == model.displayModelKey
                        ? "checkmark.circle.fill"
                        : isAvailable ? "circle" : "lock.circle"
                )
                .foregroundStyle(
                    selectedModelKey == model.displayModelKey
                        ? AISTheme.accent
                        : .secondary
                )
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(model.localizedName)
                            .font(.subheadline.weight(.semibold))
                        if model.isRecommended {
                            Text("creation.model.recommended")
                                .font(.caption2.bold())
                                .foregroundStyle(AISTheme.accent)
                        }
                        Spacer()
                        if let multiplierLabel = AISPointMultiplierFormatter
                            .visibleLabel(model.modelMarkupRate) {
                            Text(multiplierLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let description = model.localizedDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !isAvailable {
                        Text(
                            model.localizedUpgradePrompt
                                ?? String(localized: "creation.model.locked")
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selectedModelKey == model.displayModelKey
                    ? AISTheme.accent.opacity(0.1)
                    : Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 15)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.62)
    }
}

enum AISPointMultiplierFormatter {
    static func decimalText(_ multiplier: Decimal) -> String {
        NSDecimalNumber(decimal: multiplier).stringValue
    }

    static func label(_ multiplier: Decimal) -> String {
        String.localizedStringWithFormat(
            String(localized: "creation.model.points_multiplier"),
            decimalText(multiplier)
        )
    }

    static func visibleLabel(_ multiplier: Decimal) -> String? {
        multiplier == 1 ? nil : label(multiplier)
    }
}

enum AISGenerationModelSelection {
    static func canSelect(
        _ model: AISGenerationModelOption,
        allowsSelection: Bool
    ) -> Bool {
        allowsSelection && model.canUse && model.canSelect
    }
}

private struct AISPickerSummaryRow: View {
    let title: String
    let summary: String
    let selectedCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(
                            selectedCount > 0
                                ? AISTheme.accent
                                : Color.secondary
                        )
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selectedCount > 0 {
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "creation.attributes.selected"),
                            selectedCount
                        )
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AISTheme.accent)
                    .fixedSize()
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AISTheme.line.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
    }
}

struct AISChoiceChip: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    let isAvailable: Bool
    var badge: String? = nil
    var pricingBadge: String? = nil
    var fillsWidth = false
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(
                            dynamicTypeSize.isAccessibilitySize ? nil : 2
                        )
                    if !isAvailable {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                    }
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(
                            dynamicTypeSize.isAccessibilitySize ? nil : 2
                        )
                }
                if pricingBadge?.isEmpty == false || badge?.isEmpty == false {
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if let pricingBadge, !pricingBadge.isEmpty {
                            Text(pricingBadge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if let badge, !badge.isEmpty {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(
                maxWidth: fillsWidth ? .infinity : nil,
                minHeight: fillsWidth
                    ? (dynamicTypeSize.isAccessibilitySize ? 96 : 84)
                    : nil,
                alignment: .leading
            )
            .background(
                isSelected
                    ? AISTheme.accent.opacity(0.14)
                    : Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? AISTheme.accent : AISTheme.line.opacity(0.5)
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.55)
    }
}

struct AISFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(
            width: width,
            height: measuredHeight(width: width, subviews: subviews)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func measuredHeight(
        width: CGFloat,
        subviews: Subviews
    ) -> CGFloat {
        var x: CGFloat = 0
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return height + rowHeight
    }
}

private struct CreationJobStatusCard: View {
    let job: AISTaskJob
    let onViewResult: () -> Void
    let onCreateAnother: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)
            ProgressView(value: Double(job.progress), total: 100)
                .tint(AISTheme.accent)
            Text("\(job.progress)%")
                .font(.caption.monospacedDigit())
            if let error = job.errorMessage, !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if job.isSuccessful {
                Button("creation.view_result", action: onViewResult)
                    .buttonStyle(.borderedProminent)
                    .tint(AISTheme.accent)
            }
            if !job.isActive {
                Button("creation.create_another", action: onCreateAnother)
                    .buttonStyle(.bordered)
                    .tint(AISTheme.accent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .aisSurface(cornerRadius: 22)
    }

    private var title: LocalizedStringKey {
        if job.isSuccessful {
            return "creation.status.succeeded"
        }
        return job.status.lowercased() == "failed"
            ? "creation.status.failed"
            : "creation.status.processing"
    }

    private var icon: String {
        if job.isSuccessful {
            return "checkmark.circle.fill"
        }
        return job.status.lowercased() == "failed"
            ? "xmark.circle.fill"
            : "clock.arrow.circlepath"
    }

    private var color: Color {
        if job.isSuccessful {
            return .green
        }
        return job.status.lowercased() == "failed"
            ? .red
            : AISTheme.accent
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#Preview("CreationView") {
    NavigationStack {
        CreationView(selectedPreset: nil, initialTask: nil)
    }
    .environment(SessionStore())
    .environment(AISAppDataStore())
}
