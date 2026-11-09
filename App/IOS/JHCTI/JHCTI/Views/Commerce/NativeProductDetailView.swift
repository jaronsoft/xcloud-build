import CoreFoundation
import Foundation
import SwiftUI

struct ProductDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SessionStore
    let id: String
    let fallbackCover: String?
    @State private var detail: [String: Any]?
    @State private var error: String?
    @State private var selectedSkuID: String?
    @State private var choosingSku = false
    @State private var addingToCart = false
    @State private var cartOpen = false
    @State private var cartMessage: String?
    @State private var detailLoading = true
    @State private var purchaseAccessState: NativePublicFeatureAccessState = .unavailable
    @State private var detailRevision = 0
    @State private var detailSequence = 0
    private var skus: [[String: Any]] { detail?["Skus"] as? [[String: Any]] ?? [] }
    @State private var addSequence = 0
    @State private var pageVisible = true
    private var selectedSku: [String: Any]? { skus.first { nativeProductSkuID($0) == selectedSkuID && selectedSkuID != nil } }
    private var displayPrice: Double? { selectedSku.flatMap(nativeProductSkuPrice) ?? (selectedSkuID == nil ? nativeProductPrice(detail?["MinPrice"]) : nil) }
    private var selectedRegularPrice: Double? { selectedSku.flatMap(nativeProductSkuPromotionOriginalPrice) }
    private var hasPurchasableSku: Bool { skus.contains(where: nativeProductSkuPurchasable) }
    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(spacing: 0) {
                    NativeProductGallery(store: store, detail: detail, fallback: fallbackCover)
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [.white.opacity(0.78), .white.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 105).allowsHitTesting(false)
                    }
                    if let detail {
                        VStack(alignment: .leading, spacing: 13) {
                            let categoryName = detail["CategoryName"] as? String ?? "江都好物"
                            let merchantName = (detail["MerchantName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            Text(merchantName.isEmpty ? categoryName : "\(categoryName) · \(merchantName)")
                                .font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted)
                            Text(detail["Name"] as? String ?? "江都好物")
                                .font(.system(size: NativeTypography.size(24), weight: .bold)).foregroundStyle(Brand.ink)
                            if let price = displayPrice {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 7) {
                                        if selectedRegularPrice != nil {
                                            Text("限时促销").font(.system(size: NativeTypography.size(10), weight: .semibold))
                                                .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 3)
                                                .background(Color(red: 0.72, green: 0.27, blue: 0.20), in: Capsule())
                                        }
                                        Text("¥\(price, specifier: "%.2f")\(selectedSku == nil ? " 起" : "")")
                                            .font(.system(size: NativeTypography.size(19), weight: .semibold))
                                            .foregroundStyle(Color(red: 0.72, green: 0.27, blue: 0.20))
                                    }
                                    if let regular = selectedRegularPrice {
                                        Text("日常价 ¥\(regular, specifier: "%.2f")")
                                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                    }
                                }
                            }
                            if !skus.isEmpty {
                                Button { choosingSku = true } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(selectedSku.map(nativeProductSkuLabel) ?? "请选择商品规格")
                                            if let selectedSku {
                                                Text(nativeProductSkuStock(selectedSku).map { "库存 \($0)" } ?? "库存待确认")
                                                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                            }
                                        }
                                        Spacer(); Image(systemName: "chevron.right")
                                    }
                                }.disabled(addingToCart).tint(Brand.primary)
                            }
                            Divider()
                            let attributes = detail["Attributes"] as? [[String: Any]] ?? []
                            if !attributes.isEmpty {
                                VStack(alignment: .leading, spacing: 9) {
                                    Text("商品属性").font(.system(size: NativeTypography.size(16), weight: .semibold))
                                        .foregroundStyle(Brand.ink)
                                    ForEach(Array(attributes.enumerated()), id: \.offset) { _, attribute in
                                        HStack(alignment: .top, spacing: 12) {
                                            Text(attribute["Name"] as? String ?? "")
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .foregroundStyle(Brand.muted)
                                            Text(attribute["Value"] as? String ?? "")
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .foregroundStyle(Brand.ink)
                                        }
                                        .font(.system(size: NativeTypography.size(13)))
                                    }
                                }
                                Divider()
                            }
                            Text("商品介绍").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                            Text(plainTextFromHTML(detail["Description"] as? String ?? ""))
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
                                .lineSpacing(4)
                            NativePublicProductReviews(store: store, productID: id,
                                reviewCount: detail["ReviewCount"] as? Int ?? 0,
                                averageRating: nativeProductPrice(detail["AverageRating"]) ?? 0)
                            NativeProductShare(productID: id, productName: detail["Name"] as? String ?? "江都好物")
                            NativeProductVideoSection(store: store, detail: detail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        .padding(.horizontal, 12).padding(.top, -15)
                    } else if detailLoading {
                        ProgressView("正在读取商品信息…").padding(18)
                    } else if let error {
                        VStack(spacing: 10) {
                            Text(error).foregroundStyle(.red)
                            Button("重新加载商品") { detailRevision += 1 }
                        }.padding(18)
                    }
                }
            }
            .background(Brand.background)
            .ignoresSafeArea(edges: .top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedRegularPrice != nil ? "限时促销" : selectedSku == nil ? "商品价格" : "已选规格价格")
                        .font(.system(size: NativeTypography.size(10))).foregroundStyle(Brand.muted)
                    if let price = displayPrice {
                        Text("¥\(price, specifier: "%.2f")\(selectedSku == nil ? " 起" : "")")
                            .font(.system(size: NativeTypography.size(15), weight: .bold)).foregroundStyle(Brand.primary)
                        if let regular = selectedRegularPrice {
                            Text("日常价 ¥\(regular, specifier: "%.2f")")
                                .font(.system(size: NativeTypography.size(10))).foregroundStyle(Brand.muted)
                        }
                    } else {
                        Text("价格待确认").font(.system(size: NativeTypography.size(13), weight: .medium)).foregroundStyle(Brand.muted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if purchaseAccessState == .open {
                    Button {
                        if selectedSku == nil { choosingSku = true }
                        else { Task { await addProductToCart() } }
                    } label: {
                        Text(addingToCart ? "正在加入…" : !hasPurchasableSku ? "暂无可售规格" : selectedSku == nil ? "选择规格" : "加入购物车")
                            .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Brand.primary, in: RoundedRectangle(cornerRadius: 10))
                    }.disabled(addingToCart || detailLoading || detail == nil || !hasPurchasableSku || (selectedSku != nil && !nativeProductSkuPurchasable(selectedSku!)))
                } else {
                    VStack(spacing: 3) {
                        Text(detailLoading ? "正在确认商品订购服务…" : purchaseAccessMessage)
                            .font(.system(size: NativeTypography.size(10))).foregroundStyle(Brand.muted)
                            .multilineTextAlignment(.center).lineLimit(2)
                        if !detailLoading && (purchaseAccessState == .unavailable || purchaseAccessState == .pendingConfirmation) {
                            Button("重新检查") { detailRevision += 1 }
                                .font(.system(size: NativeTypography.size(10)))
                        }
                    }.frame(maxWidth: .infinity).frame(minHeight: 44)
                }
                Button { cartOpen = true } label: {
                    Text("我的购物车").font(.system(size: NativeTypography.size(13), weight: .semibold))
                        .foregroundStyle(Brand.primary).frame(maxWidth: .infinity).frame(height: 44)
                        .background(Brand.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.primary.opacity(0.55)))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.white.opacity(0.98))
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .simultaneousGesture(DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard value.startLocation.x <= 32, horizontal >= 72,
                      horizontal > abs(vertical) * 1.25 else { return }
                dismiss()
            })
        .sheet(isPresented: $cartOpen) { NativeCartView(store: store) }
        .confirmationDialog("选择商品规格", isPresented: $choosingSku, titleVisibility: .visible) {
            ForEach(skus.indices, id: \.self) { index in
                let sku = skus[index]
                let price = nativeProductSkuPrice(sku).map { String(format: "¥%.2f", $0) } ?? "价格待确认"
                let regular = nativeProductSkuPromotionOriginalPrice(sku).map { "日常价 ¥\(String(format: "%.2f", $0)) · 限时促销 · " } ?? ""
                let stock = nativeProductSkuStock(sku).map { $0 > 0 ? "库存 \($0)" : "无货" } ?? "库存待确认"
                Button("\(nativeProductSkuLabel(sku)) · \(regular)\(price) · \(stock)") { selectedSkuID = nativeProductSkuID(sku) }
                    .disabled(!nativeProductSkuPurchasable(sku) || addingToCart)
            }
            Button("取消", role: .cancel) {}
        }
        .alert("购物车", isPresented: Binding(get: { cartMessage != nil }, set: { if !$0 { cartMessage = nil } })) {
            Button("知道了", role: .cancel) { cartMessage = nil }
        } message: { Text(cartMessage ?? "") }
        .task(id: "\(id)-\(detailRevision)") { await loadProductDetail(forceRefresh: detailRevision > 0) }
        .onChange(of: cartOpen) { _, open in
            addSequence += 1; addingToCart = false
            if !open { detailRevision += 1 }
        }
        .onChange(of: store.session?.accessToken) { old, new in
            if nativeTourismPrincipal(old) != nativeTourismPrincipal(new) {
                addSequence += 1; addingToCart = false; cartMessage = nil; cartOpen = false; choosingSku = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { detailRevision += 1 }
            else { detailSequence += 1; detail = nil; detailLoading = true; choosingSku = false
                addSequence += 1; addingToCart = false; cartMessage = nil }
        }
        .onAppear { pageVisible = true }
        .onDisappear { detailSequence += 1; detail = nil; detailLoading = true; choosingSku = false
            pageVisible = false; addSequence += 1; addingToCart = false; cartMessage = nil }
    }

    @MainActor private func loadProductDetail(forceRefresh: Bool) async {
        detailSequence += 1; let operation = detailSequence
        let previousSkuID = selectedSkuID
        detailLoading = true; detail = nil; error = nil; choosingSku = false
        defer { if operation == detailSequence { detailLoading = false } }
        do {
            purchaseAccessState = .unavailable
            let accessState = await MobileAPI(store: store).featureAccessState("F-ECOM-002", forceRefresh: true)
            guard operation == detailSequence else { return }
            purchaseAccessState = accessState
            guard let number = Int64(id), number > 0, String(number) == id else {
                throw MobileAPIError.unavailable("商品编号异常，请返回商品列表重新进入。")
            }
            let value = try await MobileAPI(store: store).getPublicCached(
                "/api/JHCTIProduct/GetPublicDetail?id=\(id)", forceRefresh: forceRefresh) as? [String: Any]
            guard operation == detailSequence else { return }
            guard let value, nativeProductDetailIsValid(value, expectedProductID: id),
                  let entries = value["Skus"] as? [[String: Any]] else {
                throw MobileAPIError.unavailable("商品详情或规格库存数据异常，请重新加载后再选择规格。")
            }
            detail = value
            // 保留仍存在的原规格；售罄时显示缺货，不自动改买另一款。
            if let previousSkuID {
                if entries.contains(where: { nativeProductSkuID($0) == previousSkuID }) { selectedSkuID = previousSkuID }
                else { selectedSkuID = nil; cartMessage = "原选择规格已不可用，请重新选择。" }
            } else { selectedSkuID = entries.count == 1 ? nativeProductSkuID(entries[0]) : nil }
        } catch {
            if operation == detailSequence { detail = nil; self.error = error.localizedDescription }
        }
    }

    @MainActor private func addProductToCart() async {
        guard !Task.isCancelled, pageVisible, scenePhase == .active, !cartOpen,
              !addingToCart, !detailLoading, detail != nil, error == nil,
              purchaseAccessState == .open else { return }
        guard let token = store.session?.accessToken, !token.isEmpty,
              let requestedPrincipal = nativeTourismPrincipal(token) else {
            cartMessage = "请先登录文旅账号，再加入购物车。"; return
        }
        let candidates = skus
        guard !candidates.isEmpty else { cartMessage = "该商品暂时没有可购买的规格。"; return }
        let resolved = selectedSku
        guard let resolved, let skuID = nativeProductSkuID(resolved) else {
            choosingSku = true; return
        }
        guard nativeProductSkuPurchasable(resolved) else {
            cartMessage = "该规格暂无库存或价格信息待确认，请刷新后重试。"; return
        }
        let revision = detailSequence
        addSequence += 1; let operation = addSequence
        addingToCart = true
        func isCurrent() -> Bool {
            !Task.isCancelled && pageVisible && scenePhase == .active && !cartOpen
                && addSequence == operation && detailSequence == revision && selectedSkuID == skuID
                && nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal
        }
        defer { if addSequence == operation { addingToCart = false } }
        let latestProduct: [String: Any]
        do {
            guard let value = try await MobileAPI(store: store).getPublicCached(
                "/api/JHCTIProduct/GetPublicDetail?id=\(id)", forceRefresh: true) as? [String: Any] else {
                if isCurrent() { cartMessage = "商品详情数据暂不可用，本次未提交加购请求。请稍后重试。" }
                return
            }
            guard isCurrent() else { return }
            guard nativeProductDetailIsValid(value, expectedProductID: id) else {
                cartMessage = "商品信息暂时无法核验，请刷新后重试；本次未提交加购请求。"
                return
            }
            latestProduct = value
        } catch {
            if isCurrent() { cartMessage = "暂时无法确认商品最新价格和库存，请稍后重试；本次未提交加购请求。" }
            return
        }
        guard let latestSkus = latestProduct["Skus"] as? [[String: Any]],
              let latestSku = latestSkus.first(where: { nativeProductSkuID($0) == skuID }),
              nativeProductSkuValuesMatch(resolved, latestSku) else {
            detail = latestProduct
            if (latestProduct["Skus"] as? [[String: Any]])?.contains(where: { nativeProductSkuID($0) == skuID }) != true {
                selectedSkuID = nil
                cartMessage = "原选择规格已下架，请重新选择可购买的规格。"
            } else {
                cartMessage = "商品价格、库存或规格信息已更新，请确认最新信息后再次加入购物车。"
            }
            return
        }
        let accessState = await MobileAPI(store: store).featureAccessState("F-ECOM-002", forceRefresh: true)
        guard isCurrent() else { return }
        purchaseAccessState = accessState
        guard accessState == .open else { return }
        do {
            let result = try await MobileAPI(store: store).post("/api/JHCTICart/EnsureItem", body: ["SkuId": skuID],
                                                       authenticated: true, expectedPrincipal: requestedPrincipal)
            guard isCurrent() else { return }
            guard nativeProductCartReceiptMatches(result as? [String: Any], productID: id, skuID: skuID) else {
                throw MobileAPIError.unavailable("购物车回执与所选商品不一致")
            }
            cartOpen = true
        } catch {
            if isCurrent() { cartMessage = "加购结果暂时无法确认，请打开购物车核对。再次加入会保留购物车中原有数量。" }
        }
    }

    private var purchaseAccessMessage: String {
        switch purchaseAccessState {
        case .open: return ""
        case .closed: return "暂时不能购买，你仍可查看商品详情。"
        case .pendingConfirmation: return "暂时无法确认是否可以购买。"
        case .unavailable: return "暂时无法确认是否可以购买。"
        }
    }

}

