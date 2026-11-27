import Foundation
import CoreFoundation
import SwiftUI

private struct NativeMerchantStoreStock: Equatable {
    let id: String
    let skuID: String
    let productID: String
    let name: String
    let code: String
    let price: Decimal
    let version: Int
    let stock: Int?

    var stockText: String { stock.map(String.init) ?? "" }

    static func readPage(_ value: Any?, merchantID: String, storeID: String, page: Int, size: Int) throws -> ([Self], Int) {
        let field = NativeMerchantProductEditor.field
        let integer = NativeMerchantProductEditor.integer
        let identifier = NativeMerchantProductEditor.identifier
        let invalid = MobileAPIError.unavailable("门店库存回执不完整，请重新读取。")
        guard let response = value as? [String: Any], let data = field(response, "Data") as? [[String: Any]],
              let total = integer(field(response, "DataCount"), Int(Int32.max)),
              integer(field(response, "Page"), Int(Int32.max)) == page,
              integer(field(response, "PageSize"), 100) == size,
              let pageCount = integer(field(response, "PageCount"), Int(Int32.max)),
              pageCount == (total + size - 1) / size, page <= max(1, pageCount),
              data.count == min(size, max(0, total - (page - 1) * size)) else { throw invalid }
        let rows = try data.map { row -> Self in
            guard field(row, "MerchantId") as? String == merchantID, field(row, "StoreId") as? String == storeID,
                  let id = field(row, "Id") as? String, id == "0" || identifier(id) != nil,
                  let skuID = identifier(field(row, "SkuId")), let productID = identifier(field(row, "ProductId")),
                  let name = field(row, "ProductName") as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let code = field(row, "SkuCode") as? String,
                  let price = field(row, "Price") as? NSNumber, CFGetTypeID(price) != CFBooleanGetTypeID(),
                  price.doubleValue.isFinite, price.doubleValue >= 0,
                  let version = integer(field(row, "Version"), 9_007_199_254_740_991),
                  let rawStock = field(row, "StoreStock") else { throw invalid }
            let stock: Int?
            if rawStock is NSNull { stock = nil }
            else if let number = rawStock as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                    let parsed = Int32(exactly: number.doubleValue) { stock = Int(parsed) }
            else { throw invalid }
            guard id != "0" || (version == 0 && stock == nil),
                  NativeMerchantProductEditor.flag(field(row, "IsInventoryInvalid")) == (stock.map { $0 < 0 } ?? false) else { throw invalid }
            return Self(id: id, skuID: skuID, productID: productID, name: name, code: code,
                price: price.decimalValue, version: version, stock: stock)
        }
        guard Set(rows.map(\.skuID)).count == rows.count else { throw invalid }
        return (rows, total)
    }

    func matches(_ previous: Self) -> Bool {
        skuID == previous.skuID && productID == previous.productID
            && (previous.id == "0" || (id == previous.id && version >= previous.version))
    }
}

private struct NativeMerchantStoreStockChange {
    let row: NativeMerchantStoreStock
    let quantity: Int
    let token: String
    let sequence: Int
}

