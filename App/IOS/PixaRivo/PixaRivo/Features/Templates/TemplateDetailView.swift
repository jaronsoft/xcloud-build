import SwiftUI

struct TemplateDetailView: View {
    let template: StyleTemplate
    @Environment(SessionStore.self) private var session
    @Environment(PixaAccountDataStore.self) private var accountData
    @State private var detail: StyleTemplate?
    @State private var cases: [GalleryJob] = []
    @State private var showsEditor = false
    @State private var showsLogin = false
    @State private var sharePayload: PixaSharePayload?
    @State private var isPreparingShare = false
    @State private var showsShareError = false
    @State private var previewTarget: ArtworkPreviewTarget?

    private var active: StyleTemplate { detail ?? template }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button {
                    if let url = active.imageURL {
                        previewTarget = ArtworkPreviewTarget(url: url)
                    }
                } label: {
                    RemoteArtwork(url: active.imageURL, aspectRatio: active.displayAspectRatio, preset: .detail)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                .disabled(active.imageURL == nil)
                .accessibilityLabel(Text("preview.open"))
                Text(active.name).font(.system(.title, design: .serif, weight: .bold))
                HStack {
                    Text(active.aspectRatioText)
                    Text("·")
                    Label(
                        String.localizedStringWithFormat(
                            AppLanguage.localized("metrics.heat"),
                            active.heatScore.formatted(.number.notation(.compactName))
                        ),
                        systemImage: "flame"
                    )
                    Text("·")
                    Label(
                        String.localizedStringWithFormat(
                            AppLanguage.localized("metrics.views"),
                            active.viewCount.formatted(.number.notation(.compactName))
                        ),
                        systemImage: "eye"
                    )
                    Text("·")
                    Label(
                        String.localizedStringWithFormat(
                            AppLanguage.localized("metrics.uses"),
                            active.usageCount.formatted(.number.notation(.compactName))
                        ),
                        systemImage: "wand.and.stars"
                    )
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text(active.description.nilIfEmpty ?? AppLanguage.localized("template.detail.summary"))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                Text("template.replace_content").font(.title3.bold())
                HStack(spacing: 12) {
                    infoBox(icon: "photo", title: String.localizedStringWithFormat(AppLanguage.localized("template.images.count"), active.imageSlots.count))
                    infoBox(icon: "textformat", title: String.localizedStringWithFormat(AppLanguage.localized("template.text.count"), active.textFields.filter(\.enabled).count))
                }
                if !cases.isEmpty {
                    Text("template.same_cases").font(.title3.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(cases) { item in
                                Button {
                                    if let url = item.mediaURL {
                                        previewTarget = ArtworkPreviewTarget(url: url)
                                    }
                                } label: {
                                    RemoteArtwork(
                                        url: item.mediaURL,
                                        aspectRatio: item.displayAspectRatio,
                                        preset: .thumbnail,
                                        contentMode: .fit,
                                        usesIntrinsicAspectRatio: true
                                    )
                                    .frame(width: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .padding(7)
                                            .background(.black.opacity(0.55), in: Circle())
                                            .padding(7)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("preview.open"))
                            }
                        }
                    }
                }
            }.padding(16).padding(.bottom, 80)
        }
        .background(PixaTheme.paper.ignoresSafeArea())
        .navigationTitle("template.detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PixaShareButton(isPreparing: isPreparingShare) {
                    Task { await share() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { session.isAuthenticated ? (showsEditor = true) : (showsLogin = true) } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Text("template.use")
                        if let price = localPrice {
                            Text(String.localizedStringWithFormat(
                                AppLanguage.localized("points.format"),
                                price.points
                            ))
                        } else if session.isAuthenticated && accountData.pricingRules.isLoading {
                            ProgressView().tint(.white).controlSize(.small)
                        } else if session.isAuthenticated {
                            Text("template.price.unavailable")
                        } else {
                            Text(String.localizedStringWithFormat(
                                AppLanguage.localized("points.format"),
                                active.basePointCost
                            ))
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    if let price = localPrice, price.effectiveDiscountPercent > 0 {
                        HStack(spacing: 7) {
                            Text(String.localizedStringWithFormat(
                                AppLanguage.localized("template.original_points"),
                                price.originalPoints
                            ))
                            .strikethrough()
                            Text(String.localizedStringWithFormat(
                                AppLanguage.localized("template.discount"),
                                NSDecimalNumber(decimal: price.effectiveDiscountPercent).doubleValue
                            ))
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                }
                .pixaPrimaryButton()
            }.padding(.horizontal, 16).padding(.vertical, 8).background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showsEditor) { TemplateEditorView(template: active) }
        .sheet(isPresented: $showsLogin) { LoginView() }
        .sheet(item: $sharePayload) { payload in
            PixaActivityView(items: payload.items)
        }
        .fullScreenCover(item: $previewTarget) { target in
            PixaArtworkPreview(url: target.url)
        }
        .alert("share.failed.title", isPresented: $showsShareError) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("share.failed.message")
        }
        .task(id: template.id) {
            async let accountLoad: Void = accountData.load(session: session)
            await load()
            await accountLoad
        }
    }

    private var localPrice: PixaLocalPrice? {
        guard let rules = accountData.pricingRules.rules else { return nil }
        let resolution = active.defaultResolution ?? active.resolutions.first ?? "1536"
        return PixaLocalPricingCalculator.template(
            snapshot: rules,
            basePoints: active.basePointCost,
            defaultResolution: active.defaultResolution,
            resolution: resolution,
            selectedModelKey: active.defaultDisplayModelKey ?? ""
        )
    }

    private func infoBox(icon: String, title: String) -> some View {
        Label(title, systemImage: icon).font(.headline).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(PixaTheme.line) }
    }

    private func load() async {
        let api = APIClient()
        if var loaded: StyleTemplate = try? await api.get(
            "/api/ais/style-templates/\(template.id)",
            query: [
                URLQueryItem(name: "region", value: PixaMediaRegion.templateRegionValue),
                URLQueryItem(name: "language", value: AppLanguage.apiValue)
            ],
            token: session.accessToken,
            forceRefresh: true
        ) {
            loaded.preserveMissingMedia(from: template)
            detail = loaded
        }
        let page: PageResponse<GalleryJob>? = try? await api.get("/api/ais/jobs/gallery", query: [.init(name: "styleTemplateId", value: template.id), .init(name: "size", value: "8"), .init(name: "language", value: AppLanguage.apiValue)])
        cases = page?.items.filter { $0.mediaURL != nil } ?? []
    }

    @MainActor
    private func share() async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        sharePayload = await PixaShareService.prepare(
            title: active.name,
            description: active.description,
            imageURL: active.imageURL,
            source: .template,
            xPrompt: active.publicPrompt
        )
        showsShareError = sharePayload == nil
    }
}

private struct ArtworkPreviewTarget: Identifiable {
    let id = UUID()
    let url: URL
}