private struct NativePublicProductReviews: View {
    @ObservedObject var store: SessionStore
    let productID: String
    let reviewCount: Int
    let averageRating: Double
    @State private var rows: [[String: Any]] = []
    @State private var page = 1
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var failedPage = 1
    @State private var retry = 0
    @State private var previewURL: URL?
    @State private var previewFailed = false
    @State private var previewRetry = 0
    private let pageSize = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("已审核评价\(reviewCount > 0 ? " · \(reviewCount)" : "")")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.ink)
            if reviewCount > 0 && averageRating.isFinite && (1...5).contains(averageRating) {
                Text(String(format: "%.1f 分 · %d 条已审核评价", averageRating, reviewCount))
                    .font(.system(size: 12)).foregroundStyle(Brand.muted)
            }
            if loading && rows.isEmpty { ProgressView("正在加载已审核评价…").font(.system(size: 12)) }
            if rows.isEmpty && !loading && error == nil {
                Text("暂无已审核评价").font(.system(size: 12)).foregroundStyle(Brand.muted)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { entry in reviewCard(entry.element) }
            if let error {
                HStack {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
                    Spacer()
                    Button("重试") { page = failedPage; retry += 1 }.disabled(loading)
                }
            }
            if !loading && error == nil && rows.count < total {
                Button("查看更多评价") { page += 1 }.disabled(loading)
                    .frame(maxWidth: .infinity).font(.system(size: 13, weight: .semibold)).tint(Brand.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .task(id: "\(productID)-\(page)-\(retry)") { await load(requestedPage: page) }
        .onChange(of: productID) { _, _ in rows = []; page = 1; total = 0; error = nil; failedPage = 1 }
        .onChange(of: previewURL) { _, _ in previewFailed = false; previewRetry = 0 }
        .fullScreenCover(isPresented: Binding(get: { previewURL != nil }, set: { if !$0 { previewURL = nil } })) {
            if let url = previewURL {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    CachedRemoteImage(url: url, onLoadResult: { loaded in previewFailed = !loaded }) {
                        Color.black.overlay {
                            if previewFailed {
                                VStack(spacing: 10) {
                                    Text("评价图片暂时无法加载").foregroundStyle(.white)
                                    Button("重试") { previewFailed = false; previewRetry += 1 }.foregroundStyle(.white)
                                }
                            }
                        }
                    }
                    .id(previewRetry).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    Button("关闭") { previewURL = nil }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(12).background(.black.opacity(0.55), in: Capsule()).padding(12)
                }.preferredColorScheme(.dark)
            }
        }
    }

    @ViewBuilder private func reviewCard(_ row: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text((row["UserName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "游客")
                    .font(.system(size: 12)).foregroundStyle(Brand.muted)
                Spacer()
                Text(reviewDate(row["CreateTime"] as? String))
                    .font(.system(size: 11)).foregroundStyle(Brand.muted)
            }
            let rating = max(1, min(5, row["Rating"] as? Int ?? 0))
            Text(String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating))
                .font(.system(size: 13)).foregroundStyle(Color(red: 0.82, green: 0.54, blue: 0.20))
            Text((row["Content"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "评价者未填写文字内容。")
                .font(.system(size: 13)).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
            let media = reviewMediaURLs(row["MediaUrls"] as? [String] ?? [])
            if !media.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(media.enumerated()), id: \.element) { index, url in
                            Button { previewURL = url } label: {
                                CachedRemoteImage(url: url) {
                                    Color(red: 0.92, green: 0.95, blue: 0.93)
                                        .overlay { Image(systemName: "photo").foregroundStyle(Brand.muted) }
                                }
                                .frame(width: 68, height: 68).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain).accessibilityLabel("查看评价图片 \(index + 1)，共 \(media.count) 张")
                        }
                    }
                }
            }
            if let reply = row["Reply"] as? String, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("商家回复：\(reply)").font(.system(size: 12)).foregroundStyle(Brand.primary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                    .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.background, in: RoundedRectangle(cornerRadius: 11))
    }

    @MainActor private func load(requestedPage: Int) async {
        guard let numericID = Int64(productID), numericID > 0,
              String(numericID) == productID else { error = "商品编号无效"; return }
        loading = true; error = nil
        defer { if !Task.isCancelled { loading = false } }
        do {
            let path = "/api/JHCTIProductReview/GetPublicPage?productId=\(productID)&page=\(requestedPage)&pageSize=\(pageSize)"
            guard let response = try await MobileAPI(store: store).get(path) as? [String: Any] else {
                throw MobileAPIError.unavailable("商品评价分页响应格式异常")
            }
            try Task.checkCancellation()
            let returnedPage = response["page"] as? Int ?? response["Page"] as? Int ?? -1
            let returnedSize = response["PageSize"] as? Int ?? response["pageSize"] as? Int ?? -1
            let returnedTotal = response["dataCount"] as? Int ?? response["DataCount"] as? Int ?? -1
            guard let received = response["data"] as? [[String: Any]] ?? response["Data"] as? [[String: Any]],
                  returnedPage == requestedPage, returnedSize == pageSize, returnedTotal >= 0,
                  let expectedRows = nativeReportExpectedRows(page: requestedPage, total: returnedTotal, pageSize: pageSize),
                  received.count == expectedRows else {
                throw MobileAPIError.unavailable("商品评价分页回执异常")
            }
            for row in received {
                guard Self.validReview(row) else { throw MobileAPIError.unavailable("商品评价字段异常") }
            }
            try Task.checkCancellation()
            rows = requestedPage == 1 ? received : rows + received
            total = returnedTotal
        } catch is CancellationError {
            return
        } catch {
            failedPage = requestedPage
            self.error = error.localizedDescription
        }
    }

    private static func validReview(_ row: [String: Any]) -> Bool {
        guard let id = row["Id"] as? String, let number = Int64(id), number > 0, String(number) == id,
              let rating = row["Rating"] as? Int, (1...5).contains(rating),
              let content = row["Content"] as? String, content.utf16.count <= 2000,
              let created = row["CreateTime"] as? String, !created.isEmpty else { return false }
        return true
    }

    private func reviewMediaURLs(_ values: [String]) -> [URL] {
        var seen = Set<String>()
        return Array(values.compactMap { value -> URL? in
            let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard raw.count <= 2048, !raw.hasPrefix("//"), !raw.contains("\\"),
                  raw.rangeOfCharacter(from: .controlCharacters) == nil,
                  let url = MobileAPI(store: store).mediaURL(raw), url.scheme?.lowercased() == "https",
                  seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }.prefix(9))
    }

    private func reviewDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        return bookingBusinessDateTime(raw.replacingOccurrences(of: " ", with: "T")).map { String($0.prefix(10)) } ?? "—"
    }
}

