import Foundation

enum AppConfiguration {
    static let productName = "Meroli"
    static let apiBaseURLString = Bundle.main.object(forInfoDictionaryKey: "MeroliAPIBaseURL") as? String ?? ""
    static let apiBaseURL = URL(string: apiBaseURLString)

    static var environmentName: String {
#if DEBUG
        "开发环境"
#else
        "正式环境"
#endif
    }
}
