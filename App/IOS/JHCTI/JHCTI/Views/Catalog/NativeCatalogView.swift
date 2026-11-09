import Foundation
import SwiftUI

struct CatalogModule: Identifiable {
    let id: String
    let title: String
    let path: String
    let featureID: String
    let sortOrder: Int
    let displayCount: Int
    let siteID: String
    let categoryIDs: [String]
    let categoryValue: String

    init(id: String, title: String, path: String, featureID: String,
         sortOrder: Int = 0, displayCount: Int = 6, siteID: String = "", categoryIDs: [String] = [], categoryValue: String = "") {
        self.id = id
        self.title = title
        self.path = path
        self.featureID = featureID
        self.sortOrder = sortOrder
        self.displayCount = displayCount
        self.siteID = siteID
        self.categoryIDs = categoryIDs
        self.categoryValue = categoryValue
    }

    init?(_ value: [String: Any]) {
        guard (value["IsEnabled"] as? Bool ?? value["isEnabled"] as? Bool) == true,
              let key = value["Key"] as? String ?? value["key"] as? String else { return nil }
        let endpoints = [
            "activities": "/api/JHCTIActivity/GetPublicPage",
            "products": "/api/JHCTIProduct/GetPublicPage",
            "hotels": "/api/JHCTIHotel/GetPublicPage",
            "dining": "/api/JHCTIDining/GetPublicStoresPage",
            "articles": "/api/app/articles/List"
        ]
        guard let path = endpoints[key] else { return nil }
        let features = [
            "activities": "MODULE-ACTIVITY", "products": "MODULE-PRODUCT",
            "hotels": "MODULE-HOTEL", "dining": "MODULE-DINING", "articles": "MODULE-GUIDE"
        ]
        guard let featureID = features[key] else { return nil }
        id = key
        let configuredTitle = value["Title"] as? String ?? value["title"] as? String ?? ""
        title = key == "articles" && (configuredTitle.isEmpty || configuredTitle == "文章列表")
            ? "文旅资讯" : configuredTitle.isEmpty ? key : configuredTitle
        self.path = path
        self.featureID = featureID
        sortOrder = value["SortOrder"] as? Int ?? value["sortOrder"] as? Int ?? 0
        let defaultCount = key == "activities" ? 3 : key == "articles" ? 4 : 6
        displayCount = min(12, max(1, value["DisplayCount"] as? Int ?? value["displayCount"] as? Int ?? defaultCount))
        siteID = value["SiteId"] as? String ?? value["siteId"] as? String ?? ""
        let singleCategoryID = value["CategoryId"] as? String ?? value["categoryId"] as? String
        categoryIDs = value["CategoryIds"] as? [String] ?? value["categoryIds"] as? [String]
            ?? singleCategoryID.map { [$0] } ?? []
        categoryValue = value["CategoryValue"] as? String ?? value["categoryValue"] as? String ?? ""
    }

    func listPath(pageSize: Int, page: Int = 1) -> String {
        if id != "articles" && id != "intangibleHeritage" { return "\(path)?page=\(max(1, page))&pageSize=\(pageSize)" }
        let categories = categoryIDs.filter { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        let scope = siteID.isEmpty ? "&siteid=1" : siteID.allSatisfy(\.isNumber) ? "&siteid=\(siteID)" : ""
        let category = categories.isEmpty ? "" : "&classids=\(categories.joined(separator: ","))"
        let value = categoryValue.isEmpty ? "" : "&categoryValue=\(categoryValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? categoryValue)"
        return "\(path)?page=\(max(1, page))&pagesize=\(pageSize)&includeAttachments=false\(scope)\(category)\(value)"
    }
}

struct CatalogView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SessionStore
    let module: CatalogModule
    @State private var rows: [[String: Any]] = []
    @State private var error: String?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var moreError: String?
    @State private var moreRequiresRestart = false
    @State private var currentPage = 1
    @State private var totalCount: Int?
    @State private var hasMore = false
    @State private var revision = 0
    @State private var requestSequence = 0
    @State private var keyword = ""
    @State private var appliedKeyword = ""
    @State private var loadMoreTask: Task<Void, Never>?
    private var isArticleList: Bool { module.id == "articles" || module.id == "intangibleHeritage" }
    private var isDiningList: Bool { module.id == "dining" }
    private var pageSize: Int { isArticleList ? 12 : isDiningList ? 10 : 30 }

