import SwiftUI

struct DiscoveryCategory: Identifiable {
    let id: String
    let title: String
    let icon: Int
    let module: CatalogModule?
    let featureID: String

    static let all: [Self] = [
        .init(id: "map", title: "文旅地图", icon: 1,
              module: nil, featureID: "MODULE-SCENIC"),
        .init(id: "tickets", title: "景区门票", icon: 5,
              module: nil, featureID: "F-TKT-002"),
        .init(id: "routes", title: "旅游线路", icon: 7,
              module: .init(id: "routes", title: "旅游线路", path: "/api/JHCTITravelRoute/GetPublicPage",
                            featureID: "MODULE-TRAVEL-ROUTE"), featureID: "MODULE-TRAVEL-ROUTE"),
        .init(id: "hotels", title: "酒店民宿", icon: 3,
              module: .init(id: "hotels", title: "酒店民宿", path: "/api/JHCTIHotel/GetPublicPage",
                            featureID: "MODULE-HOTEL"), featureID: "MODULE-HOTEL"),
        .init(id: "dining", title: "特色美食", icon: 2,
              module: .init(id: "dining", title: "特色美食", path: "/api/JHCTIDining/GetPublicStoresPage",
                            featureID: "MODULE-DINING"), featureID: "MODULE-DINING"),
        .init(id: "articles", title: "旅游攻略", icon: 6,
              module: .init(id: "articles", title: "旅游攻略", path: "/api/app/articles/List",
                            featureID: "MODULE-GUIDE"), featureID: "MODULE-GUIDE"),
        .init(id: "products", title: "文旅好物", icon: 0,
              module: .init(id: "products", title: "文旅好物", path: "/api/JHCTIProduct/GetPublicPage",
                            featureID: "MODULE-PRODUCT"), featureID: "MODULE-PRODUCT"),
        .init(id: "activities", title: "近期活动", icon: 4,
              module: .init(id: "activities", title: "近期活动", path: "/api/JHCTIActivity/GetPublicPage",
                            featureID: "MODULE-ACTIVITY"), featureID: "MODULE-ACTIVITY")
    ]
}

struct DiscoveryCategoryGrid: View {
    let store: SessionStore
    let accessStates: [String: NativePublicFeatureAccessState]
    let onMap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("江都文旅").font(.system(size: NativeTypography.size(18), weight: .semibold)).foregroundStyle(Brand.ink)
                Spacer()
                Text("按兴趣探索本地服务").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 16) {
                ForEach(DiscoveryCategory.all) { category in
                    if let module = category.module {
                        NavigationLink { CatalogView(store: store, module: module) } label: {
                            categoryCard(category)
                        }
                        .disabled(accessStates[category.id] != .open)
                    } else {
                        Button(action: onMap) { categoryCard(category) }
                            .disabled(accessStates[category.id] != .open)
                    }
                }
            }
        }
        .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func categoryCard(_ category: DiscoveryCategory) -> some View {
        VStack(spacing: 4) {
            Image("Quick\(category.icon)").resizable().scaledToFit().frame(width: 42, height: 42)
            Text(category.title).font(.system(size: NativeTypography.size(14), weight: .medium)).foregroundStyle(Brand.ink)
                .lineLimit(1).minimumScaleFactor(0.85)
            if let status = categoryStatusText(category) {
                Text(status)
                    .font(.system(size: NativeTypography.size(12))).lineLimit(1).minimumScaleFactor(0.85).foregroundStyle(Brand.muted)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func categoryStatusText(_ category: DiscoveryCategory) -> String? {
        guard let state = accessStates[category.id] else { return "正在确认开放状态" }
        switch state {
        case .open: return nil
        case .closed: return "平台暂未开放"
        case .pendingConfirmation: return "开放状态待确认"
        case .unavailable: return "状态暂不可用"
        }
    }
}
