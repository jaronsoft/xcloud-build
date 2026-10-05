import Observation
import StoreKit
import SwiftUI
import UIKit

struct PixaRechargePackage: Decodable, Identifiable, Sendable {
    let packageKey: String?
    let appleProductId: String?
    let iosEnabled: Bool
    let regions: [String]
    let sort: Int
    let ruleVersion: String?
    let amount: Decimal
    let points: Int

    var id: String { packageKey ?? appleProductId ?? "\(amount)-\(points)" }

    private enum CodingKeys: String, CodingKey {
        case packageKey, appleProductId, iosEnabled, regions, sort, ruleVersion, amount, points
        case packageKeyUpper = "PackageKey"
        case appleProductIdUpper = "AppleProductId"
        case iosEnabledUpper = "IosEnabled"
        case regionsUpper = "Regions"
        case sortUpper = "Sort"
        case ruleVersionUpper = "RuleVersion"
        case amountUpper = "Amount"
        case pointsUpper = "Points"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        packageKey = try box.decodeIfPresent(String.self, forKey: .packageKey)
            ?? box.decodeIfPresent(String.self, forKey: .packageKeyUpper)
        appleProductId = try box.decodeIfPresent(String.self, forKey: .appleProductId)
            ?? box.decodeIfPresent(String.self, forKey: .appleProductIdUpper)
        iosEnabled = try box.decodeIfPresent(Bool.self, forKey: .iosEnabled)
            ?? box.decodeIfPresent(Bool.self, forKey: .iosEnabledUpper) ?? false
        regions = try box.decodeIfPresent([String].self, forKey: .regions)
            ?? box.decodeIfPresent([String].self, forKey: .regionsUpper) ?? []
        sort = try box.decodeIfPresent(Int.self, forKey: .sort)
            ?? box.decodeIfPresent(Int.self, forKey: .sortUpper) ?? 0
        ruleVersion = try box.decodeIfPresent(String.self, forKey: .ruleVersion)
            ?? box.decodeIfPresent(String.self, forKey: .ruleVersionUpper)
        amount = try box.decodeIfPresent(Decimal.self, forKey: .amount)
            ?? box.decodeIfPresent(Decimal.self, forKey: .amountUpper) ?? 0
        points = try box.decodeIfPresent(Int.self, forKey: .points)
            ?? box.decodeIfPresent(Int.self, forKey: .pointsUpper) ?? 0
    }
}

struct PixaSubscriptionOffer: Decodable, Identifiable, Sendable {
    let planCode: String
    let name: String
    let nameZh: String?
    let nameEn: String?
    let productId: String
    let discountPercent: Decimal
    let monthlyPoints: Int
    let sort: Int

    var id: String { productId }

    private enum CodingKeys: String, CodingKey {
        case planCode, name, nameZh, nameEn, productId, discountPercent, monthlyPoints, sort
        case planCodeUpper = "PlanCode", nameUpper = "Name", nameZhUpper = "NameZh", nameEnUpper = "NameEn"
        case productIdUpper = "ProductId"
        case discountPercentUpper = "DiscountPercent", monthlyPointsUpper = "MonthlyPoints", sortUpper = "Sort"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        planCode = try box.decodeIfPresent(String.self, forKey: .planCode) ?? box.decode(String.self, forKey: .planCodeUpper)
        name = try box.decodeIfPresent(String.self, forKey: .name) ?? box.decode(String.self, forKey: .nameUpper)
        nameZh = try box.decodeIfPresent(String.self, forKey: .nameZh)
            ?? box.decodeIfPresent(String.self, forKey: .nameZhUpper)
        nameEn = try box.decodeIfPresent(String.self, forKey: .nameEn)
            ?? box.decodeIfPresent(String.self, forKey: .nameEnUpper)
        productId = try box.decodeIfPresent(String.self, forKey: .productId) ?? box.decode(String.self, forKey: .productIdUpper)
        discountPercent = try box.decodeIfPresent(Decimal.self, forKey: .discountPercent)
            ?? box.decodeIfPresent(Decimal.self, forKey: .discountPercentUpper) ?? 0
        monthlyPoints = try box.decodeIfPresent(Int.self, forKey: .monthlyPoints)
            ?? box.decodeIfPresent(Int.self, forKey: .monthlyPointsUpper) ?? 0
        sort = try box.decodeIfPresent(Int.self, forKey: .sort)
            ?? box.decodeIfPresent(Int.self, forKey: .sortUpper) ?? 0
    }

    var localizedName: String {
        AppLanguage.value(zh: nameZh, en: nameEn).nilIfEmpty ?? name
    }
}

