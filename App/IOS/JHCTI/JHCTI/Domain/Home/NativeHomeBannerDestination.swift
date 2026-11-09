import Foundation

struct NativeHomeBannerDestination {
    let path: String
    let id: String?
    let siteID: String
    let guideRouteID: String?

    init?(rawPath: String) {
        guard let target = normalizeHomeBannerTargetPath(rawPath),
              target.hasPrefix("/"), !target.hasPrefix("//"),
              !target.contains("\\"), !target.contains(".."),
              let components = URLComponents(string: "https://jhcti.invalid\(target)"),
              components.host == "jhcti.invalid", components.scheme == "https" else { return nil }

        let articleTarget = components.path == "/subpackages/tourism/article/index"
        let detailTargets: Set<String> = [
            "/subpackages/activities/activity/index", "/subpackages/tourism/article/index",
            "/subpackages/commerce/product/index", "/subpackages/tourism/hotel/index",
            "/subpackages/dining/restaurant/index", "/subpackages/tourism/route/index",
            "/subpackages/tourism/resource/index", "/subpackages/tourism/facility/index"
        ]
        let guideTarget = components.path == "/subpackages/tourism/resource/index"
        let allowedQueryNames = articleTarget ? Set(["id", "siteid"])
            : guideTarget ? Set(["id", "guideRouteId"])
            : detailTargets.contains(components.path) ? Set(["id"]) : []
        let queryItems = components.queryItems ?? []
        guard queryItems.allSatisfy({ allowedQueryNames.contains($0.name) }) else { return nil }

        let idValues = queryItems.filter { $0.name == "id" }.compactMap(\.value)
        let targetID = idValues.count == 1 ? idValues.first : nil
        let validTargetID = targetID.flatMap { value -> String? in
            guard isValidHomeRecommendationTargetID(value) else { return nil }
            return value
        }

        let siteItems = queryItems.filter { $0.name == "siteid" }
        guard !articleTarget || (siteItems.count <= 1 && siteItems.allSatisfy { item in
            item.value.map { isValidHomeRecommendationTargetID($0) } == true
        }) else { return nil }

        let guideRouteItems = queryItems.filter { $0.name == "guideRouteId" }
        guard guideTarget ? (guideRouteItems.count <= 1 && guideRouteItems.allSatisfy { item in
            item.value.map { isValidHomeRecommendationTargetID($0) } == true
        }) : guideRouteItems.isEmpty else { return nil }

        path = components.path
        id = validTargetID
        siteID = siteItems.first?.value ?? "1"
        guideRouteID = guideRouteItems.first?.value
    }
}
