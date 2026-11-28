import SwiftUI

struct NativeCommerceShipmentsSection: View {
    let shipments: [NativeBuyerShipment]
    let recovery: NativeShipmentReceiptState
    let verifiedReceipt: UUID?
    let busy: Bool
    let onVerify: () -> Void
    let onConfirm: (NativeBuyerShipment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("履约与物流轨迹").font(.system(size: NativeTypography.size(14), weight: .semibold))
            if let attempt = recovery.attempt {
                Text(verifiedReceipt == attempt.marker
                    ? "原履约单仍在运输中。已收到商品时，可以再次确认。"
                    : "履约单 \(attempt.shipmentID) 的收货结果待核对。")
                Button("读取最新履约状态", action: onVerify).disabled(busy)
            } else if recovery == .damaged || (recovery == .unavailable && shipments.contains(where: \.canConfirm)) {
                Text(recovery == .damaged ? "本机收货待核对记录损坏，请联系客服核对。" : "暂时无法读取收货待核对记录。")
                Button("重试读取", action: onVerify).disabled(busy)
            } else if shipments.isEmpty {
                Text("暂无履约记录").foregroundStyle(Brand.muted)
            }
            ForEach(shipments) { shipment in
                NativeCommerceShipmentCard(shipment: shipment,
                    confirmLabel: recovery.canConfirm(shipment, verified: verifiedReceipt)
                        ? (recovery.attempt == nil ? "确认此包裹已收货" : "再次确认收货") : nil,
                    busy: busy, onConfirm: { onConfirm(shipment) })
            }
        }
        .font(.system(size: NativeTypography.size(14)))
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct NativeCommerceShipmentCard: View {
    let shipment: NativeBuyerShipment
    let confirmLabel: String?
    let busy: Bool
    let onConfirm: () -> Void

    private var statusText: String {
        ["InTransit": "运输中", "Delivered": "已收货", "ReadyForPickup": "待自提", "PickedUp": "已取货"][shipment.status] ?? "状态待核对"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(shipment.type == "Express" ? "快递配送" : "自提/虚拟交付")
                .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
            Text("状态：\(statusText)")
                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
            if let carrier = shipment.carrier, !carrier.isEmpty {
                Text("承运方：\(carrier)").font(.system(size: NativeTypography.size(14)))
            }
            if let tracking = shipment.trackingNumber, !tracking.isEmpty {
                Text("物流单号：\(tracking)").font(.system(size: NativeTypography.size(14), design: .monospaced).monospacedDigit())
            }
            ForEach(shipment.events.indices, id: \.self) { index in
                let event = shipment.events[index]
                Text("• \(trackingField(event, "Description") as? String ?? "物流状态更新")  \(trackingField(event, "EventTime") as? String ?? "")")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            }
            if let confirmLabel {
                Button(confirmLabel, action: onConfirm)
                    .font(.system(size: NativeTypography.size(14), weight: .semibold)).disabled(busy)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.background, in: RoundedRectangle(cornerRadius: 9))
    }
}
