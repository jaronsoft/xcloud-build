import Foundation
import CoreFoundation
import SwiftUI

private struct NativeMerchantTicketDraft {
    var price: String
    var sessionInventories: [String: String]
}

private struct NativeMerchantTicketChange {
    let id: String
    let name: String
    let body: [String: Any]
    let revision: Int
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
    @State private var pendingTicket: NativeMerchantTicketChange?
    @State private var blockedTickets: Set<String> = []

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
                .disabled(saving)
                StatusView(loading: loading, error: error) { revision += 1 }
                if !loading && error == nil && rows.isEmpty {
                    Text("当前商户暂无可维护门票。").foregroundStyle(Brand.muted)
                }
                ForEach(rows.indices, id: \.self) { index in ticketCard(rows[index]) }
                if !loading && error == nil && rows.count < total {
                    Button(loading ? "正在加载…" : "加载更多（\(rows.count)/\(total)）") {
                        Task { await load(page: page + 1) }
                    }
                    .disabled(loading || saving).frame(maxWidth: .infinity)
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
            Text("确认保存“\(pendingTicket?.name ?? "该门票")”的票价和场次库存？服务端会重新校验票务版本、已售和待支付数量。")
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
                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).disabled(saving || blockedTickets.contains(id))
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
                        .keyboardType(.numberPad).textFieldStyle(.roundedBorder).disabled(saving || blockedTickets.contains(id))
                }
                .padding(10).background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
            }
            Button(saving ? "保存中…" : "保存票价与库存") { prepareSave(row) }
                .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(saving || loading || id.isEmpty || blockedTickets.contains(id))
            if blockedTickets.contains(id) {
                Button("重新读取该票种") { Task { await retryReadBack(id) } }.disabled(saving || loading)
            }
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
        guard !saving, !loading, !blockedTickets.contains(id) else { return }
        let draft = drafts[id] ?? NativeMerchantTicketDraft(price: "", sessionInventories: [:])
        let rawPrice = draft.price.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawPrice.range(of: "^(0|[1-9][0-9]*)(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let price = Decimal(string: rawPrice), let maxPrice = Decimal(string: "99999999.99"),
              price > 0, price <= maxPrice else {
            error = "请输入大于 0、最多两位小数的有效票价。"; return
        }
        guard let version = Self.strictInteger(Self.field(row, "Version")),
              Self.validTicketRow(row, merchantID: merchantID, expectedID: id),
              let sessions = Self.field(row, "Sessions") as? [[String: Any]] else {
            error = "票种或场次回执不完整，请重新读取。"; return
        }
        var changes: [[String: Any]] = []
        for session in sessions {
            let sessionID = Self.idString(session["Id"] ?? session["id"])
            let raw = (draft.sessionInventories[sessionID] ?? Self.idString(session["Inventory"] ?? session["inventory"]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let sold = Self.strictInteger(Self.field(session, "SoldCount")), let reserved = Self.strictInteger(Self.field(session, "ReservedCount")),
                  let prior = Self.strictInteger(Self.field(session, "Inventory")), let sessionVersion = Self.strictInteger(Self.field(session, "Version")) else {
                error = "场次已售或待支付数量异常，请刷新后重试。"
                return
            }
            let committed = sold + reserved
            guard raw.range(of: "^(0|[1-9][0-9]*)$", options: .regularExpression) != nil,
                  let inventory = Int(raw), (0...10_000_000).contains(inventory), committed <= inventory else {
                error = "场次“\(session["Name"] as? String ?? "未命名")”库存须为 0 至 10000000，且不低于已售和待支付数量 \(committed)。"
                return
            }
            if inventory != prior { changes.append(["Id": sessionID, "Version": sessionVersion, "Inventory": inventory]) }
        }
        let body: [String: Any] = ["Id": id, "MerchantId": merchantID, "Version": version, "Price": NSDecimalNumber(decimal: price), "Sessions": changes]
        pendingTicket = NativeMerchantTicketChange(id: id, name: row["Name"] as? String ?? row["name"] as? String ?? "该门票", body: body, revision: requestSequence)
    }

    private func save(_ change: NativeMerchantTicketChange) async {
        guard !saving, !loading, change.revision == requestSequence, !blockedTickets.contains(change.id) else { return }
        guard let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { error = "登录已失效，请重新登录。"; return }
        saving = true; error = nil
        blockedTickets.insert(change.id)
        defer { saving = false; pendingTicket = nil }
        var acknowledged = false
        do {
            let receipt = try await MobileAPI(store: store).post("/api/JHCTITicket/SaveMerchantInventory", body: change.body, authenticated: true,
                expectedPrincipal: expectedPrincipal)
            acknowledged = receipt as? String == change.id
        } catch is CancellationError {
            if store.session?.accessToken == token { error = "票务保存结果待核对，请重新读取该票种。" }
            return
        } catch {
            if Task.isCancelled { return }
        }
        await readBack(change.id, token: token, principal: expectedPrincipal, revision: change.revision)
        if store.session?.accessToken == token, error == nil, !acknowledged { error = "已重新读取最新票务数据，请核对票价与库存。" }
    }

    private func retryReadBack(_ id: String) async {
        guard !saving, !loading, let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else { return }
        saving = true; error = nil
        defer { saving = false }
        await readBack(id, token: token, principal: principal, revision: requestSequence)
    }

    private func readBack(_ id: String, token: String, principal: String, revision: Int) async {
        guard store.session?.accessToken == token, requestSequence == revision else { return }
        do {
            let result = try await MobileAPI(store: store).get("/api/JHCTITicket/GetMerchantInventoryTicket?merchantId=\(merchantID)&id=\(id)",
                authenticated: true, expectedPrincipal: principal)
            guard let row = result as? [String: Any], Self.validTicketRow(row, merchantID: merchantID, expectedID: id) else {
                throw MobileAPIError.unavailable("票种回执异常")
            }
            guard store.session?.accessToken == token, requestSequence == revision else { return }
            if let index = rows.firstIndex(where: { Self.idString($0["Id"] ?? $0["id"]) == id }) { rows[index] = row }
            drafts[id] = NativeMerchantTicketDraft(price: Self.idString(Self.field(row, "Price")), sessionInventories: [:])
            blockedTickets.remove(id)
        } catch {
            if store.session?.accessToken == token, requestSequence == revision { self.error = "保存结果待核对，请重新读取该票种。" }
        }
    }

    private func load(page targetPage: Int) async {
        guard !saving else { return }
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

    private static func field(_ row: [String: Any], _ name: String) -> Any? {
        let alias = name.prefix(1).lowercased() + String(name.dropFirst())
        if let first = row[name], let second = row[alias] {
            let lhs = try? JSONSerialization.data(withJSONObject: first, options: [.sortedKeys, .fragmentsAllowed])
            let rhs = try? JSONSerialization.data(withJSONObject: second, options: [.sortedKeys, .fragmentsAllowed])
            if lhs == nil || lhs != rhs { return nil }
        }
        return row[name] ?? row[alias]
    }

    private static func strictInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 0, number.doubleValue <= 9_007_199_254_740_991,
              number.doubleValue.rounded(.towardZero) == number.doubleValue else { return nil }
        return number.intValue
    }

    private static func strictID(_ value: Any?) -> String? {
        guard let id = value as? String, let number = Int64(id), number > 0, String(number) == id else { return nil }
        return id
    }

    private static func validTicketRow(_ row: [String: Any], merchantID: String, expectedID: String) -> Bool {
        guard strictID(field(row, "Id")) == expectedID, strictID(field(row, "MerchantId")) == merchantID,
              strictInteger(field(row, "Version")) != nil,
              let price = field(row, "Price") as? NSNumber, CFGetTypeID(price) != CFBooleanGetTypeID(),
              price.doubleValue > 0, price.doubleValue <= 99_999_999.99,
              let sessions = field(row, "Sessions") as? [[String: Any]], (1...100).contains(sessions.count) else { return false }
        var ids = Set<String>()
        for session in sessions {
            guard let id = strictID(field(session, "Id")), ids.insert(id).inserted, strictInteger(field(session, "Version")) != nil,
                  let inventory = strictInteger(field(session, "Inventory")), inventory <= 10_000_000,
                  let sold = strictInteger(field(session, "SoldCount")), let reserved = strictInteger(field(session, "ReservedCount")),
                  sold <= inventory, reserved <= inventory - sold else { return false }
        }
        return true
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
