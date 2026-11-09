import Foundation
import SwiftUI
import AVFoundation
import VisionKit

struct RestaurantWorkbenchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    @State private var restaurants: [[String: Any]] = []
    @State private var stores: [[String: Any]] = []
    @State private var roles: [[String: Any]] = []
    @State private var restaurantID = ""
    @State private var loading = true
    @State private var scopeLoading = false
    @State private var error: String?
    @State private var revision = 0
    @State private var reportOpen = false

    private let roleNames = ["RestaurantAdmin": "餐饮管理", "Order": "餐饮订单", "Product": "菜单管理",
                             "Verifier": "到店核销", "FinanceReadOnly": "经营数据只读"]

    private func diningRows(_ value: Any, label: String) throws -> [[String: Any]] {
        guard let rows = value as? [[String: Any]] else {
            throw MobileAPIError.unavailable("\(label)回执格式无效，请重试")
        }
        return rows
    }

    private func diningID(_ value: Any?, allowZero: Bool = false) throws -> String {
        guard let text = value as? String, let id = Int64(text), id >= 0,
              String(id) == text, allowZero || id > 0 else {
            throw MobileAPIError.unavailable("餐饮授权回执编号无效，请重试")
        }
        return text
    }

    private func diningRestaurants(_ value: Any) throws -> [[String: Any]] {
        try diningRows(value, label: "餐饮商家").map { row in
            _ = try diningID(row["Id"])
            guard let name = row["Name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MobileAPIError.unavailable("餐饮商家资料不完整，请重试")
            }
            return row
        }
    }

    private func diningRoles(_ value: Any, restaurantID: String? = nil) throws -> [[String: Any]] {
        try diningRows(value, label: "餐饮岗位").map { row in
            let rowRestaurantID = try diningID(row["RestaurantId"])
            _ = try diningID(row["StoreId"], allowZero: true)
            guard let code = row["RoleCode"] as? String, !code.isEmpty,
                  restaurantID == nil || restaurantID == rowRestaurantID else {
                throw MobileAPIError.unavailable("餐饮岗位资料不完整，请重试")
            }
            return row
        }
    }

    private func diningStores(_ value: Any, restaurantID: String) throws -> [[String: Any]] {
        try diningRows(value, label: "餐饮门店").map { row in
            _ = try diningID(row["Id"])
            let ownerID = try diningID(row["RestaurantId"])
            guard ownerID == restaurantID,
                  let name = row["Name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  row["IsEnabled"] as? Bool != nil else {
                throw MobileAPIError.unavailable("餐饮门店资料不完整，请重试")
            }
            return row
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("餐饮工作台").font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif))
                        Text("仅显示当前文旅账号获授权的餐饮商家、门店和岗位")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    .background(LinearGradient(colors: [Color(red: 0.86, green: 0.94, blue: 0.91), Brand.background],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 12))
                    StatusView(loading: loading, error: error) { revision += 1 }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("当前餐饮商家").font(.headline)
                        if restaurants.isEmpty {
                            Text(loading ? "正在核验餐饮授权…" : "当前账号没有可访问的餐饮工作范围。")
                                .foregroundStyle(Brand.muted)
                        } else {
                            Picker("选择餐饮商家", selection: $restaurantID) {
                                ForEach(restaurants.indices, id: \.self) { index in
                                    Text(restaurants[index]["Name"] as? String ?? "未命名商家")
                                        .tag(restaurants[index]["Id"] as? String ?? "")
                                }
                            }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.merchantCard()
                    if !restaurantID.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text("授权门店").font(.headline); Spacer(); Text("\(stores.count) 家").foregroundStyle(Brand.muted) }
                            if scopeLoading { ProgressView("正在读取门店范围…") }
                            else if stores.isEmpty { Text("当前商家没有已授权门店。请联系商家管理员检查岗位范围。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted) }
                            ForEach(stores.indices, id: \.self) { index in
                                let item = stores[index]
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(item["Name"] as? String ?? "未命名门店").font(.system(size: NativeTypography.size(16), weight: .semibold))
                                        Spacer()
                                        Text(item["IsEnabled"] as? Bool == false ? "已停用" : "已启用")
                                            .font(.caption).foregroundStyle(item["IsEnabled"] as? Bool == false ? Brand.muted : Brand.primary)
                                    }
                                    Text(item["Address"] as? String ?? "未填写地址")
                                        .font(.caption).foregroundStyle(Brand.muted)
                                    let storeID = item["Id"] as? String ?? ""
                                    let storeRoles = roles.filter {
                                        let scope = $0["StoreId"] as? String ?? "0"
                                        return scope == "0" || scope == storeID
                                    }
                                    if !storeRoles.isEmpty {
                                        Text(storeRoles.map { roleNames[$0["RoleCode"] as? String ?? ""] ?? "餐饮岗位" }
                                            .joined(separator: " · "))
                                            .font(.caption.weight(.medium)).foregroundStyle(Brand.primary)
                                    }
                                    if item["IsEnabled"] as? Bool != false,
                                       storeRoles.contains(where: { ["RestaurantAdmin", "Product"].contains($0["RoleCode"] as? String ?? "") }) {
                                        NavigationLink {
                                            RestaurantMenuManagementView(store: store,
                                                storeID: storeID,
                                                storeName: item["Name"] as? String ?? "餐饮门店")
                                        } label: {
                                            Label("菜单管理", systemImage: "fork.knife")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    if item["IsEnabled"] as? Bool != false,
                                       storeRoles.contains(where: { ["RestaurantAdmin", "Order"].contains($0["RoleCode"] as? String ?? "") }) {
                                        NavigationLink {
                                            RestaurantQueueManagementView(store: store,
                                                storeID: storeID,
                                                storeName: item["Name"] as? String ?? "餐饮门店")
                                        } label: {
                                            Label("排队叫号", systemImage: "person.3.sequence")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.bordered)
                                        NavigationLink {
                                            RestaurantReservationManagementView(store: store, storeID: storeID,
                                                storeName: item["Name"] as? String ?? "餐饮门店")
                                        } label: {
                                            Label("预订管理", systemImage: "calendar")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    if item["IsEnabled"] as? Bool != false,
                                       storeRoles.contains(where: { ["RestaurantAdmin", "Verifier"].contains($0["RoleCode"] as? String ?? "") }) {
                                        NavigationLink {
                                            RestaurantPackageVerificationView(store: store, restaurantID: restaurantID,
                                                storeID: storeID, storeName: item["Name"] as? String ?? "餐饮门店")
                                        } label: {
                                            Label("团购核销", systemImage: "qrcode.viewfinder")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
                            }
                            if !scopeLoading, roles.contains(where: {
                                ($0["RestaurantId"] as? String) == restaurantID
                                    && ["RestaurantAdmin", "FinanceReadOnly"].contains($0["RoleCode"] as? String ?? "")
                            }) {
                                Button { reportOpen = true } label: {
                                    Label("查看餐饮经营报表", systemImage: "chart.bar.xaxis")
                                        .font(.caption.weight(.semibold))
                                }.buttonStyle(.bordered)
                            }
                        }.merchantCard()
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text("我的餐饮岗位").font(.headline); Spacer(); Text("\(roles.count) 项").foregroundStyle(Brand.muted) }
                            if scopeLoading { ProgressView("正在读取岗位…") }
                            else if roles.isEmpty { Text("当前账号没有有效的餐饮岗位授权。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted) }
                            ForEach(roles.indices, id: \.self) { index in
                                let role = roles[index]
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(roleNames[role["RoleCode"] as? String ?? ""] ?? "餐饮岗位")
                                        let scopeID = role["StoreId"] as? String ?? "0"
                                        Text(scopeID == "0" ? "商家全部门店" : stores.first(where: { ($0["Id"] as? String) == scopeID })?["Name"] as? String ?? "指定门店")
                                            .font(.caption).foregroundStyle(Brand.muted)
                                    }
                                    Spacer(); Text("已授权").font(.caption).foregroundStyle(Brand.primary)
                                }
                                if index < roles.count - 1 { Divider() }
                            }
                        }.merchantCard()
                    }
                    Text("页面仅展示服务端返回的授权范围；门店业务操作仍由服务端逐次校验。")
                        .font(.caption).foregroundStyle(Brand.muted).padding(.horizontal, 4)
                }.padding(16)
            }
            .background(Brand.background)
            .toolbar { Button("返回个人使用") { dismiss() } }
            .sheet(isPresented: $reportOpen) {
                RestaurantFinancialReportView(store: store,
                    restaurantID: restaurantID,
                    restaurantName: restaurants.first(where: { ($0["Id"] as? String) == restaurantID })?["Name"] as? String ?? "餐饮商家")
            }
            .task(id: revision) { await loadRestaurants() }
            .task(id: "\(restaurantID)-\(revision)") { await loadScope() }
            .onChange(of: store.session?.accessToken) { _, _ in dismiss() }
        }
    }

    private func loadRestaurants() async {
        guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else { dismiss(); return }
        let requestedRevision = revision
        loading = true; error = nil
        defer {
            if store.session?.accessToken == token, revision == requestedRevision { loading = false }
        }
        do {
            let api = MobileAPI(store: store)
            let values = try diningRestaurants(await api.get("/api/JHCTIDining/GetRestaurants", authenticated: true,
                expectedPrincipal: principal))
            let grants = try diningRoles(await api.get("/api/JHCTIDining/GetMyWorkRoles", authenticated: true,
                expectedPrincipal: principal))
            guard store.session?.accessToken == token, revision == requestedRevision else { return }
            let ids = Set(grants.compactMap { $0["RestaurantId"] as? String })
            restaurants = values.filter { ids.contains($0["Id"] as? String ?? "") }
            let valid = Set(restaurants.compactMap { $0["Id"] as? String })
            roles = grants.filter { valid.contains($0["RestaurantId"] as? String ?? "") }
            if !valid.contains(restaurantID) { restaurantID = restaurants.first?["Id"] as? String ?? "" }
            if restaurants.isEmpty { error = "当前账号没有餐饮岗位授权，或授权已失效。" }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if store.session?.accessToken == token, revision == requestedRevision {
                restaurants = []; stores = []; roles = []; self.error = error.localizedDescription
            }
        }
    }

    private func loadScope() async {
        stores = []; roles = []; error = nil
        scopeLoading = false
        guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token), !restaurantID.isEmpty,
              restaurantID.allSatisfy(\.isNumber) else { return }
        let requested = restaurantID
        let requestedRevision = revision
        scopeLoading = true
        defer {
            if store.session?.accessToken == token, restaurantID == requested, revision == requestedRevision {
                scopeLoading = false
            }
        }
        do {
            let api = MobileAPI(store: store)
            let storeResponse = try await api.get(
                "/api/JHCTIDining/GetStores?restaurantId=\(requested)", authenticated: true, expectedPrincipal: principal)
            let roleResponse = try await api.get(
                "/api/JHCTIDining/GetMyWorkRoles?restaurantId=\(requested)", authenticated: true, expectedPrincipal: principal)
            let values = try diningStores(storeResponse, restaurantID: requested)
            let scopedRoles = try diningRoles(roleResponse, restaurantID: requested)
            guard store.session?.accessToken == token, restaurantID == requested,
                  revision == requestedRevision else { return }
            stores = values
            roles = scopedRoles
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if store.session?.accessToken == token, restaurantID == requested,
               revision == requestedRevision { self.error = error.localizedDescription }
        }
    }
}

