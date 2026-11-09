import SwiftUI

struct NativeRestaurantShare: View {
    let storeID: String
    let storeName: String

    private var normalizedStoreName: String? {
        let trimmed = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var shareTitle: String {
        guard let normalizedStoreName else { return "江都餐饮" }
        return "\(normalizedStoreName)｜江都文旅"
    }

    private var shareStoreName: String { normalizedStoreName ?? "江都餐饮" }

    private var shareURL: URL? {
        var components = URLComponents(string: "https://travel.jiangdu.net/subpackages/dining/restaurant/index")
        components?.queryItems = [URLQueryItem(name: "id", value: storeID)]
        return components?.url
    }

    var body: some View {
        if let shareURL {
            ShareLink(item: shareURL, subject: Text(shareTitle), message: Text("查看餐饮门店：\(shareStoreName)")) {
                Label("分享餐饮门店", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Brand.primary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
