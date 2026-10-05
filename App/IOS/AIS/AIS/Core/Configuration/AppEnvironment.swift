import Foundation

struct AppEnvironment: Sendable {
    private let overrideAPIBaseURL: URL?

    var apiBaseURL: URL {
        overrideAPIBaseURL ?? AppAPIRoutingSnapshot.baseURL
    }

    init(apiBaseURL: URL? = nil) {
        overrideAPIBaseURL = apiBaseURL
    }

    static let current: AppEnvironment = {
        let configuredValue = Bundle.main.object(
            forInfoDictionaryKey: "AISAPIBaseURL"
        ) as? String
        let fallback = "https://ais.get-free.net"
        let value = configuredValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: value?.isEmpty == false ? value! : fallback)
            ?? URL(string: fallback)!
        return AppEnvironment(apiBaseURL: url.absoluteString == fallback ? nil : url)
    }()

    static var showsNetworkDiagnostics: Bool {
#if DEBUG
        true
#else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
#endif
    }

    static var releaseLabel: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return "\(version) (\(build))"
    }
}
