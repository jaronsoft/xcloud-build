import Foundation
import SwiftUI

private struct NativeAfterSaleAction: Identifiable {
    let row: [String: Any]
    let status: String
    var id: String { "\(row["Id"] ?? "")-\(status)" }
}

private struct NativeAfterSaleAttempt: NativeMerchantRecoveryRecord {
    let caseID: String
    let marker: String
    var orderID = ""
    var merchantOrderID = ""
    // 旧版记录未发送请求号，需要按原售后详情人工核对。
    var action: String? = nil

    var requestID: String { marker.replacingOccurrences(of: "-", with: "").lowercased() }

    var valid: Bool {
        trackingID(caseID) && UUID(uuidString: marker)?.uuidString == marker && trackingID(orderID)
            && (merchantOrderID == "0" || trackingID(merchantOrderID))
            && (action.map { ["message", "Negotiating", "ReturnRequired", "ReturnReceived"].contains($0) } ?? true)
    }
}

private func afterSaleReceiptMessageID(_ value: Any, caseID: String) throws -> String {
    guard let row = value as? [String: Any], trackingField(row, "AfterSaleId") as? String == caseID,
          let messageID = trackingField(row, "MessageId") as? String, messageID == "0" || trackingID(messageID) else {
        throw MobileAPIError.unavailable("售后核对回执与原售后单不匹配。")
    }
    return messageID
}

private func validAfterSaleDetail(_ row: [String: Any], id: String, expected: [String: Any]?) -> Bool {
    guard trackingField(row, "Id") as? String == id,
          let order = trackingField(row, "OrderId") as? String, trackingID(order),
          let child = trackingField(row, "MerchantOrderId") as? String, child == "0" || trackingID(child),
          let status = trackingField(row, "Status") as? String, !status.isEmpty,
          let requestType = trackingField(row, "RequestType") as? String, ["RefundOnly", "ReturnAndRefund"].contains(requestType),
          trackingField(row, "Items") is [[String: Any]],
          let messages = trackingField(row, "Messages") as? [[String: Any]] else { return false }
    if let expected, trackingField(expected, "OrderId") as? String != order
        || trackingField(expected, "MerchantOrderId") as? String != child { return false }
    return messages.allSatisfy { message in
        guard let id = trackingField(message, "Id") as? String, trackingID(id) else { return false }
        return trackingField(message, "Content") is String && trackingField(message, "SenderType") is String
    }
}

@MainActor
private struct NativeAfterSaleProtection {
    static var writing = Set<String>()
    let legacyKey: String
    let storage: NativeMerchantRecoveryStore<NativeAfterSaleAttempt>

    init(token: String, merchantID: String) {
        legacyKey = nativeMerchantAfterSaleLockStorageKey(accessToken: token, merchantID: merchantID)
        storage = .init(directoryName: "merchant-after-sale", principal: legacyKey, merchantID: merchantID)
    }

    func read() -> NativeMerchantRecoveryState<NativeAfterSaleAttempt> {
        // 旧版只保存售后单编号，仍须先回查旧记录。
        if let legacy = UserDefaults.standard.object(forKey: legacyKey) {
            guard let id = legacy as? String, trackingID(id) else { return .damaged }
            return .pending(.init(caseID: id, marker: "legacy"))
        }
        return storage.read()
    }

    func clear(_ attempt: NativeAfterSaleAttempt) -> Bool {
        guard read() == .pending(attempt) else { return false }
        if attempt.marker == "legacy" {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return UserDefaults.standard.object(forKey: legacyKey) == nil
        }
        return storage.clear(.pending(attempt))
    }
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
    @State private var protection = NativeMerchantRecoveryState<NativeAfterSaleAttempt>.unavailable
    @State private var uncertainReadbackVerified = false
    @State private var recoveredCaseID = ""
    @State private var recoveryNotice: String?

    private let statuses = [("", "全部"), ("PendingReview", "待协同"), ("Negotiating", "协商中"),
        ("ReturnRequired", "待退货"), ("ReturnInTransit", "运输中"), ("ReturnReceived", "已收货"),
        ("ApprovedForRefund", "待退款"), ("RefundProcessing", "退款中"), ("Refunded", "已退款"),
        ("Rejected", "已拒绝"), ("Closed", "已关闭")]