struct MerchantStockView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let merchantID: String
    let stockStore: [String: Any]
    @State private var rows: [NativeMerchantStoreStock] = []
    @State private var drafts: [String: String] = [:]
    @State private var keyword = ""
    @State private var appliedKeyword = ""
    @State private var page = 1
    @State private var total = 0
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var feedback: String?
    @State private var confirmation: NativeMerchantStoreStockChange?
    @State private var pendingRead: NativeMerchantStoreStock?
    @State private var revision = 0
    @State private var requestSequence = 0

    private var storeID: String { NativeMerchantProductEditor.identifier(NativeMerchantProductEditor.field(stockStore, "Id")) ?? "" }
    private var storeName: String { stockStore["Name"] as? String ?? "授权门店" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(storeName) · 保存后由服务端记录库存变更历史。")
                    .font(.caption).foregroundStyle(Brand.muted)
                HStack {
                    TextField("搜索商品或 SKU 编码", text: $keyword)
                        .textFieldStyle(.roundedBorder).submitLabel(.search)
                        .onSubmit { Task { await load(page: 1, search: keyword) } }
                    Button("搜索") { Task { await load(page: 1, search: keyword) } }
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                }.disabled(saving || loading)
                StatusView(loading: loading, error: error) { revision += 1 }
                if !loading && error == nil && rows.isEmpty {
                    Text("当前门店暂无可管理的 SKU。").foregroundStyle(Brand.muted)
                }
                if let feedback { Text(feedback).font(.caption).foregroundStyle(Brand.muted) }
                if pendingRead != nil {
                    Button("重新读取该 SKU") { Task { await verify() } }
                        .buttonStyle(.bordered).disabled(loading || saving)
                }
                ForEach(rows, id: \.skuID) { row in stockCard(row) }
                if !loading && error == nil && rows.count < total {
                    Button("加载更多（\(rows.count)/\(total)）") { Task { await load(page: page + 1) } }
                        .disabled(loading || saving).frame(maxWidth: .infinity)
                }
            }.padding(16)
        }
        .background(Brand.background)
        .navigationTitle("门店库存")
        .task(id: revision) { await load(page: 1) }
        .onDisappear { requestSequence += 1 }
        .onChange(of: store.session?.accessToken) { _, _ in dismiss() }
        .confirmationDialog("修改门店库存", isPresented: Binding(
            get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible, presenting: confirmation) { change in
                Button("确认保存") { Task { await save(change) } }
                Button("取消", role: .cancel) {}
            } message: { change in
                Text("将“\(change.row.name)”的 \(change.row.code.isEmpty ? change.row.skuID : change.row.code) 在\(storeName)的库存设为 \(change.quantity)？")
            }
    }

    private func stockCard(_ row: NativeMerchantStoreStock) -> some View {
        let skuID = row.skuID
        return VStack(alignment: .leading, spacing: 8) {
            Text(row.name).font(.headline)
            Text("SKU \(row.code.isEmpty ? skuID : row.code) · ¥\(NSDecimalNumber(decimal: row.price).stringValue)")
                .font(.caption).foregroundStyle(Brand.muted)
            Text(row.stock == nil ? "尚未单独设置门店库存" : "当前库存 \(row.stockText)")
                .font(.caption).foregroundStyle(Brand.muted)
            HStack {
                TextField("库存数量", text: Binding(get: { drafts[skuID] ?? "" }, set: { drafts[skuID] = $0 }))
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                Button(saving ? "处理中…" : "保存") { prepare(row) }
                    .buttonStyle(.borderedProminent).tint(Brand.primary)
            }.disabled(saving || loading || error != nil || pendingRead != nil)
        }.merchantCard()
    }

    private func current(_ token: String, _ sequence: Int) -> Bool {
        requestSequence == sequence && token == store.session?.accessToken && !Task.isCancelled
    }

    private func stockPage(page: Int, size: Int, filter: URLQueryItem, principal: String) async throws -> ([NativeMerchantStoreStock], Int) {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "merchantId", value: merchantID), URLQueryItem(name: "storeId", value: storeID),
            URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "pageSize", value: String(size)), filter]
        let encoded = (query.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        let result = try await MobileAPI(store: store).get("/api/JHCTIMerchant/GetStoreSkuStock?\(encoded)",
            authenticated: true, expectedPrincipal: principal)
        return try NativeMerchantStoreStock.readPage(result, merchantID: merchantID, storeID: storeID, page: page, size: size)
    }

    private func load(page targetPage: Int, search: String? = nil) async {
        guard !saving, targetPage == 1 || !loading else { return }
        guard NativeMerchantProductEditor.identifier(merchantID) != nil, !storeID.isEmpty,
              let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else {
            error = "商户、门店或登录范围无效，请返回工作台重新进入。"; loading = false; return
        }
        requestSequence += 1
        let sequence = requestSequence
        loading = true; error = nil
        if targetPage == 1 {
            if let search { appliedKeyword = search.trimmingCharacters(in: .whitespacesAndNewlines) }
            rows = []; drafts = [:]; page = 1; total = 0
        }
        defer { if requestSequence == sequence { loading = false } }
        do {
            let (loaded, count) = try await stockPage(page: targetPage, size: 20,
                filter: URLQueryItem(name: "keyword", value: appliedKeyword), principal: expectedPrincipal)
            guard current(token, sequence) else { return }
            if targetPage > 1, count != total || !Set(rows.map(\.skuID)).isDisjoint(with: loaded.map(\.skuID)) {
                throw MobileAPIError.unavailable("库存列表已变化，请从第一页重新读取。")
            }
            rows.append(contentsOf: loaded)
            for row in loaded { drafts[row.skuID] = row.stockText }
            total = count; page = targetPage
        } catch { if current(token, sequence) { self.error = error.localizedDescription } }
    }

    private func prepare(_ row: NativeMerchantStoreStock) {
        guard !saving, !loading, pendingRead == nil, error == nil, let token = store.session?.accessToken else { return }
        let raw = drafts[row.skuID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let stock = Int(raw), (0...2_000_000_000).contains(stock), String(stock) == raw else {
            feedback = "请输入 0 到 2000000000 的整数库存。"; return
        }
        guard stock != row.stock else { feedback = "库存数量没有变化。"; return }
        confirmation = NativeMerchantStoreStockChange(row: row, quantity: stock, token: token, sequence: requestSequence)
    }

    private func save(_ change: NativeMerchantStoreStockChange) async {
        let row = change.row
        let token = change.token
        guard !saving, !loading, pendingRead == nil, current(token, change.sequence), rows.contains(row),
              let principal = nativeTourismPrincipal(token) else { return }
        saving = true; confirmation = nil; pendingRead = row
        feedback = "正在保存并核对门店库存…"
        defer { saving = false }
        let body: [String: Any] = [
            "Id": row.id, "Version": row.version, "MerchantId": merchantID, "StoreId": storeID,
            "SkuId": row.skuID, "Stock": change.quantity
        ]
        var acknowledged = false
        var rejection: String?
        do {
            let response = try await MobileAPI(store: store).post("/api/JHCTIMerchant/SetStoreSkuStock", body: body,
                authenticated: true, expectedPrincipal: principal, canRefresh: false)
            acknowledged = response as? String == row.skuID
        } catch let failure as MobileAPIError {
            if [400, 403, 404, 409].contains(failure.httpStatusCode ?? 0) { rejection = failure.localizedDescription }
        } catch {}
        guard current(token, change.sequence) else { return }
        await readBack(row, token: token, principal: principal, sequence: change.sequence,
            expected: acknowledged ? change.quantity : nil, rejection: rejection)
    }

    private func verify() async {
        guard let row = pendingRead, !saving, !loading,
              let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else { return }
        saving = true
        defer { saving = false }
        await readBack(row, token: token, principal: principal, sequence: requestSequence)
    }
    private func readBack(_ row: NativeMerchantStoreStock, token: String, principal: String, sequence: Int,
                          expected: Int? = nil, rejection: String? = nil) async {
        do {
            let (loaded, count) = try await stockPage(page: 1, size: 1, filter: URLQueryItem(name: "skuId", value: row.skuID), principal: principal)
            guard current(token, sequence) else { return }
            guard count <= 1 else { throw MobileAPIError.unavailable("原 SKU 的库存回执包含多条记录。") }
            guard let latest = loaded.first else {
                rows.removeAll { $0.skuID == row.skuID }; drafts[row.skuID] = nil
                pendingRead = nil; feedback = nil; error = "该 SKU 已不可维护，请重新读取列表。"
                return
            }
            guard latest.matches(row) else {
                throw MobileAPIError.unavailable("无法核对原门店的 SKU。")
            }
            if let index = rows.firstIndex(where: { $0.skuID == row.skuID }) {
                rows[index] = latest; drafts[row.skuID] = latest.stockText
            }
            pendingRead = nil
            let saved = expected != nil && expected == latest.stock && latest.id != "0"
                && (row.id == "0" || latest.version > row.version)
            feedback = rejection ?? (saved ? "库存已保存。" : "已读取最新库存，请核对后再修改。")
        } catch {
            if current(token, sequence) { feedback = "库存保存结果待核对，请重新读取该 SKU。" }
        }
    }
}

