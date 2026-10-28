import SwiftUI

struct CacheManagementView: View {
    @State private var cacheSizes: (data: Int64, images: Int64) = (0, 0)
    @State private var confirmClearData = false
    @State private var confirmClearImages = false

    var body: some View {
        ScrollView {
            BmbCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("OFFLINE STORAGE").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                    Text("Saved for your next visit").font(.headline)
                    HStack {
                        Label("Data cache", systemImage: "doc.text")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: cacheSizes.data, countStyle: .file))
                            .foregroundStyle(BmbTheme.muted)
                    }.font(.subheadline)
                    HStack {
                        Label("Image cache", systemImage: "photo")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: cacheSizes.images, countStyle: .file))
                            .foregroundStyle(BmbTheme.muted)
                    }.font(.subheadline)
                    HStack(spacing: 12) {
                        Button("Clear data cache") { confirmClearData = true }
                        Button("Clear image cache") { confirmClearImages = true }
                    }.font(.caption.bold()).buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .background(BmbTheme.paper)
        .navigationTitle("Clear cache")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .task { cacheSizes = await BmbCache.shared.sizes() }
        .confirmationDialog("Clear saved data?", isPresented: $confirmClearData) {
            Button("Clear data cache", role: .destructive) {
                Task { await BmbCache.shared.clearData(); cacheSizes = await BmbCache.shared.sizes() }
            }
        }
        .confirmationDialog("Clear saved images?", isPresented: $confirmClearImages) {
            Button("Clear image cache", role: .destructive) {
                Task { await BmbCache.shared.clearImages(); cacheSizes = await BmbCache.shared.sizes() }
            }
        }
    }
}
