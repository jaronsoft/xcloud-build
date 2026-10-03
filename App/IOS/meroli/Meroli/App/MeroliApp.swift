import SwiftUI

@main
struct MeroliApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { await session.restore() }
                .preferredColorScheme(.light)
        }
    }
}
