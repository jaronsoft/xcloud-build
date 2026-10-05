import Foundation

struct AISImagePreset: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    static let original = AISImagePreset(rawValue: "original")
    static let list = AISImagePreset(rawValue: "list")
    static let largeList = AISImagePreset(rawValue: "largeList")
    static let detail = AISImagePreset(rawValue: "detail")
    static let thumbnail = AISImagePreset(rawValue: "thumbnail")
    static let square = AISImagePreset(rawValue: "square")
}

enum AISImageResourceKind: String, Codable, CaseIterable, Sendable {
    case thumbnail
    case detail
    case original
}

struct AISResolvedImageRequest: Equatable, Sendable {
    let url: URL
    let requestedPreset: AISImagePreset
    let appliedPreset: AISImagePreset
    let pixelWidth: Int?
    let resourceKind: AISImageResourceKind
    let transformed: Bool

    var diagnosticLabel: String {
        switch resourceKind {
        case .original:
            String(localized: "diagnostics.image.kind.original")
        case .detail:
            if let pixelWidth {
                String.localizedStringWithFormat(
                    String(localized: "diagnostics.image.kind.detail"),
                    pixelWidth
                )
            } else {
                String(localized: "diagnostics.image.kind.detail.unknown")
            }
        case .thumbnail:
            if let pixelWidth {
                String.localizedStringWithFormat(
                    String(localized: "diagnostics.image.kind.thumbnail"),
                    pixelWidth
                )
            } else {
                String(localized: "diagnostics.image.kind.thumbnail.unknown")
            }
        }
    }
}

struct AISImageDeliveryPresets: Codable, Sendable {
    let ios: [String: String]
}

struct AISImageDeliveryConfiguration: Codable, Sendable {
    let enabled: Bool
    let provider: String
    let mode: String
    let region: String
    let rulesVersion: String
    let cacheSeconds: Int
    let domains: [String]
    let deliveryBaseUrl: String?
    let presets: AISImageDeliveryPresets

    private enum CodingKeys: String, CodingKey {
        case enabled
        case provider
        case mode
        case region
        case rulesVersion
        case cacheSeconds
        case domains
        case deliveryBaseUrl
        case presets
    }

