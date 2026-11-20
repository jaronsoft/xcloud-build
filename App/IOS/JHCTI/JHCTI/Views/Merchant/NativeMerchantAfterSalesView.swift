import Foundation
import SwiftUI

private struct NativeAfterSaleAction: Identifiable {
    let row: [String: Any]
    let status: String
    var id: String { "\(row["Id"] ?? "")-\(status)" }
}

struct MerchantAfterSalesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let merchantID: String
    var initialAfterSaleID: String = ""
    @State private var rows: [[String: Any]] = []
    @State private var selectedStatus = ""
    @State private var page = 1
    @State private var total = 0
    @State private var expandedID = ""
    @State private var deepLinkHandled = false
    @State private var detail: [String: Any]?
    @State private var message = ""
    @State private var reason = ""
    @State private var loading = true
    @State private var detailLoading = false
    @State private var submitting = false
    @State private var error: String?
    @State private var revision = 0
    @State private var requestSequence = 0
    @State private var detailSequence = 0
    @State private var pendingAction: NativeAfterSaleAction?
    @State private var uncertainActionID = ""
    @State private var uncertainReadbackVerified = false

    private let statuses = [("", "全部"), ("PendingReview", "待协同"), ("Negotiating", "协商中"),
        ("ReturnRequired", "待退货"), ("ReturnInTransit", "运输中"), ("ReturnReceived", "已收货"),
        ("ApprovedForRefund", "待退款"), ("RefundProcessing", "退款中"), ("Refunded", "已退款"),
        ("Rejected", "已拒绝"), ("Closed", "已关闭")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("可与顾客沟通并处理退货；退款审批、拒绝申请及渠道退款由平台客服处理。")
                    .font(.caption).foregroundStyle(Brand.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(statuses.indices, id: \.self) { index in
                            let item = statuses[index]
                            Button(item.1) { selectStatus(item.0) }
                                .buttonStyle(.bordered).tint(selectedStatus == item.0 ? Brand.primary : Brand.muted)
                                .disabled(submitting)
                        }
                    }
                }
                StatusView(loading: loading, error: error) { revision += 1 }
                if !loading && error == nil && rows.isEmpty { Text("暂无售后申请。").foregroundStyle(Brand.muted) }
                ForEach(rows.indices, id: \.self) { index in afterSaleCard(rows[index]) }
                if !loading && error == nil && rows.count < total {
                    Button("加载更多（\(rows.count)/\(total)）") { Task { await load(page: page + 1) } }
                        .disabled(submitting).frame(maxWidth: .infinity)
                }
            }.padding(16)
        }
        .background(Brand.background)
        .navigationTitle("商户售后协同")
        .task(id: revision) { await load(page: 1) }
        .task(id: "\(merchantID)-\(store.session?.accessToken ?? "")") { restoreUncertainAction() }
        .onChange(of: store.session?.accessToken) { _, _ in dismiss() }
        .confirmationDialog(actionLabel, isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
            Button(actionLabel, role: pendingAction?.status == "ReturnRequired" ? .destructive : nil) {
                guard let action = pendingAction else { return }
                if action.status == "ClearUnknown" {
                    if let token = store.session?.accessToken {
                        UserDefaults.standard.removeObject(forKey: nativeMerchantAfterSaleLockStorageKey(accessToken: token, merchantID: merchantID))
                    }
                    uncertainActionID = ""; uncertainReadbackVerified = false
                    error = "已解除保护；请确认保留的内容后手动重新提交。"
                    pendingAction = nil
                    return
                }
                Task { await submit(action.row, status: action.status) }
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: {
            Text(pendingAction?.status == "ClearUnknown"
                ? "只有在核对最新售后详情并确认上次操作未生效后，才解除保护。此操作不会自动重发。"
                : "确认对售后单 \(pendingAction?.row["CaseNo"] as? String ?? "") 执行“\(actionLabel)”？")
        }
    }

    private var actionLabel: String {
        if pendingAction?.status == "ClearUnknown" { return "解除重复提交保护" }
        return pendingAction?.status == "ReturnRequired" ? "要求顾客退货" : "确认已收到退货"
    }

    private func selectStatus(_ status: String) {
        selectedStatus = status
        expandedID = ""
        detail = nil
        Task { await load(page: 1, status: status) }
    }

    private func restoreUncertainAction() {
        guard let token = store.session?.accessToken else { uncertainActionID = ""; return }
        let key = nativeMerchantAfterSaleLockStorageKey(accessToken: token, merchantID: merchantID)
        uncertainActionID = UserDefaults.standard.string(forKey: key) ?? ""
        uncertainReadbackVerified = false
    }

    private func afterSaleCard(_ row: [String: Any]) -> some View {
        let id = Self.text(row["Id"] ?? row["id"])
        let status = (row["Status"] ?? row["status"]) as? String ?? ""
        let requestType = (row["RequestType"] ?? row["requestType"]) as? String ?? ""
        let isReturn = requestType == "ReturnAndRefund"
        let statusLabel = statuses.first(where: { $0.0 == status })?.1 ?? status
        return VStack(alignment: .leading, spacing: 8) {
            HStack { Text((row["CaseNo"] ?? row["caseNo"]) as? String ?? "售后单").font(.headline); Spacer(); Text(statusLabel).font(.caption).foregroundStyle(Brand.primary) }
            Text("订单 \((row["OrderNo"] ?? row["orderNo"]) as? String ?? "—") · \(isReturn ? "退货退款" : "仅退款")")
                .font(.caption).foregroundStyle(Brand.muted)
            Text("\((row["ReasonCode"] ?? row["reasonCode"]) as? String ?? "售后申请") · ¥\(String(describing: row["RequestedAmount"] ?? row["requestedAmount"] ?? "0"))")
                .font(.caption)
            Button(expandedID == id ? "收起详情" : "查看详情") { Task { await open(row) } }
                .disabled(submitting || detailLoading)
            if expandedID == id {
                if detailLoading { ProgressView("正在读取售后详情…") }
                if let detail { afterSaleDetail(row, detail: detail, status: status, isReturn: isReturn) }
                if uncertainActionID == id {
                    Text("上次操作结果未知。请先检查最新详情；为避免重复留言或处理，当前已锁定本售后单的写操作。")
                        .font(.caption).foregroundStyle(.red)
                    Button(detailLoading ? "正在重新读取…" : "重新读取最新详情") { Task { await verifyUncertain(row) } }
                        .disabled(detailLoading || submitting)
                    Button("我已核对详情，允许手动重试") {
                        pendingAction = NativeAfterSaleAction(row: row, status: "ClearUnknown")
                    }.disabled(submitting || detailLoading || !uncertainReadbackVerified)
                }
            }
        }.merchantCard()
    }

    @ViewBuilder private func afterSaleDetail(_ row: [String: Any], detail: [String: Any], status: String, isReturn: Bool) -> some View {
        let description = (detail["Description"] ?? detail["description"]) as? String ?? ""
        if !description.isEmpty { Text("顾客说明：\(description)").font(.caption) }
        let items = detail["Items"] as? [[String: Any]] ?? detail["items"] as? [[String: Any]] ?? []
        ForEach(items.indices, id: \.self) { index in
            let item = items[index]
            Text("\((item["ProductName"] ?? item["productName"]) as? String ?? "商品") · \((item["SkuCode"] ?? item["skuCode"]) as? String ?? "默认规格") × \(Self.text(item["Quantity"] ?? item["quantity"]))")
                .font(.caption)
        }
        let carrier = (detail["ReturnCarrier"] ?? detail["returnCarrier"]) as? String ?? ""
        if !carrier.isEmpty {
            Text("退货物流：\(carrier) / \((detail["ReturnTrackingNumber"] ?? detail["returnTrackingNumber"]) as? String ?? "—")").font(.caption)
        }
        let messages = detail["Messages"] as? [[String: Any]] ?? detail["messages"] as? [[String: Any]] ?? []
        ForEach(messages.indices, id: \.self) { index in
            let item = messages[index]
            let senderType = (item["SenderType"] ?? item["senderType"]) as? String ?? ""
            let sender = senderType == "Customer" ? "顾客" : senderType == "Merchant" ? "商户" : "平台客服"
            VStack(alignment: .leading, spacing: 4) {
                Text("\(sender) · \((item["CreateTime"] ?? item["createTime"]) as? String ?? "")").font(.caption2).foregroundStyle(Brand.muted)
                Text((item["Content"] ?? item["content"]) as? String ?? "").font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
        }
        if !["Refunded", "Rejected", "Closed"].contains(status) {
            TextField("给顾客留言，最多 1000 字", text: $message, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
            Button(submitting ? "提交中…" : "发送留言") { Task { await submit(row, status: nil) } }
                .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(submitting || !uncertainActionID.isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        let canNegotiate = ["PendingReview", "Negotiating"].contains(status)
        let canRequireReturn = isReturn && canNegotiate
        let canConfirmReturn = isReturn && status == "ReturnInTransit"
        if canNegotiate || canRequireReturn || canConfirmReturn {
            TextField("处理说明，最多 1000 字", text: $reason, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
            HStack {
                if canNegotiate { Button("标记协商中") { Task { await submit(row, status: "Negotiating") } }.disabled(submitting || !uncertainActionID.isEmpty) }
                if canRequireReturn { Button("要求退货", role: .destructive) { pendingAction = NativeAfterSaleAction(row: row, status: "ReturnRequired") }.disabled(submitting || !uncertainActionID.isEmpty) }
                if canConfirmReturn { Button("确认收到退货") { pendingAction = NativeAfterSaleAction(row: row, status: "ReturnReceived") }.disabled(submitting || !uncertainActionID.isEmpty) }
            }.buttonStyle(.bordered)
        }
        Text("平台退款审批、拒绝申请及渠道退款由客服工作台处理。")
            .font(.caption2).foregroundStyle(Brand.muted)
    }

    private func load(page targetPage: Int, status requestedStatus: String? = nil) async {
        guard !merchantID.isEmpty, merchantID.allSatisfy(\.isNumber), let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else {
            error = "商户或登录范围无效，请返回工作台重新进入。"; loading = false; return
        }
        requestSequence += 1
        let sequence = requestSequence
        let activeStatus = requestedStatus ?? selectedStatus
        let append = targetPage > 1
        loading = true; error = nil
        if !append { rows = []; page = 1 }
        do {
            let encoded = activeStatus.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))) ?? ""
            let result = try await MobileAPI(store: store).get(
                "/api/JHCTIMerchantOrder/GetAfterSalePage?merchantId=\(merchantID)&page=\(targetPage)&pageSize=20\(encoded.isEmpty ? "" : "&status=\(encoded)")",
                authenticated: true, expectedPrincipal: expectedPrincipal) as? [String: Any]
            guard requestSequence == sequence, store.session?.accessToken == token,
                  let result, let data = result["data"] as? [[String: Any]] ?? result["Data"] as? [[String: Any]] else {
                throw MobileAPIError.unavailable("售后列表响应格式异常，请重试。")
            }
            let count = Self.intValue(result["dataCount"] ?? result["DataCount"])
            guard data.count <= 20, count >= data.count, count >= 0,
                  data.allSatisfy({ !Self.text($0["Id"] ?? $0["id"]).isEmpty }) else {
                throw MobileAPIError.unavailable("售后列表分页数据不完整，请刷新后重试。")
            }
            var next = append ? rows : []
            for item in data {
                let id = Self.text(item["Id"] ?? item["id"])
                if let index = next.firstIndex(where: { Self.text($0["Id"] ?? $0["id"]) == id }) { next[index] = item }
                else { next.append(item) }
            }
            rows = next; total = count; page = targetPage
            if !deepLinkHandled, !initialAfterSaleID.isEmpty {
                var target = next.first(where: { Self.text($0["Id"] ?? $0["id"]) == initialAfterSaleID })
                if target == nil {
                    target = try await MobileAPI(store: store).get(
                        "/api/JHCTIMerchantOrder/GetAfterSaleCase?merchantId=\(merchantID)&id=\(initialAfterSaleID)",
                        authenticated: true, expectedPrincipal: expectedPrincipal) as? [String: Any]
                    guard requestSequence == sequence, store.session?.accessToken == token else { return }
                    if let target { rows.insert(target, at: 0) }
                }
                if let target {
                    deepLinkHandled = true
                    await open(target)
                }
            }
            if expandedID != initialAfterSaleID && !next.contains(where: { Self.text($0["Id"] ?? $0["id"]) == expandedID }) { expandedID = ""; detail = nil }
        } catch is CancellationError {
            if requestSequence == sequence { loading = false }
        } catch {
            guard requestSequence == sequence, store.session?.accessToken == token else { return }
            self.error = error.localizedDescription
        }
        if requestSequence == sequence { loading = false }
    }

    private func open(_ row: [String: Any]) async {
        let id = Self.text(row["Id"] ?? row["id"])
        guard !id.isEmpty, !detailLoading, let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        if expandedID == id { expandedID = ""; detail = nil; message = ""; reason = ""; return }
        detailSequence += 1
        let sequence = detailSequence
        expandedID = id; detail = nil; message = ""; reason = ""; detailLoading = true
        do {
            let value = try await MobileAPI(store: store).get("/api/JHCTIMerchantOrder/GetAfterSaleCase?merchantId=\(merchantID)&id=\(id)", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any]
            guard detailSequence == sequence, store.session?.accessToken == token, let value else {
                throw MobileAPIError.unavailable("售后详情响应格式异常。")
            }
            detail = value
        } catch {
            if detailSequence == sequence && store.session?.accessToken == token { expandedID = ""; self.error = error.localizedDescription }
        }
        if detailSequence == sequence { detailLoading = false }
    }

    private func verifyUncertain(_ row: [String: Any]) async {
        let id = Self.text(row["Id"] ?? row["id"])
        guard id == uncertainActionID, !detailLoading, let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        detailSequence += 1
        let sequence = detailSequence
        detailLoading = true
        do {
            guard let value = try await MobileAPI(store: store).get(
                "/api/JHCTIMerchantOrder/GetAfterSaleCase?merchantId=\(merchantID)&id=\(id)", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any],
                detailSequence == sequence, store.session?.accessToken == token else {
                throw MobileAPIError.unavailable("售后详情读取失败，保护仍然有效。")
            }
            expandedID = id; detail = value; uncertainReadbackVerified = true
            error = "已重新读取服务端详情；请核对后再决定是否解除保护。"
        } catch {
            if detailSequence == sequence && store.session?.accessToken == token {
                uncertainReadbackVerified = false; self.error = error.localizedDescription
            }
        }
        if detailSequence == sequence { detailLoading = false }
    }

    private func submit(_ row: [String: Any], status: String?) async {
        guard !submitting, let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        let id = Self.text(row["Id"] ?? row["id"])
        guard uncertainActionID.isEmpty else { error = "存在结果未知的售后操作，请先核对详情并明确解除保护。"; return }
        let content = (status == nil ? message : reason).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !content.isEmpty, content.count <= 1000 else {
            error = content.isEmpty ? "请填写留言或处理说明。" : "内容不能超过 1000 字。"; return
        }
        submitting = true; error = nil
        var committed = false
        do {
            if let status {
                _ = try await MobileAPI(store: store).post("/api/JHCTIMerchantOrder/UpdateAfterSaleStatus?merchantId=\(merchantID)",
                    body: ["AfterSaleId": id, "Status": status, "Reason": content], authenticated: true,
                    expectedPrincipal: expectedPrincipal)
            } else {
                _ = try await MobileAPI(store: store).post("/api/JHCTIMerchantOrder/AddAfterSaleMessage?merchantId=\(merchantID)",
                    body: ["AfterSaleId": id, "Content": content, "EvidenceUrls": []], authenticated: true,
                    expectedPrincipal: expectedPrincipal)
            }
            guard store.session?.accessToken == token else { return }
            committed = true
            message = ""; reason = ""
            await load(page: 1)
            if error != nil { throw MobileAPIError.unavailable("售后列表刷新失败") }
            if expandedID == id {
                guard let refreshed = try await MobileAPI(store: store).get("/api/JHCTIMerchantOrder/GetAfterSaleCase?merchantId=\(merchantID)&id=\(id)",
                    authenticated: true, expectedPrincipal: expectedPrincipal) as? [String: Any] else {
                    throw MobileAPIError.unavailable("售后详情刷新失败")
                }
                detail = refreshed
            }
        } catch {
            if store.session?.accessToken == token {
                if !committed {
                    uncertainActionID = id; uncertainReadbackVerified = false
                    UserDefaults.standard.set(id, forKey: nativeMerchantAfterSaleLockStorageKey(accessToken: token, merchantID: merchantID))
                    self.error = "提交结果未知。草稿已保留；请核对最新详情，确认上次操作未生效后再解除保护。"
                } else {
                    self.error = "操作已提交，但售后信息刷新失败，请重新加载核对状态。"
                }
            }
        }
        submitting = false
    }

    private static func text(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return value as? String ?? String(describing: value)
    }
    private static func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }
}
