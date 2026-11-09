import SwiftUI

struct DiningPublicMenuSection: View {
    let store: SessionStore
    let menu: [String: Any]

    var body: some View {
        let categories = menu["Categories"] as? [[String: Any]] ?? menu["categories"] as? [[String: Any]] ?? []
        return VStack(alignment: .leading, spacing: 10) {
            Text("菜单").font(.headline).foregroundStyle(Brand.ink)
            if categories.isEmpty { Text("暂无公开菜单").font(.subheadline).foregroundStyle(Brand.muted) }
            ForEach(Array(categories.enumerated()), id: \.offset) { _, category in
                let dishes = category["Dishes"] as? [[String: Any]] ?? category["dishes"] as? [[String: Any]] ?? []
                if !dishes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category["Name"] as? String ?? category["name"] as? String ?? "菜品")
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(dishes.enumerated()), id: \.offset) { _, dish in
                            let skus = dish["Skus"] as? [[String: Any]] ?? dish["skus"] as? [[String: Any]] ?? []
                            HStack(alignment: .top) {
                                NativeDiningThemeImage(store: store, path: catalogCover(dish), width: 66, height: 56)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(dish["Name"] as? String ?? dish["name"] as? String ?? "菜品").font(.subheadline)
                                    if let description = dish["Description"] as? String, !description.isEmpty {
                                        Text(description).font(.caption).foregroundStyle(Brand.muted).lineLimit(2)
                                    }
                                    ForEach(Array(skus.enumerated()), id: \.offset) { _, sku in
                                        let available = sku["IsAvailable"] as? Bool ?? sku["isAvailable"] as? Bool ?? true
                                        let price = decimal(sku["Price"] ?? sku["price"])
                                        if available, let price, price >= 0, price <= 1_000_000 {
                                            let name = sku["Name"] as? String ?? sku["name"] as? String ?? ""
                                            let priceText = String(format: "¥%.2f", price)
                                            let skuText = name.isEmpty ? priceText : "\(name)　\(priceText)"
                                            Text(skuText).font(.caption).foregroundStyle(Brand.muted)
                                        }
                                    }
                                }
                                Spacer()
                                let prices = skus.filter { $0["IsAvailable"] as? Bool ?? $0["isAvailable"] as? Bool ?? true }
                                    .compactMap { decimal($0["Price"] ?? $0["price"]) }
                                    .filter { $0 >= 0 && $0 <= 1_000_000 }
                                if let price = prices.min() {
                                    let suffix = prices.count > 1 ? " 起" : ""
                                    Text("¥\(price, specifier: "%.2f")\(suffix)")
                                        .font(.caption.weight(.semibold)).foregroundStyle(Brand.primary)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 11))
                }
            }
        }
    }

    private func decimal(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? (value as? Double) ?? (value as? String).flatMap(Double.init)
    }
}
