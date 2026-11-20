import Foundation
import SwiftUI

struct NativeTradePaymentView: View {
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
    @State private var pageVisible = true
    @State private var orderOwner = ""
    @State private var launchError: String?

    private var amount: Double? {
        guard let raw = order?["PayableAmount"], let value = (raw as? NSNumber)?.doubleValue ?? Double("\(raw)"),
              value.isFinite, value > 0 else { return nil }
        return value
    }

    private var deadline: Date? {
        nativeBusinessTimestamp(order?["PaymentExpiresAt"])
    }

    private var deadlineLabel: String {
        guard let deadline else { return "待确认" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: deadline)
    }

    private var canPay: Bool {
        guard orderOwner == store.session?.accessToken, order?["Status"] as? String == "PendingPayment", amount != nil,
              let deadline, deadline > Date(), let id = order?["Id"] as? String,
              id == orderId, Int64(id).map({ $0 > 0 }) == true else { return false }
        let status = order?["PaymentStatus"] as? String ?? ""
        return status.isEmpty || status == "RequiresAction"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("订单支付").font(.system(size: NativeTypography.size(20), weight: .bold)).foregroundStyle(Brand.primary)
                        if let order {
                            Text("订单号：\(order["OrderNo"] as? String ?? "—")").font(.system(size: NativeTypography.size(14), weight: .semibold))
                            Text("订单状态：\(orderStatus(order["Status"] as? String ?? ""))").font(.system(size: NativeTypography.size(14)))
                            Text("应付金额：\(order["Currency"] as? String ?? "CNY") \(amount.map { String(format: "%.2f", $0) } ?? "待确认")")
                                .font(.system(size: NativeTypography.size(18), weight: .bold)).foregroundStyle(Brand.ink)
                            Text("支付截止：\(deadlineLabel)")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            if order["Status"] as? String == "PendingPayment", deadline == nil {
                                Text("支付期限暂不可确认，请刷新订单状态。")
                                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                            } else if let deadline, deadline <= Date(), order["Status"] as? String == "PendingPayment" {
                                Text("订单支付期限已过，请返回订单页查询最新状态。")
                                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                            }
                            let paymentStatus = order["PaymentStatus"] as? String ?? ""
                            if order["Status"] as? String == "PendingPayment", !paymentStatus.isEmpty, paymentStatus != "RequiresAction" {
                                Text(paymentStatusNotice(paymentStatus))
                                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))

                    if let error {
                        Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                    }
                    if let notice {
                        Text(notice).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                    }
                    if let launchError {
                        Text(launchError).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                    }
                    if loading && order == nil { ProgressView("正在读取订单…").frame(maxWidth: .infinity) }
                    Button(paying ? "正在准备支付宝…" : "使用支付宝支付") { Task { await pay() } }
                        .font(.system(size: NativeTypography.size(16), weight: .semibold)).frame(maxWidth: .infinity).padding(12)
                        .background(Brand.primary, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white)
                        .disabled(!canPay || loading || paying)
                    Button("查询订单状态") { revision += 1 }
                        .font(.system(size: NativeTypography.size(14), weight: .semibold)).frame(maxWidth: .infinity).padding(11)
                        .disabled(loading || paying)
                    Text("支付结果以服务端订单状态为准。若支付页面异常退出或结果待确认，请先查询订单，避免重复付款。")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                }.padding(16)
            }
            .background(Brand.background)
            .navigationTitle("商城订单支付").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .task(id: revision) { if scenePhase == .active { await load() } }
            .task(id: deadline) {
                guard let deadline, deadline > Date() else { return }
                do { try await Task.sleep(for: .milliseconds(Int64(deadline.timeIntervalSinceNow * 1000))) } catch { return }
                revision += 1
            }
            .onAppear { pageVisible = true }
            .onDisappear { pageVisible = false; invalidateRead() }
            .onChange(of: store.session?.accessToken) { _, _ in invalidateRead(); revision += 1 }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { revision += 1 } else { invalidateRead() }
            }
        }
    }

    @MainActor private func invalidateRead() {
        readSequence += 1; order = nil; orderOwner = ""; loading = false; error = nil; notice = nil; launchError = nil
    }

    @MainActor private func load() async {
        readSequence += 1
        let requestedSequence = readSequence
        guard let token = store.session?.accessToken, !token.isEmpty,
              Int64(orderId).map({ $0 > 0 && String($0) == orderId }) == true else {
            order = nil; error = "订单编号无效或登录状态已失效，请返回我的订单重新进入。"; return
        }
        guard let requestedPrincipal = nativeTourismPrincipal(token) else {
            order = nil; error = "登录状态无效，请返回我的订单重新进入。"; return
        }
        func isCurrent() -> Bool {
            !Task.isCancelled && requestedSequence == readSequence && pageVisible && scenePhase == .active
                && store.session?.accessToken == token
        }
        order = nil; orderOwner = ""
        loading = true; error = nil; notice = nil
        defer { if isCurrent() { loading = false } }
        do {
            let response = try await MobileAPI(store: store).get("/api/JHCTITradeOrder/GetMyOrder?id=\(orderId)", authenticated: true, expectedPrincipal: requestedPrincipal)
            guard isCurrent() else { return }
            guard let result = response as? [String: Any], result["Id"] as? String == orderId else {
                throw MobileAPIError.unavailable("订单查询结果与当前订单不一致，请返回我的订单重新打开。")
            }
            order = result; orderOwner = token
            if result["Status"] as? String != "PendingPayment" { launchError = nil }
            loading = false
            if nativeTradePaymentNeedsReconciliation(result) { notice = "正在核对服务端订单状态，请勿重复付款。" }
            await reconcileNativePaymentOrder(initial: result, orderID: orderId, read: {
                guard let value = try await MobileAPI(store: store).get("/api/JHCTITradeOrder/GetMyOrder?id=\(orderId)", authenticated: true, expectedPrincipal: requestedPrincipal) as? [String: Any]
                else { throw MobileAPIError.unavailable("订单详情格式异常") }
                return value
            }, isCurrent: isCurrent, apply: { value in
                order = value; self.error = nil
                if value["Status"] as? String != "PendingPayment" { launchError = nil }
                if !nativeTradePaymentNeedsReconciliation(value) {
                    notice = "订单当前状态：\(orderStatus(value["Status"] as? String ?? ""))，请以订单记录为准。"
                }
            }, exhausted: {
                notice = "自动核对已暂停，请手动查询订单状态；若已付款，请勿重复支付。"
            }, invalid: {
                order = nil; self.error = "订单查询结果不一致，请返回我的订单重新打开。"
            })
        } catch { if isCurrent() { self.error = error.localizedDescription } }
    }

    @MainActor private func pay() async {
        guard canPay, !loading, !paying, pageVisible, scenePhase == .active,
              let token = store.session?.accessToken else { return }
        let launchDeadline = order?["PaymentExpiresAt"]
        readSequence += 1
        let requestedSequence = readSequence
        paying = true; error = nil; notice = nil; launchError = nil
        defer {
            paying = false
            if requestedSequence == readSequence && store.session?.accessToken == token && pageVisible && scenePhase == .active { revision += 1 }
        }
        do {
            guard let payment = try await MobileAPI(store: store).post("/api/JHCTITradeOrder/CreatePayment", body: [
                "OrderId": orderId, "Provider": "alipay", "Scene": "wap"
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any] else {
                throw MobileAPIError.unavailable("支付响应无效或登录账号已变化，请查询订单状态。")
            }
            guard requestedSequence == readSequence, store.session?.accessToken == token,
                  pageVisible, scenePhase == .active else { return }
            guard payment["Status"] as? String == "RequiresAction",
                  let raw = payment["ApprovalUrl"] as? String, let url = URL(string: raw),
                  url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil else {
                throw MobileAPIError.unavailable("支付渠道未返回有效的 HTTPS 地址，请查询订单状态。")
            }
            try requireNativePaymentLaunchDeadline(launchDeadline)
            let opened = await withCheckedContinuation { continuation in
                openURL(url) { accepted in continuation.resume(returning: accepted) }
            }
            guard requestedSequence == readSequence, store.session?.accessToken == token,
                  pageVisible, scenePhase == .active else { return }
            guard opened else { throw MobileAPIError.unavailable("设备未能打开支付页面，请查询订单状态后再继续。") }
            notice = "已打开支付宝支付页面，返回应用后自动核对订单状态。"
        } catch {
            if requestedSequence == readSequence && store.session?.accessToken == token && pageVisible && scenePhase == .active {
                launchError = error.localizedDescription
            }
        }
    }

    private func orderStatus(_ value: String) -> String {
        ["PendingPayment": "待付款", "PendingShipment": "待发货", "Shipped": "配送中", "PendingPickup": "待自提",
         "Completed": "已完成", "Closed": "已关闭", "Refunded": "已退款"][value] ?? "状态待核对"
    }

    private func paymentStatusNotice(_ value: String) -> String {
        switch value {
        case "Creating", "Processing": return "支付请求仍在处理中，请勿重复发起；可查询订单状态。"
        case "Unknown", "PaidUnmatched": return "支付结果待核对，请勿重复支付，等待平台处理。"
        case "Failed", "Closed": return "此前支付尝试已结束，请先查询订单状态后再处理。"
        default: return "支付状态暂无法确认，请查询订单状态，不要重复发起支付。"
        }
    }
}
