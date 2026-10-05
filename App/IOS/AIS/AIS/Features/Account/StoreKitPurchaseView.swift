import Observation
import OSLog
import StoreKit
import SwiftUI

private struct AISStoreKitVerificationRequest: Encodable {
    let signedTransaction: String
    let appCode: String
    let packageKey: String
    let ruleVersion: String?
}

struct AISStoreKitVerificationResponse: Decodable {
    let credited: Bool

    private enum CodingKeys: String, CodingKey {
        case credited
        case creditedUpper = "Credited"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        credited = try box.decodeIfPresent(Bool.self, forKey: .credited)
            ?? box.decode(Bool.self, forKey: .creditedUpper)
    }
}

struct AISStoreKitPricingResponse: Decodable {
    let countryCode: String
    let presetPackages: [AISRechargePackage]

    private enum CodingKeys: String, CodingKey {
        case countryCode, presetPackages
        case countryCodeUpper = "CountryCode"
        case presetPackagesUpper = "PresetPackages"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        countryCode = try box.decodeIfPresent(
            String.self,
            forKey: .countryCode
        ) ?? box.decode(String.self, forKey: .countryCodeUpper)
        presetPackages = try box.decodeIfPresent(
            [AISRechargePackage].self,
            forKey: .presetPackages
        ) ?? box.decodeIfPresent(
            [AISRechargePackage].self,
            forKey: .presetPackagesUpper
        ) ?? []
    }
}

private struct AISStoreKitAccountStatus: Decodable {
    let appAccountToken: String

    private enum CodingKeys: String, CodingKey {
        case appAccountToken
        case appAccountTokenUpper = "AppAccountToken"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        appAccountToken = try box.decodeIfPresent(
            String.self,
            forKey: .appAccountToken
        ) ?? box.decode(String.self, forKey: .appAccountTokenUpper)
    }
}

