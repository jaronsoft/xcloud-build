import SwiftUI

struct NativeFavoritesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    @State private var rows: [[String: Any]] = []
    @State private var page = 1
    @State private var total: Int64 = 0
    @State private var loading = false
    @State private var error: String?
    @State private var failedPage: Int?
    @State private var removing: [String: Any]?
    @State private var detail: ResourceItem?
    @State private var revision = 0
    @State private var requestSequence = 0
    @State private var loadedToken = ""

    var body: some View {
        NavigationStack {
            Group {
                if loading && rows.isEmpty {
                    ProgressView("正在加载收藏…")
                } else if let error, rows.isEmpty {
                    VStack(spacing: 12) {
                        ContentUnavailableView(error, systemImage: "exclamationmark.arrow.circlepath",
                                               description: Text("检查登录状态后重试。"))
                        Button("重试第 \(failedPage ?? 1) 页") {
                            let retryPage = failedPage ?? 1
                            Task { await load(reset: retryPage == 1, pageOverride: retryPage) }
                        }
                        .disabled(loading)
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                    }
                } else if rows.isEmpty {
                    ContentUnavailableView("还没有收藏景点", systemImage: "heart",
                                           description: Text("去文旅地图发现并收藏喜欢的景点。"))
                } else {
                    List {
                        if let error {
                            Section {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(error).font(.system(size: NativeTypography.size(13)))
                                        .foregroundStyle(.red)
                                    Button(failedPage.map { "重试第 \($0) 页" } ?? "刷新并核对") {
                                        let retryPage = failedPage
                                        Task { await load(reset: retryPage == nil || retryPage == 1, pageOverride: retryPage) }
                                    }
                                    .disabled(loading)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowSeparator(.hidden).listRowBackground(Brand.background)
                        }
                        ForEach(rows.indices, id: \.self) { index in
                            let row = rows[index]
                            VStack(alignment: .leading, spacing: 9) {
                                Button { detail = ResourceItem(row) } label: {
                                    HStack(spacing: 12) {
                                        if let path = (row["ImageUrls"] as? [String])?.first ?? row["CoverUrl"] as? String,
                                           let url = MobileAPI(store: store).mediaURL(path) {
                                            CachedRemoteImage(url: url) { Color.gray.opacity(0.12) }
                                                .frame(width: 84, height: 72).clipShape(RoundedRectangle(cornerRadius: 9))
                                        }
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(row["Name"] as? String ?? "江都景点").font(.system(size: NativeTypography.size(16), weight: .semibold))
                                            Text(row["Region"] as? String ?? "江都区").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                                            Text(row["Description"] as? String ?? "查看景点介绍与出行信息").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted).lineLimit(2)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                    }.foregroundStyle(Brand.ink)
                                }.buttonStyle(.plain)
                                Button("取消收藏", role: .destructive) { removing = row }
                                    .font(.system(size: NativeTypography.size(14), weight: .medium))
                            }
                            .padding(.vertical, 5).listRowSeparator(.hidden).listRowBackground(Brand.background)
                        }
                        if error == nil && Int64(rows.count) < total {
                            Button(loading ? "正在加载…" : "加载更多") { Task { await load(reset: false) } }
                                .frame(maxWidth: .infinity).disabled(loading).listRowBackground(Brand.background)
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden).background(Brand.background)
                    .refreshable { await load(reset: true) }
                }
            }
            .background(Brand.background)
            .navigationTitle("我的收藏").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .task(id: "\(store.session?.accessToken ?? "")-\(revision)") { await load(reset: true) }
            .onChange(of: store.session?.accessToken) { _, token in
                let current = token ?? ""
                if current != loadedToken {
                    requestSequence += 1; rows = []; total = 0; failedPage = nil; error = nil
                    loadedToken = current; loading = false
                }
            }
            .confirmationDialog("确认取消收藏？", isPresented: Binding(
                get: { removing != nil }, set: { if !$0 { removing = nil } }
            ), titleVisibility: .visible) {
                Button("取消收藏", role: .destructive) { if let row = removing { Task { await remove(row) } } }
                Button("返回", role: .cancel) { removing = nil }
            }
            .sheet(item: $detail) { item in NavigationStack { ResourceDetailView(store: store, item: item) } }
            .onDisappear { requestSequence += 1; rows = [] }
        }
    }

    @MainActor private func load(reset: Bool, pageOverride: Int? = nil) async {
        guard let token = store.session?.accessToken, !token.isEmpty else {
            rows = []; total = 0; failedPage = nil; error = "请先登录文旅账号，再查看个人收藏。"; return
        }
        let requestedPrincipal = MobileAPI(store: store).nativeTourismPrincipal(token)
        let identityChanged = loadedToken != token
        let target = identityChanged ? 1 : (pageOverride ?? (reset ? 1 : page + 1))
        if identityChanged { rows = []; page = 1; total = 0; loadedToken = token; failedPage = nil }
        let replacesLoadedRows = target == 1
        if replacesLoadedRows { rows = []; total = 0 }
        loading = true; error = nil
        requestSequence += 1; let sequence = requestSequence
        do {
            let value = try await MobileAPI(store: store).get("/api/JHCTITourismResource/GetMyFavorites?page=\(target)&pageSize=20", authenticated: true, expectedPrincipal: requestedPrincipal) as? [String: Any]
            guard sequence == requestSequence, store.session?.accessToken == token else { return }
            guard let value, let data = (value["data"] ?? value["Data"]) as? [[String: Any]] else {
                throw MobileAPIError.unavailable("收藏列表响应格式异常")
            }
            guard data.allSatisfy({ row in nativeFavoriteResourceID(row) != nil }) else {
                throw MobileAPIError.unavailable("收藏列表数据格式异常，请刷新后重试。")
            }
            let count = try nativeFavoritePageTotal(value, page: target, pageSize: 20, rowCount: data.count)
            if replacesLoadedRows {
                rows = data
            } else {
                var merged = rows
                var positions: [String: Int] = [:]
                for (index, row) in merged.enumerated() {
                    if let id = nativeFavoriteResourceID(row) { positions[id] = index }
                }
                for row in data {
                    guard let id = nativeFavoriteResourceID(row) else { continue }
                    if let index = positions[id] { merged[index] = row }
                    else { positions[id] = merged.count; merged.append(row) }
                }
                rows = merged
            }
            total = max(Int64(count), Int64(rows.count)); page = target; failedPage = nil
        } catch {
            if sequence == requestSequence, target > 1, error is NativeFavoritePageOutOfRangeError {
                rows = []; total = 0; page = 1; failedPage = nil; self.error = nil
                await load(reset: true)
                return
            }
            if sequence == requestSequence { failedPage = target; self.error = error.localizedDescription }
        }
        if sequence == requestSequence { loading = false }
    }

    @MainActor private func remove(_ row: [String: Any]) async {
        guard let id = nativeFavoriteResourceID(row), let token = store.session?.accessToken else { return }
        let requestedPrincipal = MobileAPI(store: store).nativeTourismPrincipal(token)
        requestSequence += 1
        let sequence = requestSequence
        removing = nil; loading = true; error = nil
        defer { if sequence == requestSequence { loading = false } }
        do {
            let value = try await MobileAPI(store: store).delete("/api/JHCTITourismResource/RemoveFavorite?resourceId=\(id)", authenticated: true, expectedPrincipal: requestedPrincipal) as? String
            guard sequence == requestSequence,
                  MobileAPI(store: store).nativeTourismPrincipal(store.session?.accessToken ?? "") == requestedPrincipal else { return }
            guard value == id else { throw MobileAPIError.unavailable("取消收藏结果无法确认，请刷新列表核对") }
            rows.removeAll { nativeFavoriteResourceID($0) == id }; total = max(0, total - 1)
        } catch {
            guard sequence == requestSequence,
                  MobileAPI(store: store).nativeTourismPrincipal(store.session?.accessToken ?? "") == requestedPrincipal else { return }
            self.error = error.localizedDescription
        }
    }
}
