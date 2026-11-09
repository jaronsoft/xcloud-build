import SwiftUI

struct NativeActivityShare: View {
    let activityID: String
    let activityName: String

    private var normalizedActivityName: String? {
        let trimmed = activityName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var shareTitle: String {
        guard let normalizedActivityName else { return "江都文旅活动" }
        return "\(normalizedActivityName)｜江都文旅"
    }

    private var shareActivityName: String { normalizedActivityName ?? "江都文旅活动" }

    private var shareURL: URL? {
        var components = URLComponents(string: "https://travel.jiangdu.net/subpackages/activities/activity/index")
        components?.queryItems = [URLQueryItem(name: "id", value: activityID)]
        return components?.url
    }

    var body: some View {
        if let shareURL {
            ShareLink(item: shareURL, subject: Text(shareTitle), message: Text("查看活动：\(shareActivityName)")) {
                Label("分享活动", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Brand.primary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
