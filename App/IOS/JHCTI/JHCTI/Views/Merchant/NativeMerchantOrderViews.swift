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
    @State private var lockedRow = ""
    @State private var lockedSourceStatus = ""
    @State private var lockedReadBackStatus = ""
    @State private var notice: String?
    @State private var digitalCode = ""
    @State private var digitalCodeError: String?
    @State private var digitalCodeBusy = false
    @State private var digitalCodeLocked = false
    @State private var confirmingDigitalCode = false
    @State private var digitalCodeScannerOpen = false
    @State private var digitalCodeScannerToken = ""

    private let filters = [("", "全部"), ("PendingShipment", "待发货"), ("PendingPickup", "待自提"),
                           ("Shipped", "已发货"), ("Completed", "已完成"), ("Closed", "已关闭")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("仅显示当前商户授权范围内的订单商品；履约权限和订单归属由服务端再次校验。")
                    .font(.caption).foregroundStyle(Brand.muted)
                if !initialOrderNo.isEmpty { Text("当前通知关联订单：\(initialOrderNo)").font(.caption).foregroundStyle(Brand.primary) }
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
                if !lockedRow.isEmpty {
                    Text("上一笔履约结果尚未核实。刷新后若仍显示待处理，请核对现场状态并明确确认后再重试。")
                        .font(.caption).foregroundStyle(.orange)
                    Button("查看全部并刷新核对") { status = ""; Task { await load(page: 1, requestedStatus: "") } }
                        .disabled(loading)
                }
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
        .task { await load(page: 1) }
        .onChange(of: store.session?.accessToken) { oldToken, token in
            if nativeTourismPrincipal(oldToken) != nativeTourismPrincipal(token) {
                digitalCode = ""; digitalCodeError = nil; digitalCodeBusy = false; digitalCodeLocked = false
                digitalCodeScannerOpen = false; digitalCodeScannerToken = ""
            }
            if token == nil { dismiss() }
        }
        .onDisappear { requestSequence += 1; rows = []; formRow = ""; pickupCode = ""; digitalCode = "" }
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
        return VStack(alignment: .leading, spacing: 8) {
            HStack { Text((row["SubOrderNo"] ?? row["subOrderNo"] ?? row["OrderNo"] ?? row["orderNo"]) as? String ?? "订单号未知").font(.subheadline.weight(.semibold)); Spacer(); Text(statusLabel(rowStatus)).font(.caption).foregroundStyle(Brand.primary) }
            Text((row["ProductName"] ?? row["productName"]) as? String ?? "商品名称未知").font(.system(size: NativeTypography.size(16), weight: .semibold))
            Text("规格 \((row["SkuCode"] ?? row["skuCode"]) as? String ?? "默认规格") · 数量 \(Self.string(row["Quantity"] ?? row["quantity"] ?? 0)) · \((row["StoreName"] ?? row["storeName"]) as? String ?? "未指定门店")")
                .font(.caption).foregroundStyle(Brand.muted)
            HStack { Text((row["CreateTime"] ?? row["createTime"]) as? String ?? "时间未知"); Spacer(); Text(amount.map { "\((row["MerchantCurrency"] ?? row["merchantCurrency"]) as? String ?? "CNY") \(String(format: "%.2f", $0.doubleValue))" } ?? "金额待确认").fontWeight(.semibold) }
                .font(.caption2).foregroundStyle(Brand.muted)
            if rowStatus == "PendingShipment" && canFulfill && rowId != lockedRow {
                if formRow != rowId {
                    HStack {
                        Button("登记快递") { formRow = rowId; fulfillmentType = "Express"; carrierName = ""; trackingNumber = "" }
                        Button("到店自提") { formRow = rowId; fulfillmentType = "SelfPickup" }
                    }.buttonStyle(.borderedProminent).tint(Brand.primary)
                } else {
                    if fulfillmentType == "Express" {
                        TextField("快递公司", text: $carrierName).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
                        TextField("物流运单号", text: $trackingNumber).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
                    } else { Text("系统会生成自提码并展示给顾客，商户端不会显示自提码。").font(.caption).foregroundStyle(Brand.muted) }
                    HStack {
                        Button(submittingRow == rowId ? "提交中…" : "确认提交") { Task { await ship(rowId: rowId) } }
                            .buttonStyle(.borderedProminent).tint(Brand.primary)
                            .disabled(!submittingRow.isEmpty || (fulfillmentType == "Express" && (carrierName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
                        Button("取消") { formRow = "" }
                            .disabled(!submittingRow.isEmpty)
                    }
                }
            } else if rowStatus == "PendingPickup" && canFulfill && rowId != lockedRow {
                TextField("顾客提供的 8 位自提码", text: $pickupCode).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    .onChange(of: pickupCode) { _, value in pickupCode = String(value.filter(\.isNumber).prefix(8)) }
                Button(submittingRow == rowId ? "核验中…" : "核验并确认交付") { Task { await confirmPickup(orderId: orderId, merchantOrderId: merchantOrderId, rowId: rowId) } }
                    .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(!submittingRow.isEmpty || pickupCode.count != 8)
            } else if rowId == lockedRow, !lockedReadBackStatus.isEmpty, lockedReadBackStatus == lockedSourceStatus,
                      rowStatus == lockedSourceStatus {
                Text("服务端回读仍显示「\(statusLabel(rowStatus))」，上次操作未能确认。请核对现场状态后再决定是否重试。")
                    .font(.caption).foregroundStyle(.orange)
                Button("确认仍未处理，重新开放操作") {
                    lockedRow = ""; lockedSourceStatus = ""; lockedReadBackStatus = ""
                    notice = "已按你的确认重新开放该订单操作。"
                }.buttonStyle(.bordered).tint(Brand.primary).disabled(!submittingRow.isEmpty)
            } else if !canFulfill, let reason = (row["FulfillmentBlockReason"] ?? row["fulfillmentBlockReason"]) as? String, !reason.isEmpty {
                Text(reason).font(.caption).foregroundStyle(Brand.muted)
            }
        }.merchantCard()
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
            total = count; page = targetPage
            if let (lockedOrderId, lockedMerchantOrderId) = ids(lockedRow), let locked = data.first(where: {
                Self.string($0["OrderId"] ?? $0["orderId"]) == lockedOrderId
                    && Self.string($0["MerchantOrderId"] ?? $0["merchantOrderId"] ?? "0") == lockedMerchantOrderId
            }) {
                let readBackStatus = (locked["MerchantOrderStatus"] ?? locked["merchantOrderStatus"]
                    ?? locked["OrderStatus"] ?? locked["orderStatus"]) as? String ?? ""
                lockedReadBackStatus = readBackStatus
                let knownStatuses = ["PendingPayment", "PendingShipment", "PendingPickup", "Shipped", "Completed", "Closed"]
                if knownStatuses.contains(readBackStatus), !lockedSourceStatus.isEmpty, readBackStatus != lockedSourceStatus {
                    lockedRow = ""; lockedSourceStatus = ""; lockedReadBackStatus = ""
                    notice = "已根据服务端订单状态核实上一笔履约已离开待处理状态。"
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, requestSequence == sequence, store.session?.accessToken == token else { return }
            self.error = error.localizedDescription
        }
    }

    private func ship(rowId: String) async {
        guard let (orderId, merchantOrderId) = ids(rowId), let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        submittingRow = rowId; notice = nil
        do {
            _ = try await MobileAPI(store: store).post("/api/JHCTIMerchantOrder/Ship?merchantId=\(merchantID)", body: [
                "OrderId": orderId, "MerchantOrderId": merchantOrderId, "FulfillmentType": fulfillmentType,
                "CarrierName": fulfillmentType == "Express" ? carrierName.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                "TrackingNumber": fulfillmentType == "Express" ? trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            ], authenticated: true, expectedPrincipal: expectedPrincipal)
            guard store.session?.accessToken == token else { return }
            formRow = ""; notice = "履约信息已提交，列表已刷新。"; await load(page: 1)
        } catch {
            guard store.session?.accessToken == token else { return }
            lockedRow = rowId; lockedSourceStatus = "PendingShipment"; lockedReadBackStatus = ""
            formRow = ""; self.error = "履约结果未确认。请刷新全部订单核对状态，确认前不要重复提交。"
            status = ""; await load(page: 1, requestedStatus: "")
        }
        submittingRow = ""
    }

    private func confirmPickup(orderId: String, merchantOrderId: String, rowId: String) async {
        guard Self.validId(orderId), Self.validId(merchantOrderId), pickupCode.count == 8,
              let token = store.session?.accessToken, let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        submittingRow = rowId; notice = nil
        do {
            _ = try await MobileAPI(store: store).post("/api/JHCTIMerchantOrder/ConfirmPickup?merchantId=\(merchantID)", body: [
                "OrderId": orderId, "MerchantOrderId": merchantOrderId, "PickupCode": pickupCode
            ], authenticated: true, expectedPrincipal: expectedPrincipal)
            guard store.session?.accessToken == token else { return }
            pickupCode = ""; notice = "自提交付已确认，列表已刷新。"; await load(page: 1)
        } catch {
            guard store.session?.accessToken == token else { return }
            pickupCode = ""; lockedRow = rowId; lockedSourceStatus = "PendingPickup"; lockedReadBackStatus = ""
            self.error = "自提交付结果未确认。请刷新全部订单核对状态，确认前不要重复提交。"
            status = ""; await load(page: 1, requestedStatus: "")
        }
        submittingRow = ""
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
