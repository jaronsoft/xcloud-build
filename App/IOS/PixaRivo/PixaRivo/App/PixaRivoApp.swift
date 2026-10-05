import SwiftUI
import Observation
import UserNotifications
import UIKit

final class PixaAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        PixaBackgroundTransferManager.shared.restore()
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == PixaBackgroundTransferManager.sessionIdentifier else {
            completionHandler()
            return
        }
        PixaBackgroundTransferManager.shared.handleEvents(
            completionHandler: completionHandler
        )
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PixaPushNotificationService.shared.receiveDeviceToken(deviceToken)
        NotificationCenter.default.post(name: .pixaPushDeviceTokenChanged, object: nil)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // APNs 注册失败通常由网络或签名能力导致，下一次进入前台时会重新尝试。
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        // iOS 27 会在通知回调完成后立即执行 UIKit 状态恢复，必须让 completion 在主线程返回。
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .pixaRemoteNotificationReceived,
                object: nil
            )
            completionHandler([.banner, .sound, .badge])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        func stringValue(_ key: String) -> String? {
            guard let value = userInfo[key], !(value is NSNull) else { return nil }
            let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        let destination = PixaNotificationDestination(
            route: stringValue("route"),
            referenceID: stringValue("referenceId"),
            referenceType: stringValue("referenceType"),
            notificationID: stringValue("notificationId"),
            isDigest: stringValue("type") == "notification.digest"
        )
        // 避免 async 代理桥接在并发工作线程调用 UIKit 的完成回调而触发主线程断言。
        DispatchQueue.main.async {
            PixaNotificationLaunchTargetStore.shared.save(destination)
            NotificationCenter.default.post(
                name: .pixaRemoteNotificationOpened,
                object: destination
            )
            completionHandler()
        }
    }
}

enum PixaRootTab: Hashable {
    case home
    case gallery
    case templates
    case works
    case account
}

@MainActor
@Observable
final class PixaNavigationStore {
    var selectedTab: PixaRootTab = .home
    private(set) var worksRevision = 0
    var pendingAccountRoute: String?
    private(set) var pendingTemplateID: String?
    private(set) var pendingNotificationID: String?
    var opensReferralRegistration = false
    private var popRevisions: [PixaRootTab: Int] = [:]

    func selectFromTabBar(_ tab: PixaRootTab) {
        guard selectedTab == tab else {
            selectedTab = tab
            return
        }
        // 重复点击当前栏目时每次只通知导航栈回退一级，保留更深层级的返回路径。
        popRevisions[tab, default: 0] += 1
    }

    func popRevision(for tab: PixaRootTab) -> Int {
        popRevisions[tab, default: 0]
    }

    func showWorks() {
        selectedTab = .works
        worksRevision += 1
    }

    func openNotificationRoute(
        _ route: String?,
        referenceID: String? = nil,
        notificationID: String? = nil
    ) {
        switch route?.lowercased() {
        case "works":
            showWorks()
        case "templates":
            pendingTemplateID = referenceID?.nilIfEmpty
            pendingNotificationID = notificationID?.nilIfEmpty
            selectedTab = .templates
        case "points", "transactions", "membership", "notifications":
            pendingAccountRoute = route?.lowercased()
            selectedTab = .account
        default:
            pendingAccountRoute = "notifications"
            selectedTab = .account
        }
    }

    func consumePendingTemplate() {
        pendingTemplateID = nil
        pendingNotificationID = nil
    }

    func openReferralRegistration() {
        opensReferralRegistration = true
        selectedTab = .account
    }
}

struct PixaPendingWorkPlaceholder: Identifiable, Sendable {
    let id: String
    let title: String
    let aspectRatio: String
    let submittedAt: Date
}

@MainActor
@Observable
final class PixaWorkActivityStore {
    private struct ObservedJob {
        let title: String
        let status: String
        let submittedAt: Date
        let aspectRatio: String
    }

    private let api = APIClient()
    private(set) var activeCount = 0
    private(set) var latestJobs: [TaskJob] = []
    private(set) var refreshRevision = 0
    private var isRefreshing = false
    private var observedJobs: [String: ObservedJob] = [:]

    var hasPendingCreatedJobs: Bool { !observedJobs.isEmpty }

    var pendingWorkPlaceholders: [PixaPendingWorkPlaceholder] {
        let visibleJobIDs = Set(latestJobs.map(\.id))
        return observedJobs.compactMap { id, job in
            guard !visibleJobIDs.contains(id) else { return nil }
            return PixaPendingWorkPlaceholder(
                id: id,
                title: job.title,
                aspectRatio: job.aspectRatio,
                submittedAt: job.submittedAt
            )
        }
        .sorted { $0.submittedAt > $1.submittedAt }
    }

