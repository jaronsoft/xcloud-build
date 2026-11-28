import SwiftUI

enum NativeMerchantTrackingDestination: Identifiable {
    case recovery
    case order(orderID: String, merchantOrderID: String, label: String)

    var id: String {
        switch self {
        case .recovery: "recovery"
        case let .order(orderID, merchantOrderID, _): "\(orderID):\(merchantOrderID)"
        }
    }

    static func order(from row: [String: Any], label: String) -> Self? {
        guard let orderID = trackingField(row, "OrderId") as? String, trackingID(orderID),
              let merchantOrderID = trackingField(row, "MerchantOrderId") as? String,
              merchantOrderID == "0" || trackingID(merchantOrderID) else { return nil }
        return .order(orderID: orderID, merchantOrderID: merchantOrderID, label: label)
    }
}

func trackingID(_ value: String) -> Bool {
    Int64(value).map { $0 > 0 && String($0) == value } == true
}

func trackingField(_ row: [String: Any], _ name: String) -> Any? {
    let lowerName = name.prefix(1).lowercased() + name.dropFirst()
    let primary = row[name], alternate = row[lowerName]
    if let primary, let alternate {
        guard let first = try? JSONSerialization.data(withJSONObject: [primary], options: [.sortedKeys]),
              let second = try? JSONSerialization.data(withJSONObject: [alternate], options: [.sortedKeys]),
              first == second else { return nil }
    }
    return primary ?? alternate
}

private func trackingTime(_ value: Any?) -> String? {
    guard let text = value as? String else { return nil }
    return bookingBusinessDateTime(text.replacingOccurrences(of: " ", with: "T"))
}

struct NativeMerchantShipment: Identifiable {
    struct Event: Identifiable {
        let id: String
        let description: String
        let time: String
    }

    let id: String
    let type: String
    let status: String
    let carrier: String?
    let trackingNumber: String?
    let shippedAt: String
    let events: [Event]

    var canRecord: Bool { type == "Express" && status == "InTransit" }
    var statusLabel: String {
        switch status {
        case "InTransit": "运输中"
        case "Delivered": "已送达"
        case "ReadyForPickup": "待自提"
        default: "已自提"
        }
    }

    static func list(_ value: Any, orderID: String, merchantOrderID: String) throws -> [Self] {
        let invalid = MobileAPIError.unavailable("履约回执格式或订单归属异常，请重新读取。")
        guard let rows = value as? [[String: Any]] else { throw invalid }
        var shipmentIDs = Set<String>()
        return try rows.map { row in
            guard let id = trackingField(row, "Id") as? String, trackingID(id), shipmentIDs.insert(id).inserted,
                  trackingField(row, "OrderId") as? String == orderID,
                  trackingField(row, "MerchantOrderId") as? String == merchantOrderID,
                  let type = trackingField(row, "FulfillmentType") as? String,
                  let status = trackingField(row, "Status") as? String,
                  (type == "Express" && ["InTransit", "Delivered"].contains(status))
                    || (type == "SelfPickup" && ["ReadyForPickup", "PickedUp"].contains(status)),
                  let shippedAt = trackingTime(trackingField(row, "ShippedAt")),
                  let carrier = trackingField(row, "CarrierName"), carrier is NSNull || carrier is String,
                  let number = trackingField(row, "TrackingNumber"), number is NSNull || number is String,
                  let eventRows = trackingField(row, "Events") as? [[String: Any]] else { throw invalid }
            var eventIDs = Set<String>()
            let events = try eventRows.map { event in
                guard let eventID = trackingField(event, "Id") as? String, trackingID(eventID), eventIDs.insert(eventID).inserted,
                      let description = trackingField(event, "Description") as? String,
                      !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let time = trackingTime(trackingField(event, "EventTime")) else { throw invalid }
                return Event(id: eventID, description: description, time: time)
            }
            return Self(id: id, type: type, status: status, carrier: carrier as? String,
                        trackingNumber: number as? String, shippedAt: shippedAt, events: events)
        }
    }
}

private struct NativeTrackingAttempt: NativeMerchantRecoveryRecord {
    let shipmentID: String
    let requestID: String

