import SwiftUI

struct ActivityDetailSummarySection: View {
    let store: SessionStore
    let activityID: String
    let detail: [String: Any]
    let hasSessions: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(detail["Region"] as? String ?? "江都")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                Text(detail["Name"] as? String ?? "近期活动")
                    .font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif)).foregroundStyle(Brand.ink)
                Text("活动报名").font(.system(size: NativeTypography.size(12), weight: .semibold))
                    .foregroundStyle(Brand.primary)
                activityRow("活动时间", dateRange(detail["ActivityStartTime"], detail["ActivityEndTime"]))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdownView(detail["ActivityStartTime"], detail["ActivityEndTime"], now: context.date,
                                  startLabel: "活动开始", activeLabel: "活动进行中", endedLabel: "活动已结束")
                }
                activityRow("报名时间", dateRange(detail["SignupStartTime"], detail["SignupEndTime"]))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdownView(detail["SignupStartTime"], detail["SignupEndTime"], now: context.date,
                                  startLabel: "报名开始", activeLabel: "报名进行中", endedLabel: "报名已截止")
                }
                Text(hasSessions
                    ? "常规截止后，仅已开始的场次仍可报名；所选场次结束后立即停止报名。"
                    : "常规截止后，仅已开始的活动仍可报名；活动结束后立即停止报名。")
                    .font(.system(size: NativeTypography.size(10))).foregroundStyle(Brand.muted)
                if let venue = detail["Venue"] as? String, !venue.isEmpty { activityRow("活动地点", venue) }
                if let organizer = detail["Organizer"] as? String, !organizer.isEmpty { activityRow("主办方", organizer) }
                if let phone = detail["ContactPhone"] as? String, !phone.isEmpty { activityRow("联系电话", phone) }
                NativeActivityShare(activityID: activityID, activityName: detail["Name"] as? String ?? "江都文旅活动")
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, -25)
            .zIndex(1)

            NativeCoordinateMapCard(title: "活动地点", name: detail["Name"] as? String ?? "近期活动",
                address: detail["Venue"] as? String,
                latitude: nativeCoordinateNumber(detail, keys: ["Latitude", "MeetingLatitude"]),
                longitude: nativeCoordinateNumber(detail, keys: ["Longitude", "MeetingLongitude"]),
                coordinateSystem: detail["CoordinateSystem"] as? String
                    ?? detail["MeetingCoordinateSystem"] as? String ?? "")
        }
    }

    private func countdownView(_ startValue: Any?, _ endValue: Any?, now: Date,
                               startLabel: String, activeLabel: String, endedLabel: String) -> some View {
        let countdown = activityWindowCountdown(startValue, endValue, now: now,
                                                startLabel: startLabel, activeLabel: activeLabel, endedLabel: endedLabel)
        return Group {
            if !countdown.isEmpty {
                Text(countdown).font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted)
            }
        }
    }

    private func activityWindowCountdown(_ startValue: Any?, _ endValue: Any?, now: Date,
                                         startLabel: String, activeLabel: String, endedLabel: String) -> String {
        guard let startText = startValue as? String, let endText = endValue as? String,
              let start = nativeBusinessTimestamp(startText), let end = nativeBusinessTimestamp(endText), end > start else { return "" }
        if now < start { return "距\(startLabel)：\(activityCountdown(start.timeIntervalSince(now)))" }
        if now < end { return "\(activeLabel) · 距结束：\(activityCountdown(end.timeIntervalSince(now)))" }
        return endedLabel
    }

    private func activityCountdown(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(interval)))
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        let remainder = seconds % 60
        if days > 0 { return "\(days)天\(hours)小时\(minutes)分\(remainder)秒" }
        if hours > 0 { return "\(hours)小时\(minutes)分\(remainder)秒" }
        return "\(minutes)分\(remainder)秒"
    }

    private func activityRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).foregroundStyle(Brand.muted).frame(width: 64, alignment: .leading)
            Text(value).foregroundStyle(Brand.ink)
        }.font(.system(size: NativeTypography.size(14)))
    }

    private func dateRange(_ start: Any?, _ end: Any?) -> String {
        "\(start as? String ?? "待公布") — \(end as? String ?? "待公布")"
    }
}
