import SwiftUI

struct ActivityDetailContentSection: View {
    @Binding var selectedTab: String
    let hasIntroduction: Bool
    let description: String
    let hasRichContent: Bool
    let html: String
    let store: SessionStore

    var body: some View {
        if hasIntroduction {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(["registration", "content"], id: \.self) { tab in
                        let title = tab == "registration" ? "活动报名" : "活动介绍"
                        Button { selectedTab = tab } label: {
                            Text(title).font(.system(size: NativeTypography.size(13), weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? Brand.primary : Brand.muted)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(selectedTab == tab ? Color(red: 0.89, green: 0.96, blue: 0.94) : .clear,
                                            in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    }
                }
                .padding(4)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))

                if selectedTab == "content" {
                    VStack(alignment: .leading, spacing: 10) {
                        if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(hasRichContent ? "活动简介" : "活动介绍")
                                .font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                            Text(description).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
                        }
                        if hasRichContent {
                            Text("活动详情").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                            NativeHTMLContent(html: html, store: store)
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}