private struct NativeMerchantSku {
    let id: String
    let code: String
    let price: Decimal
    let originalPrice: Decimal?
    let stock: Int
    let used: Int

    var draft: NativeMerchantSkuDraft {
        NativeMerchantSkuDraft(price: NSDecimalNumber(decimal: price).stringValue,
            originalPrice: originalPrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? "", stock: String(stock))
    }
}

private struct NativeMerchantSkuDraft {
    var price: String
    var originalPrice: String
    var stock: String
}

private struct NativeMerchantProductDraft {
    var name: String
    var description: String
    var skus: [String: NativeMerchantSkuDraft]
}

private enum NativeMerchantProductAction: String, CaseIterable {
    case save, review, publish, offline

    var path: String {
        switch self {
        case .save: return "/api/JHCTIProduct/SaveMerchantDetails"
        case .review: return "/api/JHCTIProduct/SubmitReview"
        case .publish, .offline: return "/api/JHCTIProduct/UpdateStatus"
        }
    }
}

private struct NativeMerchantProductChange {
    let id: String
    let version: Int
    let sequence: Int
    let token: String
    let action: NativeMerchantProductAction
    let title: String
    let name: String
    let body: [String: Any]
}

private struct NativeMerchantProductEditor {
    let id: String
    let merchantID: String
    let version: Int
    let name: String
    let description: String
    let status: String
    let review: Int
    let reviewRemark: String
    let pending: Bool
    let inheritsDescription: Bool
    let skus: [NativeMerchantSku]

