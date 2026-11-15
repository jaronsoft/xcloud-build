import SwiftUI

struct NativeCommerceShipmentCard: View {
    let shipment: [String: Any]
    let statusText: String
    let isConfirming: Bool
    let isConfirmationBusy: Bool
    let onConfirm: () -> Void

    private var events: [[String: Any]] { shipment["Events"] as? [[String: Any]] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(shipment["FulfillmentType"] as? String == "Express" ? "快递配送" : "自提/虚拟交付")
                .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
            Text("状态：\(statusText)")
                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
            if let carrier = shipment["CarrierName"] as? String, !carrier.isEmpty {
                Text("承运方：\(carrier)").font(.system(size: NativeTypography.size(14)))
            }
            if let tracking = shipment["TrackingNumber"] as? String, !tracking.isEmpty {
                Text("物流单号：\(tracking)").font(.system(size: NativeTypography.size(14), design: .monospaced).monospacedDigit())
            }
            ForEach(events.indices, id: \.self) { index in
                let event = events[index]
                Text("• \(event["Description"] as? String ?? "物流状态更新")  \(event["EventTime"] as? String ?? "")")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            }
            if shipment["FulfillmentType"] as? String == "Express", shipment["Status"] as? String == "Shipped" {
                Button(isConfirming ? "正在确认…" : "确认此包裹已收货", action: onConfirm)
                    .font(.system(size: NativeTypography.size(14), weight: .semibold)).disabled(isConfirmationBusy)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.background, in: RoundedRectangle(cornerRadius: 9))
    }
}
