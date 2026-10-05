import AuthenticationServices
import SwiftUI

struct AccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PixaNotificationStore.self) private var notifications
    @Environment(PixaNavigationStore.self) private var navigation
    @Environment(PixaLanguageStore.self) private var language
    @Environment(PixaAppUpdateStore.self) private var appUpdate
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsLogin = false
    @State private var appleBindingRawNonce: String?
    @State private var appleBindingErrorMessage: String?
    @State private var accountPath: [PixaAccountDestination] = []
    @AppStorage("pixarivo.network_diagnostics_unlocked")
    private var networkDiagnosticsUnlocked = false
    var body: some View {
        NavigationStack(path: $accountPath) {
            VStack(spacing: 0) {
                compactHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                List {
                    Section {
                        if session.isAuthenticated {
                            profileHeader
                        } else {
                            Button("auth.login") { showsLogin = true }
                        }
                    }

                    if session.isAuthenticated {
                        Section("account.name") {
                            NavigationLink { PointsCenterView() } label: { Label("points.center.title", systemImage: "sparkles") }
                            NavigationLink { MembershipView() } label: { Label("membership.title", systemImage: "crown") }
                            NavigationLink { PixaPointTransactionsView() } label: {
                                Label("account.transactions", systemImage: "list.bullet.rectangle")
                            }
                            NavigationLink { PixaNotificationsView() } label: {
                                HStack {
                                    Label("notification.center.title", systemImage: "bell")
                                    Spacer()
                                    if notifications.unreadCount > 0 {
                                        Text(notifications.unreadCount > 99 ? "99+" : "\(notifications.unreadCount)")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(PixaTheme.accent, in: Capsule())
                                    }
                                }
                            }
                        }
                    }

                    if session.isAuthenticated && shouldShowAppleAccountSection {
                        Section("account.apple.account") {
                            appleAccountSection
                        }
                    }

                    Section("account.preferences") {
                        NavigationLink {
                            PixaLanguageSettingsView()
                        } label: {
                            LabeledContent {
                                Text(languageName(language.preference))
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label("account.current_language", systemImage: "character.bubble")
                            }
                        }
                        NavigationLink {
                            PixaMediaRegionSettingsView()
                        } label: {
                            Label("account.media_region", systemImage: "globe.asia.australia")
                        }
                        NavigationLink {
                            PixaCacheManagementView()
                        } label: {
                            Label("cache.title", systemImage: "externaldrive.badge.xmark")
                        }
                        NavigationLink {
                            NetworkTestView()
                        } label: {
                            Label("diagnostics.network_test", systemImage: "network.badge.shield.half.filled")
                        }
                    }

                    Section("account.about") {
                        NavigationLink {
                            PixaHelpAndLegalView()
                        } label: {
                            Label("account.help_and_legal", systemImage: "lifepreserver")
                        }
                        NavigationLink {
                            PixaAppUpdateView()
                        } label: {
                            HStack {
                                Label("app_update.title", systemImage: "arrow.down.app")
                                Spacer()
                                if appUpdate.hasUnseenUpdate {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 8, height: 8)
                                        .accessibilityLabel(Text("app_update.available"))
                                }
                            }
                        }
                        Link(destination: AppConfiguration.xURL) {
                            Label("account.x", systemImage: "at")
                        }
                        LabeledContent("account.company", value: AppConfiguration.companyName)
                        LabeledContent("account.version", value: AppConfiguration.releaseLabel)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 5) {
                                networkDiagnosticsUnlocked = true
                            }
                    }
                    if networkDiagnosticsUnlocked {
                        Section("diagnostics.title") {
                            NavigationLink {
                                NetworkDiagnosticsView()
                            } label: {
                                Label("diagnostics.entry", systemImage: "network")
                            }
                        }
                    }
                    if session.isAuthenticated {
                        Section {
                            Button("auth.signout", role: .destructive) {
                                session.signOut()
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 4, for: .scrollContent)
            }
            .background(PixaTheme.paper)
            .background(
                PixaNavigationPopObserver(
                    revision: navigation.popRevision(for: .account)
                )
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PixaAccountDestination.self) { destination in
                switch destination {
                case .points: PointsCenterView()
                case .transactions: PixaPointTransactionsView()
                case .membership: MembershipView()
                case .notifications: PixaNotificationsView()
                case .profileAvatar: ProfileEditView(mode: .avatar)
                case .profileNickname: ProfileEditView(mode: .nickname)
                }
            }
            .sheet(isPresented: $showsLogin) { LoginView() }
            .onChange(of: navigation.opensReferralRegistration, initial: true) { _, opens in
                guard opens else { return }
                showsLogin = true
            }
            .task(id: session.user?.id) {
                guard session.isAuthenticated else { return }
                _ = try? await session.fetchProfile()
                // 服务器状态是最终依据，避免长期使用“未绑定”的旧缓存。
                await session.refreshAppleBindingStatus(force: true)
            }
            .onChange(of: navigation.pendingAccountRoute, initial: true) { _, route in
                guard let route else { return }
                switch route {
                case "points": accountPath.append(.points)
                case "transactions": accountPath.append(.transactions)
                case "membership": accountPath.append(.membership)
                default: accountPath.append(.notifications)
                }
                navigation.pendingAccountRoute = nil
            }
        }
    }

    private func languageName(_ preference: PixaLanguagePreference) -> LocalizedStringKey {
        switch preference {
        case .system: "account.language.system"
        case .simplifiedChinese: "account.language.chinese"
        case .traditionalChinese: "account.language.traditional_chinese"
        case .english: "account.language.english"
        case .spanish: "account.language.spanish"
        case .portuguese: "account.language.portuguese"
        case .japanese: "account.language.japanese"
        }
    }

    private var shouldShowAppleAccountSection: Bool {
        session.appleBindingStatus?.isBound != true
    }

    @ViewBuilder
    private var appleAccountSection: some View {
        if (!session.hasResolvedAppleBindingStatus || session.isLoadingAppleBindingStatus)
            && session.appleBindingStatus?.isBound != true {
            HStack(spacing: 10) {
                ProgressView()
                Text("account.apple.status.loading")
                    .foregroundStyle(.secondary)
            }
        } else if session.appleBindingStatus?.isBound == true {
            EmptyView()
        } else if let error = session.appleBindingStatusError?.nilIfEmpty {
            appleStatusErrorCard(error)
        } else if session.appleBindingStatus?.isBound == false {
            VStack(alignment: .leading, spacing: 10) {
                Label("account.apple.unbound.title", systemImage: "apple.logo")
                    .font(.headline)
                if let error = appleBindingErrorMessage?.nilIfEmpty {
                    appleBindingErrorCard(error)
                } else {
                    Text("account.apple.unbound.message")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    appleBindingButton
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func appleStatusErrorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("account.apple.status.failed", systemImage: "arrow.clockwise.circle.fill")
                .font(.subheadline.bold())
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("common.retry") {
                Task { await session.refreshAppleBindingStatus(force: true) }
            }
            .buttonStyle(.bordered)
            .tint(PixaTheme.accent)
        }
        .padding(.vertical, 6)
    }

    private var appleBindingButton: some View {
        ZStack {
            SignInWithAppleButton(.continue) { request in
                prepareAppleBindingRequest(request)
            } onCompletion: { result in
                handleAppleBindingResult(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .opacity(session.isWorking ? 0 : 1)

            if session.isWorking {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("account.apple.binding")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            }
        }
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .disabled(session.isWorking)
    }

    private func appleBindingErrorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("account.apple.bind_failed", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.red)
            Text(error)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("account.apple.retry_hint")
                .font(.caption)
                .foregroundStyle(.secondary)
            appleBindingButton
        }
        .padding(14)
        .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.red.opacity(0.22))
        }
    }

    private func prepareAppleBindingRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = SessionStore.makeNonce()
        appleBindingRawNonce = nonce
        appleBindingErrorMessage = nil
        session.errorMessage = nil
        request.requestedScopes = [.fullName, .email]
        request.nonce = SessionStore.sha256(nonce)
    }

    private func handleAppleBindingResult(
        _ result: Result<ASAuthorization, any Error>
    ) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let rawNonce = appleBindingRawNonce else {
                session.errorMessage = AppLanguage.localized("auth.apple.expired")
                return
            }
            appleBindingRawNonce = nil
            Task {
                await session.bindAppleIdentity(
                    credential: credential,
                    rawNonce: rawNonce
                )
                if session.appleBindingStatus?.isBound != true {
                    appleBindingErrorMessage = session.errorMessage?.nilIfEmpty
                        ?? AppLanguage.localized("account.apple.bind_failed_fallback")
                }
            }
        case let .failure(error):
            appleBindingRawNonce = nil
            appleBindingErrorMessage = PixaAppleAuthorizationErrorPresenter.message(for: error)
        }
    }

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(PixaTheme.accent)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("account.eyebrow")
                    .font(.caption2.bold())
                    .tracking(1.3)
                    .foregroundStyle(PixaTheme.accent)
                Text("account.title")
                    .font(.system(.title2, design: .serif, weight: .bold))
            }
            Spacer()
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            Button {
                accountPath.append(.profileAvatar)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    AccountAvatarView(
                        userID: session.user?.id,
                        url: resolvedAccountURL(session.user?.avatarURL),
                        fallback: session.user?.displayName ?? session.user?.email,
                        size: 62
                    )
                    Image(systemName: "camera.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(PixaTheme.accent, in: Circle())
                        .overlay { Circle().stroke(.white, lineWidth: 2) }
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("profile.change_avatar"))

            Button {
                accountPath.append(.profileNickname)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.user?.displayName?.nilIfEmpty ?? AppLanguage.localized("profile.unnamed"))
                            .font(.headline)
                            .foregroundStyle(PixaTheme.ink)
                        if let email = session.user?.email?.nilIfEmpty {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Image(systemName: "pencil")
                        .font(.caption.bold())
                        .foregroundStyle(PixaTheme.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("profile.change_nickname"))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

private enum PixaAccountDestination: Hashable {
    case points
    case transactions
    case membership
    case notifications
    case profileAvatar
    case profileNickname
}

private struct PixaLanguageSettingsView: View {
    @Environment(PixaLanguageStore.self) private var language
    @Environment(SessionStore.self) private var session

    var body: some View {
        List {
            Section {
                ForEach(PixaLanguagePreference.allCases) { preference in
                    Button {
                        language.select(preference)
                        Task {
                            await PixaPushNotificationService.shared.synchronize(session: session)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(flag(preference))
                                .font(.system(size: 22))
                                .frame(width: 32, height: 32)
                                .background(
                                    PixaTheme.accent.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title(preference))
                                    .foregroundStyle(.primary)
                                if preference == .system {
                                    Text("account.language.system_hint")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if language.preference == preference {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(PixaTheme.accent)
                            }
                        }
                    }
                    .accessibilityAddTraits(
                        language.preference == preference ? .isSelected : []
                    )
                }
            } footer: {
                Text("account.language.switch_hint")
            }
        }
        .scrollContentBackground(.hidden)
        .background(PixaTheme.paper)
        .navigationTitle("account.language")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func title(_ preference: PixaLanguagePreference) -> LocalizedStringKey {
        switch preference {
        case .system: "account.language.system"
        case .simplifiedChinese: "account.language.chinese"
        case .traditionalChinese: "account.language.traditional_chinese"
        case .english: "account.language.english"
        case .spanish: "account.language.spanish"
        case .portuguese: "account.language.portuguese"
        case .japanese: "account.language.japanese"
        }
    }

    private func flag(_ preference: PixaLanguagePreference) -> String {
        switch preference {
        case .system: "🌐"
        case .simplifiedChinese: "🇨🇳"
        case .traditionalChinese: "🇭🇰"
        case .english: "🇺🇸"
        case .spanish: "🇪🇸"
        case .portuguese: "🇧🇷"
        case .japanese: "🇯🇵"
        }
    }
}

private struct PixaHelpAndLegalView: View {
    var body: some View {
        List {
            Section("account.help") {
                Link(destination: AppConfiguration.supportURL) {
                    Label("account.support", systemImage: "lifepreserver")
                }
            }

            Section("account.legal") {
                Link(destination: AppConfiguration.privacyURL) {
                    Label("account.privacy", systemImage: "hand.raised")
                }
                Link(destination: AppConfiguration.uploadComplianceURL) {
                    Label("account.upload_compliance", systemImage: "photo.on.rectangle.angled")
                }
                Link(destination: AppConfiguration.galleryIntellectualPropertyURL) {
                    Label("account.gallery_ip", systemImage: "rectangle.stack.badge.person.crop")
                }
                Link(destination: AppConfiguration.termsURL) {
                    Label("account.terms", systemImage: "doc.text")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PixaTheme.paper)
        .navigationTitle("account.help_and_legal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct PixaMediaRegionSettingsView: View {
    @Environment(PixaMediaRegionStore.self) private var mediaRegion

    var body: some View {
        List {
            Section {
                ForEach(PixaMediaRegionPreference.allCases) { preference in
                    Button {
                        Task { await mediaRegion.select(preference) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title(preference)).foregroundStyle(.primary)
                                if preference == .automatic {
                                    Text("account.media_region.auto_hint")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if mediaRegion.preference == preference {
                                Image(systemName: "checkmark")
                                    .font(.body.bold())
                                    .foregroundStyle(PixaTheme.accent)
                            }
                        }
                    }
                    .accessibilityAddTraits(
                        mediaRegion.preference == preference ? .isSelected : []
                    )
                }
            } footer: {
                Text("account.media_region.hint")
            }
            Section("account.media_region.effective") {
                Label(
                    mediaRegion.effectiveValue == "cn"
                        ? AppLanguage.localized("account.media_region.china")
                        : AppLanguage.localized("account.media_region.international"),
                    systemImage: mediaRegion.effectiveValue == "cn" ? "location.fill" : "globe"
                )
            }
        }
        .navigationTitle("account.media_region")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func title(_ preference: PixaMediaRegionPreference) -> LocalizedStringKey {
        switch preference {
        case .automatic: "account.media_region.automatic"
        case .china: "account.media_region.china"
        case .international: "account.media_region.international"
        }
    }
}

struct AccountAvatarView: View {
    let userID: String?
    let url: URL?
    let fallback: String?
    let size: CGFloat
    @State private var image: UIImage?
    @State private var cacheRevision = 0

    init(userID: String? = nil, url: URL?, fallback: String?, size: CGFloat) {
        self.userID = userID
        self.url = url
        self.fallback = fallback
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle().fill(PixaTheme.accent.opacity(0.12))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else if let url, userID == nil {
                RemoteArtwork(url: url, aspectRatio: 1, preset: .thumbnail, maximumPixelWidth: 320)
                    .clipShape(Circle())
            } else {
                Text(initial)
                    .font(.title2.bold())
                    .foregroundStyle(PixaTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(.white.opacity(0.85), lineWidth: 2) }
        .task(id: "\(userID ?? "")|\(url?.absoluteString ?? "")|\(cacheRevision)") {
            guard let userID, let url else { return }
            image = try? await PixaAvatarCache.shared.image(userID: userID, url: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pixaAvatarCacheDidChange)) { notification in
            guard notification.object as? String == userID else { return }
            image = nil
            cacheRevision += 1
        }
    }

    private var initial: String {
        guard let first = fallback?.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "P"
        }
        return String(first).uppercased()
    }
}

func resolvedAccountURL(_ value: String?) -> URL? {
    guard let value = value?.nilIfEmpty else { return nil }
    if let url = URL(string: value), url.scheme != nil { return url }
    return URL(string: value, relativeTo: AppConfiguration.apiBaseURL)?.absoluteURL
}