    var reviewing: Bool { [1, 4, 5].contains(review) }
    var actions: [NativeMerchantProductAction] {
        var result: [NativeMerchantProductAction] = []
        if !reviewing { result.append(.save) }
        if [0, 3].contains(review), status != "Published" || pending { result.append(.review) }
        if review == 2, status != "Published" || pending { result.append(.publish) }
        if status == "Published" { result.append(.offline) }
        return result
    }
    var draft: NativeMerchantProductDraft {
        NativeMerchantProductDraft(name: name, description: description, skus: Dictionary(uniqueKeysWithValues: skus.map { ($0.id, $0.draft) }))
    }

    func title(for action: NativeMerchantProductAction) -> String {
        switch action {
        case .save: return "保存商品变更"
        case .review: return pending ? "提交修改审核" : "提交审核"
        case .publish: return status == "Published" && pending ? "发布已审核修改" : "上架商品"
        case .offline: return "下架商品"
        }
    }

    func payload(for draft: NativeMerchantProductDraft) throws -> [String: Any]? {
        let updatedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updatedName.isEmpty, updatedName.utf16.count <= 160, draft.description.utf16.count <= 20_000 else {
            throw MobileAPIError.unavailable("请检查商品名称和介绍。")
        }
        var changes: [[String: Any]] = []
        for sku in skus {
            guard let item = draft.skus[sku.id] else { throw MobileAPIError.unavailable("商品规格已变化，请重新读取。") }
            let originalDraft = sku.draft
            if item.price == originalDraft.price, item.originalPrice == originalDraft.originalPrice, item.stock == originalDraft.stock { continue }
            let rawOriginal = item.originalPrice.trimmingCharacters(in: .whitespacesAndNewlines)
            let original = Self.inputPrice(rawOriginal)
            guard let price = Self.inputPrice(item.price), rawOriginal.isEmpty || (original.map { $0 >= price } ?? false) else {
                throw MobileAPIError.unavailable("“\(sku.code)”的销售价或划线价无效。")
            }
            let stockText = item.stock.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let stock = Int(stockText), String(stock) == stockText, stock >= sku.used, stock <= Int(Int32.max) else {
                throw MobileAPIError.unavailable("“\(sku.code)”的库存须不低于已售及预占数量 \(sku.used)。")
            }
            if price != sku.price || original != sku.originalPrice || stock != sku.stock {
                changes.append(["Id": sku.id, "Price": NSDecimalNumber(decimal: price),
                    "OriginalPrice": original.map { NSDecimalNumber(decimal: $0) as Any } ?? NSNull(), "Stock": stock])
            }
        }
        var body: [String: Any] = ["Id": id, "MerchantId": merchantID, "Version": version, "Skus": changes]
        if updatedName != name { body["Name"] = updatedName }
        if !inheritsDescription, desc != description.trimmingCharacters(in: .whitespacesAndNewlines) { body["Description"] = desc }
        return changes.isEmpty && body["Name"] == nil && body["Description"] == nil ? nil : body
    }

