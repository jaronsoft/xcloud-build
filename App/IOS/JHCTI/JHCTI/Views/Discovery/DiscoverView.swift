import Foundation
import SwiftUI

private let maximumSearchResults = 20_000
private let searchContentChangedStatus = 409

private struct SearchHistoryLoadKey: Equatable {
    let principal: String?
    let revision: Int
}

struct DiscoverView: View {
    @ObservedObject var store: SessionStore
    let initialKeyword: String
    let onMap: () -> Void
    @State private var keyword = ""
    @State private var searchedKeyword = ""
    @State private var results: [[String: Any]] = []
    @State private var resultPage = 1
    @State private var resultTotal = 0
    @State private var continuationToken: String?
    @State private var accessStates: [String: NativePublicFeatureAccessState] = [:]
    @State private var moduleStatusLoading = true
    @State private var moduleStatusError = false
    @State private var showClosedTicketNotice = false
    @State private var hotwords: [String] = []
    @State private var searchHistory: [String] = []
    @State private var historyBusy = false
    @State private var historyError: String?
    @State private var historyPrincipal: String?
    @State private var clearingHistoryFor: Set<String> = []
    @State private var historyClearUnconfirmed = false
    @State private var historyRevision = 0
    @State private var historyRequestSequence = 0
    @State private var loading = false
    @State private var loadingMore = false
    @State private var moreError: String?
    @State private var moreRequiresRestart = false
    @State private var searchSequence = 0
    @State private var error: String?

    private var currentHistoryPrincipal: String? { nativeTourismPrincipal(store.session?.accessToken) }

