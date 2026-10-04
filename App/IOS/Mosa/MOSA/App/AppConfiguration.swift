import Foundation

enum AppConfiguration {
    static let apiBaseURL = URL(string: "https://api.wekarepartners.com")!
    static let officialSiteURL = URL(string: "https://mosa.wekarepartners.com")!
    static let h5BaseURL = URL(string: "https://m.wekarepartners.com")!
    static let companySiteURL = URL(string: "https://wekarepartners.com")!
    static let defaultLocale = "en"
    static let companyName = "WeKare Partners"
    static let productName = "MOSA"

    static var showsNetworkDiagnostics: Bool {
#if DEBUG
        true
#else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
#endif
    }

    static var releaseLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "21"
        return "\(version) (Build \(build))"
    }
}

struct PublicVersionConfiguration: Codable, Equatable, Sendable {
    let ios: String
    let h5: String
}

struct PublicAppConfiguration: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let revision: String
    let maintenance: Bool
    let minimumVersion: PublicVersionConfiguration
    let recommendedVersion: PublicVersionConfiguration
    let announcement: String?
    let featureFlags: [String: Bool]
    let supportUrl: URL
    let refreshAfterSeconds: Int

    static let defaultValue = PublicAppConfiguration(
        schemaVersion: 1,
        revision: "built-in",
        maintenance: false,
        minimumVersion: PublicVersionConfiguration(ios: "1.0.0", h5: "1.0.0"),
        recommendedVersion: PublicVersionConfiguration(ios: "1.0.0", h5: "1.0.0"),
        announcement: nil,
        featureFlags: [:],
        supportUrl: AppConfiguration.officialSiteURL,
        refreshAfterSeconds: 300
    )

    var isValid: Bool {
        schemaVersion == 1
            && !revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !minimumVersion.ios.isEmpty
            && !minimumVersion.h5.isEmpty
            && !recommendedVersion.ios.isEmpty
            && !recommendedVersion.h5.isEmpty
            && supportUrl.scheme == "https"
            && (60...86400).contains(refreshAfterSeconds)
    }
}

actor PublicConfigurationService {
    private static let cacheKey = "mosa.public-config.v1"
    private let urlSession: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    nonisolated static func cachedOrDefault(userDefaults: UserDefaults = .standard) -> PublicAppConfiguration {
        guard let data = userDefaults.data(forKey: cacheKey),
              let value = try? JSONDecoder().decode(PublicAppConfiguration.self, from: data),
              value.isValid else {
            return .defaultValue
        }
        return value
    }

    func refresh() async -> PublicAppConfiguration {
        let fallback = Self.cachedOrDefault()
        let configURL = AppConfiguration.apiBaseURL.appendingPathComponent("config/v1/mosa")
        var request = URLRequest(url: configURL)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let value = try? decoder.decode(PublicAppConfiguration.self, from: data),
                  value.isValid else {
                return fallback
            }
            if let cache = try? encoder.encode(value) {
                UserDefaults.standard.set(cache, forKey: Self.cacheKey)
            }
            return value
        } catch {
            // 配置服务异常时沿用缓存或内置值，不阻塞登录和本地数据访问。
            return fallback
        }
    }
}
