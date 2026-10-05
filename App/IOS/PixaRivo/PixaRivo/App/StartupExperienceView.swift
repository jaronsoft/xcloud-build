import SwiftUI

struct StartupExperienceView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsBrand = false
    @State private var showsStatement = false
    @State private var showsCards = false
    @State private var showsSteps = false
    @State private var isExiting = false

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 700
            let horizontalPadding = max(22.0, min(32.0, proxy.size.width * 0.07))

            ZStack {
                PixaTheme.paper
                backgroundArtwork(in: proxy.size)

                VStack(alignment: .leading, spacing: 0) {
                    brandHeader(isCompact: isCompact)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, isCompact ? 22 : 34)

                    Spacer(minLength: isCompact ? 18 : 30)

                    statement(isCompact: isCompact)
                        .padding(.horizontal, horizontalPadding)

                    Spacer(minLength: isCompact ? 12 : 24)

                    skillCards(availableWidth: proxy.size.width, isCompact: isCompact)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: isCompact ? 12 : 24)

                    stepsPanel(isCompact: isCompact)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .opacity(isExiting ? 0 : 1)
        .task { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AppLanguage.localized("startup.accessibility")))
    }

    private func backgroundArtwork(in size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(PixaTheme.accent)
                .frame(width: size.width * 0.72)
                .offset(x: size.width * 0.36, y: -size.height * 0.3)
                .scaleEffect(showsBrand ? 1 : 0.72)
                .opacity(showsBrand ? 0.96 : 0)

            Circle()
                .stroke(Color(red: 0.78, green: 0.66, blue: 0.42).opacity(0.25), lineWidth: 1)
                .frame(width: size.width * 1.12)
                .offset(x: size.width * 0.35, y: -size.height * 0.16)

            Circle()
                .stroke(Color(red: 0.78, green: 0.66, blue: 0.42).opacity(0.16), lineWidth: 1)
                .frame(width: size.width * 0.88)
                .offset(x: size.width * 0.23, y: -size.height * 0.1)

            Circle()
                .fill(PixaTheme.ink)
                .frame(width: size.width * 0.9)
                .offset(x: size.width * 0.42, y: size.height * 0.5)
                .scaleEffect(showsSteps ? 1 : 0.92)
        }
        .accessibilityHidden(true)
    }

    private func brandHeader(isCompact: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: isCompact ? 42 : 48, height: isCompact ? 42 : 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(AppLanguage.localized("startup.brand"))
                    .font(.system(size: isCompact ? 20 : 23, weight: .bold, design: .rounded))
                    .foregroundStyle(PixaTheme.ink)
                    .lineLimit(1)
                Text(AppLanguage.localized("startup.kicker"))
                    .font(.system(size: isCompact ? 9 : 10, weight: .bold))
                    .tracking(AppLanguage.isChinese ? 1.2 : 1.6)
                    .foregroundStyle(PixaTheme.ink.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 8)

            Text(AppLanguage.localized("startup.made_for_ios"))
                .font(.system(size: 9, weight: .black))
                .tracking(1.8)
                .foregroundStyle(PixaTheme.ink)
                .padding(.top, 5)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .opacity(showsBrand ? 1 : 0)
        .offset(y: showsBrand ? 0 : -12)
    }

    private func statement(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 7 : 10) {
            Text(AppLanguage.localized("startup.question"))
                .font(.system(size: isCompact ? 11 : 12, weight: .black))
                .tracking(AppLanguage.isChinese ? 2.4 : 3)
                .foregroundStyle(PixaTheme.accent)

            Text(AppLanguage.localized("startup.statement"))
                .font(.system(size: isCompact ? 35 : 44, weight: .bold, design: .serif))
                .italic()
                .foregroundStyle(PixaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.82)

            Text(AppLanguage.localized("startup.summary"))
                .font(.system(size: isCompact ? 13 : 15, weight: .regular))
                .foregroundStyle(PixaTheme.ink.opacity(0.66))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(showsStatement ? 1 : 0)
        .offset(y: showsStatement ? 0 : 18)
    }

    private func skillCards(availableWidth: CGFloat, isCompact: Bool) -> some View {
        let cardWidth = min(isCompact ? 112.0 : 132.0, availableWidth * 0.34)
        let cardHeight = cardWidth * 1.28
        let spread = min(cardWidth * 0.73, (availableWidth - cardWidth - 28) / 2)

        return ZStack {
            StartupSkillCard(
                title: AppLanguage.localized("startup.card.city"),
                symbol: "building.2.fill",
                colors: [Color(red: 0.18, green: 0.37, blue: 0.5), Color(red: 0.68, green: 0.8, blue: 0.78)]
            )
            .frame(width: cardWidth, height: cardHeight)
            .rotationEffect(.degrees(showsCards && !reduceMotion ? -7 : -15))
            .offset(x: showsCards ? -spread : 0, y: showsCards ? 8 : 56)
            .zIndex(1)

            StartupSkillCard(
                title: AppLanguage.localized("startup.card.portrait"),
                symbol: "person.crop.rectangle.stack.fill",
                colors: [Color(red: 0.95, green: 0.72, blue: 0.58), Color(red: 0.73, green: 0.33, blue: 0.28)]
            )
            .frame(width: cardWidth, height: cardHeight)
            .offset(y: showsCards ? -5 : 56)
            .zIndex(3)

            StartupSkillCard(
                title: AppLanguage.localized("startup.card.poster"),
                symbol: "text.below.photo.fill",
                colors: [Color(red: 0.63, green: 0.84, blue: 0.8), Color(red: 0.23, green: 0.53, blue: 0.54)]
            )
            .frame(width: cardWidth, height: cardHeight)
            .rotationEffect(.degrees(showsCards && !reduceMotion ? 7 : 15))
            .offset(x: showsCards ? spread : 0, y: showsCards ? 8 : 56)
            .zIndex(2)
        }
        .frame(height: cardHeight + (isCompact ? 8 : 18))
        .opacity(showsCards ? 1 : 0)
        .scaleEffect(showsCards ? 1 : 0.82)
        .accessibilityHidden(true)
    }

    private func stepsPanel(isCompact: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            StartupStep(number: "01", title: AppLanguage.localized("startup.step.choose"), isCompact: isCompact)
            StartupStep(number: "02", title: AppLanguage.localized("startup.step.images"), isCompact: isCompact)
            StartupStep(number: "03", title: AppLanguage.localized("startup.step.words"), isCompact: isCompact)
        }
        .padding(.horizontal, 24)
        .padding(.top, isCompact ? 17 : 22)
        .padding(.bottom, isCompact ? 18 : 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PixaTheme.ink.opacity(0.98))
        .opacity(showsSteps ? 1 : 0)
        .offset(y: showsSteps ? 0 : 32)
        .accessibilityHidden(true)
    }

    @MainActor
    private func play() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.12)) {
                showsBrand = true
                showsStatement = true
                showsCards = true
                showsSteps = true
            }
            try? await Task.sleep(for: .milliseconds(420))
        } else {
            withAnimation(.easeOut(duration: 0.38)) { showsBrand = true }
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.42)) { showsStatement = true }
            try? await Task.sleep(for: .milliseconds(190))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.58, dampingFraction: 0.76)) { showsCards = true }
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.34)) { showsSteps = true }
            try? await Task.sleep(for: .milliseconds(760))
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

private struct StartupSkillCard: View {
    let title: String
    let symbol: String
    let colors: [Color]

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)

                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 80, height: 80)
                    .offset(x: 32, y: -36)

                Image(systemName: symbol)
                    .font(.system(size: 36, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.9))

                VStack {
                    Spacer()
                    Rectangle()
                        .fill(.white.opacity(0.24))
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
            .clipShape(Rectangle())

            Text(title.uppercased())
                .font(.system(size: 8, weight: .black))
                .tracking(1.2)
                .foregroundStyle(PixaTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.white.opacity(0.96))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 7)
    }
}

private struct StartupStep: View {
    let number: String
    let title: String
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(number)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.48))
            Text(title)
                .font(.system(size: isCompact ? 11 : 13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
