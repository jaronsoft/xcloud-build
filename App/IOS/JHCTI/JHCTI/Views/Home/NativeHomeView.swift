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
    @State private var catalogs: [CatalogModule] = []
    @State private var moduleRows: [String: [[String: Any]]] = [:]
    @State private var moduleErrors: [String: String] = [:]
    @State private var components: [[String: Any]] = []
    @State private var operationComponents: [[String: Any]] = []
    @State private var quickEntryItems: [[String: Any]] = []
    @State private var fallbackShortcutIndices: [Int] = []
    @State private var featured: [[String: Any]] = []
    @State private var configuredOrder: [String] = []
    @State private var featuredTitle = "精选推荐"
    @State private var featuredSortOrder = 0
    @State private var pendingFeatureID: String?
    @State private var quickEntriesConfigured = false
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
    @State private var loading = true
    @State private var error: String?
    @State private var revision = 0
    @State private var nextComponentChangeDelayMs: Int64?
    @State private var serviceStatusClock = Date()
    @State private var appeared = false
    @State private var initialLoadCompleted = false
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
        let key = (item["InternalPageKey"] as? String ?? item["internalPageKey"] as? String ?? "").lowercased()
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

    private let shortcuts = [
        "景区门票", "文旅地图", "特色美食", "酒店民宿",
        "促销活动", "非遗文化", "旅游攻略", "旅游线路"
    ]
    private func quickEntryFallbackTitle(_ entry: [String: Any]?, index: Int) -> String {
        guard let entry else { return shortcuts.indices.contains(index) ? shortcuts[index] : "文旅服务" }
        let key = (entry["InternalPageKey"] as? String ?? entry["internalPageKey"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pageTitles = [
            "map": "文旅地图", "discover": "发现", "attractions": "文旅地图", "tourism-map": "文旅地图",
            "activities": "近期活动", "activity": "近期活动", "tickets": "景区门票",
            "products": "文旅好物", "shop": "文旅好物", "hotels": "酒店民宿",
            "routes": "旅游线路", "travel-routes": "旅游线路", "dining": "特色美食",
            "restaurants": "特色美食", "food": "特色美食", "guide": "旅游攻略",
            "articles": "文旅资讯", "intangible-heritage": "非遗文化",
            "group-buy": "团购优惠", "flash-sale": "限时优惠", "coupon-center": "优惠券中心", "profile": "个人中心"
        ]
        if let title = pageTitles[key] { return title }
        let type = (entry["TargetType"] as? String ?? entry["targetType"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetTitles = [
            "scenicspot": "景点详情", "ticket": "景区门票", "activity": "近期活动",
            "product": "文旅好物", "hotel": "酒店民宿", "travelroute": "旅游线路",
            "diningstore": "特色美食", "article": "文旅资讯"
        ]
        if let title = targetTitles[type] { return title }
        return quickEntryPathTitle(entry) ?? (shortcuts.indices.contains(index) ? shortcuts[index] : "文旅服务")
    }
    private func quickEntryTargetPath(_ entry: [String: Any]?) -> String? {
        guard let entry else { return nil }
        let raw = (entry["TargetPath"] as? String ?? entry["targetPath"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("/"), !raw.hasPrefix("//") else { return nil }
        let path = raw.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? raw
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
            ? "/" : "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }
    private func quickEntryPathValue(_ path: String?, values: [String: Int]) -> Int? {
        guard let path else { return nil }
        if let index = values[path] { return index }
        let segments = path.split(separator: "/").map(String.init)
        guard let first = segments.first else { return nil }
        if first == "attractions", segments.count == 2 { return 1 }
        if first == "attractions", segments.last == "tickets" { return 0 }
        if first == "attractions", segments.last == "guide" { return 6 }
        return values["/\(first)"]
    }
    private func quickEntryPathTitle(_ entry: [String: Any]?) -> String? {
        let values = [
            "/map": "文旅地图", "/discover": "发现", "/attractions": "文旅地图", "/tickets": "景区门票",
            "/activities": "近期活动", "/products": "文旅好物", "/shop": "文旅好物",
            "/hotels": "酒店民宿", "/routes": "旅游线路", "/travel-routes": "旅游线路",
            "/dining": "特色美食", "/restaurants": "特色美食", "/food": "特色美食",
            "/articles": "文旅资讯", "/guide": "旅游攻略", "/intangible-heritage": "非遗文化",
            "/group-buy": "团购优惠", "/flash-sale": "限时优惠", "/coupon-center": "优惠券中心",
            "/profile": "个人中心"
        ]
        guard let path = quickEntryTargetPath(entry) else { return nil }
        if let title = values[path] { return title }
        let segments = path.split(separator: "/").map(String.init)
        guard let first = segments.first else { return nil }
        if first == "attractions", segments.count == 2 { return "景点详情" }
        if first == "attractions", segments.last == "tickets" { return "景区门票" }
        if first == "attractions", segments.last == "guide" { return "旅游攻略" }
        return values["/\(first)"]
    }
    private func quickEntryIconIndex(_ entry: [String: Any]?, fallback: Int) -> Int {
        guard let entry else { return fallback }
        let key = (entry["InternalPageKey"] as? String ?? entry["internalPageKey"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pageIndexes = [
            "map": 1, "discover": 1, "attractions": 1, "tourism-map": 1,
            "activities": 4, "activity": 4, "tickets": 0,
            "products": 0, "shop": 0, "hotels": 3,
            "routes": 7, "travel-routes": 7, "dining": 2,
            "restaurants": 2, "food": 2, "guide": 6,
            "articles": 6, "intangible-heritage": 5,
            "group-buy": 4, "flash-sale": 4, "coupon-center": 4
        ]
        if let index = pageIndexes[key] { return index }
        let type = (entry["TargetType"] as? String ?? entry["targetType"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let typeIndexes = [
            "scenicspot": 1, "ticket": 0, "activity": 4, "product": 0,
            "hotel": 3, "travelroute": 7, "diningstore": 2, "article": 6
        ]
        if let index = typeIndexes[type] { return index }
        return quickEntryPathValue(quickEntryTargetPath(entry), values: [
            "/map": 1, "/discover": 1, "/attractions": 1, "/tickets": 0, "/activities": 4,
            "/products": 0, "/shop": 0, "/hotels": 3, "/routes": 7,
            "/travel-routes": 7, "/dining": 2, "/restaurants": 2, "/food": 2,
            "/articles": 6, "/guide": 6, "/intangible-heritage": 5,
            "/group-buy": 4, "/flash-sale": 4, "/coupon-center": 4
        ]) ?? fallback
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    hero
                    StatusView(loading: loading, error: error) { revision += 1 }
                        .padding(.horizontal, 16)
                    if !loading && error == nil {
                        ForEach(orderedHomeSections) { section in
                            section.content
                        }
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
            .task(id: revision) {
                let api = MobileAPI(store: store)
                let homePath = "/api/JHCTIHomePage/GetPublicHome"
                if revision == 0 && api.hasPublicCachedData(homePath) {
                    await load(allowStale: true)
                    guard !Task.isCancelled else { return }
                    await load(forceRefresh: true)
                } else {
                    await load(forceRefresh: revision > 0)
                }
            }
            .task(id: nextComponentChangeDelayMs) {
                guard let delay = nextComponentChangeDelayMs, delay > 0,
                      scenePhase == .active, isVisible else { return }
                // 仅在服务端给出的下一次组件变化时刷新，页面离开或进入后台后由现有生命周期重新加载。
                try? await Task.sleep(for: .milliseconds(max(1000, delay)))
                guard !Task.isCancelled, scenePhase == .active, isVisible else { return }
                nextComponentChangeDelayMs = nil
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
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 18) {
            ForEach(shortcutIndices.indices, id: \.self) { position in
                let shortcutIndex = shortcutIndices[position]
                let entry = quickEntries.indices.contains(position) ? quickEntries[position] : nil
                let iconIndex = quickEntryIconIndex(entry, fallback: shortcutIndex)
                let rawTitle = entry?["Title"] as? String ?? entry?["title"] as? String
                let configuredTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = configuredTitle.flatMap { $0.isEmpty ? nil : $0 }
                    ?? quickEntryFallbackTitle(entry, index: shortcutIndex)
                let configuredImage = entry?["ImageUrl"] as? String ?? entry?["imageUrl"] as? String
                Button {
                    if let entry { openQuickEntry(entry, index: position) }
                    else { openQuickEntryPage(key: "", index: shortcutIndex) }
                } label: {
                    VStack(spacing: 4) {
                        if let configuredImage, !configuredImage.isEmpty {
                            remoteImage(configuredImage, height: 42, fallback: "Quick\(iconIndex % 8)")
                                .frame(width: 42, height: 42)
                        } else {
                            Image("Quick\(iconIndex % 8)").resizable().scaledToFit().frame(width: 42, height: 42)
                        }
                        VStack(spacing: 2) {
                            Text(title)
                                .font(.system(size: NativeTypography.size(12), weight: .medium)).foregroundStyle(Brand.ink)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityHint("打开此服务")
            }
        }
        .padding(.vertical, 20).padding(.horizontal, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private var orderedHomeSections: [HomeSectionView] {
        var sections: [HomeSectionView] = []
        var sourceOrder = 0
        let shortcutOrder = quickEntryItems.compactMap { $0["SortOrder"] as? Int ?? $0["sortOrder"] as? Int }.min()
        let hasVisibleShortcuts = quickEntriesConfigured ? !quickEntryItems.isEmpty : !fallbackShortcutIndices.isEmpty
        if hasVisibleShortcuts {
            sections.append(HomeSectionView(id: "shortcuts", sortOrder: (shortcutOrder ?? 0) + 1,
                sourceOrder: sourceOrder, content: AnyView(shortcutGrid)))
            sourceOrder += 1
        }

        for (index, item) in operationComponents.enumerated() {
            let sortOrder = item["SortOrder"] as? Int ?? item["sortOrder"] as? Int ?? 0
            sections.append(HomeSectionView(id: "operation-\(index)", sortOrder: sortOrder + 1,
                sourceOrder: sourceOrder, content: AnyView(NativeHomeOperationComponent(
                    store: store, item: item, serviceStatusClock: serviceStatusClock,
                    onOpen: { openRecommendation(item) }))))
            sourceOrder += 1
        }

        let moduleSourceOrder: (String) -> Int = { key in
            switch key {
            case "featured": return 0
            case "articles": return 1
            case "activities": return 2
            default: return 3 + (configuredOrder.firstIndex(of: key) ?? configuredOrder.count)
            }
        }
        for key in configuredOrder.sorted(by: { moduleSourceOrder($0) < moduleSourceOrder($1) }) {
            if key == "featured" {
                sections.append(HomeSectionView(id: "module-featured", sortOrder: featuredSortOrder + 1,
                    sourceOrder: sourceOrder, content: AnyView(featuredSection)))
            } else if let module = catalogs.first(where: { $0.id == key }) {
                sections.append(HomeSectionView(id: "module-\(key)", sortOrder: module.sortOrder + 1,
                    sourceOrder: sourceOrder, content: AnyView(NativeHomeCatalogSection(store: store, module: module,
                        rows: moduleRows[module.id], error: moduleErrors[module.id], onRetry: { revision += 1 }))))
            }
            sourceOrder += 1
        }

        return sections.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.sourceOrder < $1.sourceOrder
        }
    }

    private var featuredSection: some View {
        NativeHomeFeaturedSection(store: store, title: featuredTitle, rows: featured,
                                  onBrowse: onBrowse, onOpen: openRecommendation)
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

    private func load(forceRefresh: Bool = false, allowStale: Bool = false) async {
        let hasVisibleContent = !components.isEmpty
        loading = !hasVisibleContent
        error = nil
        if !allowStale { nextComponentChangeDelayMs = nil }
        var nextChangeDeadline: Date?
        do {
            let api = MobileAPI(store: store)
            let value = try await api.getPublicCached("/api/JHCTIHomePage/GetPublicHome", forceRefresh: forceRefresh,
                                                      allowStale: allowStale) as? [String: Any]
            if !allowStale, let delay = (value?["NextComponentChangeAfterMilliseconds"] as? NSNumber
                ?? value?["nextComponentChangeAfterMilliseconds"] as? NSNumber)?.int64Value,
               delay > 0 { nextChangeDeadline = Date().addingTimeInterval(Double(delay) / 1000) }
            let componentRows = value?["Components"] as? [[String: Any]] ?? value?["components"] as? [[String: Any]] ?? []
            components = componentRows.map { canonicalHomeComponent($0) as? [String: Any] ?? $0 }
            let configuredQuickEntries = components.filter {
                ($0["ComponentType"] as? String ?? $0["componentType"] as? String ?? "").lowercased() == "quickentry"
                    && ($0["IsEnabled"] as? Bool ?? $0["isEnabled"] as? Bool ?? true)
            }.sorted {
                ($0["SortOrder"] as? Int ?? $0["sortOrder"] as? Int ?? 0)
                    < ($1["SortOrder"] as? Int ?? $1["sortOrder"] as? Int ?? 0)
            }
            var availableQuickEntries: [[String: Any]] = []
            for entry in configuredQuickEntries {
                if availableQuickEntries.count >= 8 { break }
                guard isValidHomeQuickEntryTarget(entry) else { continue }
                let targetType = (entry["TargetType"] as? String ?? entry["targetType"] as? String ?? "").lowercased()
                let pageKey = (entry["InternalPageKey"] as? String ?? entry["internalPageKey"] as? String ?? "").lowercased()
                let title = entry["Title"] as? String ?? entry["title"] as? String ?? ""
                let targetPath = entry["TargetPath"] as? String ?? entry["targetPath"] as? String ?? ""
                let featureID = homeModuleIdForTarget(targetType, pageKey, title, targetPath)
                let featureOpen = featureID.isEmpty ? true : await api.featureEnabled(featureID,
                    allowStale: allowStale, forceRefresh: forceRefresh)
                guard !Task.isCancelled else { loading = false; return }
                if featureOpen { availableQuickEntries.append(entry) }
            }
            quickEntryItems = availableQuickEntries
            let hasConfiguredQuickEntries = components.contains {
                ($0["ComponentType"] as? String ?? $0["componentType"] as? String ?? "").lowercased() == "quickentry"
            }
            let fallbackShortcutFeatures = [
                "F-TKT-002", "MODULE-SCENIC", "MODULE-DINING", "MODULE-HOTEL",
                "MODULE-ACTIVITY", "MODULE-GUIDE", "MODULE-GUIDE", "MODULE-TRAVEL-ROUTE"
            ]
            var visibleFallbackShortcuts: [Int] = []
            if !hasConfiguredQuickEntries {
                for (index, featureID) in fallbackShortcutFeatures.enumerated() {
                    let featureOpen = await api.featureEnabled(featureID, allowStale: allowStale, forceRefresh: forceRefresh)
                    guard !Task.isCancelled else { loading = false; return }
                    if featureOpen {
                        visibleFallbackShortcuts.append(index)
                    }
                }
            }
            fallbackShortcutIndices = visibleFallbackShortcuts
            var visibleOperations: [[String: Any]] = []
            for item in components {
                let componentType = (item["ComponentType"] as? String ?? item["componentType"] as? String ?? "").lowercased()
                guard ["servicestatus", "noticebar", "promobanner"].contains(componentType),
                      item["IsEnabled"] as? Bool ?? item["isEnabled"] as? Bool ?? true else { continue }
                let targetType = (item["TargetType"] as? String ?? item["targetType"] as? String ?? "").lowercased()
                let pageKey = (item["InternalPageKey"] as? String ?? item["internalPageKey"] as? String ?? "").lowercased()
                let title = item["Title"] as? String ?? item["title"] as? String ?? ""
                let targetPath = item["TargetPath"] as? String ?? item["targetPath"] as? String ?? ""
                let featureID = homeModuleIdForTarget(targetType, pageKey, title, targetPath)
                let targetOpen = featureID.isEmpty ? true : await api.featureEnabled(featureID,
                    allowStale: allowStale, forceRefresh: forceRefresh)
                guard !Task.isCancelled else { loading = false; return }
                if targetOpen { visibleOperations.append(item) }
            }
            operationComponents = visibleOperations.enumerated().sorted { left, right in
                let leftOrder = left.element["SortOrder"] as? Int ?? left.element["sortOrder"] as? Int ?? 0
                let rightOrder = right.element["SortOrder"] as? Int ?? right.element["sortOrder"] as? Int ?? 0
                return leftOrder == rightOrder ? left.offset < right.offset : leftOrder < rightOrder
            }.map(\.element)
            quickEntriesConfigured = hasConfiguredQuickEntries
            let rawModules = value?["AppModules"] as? [[String: Any]] ?? value?["appModules"] as? [[String: Any]] ?? [
                ["Key": "featured", "Title": "精选推荐", "IsEnabled": true, "SortOrder": 0],
                ["Key": "activities", "Title": "最新活动", "IsEnabled": true, "SortOrder": 1]
            ]
            let moduleKeyCounts = Dictionary(grouping: rawModules.compactMap { row in
                (row["Key"] as? String ?? row["key"] as? String)?.lowercased()
            }, by: { $0 }).mapValues(\.count)
            let uniqueModules = rawModules.filter { row in
                guard let key = row["Key"] as? String ?? row["key"] as? String else { return false }
                return moduleKeyCounts[key.lowercased()] == 1
            }
            let candidates = uniqueModules.compactMap(CatalogModule.init).sorted { $0.sortOrder < $1.sortOrder }
            var enabled: [CatalogModule] = []
            var published: [String: [[String: Any]]] = [:]
            var catalogErrors: [String: String] = [:]
            for module in candidates {
                let featureEnabled = module.featureID.isEmpty ? true : await api.featureEnabled(module.featureID,
                    allowStale: allowStale, forceRefresh: forceRefresh)
                guard !Task.isCancelled else { loading = false; return }
                guard featureEnabled else { continue }
                enabled.append(module)
                let pageSize = min(4, module.displayCount)
                do {
                    guard let page = try await api.getPublicCached(module.listPath(pageSize: pageSize),
                        forceRefresh: forceRefresh, allowStale: allowStale) as? [String: Any] else {
                        if module.id == "articles" { catalogErrors[module.id] = "首页文旅资讯分页回执异常，请刷新后重试。" }
                        continue
                    }
                    if module.id == "articles" {
                        guard let parsed = nativePublicCatalogPage(page, page: 1, pageSize: pageSize) else {
                            catalogErrors[module.id] = "首页文旅资讯分页回执异常，请刷新后重试。"
                            continue
                        }
                        guard nativePublicArticleRows(parsed.rows) else {
                            catalogErrors[module.id] = "首页文旅资讯编号无效或重复，请重试。"
                            continue
                        }
                        published[module.id] = parsed.rows
                    } else {
                        published[module.id] = page["data"] as? [[String: Any]] ?? page["Data"] as? [[String: Any]] ?? page["Items"] as? [[String: Any]] ?? []
                    }
                } catch is CancellationError {
                    loading = false
                    return
                } catch {
                    if module.id == "articles" { catalogErrors[module.id] = "首页文旅资讯暂时无法加载，请重试。" }
                }
            }
            catalogs = enabled
            moduleRows = published
            moduleErrors = catalogErrors
            let featuredModule = uniqueModules.first {
                ($0["Key"] as? String ?? $0["key"] as? String) == "featured"
                    && ($0["IsEnabled"] as? Bool ?? $0["isEnabled"] as? Bool ?? false)
            }
            featuredSortOrder = featuredModule?["SortOrder"] as? Int ?? featuredModule?["sortOrder"] as? Int ?? 0
            configuredOrder = uniqueModules.enumerated().filter {
                $0.element["IsEnabled"] as? Bool ?? $0.element["isEnabled"] as? Bool ?? false
            }
                .sorted { left, right in
                    let leftOrder = left.element["SortOrder"] as? Int ?? left.element["sortOrder"] as? Int ?? 0
                    let rightOrder = right.element["SortOrder"] as? Int ?? right.element["sortOrder"] as? Int ?? 0
                    return leftOrder == rightOrder ? left.offset < right.offset : leftOrder < rightOrder
                }
                .compactMap { $0.element["Key"] as? String ?? $0.element["key"] as? String }
                .filter { key in key == "featured" || enabled.contains(where: { $0.id == key }) }
            featuredTitle = (featuredModule?["Title"] as? String ?? featuredModule?["title"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 } ?? "精选推荐"
            let scenicEnabled = await api.featureEnabled("MODULE-SCENIC", allowStale: allowStale, forceRefresh: forceRefresh)
            guard !Task.isCancelled else { loading = false; return }
            let excludedRecommendationTypes = Set(["banner", "quickentry", "servicestatus", "noticebar", "promobanner"])
            let configuredRecommendations = components.filter { item in
                let type = (item["ComponentType"] as? String ?? item["componentType"] as? String ?? "").lowercased()
                let enabled = item["IsEnabled"] as? Bool ?? item["isEnabled"] as? Bool ?? true
                return !type.isEmpty && !excludedRecommendationTypes.contains(type) && enabled
            }
            var visibleRecommendations: [[String: Any]] = []
            for item in configuredRecommendations {
                guard let typeValue = homeRecommendationTargetType(item) else { continue }
                let type = typeValue.lowercased()
                guard ["internalpage", "scenicspot", "ticket", "article", "activity", "product", "hotel", "travelroute", "diningstore"].contains(type) else { continue }
                if type == "internalpage" {
                    guard homeRecommendationInternalPageKey(item) != nil else { continue }
                } else {
                    guard isValidHomeRecommendationTargetID(homeRecommendationTargetID(item)) else { continue }
                }
                let pageKey = (item["InternalPageKey"] as? String ?? item["internalPageKey"] as? String ?? "").lowercased()
                let title = item["Title"] as? String ?? item["title"] as? String ?? ""
                let targetPath = item["TargetPath"] as? String ?? item["targetPath"] as? String ?? ""
                let featureID = homeModuleIdForTarget(type, pageKey, title, targetPath)
                let targetModuleOpen = featureID.isEmpty ? true : await api.featureEnabled(
                    featureID, allowStale: allowStale, forceRefresh: forceRefresh)
                guard !Task.isCancelled else { loading = false; return }
                if targetModuleOpen {
                    visibleRecommendations.append(item)
                }
            }
            if !visibleRecommendations.isEmpty {
                featured = visibleRecommendations
            } else if featuredModule != nil && scenicEnabled {
                let response: [String: Any]?
                do {
                    response = try await api.getPublicCached("/api/JHCTITourismResource/GetPublicPage?page=1&pageSize=8",
                        forceRefresh: forceRefresh, allowStale: allowStale) as? [String: Any]
                } catch is CancellationError {
                    loading = false
                    return
                } catch {
                    response = nil
                }
                featured = response?["data"] as? [[String: Any]] ?? response?["Data"] as? [[String: Any]] ?? []
            } else { featured = [] }
        } catch is CancellationError {
            loading = false
            return
        } catch {
            if !hasVisibleContent { self.error = error.localizedDescription }
        }
        guard !Task.isCancelled else { loading = false; return }
        if !allowStale {
            nextComponentChangeDelayMs = nextChangeDeadline.map {
                max(1, Int64(($0.timeIntervalSinceNow * 1000).rounded(.up)))
            }
        }
        loading = false
        if !initialLoadCompleted {
            initialLoadCompleted = true
            onInitialLoadComplete()
        }
    }
}
