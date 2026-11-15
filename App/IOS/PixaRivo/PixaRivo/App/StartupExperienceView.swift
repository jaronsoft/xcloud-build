import SwiftUI

private enum StartupPalette {
    static let background = Color(red: 0.933, green: 0.953, blue: 1)
    static let navy = Color(red: 0.098, green: 0.169, blue: 0.404)
    static let coral = Color(red: 0.98, green: 0.31, blue: 0.22)
    static let lime = Color(red: 0.84, green: 0.99, blue: 0.51)
    static let muted = Color(red: 0.32, green: 0.39, blue: 0.53)
}

struct StartupExperienceView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsRibbon = false
    @State private var showsTitle = false
    @State private var revealedTiles = 0
    @State private var showsSteps = false
    @State private var isExiting = false

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 710
            let horizontalPadding = max(20.0, min(28.0, proxy.size.width * 0.07))

            ZStack {
                StartupPalette.background.ignoresSafeArea()
                backgroundArtwork(in: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    brandHeader(isCompact: isCompact)
                        .padding(.top, isCompact ? 10 : 20)

                    Spacer(minLength: isCompact ? 14 : 26)

                    statement(isCompact: isCompact)

                    Spacer(minLength: isCompact ? 12 : 22)

                    visualGallery(isCompact: isCompact)

                    Spacer(minLength: isCompact ? 12 : 22)

                    stepsPanel(isCompact: isCompact)
                        .padding(.bottom, isCompact ? 8 : 18)
                }
                .frame(width: min(proxy.size.width, 560) - horizontalPadding * 2, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(StartupPalette.background.ignoresSafeArea())
        .opacity(isExiting ? 0 : 1)
        .task { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AppLanguage.localized("startup.accessibility")))
    }

    private func backgroundArtwork(in size: CGSize) -> some View {
        ZStack {
            StartupRibbon()
                .fill(StartupPalette.coral)
                .frame(width: size.width * 0.27, height: size.height * 0.3)
                .position(x: size.width * 0.9, y: size.height * 0.1)
                .scaleEffect(showsRibbon ? 1 : 0.86, anchor: .topTrailing)
                .opacity(showsRibbon ? 1 : 0)

            Image(systemName: "sparkle")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(StartupPalette.lime)
                .position(x: size.width * 0.88, y: size.height * 0.09)
                .opacity(showsRibbon ? 1 : 0)
        }
        .accessibilityHidden(true)
    }

    private func brandHeader(isCompact: Bool) -> some View {
        HStack(spacing: 10) {
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: isCompact ? 40 : 44, height: isCompact ? 40 : 44)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(AppLanguage.localized("startup.brand"))
                    .font(.system(size: isCompact ? 18 : 20, weight: .black, design: .rounded))
                    .foregroundStyle(StartupPalette.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(AppLanguage.localized("startup.kicker"))
                    .font(.system(size: isCompact ? 8 : 9, weight: .bold))
                    .tracking(AppLanguage.isChinese ? 1.2 : 1)
                    .foregroundStyle(StartupPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 24)
        }
    }

    private func statement(isCompact: Bool) -> some View {
        let headline = AppLanguage.localized("startup.statement").components(separatedBy: "\n")

        return VStack(alignment: .leading, spacing: isCompact ? 6 : 9) {
            Text(AppLanguage.localized("startup.question"))
                .font(.system(size: isCompact ? 10 : 11, weight: .black))
                .tracking(1.4)
                .foregroundStyle(StartupPalette.navy)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(StartupPalette.lime, in: RoundedRectangle(cornerRadius: 2))
                .padding(.bottom, isCompact ? 8 : 15)

            Text(headline.first ?? "")
                .font(.system(size: isCompact ? 32 : 40, weight: .black))
                .foregroundStyle(StartupPalette.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(headline.dropFirst().joined(separator: " "))
                .font(.system(size: isCompact ? 30 : 38, weight: .black))
                .foregroundStyle(StartupPalette.coral)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(AppLanguage.localized("startup.summary"))
                .font(.system(size: isCompact ? 11 : 12, weight: .medium))
                .foregroundStyle(StartupPalette.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, isCompact ? 8 : 14)
        }
        .opacity(showsTitle ? 1 : 0)
        .offset(y: showsTitle ? 0 : 18)
    }

    private func visualGallery(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppLanguage.localized("startup.gallery.title"))
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(StartupPalette.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(StartupPalette.coral)
            }

            Rectangle()
                .fill(StartupPalette.coral)
                .frame(height: 3)

            GeometryReader { proxy in
                let leftWidth = proxy.size.width * 0.62
                let rightWidth = proxy.size.width - leftWidth

                HStack(spacing: 0) {
                    StartupPortraitTile(title: AppLanguage.localized("startup.card.portrait"))
                        .frame(width: leftWidth, height: proxy.size.height)
                        .opacity(revealedTiles >= 1 ? 1 : 0)

                    VStack(spacing: 0) {
                        StartupSchoolTile(title: AppLanguage.localized("startup.card.city"))
                            .opacity(revealedTiles >= 2 ? 1 : 0)

                        StartupProductTile(title: AppLanguage.localized("startup.card.poster"))
                            .opacity(revealedTiles >= 3 ? 1 : 0)
                    }
                    .frame(width: rightWidth, height: proxy.size.height)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .background(.white, in: RoundedRectangle(cornerRadius: 4))
                .shadow(color: StartupPalette.navy.opacity(0.22), radius: 16, y: 13)
            }
            .frame(height: isCompact ? 198 : 250)
        }
        .opacity(revealedTiles > 0 ? 1 : 0)
        .accessibilityHidden(true)
    }

    private func stepsPanel(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 10 : 13) {
            Text(AppLanguage.localized("startup.steps.title"))
                .font(.system(size: 9, weight: .black))
                .tracking(1.4)
                .foregroundStyle(StartupPalette.navy)
                .lineLimit(1)

            Rectangle()
                .fill(StartupPalette.navy.opacity(0.34))
                .frame(height: 1)

            HStack(spacing: 3) {
                step("01", title: AppLanguage.localized("startup.step.choose"), isCompact: isCompact)
                stepArrow
                step("02", title: AppLanguage.localized("startup.step.images"), isCompact: isCompact)
                stepArrow
                step("03", title: AppLanguage.localized("startup.step.words"), isCompact: isCompact)
            }
        }
        .opacity(showsSteps ? 1 : 0)
        .offset(y: showsSteps ? 0 : 12)
        .accessibilityHidden(true)
    }

    private func step(_ number: String, title: String, isCompact: Bool) -> some View {
        HStack(spacing: 3) {
            Text(number)
                .foregroundStyle(StartupPalette.coral)
            Text(title)
                .foregroundStyle(StartupPalette.navy)
        }
        .font(.system(size: isCompact ? 9 : 10, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(StartupPalette.coral)
    }

    @MainActor
    private func play() async {
        if reduceMotion {
            showsRibbon = true
            showsTitle = true
            revealedTiles = 3
            showsSteps = true
            try? await Task.sleep(for: .milliseconds(650))
        } else {
            withAnimation(.easeOut(duration: 0.3)) { showsRibbon = true }
            try? await Task.sleep(for: .milliseconds(170))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { showsTitle = true }
            try? await Task.sleep(for: .milliseconds(260))
            for tile in 1...3 {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.28)) { revealedTiles = tile }
                try? await Task.sleep(for: .milliseconds(140))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { showsSteps = true }
            try? await Task.sleep(for: .milliseconds(700))
        }

        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.22)) {
            isExiting = true
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 220))
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

