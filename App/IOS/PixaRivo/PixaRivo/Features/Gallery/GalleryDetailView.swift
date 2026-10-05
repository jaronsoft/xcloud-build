import SwiftUI

struct GalleryDetailView: View {
    let item: GalleryJob

    @Environment(SessionStore.self) private var session
    @State private var previewTarget: GalleryDetailPreviewTarget?
    @State private var sharePayload: PixaSharePayload?
    @State private var isPreparingShare = false
    @State private var showsShareError = false
    @State private var creationTemplate: StyleTemplate?
    @State private var isPreparingCreation = false
    @State private var showsLogin = false
    @State private var continuesCreationAfterLogin = false
    @State private var createErrorMessage: String?
    @State private var viewCount: Int?
    @State private var heatScore: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                artworkSection
                descriptionSection
                creatorSection
                if !metadataItems.isEmpty { metadataSection }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(PixaTheme.paper.ignoresSafeArea())
        .navigationTitle("gallery.detail.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PixaShareButton(isPreparing: isPreparingShare) {
                    Task { await share() }
                }
                .disabled(item.mediaURL == nil || isPreparingShare)
                .opacity(item.mediaURL == nil ? 0.38 : 1)
            }
        }
        .safeAreaInset(edge: .bottom) {
            createSameButton
        }
        .fullScreenCover(item: $previewTarget) { target in
            PixaArtworkPreview(url: target.url)
        }
        .sheet(item: $creationTemplate) { template in
            TemplateEditorView(template: template)
        }
        .sheet(isPresented: $showsLogin, onDismiss: continueCreationAfterLogin) {
            LoginView()
        }
        .sheet(item: $sharePayload) { payload in
            PixaActivityView(items: payload.items)
        }
        .alert("share.failed.title", isPresented: $showsShareError) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("share.failed.message")
        }
        .alert(
            "gallery.detail.create_failed.title",
            isPresented: Binding(
                get: { createErrorMessage != nil },
                set: { if !$0 { createErrorMessage = nil } }
            )
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(
                createErrorMessage
                    ?? AppLanguage.localized("gallery.detail.template_unavailable")
            )
        }
        .task(id: item.id) { await recordView() }
    }

    private var createSameButton: some View {
        Button {
            Task { await createSame() }
        } label: {
            HStack(spacing: 9) {
                if isPreparingCreation {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                if isPreparingCreation {
                    Text("gallery.detail.preparing_template")
                } else {
                    Text("gallery.detail.create_same")
                }
            }
            .pixaPrimaryButton(isEnabled: !isPreparingCreation)
        }
        .buttonStyle(.plain)
        .disabled(isPreparingCreation)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var artworkSection: some View {
        Button {
            if let url = item.mediaURL {
                previewTarget = GalleryDetailPreviewTarget(url: url)
            }
        } label: {
            RemoteArtwork(
                url: item.mediaURL,
                aspectRatio: item.displayAspectRatio,
                preset: .detail,
                maximumPixelWidth: 1_600,
                contentMode: .fit,
                usesIntrinsicAspectRatio: true
            )
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if item.mediaURL != nil {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(.black.opacity(0.58), in: Circle())
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(item.mediaURL == nil)
        .accessibilityLabel(Text("preview.open"))
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("gallery.detail.curated", systemImage: "seal.fill")
                .font(.caption.bold())
                .foregroundStyle(PixaTheme.accent)
            Text(item.title.nilIfEmpty ?? AppLanguage.localized("gallery.untitled"))
                .font(.title3.bold())
                .foregroundStyle(PixaTheme.ink)
            HStack(spacing: 12) {
                Label(
                    String.localizedStringWithFormat(
                        AppLanguage.localized("metrics.heat"),
                        (heatScore ?? item.heatScore).formatted(.number.notation(.compactName))
                    ),
                    systemImage: "flame"
                )
                Label(
                    String.localizedStringWithFormat(
                        AppLanguage.localized("metrics.views"),
                        (viewCount ?? item.viewCount).formatted(.number.notation(.compactName))
                    ),
                    systemImage: "eye"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let description = item.description.nilIfEmpty {
                Text("gallery.detail.description")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !visibleKeywords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(visibleKeywords, id: \.self) { keyword in
                            Text(keyword)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PixaTheme.ink)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(PixaTheme.accent.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(14)
        .pixaSurface()
    }

    private func recordView() async {
        let api = APIClient()
        let response: PublicViewCountResponse? = try? await api.post(
            "/api/ais/jobs/gallery/\(item.id)/view",
            body: [String: String](),
            token: session.accessToken
        )
        if let response {
            viewCount = response.viewCount
            heatScore = response.heatScore
        }
    }

    private var creatorSection: some View {
        HStack(spacing: 12) {
            if let url = resolvedAccountURL(item.creatorAvatarURL) {
                RemoteArtwork(
                    url: url,
                    aspectRatio: 1,
                    preset: .thumbnail,
                    maximumPixelWidth: 120
                )
                .frame(width: 42, height: 42)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("gallery.detail.creator")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.creatorName?.nilIfEmpty ?? AppLanguage.localized("gallery.creator.anonymous"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PixaTheme.ink)
            }
            Spacer()
        }
        .padding(14)
        .pixaSurface()
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("gallery.detail.information")
                .font(.headline)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                spacing: 10
            ) {
                ForEach(metadataItems) { metadata in
                    VStack(alignment: .leading, spacing: 5) {
                        Label(metadata.title, systemImage: metadata.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(metadata.value)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PixaTheme.ink)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .padding(12)
                    .background(
                        Color(uiColor: .tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
            }
        }
        .padding(14)
        .pixaSurface()
    }

    private var visibleKeywords: [String] {
        Array(item.keywords.compactMap(\.nilIfEmpty).prefix(8))
    }

    private var metadataItems: [GalleryMetadataItem] {
        var values: [GalleryMetadataItem] = []
        if let width = item.pixelWidth, let height = item.pixelHeight {
            values.append(.init(id: "pixels", title: AppLanguage.localized("works.detail.pixel_size"), value: "\(width) × \(height) px", icon: "rectangle.expand.vertical"))
        }
        if let resolution = item.resolution?.nilIfEmpty {
            values.append(.init(id: "resolution", title: AppLanguage.localized("works.detail.resolution"), value: resolution, icon: "sparkles.rectangle.stack"))
        }
        if let bytes = item.fileSizeBytes, bytes > 0 {
            values.append(.init(id: "fileSize", title: AppLanguage.localized("works.detail.file_size"), value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file), icon: "doc"))
        }
        if let seconds = item.generationDurationSeconds, seconds >= 0 {
            values.append(.init(id: "duration", title: AppLanguage.localized("works.detail.duration"), value: formattedDuration(seconds), icon: "clock"))
        }
        if let ratio = item.aspectRatio?.nilIfEmpty {
            values.append(.init(id: "ratio", title: AppLanguage.localized("works.detail.aspect_ratio"), value: ratio, icon: "aspectratio"))
        }
        return values
    }

    private func formattedDuration(_ seconds: Int64) -> String {
        if seconds < 60 {
            return String.localizedStringWithFormat(AppLanguage.localized("works.detail.duration_seconds"), seconds)
        }
        return String.localizedStringWithFormat(AppLanguage.localized("works.detail.duration_minutes"), seconds / 60, seconds % 60)
    }

    @MainActor
    private func createSame() async {
        guard !isPreparingCreation else { return }
        guard session.isAuthenticated else {
            continuesCreationAfterLogin = true
            showsLogin = true
            return
        }
        await loadCreationTemplate()
    }

    @MainActor
    private func continueCreationAfterLogin() {
        guard continuesCreationAfterLogin else { return }
        continuesCreationAfterLogin = false
        guard session.isAuthenticated else { return }
        Task { await loadCreationTemplate() }
    }

    @MainActor
    private func loadCreationTemplate() async {
        guard let templateID = item.styleTemplateID?.nilIfEmpty else {
            createErrorMessage = AppLanguage.localized(
                "gallery.detail.template_unavailable"
            )
            return
        }
        isPreparingCreation = true
        defer { isPreparingCreation = false }
        do {
            let template: StyleTemplate = try await APIClient().get(
                "/api/ais/style-templates/\(templateID)",
                query: [
                    .init(name: "language", value: AppLanguage.apiValue)
                ],
                token: session.accessToken
            )
            creationTemplate = template
        } catch {
            createErrorMessage = AppLanguage.localized(
                "gallery.detail.template_unavailable"
            )
        }
    }

    @MainActor
    private func share() async {
        guard !isPreparingShare, item.mediaURL != nil else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        sharePayload = await PixaShareService.prepare(
            title: item.title.nilIfEmpty ?? AppLanguage.localized("gallery.untitled"),
            description: item.description.nilIfEmpty,
            imageURL: item.mediaURL,
            source: .gallery
        )
        showsShareError = sharePayload == nil
    }
}

private struct GalleryMetadataItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let icon: String
}

private struct GalleryDetailPreviewTarget: Identifiable {
    let id = UUID()
    let url: URL
}
