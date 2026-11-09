import SwiftUI

private func nativeResourceFacilities(_ rows: [[String: Any]]) -> [[String: Any]] {
    var seen = Set<String>()
    return rows.filter { row in
        guard row["ResourceType"] as? String == "Facility", let id = row["Id"] as? String,
              let number = Int64(id), number > 0, String(number) == id else { return false }
        return seen.insert(id).inserted
    }
}

struct NativeResourceFacilitiesSection: View {
    let rows: [[String: Any]]
    private var facilities: [ResourceItem] { nativeResourceFacilities(rows).compactMap(ResourceItem.init) }
    private var mapPoints: [ResourceItem] { facilities.filter { $0.latitude != nil && $0.longitude != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(facilities.isEmpty ? "景区设施" : "景区设施分布")
                .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
            if facilities.isEmpty {
                Text("景区暂未发布设施信息，完善后将在这里显示。")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
            } else {
                if mapPoints.isEmpty {
                    Text("已发布的景区设施暂未提供可用坐标，地图暂不可用。")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                } else {
                    NativeInteractiveMapView(pins: mapPoints.map {
                        .init(id: $0.id, name: $0.name, latitude: $0.latitude!, longitude: $0.longitude!)
                    }, title: "景区设施分布")
                }
                ForEach(facilities) { facility in
                    HStack(alignment: .top) {
                        Text(facility.name).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text(facility.facilityTypeLabel).foregroundStyle(Brand.muted)
                    }.font(.system(size: NativeTypography.size(14)))
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.border, lineWidth: 1))
    }
}

// 已取消回执不再用于入园；有效或已核验回执必须带齐凭证摘要后才能清除恢复标记。
func hasCompleteNativeTourismReservationReceipt(_ receipt: [String: Any]) -> Bool {
    let status = receipt["Status"] as? String ?? ""
    if status == "Cancelled" { return true }
    let epoch = Date(timeIntervalSince1970: 0)
    guard ["Reserved", "CheckedIn"].contains(status),
          let sessionName = receipt["SessionName"] as? String, !sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let startTime = paymentDeadline(receipt["StartTime"]), startTime > epoch,
          let endTime = paymentDeadline(receipt["EndTime"]), endTime > epoch else { return false }
    let expired = endTime <= Date()
    guard (receipt["CredentialCode"] as? String).map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) == true || expired else { return false }
    return true
}

func isExpiredNativeTourismReservation(_ receipt: [String: Any], now: Date = Date()) -> Bool {
    guard receipt["Status"] as? String == "Reserved",
          let end = paymentDeadline(receipt["EndTime"]) else { return false }
    return end <= now
}


struct NativeTourismReviewCard: View {
    let title: String
    let rating: Int
    let content: String
    let reply: String?
    let avatarURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                CachedRemoteImage(url: avatarURL) {
                    Image(systemName: "person.crop.circle.fill").resizable().scaledToFit()
                        .foregroundStyle(Brand.muted)
                }
                .frame(width: 30, height: 30).clipShape(Circle())
                Text(title).font(.system(size: NativeTypography.size(13), weight: .medium)).foregroundStyle(Brand.ink)
            }
            Text(String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating) + "　\(rating) 分")
                .font(.system(size: NativeTypography.size(13))).foregroundStyle(Color(red: 0.82, green: 0.54, blue: 0.20))
            Text(content).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let reply {
                VStack(alignment: .leading, spacing: 5) {
                    Text("商家回复").font(.system(size: NativeTypography.size(12), weight: .semibold))
                        .foregroundStyle(Brand.primary)
                    Text(reply).font(.system(size: NativeTypography.size(13))).foregroundStyle(Brand.ink)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(Color(red: 0.96, green: 0.98, blue: 0.97), in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
}

struct NativeTourismPublicReviewRow {
    let title: String
    let rating: Int
    let content: String
    let reply: String?
    let avatarURL: String?
}

func nativeTourismReviewPresentation(_ detail: [String: Any]) -> (count: Int, averageText: String, rows: [NativeTourismPublicReviewRow]) {
    let count = detail["ReviewCount"] as? Int ?? 0
    let average = (detail["AverageRating"] as? NSNumber)?.doubleValue
    let averageText = average.map { String(format: "%.1f", $0) } ?? "—"
    let reviews = detail["Reviews"] as? [[String: Any]] ?? []
    let rows = reviews.prefix(20).map { review -> NativeTourismPublicReviewRow in
        let name = (review["UserDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "游客"
        let rating = min(5, max(0, (review["Rating"] as? NSNumber)?.intValue ?? 0))
        let date = bookingBusinessDateTime(review["CreateTime"]).map { String($0.prefix(10)) } ?? "—"
        let content = (review["Content"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "评价者未填写文字内容。"
        let reply = (review["Reply"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return NativeTourismPublicReviewRow(title: "\(name) · \(date)", rating: rating,
            content: content, reply: reply, avatarURL: review["AvatarUrl"] as? String)
    }
    return (count, averageText, rows)
}