    func markSubmitted(jobID: String, title: String, aspectRatio: String) {
        observedJobs[jobID] = ObservedJob(
            title: title,
            status: "queued",
            submittedAt: .now,
            aspectRatio: aspectRatio
        )
        activeCount = observedJobs.count
    }

    private func update(using jobs: [TaskJob]) {
        let trackedIDs = Set(observedJobs.keys)
        let trackedJobs = jobs.filter { trackedIDs.contains($0.id) }
        latestJobs = trackedJobs
        for job in trackedJobs {
            if job.isActive {
                observedJobs[job.id] = ObservedJob(
                    title: job.title,
                    status: job.status,
                    submittedAt: observedJobs[job.id]?.submittedAt ?? .now,
                    aspectRatio: observedJobs[job.id]?.aspectRatio
                        ?? job.aspectRatio
                        ?? "4:5"
                )
            } else {
                observedJobs[job.id] = nil
            }
        }
        activeCount = observedJobs.count
        refreshRevision += 1
    }

    func refresh(token: String?, userID: String?) async {
        guard hasPendingCreatedJobs else { return }
        guard let token, let userID else {
            reset()
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let page: PageResponse<TaskJob> = try await api.getCached(
                "/api/ais/jobs",
                query: [
                    .init(name: "page", value: "1"),
                    .init(name: "size", value: "30"),
                    .init(name: "jobType", value: "style_template_generate"),
                    .init(name: "includeTotal", value: "true"),
                    .init(name: "summaryOnly", value: "true")
                ],
                token: token,
                forceRefresh: true,
                cacheScope: "works-user-\(userID)"
            )
            guard !Task.isCancelled else { return }
            update(using: page.items)
        } catch {
            // 保留最近一次数量，避免短暂网络错误让角标闪烁或错误归零。
        }
    }

    /// 根据已提交任务的等待时间调整状态刷新频率；常规生成时长内无需高频轮询。
    func nextRefreshInterval(now: Date = .now) -> TimeInterval {
        guard let earliestSubmission = observedJobs.values
            .map(\.submittedAt)
            .min() else {
            return 20
        }
        return now.timeIntervalSince(earliestSubmission) < 2 * 60 ? 15 : 20
    }

    func reset() {
        activeCount = 0
        latestJobs = []
        refreshRevision = 0
        observedJobs = [:]
    }

    private func isActive(status: String) -> Bool {
        ["queued", "pending", "processing", "running"].contains(status.lowercased())
    }
}

@main
struct PixaRivoApp: App {
    @UIApplicationDelegateAdaptor(PixaAppDelegate.self) private var appDelegate
    @State private var session = SessionStore()
    @State private var accountData = PixaAccountDataStore()
    @State private var storeKitSync = PixaStoreKitTransactionSync()
    @State private var navigation = PixaNavigationStore()
    @State private var workActivity = PixaWorkActivityStore()
    @State private var creationSubmissions = PixaCreationSubmissionStore()
    @State private var mediaRegion = PixaMediaRegionStore()
    @State private var language = PixaLanguageStore()
    @State private var notifications = PixaNotificationStore()
    @State private var durationEstimates = PixaDurationEstimateStore()
    @State private var referralAttribution = PixaReferralAttributionStore()
    @State private var appUpdate = PixaAppUpdateStore()

    var body: some Scene {
        // WindowGroup 的内容会被 SwiftUI 延迟到异步渲染线程求值，因此先在主 Actor 构造根视图。
        let rootView = PixaAppRootView(
            session: session,
            accountData: accountData,
            storeKitSync: storeKitSync,
            navigation: navigation,
            workActivity: workActivity,
            creationSubmissions: creationSubmissions,
            mediaRegion: mediaRegion,
            language: language,
            notifications: notifications,
            durationEstimates: durationEstimates,
            referralAttribution: referralAttribution,
            appUpdate: appUpdate
        )

        WindowGroup {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PixaIAPReviewScreenshot") {
                PixaIAPReviewScreenshotView(
                    region: Self.reviewScreenshotRegion
                )
                .environment(\.locale, language.locale)
                .tint(PixaTheme.accent)
            } else {
                rootView
            }
#else
            rootView
#endif
        }
    }

#if DEBUG
    private static var reviewScreenshotRegion: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PixaIAPReviewRegion"),
              arguments.indices.contains(index + 1) else { return "CN" }
        return arguments[index + 1].uppercased() == "US" ? "US" : "CN"
    }
#endif
}

