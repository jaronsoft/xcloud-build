import SwiftUI
import UIKit

struct NativeResourceBrowseMapControlsSection: View {
    let locatorMessage: String?
    let locatorBusy: Bool
    let loading: Bool
    let nearbyResourceWarning: String?
    let nearbyResourceRetryLoading: Bool
    let nearbyResourceRetryError: String?
    let nearbyResourceTitle: String
    let error: String?
    let manualRegions: [String]
    let manualRegionsLoading: Bool
    let manualRegionsError: String?
    let nearbyResourceType: String
    let onOpenLocationSettings: () -> Void
    let onRetryNearbyResources: () -> Void
    let onSelectFilter: (String) -> Void
    let onStartNearbySearch: (String) -> Void
    let onLoadRegions: () -> Void
    let onExpireNearbyLocation: () -> Void
    let onSearchRegion: (String) -> Void

    @Binding var selectedFilter: String
    @Binding var selectedManualRegion: String

    private let filters = ["全部", "景点", "卫生间", "停车场", "加油站", "其他设施"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text("文旅江都")
                        .font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif))
                        .foregroundStyle(Brand.ink)
                }
                Text("地图仅展示平台已发布的资源点位")
                    .font(.system(size: NativeTypography.size(14)))
                    .foregroundStyle(Brand.muted)
            }
            .padding(.vertical, 12)

            if let locatorMessage {
                Text(locatorMessage)
                    .font(.system(size: NativeTypography.size(14)))
                    .foregroundStyle(.red)
                if locatorMessage.contains("定位权限未开启") {
                    Button("前往系统设置开启位置权限", action: onOpenLocationSettings)
                        .foregroundStyle(Brand.primary)
                }
            }

            if let nearbyResourceWarning {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(nearbyResourceWarning)
                            .font(.system(size: NativeTypography.size(12)))
                            .foregroundStyle(Color(red: 0.55, green: 0.42, blue: 0.12))
                            .fixedSize(horizontal: false, vertical: true)
                        Button(nearbyResourceRetryLoading ? "正在重试…" : "重试附近\(nearbyResourceTitle)",
                               action: onRetryNearbyResources)
                            .font(.system(size: NativeTypography.size(12), weight: .semibold))
                            .foregroundStyle(Brand.primary)
                            .fixedSize()
                            .disabled(locatorBusy || loading || nearbyResourceRetryLoading)
                    }
                    if let nearbyResourceRetryError {
                        Text(nearbyResourceRetryError)
                            .font(.system(size: NativeTypography.size(12)))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters, id: \.self) { filter in
                        Button(filter) { onSelectFilter(filter) }
                            .font(.system(size: NativeTypography.size(14)))
                            .foregroundStyle(selectedFilter == filter ? .white : Brand.muted)
                            .accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(selectedFilter == filter ? Brand.primary : .white, in: Capsule())
                    }
                }
            }

            if selectedFilter == "全部" || selectedFilter == "景点" {
                HStack(spacing: 8) {
                    Button(locatorBusy && nearbyResourceType == "ScenicSpot" ? "正在定位…" : "附近景点与活动") {
                        onStartNearbySearch("ScenicSpot")
                    }
                    Button(locatorBusy && nearbyResourceType == "Facility" ? "正在定位…" : "附近服务设施") {
                        onStartNearbySearch("Facility")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.primary)
                .font(.system(size: NativeTypography.size(14), weight: .semibold))
                .disabled(locatorBusy)
            }

            if nearbyResourceType == "ScenicSpot"
                && (locatorMessage != nil || error != nil || !selectedManualRegion.isEmpty)
                && (selectedFilter == "全部" || selectedFilter == "景点") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedManualRegion.isEmpty ? "附近查询不可用？可以按区域浏览景点。" : "可切换区域继续浏览景点。")
                        .font(.system(size: NativeTypography.size(13)))
                        .foregroundStyle(Brand.muted)
                    if manualRegions.isEmpty {
                        Button(manualRegionsLoading ? "正在读取可选区域…" : "读取可选区域", action: onLoadRegions)
                            .disabled(manualRegionsLoading)
                            .foregroundStyle(Brand.primary)
                    } else {
                        Picker("选择区域", selection: $selectedManualRegion) {
                            Text("选择区域").tag("")
                            ForEach(manualRegions, id: \.self) { Text($0).tag($0) }
                        }
                        .onChange(of: selectedManualRegion) { _, region in
                            guard !region.isEmpty else { return }
                            onExpireNearbyLocation()
                            onSearchRegion(region)
                        }
                    }
                    if let manualRegionsError {
                        Text(manualRegionsError)
                            .font(.system(size: NativeTypography.size(12)))
                            .foregroundStyle(.red)
                    }
                    if !selectedManualRegion.isEmpty && error != nil {
                        Button("重试区域景点查询") {
                            onSearchRegion(selectedManualRegion)
                        }
                        .foregroundStyle(Brand.primary)
                    }
                }
            }
        }
    }
}
