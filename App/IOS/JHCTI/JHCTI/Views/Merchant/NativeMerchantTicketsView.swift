import Foundation
import SwiftUI

private struct NativeMerchantTicketDraft {
    var price: String
    var sessionInventories: [String: String]
}

struct MerchantTicketsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let merchantID: String
    @State private var rows: [[String: Any]] = []
    @State private var drafts: [String: NativeMerchantTicketDraft] = [:]
    @State private var keyword = ""
    @State private var page = 1
    @State private var total = 0
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var revision = 0
    @State private var requestSequence = 0
    @State private var pendingTicket: [String: Any]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("维护票价与场次库存；已售和待支付数量由服务端保护，场次新增及其他票务规则请在管理端维护。")
                    .font(.caption).foregroundStyle(Brand.muted)
                HStack {
                    TextField("搜索门票名称", text: $keyword)
                        .textFieldStyle(.roundedBorder).submitLabel(.search)
                        .onSubmit { Task { await load(page: 1) } }
                    Button("搜索") { Task { await load(page: 1) } }
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                }
                StatusView(loading: loading, error: error) { revision += 1 }
                if !loading && error == nil && rows.isEmpty {
                    Text("当前商户暂无可维护门票。").foregroundStyle(Brand.muted)
                }
                ForEach(rows.indices, id: \.self) { index in ticketCard(rows[index]) }
                if !loading && error == nil && rows.count < total {
                    Button(loading ? "正在加载…" : "加载更多（\(rows.count)/\(total)）") {
                        Task { await load(page: page + 1) }
                    }
                    .disabled(loading).frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .background(Brand.background)
        .navigationTitle("门票与场次")
        .task(id: revision) { await load(page: 1) }
        .onChange(of: store.session?.accessToken) { _, _ in dismiss() }
        .confirmationDialog("保存门票与场次", isPresented: Binding(
            get: { pendingTicket != nil }, set: { if !$0 { pendingTicket = nil } }), titleVisibility: .visible) {
            Button("确认保存") {
                guard let pendingTicket else { return }
                Task { await save(pendingTicket) }
            }.disabled(saving)
            Button("取消", role: .cancel) { pendingTicket = nil }
        } message: {
            Text("确认保存“\(pendingTicket?["Name"] as? String ?? "该门票")”的票价和场次库存？服务端会重新校验票务版本、已售和待支付数量。")
        }
    }

    @ViewBuilder private func ticketCard(_ row: [String: Any]) -> some View {
        let id = Self.idString(row["Id"] ?? row["id"])
        let draft = drafts[id] ?? NativeMerchantTicketDraft(price: Self.idString(row["Price"] ?? row["price"]), sessionInventories: [:])
        let sessions = row["Sessions"] as? [[String: Any]] ?? row["sessions"] as? [[String: Any]] ?? []
        VStack(alignment: .leading, spacing: 8) {
            Text(row["Name"] as? String ?? row["name"] as? String ?? "未命名门票").font(.headline)
            Text("\(row["ResourceName"] as? String ?? row["resourceName"] as? String ?? "景点") · \(Self.boolValue(row["IsEnabled"] ?? row["isEnabled"], default: true) ? "销售中" : "已停用") · 当前 ¥\(Self.idString(row["Price"] ?? row["price"]))")
                .font(.caption).foregroundStyle(Brand.muted)
            TextField("票价（元）", text: Binding(get: { draft.price }, set: { setDraft(id, price: $0) }))
                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            if sessions.isEmpty {
                Text("暂无场次资料；请在管理端维护场次。").font(.caption).foregroundStyle(Brand.muted)
            }
            ForEach(sessions.indices, id: \.self) { index in
                let session = sessions[index]
                let sessionID = Self.idString(session["Id"] ?? session["id"])
                let inventory = draft.sessionInventories[sessionID] ?? Self.idString(session["Inventory"] ?? session["inventory"])
                VStack(alignment: .leading, spacing: 5) {
                    Text(session["Name"] as? String ?? session["name"] as? String ?? "未命名场次").font(.subheadline.weight(.semibold))
                    Text("已售 \(Self.intValue(session["SoldCount"] ?? session["soldCount"])) · 待支付 \(Self.intValue(session["ReservedCount"] ?? session["reservedCount"]))\(Self.boolValue(session["IsEnabled"] ?? session["isEnabled"], default: true) ? "" : " · 已停用")")
                        .font(.caption).foregroundStyle(Brand.muted)
                    TextField("场次库存（最多 10000000）", text: Binding(get: { inventory }, set: { setDraft(id, sessionID: sessionID, inventory: $0) }))
                        .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                }
                .padding(10).background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
            }
            Button(saving ? "保存中…" : "保存票价与库存") { prepareSave(row) }
                .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(saving || id.isEmpty)
        }
        .merchantCard()
    }

    private func setDraft(_ id: String, price: String? = nil, sessionID: String? = nil, inventory: String? = nil) {
        var draft = drafts[id] ?? NativeMerchantTicketDraft(price: "", sessionInventories: [:])
        if let price { draft.price = String(price.filter { $0.isNumber || $0 == "." }.prefix(12)) }
        if let sessionID, let inventory {
            draft.sessionInventories[sessionID] = String(inventory.filter(\.isNumber).prefix(8))
        }
        drafts[id] = draft
        error = nil
    }

    private func prepareSave(_ row: [String: Any]) {
        let id = Self.idString(row["Id"] ?? row["id"])
        guard !id.isEmpty else { error = "门票编号缺失，请刷新后重试。"; return }
        let draft = drafts[id] ?? NativeMerchantTicketDraft(price: "", sessionInventories: [:])
        let rawPrice = draft.price.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawPrice.range(of: "^(0|[1-9][0-9]*)(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let price = Decimal(string: rawPrice), let maxPrice = Decimal(string: "99999999.99"),
              price > 0, price <= maxPrice else {
            error = "请输入大于 0、最多两位小数的有效票价。"; return
        }
        let sessions = row["Sessions"] as? [[String: Any]] ?? row["sessions"] as? [[String: Any]] ?? []
        for session in sessions {
            let sessionID = Self.idString(session["Id"] ?? session["id"])
            let raw = (draft.sessionInventories[sessionID] ?? Self.idString(session["Inventory"] ?? session["inventory"]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sold = Self.intValue(session["SoldCount"] ?? session["soldCount"])
            let reserved = Self.intValue(session["ReservedCount"] ?? session["reservedCount"])
            guard (0...10_000_000).contains(sold), (0...10_000_000).contains(reserved) else {
                error = "场次已售或待支付数量异常，请刷新后重试。"
                return
            }
            let committed = sold + reserved
            guard raw.range(of: "^(0|[1-9][0-9]*)$", options: .regularExpression) != nil,
                  let inventory = Int(raw), (0...10_000_000).contains(inventory), committed <= inventory else {
                error = "场次“\(session["Name"] as? String ?? "未命名")”库存须为 0 至 10000000，且不低于已售和待支付数量 \(committed)。"
                return
            }
        }
        pendingTicket = row
    }

    private func save(_ row: [String: Any]) async {
        guard !saving else { return }
        let id = Self.idString(row["Id"] ?? row["id"])
        guard let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { error = "登录已失效，请重新登录。"; return }
        let draft = drafts[id] ?? NativeMerchantTicketDraft(price: "", sessionInventories: [:])
        guard let price = Decimal(string: draft.price.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "票价格式无效，请重新输入。"; return
        }
        let sessions = row["Sessions"] as? [[String: Any]] ?? row["sessions"] as? [[String: Any]] ?? []
        let sessionPayload: [[String: Any]] = sessions.map { session in
            let sessionID = Self.idString(session["Id"] ?? session["id"])
            return [
                "Id": sessionID,
                "Version": Self.intValue(session["Version"] ?? session["version"]),
                "Name": session["Name"] as? String ?? session["name"] as? String ?? "",
                "StartTime": session["StartTime"] ?? session["startTime"] ?? NSNull(),
                "EndTime": session["EndTime"] ?? session["endTime"] ?? NSNull(),
                "Inventory": Int(draft.sessionInventories[sessionID] ?? Self.idString(session["Inventory"] ?? session["inventory"])) ?? 0,
                "ReservedCount": Self.intValue(session["ReservedCount"] ?? session["reservedCount"]),
                "IsEnabled": Self.boolValue(session["IsEnabled"] ?? session["isEnabled"], default: true),
                "SortOrder": Self.intValue(session["SortOrder"] ?? session["sortOrder"])
            ]
        }
        let body: [String: Any] = [
            "Id": id,
            "Version": Self.intValue(row["Version"] ?? row["version"]),
            "ResourceId": Self.idString(row["ResourceId"] ?? row["resourceId"]),
            "MerchantId": merchantID,
            "Name": row["Name"] ?? row["name"] ?? "",
            "Description": row["Description"] ?? row["description"] ?? NSNull(),
            "Price": NSDecimalNumber(decimal: price),
            "OriginalPrice": row["OriginalPrice"] ?? row["originalPrice"] ?? NSNull(),
            "SaleStartTime": row["SaleStartTime"] ?? row["saleStartTime"] ?? NSNull(),
            "SaleEndTime": row["SaleEndTime"] ?? row["saleEndTime"] ?? NSNull(),
            "MinPerOrder": Self.intValue(row["MinPerOrder"] ?? row["minPerOrder"], fallback: 1),
            "MaxPerOrder": Self.intValue(row["MaxPerOrder"] ?? row["maxPerOrder"], fallback: 5),
            "MaxPerUserPerDay": Self.intValue(row["MaxPerUserPerDay"] ?? row["maxPerUserPerDay"], fallback: 5),
            "RefundPolicy": row["RefundPolicy"] ?? row["refundPolicy"] ?? "ManualReview",
            "RefundBeforeHours": Self.intValue(row["RefundBeforeHours"] ?? row["refundBeforeHours"]),
            "RefundDescription": row["RefundDescription"] ?? row["refundDescription"] ?? NSNull(),
            "RealNameFields": row["RealNameFields"] ?? row["realNameFields"] ?? [],
            "IsEnabled": Self.boolValue(row["IsEnabled"] ?? row["isEnabled"], default: true),
            "SortOrder": Self.intValue(row["SortOrder"] ?? row["sortOrder"]),
            "Sessions": sessionPayload
        ]
        saving = true; error = nil
        do {
            _ = try await MobileAPI(store: store).post("/api/JHCTITicket/SaveMerchantManagement", body: body, authenticated: true,
                expectedPrincipal: expectedPrincipal)
            guard store.session?.accessToken == token else { return }
            await load(page: 1)
            if error != nil { error = "票务修改已提交，但列表刷新失败；请重新加载确认当前状态。" }
        } catch is CancellationError {
            if store.session?.accessToken == token {
                error = "票务保存结果未确认；请重新读取并核对版本后再操作。"
            }
        } catch {
            if store.session?.accessToken == token {
                self.error = "\(error.localizedDescription)；请重新读取并核对版本后再操作。"
            }
        }
        saving = false; pendingTicket = nil
    }

    private func load(page targetPage: Int) async {
        guard !merchantID.isEmpty, merchantID.allSatisfy(\.isNumber),
              let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else {
            error = "商户范围或登录状态无效，请返回工作台重新进入。"; loading = false; return
        }
        requestSequence += 1
        let sequence = requestSequence
        let append = targetPage > 1
        loading = true; error = nil
        if !append { rows = []; drafts = [:]; total = 0 }
        do {
            let escaped = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))) ?? ""
            guard let response = try await MobileAPI(store: store).get(
                "/api/JHCTITicket/GetMerchantManagementPage?merchantId=\(merchantID)&page=\(targetPage)&pageSize=20&keyword=\(escaped)",
                authenticated: true, expectedPrincipal: expectedPrincipal) as? [String: Any],
                  let loaded = response["data"] as? [[String: Any]] ?? response["Data"] as? [[String: Any]] else {
                throw MobileAPIError.unavailable("门票分页响应格式异常，请重试。")
            }
            let count = Self.intValue(response["dataCount"] ?? response["DataCount"], fallback: -1)
            let validTickets = loaded.allSatisfy { row in
                guard !Self.idString(row["Id"] ?? row["id"]).isEmpty,
                      let sessions = row["Sessions"] as? [[String: Any]] ?? row["sessions"] as? [[String: Any]] else { return false }
                let sessionIDs = sessions.map { Self.idString($0["Id"] ?? $0["id"]) }
                return sessionIDs.allSatisfy { !$0.isEmpty } && Set(sessionIDs).count == sessionIDs.count
            }
            guard loaded.count <= 20, count >= loaded.count, count >= 0, validTickets else {
                throw MobileAPIError.unavailable("门票分页数据不完整，请刷新后重试。")
            }
            guard requestSequence == sequence, store.session?.accessToken == token else { return }
            var next = append ? rows : []
            for row in loaded {
                let id = Self.idString(row["Id"] ?? row["id"])
                if let index = next.firstIndex(where: { Self.idString($0["Id"] ?? $0["id"]) == id }) { next[index] = row }
                else { next.append(row) }
                let sessions = row["Sessions"] as? [[String: Any]] ?? row["sessions"] as? [[String: Any]] ?? []
                drafts[id] = NativeMerchantTicketDraft(
                    price: Self.idString(row["Price"] ?? row["price"]),
                    sessionInventories: Dictionary(uniqueKeysWithValues: sessions.map {
                        (Self.idString($0["Id"] ?? $0["id"]), Self.idString($0["Inventory"] ?? $0["inventory"]))
                    })
                )
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

    private static func idString(_ value: Any?, fallback: String = "") -> String {
        guard let value, !(value is NSNull) else { return fallback }
        return value as? String ?? String(describing: value)
    }
    private static func intValue(_ value: Any?, fallback: Int = 0) -> Int {
        guard let value, !(value is NSNull) else { return fallback }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? fallback }
        return fallback
    }
    private static func boolValue(_ value: Any?, default fallback: Bool = false) -> Bool {
        guard let value, !(value is NSNull) else { return fallback }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return (string as NSString).boolValue }
        return fallback
    }
}
