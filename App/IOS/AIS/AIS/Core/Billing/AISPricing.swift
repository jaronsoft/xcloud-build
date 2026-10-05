import Foundation
import Observation

struct AISPricingRulesSnapshot: Codable {
    let version: String
    let generatedAt: Date
    let expiresAt: Date
    let token: String?
    let imageBasePoints: Int
    let videoBasePoints: Int
    let videoPerSecondPoints: Int
    let videoAllowedDurationSeconds: [Int]
    let promptOptimizeBasePoints: Int
    let imageUnderstandBasePoints: Int
    let resultAnalysisBasePoints: Int
    let templateBasePoints: Int
    let imageOrientationMultipliers: [String: String]?
    let imageAspectRatioMultipliers: [String: String]
    let imageResolutionMultipliers: [String: String]
    let imageAttributeMultipliers: [String: [String: String]]?
    let imageModelMultipliers: [String: String]?
    let videoAspectRatioMultipliers: [String: String]
    let videoResolutionMultipliers: [String: String]
    let countryMultiplier: String
    let membershipDiscountPercent: String
    let membershipBenefitCode: String?
    let membershipBenefitName: String?
    let rechargeMembershipDiscountPercent: String?
    let rechargeMembershipBenefitName: String?
    let rechargeMembershipBenefitSource: String?
    let subscriptionDiscountPercent: String?
    let subscriptionBenefitName: String?
    let effectiveDiscountPercent: String?
    let effectiveBenefitCode: String?
    let effectiveBenefitName: String?
    let effectiveBenefitSource: String?
    let discountPolicy: String?
    let effectiveMembershipLevel: String?
    let promoMarkEnabled: Bool
    let promoMarkDiscountPercent: String
    let promoMarkCode: String?
    let promoMarkName: String?
    let promoMarkVersion: String?
    let imageEdit: AISPricingSnapshotImageEdit

    private enum CodingKeys: String, CodingKey {
        case version = "Version"
        case generatedAt = "GeneratedAt"
        case expiresAt = "ExpiresAt"
        case token = "Token"
        case imageBasePoints = "ImageBasePoints"
        case videoBasePoints = "VideoBasePoints"
        case videoPerSecondPoints = "VideoPerSecondPoints"
        case videoAllowedDurationSeconds = "VideoAllowedDurationSeconds"
        case promptOptimizeBasePoints = "PromptOptimizeBasePoints"
        case imageUnderstandBasePoints = "ImageUnderstandBasePoints"
        case resultAnalysisBasePoints = "ResultAnalysisBasePoints"
        case templateBasePoints = "TemplateBasePoints"
        case imageOrientationMultipliers = "ImageOrientationMultipliers"
        case imageAspectRatioMultipliers = "ImageAspectRatioMultipliers"
        case imageResolutionMultipliers = "ImageResolutionMultipliers"
        case imageAttributeMultipliers = "ImageAttributeMultipliers"
        case imageModelMultipliers = "ImageModelMultipliers"
        case videoAspectRatioMultipliers = "VideoAspectRatioMultipliers"
        case videoResolutionMultipliers = "VideoResolutionMultipliers"
        case countryMultiplier = "CountryMultiplier"
        case membershipDiscountPercent = "MembershipDiscountPercent"
        case membershipBenefitCode = "MembershipBenefitCode"
        case membershipBenefitName = "MembershipBenefitName"
        case rechargeMembershipDiscountPercent = "RechargeMembershipDiscountPercent"
        case rechargeMembershipBenefitName = "RechargeMembershipBenefitName"
        case rechargeMembershipBenefitSource = "RechargeMembershipBenefitSource"
        case subscriptionDiscountPercent = "SubscriptionDiscountPercent"
        case subscriptionBenefitName = "SubscriptionBenefitName"
        case effectiveDiscountPercent = "EffectiveDiscountPercent"
        case effectiveBenefitCode = "EffectiveBenefitCode"
        case effectiveBenefitName = "EffectiveBenefitName"
        case effectiveBenefitSource = "EffectiveBenefitSource"
        case discountPolicy = "DiscountPolicy"
        case effectiveMembershipLevel = "EffectiveMembershipLevel"
        case promoMarkEnabled = "PromoMarkEnabled"
        case promoMarkDiscountPercent = "PromoMarkDiscountPercent"
        case promoMarkCode = "PromoMarkCode"
        case promoMarkName = "PromoMarkName"
        case promoMarkVersion = "PromoMarkVersion"
        case imageEdit = "ImageEdit"
    }
}