    var body: some View {
        Group {
        if module.id == "products" { ProductCatalogView(store: store) }
        else if module.id == "routes" { TravelRouteCatalogView(store: store) }
        else if module.id == "hotels" { HotelCatalogView(store: store) }
        else { VStack(alignment: .leading, spacing: 12) {
            NativePageHeader(title: module.title,
                subtitle: isArticleList ? "发现江都故事，了解文旅新动态" : isDiningList ? "寻味江都，发现本地特色餐饮" : "浏览平台已发布内容，发现江都文旅")
            if isDiningList {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Brand.muted)
                    TextField("搜索商家、门店或地址", text: $keyword)
                        .submitLabel(.search)
                        .onChange(of: keyword) { _, value in keyword = String(value.prefix(100)) }
                        .onSubmit { applyDiningSearch() }
                    Button { applyDiningSearch() } label: {
                        Text("搜索").font(.system(size: NativeTypography.size(13), weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Brand.primary, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }.padding(9).background(.white, in: RoundedRectangle(cornerRadius: 11))
            }
            StatusView(loading: loading, error: error) { revision += 1 }
            if !loading && error == nil && rows.isEmpty {
                Text(isDiningList ? "暂时还没找到相关门店，试试搜索商家名或地址？" : "这里暂时还没有内容，过段时间再来看看吧。")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
            }
            List {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    NavigationLink {
                        if module.id == "activities" {
                            ActivityDetailView(store: store, id: row["Id"] as? String ?? "")
                        } else if isArticleList {
                            ArticleDetailView(store: store, id: row["Id"] as? String ?? "",
                                             siteID: module.siteID)
                        } else if module.id == "routes" {
                            TravelRouteDetailView(store: store, id: row["Id"] as? String ?? "")
                        } else if module.id == "hotels" {
                            HotelPublicDetailView(store: store, id: row["Id"] as? String ?? "")
                        } else if module.id == "dining" {
                            DiningPublicDetailView(store: store, id: row["Id"] as? String ?? "")
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(row["Name"] as? String ?? module.title).font(.title.bold())
                                    Text(row["Description"] as? String ?? "")
                                    Text("该服务的后续操作暂未开放").foregroundStyle(Brand.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                            }
                        }
                    } label: {
                        if isArticleList {
                            HStack(spacing: 12) {
                                let cover = catalogCover(row)
                                if let url = MobileAPI(store: store).mediaURL(cover) {
                                    CachedRemoteImage(url: url) { Brand.background }
                                        .frame(width: 88, height: 76).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                } else {
                                    Brand.background.frame(width: 88, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(row["Title"] as? String ?? row["Name"] as? String ?? "文旅资讯")
                                        .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
                                        .lineLimit(2)
                                    Text(row["HeadLine"] as? String ?? row["SubTitle"] as? String ?? "江都文旅资讯")
                                        .font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted).lineLimit(1)
                                    let date = row["PublishDate"] as? String ?? row["AddDate"] as? String ?? ""
                                    Text(String(date.prefix(10))).font(.system(size: NativeTypography.size(10))).foregroundStyle(Brand.muted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: NativeTypography.size(11), weight: .semibold))
                                    .foregroundStyle(Brand.muted)
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 13))
                        } else {
                        HStack(spacing: 12) {
                            if isDiningList {
                                NativeDiningThemeImage(store: store, path: catalogCover(row), width: 88, height: 68)
                            } else {
                                let cover = catalogCover(row)
                                if let url = MobileAPI(store: store).mediaURL(cover) {
                                    CachedRemoteImage(url: url) { Color(red: 0.94, green: 0.96, blue: 0.95) }
                                        .frame(width: 88, height: 68).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                } else {
                                    Color(red: 0.94, green: 0.96, blue: 0.95)
                                        .frame(width: 88, height: 68)
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                }
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(row["Name"] as? String ?? row["Title"] as? String ?? module.title).font(.headline)
                                if isDiningList, let brandName = row["RestaurantName"] as? String,
                                   let storeName = row["Name"] as? String, brandName != storeName {
                                    Text(brandName).font(.system(size: NativeTypography.size(11))).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Text(isDiningList
                                     ? (row["Address"] as? String ?? "地址待补充")
                                     : (row["Venue"] as? String ?? row["Region"] as? String ?? ""))
                                    .font(.system(size: NativeTypography.size(11))).foregroundStyle(.secondary).lineLimit(1)
                                if isDiningList, let hours = row["BusinessHours"] as? String, !hours.isEmpty {
                                    Text(hours).font(.system(size: NativeTypography.size(11))).foregroundStyle(.secondary).lineLimit(1)
                                }
                                if module.id == "activities" {
                                    Text("查看活动详情").font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.primary)
                                }
                            }
                        }
                        }
                    }
                }
                if (isArticleList || isDiningList) && hasMore {
                    Section {
                        Button(loadingMore ? "正在加载…" : moreError ?? "加载更多") {
                            loadMoreTask?.cancel()
                            loadMoreTask = Task { await loadMore() }
                        }
                            .disabled(loadingMore || loading)
                    }
                } else if (isArticleList || isDiningList) && !rows.isEmpty && !loading {
                    Section { Text("已显示全部内容").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Brand.background)
            .listRowSeparator(isArticleList ? .hidden : .visible)
            .refreshable { revision += 1 }
        }
        .padding()
        .background(Brand.background)
        .task(id: revision) { await load(forceRefresh: revision > 0) }
        }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .simultaneousGesture(edgeBackGesture { dismiss() })
        .onDisappear {
            requestSequence += 1
            loadMoreTask?.cancel()
            loadMoreTask = nil
            loading = false
            loadingMore = false
        }
    }

    private func applyDiningSearch() {
        let value = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        rows = []
        currentPage = 1
        hasMore = false
        guard value != appliedKeyword else { revision += 1; return }
        appliedKeyword = value
        revision += 1
    }

    private func load(forceRefresh: Bool = false) async {
        requestSequence += 1
        let requestID = requestSequence
        loading = true; error = nil; moreError = nil; loadingMore = false
        do {
            if !module.featureID.isEmpty {
                let accessState = await MobileAPI(store: store).featureAccessState(module.featureID)
                try Task.checkCancellation()
                guard accessState == .open else {
                    rows = []
                    throw MobileAPIError.unavailable(accessState.message(featureName: "该模块", action: "当前页面暂不可访问。"))
                }
            }
            var path = module.listPath(pageSize: pageSize)
            if isDiningList, !appliedKeyword.isEmpty {
                let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+?#%"))
                let encoded = appliedKeyword.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                path += "&keyword=\(encoded)"
            }
            let value = try await MobileAPI(store: store).getPublicCached(path, forceRefresh: forceRefresh) as? [String: Any]
            try Task.checkCancellation()
            guard requestID == requestSequence else { return }
            let pageRows: [[String: Any]]
            let count: Int?
            if isDiningList || isArticleList {
                guard let value, let parsed = nativePublicCatalogPage(value, page: 1, pageSize: pageSize) else {
                    throw MobileAPIError.unavailable(isDiningList ? "餐饮门店分页回执异常，请刷新后重试。" : "攻略资讯分页回执异常，请刷新后重试。")
                }
                pageRows = parsed.rows
                count = parsed.total
            } else {
                guard let value,
                      let parsedRows = value["data"] as? [[String: Any]] ?? value["Data"] as? [[String: Any]] else {
                    throw MobileAPIError.unavailable("内容列表格式无效")
                }
                pageRows = parsedRows
                count = (value["dataCount"] as? NSNumber)?.intValue ?? (value["DataCount"] as? NSNumber)?.intValue
                if let count, count < pageRows.count { throw MobileAPIError.unavailable("内容分页信息无效") }
            }
            guard pageRows.allSatisfy({ Int64(String(describing: $0["Id"] ?? "")).map { $0 > 0 } == true }) else {
                throw MobileAPIError.unavailable("内容编号无效")
            }
            guard Set(pageRows.compactMap({ $0["Id"].map { String(describing: $0) } })).count == pageRows.count else {
                throw MobileAPIError.unavailable("内容列表包含重复编号")
            }
            rows = pageRows
            currentPage = 1
            totalCount = count
            hasMore = count.map { $0 > pageRows.count } ?? ((isArticleList || isDiningList) && pageRows.count == pageSize)
        } catch is CancellationError {
            return
        } catch {
            if requestID == requestSequence && !Task.isCancelled { self.error = error.localizedDescription }
        }
        if requestID == requestSequence && !Task.isCancelled { loading = false }
    }

    private func loadMore() async {
        guard (isArticleList || isDiningList), hasMore, !loadingMore, !loading else { return }
        loadingMore = true; moreError = nil
        let nextPage = currentPage + 1
        let requestID = requestSequence
        do {
            var path = module.listPath(pageSize: pageSize, page: nextPage)
            if isDiningList, !appliedKeyword.isEmpty {
                let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+?#%"))
                let encoded = appliedKeyword.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                path += "&keyword=\(encoded)"
            }
            guard let value = try await MobileAPI(store: store).getPublicCached(path) as? [String: Any],
                  !Task.isCancelled, requestID == requestSequence else {
                throw MobileAPIError.unavailable("更多内容暂时无法读取")
            }
            let pageRows: [[String: Any]]
            let count: Int?
            if isDiningList || isArticleList {
                guard let parsed = nativePublicCatalogPage(value, page: nextPage, pageSize: pageSize) else {
                    throw MobileAPIError.unavailable(isDiningList ? "餐饮门店分页回执异常，请刷新后重试。" : "攻略资讯分页回执异常，请刷新后重试。")
                }
                pageRows = parsed.rows
                count = parsed.total
            } else {
                guard let parsedRows = value["data"] as? [[String: Any]] ?? value["Data"] as? [[String: Any]] else {
                    throw MobileAPIError.unavailable("更多内容格式无效")
                }
                pageRows = parsedRows
                count = (value["dataCount"] as? NSNumber)?.intValue ?? (value["DataCount"] as? NSNumber)?.intValue ?? totalCount
            }
            let existingIDs = Set(rows.compactMap { $0["Id"].map { String(describing: $0) } })
            let pageIDs = pageRows.compactMap { $0["Id"].map { String(describing: $0) } }
            guard !pageRows.isEmpty || count.map({ $0 <= rows.count }) == true,
                  pageRows.allSatisfy({ Int64(String(describing: $0["Id"] ?? "")).map { $0 > 0 } == true }),
                  Set(pageRows.compactMap { $0["Id"].map { String(describing: $0) } }).count == pageRows.count,
                  Set(pageIDs).count == pageIDs.count, pageIDs.allSatisfy({ !existingIDs.contains($0) }),
                  count.map({ $0 >= rows.count + pageRows.count }) ?? true else {
                throw MobileAPIError.unavailable("更多内容分页回执无效")
            }
            rows.append(contentsOf: pageRows)
            currentPage = nextPage; totalCount = count
            hasMore = count.map { $0 > rows.count } ?? (pageRows.count == pageSize)
        } catch is CancellationError {
            return
        } catch {
            if requestID == requestSequence && !Task.isCancelled { moreError = error.localizedDescription }
        }
        if requestID == requestSequence && !Task.isCancelled { loadingMore = false }
    }
}
