import SwiftUI

struct NativeDiningPackageCheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SessionStore
    let storeID: String
    let package: [String: Any]
    @State private var quantity = 1
    @State private var pointsText = "0"
    @State private var pointsBalance: Int64?
    @State private var pointsDebt: Int64?
    @State private var pointsError = false
    @State private var pendingAttempt: [String: Any]?
    @State private var recoveryBlocked = false
    @State private var legacyRecoveryNeedsReconciliation = false
    @State private var submitting = false
    @State private var purchaseEnabled = true
    @State private var error: String?
    @State private var createdOrder: [String: Any]?
    @State private var showOrders = false

    private var packageID: String { (package["Id"] as? String) ?? (package["id"] as? String) ?? "" }
    private var name: String { (package["Name"] as? String) ?? (package["name"] as? String) ?? "团购套餐" }
    private var price: Decimal? {
        let raw = package["SalePrice"] ?? package["salePrice"]
        let amount: Decimal?
        if let value = raw as? NSNumber { amount = value.decimalValue }
        else if let value = raw as? String { amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) }
        else { amount = nil }
        guard let amount else { return nil }
        return amount > 0 && amount <= 1_000_000 ? amount : nil
    }
    private var amount: Decimal { (price ?? 0) * Decimal(quantity) }
    private var points: Int64? { Int64(pointsText) }
    private var maxPoints: Int64 {
        let amountLimit = NSDecimalNumber(decimal: amount * 50)
        let maximum = NSDecimalNumber(value: Int64.max)
        return min(pointsBalance ?? 0, amountLimit.compare(maximum) == .orderedDescending ? Int64.max : amountLimit.int64Value)
    }
    private var cashEstimate: Double { max(0, NSDecimalNumber(decimal: amount - Decimal(points ?? 0) / 100).doubleValue) }

    var body: some View {
        NavigationStack {
            Form {
                Section("套餐") {
                    Text(name).font(.headline)
                    Text("单价：¥\(NSDecimalNumber(decimal: price ?? 0).doubleValue, specifier: "%.2f") / 份")
                    Text("有效期：\(Self.date(package["ValidFrom"] ?? package["validFrom"])) 至 \(Self.date(package["ValidTo"] ?? package["validTo"]))")
                    if let description = (package["Description"] as? String) ?? (package["description"] as? String), !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(Brand.muted)
                    }
                }
                Section("购买数量") {
                    Stepper("\(quantity) 份", value: $quantity, in: 1...10).disabled(submitting || createdOrder != nil || pendingAttempt != nil)
                    Text("每份对应一整套套餐，整套仅核销一次、不支持拆分；购买多份会生成多张独立凭证。")
                        .font(.caption).foregroundStyle(Brand.muted)
                }
                Section("积分抵扣") {
                    HStack {
                        Text("可用积分")
                        Spacer()
                        Text(pointsDebt.map { $0 > 0 ? "有待抵扣欠额" : "\(pointsBalance ?? 0)" } ?? (pointsError ? "余额暂不可用" : "读取中…"))
                            .foregroundStyle(Brand.muted)
                    }
                    TextField("输入积分数", text: $pointsText).keyboardType(.numberPad).disabled(submitting || createdOrder != nil || pendingAttempt != nil || pointsError || pointsDebt.map { $0 > 0 } == true)
                    if legacyRecoveryNeedsReconciliation {
                        Text("旧版恢复记录未保存账号身份。系统已按当前账号查单但未确认订单，为避免重复建单已锁定重试；请切换到可能下单的账号核对团购券，或联系平台处理。")
                            .font(.caption).foregroundStyle(.orange)
                    } else if pendingAttempt != nil {
                        Text("上次提交结果待确认，已锁定原购买数量和积分；请重试同一请求以核对订单。").font(.caption).foregroundStyle(.orange)
                    }
                    Text("100 积分抵 1 元，最多抵订单金额的 50%；仅人民币订单可使用，最终金额由服务端核算。")
                        .font(.caption).foregroundStyle(Brand.muted)
                    Text("现金应付估算：¥\(cashEstimate, specifier: "%.2f")")
                        .foregroundStyle(Brand.primary)
                }
                if let error { Section { Text(error).font(.caption).foregroundStyle(.red) } }
                if let createdOrder {
                    Section("订单已创建") {
                        Text("订单号：\((createdOrder["OrderNo"] as? String) ?? "—")")
                        Text("支付截止：\(Self.date(createdOrder["PaymentExpiresAt"]))")
                        Text("请到“我的团购券”继续支付并查看订单状态。")
                        Button("去我的团购券继续支付") { showOrders = true }
                    }
                }
            }
            .navigationTitle("确认团购订单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() }.disabled(submitting) }
                ToolbarItem(placement: .topBarTrailing) {
                    if createdOrder == nil {
                        Button(submitting ? "正在提交…" : "提交订单") { Task { await submit() } }
                            .disabled(submitting || !purchaseEnabled || recoveryBlocked || legacyRecoveryNeedsReconciliation || price == nil || (pendingAttempt == nil && !validPoints))
                    } else { Button("完成") { dismiss() } }
                }
            }
            .task(id: store.session?.accessToken) { await restoreAttempt(); await loadPoints() }
            .sheet(isPresented: $showOrders) { NativeDiningPackageOrdersView(store: store) }
        }
    }

    private var validPoints: Bool {
        guard let points, points >= 0, points <= maxPoints else { return false }
        return points == 0 || (pointsBalance != nil && pointsDebt == 0 && !pointsError)
    }

    @MainActor private func loadPoints() async {
        pointsBalance = nil; pointsDebt = nil; pointsError = false
        guard let token = store.session?.accessToken else { return }
        do {
            guard let summary = try await MobileAPI(store: store).get("/api/JHCTIMemberProgram/GetMySummary", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any],
                  let balanceText = nativeMemberLedgerString(summary, "PointsBalance"), let balance = Int64(balanceText), balance >= 0,
                  let debtText = nativeMemberLedgerString(summary, "PointsDebt"), let debt = Int64(debtText), debt >= 0,
                  store.session?.accessToken == token else { throw MobileAPIError.unavailable("积分摘要无效") }
            pointsBalance = debt > 0 ? 0 : balance; pointsDebt = debt
        } catch {
            guard store.session?.accessToken == token else { return }
            pointsError = true; pointsText = "0"
        }
    }

    @MainActor private func restoreAttempt() async {
        recoveryBlocked = false; legacyRecoveryNeedsReconciliation = false
        pendingAttempt = nil; createdOrder = nil; quantity = 1; pointsText = "0"; error = nil
        guard let token = store.session?.accessToken else { pendingAttempt = nil; return }
        let key = nativeTradeRecoveryStorageKey(accessToken: token) + ".dining-package.\(storeID).\(packageID)"
        let legacyKey = nativeLegacyTradeRecoveryStorageKey(accessToken: token) + ".dining-package.\(storeID).\(packageID)"
        let defaults = UserDefaults.standard
        let savedKey = [key, legacyKey].first { defaults.object(forKey: $0) != nil }
        guard let savedKey else { pendingAttempt = nil; return }
        let isLegacy = savedKey == legacyKey
        guard let attempt = defaults.dictionary(forKey: savedKey),
              let idempotencyKey = attempt["IdempotencyKey"] as? String,
              idempotencyKey.range(of: "^[A-Za-z0-9._:-]{16,100}$", options: .regularExpression) != nil,
              let savedQuantity = attempt["Quantity"] as? Int, (1...10).contains(savedQuantity),
              let savedPoints = attempt["PointsToUse"] as? String, let parsedPoints = Int64(savedPoints), parsedPoints >= 0,
              attempt["ExpectedAmountCents"] == nil
                || (attempt["ExpectedAmountCents"] as? String).flatMap(Int64.init).map({ $0 >= 0 }) == true else {
            pendingAttempt = nil
            recoveryBlocked = true
            error = "发现无法安全读取的团购订单恢复标记。为避免重复下单，请先核对本人团购券。"
            return
        }
        quantity = savedQuantity; pointsText = savedPoints; pendingAttempt = attempt
        if isLegacy {
            legacyRecoveryNeedsReconciliation = true
            do {
                let result = try await MobileAPI(store: store).get(
                    "/api/JHCTIDiningPackage/GetMyOrderByIdempotencyKey?idempotencyKey=\(idempotencyKey)", authenticated: true,
                    expectedPrincipal: nativeTourismPrincipal(token)
                ) as? [String: Any]
                guard store.session?.accessToken == token else { return }
                if let result, Self.string(result["PackageId"]) == packageID,
                   Self.string(result["StoreId"]) == storeID,
                   Int64(Self.string(result["Id"])).map({ $0 > 0 }) == true,
                   Self.int(result["Quantity"]) == savedQuantity,
                   Int64(Self.string(result["PointsUsed"])) == parsedPoints,
                   nativePointsOrderSnapshotMatches(
                    result,
                    expectedPoints: parsedPoints,
                    expectedAmountCents: (attempt["ExpectedAmountCents"] as? String).flatMap(Int64.init)
                   ) {
                    defaults.removeObject(forKey: key); defaults.removeObject(forKey: legacyKey)
                    pendingAttempt = nil; legacyRecoveryNeedsReconciliation = false; createdOrder = result
                } else {
                    error = "旧版订单恢复记录无法确认属于当前账号。为避免重复建单，已停止自动重试；请切换到可能下单的账号核对团购券，或联系平台处理。"
                }
            } catch {
                guard store.session?.accessToken == token else { return }
                self.error = "旧版订单恢复记录暂时无法核对，已停止自动重试以避免重复建单。请稍后刷新本人团购券，或联系平台处理。"
            }
        }
    }

    @MainActor private func submit() async {
        guard !submitting, createdOrder == nil, price != nil, let points,
              Int64(packageID).map({ $0 > 0 }) == true, Int64(storeID).map({ $0 > 0 }) == true,
              let token = store.session?.accessToken else {
            error = store.session?.accessToken == nil ? "请先登录文旅账号，再提交团购订单。" : "请确认套餐、数量和积分信息后重试。"
            return
        }
        guard !legacyRecoveryNeedsReconciliation else { error = "旧版订单恢复记录尚未核对，不能安全重试。"; return }
        guard pendingAttempt != nil || validPoints else { error = "积分余额尚未确认或积分数量超出本单上限。"; return }
        submitting = true; error = nil
        defer { submitting = false }
        let key = nativeTradeRecoveryStorageKey(accessToken: token) + ".dining-package.\(storeID).\(packageID)"
        let requestedQuantity = pendingAttempt?["Quantity"] as? Int ?? quantity
        let requestedPoints = (pendingAttempt?["PointsToUse"] as? String).flatMap(Int64.init) ?? points
        let savedExpectedAmountCents = (pendingAttempt?["ExpectedAmountCents"] as? String).flatMap(Int64.init)
        let expectedAmountCents = savedExpectedAmountCents
            ?? nativeMoneyCents(NSDecimalNumber(decimal: (price ?? 0) * Decimal(requestedQuantity)), roundToCents: true)
        guard expectedAmountCents != nil else {
            error = "套餐价格无法安全核对，请刷新后重试。"; return
        }
        submitting = true; error = nil
        defer { submitting = false }
        let latestPackagePurchaseEnabled = await MobileAPI(store: store).featureEnabled("F-FNB-007", forceRefresh: true)
        guard store.session?.accessToken == token else { error = "登录账号已变化，请重新确认后购买。"; return }
        guard latestPackagePurchaseEnabled else {
            purchaseEnabled = false
            error = "餐饮团购已关闭或暂时无法确认，本次没有创建订单。"
            return
        }
        purchaseEnabled = true
        let idempotencyKey = pendingAttempt?["IdempotencyKey"] as? String ?? UUID().uuidString
        if pendingAttempt != nil {
            guard let lookup = try? await MobileAPI(store: store).get(
                "/api/JHCTIDiningPackage/GetMyOrderByIdempotencyKey?idempotencyKey=\(idempotencyKey)", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)
            ) else {
                error = "上次团购订单暂时无法核对，未重复提交；请稍后重试或前往我的团购券查看。"
                return
            }
            guard store.session?.accessToken == token else { return }
            if let existing = lookup as? [String: Any] {
                guard Self.string(existing["PackageId"]) == packageID,
                      Self.string(existing["StoreId"]) == storeID,
                      Self.int(existing["Quantity"]) == requestedQuantity,
                      Int64(Self.string(existing["PointsUsed"])) == requestedPoints,
                      nativePointsOrderSnapshotMatches(existing, expectedPoints: requestedPoints, expectedAmountCents: expectedAmountCents) else {
                    error = "已找到上次团购订单，但订单快照与恢复记录不一致；请前往我的团购券核对。"
                    return
                }
                UserDefaults.standard.removeObject(forKey: key)
                pendingAttempt = nil
                createdOrder = existing
                return
            }
            guard lookup is NSNull else {
                if store.session?.accessToken == token { error = "上次团购订单暂时无法核对，未重复提交；请稍后重试或前往我的团购券查看。" }
                return
            }
        }
        guard await MobileAPI(store: store).featureEnabled("F-FNB-007", forceRefresh: true) else {
            error = "餐饮团购暂未开放，或暂时无法确认开放状态；本次未创建订单。"
            return
        }
        var attempt: [String: Any] = ["IdempotencyKey": idempotencyKey, "Quantity": requestedQuantity, "PointsToUse": String(requestedPoints)]
        if let expectedAmountCents { attempt["ExpectedAmountCents"] = String(expectedAmountCents) }
        UserDefaults.standard.set(attempt, forKey: key)
        guard UserDefaults.standard.dictionary(forKey: key)?["IdempotencyKey"] as? String == idempotencyKey else { error = "无法保存订单恢复编号，本次未提交。"; return }
        pendingAttempt = attempt
        do {
            guard let result = try await MobileAPI(store: store).post("/api/JHCTIDiningPackage/CreateOrder", body: [
                "IdempotencyKey": idempotencyKey, "PackageId": packageID, "StoreId": storeID,
                "Quantity": requestedQuantity, "PointsToUse": String(requestedPoints)
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any], store.session?.accessToken == token,
                  (result["PackageId"] as? String) == packageID, (result["StoreId"] as? String) == storeID,
                  (result["Quantity"] as? Int) == requestedQuantity,
                  (result["PointsUsed"] as? String).flatMap(Int64.init) == requestedPoints,
                  (result["Status"] as? String) == "PendingPayment",
                  nativePointsOrderSnapshotMatches(result, expectedPoints: requestedPoints, expectedAmountCents: expectedAmountCents) else {
                throw MobileAPIError.unavailable("订单回执无法核对；请前往我的团购券核对，不要重复下单。")
            }
            UserDefaults.standard.removeObject(forKey: key)
            pendingAttempt = nil
            createdOrder = result
        } catch {
            guard store.session?.accessToken == token else { return }
            if error.localizedDescription.contains("该请求号对应订单已失效") {
                UserDefaults.standard.removeObject(forKey: key); pendingAttempt = nil
                self.error = "原订单已失效，恢复编号已清除；请重新确认后创建新订单。"
            } else {
                self.error = "提交结果暂未确认：\(error.localizedDescription) 请先核对我的团购券，勿重复下单。"
            }
        }
    }

    private static func date(_ raw: Any?) -> String {
        guard let text = raw as? String, text.count >= 10 else { return "—" }
        return String(text.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }

    private static func string(_ value: Any?) -> String { (value as? String) ?? (value as? NSNumber)?.stringValue ?? "" }
    private static func int(_ value: Any?) -> Int? { (value as? Int) ?? (value as? NSNumber)?.intValue }
}

struct NativeDiningPackagePaymentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SessionStore
    let orderId: String
    @State private var order: [String: Any]?
    @State private var loading = false
    @State private var paying = false
    @State private var error: String?
    @State private var notice: String?
    @State private var revision = 0
    @State private var readSequence = 0
    @State private var reconciliationTask: Task<Void, Never>?
    @State private var pageVisible = true
    @State private var orderOwner = ""
    @State private var paymentWasLaunched = false

    private var amount: Double? {
        guard let raw = order?["CashPayableAmount"] ?? order?["Amount"],
              let value = (raw as? NSNumber)?.doubleValue ?? Double("\(raw)"),
              value.isFinite, value > 0 else { return nil }
        return value
    }
    private var deadline: Date? { paymentDeadline(order?["PaymentExpiresAt"]) }
    private var canPay: Bool {
        guard order?["Status"] as? String == "PendingPayment", amount != nil,
              (order?["Currency"] as? String ?? "CNY") == "CNY",
              let deadline, deadline > Date(), order?["Id"] as? String == orderId,
              Int64(orderId).map({ $0 > 0 }) == true,
              order?["HasUnmatchedPayment"] as? Bool != true,
              order?["HasUnavailablePayment"] as? Bool != true else { return false }
        let status = order?["ActivePaymentStatus"] as? String ?? ""
        let provider = (order?["ActivePaymentProvider"] as? String ?? "").lowercased()
        let scene = (order?["ActivePaymentScene"] as? String ?? "").lowercased()
        return status.isEmpty ? provider.isEmpty && scene.isEmpty
            : status == "RequiresAction" && provider == "alipay" && scene == "wap"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("团购订单支付").font(.system(size: NativeTypography.size(20), weight: .bold)).foregroundStyle(Brand.primary)
                        if let order {
                            Text(order["PackageName"] as? String ?? "餐饮团购套餐").font(.system(size: NativeTypography.size(15), weight: .semibold))
                            Text("订单号：\(order["OrderNo"] as? String ?? "—")").font(.system(size: NativeTypography.size(12))).textSelection(.enabled)
                            Text("订单状态：\(diningPaymentOrderStatus(order["Status"] as? String ?? ""))").font(.system(size: NativeTypography.size(12)))
                            Text("应付金额：\(order["Currency"] as? String ?? "CNY") \(amount.map { String(format: "%.2f", $0) } ?? "待确认")")
                                .font(.system(size: NativeTypography.size(20), weight: .bold)).foregroundStyle(Brand.ink)
                            Text("支付截止：\(deadline.map { packagePaymentDate($0) } ?? "待确认")").font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted)
                            if order["HasUnmatchedPayment"] as? Bool == true {
                                Text("渠道收款待核对。请勿再次支付，等待平台核对。")
                                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(.orange)
                            } else if order["Status"] as? String == "PendingPayment", !canPay {
                                Text(packagePaymentBlockNotice(order: order, deadline: deadline))
                                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    if loading && order == nil { ProgressView("正在读取本人订单…").frame(maxWidth: .infinity) }
                    if let error { Text(error).font(.system(size: NativeTypography.size(12))).foregroundStyle(.red) }
                    if let notice { Text(notice).font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.primary) }
                    Button(paying ? "正在准备支付宝…" : "使用支付宝支付") { Task { await pay() } }
                        .font(.system(size: NativeTypography.size(14), weight: .semibold)).frame(maxWidth: .infinity).padding(12)
                        .background(Brand.primary, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white)
                        .disabled(!canPay || loading || paying)
                    Button("查询订单状态") { revision += 1 }
                        .font(.system(size: NativeTypography.size(13), weight: .semibold)).frame(maxWidth: .infinity).padding(11)
                        .disabled(loading || paying)
                    Text("支付结果以服务端订单状态为准。返回应用后自动核对；结果待确认时不要重复付款。")
                        .font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted)
                }.padding(16)
            }
            .background(Brand.background)
            .navigationTitle("团购订单支付").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .task(id: revision) { if scenePhase == .active { await load() } }
            .onAppear { pageVisible = true }
            .onDisappear { pageVisible = false; invalidateRead() }
            .onChange(of: store.session?.accessToken) { _, _ in
                paymentWasLaunched = false; invalidateRead(); revision += 1
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { pageVisible = true; revision += 1 }
                else { pageVisible = false; invalidateRead() }
            }
        }
    }

    @MainActor private func invalidateRead() {
        readSequence += 1; reconciliationTask?.cancel(); reconciliationTask = nil
        order = nil; orderOwner = ""; loading = false; error = nil; notice = nil
    }

    @MainActor private func load() async {
        reconciliationTask?.cancel(); reconciliationTask = nil
        readSequence += 1
        let sequence = readSequence
        guard let token = store.session?.accessToken, !token.isEmpty,
              Int64(orderId).map({ $0 > 0 && String($0) == orderId }) == true else {
            order = nil; error = "订单编号无效或登录状态已失效，请返回我的团购券重新进入。"; return
        }
        func isCurrent() -> Bool {
            sequence == readSequence && pageVisible && scenePhase == .active
                && store.session?.accessToken == token
        }
        order = nil; orderOwner = ""
        loading = true; error = nil; notice = nil
        defer { if isCurrent() { loading = false } }
        do {
            guard let result = try await MobileAPI(store: store).get("/api/JHCTIDiningPackage/GetMyOrder?id=\(orderId)", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any],
                  isCurrent(), result["Id"] as? String == orderId else {
                throw MobileAPIError.unavailable("订单查询结果与当前订单不一致，请返回我的团购券重新打开。")
            }
            order = result; orderOwner = token; loading = false
            let pending: ([String: Any]) -> Bool = {
                nativeDiningPackagePaymentNeedsReconciliation($0, afterPaymentLaunch: paymentWasLaunched)
            }
            if pending(result) { notice = "正在核对服务端订单状态，请勿重复付款。" }
            reconciliationTask = Task { @MainActor in
                await reconcileNativePaymentOrder(initial: result, orderID: orderId, read: {
                    guard let value = try await MobileAPI(store: store).get("/api/JHCTIDiningPackage/GetMyOrder?id=\(orderId)", authenticated: true,
                        expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any]
                    else { throw MobileAPIError.unavailable("团购订单详情格式异常") }
                    return value
                }, isCurrent: isCurrent, apply: { value in
                    order = value; self.error = nil
                    if !pending(value) {
                        paymentWasLaunched = false
                        notice = "订单当前状态：\(diningPaymentOrderStatus(value["Status"] as? String ?? ""))，请以订单记录为准。"
                    }
                }, exhausted: {
                    notice = "自动核对已暂停，请手动查询最新订单状态；若已付款，请勿重复支付。"
                }, invalid: {
                    order = nil; orderOwner = ""
                    self.error = "订单查询结果与当前订单不一致，请返回我的团购券重新打开。"
                }, pending: pending)
            }
        } catch {
            if isCurrent() { self.error = error.localizedDescription }
        }
    }

    @MainActor private func pay() async {
        guard canPay, !paying, pageVisible, scenePhase == .active,
              orderOwner == store.session?.accessToken, let token = store.session?.accessToken else { return }
        let launchDeadline = order?["PaymentExpiresAt"]
        readSequence += 1
        let sequence = readSequence
        reconciliationTask?.cancel(); reconciliationTask = nil
        paying = true; error = nil; notice = nil
        defer {
            paying = false
            if sequence == readSequence && store.session?.accessToken == token && pageVisible && scenePhase == .active { revision += 1 }
        }
        do {
            guard let payment = try await MobileAPI(store: store).post("/api/JHCTIDiningPackage/CreateOrderPayment", body: [
                "OrderId": orderId, "Provider": "alipay", "Scene": "wap"
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any],
                  sequence == readSequence, store.session?.accessToken == token,
                  pageVisible, scenePhase == .active else {
                throw MobileAPIError.unavailable("支付回执无效或登录账号已变化，请查询订单状态。")
            }
            guard payment["Provider"] as? String == "alipay", payment["Status"] as? String == "RequiresAction",
                  let recordId = payment["PaymentRecordId"] as? String, Int64(recordId).map({ $0 > 0 }) == true,
                  let paymentAmount = (payment["Amount"] as? NSNumber)?.doubleValue,
                  paymentAmount.isFinite, abs(paymentAmount - (amount ?? -1)) < 0.005,
                  payment["Currency"] as? String == "CNY",
                  let rawURL = payment["ApprovalUrl"] as? String, let url = URL(string: rawURL),
                  url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil else {
                throw MobileAPIError.unavailable("支付状态或渠道回执无法核对；请查询订单，勿重复支付。")
            }
            try requireNativePaymentLaunchDeadline(launchDeadline)
            paymentWasLaunched = true
            let opened = await withCheckedContinuation { continuation in openURL(url) { continuation.resume(returning: $0) } }
            guard opened else { paymentWasLaunched = false; throw MobileAPIError.unavailable("设备未能打开支付页面，请查询订单状态后再继续。") }
            if sequence == readSequence && store.session?.accessToken == token && pageVisible && scenePhase == .active {
                notice = "已打开支付宝支付页面。返回应用后将自动核对服务端订单状态。"
            }
        } catch is CancellationError {
            if sequence == readSequence && store.session?.accessToken == token && pageVisible && scenePhase == .active {
                paymentWasLaunched = false
            }
        } catch {
            if sequence == readSequence && store.session?.accessToken == token && pageVisible && scenePhase == .active {
                paymentWasLaunched = false; self.error = error.localizedDescription
            }
        }
    }
}

private func packagePaymentDate(_ value: Date) -> String {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: value)
}

private func diningPaymentOrderStatus(_ value: String) -> String {
    ["PendingPayment": "待付款", "Paid": "已付款", "Closed": "已关闭", "Refunded": "已退款"][value] ?? "状态待核对"
}

private func packagePaymentBlockNotice(order: [String: Any], deadline: Date?) -> String {
    if (order["Currency"] as? String ?? "CNY") != "CNY" { return "当前团购订单币种不支持在线支付，请联系平台核对。" }
    if order["HasUnavailablePayment"] as? Bool == true { return "支付记录关联异常，已暂停支付；请联系平台核对。" }
    guard let deadline else { return "支付期限暂不可确认，请刷新订单后再操作。" }
    if deadline <= Date() { return "支付期限已过，请刷新订单状态。" }
    switch order["ActivePaymentStatus"] as? String ?? "" {
    case "Creating", "Unknown", "Processing": return "原支付结果仍在确认，请勿重复付款；请刷新订单核对。"
    case "RequiresAction": return "当前支付尝试不是支付宝网页支付，请勿重复付款；请刷新订单核对。"
    default: return "当前订单暂不可发起支付，请刷新本人订单状态。"
    }
}