private func nativeProductDetailIsValid(_ value: [String: Any], expectedProductID: String) -> Bool {
    func validID(_ raw: Any?) -> Bool {
        guard let value = raw as? String else { return false }
        return nativeProductSkuID(["Id": value]) == value
    }
    func validMoney(_ raw: Any?) -> Double? {
        guard let amount = nativeProductPrice(raw), amount <= 999_999_999 else { return nil }
        return amount
    }
    guard validID(expectedProductID), value["Id"] as? String == expectedProductID,
          validID(value["CategoryId"]), validID(value["MerchantId"]),
          let name = value["Name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let categoryName = value["CategoryName"] as? String, !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let merchantName = value["MerchantName"] as? String, !merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          value["Description"] == nil || value["Description"] is NSNull || value["Description"] is String,
          let minPrice = validMoney(value["MinPrice"]), minPrice >= 0,
          nativeProductSkuStock(["AvailableStock": value["AvailableStock"] ?? NSNull()]) != nil,
          nativeProductSkuStock(["AvailableStock": value["ReviewCount"] ?? NSNull()]) != nil,
          let rating = nativeProductPrice(value["AverageRating"]), rating <= 5,
          value["MediaUrls"] is [String], value["VideoUrls"] is [String],
          let attributes = value["Attributes"] as? [[String: Any]], attributes.count <= 30,
          let specifications = value["Specifications"] as? [[String: Any]],
          let skuRows = value["Skus"] as? [[String: Any]], !skuRows.isEmpty else { return false }
    guard attributes.allSatisfy({ attribute in
        guard let attributeName = attribute["Name"] as? String,
              let attributeValue = attribute["Value"] as? String else { return false }
        return !attributeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attributeName.utf16.count <= 40
            && !attributeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attributeValue.utf16.count <= 200
    }), specifications.allSatisfy({ specification in
        guard let specificationName = specification["Name"] as? String,
              !specificationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              specificationName.utf16.count <= 40, let values = specification["Values"] as? [String], !values.isEmpty else { return false }
        return values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf16.count <= 100 }
    }) else { return false }
    let specificationNames = specifications.compactMap { ($0["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    guard specificationNames.count == specifications.count, Set(specificationNames).count == specificationNames.count else { return false }
    var specificationOptions: [String: Set<String>] = [:]
    for specification in specifications {
        guard let rawName = specification["Name"] as? String,
              let values = specification["Values"] as? [String] else { return false }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedValues = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(normalizedValues).count == normalizedValues.count else { return false }
        specificationOptions[name] = Set(normalizedValues)
    }
    let skuIDs = skuRows.compactMap(nativeProductSkuID)
    guard skuIDs.count == skuRows.count, Set(skuIDs).count == skuIDs.count else { return false }
    var combinations = Set<String>()
    return skuRows.allSatisfy { sku in
        guard nativeProductSkuID(sku) != nil, let price = validMoney(sku["Price"]),
              let stock = nativeProductSkuStock(["AvailableStock": sku["AvailableStock"] ?? NSNull()]),
              let specs = sku["Specs"] as? [String: Any] else { return false }
        let rawOriginalPrice = sku["OriginalPrice"]
        let originalPrice = rawOriginalPrice == nil || rawOriginalPrice is NSNull ? nil : validMoney(rawOriginalPrice)
        if rawOriginalPrice != nil && !(rawOriginalPrice is NSNull) && originalPrice == nil { return false }
        if let originalPrice, originalPrice < price { return false }
        let promotionID = sku["PromotionId"]
        if promotionID != nil && !(promotionID is NSNull) && !validID(promotionID) { return false }
        let normalizedSpecs = specs.compactMap { key, rawValue -> (String, String)? in
            guard let specValue = rawValue as? String else { return nil }
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedValue = specValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedKey.isEmpty, normalizedKey.utf16.count <= 40,
                  !normalizedValue.isEmpty, normalizedValue.utf16.count <= 100 else { return nil }
            return (normalizedKey, normalizedValue)
        }
        guard normalizedSpecs.count == specs.count,
              Set(normalizedSpecs.map(\.0)).count == normalizedSpecs.count else { return false }
        if !specificationNames.isEmpty {
            let valuesByName = Dictionary(uniqueKeysWithValues: normalizedSpecs)
            guard normalizedSpecs.count == specificationNames.count,
                  Set(valuesByName.keys) == Set(specificationNames) else { return false }
            var combination: [String] = []
            for name in specificationNames {
                guard let specValue = valuesByName[name], specificationOptions[name, default: []].contains(specValue) else { return false }
                combination.append(specValue)
            }
            let signature = combination.map { "\($0.utf16.count):\($0)" }.joined()
            guard combinations.insert(signature).inserted else { return false }
        }
        return stock >= 0
    }
}

private func nativeProductSkuID(_ sku: [String: Any]) -> String? {
    guard let value = sku["Id"] as? String, let number = Int64(value), number > 0, String(number) == value else { return nil }
    return value
}

private func nativeProductSkuPrice(_ sku: [String: Any]) -> Double? { nativeProductPrice(sku["Price"]) }

private func nativeProductSkuPromotionOriginalPrice(_ sku: [String: Any]) -> Double? {
    guard let rawID = sku["PromotionId"] as? String, let id = Int64(rawID), id > 0,
          String(id) == rawID, let current = nativeProductSkuPrice(sku),
          let original = nativeProductPrice(sku["OriginalPrice"]), original > current else { return nil }
    return original
}

private func nativeProductSkuStock(_ sku: [String: Any]) -> Int? {
    guard let number = sku["AvailableStock"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let stock = number.doubleValue
    guard stock.isFinite, stock >= 0, stock <= Double(Int32.max), stock.rounded(.towardZero) == stock else { return nil }
    return Int(stock)
}

private func nativeProductSkuPurchasable(_ sku: [String: Any]) -> Bool {
    nativeProductSkuID(sku) != nil && nativeProductSkuPrice(sku) != nil && (nativeProductSkuStock(sku) ?? 0) > 0
}

private func nativeProductSkuValuesMatch(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
    func number(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull), let number = value as? NSNumber else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }
    func identifier(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return String(describing: value)
    }
    func specs(_ value: Any?) -> [(String, String)]? {
        guard let values = value as? [String: String] else { return nil }
        return values.map { ($0.key.trimmingCharacters(in: .whitespacesAndNewlines), $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .sorted { $0.0 < $1.0 }
    }
    guard nativeProductSkuID(lhs) == nativeProductSkuID(rhs),
          number(lhs["Price"]) == number(rhs["Price"]),
          number(lhs["OriginalPrice"]) == number(rhs["OriginalPrice"]),
          identifier(lhs["PromotionId"]) == identifier(rhs["PromotionId"]),
          number(lhs["AvailableStock"]) == number(rhs["AvailableStock"]),
          let leftSpecs = specs(lhs["Specs"]), let rightSpecs = specs(rhs["Specs"]),
          leftSpecs.count == rightSpecs.count else { return false }
    return zip(leftSpecs, rightSpecs).allSatisfy { $0.0.0 == $0.1.0 && $0.0.1 == $0.1.1 }
}

// EnsureItem 返回完整购物车；仅在目标规格确实存在且属于当前商品时引导进入购物车。
private func nativeProductCartReceiptMatches(_ value: [String: Any]?, productID: String, skuID: String) -> Bool {
    guard nativeProductSkuID(["Id": productID]) != nil, nativeProductSkuID(["Id": skuID]) != nil,
          let rows = value?["Items"] as? [[String: Any]] else { return false }
    let ids = rows.compactMap(nativeProductSkuID)
    guard ids.count == rows.count, Set(ids).count == ids.count else { return false }
    let matches = rows.filter { $0["SkuId"] as? String == skuID }
    guard matches.count == 1, let row = matches.first, row["ProductId"] as? String == productID,
          let rawQuantity = row["Quantity"], let quantity = nativeProductSkuStock(["AvailableStock": rawQuantity]),
          (1...99).contains(quantity) else { return false }
    return true
}

private func nativeProductSkuLabel(_ sku: [String: Any]) -> String {
    let specs = (sku["Specs"] as? [String: String])?.sorted { $0.key < $1.key }
        .map { "\($0.key) \($0.value)" }.joined(separator: " · ") ?? ""
    return specs.isEmpty ? (sku["SkuCode"] as? String ?? "默认规格") : specs
}
