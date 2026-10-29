import Foundation

enum BmbLanguage {
    static var preference: String { UserDefaults.standard.string(forKey: "bmb.app_language") ?? "system" }

    static var code: String { code(for: preference) }

    static func code(for preference: String) -> String {
        switch preference {
        case "zh": "zh"
        case "en": "en"
        default: Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en"
        }
    }

    static var locale: Locale { locale(for: preference) }
    static func locale(for preference: String) -> Locale {
        Locale(identifier: code(for: preference) == "zh" ? "zh-Hans" : "en")
    }

    static func localized(_ key: String) -> String {
        guard code == "zh",
              let path = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
