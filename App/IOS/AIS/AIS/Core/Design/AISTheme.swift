import SwiftUI

enum AISTheme {
    static let accent = Color(
        red: 1,
        green: 0.38,
        blue: 0.24
    )
    static let accentSecondary = Color(
        red: 0.13,
        green: 0.19,
        blue: 0.22
    )
    static let accentWarm = Color(
        red: 0.40,
        green: 0.51,
        blue: 0.55
    )
    static let canvas = Color(
        red: 0.94,
        green: 0.95,
        blue: 0.94
    )
    static let elevated = Color(
        red: 0.98,
        green: 0.985,
        blue: 0.98
    )
    static let line = Color(
        red: 0.77,
        green: 0.81,
        blue: 0.82
    )
    static let muted = Color(
        red: 0.43,
        green: 0.49,
        blue: 0.52
    )

    static let accentGradient = LinearGradient(
        colors: [
            accent,
            Color(red: 1, green: 0.51, blue: 0.36)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let auroraGradient = accentGradient
}

struct AISPageBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.97, green: 0.96, blue: 0.93),
                        AISTheme.canvas,
                        Color(red: 0.82, green: 0.87, blue: 0.89)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Path { path in
                    var y: CGFloat = 52
                    while y < proxy.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(
                            to: CGPoint(x: proxy.size.width, y: y)
                        )
                        y += 56
                    }
                }
                .stroke(AISTheme.line.opacity(0.27), lineWidth: 0.7)

                RadialGradient(
                    colors: [.white.opacity(0.85), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: min(
                        proxy.size.width,
                        proxy.size.height
                    ) * 0.58
                )
            }
        }
        .ignoresSafeArea()
    }
}

private struct AISSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let hasShadow: Bool

    func body(content: Content) -> some View {
        content
            .background(
                AISTheme.elevated.opacity(0.70),
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.96),
                            AISTheme.line.opacity(0.80)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(
                color: hasShadow
                    ? AISTheme.accentSecondary.opacity(0.13)
                    : .clear,
                radius: 22,
                y: 12
            )
    }
}

private struct AISPrimaryButtonModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(
                isEnabled
                    ? Color.white
                    : Color(uiColor: .label)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(
                isEnabled
                    ? AnyShapeStyle(AISTheme.accentGradient)
                    : AnyShapeStyle(
                        Color(uiColor: .secondarySystemFill)
                    ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(
                color: isEnabled
                    ? AISTheme.accent.opacity(0.22)
                    : .clear,
                radius: 16,
                y: 7
            )
            .contentShape(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}

struct AISVisualHeader<Content: View>: View {
    let imageName: String
    let imageAlignment: Alignment
    let content: Content

    init(
        imageName: String,
        imageAlignment: Alignment = .trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.imageName = imageName
        self.imageAlignment = imageAlignment
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: imageAlignment) {
            AISBlueprintGrid()

            HStack(spacing: 18) {
                content
                    .frame(maxWidth: 430, alignment: .leading)

                Spacer(minLength: 0)

                AISStageProductSymbol()
                    .frame(width: 118, height: 140)
                    .padding(.trailing, 4)
            }
            .padding(24)
        }
        .frame(minHeight: 230)
        .clipShape(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.96), lineWidth: 1)
        }
        .shadow(
            color: AISTheme.accentSecondary.opacity(0.12),
            radius: 24,
            y: 14
        )
    }
}

struct AISBlueprintGrid: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AISTheme.elevated.opacity(0.72)

                Path { path in
                    var y: CGFloat = 20
                    while y < proxy.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(
                            to: CGPoint(x: proxy.size.width, y: y)
                        )
                        y += 28
                    }

                    var x: CGFloat = 20
                    while x < proxy.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(
                            to: CGPoint(x: x, y: proxy.size.height)
                        )
                        x += 28
                    }
                }
                .stroke(AISTheme.line.opacity(0.22), lineWidth: 0.6)
            }
        }
    }
}

struct AISStageProductSymbol: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotatesLightRing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AISTheme.accent.opacity(0.18))
                .frame(width: 112, height: 112)
                .blur(radius: 18)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white,
                            Color(red: 0.84, green: 0.89, blue: 0.91),
                            .white
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 112, height: 112)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.94), lineWidth: 2)
                        .padding(5)
                }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.36, green: 0.48, blue: 0.55),
                            AISTheme.accentSecondary,
                            Color(red: 0.035, green: 0.075, blue: 0.09)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 48
                    )
                )
                .frame(width: 82, height: 82)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.48), lineWidth: 1)
                        .padding(4)
                }

            Circle()
                .trim(from: 0.05, to: 0.34)
                .stroke(
                    AISTheme.accentGradient,
                    style: StrokeStyle(
                        lineWidth: 4,
                        lineCap: .round
                    )
                )
                .frame(width: 69, height: 69)
                .rotationEffect(.degrees(rotatesLightRing ? 360 : 0))

            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: 54, height: 54)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            Color(red: 0.24, green: 0.39, blue: 0.48),
                            Color(red: 0.02, green: 0.05, blue: 0.07)
                        ],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: 18
                    )
                )
                .frame(width: 28, height: 28)

            Circle()
                .fill(Color.white.opacity(0.76))
                .frame(width: 7, height: 7)
                .offset(x: -8, y: -8)

            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 28, height: 6)
                .rotationEffect(.degrees(-38))
                .offset(x: -11, y: -19)
        }
        .shadow(
            color: AISTheme.accentSecondary.opacity(0.18),
            radius: 20,
            y: 14
        )
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            rotatesLightRing = true
        }
        .animation(
            reduceMotion
                ? nil
                : .linear(duration: 10).repeatForever(
                    autoreverses: false
                ),
            value: rotatesLightRing
        )
    }
}

struct AISSectionLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(AISTheme.accent)
    }
}

extension View {
    func aisSurface(
        cornerRadius: CGFloat = 24,
        hasShadow: Bool = false
    ) -> some View {
        modifier(
            AISSurfaceModifier(
                cornerRadius: cornerRadius,
                hasShadow: hasShadow
            )
        )
    }

    func aisPrimaryButton(isEnabled: Bool = true) -> some View {
        modifier(AISPrimaryButtonModifier(isEnabled: isEnabled))
    }
}
