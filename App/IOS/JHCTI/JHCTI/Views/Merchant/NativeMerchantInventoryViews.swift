import Foundation
import SwiftUI

private struct NativeMerchantProductDraft {
    var name: String
    var description: String
    var prices: [String]
    var originalPrices: [String]
}

private struct NativeMerchantProductAction: Identifiable {
    let row: [String: Any]
    let action: String
    var id: String { "\(row["Id"] ?? "")-\(action)" }
}

struct MerchantStockView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let merchantID: String
    let stockStore: [String: Any]
    @State private var rows: [[String: Any]] = []
    @State private var drafts: [String: String] = [:]
    @State private var keyword = ""
    @State private var page = 1
    @State private var total = 0
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var revision = 0
    @State private var requestSequence = 0

    private var storeID: String { Self.idString(stockStore["Id"] ?? stockStore["id"]) }
    private var storeName: String { stockStore["Name"] as? String ?? "授权门店" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(storeName) · 保存后由服务端记录库存变更历史。")
                    .font(.caption).foregroundStyle(Brand.muted)
                HStack {
                    TextField("搜索商品或 SKU 编码", text: $keyword)
                        .textFieldStyle(.roundedBorder).submitLabel(.search)
                        .onSubmit { Task { await load(page: 1) } }
                    Button("搜索") { Task { await load(page: 1) } }
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                }
                StatusView(loading: loading, error: error) { revision += 1 }
                if !loading && error == nil && rows.isEmpty {
                    Text("当前门店暂无可管理的 SKU。").foregroundStyle(Brand.muted)
                }
                ForEach(rows.indices, id: \.self) { index in stockCard(rows[index]) }
                if !loading && error == nil && rows.count < total {
                    Button("加载更多（\(rows.count)/\(total)）") { Task { await load(page: page + 1) } }
                        .disabled(loading).frame(maxWidth: .infinity)
                }
            }.padding(16)
        }
        .background(Brand.background)
        .navigationTitle("门店库存")
        .task(id: revision) { await load(page: 1) }
        .onChange(of: store.session?.accessToken) { _, _ in dismiss() }
    }

    private func stockCard(_ row: [String: Any]) -> some View {
        let skuID = Self.idString(row["SkuId"] ?? row["skuId"])
        let stock = row["StoreStock"] ?? row["storeStock"]
        return VStack(alignment: .leading, spacing: 8) {
            Text((row["ProductName"] ?? row["productName"]) as? String ?? "未命名商品").font(.headline)
            Text("SKU \((row["SkuCode"] ?? row["skuCode"]) as? String ?? skuID) · ¥\(String(describing: row["Price"] ?? row["price"] ?? "—"))")
                .font(.caption).foregroundStyle(Brand.muted)
            Text(stock is NSNull || stock == nil ? "尚未单独设置门店库存" : "当前库存 \(String(describing: stock!))")
                .font(.caption).foregroundStyle(Brand.muted)
            HStack {
                TextField("库存数量", text: Binding(get: { drafts[skuID] ?? "" }, set: { drafts[skuID] = $0 }))
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                Button(saving ? "保存中…" : "保存") { Task { await save(row) } }
                    .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(saving)
            }
        }.merchantCard()
    }

    private func load(page targetPage: Int) async {
        guard !merchantID.isEmpty, merchantID.allSatisfy(\.isNumber), !storeID.isEmpty, storeID.allSatisfy(\.isNumber),
              let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else {
            error = "商户、门店或登录范围无效，请返回工作台重新进入。"; loading = false; return
        }
        requestSequence += 1
        let sequence = requestSequence
        let append = targetPage > 1
        loading = true; error = nil
        if !append { rows = []; drafts = [:] }
        do {
            let escaped = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))) ?? ""
            guard let response = try await MobileAPI(store: store).get(
                "/api/JHCTIMerchant/GetStoreSkuStock?merchantId=\(merchantID)&storeId=\(storeID)&page=\(targetPage)&pageSize=20&keyword=\(escaped)",
                authenticated: true, expectedPrincipal: expectedPrincipal) as? [String: Any],
                let loaded = response["data"] as? [[String: Any]] ?? response["Data"] as? [[String: Any]] else {
                throw MobileAPIError.unavailable("库存分页响应格式异常，请重试。")
            }
            guard requestSequence == sequence, store.session?.accessToken == token else { return }
            let count = Self.intValue(response["dataCount"] ?? response["DataCount"])
            guard loaded.count <= 20, count >= loaded.count, count >= 0,
                  loaded.allSatisfy({ !Self.idString($0["SkuId"] ?? $0["skuId"]).isEmpty && !Self.idString($0["ProductId"] ?? $0["productId"]).isEmpty }) else {
                throw MobileAPIError.unavailable("库存分页数据不完整，请刷新后重试。")
            }
            var next = append ? rows : []
            for item in loaded {
                let id = Self.idString(item["SkuId"] ?? item["skuId"])
                if let index = next.firstIndex(where: { Self.idString($0["SkuId"] ?? $0["skuId"]) == id }) { next[index] = item }
                else { next.append(item) }
                let stock = item["StoreStock"] ?? item["storeStock"]
                drafts[id] = stock is NSNull || stock == nil ? "" : Self.intValue(stock).description
            }
            rows = next; total = count; page = targetPage
        } catch is CancellationError {
            if requestSequence == sequence { loading = false }
        } catch {
            guard requestSequence == sequence, store.session?.accessToken == token else { return }
            self.error = error.localizedDescription
        }
        if requestSequence == sequence { loading = false }
    }

    private func save(_ row: [String: Any]) async {
        guard !saving else { return }
        let skuID = Self.idString(row["SkuId"] ?? row["skuId"])
        let raw = drafts[skuID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, raw.allSatisfy(\.isNumber), let stock = Int(raw), (0...2_000_000_000).contains(stock) else {
            error = "请输入 0 到 2000000000 的整数库存。"; return
        }
        guard let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { error = "登录已失效，请重新登录。"; return }
        saving = true; error = nil
        let body: [String: Any] = [
            "Id": Self.idString(row["Id"] ?? row["id"] ?? "0"), "Version": Self.intValue(row["Version"] ?? row["version"]),
            "MerchantId": merchantID, "StoreId": storeID, "SkuId": skuID, "Stock": stock
        ]
        var committed = false
        do {
            _ = try await MobileAPI(store: store).post("/api/JHCTIMerchant/SetStoreSkuStock", body: body, authenticated: true,
                expectedPrincipal: expectedPrincipal)
            committed = true
            guard store.session?.accessToken == token else { return }
            await load(page: page)
        } catch is CancellationError {
            if store.session?.accessToken == token { error = committed ? "库存已保存，但刷新被取消；请重新读取确认当前状态。" : "库存保存结果未确认，请刷新库存并核对版本后再操作。" }
        } catch { if store.session?.accessToken == token { self.error = "\(error.localizedDescription)；请刷新库存并核对版本后重试。" } }
        saving = false
    }

    private static func idString(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return value as? String ?? String(describing: value)
    }
    private static func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }
}

