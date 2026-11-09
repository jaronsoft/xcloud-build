import SwiftUI

struct NativeResourceBrowseResultsSection: View {
    let store: SessionStore
    let resources: [ResourceItem]
    let mapMode: Bool
    let nearbyResultsActive: Bool
    let nearbyResourceType: String
    let selectedManualRegion: String
    let selectedFilter: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mapMode && nearbyResultsActive && nearbyResourceType == "Facility" ? "附近服务设施" : mapMode ? "景点与设施" : "已发布内容")
                .font(.system(size: NativeTypography.size(18), weight: .semibold)).foregroundStyle(Brand.ink)
                .padding(.bottom, 8)
            if mapMode && nearbyResultsActive && selectedManualRegion.isEmpty
                && (selectedFilter == "全部" || selectedFilter == "景点") {
                Text(nearbyResourceType == "Facility"
                     ? "距离按直线估算；无独立坐标的设施按所属景点位置估算，实际路程以导航为准。"
                     : "距离按直线估算，实际路程以导航为准。")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            }
            ForEach(resources) { item in
                NavigationLink(value: item.id) {
                    HStack(spacing: 10) {
                        Group {
                            if let url = MobileAPI(store: store).mediaURL(item.coverURL) {
                                CachedRemoteImage(url: url) { Image("Hero").resizable().scaledToFill() }
                            } else { Image("Hero").resizable().scaledToFill() }
                        }
                        .frame(width: 76, height: 58).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(item.name).font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink).lineLimit(1)
                                Text(item.resourceType == "Facility" ? item.facilityTypeLabel : "景点")
                                    .font(.system(size: NativeTypography.size(10))).foregroundStyle(Brand.muted)
                            }
                            Text(item.address.isEmpty ? "地址待补充" : item.address).font(.system(size: NativeTypography.size(14))).lineLimit(2).foregroundStyle(Brand.muted)
                            Text(item.resourceType == "Facility"
                                 ? "\(item.facilityTypeLabel)  \(item.cardOpenStatusLabel)"
                                 : "\(item.cardOpenStatusLabel)  \(item.admissionCardLabel)")
                                .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.primary)
                            if mapMode && nearbyResultsActive && selectedManualRegion.isEmpty
                                && (selectedFilter == "全部" || selectedFilter == "景点"),
                               let distanceKm = item.distanceKm,
                               let distanceText = nativeMapDistanceText(distanceKm * 1000) {
                                Text(item.locationIsApproximate ? "所属景点约 \(distanceText)" : distanceText)
                                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.primary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    }
                    .padding(.vertical, 8)
                }
                Divider()
            }
        }
    }
}
