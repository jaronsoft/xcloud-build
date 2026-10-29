import SwiftUI

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 40
    @AppStorage("bmb.content_language") private var contentLanguage = Locale.current.language.languageCode?.identifier == "zh" ? "zh" : "en"
    @AppStorage("bmb.include_english") private var includeEnglish = true
    @State private var showCreate = false
    @State private var showHelp = false
    @State private var items: [BmbPublicDecision] = []
    @State private var loading = true
    @State private var failed = false
    @State private var openedPath: String?
    @State private var feedRequest = UUID()

    private let forest = Color(red: 0.08, green: 0.25, blue: 0.17)
    private let paleGreen = Color(red: 0.77, green: 0.84, blue: 0.69)
    private var feedPath: String {
        BmbPublicFeed.path(language: contentLanguage, includeEnglish: includeEnglish)
    }

    var body: some View {
        GeometryReader { geometry in
            if #available(iOS 27.1, *), geometry.size.width >= 540 {
                HStack(spacing: 0) {
                    NavigationStack { homeContent(showCommunity: false) }
                        .frame(width: min(geometry.size.width * 0.45, 420))
                    Divider()
                    NavigationStack { ExploreView() }
                        .frame(maxWidth: .infinity)
                }
                .background(BmbTheme.paper)
            } else {
                NavigationStack { homeContent(showCommunity: true) }
            }
        }
        .sheet(isPresented: $showCreate) { NavigationStack { CreateView() } }
        .sheet(isPresented: $showHelp) { helpSheet }
        .task(id: feedPath) { await openFeed() }
    }

    private func homeContent(showCommunity: Bool) -> some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - 40)
            let columns = dynamicTypeSize.isAccessibilitySize || width < 300 ? 1 : 2
            let cardWidth = max(0, (width - CGFloat(columns - 1) * 12) / CGFloat(columns))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    introduction
                    askCard
                    if showCommunity { community(columns: columns, cardWidth: cardWidth) }
                    offerLink
                }
                .frame(width: width, alignment: .leading)
                .padding(20)
            }
            .refreshable { await refreshFeed() }
            .background(BmbTheme.paper)
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("LaunchMark").resizable().scaledToFit().frame(width: 43, height: 43)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("ByeMyBuy").font(.system(size: 23, weight: .black, design: .rounded))
                Text("THINK. ASK. DECIDE.").font(.system(size: 8, weight: .bold))
                    .tracking(2).foregroundStyle(BmbTheme.muted)
            }
            Spacer(minLength: 4)
            Button { showHelp = true } label: {
                Image(systemName: "questionmark.circle").font(.system(size: 23))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("How it works"))
        }
        .foregroundStyle(BmbTheme.ink)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A BETTER PAUSE BEFORE CHECKOUT")
                        .font(.system(.caption2, design: .rounded, weight: .heavy))
                        .foregroundStyle(.green)
                    Text("Love it?").font(.system(size: headlineSize, weight: .black, design: .rounded))
                        .tracking(-1).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    ZStack {
                        Image(systemName: "bubble.left.fill")
                            .foregroundStyle(BmbTheme.lime.opacity(0.35)).offset(x: -18, y: -11)
                        Image(systemName: "ellipsis.bubble.fill")
                            .foregroundStyle(BmbTheme.lime.opacity(0.65)).offset(x: 8, y: 13)
                    }
                    .font(.system(size: 48)).frame(width: 85, height: 73)
                    .accessibilityHidden(true)
                }
            }
            Text("Hear what others think.")
                .font(.system(.title, design: .rounded, weight: .black))
                .tracking(-0.7).fixedSize(horizontal: false, vertical: true)
            Text("Share what you love. Let different perspectives help you decide.")
                .font(.subheadline).foregroundStyle(BmbTheme.muted)
                .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        }
        .foregroundStyle(BmbTheme.ink)
    }

    private var askCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "bag").font(.system(size: 43, weight: .light))
                        .foregroundStyle(.white).frame(width: 52, height: 58)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "minus.circle.fill").font(.system(size: 22))
                                .symbolRenderingMode(.palette).foregroundStyle(.white, Color(red: 1, green: 0.45, blue: 0.35))
                        }
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Buy or pass? Talk it through.")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Ask · Share with friends · Hear real perspectives")
                        .font(.caption).foregroundStyle(paleGreen)
                }.fixedSize(horizontal: false, vertical: true)
            }
            Button { showCreate = true } label: {
                Label("Ask everyone", systemImage: "plus")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 20).padding(16)
                    .foregroundStyle(forest)
                    .background(BmbTheme.lime, in: RoundedRectangle(cornerRadius: 17))
            }.buttonStyle(.plain)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(forest, in: RoundedRectangle(cornerRadius: 25))
    }

    private func community(columns: Int, cardWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { communityTitle; Spacer(minLength: 8); browseLink }
                VStack(alignment: .leading, spacing: 8) { communityTitle; browseLink }
            }
            Text("See what others love. Add your perspective.")
                .font(.caption).foregroundStyle(BmbTheme.muted).padding(.top, -8)
            if !items.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: 12), count: columns), spacing: 12) {
                    ForEach(Array(items.prefix(4))) { item in
                        NavigationLink(destination: DecisionView(shareToken: item.ShareToken)) {
                            questionCard(item, width: cardWidth)
                        }.buttonStyle(.plain)
                    }
                }
            } else {
                BmbCard {
                    VStack(alignment: .leading, spacing: 12) {
                        if loading {
                            ProgressView()
                            Text("Finding community decisions…").font(.subheadline)
                        } else if failed {
                            Text("Couldn't load community questions. Pull to try again.")
                                .font(.subheadline).foregroundStyle(BmbTheme.muted)
                            Button("Try again") { Task { await refreshFeed() } }.font(.subheadline.bold())
                        } else {
                            Text("It's quiet here for now").font(.headline)
                            Text("Start a question or explore more decisions.")
                                .font(.subheadline).foregroundStyle(BmbTheme.muted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if failed && !items.isEmpty {
                Text("Couldn't refresh. Your saved questions are still here.")
                    .font(.caption).foregroundStyle(BmbTheme.muted)
            }
        }
    }

    private var communityTitle: some View {
        Text("What people are considering").font(.system(.title2, design: .rounded, weight: .bold))
            .foregroundStyle(BmbTheme.ink)
    }

    private var browseLink: some View {
        NavigationLink(destination: ExploreView()) {
            Label("Explore decisions", systemImage: "arrow.up.right")
                .font(.subheadline.bold()).foregroundStyle(BmbTheme.ink).padding(.vertical, 8)
        }.buttonStyle(.plain)
    }

    private func questionCard(_ item: BmbPublicDecision, width: CGFloat) -> some View {
        let imageURL = item.Products.first?.ImageUrl.flatMap(URL.init(string:))
        return VStack(alignment: .leading, spacing: 10) {
            if let imageURL {
                BmbCachedImage(url: imageURL, preset: .list) {
                    Image("LaunchMark").resizable().scaledToFit().padding(30)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(BmbTheme.hero)
                }
                .frame(width: max(0, width - 16), height: max(100, width * 0.7))
                .clipped().clipShape(RoundedRectangle(cornerRadius: 13))
            } else {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 19, weight: .medium)).foregroundStyle(forest)
                    .frame(width: 40, height: 40)
                    .background(BmbTheme.hero, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(item.Question).font(.subheadline.bold()).lineLimit(imageURL == nil ? 3 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let tag = item.Products.first?.Tags?.first, !tag.isEmpty {
                    Text(tag).font(.caption2).foregroundStyle(BmbTheme.muted).lineLimit(1)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(BmbTheme.paper, in: Capsule())
                }
                Divider().overlay(BmbTheme.muted.opacity(0.1))
                Label("Add your perspective", systemImage: "bubble.left")
                    .font(.caption).foregroundStyle(BmbTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            }.padding(.horizontal, 5).padding(.bottom, 6)
        }
        .padding(8).frame(width: width, alignment: .leading)
        .foregroundStyle(BmbTheme.ink)
        .background(BmbTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(BmbTheme.ink.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }

    private var offerLink: some View {
        NavigationLink(destination: ExploreView()) {
            BmbCard {
                HStack(spacing: 13) {
                    Image(systemName: "tag").font(.title3).foregroundStyle(.green)
                        .frame(width: 40, height: 40)
                        .background(BmbTheme.hero, in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Have a relevant offer link?").font(.subheadline.bold()).foregroundStyle(BmbTheme.ink)
                        Text("Share it with someone considering a purchase.")
                            .font(.caption).foregroundStyle(BmbTheme.muted)
                    }.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(BmbTheme.muted)
                }
            }
        }.buttonStyle(.plain)
    }

    private var helpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Shopping decisions feel lighter together.").font(.title2.bold())
                    ForEach(Array(["Find something you want", "Hear what others think", "Decide with confidence"].enumerated()), id: \.offset) { index, text in
                        HStack(alignment: .top, spacing: 15) {
                            Text("0\(index + 1)").font(.headline).foregroundStyle(.green)
                            Text(LocalizedStringKey(text)).font(.body)
                        }
                    }
                }.padding(24)
            }
            .background(BmbTheme.paper)
            .navigationTitle("How it works").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHelp = false } } }
        }.presentationDetents([.medium, .large])
    }

    private func openFeed() async {
        let path = feedPath
        guard openedPath != path else { return }
        openedPath = path
        let request = UUID()
        feedRequest = request
        items = []; loading = true; failed = false
        if let cached: BmbPublicPage = await BmbAPI().cached(path, forCurrentLaunch: true) {
            guard feedRequest == request else { return }
            items = cached.Items; loading = false
            // 更新供下次启动读取，避免用户正在浏览的内容发生跳动。
            Task { let _: BmbPublicPage? = try? await BmbAPI().call(path) }
        } else {
            guard feedRequest == request else { return }
            await refreshFeed()
        }
    }

    private func refreshFeed() async {
        let path = feedPath
        let request = UUID()
        feedRequest = request
        loading = true; failed = false
        do {
            let response: BmbPublicPage = try await BmbAPI().call(path, activateCache: true)
            guard feedRequest == request else { return }
            items = response.Items
        } catch {
            guard feedRequest == request else { return }
            failed = !Task.isCancelled && !(error is CancellationError)
                && (error as? URLError)?.code != .cancelled
        }
        if feedRequest == request { loading = false }
    }
}