typealias AISPricingSnapshot = AISPricingRulesSnapshot

struct AISPricingSnapshotImageEdit: Codable {
    let localAiEditRate: String
    let localAiEditMinPoints: Int
    let aiEditRate: String
    let aiEditMinPoints: Int
    let aiFusionRate: String
    let aiFusionMinPoints: Int
    let roundTo: Int

    private enum CodingKeys: String, CodingKey {
        case localAiEditRate = "LocalAiEditRate"
        case localAiEditMinPoints = "LocalAiEditMinPoints"
        case aiEditRate = "AiEditRate"
        case aiEditMinPoints = "AiEditMinPoints"
        case aiFusionRate = "AiFusionRate"
        case aiFusionMinPoints = "AiFusionMinPoints"
        case roundTo = "RoundTo"
    }
}

struct AISLocalPrice {
    let points: Int
    let originalPoints: Int
    let savedPoints: Int
    let effectiveDiscountPercent: Decimal
    let effectiveBenefitName: String?
    let effectiveBenefitSource: String?
    let promoMarkApplied: Bool
    let promoMarkSuppressedReason: String?
}

struct AISPriceChangePayload: Decodable {
    let localCalculatedPoints: Int?
    let points: Int
    let originalPoints: Int?
    let savedPoints: Int?
    let latestPricingRules: AISPricingRulesSnapshot?

    init?(details: JSONValue?) {
        guard let details,
              let data = try? JSONEncoder().encode(details) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds
            ]
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            guard let date = fractional.date(from: value)
                    ?? standard.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "无法解析价格规则时间"
                )
            }
            return date
        }
        guard let value = try? decoder.decode(Self.self, from: data) else {
            return nil
        }
        self = value
    }
}

enum AISLocalPricingCalculator {
    static func image(
        snapshot: AISPricingRulesSnapshot,
        orientation: String = "",
        aspectRatio: String,
        resolution: String,
        selectedAttributes: [String: [String]] = [:],
        selectedModelKey: String = "",
        fallbackOrientationMultiplier: Decimal = 1,
        fallbackAspectRatioMultiplier: Decimal = 1,
        fallbackResolutionMultiplier: Decimal = 1,
        attributeMultipliers: [Decimal] = [],
        modelMultiplier: Decimal = 1,
        count: Int = 1,
        promoMarkEnabled: Bool = false
    ) -> AISLocalPrice {
        var raw = Decimal(snapshot.imageBasePoints)
        raw *= decimal(
            value(
                for: orientation,
                in: snapshot.imageOrientationMultipliers
            ),
            fallback: max(1, fallbackOrientationMultiplier)
        )
        raw *= decimal(
            value(
                for: aspectRatio,
                in: snapshot.imageAspectRatioMultipliers
            ),
            fallback: max(1, fallbackAspectRatioMultiplier)
        )
        raw *= decimal(
            value(
                for: resolution,
                in: snapshot.imageResolutionMultipliers
            ),
            fallback: max(1, fallbackResolutionMultiplier)
        )
        let cachedAttributeMultipliers = selectedAttributes.flatMap {
            group, itemIDs in
            itemIDs.compactMap {
                decimalValue(
                    value(
                        for: $0,
                        in: nestedValues(
                            for: group,
                            in: snapshot.imageAttributeMultipliers
                        )
                    )
                )
            }
        }
        let resolvedAttributeMultipliers =
            snapshot.imageAttributeMultipliers == nil
                ? attributeMultipliers
                : cachedAttributeMultipliers
        resolvedAttributeMultipliers.forEach { raw *= max(1, $0) }
        raw *= decimal(snapshot.countryMultiplier, fallback: 1)
        let cachedModelMultiplier = decimalValue(
            value(
                for: selectedModelKey,
                in: snapshot.imageModelMultipliers
            )
        )
        let resolvedModelMultiplier = cachedModelMultiplier
            ?? modelMultiplier
        raw *= max(1, resolvedModelMultiplier)
        raw *= Decimal(max(1, count))

        let original = max(1, ceiling(raw))
        let membershipDiscount = decimal(
            snapshot.effectiveDiscountPercent
                ?? snapshot.membershipDiscountPercent
        )
        let promoDiscount = promoMarkEnabled && snapshot.promoMarkEnabled
            ? decimal(snapshot.promoMarkDiscountPercent)
            : 0
        let promoMarkApplied = promoDiscount > membershipDiscount
        let effectiveDiscount = promoMarkApplied
            ? promoDiscount
            : membershipDiscount
        let final = discounted(original, percent: effectiveDiscount)
        return AISLocalPrice(
            points: final,
            originalPoints: original,
            savedPoints: max(0, original - final),
            effectiveDiscountPercent: effectiveDiscount,
            effectiveBenefitName: promoMarkApplied
                ? snapshot.promoMarkName
                : snapshot.effectiveBenefitName ?? snapshot.membershipBenefitName,
            effectiveBenefitSource: promoMarkApplied
                ? "promo_mark"
                : snapshot.effectiveBenefitSource,
            promoMarkApplied: promoMarkApplied,
            promoMarkSuppressedReason: promoMarkEnabled
                && snapshot.promoMarkEnabled
                && !promoMarkApplied
                ? String(localized: "creation.promo.suppressed")
                : nil
        )
    }