private struct RestaurantFinancialReportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let restaurantID: String
    let restaurantName: String
    @State private var fromDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: -29, to: Date()) ?? Date()
    @State private var toDate = Date()
    @State private var report: [String: Any]?
    @State private var page = 1
    @State private var loading = false
    @State private var error: String?
    @State private var revision = 0
    @State private var activeToken = ""
    @State private var requestGeneration = 0
    private let pageSize = 20

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("餐饮经营报表").font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif))
                        Text("\(restaurantName) · 按当前账号获授权的门店汇总")
                            .font(.caption).foregroundStyle(Brand.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(Brand.background, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("统计日期（含首尾）").font(.headline)
                        DatePicker("开始日期", selection: $fromDate, displayedComponents: .date)
                        DatePicker("结束日期", selection: $toDate, displayedComponents: .date)
                        Button(loading ? "正在查询…" : "查询报表") { revision += 1 }
                            .buttonStyle(.borderedProminent).disabled(loading)
                    }.merchantCard()
                    if loading { ProgressView("正在读取报表…").frame(maxWidth: .infinity).padding(20) }
                    if let error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.caption).foregroundStyle(.red)
                            Button("重试") { revision += 1 }.buttonStyle(.bordered)
                        }.merchantCard()
                    }
                    if let report {
                        let totals = report["Totals"] as? [[String: Any]] ?? report["totals"] as? [[String: Any]] ?? []
                        let items = report["Items"] as? [[String: Any]] ?? report["items"] as? [[String: Any]] ?? []
                        VStack(alignment: .leading, spacing: 10) {
                            Text("团购套餐支付与退款流水").font(.headline)
                            if totals.isEmpty {
                                Text("所选日期范围内暂无支付或完成退款的团购订单。")
                                    .font(.caption).foregroundStyle(Brand.muted)
                            }
                            ForEach(totals.indices, id: \.self) { index in
                                let item = totals[index]
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(display(field(item, "Currency")) ?? "币种未知")
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.primary)
                                    reportLine("已支付订单", "\(integer(field(item, "PaidOrderCount"))) 单")
                                    reportLine("统计期支付金额", reportMoney(item, "PaidAmount"))
                                    reportLine("统计期已完成退款", "\(integer(field(item, "RefundedCount"))) 笔 · \(reportMoney(item, "RefundedAmount"))")
                                    reportLine("期间流水差额", reportMoney(item, "NetAmount"))
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
                            }
                            Text("门店明细 · \(integer(field(report, "Total"))) 项").font(.subheadline.weight(.semibold))
                            ForEach(items.indices, id: \.self) { index in
                                let item = items[index]
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(display(field(item, "StoreName")) ?? "授权门店") · \(display(field(item, "Currency")) ?? "币种未知")")
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(integer(field(item, "PaidOrderCount"))) 单 · 支付 \(reportMoney(item, "PaidAmount")) · 退款 \(reportMoney(item, "RefundedAmount"))")
                                        .font(.caption).foregroundStyle(Brand.muted)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(12).merchantCard()
                            }
                            let total = integer(field(report, "Total"))
                            let pages = max(1, (total + pageSize - 1) / pageSize)
                            if pages > 1 {
                                HStack {
                                    Button("上一页") { page -= 1; revision += 1 }.disabled(page <= 1 || loading)
                                    Spacer(); Text("\(page) / \(pages)").font(.caption)
                                    Spacer(); Button("下一页") { page += 1; revision += 1 }.disabled(page >= pages || loading)
                                }.buttonStyle(.bordered)
                            }
                            Text("支付按渠道确认支付时间统计，退款按实际完成时间统计。期间流水差额仅为本系统团购支付和退款记录的差值，不等同支付渠道到账或门店正式结算；桌台点餐/结账尚未纳入。")
                                .font(.caption2).foregroundStyle(Brand.muted)
                        }.merchantCard()
                    }
                    Text("报表只读；服务端按餐饮商家、当前岗位和门店授权范围过滤数据。")
                        .font(.caption2).foregroundStyle(Brand.muted)
                }.padding(16)
            }.background(Brand.background)
                .toolbar { Button("关闭") { dismiss() } }
                .task(id: "\(restaurantID)-\(page)-\(revision)-\(store.session?.accessToken ?? "")") { await loadReport() }
                .onChange(of: fromDate) { _, _ in report = nil; page = 1; requestGeneration += 1; loading = false; error = nil }
                .onChange(of: toDate) { _, _ in report = nil; page = 1; requestGeneration += 1; loading = false; error = nil }
                .onChange(of: store.session?.accessToken) { _, _ in dismiss() }
        }
    }

    private func loadReport() async {
        guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else { error = "请登录后查看餐饮经营报表。"; return }
        var businessCalendar = Calendar(identifier: .gregorian)
        businessCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        guard restaurantID.allSatisfy(\.isNumber), fromDate <= toDate,
              let dayCount = businessCalendar.dateComponents([.day], from: fromDate, to: toDate).day,
              dayCount <= 365, let exclusiveEnd = businessCalendar.date(byAdding: .day, value: 1, to: toDate) else {
            report = nil; error = "请选择有效日期范围，最多 366 天。"; return
        }
        requestGeneration += 1
        let requestID = requestGeneration
        activeToken = token; loading = true; error = nil; report = nil
        defer {
            if store.session?.accessToken == token, requestGeneration == requestID { loading = false }
        }
        let formatter = DateFormatter(); formatter.calendar = businessCalendar
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd"
        let from = formatter.string(from: fromDate), to = formatter.string(from: toDate)
        let exclusiveDate = formatter.string(from: exclusiveEnd)
        let range = "from=\(from)T00%3A00%3A00&to=\(to)T23%3A59%3A59&restaurantId=\(restaurantID)&page=\(page)&pageSize=\(pageSize)"
        do {
            let result = try await MobileAPI(store: store).get("/api/JHCTIDining/GetMyFinancialReport?\(range)", authenticated: true,
                expectedPrincipal: principal) as? [String: Any] ?? [:]
            guard store.session?.accessToken == token, activeToken == token, requestGeneration == requestID else { return }
            let data = result["Data"] as? [String: Any] ?? result["data"] as? [String: Any] ?? result
            let totals = data["Totals"] as? [[String: Any]] ?? data["totals"] as? [[String: Any]]
            let rows = data["Items"] as? [[String: Any]] ?? data["items"] as? [[String: Any]]
            let currencies = totals?.compactMap { field($0, "Currency") as? String }
            guard let responseFrom = field(data, "From") as? String,
                  let responseTo = field(data, "ToExclusive") as? String,
                  let generatedAt = field(data, "GeneratedAt") as? String,
                  businessDate(responseFrom) == from, businessDate(responseTo) == exclusiveDate,
                  parseDateTime(generatedAt) != nil,
                  let totals, let rows,
                  let total = data["Total"] as? Int ?? data["total"] as? Int, total >= 0,
                  let resultPage = data["Page"] as? Int ?? data["page"] as? Int, resultPage == page,
                  let resultSize = data["PageSize"] as? Int ?? data["pageSize"] as? Int, resultSize == pageSize,
                  let expectedRows = nativeReportExpectedRows(page: page, total: total, pageSize: pageSize),
                  rows.count == expectedRows,
                  currencies?.count == totals.count,
                  Set(currencies?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() } ?? []).count == totals.count,
                  totals.allSatisfy({ validSummary($0, requireStore: false) }),
                  totals.allSatisfy({ (field($0, "RestaurantId") as? String) == restaurantID }),
                  rows.allSatisfy({ validSummary($0, requireStore: true) }),
                  rows.allSatisfy({ (field($0, "RestaurantId") as? String) == restaurantID }) else {
                throw MobileAPIError.unavailable("餐饮经营报表分页回执无效")
            }
            let uniqueStoreKeys = rows.compactMap { item -> String? in
                guard let storeID = field(item, "StoreId") as? String,
                      let currency = field(item, "Currency") as? String else { return nil }
                return "\(storeID)|\(currency.uppercased())"
            }
            guard uniqueStoreKeys.count == rows.count, Set(uniqueStoreKeys).count == rows.count else {
                throw MobileAPIError.unavailable("餐饮经营报表门店明细重复")
            }
            report = data
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if store.session?.accessToken == token && requestGeneration == requestID { self.error = error.localizedDescription }
        }
    }

    private func reportLine(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(Brand.muted); Spacer(); Text(value).multilineTextAlignment(.trailing) }
            .font(.caption)
    }
    private func reportMoney(_ item: [String: Any], _ key: String) -> String {
        let currency = display(field(item, "Currency")) ?? "币种未知"
        guard let text = display(field(item, key)), let amount = Decimal(string: text),
              amount >= 0 || key == "NetAmount" else { return "金额待确认" }
        var source = amount; var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .plain)
        guard rounded == amount else { return "金额待确认" }
        return "\(currency) \(NSDecimalNumber(decimal: amount).stringValue)"
    }
    private func integer(_ value: Any?) -> Int { (value as? Int) ?? Int(display(value) ?? "") ?? 0 }
    private func display(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return String(describing: value)
    }
    private func field(_ item: [String: Any], _ key: String) -> Any? {
        item[key] ?? item[key.prefix(1).lowercased() + String(key.dropFirst())]
    }
    private func validSummary(_ item: [String: Any], requireStore: Bool) -> Bool {
        guard let currency = field(item, "Currency") as? String, !currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let paidCount = field(item, "PaidOrderCount") as? Int, paidCount >= 0,
              let refundCount = field(item, "RefundedCount") as? Int, refundCount >= 0,
              validAmount(field(item, "PaidAmount"), allowNegative: false),
              validAmount(field(item, "RefundedAmount"), allowNegative: false),
              validAmount(field(item, "NetAmount"), allowNegative: true) else { return false }
        guard requireStore else { return true }
        guard let storeID = field(item, "StoreId") as? String,
              Int64(storeID).map({ $0 > 0 }) == true,
              let storeName = field(item, "StoreName") as? String, !storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rowRestaurantID = field(item, "RestaurantId") as? String,
              Int64(rowRestaurantID).map({ $0 > 0 }) == true else { return false }
        return true
    }
    private func validAmount(_ value: Any?, allowNegative: Bool) -> Bool {
        guard let text = display(value), let amount = Decimal(string: text),
              allowNegative || amount >= 0,
              amount <= Decimal(string: "90071992547409.91")!,
              amount >= Decimal(string: "-90071992547409.91")! else { return false }
        var source = amount; var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .plain)
        return rounded == amount
    }
    private func parseDateTime(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) { return date }
        let suffix = String(value.dropFirst(min(value.count, 19)))
        guard value.count >= 19, suffix.isEmpty || suffix.first == "." else { return nil }
        let wallClock = DateFormatter(); wallClock.calendar = Calendar(identifier: .gregorian)
        wallClock.timeZone = TimeZone(identifier: "Asia/Shanghai"); wallClock.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return wallClock.date(from: String(value.prefix(19)))
    }
    private func businessDate(_ value: String) -> String? {
        guard let date = parseDateTime(value) else { return nil }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct RestaurantPackageVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let restaurantID: String
    let storeID: String
    let storeName: String
    @State private var authorized = false
    @State private var loading = true
    @State private var scanning = false
    @State private var scannerOpen = false
    @State private var cameraAvailable = false
    @State private var scannerSessionToken = ""
    @State private var showFeatureStatus = false
    @State private var redeeming = false
    @State private var confirming = false
    @State private var code = ""
    @State private var error: String?
    @State private var receipt: [String: Any]?
    @State private var revision = 0
    @State private var requestGeneration = 0

    var body: some View {
        List {
            Section {
                Text(storeName).font(.headline)
                Text("请核对顾客团购凭证和适用门店。每张凭证对应一整套套餐，成功后整套完成一次核销；有效期、重复核销及最终结果由服务端校验。")
                    .font(.caption).foregroundStyle(Brand.muted)
            }
            if loading { Section { ProgressView("正在核验餐饮门店授权…") } }
            if authorized {
                Section("核销凭证") {
                    if DataScannerViewController.isSupported {
                        Button(scanning ? "正在启动扫码…" : "扫描团购凭证") { Task { await requestScannerAccess() } }
                            .disabled(scanning || redeeming)
                    }
                    TextField("团购凭证码", text: $code)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(redeeming).onChange(of: code) { _, value in
                            if value.count > 128 { code = String(value.prefix(128)) }
                            receipt = nil; error = nil
                        }
                    if !DataScannerViewController.isSupported {
                        Text("当前设备不支持二维码扫描，请手动输入凭证码。")
                            .font(.caption).foregroundStyle(Brand.muted)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Button(redeeming ? "正在核销…" : "核对后确认核销") { confirming = true }
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                        .disabled(redeeming || scanning || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if !loading, !authorized, let error {
                Section("无法核验授权") {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("重试授权") { revision += 1 }
                        .disabled(redeeming || scanning)
                }
            }
            if let receipt {
                Section("核销成功") {
                    Text("套餐：\(receipt["PackageName"] as? String ?? "餐饮团购套餐")")
                    Text("该凭证对应的整套套餐已一次性核销。")
                    Text("订单号：\(receipt["OrderNo"] as? String ?? "—")")
                    Text("完成时间：\(verificationText(receipt["RedeemedAt"], fallback: "刚刚"))")
                }
            }
            Section {
                Text("核销成功后不可重复使用。页面不保存凭证码；核销记录由服务端按账号和门店权限留存。")
                    .font(.caption2).foregroundStyle(Brand.muted)
            }
        }
        .navigationTitle("餐饮团购核销")
        .task(id: revision) { await loadAccess() }
        .onChange(of: store.session?.accessToken) { _, token in
            code = ""; receipt = nil; scannerOpen = false; scannerSessionToken = ""
            if token == nil { dismiss() } else { revision += 1 }
        }
        .onDisappear { code = ""; scannerOpen = false; scannerSessionToken = ""; receipt = nil }
        .sheet(isPresented: $scannerOpen) {
            NativeActivityQrScanner(inputLabel: "团购凭证码", onCode: { scanned in
                guard !scannerSessionToken.isEmpty,
                      store.session?.accessToken == scannerSessionToken else {
                    code = ""; scannerOpen = false; scannerSessionToken = ""
                    error = "登录账号已变化，请重新读取授权后扫码。"
                    return
                }
                let value = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty && value.count <= 128 { code = value; error = nil; receipt = nil }
                else { code = ""; receipt = nil; error = "二维码内容不是有效的团购凭证码，请手动核对。" }
                scannerOpen = false; scannerSessionToken = ""
            }, onFailure: { message in
                guard !scannerSessionToken.isEmpty,
                      store.session?.accessToken == scannerSessionToken else {
                    scannerOpen = false; scannerSessionToken = ""; return
                }
                error = message; cameraAvailable = false; scannerOpen = false; scannerSessionToken = ""
            }).ignoresSafeArea()
        }
        .confirmationDialog("确认核销团购凭证？", isPresented: $confirming, titleVisibility: .visible) {
            Button("确认核销", role: .destructive) { Task { await redeem() } }.disabled(redeeming)
            Button("再核对一下", role: .cancel) { confirming = false }
        } message: {
            Text("该凭证对应一整套套餐，将在“\(storeName)”一次性核销全部套餐内容，不支持拆分；成功后不可重复使用。请确认顾客凭证与门店一致。")
        }
    }

    private func loadAccess() async {
        guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token),
              Int64(restaurantID).map({ $0 > 0 }) == true,
              Int64(storeID).map({ $0 > 0 }) == true else {
            authorized = false; error = "商家、门店或登录范围无效，请返回工作台重新进入。"; loading = false; return
        }
        requestGeneration += 1
        let requestID = requestGeneration
        loading = true; authorized = false; error = nil
        defer {
            if requestGeneration == requestID, store.session?.accessToken == token { loading = false }
        }
        do {
            let api = MobileAPI(store: store)
            let storeResponse = try await api.get(
                "/api/JHCTIDining/GetStores?restaurantId=\(restaurantID)", authenticated: true, expectedPrincipal: principal)
            try Task.checkCancellation()
            guard requestGeneration == requestID, store.session?.accessToken == token else { return }
            let roleResponse = try await api.get(
                "/api/JHCTIDining/GetMyWorkRoles?restaurantId=\(restaurantID)", authenticated: true, expectedPrincipal: principal)
            try Task.checkCancellation()
            let stores = storeResponse as? [[String: Any]] ?? []
            let roles = roleResponse as? [[String: Any]] ?? []
            guard requestGeneration == requestID, store.session?.accessToken == token else { return }
            let selected = stores.first { verificationText($0["Id"]) == storeID }
            let roleAllowed = roles.contains {
                ["RestaurantAdmin", "Verifier"].contains(verificationText($0["RoleCode"]))
                    && (["", "0"].contains(verificationText($0["StoreId"])) || verificationText($0["StoreId"]) == storeID)
            }
            guard selected != nil, (selected?["IsEnabled"] as? Bool) != false, roleAllowed else {
                throw MobileAPIError.unavailable("当前账号没有该门店的团购核销授权，请返回工作台核对岗位。")
            }
            authorized = true
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if requestGeneration == requestID, store.session?.accessToken == token {
                self.error = error.localizedDescription
            }
        }
    }

    private func verificationText(_ value: Any?, fallback: String = "") -> String {
        guard let value, !(value is NSNull) else { return fallback }
        return String(describing: value)
    }

    @MainActor private func requestScannerAccess() async {
        guard let token = store.session?.accessToken, !token.isEmpty else { error = "请先登录已获授权的餐饮工作人员账号。"; return }
        guard DataScannerViewController.isSupported else { error = "当前设备不支持扫码，请手动输入凭证码。"; return }
        scanning = true
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted = status == .authorized ? true : status == .notDetermined
            ? await AVCaptureDevice.requestAccess(for: .video) : false
        guard store.session?.accessToken == token else {
            code = ""; scannerOpen = false; scannerSessionToken = ""
            error = "登录账号已变化，请重新读取授权后扫码。"; scanning = false; return
        }
        cameraAvailable = granted && DataScannerViewController.isAvailable
        scannerSessionToken = cameraAvailable ? token : ""
        scannerOpen = cameraAvailable
        if !cameraAvailable { error = "相机权限未开启或设备不可用，请手动输入凭证码。" }
        scanning = false
    }

    private func redeem() async {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard authorized, !redeeming, !value.isEmpty, value.count <= 128,
              let token = store.session?.accessToken,
              let principal = nativeTourismPrincipal(token) else {
            error = value.isEmpty ? "请先扫描或输入团购凭证码。" : "凭证码长度无效，请核对后重试。"; return
        }
        redeeming = true; error = nil; receipt = nil
        defer { redeeming = false }
        do {
            guard let result = try await MobileAPI(store: store).post(
                "/api/JHCTIDiningPackage/Redeem", body: ["StoreId": storeID, "Code": value], authenticated: true,
                expectedPrincipal: principal
            ) as? [String: Any] else { throw MobileAPIError.unavailable("核销回执格式异常，请联系管理员核对。") }
            try Task.checkCancellation()
            guard store.session?.accessToken == token else {
                code = ""; throw MobileAPIError.unavailable("登录账号已变化，请在原门店核对核销结果。")
            }
            guard !(result["OrderNo"] as? String ?? "").isEmpty,
                  !(result["PackageName"] as? String ?? "").isEmpty,
                  (result["Status"] as? String) == "Redeemed" else {
                throw MobileAPIError.unavailable("核销回执无法确认，请核对门店记录后再操作。")
            }
            receipt = result; code = ""
        } catch is CancellationError {
            if store.session?.accessToken == token {
                self.error = "核销请求已取消，结果可能已提交；请先核对门店核销记录后再操作。"
            }
            return
        } catch {
            if Task.isCancelled {
                if store.session?.accessToken == token {
                    self.error = "核销请求已取消，结果可能已提交；请先核对门店核销记录后再操作。"
                }
                return
            }
            if store.session?.accessToken == token { self.error = error.localizedDescription }
        }
    }
}
