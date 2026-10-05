import Foundation
import Observation
import StoreKit
import SwiftUI

enum AppConfiguration {
    static let companyName = "WeKare Partners LLC"
    static var supportURL: URL { websiteURL(path: "support") }
    static var termsURL: URL { websiteURL(path: "terms") }
    static var subscriptionTermsURL: URL { websiteURL(path: "subscription-terms") }
    static var privacyURL: URL { websiteURL(path: "privacy") }
    static let appStoreURL = URL(
        string: "https://apps.apple.com/app/id6800612526"
    )!
    static let xURL = URL(string: "https://x.com/PixaRivo/")!
    static let standardEULAURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!
    static var uploadComplianceURL: URL { websiteURL(path: "upload-compliance") }
    static var galleryIntellectualPropertyURL: URL { websiteURL(path: "gallery-ip") }
    static let complianceAgreementVersion = "2026-08-13.1"

    private static let configuredAPIBaseURL: URL = {
        let value = Bundle.main.object(forInfoDictionaryKey: "PixaRivoAPIBaseURL") as? String
        return URL(string: value ?? "https://ais.get-free.net")!
    }()

    static var apiBaseURL: URL {
        configuredAPIBaseURL.absoluteString == "https://ais.get-free.net"
            ? AppAPIRoutingSnapshot.baseURL
            : configuredAPIBaseURL
    }

    static var isLocalDevelopment: Bool {
        configuredAPIBaseURL.host == "localhost"
            || configuredAPIBaseURL.host == "127.0.0.1"
            || configuredAPIBaseURL.host == "::1"
    }

    static var apiDisplayName: String {
        if isLocalDevelopment {
            return AppLanguage.localized("diagnostics.api.local")
        }
        switch AppAPIRoutingSnapshot.endpointRole {
        case .primary: return AppLanguage.localized("diagnostics.api.primary")
        case .backup: return AppLanguage.localized("diagnostics.api.backup")
        case .test: return AppLanguage.localized("diagnostics.api.test")
        }
    }

    static var releaseLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (Build \(build))"
    }

    private static func websiteURL(path: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "pixarivo.get-free.net"
        components.path = "/\(path)/"
        components.queryItems = [
            URLQueryItem(
                name: "lang",
                value: AppLanguage.apiValue
            )
        ]
        return components.url!
    }
}

enum PixaTheme {
    static let paper = Color(red: 0.957, green: 0.945, blue: 0.918)
    static let ink = Color(red: 0.094, green: 0.094, blue: 0.09)
    static let accent = Color(red: 0.941, green: 0.322, blue: 0.239)
    static let line = Color.black.opacity(0.11)
}

enum PixaLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case traditionalChinese
    case english
    case spanish
    case portuguese
    case japanese

    var id: String { rawValue }
}

@MainActor
@Observable
final class PixaLanguageStore {
    private static let storageKey = "pixarivo.app_language"

    private(set) var preference: PixaLanguagePreference
    private(set) var locale: Locale

    init() {
        let storedPreference = PixaLanguagePreference(
            rawValue: UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        ) ?? .system
        preference = storedPreference
        locale = Self.resolve(storedPreference)
        AppLanguage.install(locale: locale)
    }

    func select(_ value: PixaLanguagePreference) {
        guard preference != value else { return }
        preference = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.storageKey)
        applyResolvedLocale()
    }

    func refreshSystemLanguage() {
        guard preference == .system else { return }
        applyResolvedLocale()
    }

    private func applyResolvedLocale() {
        let resolved = Self.resolve(preference)
        guard locale.identifier != resolved.identifier else { return }
        locale = resolved
        AppLanguage.install(locale: resolved)
    }

    private static func resolve(_ preference: PixaLanguagePreference) -> Locale {
        switch preference {
        case .system:
            // 界面语言应跟随系统首选本地化，而不是可能不同的日期与数字格式区域。
            Locale(
                identifier: Bundle.main.preferredLocalizations.first
                    ?? Locale.preferredLanguages.first
                    ?? "en"
            )
        case .simplifiedChinese:
            Locale(identifier: "zh-Hans")
        case .traditionalChinese:
            Locale(identifier: "zh-Hant")
        case .english:
            Locale(identifier: "en")
        case .spanish:
            Locale(identifier: "es")
        case .portuguese:
            Locale(identifier: "pt-BR")
        case .japanese:
            Locale(identifier: "ja")
        }
    }
}

enum AppLanguage {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var storedLocaleIdentifier = Locale.current.identifier

    static var locale: Locale {
        Locale(identifier: lock.withLock { storedLocaleIdentifier })
    }

    static var isChinese: Bool {
        locale.language.languageCode?.identifier == "zh"
    }

    // 内容接口与应用界面使用同一语言，素材分发区域仍由独立设置决定。
    static var apiValue: String {
        switch locale.language.languageCode?.identifier {
        case "zh": isTraditionalChinese ? "zh-TW" : "zh-CN"
        case "es": "es-ES"
        case "pt": "pt-BR"
        case "ja": "ja-JP"
        default: "en-US"
        }
    }

