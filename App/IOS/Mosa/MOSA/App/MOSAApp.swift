import SwiftUI

@main
struct MOSAApp: App {
    @StateObject private var store = MosaStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(MosaPalette.navy)
                .preferredColorScheme(nil)
                .task {
                    await store.refreshPublicConfiguration()
                }
        }
    }
}
