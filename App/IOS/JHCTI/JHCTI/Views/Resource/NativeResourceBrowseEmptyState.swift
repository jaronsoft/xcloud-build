import SwiftUI

struct NativeResourceBrowseScreenTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .foregroundStyle(Brand.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NativeResourceBrowseEmptyState: View {
    let loading: Bool
    let error: String?
    let selectedManualRegion: String
    let keyword: String
    let selectedFilter: String
    let nearbyResourceType: String
    let onSearch: () -> Void
    let onViewAll: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: loading ? "map" : error != nil ? "wifi.exclamationmark" : "map.circle")
                .font(.system(size: 44)).foregroundStyle(Brand.primary)
                .padding(20).background(Brand.primary.opacity(0.08), in: Circle())
            if loading {
                ProgressView().tint(Brand.primary)
                Text("正在加载景点与设施…").foregroundStyle(Brand.ink)
            } else {
                Text(error != nil ? "暂时无法加载" : "暂未找到相关内容")
                    .font(.system(size: NativeTypography.size(18), weight: .semibold)).foregroundStyle(Brand.ink)
                Text(error ?? (!selectedManualRegion.isEmpty
                    ? (!keyword.isEmpty
                        ? "所选区域没有名称包含“\(keyword)”的已发布景点。"
                        : "所选区域暂无已发布景点。")
                    : (keyword.isEmpty && selectedFilter == "全部" && nearbyResourceType == "Facility"
                        ? "附近暂无已发布服务设施。"
                        : keyword.isEmpty && selectedFilter == "全部"
                        ? "已发布的景点与设施会显示在这里，稍后再来看看吧。"
                        : "试试其他分类，或清空关键词后重新搜索。")))
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
                Button(!selectedManualRegion.isEmpty ? "刷新所选区域" : error != nil ? "重新加载" : "刷新内容", action: onSearch)
                    .buttonStyle(.borderedProminent).tint(Brand.primary)
                if !keyword.isEmpty || selectedFilter != "全部" {
                    Button("查看全部", action: onViewAll)
                        .foregroundStyle(Brand.primary)
                }
            }
        }
        .padding(24).frame(maxWidth: .infinity, minHeight: 300)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}
