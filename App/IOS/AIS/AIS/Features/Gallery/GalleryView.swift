import SwiftUI

enum GalleryContentKind: String, Identifiable, Hashable {
    case imageShowcase
    case templateShowcase

    var id: String { rawValue }

    var navigationTitle: LocalizedStringKey {
        switch self {
        case .imageShowcase: "gallery.title"
        case .templateShowcase: "templates.user_cases"
        }
    }

    var heading: LocalizedStringKey {
        switch self {
        case .imageShowcase: "gallery.heading"
        case .templateShowcase: "templates.user_cases.heading"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .imageShowcase: "gallery.subtitle"
        case .templateShowcase: "templates.user_cases.subtitle"
        }
    }

    var emptyTitle: LocalizedStringKey {
        switch self {
        case .imageShowcase: "gallery.empty"
        case .templateShowcase: "templates.user_cases.empty"
        }
    }

    var cacheResource: String {
        switch self {
        case .imageShowcase: "image-showcase-v2"
        case .templateShowcase: "template-showcase"
        }
    }
}

struct GalleryView: View {
    let initialJobID: String?
    let contentKind: GalleryContentKind
    let onCreate: () -> Void
    let onUseTemplate: ((String) -> Void)?

    @State private var viewModel = GalleryViewModel()
    @State private var selectedJob: GalleryJob?
    @State private var selectedSharedRoute: SharedGalleryRoute?
    @State private var contentWidth: CGFloat = 0
    @State private var loadMoreSentinelMinY = CGFloat.infinity
    @State private var scrollViewportHeight: CGFloat = 0

    init(
        initialJobID: String? = nil,
        contentKind: GalleryContentKind = .imageShowcase,
        onCreate: @escaping () -> Void,
        onUseTemplate: ((String) -> Void)? = nil
    ) {
        self.initialJobID = initialJobID
        self.contentKind = contentKind
        self.onCreate = onCreate
        self.onUseTemplate = onUseTemplate
    }

