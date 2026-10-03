import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: MosaStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsSplash = true
    @AppStorage("mosa.initialBackfillOffered") private var initialBackfillOffered = false

    var body: some View {
        Group {
            if showsSplash {
                SplashView()
            } else if store.profile == nil {
                NavigationStack {
                    WelcomeView()
                }
            } else if !initialBackfillOffered {
                NavigationStack { BackfillView(initialCompletion: { initialBackfillOffered = true }) }
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showsSplash)
        .animation(.easeInOut(duration: 0.25), value: store.profile != nil)
        .task {
            let duration = reduceMotion ? 1_100 : 2_450
            try? await Task.sleep(for: .milliseconds(duration))
            showsSplash = false
        }
    }
}

struct CompanyFooter: View {
    var body: some View {
        Link(destination: AppConfiguration.companySiteURL) {
            Text("© 2026 WeKare Partners")
                .font(.caption)
                .foregroundStyle(MosaPalette.muted)
        }
    }
}