private struct PixaRechargePricing: Decodable, Sendable {
    let countryCode: String
    let currency: String
    let currencySymbol: String
    let presetPackages: [PixaRechargePackage]
    let subscriptions: [PixaSubscriptionOffer]

    private enum CodingKeys: String, CodingKey {
        case countryCode, currency, currencySymbol, presetPackages, subscriptions
        case countryCodeUpper = "CountryCode"
        case currencyUpper = "Currency"
        case currencySymbolUpper = "CurrencySymbol"
        case presetPackagesUpper = "PresetPackages"
        case subscriptionsUpper = "Subscriptions"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        countryCode = try box.decodeIfPresent(String.self, forKey: .countryCode)
            ?? box.decode(String.self, forKey: .countryCodeUpper)
        currency = try box.decodeIfPresent(String.self, forKey: .currency)
            ?? box.decode(String.self, forKey: .currencyUpper)
        currencySymbol = try box.decodeIfPresent(String.self, forKey: .currencySymbol)
            ?? box.decode(String.self, forKey: .currencySymbolUpper)
        presetPackages = try box.decodeIfPresent([PixaRechargePackage].self, forKey: .presetPackages)
            ?? box.decodeIfPresent([PixaRechargePackage].self, forKey: .presetPackagesUpper) ?? []
        subscriptions = try box.decodeIfPresent([PixaSubscriptionOffer].self, forKey: .subscriptions)
            ?? box.decodeIfPresent([PixaSubscriptionOffer].self, forKey: .subscriptionsUpper) ?? []
    }
}

private struct PixaIOSCapabilities: Decodable, Sendable {
    let storeKitEnabled: Bool
    let allowedRegions: [String]
}

private struct PixaCommerceCapabilities: Decodable, Sendable {
    let ios: PixaIOSCapabilities?
}

private struct PixaStoreKitVerificationRequest: Encodable {
    let signedTransaction: String
    let appCode: String
    let packageKey: String?
    let ruleVersion: String?
}

private struct PixaStoreKitVerificationResponse: Decodable {
    let credited: Bool
}

private struct PixaSubscriptionStatus: Decodable {
    let appAccountToken: String
    let planCode: String?
    let autoRenew: Bool
    let expiresAt: String?
    let subscriptionPoints: Int
    let permanentPoints: Int
    let pointDebt: Int
    let effectiveDiscountPercent: Decimal
    let effectiveBenefitName: String?
    let effectiveBenefitSource: String?
    let rechargeMembershipDiscountPercent: Decimal?
    let rechargeMembershipBenefitName: String?
    let subscriptionDiscountPercent: Decimal?
    let subscriptionBenefitName: String?
    let discountPolicy: String?

