import SwiftUI

struct RootView: View {
    let session: SessionStore
    let tenants: TenantStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if session.isRestoring {
                ProgressView("app.restoring")
            } else if !session.isAuthenticated {
                AccessLandingView(session: session, tenants: tenants)
            } else if let tenant = tenants.selectedTenant {
                ChatView(
                    session: session,
                    tenantStore: tenants,
                    tenant: tenant
                )
            } else if session.mode == .system {
                TenantSelectorView(session: session, store: tenants)
            } else {
                AccessLandingView(session: session, tenants: tenants)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: session.mode)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: tenants.selectedTenant?.id
        )
    }
}
