import SwiftUI

struct ExploreView: View {
    @State private var showCreate = false
    @State private var items: [BmbPublicDecision] = []
    @State private var page = 0
    @State private var snapshot: Int64?
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("THE COMMUNITY").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                        Text("Explore decisions").font(.system(size: 31, weight: .black, design: .rounded))
                        Text("See what people are thinking of buying.").font(.system(size: 14)).foregroundStyle(BmbTheme.muted)
                    }
                    Spacer(minLength: 0)
                    Button { showCreate = true } label: {
                        Label("Post", systemImage: "plus")
                            .font(.subheadline.bold()).foregroundStyle(BmbTheme.ink)
                            .padding(.horizontal, 15).frame(height: 44)
                            .background(BmbTheme.lime, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if let error {
                    BmbCard { VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(.caption).foregroundStyle(.red)
                        Button("Retry") { Task { await load(reset: page == 0) } }
                    } }
                }
                if items.isEmpty && !loading && error == nil {
                    BmbCard { Text("No public decisions yet.").foregroundStyle(BmbTheme.muted) }
                }
                HStack(alignment: .top, spacing: 12) {
                    pinColumn(0)
                    pinColumn(1)
                }
                if hasMore {
                    Button(loading ? "Loading…" : "Load more") { Task { await load(reset: false) } }
                        .disabled(loading).frame(maxWidth: .infinity).padding(14)
                }
            }.padding(18)
        }
        .background(BmbTheme.paper)
        .navigationBarHidden(true)
        .sheet(isPresented: $showCreate) { NavigationStack { CreateView() } }
        .task {
            if let cached: BmbPublicPage = await BmbAPI().cached("/decisions/public?page=1&size=20") {
                items = cached.Items; page = cached.Page; snapshot = cached.Snapshot; hasMore = cached.HasMore
            }
            await load(reset: true)
        }
        .refreshable { await load(reset: true) }
    }

    private func pinColumn(_ column: Int) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(items.enumerated()).filter { $0.offset % 2 == column }, id: \.element.Id) { index, item in
                NavigationLink(destination: DecisionView(shareToken: item.ShareToken)) {
                    pinCard(item, index: index)
                }.buttonStyle(.plain)
            }
        }.frame(maxWidth: .infinity)
    }

    private func pinCard(_ item: BmbPublicDecision, index: Int) -> some View {
        let product = item.Products.first
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                BmbTheme.hero
                if let image = product?.ImageUrl, let url = URL(string: image) {
                    BmbCachedImage(url: url) {
                        Image("LaunchMark").resizable().scaledToFit().padding(40)
                    }
                } else {
                    Image("LaunchMark").resizable().scaledToFit().padding(40)
                }
                if item.Mode == "pick_one" {
                    Text("A / B").font(.caption2.bold()).padding(6)
                        .background(BmbTheme.card, in: RoundedRectangle(cornerRadius: 7)).padding(9)
                }
            }
            .frame(height: [188.0, 230.0, 205.0][index % 3]).clipped()
            VStack(alignment: .leading, spacing: 5) {
                Text(product?.Title ?? item.Question).font(.subheadline.bold()).lineLimit(2)
                if let model = product?.Model, !model.isEmpty {
                    Text(model).font(.caption2).foregroundStyle(BmbTheme.muted).lineLimit(1)
                }
                if let price = product?.Price {
                    Text("\(product?.Currency ?? "") \(price, specifier: "%.2f")")
                        .font(.caption.bold()).foregroundStyle(BmbTheme.muted)
                }
                Text(item.Question).font(.caption).foregroundStyle(BmbTheme.muted).lineLimit(2)
            }.padding(12)
        }
        .background(BmbTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BmbTheme.ink.opacity(0.07)))
        .foregroundStyle(BmbTheme.ink)
    }

    private func load(reset: Bool) async {
        guard !loading else { return }
        loading = true; error = nil
        do {
            let nextPage = reset ? 1 : page + 1
            let snapshotQuery = reset ? "" : snapshot.map { "&snapshot=\($0)" } ?? ""
            let response: BmbPublicPage = try await BmbAPI().call("/decisions/public?page=\(nextPage)&size=20\(snapshotQuery)")
            items = reset ? response.Items : items + response.Items
            page = response.Page
            snapshot = response.Snapshot
            hasMore = response.HasMore
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}