private struct PixaAppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsStartupExperience = true
    @State private var showsComplianceConsent = false
    @State private var showsAppUpdatePrompt = false
    @State private var maintenanceStatus: PixaMaintenanceStatus?

    let session: SessionStore
    let accountData: PixaAccountDataStore
    let storeKitSync: PixaStoreKitTransactionSync
    let navigation: PixaNavigationStore
    let workActivity: PixaWorkActivityStore
    let creationSubmissions: PixaCreationSubmissionStore
    let mediaRegion: PixaMediaRegionStore
    let language: PixaLanguageStore
    let notifications: PixaNotificationStore
    let durationEstimates: PixaDurationEstimateStore
    let referralAttribution: PixaReferralAttributionStore
    let appUpdate: PixaAppUpdateStore
    @AppStorage("pixarivo.push_explainer_shown") private var pushExplainerShown = false
    @State private var showsPushExplainer = false

    var body: some View {
        ZStack {
            RootView()
                .modifier(PixaMaintenancePrompt(status: $maintenanceStatus))
                .allowsHitTesting(!showsStartupExperience)
            if showsStartupExperience {
                StartupExperienceView {
                    showsStartupExperience = false
                }
                .zIndex(10)
            }
        }
        .environment(session)
        .environment(accountData)
        .environment(navigation)
        .environment(workActivity)
        .environment(creationSubmissions)
        .environment(mediaRegion)
        .environment(language)
        .environment(notifications)
        .environment(durationEstimates)
        .environment(referralAttribution)
        .environment(appUpdate)
        .environment(\.locale, language.locale)
        .tint(PixaTheme.accent)
        .task(id: session.user?.id) {
            if let status = await PixaMaintenanceService.checkGeneration() {
                maintenanceStatus = status
            }
            await AppAPIRouter.shared.bootstrap(product: "pixarivo")
            await appUpdate.check()
            let token = session.isAuthenticated
                ? await session.validAccessToken()
                : nil
            if token != nil {
                await session.pingActivity()
            }
            await mediaRegion.refresh(accountCountryCode: session.user?.countryCode)
            if let destination = PixaNotificationLaunchTargetStore.shared.take() {
                openNotificationDestination(destination)
            }
            await PixaImageDeliveryStore.shared.load(
                forceRefresh: token != nil,
                token: token
            )
            await accountData.load(session: session, force: true)
            await durationEstimates.load(accessToken: token)
            // 首屏已可展示后预热内容页数据，不阻塞启动流程。
            Task { await PixaLaunchContentPreloader.shared.preload() }
            if session.isAuthenticated {
                await notifications.refreshUnreadCount(session: session)
                let enabled = await PixaPushNotificationService.shared.refreshConfiguration()
                let authorizationStatus = await PixaPushNotificationService.shared.authorizationStatus()
                if enabled && !pushExplainerShown && authorizationStatus == .notDetermined {
                    showsPushExplainer = true
                } else {
                    await PixaPushNotificationService.shared.registerForRemoteNotifications()
                    await PixaPushNotificationService.shared.synchronize(session: session)
                }
                await session.refreshComplianceConsent()
                storeKitSync.start(session: session)
                await storeKitSync.sync(session: session)
            }
        }
        .task(id: session.user?.countryCode) {
            await mediaRegion.refresh(accountCountryCode: session.user?.countryCode)
        }
        .task(id: "\(session.user?.id ?? "")|\(navigation.worksRevision)") {
            guard session.isAuthenticated else {
                workActivity.reset()
                creationSubmissions.reset()
                return
            }
            guard workActivity.hasPendingCreatedJobs else { return }
            while !Task.isCancelled {
                let token = await session.validAccessToken()
                await workActivity.refresh(token: token, userID: session.user?.id)
                guard workActivity.activeCount > 0 else { return }
                try? await Task.sleep(
                    for: .seconds(workActivity.nextRefreshInterval())
                )
            }
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active, session.isAuthenticated else { return }
            while !Task.isCancelled {
                await session.pingActivity()
                try? await Task.sleep(for: .seconds(5 * 60))
            }
        }
        .fullScreenCover(isPresented: $showsComplianceConsent) {
            ComplianceConsentView()
                .environment(session)
                .environment(language)
                .environment(\.locale, language.locale)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showsAppUpdatePrompt) {
            NavigationStack {
                PixaAppUpdateView()
            }
            .environment(appUpdate)
            .environment(\.locale, language.locale)
            .presentationDetents([.medium, .large])
            .onDisappear {
                appUpdate.acknowledgeCurrentUpdate()
            }
        }
        .onChange(of: session.needsComplianceConsent, initial: true) { _, needsConsent in
            // SwiftUI 可能在异步渲染线程求值 Binding；这里只在主 Actor 将会话状态同步到纯视图状态。
            showsComplianceConsent = needsConsent
            presentUpdatePromptIfNeeded()
        }
        .onChange(of: showsStartupExperience) { _, _ in
            presentUpdatePromptIfNeeded()
        }
        .onChange(of: appUpdate.hasUnseenUpdate) { _, _ in
            presentUpdatePromptIfNeeded()
        }
        .onChange(of: showsPushExplainer) { _, _ in
            presentUpdatePromptIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                if let status = await PixaMaintenanceService.checkGeneration() {
                    maintenanceStatus = status
                }
            }
            language.refreshSystemLanguage()
            creationSubmissions.refresh()
            Task {
                await session.pingActivity()
                await AppAPIRouter.shared.refresh()
                await appUpdate.check()
                await session.resume()
                // 回到前台时重新读取商店地区，兼容用户在后台切换 App Store 地区的情况。
                await mediaRegion.refresh(
                    accountCountryCode: session.user?.countryCode,
                    reloadStorefront: true
                )
                await accountData.load(session: session, force: true)
                await durationEstimates.load(accessToken: session.accessToken)
                await workActivity.refresh(
                    token: session.accessToken,
                    userID: session.user?.id
                )
                await notifications.refreshUnreadCount(session: session)
                await PixaPushNotificationService.shared.registerForRemoteNotifications()
                await PixaPushNotificationService.shared.synchronize(session: session)
                storeKitSync.start(session: session)
                await storeKitSync.sync(session: session)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pixaBalanceDidChange)) { _ in
            Task { await accountData.load(session: session, force: true) }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .pixaBackgroundSubmissionsChanged)
        ) { _ in
            creationSubmissions.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .pixaBackgroundSubmissionCompleted)
        ) { notification in
            guard let completion = notification.object
                as? PixaBackgroundSubmissionCompletion else { return }
            creationSubmissions.refresh()
            if let jobID = completion.jobID, !jobID.isEmpty {
                workActivity.markSubmitted(
                    jobID: jobID,
                    title: completion.title,
                    aspectRatio: completion.aspectRatio
                )
            }
            navigation.showWorks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pixaCredentialDidRefresh)) { notification in
            guard let token = notification.object as? String else { return }
            session.applyRefreshedAccessToken(token)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pixaCredentialRejected)) { _ in
            session.signOut()
            accountData.reset()
            workActivity.reset()
            creationSubmissions.reset()
            notifications.reset()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pixaPushDeviceTokenChanged)) { _ in
            Task { await PixaPushNotificationService.shared.synchronize(session: session) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pixaRemoteNotificationReceived)) { _ in
            Task {
                await notifications.refresh(session: session)
                await accountData.load(session: session, force: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pixaRemoteNotificationOpened)) { notification in
            if let destination = PixaNotificationLaunchTargetStore.shared.take()
                ?? notification.object as? PixaNotificationDestination {
                openNotificationDestination(destination)
            }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL,
                  referralAttribution.capture(url: url) else { return }
            navigation.openReferralRegistration()
        }
        .sheet(isPresented: $showsPushExplainer, onDismiss: {
            pushExplainerShown = true
        }) {
            PixaNotificationPermissionPrompt {
                Task {
                    let authorized = await PixaPushNotificationService.shared.requestAuthorizationAndRegister()
                    if authorized {
                        await PixaPushNotificationService.shared.synchronize(session: session)
                    }
                }
            }
        }
    }

    private func presentUpdatePromptIfNeeded() {
        guard !showsStartupExperience,
              !showsComplianceConsent,
              !showsPushExplainer,
              appUpdate.hasUnseenUpdate else { return }
        showsAppUpdatePrompt = true
    }

    private func openNotificationDestination(_ destination: PixaNotificationDestination) {
        Task {
            if destination.isDigest {
                navigation.openNotificationRoute("notifications")
                await notifications.refresh(session: session)
                return
            }
            await notifications.refresh(session: session)
            let storedType = notifications.items.first { $0.id == destination.notificationID }?.referenceType
            navigation.openNotificationRoute(
                destination.route?.lowercased() != "notifications"
                    && (destination.referenceType == "daily_visit_gift" || storedType == "daily_visit_gift")
                    ? "transactions" : destination.route,
                referenceID: destination.referenceID,
                notificationID: destination.notificationID
            )
            if let notificationID = destination.notificationID {
                await notifications.markRead(id: notificationID, session: session)
            }
        }
    }
}