    private enum CodingKeys: String, CodingKey {
        case appAccountToken, planCode, autoRenew, expiresAt
        case subscriptionPoints, permanentPoints, pointDebt
        case effectiveDiscountPercent, effectiveBenefitName, effectiveBenefitSource
        case rechargeMembershipDiscountPercent, rechargeMembershipBenefitName
        case subscriptionDiscountPercent, subscriptionBenefitName, discountPolicy
        case appAccountTokenUpper = "AppAccountToken"
        case planCodeUpper = "PlanCode"
        case autoRenewUpper = "AutoRenew"
        case expiresAtUpper = "ExpiresAt"
        case subscriptionPointsUpper = "SubscriptionPoints"
        case permanentPointsUpper = "PermanentPoints"
        case pointDebtUpper = "PointDebt"
        case effectiveDiscountPercentUpper = "EffectiveDiscountPercent"
        case effectiveBenefitNameUpper = "EffectiveBenefitName"
        case effectiveBenefitSourceUpper = "EffectiveBenefitSource"
        case rechargeMembershipDiscountPercentUpper = "RechargeMembershipDiscountPercent"
        case rechargeMembershipBenefitNameUpper = "RechargeMembershipBenefitName"
        case subscriptionDiscountPercentUpper = "SubscriptionDiscountPercent"
        case subscriptionBenefitNameUpper = "SubscriptionBenefitName"
        case discountPolicyUpper = "DiscountPolicy"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        appAccountToken = try box.decodeIfPresent(String.self, forKey: .appAccountToken)
            ?? box.decode(String.self, forKey: .appAccountTokenUpper)
        planCode = try box.decodeIfPresent(String.self, forKey: .planCode)
            ?? box.decodeIfPresent(String.self, forKey: .planCodeUpper)
        autoRenew = try box.decodeIfPresent(Bool.self, forKey: .autoRenew)
            ?? box.decodeIfPresent(Bool.self, forKey: .autoRenewUpper) ?? false
        expiresAt = try box.decodeIfPresent(String.self, forKey: .expiresAt)
            ?? box.decodeIfPresent(String.self, forKey: .expiresAtUpper)
        subscriptionPoints = try box.decodeIfPresent(Int.self, forKey: .subscriptionPoints)
            ?? box.decodeIfPresent(Int.self, forKey: .subscriptionPointsUpper) ?? 0
        permanentPoints = try box.decodeIfPresent(Int.self, forKey: .permanentPoints)
            ?? box.decodeIfPresent(Int.self, forKey: .permanentPointsUpper) ?? 0
        pointDebt = try box.decodeIfPresent(Int.self, forKey: .pointDebt)
            ?? box.decodeIfPresent(Int.self, forKey: .pointDebtUpper) ?? 0
        effectiveDiscountPercent = try box.decodeIfPresent(Decimal.self, forKey: .effectiveDiscountPercent)
            ?? box.decodeIfPresent(Decimal.self, forKey: .effectiveDiscountPercentUpper) ?? 0
        effectiveBenefitName = try box.decodeIfPresent(String.self, forKey: .effectiveBenefitName)
            ?? box.decodeIfPresent(String.self, forKey: .effectiveBenefitNameUpper)
        effectiveBenefitSource = try box.decodeIfPresent(String.self, forKey: .effectiveBenefitSource)
            ?? box.decodeIfPresent(String.self, forKey: .effectiveBenefitSourceUpper)
        rechargeMembershipDiscountPercent = try box.decodeIfPresent(Decimal.self, forKey: .rechargeMembershipDiscountPercent)
            ?? box.decodeIfPresent(Decimal.self, forKey: .rechargeMembershipDiscountPercentUpper)
        rechargeMembershipBenefitName = try box.decodeIfPresent(String.self, forKey: .rechargeMembershipBenefitName)
            ?? box.decodeIfPresent(String.self, forKey: .rechargeMembershipBenefitNameUpper)
        subscriptionDiscountPercent = try box.decodeIfPresent(Decimal.self, forKey: .subscriptionDiscountPercent)
            ?? box.decodeIfPresent(Decimal.self, forKey: .subscriptionDiscountPercentUpper)
        subscriptionBenefitName = try box.decodeIfPresent(String.self, forKey: .subscriptionBenefitName)
            ?? box.decodeIfPresent(String.self, forKey: .subscriptionBenefitNameUpper)
        discountPolicy = try box.decodeIfPresent(String.self, forKey: .discountPolicy)
            ?? box.decodeIfPresent(String.self, forKey: .discountPolicyUpper)
    }
}

/// 登录、启动和回到前台时同步所有未完成与有效订阅交易，防止断网或跨设备后漏单。
@MainActor
@Observable
final class PixaStoreKitTransactionSync {
    private let api = APIClient()
    private var updatesTask: Task<Void, Never>?

    deinit { MainActor.assumeIsolated { updatesTask?.cancel() } }

    func start(session: SessionStore) {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await result in StoreKit.Transaction.updates {
                try? await verifyAndFinish(result, session: session)
            }
        }
    }

    func sync(session: SessionStore) async {
        guard session.isAuthenticated else { return }
        for await result in StoreKit.Transaction.unfinished {
            try? await verifyAndFinish(result, session: session)
        }
        for await result in StoreKit.Transaction.currentEntitlements {
            try? await verifyAndFinish(result, session: session)
        }
    }

    private func verifyAndFinish(
        _ result: VerificationResult<StoreKit.Transaction>,
        session: SessionStore
    ) async throws {
        guard case let .verified(transaction) = result,
              let token = await session.validAccessToken() else { return }
        let response: PixaStoreKitVerificationResponse = try await api.post(
            "/api/ais/storekit/transactions/verify",
            body: PixaStoreKitVerificationRequest(
                signedTransaction: result.jwsRepresentation,
                appCode: "pixarivo",
                packageKey: nil,
                ruleVersion: nil
            ),
            token: token,
            headers: ["Idempotency-Key": String(transaction.id)]
        )
        guard response.credited else { return }
        await transaction.finish()
        NotificationCenter.default.post(name: .pixaBalanceDidChange, object: nil)
    }
}

@MainActor
@Observable
private final class RechargeStoreKitViewModel {
    private let api = APIClient()
    private(set) var products: [Product] = []
    private(set) var packagesByProductID: [String: PixaRechargePackage] = [:]
    private(set) var subscriptionsByProductID: [String: PixaSubscriptionOffer] = [:]
    private(set) var subscriptionProducts: [Product] = []
    private(set) var subscriptionStatus: PixaSubscriptionStatus?
    private(set) var countryCode = ""
    private(set) var currency = ""
    private(set) var isLoading = false
    private(set) var purchasingProductID: String?
    private(set) var isStoreKitEnabled = false
    private(set) var message: String?
    private var updatesTask: Task<Void, Never>?

