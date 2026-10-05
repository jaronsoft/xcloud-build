import SwiftUI

@main
struct AIKApp: App {
    var body: some Scene {
        WindowGroup {
            AIKRootContainer()
        }
    }
}

private struct AIKRootContainer: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = SessionStore()
    @State private var tenants = TenantStore()
    @State private var releaseStore = AppReleaseStore()

    var body: some View {
        AppReleaseGate(store: releaseStore) {
            RootView(session: session, tenants: tenants)
        }
        .tint(AIKTheme.accent)
            .accessibilityIdentifier("xcloud-pipeline-test-2026-10-05")
            .task {
                async let restore: Void = session.restore()
                async let releaseCheck: Void = releaseStore.check()
                _ = await (restore, releaseCheck)
                if session.mode == .signedOut {
                    tenants.prepareForSignedOut()
                } else if session.mode == .system {
                    await tenants.loadTenants(
                        session: session,
                        selectsDefaultTenant: true
                    )
                }
            }
            .onOpenURL { url in
                guard let reference = InviteLinkParser.parse(url.absoluteString) else {
                    return
                }
                NotificationCenter.default.post(
                    name: .aikOpenInvite,
                    object: reference
                )
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await releaseStore.check()
                }
            }
    }
}

extension Notification.Name {
    static let aikOpenInvite = Notification.Name("AIKOpenInvite")
}