    static func template(
        snapshot: AISPricingRulesSnapshot,
        basePoints: Int,
        defaultResolution: String?,
        resolution: String,
        selectedModelKey: String,
        fallbackResolutionMultiplier: Decimal = 1,
        fallbackModelMultiplier: Decimal = 1,
        promoMarkEnabled: Bool = false
    ) -> AISLocalPrice {
        let usesDefaultResolution = defaultResolution?.nilIfEmpty == nil
            || defaultResolution?.caseInsensitiveCompare(resolution)
                == .orderedSame
        let resolutionMultiplier = usesDefaultResolution
            ? Decimal(1)
            : decimal(
                value(
                    for: resolution,
                    in: snapshot.imageResolutionMultipliers
                ),
                fallback: max(1, fallbackResolutionMultiplier)
            )
        var raw = Decimal(basePoints > 0 ? basePoints : 150)
        raw *= resolutionMultiplier
        let cachedModelMultiplier = decimalValue(
            value(
                for: selectedModelKey,
                in: snapshot.imageModelMultipliers
            )
        )
        let resolvedModelMultiplier = cachedModelMultiplier
            ?? fallbackModelMultiplier
        raw *= max(
            1,
            resolvedModelMultiplier
        )
        raw *= decimal(snapshot.countryMultiplier, fallback: 1)

        let original = max(1, ceiling(raw))
        let membershipDiscount = decimal(
            snapshot.effectiveDiscountPercent
                ?? snapshot.membershipDiscountPercent
        )
        let promoDiscount = promoMarkEnabled && snapshot.promoMarkEnabled
            ? decimal(snapshot.promoMarkDiscountPercent)
            : 0
        let promoMarkApplied = promoDiscount > membershipDiscount
        let effectiveDiscount = promoMarkApplied
            ? promoDiscount
            : membershipDiscount
        let final = discounted(original, percent: effectiveDiscount)
        return AISLocalPrice(
            points: final,
            originalPoints: original,
            savedPoints: max(0, original - final),
            effectiveDiscountPercent: effectiveDiscount,
            effectiveBenefitName: promoMarkApplied
                ? snapshot.promoMarkName
                : snapshot.effectiveBenefitName ?? snapshot.membershipBenefitName,
            effectiveBenefitSource: promoMarkApplied
                ? "promo_mark"
                : snapshot.effectiveBenefitSource,
            promoMarkApplied: promoMarkApplied,
            promoMarkSuppressedReason: promoMarkEnabled
                && snapshot.promoMarkEnabled
                && !promoMarkApplied
                ? String(localized: "creation.promo.suppressed")
                : nil
        )
    }

    static func membershipSavedPoints(
        snapshot: AISPricingRulesSnapshot,
        originalPoints: Int
    ) -> Int {
        let membershipPrice = discounted(
            originalPoints,
            percent: decimal(snapshot.membershipDiscountPercent)
        )
        return max(0, originalPoints - membershipPrice)
    }

    private static func discounted(_ points: Int, percent: Decimal) -> Int {
        guard percent > 0 else { return points }
        let value = Decimal(points) * (100 - min(80, percent)) / 100
        return max(1, ceiling(value))
    }