private struct StartupRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.72))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct StartupPortraitTile: View {
    let title: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 1, green: 0.76, blue: 0.65), Color(red: 0.94, green: 0.43, blue: 0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.white.opacity(0.23))
                    .frame(width: proxy.size.width * 0.8)
                    .position(x: proxy.size.width * 0.77, y: proxy.size.height * 0.18)

                Ellipse()
                    .fill(Color(red: 0.62, green: 0.2, blue: 0.25))
                    .frame(width: proxy.size.width * 0.96, height: proxy.size.height * 0.78)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 1.08)

                Ellipse()
                    .fill(Color(red: 0.25, green: 0.15, blue: 0.17))
                    .frame(width: proxy.size.width * 0.43, height: proxy.size.height * 0.36)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.37)

                Circle()
                    .fill(Color(red: 1, green: 0.91, blue: 0.84))
                    .frame(width: proxy.size.width * 0.43)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.48)

                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(12)
            }
        }
    }
}

private struct StartupSchoolTile: View {
    let title: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.35, green: 0.56, blue: 0.83), Color(red: 0.13, green: 0.24, blue: 0.68)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(StartupPalette.lime)
                    .frame(width: proxy.size.width * 0.45)
                    .position(x: proxy.size.width * 0.72, y: proxy.size.height * 0.3)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.25, y: proxy.size.height * 0.56))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.55, y: proxy.size.height * 0.76))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.83, y: proxy.size.height * 0.45))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * 0.62))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(Color(red: 0.1, green: 0.17, blue: 0.54).opacity(0.7))

                Text(title)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(10)
            }
        }
    }
}

private struct StartupProductTile: View {
    let title: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                StartupPalette.lime

                Image(systemName: "bag.fill")
                    .font(.system(size: min(proxy.size.width * 0.45, 52), weight: .regular))
                    .foregroundStyle(Color(red: 0.09, green: 0.15, blue: 0.16))
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.45)

                Text(title)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color(red: 0.09, green: 0.15, blue: 0.16))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(10)
            }
        }
    }
}
