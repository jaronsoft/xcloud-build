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
    @State private var filter = "recommended"
    @State private var tag = ""
    @AppStorage("bmb.content_language") private var contentLanguage = Locale.current.language.languageCode?.identifier == "zh" ? "zh" : "en"
    @AppStorage("bmb.include_english") private var includeEnglish = true
    @State private var feedRequest = UUID()

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
                if hasActiveFilters {
                    Text([filter == "recommended" ? nil : filterTitle(filter), tag.isEmpty ? nil : "#\(tag)"].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(BmbTheme.muted)
                }
                if let error {
                    BmbCard { VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(.caption).foregroundStyle(.red)
                        Button("Retry") { Task { await load(reset: page == 0) } }
                    } }
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
                    Button(loading ? "Loading…" : "Load more") { Task { await load(reset: false) } }
                        .disabled(loading).frame(maxWidth: .infinity).padding(14)
                }
            }.frame(width: contentWidth).padding(18)
        }
        }
        .background(BmbTheme.paper)
        .navigationBarHidden(true)
        .sheet(isPresented: $showCreate) { NavigationStack { CreateView() } }
        .sheet(isPresented: $showFilters) { filterSheet }
        .task {
            if !hasActiveFilters, let cached: BmbPublicPage = await BmbAPI().cached("/decisions/public?page=1&size=20&language=\(contentLanguage)&includeEnglish=\(contentLanguage == "zh" && includeEnglish)") {
                items = cached.Items; page = cached.Page; snapshot = cached.Snapshot; hasMore = cached.HasMore
            }
            await load(reset: true)
        }
        .refreshable { await load(reset: true) }
    }

    private var hasActiveFilters: Bool { filter != "recommended" || !tag.isEmpty || contentLanguage == "zh" && includeEnglish }

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
                        items = []; page = 0; snapshot = nil; hasMore = false
                        Task { await load(reset: true) }
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
            }
            VStack(alignment: .leading, spacing: 5) {
                if item.Mode == "pick_one" && product?.ImageUrl == nil {
                    Text("A / B").font(.caption2.bold()).padding(6)
                        .background(BmbTheme.paper, in: RoundedRectangle(cornerRadius: 7))
                }
                Text(product?.Title ?? item.Question).font(.subheadline.bold()).lineLimit(2)
                if let model = product?.Model, !model.isEmpty {
                    Text(model).font(.caption2).foregroundStyle(BmbTheme.muted).lineLimit(1)
                }
                if let price = product?.Price {
                    Text(BmbMoney.display(price, currency: product?.Currency))
                        .font(.caption.bold()).foregroundStyle(BmbTheme.muted)
                }
                Text(item.Question).font(.caption).foregroundStyle(BmbTheme.muted).lineLimit(2)
                if item.IsWaiting == true { Text(BmbEngagementCopy.text("Taking a pause", "暂缓中")).font(.caption.bold()) }
                if let result = item.FinalChoice { Text(BmbEngagementCopy.text("Result: \(result)", "最终选择：\(result)")).font(.caption) }
                Text("\(item.VoteCount ?? 0) \(BmbEngagementCopy.text("votes", "票"))").font(.caption)
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
    }

    private func load(reset: Bool) async {
        guard !loading || reset else { return }
        let current = UUID()
        feedRequest = current
        loading = true; error = nil
        do {
            let nextPage = reset ? 1 : page + 1
            let snapshotQuery = reset ? "" : snapshot.map { "&snapshot=\($0)" } ?? ""
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "filter", value: filter), URLQueryItem(name: "tag", value: tag),
                URLQueryItem(name: "language", value: contentLanguage), URLQueryItem(name: "includeEnglish", value: contentLanguage == "zh" && includeEnglish ? "true" : "false")]
            let query = components.percentEncodedQuery ?? ""
            let response: BmbPublicPage = try await BmbAPI().call("/decisions/public?page=\(nextPage)&size=20&\(query)\(snapshotQuery)")
            guard current == feedRequest else { return }
            items = reset ? response.Items : items + response.Items
            page = response.Page
            snapshot = response.Snapshot
            hasMore = response.HasMore
        } catch {
            let cancelled = Task.isCancelled || error is CancellationError
                || (error as? URLError)?.code == .cancelled
                || (error as NSError).code == NSURLErrorCancelled
            if current == feedRequest && !cancelled { self.error = error.localizedDescription }
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
