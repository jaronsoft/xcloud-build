import Observation
import PhotosUI
import SwiftUI
import UIKit

private enum PixaCreationWarning {
    case validation(String)
    case unchanged
    case insufficientPoints(required: Int, available: Int)
    case balanceUnavailable
}

struct TemplateEditorView: View {
    let template: StyleTemplate
    private let initialTexts: [String: String]
    private let initialAspectRatio: String
    private let initialResolution: String

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(PixaAccountDataStore.self) private var accountData
    @Environment(PixaNavigationStore.self) private var navigation
    @Environment(PixaWorkActivityStore.self) private var workActivity
    @Environment(PixaCreationSubmissionStore.self) private var creationSubmissions
    @State private var outputStore = PixaOutputSpecStore()
    @AppStorage("pixarivo.output_specs_hint.last_shown_day")
    private var outputSpecsHintLastShownDay = ""
    @State private var references: [String: PixaTemplateSlotReference] = [:]
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var activeSlotKey = ""
    @State private var librarySlotKey = ""
    @State private var loadingPhotoSlotKeys: Set<String> = []
    @State private var presentsPhotoPicker = false
    @State private var presentsAssetLibrary = false
    @State private var texts: [String: String]
    @State private var selectedAspectRatio: String
    @State private var selectedResolution: String
    @State private var socialInfoSpec: PixaOutputSpec?
    @State private var isPreparing = false
    @State private var errorMessage: String?
    @State private var showsMoreOutputSpecs = false
    @State private var showsMembershipHint = false
    @State private var showsOutputSpecsHint = false
    @State private var outputSpecsHintPulse = false
    @State private var clientRequestID: String?
    @State private var creationWarning: PixaCreationWarning?
    @State private var scrollTargetID: String?
    @State private var highlightedTargetID: String?
    @FocusState private var focusedFieldKey: String?
    @State private var pointsCenterTab: PointsCenterView.Tab?
    @State private var previewTarget: TemplateEditorPreviewTarget?
    @AppStorage("pixarivo.promo_mark_enabled")
    private var promoMarkEnabled = false
    @AppStorage("pixarivo.recommend_to_gallery")
    private var recommendToGallery = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(template: StyleTemplate) {
        self.template = template
        let aspectRatio = template.aspectRatioText
        let resolution = template.defaultResolution ?? template.resolutions.first ?? "1536"
        let textValues = Dictionary(
            uniqueKeysWithValues: template.textFields
                .filter(\.enabled)
                .map { ($0.fieldKey, $0.defaultValue ?? "") }
        )
        initialAspectRatio = aspectRatio
        initialResolution = resolution
        initialTexts = textValues
        _selectedAspectRatio = State(initialValue: aspectRatio)
        _selectedResolution = State(initialValue: resolution)
        _texts = State(initialValue: textValues)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        previewSection
                        if !template.imageSlots.isEmpty { imageSection }
                        if !enabledTextFields.isEmpty { textSection }
                        outputSection
                        publishingSection
                        statusMessages
                    }
                    .padding(16)
                    .padding(.bottom, 78)
                }
                .onChange(of: scrollTargetID) { _, targetID in
                    guard let targetID else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
            .disabled(isCreating)
            .scrollDismissesKeyboard(.interactively)
            .background(PixaTheme.paper.ignoresSafeArea())
            .navigationTitle("editor.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { generationButton }
            .photosPicker(
                isPresented: $presentsPhotoPicker,
                selection: $selectedPhoto,
                matching: .images
            )
            .onChange(of: selectedPhoto) { _, item in
                guard let item, !activeSlotKey.isEmpty else { return }
                Task { await loadPhoto(item, slotKey: activeSlotKey) }
            }
            .onAppear(perform: showDailyOutputSpecsHintIfNeeded)
            .sheet(isPresented: $presentsAssetLibrary) {
                PixaAssetLibraryPicker(accessToken: session.accessToken) { item in
                    guard !librarySlotKey.isEmpty else { return }
                    references[librarySlotKey] = PixaTemplateSlotReference(
                        image: nil,
                        data: nil,
                        fileExtension: "jpg",
                        mimeType: "image/jpeg",
                        assetID: item.id,
                        remoteURL: item.imageURL
                    )
                    invalidateSubmission()
                }
            }
            .sheet(item: $pointsCenterTab) { tab in
                PixaPointsCenterSheet(initialTab: tab)
            }
            .sheet(item: $socialInfoSpec) { spec in
                PixaAspectRatioUseSheet(spec: spec)
            }
            .fullScreenCover(item: $previewTarget) { target in
                PixaArtworkPreview(url: target.url)
            }
            .alert(
                creationWarningTitle,
                isPresented: showsCreationWarning
            ) {
                if case .unchanged = creationWarning {
                    Button("common.cancel", role: .cancel) {}
                    Button("editor.unchanged.continue", action: beginCreation)
                } else if case .insufficientPoints = creationWarning {
                    Button("common.cancel", role: .cancel) {}
                    Button("editor.points.recharge") {
                        pointsCenterTab = .recharge
                    }
                    Button("editor.points.subscription") {
                        pointsCenterTab = .subscription
                    }
                } else {
                    Button("common.ok", role: .cancel) {}
                }
            } message: {
                Text(creationWarningMessage)
            }
            .task {
                async let outputLoad: Void = outputStore.load(token: session.accessToken)
                async let accountLoad: Void = accountData.load(session: session)
                async let editorOpen: Void = recordEditorOpen()
                await outputLoad
                await accountLoad
                await editorOpen
                normalizeSelections()
            }
            .onChange(of: promoMarkEnabled) { _, _ in
                invalidateSubmission()
            }
        }
    }

    private func recordEditorOpen() async {
        let request = PixaTemplateEditorOpenRequest(
            entry: "ios_editor",
            region: PixaMediaRegion.templateRegionValue
        )
        let _: Bool? = try? await APIClient().post(
            "/api/ais/style-templates/\(template.id)/editor-open",
            body: request,
            token: session.accessToken
        )
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("editor.preview", systemImage: "rectangle.inset.filled")
            Button {
                if let url = template.imageURL {
                    previewTarget = TemplateEditorPreviewTarget(url: url)
                }
            } label: {
                RemoteArtwork(
                    url: template.imageURL,
                    aspectRatio: template.displayAspectRatio,
                    preset: .detail,
                    contentMode: .fit
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PixaTheme.line)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(.black.opacity(0.55), in: Circle())
                        .padding(10)
                }
            }
            .buttonStyle(.plain)
            .disabled(template.imageURL == nil)
            .accessibilityLabel(Text("preview.open"))
        }
        .padding(14)
        .pixaSurface()
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("editor.replace_images", systemImage: "photo.stack")
            ForEach(template.imageSlots.sorted { $0.sort < $1.sort }) { slot in
                slotView(slot)
            }
        }
        .padding(14)
        .pixaSurface()
        .id("image-section")
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("editor.edit_text", systemImage: "textformat")
            ForEach(enabledTextFields) { field in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(field.name).font(.caption.weight(.semibold))
                        if field.isRequired { Text("*").foregroundStyle(.red) }
                        Spacer()
                        Text("\(texts[field.fieldKey, default: ""].count)/\(field.maxLength)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    TextField(
                        field.placeholder.isEmpty ? field.name : field.placeholder,
                        text: binding(field),
                        axis: .vertical
                    )
                    .focused($focusedFieldKey, equals: field.fieldKey)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(
                        Color(uiColor: .tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .id("text-\(field.fieldKey)")
                .padding(8)
                .background(
                    highlightedTargetID == "text-\(field.fieldKey)"
                        ? PixaTheme.accent.opacity(0.14)
                        : .clear,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
        }
        .padding(14)
        .pixaSurface()
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionTitle("editor.output", systemImage: "slider.horizontal.3")
                if outputStore.didLoad && hasMembershipLockedSpecs {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsMembershipHint.toggle()
                        }
                    } label: {
                        Image(systemName: showsMembershipHint ? "info.circle.fill" : "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(PixaTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("editor.output.membership.hint.title")
                    .accessibilityHint("editor.output.membership.hint.accessibility")
                }
                Spacer()
                if outputStore.isLoading { ProgressView().controlSize(.small) }
            }
            if showsMoreOutputSpecs {
                VStack(alignment: .leading, spacing: 14) {
                    specPicker(
                        title: AppLanguage.localized("editor.aspect_ratio"),
                        specs: aspectSpecs,
                        selection: $selectedAspectRatio,
                        groupsByAspect: true
                    )
                    specPicker(
                        title: AppLanguage.localized("editor.resolution"),
                        specs: resolutionSpecs,
                        selection: $selectedResolution
                    )
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    specPicker(
                        title: AppLanguage.localized("editor.aspect_ratio"),
                        specs: visibleSpecs(aspectSpecs, selection: selectedAspectRatio),
                        selection: $selectedAspectRatio,
                        groupsByAspect: true
                    )
                    specPicker(
                        title: AppLanguage.localized("editor.resolution"),
                        specs: visibleSpecs(resolutionSpecs, selection: selectedResolution),
                        selection: $selectedResolution
                    )
                }
            }
            if showsMembershipHint && outputStore.didLoad && hasMembershipLockedSpecs {
                Label("editor.output.membership.hint", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        PixaTheme.accent.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
            }
            if showsOutputSpecsHint && !showsMoreOutputSpecs {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsMoreOutputSpecs = true
                        showsOutputSpecsHint = false
                    }
                } label: {
                    Label("editor.output.try_another_size", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PixaTheme.accent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            PixaTheme.accent.opacity(outputSpecsHintPulse ? 0.15 : 0.08),
                            in: Capsule()
                        )
                        .scaleEffect(outputSpecsHintPulse ? 1.02 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppLanguage.localized("editor.output.try_another_size.accessibility"))
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsMoreOutputSpecs.toggle()
                    showsOutputSpecsHint = false
                }
            } label: {
                HStack {
                    Label(
                        showsMoreOutputSpecs ? "editor.output.collapse" : "editor.output.more",
                        systemImage: showsMoreOutputSpecs ? "chevron.up" : "chevron.down"
                    )
                    Spacer()
                    if let membership = outputStore.effectiveMembershipLabel {
                        Text(
                            String.localizedStringWithFormat(
                                AppLanguage.localized("editor.output.membership"),
                                membership
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PixaTheme.accent)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
            if let configurationError = outputStore.errorMessage {
                Label(configurationError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let price = localPrice {
                HStack {
                    Label("editor.pricing.estimate", systemImage: "sparkles")
                    Spacer()
                    Text(
                        String.localizedStringWithFormat(
                            AppLanguage.localized("editor.pricing.points"),
                            price.points
                        )
                    )
                    .fontWeight(.semibold)
                    .foregroundStyle(PixaTheme.accent)
                }
                .font(.footnote)
            } else if accountData.pricingRules.isLoading {
                Label("editor.pricing.loading", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .pixaSurface()
    }

    private var publishingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("editor.publishing", systemImage: "rectangle.and.pencil.and.ellipsis")
            Toggle(isOn: $promoMarkEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("editor.promo.title")
                        .font(.subheadline.weight(.semibold))
                    Text(promoMarkHelper)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(PixaTheme.accent)
            Divider()
            Toggle(isOn: $recommendToGallery) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("editor.gallery.title")
                        .font(.subheadline.weight(.semibold))
                    Text("editor.gallery.helper")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(PixaTheme.accent)
        }
        .padding(14)
        .pixaSurface()
    }

    private func showDailyOutputSpecsHintIfNeeded() {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let today = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        guard outputSpecsHintLastShownDay != today else { return }
        outputSpecsHintLastShownDay = today
        showsOutputSpecsHint = true
        guard !reduceMotion else { return }
        outputSpecsHintPulse = false
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
            outputSpecsHintPulse = true
        }
    }

    private var promoMarkHelper: String {
        if promoMarkEnabled, let price = localPrice {
            if price.promoMarkApplied, price.savedPoints > 0 {
                return String.localizedStringWithFormat(
                    AppLanguage.localized("editor.promo.saved"),
                    price.savedPoints
                )
            }
            return AppLanguage.localized("editor.promo.suppressed")
        }
        return AppLanguage.localized("editor.promo.helper")
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var generationButton: some View {
        VStack(spacing: 6) {
            if let shortage = pointsShortage {
                Label(
                    String.localizedStringWithFormat(
                        AppLanguage.localized("editor.points.shortage"),
                        shortage
                    ),
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                prepareCreation()
            } label: {
                HStack(spacing: 10) {
                    if isCreating { ProgressView().tint(.white) }
                    if isPreparing {
                        Text("editor.preparing")
                    } else if let price = localPrice {
                        VStack(spacing: 2) {
                            Text(
                                String.localizedStringWithFormat(
                                    AppLanguage.localized("editor.compose.points"),
                                    price.points
                                )
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            if price.effectiveDiscountPercent > 0 {
                                HStack(spacing: 7) {
                                    Text(
                                        String.localizedStringWithFormat(
                                            AppLanguage.localized("editor.compose.original_points"),
                                            price.originalPoints
                                        )
                                    )
                                    .strikethrough()
                                    Text(
                                        String.localizedStringWithFormat(
                                            AppLanguage.localized("editor.compose.discount"),
                                            NSDecimalNumber(
                                                decimal: price.effectiveDiscountPercent
                                            ).doubleValue
                                        )
                                    )
                                }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.84))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            }
                        }
                    } else {
                        Text("editor.compose")
                    }
                }
                .pixaPrimaryButton(isEnabled: !isCreating)
            }
            .buttonStyle(.plain)
            .disabled(isCreating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func sectionTitle(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(PixaTheme.ink)
    }

    private func slotView(_ slot: TemplateImageSlot) -> some View {
        let reference = references[slot.slotKey]
        let isLoadingPhoto = loadingPhotoSlotKeys.contains(slot.slotKey)
        let imageActionLabel = AppLanguage.localized(
            reference == nil ? "editor.image.empty" : "editor.image.tap_to_replace"
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(slot.name).font(.subheadline.weight(.semibold))
                if slot.required {
                    Text("editor.required")
                        .font(.caption2.bold())
                        .foregroundStyle(PixaTheme.accent)
                }
                Spacer()
                if reference != nil {
                    Button(role: .destructive) {
                        references.removeValue(forKey: slot.slotKey)
                        invalidateSubmission()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(Text("editor.remove"))
                }
            }
            if let description = AppLanguage.value(zh: slot.descriptionZh, en: slot.descriptionEn).nilIfEmpty {
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                presentPhotoPicker(for: slot.slotKey)
            } label: {
                Group {
                    if let reference {
                        referencePreview(reference)
                            .overlay(alignment: .bottom) {
                                Label("editor.image.tap_to_replace", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(.black.opacity(0.62), in: Capsule())
                                    .padding(10)
                            }
                    } else {
                        emptyImagePicker
                    }
                }
                .overlay {
                    if isLoadingPhoto {
                        ZStack {
                            Color.black.opacity(0.32)
                            ProgressView("editor.image.loading")
                                .font(.caption.weight(.semibold))
                                .tint(.white)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.black.opacity(0.56), in: Capsule())
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoadingPhoto)
            .accessibilityLabel(Text(imageActionLabel))
            .accessibilityHint(Text("editor.image.photos_hint"))
            HStack(spacing: 10) {
                Button {
                    presentPhotoPicker(for: slot.slotKey)
                } label: {
                    Label(reference == nil ? "editor.photos" : "editor.replace", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 42)
                        .foregroundStyle(.white)
                        .background(PixaTheme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLoadingPhoto)
                Button {
                    librarySlotKey = slot.slotKey
                    presentsAssetLibrary = true
                } label: {
                    Label("editor.library", systemImage: "photo.stack")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 42)
                        .foregroundStyle(PixaTheme.ink)
                        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(PixaTheme.line)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isLoadingPhoto)
            }
            .id("image-\(slot.slotKey)")
            .padding(8)
            .background(
                highlightedTargetID == "image-\(slot.slotKey)"
                    ? PixaTheme.accent.opacity(0.14)
                    : .clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.68), PixaTheme.accent.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(reference == nil ? PixaTheme.accent.opacity(0.18) : PixaTheme.line)
        }
    }

    private var emptyImagePicker: some View {
        ZStack {
            LinearGradient(
                colors: [PixaTheme.accent.opacity(0.09), Color.white.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(PixaTheme.accent)
                    .frame(width: 58, height: 58)
                    .background(.white.opacity(0.86), in: Circle())
                    .shadow(color: PixaTheme.accent.opacity(0.12), radius: 8, y: 4)
                Text("editor.image.empty")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PixaTheme.ink)
                Text("editor.image.photos_hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 156)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    PixaTheme.accent.opacity(0.36),
                    style: StrokeStyle(lineWidth: 1.2, dash: [7, 5])
                )
        }
    }

    @ViewBuilder
    private func referencePreview(_ reference: PixaTemplateSlotReference) -> some View {
        ZStack {
            Color.white.opacity(0.7)
            if let image = reference.image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                RemoteArtwork(
                    url: reference.remoteURL,
                    aspectRatio: 16 / 9,
                    preset: .thumbnail,
                    maximumPixelWidth: 600,
                    contentMode: .fit
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PixaTheme.line)
        }
    }

    private func presentPhotoPicker(for slotKey: String) {
        guard !loadingPhotoSlotKeys.contains(slotKey) else { return }
        activeSlotKey = slotKey
        selectedPhoto = nil
        presentsPhotoPicker = true
    }

    private func specPicker(
        title: String,
        specs: [PixaOutputSpec],
        selection: Binding<String>,
        groupsByAspect: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold))
            if groupsByAspect && showsMoreOutputSpecs {
                ForEach(orderedAspectGroups, id: \.self) { group in
                    let groupSpecs = specs.filter { group.contains($0) }
                    if !groupSpecs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: group.systemImage)
                                    .frame(width: 15, height: 15)
                                Text(outputStore.orientationSpec(for: group)?.localizedName ?? group.title)
                            }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: outputSpecGridColumns, alignment: .leading, spacing: 8) {
                                ForEach(groupSpecs) { spec in
                                    outputSpecButton(spec, selection: selection)
                                }
                            }
                        }
                    }
                }
            } else {
                LazyVGrid(columns: outputSpecGridColumns, alignment: .leading, spacing: 8) {
                    ForEach(specs) { spec in
                        outputSpecButton(spec, selection: selection)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func outputSpecButton(
        _ spec: PixaOutputSpec,
        selection: Binding<String>
    ) -> some View {
        let isSelected = selection.wrappedValue == spec.value
        let socialPlatforms = PixaSocialPlatform.platforms(for: spec)
        let socialIcons = PixaSocialPlatform.uniquePlatforms(for: spec)
        let isSelectable = spec.isSelectable(
            effectiveMembershipLevel: outputStore.effectiveMembershipLevel
        )
        return HStack(alignment: .top, spacing: 4) {
            Button {
                guard isSelectable else { return }
                selection.wrappedValue = spec.value
                invalidateSubmission()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(spec.specType.lowercased() == "aspect_ratio" ? spec.value : spec.localizedName)
                            .font(.subheadline)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                        if socialPlatforms.isEmpty, let descriptor = aspectRatioDescriptor(for: spec) {
                            Text(descriptor)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .layoutPriority(-1)
                        }
                        if !isSelectable {
                            Image(systemName: "lock.fill").font(.caption2)
                        }
                    }
                    if !socialIcons.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(socialIcons, id: \.self) { platform in
                                Image(platform.assetName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 12, height: 12)
                                    .accessibilityLabel(platform.displayName)
                            }
                        }
                    }
                    if spec.specType.lowercased() != "aspect_ratio",
                       spec.localizedName.range(of: spec.value, options: .caseInsensitive) == nil {
                        Text(spec.value)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let membership = spec.membershipLabel {
                        Text(
                            String.localizedStringWithFormat(
                                AppLanguage.localized("editor.output.requires_membership"),
                                membership
                            )
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelectable ? PixaTheme.accent : .secondary)
                        .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable)

            if !socialPlatforms.isEmpty {
                Button {
                    socialInfoSpec = spec
                } label: {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    String.localizedStringWithFormat(
                        AppLanguage.localized("editor.output.social_uses.accessibility"),
                        spec.value
                    )
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(
            isSelected ? PixaTheme.accent.opacity(0.13) : Color(uiColor: .tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isSelected ? PixaTheme.accent : PixaTheme.line)
        }
        .opacity(isSelectable ? 1 : 0.62)
    }

    private func aspectRatioDescriptor(for spec: PixaOutputSpec) -> String? {
        guard spec.specType.lowercased() == "aspect_ratio",
              let range = spec.localizedName.range(of: spec.value, options: .caseInsensitive) else {
            return nil
        }
        let remainder = spec.localizedName.replacingCharacters(in: range, with: "")
        let trimmed = remainder.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return trimmed.isEmpty ? nil : trimmed
    }

    private var orderedAspectGroups: [PixaAspectRatioGroup] {
        let configuredGroups = outputStore.orientationSpecs
            .compactMap(PixaAspectRatioGroup.init(spec:))
            .reduce(into: [PixaAspectRatioGroup]()) { groups, group in
                if !groups.contains(group) { groups.append(group) }
            }
        let availableGroups = configuredGroups.isEmpty ? PixaAspectRatioGroup.allCases : configuredGroups
        return availableGroups.sorted { left, right in
            let leftSort = outputStore.orientationSpec(for: left)?.sort ?? Int.max
            let rightSort = outputStore.orientationSpec(for: right)?.sort ?? Int.max
            return leftSort == rightSort
                ? PixaAspectRatioGroup.allCases.firstIndex(of: left)! < PixaAspectRatioGroup.allCases.firstIndex(of: right)!
                : leftSort < rightSort
        }
    }

    private var outputSpecGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 130, maximum: 210), spacing: 8, alignment: .leading)]
    }

    private var enabledTextFields: [TemplateTextField] {
        template.textFields.filter(\.enabled).sorted { $0.sort < $1.sort }
    }

    private var isCreating: Bool {
        isPreparing
    }

    private var hasCreativeChanges: Bool {
        !references.isEmpty
            || normalizedTextValues(texts) != normalizedTextValues(initialTexts)
            || selectedAspectRatio.caseInsensitiveCompare(initialAspectRatio) != .orderedSame
            || selectedResolution.caseInsensitiveCompare(initialResolution) != .orderedSame
    }

    private var showsCreationWarning: Binding<Bool> {
        Binding(
            get: { creationWarning != nil },
            set: { if !$0 { creationWarning = nil } }
        )
    }

    private var creationWarningTitle: LocalizedStringKey {
        switch creationWarning {
        case .unchanged:
            "editor.unchanged.title"
        case .insufficientPoints:
            "editor.points.insufficient.title"
        case .balanceUnavailable:
            "editor.points.unavailable.title"
        default:
            "editor.validation.title"
        }
    }

    private var creationWarningMessage: String {
        switch creationWarning {
        case let .validation(message):
            message
        case .unchanged:
            AppLanguage.localized("editor.unchanged.message")
        case let .insufficientPoints(required, available):
            String.localizedStringWithFormat(
                AppLanguage.localized("editor.points.insufficient.message"),
                required,
                available
            )
        case .balanceUnavailable:
            AppLanguage.localized("editor.points.unavailable.message")
        case nil:
            ""
        }
    }

    private var aspectSpecs: [PixaOutputSpec] {
        outputStore.aspectSpecs(templateValues: template.aspectRatios, defaultValue: template.defaultAspectRatio)
    }

    private var resolutionSpecs: [PixaOutputSpec] {
        outputStore.resolutionSpecs(templateValues: template.resolutions, defaultValue: template.defaultResolution)
    }

    private var hasMembershipLockedSpecs: Bool {
        (aspectSpecs + resolutionSpecs).contains { spec in
            guard spec.isAvailable,
                  spec.requiredMembershipCode?.nilIfEmpty != nil else {
                return false
            }
            return !spec.isSelectable(
                effectiveMembershipLevel: outputStore.effectiveMembershipLevel
            )
        }
    }

    private var localPrice: PixaLocalPrice? {
        guard let rules = accountData.pricingRules.rules else { return nil }
        let resolutionMultiplier = resolutionSpecs.first {
            $0.value.caseInsensitiveCompare(selectedResolution) == .orderedSame
        }?.multiplier ?? 1
        return PixaLocalPricingCalculator.template(
            snapshot: rules,
            basePoints: template.basePointCost,
            defaultResolution: template.defaultResolution,
            resolution: selectedResolution,
            selectedModelKey: template.defaultDisplayModelKey ?? "",
            fallbackResolutionMultiplier: resolutionMultiplier,
            promoMarkEnabled: promoMarkEnabled
        )
    }

    private var pointsShortage: Int? {
        guard let price = localPrice,
              let available = accountData.balance?.availablePoints,
              available < price.points else {
            return nil
        }
        return price.points - available
    }

    private func visibleSpecs(
        _ specs: [PixaOutputSpec],
        selection: String
    ) -> [PixaOutputSpec] {
        guard !showsMoreOutputSpecs else { return specs }
        return specs.first(where: { $0.value == selection }).map { [$0] }
            ?? specs.first.map { [$0] }
            ?? []
    }

    private func normalizeSelections() {
        if !aspectSpecs.contains(where: {
            $0.value == selectedAspectRatio
                && $0.isSelectable(effectiveMembershipLevel: outputStore.effectiveMembershipLevel)
        }) {
            selectedAspectRatio = aspectSpecs.first(where: {
                $0.isSelectable(effectiveMembershipLevel: outputStore.effectiveMembershipLevel)
            })?.value ?? template.aspectRatioText
        }
        if !resolutionSpecs.contains(where: {
            $0.value == selectedResolution
                && $0.isSelectable(effectiveMembershipLevel: outputStore.effectiveMembershipLevel)
        }) {
            selectedResolution = resolutionSpecs.first(where: {
                $0.isSelectable(effectiveMembershipLevel: outputStore.effectiveMembershipLevel)
            })?.value
                ?? template.defaultResolution
                ?? template.resolutions.first
                ?? "1536"
        }
    }

    private func binding(_ field: TemplateTextField) -> Binding<String> {
        Binding(
            get: { texts[field.fieldKey] ?? field.defaultValue ?? "" },
            set: {
                texts[field.fieldKey] = String($0.prefix(field.maxLength))
                invalidateSubmission()
            }
        )
    }

    private func loadPhoto(_ item: PhotosPickerItem, slotKey: String) async {
        loadingPhotoSlotKeys.insert(slotKey)
        defer {
            loadingPhotoSlotKeys.remove(slotKey)
            selectedPhoto = nil
        }
        guard let originalData = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: originalData),
              let payload = image.pixaTemplateUploadPayload(
                preservesPNG: originalData.starts(with: [0x89, 0x50, 0x4E, 0x47])
              ) else {
            errorMessage = AppLanguage.localized("editor.image.invalid")
            return
        }
        references[slotKey] = PixaTemplateSlotReference(
            image: payload.image,
            data: payload.data,
            fileExtension: payload.fileExtension,
            mimeType: payload.mimeType,
            assetID: nil,
            remoteURL: nil
        )
        errorMessage = nil
        invalidateSubmission()
    }

    private func validationMessage() -> String? {
        if let missing = template.imageSlots.first(where: { $0.required && references[$0.slotKey] == nil }) {
            return String.localizedStringWithFormat(AppLanguage.localized("editor.missing_image"), missing.name)
        }
        for field in enabledTextFields {
            let value = texts[field.fieldKey, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if field.isRequired && value.isEmpty {
                return String.localizedStringWithFormat(AppLanguage.localized("editor.missing_text"), field.name)
            }
        }
        guard !selectedAspectRatio.isEmpty, !selectedResolution.isEmpty else {
            return AppLanguage.localized("editor.missing_output")
        }
        return nil
    }

    private func normalizedTextValues(
        _ values: [String: String]
    ) -> [String: String] {
        values.mapValues {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func prepareCreation() {
        guard !isCreating else { return }
        if let validation = validationMessage() {
            focusFirstInvalidField()
            errorMessage = validation
            creationWarning = .validation(validation)
            return
        }
        if !hasCreativeChanges {
            errorMessage = nil
            creationWarning = .unchanged
            return
        }
        beginCreation()
    }

    private func focusFirstInvalidField() {
        if let missing = template.imageSlots.first(where: { $0.required && references[$0.slotKey] == nil }) {
            let targetID = "image-\(missing.slotKey)"
            highlightedTargetID = targetID
            scrollTargetID = targetID
        } else if let field = enabledTextFields.first(where: { field in
            field.isRequired
                && texts[field.fieldKey, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            let targetID = "text-\(field.fieldKey)"
            highlightedTargetID = targetID
            focusedFieldKey = field.fieldKey
            scrollTargetID = targetID
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            highlightedTargetID = nil
        }
    }

    private func beginCreation() {
        guard !isCreating else { return }
        creationWarning = nil
        isPreparing = true
        Task { await createTask() }
    }

    @MainActor
    private func createTask() async {
        defer { isPreparing = false }
        if let status = await PixaMaintenanceService.checkGeneration() {
            NotificationCenter.default.post(name: .pixaMaintenanceBlocked, object: status)
            return
        }
        if let validation = validationMessage() {
            errorMessage = validation
            return
        }
        guard let token = await session.validAccessToken(),
              let userID = session.user?.id else {
            errorMessage = AppLanguage.localized("auth.session_invalid")
            return
        }
        errorMessage = nil
        await accountData.pricingRules.load(
            userID: userID,
            accessToken: token
        )
        guard let price = localPrice else {
            errorMessage = accountData.pricingRules.errorMessage
                ?? AppLanguage.localized("editor.pricing.unavailable")
            return
        }
        let balanceResult = await accountData.refreshBalance(
            userID: userID,
            accessToken: token,
            force: true
        )
        switch balanceResult {
        case let .success(balance):
            guard balance.availablePoints >= price.points else {
                creationWarning = .insufficientPoints(
                    required: price.points,
                    available: balance.availablePoints
                )
                return
            }
        case .unavailable:
            creationWarning = .balanceUnavailable
            return
        }
        if clientRequestID == nil {
            clientRequestID = UUID().uuidString.lowercased()
        }
        guard let payload = makeQueuedComposition(localCalculatedPoints: price.points) else {
            errorMessage = AppLanguage.localized("submission.prepare_failed")
            return
        }
        creationSubmissions.enqueue(
            payload,
            session: session,
            workActivity: workActivity,
            navigation: navigation
        )
        dismiss()
        navigation.showWorks()
    }

    private func makeQueuedComposition(
        localCalculatedPoints: Int
    ) -> PixaQueuedComposition? {
        guard let clientRequestID else { return nil }
        let slots = template.imageSlots
            .sorted { $0.sort < $1.sort }
            .enumerated()
            .compactMap { index, slot -> PixaQueuedTemplateSlot? in
                guard let reference = references[slot.slotKey] else { return nil }
                return PixaQueuedTemplateSlot(
                    slotKey: slot.slotKey,
                    slotIndex: index + 1,
                    name: slot.name,
                    fileExtension: reference.fileExtension,
                    mimeType: reference.mimeType,
                    data: reference.data,
                    assetID: reference.assetID
                )
            }
        return PixaQueuedComposition(
            clientRequestID: clientRequestID,
            templateID: template.id,
            templateKey: template.templateKey,
            templateName: template.name,
            slots: slots,
            textValues: texts,
            language: AppLanguage.apiValue,
            aspectRatio: selectedAspectRatio,
            resolution: selectedResolution,
            recommendToGallery: recommendToGallery,
            promoMarkEnabled: promoMarkEnabled,
            selectedDisplayModelKey: template.defaultDisplayModelKey,
            pricingRulesVersion: accountData.pricingRules.rules?.version,
            localCalculatedPoints: localCalculatedPoints,
            previewData: slots.first?.data
        )
    }

    private func invalidateSubmission() {
        clientRequestID = nil
    }
}

private struct TemplateEditorPreviewTarget: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PixaTemplateEditorOpenRequest: Encodable {
    let entry: String
    let region: String

    private enum CodingKeys: String, CodingKey {
        case entry = "Entry"
        case region = "Region"
    }
}

private struct PixaPointsCenterSheet: View {
    let initialTab: PointsCenterView.Tab

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PointsCenterView(initialTab: initialTab)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.close") { dismiss() }
                    }
                }
        }
    }
}

struct CompositionRequest: Encodable {
    let clientRequestId: String?
    let sourceAssetId: String?
    let referenceAssetIds: [String]
    let textValues: [String: String]
    let entry: String
    let language: String
    let aspectRatio: String
    let resolution: String
    let additionalRequirement: String
    let recommendToGallery: Bool
    let promoMarkEnabled: Bool
    let selectedDisplayModelKey: String?
    let clientSnapshot: CompositionSnapshot
    let pricingRulesVersion: String?
    let localCalculatedPoints: Int?
}

struct CompositionSnapshot: Encodable {
    let templateKey: String
    let templateName: String
    let imageSlots: [CompositionSlotSnapshot]
    let textValues: [String: String]
    let selectedAspectRatio: String
    let selectedResolution: String
    let recommendToGallery: Bool
    let promoMarkEnabled: Bool
}

struct CompositionSlotSnapshot: Encodable {
    let slotKey: String
    let slotIndex: Int
    let name: String
    let assetId: String
}

private struct PixaTemplateSlotReference {
    let image: UIImage?
    let data: Data?
    let fileExtension: String
    let mimeType: String
    var assetID: String?
    let remoteURL: URL?
}

private enum PixaAspectRatioGroup: CaseIterable {
    case portrait
    case square
    case landscape
    case other

    init?(spec: PixaOutputSpec) {
        guard spec.specType.lowercased() == "orientation" else { return nil }
        switch spec.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "portrait": self = .portrait
        case "square": self = .square
        case "landscape": self = .landscape
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .portrait: AppLanguage.localized("editor.aspect_ratio.group.portrait")
        case .square: AppLanguage.localized("editor.aspect_ratio.group.square")
        case .landscape: AppLanguage.localized("editor.aspect_ratio.group.landscape")
        case .other: AppLanguage.localized("editor.aspect_ratio.group.other")
        }
    }

    var systemImage: String {
        switch self {
        case .portrait: "rectangle.portrait"
        case .square: "square"
        case .landscape: "rectangle"
        case .other: "aspectratio"
        }
    }

    func contains(_ spec: PixaOutputSpec) -> Bool {
        guard spec.specType.lowercased() == "aspect_ratio" else { return false }
        let numbers = spec.value
            .split(whereSeparator: { !$0.isNumber && $0 != "." })
            .compactMap { Double($0) }
        guard numbers.count >= 2, numbers[1] > 0 else { return self == .other }
        let ratio = numbers[0] / numbers[1]
        if abs(ratio - 1) < 0.03 { return self == .square }
        if ratio < 1 { return self == .portrait }
        return self == .landscape
    }
}

private enum PixaSocialPlatform: String, CaseIterable {
    case instagram
    case facebook
    case linkedin
    case pinterest
    case rednote
    case tiktok
    case wechatMoments
    case wechatOfficialAccount
    case wechatChannels
    case youtube
    case bilibili

    var assetName: String {
        switch self {
        case .wechatMoments, .wechatOfficialAccount, .wechatChannels: "SocialWechat"
        default: "Social\(rawValue.capitalized)"
        }
    }

    var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .facebook: "Facebook"
        case .linkedin: "LinkedIn"
        case .pinterest: "Pinterest"
        case .rednote: AppLanguage.isChinese ? "小红书" : "RED"
        case .tiktok: "TikTok"
        case .wechatMoments: AppLanguage.isChinese ? "微信朋友圈" : "WeChat Moments"
        case .wechatOfficialAccount: AppLanguage.isChinese ? "微信公众号" : "WeChat Official Accounts"
        case .wechatChannels: AppLanguage.isChinese ? "微信视频号" : "WeChat Channels"
        case .youtube: "YouTube"
        case .bilibili: AppLanguage.isChinese ? "哔哩哔哩（B站）" : "Bilibili"
        }
    }

    static func platforms(for spec: PixaOutputSpec) -> [PixaSocialPlatform] {
        guard spec.specType.lowercased() == "aspect_ratio" else { return [] }
        let components = spec.value
            .split(whereSeparator: { !$0.isNumber && $0 != "." })
            .compactMap { Double($0) }
        guard components.count >= 2, components[1] > 0 else { return [] }
        let ratio = components[0] / components[1]
        if abs(ratio - 1) < 0.01 {
            return [.instagram, .facebook, .linkedin, .wechatMoments, .wechatOfficialAccount]
        }
        if abs(ratio - 0.8) < 0.01 { return [.instagram, .facebook, .rednote] }
        if abs(ratio - 0.75) < 0.01 { return [.instagram, .rednote] }
        if abs(ratio - (2.0 / 3.0)) < 0.01 { return [.pinterest, .rednote] }
        if abs(ratio - 1.3333) < 0.01 { return [.bilibili, .wechatOfficialAccount] }
        if abs(ratio - (9.0 / 16.0)) < 0.01 {
            return [.instagram, .facebook, .tiktok, .wechatChannels, .youtube, .bilibili]
        }
        if abs(ratio - (16.0 / 9.0)) < 0.01 {
            return [.facebook, .linkedin, .wechatChannels, .youtube, .bilibili]
        }
        return []
    }

    static func uniquePlatforms(for spec: PixaOutputSpec) -> [PixaSocialPlatform] {
        platforms(for: spec).reduce(into: [PixaSocialPlatform]()) { result, platform in
            if !result.contains(where: { $0.assetName == platform.assetName }) {
                result.append(platform)
            }
        }
    }
}

private struct PixaAspectRatioUseSheet: View {
    let spec: PixaOutputSpec

    @Environment(\.dismiss) private var dismiss

    private var platforms: [PixaSocialPlatform] {
        PixaSocialPlatform.platforms(for: spec)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(platforms, id: \.self) { platform in
                        HStack(spacing: 12) {
                            Image(platform.assetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                            Text(platform.displayName)
                        }
                    }
                } header: {
                    Text("editor.output.social_uses.title")
                } footer: {
                    Text("editor.output.social_uses.note")
                }
            }
            .navigationTitle(spec.value)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

@MainActor
@Observable
private final class PixaOutputSpecStore {
    private(set) var specs: [PixaOutputSpec] = []
    private(set) var effectiveMembershipLevel: String?
    private(set) var isLoading = false
    private(set) var didLoad = false
    private(set) var errorMessage: String?

    func load(token: String?) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let settings: PixaPromptAttributeSettings = try await APIClient().get(
                "/api/ais/prompt-attributes",
                query: [URLQueryItem(name: "mediaType", value: "image")],
                token: token
            )
            specs = settings.modelOutputSpecs
                .filter { $0.mediaType.lowercased() == "image" }
                .sorted { $0.sort < $1.sort }
            effectiveMembershipLevel = settings.effectiveMembershipLevel
            didLoad = true
        } catch {
            errorMessage = AppLanguage.localized("editor.output.fallback")
        }
    }

    var effectiveMembershipLabel: String? {
        guard let level = effectiveMembershipLevel?.nilIfEmpty else { return nil }
        return switch level.lowercased() {
        case "normal": AppLanguage.isChinese ? "普通" : "Standard"
        case "vip": "VIP"
        case "plus": "Plus"
        case "pro": "Pro"
        case "student": AppLanguage.isChinese ? "学生" : "Student"
        case "max": "Max"
        case "enterprise": AppLanguage.isChinese ? "企业" : "Enterprise"
        default: level
        }
    }

    var orientationSpecs: [PixaOutputSpec] {
        specs.filter { $0.specType.lowercased() == "orientation" }
    }

    func orientationSpec(for group: PixaAspectRatioGroup) -> PixaOutputSpec? {
        orientationSpecs.first { PixaAspectRatioGroup(spec: $0) == group }
    }

    func aspectSpecs(templateValues: [String], defaultValue: String?) -> [PixaOutputSpec] {
        let configured = specs.filter { $0.specType.lowercased() == "aspect_ratio" }
        return merged(templateValues: templateValues, defaultValue: defaultValue, configured: configured, type: "aspect_ratio")
    }

    func resolutionSpecs(templateValues: [String], defaultValue: String?) -> [PixaOutputSpec] {
        let configured = specs.filter { $0.specType.lowercased() == "resolution" }
        if didLoad, !configured.isEmpty { return configured }
        return merged(templateValues: templateValues, defaultValue: defaultValue, configured: [], type: "resolution")
    }

    private func merged(
        templateValues: [String],
        defaultValue: String?,
        configured: [PixaOutputSpec],
        type: String
    ) -> [PixaOutputSpec] {
        let orderedTemplateValues = ([defaultValue].compactMap { $0 } + templateValues)
            .reduce(into: [String]()) { values, value in
                if !values.contains(value) { values.append(value) }
            }
        var result = orderedTemplateValues.map { value in
            configured.first(where: { $0.value == value })
                ?? PixaOutputSpec(specType: type, value: value)
        }
        let existing = Set(result.map(\.value))
        result.append(contentsOf: configured.filter { !existing.contains($0.value) })
        return result
    }
}

private struct PixaAssetLibraryPicker: View {
    let accessToken: String?
    let onSelect: (PixaAssetLibraryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [PixaAssetLibraryItem] = []
    @State private var selectedID: String?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("common.loading")
                } else if let errorMessage {
                    ContentUnavailableView("common.error", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                } else if items.isEmpty {
                    ContentUnavailableView("editor.library.empty", systemImage: "photo.stack")
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], spacing: 12) {
                            ForEach(items) { item in
                                Button { selectedID = item.id } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        RemoteArtwork(
                                            url: item.imageURL,
                                            aspectRatio: 1,
                                            preset: .thumbnail,
                                            maximumPixelWidth: 480,
                                            contentMode: .fill
                                        )
                                        .frame(height: 112)
                                        .clipShape(RoundedRectangle(cornerRadius: 11))
                                        HStack {
                                            Text(item.name).font(.caption).lineLimit(1)
                                            Spacer()
                                            Image(systemName: selectedID == item.id ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(PixaTheme.accent)
                                        }
                                    }
                                    .padding(8)
                                    .background(
                                        selectedID == item.id ? PixaTheme.accent.opacity(0.1) : Color.white.opacity(0.68),
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(selectedID == item.id ? PixaTheme.accent : PixaTheme.line)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(PixaTheme.paper.ignoresSafeArea())
            .navigationTitle("editor.library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        guard let item = items.first(where: { $0.id == selectedID }) else { return }
                        onSelect(item)
                        dismiss()
                    }
                    .disabled(selectedID == nil)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            let page: PageResponse<PixaAssetLibraryItem> = try await APIClient().get(
                "/api/ais/assets",
                query: [
                    URLQueryItem(name: "page", value: "1"),
                    URLQueryItem(name: "size", value: "50"),
                    URLQueryItem(name: "assetType", value: "style_template_source")
                ],
                token: accessToken
            )
            items = page.items
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct PixaTemplateUploadPayload {
    let data: Data
    let image: UIImage
    let fileExtension: String
    let mimeType: String
}

private extension UIImage {
    func pixaTemplateUploadPayload(
        maximumDimension: CGFloat = 4096,
        preservesPNG: Bool
    ) -> PixaTemplateUploadPayload? {
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let resizeScale = min(1, maximumDimension / max(pixelWidth, pixelHeight))
        let outputSize = CGSize(
            width: max(1, round(pixelWidth * resizeScale)),
            height: max(1, round(pixelHeight * resizeScale))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !preservesPNG
        let normalized = UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            if !preservesPNG {
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: outputSize))
            }
            draw(in: CGRect(origin: .zero, size: outputSize))
        }
        if preservesPNG, let data = normalized.pngData() {
            return PixaTemplateUploadPayload(data: data, image: normalized, fileExtension: "png", mimeType: "image/png")
        }
        guard let data = normalized.jpegData(compressionQuality: 0.88) else { return nil }
        return PixaTemplateUploadPayload(data: data, image: normalized, fileExtension: "jpg", mimeType: "image/jpeg")
    }
}
