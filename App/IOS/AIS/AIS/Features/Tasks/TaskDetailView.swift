import Observation
import Photos
import SwiftUI
import UIKit

@MainActor
@Observable
final class TaskDetailViewModel {
    private let api = APIClient()

    private(set) var job: AISTaskJob
    private(set) var isLoading = false
    private(set) var isPerformingAction = false
    var errorMessage: String?
    var noticeMessage: String?
    var exportPayload: AISSharePayload?

    init(job: AISTaskJob) {
        self.job = job
    }

    func load(session: SessionStore) async {
        guard let token = await session.validAccessToken() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            job = try await api.get(
                "/api/ais/jobs/\(job.id)",
                accessToken: token
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveToPhotos(session: SessionStore) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                throw APIError.rejected(
                    message: String(localized: "tasks.detail.photos_denied")
                )
            }
            if job.creationKind == .video {
                let fileURL = try await resultFile(session: session)
                defer { try? FileManager.default.removeItem(at: fileURL) }
                try await AISPhotoLibraryWriter.saveVideo(at: fileURL)
                noticeMessage = String(localized: "media.viewer.video_saved")
            } else {
                let data = try await resultData(session: session)
                try await AISPhotoLibraryWriter.savePhoto(data)
                noticeMessage = String(localized: "tasks.detail.saved")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func prepareFileExport(session: SessionStore) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            if job.creationKind == .video {
                let downloadedURL = try await resultFile(session: session)
                let downloadedExtension =
                    downloadedURL.pathExtension.nilIfEmpty
                let validDownloadedExtension = downloadedExtension == "bin"
                    ? nil
                    : downloadedExtension
                let fileExtension = validDownloadedExtension
                    ?? job.resultMediaURL?.pathExtension.nilIfEmpty
                    ?? "mp4"
                let exportURL = FileManager.default.temporaryDirectory
                    .appending(path: "AIS-\(job.id).\(fileExtension)")
                try? FileManager.default.removeItem(at: exportURL)
                try FileManager.default.moveItem(
                    at: downloadedURL,
                    to: exportURL
                )
                exportPayload = AISSharePayload(items: [exportURL])
                return
            }
            let data = try await resultData(session: session)
            let fileExtension = data.starts(
                with: [0x89, 0x50, 0x4E, 0x47]
            ) ? "png" : "jpg"
            let url = FileManager.default.temporaryDirectory.appending(
                path: "AIS-\(job.id).\(fileExtension)"
            )
            try data.write(to: url, options: .atomic)
            exportPayload = AISSharePayload(items: [url])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func enableShare(session: SessionStore) async throws -> AISSharedJob {
        guard let token = await session.validAccessToken() else {
            throw APIError.rejected(message: String(localized: "auth.required"))
        }
        return try await api.post(
            "/api/ais/jobs/\(job.id)/share",
            body: [String: String](),
            accessToken: token
        )
    }

    private func resultData(session: SessionStore) async throws -> Data {
        guard let url = job.resultMediaURL else {
            throw APIError.missingData
        }
        guard let originalURL = AISImageURLBuilder.url(
            from: url,
            preset: .original
        ) else {
            throw APIError.missingData
        }
        let token = requiresAuthentication(for: originalURL)
            ? await session.validAccessToken()
            : nil
        return try await api.download(originalURL, accessToken: token)
    }

    private func resultFile(session: SessionStore) async throws -> URL {
        guard let url = job.resultMediaURL else {
            throw APIError.missingData
        }
        let token = requiresAuthentication(for: url)
            ? await session.validAccessToken()
            : nil
        return try await api.downloadFile(url, accessToken: token)
    }

    private func requiresAuthentication(for url: URL) -> Bool {
        url.host == AppEnvironment.current.apiBaseURL.host
            && url.path.hasPrefix("/api/")
    }
}

struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session

    @State private var model: TaskDetailViewModel
    @State private var confirmsDeletion = false
    @State private var sharePayload: AISSharePayload?
    @State private var mediaViewerRoute: AISMediaViewerRoute?
    @State private var isPreparingShare = false

    let estimateSeconds: Int?
    let onDeleted: () -> Void
    let onContinueEditing: ((AISTaskJob) -> Void)?

    init(
        job: AISTaskJob,
        estimateSeconds: Int?,
        onDeleted: @escaping () -> Void,
        onContinueEditing: ((AISTaskJob) -> Void)?
    ) {
        _model = State(initialValue: TaskDetailViewModel(job: job))
        self.estimateSeconds = estimateSeconds
        self.onDeleted = onDeleted
        self.onContinueEditing = onContinueEditing
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    resultSection
                    statusSection
                    if !model.job.inputMaterialURLs.isEmpty {
                        inputSection
                    }
                    requirementSection
                    if memoryContext != nil {
                        memoryContextSection
                    }
                    if !resultMetadataItems.isEmpty {
                        resultMetadataSection
                    }
                    actionSection
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .background(AISPageBackground())
            .navigationTitle("tasks.detail.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        confirmsDeletion = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(model.job.isActive)
                }
            }
            .task {
                await model.load(session: session)
            }
            .sheet(item: $sharePayload) { payload in
                AISActivityView(items: payload.items)
            }
            .sheet(item: $model.exportPayload) { payload in
                AISActivityView(items: payload.items)
            }
            .fullScreenCover(item: $mediaViewerRoute) { route in
                AISMediaGalleryViewer(
                    items: mediaViewerItems,
                    initialItemID: route.id
                )
                .environment(session)
            }
            .alert(
                "tasks.detail.delete.title",
                isPresented: $confirmsDeletion
            ) {
                Button("common.cancel", role: .cancel) {}
                Button("common.delete", role: .destructive) {
                    Task { await deleteTask() }
                }
            } message: {
                Text("tasks.detail.delete.message")
            }
            .alert(
                "common.error",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .alert(
                "common.done",
                isPresented: Binding(
                    get: { model.noticeMessage != nil },
                    set: { if !$0 { model.noticeMessage = nil } }
                )
            ) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text(model.noticeMessage ?? "")
            }
        }
    }

    private var resultSection: some View {
        Group {
            if model.job.resultMediaURL != nil {
                ZStack {
                    if let coverURL = model.job.mediaURL {
                        AISCachedAsyncImage(
                            url: coverURL,
                            preset: .detail,
                            module: .tasks
                        ) { phase in
                            switch phase {
                            case let .success(image):
                                image.resizable().scaledToFit()
                            case .empty:
                                ProgressView()
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: 260
                                    )
                            default:
                                resultPlaceholder
                            }
                        }
                    } else {
                        resultPlaceholder
                    }

                    if model.job.creationKind == .video {
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
                .background(.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .contentShape(Rectangle())
                .onTapGesture {
                    presentMedia(id: "result")
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("media.viewer.open_hint")
            } else {
                ContentUnavailableView(
                    model.job.isActive
                        ? "tasks.detail.processing"
                        : "tasks.detail.result_unavailable",
                    systemImage: model.job.isActive
                        ? "clock.arrow.circlepath"
                        : "photo.badge.exclamationmark"
                )
                .frame(maxWidth: .infinity, minHeight: 220)
                .aisSurface(cornerRadius: 24)
            }
        }
    }

    private var resultPlaceholder: some View {
        ContentUnavailableView(
            model.job.creationKind == .video
                ? "media.viewer.video_cover_unavailable"
                : "tasks.detail.result_unavailable",
            systemImage: model.job.creationKind == .video
                ? "play.rectangle.fill"
                : "photo.badge.exclamationmark"
        )
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(statusTitle, systemImage: statusIcon)
                    .font(.headline)
                Spacer()
                if model.job.pointCost > 0 {
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "tasks.points"),
                            model.job.pointCost
                        )
                    )
                    .font(.caption.weight(.semibold))
                }
            }
            ProgressView(value: Double(model.job.progress), total: 100)
                .tint(AISTheme.accent)
            if model.job.isActive {
                if AISTaskDurationPresentation.isQueued(model.job.status) {
                    Text("tasks.queued")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Group {
                            switch AISTaskDurationPresentation.resolve(
                                status: model.job.status,
                                startedAt: model.job.startedDate,
                                estimateSeconds: estimateSeconds,
                                now: context.date
                            ) {
                            case let .remaining(seconds):
                                Text(
                                    String.localizedStringWithFormat(
                                        String(localized: "tasks.remaining"),
                                        AISDurationTextFormatter.countdown(
                                            seconds: seconds
                                        )
                                    )
                                )
                            case .overdue:
                                Text("tasks.estimate.overdue")
                            case .queued:
                                Text("tasks.queued")
                            case .unavailable:
                                EmptyView()
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            if model.job.status.lowercased() == "failed" {
                Label(
                    model.job.errorMessage
                        ?? String(localized: "tasks.detail.failed_default"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
                Text("tasks.detail.refund")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .aisSurface(cornerRadius: 20)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("tasks.detail.inputs", systemImage: "photo.stack")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(
                        Array(model.job.inputMaterialURLs.enumerated()),
                        id: \.offset
                    ) { index, url in
                        Button {
                            presentMedia(id: "input:\(index)")
                        } label: {
                            AISCachedAsyncImage(
                                url: url,
                                preset: .thumbnail,
                                module: .tasks
                            ) { phase in
                                if case let .success(image) = phase {
                                    image.resizable().scaledToFill()
                                } else {
                                    ProgressView()
                                }
                            }
                            .frame(width: 108, height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("image.viewer.open_hint")
                    }
                }
            }
        }
        .padding(18)
        .aisSurface(cornerRadius: 20)
    }

    private var requirementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("tasks.detail.specification", systemImage: "doc.text")
                .font(.headline)
            Text(model.job.userRequirement.isEmpty ? "—" : model.job.userRequirement)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LabeledContent("tasks.detail.type", value: localizedJobType)
            LabeledContent("tasks.detail.created_at") {
                Text(model.job.formattedCreationTime)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("tasks.detail.number") {
                Text(model.job.id)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .aisSurface(cornerRadius: 20)
    }

    private var memoryContext: AISMemoryContextSnapshot? {
        guard let input = model.job.inputJSON,
              let data = input.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let rawContext = object["MemoryContext"] ?? object["memoryContext"],
              JSONSerialization.isValidJSONObject(rawContext),
              let contextData = try? JSONSerialization.data(withJSONObject: rawContext)
        else { return nil }
        return try? JSONDecoder().decode(
            AISMemoryContextSnapshot.self,
            from: contextData
        )
    }

    private var memoryContextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("tasks.detail.memory_context", systemImage: "brain.head.profile")
                .font(.headline)
            if let context = memoryContext {
                ForEach(context.applied) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.content ?? item.preferenceKey ?? item.id)
                            .font(.subheadline)
                        Text("tasks.detail.memory_applied")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                ForEach(context.overridden) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.content ?? item.preferenceKey ?? item.id)
                            .font(.subheadline)
                        Text(item.decisionReason ?? String(localized: "tasks.detail.memory_overridden"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(18)
        .aisSurface(cornerRadius: 20)
    }

    private var resultMetadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("tasks.detail.result_info", systemImage: "info.circle")
                .font(.headline)
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 130), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(resultMetadataItems) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AISTheme.accentSecondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        AISTheme.line.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
            }
        }
        .padding(18)
        .aisSurface(cornerRadius: 20)
    }

    private var resultMetadataItems: [TaskResultMetadataItem] {
        var items: [TaskResultMetadataItem] = []
        if let value = model.job.aspectRatio?.nilIfEmpty {
            items.append(
                TaskResultMetadataItem(
                    id: "aspectRatio",
                    title: String(localized: "tasks.detail.ratio"),
                    value: value
                )
            )
        }
        if let value = model.job.resolution?.nilIfEmpty {
            items.append(
                TaskResultMetadataItem(
                    id: "resolution",
                    title: String(localized: "tasks.detail.resolution"),
                    value: value
                )
            )
        }
        if let bytes = model.job.fileSizeBytes, bytes > 0 {
            items.append(
                TaskResultMetadataItem(
                    id: "fileSize",
                    title: String(localized: "tasks.detail.file_size"),
                    value: ByteCountFormatter.string(
                        fromByteCount: bytes,
                        countStyle: .file
                    )
                )
            )
        }
        if let seconds = model.job.generationDurationSeconds, seconds >= 0 {
            items.append(
                TaskResultMetadataItem(
                    id: "duration",
                    title: String(localized: "tasks.detail.duration"),
                    value: formatDuration(seconds)
                )
            )
        }
        return items
    }

    @ViewBuilder
    private var actionSection: some View {
        if model.job.resultMediaURL != nil {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        Task { await model.saveToPhotos(session: session) }
                    } label: {
                        Label(
                            "tasks.detail.save_photos",
                            systemImage: "photo.badge.arrow.down"
                        )
                        .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AISTheme.accent)

                    Button {
                        Task { await model.prepareFileExport(session: session) }
                    } label: {
                        Label("tasks.detail.save_files", systemImage: "folder")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                    .tint(AISTheme.accent)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await prepareShare() }
                    } label: {
                        if isPreparingShare {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity, minHeight: 46)
                        } else {
                            Label(
                                "gallery.share",
                                systemImage: "square.and.arrow.up"
                            )
                            .frame(maxWidth: .infinity, minHeight: 46)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AISTheme.accentSecondary)

                    if let onContinueEditing {
                        Button {
                            onContinueEditing(model.job)
                            dismiss()
                        } label: {
                            Label(
                                "tasks.detail.continue_editing",
                                systemImage: "slider.horizontal.3"
                            )
                            .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.bordered)
                        .tint(AISTheme.accentSecondary)
                    }
                }
            }
            .disabled(model.isPerformingAction || isPreparingShare)
        }
    }

    private var statusTitle: LocalizedStringKey {
        switch model.job.status.lowercased() {
        case "succeeded", "completed": "tasks.status.succeeded"
        case "failed": "tasks.status.failed"
        case "cancelled", "canceled": "tasks.status.cancelled"
        case "running", "processing": "tasks.status.running"
        default: "tasks.status.queued"
        }
    }

    private var statusIcon: String {
        switch model.job.status.lowercased() {
        case "succeeded", "completed": "checkmark.circle.fill"
        case "failed": "exclamationmark.triangle.fill"
        default: "clock.arrow.circlepath"
        }
    }

    private var localizedJobType: String {
        switch model.job.jobType.lowercased() {
        case "image_generate": String(localized: "tasks.type.image")
        case "image_edit": String(localized: "tasks.type.edit")
        case "style_template_generate": String(localized: "tasks.type.template")
        case "video_generate": String(localized: "tasks.type.video")
        default: String(localized: "tasks.type.other")
        }
    }

    private func prepareShare() async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        do {
            let shared = try await model.enableShare(session: session)
            sharePayload = await AISShareService.prepare(
                jobID: model.job.id,
                title: shared.title.isEmpty
                    ? String(localized: "tasks.share.default_title")
                    : shared.title,
                description: shared.description,
                imageURL: shared.displayURL ?? model.job.mediaURL
            )
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private var mediaViewerItems: [AISMediaViewerItem] {
        var items: [AISMediaViewerItem] = []
        if let resultURL = model.job.resultMediaURL {
            items.append(
                AISMediaViewerItem(
                    id: "result",
                    kind: model.job.creationKind == .video
                        ? .video : .image,
                    originalURL: resultURL,
                    thumbnailURL: model.job.mediaURL,
                    title: model.job.title.nilIfEmpty,
                    requiresAuthentication: requiresAuthentication(
                        for: resultURL
                    ),
                    cacheModule: .tasks
                )
            )
        }
        items.append(
            contentsOf: model.job.inputMaterialURLs.enumerated().map {
                AISMediaViewerItem(
                    id: "input:\($0.offset)",
                    originalURL: $0.element,
                    requiresAuthentication: requiresAuthentication(
                        for: $0.element
                    ),
                    cacheModule: .tasks
                )
            }
        )
        return items
    }

    private func requiresAuthentication(for url: URL) -> Bool {
        url.host == AppEnvironment.current.apiBaseURL.host
            && url.path.hasPrefix("/api/")
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

    private func formatDuration(_ seconds: Int64) -> String {
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

    private func deleteTask() async {
        guard let token = await session.validAccessToken() else { return }
        do {
            let _: String = try await APIClient().post(
                "/api/ais/jobs/delete",
                body: [model.job.id],
                accessToken: token
            )
            onDeleted()
            dismiss()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct TaskResultMetadataItem: Identifiable {
    let id: String
    let title: String
    let value: String
}