    init(
        enabled: Bool,
        provider: String = "tencent",
        mode: String = "query",
        region: String = AISMediaRegionRequestContext.headerValue,
        rulesVersion: String = "1",
        cacheSeconds: Int,
        domains: [String],
        deliveryBaseUrl: String? = nil,
        presets: AISImageDeliveryPresets
    ) {
        self.enabled = enabled
        self.provider = provider
        self.mode = mode
        self.region = region
        self.rulesVersion = rulesVersion
        self.cacheSeconds = cacheSeconds
        self.domains = domains
        self.deliveryBaseUrl = deliveryBaseUrl
        self.presets = presets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        let decodedProvider = try container.decodeIfPresent(
            String.self,
            forKey: .provider
        ) ?? "tencent"
        provider = decodedProvider.caseInsensitiveCompare("cloudflare")
            == .orderedSame ? "cloudflare" : "tencent"
        let decodedMode = try container.decodeIfPresent(
            String.self,
            forKey: .mode
        ) ?? "query"
        mode = decodedMode == "presetQuery" ? "presetQuery" : "query"
        let decodedRegion = try container.decodeIfPresent(
            String.self,
            forKey: .region
        ) ?? AISMediaRegionRequestContext.headerValue
        region = decodedRegion == "cn" ? "cn" : "global"
        let decodedRulesVersion = try container.decodeIfPresent(
            String.self,
            forKey: .rulesVersion
        ) ?? "1"
        let allowedRulesVersion = decodedRulesVersion.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
                || "._-".unicodeScalars.contains($0)
        }
        rulesVersion = allowedRulesVersion
            && !decodedRulesVersion.isEmpty
            && decodedRulesVersion.count <= 32
            ? decodedRulesVersion
            : "1"
        cacheSeconds = try container.decode(Int.self, forKey: .cacheSeconds)
        domains = try container.decode([String].self, forKey: .domains)
        deliveryBaseUrl = try container.decodeIfPresent(
            String.self,
            forKey: .deliveryBaseUrl
        )
        presets = try container.decode(
            AISImageDeliveryPresets.self,
            forKey: .presets
        )
    }

    private static let cloudflarePresets: Set<String> = [
        "w200",
        "w400",
        "w600",
        "w800",
        "w900",
        "detail1200",
        "square600",
        "original"
    ]

    var usesCloudflarePresetQuery: Bool {
        provider.caseInsensitiveCompare("cloudflare") == .orderedSame
            && mode == "presetQuery"
    }

    var normalizedDeliveryBaseURL: URL? {
        guard usesCloudflarePresetQuery,
              let deliveryBaseUrl,
              let url = URL(string: deliveryBaseUrl),
              url.scheme?.lowercased() == "https",
              url.path.isEmpty || url.path == "/",
              url.query == nil,
              url.fragment == nil else {
            return nil
        }
        return url
    }

    func rule(for preset: AISImagePreset, host: String) -> String? {
        guard enabled,
              domains.contains(where: {
                  $0.caseInsensitiveCompare(host) == .orderedSame
              }),
              let value = presets.ios[preset.rawValue] else {
            return nil
        }
        let rule = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let supported = usesCloudflarePresetQuery
            ? Self.cloudflarePresets.contains(rule)
            : rule.hasPrefix("imageMogr2/")
                || rule.hasPrefix("imageView2/")
        guard supported,
              !rule.contains(where: { "?&#\r\n".contains($0) }) else {
            return nil
        }
        return rule
    }

    func adaptiveRule(
        targetPixelWidth: Int,
        maximumPixelWidth: Int,
        host: String
    ) -> (preset: AISImagePreset, rule: String, pixelWidth: Int)? {
        guard enabled,
              domains.contains(where: {
                  $0.caseInsensitiveCompare(host) == .orderedSame
              }) else {
            return nil
        }
        let maximum = max(1, maximumPixelWidth)
        let target = min(maximum, max(1, targetPixelWidth))
        let candidates: [
            (preset: AISImagePreset, rule: String, pixelWidth: Int)
        ] = presets.ios.compactMap { element in
            let (key, _) = element
            let preset = AISImagePreset(rawValue: key)
            guard preset != .square,
                  let rule = rule(for: preset, host: host),
                  let width = Self.thumbnailPixelWidth(in: rule),
                  width <= maximum else {
                return nil
            }
            return (preset: preset, rule: rule, pixelWidth: width)
        }
        .sorted { $0.pixelWidth < $1.pixelWidth }
        return candidates.first { $0.pixelWidth >= target }
            ?? candidates.last
    }

    static func thumbnailPixelWidth(in rule: String) -> Int? {
        if rule == "detail1200" {
            return 1_200
        }
        if rule.hasPrefix("w"),
           let width = Int(rule.dropFirst()),
           width > 0 {
            return width
        }
        guard let expression = try? NSRegularExpression(
            pattern: #"imageMogr2/thumbnail/(\d+)x"#
        ) else {
            return nil
        }
        let range = NSRange(rule.startIndex..., in: rule)
        guard let match = expression.firstMatch(in: rule, range: range),
              let widthRange = Range(match.range(at: 1), in: rule) else {
            return nil
        }
        return Int(rule[widthRange])
    }
}

private struct AISImageDeliveryCapabilities: Decodable {
    let imageDelivery: AISImageDeliveryConfiguration?
}

final class AISImageDeliveryStore: @unchecked Sendable {
    static let shared = AISImageDeliveryStore()

    private let lock = NSLock()
    private var configuration: AISImageDeliveryConfiguration?
    private let userDefaults = UserDefaults.standard
    private var cacheKey: String {
        let region = AISMediaRegionRequestContext.headerValue
        let version = userDefaults.string(
            forKey: rulesVersionStorageKey(region: region)
        ) ?? "1"
        return cacheKey(region: region, rulesVersion: version)
    }

    private func cacheKey(
        region: String,
        rulesVersion: String
    ) -> String {
        AISResponseCache.key(
            scope: "public",
            resource: "image-delivery:\(region):\(rulesVersion)"
        )
    }

    private func rulesVersionStorageKey(region: String) -> String {
        "ais.image_delivery_rules_version.\(region)"
    }

    private func cacheKey(
        for value: AISImageDeliveryConfiguration
    ) -> String {
        cacheKey(
            region: value.region,
            rulesVersion: value.rulesVersion
        )
    }

    func snapshot() -> AISImageDeliveryConfiguration? {
        lock.withLock { configuration }
    }

