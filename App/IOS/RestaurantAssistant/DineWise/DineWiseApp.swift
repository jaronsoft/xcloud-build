import SwiftUI

@main
struct DineWiseApp: App {
    @State private var showContent = false

    var body: some Scene {
        WindowGroup {
            if showContent {
                ContentView()
            } else {
                DineWiseLaunchAnimationView { showContent = true }
            }
        }
    }
}