struct MerchantProductsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let merchantID: String
    @State private var rows: [[String: Any]] = []
    @State private var drafts: [String: NativeMerchantProductDraft] = [:]
    @State private var keyword = ""
    @State private var page = 1
    @State private var total = 0
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var moreError: String?
    @State private var revision = 0
    @State private var requestSequence = 0
    @State private var pendingAction: NativeMerchantProductAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("保存后成为草稿，需单独提交审核；分类、运费及新商品仍由管理端维护。")
                    .font(.caption).foregroundStyle(Brand.muted)
                HStack {
                    TextField("搜索商品名称", text: $keyword)
                        .textFieldStyle(.roundedBorder).submitLabel(.search)
                        .onSubmit { Task { await load(page: 1) } }
                    Button("搜索") { Task { await load(page: 1) } }
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                }
                StatusView(loading: loading, error: error) { revision += 1 }
                if !loading && error == nil && rows.isEmpty { Text("当前商户暂无商品资料。").foregroundStyle(Brand.muted) }
                ForEach(rows.indices, id: \.self) { index in
                    productCard(index: index)
                }
                if let moreError { Text(moreError).font(.caption).foregroundStyle(.red) }
                if rows.count < total && !rows.isEmpty {
                    Button(loading ? "正在加载…" : "加载更多（\(rows.count)/\(total)）") {
                        Task { await load(page: page + 1) }
                    }
                    .disabled(loading).frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .background(Brand.background)
        .navigationTitle("商品资料与价格")
        .task(id: revision) { await load(page: 1) }
        .onChange(of: store.session?.accessToken) { _, _ in dismiss() }
        .confirmationDialog(actionTitle, isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
            Button(actionTitle, role: pendingAction?.action == "Offline" ? .destructive : nil) {
                guard let pendingAction else { return }
                Task { await runAction(pendingAction) }
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: {
            Text("确认\(actionTitle)“\(pendingAction?.row["Name"] as? String ?? "该商品")”？")
        }
    }

    private var actionTitle: String {
        switch pendingAction?.action {
        case "review": return "提交平台审核"
        case "Published": return "上架商品"
        default: return "下架商品"
        }
    }

    @ViewBuilder private func productCard(index: Int) -> some View {
        let row = rows[index]
        let id = Self.idString(row["Id"])
        let draft = drafts[id] ?? NativeMerchantProductDraft(name: row["Name"] as? String ?? "",
            description: row["Description"] as? String ?? "", prices: [], originalPrices: [])
        let review = Self.intValue(row["ReviewStatus"])
        let reviewRemark = row["ReviewRemark"] as? String ?? ""
        VStack(alignment: .leading, spacing: 8) {
            Text(row["Name"] as? String ?? "未命名商品").font(.headline)
            Text("\(Self.statusName(row["Status"] as? String ?? "")) · \(Self.reviewName(review))\(reviewRemark.isEmpty ? "" : " · \(reviewRemark)")")
                .font(.caption).foregroundStyle(Brand.muted)
            Text("\(row["CategoryName"] as? String ?? "分类未设置") · \(row["FamilyName"] as? String ?? "独立商品") · 运费：\(row["FreightTemplateName"] as? String ?? "未设置")")
                .font(.caption2).foregroundStyle(Brand.muted)
            TextField("商品名称", text: Binding(get: { draft.name }, set: { setDraft(id, draft: draft, name: $0) }))
                .textFieldStyle(.roundedBorder)
            TextField(row["UseFamilyDescription"] as? Bool == false ? "商品介绍" : "商品介绍 · 继承系列资料",
                text: Binding(get: { draft.description }, set: { setDraft(id, draft: draft, description: $0) }))
                .textFieldStyle(.roundedBorder).disabled(row["UseFamilyDescription"] as? Bool != false)
            let skus = row["Skus"] as? [[String: Any]] ?? []
            ForEach(skus.indices, id: \.self) { skuIndex in
                let sku = skus[skuIndex]
                Text(sku["SkuCode"] as? String ?? "SKU \(skuIndex + 1)").font(.subheadline.weight(.semibold))
                HStack {
                    TextField("售价（元）", text: Binding(get: { draft.prices.indices.contains(skuIndex) ? draft.prices[skuIndex] : "" },
                        set: { setPrice(id, draft: draft, index: skuIndex, value: $0, original: false) }))
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    TextField("原价（可空）", text: Binding(get: { draft.originalPrices.indices.contains(skuIndex) ? draft.originalPrices[skuIndex] : "" },
                        set: { setPrice(id, draft: draft, index: skuIndex, value: $0, original: true) }))
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                }
            }
            Button(saving ? "保存中…" : "保存资料与价格") { Task { await save(row, draft: draft) } }
                .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(saving)
            HStack {
                if review == 0 || review == 3 {
                    Button("提交平台审核") { pendingAction = NativeMerchantProductAction(row: row, action: "review") }
                        .disabled(saving || (row["Status"] as? String == "Published"))
                }
                if review == 2 {
                    let published = row["Status"] as? String == "Published"
                    Button(published ? "下架商品" : "上架商品", role: published ? .destructive : nil) {
                        pendingAction = NativeMerchantProductAction(row: row, action: published ? "Offline" : "Published")
                    }.disabled(saving)
                }
            }
        }
        .merchantCard()
    }

    private func load(page targetPage: Int) async {
        guard merchantID.allSatisfy(\.isNumber), let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else {
            error = "商户或登录状态无效，请返回工作台重新进入。"; loading = false; return
        }
        requestSequence += 1
        let sequence = requestSequence
        let append = targetPage > 1
        loading = true; error = nil; moreError = nil
        if !append { rows = []; drafts = [:] }
        do {
            let escaped = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let response = try await MobileAPI(store: store).get(
                "/api/JHCTIProduct/GetPage?page=\(targetPage)&pageSize=20&merchantId=\(merchantID)&keyword=\(escaped)&includeSkuDetails=true",
                authenticated: true, expectedPrincipal: expectedPrincipal) as? [String: Any]
            guard requestSequence == sequence, store.session?.accessToken == token, let response,
                  let loaded = response["data"] as? [[String: Any]] ?? response["Data"] as? [[String: Any]] else {
                throw MobileAPIError.unavailable("商品分页响应格式异常，请重试。")
            }
            let count = Self.intValue(response["dataCount"] ?? response["DataCount"])
            guard loaded.count <= 20, count >= loaded.count, count >= 0,
                  loaded.allSatisfy({ Self.idString($0["Id"]).count > 0 && $0["Skus"] is [[String: Any]] }) else {
                throw MobileAPIError.unavailable("商品分页数据不完整，请刷新后重试。")
            }
            var next = append ? rows : []
            for item in loaded {
                let id = Self.idString(item["Id"])
                if let existing = next.firstIndex(where: { Self.idString($0["Id"]) == id }) { next[existing] = item }
                else { next.append(item) }
            }
            rows = next; total = count; page = targetPage
            for item in loaded {
                let id = Self.idString(item["Id"])
                let skus = item["Skus"] as? [[String: Any]] ?? []
                drafts[id] = NativeMerchantProductDraft(name: item["Name"] as? String ?? "",
                    description: item["Description"] as? String ?? "",
                    prices: skus.map { String(describing: $0["Price"] ?? "") },
                    originalPrices: skus.map { $0["OriginalPrice"] is NSNull ? "" : String(describing: $0["OriginalPrice"] ?? "") })
            }
        } catch is CancellationError {
            if requestSequence == sequence { loading = false }
        } catch {
            guard requestSequence == sequence else { return }
            if append { moreError = error.localizedDescription }
            else { rows = []; drafts = [:]; self.error = error.localizedDescription }
        }
        if requestSequence == sequence { loading = false }
    }

    private func save(_ row: [String: Any], draft: NativeMerchantProductDraft) async {
        guard !saving else { return }
        let id = Self.idString(row["Id"])
        let skus = row["Skus"] as? [[String: Any]] ?? []
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.prices.count == skus.count,
              draft.prices.indices.allSatisfy({ index in
                  guard let price = Decimal(string: draft.prices[index]), price >= 0 else { return false }
                  let originalText = draft.originalPrices.indices.contains(index) ? draft.originalPrices[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                  return originalText.isEmpty || (Decimal(string: originalText).map { $0 >= price } ?? false)
              }) else { error = "请检查商品名称和 SKU 价格；原价需不低于售价。"; return }
        guard let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { error = "登录已失效，请重新登录。"; return }
        saving = true; error = nil
        let saveSkus: [[String: Any]] = skus.enumerated().map { index, old in
            var value = old
            value["Price"] = draft.prices[index]
            let original = draft.originalPrices.indices.contains(index) ? draft.originalPrices[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            value["OriginalPrice"] = original.isEmpty ? NSNull() : original as Any
            return value
        }
        let body: [String: Any] = [
            "Id": id, "Version": Self.intValue(row["Version"]), "MerchantId": merchantID,
            "FamilyId": Self.idString(row["FamilyId"] ?? "0"), "UseFamilyDescription": row["UseFamilyDescription"] as? Bool ?? true,
            "UseFamilyAttributes": row["UseFamilyAttributes"] as? Bool ?? true, "CategoryId": Self.idString(row["CategoryId"] ?? "0"),
            "FreightTemplateId": Self.idString(row["FreightTemplateId"] ?? "0"), "DeliveryType": row["DeliveryType"] as? String ?? "Physical",
            "Name": draft.name.trimmingCharacters(in: .whitespacesAndNewlines), "Description": draft.description,
            "MediaUrls": row["MediaUrls"] ?? [], "Attributes": row["Attributes"] ?? [],
            "Specifications": row["Specifications"] ?? [], "SortOrder": Self.intValue(row["SortOrder"]), "Skus": saveSkus
        ]
        var committed = false
        do {
            _ = try await MobileAPI(store: store).post("/api/JHCTIProduct/Save", body: body, authenticated: true,
                expectedPrincipal: expectedPrincipal)
            committed = true
            guard store.session?.accessToken == token else { return }
            await load(page: page)
        } catch is CancellationError {
            if store.session?.accessToken == token { error = committed ? "商品已保存，但刷新被取消；请重新读取确认当前状态。" : "商品保存结果未确认，请重新读取商品并核对版本后再操作。" }
        } catch { if store.session?.accessToken == token { self.error = "\(error.localizedDescription)；请重新读取商品并核对版本后再操作。" } }
        saving = false
    }

    private func runAction(_ pending: NativeMerchantProductAction) async {
        guard !saving, let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        saving = true; error = nil
        var body: [String: Any] = ["Id": Self.idString(pending.row["Id"]), "Version": Self.intValue(pending.row["Version"])]
        let path: String
        if pending.action == "review" { path = "/api/JHCTIProduct/SubmitReview" }
        else { path = "/api/JHCTIProduct/UpdateStatus"; body["Status"] = pending.action }
        var committed = false
        do {
            _ = try await MobileAPI(store: store).post(path, body: body, authenticated: true,
                expectedPrincipal: expectedPrincipal)
            committed = true
            guard store.session?.accessToken == token else { return }
            await load(page: page)
        } catch is CancellationError {
            if store.session?.accessToken == token { error = committed ? "商品操作已提交，但刷新被取消；请重新读取确认当前状态。" : "商品操作结果未确认，请刷新商品状态后再操作。" }
        } catch { if store.session?.accessToken == token { self.error = "\(error.localizedDescription)；请刷新商品状态后再操作。" } }
        saving = false
    }

    private func setDraft(_ id: String, draft: NativeMerchantProductDraft, name: String? = nil, description: String? = nil) {
        var next = draft
        if let name { next.name = name }
        if let description { next.description = description }
        drafts[id] = next
    }

    private func setPrice(_ id: String, draft: NativeMerchantProductDraft, index: Int, value: String, original: Bool) {
        var next = draft
        if original {
            while next.originalPrices.count <= index { next.originalPrices.append("") }
            next.originalPrices[index] = value
        } else {
            while next.prices.count <= index { next.prices.append("") }
            next.prices[index] = value
        }
        drafts[id] = next
    }

    private static func idString(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let string = value as? String { return string }
        return String(describing: value)
    }
    private static func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }
    private static func statusName(_ value: String) -> String {
        ["Draft": "草稿", "Scheduled": "已安排上架", "Published": "已上架", "Offline": "已下架"][value] ?? "状态未知"
    }
    private static func reviewName(_ value: Int) -> String {
        [0: "未提交审核", 1: "待平台审核", 2: "审核通过", 3: "审核驳回"][value] ?? "审核状态未知"
    }
}