    static var isTraditionalChinese: Bool {
        locale.language.script?.identifier == "Hant"
    }

    static func localized(_ key: String) -> String {
        let localization: String
        switch locale.language.languageCode?.identifier {
        case "zh": localization = isTraditionalChinese ? "zh-Hant" : "zh-Hans"
        case "es": localization = "es"
        case "pt": localization = "pt-BR"
        case "ja": localization = "ja"
        default: localization = "en"
        }
        guard let path = Bundle.main.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.main.localizedString(forKey: key, value: key, table: nil)
        }
        let localized = bundle.localizedString(forKey: key, value: key, table: nil)
        if localized != key {
            return localized
        }
        guard let englishPath = Bundle.main.path(forResource: "en", ofType: "lproj"),
              let englishBundle = Bundle(path: englishPath) else {
            return Bundle.main.localizedString(forKey: key, value: key, table: nil)
        }
        return englishBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func value(zh: String?, en: String?) -> String {
        let primary = isChinese ? zh : en
        let fallback = isChinese ? en : zh
        return primary?.nilIfEmpty ?? fallback?.nilIfEmpty ?? ""
    }

    static func install(locale: Locale) {
        lock.withLock { storedLocaleIdentifier = locale.identifier }
    }
}

enum PixaMediaRegion {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var storedValue = localeValue
    private nonisolated(unsafe) static var storedPreference = PixaMediaRegionPreference.automatic.rawValue

    static var headerValue: String {
        lock.withLock { storedValue }
    }

    static var templateRegionValue: String {
        headerValue == "cn" ? "CN" : "GLOBAL"
    }

    static var preferenceHeaderValue: String {
        lock.withLock { storedPreference }
    }

    static func install(value: String, preference: PixaMediaRegionPreference) {
        lock.withLock {
            storedValue = value == "cn" ? "cn" : "global"
            storedPreference = preference.rawValue
        }
    }

    private static var localeValue: String {
        let code = Locale.current.region?.identifier.uppercased()
        return code == "CN" || code == "CHN" ? "cn" : "global"
    }
}

enum PixaMediaRegionPreference: String, CaseIterable, Identifiable {
    case automatic
    case china
    case international

    var id: String { rawValue }
}

@MainActor
@Observable
final class PixaMediaRegionStore {
    private static let storageKey = "pixarivo.media_region_preference"

    private(set) var preference: PixaMediaRegionPreference
    private(set) var effectiveValue: String
    private(set) var revision = 0
    private var accountCountryCode: String?
    private var storefrontCountryCode: String?

    init() {
        let storedPreference = PixaMediaRegionPreference(
            rawValue: UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        ) ?? .automatic
        let resolvedValue = Self.resolve(
            preference: storedPreference,
            storefrontCountryCode: nil,
            accountCountryCode: nil,
            localeCountryCode: Locale.current.region?.identifier
        )
        preference = storedPreference
        effectiveValue = resolvedValue
        PixaMediaRegion.install(value: resolvedValue, preference: storedPreference)
    }

    func refresh(accountCountryCode: String?, reloadStorefront: Bool = false) async {
        self.accountCountryCode = accountCountryCode
        if storefrontCountryCode == nil || reloadStorefront {
            storefrontCountryCode = await Storefront.current?.countryCode
        }
        await apply(forceRefresh: false)
    }

    func select(_ value: PixaMediaRegionPreference) async {
        guard preference != value else { return }
        preference = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.storageKey)
        if value == .automatic && storefrontCountryCode == nil {
            storefrontCountryCode = await Storefront.current?.countryCode
        }
        await apply(forceRefresh: true)
    }

    private func apply(forceRefresh: Bool) async {
        let resolved = Self.resolve(
            preference: preference,
            storefrontCountryCode: storefrontCountryCode,
            accountCountryCode: accountCountryCode,
            localeCountryCode: Locale.current.region?.identifier
        )
        let changed = resolved != effectiveValue
        effectiveValue = resolved
        PixaMediaRegion.install(value: resolved, preference: preference)
        if changed || forceRefresh {
            await PixaImageDeliveryStore.shared.load(forceRefresh: true)
            revision += 1
            NotificationCenter.default.post(name: .pixaMediaRegionDidChange, object: nil)
        }
    }

    private static func resolve(
        preference: PixaMediaRegionPreference,
        storefrontCountryCode: String?,
        accountCountryCode: String?,
        localeCountryCode: String?
    ) -> String {
        switch preference {
        case .china:
            return "cn"
        case .international:
            return "global"
        case .automatic:
            // App Store 商店、账号归属和设备地区均不依赖 VPN 出口；任一信号为中国时优先国内 CDN。
            let hasChinaSignal = [storefrontCountryCode, accountCountryCode, localeCountryCode]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .contains { $0 == "CN" || $0 == "CHN" }
            return hasChinaSignal ? "cn" : "global"
        }
    }
}

extension Notification.Name {
    static let pixaMediaRegionDidChange = Notification.Name("PixaMediaRegionDidChange")
}

extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
