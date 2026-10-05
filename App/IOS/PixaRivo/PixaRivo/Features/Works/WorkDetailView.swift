import SwiftUI

struct WorkDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session

    @State private var job: TaskJob
    @State private var isLoading = false
    @State private var isDeleting = false
    @State private var hasBeenDeleted = false
    @State private var loadRevision = 0
    @State private var confirmsDeletion = false
    @State private var errorMessage: String?
    @State private var previewTarget: WorkDetailPreviewTarget?
    @State private var sharePayload: PixaSharePayload?
    @State private var isPreparingShare = false
    @State private var showsShareError = false

    let onDeleted: () -> Void

    init(job: TaskJob, onDeleted: @escaping () -> Void) {
        _job = State(initialValue: job)
        self.onDeleted = onDeleted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                artworkSection
                statusSection
                if !metadataItems.isEmpty { metadataSection }
                if let error = job.errorMessage?.nilIfEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(PixaTheme.paper.ignoresSafeArea())
        .navigationTitle("works.detail.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PixaShareButton(isPreparing: isPreparingShare) {
                    Task { await share() }
                }
                .disabled(job.mediaURL == nil || isPreparingShare)
                .opacity(job.mediaURL == nil ? 0.38 : 1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmsDeletion = true } label: {
                    if isDeleting { ProgressView().controlSize(.small) }
                    else { Image(systemName: "trash") }
                }
                .disabled(!canDelete || isLoading || isDeleting)
                .accessibilityLabel(Text("common.delete"))
            }
        }
        .task { await load() }
        .fullScreenCover(item: $previewTarget) { target in
            PixaArtworkPreview(url: target.url)
        }
        .sheet(item: $sharePayload) { payload in
            PixaActivityView(items: payload.items)
        }
        .confirmationDialog(
            "works.delete.title",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("common.delete", role: .destructive) {
                Task { await deleteWork() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("works.delete.message")
        }
        .alert(
            "common.error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("share.failed.title", isPresented: $showsShareError) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("share.failed.message")
        }
        .overlay(alignment: .top) {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(PixaTheme.accent)
                    Text("loading.work_detail.title")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 42)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().stroke(PixaTheme.line) }
                .padding(.top, 10)
                .allowsHitTesting(false)
            }
        }
    }

    private var artworkSection: some View {
        Button {
            if let url = job.mediaURL { previewTarget = WorkDetailPreviewTarget(url: url) }
        } label: {
            RemoteArtwork(
                url: job.mediaURL,
                aspectRatio: job.displayAspectRatio,
                preset: .detail,
                maximumPixelWidth: 1_600,
                contentMode: .fit,
                usesIntrinsicAspectRatio: true
            )
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if job.mediaURL != nil {
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
        .disabled(job.mediaURL == nil)
        .accessibilityLabel(Text("preview.open"))
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(statusText, systemImage: statusIcon)
                    .font(.headline)
                    .foregroundStyle(statusColor)
                Spacer()
                if job.pointCost > 0 {
                    Text(String.localizedStringWithFormat(
                        AppLanguage.localized("points.format"),
                        job.pointCost
                    ))
                    .font(.caption.bold())
                    .foregroundStyle(PixaTheme.accent)
                }
            }
            Text(job.title.nilIfEmpty ?? AppLanguage.localized("works.untitled"))
                .font(.title3.bold())
            if job.isActive {
                ProgressView(value: Double(job.progress), total: 100)
                    .tint(PixaTheme.accent)
                Text("\(job.progress)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if job.isGallery {
                Label("works.delete.unavailable_gallery", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if job.isActive {
                Label("works.delete.unavailable_active", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .pixaSurface()
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("works.detail.information").font(.headline)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                spacing: 10
            ) {
                ForEach(metadataItems) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Label(item.title, systemImage: item.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.value)
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

    private var metadataItems: [WorkMetadataItem] {
        var values: [WorkMetadataItem] = []
        if let width = job.pixelWidth, let height = job.pixelHeight {
            values.append(.init(id: "pixels", title: AppLanguage.localized("works.detail.pixel_size"), value: "\(width) × \(height) px", icon: "rectangle.expand.vertical"))
        } else if let resolution = job.resolution?.nilIfEmpty {
            values.append(.init(id: "resolution", title: AppLanguage.localized("works.detail.resolution"), value: resolution, icon: "sparkles.rectangle.stack"))
        }
        if let resolution = job.resolution?.nilIfEmpty,
           job.pixelWidth != nil, job.pixelHeight != nil {
            values.append(.init(id: "resolution", title: AppLanguage.localized("works.detail.resolution"), value: resolution, icon: "sparkles.rectangle.stack"))
        }
        if let bytes = job.fileSizeBytes, bytes > 0 {
            values.append(.init(id: "fileSize", title: AppLanguage.localized("works.detail.file_size"), value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file), icon: "doc"))
        }
        if let date = job.createdDate {
            values.append(.init(id: "createdAt", title: AppLanguage.localized("works.detail.created_at"), value: formattedDate(date), icon: "calendar.badge.plus"))
        }
        if let date = job.finishedDate {
            values.append(.init(id: "finishedAt", title: AppLanguage.localized("works.detail.finished_at"), value: formattedDate(date), icon: "calendar.badge.checkmark"))
        }
        if let seconds = job.generationDurationSeconds, seconds >= 0 {
            values.append(.init(id: "duration", title: AppLanguage.localized("works.detail.duration"), value: formattedDuration(seconds), icon: "clock"))
        }
        if let ratio = job.aspectRatio?.nilIfEmpty {
            values.append(.init(id: "ratio", title: AppLanguage.localized("works.detail.aspect_ratio"), value: ratio, icon: "aspectratio"))
        }
        return values
    }

    private var statusText: String {
        switch job.status.lowercased() {
        case "queued", "pending": AppLanguage.localized("status.queued")
        case "processing", "running": AppLanguage.localized("status.processing")
        case "succeeded", "completed": AppLanguage.localized("status.completed")
        case "failed": AppLanguage.localized("status.failed")
        case "cancelled", "canceled": AppLanguage.localized("status.cancelled")
        default: AppLanguage.localized("status.unknown")
        }
    }

    private var statusIcon: String {
        switch job.status.lowercased() {
        case "succeeded", "completed": "checkmark.circle.fill"
        case "failed": "exclamationmark.triangle.fill"
        case "cancelled", "canceled": "xmark.circle.fill"
        default: "clock.arrow.circlepath"
        }
    }

    private var statusColor: Color {
        switch job.status.lowercased() {
        case "succeeded", "completed": .green
        case "failed", "cancelled", "canceled": .red
        default: PixaTheme.accent
        }
    }

    private var canDelete: Bool {
        !job.isActive && !job.isGallery
    }

    private func formattedDuration(_ seconds: Int64) -> String {
        if seconds < 60 {
            return String.localizedStringWithFormat(AppLanguage.localized("works.detail.duration_seconds"), seconds)
        }
        return String.localizedStringWithFormat(AppLanguage.localized("works.detail.duration_minutes"), seconds / 60, seconds % 60)
    }

    private func formattedDate(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.locale = AppLanguage.locale
        return date.formatted(style)
    }

    private func load() async {
        guard let token = await session.validAccessToken() else { return }
        let revision = loadRevision
        isLoading = true
        defer {
            if revision == loadRevision {
                isLoading = false
            }
        }
        do {
            let loadedJob: TaskJob = try await APIClient().get(
                "/api/ais/jobs/\(job.id)",
                token: token,
                forceRefresh: true
            )
            guard revision == loadRevision, !isDeleting, !hasBeenDeleted else { return }
            job = loadedJob
        } catch {
            guard revision == loadRevision, !isDeleting, !hasBeenDeleted else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func share() async {
        guard !isPreparingShare, job.mediaURL != nil else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        sharePayload = await PixaShareService.prepare(
            title: job.title.nilIfEmpty ?? AppLanguage.localized("works.untitled"),
            description: job.shareDescription
                ?? AppLanguage.localized("share.work.description"),
            imageURL: job.mediaURL,
            source: .work
        )
        showsShareError = sharePayload == nil
    }

    private func deleteWork() async {
        guard !isDeleting,
              canDelete,
              let token = await session.validAccessToken() else { return }
        loadRevision += 1
        isDeleting = true
        isLoading = false
        errorMessage = nil
        defer { isDeleting = false }
        do {
            let _: String = try await APIClient().post(
                "/api/ais/jobs/delete",
                body: [job.id],
                token: token
            )
            hasBeenDeleted = true
            dismiss()
            await Task.yield()
            onDeleted()
        } catch {
            guard !hasBeenDeleted else { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct WorkMetadataItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let icon: String
}

private struct WorkDetailPreviewTarget: Identifiable {
    let id = UUID()
    let url: URL
}