    static func field(_ row: [String: Any], _ name: String) -> Any? {
        let alias = name.prefix(1).lowercased() + String(name.dropFirst())
        if let a = row[name], let b = row[alias] {
            let left = try? JSONSerialization.data(withJSONObject: a, options: [.sortedKeys, .fragmentsAllowed])
            let right = try? JSONSerialization.data(withJSONObject: b, options: [.sortedKeys, .fragmentsAllowed])
            if left == nil || left != right { return nil }
        }
        return row[name] ?? row[alias]
    }
    static func identifier(_ value: Any?) -> String? {
        guard let id = value as? String, let number = Int64(id), number > 0, String(number) == id else { return nil }
        return id
    }
    static func integer(_ value: Any?, limit: Int = 9_007_199_254_740_991) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let int = Int(exactly: number.doubleValue), (0...limit).contains(int) else { return nil }
        return int
    }
    static func flag(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    private static func validPrice(_ value: Decimal) -> Bool {
        var original = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &original, 2, .plain)
        return value >= 0 && value <= 999_999_999 && rounded == value
    }
    private static func price(_ value: Any?) -> Decimal? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let decimal = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")), validPrice(decimal) else { return nil }
        return decimal
    }
    private static func inputPrice(_ value: String) -> Decimal? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: "^(0|[1-9][0-9]*)(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), validPrice(decimal) else { return nil }
        return decimal
    }

    static func read(_ row: [String: Any], merchantID: String, id: String) throws -> Self {
        let description = field(row, "Description")
        let family = field(row, "FamilyId")
        let remark = field(row, "ReviewRemark") as? String ?? ""
        guard identifier(field(row, "Id")) == id, identifier(field(row, "MerchantId")) == merchantID,
              let version = integer(field(row, "Version")), let name = field(row, "Name") as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              description is NSNull || description is String, identifier(family) != nil || family as? String == "0",
              let status = field(row, "Status") as? String, ["Draft", "Scheduled", "Published", "Offline"].contains(status),
              let review = integer(field(row, "ReviewStatus"), limit: 5),
              let inherits = flag(field(row, "UseFamilyDescription")), let revision = flag(field(row, "HasPendingRevision")),
              let legacyEdit = flag(field(row, "HasPendingEdit")),
              let values = field(row, "Skus") as? [[String: Any]], (1...100).contains(values.count) else {
            throw MobileAPIError.unavailable("商品编号、商户、版本或审核回执异常。")
        }
        var ids = Set<String>()
        let skus = try values.map { item -> NativeMerchantSku in
            let original = field(item, "OriginalPrice")
            let originalPrice = price(original)
            guard let id = identifier(field(item, "Id")), ids.insert(id).inserted,
                  let code = field(item, "SkuCode") as? String, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let skuPrice = price(field(item, "Price")), original is NSNull || (originalPrice.map { $0 >= skuPrice } ?? false),
                  let stock = integer(field(item, "Stock"), limit: Int(Int32.max)),
                  let sold = integer(field(item, "SoldCount"), limit: Int(Int32.max)),
                  let reserved = integer(field(item, "ReservedStock"), limit: Int(Int32.max)) else {
                throw MobileAPIError.unavailable("商品规格、金额或库存回执异常。")
            }
            return NativeMerchantSku(id: id, code: code, price: skuPrice, originalPrice: originalPrice, stock: stock, used: sold + reserved)
        }
        return Self(id: id, merchantID: merchantID, version: version, name: name, description: description as? String ?? "",
            status: status, review: review, reviewRemark: remark, pending: revision || legacyEdit,
            inheritsDescription: family as? String != "0" && inherits, skus: skus)
    }
}

