import SwiftUI

enum AIKTheme {
    static let accent = Color(red: 0.145, green: 0.388, blue: 0.922)
    static let secondary = Color(red: 0.31, green: 0.275, blue: 0.898)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let background = Color(uiColor: .systemGroupedBackground)

    static func gradient(opacity: Double = 1) -> LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(opacity),
                secondary.opacity(opacity),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct AIKBrandMark: View {
    var size: CGFloat = 72

    var body: some View {
        Image("BrandIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.23))
            .shadow(color: AIKTheme.accent.opacity(0.2), radius: 16, y: 8)
            .accessibilityHidden(true)
    }
}
