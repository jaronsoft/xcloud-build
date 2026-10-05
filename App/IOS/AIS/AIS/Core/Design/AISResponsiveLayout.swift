import SwiftUI

enum AISResponsiveLayout {
    static let maximumContentWidth: CGFloat = 1_280

    static func templateColumns(for width: CGFloat) -> Int {
        if width >= 1_100 { return 5 }
        if width >= 800 { return 4 }
        if width >= 560 { return 3 }
        return 2
    }

    static func imageGalleryColumns(for width: CGFloat) -> Int {
        if width >= 1_000 { return 3 }
        if width >= 620 { return 2 }
        return 1
    }

    static func usesWideCreationLayout(for width: CGFloat) -> Bool {
        width >= 900
    }

    static func usesCompactCreationPickers(for width: CGFloat) -> Bool {
        width < 700
    }

    static func taskColumns(for size: CGSize) -> Int {
        size.width > size.height && size.width >= 1_000 ? 2 : 1
    }

    static func taskMaximumContentWidth(for size: CGSize) -> CGFloat {
        taskColumns(for: size) == 2 ? maximumContentWidth : 860
    }

    static func usesWideTemplateDetailLayout(for size: CGSize) -> Bool {
        size.width > size.height && size.width >= 1_000
    }

    static func horizontalPadding(for width: CGFloat) -> CGFloat {
        width >= 700 ? 24 : 16
    }
}

private struct AISContentWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func onAISContentWidthChange(
        perform action: @escaping (CGFloat) -> Void
    ) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: AISContentWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        }
        .onPreferenceChange(AISContentWidthPreferenceKey.self) { width in
            guard width > 0 else { return }
            action(width)
        }
    }
}
