import AVKit
import Photos
import SwiftUI
import UIKit

enum AISMediaKind: String, Hashable {
    case image
    case video
}

struct AISMediaViewerItem: Identifiable, Hashable {
    let id: String
    let kind: AISMediaKind
    let originalURL: URL
    let thumbnailURL: URL?
    let title: String?
    let requiresAuthentication: Bool
    let cacheModule: AISImageCacheModule

    init(
        id: String,
        kind: AISMediaKind = .image,
        originalURL: URL,
        thumbnailURL: URL? = nil,
        title: String? = nil,
        requiresAuthentication: Bool = false,
        cacheModule: AISImageCacheModule = .galleryTemplates
    ) {
        self.id = id
        self.kind = kind
        self.originalURL = originalURL
        self.thumbnailURL = thumbnailURL
            ?? (kind == .image ? originalURL : nil)
        self.title = title
        self.requiresAuthentication = requiresAuthentication
        self.cacheModule = cacheModule
    }
}

struct AISMediaViewerRoute: Identifiable {
    let id: String
}

enum AISMediaViewerCollection {
    static func galleryItems(
        resultURL: URL?,
        resultKind: AISMediaKind,
        posterURL: URL?,
        title: String?,
        references: [AISSharedInputMaterial],
        requiresAuthentication: Bool = false
    ) -> [AISMediaViewerItem] {
        var items: [AISMediaViewerItem] = []
        if let resultURL {
            items.append(
                AISMediaViewerItem(
                    id: "main",
                    kind: resultKind,
                    originalURL: resultURL,
                    thumbnailURL: posterURL,
                    title: title,
                    requiresAuthentication: requiresAuthentication
                )
            )
        }
        items.append(
            contentsOf: references
                .filter { $0.available && $0.url != nil }
                .sorted {
                    if $0.index == $1.index {
                        return $0.id < $1.id
                    }
                    return $0.index < $1.index
                }
                .compactMap { material in
                    guard let url = material.url else { return nil }
                    return AISMediaViewerItem(
                        id: "reference:\(material.id)",
                        originalURL: url,
                        title: material.galleryDisplayName,
                        requiresAuthentication: requiresAuthentication
                    )
                }
        )
        return items
    }

    static func resolvedID(
        preferredID: String?,
        items: [AISMediaViewerItem]
    ) -> String? {
        guard !items.isEmpty else { return nil }
        if let preferredID, items.contains(where: { $0.id == preferredID }) {
            return preferredID
        }
        return items[0].id
    }

    static func position(
        selectedID: String?,
        items: [AISMediaViewerItem]
    ) -> Int {
        guard let selectedID,
              let index = items.firstIndex(where: { $0.id == selectedID })
        else {
            return items.isEmpty ? 0 : 1
        }
        return index + 1
    }
}

enum AISZoomTransform {
    static func isZoomed(_ scale: CGFloat) -> Bool {
        scale > 1
    }

    static func clampedScale(_ value: CGFloat) -> CGFloat {
        min(5, max(1, value))
    }

    static func clampedOffset(
        _ value: CGSize,
        scale: CGFloat,
        viewport: CGSize
    ) -> CGSize {
        guard scale > 1 else { return .zero }
        let maximumX = max(0, viewport.width * (scale - 1) / 2)
        let maximumY = max(0, viewport.height * (scale - 1) / 2)
        return CGSize(
            width: min(maximumX, max(-maximumX, value.width)),
            height: min(maximumY, max(-maximumY, value.height))
        )
    }
}

enum AISMediaDismissalGesture {
    static let translationThreshold: CGFloat = 100
    static let predictedTranslationThreshold: CGFloat = 180

    static func isDownwardVerticalDrag(_ translation: CGSize) -> Bool {
        translation.height > 0
            && translation.height > abs(translation.width)
    }

    static func shouldDismiss(
        translation: CGSize,
        predictedTranslation: CGSize,
        isZoomed: Bool
    ) -> Bool {
        guard !isZoomed,
              isDownwardVerticalDrag(translation) else {
            return false
        }
        return translation.height >= translationThreshold
            || predictedTranslation.height >= predictedTranslationThreshold
    }
}

enum AISPhotoLibraryWriter {
    static func save(_ data: Data) async throws {
        try await savePhoto(data)
    }

    static func savePhoto(_ data: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(
                with: .photo,
                data: data,
                options: nil
            )
        }
    }

    static func saveVideo(at fileURL: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(
                with: .video,
                fileURL: fileURL,
                options: nil
            )
        }
    }
}

