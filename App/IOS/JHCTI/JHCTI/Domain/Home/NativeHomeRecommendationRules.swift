import Foundation

// 首页组件兼容小写开头字段，并保留原字段以沿用既有主视觉和快捷入口读取方式。
func canonicalHomeComponent(_ value: Any) -> Any {
    if let fields = value as? [String: Any] {
        var result = fields.mapValues { canonicalHomeComponent($0) }
        for key in fields.keys where key.first?.isLowercase == true {
            let canonical = String(key.prefix(1)).uppercased() + String(key.dropFirst())
            if result[canonical] == nil { result[canonical] = result[key] }
        }
        return result
    }
    if let values = value as? [Any] { return values.map(canonicalHomeComponent) }
    return value
}

func homeAdmissionPresentation(_ item: [String: Any]) -> (label: String, isFree: Bool, isUnknown: Bool)? {
    guard homeRecommendationTargetType(item)?
        .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "scenicspot" else { return nil }

    let hasUpperAdmission = item["AdmissionType"] != nil
    let hasLowerAdmission = item["admissionType"] != nil
    let upperAdmission = item["AdmissionType"] as? String
    let lowerAdmission = item["admissionType"] as? String
    if (hasUpperAdmission && upperAdmission == nil) || (hasLowerAdmission && lowerAdmission == nil) { return nil }
    if hasUpperAdmission && hasLowerAdmission && upperAdmission != lowerAdmission { return nil }
    guard let admission = (upperAdmission ?? lowerAdmission)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !admission.isEmpty else { return nil }
    switch admission {
    case "Free": return ("免费", true, false)
    case "Paid": return ("收费", false, false)
    case "FreeReservation": return ("预约·免费", true, false)
    case "PaidReservation": return ("预约·收费", false, false)
    default: return ("入园方式待确认", false, true)
    }
}

func consistentHomeStringField(_ item: [String: Any], upperKey: String, lowerKey: String) -> (isValid: Bool, value: String?) {
    let hasUpper = item[upperKey] != nil
    let hasLower = item[lowerKey] != nil
    let upper = item[upperKey] as? String
    let lower = item[lowerKey] as? String
    guard (!hasUpper || upper != nil), (!hasLower || lower != nil),
          !(hasUpper && hasLower && upper != lower) else { return (false, nil) }
    return (true, upper ?? lower)
}

private let homeRecommendationInternalPageKeys: Set<String> = [
    "attractions", "tickets", "activities", "shop", "hotels", "routes", "guide", "profile",
    "coupon-center", "dining", "group-buy", "flash-sale", "articles", "intangible-heritage", "tourism-map"
]

func homeRecommendationInternalPageKey(_ item: [String: Any]) -> String? {
    let field = consistentHomeStringField(item, upperKey: "InternalPageKey", lowerKey: "internalPageKey")
    guard field.isValid, let value = field.value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          homeRecommendationInternalPageKeys.contains(value) else { return nil }
    return value
}

