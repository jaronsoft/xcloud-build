import Foundation
import Observation
import StoreKit

enum AISMediaRegion: String, Sendable {
    case china = "cn"
    case international = "global"

    var storeKitCountryCode: String {
        switch self {
        case .china:
            return "CN"
        case .international:
            return "US"
        }
    }
}

enum AISMediaRegionResolver {
    static func resolve(
        storefrontCountryCode: String?,
        accountCountryCode: String?,
        localeCountryCode: String?
    ) -> AISMediaRegion {
        let countryCode = [
            storefrontCountryCode,
            accountCountryCode,
            localeCountryCode
        ]
        .compactMap(normalizeCountryCode)
        .first
        return countryCode == "CN" || countryCode == "CHN"
            ? .china
            : .international
    }

    private static func normalizeCountryCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).uppercased()
        return normalized.isEmpty ? nil : normalized
    }
}

enum AISMediaRegionRequestContext {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var storedRegion =
        AISMediaRegion.international

    static var headerValue: String {
        lock.withLock { storedRegion.rawValue }
    }

    static func install(_ region: AISMediaRegion) {
        lock.withLock {
            storedRegion = region
        }
    }
}

@MainActor
@Observable
final class AISMediaRegionStore {
    private(set) var effectiveRegion = AISMediaRegion.international
    private(set) var revision = 0
    private var storefrontCountryCode: String?
    private var accountCountryCode: String?
    private let refreshImageDelivery: @Sendable () async -> Void

    init(
        refreshImageDelivery: @escaping @Sendable () async -> Void = {
            await AISImageDeliveryStore.shared.load(forceRefresh: true)
        }
    ) {
        self.refreshImageDelivery = refreshImageDelivery
        effectiveRegion = AISMediaRegionResolver.resolve(
            storefrontCountryCode: nil,
            accountCountryCode: nil,
            localeCountryCode: Locale.current.region?.identifier
        )
        AISMediaRegionRequestContext.install(effectiveRegion)
    }

    func refresh(
        accountCountryCode: String?,
        reloadStorefront: Bool = false
    ) async {
        self.accountCountryCode = accountCountryCode
        if storefrontCountryCode == nil || reloadStorefront {
            storefrontCountryCode = await Storefront.current?.countryCode
        }
        await applyEffectiveRegion()
    }

    private func applyEffectiveRegion(forceRefresh: Bool = false) async {
        let resolved = AISMediaRegionResolver.resolve(
            storefrontCountryCode: storefrontCountryCode,
            accountCountryCode: accountCountryCode,
            localeCountryCode: Locale.current.region?.identifier
        )
        let changed = resolved != effectiveRegion
        effectiveRegion = resolved
        AISMediaRegionRequestContext.install(resolved)
        if changed || forceRefresh {
            await AISResponseCache.shared.clear()
            await refreshImageDelivery()
            revision += 1
        }
    }

}