    private static func ceiling(_ value: Decimal) -> Int {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 0, .up)
        return NSDecimalNumber(decimal: output).intValue
    }

    private static func decimal(
        _ value: String?,
        fallback: Decimal = 0
    ) -> Decimal {
        guard let value,
              let result = Decimal(
                  string: value,
                  locale: Locale(identifier: "en_US_POSIX")
              ) else {
            return fallback
        }
        return result
    }

    private static func decimalValue(_ value: String?) -> Decimal? {
        guard let value else { return nil }
        return Decimal(
            string: value,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func value(
        for key: String,
        in values: [String: String]?
    ) -> String? {
        guard !key.isEmpty, let values else { return nil }
        return values.first {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        }?.value
    }

    private static func nestedValues(
        for key: String,
        in values: [String: [String: String]]?
    ) -> [String: String]? {
        guard let values else { return nil }
        return values.first {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        }?.value
    }
}

extension Notification.Name {
    static let aisPricingRulesInvalidated = Notification.Name(
        "AIS.PricingRulesInvalidated"
    )
    static let aisRechargeCredited = Notification.Name(
        "AIS.RechargeCredited"
    )
}

enum AISPricingRulesRetryPolicy {
    static let maximumAttempts = 3

    static func delayMilliseconds(afterFailedAttempt attempt: Int) -> Int? {
        switch attempt {
        case 1:
            return 300
        case 2:
            return 900
        default:
            return nil
        }
    }

    static func shouldRetry(
        _ error: Error,
        afterFailedAttempt attempt: Int
    ) -> Bool {
        guard attempt < maximumAttempts,
              !AISErrorClassifier.isCancellation(error) else {
            return false
        }
        guard let apiError = error as? APIError else {
            return true
        }
        switch apiError {
        case .invalidResponse, .missingData:
            return true
        case let .server(status, _):
            return status == 408 || status == 429 || status >= 500
        case .business, .rejected:
            return false
        }
    }
}

@MainActor
@Observable
final class AISPricingRulesStore {
    private let api = APIClient()

    private(set) var rules: AISPricingRulesSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func reset() {
        rules = nil
        isLoading = false
        errorMessage = nil
    }

    func load(
        userID: String?,
        accessToken: String?,
        force: Bool = false
    ) async {
        guard let userID, let accessToken else {
            rules = nil
            return
        }
        let key = cacheKey(userID: userID)
        if let cached = await AISResponseCache.shared.read(
               AISPricingRulesSnapshot.self,
               key: key,
               allowsStale: true
           ) {
            rules = cached.value
            errorMessage = nil
            if !force {
                return
            }
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        var latestError: Error?
        for attempt in 1...AISPricingRulesRetryPolicy.maximumAttempts {
            do {
                let latest: AISPricingRulesSnapshot = try await api.get(
                    "/api/ais/billing/pricing-snapshot",
                    query: [
                        URLQueryItem(
                            name: "mediaType",
                            value: "image"
                        )
                    ],
                    accessToken: accessToken
                )
                rules = latest
                errorMessage = nil
                await AISResponseCache.shared.write(latest, key: key)
                return
            } catch {
                if AISErrorClassifier.isCancellation(error) {
                    return
                }
                latestError = error
                guard AISPricingRulesRetryPolicy.shouldRetry(
                    error,
                    afterFailedAttempt: attempt
                ), let delay = AISPricingRulesRetryPolicy
                    .delayMilliseconds(afterFailedAttempt: attempt) else {
                    break
                }
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
            }
        }
        if let latestError {
            errorMessage = latestError.localizedDescription
        }
    }

    func replace(
        _ latest: AISPricingRulesSnapshot,
        userID: String?
    ) async {
        guard let userID else { return }
        rules = latest
        errorMessage = nil
        await AISResponseCache.shared.write(
            latest,
            key: cacheKey(userID: userID)
        )
    }

    func invalidate(userID: String?) async {
        guard let userID else {
            rules = nil
            return
        }
        await AISResponseCache.shared.remove(key: cacheKey(userID: userID))
        rules = nil
    }

    private func cacheKey(userID: String) -> String {
        AISResponseCache.key(
            scope: "user:\(userID)",
            resource: "pricing-rules-image"
        )
    }
}
