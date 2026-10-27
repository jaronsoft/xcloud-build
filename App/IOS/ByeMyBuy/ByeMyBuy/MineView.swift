import SwiftUI

struct MineView: View {
    @EnvironmentObject private var session: BmbSession
    @State private var items: [BmbDecisionSummary] = []
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("YOUR SPACE").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                Text("My decisions").font(.system(size: 35, weight: .black, design: .rounded))
                Text("Every pause tells a story.").foregroundStyle(BmbTheme.muted)
                if !session.isLoggedIn {
                    BmbCard { VStack(alignment: .leading, spacing: 16) {
                        Text("Sign in to keep your decisions together.")
                        BmbPrimaryButton(title: "Sign in") { session.showLogin = true }
                    } }
                } else if items.isEmpty {
                    BmbCard { Text(error ?? String(localized: "Your decisions will appear here."))
                        .foregroundStyle(BmbTheme.muted) }
                } else {
                    ForEach(items) { item in
                        NavigationLink(destination: DecisionView(shareToken: item.ShareToken)) {
                            BmbCard { HStack {
                                Text("✦").frame(width: 40, height: 40).background(BmbTheme.lime, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.Question).font(.subheadline.bold())
                                    Text(item.Status == "open" ? "Open" : "Closed").font(.caption).foregroundStyle(BmbTheme.muted)
                                    if item.Visibility == "public" {
                                        Text(LocalizedStringKey(item.PublicReviewStatus == "approved" ? "Visible in Explore" :
                                            item.PublicReviewStatus == "rejected" ? "Explore submission declined" : "Awaiting Explore review"))
                                            .font(.caption).foregroundStyle(BmbTheme.muted)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            } }.foregroundStyle(BmbTheme.ink)
                        }
                    }
                }
            }.padding(20)
        }
        .background(BmbTheme.paper)
        .navigationBarHidden(true)
        .task(id: session.token) { await load() }
    }
    private func load() async {
        guard let token = session.token else { items = []; return }
        do { items = try await session.api.call("/decisions/mine", token: token); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