    /// 启动时优先安装磁盘缓存；首次安装最多等待 3 秒，避免公共配置故障阻塞进入应用。
    func load(forceRefresh: Bool = false) async {
        if forceRefresh {
            guard let value = await fetch() else { return }
            install(value)
            await AISResponseCache.shared.write(value, key: cacheKey(for: value))
            return
        }
        if let cached = await AISResponseCache.shared.read(
            AISImageDeliveryConfiguration.self,
            key: cacheKey,
            ttl: 86400,
            allowsStale: true
        ) {
            install(cached.value)
            Task { await refresh() }
            return
        }

        await withTaskGroup(of: AISImageDeliveryConfiguration?.self) {
            group in
            group.addTask { await self.fetch() }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return nil
            }
            if let first = await group.next(), let value = first {
                install(value)
                await AISResponseCache.shared.write(
                    value,
                    key: cacheKey(for: value)
                )
            }
            group.cancelAll()
        }
    }

    private func refresh() async {
        guard let value = await fetch() else { return }
        install(value)
        await AISResponseCache.shared.write(value, key: cacheKey(for: value))
    }

    private func fetch() async -> AISImageDeliveryConfiguration? {
        do {
            let capabilities: AISImageDeliveryCapabilities =
                try await APIClient().get("/api/ais/capabilities")
            return capabilities.imageDelivery
        } catch {
            return nil
        }
    }

    private func install(_ value: AISImageDeliveryConfiguration) {
        userDefaults.set(
            value.rulesVersion,
            forKey: rulesVersionStorageKey(region: value.region)
        )
        lock.withLock {
            configuration = value
        }
    }
}

enum AISImageURLBuilder {
    static func maximumAdaptivePixelWidth(for preset: AISImagePreset) -> Int {
        if preset == .thumbnail { return 400 }
        if preset == .list { return 600 }
        return 900
    }

    static func resolve(
        from originalURL: URL?,
        preset: AISImagePreset,
        targetPixelWidth: Int? = nil,
        maximumPixelWidth: Int = 900
    ) -> AISResolvedImageRequest? {
        resolve(
            from: originalURL,
            preset: preset,
            targetPixelWidth: targetPixelWidth,
            maximumPixelWidth: maximumPixelWidth,
            configuration: AISImageDeliveryStore.shared.snapshot()
        )
    }

