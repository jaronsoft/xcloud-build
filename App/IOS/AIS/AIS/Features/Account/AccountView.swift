import AuthenticationServices
import SwiftUI

struct AccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AISAppDataStore.self) private var appData
    @Environment(AISMediaRegionStore.self) private var mediaRegion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var presentsLogin = false
    @State private var confirmsDeletion = false
    @State private var showsFrozenPointsHelp = false
    @State private var cacheSize: Int64 = 0
    @State private var appleBindingRawNonce: String?
    @AppStorage("ais.recommend_to_gallery")
    private var recommendToGallery = true
    @AppStorage("ais.promo_mark_enabled")
    private var promoMarkEnabled = false

    var body: some View {
        ZStack {
            AISPageBackground()

            ScrollView {
                Group {
                    if horizontalSizeClass == .regular {
                        HStack(alignment: .top, spacing: 20) {
                            identityColumn
                                .frame(maxWidth: .infinity)
                            settingsColumn
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        compactContent
                    }
                }
                .frame(maxWidth: AISResponsiveLayout.maximumContentWidth)
                .padding(
                    .horizontal,
                    horizontalSizeClass == .regular ? 24 : 16
                )
                .padding(.top, 10)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                await appData.refreshUserData(session: session, force: true)
            }
        }
        .navigationTitle("account.title")
        .task {
            await refreshCacheSize()
        }
        .task(id: session.user?.id) {
            if session.isAuthenticated {
                await session.refreshAppleBindingStatus()
            }
        }
        .onAppear {
            Task {
                await refreshCacheSize()
                await appData.refreshPoints(session: session)
            }
        }
        .sheet(isPresented: $presentsLogin) {
            LoginView()
        }
        .alert("account.delete.title", isPresented: $confirmsDeletion) {
            Button("common.cancel", role: .cancel) {}
            Button("account.delete.confirm", role: .destructive) {
                Task {
                    await session.requestAccountDeletion()
                }
            }
        } message: {
            Text("account.delete.description")
        }
        .alert(
            "account.frozen_points.help.title",
            isPresented: $showsFrozenPointsHelp
        ) {
            Button("common.done", role: .cancel) {}
        } message: {
            Text("account.frozen_points.help.message")
        }
    }

    private var identityColumn: some View {
        VStack(spacing: 18) {
            accountAndMembership
            if session.isAuthenticated {
                invitationSection
            }
        }
    }

    private var settingsColumn: some View {
        VStack(spacing: 18) {
            preferenceSection
            storageSection
            if AppEnvironment.showsNetworkDiagnostics {
                diagnosticsLink
            }
            aboutLinks

            if let errorMessage = session.errorMessage {
                errorBanner(message: errorMessage)
            }

            if session.isAuthenticated {
                appleAccountSection
                deleteAccountSection
                signOutSection
            }
        }
    }

    private var compactContent: some View {
        VStack(spacing: 18) {
            accountAndMembership
            preferenceSection
            if session.isAuthenticated {
                invitationSection
            }
            storageSection
            if AppEnvironment.showsNetworkDiagnostics {
                diagnosticsLink
            }
            aboutLinks
            if let errorMessage = session.errorMessage {
                errorBanner(message: errorMessage)
            }
            if session.isAuthenticated {
                appleAccountSection
                deleteAccountSection
                signOutSection
            }
        }
    }

    @ViewBuilder
    private var accountAndMembership: some View {
        if let user = session.user {
            signedInHeader(user: user)
            billingSection
        } else {
            guestHeader
        }
    }

    private func signedInHeader(user: AuthUser) -> some View {
        HStack(spacing: 16) {
            accountAvatar(
                text: user.displayName ?? user.email ?? "AIS"
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(user.displayName ?? String(localized: "account.user"))
                    .font(.title3.bold())
                Text(user.email ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            membershipIcon
        }
        .padding(20)
        .aisSurface(cornerRadius: 26, hasShadow: true)
    }

    private var guestHeader: some View {
        VStack(spacing: 18) {
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 82, height: 82)
                .shadow(color: AISTheme.accent.opacity(0.36), radius: 22, y: 10)

            VStack(spacing: 7) {
                Text("account.guest")
                    .font(.title3.bold())
                Text("auth.required")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                presentsLogin = true
            } label: {
                Text("account.signin")
                    .aisPrimaryButton()
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .aisSurface(cornerRadius: 26, hasShadow: true)
    }

    private func accountAvatar(text: String) -> some View {
        Text(String(text.prefix(1)).uppercased())
            .font(.title2.bold())
            .foregroundStyle(.white)
            .frame(width: 58, height: 58)
            .background(AISTheme.accentGradient, in: Circle())
            .accessibilityHidden(true)
    }

    private var signOutSection: some View {
        Button {
            session.signOut()
        } label: {
            SettingsRow(
                title: "account.signout",
                systemImage: "rectangle.portrait.and.arrow.right",
                tint: AISTheme.accent
            )
        }
        .buttonStyle(.plain)
        .aisSurface(cornerRadius: 22)
    }

    private var appleAccountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("account.security")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                if let status = session.appleBindingStatus {
                    if status.isBound {
                        SettingsRow(
                            verbatimTitle: String(localized: "account.apple.bound"),
                            systemImage: "apple.logo",
                            tint: .primary
                        )
                    } else {
                        SignInWithAppleButton(.continue) { request in
                            let nonce = SessionStore.makeNonce()
                            appleBindingRawNonce = nonce
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = SessionStore.sha256(nonce)
                        } onCompletion: { result in
                            handleAppleBindingResult(result)
                        }
                        .signInWithAppleButtonStyle(
                            colorScheme == .dark ? .white : .black
                        )
                        .frame(height: 50)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )
                        .disabled(session.isWorking)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                        Text("account.apple.bind.helper")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("account.apple.status.loading")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
            .aisSurface(cornerRadius: 22)
        }
    }

    private func handleAppleBindingResult(
        _ result: Result<ASAuthorization, any Error>
    ) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential
                as? ASAuthorizationAppleIDCredential,
                  let rawNonce = appleBindingRawNonce else {
                session.errorMessage = String(localized: "auth.apple.expired")
                return
            }
            appleBindingRawNonce = nil
            Task {
                await session.bindAppleIdentity(
                    credential: credential,
                    rawNonce: rawNonce
                )
            }
        case let .failure(error):
            appleBindingRawNonce = nil
            if (error as? ASAuthorizationError)?.code != .canceled {
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private var deleteAccountSection: some View {
        Button {
            confirmsDeletion = true
        } label: {
            SettingsRow(
                title: "account.delete",
                systemImage: "trash",
                tint: .red
            )
        }
        .buttonStyle(.plain)
        .aisSurface(cornerRadius: 22)
    }

    private var billingSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                billingMetric(
                    title: "account.available_points",
                    value: appData.billing.balance?.availablePoints,
                    systemImage: "sparkles"
                )
                billingMetric(
                    title: "account.frozen_points",
                    value: appData.billing.balance?.frozenPoints,
                    systemImage: "snowflake",
                    helpAction: {
                        showsFrozenPointsHelp = true
                    }
                )
            }

            HStack(spacing: 12) {
                billingMetric(
                    title: "account.subscription_points",
                    value: appData.billing.balance?.subscriptionPoints,
                    systemImage: "calendar.badge.clock"
                )
                billingMetric(
                    title: "account.permanent_points",
                    value: appData.billing.balance?.balancePoints,
                    systemImage: "infinity"
                )
            }

            if let balance = appData.billing.balance,
               let discount = balance.effectiveDiscountPercent,
               discount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "account.effective_discount"),
                            balance.effectiveBenefitName
                                ?? balance.effectiveMembershipBenefitName
                                ?? String(localized: "creation.membership.default"),
                            NSDecimalNumber(decimal: discount).doubleValue
                        )
                    )
                    .font(.subheadline.weight(.semibold))
                    Text("account.discount_policy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let expiresAt = balance.subscriptionPointsExpiresAt,
                       balance.subscriptionPoints > 0 {
                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "account.subscription_expires"),
                                expiresAt
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .aisSurface(cornerRadius: 20)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("account.membership")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    membershipValue
                }
                Spacer()
                NavigationLink {
                    AccountTransactionsView(model: appData.billing)
                } label: {
                    Label("account.transactions", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .aisSurface(cornerRadius: 20)

            if let packages = appData.billing.membership?.recommendedPackages,
               packages.contains(where: \.iosEnabled) {
                NavigationLink {
                    StoreKitPurchaseView(
                        region: mediaRegion.effectiveRegion.storeKitCountryCode
                    )
                } label: {
                    SettingsRow(
                        title: "storekit.title",
                        systemImage: "cart.fill",
                        tint: AISTheme.accent,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                .aisSurface(cornerRadius: 20)
            }

            if appData.userDataState == .failed {
                Button {
                    Task {
                        await appData.retryGenerationPrerequisites(
                            session: session
                        )
                    }
                } label: {
                    Label(
                        "account.data.retry",
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func billingMetric(
        title: LocalizedStringKey,
        value: Int?,
        systemImage: String,
        helpAction: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Label(title, systemImage: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let helpAction {
                    Button(action: helpAction) {
                        Image(systemName: "questionmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        Text("account.frozen_points.help.title")
                    )
                }
            }
            HStack(spacing: 8) {
                if let value {
                    Text(value, format: .number)
                        .font(.title2.bold().monospacedDigit())
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("account.data.loading")
                }
                if value != nil && appData.isRefreshingUserData {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("account.data.refreshing")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .aisSurface(cornerRadius: 20)
    }

    @ViewBuilder
    private var membershipValue: some View {
        if let name = appData.billing.membership?.currentLevelName
            ?? appData.billing.balance?.effectiveMembershipBenefitName {
            HStack(spacing: 8) {
                Text(name)
                    .font(.headline)
                if appData.isRefreshingUserData {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("account.data.refreshing")
                }
            }
        } else {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("account.data.loading")
        }
    }

    @ViewBuilder
    private var membershipIcon: some View {
        if appData.billing.membership != nil
            || appData.billing.balance?.effectiveMembershipBenefitName != nil {
            HStack(spacing: 5) {
                Image(membershipIconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                if appData.isRefreshingUserData {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .accessibilityLabel(Text("account.membership"))
        } else {
            ProgressView()
                .frame(width: 58, height: 58)
                .accessibilityLabel("account.data.loading")
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    private var aboutLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("account.about")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                NavigationLink {
                    LegalDocumentView(document: .privacy)
                } label: {
                    SettingsRow(
                        title: "account.privacy",
                        systemImage: "hand.raised",
                        tint: AISTheme.accent,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                Divider()
                    .padding(.leading, 54)
                NavigationLink {
                    LegalDocumentView(document: .terms)
                } label: {
                    SettingsRow(
                        title: "account.terms",
                        systemImage: "doc.text",
                        tint: AISTheme.accent,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                Divider()
                    .padding(.leading, 54)
                accountLink(
                    title: "account.support",
                    systemImage: "questionmark.bubble",
                    url: "https://ais.jaronsoft.com/contact"
                )
                Divider()
                    .padding(.leading, 54)

                infoRow(
                    title: "account.about.global_operator",
                    value: String(localized: "account.about.global_operator_value"),
                    systemImage: "globe"
                )
                Divider()
                    .padding(.leading, 54)

                infoRow(
                    title: "account.about.china_distributor",
                    value: String(localized: "account.about.china_distributor_value"),
                    systemImage: "building.2"
                )
                Divider()
                    .padding(.leading, 54)

                infoRow(
                    title: "account.about.app_version",
                    value: appVersionString,
                    systemImage: "info.circle"
                )
            }
            .aisSurface(cornerRadius: 22)
        }
    }

    private func infoRow(
        title: LocalizedStringKey,
        value: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.bold())
                .foregroundStyle(AISTheme.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("account.storage")
                .font(.headline)
                .padding(.horizontal, 4)

            NavigationLink {
                CacheManagementView()
            } label: {
                SettingsRow(
                    verbatimTitle: cacheClearTitle,
                    systemImage: "externaldrive.badge.xmark",
                    tint: AISTheme.accentWarm,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .aisSurface(cornerRadius: 22)
        }
    }

    private var preferenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("account.preferences")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if session.isAuthenticated {
                    NavigationLink {
                        MemoryCenterView()
                    } label: {
                        SettingsRow(
                            title: "memory.title",
                            systemImage: "brain.head.profile",
                            tint: AISTheme.accent,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 16)
                }
                Toggle(isOn: $recommendToGallery) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("account.gallery_preference")
                        Text("account.gallery_preference.helper")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                Divider().padding(.leading, 16)
                Toggle(isOn: $promoMarkEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("account.promo_mark_preference")
                        Text("account.promo_mark_preference.helper")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .tint(AISTheme.accent)
            .aisSurface(cornerRadius: 22)
        }
    }

    private var invitationSection: some View {
        NavigationLink {
            InvitationView()
        } label: {
            SettingsRow(
                title: "invitation.title",
                systemImage: "gift.fill",
                tint: AISTheme.accentWarm,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .aisSurface(cornerRadius: 22)
    }

    private var membershipIconName: String {
        AISMembershipLevel.iconName(
            code: appData.billing.membership?.currentLevelCode,
            name: appData.billing.membership?.currentLevelName
                ?? appData.billing.balance?.effectiveMembershipBenefitName
        )
    }

    private var diagnosticsLink: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("diagnostics.section")
                .font(.headline)
                .padding(.horizontal, 4)

            NavigationLink {
                NetworkDiagnosticsView()
            } label: {
                SettingsRow(
                    title: "diagnostics.title",
                    systemImage: "network",
                    tint: AISTheme.accentSecondary,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .aisSurface(cornerRadius: 22)
        }
    }

    private func accountLink(
        title: LocalizedStringKey,
        systemImage: String,
        url: String
    ) -> some View {
        Link(destination: URL(string: url)!) {
            SettingsRow(
                title: title,
                systemImage: systemImage,
                tint: AISTheme.accent,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(message: String) -> some View {
        Label {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var cacheClearTitle: String {
        String.localizedStringWithFormat(
            String(localized: "account.cache.clear"),
            ByteCountFormatter.string(
                fromByteCount: cacheSize,
                countStyle: .file
            )
        )
    }

    private func refreshCacheSize() async {
        let imageSize = await AISImageCache.shared.diskSize()
        let responseSize = await AISResponseCache.shared.diskSize()
        cacheSize = imageSize + responseSize
    }
}

private struct SettingsRow: View {
    let title: Text
    let systemImage: String
    let tint: Color
    var showsChevron = false
    var showsProgress = false

    init(
        title: LocalizedStringKey,
        systemImage: String,
        tint: Color,
        showsChevron: Bool = false
    ) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.tint = tint
        self.showsChevron = showsChevron
    }

    init(
        verbatimTitle: String,
        systemImage: String,
        tint: Color,
        showsChevron: Bool = false,
        showsProgress: Bool = false
    ) {
        title = Text(verbatimTitle)
        self.systemImage = systemImage
        self.tint = tint
        self.showsChevron = showsChevron
        self.showsProgress = showsProgress
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            title
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            if showsProgress {
                ProgressView()
                    .tint(tint)
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

#Preview("AccountView") {
    NavigationStack {
        AccountView()
    }
    .environment(SessionStore())
    .environment(AISAppDataStore())
    .environment(AISMediaRegionStore())
}
