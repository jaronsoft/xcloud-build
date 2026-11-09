import SwiftUI

struct NativeHomeFeaturedSection: View {
    let store: SessionStore
    let title: String
    let rows: [[String: Any]]
    let onBrowse: () -> Void
    let onOpen: ([String: Any]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onBrowse) { NativeHomeSectionHeader(title: title) }.buttonStyle(.plain)
            if rows.isEmpty {
                Text("暂无已发布内容")
                    .font(.system(size: NativeTypography.size(12)))
                    .foregroundStyle(Brand.muted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(rows.indices, id: \.self) { index in
                            let row = rows[index]
                            let admission = homeAdmissionPresentation(row)
                            let itemTitle = row["Title"] as? String ?? row["Name"] as? String ?? "江都文旅"
                            Button { onOpen(row) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ZStack(alignment: .topLeading) {
                                        featuredImage(catalogCover(row), height: 112)
                                        if let admission {
                                            Text(admission.label)
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(admission.isUnknown ? Color(red: 0.39, green: 0.45, blue: 0.43) : admission.isFree ? Color(red: 0.25, green: 0.40, blue: 0.29) : Color(red: 0.45, green: 0.32, blue: 0.25))
                                                .padding(.horizontal, 7).padding(.vertical, 4)
                                                .background(admission.isUnknown ? Color(red: 0.93, green: 0.95, blue: 0.94) : admission.isFree ? Color(red: 0.91, green: 0.95, blue: 0.91) : Color(red: 0.96, green: 0.93, blue: 0.88), in: Capsule())
                                                .padding(6)
                                        }
                                    }
                                    .frame(height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Text(itemTitle)
                                        .font(.system(size: NativeTypography.size(13), weight: .semibold))
                                        .lineLimit(1).foregroundStyle(Brand.ink)
                                    if let subtitle = row["Subtitle"] as? String ?? row["Description"] as? String ?? row["Address"] as? String,
                                       !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(subtitle)
                                            .font(.system(size: NativeTypography.size(11)))
                                            .lineLimit(1).foregroundStyle(Brand.muted)
                                    }
                                }
                                .frame(width: 140, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(admission.map { "查看\(itemTitle)详情，\($0.label)" } ?? "查看\(itemTitle)详情")
                        }
                    }
                }
            }
        }
        .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func featuredImage(_ path: String?, height: CGFloat) -> some View {
        GeometryReader { geometry in
            if let url = MobileAPI(store: store).mediaURL(path) {
                CachedRemoteImage(url: url) { featuredImageFallback }
                    .frame(width: geometry.size.width, height: height).clipped()
            } else {
                featuredImageFallback.frame(width: geometry.size.width, height: height).clipped()
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var featuredImageFallback: some View {
        Image("Hero").resizable().scaledToFill()
    }
}