private struct PixaMaintenancePrompt: ViewModifier {
    @Binding var status: PixaMaintenanceStatus?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .pixaMaintenanceBlocked)) { notification in
                status = notification.object as? PixaMaintenanceStatus
            }
            .alert(AppLanguage.localized("maintenance.title"), isPresented: Binding(
                get: { status != nil },
                set: { if !$0 { status = nil } }
            )) {
                Button(AppLanguage.localized("maintenance.dismiss")) { status = nil }
            } message: {
                Text(status?.notice ?? "")
            }
    }
}

struct RootView: View {
    @Environment(PixaNavigationStore.self) private var navigation
    @Environment(PixaWorkActivityStore.self) private var workActivity
    @Environment(PixaAppUpdateStore.self) private var appUpdate

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.selectedTab) {
            HomeView().tag(PixaRootTab.home)
            GalleryView().tag(PixaRootTab.gallery)
            NavigationStack {
                TemplatesView()
                    .background(
                        PixaNavigationPopObserver(
                            revision: navigation.popRevision(for: .templates)
                        )
                    )
            }
            .tag(PixaRootTab.templates)
            WorksView().tag(PixaRootTab.works)
            AccountView().tag(PixaRootTab.account)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PixaRootTabBar(
                selection: $navigation.selectedTab,
                onSelect: navigation.selectFromTabBar,
                activeWorksCount: workActivity.activeCount,
                showsAccountUpdateDot: appUpdate.hasUnseenUpdate
            )
        }
        .background(PixaTheme.paper)
    }
}

