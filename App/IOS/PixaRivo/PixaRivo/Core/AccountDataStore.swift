import Foundation
import Observation

extension Notification.Name {
    static let pixaBalanceDidChange = Notification.Name("PixaBalanceDidChange")
}

struct PixaBalanceSummary: Codable, Sendable {
    let balancePoints: Int
    let subscriptionPoints: Int
    let frozenPoints: Int
    let availablePoints: Int

    private enum CodingKeys: String, CodingKey {
        case balancePoints, subscriptionPoints, frozenPoints, availablePoints
        case balancePointsUpper = "BalancePoints"
        case subscriptionPointsUpper = "SubscriptionPoints"
        case frozenPointsUpper = "FrozenPoints"
        case availablePointsUpper = "AvailablePoints"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        balancePoints = try box.decodeIfPresent(Int.self, forKey: .balancePoints)
            ?? box.decodeIfPresent(Int.self, forKey: .balancePointsUpper) ?? 0
        subscriptionPoints = try box.decodeIfPresent(Int.self, forKey: .subscriptionPoints)
            ?? box.decodeIfPresent(Int.self, forKey: .subscriptionPointsUpper) ?? 0
        frozenPoints = try box.decodeIfPresent(Int.self, forKey: .frozenPoints)
            ?? box.decodeIfPresent(Int.self, forKey: .frozenPointsUpper) ?? 0
        availablePoints = try box.decodeIfPresent(Int.self, forKey: .availablePoints)
            ?? box.decodeIfPresent(Int.self, forKey: .availablePointsUpper)
            ?? max(0, balancePoints + subscriptionPoints - frozenPoints)
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(balancePoints, forKey: .balancePoints)
        try box.encode(subscriptionPoints, forKey: .subscriptionPoints)
        try box.encode(frozenPoints, forKey: .frozenPoints)
        try box.encode(availablePoints, forKey: .availablePoints)
    }
}

enum PixaBalanceRefreshResult: Sendable {
    case success(PixaBalanceSummary)
    case unavailable
}

@MainActor
@Observable
final class PixaAccountDataStore {
    private let api = APIClient()
    let pricingRules = PixaPricingRulesStore()
    private(set) var balance: PixaBalanceSummary?
    private(set) var isRefreshing = false
    private var loadedUserID: String?
    private var balanceTask: Task<PixaBalanceSummary, Error>?
    private var balanceTaskID: UUID?
    private var balanceTaskUserID: String?

    var membershipLevelCode: String? {
        pricingRules.rules?.effectiveMembershipLevel?.nilIfEmpty
            ?? pricingRules.rules?.membershipBenefitCode?.nilIfEmpty
    }

    func load(session: SessionStore, force: Bool = false) async {
        guard let token = await session.validAccessToken(),
              let userID = session.user?.id else {
            reset()
            return
        }
        if loadedUserID != userID {
            balance = Self.cachedBalance(userID: userID)
            loadedUserID = userID
        }
        async let pricingLoad: Void = pricingRules.load(
            userID: userID,
            accessToken: token,
            force: force
        )
        _ = await refreshBalance(
            userID: userID,
            accessToken: token,
            force: force
        )
        await pricingLoad
    }

    func refreshBalance(
        userID: String,
        accessToken: String,
        force: Bool = false
    ) async -> PixaBalanceRefreshResult {
        if loadedUserID != userID {
            balance = Self.cachedBalance(userID: userID)
            loadedUserID = userID
        }
        if let balanceTask,
           balanceTaskUserID == userID,
           let balanceTaskID {
            return await finishBalanceRefresh(
                balanceTask,
                id: balanceTaskID,
                userID: userID
            )
        }
        if let balance, !force {
            return .success(balance)
        }

        balanceTask?.cancel()
        let requestID = UUID()
        let requestTask = Task<PixaBalanceSummary, Error> {
            try await api.get(
                "/api/ais/balance",
                token: accessToken
            )
        }
        balanceTask = requestTask
        balanceTaskID = requestID
        balanceTaskUserID = userID
        isRefreshing = true
        return await finishBalanceRefresh(
            requestTask,
            id: requestID,
            userID: userID
        )
    }

