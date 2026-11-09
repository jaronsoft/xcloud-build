import SwiftUI

struct NativeProductShare: View {
    let productID: String
    let productName: String

    private var normalizedProductName: String? {
        let trimmed = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var shareTitle: String {
        guard let normalizedProductName else { return "江都好物" }
        return "\(normalizedProductName)｜江都文旅"
    }

    private var shareProductName: String { normalizedProductName ?? "江都好物" }

    private var shareURL: URL? {
        var components = URLComponents(string: "https://travel.jiangdu.net/subpackages/commerce/product/index")
        components?.queryItems = [URLQueryItem(name: "id", value: productID)]
        return components?.url
    }

    var body: some View {
        if let shareURL {
            ShareLink(item: shareURL, subject: Text(shareTitle), message: Text("查看商品：\(shareProductName)")) {
                Label("分享商品", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Brand.primary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
