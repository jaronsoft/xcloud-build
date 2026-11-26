import Foundation

enum NativeHomeQuickEntryPresentation {
    private static let defaultTitles = [
        "景区门票", "文旅地图", "特色美食", "酒店民宿",
        "促销活动", "非遗文化", "旅游攻略", "旅游线路"
    ]

    private static let internalPageTitles = [
        "map": "文旅地图", "discover": "发现", "attractions": "文旅地图", "tourism-map": "文旅地图",
        "activities": "近期活动", "activity": "近期活动", "tickets": "景区门票",
        "products": "文旅好物", "shop": "文旅好物", "hotels": "酒店民宿",
        "routes": "旅游线路", "travel-routes": "旅游线路", "dining": "特色美食",
        "restaurants": "特色美食", "food": "特色美食", "guide": "旅游攻略",
        "articles": "文旅资讯", "intangible-heritage": "非遗文化",
        "group-buy": "团购优惠", "flash-sale": "限时优惠", "coupon-center": "优惠券中心", "profile": "个人中心"
    ]

    private static let targetTitles = [
        "scenicspot": "景点详情", "ticket": "景区门票", "activity": "近期活动",
        "product": "文旅好物", "hotel": "酒店民宿", "travelroute": "旅游线路",
        "diningstore": "特色美食", "article": "文旅资讯"
    ]

    private static let pathTitles = [
        "/map": "文旅地图", "/discover": "发现", "/attractions": "文旅地图", "/tickets": "景区门票",
        "/activities": "近期活动", "/products": "文旅好物", "/shop": "文旅好物",
        "/hotels": "酒店民宿", "/routes": "旅游线路", "/travel-routes": "旅游线路",
        "/dining": "特色美食", "/restaurants": "特色美食", "/food": "特色美食",
        "/articles": "文旅资讯", "/guide": "旅游攻略", "/intangible-heritage": "非遗文化",
        "/group-buy": "团购优惠", "/flash-sale": "限时优惠", "/coupon-center": "优惠券中心",
        "/profile": "个人中心"
    ]

    private static let internalPageIconIndexes = [
        "map": 1, "discover": 1, "attractions": 1, "tourism-map": 1,
        "activities": 4, "activity": 4, "tickets": 0,
        "products": 0, "shop": 0, "hotels": 3,
        "routes": 7, "travel-routes": 7, "dining": 2,
        "restaurants": 2, "food": 2, "guide": 6,
        "articles": 6, "intangible-heritage": 5,
        "group-buy": 4, "flash-sale": 4, "coupon-center": 4
    ]

    private static let targetIconIndexes = [
        "scenicspot": 1, "ticket": 0, "activity": 4, "product": 0,
        "hotel": 3, "travelroute": 7, "diningstore": 2, "article": 6
    ]

    private static let pathIconIndexes = [
        "/map": 1, "/discover": 1, "/attractions": 1, "/tickets": 0, "/activities": 4,
        "/products": 0, "/shop": 0, "/hotels": 3, "/routes": 7,
        "/travel-routes": 7, "/dining": 2, "/restaurants": 2, "/food": 2,
        "/articles": 6, "/guide": 6, "/intangible-heritage": 5,
        "/group-buy": 4, "/flash-sale": 4, "/coupon-center": 4
    ]

    static func fallbackTitle(for entry: [String: Any]?, index: Int) -> String {
        guard let entry else { return defaultTitle(at: index) }
        let key = normalizedField(entry, "InternalPageKey", "internalPageKey")
        if let title = internalPageTitles[key] { return title }
        let type = normalizedField(entry, "TargetType", "targetType")
        if let title = targetTitles[type] { return title }
        return pathTitle(for: entry) ?? defaultTitle(at: index)
    }

    static func iconIndex(for entry: [String: Any]?, fallback: Int) -> Int {
        guard let entry else { return fallback }
        let key = normalizedField(entry, "InternalPageKey", "internalPageKey")
        let title = (entry["Title"] as? String ?? entry["title"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if key == "articles", title == "非遗文化" { return 5 }
        if let index = internalPageIconIndexes[key] { return index }
        let type = normalizedField(entry, "TargetType", "targetType")
        if let index = targetIconIndexes[type] { return index }
        return pathValue(for: entry, values: pathIconIndexes) ?? fallback
    }

    private static func defaultTitle(at index: Int) -> String {
        defaultTitles.indices.contains(index) ? defaultTitles[index] : "文旅服务"
    }

    private static func normalizedField(_ entry: [String: Any], _ upper: String, _ lower: String) -> String {
        (entry[upper] as? String ?? entry[lower] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func targetPath(for entry: [String: Any]?) -> String? {
        guard let entry else { return nil }
        let raw = (entry["TargetPath"] as? String ?? entry["targetPath"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("/"), !raw.hasPrefix("//") else { return nil }
        let path = raw.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? raw
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
            ? "/" : "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    private static func pathValue(for entry: [String: Any]?, values: [String: Int]) -> Int? {
        guard let path = targetPath(for: entry) else { return nil }
        if let index = values[path] { return index }
        let segments = path.split(separator: "/").map(String.init)
        guard let first = segments.first else { return nil }
        if first == "attractions", segments.count == 2 { return 1 }
        if first == "attractions", segments.last == "tickets" { return 0 }
        if first == "attractions", segments.last == "guide" { return 6 }
        return values["/\(first)"]
    }

    private static func pathTitle(for entry: [String: Any]?) -> String? {
        guard let path = targetPath(for: entry) else { return nil }
        if let title = pathTitles[path] { return title }
        let segments = path.split(separator: "/").map(String.init)
        guard let first = segments.first else { return nil }
        if first == "attractions", segments.count == 2 { return "景点详情" }
        if first == "attractions", segments.last == "tickets" { return "景区门票" }
        if first == "attractions", segments.last == "guide" { return "旅游攻略" }
        return pathTitles["/\(first)"]
    }
}