    private func finishBalanceRefresh(
        _ task: Task<PixaBalanceSummary, Error>,
        id: UUID,
        userID: String
    ) async -> PixaBalanceRefreshResult {
        do {
            let value = try await task.value
            guard loadedUserID == userID else { return .unavailable }
            if balanceTaskID == id, balanceTaskUserID == userID {
                balance = value
                Self.cache(value, userID: userID)
                clearBalanceTask(id: id, userID: userID)
            }
            return .success(value)
        } catch {
            // 已有安全快照时继续保留展示，但调用方可以决定是否允许后续敏感操作。
            clearBalanceTask(id: id, userID: userID)
            return .unavailable
        }
    }

    private func clearBalanceTask(id: UUID, userID: String) {
        guard balanceTaskID == id, balanceTaskUserID == userID else { return }
        balanceTask = nil
        balanceTaskID = nil
        balanceTaskUserID = nil
        isRefreshing = false
    }

    func reset() {
        balance = nil
        loadedUserID = nil
        balanceTask?.cancel()
        balanceTask = nil
        balanceTaskID = nil
        balanceTaskUserID = nil
        isRefreshing = false
        pricingRules.reset()
    }

    private static func cache(_ value: PixaBalanceSummary, userID: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        KeychainStore.save(data, account: cacheAccount(userID: userID))
    }

    private static func cachedBalance(userID: String) -> PixaBalanceSummary? {
        guard let data = KeychainStore.loadData(account: cacheAccount(userID: userID)) else {
            return nil
        }
        return try? JSONDecoder().decode(PixaBalanceSummary.self, from: data)
    }

    private static func cacheAccount(userID: String) -> String {
        "balance-\(userID)"
    }
}

struct PixaPricingRulesSnapshot: Codable, Sendable {
    let version: String
    let imageResolutionMultipliers: [String: String]
    let imageModelMultipliers: [String: String]?
    let countryMultiplier: String
    let membershipDiscountPercent: String
    let membershipBenefitCode: String?
    let membershipBenefitName: String?
    let effectiveDiscountPercent: String?
    let effectiveBenefitName: String?
    let effectiveBenefitSource: String?
    let discountPolicy: String?
    let effectiveMembershipLevel: String?
    let promoMarkEnabled: Bool
    let promoMarkDiscountPercent: String
    let promoMarkName: String?

    private enum CodingKeys: String, CodingKey {
        case version = "Version"
        case imageResolutionMultipliers = "ImageResolutionMultipliers"
        case imageModelMultipliers = "ImageModelMultipliers"
        case countryMultiplier = "CountryMultiplier"
        case membershipDiscountPercent = "MembershipDiscountPercent"
        case membershipBenefitCode = "MembershipBenefitCode"
        case membershipBenefitName = "MembershipBenefitName"
        case effectiveDiscountPercent = "EffectiveDiscountPercent"
        case effectiveBenefitName = "EffectiveBenefitName"
        case effectiveBenefitSource = "EffectiveBenefitSource"
        case discountPolicy = "DiscountPolicy"
        case effectiveMembershipLevel = "EffectiveMembershipLevel"
        case promoMarkEnabled = "PromoMarkEnabled"
        case promoMarkDiscountPercent = "PromoMarkDiscountPercent"
        case promoMarkName = "PromoMarkName"
    }
}

struct PixaLocalPrice: Sendable {
    let points: Int
    let originalPoints: Int
    let savedPoints: Int
    let effectiveDiscountPercent: Decimal
    let effectiveBenefitName: String?
    let effectiveBenefitSource: String?
    let promoMarkApplied: Bool
}