func isValidHomeQuickEntryTarget(_ item: [String: Any]) -> Bool {
    let target = consistentHomeStringField(item, upperKey: "TargetType", lowerKey: "targetType")
    let legacy = consistentHomeStringField(item, upperKey: "Type", lowerKey: "type")
    let page = consistentNullableHomeStringField(item, upperKey: "InternalPageKey", lowerKey: "internalPageKey")
    let targetID = consistentNullableHomeStringField(item, upperKey: "TargetId", lowerKey: "targetId")
    guard target.isValid, legacy.isValid, page.isValid, targetID.isValid else { return false }
    if let targetType = target.value, let legacyType = legacy.value,
       targetType.trimmingCharacters(in: .whitespacesAndNewlines)
        .caseInsensitiveCompare(legacyType.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame { return false }

    let type = (target.value ?? legacy.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let key = page.value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let id = targetID.value?.trimmingCharacters(in: .whitespacesAndNewlines)
    let detailTypes: Set<String> = ["scenicspot", "ticket", "article", "activity", "product", "hotel", "travelroute", "diningstore"]
    guard type.isEmpty || type == "internalpage" || detailTypes.contains(type) else { return false }
    if !key.isEmpty && !homeRecommendationInternalPageKeys.contains(key) { return false }
    if !key.isEmpty && !type.isEmpty && type != "internalpage" { return false }
    // CMS 用字符串 "0" 表示内部页没有关联内容 ID；真实雪花 ID 仍不允许作为内部页目标。
    let hasNoInternalTargetID = id == nil || id == "0"
    if type == "internalpage" && (key.isEmpty || !hasNoInternalTargetID) { return false }
    if type.isEmpty && (key.isEmpty || id != nil) { return false }
    if detailTypes.contains(type) && !(id.map { isValidHomeRecommendationTargetID($0) } ?? false) { return false }
    return true
}

private func consistentNullableHomeStringField(
    _ item: [String: Any],
    upperKey: String,
    lowerKey: String
) -> (isValid: Bool, value: String?) {
    let hasUpper = item.keys.contains(upperKey)
    let hasLower = item.keys.contains(lowerKey)
    let upperRaw = item[upperKey]
    let lowerRaw = item[lowerKey]
    let upper = upperRaw is NSNull ? nil : upperRaw as? String
    let lower = lowerRaw is NSNull ? nil : lowerRaw as? String
    guard (!hasUpper || upperRaw is NSNull || upper != nil),
          (!hasLower || lowerRaw is NSNull || lower != nil),
          !(hasUpper && hasLower && upper != lower) else { return (false, nil) }
    return (true, upper ?? lower)
}

func homeRecommendationTargetType(_ item: [String: Any]) -> String? {
    let target = consistentHomeStringField(item, upperKey: "TargetType", lowerKey: "targetType")
    let legacy = consistentHomeStringField(item, upperKey: "Type", lowerKey: "type")
    let resource = consistentHomeStringField(item, upperKey: "ResourceType", lowerKey: "resourceType")
    guard target.isValid, legacy.isValid, resource.isValid else { return nil }
    if let targetType = target.value, let legacyType = legacy.value,
       targetType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        != legacyType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() { return nil }
    let value = (target.value ?? legacy.value ?? resource.value)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return value?.isEmpty == false ? value : nil
}

func homeRecommendationTargetID(_ item: [String: Any]) -> String? {
    let target = consistentHomeStringField(item, upperKey: "TargetId", lowerKey: "targetId")
    let resource = consistentHomeStringField(item, upperKey: "ResourceType", lowerKey: "resourceType")
    guard target.isValid, resource.isValid else { return nil }
    if let targetID = target.value { return targetID }
    let hasConfiguredTargetType = ["TargetType", "targetType", "Type", "type"].contains { item[$0] != nil }
    let hasPublicResourceType = resource.value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    guard !hasConfiguredTargetType, hasPublicResourceType else { return nil }
    let legacy = consistentHomeStringField(item, upperKey: "Id", lowerKey: "id")
    return legacy.isValid ? legacy.value : nil
}

func isValidHomeRecommendationTargetID(_ value: String?) -> Bool {
    guard let value, value.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
          Int64(value).map({ $0 > 0 }) == true else { return false }
    return true
}

func normalizeHomeBannerTargetPath(_ value: String) -> String? {
    guard value.count <= 2048, !value.contains("\\"), !value.contains("#"),
          !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
          value.hasPrefix("/"), !value.hasPrefix("//"),
          let components = URLComponents(string: "https://jhcti.invalid\(value)"),
          components.scheme == "https", components.host == "jhcti.invalid",
          !components.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
    let pageAliases: [String: String] = [
        "/map": "/pages/map/index", "/discover": "/pages/discover/index",
        "/attractions": "/pages/map/index", "/tickets": "/pages/map/index",
        "/activities": "/subpackages/activities/activities/index",
        "/articles": "/subpackages/tourism/articles/index",
        "/intangible-heritage": "/subpackages/tourism/intangible-heritage/index",
        "/products": "/subpackages/commerce/products/index",
        "/hotels": "/subpackages/tourism/hotels/index",
        "/restaurants": "/subpackages/dining/restaurants/index", "/dining": "/subpackages/dining/restaurants/index",
        "/routes": "/subpackages/tourism/routes/index", "/travel-routes": "/subpackages/tourism/routes/index",
        "/profile": "/pages/profile/index"
    ]
    if let route = pageAliases[components.path] {
        return components.queryItems?.isEmpty == false ? nil : route
    }

    if let range = components.path.range(of: "^/attractions/([1-9][0-9]{0,18})/guide$", options: .regularExpression) {
        let matched = String(components.path[range])
        guard let resourceRange = matched.range(of: "[1-9][0-9]{0,18}(?=/guide$)", options: .regularExpression) else { return nil }
        let resourceID = String(matched[resourceRange])
        let queryItems = components.queryItems ?? []
        let routeItems = queryItems.filter { $0.name == "routeId" }
        guard isValidHomeRecommendationTargetID(resourceID),
              queryItems.allSatisfy({ $0.name == "routeId" }), routeItems.count == 1,
              let routeID = routeItems.first?.value, isValidHomeRecommendationTargetID(routeID) else { return nil }
        return "/subpackages/tourism/resource/index?id=\(resourceID)&guideRouteId=\(routeID)"
    }

    let details: [(String, String)] = [
        ("^/attractions/([1-9][0-9]{0,18})$", "/subpackages/tourism/resource/index"),
        ("^/activities/([1-9][0-9]{0,18})$", "/subpackages/activities/activity/index"),
        ("^/products/([1-9][0-9]{0,18})$", "/subpackages/commerce/product/index"),
        ("^/hotels/([1-9][0-9]{0,18})$", "/subpackages/tourism/hotel/index"),
        ("^/(?:restaurants|dining)/([1-9][0-9]{0,18})$", "/subpackages/dining/restaurant/index"),
        ("^/travel-routes/([1-9][0-9]{0,18})$", "/subpackages/tourism/route/index"),
        ("^/articles/([1-9][0-9]{0,18})$", "/subpackages/tourism/article/index")
    ]
    for (pattern, route) in details {
        guard let range = components.path.range(of: pattern, options: .regularExpression) else { continue }
        let matched = String(components.path[range])
        guard let idRange = matched.range(of: "[1-9][0-9]{0,18}$", options: .regularExpression) else { return nil }
        let id = String(matched[idRange])
        guard isValidHomeRecommendationTargetID(id) else { return nil }
        let isArticle = route == "/subpackages/tourism/article/index"
        let queryItems = components.queryItems ?? []
        guard isArticle ? queryItems.allSatisfy({ $0.name == "siteid" }) : queryItems.isEmpty else { return nil }
        let siteItems = queryItems.filter { $0.name == "siteid" }
        guard siteItems.count <= 1,
              siteItems.allSatisfy({ item in item.value.map { isValidHomeRecommendationTargetID($0) } ?? false }) else { return nil }
        return "\(route)?id=\(id)" + (isArticle ? "&siteid=\(siteItems.first?.value ?? "1")" : "")
    }
    return value
}

// 内部页键决定实际导航目标，不能被兼容标题改写成其他业务模块。
func homeModuleIdForTarget(_ targetType: String, _ pageKey: String, _ title: String, _ targetPath: String = "") -> String {
    let type = targetType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let key = pageKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let path = targetPath.split(separator: "?", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
    if key == "tickets" || path.range(of: "^/(tickets|subpackages/(ticket-booking|ticketing/ticket-booking))(/|$)", options: .regularExpression) != nil
        || path.range(of: "^/attractions/[1-9][0-9]{0,18}/tickets$", options: .regularExpression) != nil {
        return "F-TKT-002"
    }
    switch type {
    case "scenicspot": return "MODULE-SCENIC"
    case "ticket": return "F-TKT-002"
    case "article", "guideroute": return "MODULE-GUIDE"
    case "activity": return "MODULE-ACTIVITY"
    case "product": return "MODULE-PRODUCT"
    case "hotel": return "MODULE-HOTEL"
    case "travelroute": return "MODULE-TRAVEL-ROUTE"
    case "diningstore": return "MODULE-DINING"
    default: break
    }
    if type == "internalpage" || (type.isEmpty && !key.isEmpty) {
        switch key {
        case "tickets": return "F-TKT-002"
        case "attractions", "tourism-map": return "MODULE-SCENIC"
        case "activity", "activities": return "MODULE-ACTIVITY"
        case "shop", "products", "flash-sale": return "MODULE-PRODUCT"
        case "hotels": return "MODULE-HOTEL"
        case "dining", "restaurants", "food", "group-buy": return "MODULE-DINING"
        case "routes": return "MODULE-TRAVEL-ROUTE"
        case "guide", "articles", "intangible-heritage": return "MODULE-GUIDE"
        default: return ""
        }
    }
    if title.trimmingCharacters(in: .whitespacesAndNewlines) == "景区门票" { return "F-TKT-002" }
    if title.range(of: "景区|门票|地图", options: .regularExpression) != nil { return "MODULE-SCENIC" }
    if title.contains("活动") { return "MODULE-ACTIVITY" }
    if title.range(of: "好物|商品", options: .regularExpression) != nil { return "MODULE-PRODUCT" }
    if title.range(of: "酒店|住宿", options: .regularExpression) != nil { return "MODULE-HOTEL" }
    if title.range(of: "美食|餐饮", options: .regularExpression) != nil { return "MODULE-DINING" }
    if title.contains("线路") { return "MODULE-TRAVEL-ROUTE" }
    if title.range(of: "攻略|非遗|资讯", options: .regularExpression) != nil { return "MODULE-GUIDE" }
    return ""
}
