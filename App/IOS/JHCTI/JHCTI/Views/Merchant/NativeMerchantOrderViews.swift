import AVFoundation
import Foundation
import SwiftUI
import VisionKit

struct NativeMerchantOrdersView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let merchantID: String
    var initialOrderNo: String = ""
    @State private var rows: [[String: Any]] = []
    @State private var status = ""
    @State private var page = 1
    @State private var total = 0
    @State private var loading = true
    @State private var error: String?
    @State private var requestSequence = 0
    @State private var submittingRow = ""
    @State private var formRow = ""
    @State private var fulfillmentType = "Express"
    @State private var carrierName = ""
    @State private var trackingNumber = ""
    @State private var pickupCode = ""
    @StateObject private var fulfillmentRecovery = NativeMerchantFulfillmentRecovery()
    @State private var confirmingFulfillmentRelease = false
    @State private var notice: String?
    @State private var digitalCode = ""
    @State private var digitalCodeError: String?
    @State private var digitalCodeBusy = false
    @State private var digitalCodeLocked = false
    @State private var confirmingDigitalCode = false
    @State private var digitalCodeScannerOpen = false
    @State private var digitalCodeScannerToken = ""
    @State private var trackingDestination: NativeMerchantTrackingDestination?
    @State private var trackingOwner = ""
    @State private var orderRowsOwner = ""

    private let filters = [("", "全部"), ("PendingShipment", "待发货"), ("PendingPickup", "待自提"),
                           ("Shipped", "已发货"), ("Completed", "已完成"), ("Closed", "已关闭")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("仅显示当前商户授权范围内的订单商品；履约权限和订单归属由服务端再次校验。")
                    .font(.caption).foregroundStyle(Brand.muted)
                if !initialOrderNo.isEmpty { Text("当前通知关联订单：\(initialOrderNo)").font(.caption).foregroundStyle(Brand.primary) }
                Button("核对物流补录") { openTracking(.recovery) }
                    .buttonStyle(.bordered).disabled(!submittingRow.isEmpty || digitalCodeBusy)
                VStack(alignment: .leading, spacing: 9) {
                    Text("虚拟商品券码核验").font(.subheadline.weight(.semibold))
                    Text("核对顾客本人订单中的 32 位平台券码。成功后立即失效；核验权限和券码状态由服务端校验。")
                        .font(.caption).foregroundStyle(Brand.muted)
                    if DataScannerViewController.isSupported {
                        Button("扫描电子券码") { Task { await requestDigitalCodeScannerAccess() } }
                            .buttonStyle(.bordered).disabled(digitalCodeBusy || digitalCodeLocked)
                    } else {
                        Text("此设备暂不支持扫码，可手动输入券码。")
                            .font(.caption).foregroundStyle(Brand.muted)
                    }
                    TextField("输入 32 位平台券码", text: $digitalCode)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .disabled(digitalCodeBusy || digitalCodeLocked)
                        .onChange(of: digitalCode) { _, value in
                            digitalCode = String(value.uppercased().filter { "0123456789ABCDEF".contains($0) }.prefix(32))
                            digitalCodeError = nil
                        }
                    if let digitalCodeError { Text(digitalCodeError).font(.caption).foregroundStyle(.red) }
                    if digitalCodeLocked {
                        Text("上次核验结果未确认。请先核对券码状态；确认尚未核销后再开放重试。")
                            .font(.caption).foregroundStyle(.orange)
                        Button("已核实未核销，允许重试") {
                            digitalCodeLocked = false
                            notice = "请重新扫描或输入已核实的券码。"
                        }.buttonStyle(.bordered)
                    } else {
                        Button(digitalCodeBusy ? "正在核验…" : "核对并核销券码") {
                            confirmingDigitalCode = true
                        }
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                        .disabled(digitalCodeBusy || digitalCode.count != 32)
                    }
                }.merchantCard()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.0) { item in
                            Button(item.1) {
                                guard status != item.0, submittingRow.isEmpty else { return }
                                status = item.0; formRow = ""; Task { await load(page: 1, requestedStatus: item.0) }
                            }.buttonStyle(.bordered).tint(status == item.0 ? Brand.primary : Brand.muted)
                                .disabled(!submittingRow.isEmpty)
                        }
                    }
                }
                if let notice { Text(notice).font(.caption).foregroundStyle(Brand.primary) }
                fulfillmentRecoveryPanel
                if loading && rows.isEmpty { ProgressView("正在读取商户订单…") }
                if let error { StatusView(loading: false, error: error) { Task { await load(page: 1) } } }
                if !loading && error == nil && rows.isEmpty { Text("暂无相关订单").foregroundStyle(Brand.muted) }
                ForEach(rows.indices, id: \.self) { index in orderCard(rows[index]) }
                if rows.count < total && error == nil {
                    Button(loading ? "正在加载…" : "加载更多（\(rows.count)/\(total)）") { Task { await load(page: page + 1) } }
                        .disabled(loading || !submittingRow.isEmpty).frame(maxWidth: .infinity)
                }
            }.padding(16)
        }
        .background(Brand.background)
        .navigationTitle("商户订单")
        .onAppear { fulfillmentRecovery.reload(merchantID: merchantID, store: store) }
        .task { await load(page: 1) }
        .onChange(of: store.session?.accessToken) { oldToken, token in
            if nativeTourismPrincipal(oldToken) != nativeTourismPrincipal(token) {
                resetOrderScope()
                if token != nil { Task { await load(page: 1) } }
            }
            if token == nil { dismiss() }
        }
        .onChange(of: merchantID) {
            resetOrderScope()
            Task { await load(page: 1) }
        }
        .onDisappear {
            requestSequence += 1; rows = []; formRow = ""; pickupCode = ""; digitalCode = ""
            carrierName = ""; trackingNumber = ""; confirmingFulfillmentRelease = false; submittingRow = ""
            fulfillmentRecovery.invalidate()
        }
        .sheet(item: $trackingDestination) { destination in
            NativeMerchantTrackingView(store: store, merchantID: merchantID, principal: trackingOwner, destination: destination)
        }
        .sheet(isPresented: $digitalCodeScannerOpen) {
            NativeActivityQrScanner(inputLabel: "电子券码", onCode: { scanned in
                guard !digitalCodeScannerToken.isEmpty,
                      nativeTourismPrincipal(store.session?.accessToken) == digitalCodeScannerToken else {
                    digitalCode = ""; digitalCodeScannerOpen = false; digitalCodeScannerToken = ""
                    digitalCodeError = "登录账号已变化，请重新进入商户订单页后扫码。"
                    return
                }
                let value = scanned.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if value.range(of: "^[0-9A-F]{32}$", options: .regularExpression) != nil {
                    digitalCode = value
                } else {
                    digitalCode = ""; digitalCodeError = "二维码不是有效的 32 位电子券码，请手动核对。"
                }
                digitalCodeScannerOpen = false; digitalCodeScannerToken = ""
            }, onFailure: { message in
                guard !digitalCodeScannerToken.isEmpty,
                      nativeTourismPrincipal(store.session?.accessToken) == digitalCodeScannerToken else {
                    digitalCodeScannerOpen = false; digitalCodeScannerToken = ""; return
                }
                digitalCodeError = message; digitalCodeScannerOpen = false; digitalCodeScannerToken = ""
            }).ignoresSafeArea()
        }
        .confirmationDialog("确认核验此电子券码？", isPresented: $confirmingDigitalCode, titleVisibility: .visible) {
            Button("确认核销", role: .destructive) { Task { await redeemDigitalCode() } }
            Button("再核对一下", role: .cancel) { confirmingDigitalCode = false }
        } message: {
            Text("核验成功后该码立即失效，且不可重复使用。请先核对顾客本人订单和券码。")
        }
    }

    private func orderCard(_ row: [String: Any]) -> some View {
        let orderId = Self.string(row["OrderId"] ?? row["orderId"])
        let merchantOrderId = Self.string(row["MerchantOrderId"] ?? row["merchantOrderId"] ?? "0")
        let rowId = "\(orderId):\(merchantOrderId)"
        let rowStatus = (row["MerchantOrderStatus"] ?? row["merchantOrderStatus"] ?? row["OrderStatus"] ?? row["orderStatus"]) as? String ?? ""
        let canFulfill = (row["CanFulfill"] ?? row["canFulfill"]) as? Bool == true
        let amount = (row["LineAmount"] ?? row["lineAmount"]) as? NSNumber
        let orderLabel = (row["SubOrderNo"] ?? row["subOrderNo"] ?? row["OrderNo"] ?? row["orderNo"]) as? String ?? "订单号未知"
        return VStack(alignment: .leading, spacing: 8) {
            HStack { Text(orderLabel).font(.subheadline.weight(.semibold)); Spacer(); Text(statusLabel(rowStatus)).font(.caption).foregroundStyle(Brand.primary) }
            Text((row["ProductName"] ?? row["productName"]) as? String ?? "商品名称未知").font(.system(size: NativeTypography.size(16), weight: .semibold))
            Text("规格 \((row["SkuCode"] ?? row["skuCode"]) as? String ?? "默认规格") · 数量 \(Self.string(row["Quantity"] ?? row["quantity"] ?? 0)) · \((row["StoreName"] ?? row["storeName"]) as? String ?? "未指定门店")")
                .font(.caption).foregroundStyle(Brand.muted)
            HStack { Text((row["CreateTime"] ?? row["createTime"]) as? String ?? "时间未知"); Spacer(); Text(amount.map { "\((row["MerchantCurrency"] ?? row["merchantCurrency"]) as? String ?? "CNY") \(String(format: "%.2f", $0.doubleValue))" } ?? "金额待确认").fontWeight(.semibold) }
                .font(.caption2).foregroundStyle(Brand.muted)
            if canFulfill, ["PendingPickup", "Shipped", "Completed"].contains(rowStatus),
               let destination = NativeMerchantTrackingDestination.order(from: row, label: orderLabel) {
                Button("查看履约") { openTracking(destination) }.buttonStyle(.bordered)
                    .disabled(!submittingRow.isEmpty || digitalCodeBusy)
            }
            if rowStatus == "PendingShipment" && canFulfill && fulfillmentRecovery.state == .ready {
                if formRow != rowId {
                    HStack {
                        Button("登记快递") { formRow = rowId; fulfillmentType = "Express"; carrierName = ""; trackingNumber = "" }
                        Button("到店自提") { formRow = rowId; fulfillmentType = "SelfPickup" }
                    }.buttonStyle(.borderedProminent).tint(Brand.primary)
                } else {
                    if fulfillmentType == "Express" {
                        TextField("快递公司", text: $carrierName).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
                            .onChange(of: carrierName) { _, value in carrierName = nativeLimitUtf16Text(value, maximum: 100) }
                        TextField("物流运单号", text: $trackingNumber).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
                            .onChange(of: trackingNumber) { _, value in trackingNumber = nativeLimitUtf16Text(value, maximum: 100) }
                    } else { Text("系统会生成自提码并展示给顾客，商户端不会显示自提码。").font(.caption).foregroundStyle(Brand.muted) }
                    HStack {
                        Button(submittingRow == rowId ? "提交中…" : "确认提交") { Task { await ship(rowId: rowId) } }
                            .buttonStyle(.borderedProminent).tint(Brand.primary)
                            .disabled(!submittingRow.isEmpty || (fulfillmentType == "Express" && (carrierName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
                        Button("取消") { formRow = "" }
                            .disabled(!submittingRow.isEmpty)
                    }
                }
            } else if rowStatus == "PendingPickup" && canFulfill && fulfillmentRecovery.state == .ready {
                TextField("顾客提供的 8 位自提码", text: $pickupCode).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    .onChange(of: pickupCode) { _, value in pickupCode = String(value.filter { "0123456789".contains($0) }.prefix(8)) }
                Button(submittingRow == rowId ? "核验中…" : "核验并确认交付") { Task { await confirmPickup(orderId: orderId, merchantOrderId: merchantOrderId, rowId: rowId) } }
                    .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(!submittingRow.isEmpty || pickupCode.count != 8)
            } else if !canFulfill, let reason = (row["FulfillmentBlockReason"] ?? row["fulfillmentBlockReason"]) as? String, !reason.isEmpty {
                Text(reason).font(.caption).foregroundStyle(Brand.muted)
            }
        }.merchantCard()
    }

    @ViewBuilder
    private var fulfillmentRecoveryPanel: some View {
        if fulfillmentRecovery.state != .ready || fulfillmentRecovery.message != nil {
            VStack(alignment: .leading, spacing: 8) {
                switch fulfillmentRecovery.state {
                case .ready: EmptyView()
                case .unavailable:
                    Text("履约待核对记录暂不可读。")
                    Button("重新读取") { fulfillmentRecovery.reload(merchantID: merchantID, store: store) }
                case .damaged:
                    Text("履约待核对记录已损坏，请先核对可能已提交的履约。")
                    Button("已人工核对") { confirmingFulfillmentRelease = true }
                case let .pending(attempt):
                    let reference = attempt.merchantOrderID == "0" ? attempt.orderID : attempt.merchantOrderID
                    Text("\(attempt.kind.title)待核对 · 订单 \(reference)").fontWeight(.semibold)
                    Button("查询原订单履约") { Task { await verifyFulfillment(release: false) } }
                    if fulfillmentRecovery.canRelease {
                        Button("已人工核对") { confirmingFulfillmentRelease = true }
                    }
                }
                if fulfillmentRecovery.busy { ProgressView("正在处理履约记录…") }
                if let message = fulfillmentRecovery.message { Text(message).foregroundStyle(Brand.muted) }
            }.font(.callout).buttonStyle(.bordered).disabled(fulfillmentRecovery.busy).merchantCard()
                .confirmationDialog("解除履约待核对状态？", isPresented: $confirmingFulfillmentRelease, titleVisibility: .visible) {
                    Button("确认已核对") { Task { await verifyFulfillment(release: true) } }
                    Button("取消", role: .cancel) {}
                } message: { Text("请先确认原操作尚未实际完成，再恢复办理。") }
        }
    }

    private func verifyFulfillment(release: Bool) async {
        if await fulfillmentRecovery.verify(merchantID: merchantID, store: store, release: release) {
            await load(page: 1)
        }
    }

    private func resetOrderScope() {
        requestSequence += 1; rows = []; total = 0; orderRowsOwner = ""; notice = nil; submittingRow = ""
        formRow = ""; pickupCode = ""; carrierName = ""; trackingNumber = ""
        digitalCode = ""; digitalCodeError = nil; digitalCodeBusy = false; digitalCodeLocked = false
        digitalCodeScannerOpen = false; digitalCodeScannerToken = ""; confirmingDigitalCode = false
        trackingDestination = nil; confirmingFulfillmentRelease = false
        fulfillmentRecovery.invalidate()
        fulfillmentRecovery.reload(merchantID: merchantID, store: store)
    }

    private func openTracking(_ destination: NativeMerchantTrackingDestination) {
        guard let principal = nativeTourismPrincipal(store.session?.accessToken) else { return }
        if case .order = destination, orderRowsOwner != principal { return }
        trackingOwner = principal
        trackingDestination = destination
    }

    private func load(page targetPage: Int, requestedStatus: String? = nil) async {
        guard !merchantID.isEmpty, merchantID.allSatisfy(\.isNumber), let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else {
            error = "商户或登录范围无效，请返回工作台重新进入。"; loading = false; return
        }
        requestSequence += 1; let sequence = requestSequence; let append = targetPage > 1
        let activeStatus = requestedStatus ?? status; loading = true; error = nil
        defer { if requestSequence == sequence { loading = false } }
        if !append { rows = []; page = 1 }
        do {
            let encoded = activeStatus.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))) ?? ""
            let encodedOrderNo = initialOrderNo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))) ?? ""
            let orderSuffix = encodedOrderNo.isEmpty ? "" : "&orderNo=\(encodedOrderNo)"
            let result = try await MobileAPI(store: store).get("/api/JHCTIMerchantOrder/GetLines?merchantId=\(merchantID)&page=\(targetPage)&pageSize=20\(encoded.isEmpty ? "" : "&status=\(encoded)")\(orderSuffix)", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any]
            try Task.checkCancellation()
            guard requestSequence == sequence, store.session?.accessToken == token, let result,
                  let data = result["data"] as? [[String: Any]] ?? result["Data"] as? [[String: Any]] else {
                throw MobileAPIError.unavailable("订单列表响应格式异常，请重试。")
            }
            let count = Int(Self.string(result["dataCount"] ?? result["DataCount"] ?? -1)) ?? -1
            guard data.count <= 20, count >= data.count, count >= 0,
                  data.allSatisfy({ Self.validId($0["OrderItemId"] ?? $0["orderItemId"]) && Self.validId($0["OrderId"] ?? $0["orderId"]) }) else {
                throw MobileAPIError.unavailable("订单分页或编号格式异常，请刷新后重试。")
            }
            rows = append ? (rows + data).uniqued(by: { Self.string($0["OrderItemId"] ?? $0["orderItemId"]) }) : data
            orderRowsOwner = expectedPrincipal
            total = count; page = targetPage
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, requestSequence == sequence, store.session?.accessToken == token else { return }
            self.error = error.localizedDescription
        }
    }

    private func ship(rowId: String) async {
        guard let (orderID, merchantOrderID) = ids(rowId),
              let kind = NativeMerchantFulfillmentAttempt.Kind(rawValue: fulfillmentType), kind != .handover else { return }
        let carrier = carrierName.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind != .express || !carrier.isEmpty && !number.isEmpty else { return }
        await submitFulfillment(.init(orderID: orderID, merchantOrderID: merchantOrderID, kind: kind), rowId: rowId, body: [
            "OrderId": orderID, "MerchantOrderId": merchantOrderID, "FulfillmentType": kind.rawValue,
            "CarrierName": kind == .express ? carrier : "", "TrackingNumber": kind == .express ? number : ""
        ])
    }

    private func confirmPickup(orderId: String, merchantOrderId: String, rowId: String) async {
        guard pickupCode.count == 8, pickupCode.allSatisfy({ "0123456789".contains($0) }) else { return }
        await submitFulfillment(.init(orderID: orderId, merchantOrderID: merchantOrderId, kind: .handover), rowId: rowId,
            body: ["OrderId": orderId, "MerchantOrderId": merchantOrderId, "PickupCode": pickupCode])
    }

    private func submitFulfillment(_ attempt: NativeMerchantFulfillmentAttempt, rowId: String, body: [String: String]) async {
        let requiredStatus = attempt.kind == .handover ? "PendingPickup" : "PendingShipment"
        guard submittingRow.isEmpty, fulfillmentRecovery.state == .ready, !fulfillmentRecovery.busy, !loading,
              let principal = nativeTourismPrincipal(store.session?.accessToken), orderRowsOwner == principal,
              rows.contains(where: { row in
                  trackingField(row, "OrderId") as? String == attempt.orderID
                      && trackingField(row, "MerchantOrderId") as? String == attempt.merchantOrderID
                      && trackingField(row, "CanFulfill") as? Bool == true
                      && (trackingField(row, "MerchantOrderStatus") as? String
                          ?? trackingField(row, "OrderStatus") as? String) == requiredStatus
              }) else { return }
        let sequence = requestSequence
        submittingRow = rowId; notice = nil
        formRow = ""; pickupCode = ""; carrierName = ""; trackingNumber = ""
        let accepted = await fulfillmentRecovery.submit(attempt, body: body, merchantID: merchantID, store: store)
        guard requestSequence == sequence, nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
        submittingRow = ""
        if accepted { await load(page: 1) }
    }

    @MainActor private func requestDigitalCodeScannerAccess() async {
        guard DataScannerViewController.isSupported else { digitalCodeError = "当前设备不支持扫码，请手动输入券码。"; return }
        guard let token = store.session?.accessToken else { digitalCodeError = "请重新登录商户账号。"; return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted = status == .authorized ? true : status == .notDetermined ? await AVCaptureDevice.requestAccess(for: .video) : false
        if granted && DataScannerViewController.isAvailable {
            digitalCodeScannerToken = nativeTourismPrincipal(token) ?? ""; digitalCodeScannerOpen = true
        } else { digitalCodeError = "相机权限未开启或设备不可用，请手动输入券码。" }
    }

    @MainActor private func redeemDigitalCode() async {
        let code = digitalCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !digitalCodeBusy, !digitalCodeLocked,
              code.range(of: "^[0-9A-F]{32}$", options: .regularExpression) != nil,
              let token = store.session?.accessToken, let requestedPrincipal = nativeTourismPrincipal(token),
              merchantID.allSatisfy(\.isNumber), !merchantID.isEmpty else {
            digitalCodeError = "券码或当前商户范围无效，请核对后重试。"; return
        }
        confirmingDigitalCode = false; digitalCodeBusy = true; notice = nil; digitalCodeError = nil
        defer { digitalCodeBusy = false }
        do {
            let result = try await MobileAPI(store: store).post("/api/JHCTIMerchantOrder/RedeemDigitalCode?merchantId=\(merchantID)",
                body: ["Code": code], authenticated: true, expectedPrincipal: requestedPrincipal) as? String
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            guard result.flatMap(Int64.init).map({ $0 > 0 }) == true else {
                throw MobileAPIError.unavailable("服务器未返回有效的核验编号，请先核对券码状态。")
            }
            digitalCode = ""; notice = "券码核验成功，该码已失效。"
        } catch {
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            digitalCode = ""; digitalCodeLocked = true
            digitalCodeError = "核验结果未确认：\(error.localizedDescription) 请先核对券码状态，确认未核销后再开放重试。"
        }
    }

    private func statusLabel(_ status: String) -> String { filters.first(where: { $0.0 == status })?.1 ?? (status.isEmpty ? "状态未知" : status) }
    private static func string(_ value: Any?) -> String { guard let value else { return "" }; return value as? String ?? String(describing: value) }
    private static func validId(_ value: Any?) -> Bool { let value = string(value); return !value.isEmpty && value.allSatisfy(\.isNumber) && value != "0" }
    private func ids(_ rowId: String) -> (String, String)? { let parts = rowId.split(separator: ":", omittingEmptySubsequences: false).map(String.init); guard parts.count == 2, Self.validId(parts[0]), parts[1].allSatisfy(\.isNumber) else { return nil }; return (parts[0], parts[1]) }
}

private extension Array where Element == [String: Any] {
    func uniqued(by key: ([String: Any]) -> String) -> [[String: Any]] {
        var seen = Set<String>(); return filter { seen.insert(key($0)).inserted }
    }
}
