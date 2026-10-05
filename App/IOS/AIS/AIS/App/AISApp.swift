import SwiftUI

@main
struct AISApp: App {
    var body: some Scene {
        WindowGroup {
            AISRootContainerView()
        }
    }
}

// 场景构建闭包保持无状态，避免 SwiftUI 异步渲染线程触发主执行域检查。
private struct AISRootContainerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = SessionStore()
    @State private var appData = AISAppDataStore()
    @State private var mediaRegion = AISMediaRegionStore()
    @State private var releaseStore = AppReleaseStore(
        productKey: "ais",
        checkPath: "/api/AppRelease/Check"
    )
    @State private var splashAnimationFinished = false
    @State private var imageDeliveryReady = false
    @State private var maintenanceStatus: AISMaintenanceStatus?

    private var showsSplash: Bool {
        !splashAnimationFinished || session.isRestoring || !imageDeliveryReady
    }

    var body: some View {
        ZStack {
            if imageDeliveryReady {
                AppReleaseGate(
                    store: releaseStore,
                    content: AnyView(
                        RootView()
                            .id(mediaRegion.revision)
                            .environment(session)
                            .environment(appData)
                            .environment(mediaRegion)
                    )
                )
            }

            if showsSplash {
                SplashView {
                    splashAnimationFinished = true
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showsSplash)
        .task {
            if let status = await AISMaintenanceService.checkGeneration() {
                maintenanceStatus = status
            }
            await AppAPIRouter.shared.bootstrap(product: "ais")
            await mediaRegion.refresh(
                accountCountryCode: session.user?.countryCode
            )
            async let imageDelivery: Void = AISImageDeliveryStore.shared.load()
            async let capabilities: Void = AISCapabilitiesStore.shared.load()
            async let releaseCheck: Void = releaseStore.check()
            await imageDelivery
            imageDeliveryReady = true
            await session.restore()
            await mediaRegion.refresh(
                accountCountryCode: session.user?.countryCode
            )
            let durationAccessToken = await session.validAccessToken()
            async let durationEstimates: Void = appData.durationEstimates.load(
                accessToken: durationAccessToken
            )
            await appData.preload(session: session)
            _ = await (
                capabilities,
                releaseCheck,
                durationEstimates
            )
        }
        .onChange(of: session.user?.id) { _, newUserID in
            Task {
                await mediaRegion.refresh(
                    accountCountryCode: session.user?.countryCode
                )
                if newUserID == nil {
                    appData.reset()
                }
                await appData.preload(session: session)
                let durationAccessToken = await session.validAccessToken()
                await appData.durationEstimates.load(
                    accessToken: durationAccessToken
                )
            }
        }
        .onChange(of: mediaRegion.revision) {
            Task {
                appData.reset()
                await appData.preload(session: session)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                if let status = await AISMaintenanceService.checkGeneration() {
                    maintenanceStatus = status
                }
                await AppAPIRouter.shared.refresh()
                await session.resume()
                await mediaRegion.refresh(
                    accountCountryCode: session.user?.countryCode,
                    reloadStorefront: true
                )
                await appData.refreshUserData(session: session, force: true)
                let durationAccessToken = await session.validAccessToken()
                await appData.durationEstimates.refreshIfNeeded(
                    accessToken: durationAccessToken
                )
                await releaseStore.check()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aisMaintenanceBlocked)) { notification in
            maintenanceStatus = notification.object as? AISMaintenanceStatus
        }
        .alert(String(localized: "maintenance.title"), isPresented: Binding(
            get: { maintenanceStatus != nil },
            set: { if !$0 { maintenanceStatus = nil } }
        )) {
            Button(String(localized: "maintenance.dismiss")) { maintenanceStatus = nil }
        } message: {
            Text(maintenanceStatus?.notice ?? "")
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .aisTaskSubmitted)
        ) { _ in
            Task {
                await appData.refreshPoints(session: session)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .aisRechargeCredited)
        ) { _ in
            Task {
                await appData.refreshAfterRecharge(session: session)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .aisPricingRulesInvalidated
            )
        ) { _ in
            Task {
                await appData.refreshPricingRules(session: session)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .aisCredentialRejected
            )
        ) { _ in
            session.signOut()
        }
    }
}
