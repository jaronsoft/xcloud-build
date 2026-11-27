import Foundation
import SwiftUI
import AVFoundation
import VisionKit

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
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SessionStore
    @StateObject private var redemption = NativeDiningPackageRedemption()
    let restaurantID: String
    let storeID: String
    let storeName: String
    @State private var authorized = false
    @State private var loading = true
    @State private var scanning = false
    @State private var scannerOpen = false
    @State private var cameraAvailable = false
    @State private var scannerPrincipal: String?
    @State private var confirming = false
    @State private var confirmingRelease = false
    @State private var code = ""
    @State private var error: String?
    @State private var revision = 0
    @State private var requestGeneration = 0
    @State private var visible = false
    @State private var operation: Task<Void, Never>?

    private var principal: String? { nativeTourismPrincipal(store.session?.accessToken) }
    private var canRedeem: Bool { authorized && !redemption.accessRevoked && redemption.state == .ready }

    var body: some View {
        List {
            Section {
                Text(storeName).font(.headline)
                Text("请核对顾客团购凭证和适用门店。每张凭证对应一整套套餐，成功后整套完成一次核销；有效期、重复核销及最终结果由服务端校验。")
                    .font(.caption).foregroundStyle(Brand.muted)
            }
            if loading { Section { ProgressView("正在核验餐饮门店授权…") } }
            if canRedeem {
                Section("核销凭证") {
                    if DataScannerViewController.isSupported {
                        Button(scanning ? "正在启动扫码…" : "扫描团购凭证") { Task { await requestScannerAccess() } }
                            .disabled(scanning || redemption.busy)
                    }
                    TextField("团购凭证码", text: Binding(get: { code }, set: { value in
                        code = String(value.prefix(129)); redemption.clearFeedback(); error = nil
                    }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(redemption.busy)
                    if code.utf16.count > 128 {
                        Text("凭证码最多 128 个字符，请核对输入内容。").font(.caption).foregroundStyle(.red)
                    }
                    if !DataScannerViewController.isSupported {
                        Text("当前设备不支持二维码扫描，请手动输入凭证码。")
                            .font(.caption).foregroundStyle(Brand.muted)
                    }
                    Button("核对后确认核销") { confirming = true }
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                        .disabled(redemption.busy || scanning || !(1...128).contains(code.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count))
                }
            }
            if authorized, !redemption.accessRevoked {
                switch redemption.state {
                case let .pending(attempt):
                    Section("核对团购核销") {
                        Text("上一次核销结果待核对，请查询原请求。")
                        Button("查询核销结果") { lookup(release: false) }.disabled(redemption.busy)
                        if redemption.canRelease {
                            Text("请求号 \(attempt.requestID)").font(.caption).textSelection(.enabled)
                            Button("已人工核对") { confirmingRelease = true }.disabled(redemption.busy)
                        }
                    }
                case .unavailable, .damaged:
                    Section { Text("暂时无法读取核销请求，请联系门店负责人核对。").font(.caption) }
                case .ready:
                    EmptyView()
                }
            }
            if redemption.busy { Section { ProgressView("正在处理核销请求…") } }
            if !loading, !authorized || redemption.accessRevoked, let message = redemption.notice ?? error {
                Section("无法核验授权") {
                    Text(message).font(.caption).foregroundStyle(.red)
                    Button("重试授权") { revision += 1 }
                        .disabled(redemption.busy || scanning)
                }
            }
            if authorized, !redemption.accessRevoked, let message = redemption.notice ?? error {
                Section { Text(message).font(.caption) }
            }
            if authorized, !redemption.accessRevoked, let receipt = redemption.receipt {
                Section("核销成功") {
                    Text("套餐：\(receipt.packageName)")
                    Text("该凭证对应的整套套餐已一次性核销。")
                    Text("订单号：\(receipt.orderNo)")
                    Text("完成时间：\(receipt.redeemedAt)")
                }
            }
            Section {
                Text("核销成功后不可重复使用。页面不保存凭证码；核销记录由服务端按账号和门店权限留存。")
                    .font(.caption2).foregroundStyle(Brand.muted)
            }
        }
        .navigationTitle("餐饮团购核销")
        .task(id: revision) { await loadAccess() }
        .onAppear { visible = true; revision += 1 }
        .onChange(of: principal) { _, next in
            reset()
            if next == nil { dismiss() } else { revision += 1 }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || (phase == .inactive && operation != nil) { reset() }
            if phase == .active, visible, !authorized, !loading { revision += 1 }
        }
        .onDisappear { visible = false; reset() }
        .sheet(isPresented: $scannerOpen) {
            NativeActivityQrScanner(inputLabel: "团购凭证码", onCode: { scanned in
                guard visible, canRedeem, let scannerPrincipal, principal == scannerPrincipal else { return }
                let value = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
                redemption.clearFeedback()
                if (1...128).contains(value.utf16.count) { code = value; error = nil }
                else { code = ""; error = "二维码内容不是有效的团购凭证码，请手动核对。" }
                scannerOpen = false; self.scannerPrincipal = nil
            }, onFailure: { message in
                guard visible, let scannerPrincipal, principal == scannerPrincipal else { return }
                error = message; cameraAvailable = false; scannerOpen = false; self.scannerPrincipal = nil
            }).ignoresSafeArea()
        }
        .confirmationDialog("确认核销团购凭证？", isPresented: $confirming, titleVisibility: .visible) {
            Button("确认核销", role: .destructive) { submit() }.disabled(redemption.busy)
            Button("再核对一下", role: .cancel) { confirming = false }
        } message: {
            Text("该凭证对应一整套套餐，将在“\(storeName)”一次性核销全部套餐内容，不支持拆分；成功后不可重复使用。请确认顾客凭证与门店一致。")
        }
        .alert("确认已人工核对", isPresented: $confirmingRelease) {
            Button("再次查询") { lookup(release: true) }
            Button("返回", role: .cancel) {}
        } message: {
            Text("请确认门店负责人已核对原请求。系统会再查询一次，仍未查到时结束本地等待。")
        }
    }

    private func loadAccess() async {
        guard visible, scenePhase != .background else { return }
        guard let principal, trackingID(restaurantID), trackingID(storeID) else {
            authorized = false; error = "商家、门店或登录范围无效，请返回工作台重新进入。"; loading = false; return
        }
        requestGeneration += 1
        let requestID = requestGeneration
        loading = true; authorized = false; error = nil; redemption.clearFeedback()
        func current() -> Bool { visible && requestGeneration == requestID && self.principal == principal }
        defer { if current() { loading = false } }
        do {
            let api = MobileAPI(store: store)
            let storeResponse = try await api.get(
                "/api/JHCTIDining/GetStores?restaurantId=\(restaurantID)", authenticated: true, expectedPrincipal: principal)
            try Task.checkCancellation()
            guard current() else { return }
            let roleResponse = try await api.get(
                "/api/JHCTIDining/GetMyWorkRoles?restaurantId=\(restaurantID)", authenticated: true, expectedPrincipal: principal)
            try Task.checkCancellation()
            let stores = storeResponse as? [[String: Any]] ?? []
            let roles = roleResponse as? [[String: Any]] ?? []
            guard current() else { return }
            let selected = stores.first { trackingField($0, "Id") as? String == storeID
                && trackingField($0, "RestaurantId") as? String == restaurantID }
            let roleAllowed = roles.contains {
                trackingField($0, "RestaurantId") as? String == restaurantID
                    && ["RestaurantAdmin", "Verifier"].contains(trackingField($0, "RoleCode") as? String ?? "")
                    && ["0", storeID].contains(trackingField($0, "StoreId") as? String ?? "")
            }
            guard let selected, trackingField(selected, "IsEnabled") as? Bool == true, roleAllowed else {
                throw MobileAPIError.unavailable("当前账号没有该门店的团购核销授权，请返回工作台核对岗位。")
            }
            redemption.reload(storeID: storeID, store: store); authorized = true
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if current() {
                self.error = error.localizedDescription
            }
        }
    }

    @MainActor private func requestScannerAccess() async {
        guard visible, !redemption.busy, canRedeem, let principal else { return }
        guard DataScannerViewController.isSupported else { error = "当前设备不支持扫码，请手动输入凭证码。"; return }
        scanning = true
        let generation = requestGeneration
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted = status == .authorized ? true : status == .notDetermined
            ? await AVCaptureDevice.requestAccess(for: .video) : false
        guard visible, canRedeem, requestGeneration == generation, self.principal == principal else { return }
        cameraAvailable = granted && DataScannerViewController.isAvailable
        scannerPrincipal = cameraAvailable ? principal : nil
        scannerOpen = cameraAvailable
        if !cameraAvailable { error = "相机权限未开启或设备不可用，请手动输入凭证码。" }
        scanning = false
    }

    private func submit() {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canRedeem, (1...128).contains(value.utf16.count) else { return }
        run { await redemption.submit(code: value, storeID: storeID, store: store) { code = "" } }
    }

    private func lookup(release: Bool) {
        run { await redemption.lookup(storeID: storeID, store: store, release: release) }
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        guard visible, scenePhase == .active, authorized, !redemption.accessRevoked, operation == nil,
              let expectedPrincipal = principal else { return }
        let generation = requestGeneration
        error = nil
        operation = Task { @MainActor in
            defer { if requestGeneration == generation { operation = nil } }
            guard visible, scenePhase == .active, requestGeneration == generation, principal == expectedPrincipal else { return }
            await action()
        }
    }

    private func reset() {
        requestGeneration += 1; operation?.cancel(); operation = nil
        redemption.invalidate(); authorized = false; loading = false; error = nil
        code = ""; scanning = false; scannerOpen = false; scannerPrincipal = nil
        confirming = false; confirmingRelease = false
    }
}

enum RestaurantWorkbenchPages {
    @ViewBuilder
    static func financialReport(store: SessionStore, restaurantID: String, restaurantName: String) -> some View {
        RestaurantFinancialReportView(store: store, restaurantID: restaurantID, restaurantName: restaurantName)
    }

    @ViewBuilder
    static func packageVerification(store: SessionStore, restaurantID: String, storeID: String, storeName: String) -> some View {
        RestaurantPackageVerificationView(store: store, restaurantID: restaurantID, storeID: storeID, storeName: storeName)
    }
}
