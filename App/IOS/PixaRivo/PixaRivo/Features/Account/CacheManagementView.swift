import SwiftUI

struct PixaCacheManagementView: View {
    @State private var imageStatistics: PixaImageCacheStatistics?
    @State private var responseByteCount: Int64 = 0
    @State private var responseFileCount = 0
    @State private var pendingAction: PixaCacheAction?
    @State private var clearingAction: PixaCacheAction?

    var body: some View {
        List {
            Section {
                LabeledContent(
                    "cache.images",
                    value: formatted(imageStatistics?.physicalByteCount ?? 0)
                )
                LabeledContent(
                    "cache.data",
                    value: formatted(responseByteCount)
                )
            } footer: {
                Text("cache.preserved_hint")
            }

            Section("cache.actions") {
                clearButton(
                    action: .images,
                    title: "cache.clear_images",
                    icon: "photo.stack",
                    detail: String.localizedStringWithFormat(
                        AppLanguage.localized("cache.files_format"),
                        imageStatistics?.fileCount ?? 0
                    )
                )
                clearButton(
                    action: .data,
                    title: "cache.clear_data",
                    icon: "externaldrive.badge.xmark",
                    detail: String.localizedStringWithFormat(
                        AppLanguage.localized("cache.files_format"),
                        responseFileCount
                    )
                )
            }
        }
        .navigationTitle("cache.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .confirmationDialog(
            "cache.confirm_title",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("cache.confirm_action", role: .destructive) {
                guard let action = pendingAction else { return }
                pendingAction = nil
                Task { await clear(action) }
            }
            Button("common.cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text("cache.preserved_hint")
        }
    }

    private func clearButton(
        action: PixaCacheAction,
        title: LocalizedStringKey,
        icon: String,
        detail: String
    ) -> some View {
        Button { pendingAction = action } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(PixaTheme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if clearingAction == action {
                    ProgressView()
                } else {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(clearingAction != nil)
    }

    private func clear(_ action: PixaCacheAction) async {
        clearingAction = action
        defer { clearingAction = nil }
        switch action {
        case .images:
            try? await PixaImageCache.shared.clear()
        case .data:
            await PixaResponseCache.shared.clear()
        }
        await refresh()
    }

    private func refresh() async {
        async let images = PixaImageCache.shared.statistics()
        async let responses = PixaResponseCache.shared.statistics()
        imageStatistics = await images
        let responseStatistics = await responses
        responseByteCount = responseStatistics.byteCount
        responseFileCount = responseStatistics.fileCount
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private enum PixaCacheAction: Equatable {
    case images
    case data
}
