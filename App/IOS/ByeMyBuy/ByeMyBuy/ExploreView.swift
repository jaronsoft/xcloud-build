import SwiftUI

struct ExploreView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showCreate = false
    @State private var showFilters = false
    @State private var draftFilter = "recommended"
    @State private var draftTag = ""
    @State private var items: [BmbPublicDecision] = []
    @State private var page = 0
    @State private var snapshot: Int64?
    @State private var hasMore = false
    @State private var loading = true
    @State private var error: String?
    @State private var timedOut = false
    @State private var filter = "recommended"
    @State private var tag = ""
    @AppStorage("bmb.content_language") private var contentLanguage = Locale.current.language.languageCode?.identifier == "zh" ? "zh" : "en"
    @AppStorage("bmb.include_english") private var includeEnglish = true
    @State private var feedRequest = UUID()
    @State private var openedPath: String?
    @State private var voteBreakdowns: [String: (votes: [String: Int], total: Int)] = [:]
    @State private var endMessageIndex = Int.random(in: 0..<4)

    var body: some View {
        GeometryReader { geometry in
        let contentWidth = max(0, geometry.size.width - 36)
        let columnCount = dynamicTypeSize.isAccessibilitySize || contentWidth < 300 ? 1 : 2
        let columnWidth = max(0, (contentWidth - CGFloat(columnCount - 1) * 12) / CGFloat(columnCount))
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("THE COMMUNITY").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                        Text("Explore decisions").font(.system(size: 31, weight: .black, design: .rounded))
                        Text("See what people are thinking of buying.").font(.system(size: 14)).foregroundStyle(BmbTheme.muted)
                    }
                    Spacer(minLength: 0)
                    Button {
                        draftFilter = filter; draftTag = tag; showFilters = true
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                            .font(.title3).frame(width: 44, height: 44)
                            .background(BmbTheme.card, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(BmbEngagementCopy.text("Filter", "筛选"))
                    .accessibilityValue(hasActiveFilters ? BmbEngagementCopy.text("Filters applied", "已启用筛选") : BmbEngagementCopy.text("All decisions", "全部提问"))
                    Button { showCreate = true } label: {
                        Label("Post", systemImage: "plus")
                            .font(.subheadline.bold()).foregroundStyle(BmbTheme.ink)
                            .padding(.horizontal, 15).frame(height: 44)
                            .background(BmbTheme.lime, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if filter != "recommended" || !tag.isEmpty {
                    Text([filter == "recommended" ? nil : filterTitle(filter), tag.isEmpty ? nil : "#\(tag)"].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(BmbTheme.muted)
                }
                if let error {
                    BmbCard {
                        VStack(spacing: 12) {
                            if timedOut && items.isEmpty {
                                Image("TimeoutBag")
                                    .resizable().scaledToFit()
                                    .frame(width: 124, height: 124)
                                    .accessibilityHidden(true)
                            }
                            Text(timedOut
                                 ? BmbEngagementCopy.text("Oops, our little bag took a nap", "哎呀，小袋子打了个盹")
                                 : BmbEngagementCopy.text("Couldn't load decisions", "暂时没能加载提问"))
                                .font(.headline).multilineTextAlignment(.center)
                            Text(timedOut
                                 ? BmbEngagementCopy.text("The request took too long. Give it another try?", "等得有点久啦，再试一次吧？")
                                 : error)
                                .font(.subheadline).foregroundStyle(BmbTheme.muted)
                                .multilineTextAlignment(.center)
                            Button {
                                Task { await load(reset: page == 0) }
                            } label: {
                                Label(BmbEngagementCopy.text("Try again", "再试一次"), systemImage: "arrow.clockwise")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(BmbTheme.ink)
                                    .padding(.horizontal, 20).frame(height: 42)
                                    .background(BmbTheme.lime, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, items.isEmpty ? 16 : 4)
                    }
                }
                if loading && items.isEmpty && error == nil {
                    BmbCard {
                        VStack(spacing: 13) {
                            ProgressView().tint(.green)
                            Text("Finding community decisions…").font(.subheadline.bold())
                            Text("Just a moment.").font(.caption).foregroundStyle(BmbTheme.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
                if items.isEmpty && !loading && error == nil {
                    BmbCard {
                        VStack(spacing: 11) {
                            ZStack(alignment: .topTrailing) {
                                Circle().fill(BmbTheme.hero).frame(width: 118, height: 118)
                                Image("LaunchMark").resizable().scaledToFit().frame(width: 74, height: 74).padding(22)
                                Text("?").font(.title2.bold()).foregroundStyle(.white)
                                    .frame(width: 32, height: 32).background(.orange, in: Circle())
                            }
                            Text("It's quiet here for now").font(.headline)
                            Text(contentLanguage == "zh" && !includeEnglish ? "No Chinese decisions yet. Try including English." : "No public decisions match this view yet.")
                                .font(.subheadline).foregroundStyle(BmbTheme.muted).multilineTextAlignment(.center)
                            if contentLanguage == "zh" && !includeEnglish {
                                Button("Include English") { includeEnglish = true; Task { await load(reset: true) } }
                                    .font(.subheadline.bold()).foregroundStyle(.green)
                            }
                            Button("Ask everyone") { showCreate = true }
                                .font(.subheadline.bold()).foregroundStyle(BmbTheme.ink)
                                .padding(.horizontal, 20).frame(height: 42)
                                .background(BmbTheme.lime, in: Capsule())
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<columnCount, id: \.self) { column in
                        pinColumn(column, columnCount: columnCount, width: columnWidth)
                    }
                }
                if hasMore {
                    HStack {
                        Spacer(minLength: 0)
                        Button { Task { await load(reset: false) } } label: {
                            Label(BmbEngagementCopy.text(loading ? "Loading…" : "Load more", loading ? "加载中…" : "加载更多"),
                                  systemImage: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BmbTheme.ink)
                                .padding(.horizontal, 15).padding(.vertical, 8)
                                .background(BmbTheme.card, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(loading)
                        .frame(minHeight: 44)
                        Spacer(minLength: 0)
                    }
                } else if !items.isEmpty && !loading && error == nil {
                    Text(endMessage)
                        .font(.caption)
                        .foregroundStyle(BmbTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
            }.frame(width: contentWidth).padding(18)
        }
        }
        .background(BmbTheme.paper)
        .navigationBarHidden(true)
        .sheet(isPresented: $showCreate) { NavigationStack { CreateView() } }
        .sheet(isPresented: $showFilters) { filterSheet }
        .task { await openCurrentPage() }
        .refreshable { await load(reset: true) }
    }

    private var hasActiveFilters: Bool { filter != "recommended" || !tag.isEmpty || contentLanguage == "zh" && includeEnglish }

    private var endMessage: String {
        switch endMessageIndex {
        case 0: BmbEngagementCopy.text("That's the bottom of the bag. Your next question could be next!", "我们也是有底线的。下一条提问，等你来发！")
        case 1: BmbEngagementCopy.text("All caught up! Got something on your wish list?", "这次逛到底啦。愿望清单里还有什么想问？")
        case 2: BmbEngagementCopy.text("No more questions for now. Maybe yours is next?", "暂时没有更多啦，也许下一条就是你的问题。")
        default: BmbEngagementCopy.text("The shelf is empty for now. Bring us your next big maybe!", "问题架暂时见底。下一个纠结，交给大家吧！")
        }
    }

    private func filterTitle(_ value: String) -> String {
        switch value {
        case "unanswered": BmbEngagementCopy.text("No votes yet", "还没人投票")
        case "results": BmbEngagementCopy.text("With results", "已有结果")
        default: BmbEngagementCopy.text("Recommended", "推荐")
        }
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section(BmbEngagementCopy.text("Content language", "内容语言")) {
                    Picker(BmbEngagementCopy.text("My language", "我的语言"), selection: $contentLanguage) {
                        Text("简体中文").tag("zh")
                        Text("English").tag("en")
                    }
                    if contentLanguage == "zh" { Toggle(BmbEngagementCopy.text("Include English", "同时显示英语"), isOn: $includeEnglish) }
                }
                Section(BmbEngagementCopy.text("Decisions", "提问范围")) {
                    Picker(BmbEngagementCopy.text("Filter", "筛选"), selection: $draftFilter) {
                        ForEach(["recommended", "unanswered", "results"], id: \.self) { value in
                            Text(filterTitle(value)).tag(value)
                        }
                    }.pickerStyle(.inline).labelsHidden()
                }
                Section(BmbEngagementCopy.text("Product tag", "商品标签")) {
                    TextField(BmbEngagementCopy.text("Filter by tag", "按标签筛选"), text: $draftTag)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Button(BmbEngagementCopy.text("Reset filters", "重置筛选")) {
                    draftFilter = "recommended"; draftTag = ""
                }
            }
            .navigationTitle(BmbEngagementCopy.text("Filter", "筛选"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(BmbEngagementCopy.text("Cancel", "取消")) { showFilters = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(BmbEngagementCopy.text("Apply", "应用")) {
                        let nextTag = draftTag.trimmingCharacters(in: .whitespacesAndNewlines)
                        filter = draftFilter; tag = nextTag; showFilters = false
                        // 换条件时清空旧列表及快照，避免把旧结果误认作新筛选结果。
                        items = []; page = 0; snapshot = nil; hasMore = false; loading = true; openedPath = nil
                        Task { await openCurrentPage() }
                    }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func pinColumn(_ column: Int, columnCount: Int, width: CGFloat) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(items.enumerated()).filter { $0.offset % columnCount == column }, id: \.element.Id) { _, item in
                NavigationLink(destination: DecisionView(shareToken: item.ShareToken)) {
                    pinCard(item, width: width)
                }.buttonStyle(.plain)
            }
        }.frame(width: width)
    }

    private func pinCard(_ item: BmbPublicDecision, width: CGFloat) -> some View {
        let product = item.Products.first
        return VStack(alignment: .leading, spacing: 0) {
            if let image = product?.ImageUrl, let url = URL(string: image) {
                BmbExploreImage(url: url, width: width)
                    .overlay(alignment: .topTrailing) {
                        if let result = item.FinalChoice {
                            resultTag(result).padding(9)
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 5) {
                if product?.ImageUrl == nil && (item.Mode == "pick_one" || item.FinalChoice != nil) {
                    HStack(spacing: 6) {
                        if item.Mode == "pick_one" {
                            Text("A / B").font(.caption2.bold()).padding(6)
                                .background(BmbTheme.paper, in: RoundedRectangle(cornerRadius: 7))
                        }
                        if let result = item.FinalChoice { resultTag(result) }
                    }
                }
                Text(product?.Title ?? item.Question).font(.subheadline.bold()).lineLimit(2)
                if let price = product?.Price {
                    Text(BmbMoney.display(price, currency: product?.Currency))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BmbTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if let model = product?.Model, !model.isEmpty {
                    Text(model).font(.caption2).foregroundStyle(BmbTheme.muted).lineLimit(1)
                }
                Text(item.Question).font(.caption).foregroundStyle(BmbTheme.muted).lineLimit(2)
                if item.IsWaiting == true && item.FinalChoice != "waiting" { Text(BmbEngagementCopy.text("Taking a pause", "暂缓中")).font(.caption.bold()) }
                voteSummary(item)
            }.padding(12)
        }
        .frame(width: width, alignment: .leading)
        .background(BmbTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BmbTheme.ink.opacity(0.07)))
        .overlay(alignment: .topLeading) {
            if item.Mode == "pick_one" && product?.ImageUrl != nil {
                Text("A / B").font(.caption2.bold()).padding(6)
                    .background(BmbTheme.card, in: RoundedRectangle(cornerRadius: 7)).padding(9)
            }
        }
        .foregroundStyle(BmbTheme.ink)
        .task(id: item.ShareToken) {
            guard item.Votes == nil, (item.VoteCount ?? 0) > 0,
                  voteBreakdowns[item.ShareToken] == nil else { return }
            let path = "/d/\(item.ShareToken)"
            if let detail: BmbDecision = await BmbAPI().cached(path) {
                voteBreakdowns[item.ShareToken] = (detail.Votes, detail.VoteCount)
                Task { let _: BmbDecision? = try? await BmbAPI().detail(item.ShareToken, token: nil) }
            } else if let detail = try? await BmbAPI().detail(item.ShareToken, token: nil) {
                voteBreakdowns[item.ShareToken] = (detail.Votes, detail.VoteCount)
            }
        }
    }

    private func resultTag(_ choice: String) -> some View {
        Text(BmbEngagementCopy.finalChoice(choice))
            .font(.caption2.bold())
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .foregroundStyle(BmbTheme.ink)
            .background(BmbTheme.lime, in: Capsule())
    }

    @ViewBuilder
    private func voteSummary(_ item: BmbPublicDecision) -> some View {
        let total = voteBreakdowns[item.ShareToken]?.total ?? item.VoteCount ?? 0
        let supportColor = Color(red: 0.55, green: 0.69, blue: 0.54)
        let opposeColor = Color(red: 0.79, green: 0.62, blue: 0.61)
        if let votes = item.Votes ?? voteBreakdowns[item.ShareToken]?.votes {
            let left = votes[item.Mode == "pick_one" ? "a" : "buy"] ?? 0
            let right = votes[item.Mode == "pick_one" ? "b" : "pass"] ?? 0
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    if item.Mode == "pick_one" {
                        Text("A \(left)").foregroundStyle(supportColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Label("\(left)", systemImage: "hand.thumbsup").foregroundStyle(supportColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(BmbEngagementCopy.text("\(total) vote\(total == 1 ? "" : "s")", "共 \(total) 票"))
                        .font(.caption2).foregroundStyle(BmbTheme.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if item.Mode == "pick_one" {
                        Text("B \(right)").foregroundStyle(opposeColor)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Label("\(right)", systemImage: "hand.thumbsdown").foregroundStyle(opposeColor)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .font(.caption2.weight(.semibold))
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        supportColor.frame(width: total > 0 ? geometry.size.width * CGFloat(left) / CGFloat(total) : 0)
                        opposeColor.frame(width: total > 0 ? geometry.size.width * CGFloat(right) / CGFloat(total) : 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BmbTheme.muted.opacity(0.12))
                    .clipShape(Capsule())
                }
                .frame(height: 5)
            }
            .padding(.top, 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.Mode == "pick_one"
                ? BmbEngagementCopy.text("A \(left), B \(right), \(total) votes total", "A \(left) 票，B \(right) 票，共 \(total) 票")
                : BmbEngagementCopy.text("Support \(left), against \(right), \(total) votes total", "支持 \(left) 票，不支持 \(right) 票，共 \(total) 票"))
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    if item.Mode == "pick_one" { Text("A —").frame(maxWidth: .infinity, alignment: .leading) }
                    else { Label("—", systemImage: "hand.thumbsup").frame(maxWidth: .infinity, alignment: .leading) }
                    Text(BmbEngagementCopy.text("\(total) vote\(total == 1 ? "" : "s")", "共 \(total) 票"))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if item.Mode == "pick_one" { Text("B —").frame(maxWidth: .infinity, alignment: .trailing) }
                    else { Label("—", systemImage: "hand.thumbsdown").frame(maxWidth: .infinity, alignment: .trailing) }
                }.font(.caption2).foregroundStyle(BmbTheme.muted)
                Capsule().fill(BmbTheme.muted.opacity(0.12)).frame(height: 5)
            }.padding(.top, 5)
        }
    }

    private func publicPagePath(page: Int, snapshot: Int64? = nil) -> String {
        BmbPublicFeed.path(page: page, snapshot: snapshot, filter: filter, tag: tag,
                           language: contentLanguage, includeEnglish: includeEnglish)
    }

    private func openCurrentPage() async {
        let path = publicPagePath(page: 1)
        guard openedPath != path else { return }
        openedPath = path
        let request = UUID()
        feedRequest = request
        if let cached: BmbPublicPage = await BmbAPI().cached(path, forCurrentLaunch: true) {
            guard request == feedRequest else { return }
            items = cached.Items; page = cached.Page; snapshot = cached.Snapshot; hasMore = cached.HasMore
            voteBreakdowns = [:]
            loading = false; error = nil; timedOut = false
            // 静默更新仅写磁盘，本次启动继续展示原列表。
            Task { let _: BmbPublicPage? = try? await BmbAPI().call(path) }
        } else {
            await load(reset: true)
        }
    }

    private func load(reset: Bool) async {
        guard !loading || reset else { return }
        let current = UUID()
        feedRequest = current
        loading = true; error = nil; timedOut = false
        do {
            let nextPage = reset ? 1 : page + 1
            let response: BmbPublicPage = try await BmbAPI().call(publicPagePath(page: nextPage, snapshot: reset ? nil : snapshot), activateCache: true)
            guard current == feedRequest else { return }
            items = reset ? response.Items : items + response.Items
            if reset { voteBreakdowns = [:] }
            page = response.Page
            snapshot = response.Snapshot
            hasMore = response.HasMore
        } catch {
            let cancelled = Task.isCancelled || error is CancellationError
                || (error as? URLError)?.code == .cancelled
                || (error as NSError).code == NSURLErrorCancelled
            if current == feedRequest && !cancelled {
                timedOut = (error as? URLError)?.code == .timedOut
                    || ((error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorTimedOut)
                self.error = error.localizedDescription
            }
        }
        if current == feedRequest { loading = false }
    }
}

private struct BmbExploreImage: View {
    let url: URL
    let width: CGFloat
    @State private var height: CGFloat = 150

    var body: some View {
        BmbCachedImage(url: url, loadingLabel: "Loading image…", contentMode: .fit, preset: .list,
                       onImageLoaded: { size in
            guard size.width > 0 else { return }
            height = min(320, max(90, width * size.height / size.width))
        }) {
            ProgressView().tint(.green)
        }
        .frame(width: width, height: height)
        .background(BmbTheme.hero)
        .clipped()
    }
}