enum PixaLocalPricingCalculator {
    static func template(
        snapshot: PixaPricingRulesSnapshot,
        basePoints: Int,
        defaultResolution: String?,
        resolution: String,
        selectedModelKey: String = "",
        fallbackResolutionMultiplier: Decimal = 1,
        fallbackModelMultiplier: Decimal = 1,
        promoMarkEnabled: Bool = false
    ) -> PixaLocalPrice {
        let usesDefaultResolution = defaultResolution?.nilIfEmpty == nil
            || defaultResolution?.caseInsensitiveCompare(resolution) == .orderedSame
        let resolutionMultiplier = usesDefaultResolution
            ? Decimal(1)
            : decimal(
                value(for: resolution, in: snapshot.imageResolutionMultipliers),
                fallback: max(1, fallbackResolutionMultiplier)
            )
        var raw = Decimal(basePoints > 0 ? basePoints : 150)
        raw *= resolutionMultiplier
        raw *= max(
            1,
            decimal(
                value(for: selectedModelKey, in: snapshot.imageModelMultipliers),
                fallback: max(1, fallbackModelMultiplier)
            )
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
        return PixaLocalPrice(
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
            promoMarkApplied: promoMarkApplied
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

    private static func discounted(_ points: Int, percent: Decimal) -> Int {
        guard percent > 0 else { return points }
        return max(1, ceiling(Decimal(points) * (100 - min(80, percent)) / 100))
    }

    private static func ceiling(_ value: Decimal) -> Int {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 0, .up)
        return NSDecimalNumber(decimal: output).intValue
    }
}

@MainActor
@Observable
final class PixaPricingRulesStore {
    private let api = APIClient()
    private(set) var rules: PixaPricingRulesSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var loadingTask: Task<PixaPricingRulesSnapshot, Error>?
    private var loadingID: UUID?
    private var loadingUserID: String?

    func load(
        userID: String?,
        accessToken: String?,
        force: Bool = false
    ) async {
        guard let userID, let accessToken else {
            reset()
            return
        }
        let cacheKey = Self.cacheKey(userID: userID)
        if rules == nil,
           let cachedData = await PixaResponseCache.shared.read(key: cacheKey),
           let cached = try? JSONDecoder().decode(PixaPricingRulesSnapshot.self, from: cachedData) {
            rules = cached
            errorMessage = nil
        }

        if let loadingTask, loadingUserID == userID, let loadingID {
            await finishLoading(
                loadingTask,
                id: loadingID,
                userID: userID,
                cacheKey: cacheKey
            )
            return
        }
        if rules != nil, !force { return }

        loadingTask?.cancel()
        let requestID = UUID()
        let requestTask = Task<PixaPricingRulesSnapshot, Error> {
            try await api.get(
                "/api/ais/billing/pricing-snapshot",
                query: [URLQueryItem(name: "mediaType", value: "image")],
                token: accessToken
            )
        }
        loadingTask = requestTask
        loadingID = requestID
        loadingUserID = userID
        isLoading = true
        await finishLoading(
            requestTask,
            id: requestID,
            userID: userID,
            cacheKey: cacheKey
        )
    }

    private func finishLoading(
        _ task: Task<PixaPricingRulesSnapshot, Error>,
        id: UUID,
        userID: String,
        cacheKey: String
    ) async {
        do {
            let latest = try await task.value
            guard loadingID == id, loadingUserID == userID else { return }
            rules = latest
            errorMessage = nil
            if let data = try? JSONEncoder().encode(latest) {
                await PixaResponseCache.shared.write(data, key: cacheKey)
            }
        } catch {
            guard loadingID == id, loadingUserID == userID else { return }
            errorMessage = error.localizedDescription
        }
        guard loadingID == id, loadingUserID == userID else { return }
        loadingTask = nil
        loadingID = nil
        loadingUserID = nil
        isLoading = false
    }

    func reset() {
        loadingTask?.cancel()
        loadingTask = nil
        loadingID = nil
        loadingUserID = nil
        rules = nil
        isLoading = false
        errorMessage = nil
    }

    private static func cacheKey(userID: String) -> String {
        "pricing-rules-image|user:\(userID)"
    }
}