    deinit {
        MainActor.assumeIsolated { updatesTask?.cancel() }
    }

    func load(session: SessionStore) async {
        guard let token = await session.validAccessToken() else {
            message = AppLanguage.localized("storekit.signin_required")
            return
        }
        isLoading = true
        message = nil
        products = []
        subscriptionProducts = []
        packagesByProductID = [:]
        subscriptionsByProductID = [:]
        subscriptionStatus = nil
        countryCode = ""
        currency = ""
        isStoreKitEnabled = false
        defer { isLoading = false }

        do {
            let storefrontRegion = await Storefront.current?.countryCode
            let requestedRegion = storefrontRegion
                ?? session.user?.countryCode
                ?? Locale.current.region?.identifier
                ?? "US"
            async let capabilitiesRequest: PixaCommerceCapabilities = api.get(
                "/api/ais/capabilities",
                query: [URLQueryItem(name: "appCode", value: "pixarivo")]
            )
            async let pricingRequest: PixaRechargePricing = api.get(
                "/api/ais/recharge/getpricing",
                query: [
                    URLQueryItem(name: "countryCode", value: requestedRegion),
                    URLQueryItem(name: "appCode", value: "pixarivo")
                ],
                token: token
            )
            async let statusRequest: PixaSubscriptionStatus? = try? api.get(
                "/api/ais/storekit/subscription/status",
                token: token
            )
            let (capabilities, pricing, status) = try await (capabilitiesRequest, pricingRequest, statusRequest)
            subscriptionStatus = status
            countryCode = pricing.countryCode
            currency = pricing.currency
            isStoreKitEnabled = capabilities.ios?.storeKitEnabled == true

            guard isStoreKitEnabled else {
                products = []
                message = AppLanguage.localized("storekit.disabled_by_system")
                return
            }
            if let allowed = capabilities.ios?.allowedRegions,
               !allowed.isEmpty,
               !allowed.contains(where: { $0.caseInsensitiveCompare(pricing.countryCode) == .orderedSame }) {
                products = []
                message = AppLanguage.localized("storekit.unavailable")
                return
            }
            let eligible = pricing.presetPackages.filter { package in
                package.iosEnabled
                    && package.points > 0
                    && package.appleProductId?.isEmpty == false
                    && (package.regions.isEmpty || package.regions.contains {
                        $0.caseInsensitiveCompare(pricing.countryCode) == .orderedSame
                    })
            }
            packagesByProductID = Dictionary(uniqueKeysWithValues: eligible.compactMap { package in
                package.appleProductId.map { ($0, package) }
            })
            subscriptionsByProductID = Dictionary(uniqueKeysWithValues: pricing.subscriptions.map { ($0.productId, $0) })
            let requestedProductIDs = Array(
                Set(packagesByProductID.keys).union(subscriptionsByProductID.keys)
            ).sorted()
            guard !requestedProductIDs.isEmpty else {
                NetworkDiagnosticsStore.shared.recordSystemLog(
                    tag: "STOREKIT_CONFIG",
                    "storefront=\(storefrontRegion ?? "unknown") requestedRegion=\(requestedRegion) "
                        + "pricingRegion=\(pricing.countryCode) requestedProducts=0"
                )
                message = AppLanguage.localized("storekit.no_packages")
                return
            }

            let allProducts = try await loadProducts(
                productIDs: requestedProductIDs,
                storefrontRegion: storefrontRegion,
                requestedRegion: requestedRegion,
                pricingRegion: pricing.countryCode
            )
            products = allProducts.filter { packagesByProductID[$0.id] != nil }.sorted {
                (packagesByProductID[$0.id]?.sort ?? 0) < (packagesByProductID[$1.id]?.sort ?? 0)
            }
            subscriptionProducts = allProducts.filter { subscriptionsByProductID[$0.id] != nil }.sorted {
                (subscriptionsByProductID[$0.id]?.sort ?? 0) < (subscriptionsByProductID[$1.id]?.sort ?? 0)
            }
            if products.isEmpty && subscriptionProducts.isEmpty {
                message = AppLanguage.localized("storekit.catalog_unavailable")
            }
            startTransactionUpdates(session: session)
            await recoverTransactions(session: session)
        } catch {
            NetworkDiagnosticsStore.shared.recordSystemLog(
                tag: "STOREKIT_LOAD",
                error.localizedDescription
            )
            message = AppLanguage.localized("storekit.load_failed")
        }
    }

