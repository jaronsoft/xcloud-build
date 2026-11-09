import Foundation
import SwiftUI

struct ProductCatalogView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SessionStore
    @State private var rows: [[String: Any]] = []
    @State private var categories: [[String: Any]] = []
    @State private var keyword = ""
    @State private var appliedKeyword = ""
    @State private var categoryID = ""
    @State private var sortBy = "recommend"
    @State private var revision = 0
    @State private var loading = true
    @State private var error: String?
    @State private var total = 0
    @State private var currentPage = 1
    @State private var catalogSequence = 0
    @State private var loadedQuery: [String]?
    private var querySignature: [String] { [appliedKeyword, categoryID, sortBy, String(revision)] }
    private let sorts = [("推荐", "recommend"), ("最新", "newest"), ("销量", "salesDesc"),
                         ("价格从低到高", "priceAsc"), ("价格从高到低", "priceDesc")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                NativePageHeader(title: "江都好物", subtitle: "浏览已发布商品，查看规格与当前库存")
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Brand.muted)
                    TextField("搜索商品名称", text: $keyword).submitLabel(.search)
                        .onSubmit { appliedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines) }
                    Button("搜索") { appliedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .font(.system(size: NativeTypography.size(13), weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Brand.primary, in: RoundedRectangle(cornerRadius: 8))
                }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        categoryButton("全部", id: "")
                        ForEach(categories.indices, id: \.self) { index in
                            categoryButton(categories[index]["Name"] as? String ?? "分类",
                                           id: categories[index]["Id"] as? String ?? "")
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sorts.indices, id: \.self) { index in
                            let option = sorts[index]
                            Button(option.0) { sortBy = option.1 }
                                .font(.system(size: NativeTypography.size(11))).foregroundStyle(sortBy == option.1 ? Color.white : Brand.ink)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(sortBy == option.1 ? Brand.primary : .white, in: Capsule())
                        }
                    }
                }
                StatusView(loading: loading, error: error) { revision += 1 }
                if !loading && error == nil && rows.isEmpty { Text("暂无相关商品").foregroundStyle(Brand.muted) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(rows.indices, id: \.self) { index in
                        NavigationLink {
                            ProductDetailView(store: store, id: rows[index]["Id"] as? String ?? "",
                                              fallbackCover: catalogCover(rows[index]))
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Group {
                                    if let url = MobileAPI(store: store).mediaURL(catalogCover(rows[index])) {
                                        CachedRemoteImage(url: url) { Brand.background }
                                            .frame(height: 142).frame(maxWidth: .infinity).clipped()
                                    } else { Brand.background.frame(height: 142) }
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(rows[index]["Name"] as? String ?? "江都好物")
                                        .font(.system(size: NativeTypography.size(13), weight: .semibold)).lineLimit(2).foregroundStyle(Brand.ink)
                                    Text(rows[index]["CategoryName"] as? String ?? "精选商品")
                                        .font(.system(size: NativeTypography.size(10))).foregroundStyle(Brand.muted)
                                    if let price = rows[index]["MinPrice"] as? NSNumber {
                                        Text("¥\(price.doubleValue, specifier: "%.2f") 起")
                                            .font(.system(size: NativeTypography.size(13), weight: .semibold))
                                            .foregroundStyle(Color(red: 0.72, green: 0.27, blue: 0.20))
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white, in: RoundedRectangle(cornerRadius: 11))
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                                .shadow(color: Brand.ink.opacity(0.07), radius: 7, y: 3)
                        }.buttonStyle(.plain)
                    }
                }
                if !loading && error == nil && !rows.isEmpty {
                    if total > rows.count {
                        Button("加载更多商品") { Task { await load(page: currentPage + 1) } }
                            .font(.system(size: NativeTypography.size(12), weight: .medium)).foregroundStyle(Brand.primary)
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                    } else {
                        Text("已显示全部商品").font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                }
                Text("商品信息及价格以平台当前发布数据为准。")
                    .font(.system(size: NativeTypography.size(10))).foregroundStyle(Brand.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(Color(red: 0.94, green: 0.97, blue: 0.96),
                                            in: RoundedRectangle(cornerRadius: 9))
            }.padding(16)
        }.background(Color(red: 0.97, green: 0.97, blue: 0.99))
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .simultaneousGesture(edgeBackGesture { dismiss() })
            .task { await loadCategories() }
            .task(id: querySignature) { await load(page: 1) }
            .onDisappear { catalogSequence += 1 }
    }

    private func categoryButton(_ title: String, id: String) -> some View {
        Button(title) { categoryID = id }.font(.system(size: NativeTypography.size(11)))
            .foregroundStyle(categoryID == id ? Color.white : Brand.ink)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(categoryID == id ? Brand.primary : .white, in: Capsule())
    }

    private func loadCategories() async {
        if let value = try? await MobileAPI(store: store).getPublicCached("/api/JHCTIProduct/GetPublicCategories") {
            categories = value as? [[String: Any]] ?? (value as? [String: Any])?["data"] as? [[String: Any]] ?? []
        }
    }

    private func load(page: Int) async {
        let signature = querySignature
        guard page == 1 || (!loading && loadedQuery == signature && page == currentPage + 1) else { return }
        catalogSequence += 1; let operation = catalogSequence
        loading = true; error = nil
        if page == 1 { rows = []; total = 0; currentPage = 1; loadedQuery = nil }
        defer { if operation == catalogSequence && querySignature == signature { loading = false } }
        do {
            guard await MobileAPI(store: store).featureEnabled("MODULE-PRODUCT") else {
                throw MobileAPIError.unavailable("商品模块暂未开放")
            }
            guard operation == catalogSequence, querySignature == signature, !Task.isCancelled else { return }
            var path = "/api/JHCTIProduct/GetPublicPage?page=\(page)&pageSize=12&sortBy=\(signature[2])&includeSkus=false&includeDetails=false&includeReviewSummary=false"
            if !signature[1].isEmpty { path += "&categoryId=\(signature[1])" }
            let queryCharacters = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?+"))
            if !signature[0].isEmpty { path += "&keyword=\(signature[0].addingPercentEncoding(withAllowedCharacters: queryCharacters) ?? "")" }
            guard let value = try await MobileAPI(store: store).getPublicCached(path, forceRefresh: signature[3] != "0") as? [String: Any],
                  let loaded = value["data"] as? [[String: Any]] ?? value["Data"] as? [[String: Any]] ?? value["Items"] as? [[String: Any]] else {
                throw MobileAPIError.unavailable("商品列表数据异常，请重试。")
            }
            guard operation == catalogSequence, querySignature == signature, !Task.isCancelled else { return }
            rows = page == 1 ? loaded : rows + loaded
            currentPage = page
            total = value["dataCount"] as? Int ?? value["DataCount"] as? Int ?? rows.count
            loadedQuery = signature
        } catch {
            if !(error is CancellationError), operation == catalogSequence, querySignature == signature {
                self.error = error.localizedDescription
            }
        }
    }
}
