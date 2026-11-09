import SwiftUI

struct NativeTicketOrdersView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var rows: [[String: Any]] = []
    @State private var selectedOrder: [String: Any]?
    @State private var status = ""
    @State private var page = 1
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var revealedCodes: Set<String> = []
    @State private var credentialClockNow = Date()
    @State private var requestSequence = 0
    @State private var pendingCancelOrder: [String: Any]?
    @State private var refundCandidates: [[String: Any]] = []
    @State private var refundOrderId = ""
    @State private var refundSelectedIds: Set<String> = []
    @State private var refundReason = ""
    @State private var refundSheetOpen = false
    @State private var operationBusy = false
    @State private var operationNotice: String?
    @State private var paymentNotice: String?
    @State private var detailID = ""
    @State private var detailOwner = ""
    @State private var pageVisible = true
    @State private var resumeRevision = 0
    @State private var operationSequence = 0
    @State private var reconciliationTask: Task<Void, Never>?
    @State private var detailReadTask: Task<Void, Never>?
    @State private var reconciliationNotice: String?
    private let filters = [("", "全部"), ("PendingPayment", "待支付"), ("PaidPendingIssue", "待出票"),
        ("Issued", "已出票"), ("PaidIssueFailed", "出票异常"), ("PartiallyRefunded", "部分退款"),
        ("Refunded", "已退款"), ("Closed", "已关闭")]

    var body: some View {
        NavigationStack {
            Group {
                if let selectedOrder { orderDetail(selectedOrder) }
                else if !detailID.isEmpty {
                    VStack(spacing: 12) {
                        if loading { ProgressView("正在读取门票订单…") }
                        if let error { Text(error).foregroundStyle(.red) }
                        Button("重新查询订单") { openTicketOrder(id: detailID) }.disabled(loading)
                    }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { orderList }
            }
            .background(Brand.background)
            .navigationTitle(detailID.isEmpty ? "我的门票订单" : "门票订单详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !detailID.isEmpty { Button("返回") { leaveDetail() } }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .task(id: "\(store.session?.accessToken ?? "")-\(status)-\(resumeRevision)") {
                if scenePhase == .active && pageVisible {
                    if detailID.isEmpty { await loadOrders(reset: true) } else { await loadOrder(id: detailID) }
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active && pageVisible else { return }
                while !Task.isCancelled {
                    credentialClockNow = Date()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            .confirmationDialog("取消未支付门票订单？", isPresented: Binding(
                get: { pendingCancelOrder != nil }, set: { if !$0 { pendingCancelOrder = nil } }
            ), titleVisibility: .visible) {
                Button("确认取消订单", role: .destructive) {
                    guard let order = pendingCancelOrder else { return }
                    pendingCancelOrder = nil
                    Task { await cancelPendingOrder(order) }
                }
                Button("暂不取消", role: .cancel) { pendingCancelOrder = nil }
            } message: {
                Text("仅取消尚未支付的订单。支付状态不确定或渠道已收款待核对时，请先刷新订单。")
            }
            .sheet(isPresented: $refundSheetOpen) { refundApplicationSheet }
            .onChange(of: store.session?.accessToken) { _, _ in
                detailReadTask?.cancel(); detailReadTask = nil
                reconciliationTask?.cancel(); detailID = ""; detailOwner = ""; reconciliationNotice = nil; operationSequence += 1
                requestSequence += 1; rows = []; selectedOrder = nil; total = 0; page = 1
                revealedCodes = []; error = nil; loading = false; pendingCancelOrder = nil
                refundSheetOpen = false; refundCandidates = []; refundSelectedIds = []; refundOrderId = ""
                refundReason = ""; operationBusy = false; operationNotice = nil; paymentNotice = nil
            }
            .onAppear { pageVisible = true }
            .onDisappear { pageVisible = false; invalidateTicketRead() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { resumeRevision += 1 } else { invalidateTicketRead() }
            }
        }
    }

    private func leaveDetail() {
        invalidateTicketRead(); detailID = ""; operationNotice = nil; resumeRevision += 1
    }

    private func invalidateTicketRead() {
        detailReadTask?.cancel(); detailReadTask = nil
        requestSequence += 1; reconciliationTask?.cancel(); rows = []; selectedOrder = nil; detailOwner = ""
        revealedCodes = []; loading = false; error = nil; paymentNotice = nil; reconciliationNotice = nil
        pendingCancelOrder = nil; refundSheetOpen = false; refundCandidates = []; refundSelectedIds = []; refundReason = ""
    }

    private var orderList: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(filters, id: \.0) { filter in
                        Button(filter.1) { status = filter.0 }
                            .font(.system(size: NativeTypography.size(14), weight: .semibold))
                            .foregroundStyle(status == filter.0 ? .white : Brand.primary)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .background(status == filter.0 ? Brand.primary : .white, in: Capsule()).buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 10)
            }
            if loading && rows.isEmpty { ProgressView("正在读取门票订单…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error, rows.isEmpty { ContentUnavailableView(error, systemImage: "exclamationmark.arrow.circlepath", description: Text("检查登录状态后重试。")) }
            else if rows.isEmpty { ContentUnavailableView("暂无门票订单", systemImage: "ticket", description: Text("购票订单和有效入园凭证会显示在这里。")) }
            else {
                List {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, order in
                        Button { operationNotice = nil; openTicketOrder(id: order["Id"] as? String ?? "") } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(order["OrderNo"] as? String ?? "门票订单").font(.system(size: NativeTypography.size(14), weight: .semibold))
                                    Spacer(); Text(ticketStatus(order["Status"] as? String ?? "")).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                                }
                                let lines = order["Lines"] as? [[String: Any]] ?? []
                                Text(lines.prefix(2).map { "\($0["TicketName"] as? String ?? "门票") × \($0["Quantity"] as? Int ?? 1)" }.joined(separator: "、"))
                                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink).lineLimit(2)
                                Text("\(order["Currency"] as? String ?? "CNY") \(ticketMoney(order["Amount"])) · \(order["CreateTime"] as? String ?? "")")
                                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                            }.padding(.vertical, 4)
                        }.buttonStyle(.plain)
                    }
                    if rows.count < total {
                        Button(loading ? "正在加载…" : "加载更多") { Task { await loadOrders(reset: false) } }
                            .frame(maxWidth: .infinity).disabled(loading)
                    }
                }.listStyle(.plain)
            }
            if let error, !rows.isEmpty { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red).padding(8) }
        }
    }

    private func orderDetail(_ order: [String: Any]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(order["OrderNo"] as? String ?? "门票订单").font(.system(size: NativeTypography.size(16), weight: .bold))
                    Text("状态：\(ticketStatus(order["Status"] as? String ?? ""))")
                    Text("金额：\(order["Currency"] as? String ?? "CNY") \(ticketMoney(order["CashPayableAmount"] ?? order["Amount"]))")
                }.font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink).padding(13).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 11))
                ticketPaymentAction(order)
                if let reconciliationNotice { Text(reconciliationNotice).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary) }
                ForEach(Array((order["Lines"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(line["TicketName"] as? String ?? "门票") × \(line["Quantity"] as? Int ?? 1)")
                            .font(.system(size: NativeTypography.size(14), weight: .semibold))
                        Text("\(line["SessionName"] as? String ?? "场次") · \(line["SessionStartTime"] as? String ?? "")")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        if line["TicketKind"] as? String == "Bundle" {
                            let bundleItems = line["BundleItems"] as? [[String: Any]] ?? []
                            if bundleItems.isEmpty {
                                Text("套票项目快照缺失，需人工核对")
                                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(.orange)
                            } else {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("套票包含项目 · 一张凭证一次核销全部项目")
                                        .font(.system(size: NativeTypography.size(12), weight: .semibold))
                                    ForEach(Array(bundleItems.enumerated()), id: \.offset) { _, item in
                                        let name = item["Name"] as? String ?? "项目"
                                        let quantity = item["Quantity"] as? Int ?? 1
                                        let description = item["Description"] as? String ?? ""
                                        Text("\(name) × \(quantity)\(description.isEmpty ? "" : " · \(description)")")
                                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                    }
                                }
                            }
                        }
                        ForEach(Array((line["Credentials"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, credential in
                            let id = credential["Id"] as? String ?? ""
                            let code = credential["Code"] as? String ?? ""
                            let credentialStatus = credential["Status"] as? String ?? ""
                            let validUntil = nativeTicketCredentialValidUntil(credential["ValidUntil"])
                            let expired = credentialStatus == "Active" && validUntil.map { credentialClockNow >= $0 } == true
                            let credentialStatusText = credentialStatus == "Active" && validUntil == nil
                                ? "有效期待核对" : expired ? "已过期" : ticketCredentialStatus(credentialStatus)
                            let canShowCode = credentialStatus == "Active" && validUntil.map { credentialClockNow < $0 } == true
                                && !code.isEmpty
                            VStack(alignment: .leading, spacing: 5) {
                                let bundleItems = line["BundleItems"] as? [[String: Any]] ?? []
                                let redemptions = credential["BundleRedemptions"] as? [[String: Any]] ?? []
                                let partiallyRedeemed = line["TicketKind"] as? String == "Bundle"
                                    && credential["Status"] as? String == "Active"
                                    && !redemptions.isEmpty && redemptions.count < bundleItems.count
                                Text("凭证 · \(partiallyRedeemed ? "历史逐项核销，需人工核对" : credentialStatusText)")
                                    .font(.system(size: NativeTypography.size(14), weight: .medium))
                                    .foregroundStyle(partiallyRedeemed ? .orange : Brand.primary)
                                if line["TicketKind"] as? String == "Bundle" {
                                    ForEach(Array(bundleItems.enumerated()), id: \.offset) { itemIndex, bundleItem in
                                        let event = redemptions.first { ($0["ItemIndex"] as? Int) == itemIndex }
                                        let itemName = bundleItem["Name"] as? String ?? "套票项目"
                                        let quantity = bundleItem["Quantity"] as? Int ?? 1
                                        Text("\(itemName) × \(quantity) · \(event == nil ? "待核销" : "已核销 \(bookingBusinessDateTime(event?["RedeemedAt"]) ?? "")")")
                                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(event == nil ? Brand.muted : Brand.primary)
                                    }
                                }
                                Text("有效期：\(credential["ValidFrom"] as? String ?? "") 至 \(credential["ValidUntil"] as? String ?? "")")
                                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                if canShowCode {
                                    Button(revealedCodes.contains(id) ? "隐藏入园码" : "显示入园码") {
                                        if revealedCodes.contains(id) { revealedCodes.remove(id) } else { revealedCodes.insert(id) }
                                    }.font(.system(size: NativeTypography.size(14), weight: .semibold))
                                    if revealedCodes.contains(id) {
                                        Text(code).font(.system(size: NativeTypography.size(16), weight: .bold, design: .monospaced)).textSelection(.enabled)
                                    }
                                } else if expired {
                                    Text("已过期，凭证码已失效。")
                                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                } else if credentialStatus == "Active" {
                                    Text("凭证暂不可展示，请刷新订单确认状态。")
                                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                }
                            }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 11))
                }
                ticketRefundHistory(order)
                ticketOrderActions(order)
                if let operationNotice { Text(operationNotice).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary).fixedSize(horizontal: false, vertical: true) }
                if let error { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red) }
                Button("刷新订单") { openTicketOrder(id: order["Id"] as? String ?? "") }
                    .font(.system(size: NativeTypography.size(14), weight: .semibold)).disabled(loading || operationBusy)
            }.padding(14)
        }
    }

    @ViewBuilder private func ticketPaymentAction(_ order: [String: Any]) -> some View {
        if (order["Status"] as? String) == "PendingPayment" {
            let orderId = order["Id"] as? String ?? ""
            let paymentStatus = order["PaymentStatus"] as? String ?? ""
            let provider = (order["PaymentProvider"] as? String ?? "").lowercased()
            let scene = (order["PaymentScene"] as? String ?? "").lowercased()
            let unmatched = order["HasUnmatchedPayment"] as? Bool == true || paymentStatus == "PaidUnmatched"
            let canResume = !unmatched && ((paymentStatus.isEmpty && provider.isEmpty && scene.isEmpty)
                || (paymentStatus == "RequiresAction" && provider == "alipay" && scene == "wap"))
            VStack(alignment: .leading, spacing: 8) {
            Text("支付宝将通过安全网页打开，返回应用后自动核对订单状态。")
                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
            if let paymentNotice { Text(paymentNotice).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary) }
            if canResume {
                Button(operationBusy ? "正在准备支付…" : "使用支付宝支付") { Task { await startTicketAlipayPayment(orderId: orderId) } }
                    .disabled(operationBusy || loading || orderId.isEmpty)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Brand.primary, in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(.white)
            } else {
                Text(unmatched ? "渠道已收款但订单尚未匹配，请勿重复支付；请联系平台核对。"
                    : "支付尝试状态或渠道场景待确认，请勿重复支付；请刷新本人订单状态。")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(.orange)
            }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private func startTicketAlipayPayment(orderId: String) async {
        let paymentStatus = selectedOrder?["PaymentStatus"] as? String ?? ""
        let paymentProvider = (selectedOrder?["PaymentProvider"] as? String ?? "").lowercased()
        let paymentScene = (selectedOrder?["PaymentScene"] as? String ?? "").lowercased()
        let resumableAttempt = (paymentStatus.isEmpty && paymentProvider.isEmpty && paymentScene.isEmpty)
            || (paymentStatus == "RequiresAction" && paymentProvider == "alipay" && paymentScene == "wap")
        guard let token = store.session?.accessToken, !token.isEmpty,
              let order = selectedOrder, order["Id"] as? String == orderId,
              detailOwner == token, detailID == orderId, pageVisible, scenePhase == .active,
              order["Status"] as? String == "PendingPayment", !operationBusy, !loading,
              order["HasUnmatchedPayment"] as? Bool != true,
              resumableAttempt else { return }
        guard let paymentDeadline = nativeBusinessTimestamp(order["PaymentExpiresAt"]), paymentDeadline > Date() else {
            paymentNotice = "支付期限暂无法确认，请刷新订单状态后再试。"
            return
        }
        reconciliationTask?.cancel(); requestSequence += 1
        let sequence = requestSequence
        operationSequence += 1; let operation = operationSequence
        func isCurrent() -> Bool {
            requestSequence == sequence && store.session?.accessToken == token && detailID == orderId
                && pageVisible && scenePhase == .active
        }
        operationBusy = true; paymentNotice = nil; operationNotice = nil; error = nil
        defer { if operationSequence == operation { operationBusy = false } }
        do {
            guard let payment = try await MobileAPI(store: store).post("/api/JHCTITicket/CreateOrderPayment", body: [
                "OrderId": orderId, "Provider": "alipay", "Scene": "wap"
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any] else {
                throw MobileAPIError.unavailable("支付回执无效或订单页面已变化，请刷新本人订单状态。")
            }
            guard isCurrent() else { return }
            guard payment["Provider"] as? String == "alipay", payment["Status"] as? String == "RequiresAction",
                  let recordId = payment["PaymentRecordId"] as? String, Int64(recordId).map({ $0 > 0 }) == true,
                  let rawURL = payment["ApprovalUrl"] as? String,
                  let url = URL(string: rawURL), url.scheme?.lowercased() == "https",
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
                throw MobileAPIError.unavailable("支付状态或渠道回执无法核对；请刷新订单，勿重复支付。")
            }
            try requireNativePaymentLaunchDeadline(order["PaymentExpiresAt"])
            let opened = await withCheckedContinuation { continuation in openURL(url) { continuation.resume(returning: $0) } }
            guard isCurrent() else { return }
            guard opened else { throw MobileAPIError.unavailable("设备未能打开支付页面，请刷新本人订单状态后再继续。") }
            paymentNotice = "已打开支付宝支付页面，返回应用后自动核对订单状态。"
            await loadOrder(id: orderId)
        } catch {
            guard isCurrent() else { return }
            let refreshSequence = requestSequence + 1
            await loadOrder(id: orderId)
            guard store.session?.accessToken == token, requestSequence == refreshSequence, detailID == orderId, pageVisible, scenePhase == .active else { return }
            paymentNotice = "支付结果未确认，已刷新本人订单；请核对支付状态后再操作。"
        }
    }

    private var refundApplicationSheet: some View {
        NavigationStack {
            Form {
                Section("符合当前规则的未核销门票") {
                    ForEach(refundCandidates.indices, id: \.self) { index in
                        let credential = refundCandidates[index]
                        let id = credential["Id"] as? String ?? ""
                        Toggle("\(credential["TicketName"] as? String ?? "门票") · \(credential["SessionName"] as? String ?? "场次")",
                               isOn: Binding(get: { refundSelectedIds.contains(id) }, set: { selected in
                            if selected && refundSelectedIds.count < 50 { refundSelectedIds.insert(id) } else if !selected { refundSelectedIds.remove(id) }
                        })).disabled(!refundSelectedIds.contains(id) && refundSelectedIds.count >= 50)
                    }
                }
                Section("退款原因（必填，最多 500 字）") {
                    TextField("请填写退款原因", text: $refundReason, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    Text("退款资格与金额由服务端按购票时规则再次核验；提交结果不确定时请先刷新退款记录。")
                        .font(.footnote).foregroundStyle(Brand.muted)
                }
            }
            .navigationTitle("申请门票退款").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { refundSheetOpen = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(operationBusy ? "提交中…" : "提交申请") { Task { await submitTicketRefund() } }
                        .disabled(operationBusy || refundSelectedIds.isEmpty || refundSelectedIds.count > 50 || refundReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || refundReason.utf16.count > 500)
                }
            }
        }
    }

    @ViewBuilder private func ticketRefundHistory(_ order: [String: Any]) -> some View {
        let refunds = order["Refunds"] as? [[String: Any]] ?? []
        if !refunds.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("退款记录").font(.system(size: NativeTypography.size(14), weight: .semibold))
                ForEach(Array(refunds.enumerated()), id: \.offset) { _, refund in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(ticketRefundStatus(refund["Status"] as? String ?? "")) · \(refund["TicketCount"] as? Int ?? 0) 张")
                            .font(.system(size: NativeTypography.size(14), weight: .semibold))
                        Text("申请 \(refund["CreateTime"] as? String ?? "时间待提供") · \(refund["Currency"] as? String ?? "CNY") \(ticketMoney(refund["Amount"]))")
                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                        let reason = refund["DecisionReason"] as? String ?? refund["Reason"] as? String ?? ""
                        if !reason.isEmpty { Text(reason).font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 11))
        }
    }

    @ViewBuilder private func ticketOrderActions(_ order: [String: Any]) -> some View {
        let orderId = order["Id"] as? String ?? ""
        let orderStatus = order["Status"] as? String ?? ""
        let paymentStatus = order["PaymentStatus"] as? String
        let unmatched = order["HasUnmatchedPayment"] as? Bool == true || paymentStatus == "PaidUnmatched"
        let refunds = order["Refunds"] as? [[String: Any]] ?? []
        let hasActiveRefund = refunds.contains { ["Requested", "Processing"].contains($0["Status"] as? String ?? "") }
        let candidates = (order["Lines"] as? [[String: Any]] ?? []).flatMap { line in
            (line["Credentials"] as? [[String: Any]] ?? []).compactMap { credential -> [String: Any]? in
                guard credential["CanRefund"] as? Bool == true, let id = credential["Id"] as? String, Int64(id).map({ $0 > 0 }) == true else { return nil }
                var item = credential
                item["TicketName"] = line["TicketName"] as? String ?? "门票"
                item["SessionName"] = line["SessionName"] as? String ?? "场次"
                return item
            }
        }
        if orderStatus == "PendingPayment" {
            VStack(alignment: .leading, spacing: 8) {
                if unmatched || (paymentStatus != nil && paymentStatus != "RequiresAction") {
                    Text("支付状态待核对，请勿重复支付或取消。刷新订单确认渠道结果。")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(.orange)
                } else {
                    Button(operationBusy ? "正在处理…" : "取消未支付订单", role: .destructive) { pendingCancelOrder = order }
                        .disabled(operationBusy || orderId.isEmpty)
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 11))
        }
        if ["Issued", "PartiallyRefunded"].contains(orderStatus) && !unmatched && !hasActiveRefund && !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("退款仅开放给服务端标记为符合规则的未核销门票。")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                Button("申请退款（\(candidates.count) 张可选）") {
                    refundOrderId = orderId; refundCandidates = candidates
                    refundSelectedIds = Set(candidates.compactMap { $0["Id"] as? String })
                    refundReason = ""; operationNotice = nil; refundSheetOpen = true
                }.disabled(operationBusy || orderId.isEmpty)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private func cancelPendingOrder(_ order: [String: Any]) async {
        guard let token = store.session?.accessToken, !token.isEmpty,
              let id = order["Id"] as? String, !id.isEmpty,
              detailID == id, detailOwner == token, selectedOrder?["Status"] as? String == "PendingPayment",
              selectedOrder?["HasUnmatchedPayment"] as? Bool != true,
              (selectedOrder?["PaymentStatus"] as? String == nil || selectedOrder?["PaymentStatus"] as? String == "RequiresAction"),
              pageVisible, scenePhase == .active, !loading,
              order["Status"] as? String == "PendingPayment",
              order["HasUnmatchedPayment"] as? Bool != true,
              (order["PaymentStatus"] as? String == nil || order["PaymentStatus"] as? String == "RequiresAction"),
              !operationBusy else { return }
        reconciliationTask?.cancel(); requestSequence += 1; let sequence = requestSequence
        operationSequence += 1; let operation = operationSequence
        func isCurrent() -> Bool { requestSequence == sequence && store.session?.accessToken == token && detailID == id && pageVisible && scenePhase == .active }
        operationBusy = true; operationNotice = nil
        defer { if operationSequence == operation { operationBusy = false } }
        do {
            let receipt = try await MobileAPI(store: store).post("/api/JHCTITicket/CancelMyPendingOrder?id=\(id)", body: [:], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? String
            guard isCurrent() else { return }
            guard receipt == id else { throw MobileAPIError.unavailable("取消回执与当前订单不一致，请刷新核对。") }
            operationNotice = "订单已取消。"
            await loadOrder(id: id)
        } catch {
            guard isCurrent() else { return }
            let refreshSequence = requestSequence + 1
            await loadOrder(id: id)
            guard requestSequence == refreshSequence, store.session?.accessToken == token, detailID == id, pageVisible, scenePhase == .active else { return }
            operationNotice = "取消结果未确认，已尝试刷新订单。请核对当前状态；仍待支付时再重新操作。"
        }
    }

    private func submitTicketRefund() async {
        guard let token = store.session?.accessToken, !token.isEmpty, !operationBusy,
              !refundOrderId.isEmpty, !refundSelectedIds.isEmpty, detailID == refundOrderId, detailOwner == token,
              pageVisible, scenePhase == .active, !loading else { return }
        let reason = refundReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty, reason.utf16.count <= 500, refundSelectedIds.count <= 50 else { operationNotice = "请填写不超过 500 字的退款原因，每次最多选择 50 张门票。"; return }
        let orderId = refundOrderId
        reconciliationTask?.cancel(); requestSequence += 1; let sequence = requestSequence
        operationSequence += 1; let operation = operationSequence
        func isCurrent() -> Bool { requestSequence == sequence && store.session?.accessToken == token && detailID == orderId && pageVisible && scenePhase == .active }
        operationBusy = true; operationNotice = nil
        defer { if operationSequence == operation { operationBusy = false } }
        do {
            guard let receipt = try await MobileAPI(store: store).post("/api/JHCTITicket/RequestMyRefund", body: [
                "OrderId": orderId, "CredentialIds": Array(refundSelectedIds), "Reason": reason
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any],
            isCurrent(),
            receipt["OrderId"] as? String == orderId,
            ["Requested", "Processing"].contains(receipt["Status"] as? String ?? "") else {
                throw MobileAPIError.unavailable("退款回执无法核对，已避免重复提交；请刷新退款记录。")
            }
            refundSheetOpen = false; operationNotice = "退款申请已提交，等待处理。"
            await loadOrder(id: orderId)
        } catch {
            guard isCurrent() else { return }
            let refreshSequence = requestSequence + 1
            await loadOrder(id: orderId)
            guard requestSequence == refreshSequence, store.session?.accessToken == token, detailID == orderId, pageVisible, scenePhase == .active else { return }
            operationNotice = "退款提交结果未确认。请核对订单中的退款记录，避免重复申请。"
        }
    }

    private func loadOrders(reset: Bool) async {
        guard detailID.isEmpty, pageVisible, scenePhase == .active else { return }
        if !reset && loading { return }
        reconciliationTask?.cancel()
        guard let token = store.session?.accessToken else { rows = []; error = "请先登录文旅账号。"; return }
        let previousRows = rows
        let previousTotal = total
        let previousPage = page
        let targetPage = reset ? 1 : page + 1
        let principal = MobileAPI(store: store).nativeTourismPrincipal(token)
        if reset { requestSequence += 1; page = 1; total = 0; rows = []; revealedCodes = [] }
        let sequence = requestSequence; loading = true; error = nil
        do {
            let cursor = targetPage > 1 ? "&beforeOrderId=\(rows.last?["Id"] as? String ?? "")" : ""
            guard let result = try await MobileAPI(store: store).get("/api/JHCTITicket/GetMyOrderPage?page=\(targetPage)&pageSize=20\(status.isEmpty ? "" : "&status=\(status)")\(cursor)", authenticated: true, expectedPrincipal: principal) as? [String: Any] else {
                throw MobileAPIError.unavailable("门票订单响应格式异常，请重试。")
            }
            guard !Task.isCancelled, store.session?.accessToken == token, requestSequence == sequence,
                  detailID.isEmpty, pageVisible, scenePhase == .active else { return }
            guard let parsedPage = nativeTicketOrderPage(result, page: targetPage, pageSize: 20) else {
                throw MobileAPIError.unavailable("门票订单分页数据与请求不一致，请刷新后重试。")
            }
            if !reset {
                let existingIDs = Set(rows.compactMap { ($0["Id"] as? String) ?? ($0["id"] as? String) })
                let containsDuplicate = parsedPage.items.contains { item in
                    guard let orderID = (item["Id"] as? String) ?? (item["id"] as? String) else { return false }
                    return existingIDs.contains(orderID)
                }
                guard !containsDuplicate else {
                    throw MobileAPIError.unavailable("门票订单分页出现重复订单，请刷新后重试。")
                }
            }
            rows = reset ? parsedPage.items : rows + parsedPage.items
            total = parsedPage.total
            page = targetPage
        } catch {
            if !Task.isCancelled && store.session?.accessToken == token && requestSequence == sequence && pageVisible && scenePhase == .active {
                if reset { rows = previousRows; total = previousTotal; page = previousPage }
                self.error = error.localizedDescription
            }
        }
        if requestSequence == sequence { loading = false }
    }

    private func openTicketOrder(id: String) {
        detailReadTask?.cancel()
        detailReadTask = Task { await loadOrder(id: id) }
    }

    private func loadOrder(id: String) async {
        guard Int64(id).map({ $0 > 0 && String($0) == id }) == true,
              let token = store.session?.accessToken, !token.isEmpty else { error = "请重新登录后查看订单。"; return }
        let principal = MobileAPI(store: store).nativeTourismPrincipal(token)
        reconciliationTask?.cancel()
        requestSequence += 1; let sequence = requestSequence; loading = true; error = nil; revealedCodes = []
        detailID = id; detailOwner = ""; selectedOrder = nil; reconciliationNotice = nil
        func isCurrent() -> Bool {
            !Task.isCancelled && store.session?.accessToken == token && requestSequence == sequence
                && detailID == id && pageVisible && scenePhase == .active
        }
        do {
            let response = try await MobileAPI(store: store).get("/api/JHCTITicket/GetMyOrder?id=\(id)", authenticated: true, expectedPrincipal: principal) as? [String: Any]
            guard isCurrent() else { return }
            guard let response, let order = nativeTicketOrderDetail(response, expectedOrderID: id) else {
                throw MobileAPIError.unavailable("门票订单详情结构异常，请返回列表重新打开。")
            }
            selectedOrder = order; detailOwner = token; loading = false
            if nativeTicketPaymentNeedsReconciliation(order) {
                reconciliationNotice = order["Status"] as? String == "PaidPendingIssue" ? "支付已确认，正在核对出票进度…" : "正在核对服务端订单状态，请勿重复付款。"
                reconciliationTask = Task { @MainActor in
                    await reconcileNativePaymentOrder(initial: order, orderID: id, read: {
                        guard let response = try await MobileAPI(store: store).get("/api/JHCTITicket/GetMyOrder?id=\(id)", authenticated: true, expectedPrincipal: principal) as? [String: Any],
                              let value = nativeTicketOrderDetail(response, expectedOrderID: id) else {
                            throw MobileAPIError.unavailable("门票订单详情结构异常")
                        }
                        return value
                    }, isCurrent: isCurrent, apply: { value in
                        selectedOrder = value; revealedCodes = []
                        reconciliationNotice = value["Status"] as? String == "PaidPendingIssue" ? "支付已确认，正在核对出票进度…"
                            : "订单当前状态：\(ticketStatus(value["Status"] as? String ?? ""))，请以订单记录为准。"
                    }, exhausted: {
                        reconciliationNotice = "自动核对已暂停，请手动刷新订单；已付款或出票中时无需再次支付。"
                    }, invalid: {
                        selectedOrder = nil; detailOwner = ""; reconciliationNotice = nil; self.error = "订单查询结果不一致，请返回列表重新打开。"
                    }, pending: nativeTicketPaymentNeedsReconciliation)
                }
            }
        } catch { if isCurrent() { self.error = error.localizedDescription } }
        if isCurrent() { loading = false }
    }

    private func ticketStatus(_ value: String) -> String {
        ["PendingPayment":"待支付", "PaidPendingIssue":"支付成功，出票中", "Issued":"已出票", "Closed":"已关闭",
         "PaidIssueFailed":"出票异常，等待处理", "PartiallyRefunded":"部分退款", "Refunded":"已退款"][value] ?? "状态更新中"
    }
    private func ticketCredentialStatus(_ value: String) -> String {
        ["Active":"可使用", "Redeemed":"已核销", "Refunded":"已退款", "Expired":"已过期"][value] ?? "状态更新中"
    }
    private func ticketRefundStatus(_ value: String) -> String {
        ["Requested":"等待审核", "Processing":"退款处理中", "Refunded":"退款成功", "Rejected":"申请未通过", "Failed":"退款失败"][value] ?? "状态更新中"
    }
    private func ticketMoney(_ value: Any?) -> String {
        let amount = (value as? NSNumber)?.doubleValue ?? (value as? Double) ?? 0
        return String(format: "%.2f", amount)
    }
}

private func nativeTicketCredentialValidUntil(_ value: Any?) -> Date? {
    nativeBusinessTimestamp(value)
}
