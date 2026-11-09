import SwiftUI

struct DiningPublicPackagesSection: View {
    let store: SessionStore
    let packages: [[String: Any]]
    let isLoading: Bool
    let isPending: Bool
    let errorMessage: String?
    let recoveryAvailable: Bool
    let recoveryBusy: Bool
    let recoveryMessage: String?
    let onRetry: () -> Void
    let onBuy: ([String: Any]) -> Void
    let onRecover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前团购套餐").font(.headline).foregroundStyle(Brand.ink)
            if isLoading { ProgressView("正在查询当前可用套餐…") }
            else if isPending {
                Text("餐饮团购功能尚未开放，套餐将在开放后显示。")
                    .font(.subheadline).foregroundStyle(Brand.muted)
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                    Button("重试加载套餐", action: onRetry).buttonStyle(.bordered)
                }
            } else if packages.isEmpty {
                Text("当前没有适用中的已发布套餐").font(.subheadline).foregroundStyle(Brand.muted)
            } else {
                ForEach(Array(packages.enumerated()), id: \.offset) { _, item in
                    packageCard(item)
                    Button("购买套餐") { onBuy(item) }
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                }
                Text("套餐仅展示当前公开信息；下单功能以平台开放状态为准。")
                    .font(.caption2).foregroundStyle(Brand.muted)
            }
            if recoveryAvailable {
                Button(action: onRecover) {
                    if recoveryBusy { ProgressView("正在核对未完成订单…") }
                    else { Text("核对未完成订单") }
                }
                .buttonStyle(.bordered)
                .disabled(recoveryBusy)
                if let recoveryMessage {
                    Text(recoveryMessage).font(.caption).foregroundStyle(Brand.muted)
                }
            }
        }
    }

    private func packageCard(_ item: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NativeDiningThemeImage(store: store, path: catalogCover(item), width: nil, height: 90)
            HStack(alignment: .firstTextBaseline) {
                Text(item["Name"] as? String ?? item["name"] as? String ?? "团购套餐")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                Spacer()
                if let price = decimal(item["SalePrice"] ?? item["salePrice"]), price > 0, price <= 1_000_000 {
                    Text("¥\(price, specifier: "%.2f")").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.primary)
                }
            }
            if let description = item["Description"] as? String ?? item["description"] as? String, !description.isEmpty {
                Text(description).font(.caption).foregroundStyle(Brand.muted).lineLimit(3)
            }
            let parts = item["Items"] as? [[String: Any]] ?? item["items"] as? [[String: Any]] ?? []
            if !parts.isEmpty {
                Text(parts.map { part in
                    let name = part["ItemName"] as? String ?? part["itemName"] as? String ?? "套餐内容"
                    let spec = part["Specification"] as? String ?? part["specification"] as? String ?? ""
                    let quantity = integer(part["Quantity"] ?? part["quantity"]) ?? 0
                    return "\(name)\(spec.isEmpty ? "" : " \(spec)") ×\(quantity)"
                }.joined(separator: " · ")).font(.caption2).foregroundStyle(Brand.muted)
            }
            Text("可用日期：\(String((item["ValidFrom"] as? String ?? item["validFrom"] as? String ?? "").prefix(10))) 至 \(String((item["ValidTo"] as? String ?? item["validTo"] as? String ?? "").prefix(10)))")
                .font(.caption2).foregroundStyle(Brand.muted)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 11))
    }

    private func decimal(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? (value as? Double) ?? (value as? String).flatMap(Double.init)
    }

    private func integer(_ value: Any?) -> Int? {
        (value as? Int) ?? (value as? NSNumber)?.intValue
    }
}