    /// StoreKit 可能在商品刚发布或 storefront 切换后短暂返回不完整目录，最后逐个商品补查，避免单个目录项异常影响其他可售商品。
    private func loadProducts(
        productIDs: [String],
        storefrontRegion: String?,
        requestedRegion: String,
        pricingRegion: String
    ) async throws -> [Product] {
        let initialProducts = try await Product.products(for: productIDs)
        let initialProductIDs = Set(initialProducts.map(\.id))
        let missingProductIDs = productIDs.filter { !initialProductIDs.contains($0) }

        recordCatalogDiagnostic(
            attempt: 1,
            storefrontRegion: storefrontRegion,
            requestedRegion: requestedRegion,
            pricingRegion: pricingRegion,
            requestedProductIDs: productIDs,
            returnedProductIDs: initialProducts.map(\.id),
            missingProductIDs: missingProductIDs
        )
        guard !missingProductIDs.isEmpty else { return initialProducts }

        try await Task.sleep(for: .milliseconds(800))
        let retryProducts = try await Product.products(for: missingProductIDs)
        var productsByID = Dictionary(uniqueKeysWithValues: initialProducts.map { ($0.id, $0) })
        retryProducts.forEach { productsByID[$0.id] = $0 }
        let mergedProducts = productIDs.compactMap { productsByID[$0] }
        let mergedProductIDs = Set(mergedProducts.map(\.id))

        recordCatalogDiagnostic(
            attempt: 2,
            storefrontRegion: storefrontRegion,
            requestedRegion: requestedRegion,
            pricingRegion: pricingRegion,
            requestedProductIDs: missingProductIDs,
            returnedProductIDs: retryProducts.map(\.id),
            missingProductIDs: productIDs.filter { !mergedProductIDs.contains($0) }
        )
        let individuallyMissingProductIDs = productIDs.filter { !mergedProductIDs.contains($0) }
        guard !individuallyMissingProductIDs.isEmpty else { return mergedProducts }

        var individuallyLoadedProducts = productsByID
        for productID in individuallyMissingProductIDs {
            // 单个商品查询失败不影响其他已成功返回的商品，最终缺失清单会写入诊断日志。
            let products = try? await Product.products(for: [productID])
            guard let product = products?.first else { continue }
            individuallyLoadedProducts[product.id] = product
        }
        let individuallyMergedProducts = productIDs.compactMap { individuallyLoadedProducts[$0] }
        let individuallyMergedProductIDs = Set(individuallyMergedProducts.map(\.id))
        recordCatalogDiagnostic(
            attempt: 3,
            storefrontRegion: storefrontRegion,
            requestedRegion: requestedRegion,
            pricingRegion: pricingRegion,
            requestedProductIDs: individuallyMissingProductIDs,
            returnedProductIDs: individuallyMissingProductIDs.filter { individuallyMergedProductIDs.contains($0) },
            missingProductIDs: productIDs.filter { !individuallyMergedProductIDs.contains($0) }
        )
        return individuallyMergedProducts
    }

    private func recordCatalogDiagnostic(
        attempt: Int,
        storefrontRegion: String?,
        requestedRegion: String,
        pricingRegion: String,
        requestedProductIDs: [String],
        returnedProductIDs: [String],
        missingProductIDs: [String]
    ) {
        NetworkDiagnosticsStore.shared.recordSystemLog(
            tag: "STOREKIT_CATALOG",
            "attempt=\(attempt) storefront=\(storefrontRegion ?? "unknown") "
                + "requestedRegion=\(requestedRegion) pricingRegion=\(pricingRegion) "
                + "requested=[\(requestedProductIDs.sorted().joined(separator: ","))] "
                + "returned=[\(returnedProductIDs.sorted().joined(separator: ","))] "
                + "missing=[\(missingProductIDs.sorted().joined(separator: ","))]"
        )
    }

    func purchase(_ product: Product, session: SessionStore) async {
        guard purchasingProductID == nil else { return }
        purchasingProductID = product.id
        message = nil
        defer { purchasingProductID = nil }
        do {
            guard let tokenString = subscriptionStatus?.appAccountToken,
                  let appAccountToken = UUID(uuidString: tokenString) else {
                throw APIError.rejected(AppLanguage.localized("storekit.unavailable"))
            }
            switch try await product.purchase(options: [.appAccountToken(appAccountToken)]) {
            case let .success(result):
                try await deliver(result, session: session)
            case .pending:
                message = AppLanguage.localized("storekit.pending")
            case .userCancelled:
                break
            @unknown default:
                message = AppLanguage.localized("storekit.unavailable")
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func startTransactionUpdates(session: SessionStore) {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled,
                      case let .verified(transaction) = result,
                      packagesByProductID[transaction.productID] != nil
                        || subscriptionsByProductID[transaction.productID] != nil else { continue }
                try? await deliver(result, session: session)
            }
        }
    }

    func restore(session: SessionStore) async {
        do {
            try await AppStore.sync()
            await recoverTransactions(session: session)
            await load(session: session)
            message = AppLanguage.localized("storekit.restore_success")
        } catch {
            message = error.localizedDescription
        }
    }

    func manageSubscription() async {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        do { try await AppStore.showManageSubscriptions(in: scene) }
        catch { message = error.localizedDescription }
    }

    private func recoverTransactions(session: SessionStore) async {
        for await result in StoreKit.Transaction.unfinished {
            try? await deliver(result, session: session)
        }
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  subscriptionsByProductID[transaction.productID] != nil else { continue }
            try? await deliver(result, session: session)
        }
    }

