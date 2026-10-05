import Foundation

extension Notification.Name {
    static let pixaImageDeliveryDidChange = Notification.Name("PixaImageDeliveryDidChange")
}

struct PixaImagePreset: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    static let original = PixaImagePreset(rawValue: "original")
    static let list = PixaImagePreset(rawValue: "list")
    static let largeList = PixaImagePreset(rawValue: "largeList")
    static let detail = PixaImagePreset(rawValue: "detail")
    static let thumbnail = PixaImagePreset(rawValue: "thumbnail")
}

enum PixaImageResourceKind: String, Codable, Sendable {
    case thumbnail
    case detail
    case original
}

struct PixaResolvedImageRequest: Equatable, Sendable {
    let url: URL
    let requestedPreset: PixaImagePreset
    let appliedPreset: PixaImagePreset
    let pixelWidth: Int?
    let resourceKind: PixaImageResourceKind
    let transformed: Bool
}

struct PixaImageDeliveryPresets: Codable, Sendable {
    let ios: [String: String]
}

struct PixaImageDeliveryConfiguration: Codable, Sendable {
    let enabled: Bool
    let provider: String
    let mode: String
    let region: String
    let rulesVersion: String
    let cacheSeconds: Int
    let domains: [String]
    let deliveryBaseUrl: String?
    let presets: PixaImageDeliveryPresets

    private static let cloudflarePresets: Set<String> = [
        "w200", "w400", "w600", "w800", "w900", "detail1200", "square600", "original"
    ]

    var usesCloudflarePresetQuery: Bool {
        provider.caseInsensitiveCompare("cloudflare") == .orderedSame && mode == "presetQuery"
    }

    var normalizedDeliveryBaseURL: URL? {
        guard usesCloudflarePresetQuery,
              let deliveryBaseUrl,
              let url = URL(string: deliveryBaseUrl),
              url.scheme?.lowercased() == "https",
              url.path.isEmpty || url.path == "/",
              url.query == nil,
              url.fragment == nil else { return nil }
        return url
    }

    func rule(for preset: PixaImagePreset, host: String) -> String? {
        guard enabled,
              domains.contains(where: { $0.caseInsensitiveCompare(host) == .orderedSame }),
              let rawRule = presets.ios[preset.rawValue] else { return nil }
        let rule = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let supported = usesCloudflarePresetQuery
            ? Self.cloudflarePresets.contains(rule)
            : rule.hasPrefix("imageMogr2/") || rule.hasPrefix("imageView2/")
        guard supported, !rule.contains(where: { "?&#\r\n".contains($0) }) else { return nil }
        return rule
    }

    func adaptiveRule(targetPixelWidth: Int, maximumPixelWidth: Int, host: String)
        -> (preset: PixaImagePreset, rule: String, pixelWidth: Int)? {
        let maximum = max(1, maximumPixelWidth)
        let target = min(maximum, max(1, targetPixelWidth))
        let candidates = presets.ios.compactMap { key, _ -> (PixaImagePreset, String, Int)? in
            let preset = PixaImagePreset(rawValue: key)
            guard let rule = rule(for: preset, host: host),
                  let width = Self.pixelWidth(in: rule),
                  width <= maximum else { return nil }
            return (preset, rule, width)
        }.sorted { $0.2 < $1.2 }
        return candidates.first(where: { $0.2 >= target }) ?? candidates.last
    }

    static func pixelWidth(in rule: String) -> Int? {
        if rule == "detail1200" { return 1_200 }
        if rule.hasPrefix("w"), let width = Int(rule.dropFirst()), width > 0 { return width }
        guard let expression = try? NSRegularExpression(pattern: #"imageMogr2/thumbnail/(\d+)x"#),
              let match = expression.firstMatch(in: rule, range: NSRange(rule.startIndex..., in: rule)),
              let range = Range(match.range(at: 1), in: rule) else { return nil }
        return Int(rule[range])
    }
}

private struct PixaCapabilities: Decodable {
    let imageDelivery: PixaImageDeliveryConfiguration?
}

final class PixaImageDeliveryStore: @unchecked Sendable {
    static let shared = PixaImageDeliveryStore()

    private let lock = NSLock()
    private var configuration: PixaImageDeliveryConfiguration?
    private var cacheKey: String { "pixarivo.image_delivery_configuration.\(PixaMediaRegion.headerValue)" }
    private var cacheDateKey: String { "pixarivo.image_delivery_configuration_date.\(PixaMediaRegion.headerValue)" }

    func snapshot() -> PixaImageDeliveryConfiguration? {
        lock.withLock { configuration }
    }