    var body: some View {
        let historyLoadKey = SearchHistoryLoadKey(principal: currentHistoryPrincipal, revision: historyRevision)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("发现江都").font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif))
                            .foregroundStyle(Brand.ink)
                        Text("搜索景点、导览路线、门票、活动、商品、住宿、线路、餐饮和攻略")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    }
                    .padding(.vertical, 15)
                    HStack(spacing: 8) {
                        TextField("搜索江都文旅内容", text: $keyword)
                            .font(.system(size: NativeTypography.size(14))).submitLabel(.search)
                            .onSubmit { Task { await searchNow() } }
                        Button("搜索") { Task { await searchNow() } }
                            .font(.system(size: NativeTypography.size(14), weight: .semibold))
                            .foregroundStyle(.white).padding(.horizontal, 20).frame(height: 36)
                            .background(Brand.primary, in: Capsule())
                    }
                    .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    if loading { ProgressView().tint(Brand.primary) }
                    if let error {
                        Button("\(error)　点此重试") { Task { await searchNow(for: searchedKeyword) } }
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                    }
                    if searchedKeyword.isEmpty {
                        if moduleStatusLoading || moduleStatusError {
                            HStack(spacing: 10) {
                                Text(moduleStatusLoading ? "正在确认服务开放状态…"
                                    : accessStates.values.allSatisfy { $0 == .unavailable }
                                        ? "暂时无法确认服务状态，入口已暂停。"
                                        : "部分服务状态无法确认，对应入口已暂停。")
                                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                Spacer(minLength: 0)
                                if moduleStatusError {
                                    Button("重试") { Task { await loadFeatureStatuses(forceRefresh: true) } }
                                        .disabled(moduleStatusLoading)
                                        .font(.system(size: NativeTypography.size(12), weight: .semibold))
                                }
                            }
                        }
                        DiscoveryCategoryGrid(store: store, accessStates: accessStates, onMap: onMap,
                            onClosedTicket: { showClosedTicketNotice = true })
                        if let principal = historyLoadKey.principal, historyPrincipal == principal {
                            searchHistorySection(principal: principal)
                        }
                        if !hotwords.isEmpty {
                            Text("热门搜索").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(hotwords.indices, id: \.self) { index in
                                        let word = hotwords[index]
                                        Button(word) { keyword = word; Task { await searchNow() } }
                                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(Color(red: 0.9, green: 0.95, blue: 0.93), in: Capsule())
                                    }
                                }
                            }
                        }
                    } else {
                        if !loading && results.isEmpty && error == nil {
                            Text("没有找到已发布的相关内容。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        }
                        ForEach(results.indices, id: \.self) { index in
                            NavigationLink {
                                searchDestination(results[index])
                            } label: {
                                HStack(spacing: 10) {
                                    searchCover(results[index]["ImageUrl"] as? String)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(results[index]["Title"] as? String ?? "文旅内容")
                                            .font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                                        Text(results[index]["Summary"] as? String ?? "查看详情")
                                            .font(.system(size: NativeTypography.size(14))).lineLimit(1).foregroundStyle(Brand.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
                                }
                                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        if resultTotal > maximumSearchResults {
                            Text("搜索结果较多，当前最多展示前 20,000 条，请缩小关键词范围。")
                                .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                        }
                        if !results.isEmpty && results.count < min(resultTotal, maximumSearchResults) {
                            if let moreError {
                                Button("\(moreError)　\(moreRequiresRestart ? "重新搜索" : "点此重试")") {
                                    Task {
                                        if moreRequiresRestart { await searchNow(for: searchedKeyword) }
                                        else { await loadMoreSearchResults() }
                                    }
                                }
                                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                            } else {
                                Button {
                                    Task { await loadMoreSearchResults() }
                                } label: {
                                    HStack(spacing: 6) {
                                        if loadingMore { ProgressView().tint(Brand.primary) }
                                        Text(loadingMore ? "正在加载…" : "加载更多（\(results.count)/\(resultTotal)）")
                                    }.frame(maxWidth: .infinity).padding(.vertical, 10)
                                }
                                .disabled(loadingMore || loading)
                                .font(.system(size: NativeTypography.size(14), weight: .medium))
                            }
                        } else if !results.isEmpty && resultTotal <= maximumSearchResults {
                            Text("已显示全部内容").font(.system(size: NativeTypography.size(12)))
                                .foregroundStyle(Brand.muted).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 20)
            }
            .background(Brand.background)
            .alert("景区门票暂未开放", isPresented: $showClosedTicketNotice) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text("你仍可浏览景点介绍。")
            }
            .task { await loadLanding() }
            .task(id: initialKeyword) {
                // 深链搜索独立于服务状态和热词加载，较慢的读取不会覆盖用户随后输入的关键词。
                guard !initialKeyword.isEmpty else { return }
                keyword = initialKeyword
                await searchNow(for: initialKeyword)
            }
            .task(id: historyLoadKey) { await loadSearchHistory(principal: historyLoadKey.principal) }
        }
    }

    @ViewBuilder
    private func searchHistorySection(principal: String) -> some View {
        let clearing = clearingHistoryFor.contains(principal)
        HStack {
            Text("最近搜索").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
            Spacer()
            if !searchHistory.isEmpty {
                Button("清空") { Task { await clearSearchHistory(principal: principal) } }
                    .font(.system(size: NativeTypography.size(12))).disabled(historyBusy || clearing)
            }
        }
        if historyClearUnconfirmed {
            Text("未收到清空确认，请核对最新记录。").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
        }
        if historyError != nil && !clearing {
            Button("重试读取搜索记录") { historyRevision += 1 }
                .font(.system(size: NativeTypography.size(12)))
        }
        if clearing || historyBusy {
            ProgressView(clearing ? "正在清空搜索记录…" : "正在加载搜索记录…").tint(Brand.primary)
        } else if historyError == nil && searchHistory.isEmpty {
            Text("暂无搜索记录").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
        }
        if !searchHistory.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(searchHistory.enumerated()), id: \.offset) { _, word in
                        Button(word) {
                            keyword = word
                            Task { await searchNow(for: word) }
                        }
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(red: 0.9, green: 0.95, blue: 0.93), in: Capsule())
                        .disabled(clearing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func searchDestination(_ result: [String: Any]) -> some View {
        let type = (result["Type"] as? String ?? result["type"] as? String ?? "").lowercased()
        if type == "ticket", accessStates["tickets"] != .open {
            Text("景区门票功能暂未开放")
        } else {
        let id = result["Id"] as? String ?? result["id"] as? String ?? ""
        let title = result["Title"] as? String ?? result["title"] as? String ?? "景点"
        let targetPath = result["TargetPath"] as? String ?? result["targetPath"] as? String ?? ""
        let components = URLComponents(string: "https://local.invalid\(targetPath)")
        let pathParts = components?.path.split(separator: "/").map(String.init) ?? []
        let guideRouteIDs = components?.queryItems?.filter { $0.name == "routeId" }.compactMap(\.value) ?? []
        let articleSiteIDs = components?.queryItems?.filter { $0.name == "siteid" }.compactMap(\.value) ?? []
        let parentID = pathParts.count >= 2 && pathParts[0] == "attractions" ? pathParts[1] : ""
        let validID: (String) -> Bool = { value in
            value.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil
                && Int64(value).map { $0 > 0 && String($0) == value } == true
        }
        switch type {
        case "scenicspot" where pathParts.count == 2 && pathParts[0] == "attractions" && id == parentID && validID(id):
            if let item = ResourceItem(["Id": id, "Name": title, "ResourceType": "ScenicSpot"]) {
                ResourceDetailView(store: store, item: item, onVisibilityChange: nil)
            }
        case "guideroute" where pathParts.count == 3 && pathParts[0] == "attractions"
            && pathParts[2] == "guide" && validID(parentID) && validID(id)
            && (guideRouteIDs.isEmpty || guideRouteIDs == [id]):
            if let item = ResourceItem(["Id": parentID, "Name": title, "ResourceType": "ScenicSpot"]) {
                ResourceDetailView(store: store, item: item, onVisibilityChange: nil, initialGuideRouteID: id)
            }
        case "ticket" where pathParts.count == 3 && pathParts[0] == "attractions"
            && pathParts[2] == "tickets" && validID(parentID) && validID(id):
            NativeTicketBookingView(store: store, resourceId: parentID, resourceName: title,
                admissionType: "", initialTicketTypeID: id)
        case "activity" where pathParts.count == 2 && pathParts[0] == "activities" && pathParts[1] == id && validID(id):
            ActivityDetailView(store: store, id: id)
        case "product" where pathParts.count == 2 && pathParts[0] == "products" && pathParts[1] == id && validID(id):
            ProductDetailView(store: store, id: id, fallbackCover: result["ImageUrl"] as? String)
        case "hotel" where pathParts.count == 2 && pathParts[0] == "hotels" && pathParts[1] == id && validID(id):
            HotelPublicDetailView(store: store, id: id)
        case "travelroute" where pathParts.count == 2 && pathParts[0] == "travel-routes" && pathParts[1] == id && validID(id):
            TravelRouteDetailView(store: store, id: id)
        case "diningstore" where pathParts.count == 2 && pathParts[0] == "restaurants" && pathParts[1] == id && validID(id):
            DiningPublicDetailView(store: store, id: id)
        case "article" where components?.percentEncodedPath == "/articles/\(id)" && pathParts.count == 2
            && pathParts[0] == "articles" && pathParts[1] == id && validID(id) && components?.fragment == nil
            && components?.queryItems?.count == 1 && articleSiteIDs.count == 1 && validID(articleSiteIDs[0]):
            ArticleDetailView(store: store, id: id, siteID: articleSiteIDs[0])
        default:
            searchDestinationUnavailable()
        }
        }
    }

    private func searchDestinationUnavailable() -> some View {
        ContentUnavailableView("内容暂不可用", systemImage: "exclamationmark.circle",
            description: Text("搜索目标与内容类型不匹配，请返回后重试。"))
    }

    @ViewBuilder
    private func searchCover(_ path: String?) -> some View {
        if let url = MobileAPI(store: store).mediaURL(path) {
            CachedRemoteImage(url: url) { Image("Hero").resizable().scaledToFill() }
                .frame(width: 58, height: 58).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image("Hero").resizable().scaledToFill()
                .frame(width: 58, height: 58).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func loadLanding() async {
        await loadFeatureStatuses()
        guard !Task.isCancelled else { return }
        do {
            if let value = try await MobileAPI(store: store).get("/api/JHCTISearch/GetPublicHotwords") as? [String] {
                hotwords = value
            }
        } catch is CancellationError {
            return
        } catch {
            // 热词读取失败时保留空态，搜索功能仍可使用。
        }
    }

    private func loadSearchHistory(principal: String?) async {
        guard !Task.isCancelled, currentHistoryPrincipal == principal else { return }
        if historyPrincipal != principal {
            historyPrincipal = principal
            searchHistory = []
            historyBusy = false
            historyError = nil
            historyClearUnconfirmed = false
        }
        guard let principal, !clearingHistoryFor.contains(principal) else { return }
        historyRequestSequence += 1
        let requestID = historyRequestSequence
        historyBusy = true
        historyError = nil
        defer { if currentHistoryPrincipal == principal && historyRequestSequence == requestID { historyBusy = false } }
        do {
            let response = try await MobileAPI(store: store).get("/api/JHCTISearch/GetMyHistory", authenticated: true,
                expectedPrincipal: principal)
            guard !Task.isCancelled, currentHistoryPrincipal == principal, historyRequestSequence == requestID else { return }
            guard let rows = response as? [[String: Any]] else {
                throw MobileAPIError.unavailable("搜索记录回执格式异常，请重试。")
            }
            var seen = Set<[UInt16]>()
            searchHistory = rows.compactMap { row in
                guard let value = row["Keyword"] as? String ?? row["keyword"] as? String else { return nil }
                let word = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty, word.utf16.count <= 80, seen.insert(Array(word.utf16)).inserted else { return nil }
                return word
            }.prefix(20).map { $0 }
        } catch is CancellationError { return }
        catch { if !Task.isCancelled && currentHistoryPrincipal == principal && historyRequestSequence == requestID { historyError = "搜索记录暂时无法加载。" } }
    }

    private func clearSearchHistory(principal: String) async {
        guard currentHistoryPrincipal == principal, !historyBusy, clearingHistoryFor.insert(principal).inserted else { return }
        historyRequestSequence += 1
        historyClearUnconfirmed = false
        defer {
            clearingHistoryFor.remove(principal)
            if currentHistoryPrincipal == principal { historyRevision += 1 }
        }
        do {
            let result = try await MobileAPI(store: store).delete("/api/JHCTISearch/ClearMyHistory", authenticated: true,
                expectedPrincipal: principal, requireExplicitResponse: true)
            guard (result as? String) == "" else { throw MobileAPIError.unavailable("清空搜索记录回执格式异常。") }
            if currentHistoryPrincipal == principal { searchHistory = [] }
        } catch {
            if currentHistoryPrincipal == principal { historyClearUnconfirmed = true }
        }
    }

    private func loadFeatureStatuses(forceRefresh: Bool = false) async {
        moduleStatusLoading = true
        moduleStatusError = false
        accessStates = [:]
        var statuses: [String: NativePublicFeatureAccessState] = [:]
        for category in DiscoveryCategory.all {
            guard !Task.isCancelled else { moduleStatusLoading = false; return }
            let status = await MobileAPI(store: store).featureAccessState(category.featureID, forceRefresh: forceRefresh)
            guard !Task.isCancelled else { moduleStatusLoading = false; return }
            statuses[category.id] = status
        }
        guard !Task.isCancelled else { moduleStatusLoading = false; return }
        accessStates = statuses
        moduleStatusError = statuses.values.contains(.unavailable)
        moduleStatusLoading = false
    }

    private func searchNow(for term: String? = nil) async {
        guard !Task.isCancelled else { return }
        let query = (term ?? keyword).trimmingCharacters(in: .whitespacesAndNewlines)
        searchSequence += 1
        let sequence = searchSequence
        resultPage = 1; resultTotal = 0; results = []; moreError = nil; moreRequiresRestart = false; loading = false; loadingMore = false
        continuationToken = nil
        guard !query.isEmpty else { searchedKeyword = ""; loading = false; return }
        searchedKeyword = query
        guard query.utf16.count <= 80 else {
            error = "搜索词最多 80 个字符，请缩短后再试。"
            loading = false
            return
        }
        loading = true; error = nil
        defer { if sequence == searchSequence { loading = false } }
        let requestToken = store.session?.accessToken
        let requestPrincipal = requestToken.map { MobileAPI(store: store).nativeTourismPrincipal($0) }
        do {
            guard let requestPath = searchRequestPath(keyword: query, page: 1),
                  let page = try await MobileAPI(store: store).get(requestPath,
                    authenticated: requestToken != nil,
                    expectedPrincipal: requestPrincipal) as? [String: Any],
                  let parsed = nativeSearchResultPage(page, page: 1, pageSize: 20) else {
                throw MobileAPIError.unavailable("搜索结果格式异常，请重试。")
            }
            guard sequence == searchSequence, !Task.isCancelled, store.session?.accessToken == requestToken else { return }
            results = parsed.rows; resultTotal = parsed.total; resultPage = 1
            continuationToken = parsed.continuationToken
            if requestPrincipal != nil {
                historyRequestSequence += 1
                historyRevision += 1
            }
        } catch is CancellationError {
            return
        } catch {
            guard sequence == searchSequence, !Task.isCancelled,
                  store.session?.accessToken == requestToken else { return }
            self.error = error.localizedDescription
        }
    }

    private func loadMoreSearchResults() async {
        guard !loadingMore, !loading, results.count < resultTotal,
              !searchedKeyword.isEmpty else { return }
        let sequence = searchSequence
        let nextPage = resultPage + 1
        let previousToken = continuationToken
        let requestToken = store.session?.accessToken
        let api = MobileAPI(store: store)
        let requestPrincipal = requestToken.map { api.nativeTourismPrincipal($0) }
        loadingMore = true; moreError = nil
        defer { if sequence == searchSequence { loadingMore = false } }
        do {
            guard let requestPath = searchRequestPath(keyword: searchedKeyword, page: nextPage, continuationToken: previousToken),
                  let response = try await api.get(requestPath,
                    authenticated: requestToken != nil,
                    expectedPrincipal: requestPrincipal) as? [String: Any] else {
                throw MobileAPIError.unavailable("搜索结果格式异常，请重试。")
            }
            guard sequence == searchSequence, !Task.isCancelled,
                  store.session.map({ api.nativeTourismPrincipal($0.accessToken) }) == requestPrincipal else { return }
            if nativeSearchPageIsOutOfRange(response, page: nextPage, pageSize: 20) {
                moreError = "搜索结果已发生变化。"
                moreRequiresRestart = true
                return
            }
            guard let parsed = nativeSearchResultPage(response, page: nextPage, pageSize: 20) else {
                throw MobileAPIError.unavailable("搜索结果格式异常，请重试。")
            }
            let existingKeys = Set(results.compactMap { row -> String? in
                guard let type = (row["Type"] as? String ?? row["type"] as? String),
                      let id = (row["Id"] as? String ?? row["id"] as? String) else { return nil }
                return "\(type.lowercased()):\(id)"
            })
            let nextKeys = parsed.rows.compactMap { row -> String? in
                guard let type = (row["Type"] as? String ?? row["type"] as? String),
                      let id = (row["Id"] as? String ?? row["id"] as? String) else { return nil }
                return "\(type.lowercased()):\(id)"
            }
            guard nextKeys.count == parsed.rows.count, Set(nextKeys).count == nextKeys.count,
                  existingKeys.isDisjoint(with: nextKeys), parsed.total == resultTotal,
                  (previousToken == nil) == (parsed.continuationToken == nil) else {
                moreError = "搜索结果已发生变化。"
                moreRequiresRestart = true
                return
            }
            results.append(contentsOf: parsed.rows); resultPage = nextPage
            continuationToken = parsed.continuationToken
        } catch {
            guard sequence == searchSequence, !Task.isCancelled, !(error is CancellationError),
                  store.session.map({ api.nativeTourismPrincipal($0.accessToken) }) == requestPrincipal else { return }
            moreRequiresRestart = (error as? MobileAPIError)?.httpStatusCode == searchContentChangedStatus
            moreError = moreRequiresRestart ? "搜索结果已发生变化。" : error.localizedDescription
        }
    }

    private func searchRequestPath(keyword: String, page: Int, continuationToken: String? = nil) -> String? {
        guard page > 0 else { return nil }
        var components = URLComponents()
        components.path = "/api/JHCTISearch/Search"
        var items = [
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: "20"),
            // 由 API 使用当前已发布站点，并在续页时核对站点范围。
            URLQueryItem(name: "articleSiteId", value: "0"),
        ]
        if let continuationToken { items.append(URLQueryItem(name: "continuationToken", value: continuationToken)) }
        components.queryItems = items
        return components.string
    }
}
