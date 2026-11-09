import SwiftUI

private struct NoticeTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct NoticeTicker: View {
    let content: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentWidth: CGFloat = 0
    @State private var startDate = Date()

    var body: some View {
        GeometryReader { viewport in
            if reduceMotion {
                Text(content)
                    .lineLimit(1)
                    .frame(width: viewport.size.width, height: viewport.size.height, alignment: .leading)
            } else {
                TimelineView(.animation) { timeline in
                    let progress = timeline.date.timeIntervalSince(startDate)
                        .truncatingRemainder(dividingBy: 18) / 18
                    let offset = -max(0, (progress - 0.1) / 0.9) * (contentWidth + 24)
                    HStack(spacing: 24) {
                        Text(content)
                            .background {
                                GeometryReader { size in
                                    Color.clear.preference(key: NoticeTextWidthKey.self, value: size.size.width)
                                }
                            }
                        Text(content)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: viewport.size.height)
                    .offset(x: offset)
                }
            }
        }
        .frame(height: 18)
        .font(.system(size: NativeTypography.size(11)))
        .foregroundStyle(Brand.ink)
        .lineLimit(1)
        .clipped()
        .onPreferenceChange(NoticeTextWidthKey.self) { contentWidth = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content)
    }
}

struct HomeSectionView: Identifiable {
    let id: String
    let sortOrder: Int
    let sourceOrder: Int
    let content: AnyView
}