    /// 图片规则由服务端下发；本地缓存只用于启动加速，避免将 CDN 域名和转换参数硬编码进 App。
    func load(forceRefresh: Bool = false, token: String? = nil) async {
        let defaults = UserDefaults.standard
        if !forceRefresh,
           let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(PixaImageDeliveryConfiguration.self, from: data) {
            install(cached)
            let cachedAt = defaults.object(forKey: cacheDateKey) as? Date ?? .distantPast
            if Date.now.timeIntervalSince(cachedAt) < 86_400 { return }
        }
        do {
            let value: PixaCapabilities = try await APIClient().get(
                "/api/ais/capabilities",
                token: token
            )
            guard let configuration = value.imageDelivery else { return }
            install(configuration)
            if let data = try? JSONEncoder().encode(configuration) {
                defaults.set(data, forKey: cacheKey)
                defaults.set(Date.now, forKey: cacheDateKey)
            }
            await NetworkDiagnosticsStore.shared.recordSystemLog(
                tag: "IMAGE_RULES",
                "Installed provider=\(configuration.provider) region=\(configuration.region) enabled=\(configuration.enabled) version=\(configuration.rulesVersion)."
            )
        } catch {
            await NetworkDiagnosticsStore.shared.recordSystemLog(tag: "IMAGE_RULES", "Refresh failed: \(error.localizedDescription)")
        }
    }

    private func install(_ value: PixaImageDeliveryConfiguration) {
        let changed = lock.withLock { () -> Bool in
            let changed = configuration?.region != value.region
                || configuration?.rulesVersion != value.rulesVersion
                || configuration?.enabled != value.enabled
                || configuration?.provider != value.provider
            configuration = value
            return changed
        }
        if changed {
            // 每张远程图片都会订阅规则变化；通知必须从主线程发送，避免批量触发后台线程发布 SwiftUI 状态。
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .pixaImageDeliveryDidChange,
                    object: nil
                )
            }
        }
    }
}

enum PixaImageURLBuilder {
    static func resolve(
        from originalURL: URL?,
        preset: PixaImagePreset,
        targetPixelWidth: Int? = nil,
        maximumPixelWidth: Int = 900
    ) -> PixaResolvedImageRequest? {
        guard let originalURL else { return nil }
        if preset == .original {
            return PixaResolvedImageRequest(
                url: originalURL,
                requestedPreset: preset,
                appliedPreset: .original,
                pixelWidth: nil,
                resourceKind: .original,
                transformed: false
            )
        }
        guard originalURL.scheme?.lowercased() == "https",
              let host = originalURL.host?.lowercased(),
              !containsProcessingRule(originalURL) else {
            return existingRequest(for: originalURL, preset: preset)
        }
        let configuration = PixaImageDeliveryStore.shared.snapshot()
        if let targetPixelWidth,
           preset == .list || preset == .largeList || preset == .thumbnail,
           let selected = configuration?.adaptiveRule(
               targetPixelWidth: targetPixelWidth,
               maximumPixelWidth: maximumPixelWidth,
               host: host
           ),
           let url = transformedURL(rule: selected.rule, to: originalURL, configuration: configuration) {
            return PixaResolvedImageRequest(
                url: url,
                requestedPreset: preset,
                appliedPreset: selected.preset,
                pixelWidth: selected.pixelWidth,
                resourceKind: .thumbnail,
                transformed: true
            )
        }
        guard let rule = configuration?.rule(for: preset, host: host),
              let url = transformedURL(rule: rule, to: originalURL, configuration: configuration) else {
            return existingRequest(for: originalURL, preset: preset)
        }
        return PixaResolvedImageRequest(
            url: url,
            requestedPreset: preset,
            appliedPreset: preset,
            pixelWidth: PixaImageDeliveryConfiguration.pixelWidth(in: rule),
            resourceKind: preset == .detail ? .detail : .thumbnail,
            transformed: true
        )
    }

    private static func transformedURL(
        rule: String,
        to sourceURL: URL,
        configuration: PixaImageDeliveryConfiguration?
    ) -> URL? {
        if configuration?.usesCloudflarePresetQuery == true {
            guard let deliveryBaseURL = configuration?.normalizedDeliveryBaseURL,
                  let source = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else { return nil }
            let sourceItems = source.queryItems ?? []
            guard sourceItems.allSatisfy({ $0.name == "v" || $0.name == "version" }) else { return nil }
            var delivery = URLComponents(url: deliveryBaseURL, resolvingAgainstBaseURL: false)
            delivery?.percentEncodedPath = source.percentEncodedPath
            delivery?.queryItems = sourceItems + [URLQueryItem(name: "preset", value: rule)]
            delivery?.fragment = source.fragment
            return delivery?.url
        }
        return URL(string: sourceURL.absoluteString + (sourceURL.query == nil ? "?" : "&") + rule)
    }

    private static func containsProcessingRule(_ url: URL) -> Bool {
        url.absoluteString.contains("imageMogr2/")
            || url.absoluteString.contains("imageView2/")
            || URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.contains(where: { $0.name == "preset" }) == true
    }

    private static func existingRequest(for url: URL, preset: PixaImagePreset) -> PixaResolvedImageRequest {
        let transformed = containsProcessingRule(url)
        return PixaResolvedImageRequest(
            url: url,
            requestedPreset: preset,
            appliedPreset: preset,
            pixelWidth: PixaImageDeliveryConfiguration.pixelWidth(in: url.absoluteString),
            resourceKind: transformed ? (preset == .detail ? .detail : .thumbnail) : .original,
            transformed: transformed
        )
    }
}
