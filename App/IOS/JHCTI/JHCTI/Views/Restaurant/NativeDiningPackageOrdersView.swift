import SwiftUI

struct NativeDiningPackageOrdersView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
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
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var revision = 0
    @State private var requestSequence = 0
    @State private var refundRequestSequence = 0
    @State private var refundSubmissionSequence = 0
    private let pageSize = 20

    var body: some View {
        NavigationStack {
            Group {
                if loading && rows.isEmpty { ProgressView("正在读取团购订单…") }
                else if let error, rows.isEmpty {
                    ContentUnavailableView(error, systemImage: "exclamationmark.arrow.circlepath", description: Text("检查登录状态后重试。"))
                } else if rows.isEmpty {
                    ContentUnavailableView("暂无团购订单", systemImage: "ticket", description: Text("购买的套餐、凭证和退款状态会显示在这里。"))
                } else {
                    List {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, order in orderCard(order) }
                        if rows.count < total {
                            Button(loading ? "正在加载…" : "加载更多") { Task { await load(reset: false) } }
                                .frame(maxWidth: .infinity).disabled(loading)
                        }
                    }.listStyle(.plain)
                }
            }
            .background(Brand.background)
            .navigationTitle("我的团购券")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("刷新") { revision += 1 }.disabled(loading || busy) }
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .task(id: "\(store.session?.accessToken ?? "")-\(revision)") { await load(reset: true) }
            .onChange(of: store.session?.accessToken) { _, _ in
                requestSequence += 1; refundRequestSequence += 1; refundSubmissionSequence += 1
                busy = false; rows = []; revealed = []; refunds = []; refundCredential = nil
                refundOrder = nil; refundReason = ""; total = 0; page = 1; error = nil; notice = nil
            }
            .onDisappear { requestSequence += 1; refundRequestSequence += 1; refundSubmissionSequence += 1; rows = []; revealed = []; refunds = [] }
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
            if state == "Active", (order["Status"] as? String) == "Paid" {
                Button("申请退款") { refundOrder = order; refundCredential = credential; refundReason = "" }
                    .font(.caption).foregroundStyle(.red).disabled(busy)
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
                Button(busy ? "正在提交…" : "提交退款申请") { Task { await submitRefund(credential) } }
                    .disabled(busy || refundReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
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
            guard let data = response as? [String: Any],
                  let list = data["data"] as? [[String: Any]] ?? data["Data"] as? [[String: Any]]
                    ?? data["Items"] as? [[String: Any]] ?? data["items"] as? [[String: Any]] else {
                throw MobileAPIError.unavailable("团购订单响应格式异常")
            }
            guard let responsePage = data["page"] as? Int ?? data["Page"] as? Int,
                  responsePage == targetPage,
                  let responseSize = data["PageSize"] as? Int ?? data["pageSize"] as? Int,
                  responseSize == pageSize,
                  let count = data["dataCount"] as? Int ?? data["DataCount"] as? Int,
                  count >= 0, list.count <= pageSize,
                  list.allSatisfy({ (Int64($0["Id"] as? String ?? "") ?? 0) > 0 }),
                  Set(list.compactMap { $0["Id"] as? String }).count == list.count else {
                throw MobileAPIError.unavailable("团购订单分页回执无效")
            }
            rows = reset ? list : rows + list
            total = count
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
        guard !busy, let token = store.session?.accessToken, let order = refundOrder,
              let orderID = order["Id"] as? String, let credentialID = credential["Id"] as? String else { return }
        let requestedPrincipal = MobileAPI(store: store).nativeTourismPrincipal(token)
        let reason = refundReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count >= 2, reason.count <= 500 else { error = "退款原因需为 2 至 500 个字符"; return }
        refundSubmissionSequence += 1
        let sequence = refundSubmissionSequence
        busy = true; error = nil
        defer { if sequence == refundSubmissionSequence { busy = false } }
        do {
            _ = try await MobileAPI(store: store).post("/api/JHCTIDiningPackage/RequestRefund", body: ["OrderId": orderID, "CredentialIds": [credentialID], "Reason": reason], authenticated: true, expectedPrincipal: requestedPrincipal)
            guard store.session?.accessToken == token else { return }
            refundCredential = nil; refundOrder = nil; refundReason = ""; notice = "退款申请已提交，处理状态以订单退款记录为准。"
            revision += 1
        } catch is CancellationError {
            if store.session?.accessToken == token {
                self.error = "退款申请结果未确认。请先刷新团购订单并查看退款记录，确认前不要重复提交。"
            }
        } catch {
            if store.session?.accessToken == token { self.error = error.localizedDescription }
        }
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
        guard !orderID.isEmpty, let token = store.session?.accessToken else { return }
        let requestedPrincipal = MobileAPI(store: store).nativeTourismPrincipal(token)
        refundRequestSequence += 1
        let sequence = refundRequestSequence
        do {
            let response = try await MobileAPI(store: store).get("/api/JHCTIDiningPackage/GetMyRefunds?orderId=\(orderID)", authenticated: true, expectedPrincipal: requestedPrincipal)
            try Task.checkCancellation()
            guard refundRequestSequence == sequence, store.session?.accessToken == token else { return }
            refunds = response as? [[String: Any]] ?? []
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
    private func refundStatus(_ value: String) -> String { ["Requested":"待审核", "Processing":"退款处理中", "Refunded":"已退款", "Rejected":"未通过", "Failed":"退款失败"][value] ?? "状态待确认" }
}


private struct RefundCredentialItem: Identifiable {
    let value: [String: Any]
    var id: String { value["Id"] as? String ?? UUID().uuidString }
}
