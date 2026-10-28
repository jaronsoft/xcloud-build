import SwiftUI

struct MineView: View {
    @EnvironmentObject private var session: BmbSession
    @State private var items: [BmbDecisionSummary] = []
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR SPACE").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                    Text("My decisions").font(.system(size: 31, weight: .black, design: .rounded))
                    Text("Every pause tells a story.").font(.system(size: 14)).foregroundStyle(BmbTheme.muted)
                }
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
                            BmbCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(alignment: .top, spacing: 13) {
                                        BmbCachedImage(url: item.ImageUrl.flatMap(URL.init(string:)), preset: .thumbnail) {
                                            Image("LaunchMark").resizable().scaledToFit().padding(16)
                                        }
                                        .frame(width: 78, height: 78)
                                        .background(BmbTheme.hero, in: RoundedRectangle(cornerRadius: 14))
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.Question).font(.subheadline.bold()).lineLimit(2)
                                            Label(item.Status == "open" ? "Open" : "Closed", systemImage: "circle.fill")
                                                .font(.caption2).foregroundStyle(item.Status == "open" ? .green : BmbTheme.muted)
                                            HStack(spacing: 4) {
                                                Image(systemName: "clock")
                                                Text("Published")
                                                Text(item.publishedAt)
                                            }.font(.caption2).foregroundStyle(BmbTheme.muted)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(BmbTheme.muted)
                                    }
                                    HStack(spacing: 15) {
                                        countLabel(item.Mode == "pick_one" ? "Option A" : "Buy it",
                                                   count: item.Votes[item.Mode == "pick_one" ? "a" : "buy"] ?? 0,
                                                   symbol: "hand.thumbsup")
                                        countLabel(item.Mode == "pick_one" ? "Option B" : "Pass",
                                                   count: item.Votes[item.Mode == "pick_one" ? "b" : "pass"] ?? 0,
                                                   symbol: "hand.thumbsdown")
                                        countLabel("Comments", count: item.CommentCount, symbol: "bubble.left")
                                    }
                                    .font(.caption).foregroundStyle(BmbTheme.muted)
                                    if item.Visibility == "public" {
                                        Text(LocalizedStringKey(item.PublicReviewStatus == "approved" ? "Visible in Explore" :
                                            item.PublicReviewStatus == "rejected" ? "Explore submission declined" : "Awaiting Explore review"))
                                            .font(.caption2).foregroundStyle(BmbTheme.muted)
                                    }
                                }
                            }.foregroundStyle(BmbTheme.ink)
                        }
                    }
                }
            }.padding(20)
        }
        .background(BmbTheme.paper)
        .navigationBarHidden(true)
        .task(id: session.token) {
            items = []
            if let token = session.token,
               let cached: [BmbDecisionSummary] = await session.api.cached("/decisions/mine", token: token) { items = cached }
            await load()
        }
        .refreshable { await load() }
    }

    private func countLabel(_ title: LocalizedStringKey, count: Int, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title)
            Text("\(count)")
        }
    }

    private func load() async {
        guard let token = session.token else { items = []; return }
        do { items = try await session.api.call("/decisions/mine", token: token); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private extension BmbDecisionSummary {
    var publishedAt: String { String(CreateTime.replacingOccurrences(of: "T", with: " ").prefix(16)) }
}
