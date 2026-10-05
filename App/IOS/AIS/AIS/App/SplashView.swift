import SwiftUI

struct SplashView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconScale = 0.94
    @State private var contentOpacity = 0.0
    @State private var contentOffset: CGFloat = 6
    @State private var ringRotation = -18.0
    @State private var glowScale = 0.88

    var body: some View {
        ZStack {
            AISPageBackground()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(
                            AISTheme.accentGradient,
                            style: StrokeStyle(lineWidth: 2, dash: [18, 12])
                        )
                        .frame(width: 174, height: 174)
                        .rotationEffect(.degrees(ringRotation))

                    Circle()
                        .fill(AISTheme.accent.opacity(0.10))
                        .frame(width: 148, height: 148)
                        .scaleEffect(glowScale)

                    Image("BrandIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 118, height: 118)
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                }
                .shadow(
                    color: AISTheme.accentSecondary.opacity(0.18),
                    radius: 24,
                    y: 12
                )
                .scaleEffect(iconScale)

                VStack(spacing: 7) {
                    Text("app.display_name")
                        .font(
                            .system(
                                size: 25,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(AISTheme.accentSecondary)
                    Text("splash.tagline")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AISTheme.muted)

                    Text(verbatim: versionText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AISTheme.muted)
                        .padding(.top, 8)

                    Text("splash.publisher")
                    .font(.caption2)
                    .foregroundStyle(AISTheme.muted)
                    .multilineTextAlignment(.center)
                }
                .offset(y: contentOffset)
            }
            .opacity(contentOpacity)
        }
        .preferredColorScheme(.light)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AIS")
        .task {
            await animate()
        }
    }

    @MainActor
    private func animate() async {
        if reduceMotion {
            iconScale = 1
            contentOpacity = 1
            contentOffset = 0
            try? await Task.sleep(for: .milliseconds(420))
        } else {
            withAnimation(.easeOut(duration: 0.28)) {
                iconScale = 1
                contentOpacity = 1
                contentOffset = 0
            }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                ringRotation = 342
            }
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                glowScale = 1.06
            }
            try? await Task.sleep(for: .milliseconds(560))
        }
        onFinished()
    }

    private var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
        return String.localizedStringWithFormat(
            String(localized: "splash.version"),
            version,
            build
        )
    }
}

#Preview("SplashView") {
    SplashView {}
}
