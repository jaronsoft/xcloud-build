import SwiftUI

struct CacheManagementView: View {
    @State private var imageStatistics: AISImageCacheStatistics?
    @State private var responseByteCount: Int64 = 0
    @State private var responseFileCount = 0
    @State private var clearingID: String?
    @State private var pendingAction: CacheClearAction?

    var body: some View {
        List {
            Section {
                LabeledContent(
                    "account.cache.total",
                    value: formattedByteCount(totalByteCount)
                )
                if let imageStatistics {
                    LabeledContent(
                        "account.cache.images",
                        value: String.localizedStringWithFormat(
                            String(localized: "account.cache.files"),
                            imageStatistics.fileCount
                        )
                    )
                }
            } footer: {
                Text("account.cache.breakdown.helper")
            }

            Section("account.cache.modules") {
                ForEach(AISImageCacheModule.allCases) { module in
                    cacheRow(
                        id: module.rawValue,
                        title: module.title,
                        systemImage: module.systemImage,
                        byteCount: statistics(for: module)?.byteCount ?? 0,
                        fileCount: statistics(for: module)?.fileCount ?? 0
                    ) {
                        pendingAction = .images(module)
                    }
                }

                cacheRow(
                    id: "responses",
                    title: String(localized: "account.cache.module.responses"),
                    systemImage: "arrow.left.arrow.right.circle",
                    byteCount: responseByteCount,
                    fileCount: responseFileCount
                ) {
                    pendingAction = .responses
                }
            }

            Section {
                Button(role: .destructive) {
                    pendingAction = .all
                } label: {
                    Label(
                        "account.cache.clear_all",
                        systemImage: "trash"
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(clearingID != nil || totalByteCount == 0)
            }
        }
        .navigationTitle("account.cache.management")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
        }
        .confirmationDialog(
            "account.cache.confirm.title",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("account.cache.confirm.action", role: .destructive) {
                guard let action = pendingAction else { return }
                pendingAction = nil
                Task { await clear(action) }
            }
            Button("common.cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text("account.cache.confirm.message")
        }
    }

    private var totalByteCount: Int64 {
        (imageStatistics?.physicalByteCount ?? 0) + responseByteCount
    }

    private func statistics(
        for module: AISImageCacheModule
    ) -> AISCacheModuleStatistics? {
        imageStatistics?.modules.first { $0.module == module }
    }

    private func cacheRow(
        id: String,
        title: String,
        systemImage: String,
        byteCount: Int64,
        fileCount: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(AISTheme.accentSecondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "account.cache.module.detail"),
                            formattedByteCount(byteCount),
                            fileCount
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if clearingID == id {
                    ProgressView()
                } else {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(clearingID != nil || byteCount == 0)
    }

    private func clear(_ action: CacheClearAction) async {
        clearingID = action.id
        defer { clearingID = nil }
        switch action {
        case let .images(module):
            await AISImageCache.shared.clear(module: module)
        case .responses:
            await AISResponseCache.shared.clear()
            NetworkDiagnosticsStore.shared.recordSystemLog(
                tag: "CACHE",
                "Cleared response cache."
            )
        case .all:
            try? await AISImageCache.shared.clear()
            await AISResponseCache.shared.clear()
            NetworkDiagnosticsStore.shared.recordSystemLog(
                tag: "CACHE",
                "Cleared all application caches."
            )
        }
        await refresh()
    }

    private func refresh() async {
        async let images = AISImageCache.shared.statistics()
        async let responses = AISResponseCache.shared.diskSize()
        async let responseFiles = AISResponseCache.shared.fileCount()
        imageStatistics = await images
        responseByteCount = await responses
        responseFileCount = await responseFiles
    }

    private func formattedByteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

private enum CacheClearAction {
    case images(AISImageCacheModule)
    case responses
    case all

    var id: String {
        switch self {
        case let .images(module): module.rawValue
        case .responses: "responses"
        case .all: "all"
        }
    }
}

private extension AISImageCacheModule {
    var title: String {
        switch self {
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

    var systemImage: String {
        switch self {
        case .tasks: "clock.arrow.circlepath"
        case .galleryTemplates: "rectangle.grid.2x2"
        case .projectsAssets: "folder.badge.gearshape"
        case .other: "shippingbox"
        }
    }
}
