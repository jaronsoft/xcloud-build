import SwiftUI

struct NearbyActivitySection: View {
    let store: SessionStore
    let activities: [[String: Any]]
    let isLoading: Bool
    let error: String?
    let onRetry: () -> Void
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("附近活动")
                .font(.system(size: NativeTypography.size(18), weight: .semibold)).foregroundStyle(Brand.ink)
            if isLoading {
                ProgressView("正在查找附近活动…").tint(Brand.primary)
            } else {
                if let error {
                    Text(error).font(.system(size: NativeTypography.size(13))).foregroundStyle(Brand.muted)
                    Button("重试附近活动查询", action: onRetry).foregroundStyle(Brand.primary)
                } else if activities.isEmpty {
                    Text("附近暂无可按位置展示的进行中或后续活动。")
                        .font(.system(size: NativeTypography.size(13))).foregroundStyle(Brand.muted)
                }
            }
            ForEach(Array(activities.enumerated()), id: \.offset) { row in
                let activity = row.element
                let id = activity["Id"] as? String ?? ""
                Button {
                    guard nativeCartID(id) != nil else { return }
                    onOpen(id)
                } label: {
                    HStack(spacing: 10) {
                        let imageURL = (activity["ImageUrls"] as? [String])?.first
                        NearbyActivityCover(store: store, imagePath: imageURL)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity["Name"] as? String ?? "江都文旅活动")
                                .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
                            let venue = [activity["Region"] as? String, activity["Venue"] as? String]
                                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }.joined(separator: " · ")
                            Text(venue.isEmpty ? "活动地点待补充" : venue)
                                .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted).lineLimit(2)
                            Text(activityDate(activity))
                                .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.primary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
                    }
                    .padding(10).background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func activityDate(_ activity: [String: Any]) -> String {
        let date = (activity["ActivityStartTime"] as? String)
            ?? (activity["StartTime"] as? String)
            ?? (activity["SignupStartTime"] as? String)
        var components: [String] = []
        if let date, let formattedDate = businessDate(date) { components.append(formattedDate) }
        if let raw = activity["DistanceKm"] as? NSNumber, raw.doubleValue.isFinite, raw.doubleValue >= 0 {
            components.append(nativeMapDistanceText(raw.doubleValue * 1000) ?? "")
        }
        return components.isEmpty ? "查看活动时间" : components.joined(separator: " · ")
    }

    private func businessDate(_ value: String) -> String? {
        guard let parsedDate = nativeBusinessDateTime(value) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: parsedDate)
    }
}
