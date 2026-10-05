import SwiftUI
import UIKit

struct NetworkDiagnosticsView: View {
    @State private var diagnostics = NetworkDiagnosticsStore.shared
    @State private var exportFileURL: URL?
    @State private var cacheStatistics: AISImageCacheStatistics?

    var body: some View {
        List {
            Section {
                LabeledContent(
                    "diagnostics.version",
                    value: AppEnvironment.releaseLabel
                )
                LabeledContent(
                    "diagnostics.api",
                    value: AppEnvironment.current.apiBaseURL.host
                        ?? AppEnvironment.current.apiBaseURL.absoluteString
                )
                LabeledContent("API Node", value: AppAPIRoutingSnapshot.endpointID)
                LabeledContent("Routing Version", value: "v\(AppAPIRoutingSnapshot.configVersion)")
                LabeledContent("Routing Cache", value: AppAPIRoutingSnapshot.isStale ? "stale" : "fresh")
                LabeledContent(
                    "diagnostics.cache.total",
                    value: formattedCacheSize
                )
                if let updatedAt = cacheStatistics?.updatedAt {
                    LabeledContent(
                        "diagnostics.updated_at",
                        value: updatedAt.formatted(
                            date: .omitted,
                            time: .standard
                        )
                    )
                }
            }

            Section("diagnostics.viewers") {
                NavigationLink {
                    NetworkRequestDiagnosticsView()
                } label: {
                    DiagnosticViewerRow(
                        title: "diagnostics.network.title",
                        subtitle: String.localizedStringWithFormat(
                            String(localized: "diagnostics.count"),
                            diagnostics.entries.count
                        ),
                        systemImage: "network",
                        tint: AISTheme.accentSecondary
                    )
                }

                NavigationLink {
                    ImageCacheDiagnosticsView()
                } label: {
                    DiagnosticViewerRow(
                        title: "diagnostics.image.title",
                        subtitle: String.localizedStringWithFormat(
                            String(localized: "diagnostics.count"),
                            diagnostics.imageCacheEntries.count
                        ),
                        systemImage: "photo.stack",
                        tint: AISTheme.accentWarm
                    )
                }
            }

            Section {
                Button("Refresh API Routing") {
                    Task { await AppAPIRouter.shared.refresh(force: true) }
                }
                if let fileURL = exportFileURL {
                    ShareLink(
                        item: fileURL,
                        preview: SharePreview(
                            fileURL.lastPathComponent,
                            image: Image(systemName: "doc.text.fill")
                        )
                    ) {
                        Label(
                            "diagnostics.share_file",
                            systemImage: "doc.badge.arrow.up"
                        )
                    }
                } else {
                    ShareLink(item: diagnostics.exportText) {
                        Label(
                            "diagnostics.share",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                }

                Button(role: .destructive) {
                    diagnostics.clear()
                    exportFileURL = nil
                } label: {
                    Label("diagnostics.clear", systemImage: "trash")
                }
                .disabled(
                    diagnostics.entries.isEmpty
                        && diagnostics.imageCacheEntries.isEmpty
                        && diagnostics.systemLogs.isEmpty
                )
            } footer: {
                Text("diagnostics.privacy")
            }
        }
        .navigationTitle("diagnostics.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let fileURL = diagnostics.generateLogFile()
            async let statistics = AISImageCache.shared.statistics()
            exportFileURL = await fileURL
            cacheStatistics = await statistics
        }
    }

    private var formattedCacheSize: String {
        guard let byteCount = cacheStatistics?.physicalByteCount else {
            return "—"
        }
        return ByteCountFormatter.string(
            fromByteCount: byteCount,
            countStyle: .file
        )
    }
}

private struct NetworkRequestDiagnosticsView: View {
    @State private var diagnostics = NetworkDiagnosticsStore.shared
    @State private var copiedEntryID: UUID?

    var body: some View {
        List {
            Section("diagnostics.requests") {
                if diagnostics.entries.isEmpty {
                    ContentUnavailableView(
                        "diagnostics.empty",
                        systemImage: "network",
                        description: Text("diagnostics.empty.description")
                    )
                } else {
                    ForEach(diagnostics.entries) { entry in
                        Button {
                            copy(entry)
                        } label: {
                            diagnosticRow(entry)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("diagnostics.copy.hint")
                    }
                }
            }
        }
        .navigationTitle("diagnostics.network.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func diagnosticRow(
        _ entry: NetworkDiagnosticEntry
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(entry.method)
                    .font(.caption.monospaced().bold())
                Text(entry.statusCode.map(String.init) ?? "NETWORK")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(entry.succeeded ? .green : .red)
                Spacer()
                Text("\(entry.durationMilliseconds)ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(entry.path)
                .font(.footnote.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Text(entry.message)
                .font(.footnote)
                .foregroundStyle(
                    entry.succeeded ? Color.secondary : Color.red
                )
                .textSelection(.enabled)

            HStack {
                Text(
                    entry.timestamp.formatted(
                        date: .omitted,
                        time: .standard
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                if copiedEntryID == entry.id {
                    Label("diagnostics.copied", systemImage: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func copy(_ entry: NetworkDiagnosticEntry) {
        UIPasteboard.general.string = diagnostics.text(for: entry)
        copiedEntryID = entry.id
        Task {
            try? await Task.sleep(for: .milliseconds(1_200))
            if copiedEntryID == entry.id {
                copiedEntryID = nil
            }
        }
    }
}

private struct ImageCacheDiagnosticsView: View {
    @State private var diagnostics = NetworkDiagnosticsStore.shared
    @State private var selectedModule: AISImageCacheModule?
    @State private var selectedKind: AISImageResourceKind?

    var body: some View {
        List {
            Section {
                HStack {
                    filterMenu(
                        title: selectedModule.map(moduleTitle)
                            ?? String(localized: "diagnostics.filter.all_modules"),
                        systemImage: "square.grid.2x2"
                    ) {
                        Button("diagnostics.filter.all_modules") {
                            selectedModule = nil
                        }
                        ForEach(AISImageCacheModule.allCases) { module in
                            Button(moduleTitle(module)) {
                                selectedModule = module
                            }
                        }
                    }

                    filterMenu(
                        title: selectedKind.map(kindFilterTitle)
                            ?? String(localized: "diagnostics.filter.all_types"),
                        systemImage: "photo"
                    ) {
                        Button("diagnostics.filter.all_types") {
                            selectedKind = nil
                        }
                        ForEach(AISImageResourceKind.allCases, id: \.self) {
                            kind in
                            Button(kindFilterTitle(kind)) {
                                selectedKind = kind
                            }
                        }
                    }
                }
            }

            Section("diagnostics.image.events") {
                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "diagnostics.image.empty",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("diagnostics.image.empty.description")
                    )
                } else {
                    ForEach(filteredEntries.prefix(200)) { entry in
                        imageCacheRow(entry)
                    }
                }
            }
        }
        .navigationTitle("diagnostics.image.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filteredEntries: [ImageCacheDiagnosticEntry] {
        diagnostics.imageCacheEntries.filter { entry in
            (selectedModule == nil || entry.module == selectedModule)
                && (selectedKind == nil || entry.resourceKind == selectedKind)
        }
    }

    private func imageCacheRow(
        _ entry: ImageCacheDiagnosticEntry
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(resourceLabel(entry))
                    .font(.caption.bold())
                    .foregroundStyle(AISTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        AISTheme.accent.opacity(0.12),
                        in: Capsule()
                    )
                Text(sourceTitle(entry.source))
                    .font(.caption.monospaced().bold())
                Spacer()
                Text("\(entry.durationMilliseconds)ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("\(entry.host)\(entry.path)")
                .font(.footnote.monospaced())
                .lineLimit(2)
                .textSelection(.enabled)

            Text(
                "module=\(entry.module.rawValue) "
                    + "preset=\(entry.appliedPreset) "
                    + "key=\(entry.cacheKey) "
                    + "bytes=\(entry.byteCount)"
            )
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            Text(
                entry.timestamp.formatted(
                    date: .omitted,
                    time: .standard
                )
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func resourceLabel(_ entry: ImageCacheDiagnosticEntry) -> String {
        switch entry.resourceKind {
        case .original:
            return String(localized: "diagnostics.image.kind.original")
        case .detail:
            guard let width = entry.pixelWidth else {
                return String(localized: "diagnostics.image.kind.detail.unknown")
            }
            return String.localizedStringWithFormat(
                String(localized: "diagnostics.image.kind.detail"),
                width
            )
        case .thumbnail:
            guard let width = entry.pixelWidth else {
                return String(
                    localized: "diagnostics.image.kind.thumbnail.unknown"
                )
            }
            return String.localizedStringWithFormat(
                String(localized: "diagnostics.image.kind.thumbnail"),
                width
            )
        }
    }

    private func moduleTitle(_ module: AISImageCacheModule) -> String {
        switch module {
        case .tasks:
            String(localized: "account.cache.module.tasks")
        case .galleryTemplates:
            String(localized: "account.cache.module.gallery_templates")
        case .projectsAssets:
            String(localized: "account.cache.module.projects_assets")
        case .other:
            String(localized: "account.cache.module.other")
        }
    }

    private func kindFilterTitle(_ kind: AISImageResourceKind) -> String {
        switch kind {
        case .thumbnail:
            String(localized: "diagnostics.image.filter.thumbnail")
        case .detail:
            String(localized: "diagnostics.image.filter.detail")
        case .original:
            String(localized: "diagnostics.image.kind.original")
        }
    }

    private func sourceTitle(_ source: String) -> String {
        switch source {
        case "memory-image", "memory-data":
            return "MEMORY"
        case "disk":
            return "DISK"
        case "in-flight":
            return "MERGED"
        case "network":
            return "CDN"
        default:
            return source.uppercased()
        }
    }

    private func filterMenu<MenuContent: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> MenuContent
    ) -> some View {
        Menu(content: content) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }
}

private struct DiagnosticViewerRow: View {
    let title: LocalizedStringKey
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

#Preview("NetworkDiagnosticsView") {
    NavigationStack {
        NetworkDiagnosticsView()
    }
}
