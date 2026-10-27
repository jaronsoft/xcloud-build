import SwiftUI

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showCreate = false

    var body: some View {
        GeometryReader { geometry in
            if #available(iOS 27.1, *), horizontalSizeClass == .regular,
               geometry.size.width >= 650, geometry.size.width > geometry.size.height {
                NavigationSplitView {
                    homeContent(showExploreLink: false)
                } detail: {
                    NavigationStack { ExploreView() }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack { homeContent(showExploreLink: true) }
            }
        }
        .sheet(isPresented: $showCreate) { NavigationStack { CreateView() } }
    }

    private func homeContent(showExploreLink: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 11) {
                    Image("LaunchMark").resizable().frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ByeMyBuy").font(.system(size: 20, weight: .black, design: .rounded))
                        Text("THINK. ASK. DECIDE.").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(BmbTheme.muted)
                    }
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text("A BETTER PAUSE BEFORE CHECKOUT").font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(.green)
                    Text("Love it? Hear what others think.").font(.system(size: 31, weight: .black, design: .rounded)).tracking(-0.8).fixedSize(horizontal: false, vertical: true)
                    Text("Share a product with friends, the community, and people who have bought it. Hear their votes and experiences before you decide.")
                        .font(.system(size: 14)).foregroundStyle(BmbTheme.muted).lineSpacing(4)
                    BmbPrimaryButton(title: "Ask before you buy") { showCreate = true }
                }
                .padding(27).frame(maxWidth: .infinity, alignment: .leading)
                .background(BmbTheme.hero, in: RoundedRectangle(cornerRadius: 29))
                if showExploreLink {
                    NavigationLink(destination: ExploreView()) {
                        HStack { Text("Explore decisions").font(.headline); Spacer(); Image(systemName: "arrow.right") }
                            .padding(18).background(BmbTheme.card, in: RoundedRectangle(cornerRadius: 17))
                    }.foregroundStyle(BmbTheme.ink)
                }
                VStack(alignment: .leading, spacing: 17) {
                    Text("Shopping decisions feel lighter together.").font(.system(size: 26, weight: .bold, design: .rounded))
                    ForEach(Array(["Find something you want", "Hear what others think", "Decide with confidence"].enumerated()), id: \.offset) { index, item in
                        BmbCard {
                            HStack(spacing: 17) {
                                Text("0\(index + 1)").font(.caption.bold()).foregroundStyle(.green)
                                Text(LocalizedStringKey(item)).font(.subheadline.bold())
                                Spacer()
                                Image(systemName: ["link", "bubble.left.and.bubble.right", "heart"][index]).foregroundStyle(BmbTheme.muted)
                            }
                        }
                    }
                }
            }.padding(20)
        }
        .background(BmbTheme.paper)
        .navigationBarHidden(true)
    }
}