    private func deliver(
        _ result: VerificationResult<StoreKit.Transaction>,
        session: SessionStore
    ) async throws {
        guard case let .verified(transaction) = result,
              let token = await session.validAccessToken() else {
            throw APIError.rejected(AppLanguage.localized("storekit.unverified"))
        }
        let package = packagesByProductID[transaction.productID]
        let response: PixaStoreKitVerificationResponse = try await api.post(
            "/api/ais/storekit/transactions/verify",
            body: PixaStoreKitVerificationRequest(
                signedTransaction: result.jwsRepresentation,
                appCode: "pixarivo",
                packageKey: package?.packageKey,
                ruleVersion: package?.ruleVersion
            ),
            token: token,
            headers: ["Idempotency-Key": String(transaction.id)]
        )
        guard response.credited else { throw APIError.rejected(AppLanguage.localized("storekit.pending")) }
        await transaction.finish()
        message = AppLanguage.localized("storekit.success")
        NotificationCenter.default.post(name: .pixaBalanceDidChange, object: nil)
    }
}

#if DEBUG
/// 仅用于生成 App Store Connect 内购审核截图，不参与 Release 构建。
struct PixaIAPReviewScreenshotView: View {
    struct ReviewPackage: Identifiable {
        let id: String
        let name: String
        let points: Int
        let price: String
    }

    let region: String

