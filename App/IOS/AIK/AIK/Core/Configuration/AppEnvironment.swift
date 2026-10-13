import Foundation

struct AppEnvironment: Sendable {
    let apiBaseURL: URL

    static let current: AppEnvironment = {
        let configured = Bundle.main.object(
            forInfoDictionaryKey: "AIKAPIBaseURL"
        ) as? String
        let fallback = "https://app.jaronsoft.com/api"
        let value = configured?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppEnvironment(
            apiBaseURL: URL(string: value?.isEmpty == false ? value! : fallback)
                ?? URL(string: fallback)!
        )
    }()

    static var releaseLabel: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return "\(version) (\(build))"
    }

    static var versionDisplayLabel: String {
        String(format: String(localized: "app.version_format"), releaseLabel)
    }

    static var privacyURL: URL { legalURL(path: "privacy-policy") }
    static var termsURL: URL { legalURL(path: "terms") }

    private static func legalURL(path: String) -> URL {
        let language = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-CN" : "en-US"
        return URL(string: "https://ai.jaronsoft.com/\(path)/?lang=\(language)")!
    }
}