private struct AISZoomableMediaSurface<Content: View>: View {
    let resetToken: String?
    let onZoomStateChanged: ((Bool) -> Void)?
    let onSingleTap: (() -> Void)?
    let content: Content

    @State private var baseScale: CGFloat = 1
    @State private var baseOffset: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1
    @GestureState private var translation: CGSize = .zero

    init(
        resetToken: String?,
        onZoomStateChanged: ((Bool) -> Void)?,
        onSingleTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.resetToken = resetToken
        self.onZoomStateChanged = onZoomStateChanged
        self.onSingleTap = onSingleTap
        self.content = content()
    }

    private var scale: CGFloat {
        AISZoomTransform.clampedScale(baseScale * magnification)
    }

    var body: some View {
        GeometryReader { proxy in
            interactiveSurface(viewport: proxy.size)
        }
        .clipped()
        .onDisappear {
            onZoomStateChanged?(false)
        }
        .onChange(of: resetToken) {
            resetTransform()
        }
    }

    @ViewBuilder
    private func interactiveSurface(viewport: CGSize) -> some View {
        let surface = content
                .frame(width: viewport.width, height: viewport.height)
                .scaleEffect(scale)
                .offset(displayOffset(viewport: viewport))
                .contentShape(Rectangle())
                .simultaneousGesture(magnifyGesture(viewport: viewport))
                .simultaneousGesture(tapGesture())

        if AISZoomTransform.isZoomed(baseScale) {
            // 只有放大后才接管单指拖动，1 倍状态将横向手势留给外层分页。
            surface.simultaneousGesture(dragGesture(viewport: viewport))
        } else {
            surface
        }
    }

    private func displayOffset(viewport: CGSize) -> CGSize {
        AISZoomTransform.clampedOffset(
            CGSize(
                width: baseOffset.width + translation.width,
                height: baseOffset.height + translation.height
            ),
            scale: scale,
            viewport: viewport
        )
    }

    private func magnifyGesture(viewport: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in
                state = value.magnification
            }
            .onChanged { value in
                onZoomStateChanged?(
                    AISZoomTransform.clampedScale(
                        baseScale * value.magnification
                    ) > 1
                )
            }
            .onEnded { value in
                baseScale = AISZoomTransform.clampedScale(
                    baseScale * value.magnification
                )
                baseOffset = AISZoomTransform.clampedOffset(
                    baseOffset,
                    scale: baseScale,
                    viewport: viewport
                )
                if !AISZoomTransform.isZoomed(baseScale) {
                    baseOffset = .zero
                }
                onZoomStateChanged?(
                    AISZoomTransform.isZoomed(baseScale)
                )
            }
    }

    private func dragGesture(viewport: CGSize) -> some Gesture {
        DragGesture()
            .updating($translation) { value, state, _ in
                guard AISZoomTransform.isZoomed(scale) else { return }
                state = value.translation
            }
            .onEnded { value in
                guard AISZoomTransform.isZoomed(scale) else {
                    baseOffset = .zero
                    return
                }
                baseOffset = AISZoomTransform.clampedOffset(
                    CGSize(
                        width: baseOffset.width + value.translation.width,
                        height: baseOffset.height + value.translation.height
                    ),
                    scale: scale,
                    viewport: viewport
                )
            }
    }

    private func tapGesture() -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.snappy) {
                    if AISZoomTransform.isZoomed(baseScale) {
                        resetTransform()
                    } else {
                        baseScale = 2
                        baseOffset = .zero
                        onZoomStateChanged?(true)
                    }
                }
            }
            .exclusively(
                before: TapGesture(count: 1)
                    .onEnded {
                        onSingleTap?()
                    }
            )
    }

    private func resetTransform() {
        baseScale = 1
        baseOffset = .zero
        onZoomStateChanged?(false)
    }
}

struct AISZoomableImagePage: View {
    let url: URL
    var title: String? = nil
    var resetToken: String? = nil
    var cacheModule: AISImageCacheModule = .galleryTemplates
    var requiresAuthentication = false
    var onZoomStateChanged: ((Bool) -> Void)?
    var onSingleTap: (() -> Void)?

    @Environment(SessionStore.self) private var session
    @State private var authenticatedImage: UIImage?
    @State private var authenticatedImageFailed = false

