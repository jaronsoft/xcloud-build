import SwiftUI

struct NativeHomeQuickEntrySection: View {
    let store: SessionStore
    let shortcutIndices: [Int]
    let entries: [[String: Any]]
    let titleForEntry: ([String: Any]?, Int) -> String
    let iconIndexForEntry: ([String: Any]?, Int) -> Int
    let onOpenEntry: ([String: Any], Int) -> Void
    let onOpenFallback: (String, Int) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 18) {
            ForEach(shortcutIndices.indices, id: \.self) { position in
                let shortcutIndex = shortcutIndices[position]
                let entry = entries.indices.contains(position) ? entries[position] : nil
                let iconIndex = iconIndexForEntry(entry, shortcutIndex)
                let rawTitle = entry?["Title"] as? String ?? entry?["title"] as? String
                let configuredTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = configuredTitle.flatMap { $0.isEmpty ? nil : $0 }
                    ?? titleForEntry(entry, shortcutIndex)
                let configuredImage = entry?["ImageUrl"] as? String ?? entry?["imageUrl"] as? String

                Button {
                    if let entry { onOpenEntry(entry, position) }
                    else { onOpenFallback("", shortcutIndex) }
                } label: {
                    VStack(spacing: 4) {
                        if let configuredImage, !configuredImage.isEmpty {
                            remoteImage(configuredImage, height: 42, fallback: "Quick\(iconIndex % 8)")
                                .frame(width: 42, height: 42)
                        } else {
                            Image("Quick\(iconIndex % 8)").resizable().scaledToFit().frame(width: 42, height: 42)
                        }
                        Text(title)
                            .font(.system(size: NativeTypography.size(12), weight: .medium))
                            .foregroundStyle(Brand.ink)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityHint("打开此服务")
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func remoteImage(_ path: String, height: CGFloat, fallback: String) -> some View {
        GeometryReader { geometry in
            if let url = MobileAPI(store: store).mediaURL(path) {
                CachedRemoteImage(url: url) {
                    Image(fallback).resizable().scaledToFill()
                }
                .frame(width: geometry.size.width, height: height)
                .clipped()
            } else {
                Image(fallback).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: height)
                    .clipped()
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
