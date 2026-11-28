import SwiftUI

struct NativeDiningPackageOrdersView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var recovery = NativeDiningPackageRefundRecovery()
    @State private var rows = [[String: Any]]()
    @State private var revealed = Set<String>()
    @State private var refundCredential: [String: Any]?
    @State private var refundOrder: [String: Any]?
    @State private var refundReason = ""
    @State private var refunds: [[String: Any]] = []
    @State private var refundsOrderNo = ""
    @State private var paymentOrderID = ""
    @State private var page = 1
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var notice: String?
    @State private var revision = 0
    @State private var requestSequence = 0
    @State private var refundRequestSequence = 0
    @State private var visible = false
    private let pageSize = 20
    private var busy: Bool { recovery.busy }
    private var principal: String? { nativeTourismPrincipal(store.session?.accessToken) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if recovery.attempts?.isEmpty == false || recovery.message != nil || !rows.isEmpty {
                    List {
                        refundRecoverySection
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, order in orderCard(order) }
                        if rows.count < total {
                            Button(loading ? "正在加载…" : "加载更多") { Task { await load(reset: false) } }
                                .frame(maxWidth: .infinity).disabled(loading)
                        }
                    }.listStyle(.plain)
                } else if loading { ProgressView("正在读取团购订单…") }
                else if let error, rows.isEmpty {
                    ContentUnavailableView(error, systemImage: "exclamationmark.arrow.circlepath", description: Text("检查登录状态后重试。"))
                } else {
                    ContentUnavailableView("暂无团购订单", systemImage: "ticket", description: Text("购买的套餐、凭证和退款状态会显示在这里。"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.background)
            .navigationTitle("我的团购券")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("刷新") { revision += 1 }.disabled(loading || busy) }
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .onAppear { visible = true }
            .task(id: "\(store.session?.accessToken ?? "")-\(revision)") {
                if scenePhase == .active { recovery.reload(store: store) }
                await load(reset: true)
            }
            .onChange(of: principal) { _, _ in
                rows = []; revealed = []; total = 0; page = 1; error = nil; notice = nil; paymentOrderID = ""
                invalidateRefunds()
                if scenePhase == .active { recovery.reload(store: store) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { recovery.reload(store: store) }
                else { invalidateRefunds() }
            }
            .onDisappear {
                visible = false
                requestSequence += 1; rows = []; revealed = []
                invalidateRefunds()
            }
            .sheet(item: Binding(
                get: { refundCredential.map { RefundCredentialItem(value: $0) } },
                set: { if $0 == nil { refundCredential = nil; refundOrder = nil; refundReason = "" } }
            )) { item in refundSheet(item.value) }
            .sheet(isPresented: Binding(get: { !refundsOrderNo.isEmpty }, set: { if !$0 { refundRequestSequence += 1; refundsOrderNo = ""; refunds = [] } })) {
                NavigationStack {
                    List(Array(refunds.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(row["RefundNo"] as? String ?? "退款记录") · \(refundStatus(row["Status"] as? String ?? ""))")
                            Text("\(row["PackageName"] as? String ?? "团购套餐") · \(money(row["Amount"]))")
                                .font(.caption).foregroundStyle(Brand.muted)
                            if let reason = row["Reason"] as? String, !reason.isEmpty { Text("原因：\(reason)").font(.caption) }
                        }.padding(.vertical, 4)
                    }
                    .navigationTitle("退款记录")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { refundRequestSequence += 1; refundsOrderNo = ""; refunds = [] } } }
                    .overlay { if refunds.isEmpty { ContentUnavailableView("暂无退款记录", systemImage: "arrow.uturn.backward") } }
                }
            }
            .sheet(isPresented: Binding(get: { !paymentOrderID.isEmpty }, set: { if !$0 { paymentOrderID = "" } }), onDismiss: {
                revision += 1
            }) {
                NativeDiningPackagePaymentView(store: store, orderId: paymentOrderID)
            }
            .alert("服务提示", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("知道了") { notice = nil }
            } message: { Text(notice ?? "") }
        }
    }

    private func invalidateRefunds() {
        recovery.invalidate()
        refundRequestSequence += 1
        refunds = []; refundsOrderNo = ""; refundCredential = nil; refundOrder = nil; refundReason = ""; notice = nil
    }

    @ViewBuilder private var refundRecoverySection: some View {
        if let message = recovery.message { Text(message).font(.callout) }
        if let attempts = recovery.attempts {
            if !attempts.isEmpty {
                Section("待核对退款申请") {
                    ForEach(attempts) { attempt in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("订单编号 \(attempt.orderID)").font(.callout)
                            Text("原申请号 \(attempt.requestID)").font(.caption).foregroundStyle(Brand.muted).textSelection(.enabled)
                            Button("查询原申请") { Task { await lookupRefund(attempt, release: false) } }.buttonStyle(.borderless)
                            if recovery.missingRequestID == attempt.requestID {
                                Text("暂未查到原申请。请先核对该订单的退款记录，再复查一次。").font(.caption)
                                Button("查看退款记录") {
                                    Task { await loadRefunds(orderID: attempt.orderID, orderNo: attempt.orderID) }
                                }.buttonStyle(.borderless)
                                Button("已核对退款记录，复查原申请") {
                                    Task { await lookupRefund(attempt, release: true) }
                                }.buttonStyle(.borderless)
                            }
                        }.disabled(busy || scenePhase != .active)
                    }
                }
            }
        } else if !rows.isEmpty && scenePhase == .active {
            Text("暂时无法读取退款待核对记录，请刷新后再试。").font(.caption)
        }
    }

    private func orderCard(_ order: [String: Any]) -> some View {
        let orderID = order["Id"] as? String ?? ""
        let status = order["Status"] as? String ?? ""
        let credentials = order["Credentials"] as? [[String: Any]] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(order["PackageName"] as? String ?? "餐饮团购套餐").font(.system(size: NativeTypography.size(16), weight: .semibold))
                Spacer(); Text(orderStatus(status)).font(.caption.weight(.semibold)).foregroundStyle(Brand.primary)
            }
            Text("订单号：\(order["OrderNo"] as? String ?? "—")").font(.caption).textSelection(.enabled)
            Text("金额：\(money(order["Amount"])) · 数量：\(order["Quantity"] as? Int ?? 0)").font(.caption)
            if order["HasUnmatchedPayment"] as? Bool == true {
                Text("渠道收款待核对。请勿再次支付或重复下单，等待平台核对。")
                    .font(.caption).foregroundStyle(.orange)
            }
            if status == "PendingPayment" {
                Text("支付截止：\(date(order["PaymentExpiresAt"])) · 现金应付：\(money(order["CashPayableAmount"] ?? order["Amount"]))")
                    .font(.caption).foregroundStyle(Brand.muted)
                if canContinueAlipayPayment(order) {
                    Button("查看团购支付页") { paymentOrderID = orderID }
                        .font(.caption.weight(.semibold)).disabled(busy)
                } else {
                    Text(paymentStatusNotice(order)).font(.caption).foregroundStyle(.orange)
                }
            }
            ForEach(Array(credentials.enumerated()), id: \.offset) { _, credential in
                credentialRow(order: order, credential: credential)
            }
            Button("查看退款记录") { Task { await loadRefunds(orderID: orderID, orderNo: order["OrderNo"] as? String ?? "") } }
                .font(.caption)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder private func credentialRow(order: [String: Any], credential: [String: Any]) -> some View {
        let id = credential["Id"] as? String ?? ""
        let state = credential["Status"] as? String ?? ""
        VStack(alignment: .leading, spacing: 5) {
            Text("凭证 · \(credentialStatus(state))").font(.caption.weight(.semibold))
            Text("有效期：\(date(credential["ValidFrom"])) 至 \(date(credential["ValidUntil"]))").font(.caption2).foregroundStyle(Brand.muted)
            Text("本凭证对应一整套套餐，整套仅核销一次，不支持拆分核销。")
                .font(.caption2).foregroundStyle(Brand.muted)
            if revealed.contains(id) {
                Text(credential["Code"] as? String ?? "凭证码暂不可用").font(.caption.monospaced()).textSelection(.enabled)
                Button("隐藏凭证码") { revealed.remove(id) }.font(.caption)
            } else {
                Button("显示凭证码") { revealed.insert(id) }.font(.caption)
            }
            if state == "Active", (order["Status"] as? String) == "Paid",
               order["HasUnavailablePayment"] as? Bool != true, order["HasUnmatchedPayment"] as? Bool != true,
               recovery.attempts?.contains(where: { $0.credentialID == id }) == false {
                Button("申请退款") { refundOrder = order; refundCredential = credential; refundReason = "" }
                    .font(.caption).foregroundStyle(.red).disabled(busy || loading || scenePhase != .active)
            }
        }
        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.background, in: RoundedRectangle(cornerRadius: 9))
    }

    private func refundSheet(_ credential: [String: Any]) -> some View {
        NavigationStack {
            Form {
                Text("退款将针对这一张未使用凭证提交，是否通过及退款金额以平台审核和原支付渠道结果为准。")
                    .font(.caption).foregroundStyle(Brand.muted)
                TextField("请填写退款原因", text: $refundReason, axis: .vertical).lineLimit(3...6)
                if let error { Text(error).foregroundStyle(.red) }
                if let message = recovery.message { Text(message).foregroundStyle(.red) }
                Button(busy ? "正在提交…" : "提交退款申请") { Task { await submitRefund(credential) } }
                    .disabled(busy || scenePhase != .active || refundReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            }
            .navigationTitle("申请团购券退款")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { refundCredential = nil; refundOrder = nil } } }
        }
    }

    private func load(reset: Bool) async {
        guard let token = store.session?.accessToken, !token.isEmpty else {
            rows = []; total = 0; error = "请先登录文旅账号，再查看团购订单。"; return
        }
        let requestedPrincipal = MobileAPI(store: store).nativeTourismPrincipal(token)
        let sequence = requestSequence + 1; requestSequence = sequence
        let targetPage = reset ? 1 : page + 1
        loading = true; error = nil
        if reset { rows = []; total = 0; page = 1; revealed = [] }
        defer { if sequence == requestSequence { loading = false } }
        do {
            let response = try await MobileAPI(store: store).get("/api/JHCTIDiningPackage/GetMyOrderPage?page=\(targetPage)&pageSize=\(pageSize)", authenticated: true, expectedPrincipal: requestedPrincipal)
            try Task.checkCancellation()
            guard sequence == requestSequence, store.session?.accessToken == token else { return }
            guard let parsed = validatedDiningPackageOrderPage(response, page: targetPage, pageSize: pageSize) else {
                throw MobileAPIError.unavailable("团购订单分页回执或订单内容无效，请刷新后重试")
            }
            rows = reset ? parsed.rows : rows + parsed.rows
            total = parsed.total
            page = targetPage
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled, sequence == requestSequence, store.session?.accessToken == token {
                self.error = error.localizedDescription
            }
        }
    }

    private func submitRefund(_ credential: [String: Any]) async {
        guard visible, !busy, !loading, scenePhase == .active, let order = refundOrder,
              let orderID = order["Id"] as? String, let credentialID = credential["Id"] as? String,
              refundCredential?["Id"] as? String == credentialID,
              credential["Status"] as? String == "Active", order["Status"] as? String == "Paid",
              order["HasUnavailablePayment"] as? Bool != true, order["HasUnmatchedPayment"] as? Bool != true else { return }
        let reason = refundReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...500).contains(reason.utf16.count) else { error = "退款原因需为 2 至 500 个字符"; return }
        error = nil
        let attempt = NativeDiningRefundAttempt(orderID: orderID, credentialID: credentialID)
        if await recovery.submit(attempt, reason: reason, store: store, onDispatched: {
            refundCredential = nil; refundOrder = nil; refundReason = ""
        }) {
            revision += 1
        }
    }

    private func lookupRefund(_ attempt: NativeDiningRefundAttempt, release: Bool) async {
        guard visible, scenePhase == .active else { return }
        if await recovery.lookup(attempt, release: release, store: store) { revision += 1 }
    }

    private func canContinueAlipayPayment(_ order: [String: Any]) -> Bool {
        guard order["Status"] as? String == "PendingPayment",
              order["HasUnmatchedPayment"] as? Bool != true,
              order["HasUnavailablePayment"] as? Bool != true,
              let expires = paymentDeadline(order["PaymentExpiresAt"]), expires > Date() else { return false }
        let status = order["ActivePaymentStatus"] as? String ?? ""
        let provider = (order["ActivePaymentProvider"] as? String ?? "").lowercased()
        let scene = (order["ActivePaymentScene"] as? String ?? "").lowercased()
        if status.isEmpty { return provider.isEmpty && scene.isEmpty }
        return status == "RequiresAction" && provider == "alipay" && scene == "wap"
    }

    private func paymentStatusNotice(_ order: [String: Any]) -> String {
        if order["HasUnavailablePayment"] as? Bool == true { return "支付记录关联异常，已暂停支付；请联系平台核对。" }
        if order["HasUnmatchedPayment"] as? Bool == true { return "渠道收款待核对，请勿重复支付；等待平台处理。" }
        if paymentDeadline(order["PaymentExpiresAt"]) == nil { return "支付期限暂不可确认，请刷新订单后再操作。" }
        if let expires = paymentDeadline(order["PaymentExpiresAt"]), expires <= Date() { return "支付期限已过，请刷新订单状态。" }
        let status = order["ActivePaymentStatus"] as? String ?? ""
        if status == "Creating" || status == "Unknown" || status == "Processing" { return "原支付结果仍在确认，请勿重复付款；请刷新订单核对。" }
        if !status.isEmpty { return "当前支付尝试不是可续办的支付宝网页支付，请勿重复付款；请刷新订单核对。" }
        return "当前订单暂不可发起支付，请刷新本人订单状态。"
    }

    private func loadRefunds(orderID: String, orderNo: String) async {
        guard visible, scenePhase == .active, trackingID(orderID), let token = store.session?.accessToken else { return }
        let requestedPrincipal = MobileAPI(store: store).nativeTourismPrincipal(token)
        refundRequestSequence += 1
        let sequence = refundRequestSequence
        do {
            let response = try await MobileAPI(store: store).get("/api/JHCTIDiningPackage/GetMyRefunds?orderId=\(orderID)", authenticated: true, expectedPrincipal: requestedPrincipal)
            try Task.checkCancellation()
            guard refundRequestSequence == sequence, store.session?.accessToken == token else { return }
            guard let validated = validatedDiningPackageRefunds(response, expectedOrderID: orderID) else {
                throw MobileAPIError.unavailable("团购退款记录无效或与当前订单不匹配，请刷新后重试。")
            }
            refunds = validated
            refundsOrderNo = orderNo
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled, refundRequestSequence == sequence, store.session?.accessToken == token {
                notice = error.localizedDescription
            }
        }
    }

    private func money(_ value: Any?) -> String {
        guard let number = value as? NSNumber, number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 1_000_000 else { return "金额待确认" }
        return String(format: "¥%.2f", number.doubleValue)
    }
    private func date(_ value: Any?) -> String { String((value as? String ?? "").prefix(10)).isEmpty ? "—" : String((value as? String ?? "").prefix(10)) }
    private func orderStatus(_ value: String) -> String { ["PendingPayment":"待支付", "Paid":"已付款", "Closed":"已关闭", "Refunded":"已退款"][value] ?? "状态待确认" }
    private func credentialStatus(_ value: String) -> String { ["Active":"可使用", "Redeemed":"已核销", "RefundPending":"退款审核中", "Refunded":"已退款", "Expired":"已过期"][value] ?? "状态待确认" }
    private func refundStatus(_ value: String) -> String { nativeDiningRefundStatus(value) }
}


private struct RefundCredentialItem: Identifiable {
    let value: [String: Any]
    var id: String { value["Id"] as? String ?? UUID().uuidString }
}