private struct PixaRootTabBar: View {
    @Binding var selection: PixaRootTab
    let onSelect: (PixaRootTab) -> Void
    let activeWorksCount: Int
    let showsAccountUpdateDot: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            item(.home, title: "tab.home", icon: "house.fill")
            item(.gallery, title: "tab.gallery", icon: "rectangle.stack.fill")
            creationItem
            item(
                .works,
                title: "tab.works",
                icon: "folder.fill",
                badge: activeWorksCount
            )
            item(
                .account,
                title: "tab.account",
                icon: "person.fill",
                showsDot: showsAccountUpdateDot
            )
        }
        .frame(height: 62)
        .padding(.horizontal, 8)
        // 底部导航保持不透明，避免系统玻璃材质叠加内容后产生异常的半透明带。
        .background(PixaTheme.paper)
        .overlay(alignment: .top) { Divider() }
    }

    private func item(
        _ tab: PixaRootTab,
        title: LocalizedStringKey,
        icon: String,
        badge: Int = 0,
        showsDot: Bool = false
    ) -> some View {
        Button { onSelect(tab) } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(badge > 99 ? "99+" : "\(badge)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, badge > 9 ? 4 : 0)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(PixaTheme.accent, in: Capsule())
                                .overlay { Capsule().stroke(.white, lineWidth: 1.5) }
                                .offset(x: 9, y: -8)
                                .contentTransition(.numericText())
                                .transition(.scale.combined(with: .opacity))
                        } else if showsDot {
                            Circle()
                                .fill(.red)
                                .frame(width: 9, height: 9)
                                .overlay { Circle().stroke(.white, lineWidth: 1.5) }
                                .offset(x: 7, y: -5)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                Text(title).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selection == tab ? PixaTheme.accent : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
        .accessibilityValue(
            showsDot
                ? Text("app_update.available")
                : badge > 0
                ? Text(String.localizedStringWithFormat(
                    AppLanguage.localized("works.processing_count"),
                    badge
                ))
                : Text("")
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: badge)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: showsDot)
    }

    private var creationItem: some View {
        Button { onSelect(.templates) } label: {
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(PixaTheme.accent, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.9), lineWidth: 3) }
                .shadow(color: PixaTheme.accent.opacity(0.3), radius: 8, y: 4)
            .frame(maxWidth: .infinity)
            .offset(y: -9)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("tab.templates"))
        .accessibilityAddTraits(selection == .templates ? .isSelected : [])
    }
}

/// 接收当前 Tab 的重复点击信号，并通过所属 UINavigationController 精确回退一级。
struct PixaNavigationPopObserver: UIViewControllerRepresentable {
    let revision: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(revision: revision)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard context.coordinator.revision != revision else { return }
        context.coordinator.revision = revision
        DispatchQueue.main.async {
            guard let navigationController = controller.navigationController,
                  navigationController.viewControllers.count > 1 else { return }
            navigationController.popViewController(animated: true)
        }
    }

    final class Coordinator {
        var revision: Int

        init(revision: Int) {
            self.revision = revision
        }
    }
}