    private var uncertainActionID: String {
        if case let .pending(attempt) = protection { return attempt.caseID }
        return ""
    }

    private var recoveryDetail: [String: Any]? {
        expandedID == recoveredCaseID && !recoveredCaseID.isEmpty ? detail : nil
    }

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
                                .disabled(submitting || detailLoading)
                        }
                    }
                }
                StatusView(loading: loading, error: error) { revision += 1 }
                if !uncertainActionID.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("待核对售后单 \(uncertainActionID)").font(.headline)
                        Button("核对原售后操作") {
                            Task { await verifyUncertain(uncertainActionID) }
                        }.disabled(submitting || detailLoading)
                    }.merchantCard()
                } else if protection == .damaged || protection == .unavailable {
                    Button("待核对记录无法读取，点击重试") { restoreUncertainAction() }
                        .disabled(submitting || detailLoading)
                }
                if let recoveryDetail { afterSaleCard(recoveryDetail) }
                if !loading && error == nil && rows.isEmpty && recoveryDetail == nil { Text("暂无售后申请。").foregroundStyle(Brand.muted) }
                ForEach(rows.indices, id: \.self) { index in
                    if recoveryDetail == nil || Self.caseID(rows[index]) != recoveredCaseID { afterSaleCard(rows[index]) }
                }
                if !loading && error == nil && rows.count < total {
                    Button("加载更多（\(rows.count)/\(total)）") { Task { await load(page: page + 1) } }
                        .disabled(submitting).frame(maxWidth: .infinity)
                }
            }.padding(16)
        }
        .background(Brand.background)
        .navigationTitle("商户售后协同")
        .task(id: revision) { await load(page: 1) }
        .task(id: "\(merchantID)-\(nativeTourismPrincipal(store.session?.accessToken) ?? "")") { restoreUncertainAction() }
        .onChange(of: nativeTourismPrincipal(store.session?.accessToken)) { _, _ in dismiss() }
        .onDisappear { detailSequence += 1; requestSequence += 1; detailLoading = false; uncertainReadbackVerified = false }
        .confirmationDialog(actionLabel, isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
            Button(actionLabel, role: pendingAction?.status == "ReturnRequired" ? .destructive : nil) {
                guard let action = pendingAction else { return }
                pendingAction = nil
                if action.status == "ClearUnknown" {
                    let id = Self.caseID(action.row)
                    Task { await verifyUncertain(id, release: true) }
                    return
                }
                Task { await submit(action.row, status: action.status) }
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: {
            Text(pendingAction?.status == "ClearUnknown"
                ? "请确认原操作需要重新提交。系统会再次核对原操作，再决定是否解除保护。"
                : "确认对售后单 \(pendingAction?.row["CaseNo"] as? String ?? "") 执行“\(actionLabel)”？")
        }
    }

    private var actionLabel: String {
        if pendingAction?.status == "ClearUnknown" { return "解除重复提交保护" }
        return pendingAction?.status == "ReturnRequired" ? "要求顾客退货" : "确认已收到退货"
    }

    private func selectStatus(_ status: String) {
        selectedStatus = status
        detailSequence += 1
        detailLoading = false
        uncertainReadbackVerified = false
        recoveredCaseID = ""
        expandedID = ""
        detail = nil
        message = ""; reason = ""
        Task { await load(page: 1, status: status) }
    }

    private func restoreUncertainAction() {
        guard let token = store.session?.accessToken, trackingID(merchantID) else { protection = .unavailable; return }
        protection = NativeAfterSaleProtection(token: token, merchantID: merchantID).read()
        uncertainReadbackVerified = false
        recoveryNotice = nil
    }

    private func afterSaleCard(_ row: [String: Any]) -> some View {
        let id = Self.caseID(row)
        let activeRow = expandedID == id ? detail ?? row : row
        let status = trackingField(activeRow, "Status") as? String ?? ""
        let requestType = trackingField(activeRow, "RequestType") as? String ?? ""
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
                if let recoveryNotice { Text(recoveryNotice).font(.caption).foregroundStyle(Brand.muted) }
                if let detail {
                    afterSaleDetail(detail, detail: detail, status: trackingField(detail, "Status") as? String ?? "",
                                    isReturn: trackingField(detail, "RequestType") as? String == "ReturnAndRefund")
                }
                if uncertainActionID == id {
                    Text("上次操作结果未知。请先检查最新详情；为避免重复留言或处理，当前已锁定本售后单的写操作。")
                        .font(.caption).foregroundStyle(.red)
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
        if statuses.contains(where: { $0.0 == status }) && !["Refunded", "Rejected", "Closed"].contains(status) {
            TextField("给顾客留言，最多 1000 字", text: $message, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
            Button(submitting ? "提交中…" : "发送留言") { Task { await submit(row, status: nil) } }
                .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(submitting || detailLoading || protection != .ready || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        let canNegotiate = ["PendingReview", "Negotiating"].contains(status)
        let canRequireReturn = isReturn && canNegotiate
        let canConfirmReturn = isReturn && status == "ReturnInTransit"
        if canNegotiate || canRequireReturn || canConfirmReturn {
            TextField("处理说明，最多 1000 字", text: $reason, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
            HStack {
                if canNegotiate { Button("标记协商中") { Task { await submit(row, status: "Negotiating") } } }
                if canRequireReturn { Button("要求退货", role: .destructive) { pendingAction = NativeAfterSaleAction(row: row, status: "ReturnRequired") } }
                if canConfirmReturn { Button("确认收到退货") { pendingAction = NativeAfterSaleAction(row: row, status: "ReturnReceived") } }
            }.buttonStyle(.bordered).disabled(submitting || detailLoading || protection != .ready)
        }
        Text("平台退款审批、拒绝申请及渠道退款由客服工作台处理。")
            .font(.caption2).foregroundStyle(Brand.muted)
    }

    private func load(page targetPage: Int, status requestedStatus: String? = nil) async {
        guard trackingID(merchantID), let expectedPrincipal = nativeTourismPrincipal(store.session?.accessToken) else {
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
            guard requestSequence == sequence, nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal else { return }
            guard let result, let data = result["data"] as? [[String: Any]] ?? result["Data"] as? [[String: Any]] else {
                throw MobileAPIError.unavailable("售后列表响应格式异常，请重试。")
            }
            let count = Self.intValue(result["dataCount"] ?? result["DataCount"])
            guard data.count <= 20, count >= data.count, count >= 0,
                  data.allSatisfy({ trackingID(Self.caseID($0)) }) else {
                throw MobileAPIError.unavailable("售后列表分页数据不完整，请刷新后重试。")
            }
            var next = append ? rows : []
            for item in data {
                let id = Self.caseID(item)
                if let index = next.firstIndex(where: { Self.caseID($0) == id }) { next[index] = item }
                else { next.append(item) }
            }
            rows = next; total = count; page = targetPage
            if !deepLinkHandled, trackingID(initialAfterSaleID) {
                var target = next.first(where: { Self.caseID($0) == initialAfterSaleID })
                if target == nil {
                    target = try await readDetail(id: initialAfterSaleID, principal: expectedPrincipal)
                    guard requestSequence == sequence, nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal else { return }
                }
                if let target {
                    deepLinkHandled = true
                    if next.contains(where: { Self.caseID($0) == initialAfterSaleID }) {
                        await open(target)
                    } else if expandedID.isEmpty {
                        recoveredCaseID = initialAfterSaleID
                        expandedID = initialAfterSaleID; detail = target
                    }
                }
            }
            if expandedID != initialAfterSaleID && expandedID != recoveredCaseID
                && !next.contains(where: { Self.caseID($0) == expandedID }) { expandedID = ""; detail = nil }
        } catch is CancellationError {
            if requestSequence == sequence { loading = false }
        } catch {
            guard requestSequence == sequence, nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal else { return }
            self.error = error.localizedDescription
        }
        if requestSequence == sequence { loading = false }
    }

    private func open(_ row: [String: Any]) async {
        let id = Self.caseID(row)
        guard trackingID(id), !submitting, !detailLoading, let expectedPrincipal = nativeTourismPrincipal(store.session?.accessToken) else { return }
        uncertainReadbackVerified = false
        recoveryNotice = nil
        recoveredCaseID = ""
        if expandedID == id { expandedID = ""; detail = nil; message = ""; reason = ""; return }
        detailSequence += 1
        let sequence = detailSequence
        expandedID = id; detail = nil; message = ""; reason = ""; detailLoading = true
        defer { if detailSequence == sequence { detailLoading = false } }
        do {
            let value = try await readDetail(id: id, principal: expectedPrincipal, expected: row)
            guard detailSequence == sequence, nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal else { return }
            detail = value
        } catch {
            if detailSequence == sequence && nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal { expandedID = ""; self.error = error.localizedDescription }
        }
    }

    private func verifyUncertain(_ id: String, release: Bool = false) async {
        guard trackingID(id), !submitting, !detailLoading, let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        let recovery = NativeAfterSaleProtection(token: token, merchantID: merchantID)
        guard case let .pending(attempt) = protection, attempt.caseID == id, recovery.read() == protection else {
            restoreUncertainAction()
            return
        }
        guard !NativeAfterSaleProtection.writing.contains(recovery.legacyKey) else {
            error = "原请求仍在处理中，请稍后核对。"; return
        }
        let reviewed = release && uncertainReadbackVerified ? recoveryDetail : nil
        guard !release || reviewed != nil else { return }
        if expandedID != id { message = ""; reason = "" }
        uncertainReadbackVerified = false
        recoveryNotice = nil
        detailSequence += 1
        let sequence = detailSequence
        detailLoading = true
        defer { if detailSequence == sequence { detailLoading = false } }
        do {
            var messageID = "0"
            if attempt.action != nil {
                let response = try await MobileAPI(store: store).post(
                    "/api/JHCTIMerchantOrder/GetAfterSaleReceipt?merchantId=\(merchantID)",
                    body: ["AfterSaleId": id, "RequestId": attempt.requestID],
                    authenticated: true, expectedPrincipal: expectedPrincipal, canRefresh: false)
                try Task.checkCancellation()
                guard detailSequence == sequence, nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal else { return }
                guard recovery.read() == .pending(attempt) else { restoreUncertainAction(); return }
                messageID = try afterSaleReceiptMessageID(response, caseID: id)
            }
            let expected: [String: Any]? = attempt.marker == "legacy" ? reviewed : [
                "OrderId": attempt.orderID, "MerchantOrderId": attempt.merchantOrderID,
            ]
            let value = try await readDetail(id: id, principal: expectedPrincipal, expected: expected)
            try Task.checkCancellation()
            guard detailSequence == sequence, nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal else { return }
            guard recovery.read() == .pending(attempt) else { restoreUncertainAction(); return }
            recoveredCaseID = id; expandedID = id; detail = value
            if messageID != "0" {
                let messages = trackingField(value, "Messages") as? [[String: Any]] ?? []
                guard messages.contains(where: {
                    trackingField($0, "Id") as? String == messageID && trackingField($0, "SenderType") as? String == "Merchant"
                }) else {
                    throw MobileAPIError.unavailable("原售后单尚未显示回执对应的商户协商记录，请重新核对。")
                }
                if attempt.action == "message" { message = "" } else { reason = "" }
                let cleared = recovery.clear(attempt)
                restoreUncertainAction()
                error = nil
                recoveryNotice = cleared ? "已确认原售后操作写入，无需重提。"
                    : "已确认写入，待核对记录暂时无法清除，请重新读取。"
                return
            }
            if release, let reviewed, NSDictionary(dictionary: reviewed).isEqual(to: value) {
                guard recovery.clear(attempt) else { throw MobileAPIError.unavailable("无法解除保护，请重新读取待核对记录。") }
                restoreUncertainAction()
                error = nil
                recoveryNotice = "已解除本次保护，后续操作需手动提交。"
                return
            }
            uncertainReadbackVerified = true
            error = nil
            recoveryNotice = release ? "详情已有更新，请核对当前内容后再决定。" : nil
        } catch {
            if detailSequence == sequence && nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal {
                self.error = error.localizedDescription
            }
        }
    }

    private func readDetail(id: String, principal: String, expected: [String: Any]? = nil) async throws -> [String: Any] {
        guard trackingID(id), trackingID(merchantID),
              let row = try await MobileAPI(store: store).get(
                "/api/JHCTIMerchantOrder/GetAfterSaleCase?merchantId=\(merchantID)&id=\(id)",
                authenticated: true, expectedPrincipal: principal) as? [String: Any],
              validAfterSaleDetail(row, id: id, expected: expected) else {
            throw MobileAPIError.unavailable("售后详情与原售后单不匹配或格式异常。")
        }
        return row
    }

    private func submit(_ row: [String: Any], status: String?) async {
        guard !submitting, !detailLoading, let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        let id = Self.caseID(row)
        guard trackingID(merchantID), trackingID(id), expandedID == id, let detail, Self.caseID(detail) == id,
              let order = trackingField(detail, "OrderId") as? String, let child = trackingField(detail, "MerchantOrderId") as? String else { return }
        let content = (status == nil ? message : reason).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, content.utf16.count <= 1000 else {
            error = content.isEmpty ? "请填写留言或处理说明。" : "内容不能超过 1000 字。"; return
        }
        let recovery = NativeAfterSaleProtection(token: token, merchantID: merchantID)
        let attempt = NativeAfterSaleAttempt(caseID: id, marker: UUID().uuidString, orderID: order, merchantOrderID: child,
                                            action: status ?? "message")
        guard recovery.read() == .ready, !NativeAfterSaleProtection.writing.contains(recovery.legacyKey),
              recovery.storage.save(attempt) else {
            restoreUncertainAction(); error = "无法保存新的待核对记录，售后操作未发送。"; return
        }
        protection = .pending(attempt)
        NativeAfterSaleProtection.writing.insert(recovery.legacyKey)
        submitting = true; error = nil
        let sequence = detailSequence
        defer { NativeAfterSaleProtection.writing.remove(recovery.legacyKey); submitting = false }
        var committed = false
        do {
            let endpoint: String
            var body: [String: Any] = ["AfterSaleId": id, "IdempotencyKey": attempt.requestID]
            if let status {
                endpoint = "UpdateAfterSaleStatus"
                body["Status"] = status
                body["Reason"] = content
            } else {
                endpoint = "AddAfterSaleMessage"
                body["Content"] = content
                body["EvidenceUrls"] = [String]()
            }
            let response = try await MobileAPI(store: store).post("/api/JHCTIMerchantOrder/\(endpoint)?merchantId=\(merchantID)",
                body: body, authenticated: true, expectedPrincipal: expectedPrincipal, canRefresh: false)
            try Task.checkCancellation()
            guard detailSequence == sequence, nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal else { return }
            guard response as? String == id else { throw MobileAPIError.unavailable("售后写入回执与原售后单不一致。") }
            committed = true
            let cleared = recovery.clear(attempt)
            restoreUncertainAction()
            message = ""; reason = ""
            guard cleared else { error = "操作已提交，但待核对记录清理失败，请回查原售后单。"; return }
            self.detail = nil
            await load(page: 1)
            if error != nil { throw MobileAPIError.unavailable("售后列表刷新失败") }
            if expandedID == id {
                let refreshed = try await readDetail(id: id, principal: expectedPrincipal, expected: detail)
                if detailSequence == sequence && nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal && expandedID == id {
                    self.detail = refreshed
                }
            }
        } catch {
            if detailSequence == sequence && nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal {
                if !committed {
                    restoreUncertainAction()
                    self.error = "提交结果未知，请核对最新售后详情后再决定是否解除保护。"
                } else {
                    self.error = "操作已提交，但售后信息刷新失败，请重新加载核对状态。"
                }
            }
        }
    }

    private static func caseID(_ row: [String: Any]) -> String { trackingField(row, "Id") as? String ?? "" }

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