struct MerchantProductsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let merchantID: String
    @State private var rows: [[String: Any]] = []
    @State private var selectedID: String?
    @State private var product: NativeMerchantProductEditor?
    @State private var draft: NativeMerchantProductDraft?
    @State private var editorToken: String?
    @State private var keyword = ""
    @State private var appliedKeyword = ""
    @State private var page = 1
    @State private var total = 0
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @State private var detailMessage: String?
    @State private var requestSequence = 0
    @State private var pending: NativeMerchantProductChange?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let selectedID { editor(selectedID) } else { productList }
            }
            .padding(16)
        }
        .background(Brand.background)
        .navigationTitle("商品资料与价格")
        .task { await load(page: 1) }
        .onChange(of: store.session?.accessToken) { _, _ in requestSequence += 1; dismiss() }
        .onDisappear { requestSequence += 1; pending = nil }
        .confirmationDialog(pending?.title ?? "确认商品操作", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let action = pending {
                Button(action.title, role: action.action == .offline ? .destructive : nil) { Task { await run(action) } }
            }
            Button("取消", role: .cancel) { pending = nil }
        } message: {
            if let action = pending { Text("确认\(action.title)“\(action.name)”？") }
        }
    }

    private var productList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("搜索商品名称", text: $keyword).textFieldStyle(.roundedBorder).submitLabel(.search)
                    .onSubmit { Task { await load(page: 1) } }
                Button("搜索") { Task { await load(page: 1) } }.buttonStyle(.borderedProminent).tint(Brand.primary)
            }
            StatusView(loading: loading, error: error) { Task { await load(page: rows.isEmpty ? 1 : page + 1) } }
            if !loading && error == nil && rows.isEmpty { Text("当前商户暂无商品资料。").foregroundStyle(Brand.muted) }
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                if let id = NativeMerchantProductEditor.identifier(NativeMerchantProductEditor.field(row, "Id")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NativeMerchantProductEditor.field(row, "Name") as? String ?? "未命名商品").font(.headline)
                        Text(Self.statusName(NativeMerchantProductEditor.field(row, "Status") as? String ?? "")
                            + " · " + Self.reviewName(NativeMerchantProductEditor.integer(NativeMerchantProductEditor.field(row, "ReviewStatus")) ?? -1))
                            .font(.caption).foregroundStyle(Brand.muted)
                        Text([NativeMerchantProductEditor.field(row, "CategoryName") as? String,
                            NativeMerchantProductEditor.field(row, "FamilyName") as? String,
                            NativeMerchantProductEditor.field(row, "FreightTemplateName") as? String].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(Brand.muted)
                        Button("维护商品") { Task { await select(id) } }.disabled(loading || busy)
                    }
                    .merchantCard()
                }
            }
            if rows.count < total && !rows.isEmpty {
                Button("加载更多（\(rows.count)/\(total)）") { Task { await load(page: page + 1) } }
                    .disabled(loading || busy).frame(maxWidth: .infinity)
            }
        }
    }

    private func editor(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("‹ 返回商品列表") {
                requestSequence += 1; selectedID = nil; pending = nil; product = nil; draft = nil; editorToken = nil; detailMessage = nil
            }
            .disabled(busy)
            if let detailMessage { Text(detailMessage).font(.caption).foregroundStyle(Brand.muted) }
            if let product, let draft {
                Text(product.name).font(.headline)
                Text(Self.statusName(product.status) + " · " + Self.reviewName(product.review)).font(.caption).foregroundStyle(Brand.muted)
                if !product.reviewRemark.isEmpty { Text(product.reviewRemark).font(.caption).foregroundStyle(Brand.muted) }
                if product.pending && product.status == "Published" {
                    Text("修改版本审核并发布后生效，期间继续展示当前上架版本。").font(.caption).foregroundStyle(Brand.muted)
                }
                TextField("商品名称", text: Binding(get: { self.draft?.name ?? "" }, set: { self.draft?.name = $0 }))
                    .textFieldStyle(.roundedBorder).disabled(busy || product.reviewing)
                TextField(product.inheritsDescription ? "商品介绍 · 继承系列资料" : "商品介绍",
                    text: Binding(get: { self.draft?.description ?? "" }, set: { self.draft?.description = $0 }), axis: .vertical)
                    .textFieldStyle(.roundedBorder).disabled(busy || product.reviewing || product.inheritsDescription)
                ForEach(product.skus, id: \.id) { sku in
                    if draft.skus[sku.id] != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(sku.code).font(.subheadline.weight(.semibold))
                            HStack {
                                TextField("售价（元）", text: skuBinding(sku.id, \.price)).keyboardType(.decimalPad)
                                TextField("划线价（可空）", text: skuBinding(sku.id, \.originalPrice)).keyboardType(.decimalPad)
                            }
                            Text("库存总量 · 已售和预占 \(sku.used) 件").font(.caption)
                            TextField("库存总量", text: skuBinding(sku.id, \.stock)).keyboardType(.numberPad)
                        }
                        .textFieldStyle(.roundedBorder).disabled(busy || product.reviewing)
                    }
                }
                ForEach(product.actions, id: \.self) { action in
                    Button(product.title(for: action), role: action == .offline ? .destructive : nil) { prepare(action) }
                        .buttonStyle(.bordered).disabled(busy)
                }
            } else if busy {
                ProgressView("正在读取商品…")
            } else {
                Button("重新读取并核对") { Task { await select(id) } }
            }
        }
        .merchantCard()
    }

    private func skuBinding(_ id: String, _ field: WritableKeyPath<NativeMerchantSkuDraft, String>) -> Binding<String> {
        Binding(get: { draft?.skus[id]?[keyPath: field] ?? "" }, set: { value in
            guard var item = draft?.skus[id] else { return }
            item[keyPath: field] = value
            draft?.skus[id] = item
        })
    }

    private func current(_ token: String, _ sequence: Int) -> Bool {
        requestSequence == sequence && store.session?.accessToken == token
    }

    private func load(page targetPage: Int) async {
        guard !busy, selectedID == nil, targetPage == 1 || !loading else { return }
        guard NativeMerchantProductEditor.identifier(merchantID) != nil, let token = store.session?.accessToken,
              let principal = nativeTourismPrincipal(token) else {
            error = "商户或登录状态无效，请返回工作台重新进入。"; loading = false; return
        }
        requestSequence += 1
        let sequence = requestSequence
        loading = true; error = nil
        if targetPage == 1 { rows = []; total = 0; page = 1; appliedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines) }
        defer { if current(token, sequence) { loading = false } }
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "page", value: String(targetPage)), URLQueryItem(name: "pageSize", value: "20"),
            URLQueryItem(name: "merchantId", value: merchantID), URLQueryItem(name: "keyword", value: appliedKeyword)]
        let encoded = (query.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        do {
            let result = try await MobileAPI(store: store).get("/api/JHCTIProduct/GetPage?\(encoded)", authenticated: true, expectedPrincipal: principal)
            guard current(token, sequence), !Task.isCancelled else { return }
            guard let response = result as? [String: Any],
                  let loaded = NativeMerchantProductEditor.field(response, "Data") as? [[String: Any]],
                  let count = NativeMerchantProductEditor.integer(NativeMerchantProductEditor.field(response, "DataCount")),
                  count >= loaded.count, loaded.count <= 20, loaded.allSatisfy({
                      NativeMerchantProductEditor.identifier(NativeMerchantProductEditor.field($0, "Id")) != nil
                      && NativeMerchantProductEditor.field($0, "MerchantId") as? String == merchantID
                  }) else { throw MobileAPIError.unavailable("商品分页数据不完整，请刷新后重试。") }
            var merged = rows
            for row in loaded {
                let id = NativeMerchantProductEditor.field(row, "Id") as? String
                if let index = merged.firstIndex(where: { NativeMerchantProductEditor.field($0, "Id") as? String == id }) { merged[index] = row }
                else { merged.append(row) }
            }
            rows = merged; total = count; page = targetPage
        } catch is CancellationError {
            return
        } catch { if current(token, sequence) { self.error = error.localizedDescription } }
    }

    private func readProduct(_ id: String, token: String, principal: String, sequence: Int) async throws {
        let result = try await MobileAPI(store: store).get("/api/JHCTIProduct/GetById?id=\(id)", authenticated: true, expectedPrincipal: principal)
        guard current(token, sequence), selectedID == id, !Task.isCancelled else { return }
        guard let row = result as? [String: Any] else { throw MobileAPIError.unavailable("商品回执异常。") }
        let next = try NativeMerchantProductEditor.read(row, merchantID: merchantID, id: id)
        if let index = rows.firstIndex(where: { NativeMerchantProductEditor.field($0, "Id") as? String == id }) {
            rows[index] = row
        }
        product = next; draft = next.draft; editorToken = token
    }

    private func select(_ id: String) async {
        guard !loading, !busy, NativeMerchantProductEditor.identifier(id) != nil, let token = store.session?.accessToken,
              let principal = nativeTourismPrincipal(token) else { return }
        requestSequence += 1
        let sequence = requestSequence
        selectedID = id; product = nil; draft = nil; editorToken = nil; detailMessage = nil; busy = true
        defer { busy = false }
        do { try await readProduct(id, token: token, principal: principal, sequence: sequence) }
        catch { if current(token, sequence) { detailMessage = error.localizedDescription } }
    }

    private func prepare(_ action: NativeMerchantProductAction) {
        guard !busy, let product, let draft, let token = editorToken, token == store.session?.accessToken,
              product.actions.contains(action) else { return }
        do {
            var body: [String: Any] = ["Id": product.id, "Version": product.version]
            if action == .save {
                guard let payload = try product.payload(for: draft) else { detailMessage = "商品资料、价格和库存没有变化。"; return }
                body = payload
            } else if action != .review { body["Status"] = action == .publish ? "Published" : "Offline" }
            pending = NativeMerchantProductChange(id: product.id, version: product.version, sequence: requestSequence, token: token,
                action: action, title: product.title(for: action), name: product.name, body: body)
        } catch { detailMessage = error.localizedDescription }
    }

    private func run(_ change: NativeMerchantProductChange) async {
        let token = change.token
        guard !busy, current(token, change.sequence), editorToken == token, selectedID == change.id,
              product?.version == change.version, let principal = nativeTourismPrincipal(token) else { return }
        busy = true; pending = nil; product = nil; draft = nil; editorToken = nil; detailMessage = nil
        defer { busy = false }
        var acknowledged = false
        var rejection: String?
        do {
            let receipt = try await MobileAPI(store: store).post(change.action.path, body: change.body,
                authenticated: true, expectedPrincipal: principal, canRefresh: false)
            acknowledged = receipt as? String == change.id
        } catch is CancellationError {
            if current(token, change.sequence) { detailMessage = "商品操作结果待核对，请重新读取该商品。" }
            return
        } catch let failure as MobileAPIError {
            if [400, 403, 404, 409].contains(failure.httpStatusCode ?? 0) { rejection = failure.localizedDescription }
        } catch { }
        guard current(token, change.sequence), !Task.isCancelled else { return }
        do {
            try await readProduct(change.id, token: token, principal: principal, sequence: change.sequence)
            if current(token, change.sequence), let product {
                detailMessage = rejection ?? (acknowledged && product.version > change.version ? "操作已提交。" : "已读取最新商品，请核对价格、库存和审核状态。")
            }
        } catch { if current(token, change.sequence) { detailMessage = rejection ?? "商品操作结果待核对，请重新读取该商品。" } }
    }

    private static func statusName(_ value: String) -> String {
        ["Draft": "草稿", "Scheduled": "已安排上架", "Published": "已上架", "Offline": "已下架"][value] ?? "状态未知"
    }
    private static func reviewName(_ value: Int) -> String {
        [0: "未提交审核", 1: "待审核", 2: "审核通过", 3: "审核驳回", 4: "待街区初审", 5: "待运营终审"][value] ?? "审核状态未知"
    }
}