    var body: some View {
        AISZoomableMediaSurface(
            resetToken: resetToken,
            onZoomStateChanged: onZoomStateChanged,
            onSingleTap: onSingleTap
        ) {
            imageContent
        }
        .task(id: requiresAuthentication ? url : nil) {
            guard requiresAuthentication else { return }
            await loadAuthenticatedImage()
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if requiresAuthentication {
            if let authenticatedImage {
                Image(uiImage: authenticatedImage)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(
                        title ?? String(localized: "image.viewer.image")
                    )
            } else if authenticatedImageFailed {
                unavailableContent
            } else {
                ProgressView().tint(.white)
            }
        } else {
            AISCachedAsyncImage(
                url: url,
                preset: .original,
                module: cacheModule
            ) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(
                            title ?? String(localized: "image.viewer.image")
                        )
                case .empty:
                    ProgressView().tint(.white)
                default:
                    unavailableContent
                }
            }
        }
    }

    private var unavailableContent: some View {
        ContentUnavailableView(
            "image.viewer.unavailable",
            systemImage: "photo.badge.exclamationmark"
        )
        .foregroundStyle(.white)
    }

    @MainActor
    private func loadAuthenticatedImage() async {
        authenticatedImage = nil
        authenticatedImageFailed = false
        do {
            guard let token = await session.validAccessToken() else {
                throw APIError.rejected(
                    message: String(localized: "auth.required")
                )
            }
            let data = try await APIClient().download(
                url,
                accessToken: token
            )
            guard !Task.isCancelled, let image = UIImage(data: data) else {
                throw APIError.missingData
            }
            authenticatedImage = image
        } catch {
            guard !Task.isCancelled else { return }
            authenticatedImageFailed = true
        }
    }
}

private struct AISZoomableVideoPage: View {
    let item: AISMediaViewerItem
    let isActive: Bool
    let resetToken: String?
    let onZoomStateChanged: ((Bool) -> Void)?

    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var player: AVPlayer?
    @State private var localPlaybackURL: URL?
    @State private var playRequested = false
    @State private var isPreparing = false
    @State private var errorMessage: String?

    var body: some View {
        AISZoomableMediaSurface(
            resetToken: resetToken,
            onZoomStateChanged: onZoomStateChanged
        ) {
            ZStack {
                Color.black
                if let player {
                    VideoPlayer(player: player)
                        .accessibilityLabel(
                            item.title
                                ?? String(localized: "media.viewer.video")
                        )
                } else {
                    poster
                }

                if isPreparing {
                    ProgressView()
                        .tint(.white)
                        .padding(18)
                        .background(.ultraThinMaterial, in: Circle())
                } else if player == nil {
                    Button {
                        playRequested = true
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .frame(width: 74, height: 74)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("media.viewer.play")
                }

                if let errorMessage {
                    VStack {
                        Spacer()
                        Label(
                            errorMessage,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(.bottom, 28)
                    }
                }
            }
        }
        .task(id: playRequested) {
            guard playRequested else { return }
            await prepareAndPlay()
        }
        .onChange(of: isActive) {
            if !isActive {
                player?.pause()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                player?.pause()
            }
        }
        .onDisappear {
            player?.pause()
            cleanupPlaybackFile()
        }
    }

    @ViewBuilder
    private var poster: some View {
        if let thumbnailURL = item.thumbnailURL {
            AISCachedAsyncImage(
                url: thumbnailURL,
                preset: .detail,
                module: item.cacheModule
            ) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFit()
                case .empty:
                    ProgressView().tint(.white)
                default:
                    videoPlaceholder
                }
            }
        } else {
            videoPlaceholder
        }
    }

    private var videoPlaceholder: some View {
        ContentUnavailableView(
            "media.viewer.video_cover_unavailable",
            systemImage: "play.rectangle.fill"
        )
        .foregroundStyle(.white)
    }

    @MainActor
    private func prepareAndPlay() async {
        guard !isPreparing else { return }
        errorMessage = nil
        isPreparing = true
        defer { isPreparing = false }
        do {
            let playbackURL: URL
            if item.requiresAuthentication {
                guard let token = await session.validAccessToken() else {
                    throw APIError.rejected(
                        message: String(localized: "auth.required")
                    )
                }
                playbackURL = try await APIClient().downloadFile(
                    item.originalURL,
                    accessToken: token
                )
                localPlaybackURL = playbackURL
            } else {
                playbackURL = item.originalURL
            }
            let asset = AVURLAsset(url: playbackURL)
            guard try await asset.load(.isPlayable) else {
                throw APIError.invalidResponse
            }
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            self.player = player
            player.play()
        } catch {
            playRequested = false
            errorMessage = error.localizedDescription
        }
    }