@MainActor
@Observable
final class StoreKitPurchaseViewModel {
    private let api = APIClient()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AIS",
        category: "StoreKitPurchase"
    )
    private(set) var products: [Product] = []
    private(set) var packagesByProductID: [String: AISRechargePackage] = [:]
    private(set) var isLoading = false
    private(set) var purchasingProductID: String?
    private(set) var message: String?
    private var appAccountToken: UUID?
    private var updatesTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?

    deinit {
        MainActor.assumeIsolated {
            updatesTask?.cancel()
            recoveryTask?.cancel()
        }
    }

    func load(
        region: String?,
        session: SessionStore
    ) async {
        products = []
        packagesByProductID = [:]
        message = nil
        appAccountToken = nil
        isLoading = true
        defer { isLoading = false }

        await AISCapabilitiesStore.shared.load()
        let capabilities = await AISCapabilitiesStore.shared.ios
        guard capabilities.storeKitEnabled else {
            message = String(localized: "storekit.unavailable")
            return
        }

        let storefrontRegion = await Storefront.current?.countryCode
        let requestedRegion = Self.requestedRegion(
            storefrontCountryCode: storefrontRegion,
            fallbackRegion: region
        )
        var loadingStage = "access-token"
        do {
            guard let accessToken = await session.validAccessToken() else {
                message = String(localized: "storekit.unavailable")
                return
            }
            loadingStage = "pricing"
            let pricing: AISStoreKitPricingResponse = try await api.get(
                "/api/ais/recharge/getpricing",
                query: [
                    URLQueryItem(name: "countryCode", value: requestedRegion),
                    URLQueryItem(name: "appCode", value: "ais")
                ],
                accessToken: accessToken
            )
            guard capabilities.allows(region: pricing.countryCode) else {
                message = String(localized: "storekit.unavailable")
                return
            }
            let eligible = Self.eligiblePackages(
                pricing.presetPackages,
                region: pricing.countryCode,
                capabilities: capabilities
            )
            guard !eligible.isEmpty else {
                recordCatalogDiagnostic(
                    attempt: 0,
                    storefrontRegion: storefrontRegion,
                    requestedRegion: requestedRegion,
                    pricingRegion: pricing.countryCode,
                    requestedProductIDs: [],
                    returnedProductIDs: [],
                    missingProductIDs: []
                )
                message = String(localized: "storekit.empty.description")
                return
            }
            packagesByProductID = Dictionary(
                uniqueKeysWithValues: eligible.compactMap { package in
                    package.appleProductId.map { ($0, package) }
                }
            )
            loadingStage = "products"
            let requestedProductIDs = packagesByProductID.keys.sorted()
            products = try await loadProducts(
                productIDs: requestedProductIDs,
                storefrontRegion: storefrontRegion,
                requestedRegion: requestedRegion,
                pricingRegion: pricing.countryCode
            ).sorted {
                (packagesByProductID[$0.id]?.sort ?? 0)
                    < (packagesByProductID[$1.id]?.sort ?? 0)
            }
            if products.isEmpty {
                message = String(localized: "storekit.empty.description")
            } else {
                startTransactionUpdates(session: session)
                startUnfinishedTransactionRecovery(session: session)
                // 商品展示不依赖账户令牌接口；预取失败时在用户购买前再次请求。
                Task { [weak self] in
                    _ = try? await self?.resolveAppAccountToken(
                        session: session
                    )
                }
            }
        } catch {
            logger.error(
                "加载失败 stage=\(loadingStage, privacy: .public) error=\(String(reflecting: error), privacy: .public)"
            )
            message = String(localized: "storekit.load_failed")
        }
    }

    static func eligiblePackages(
        _ packages: [AISRechargePackage],
        region: String?,
        capabilities: AISIOSCapabilities
    ) -> [AISRechargePackage] {
        packages.filter {
            $0.iosEnabled
                && capabilities.allows(region: region)
                && ($0.regions.isEmpty || $0.regions.contains {
                    $0.caseInsensitiveCompare(region ?? "") == .orderedSame
                })
                && !($0.appleProductId?.isEmpty ?? true)
        }
    }

    static func requestedRegion(
        storefrontCountryCode: String?,
        fallbackRegion: String?
    ) -> String {
        [storefrontCountryCode, fallbackRegion, "US"]
            .compactMap { value in
                let normalized = value?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).uppercased()
                return normalized?.isEmpty == false ? normalized : nil
            }
            .first ?? "US"
    }

    func purchase(_ product: Product, session: SessionStore) async {
        guard purchasingProductID == nil,
              let package = packagesByProductID[product.id] else { return }
        purchasingProductID = product.id
        defer { purchasingProductID = nil }
        do {
            let appAccountToken = try await resolveAppAccountToken(
                session: session
            )
            switch try await product.purchase(
                options: [.appAccountToken(appAccountToken)]
            ) {
            case let .success(result):
                try await deliver(
                    result,
                    package: package,
                    session: session
                )
            case .pending:
                message = String(localized: "storekit.pending")
            case .userCancelled:
                break
            @unknown default:
                message = String(localized: "storekit.unavailable")
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// StoreKit 目录可能在商品刚提交或 storefront 切换后短暂缺项，分批补查可避免一次空响应直接阻断审核购买链路。
    private func loadProducts(
        productIDs: [String],
        storefrontRegion: String?,
        requestedRegion: String,
        pricingRegion: String
    ) async throws -> [Product] {
        let initialProducts = try await Product.products(for: productIDs)
        let initialProductIDs = Set(initialProducts.map(\.id))
        let missingProductIDs = productIDs.filter {
            !initialProductIDs.contains($0)
        }
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
        var productsByID = Dictionary(
            uniqueKeysWithValues: initialProducts.map { ($0.id, $0) }
        )
        retryProducts.forEach { productsByID[$0.id] = $0 }
        let mergedProducts = productIDs.compactMap { productsByID[$0] }
        let mergedProductIDs = Set(mergedProducts.map(\.id))
        let individuallyMissingProductIDs = productIDs.filter {
            !mergedProductIDs.contains($0)
        }
        recordCatalogDiagnostic(
            attempt: 2,
            storefrontRegion: storefrontRegion,
            requestedRegion: requestedRegion,
            pricingRegion: pricingRegion,
            requestedProductIDs: missingProductIDs,
            returnedProductIDs: retryProducts.map(\.id),
            missingProductIDs: individuallyMissingProductIDs
        )
        guard !individuallyMissingProductIDs.isEmpty else {
            return mergedProducts
        }

        for productID in individuallyMissingProductIDs {
            // 单个商品查询失败不影响已经返回的其他积分包。
            guard let product = try? await Product.products(for: [productID]).first
            else { continue }
            productsByID[product.id] = product
        }
        let finalProducts = productIDs.compactMap { productsByID[$0] }
        let finalProductIDs = Set(finalProducts.map(\.id))
        recordCatalogDiagnostic(
            attempt: 3,
            storefrontRegion: storefrontRegion,
            requestedRegion: requestedRegion,
            pricingRegion: pricingRegion,
            requestedProductIDs: individuallyMissingProductIDs,
            returnedProductIDs: individuallyMissingProductIDs.filter {
                finalProductIDs.contains($0)
            },
            missingProductIDs: productIDs.filter {
                !finalProductIDs.contains($0)
            }
        )
        return finalProducts
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

    private func resolveAppAccountToken(
        session: SessionStore
    ) async throws -> UUID {
        if let appAccountToken { return appAccountToken }
        guard let accessToken = await session.validAccessToken() else {
            throw APIError.rejected(
                message: String(localized: "storekit.unavailable")
            )
        }
        let status: AISStoreKitAccountStatus = try await api.get(
            "/api/ais/storekit/subscription/status",
            accessToken: accessToken
        )
        guard let accountToken = UUID(uuidString: status.appAccountToken) else {
            throw APIError.rejected(
                message: String(localized: "storekit.load_failed")
            )
        }
        appAccountToken = accountToken
        return accountToken
    }

    private func startTransactionUpdates(session: SessionStore) {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled,
                      case let .verified(transaction) = result,
                      let package = packagesByProductID[transaction.productID]
                else { continue }
                // 恢复中的交易仍须由服务端确认入账，客户端不单方面 finish。
                do {
                    try await deliver(result, package: package, session: session)
                } catch {
                    message = error.localizedDescription
                }
            }
        }
    }

    private func startUnfinishedTransactionRecovery(session: SessionStore) {
        guard recoveryTask == nil else { return }
        recoveryTask = Task {
            defer { recoveryTask = nil }
            // 页面打开后主动补交未完成交易，避免错过应用启动时 StoreKit 只投递一次的更新。
            for await result in StoreKit.Transaction.unfinished {
                guard !Task.isCancelled,
                      case let .verified(transaction) = result,
                      let package = packagesByProductID[transaction.productID]
                else { continue }
                do {
                    try await deliver(result, package: package, session: session)
                } catch {
                    message = error.localizedDescription
                }
            }
        }
    }

    private func deliver(
        _ result: VerificationResult<StoreKit.Transaction>,
        package: AISRechargePackage,
        session: SessionStore
    ) async throws {
        guard case let .verified(transaction) = result else {
            throw APIError.rejected(
                message: String(localized: "storekit.unverified")
            )
        }
        guard let token = await session.validAccessToken(),
              let packageKey = package.packageKey else {
            throw APIError.rejected(
                message: String(localized: "storekit.unavailable")
            )
        }
        let response: AISStoreKitVerificationResponse = try await api.post(
            "/api/ais/storekit/transactions/verify",
            body: AISStoreKitVerificationRequest(
                signedTransaction: result.jwsRepresentation,
                appCode: "ais",
                packageKey: packageKey,
                ruleVersion: package.ruleVersion
            ),
            accessToken: token,
            headers: ["Idempotency-Key": String(transaction.id)]
        )
        guard response.credited else {
            throw APIError.rejected(
                message: String(localized: "storekit.pending")
            )
        }
        await transaction.finish()
        message = String(localized: "storekit.success")
        NotificationCenter.default.post(
            name: .aisPricingRulesInvalidated,
            object: nil
        )
        NotificationCenter.default.post(
            name: .aisRechargeCredited,
            object: nil
        )
    }

}

struct StoreKitPurchaseView: View {
    @Environment(SessionStore.self) private var session
    let region: String?
    @State private var model = StoreKitPurchaseViewModel()

    var body: some View {
        List {
            if model.isLoading {
                ProgressView()
            }
            if !model.isLoading && model.products.isEmpty {
                ContentUnavailableView {
                    Label(
                        "storekit.empty.title",
                        systemImage: "cart.badge.questionmark"
                    )
                } description: {
                    Text(model.message ?? String(
                        localized: "storekit.empty.description"
                    ))
                } actions: {
                    Button("storekit.retry") {
                        Task {
                            await model.load(
                                region: region,
                                session: session
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }
            ForEach(model.products, id: \.id) { product in
                Button {
                    Task { await model.purchase(product, session: session) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(product.displayName)
                            if let points = model.packagesByProductID[
                                product.id
                            ]?.points {
                                Text("\(points) \(String(localized: "storekit.points"))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(product.displayPrice).bold()
                    }
                }
                .disabled(model.purchasingProductID != nil)
            }
            if !model.products.isEmpty, let message = model.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("storekit.title")
        .task {
            await model.load(
                region: region,
                session: session
            )
        }
    }
}

#Preview("StoreKitPurchaseView") {
    NavigationStack {
        StoreKitPurchaseView(region: "CN")
    }
    .environment(SessionStore())
}
