import SwiftUI
import UIKit

struct NativeCommerceDigitalDeliverySection: View {
    let orderStatus: String
    let items: [[String: Any]]
    @Binding var notice: String?

    private var digitalItemIndices: [Int] {
        items.indices.filter { ["DigitalCode", "DigitalLink"].contains(items[$0]["DeliveryType"] as? String ?? "") }
    }

    @ViewBuilder var body: some View {
        if !digitalItemIndices.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("虚拟商品交付").font(.system(size: NativeTypography.size(14), weight: .semibold))
                if let notice {
                    Text(notice).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                }
                ForEach(digitalItemIndices, id: \.self) { index in
                    let item = items[index]
                    let deliveryType = item["DeliveryType"] as? String ?? ""
                    let deliveries = item["DigitalDeliveries"] as? [[String: Any]] ?? []
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(item["ProductName"] as? String ?? "虚拟商品") × \(item["Quantity"] as? Int ?? 1)")
                            .font(.system(size: NativeTypography.size(14), weight: .semibold))
                        if deliveries.isEmpty {
                            Text(orderStatus == "PendingPayment"
                                 ? "支付成功后自动发放，可在此查看。"
                                 : "交付信息暂不可用，请刷新订单后重试。")
                                .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                        }
                        ForEach(deliveries.indices, id: \.self) { deliveryIndex in
                            let delivery = deliveries[deliveryIndex]
                            let status = delivery["Status"] as? String ?? ""
                            let type = delivery["DeliveryType"] as? String ?? deliveryType
                            let content = delivery["Content"] as? String ?? ""
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(type == "DigitalLink" ? "交付链接" : "电子券码") · \(deliveryStatus(status))")
                                    .font(.system(size: NativeTypography.size(12), weight: .medium)).foregroundStyle(Brand.muted)
                                if status == "Revoked" {
                                    Text("退款后已作废").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                                } else if !["Issued", "Redeemed"].contains(status) {
                                    Text("凭证状态无法识别，暂不显示交付内容，请联系平台。")
                                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                } else if !["DigitalCode", "DigitalLink"].contains(type) {
                                    Text("交付类型无法识别，暂不显示交付内容，请联系平台。")
                                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                } else if content.isEmpty {
                                    Text("交付内容暂不可用，请刷新订单后重试。")
                                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                } else if type == "DigitalLink" {
                                    if let components = URLComponents(string: content),
                                       components.scheme?.lowercased() == "https",
                                       let host = components.host, !host.isEmpty,
                                       components.user == nil, components.password == nil,
                                       let url = components.url {
                                        Text(content).font(.system(size: NativeTypography.size(12), design: .monospaced))
                                            .textSelection(.enabled).foregroundStyle(Brand.ink)
                                        HStack {
                                            Link("打开交付链接", destination: url).font(.system(size: NativeTypography.size(12), weight: .semibold))
                                            Button("复制链接") {
                                                UIPasteboard.general.string = content
                                                notice = "交付链接已复制。"
                                            }.font(.system(size: NativeTypography.size(12), weight: .semibold))
                                        }
                                    } else {
                                        Text("交付链接格式无效，请联系商户。")
                                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                    }
                                } else {
                                    Text(content).font(.system(size: NativeTypography.size(14), weight: .semibold, design: .monospaced))
                                        .textSelection(.enabled).foregroundStyle(Brand.ink)
                                    Button("复制券码") {
                                        UIPasteboard.general.string = content
                                        notice = "电子券码已复制。"
                                    }.font(.system(size: NativeTypography.size(12), weight: .semibold))
                                }
                                if status == "Redeemed", let redeemedAt = delivery["RedeemedAt"] as? String, !redeemedAt.isEmpty {
                                    Text("核销时间：\(bookingBusinessDateTime(redeemedAt) ?? "—")")
                                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                }
                            }
                            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 9))
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private func deliveryStatus(_ status: String) -> String {
        switch status {
        case "Issued": return "待使用"
        case "Redeemed": return "已核销"
        case "Revoked": return "已作废"
        default: return "状态待核对"
        }
    }
}