    private func cleanupPlaybackFile() {
        guard let localPlaybackURL else { return }
        try? FileManager.default.removeItem(at: localPlaybackURL)
        self.localPlaybackURL = nil
    }
}

struct AISMediaGalleryViewer: View {
    let items: [AISMediaViewerItem]

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var selectedID: String?
    @State private var zoomedItemID: String?
    @State private var controlsVisible = true
    @State private var dismissalOffset: CGFloat = 0
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var noticeMessage: String?

    init(items: [AISMediaViewerItem], initialItemID: String? = nil) {
        self.items = items
        _selectedID = State(
            initialValue: AISMediaViewerCollection.resolvedID(
                preferredID: initialItemID,
                items: items
            )
        )
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(dismissalBackgroundOpacity)
                .ignoresSafeArea()

            if items.isEmpty {
                ContentUnavailableView(
                    "image.viewer.unavailable",
                    systemImage: "photo.badge.exclamationmark"
                )
                .foregroundStyle(.white)
            } else {
                TabView(selection: $selectedID) {
                    ForEach(items) { item in
                        mediaPage(item)
                            .tag(Optional(item.id))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .scrollDisabled(zoomedItemID == selectedID)
                .offset(y: dismissalOffset)
            }

            controls
                .opacity(controlsVisible ? controlsOpacity : 0)
                .allowsHitTesting(controlsVisible)
        }
        .statusBarHidden()
        .simultaneousGesture(dismissGesture)
        .onChange(of: selectedID) {
            zoomedItemID = nil
            dismissalOffset = 0
        }
        .onChange(of: items) {
            selectedID = AISMediaViewerCollection.resolvedID(
                preferredID: selectedID,
                items: items
            )
            zoomedItemID = nil
            dismissalOffset = 0
        }
        .alert(
            "common.error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("common.done", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "common.done",
            isPresented: Binding(
                get: { noticeMessage != nil },
                set: { if !$0 { noticeMessage = nil } }
            )
        ) {
            Button("common.done", role: .cancel) {}
        } message: {
            Text(noticeMessage ?? "")
        }
    }

    @ViewBuilder
    private func mediaPage(_ item: AISMediaViewerItem) -> some View {
        switch item.kind {
        case .image:
            AISZoomableImagePage(
                url: item.originalURL,
                title: item.title,
                resetToken: selectedID,
                cacheModule: item.cacheModule,
                requiresAuthentication: item.requiresAuthentication,
                onZoomStateChanged: { isZoomed in
                    guard selectedID == item.id else { return }
                    zoomedItemID = isZoomed ? item.id : nil
                },
                onSingleTap: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        controlsVisible.toggle()
                    }
                }
            )
        case .video:
            AISZoomableVideoPage(
                item: item,
                isActive: selectedID == item.id,
                resetToken: selectedID,
                onZoomStateChanged: { isZoomed in
                    guard selectedID == item.id else { return }
                    zoomedItemID = isZoomed ? item.id : nil
                }
            )
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .frame(width: 60, height: 60)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel("common.done")

                Spacer()

                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .frame(width: 60, height: 60)
                } else if let selectedItem {
                    Button {
                        save(selectedItem)
                    } label: {
                        Image(systemName: "photo.badge.arrow.down")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityLabel("media.viewer.save")
                }
            }

            Spacer()