    static func resolve(
        from originalURL: URL?,
        preset: AISImagePreset,
        targetPixelWidth: Int? = nil,
        maximumPixelWidth: Int = 900,
        configuration: AISImageDeliveryConfiguration?
    ) -> AISResolvedImageRequest? {
        guard let originalURL else { return nil }
        guard preset != .original else {
            let deliveryURL = originalDeliveryURL(
                from: originalURL,
                configuration: configuration
            )
            return AISResolvedImageRequest(
                url: deliveryURL,
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

        if let targetPixelWidth,
           preset == .list || preset == .largeList || preset == .thumbnail,
           let selected = configuration?.adaptiveRule(
               targetPixelWidth: targetPixelWidth,
               maximumPixelWidth: maximumPixelWidth,
               host: host
           ),
           let transformedURL = transformedURL(
               rule: selected.rule,
               to: originalURL,
               configuration: configuration
           ) {
            return AISResolvedImageRequest(
                url: transformedURL,
                requestedPreset: preset,
                appliedPreset: selected.preset,
                pixelWidth: selected.pixelWidth,
                resourceKind: .thumbnail,
                transformed: true
            )
        }

        guard let rule = configuration?.rule(for: preset, host: host),
              let transformedURL = transformedURL(
                  rule: rule,
                  to: originalURL,
                  configuration: configuration
              )
        else {
            return existingRequest(for: originalURL, preset: preset)
        }
        return AISResolvedImageRequest(
            url: transformedURL,
            requestedPreset: preset,
            appliedPreset: preset,
            pixelWidth: AISImageDeliveryConfiguration
                .thumbnailPixelWidth(in: rule),
            resourceKind: preset == .detail ? .detail : .thumbnail,
            transformed: true
        )
    }

    static func url(
        from originalURL: URL?,
        preset: AISImagePreset
    ) -> URL? {
        resolve(
            from: originalURL,
            preset: preset,
            configuration: AISImageDeliveryStore.shared.snapshot()
        )?.url
    }

    static func url(
        from originalURL: URL?,
        preset: AISImagePreset,
        configuration: AISImageDeliveryConfiguration?
    ) -> URL? {
        resolve(
            from: originalURL,
            preset: preset,
            configuration: configuration
        )?.url
    }

    static func url(
        from originalURLString: String?,
        preset: AISImagePreset
    ) -> URL? {
        guard let originalURLString, !originalURLString.isEmpty else {
            return nil
        }
        return url(from: URL(string: originalURLString), preset: preset)
    }

    private static func containsProcessingRule(_ url: URL) -> Bool {
        url.absoluteString.contains("imageMogr2/")
            || url.absoluteString.contains("imageView2/")
            || URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )?.queryItems?.contains(where: { $0.name == "preset" }) == true
    }

    /// 文件交付必须移除 CDN 图片处理片段，同时保留版本号或签名等其他查询参数。
    private static func removingProcessingRules(from url: URL) -> URL {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        let query = components.percentEncodedQuery else {
            return url
        }
        let retained = query.split(separator: "&").filter { component in
            let decoded = component.removingPercentEncoding
                ?? String(component)
            return !decoded.hasPrefix("imageMogr2/")
                && !decoded.hasPrefix("imageView2/")
                && !decoded.hasPrefix("preset=")
        }
        components.percentEncodedQuery = retained.isEmpty
            ? nil
            : retained.joined(separator: "&")
        return components.url ?? url
    }

    private static func originalDeliveryURL(
        from url: URL,
        configuration: AISImageDeliveryConfiguration?
    ) -> URL {
        let cleaned = removingProcessingRules(from: url)
        guard configuration?.usesCloudflarePresetQuery == true,
              let deliveryHost = configuration?.normalizedDeliveryBaseURL?.host,
              cleaned.host?.caseInsensitiveCompare(deliveryHost) == .orderedSame,
              let sourceHost = configuration?.domains.first,
              var components = URLComponents(
                  url: cleaned,
                  resolvingAgainstBaseURL: false
              ) else {
            return cleaned
        }
        components.scheme = "https"
        components.host = sourceHost
        components.port = nil
        return components.url ?? cleaned
    }

    private static func transformedURL(
        rule: String,
        to url: URL,
        configuration: AISImageDeliveryConfiguration?
    ) -> URL? {
        if configuration?.usesCloudflarePresetQuery == true {
            return cloudflareURL(
                rule: rule,
                sourceURL: url,
                deliveryBaseURL: configuration?.normalizedDeliveryBaseURL
            )
        }
        let separator = url.absoluteString.contains("?") ? "&" : "?"
        return URL(string: url.absoluteString + separator + rule)
    }

    /// 国际图片只保留公开版本参数，签名或未知参数继续使用原图。
    private static func cloudflareURL(
        rule: String,
        sourceURL: URL,
        deliveryBaseURL: URL?
    ) -> URL? {
        guard let deliveryBaseURL,
              let source = URLComponents(
                  url: sourceURL,
                  resolvingAgainstBaseURL: false
              ) else {
            return nil
        }
        let sourceItems = source.queryItems ?? []
        guard sourceItems.allSatisfy({
            $0.name == "v" || $0.name == "version"
        }) else {
            return nil
        }
        var delivery = URLComponents(
            url: deliveryBaseURL,
            resolvingAgainstBaseURL: false
        )
        delivery?.percentEncodedPath = source.percentEncodedPath
        delivery?.percentEncodedQueryItems = sourceItems.map {
            URLQueryItem(name: $0.name, value: $0.value)
        } + [URLQueryItem(name: "preset", value: rule)]
        delivery?.fragment = source.fragment
        return delivery?.url
    }

    private static func existingRequest(
        for url: URL,
        preset: AISImagePreset
    ) -> AISResolvedImageRequest {
        let rule = url.absoluteString
        let width = AISImageDeliveryConfiguration.thumbnailPixelWidth(in: rule)
        let transformed = containsProcessingRule(url)
        let kind: AISImageResourceKind
        if !transformed {
            kind = .original
        } else if preset == .detail {
            kind = .detail
        } else {
            kind = .thumbnail
        }
        return AISResolvedImageRequest(
            url: url,
            requestedPreset: preset,
            appliedPreset: preset,
            pixelWidth: width,
            resourceKind: kind,
            transformed: transformed
        )
    }
}