    var body: some View {
        ZStack {
            AISPageBackground()

            Group {
                if viewModel.isLoading && viewModel.jobs.isEmpty {
                    ProgressView("common.loading")
                } else if let errorMessage = viewModel.errorMessage,
                          viewModel.jobs.isEmpty {
                    ContentUnavailableView {
                        Label("common.error", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("templates.retry") {
                            Task {
                                await viewModel.load(
                                    kind: contentKind,
                                    force: true
                                )
                            }
                        }
                    }
                } else if viewModel.jobs.isEmpty {
                    ContentUnavailableView(
                        contentKind.emptyTitle,
                        systemImage: "photo.stack"
                    )
                } else {
                    galleryContent
                }
            }
        }
        .navigationTitle(contentKind.navigationTitle)
        .task {
            await viewModel.load(kind: contentKind)
        }
        .sheet(item: $selectedJob) { job in
            GalleryDetailView(
                job: job,
                onCreate: onCreate,
                onUseTemplate: onUseTemplate
            )
        }
        .sheet(item: $selectedSharedRoute) { route in
            GalleryDetailView(jobID: route.jobID, onCreate: onCreate)
        }
        .task(id: initialJobID) {
            guard let initialJobID, !initialJobID.isEmpty else { return }
            selectedSharedRoute = SharedGalleryRoute(jobID: initialJobID)
        }
    }

    private var galleryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(contentKind.heading)
                        .font(.title3.bold())
                    Text(contentKind.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                PinterestMasonryLayout(columns: masonryColumns, spacing: 12) {
                    ForEach(viewModel.jobs) { job in
                        Button {
                            selectedJob = job
                        } label: {
                            GalleryCard(job: job)
                        }
                        .buttonStyle(.plain)
                    }
                }

                galleryFooter
                GalleryLoadMoreSentinel()
            }
            .frame(
                maxWidth: AISResponsiveLayout.maximumContentWidth,
                alignment: .leading
            )
            .onAISContentWidthChange { width in
                if abs(contentWidth - width) > 1 {
                    contentWidth = width
                }
            }
            .padding(
                .horizontal,
                AISResponsiveLayout.horizontalPadding(for: contentWidth)
            )
            .padding(.top, 10)
            .padding(.bottom, 38)
            .frame(maxWidth: .infinity)
        }
        .coordinateSpace(name: GalleryScrollCoordinateSpace.name)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: GalleryViewportHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(GalleryViewportHeightPreferenceKey.self) { height in
            scrollViewportHeight = height
            loadMoreIfNeeded()
        }
        .onPreferenceChange(GallerySentinelMinYPreferenceKey.self) { minY in
            loadMoreSentinelMinY = minY
            loadMoreIfNeeded()
        }
        .onChange(of: viewModel.isLoading) {
            loadMoreIfNeeded()
        }
        .onChange(of: viewModel.isLoadingMore) {
            loadMoreIfNeeded()
        }
        .refreshable {
            await viewModel.load(kind: contentKind, force: true)
        }
    }

    private var masonryColumns: Int {
        if contentWidth >= 1100 { return 4 }
        if contentWidth >= 740 { return 3 }
        return 2
    }

    @ViewBuilder
    private var galleryFooter: some View {
        if viewModel.isLoadingMore {
            HStack(spacing: 8) {
                ProgressView()
                Text("gallery.loading_more")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if viewModel.hasMore,
                  let loadMoreErrorMessage = viewModel.loadMoreErrorMessage {
            VStack(spacing: 8) {
                Text(loadMoreErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("templates.retry") {
                    Task { await viewModel.loadMore(kind: contentKind) }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        } else if !viewModel.hasMore {
            Text(
                String.localizedStringWithFormat(
                    String(localized: "gallery.loaded_all"),
                    viewModel.jobs.count
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func loadMoreIfNeeded() {
        guard GalleryPaginationTrigger.shouldLoadMore(
            sentinelMinY: loadMoreSentinelMinY,
            viewportHeight: scrollViewportHeight,
            hasMore: viewModel.hasMore,
            isLoading: viewModel.isLoading,
            isLoadingMore: viewModel.isLoadingMore,
            hasLoadMoreError: viewModel.loadMoreErrorMessage != nil
        ) else {
            return
        }
        Task {
            await viewModel.loadMore(kind: contentKind)
        }
    }
}

private struct SharedGalleryRoute: Identifiable {
    let jobID: String
    var id: String { jobID }
}

private enum GalleryScrollCoordinateSpace {
    static let name = "gallery-scroll"
}

private struct GalleryViewportHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct GallerySentinelMinYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

private struct GalleryLoadMoreSentinel: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: GallerySentinelMinYPreferenceKey.self,
                value: proxy.frame(
                    in: .named(GalleryScrollCoordinateSpace.name)
                ).minY
            )
        }
        .frame(height: 1)
    }
}

enum GalleryPaginationTrigger {
    static let prefetchDistance: CGFloat = 240

    static func shouldLoadMore(
        sentinelMinY: CGFloat,
        viewportHeight: CGFloat,
        hasMore: Bool,
        isLoading: Bool,
        isLoadingMore: Bool,
        hasLoadMoreError: Bool
    ) -> Bool {
        hasMore
            && !isLoading
            && !isLoadingMore
            && !hasLoadMoreError
            && viewportHeight > 0
            && sentinelMinY.isFinite
            && sentinelMinY <= viewportHeight + prefetchDistance
    }
}

struct GalleryCard: View {
    let job: GalleryJob

    private var aspectRatio: CGFloat {
        job.mediaAspectRatio ?? 1.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let coverURL = job.mediaURL {
                        AISCachedAsyncImage(
                            url: coverURL,
                            preset: .list,
                            module: .galleryTemplates
                        ) { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .aspectRatio(
                                        aspectRatio,
                                        contentMode: .fill
                                    )
                            case .failure:
                                placeholder
                            case .empty:
                                ZStack {
                                    placeholder
                                    ProgressView()
                                        .tint(AISTheme.accent)
                                }
                            @unknown default:
                                placeholder
                            }
                        }
                    } else {
                        placeholder
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipped()
                .background(Color(uiColor: .secondarySystemGroupedBackground))

                if job.creationKind == .video {
                    Image(systemName: "play.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.ultraThinMaterial, in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 5) {
                    Image(systemName: job.creationKind.badgeSymbol)
                    .font(.caption2.bold())
                    Text(job.creationKind.badgeTitle)
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(job.creationKind.badgeColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(
                            job.creationKind.badgeColor.opacity(0.45),
                            lineWidth: 1
                        )
                }
                .padding(8)
            }
            .clipShape(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(job.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !job.description.isEmpty {
                    Text(job.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Label("\(job.pointCost)", systemImage: "sparkles")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AISTheme.accent)
                    Spacer()
                    if let aspect = job.mediaAspectRatio {
                        Text(String(format: "%.1f:1", aspect))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .aisSurface(cornerRadius: 20, hasShadow: true)
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)
            Image(
                systemName: job.creationKind == .video
                    ? "play.rectangle.fill" : "photo"
            )
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}

struct GalleryDetailView: View {
    let job: GalleryJob?
    let jobID: String
    let onCreate: () -> Void
    let onUseTemplate: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var model = GalleryDetailViewModel()
    @State private var sharePayload: AISSharePayload?
    @State private var isPreparingShare = false
    @State private var mediaViewerRoute: AISMediaViewerRoute?

    init(
        job: GalleryJob,
        onCreate: @escaping () -> Void,
        onUseTemplate: ((String) -> Void)? = nil
    ) {
        self.job = job
        jobID = job.id
        self.onCreate = onCreate
        self.onUseTemplate = onUseTemplate
    }

    init(jobID: String, onCreate: @escaping () -> Void) {
        job = nil
        self.jobID = jobID
        self.onCreate = onCreate
        onUseTemplate = nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ZStack {
                        if let coverURL = detailCoverURL {
                            AISCachedAsyncImage(
                                url: coverURL,
                                preset: .detail,
                                module: .galleryTemplates
                            ) { phase in
                                switch phase {
                                case let .success(image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                case .failure:
                                    detailMediaPlaceholder
                                case .empty:
                                    ZStack {
                                        detailMediaPlaceholder
                                        ProgressView()
                                            .tint(AISTheme.accent)
                                    }
                                @unknown default:
                                    detailMediaPlaceholder
                                }
                            }
                        } else {
                            detailMediaPlaceholder
                        }

                        if detailMediaKind == .video {
                            Image(systemName: "play.fill")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                                .frame(width: 72, height: 72)
                                .background(.ultraThinMaterial, in: Circle())
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 220)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .contentShape(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .onTapGesture {
                        presentMedia(id: "main")
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("media.viewer.open_hint")

                    VStack(alignment: .leading, spacing: 9) {
                        Text(displayTitle)
                            .font(.title2.bold())
                        if !displayDescription.isEmpty {
                            Text(displayDescription)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .aisSurface(cornerRadius: 22)

                    referenceSection
                    specificationSection

                    if let errorMessage = model.errorMessage {
                        Label(
                            errorMessage,
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await prepareShare() }
                    } label: {
                        Label(
                            isPreparingShare
                                ? "gallery.share.preparing"
                                : "gallery.share",
                            systemImage: "square.and.arrow.up"
                        )
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AISTheme.accentSecondary)
                    .disabled(isPreparingShare)

                    Button {
                        dismiss()
                        if let templateID = job?.styleTemplateID,
                           let onUseTemplate {
                            onUseTemplate(templateID)
                        } else {
                            onCreate()
                        }
                    } label: {
                        Label(
                            job?.styleTemplateID == nil
                                ? "gallery.create"
                                : "templates.action.use",
                            systemImage: "wand.and.sparkles"
                        )
                        .aisPrimaryButton()
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background {
                AISPageBackground()
            }
            .navigationTitle("gallery.detail.title")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: jobID) {
                await model.load(jobID: jobID)
            }
            .sheet(item: $sharePayload) { payload in
                AISActivityView(items: payload.items)
            }
            .fullScreenCover(item: $mediaViewerRoute) { route in
                AISMediaGalleryViewer(
                    items: mediaViewerItems,
                    initialItemID: route.id
                )
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var referenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("gallery.detail.references")
                .font(.headline)

            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else if model.references.isEmpty {
                Text("gallery.detail.references.empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.references) { material in
                            Button {
                                presentMedia(id: "reference:\(material.id)")
                            } label: {
                                Group {
                                    if material.available,
                                       material.url != nil {
                                        AISCachedAsyncImage(
                                            url: material.url,
                                            preset: .thumbnail,
                                            module: .galleryTemplates
                                        ) { phase in
                                            switch phase {
                                            case let .success(image):
                                                image
                                                    .resizable()
                                                    .scaledToFit()
                                            case .empty:
                                                ProgressView()
                                            default:
                                                Image(systemName: "photo")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    } else {
                                        VStack(spacing: 6) {
                                            Image(systemName: "photo.badge.exclamationmark")
                                            Text("gallery.detail.material.unavailable")
                                                .font(.caption2)
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 160, height: 130)
                                .background(
                                    Color(
                                        uiColor:
                                            .secondarySystemGroupedBackground
                                    )
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 16,
                                        style: .continuous
                                    )
                                )
                                .overlay(alignment: .bottomLeading) {
                                    Text(material.galleryDisplayName)
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(.black.opacity(0.68))
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius: 7,
                                                style: .continuous
                                            )
                                        )
                                        .padding(8)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!material.available || material.url == nil)
                            .accessibilityHint("image.viewer.open_hint")
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aisSurface(cornerRadius: 22)
    }

    private var mediaViewerItems: [AISMediaViewerItem] {
        AISMediaViewerCollection.galleryItems(
            resultURL: detailResultURL,
            resultKind: detailMediaKind,
            posterURL: detailCoverURL,
            title: displayTitle,
            references: model.availableReferences
        )
    }

    private func presentMedia(id: String) {
        guard let resolvedID = AISMediaViewerCollection.resolvedID(
            preferredID: id,
            items: mediaViewerItems
        ) else {
            return
        }
        mediaViewerRoute = AISMediaViewerRoute(id: resolvedID)
    }

    private var detailMediaKind: AISMediaKind {
        if let shared = model.sharedJob {
            return shared.mediaKind
        }
        return job?.creationKind == .video ? .video : .image
    }

    private var detailResultURL: URL? {
        if let job {
            let resultURL = job.creationKind == .video
                ? job.videoURL : job.mediaURL
            if let resultURL {
                return resultURL
            }
        }
        guard let shared = model.sharedJob else { return nil }
        return shared.mediaKind == .video
            ? shared.publicMediaProxyURL
            : shared.mediaURL
    }

    private var detailCoverURL: URL? {
        job?.mediaURL ?? model.sharedJob?.displayURL
    }

    private var detailMediaPlaceholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)
            Image(
                systemName: detailMediaKind == .video
                    ? "play.rectangle.fill" : "photo"
            )
            .font(.largeTitle)
            .foregroundStyle(.tertiary)
        }
    }

    private var specificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("gallery.detail.specification")
                .font(.headline)

            if specificationRows.isEmpty && model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else {
                ForEach(specificationRows, id: \.title) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(row.value)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aisSurface(cornerRadius: 22)
    }

    private var specificationRows: [(title: String, value: String)] {
        let shared = model.sharedJob
        var rows: [(String, String)] = []
        if let value = shared?.aspectRatio, !value.isEmpty {
            rows.append((String(localized: "gallery.detail.ratio"), value))
        }
        if let width = shared?.pixelWidth,
           let height = shared?.pixelHeight {
            rows.append(
                (
                    String(localized: "gallery.detail.pixel_size"),
                    "\(width)×\(height)"
                )
            )
        }
        if let bytes = shared?.fileSizeBytes, bytes > 0 {
            rows.append(
                (
                    String(localized: "gallery.detail.file_size"),
                    ByteCountFormatter.string(
                        fromByteCount: bytes,
                        countStyle: .file
                    )
                )
            )
        }
        if let startedAt = shared?.startedAt,
           let finishedAt = shared?.finishedAt {
            let seconds = max(
                0,
                Int(finishedAt.timeIntervalSince(startedAt).rounded())
            )
            rows.append(
                (
                    String(localized: "gallery.detail.duration"),
                    formatDuration(seconds)
                )
            )
        }
        let points = shared?.pointCost ?? job?.pointCost ?? 0
        if points > 0 {
            rows.append(
                (
                    String(localized: "gallery.detail.point_cost"),
                    String.localizedStringWithFormat(
                        String(localized: "gallery.detail.points"),
                        points
                    )
                )
            )
        }
        return rows
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return String.localizedStringWithFormat(
                String(localized: "gallery.detail.duration.seconds"),
                seconds
            )
        }
        return String.localizedStringWithFormat(
            String(localized: "gallery.detail.duration.minutes"),
            seconds / 60,
            seconds % 60
        )
    }

    private func prepareShare() async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        let title = displayTitle
        sharePayload = await AISShareService.prepare(
            jobID: jobID,
            title: title,
            description: displayDescription,
            imageURL: detailCoverURL
        )
    }

    private var displayTitle: String {
        if let title = model.sharedJob?.title, !title.isEmpty {
            return title
        }
        if let title = job?.title, !title.isEmpty {
            return title
        }
        return String(localized: "tasks.share.default_title")
    }

    private var displayDescription: String {
        if let value = model.sharedJob?.description, !value.isEmpty {
            return value
        }
        return job?.description ?? ""
    }
}

@MainActor
@Observable
private final class GalleryDetailViewModel {
    private let api = APIClient()
    private(set) var sharedJob: AISSharedJob?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var references: [AISSharedInputMaterial] {
        sharedJob?.inputMaterials.sorted {
            if $0.index == $1.index {
                return $0.id < $1.id
            }
            return $0.index < $1.index
        } ?? []
    }

    var availableReferences: [AISSharedInputMaterial] {
        references.filter {
            $0.available && $0.url != nil
        }
    }

    func load(jobID: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            sharedJob = try await api.get(
                "/api/ais/jobs/shared/\(jobID)"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
@Observable
final class GalleryViewModel {
    private let api = APIClient()
    private let pageSize = 20

    private(set) var jobs: [GalleryJob] = []
    private(set) var total = 0
    private(set) var page = 0
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var loadMoreErrorMessage: String?

    var hasMore: Bool {
        total > jobs.count
    }

    func load(kind: GalleryContentKind, force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        loadMoreErrorMessage = nil
        defer { isLoading = false }

        do {
            let language = AISLocalization.isChinese ? "zh" : "en"
            let cacheKey = AISResponseCache.key(
                scope: "public",
                resource: kind.cacheResource,
                parameters: [
                    "language": language,
                    "page": "1",
                    "size": String(pageSize)
                ]
            )
            if !force,
               let cached = await AISResponseCache.shared.read(
                   PageResponse<GalleryJob>.self,
                   key: cacheKey,
                   allowsStale: true
               ) {
                jobs = cached.value.items
                    .filter(\.hasDisplayableMedia)
                    .sorted { $0.id > $1.id }
                total = cached.value.total
                page = 1
                if cached.isFresh { return }
            }
            let response = try await fetchPage(
                1,
                kind: kind,
                language: language
            )
            jobs = response.items
                .filter(\.hasDisplayableMedia)
                .sorted { $0.id > $1.id }
            total = response.total
            page = 1
            await AISResponseCache.shared.write(response, key: cacheKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore(kind: GalleryContentKind) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer { isLoadingMore = false }
        do {
            let language = AISLocalization.isChinese ? "zh" : "en"
            let nextPage = page + 1
            let response = try await fetchPage(
                nextPage,
                kind: kind,
                language: language
            )
            var merged: [String: GalleryJob] = [:]
            for job in jobs {
                merged[job.id] = job
            }
            for job in response.items where job.hasDisplayableMedia {
                merged[job.id] = job
            }
            jobs = merged.values.sorted { $0.id > $1.id }
            total = response.total
            page = nextPage
        } catch {
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    private func fetchPage(
        _ page: Int,
        kind: GalleryContentKind,
        language: String
    ) async throws -> PageResponse<GalleryJob> {
        try await api.get(
            "/api/ais/jobs/gallery",
            query: Self.requestQuery(
                page: page,
                pageSize: pageSize,
                language: language,
                kind: kind
            )
        )
    }

    nonisolated static func requestQuery(
        page: Int,
        pageSize: Int,
        language: String,
        kind: GalleryContentKind
    ) -> [URLQueryItem] {
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(pageSize)),
            URLQueryItem(name: "language", value: language)
        ]
        switch kind {
        case .imageShowcase:
            query.append(
                URLQueryItem(
                    name: "excludeStyleTemplates",
                    value: "true"
                )
            )
        case .templateShowcase:
            query.append(
                URLQueryItem(
                    name: "jobType",
                    value: "style_template_generate"
                )
            )
        }
        return query
    }
}

/// 按卡片实际高度分配到当前最短列，让不同画幅案例保持 Pin 瀑布流节奏。
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

private extension AISCreationKind {
    var badgeTitle: LocalizedStringKey {
        switch self {
        case .image: "gallery.type.image"
        case .imageEdit: "gallery.type.image_edit"
        case .video: "gallery.type.video"
        case .template: "gallery.type.template"
        case .other: "gallery.type.other"
        }
    }

    var badgeSymbol: String {
        switch self {
        case .image: "sparkles"
        case .imageEdit: "slider.horizontal.3"
        case .video: "play.rectangle.fill"
        case .template: "square.grid.2x2.fill"
        case .other: "wand.and.sparkles"
        }
    }

    var badgeColor: Color {
        switch self {
        case .image: AISTheme.accent
        case .imageEdit: .blue
        case .video: .purple
        case .template: .teal
        case .other: AISTheme.accentSecondary
        }
    }
}

#Preview("GalleryView") {
    NavigationStack {
        GalleryView(onCreate: {})
    }
    .environment(SessionStore())
}