    private var currency: String { region == "CN" ? "CNY" : "USD" }
    private var packages: [ReviewPackage] {
        if region == "CN" {
            return [
                ReviewPackage(id: "cn-starter", name: "1000 积分", points: 1_000, price: "¥12.00"),
                ReviewPackage(id: "cn-plus", name: "5500 积分", points: 5_500, price: "¥48.00"),
                ReviewPackage(id: "cn-pro", name: "12000 积分", points: 12_000, price: "¥98.00")
            ]
        }
        return [
            ReviewPackage(id: "us-starter", name: "1,000 Points", points: 1_000, price: "$4.99"),
            ReviewPackage(id: "us-plus", name: "4,500 Points", points: 4_500, price: "$19.99"),
            ReviewPackage(id: "us-pro", name: "12,000 Points", points: 12_000, price: "$49.99")
        ]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("points.center.title", selection: .constant(PointsCenterView.Tab.recharge)) {
                    Text("points.center.subscription").tag(PointsCenterView.Tab.subscription)
                    Text("points.center.recharge").tag(PointsCenterView.Tab.recharge)
                    Text("points.center.code").tag(PointsCenterView.Tab.code)
                    Text("points.center.invitation").tag(PointsCenterView.Tab.invitation)
                }
                .pickerStyle(.segmented)
                .disabled(true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                List {
                    Section("storekit.region_pricing") {
                        LabeledContent("storekit.region", value: region)
                        LabeledContent("storekit.currency", value: currency)
                        Text("storekit.system_price_hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        ForEach(packages) { package in
                            HStack(spacing: 14) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(PixaTheme.accent)
                                    .frame(width: 38, height: 38)
                                    .background(
                                        PixaTheme.accent.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(package.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(PixaTheme.ink)
                                    Text(String.localizedStringWithFormat(
                                        AppLanguage.localized("storekit.points_format"),
                                        package.points
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(package.price)
                                    .font(.body.bold())
                                    .foregroundStyle(PixaTheme.accent)
                            }
                            .padding(.vertical, 5)
                        }
                    } header: {
                        Text("storekit.packages")
                    } footer: {
                        Text("storekit.review_purchase_hint")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(PixaTheme.paper.ignoresSafeArea())
            .navigationTitle("points.center.title")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif

struct RechargeStoreKitView: View {
    enum Mode { case subscription, recharge }

    @Environment(SessionStore.self) private var session
    @State private var model = RechargeStoreKitViewModel()
    let mode: Mode

    init(mode: Mode = .recharge) {
        self.mode = mode
    }

    private func discountValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private func planDiscountComparison(_ offer: PixaSubscriptionOffer) -> String {
        let membershipDiscount = model.subscriptionStatus?.rechargeMembershipDiscountPercent ?? 0
        let planDiscount = offer.discountPercent
        guard membershipDiscount > 0 else {
            return String.localizedStringWithFormat(
                AppLanguage.localized("storekit.plan_discount_only_format"),
                discountValue(planDiscount)
            )
        }

        let membershipName = localizedBenefitName(
            model.subscriptionStatus?.rechargeMembershipBenefitName
        )
        if membershipDiscount > planDiscount {
            return String.localizedStringWithFormat(
                AppLanguage.localized("storekit.member_discount_higher_format"),
                membershipName,
                discountValue(membershipDiscount),
                discountValue(planDiscount),
                discountValue(membershipDiscount)
            )
        }
        if planDiscount > membershipDiscount {
            return String.localizedStringWithFormat(
                AppLanguage.localized("storekit.plan_discount_higher_format"),
                membershipName,
                discountValue(membershipDiscount),
                discountValue(planDiscount)
            )
        }
        return String.localizedStringWithFormat(
            AppLanguage.localized("storekit.discount_equal_format"),
            membershipName,
            discountValue(planDiscount),
            discountValue(planDiscount)
        )
    }

    /// 服务端会按当前界面语言返回套餐名称；仅在名称缺失时才使用稳定标识或 StoreKit 元数据兜底。
    private func localizedPlanName(
        code: String?,
        configuredName: String? = nil,
        productID: String? = nil,
        storeKitName: String? = nil
    ) -> String {
        if let configuredName = configuredName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty {
            return configuredName
        }
        let value = (code ?? productID ?? "").lowercased()
        if value.contains("advanced") || value.contains("pro") {
            return AppLanguage.localized("storekit.plan.pro")
        }
        if value.contains("basic") || value.contains("plus") {
            return AppLanguage.localized("storekit.plan.plus")
        }
        return storeKitName?.nilIfEmpty
            ?? code?.nilIfEmpty
            ?? AppLanguage.localized("storekit.plan.basic")
    }

    private func localizedBenefitName(_ value: String?) -> String {
        guard let value = value?.nilIfEmpty else {
            return AppLanguage.localized("storekit.membership_default")
        }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "normal", "standard", "普通", "普通会员", "基础会员":
            return AppLanguage.localized("storekit.membership.standard")
        case "student", "学生", "学生会员", "学生权益":
            return AppLanguage.localized("storekit.membership.student")
        case "enterprise", "企业", "企业会员", "企业权益":
            return AppLanguage.localized("storekit.membership.enterprise")
        case "vip": return "VIP"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "max": return "Max"
        default: return value
        }
    }

    private func subscriptionPeriod(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return AppLanguage.localized("storekit.subscription_period_unknown")
        }
        let isSinglePeriod = period.value == 1
        let key: String
        switch period.unit {
        case .day:
            key = isSinglePeriod ? "storekit.subscription_period_day" : "storekit.subscription_period_days"
        case .week:
            key = isSinglePeriod ? "storekit.subscription_period_week" : "storekit.subscription_period_weeks"
        case .month:
            key = isSinglePeriod ? "storekit.subscription_period_month" : "storekit.subscription_period_months"
        case .year:
            key = isSinglePeriod ? "storekit.subscription_period_year" : "storekit.subscription_period_years"
        @unknown default:
            key = "storekit.subscription_period_unknown"
        }
        guard key != "storekit.subscription_period_unknown" else {
            return AppLanguage.localized(key)
        }
        return String.localizedStringWithFormat(
            AppLanguage.localized(key),
            period.value
        )
    }

    var body: some View {
        List {
            if model.isLoading && model.products.isEmpty && model.subscriptionProducts.isEmpty {
                Section {
                    PixaLoadingStateView(
                        title: "loading.store.title",
                        message: "loading.store.message",
                        minHeight: 160
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            if mode == .subscription {
              if let status = model.subscriptionStatus, let plan = status.planCode {
                Section("storekit.account_overview") {
                    subscriptionOverview(status, plan: plan)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
              }
              if !model.subscriptionProducts.isEmpty {
                Section("storekit.subscription_plans") {
                    VStack(spacing: 12) {
                        ForEach(model.subscriptionProducts, id: \.id) { product in
                            subscriptionPlanCard(product)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
              }
              Section {
                subscriptionActions
                Text("storekit.subscription_expiry_hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                HStack(spacing: 18) {
                    Link("storekit.privacy_policy", destination: AppConfiguration.privacyURL)
                    Link("storekit.subscription_terms", destination: AppConfiguration.subscriptionTermsURL)
                    Link("storekit.terms_of_use", destination: AppConfiguration.standardEULAURL)
                }
                .font(.caption)
              }
              if let message = model.message {
                  Text(message).font(.footnote).foregroundStyle(.secondary)
              }
            }
            if mode == .recharge && !model.countryCode.isEmpty {
                Section("storekit.region_pricing") {
                    LabeledContent("storekit.region", value: model.countryCode)
                    LabeledContent("storekit.currency", value: model.currency)
                    Text("storekit.system_price_hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if mode == .recharge {
              Section("storekit.packages") {
                ForEach(model.products, id: \.id) { product in
                    Button {
                        Task { await model.purchase(product, session: session) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(PixaTheme.accent)
                                .frame(width: 34, height: 34)
                                .background(PixaTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 4) {
                                if let points = model.packagesByProductID[product.id]?.points {
                                    Text(String.localizedStringWithFormat(
                                        AppLanguage.localized("storekit.points_package_name"),
                                        points
                                    ))
                                    .foregroundStyle(PixaTheme.ink)
                                    Text(String.localizedStringWithFormat(AppLanguage.localized("storekit.points_format"), points))
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(product.displayName).foregroundStyle(PixaTheme.ink)
                                }
                            }
                            Spacer()
                            Text(product.displayPrice).bold().foregroundStyle(PixaTheme.accent)
                        }
                    }
                    .disabled(model.purchasingProductID != nil)
                }
                if let message = model.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
              }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PixaTheme.paper)
        .task { await model.load(session: session) }
    }

    private func subscriptionOverview(_ status: PixaSubscriptionStatus, plan: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("storekit.current_plan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(localizedPlanName(code: plan))
                        .font(.title3.bold())
                        .foregroundStyle(PixaTheme.ink)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title3.bold())
                    .foregroundStyle(PixaTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(PixaTheme.accent.opacity(0.1), in: Circle())
            }

            HStack(spacing: 10) {
                subscriptionMetric(
                    title: "storekit.subscription_points",
                    value: status.subscriptionPoints.formatted(),
                    icon: "calendar"
                )
                subscriptionMetric(
                    title: "storekit.permanent_points",
                    value: status.permanentPoints.formatted(),
                    icon: "infinity"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("storekit.discount", systemImage: "percent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(String.localizedStringWithFormat(
                    AppLanguage.localized("storekit.effective_discount_format"),
                    discountValue(status.effectiveDiscountPercent),
                    localizedBenefitName(status.effectiveBenefitName)
                ))
                .font(.headline)
                .foregroundStyle(PixaTheme.accent)
                Text("storekit.discount_policy_hint")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PixaTheme.accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let expiresAt = status.expiresAt {
                LabeledContent("storekit.renews_at", value: expiresAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.9))
        }
        .shadow(color: PixaTheme.ink.opacity(0.055), radius: 16, y: 7)
    }

    private func subscriptionMetric(
        title: LocalizedStringKey,
        value: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(PixaTheme.ink)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func subscriptionPlanCard(_ product: Product) -> some View {
        Button {
            Task { await model.purchase(product, session: session) }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(localizedPlanName(
                        code: model.subscriptionsByProductID[product.id]?.planCode,
                        configuredName: model.subscriptionsByProductID[product.id]?.localizedName,
                        productID: product.id,
                        storeKitName: product.displayName
                    ))
                    .font(.headline)
                    .foregroundStyle(PixaTheme.ink)
                    Spacer()
                    Text(String.localizedStringWithFormat(
                        AppLanguage.localized("storekit.subscription_price_format"),
                        product.displayPrice,
                        subscriptionPeriod(product)
                    ))
                    .font(.subheadline.bold())
                    .foregroundStyle(PixaTheme.accent)
                }
                if let offer = model.subscriptionsByProductID[product.id] {
                    Label(
                        String.localizedStringWithFormat(
                            AppLanguage.localized("storekit.subscription_benefit_format"),
                            offer.monthlyPoints,
                            discountValue(offer.discountPercent)
                        ),
                        systemImage: "sparkles"
                    )
                    .font(.caption)
                    .foregroundStyle(PixaTheme.ink.opacity(0.72))
                    Text(planDiscountComparison(offer))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text("storekit.choose_plan")
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption.bold())
                }
                .foregroundStyle(PixaTheme.accent)
            }
            .padding(16)
            .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PixaTheme.accent.opacity(0.16))
            }
        }
        .buttonStyle(.plain)
        .disabled(model.purchasingProductID != nil)
    }

    private var subscriptionActions: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.manageSubscription() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("storekit.manage_subscription")
                        .font(.footnote.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(PixaTheme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                Task { await model.restore(session: session) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text("storekit.restore")
                        .font(.footnote.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                }
                .foregroundStyle(PixaTheme.accent)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(PixaTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(PixaTheme.accent.opacity(0.2))
                }
            }
            .buttonStyle(.plain)
        }
    }
}
