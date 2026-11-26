import SwiftUI

enum HomePaneDestination {
    case feature(String)
    case catalog(CatalogModule)
    case scenic(ResourceItem, String?)
    case activity(String)
    case article(String, String)
    case product(String)
    case hotel(String)
    case dining(String)
    case travelRoute(String)
}
struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    let store: SessionStore
    let isVisible: Bool
    let onMap: () -> Void
    let onBrowse: () -> Void
    let onProfile: () -> Void
    let onCouponCenter: () -> Void
    let onSearch: (String) -> Void
    let onDetailChange: (Bool) -> Void
    let onInitialLoadComplete: () -> Void
    let pinnedHome: Bool
    let onPinnedDestination: (HomePaneDestination) -> Void
    @State var catalogs: [CatalogModule] = []
    @State var moduleRows: [String: [[String: Any]]] = [:]
    @State var moduleErrors: [String: String] = [:]
    @State var components: [[String: Any]] = []
    @State var operationComponents: [[String: Any]] = []
    @State var quickEntryItems: [[String: Any]] = []
    @State var fallbackShortcutIndices: [Int] = []
    @State var featured: [[String: Any]] = []
    @State var configuredOrder: [String] = []
    @State var featuredTitle = "精选推荐"
    @State var featuredSortOrder = 0
    @State private var pendingFeatureID: String?
    @State var quickEntriesConfigured = false
    @State private var quickEntryNotice: String?
    @State private var shortcutCatalog: CatalogModule?
    @State private var shortcutScenic: ResourceItem?
    @State private var shortcutGuideRouteID: String?
    @State private var bannerActivityID: String?
    @State private var bannerArticleID: String?
    @State private var bannerArticleSiteID = "1"
    @State private var bannerProductID: String?
    @State private var bannerHotelID: String?
    @State private var bannerDiningID: String?
    @State private var bannerTravelRouteID: String?
    @State private var search = ""
    @State var loading = true
    @State var error: String?
    @State private var revision = 0
    @State var homeLayoutDeadline: Date?
    @State var homeLoadGeneration = 0
    @State private var serviceStatusClock = Date()
    @State private var appeared = false
    @State var initialLoadCompleted = false
    @State private var bannerIndex = 0
    @State private var bannerManualPauseUntil = Date.distantPast

    private var banner: [String: Any]? {
        components.first { ($0["ComponentType"] as? String)?.lowercased() == "banner" }
    }

    private var bannerSlides: [[String: Any]] {
        let design = banner?["BannerDesign"] as? [String: Any]
        let slides = design?["Slides"] as? [[String: Any]] ?? []
        return slides.isEmpty ? (banner.map { [$0] } ?? []) : slides
    }

    private var slide: [String: Any]? {
        guard !bannerSlides.isEmpty else { return nil }
        return bannerSlides[min(bannerIndex, bannerSlides.count - 1)]
    }

    private var bannerDesign: [String: Any]? { banner?["BannerDesign"] as? [String: Any] }

    private var bannerOverlaySlide: [String: Any]? {
        guard !bannerSlides.isEmpty else { return nil }
        return (bannerDesign?["OverlayMode"] as? String) == "Shared"
            ? bannerSlides[0] : bannerSlides[min(bannerIndex, bannerSlides.count - 1)]
    }

    private var quickEntries: [[String: Any]] {
        quickEntryItems
    }

    private func showPendingFeature(_ id: String) {
        if pinnedHome { onPinnedDestination(.feature(id)) }
        else { pendingFeatureID = id }
    }

    private func showCatalog(_ module: CatalogModule) {
        if pinnedHome { onPinnedDestination(.catalog(module)) }
        else { shortcutCatalog = module }
    }

    private func showScenic(_ item: ResourceItem, initialGuideRouteID: String? = nil) {
        if pinnedHome { onPinnedDestination(.scenic(item, initialGuideRouteID)) }
        else {
            shortcutScenic = item
            shortcutGuideRouteID = initialGuideRouteID
        }
    }

    private func showActivity(_ id: String) {
        if pinnedHome { onPinnedDestination(.activity(id)) }
        else { bannerActivityID = id }
    }

    private func showArticle(_ id: String, siteID: String = "1") {
        if pinnedHome { onPinnedDestination(.article(id, siteID)) }
        else { bannerArticleID = id; bannerArticleSiteID = siteID }
    }

    private func showProduct(_ id: String) {
        if pinnedHome { onPinnedDestination(.product(id)) }
        else { bannerProductID = id }
    }

    private func showHotel(_ id: String) {
        if pinnedHome { onPinnedDestination(.hotel(id)) }
        else { bannerHotelID = id }
    }

    private func showDining(_ id: String) {
        if pinnedHome { onPinnedDestination(.dining(id)) }
        else { bannerDiningID = id }
    }

    private func showTravelRoute(_ id: String) {
        if pinnedHome { onPinnedDestination(.travelRoute(id)) }
        else { bannerTravelRouteID = id }
    }

    private func openBannerTarget() {
        let targetPathField = slide.map { consistentHomeStringField($0, upperKey: "TargetPath", lowerKey: "targetPath") }
        guard targetPathField?.isValid == true, let rawTarget = targetPathField?.value,
              let destination = NativeHomeBannerDestination(rawPath: rawTarget) else { return }
        switch destination.path {
        case "/pages/map/index": onMap()
        case "/pages/discover/index": onBrowse()
        case "/pages/profile/index": onProfile()
        case "/subpackages/activities/activity/index":
            if let id = destination.id { showActivity(id) }
        case "/subpackages/tourism/article/index":
            if let id = destination.id { showArticle(id, siteID: destination.siteID) }
        case "/subpackages/commerce/product/index":
            if let id = destination.id { showProduct(id) }
        case "/subpackages/tourism/hotel/index":
            if let id = destination.id { showHotel(id) }
        case "/subpackages/dining/restaurant/index":
            if let id = destination.id { showDining(id) }
        case "/subpackages/tourism/route/index":
            if let id = destination.id { showTravelRoute(id) }
        case "/subpackages/tourism/resource/index":
            if let id = destination.id, let item = ResourceItem(["Id": id, "ResourceType": "ScenicSpot"]) {
                showScenic(item, initialGuideRouteID: destination.guideRouteID)
            }
        case "/subpackages/tourism/facility/index":
            if let id = destination.id, let item = ResourceItem(["Id": id, "ResourceType": "Facility"]) {
                showScenic(item)
            }
        case "/subpackages/activities/activities/index":
            showCatalog(.init(id: "activities", title: "最新活动", path: "/api/JHCTIActivity/GetPublicPage", featureID: "MODULE-ACTIVITY"))
        case "/subpackages/tourism/articles/index":
            showCatalog(.init(id: "articles", title: "文旅资讯", path: "/api/app/articles/List", featureID: "MODULE-GUIDE"))
        case "/subpackages/commerce/products/index":
            showCatalog(.init(id: "products", title: "江都好物", path: "/api/JHCTIProduct/GetPublicPage", featureID: "MODULE-PRODUCT"))
        case "/subpackages/tourism/hotels/index":
            showCatalog(.init(id: "hotels", title: "酒店民宿", path: "/api/JHCTIHotel/GetPublicPage", featureID: "MODULE-HOTEL"))
        case "/subpackages/dining/restaurants/index":
            showCatalog(.init(id: "dining", title: "特色美食", path: "/api/JHCTIDining/GetPublicStoresPage", featureID: "MODULE-DINING"))
        case "/subpackages/tourism/routes/index":
            showCatalog(.init(id: "routes", title: "旅游线路", path: "/api/JHCTITravelRoute/GetPublicPage", featureID: "MODULE-TRAVEL-ROUTE"))
        case "/subpackages/tourism/intangible-heritage/index":
            showCatalog(.init(id: "intangibleHeritage", title: "非遗文化", path: "/api/app/articles/List", featureID: "MODULE-GUIDE", categoryValue: "非遗文化"))
        default: break
        }
    }

    private func openQuickEntry(_ item: [String: Any], index: Int) {
        guard isValidHomeQuickEntryTarget(item) else {
            quickEntryNotice = "内容暂不可用"
            return
        }
        let type = (item["TargetType"] as? String ?? item["targetType"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetID = item["TargetId"] as? String ?? item["targetId"] as? String ?? ""
        if ["scenicspot", "ticket", "article", "activity", "product", "hotel", "travelroute", "diningstore"].contains(type) {
            guard targetID.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
                  Int64(targetID).map({ $0 > 0 }) == true else {
                quickEntryNotice = "内容暂不可用"
                return
            }
            switch type {
            case "scenicspot", "ticket":
                if let item = ResourceItem(["Id": targetID]) { showScenic(item) }
            case "article": showArticle(targetID)
            case "activity": showActivity(targetID)
            case "product": showProduct(targetID)
            case "hotel": showHotel(targetID)
            case "travelroute": showTravelRoute(targetID)
            case "diningstore": showDining(targetID)
            default: break
            }
            return
        }
        let key = (item["InternalPageKey"] as? String ?? item["internalPageKey"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let title = item["Title"] as? String ?? item["title"] as? String
        if key == "intangible-heritage" || (key == "articles" && title?.trimmingCharacters(in: .whitespacesAndNewlines) == "非遗文化") {
            showCatalog(.init(id: "intangibleHeritage", title: "非遗文化", path: "/api/app/articles/List", featureID: "MODULE-GUIDE", categoryValue: "非遗文化"))
        } else if key == "guide" || (index == 6 && !quickEntriesConfigured) {
            showCatalog(.init(id: "articles", title: "旅游攻略", path: "/api/app/articles/List", featureID: "MODULE-GUIDE", categoryValue: "859587799032325"))
        } else if key == "hotels" {
            showCatalog(.init(id: "hotels", title: "酒店民宿", path: "/api/JHCTIHotel/GetPublicPage", featureID: "MODULE-HOTEL"))
        } else {
            openQuickEntryPage(key: key, index: index)
        }
    }

    private func openQuickEntryPage(key: String, index: Int) {
        if key == "discover" { onBrowse() }
        else if key == "profile" { onProfile() }
        else if key == "coupon-center" { onCouponCenter() }
        else if key == "group-buy" { showPendingFeature("F-FNB-007") }
        else if key == "flash-sale" { showPendingFeature("F-OPS-005") }
        else if ["map", "attractions", "tickets", "tourism-map"].contains(key) || (key.isEmpty && (index == 0 || index == 1)) { onMap() }
        else if ["activity", "activities"].contains(key) || (key.isEmpty && index == 4) {
            showCatalog(.init(id: "activities", title: "江都活动", path: "/api/JHCTIActivity/GetPublicPage", featureID: "MODULE-ACTIVITY"))
        } else if ["shop", "products"].contains(key) {
            showCatalog(.init(id: "products", title: "江都好物", path: "/api/JHCTIProduct/GetPublicPage", featureID: "MODULE-PRODUCT"))
        } else if ["hotels"].contains(key) || (key.isEmpty && index == 3) {
            showCatalog(.init(id: "hotels", title: "酒店民宿", path: "/api/JHCTIHotel/GetPublicPage", featureID: "MODULE-HOTEL"))
        } else if ["routes", "travel-routes"].contains(key) || (key.isEmpty && index == 7) {
            showCatalog(.init(id: "routes", title: "旅游线路", path: "/api/JHCTITravelRoute/GetPublicPage", featureID: "MODULE-TRAVEL-ROUTE"))
        } else if ["dining", "restaurants", "food"].contains(key) || (key.isEmpty && index == 2) {
            showCatalog(.init(id: "dining", title: "特色美食", path: "/api/JHCTIDining/GetPublicStoresPage", featureID: "MODULE-DINING"))
        } else if key == "intangible-heritage" || (key.isEmpty && index == 5) {
            showCatalog(.init(id: "intangibleHeritage", title: "非遗文化", path: "/api/app/articles/List", featureID: "MODULE-GUIDE", categoryValue: "非遗文化"))
        } else if ["guide", "articles"].contains(key) || (key.isEmpty && index == 6) {
            showCatalog(.init(id: "articles", title: "文旅资讯", path: "/api/app/articles/List", featureID: "MODULE-GUIDE"))
        } else { quickEntryNotice = "该服务暂未接入" }
    }

    private func openRecommendation(_ item: [String: Any]) {
        guard let rawType = homeRecommendationTargetType(item) else {
            quickEntryNotice = "内容暂不可用"
            return
        }
        let type = rawType.lowercased()
        if type == "internalpage" {
            guard let key = homeRecommendationInternalPageKey(item) else {
                quickEntryNotice = "内容暂不可用"
                return
            }
            let title = item["Title"] as? String ?? item["title"] as? String ?? ""
            switch key {
            case "profile": onProfile()
            case "coupon-center": onCouponCenter()
            case "group-buy": showPendingFeature("F-FNB-007")
            case "flash-sale": showPendingFeature("F-OPS-005")
            case "articles" where title.trimmingCharacters(in: .whitespacesAndNewlines) == "非遗文化":
                showCatalog(.init(id: "intangibleHeritage", title: "非遗文化", path: "/api/app/articles/List",
                    featureID: "MODULE-GUIDE", categoryValue: "非遗文化"))
            default: openQuickEntryPage(key: key, index: -1)
            }
            return
        }
        guard ["scenicspot", "ticket", "article", "activity", "product", "hotel", "travelroute", "diningstore"].contains(type) else {
            quickEntryNotice = "该内容暂未接入"
            return
        }
        guard let id = homeRecommendationTargetID(item), isValidHomeRecommendationTargetID(id) else {
            quickEntryNotice = "内容暂不可用"
            return
        }
        switch type {
        case "scenicspot", "ticket":
            if let item = ResourceItem(["Id": id]) { showScenic(item) }
        case "article": showArticle(id)
        case "activity": showActivity(id)
        case "product": showProduct(id)
        case "hotel": showHotel(id)
        case "travelroute": showTravelRoute(id)
        case "diningstore": showDining(id)
        default: break
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    hero
                    StatusView(loading: loading, error: error) { revision += 1 }
                        .padding(.horizontal, 16)
                    if !loading && (error == nil || (quickEntriesConfigured && !quickEntryItems.isEmpty)) {
                        NativeHomeSectionList(
                            store: store,
                            showsShortcuts: quickEntriesConfigured ? !quickEntryItems.isEmpty : !fallbackShortcutIndices.isEmpty,
                            shortcutOrder: quickEntryItems.compactMap {
                                $0["SortOrder"] as? Int ?? $0["sortOrder"] as? Int
                            }.min(),
                            shortcutContent: AnyView(shortcutGrid),
                            operationComponents: operationComponents,
                            configuredOrder: configuredOrder,
                            catalogs: catalogs,
                            featuredTitle: featuredTitle,
                            featuredRows: featured,
                            featuredSortOrder: featuredSortOrder,
                            moduleRows: moduleRows,
                            moduleErrors: moduleErrors,
                            serviceStatusClock: serviceStatusClock,
                            onBrowse: onBrowse,
                            onOpenRecommendation: openRecommendation,
                            onRetry: { revision += 1 }
                        )
                    }
                }
                .padding(.bottom, 20)
            }
            .background(Brand.background)
            .alert("提示", isPresented: Binding(
                get: { quickEntryNotice != nil }, set: { if !$0 { quickEntryNotice = nil } }
            )) {
                Button("确定", role: .cancel) { quickEntryNotice = nil }
            } message: {
                Text(quickEntryNotice ?? "")
            }
            .refreshable { await load(forceRefresh: true) }
            .task(id: "\(scenePhase)-\(isVisible)") {
                guard scenePhase == .active, isVisible else { return }
                serviceStatusClock = Date()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled, scenePhase == .active, isVisible else { return }
                    serviceStatusClock = Date()
                }
            }
            .task(id: "\(scenePhase)-\(revision)-\(isVisible)") {
                guard scenePhase == .active, isVisible else { return }
                let api = MobileAPI(store: store)
                let cached = api.cachedHomeLayout()
                if let cached {
                    // 首页只预览尚未越过排期的布局，随后重新向服务端读取。
                    await load(cachedLayout: cached)
                    guard !Task.isCancelled else { return }
                }
                await load(forceRefresh: cached == nil && revision > 0)
            }
            .task(id: "\(homeLayoutDeadline?.timeIntervalSince1970 ?? 0)-\(scenePhase)-\(isVisible)") {
                guard let deadline = homeLayoutDeadline, scenePhase == .active, isVisible else { return }
                while !Task.isCancelled {
                    let remaining = deadline.timeIntervalSinceNow
                    if remaining <= 0 { break }
                    try? await Task.sleep(for: .seconds(min(86_400, remaining)))
                }
                guard !Task.isCancelled, homeLayoutDeadline == deadline else { return }
                clearExpiredHomeLayout()
                revision += 1
            }
            .task(id: "\(bannerSlides.count)-\(bannerDesign?["AutoPlay"] as? Bool ?? false)-\(bannerDesign?["IntervalSeconds"] as? Int ?? 5)-\(bannerDesign?["Loop"] as? Bool ?? true)-\(bannerIndex)-\(bannerManualPauseUntil.timeIntervalSince1970)-\(scenePhase)-\(isVisible)") {
                guard bannerSlides.count > 1,
                      scenePhase == .active,
                      isVisible,
                      bannerDesign?["AutoPlay"] as? Bool == true else { return }
                let interval = min(10, max(3, bannerDesign?["IntervalSeconds"] as? Int ?? 5))
                let loops = bannerDesign?["Loop"] as? Bool ?? true
                let pauseRemaining = bannerManualPauseUntil.timeIntervalSinceNow
                if pauseRemaining > 0 { try? await Task.sleep(for: .seconds(pauseRemaining)) }
                while !Task.isCancelled {
                    if !loops && bannerIndex >= bannerSlides.count - 1 { return }
                    try? await Task.sleep(for: .seconds(interval))
                    guard !Task.isCancelled else { return }
                    if bannerIndex + 1 < bannerSlides.count { bannerIndex += 1 }
                    else if loops { bannerIndex = 0 }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { shortcutCatalog != nil },
                set: { if !$0 { shortcutCatalog = nil } }
            )) {
                if let shortcutCatalog { CatalogView(store: store, module: shortcutCatalog) }
            }
            .navigationDestination(isPresented: Binding(
                get: { shortcutScenic != nil }, set: { if !$0 { shortcutScenic = nil } }
            )) {
                if let shortcutScenic {
                    ResourceDetailView(store: store, item: shortcutScenic, onVisibilityChange: onDetailChange,
                        initialGuideRouteID: shortcutGuideRouteID)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { bannerActivityID != nil }, set: { if !$0 { bannerActivityID = nil } }
            )) {
                if let bannerActivityID { ActivityDetailView(store: store, id: bannerActivityID) }
            }
            .navigationDestination(isPresented: Binding(
                get: { bannerArticleID != nil }, set: { if !$0 { bannerArticleID = nil } }
            )) {
                if let bannerArticleID {
                    ArticleDetailView(store: store, id: bannerArticleID, siteID: bannerArticleSiteID)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { bannerProductID != nil }, set: { if !$0 { bannerProductID = nil } }
            )) {
                if let bannerProductID { ProductDetailView(store: store, id: bannerProductID, fallbackCover: nil) }
            }
            .navigationDestination(isPresented: Binding(
                get: { bannerHotelID != nil }, set: { if !$0 { bannerHotelID = nil } }
            )) {
                if let bannerHotelID { HotelPublicDetailView(store: store, id: bannerHotelID) }
            }
            .navigationDestination(isPresented: Binding(
                get: { bannerDiningID != nil }, set: { if !$0 { bannerDiningID = nil } }
            )) {
                if let bannerDiningID { DiningPublicDetailView(store: store, id: bannerDiningID) }
            }
            .navigationDestination(isPresented: Binding(
                get: { bannerTravelRouteID != nil }, set: { if !$0 { bannerTravelRouteID = nil } }
            )) {
                if let bannerTravelRouteID { TravelRouteDetailView(store: store, id: bannerTravelRouteID) }
            }
            .sheet(isPresented: Binding(
                get: { pendingFeatureID != nil }, set: { if !$0 { pendingFeatureID = nil } }
            )) {
                if let pendingFeatureID { NativeFeaturePendingView(store: store, featureId: pendingFeatureID) }
            }
            .onAppear {
                if appeared && !loading { revision += 1 }
                appeared = true
            }
            .onChange(of: scenePhase) { _, phase in
                // 前台恢复时重新计算首页组件的上线和下线时间，避免沿用旧布局缓存。
                if phase == .active && isVisible && initialLoadCompleted {
                    revision += 1
                }
            }
        }
        // 首页内部导航栈也隐藏系统 Tab 栏，避免 Duo 单屏在详情页出现右侧系统菜单。
        // 单屏从首页进入的详情继续使用紧凑布局，避免导航目的页重新继承设备的 regular 尺寸类别。
        .environment(\.horizontalSizeClass, pinnedHome ? .regular : .compact)
        .toolbar(.hidden, for: .tabBar)
    }

    private var hero: some View {
        NativeHomeHeroView(
            store: store,
            slide: slide,
            overlay: bannerOverlaySlide,
            bannerSlides: bannerSlides,
            bannerDesign: bannerDesign,
            bannerIndex: $bannerIndex,
            bannerManualPauseUntil: $bannerManualPauseUntil,
            search: $search,
            onSearch: onSearch,
            onBannerTap: openBannerTarget
        )
    }

    private var shortcutGrid: some View {
        let shortcutIndices = quickEntriesConfigured ? Array(quickEntries.indices) : fallbackShortcutIndices
        return NativeHomeQuickEntrySection(
            store: store,
            shortcutIndices: shortcutIndices,
            entries: quickEntries,
            titleForEntry: { entry, index in NativeHomeQuickEntryPresentation.fallbackTitle(for: entry, index: index) },
            iconIndexForEntry: { entry, index in NativeHomeQuickEntryPresentation.iconIndex(for: entry, fallback: index) },
            onOpenEntry: { entry, index in openQuickEntry(entry, index: index) },
            onOpenFallback: { key, index in openQuickEntryPage(key: key, index: index) }
        )
    }

    @ViewBuilder
    private func remoteImage(_ path: String?, height: CGFloat, fallback: String? = "Hero") -> some View {
        GeometryReader { geometry in
            if let url = MobileAPI(store: store).mediaURL(path) {
                CachedRemoteImage(url: url) {
                    imageFallback(fallback)
                }
                .frame(width: geometry.size.width, height: height).clipped()
            } else {
                imageFallback(fallback)
                    .frame(width: geometry.size.width, height: height).clipped()
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func imageFallback(_ name: String?) -> some View {
        if let name {
            Image(name).resizable().scaledToFill()
        } else {
            Color(red: 0.94, green: 0.96, blue: 0.95)
                .overlay { Image(systemName: "photo").foregroundStyle(Brand.muted) }
        }
    }

}