    var valid: Bool {
        trackingID(shipmentID) && requestID.utf8.count == 32 && requestID.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

private typealias NativeTrackingRecovery = NativeMerchantRecoveryState<NativeTrackingAttempt>

struct NativeMerchantTrackingView: View {
    private enum Confirmation: Equatable { case record(String), release }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SessionStore
    let merchantID: String
    let principal: String
    let destination: NativeMerchantTrackingDestination
    @State private var shipments: [NativeMerchantShipment] = []
    @State private var recovery = NativeTrackingRecovery.unavailable
    @State private var canRelease = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var notice: String?
    @State private var editorID: String?
    @State private var draft = ""
    @State private var confirmation: Confirmation?
    @State private var confirming = false
    @State private var operation: Task<Void, Never>?
    @State private var visible = false

    private var storage: NativeMerchantRecoveryStore<NativeTrackingAttempt> {
        .init(directoryName: "jhcti-merchant-tracking-v1", principal: principal, merchantID: merchantID)
    }
    private var validScope: Bool {
        trackingID(merchantID) && !principal.isEmpty && nativeTourismPrincipal(store.session?.accessToken) == principal
    }
    private var current: Bool { visible && scenePhase == .active && validScope && !Task.isCancelled }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !validScope {
                        Text("登录或商户范围已变化，请重新进入商户订单。").foregroundStyle(.red)
                    } else {
                        if recovery != .ready || destination.id == "recovery" { recoveryPanel }
                        if operation != nil && !loading { ProgressView("正在处理物流记录…") }
                        if let notice { Text(notice).font(.callout).foregroundStyle(Brand.primary) }
                        if case let .order(_, _, label) = destination {
                            Text(label).font(.headline)
                            if loading { ProgressView("正在读取履约记录…") }
                            if let loadError {
                                StatusView(loading: false, error: loadError) { run { await load() } }
                            } else if !loading && shipments.isEmpty {
                                Text("暂无履约记录").foregroundStyle(Brand.muted)
                            }
                            ForEach(shipments) { shipment in shipmentCard(shipment) }
                        }
                    }
                }.padding(16)
            }
            .background(Brand.background)
            .navigationTitle(destination.id == "recovery" ? "核对物流补录" : "订单履约")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .onAppear { visible = true; activate() }
        .onDisappear { visible = false; deactivate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { activate() } else { deactivate() }
        }
        .onChange(of: validScope) { _, valid in
            if !valid { deactivate(); shipments = []; recovery = .unavailable }
        }
        .confirmationDialog(confirmation == .release ? "解除待核对状态？" : "确认记录物流进度？",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(confirmation == .release ? "确认已核对" : "确认记录") {
                let selection = confirmation
                confirmation = nil
                switch selection {
                case let .record(id): run { await submit(id: id) }
                case .release: run { await verify(release: true) }
                case nil: break
                }
            }
            Button("取消", role: .cancel) { confirmation = nil }
        } message: {
            Text(confirmation == .release
                 ? "请先核对履约轨迹，确认这次操作没有记录后再继续。"
                 : "提交前请核对运单和填写的进度。")
        }
    }

    private var recoveryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch recovery {
            case .ready: Text("没有待核对的物流补录。")
            case .unavailable:
                Text("暂时无法读取待核对记录。")
                Button("重新读取") { activate() }
            case .damaged:
                Text("本机待核对记录已损坏。请核对履约轨迹后解除限制。")
                Button("已人工核对") { confirm(.release) }
            case let .pending(attempt):
                Text("履约单 \(attempt.shipmentID) 的物流补录待核对。")
                Button("查询原请求") { run { await verify(release: false) } }
                if canRelease { Button("已人工核对") { confirm(.release) } }
            }
        }
        .font(.callout)
        .buttonStyle(.bordered)
        .disabled(operation != nil)
        .merchantCard()
    }

    private func shipmentCard(_ shipment: NativeMerchantShipment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(shipment.type == "Express" ? "快递配送" : "到店自提") · \(shipment.statusLabel)").font(.headline)
            if let carrier = shipment.carrier, !carrier.isEmpty { Text(carrier) }
            if let number = shipment.trackingNumber, !number.isEmpty { Text(number).textSelection(.enabled) }
            Text("登记于 \(shipment.shippedAt)").font(.caption).foregroundStyle(Brand.muted)
            ForEach(shipment.events) { event in
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.description).fixedSize(horizontal: false, vertical: true)
                    Text(event.time).font(.caption).foregroundStyle(Brand.muted)
                }
            }
            if shipment.canRecord && recovery == .ready && loadError == nil && !loading {
                if editorID == shipment.id {
                    TextField("物流进度说明", text: $draft, axis: .vertical)
                        .lineLimit(2...4).textFieldStyle(.roundedBorder)
                        .onChange(of: draft) { _, text in draft = nativeLimitUtf16Text(text, maximum: 500) }
                    Button("补录进度") { confirm(.record(shipment.id)) }
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                        .disabled(operation != nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("补录物流进度") { editorID = shipment.id; draft = "" }
                        .buttonStyle(.bordered).disabled(operation != nil)
                }
            }
        }.merchantCard()
    }

    private func activate() {
        guard current else { return }
        recovery = storage.read()
        canRelease = false
        run { await load() }
    }

    private func deactivate() {
        operation?.cancel(); operation = nil; loading = false
        editorID = nil; draft = ""; confirmation = nil; confirming = false
    }

    private func confirm(_ action: Confirmation) {
        guard current, operation == nil else { return }
        confirmation = action; confirming = true
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        guard current, operation == nil else { return }
        operation = Task { @MainActor in
            defer { if !Task.isCancelled { operation = nil } }
            guard current else { return }
            await action()
        }
    }

    private func load() async {
        guard current, case let .order(orderID, merchantOrderID, _) = destination else { return }
        loading = true; loadError = nil; shipments = []
        defer { if current { loading = false } }
        do {
            let result = try await MobileAPI(store: store).get(
                "/api/JHCTIMerchantOrder/GetFulfillments?merchantId=\(merchantID)&orderId=\(orderID)&merchantOrderId=\(merchantOrderID)",
                authenticated: true, expectedPrincipal: principal)
            guard current else { return }
            shipments = try NativeMerchantShipment.list(result, orderID: orderID, merchantOrderID: merchantOrderID)
        } catch {
            if current { loadError = error.localizedDescription }
        }
    }

    private func submit(id: String) async {
        guard current, loadError == nil, editorID == id,
              shipments.contains(where: { $0.id == id && $0.canRecord }) else { return }
        let description = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...500).contains(description.utf16.count) else { return }
        let attempt = NativeTrackingAttempt(shipmentID: id, requestID: UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))
        guard storage.save(attempt) else {
            recovery = storage.read(); notice = "无法保存待核对记录，物流进度尚未提交。"; return
        }
        recovery = .pending(attempt); canRelease = false; notice = nil
        editorID = nil; draft = ""
        // 网络结果不确定时由原请求号核对，避免用新请求号重复补录。
        do {
            let response = try await MobileAPI(store: store).post("/api/JHCTIMerchantOrder/AddTrackingEvent?merchantId=\(merchantID)",
                body: ["ShipmentId": id, "Description": description, "IdempotencyKey": attempt.requestID],
                authenticated: true, expectedPrincipal: principal, canRefresh: false, requireExplicitResponse: true)
            guard current else { return }
            guard response as? String == id else { throw MobileAPIError.unavailable("回执不匹配") }
            finish(.pending(attempt), recorded: true)
            await load()
        } catch {
            guard current else { return }
            if let status = (error as? MobileAPIError)?.httpStatusCode, [400, 404, 422].contains(status),
               storage.clear(.pending(attempt)) {
                recovery = storage.read()
                notice = error.localizedDescription
            } else { notice = "补录结果尚未确认，请查询原请求。" }
        }
    }

    private func verify(release: Bool) async {
        guard current, recovery == storage.read() else { recovery = storage.read(); canRelease = false; return }
        if recovery == .damaged && release { finish(.damaged, recorded: false); return }
        guard case let .pending(attempt) = recovery, !release || canRelease else { return }
        canRelease = false; notice = nil
        do {
            let response = try await MobileAPI(store: store).post("/api/JHCTIMerchantOrder/GetTrackingReceipt?merchantId=\(merchantID)",
                body: ["ShipmentId": attempt.shipmentID, "RequestId": attempt.requestID],
                authenticated: true, expectedPrincipal: principal, requireExplicitResponse: true)
            guard current else { return }
            guard let row = response as? [String: Any], trackingField(row, "ShipmentId") as? String == attempt.shipmentID,
                  trackingField(row, "RequestId") as? String == attempt.requestID,
                  let eventID = trackingField(row, "EventId") as? String, eventID == "0" || trackingID(eventID) else {
                throw MobileAPIError.unavailable("物流核对回执与原履约单或请求号不匹配。")
            }
            if eventID != "0" || release {
                finish(.pending(attempt), recorded: eventID != "0")
                await load()
            } else {
                canRelease = true; notice = "暂未查到原请求。请先核对实际履约轨迹。"
            }
        } catch {
            if current { notice = "核对失败。\(error.localizedDescription)" }
        }
    }

    private func finish(_ expected: NativeTrackingRecovery, recorded: Bool) {
        let cleared = storage.clear(expected)
        recovery = storage.read(); canRelease = false
        notice = cleared ? (recorded ? "已确认物流进度记录成功。" : "已解除待核对状态。")
            : "待核对记录未能清除，请重新读取。"
    }
}
