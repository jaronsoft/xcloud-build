import Foundation

struct AISIOSCapabilities: Codable, Sendable, Equatable {
    let enabled: Bool
    let minimumVersion: String
    let allowedRegions: [String]
    let loginMethods: [String]
    let storeKitEnabled: Bool
    let videoEnabled: Bool
    let publicContentEnabled: Bool
    let pushNotificationsEnabled: Bool
    let rulesVersion: String

    static let safeDefault = AISIOSCapabilities(
        enabled: true,
        minimumVersion: "1.0",
        allowedRegions: ["US"],
        loginMethods: ["apple", "email"],
        storeKitEnabled: false,
        videoEnabled: false,
        publicContentEnabled: false,
        pushNotificationsEnabled: false,
        rulesVersion: "fallback"
    )

    func allows(region: String?) -> Bool {
        guard let region = region?.uppercased(), !region.isEmpty else {
            return false
        }
        return allowedRegions.contains {
            $0.caseInsensitiveCompare(region) == .orderedSame
        }
    }
}

private struct AISCapabilitiesResponse: Decodable {
    let ios: AISIOSCapabilities
}

actor AISCapabilitiesStore {
    static let shared = AISCapabilitiesStore()

    private(set) var ios = AISIOSCapabilities.safeDefault
    private let cacheKey = AISResponseCache.key(
        scope: "public",
        resource: "ios-capabilities-ais"
    )

    func load() async {
        if let cached = await AISResponseCache.shared.read(
            AISIOSCapabilities.self,
            key: cacheKey,
            ttl: 3600,
            allowsStale: true
        ) {
            ios = cached.value
            if cached.isFresh { return }
        }

        do {
            let response: AISCapabilitiesResponse = try await APIClient().get(
                "/api/ais/capabilities",
                query: [URLQueryItem(name: "appCode", value: "ais")]
            )
            ios = response.ios
            await AISResponseCache.shared.write(response.ios, key: cacheKey)
        } catch {
            // 公共配置不可用时采用最小安全能力集，避免误开放支付和公开内容。
        }
    }
}