            Text("media.viewer.hint")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 14)
                )

            if items.count > 1 {
                Text(positionText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                thumbnailStrip
            }
        }
        .safeAreaPadding(.top, 8)
        .padding(.horizontal, 4)
        .padding(.bottom, 16)
    }

    private var controlsOpacity: Double {
        max(0.25, 1 - Double(dismissalOffset / 260))
    }

    private var dismissalBackgroundOpacity: Double {
        max(0.42, 1 - Double(dismissalOffset / 360))
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard canDragToDismiss,
                      AISMediaDismissalGesture.isDownwardVerticalDrag(
                        value.translation
                      ) else {
                    dismissalOffset = 0
                    return
                }
                dismissalOffset = value.translation.height
            }
            .onEnded { value in
                guard canDragToDismiss else {
                    resetDismissalOffset()
                    return
                }
                if AISMediaDismissalGesture.shouldDismiss(
                    translation: value.translation,
                    predictedTranslation: value.predictedEndTranslation,
                    isZoomed: zoomedItemID == selectedID
                ) {
                    dismiss()
                } else {
                    resetDismissalOffset()
                }
            }
    }

    private var canDragToDismiss: Bool {
        selectedItem?.kind == .image && zoomedItemID != selectedID
    }

    private func resetDismissalOffset() {
        withAnimation(.snappy) {
            dismissalOffset = 0
        }
    }

    private var selectedItem: AISMediaViewerItem? {
        guard let selectedID else { return nil }
        return items.first { $0.id == selectedID }
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(items) { item in
                        Button {
                            withAnimation(.snappy) {
                                selectedID = item.id
                            }
                        } label: {
                            mediaThumbnail(item)
                                .frame(width: 58, height: 58)
                                .background(Color.white.opacity(0.12))
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 9,
                                        style: .continuous
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius: 9,
                                        style: .continuous
                                    )
                                    .stroke(
                                        selectedID == item.id
                                            ? AISTheme.accent
                                            : Color.white.opacity(0.25),
                                        lineWidth:
                                            selectedID == item.id ? 3 : 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .accessibilityLabel(
                            thumbnailAccessibilityLabel(for: item)
                        )
                        .accessibilityAddTraits(
                            selectedID == item.id ? .isSelected : []
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: 560)
            .onChange(of: selectedID) {
                guard let selectedID else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func mediaThumbnail(_ item: AISMediaViewerItem) -> some View {
        if let thumbnailURL = item.thumbnailURL {
            AISCachedAsyncImage(
                url: thumbnailURL,
                preset: .thumbnail,
                module: item.cacheModule
            ) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .empty:
                    ProgressView().tint(.white)
                default:
                    mediaPlaceholder(item)
                }
            }
        } else {
            mediaPlaceholder(item)
        }
    }

    private func mediaPlaceholder(_ item: AISMediaViewerItem) -> some View {
        Image(
            systemName: item.kind == .video
                ? "play.rectangle.fill" : "photo"
        )
        .foregroundStyle(.white.opacity(0.7))
    }

    private var positionText: String {
        String.localizedStringWithFormat(
            String(localized: "image.viewer.position"),
            AISMediaViewerCollection.position(
                selectedID: selectedID,
                items: items
            ),
            items.count
        )
    }

    private func thumbnailAccessibilityLabel(
        for item: AISMediaViewerItem
    ) -> String {
        let position = AISMediaViewerCollection.position(
            selectedID: item.id,
            items: items
        )
        return String.localizedStringWithFormat(
            String(localized: "image.viewer.thumbnail"),
            position,
            items.count
        )
    }

    private func save(_ item: AISMediaViewerItem) {
        guard !isSaving else { return }
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                let status = await PHPhotoLibrary.requestAuthorization(
                    for: .addOnly
                )
                guard status == .authorized || status == .limited else {
                    throw APIError.rejected(
                        message: String(
                            localized: "image.viewer.photos_denied"
                        )
                    )
                }
                let token = item.requiresAuthentication
                    ? await session.validAccessToken()
                    : nil
                if item.requiresAuthentication && token == nil {
                    throw APIError.rejected(
                        message: String(localized: "auth.required")
                    )
                }
                switch item.kind {
                case .image:
                    let data: Data
                    if item.requiresAuthentication {
                        data = try await APIClient().download(
                            item.originalURL,
                            accessToken: token
                        )
                    } else {
                        guard let request = AISImageURLBuilder.resolve(
                            from: item.originalURL,
                            preset: .original
                        ) else {
                            throw APIError.missingData
                        }
                        data = try await AISImageCache.shared.data(
                            for: request.url,
                            module: item.cacheModule,
                            preset: .original,
                            request: request
                        )
                    }
                    try await AISPhotoLibraryWriter.savePhoto(data)
                case .video:
                    let fileURL = try await APIClient().downloadFile(
                        item.originalURL,
                        accessToken: token
                    )
                    defer { try? FileManager.default.removeItem(at: fileURL) }
                    try await AISPhotoLibraryWriter.saveVideo(at: fileURL)
                }
                noticeMessage = String(
                    localized: item.kind == .video
                        ? "media.viewer.video_saved"
                        : "image.viewer.saved"
                )
            } catch let error as APIError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = String(
                    localized: item.kind == .video
                        ? "media.viewer.video_save_failed"
                        : "image.viewer.save_failed"
                )
            }
        }
    }
}
