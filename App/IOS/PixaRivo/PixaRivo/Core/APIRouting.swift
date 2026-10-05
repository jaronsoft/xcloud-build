import CryptoKit
import Foundation
import Network

struct AppRoutingEndpoint: Codable, Sendable {
    let Id: String
    let BaseUrl: String
    let HealthPath: String
    let Enabled: Bool
    let Priority: Int
    let FallbackEndpointIds: [String]
    let Role: String?
    let DisplayName: String?

    var role: AppRoutingEndpointRole {
        AppRoutingEndpointRole(rawValue: Role?.lowercased() ?? "") ?? .primary
    }

    var displayName: String {
        DisplayName?.nilIfEmpty ?? role.defaultDisplayName
    }
}

enum AppRoutingEndpointRole: String, Codable, Sendable {
    case primary
    case backup
    case test

    var sortPriority: Int {
        switch self {
        case .primary: 0
        case .backup: 1
        case .test: 2
        }
    }

    var defaultDisplayName: String {
        switch self {
        case .primary: "Primary API"
        case .backup: "Backup API"
        case .test: "Network Test"
        }
    }

    var displayName: String { defaultDisplayName }
}

struct AppRoutingPayload: Codable, Sendable {
    let SchemaVersion: Int
    let ConfigVersion: Int64
    let IssuedAt: String
    let RefreshSeconds: Int
    let ConsecutiveFailures: Int?
    let CooldownSeconds: Int?
    let DefaultEndpointId: String
    let Products: [String]?
    let Endpoints: [AppRoutingEndpoint]
}

private struct AppRoutingDiscoveryResponse: Codable, Sendable {
    let EnvelopeVersion: Int
    let ResolvedCountry: String
    let RecommendedEndpointId: String
    let ResolvedAt: String
    let SignedPayload: String
    let KeyId: String
    let Signature: String
}

private struct AppRoutingCache: Codable, Sendable {
    let response: AppRoutingDiscoveryResponse
    let fetchedAt: Date
    var selectedEndpointId: String
}

struct AppRoutingProbeMeasurement: Sendable {
    let endpointID: String
    let latency: TimeInterval
    let statusCode: Int?
    let succeeded: Bool

    init(endpointID: String, latency: TimeInterval, statusCode: Int? = nil, succeeded: Bool = true) {
        self.endpointID = endpointID
        self.latency = latency
        self.statusCode = statusCode
        self.succeeded = succeeded
    }
}

struct AppRoutingDiagnosticResult: Identifiable, Sendable {
    let id: String
    let role: AppRoutingEndpointRole
    let displayName: String
    let succeeded: Bool
    let statusCode: Int?
    let latencyMilliseconds: Int?

    var latencyCategory: AppRoutingLatencyCategory? {
        guard succeeded, let latencyMilliseconds else { return nil }
        return AppRoutingLatencyCategory(milliseconds: latencyMilliseconds)
    }

    var statusLocalizationKey: String {
        latencyCategory?.localizationKey
            ?? (succeeded ? "diagnostics.available" : "diagnostics.unavailable")
    }
}

enum AppRoutingLatencyCategory: Sendable {
    case fast
    case normal
    case slow
    case verySlow

    init(milliseconds: Int) {
        switch milliseconds {
        case ...500: self = .fast
        case ...1_500: self = .normal
        case ...3_000: self = .slow
        default: self = .verySlow
        }
    }

    var localizationKey: String {
        switch self {
        case .fast: "diagnostics.latency.fast"
        case .normal: "diagnostics.latency.normal"
        case .slow: "diagnostics.latency.slow"
        case .verySlow: "diagnostics.latency.very_slow"
        }
    }
}

enum AppRoutingEndpointSelector {
    static func select(
        measurements: [AppRoutingProbeMeasurement],
        preferredEndpointID: String?,
        switchImprovementRatio: Double = 0.7
    ) -> String? {
        guard let fastest = measurements.min(by: { $0.latency < $1.latency }) else {
            return preferredEndpointID
        }
        guard let preferredEndpointID,
              let preferred = measurements.first(where: {
                  $0.endpointID == preferredEndpointID
              }),
              preferred.endpointID != fastest.endpointID else {
            return fastest.endpointID
        }
        return fastest.latency <= preferred.latency * switchImprovementRatio
            ? fastest.endpointID
            : preferred.endpointID
    }
}

private final class AppRoutingPathObserver: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.jaronsoft.pixarivo.api-routing")

    func start(onChange: @escaping @Sendable () -> Void) {
        monitor.pathUpdateHandler = { path in
            AppNetworkPathSnapshot.install(path)
            onChange()
        }
        monitor.start(queue: queue)
    }
}

enum AppNetworkPathState: Sendable {
    case unknown
    case available
    case unavailable
    case accessDenied
}

enum AppNetworkPathSnapshot {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var storedState = AppNetworkPathState.unknown

    static var state: AppNetworkPathState {
        lock.withLock { storedState }
    }

    static func install(_ path: NWPath) {
        let state: AppNetworkPathState
        if path.status == .satisfied {
            state = .available
        } else {
            switch path.unsatisfiedReason {
            case .cellularDenied, .wifiDenied, .localNetworkDenied:
                state = .accessDenied
            case .notAvailable, .vpnInactive:
                state = .unavailable
            @unknown default:
                state = .unknown
            }
        }
        lock.withLock { storedState = state }
    }
}

enum AppAPIRoutingSnapshot {
    static let fallbackBaseURL = URL(string: "https://ais.get-free.net")!
    private static let lock = NSLock()
    private nonisolated(unsafe) static var storedBaseURL = fallbackBaseURL
    private nonisolated(unsafe) static var storedEndpointID = "global-primary"
    private nonisolated(unsafe) static var storedEndpointRole: AppRoutingEndpointRole = .backup
    private nonisolated(unsafe) static var storedDisplayName = "Backup API"
    private nonisolated(unsafe) static var storedConfigVersion: Int64 = 0
    private nonisolated(unsafe) static var storedFetchedAt: Date?

    static var baseURL: URL { lock.withLock { storedBaseURL } }
    static var endpointID: String { lock.withLock { storedEndpointID } }
    static var endpointRole: AppRoutingEndpointRole { lock.withLock { storedEndpointRole } }
    static var displayName: String { lock.withLock { storedDisplayName } }
    static var configVersion: Int64 { lock.withLock { storedConfigVersion } }
    static var fetchedAt: Date? { lock.withLock { storedFetchedAt } }
    static var isStale: Bool {
        guard let fetchedAt else { return true }
        return Date().timeIntervalSince(fetchedAt) >= 86_400
    }

    static func install(baseURL: URL, endpointID: String, role: AppRoutingEndpointRole, displayName: String, configVersion: Int64, fetchedAt: Date?) {
        lock.withLock {
            storedBaseURL = baseURL
            storedEndpointID = endpointID
            storedEndpointRole = role
            storedDisplayName = displayName
            storedConfigVersion = configVersion
            storedFetchedAt = fetchedAt
        }
    }
}

actor AppAPIRouter {
    static let shared = AppAPIRouter()

    private let discoveryURL = URL(string: "https://ais.get-free.net/config/v1/resolve-api")!
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var cache: AppRoutingCache?
    private var payload: AppRoutingPayload?
    private var usingBuiltInFallback = false
    private var product = ""
    private var didBootstrap = false
    private var consecutiveFailures = 0
    private var lastSwitchAt: Date?
    private var lastProbeAt: Date?
    private var hasObservedInitialNetworkPath = false
    private var pathObserver: AppRoutingPathObserver?
    private var isProbing = false
    private var needsProbeAfterCurrent = false
    private var completedInitialSelection = false
    private var initialSelectionWaiters: [CheckedContinuation<Void, Never>] = []

    func bootstrap(product: String) async {
        self.product = product
        guard !didBootstrap else {
            await waitForInitialSelection()
            return
        }
        didBootstrap = true
        defer { completeInitialSelection() }
        loadCache()
        startNetworkObservation()
        if shouldRefresh {
            await refresh(force: true)
        } else {
            await probeAvailableEndpoints()
        }
    }

    func waitForInitialSelection() async {
        guard didBootstrap, !completedInitialSelection else { return }
        await withCheckedContinuation { continuation in
            initialSelectionWaiters.append(continuation)
        }
    }

    @discardableResult
    func refresh(force: Bool = false) async -> Bool {
        guard !product.isEmpty, force || shouldRefresh else { return false }
        var components = URLComponents(url: discoveryURL, resolvingAgainstBaseURL: false)!
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        components.queryItems = [
            URLQueryItem(name: "product", value: product),
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "appVersion", value: version),
            URLQueryItem(name: "build", value: build),
        ]
        guard let url = components.url else { return false }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { return false }
            let discovery = try decoder.decode(AppRoutingDiscoveryResponse.self, from: data)
            let verifiedPayload = try verify(discovery)
            if let current = payload, verifiedPayload.ConfigVersion < current.ConfigVersion { return false }
            guard let endpoint = enabledEndpoint(discovery.RecommendedEndpointId, in: verifiedPayload) else { return false }
            let next = AppRoutingCache(
                response: discovery,
                fetchedAt: Date(),
                selectedEndpointId: endpoint.Id
            )
            cache = next
            payload = verifiedPayload
            usingBuiltInFallback = false
            consecutiveFailures = 0
            await probeAvailableEndpoints(
                preferredEndpointID: endpoint.Id
            )
            return true
        } catch {
            // 发现入口不可达时，首次安装和已有缓存都继续使用安全的主备兜底探测。
            installBuiltInFallbackIfNeeded()
            await probeAvailableEndpoints()
            return false
        }
    }

    func diagnosticResults() async -> [AppRoutingDiagnosticResult] {
        installBuiltInFallbackIfNeeded()
        guard let payload else { return [] }
        let endpoints = payload.Endpoints.filter { $0.Enabled }
        let selectedID = cache?.selectedEndpointId
        let fallbackIDs = payload.Endpoints.first(where: { $0.Id == selectedID })?.FallbackEndpointIds ?? []
        return await withTaskGroup(of: AppRoutingDiagnosticResult.self, returning: [AppRoutingDiagnosticResult].self) { group in
            for endpoint in endpoints {
                group.addTask {
                    let measurement = await Self.probeDetailed(endpoint)
                    let role: AppRoutingEndpointRole = endpoint.role == .test
                        ? .test
                        : endpoint.Id == selectedID
                            ? .primary
                            : fallbackIDs.contains(endpoint.Id) ? .backup : endpoint.role
                    return AppRoutingDiagnosticResult(
                        id: endpoint.Id,
                        role: role,
                        displayName: role.defaultDisplayName,
                        succeeded: measurement?.succeeded == true,
                        statusCode: measurement?.statusCode,
                        latencyMilliseconds: measurement.map { Int($0.latency * 1_000) }
                    )
                }
            }
            var results: [AppRoutingDiagnosticResult] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.role.sortPriority < $1.role.sortPriority }
        }
    }

    func reportSuccess() {
        consecutiveFailures = 0
    }

    func retryRequestIfNeeded(
        _ request: URLRequest,
        statusCode: Int?,
        error: Error?
    ) -> URLRequest? {
        guard isRetryable(statusCode: statusCode, error: error),
              request.value(forHTTPHeaderField: "X-App-Node-Retry") == nil,
              let payload,
              var cache else { return nil }
        consecutiveFailures += 1
        let threshold = max(1, payload.ConsecutiveFailures ?? 2)
        guard consecutiveFailures >= threshold else { return nil }
        guard request.httpMethod == "GET" || request.httpMethod == "HEAD" else {
            consecutiveFailures = 0
            Task { await self.probeAvailableEndpoints(force: true) }
            return nil
        }
        let cooldown = TimeInterval(max(60, payload.CooldownSeconds ?? 900))
        if let lastSwitchAt, Date().timeIntervalSince(lastSwitchAt) < cooldown { return nil }
        guard let current = enabledEndpoint(cache.selectedEndpointId, in: payload),
              let fallbackID = current.FallbackEndpointIds.first(where: {
                  $0 != current.Id && enabledEndpoint($0, in: payload) != nil
              }),
              let fallback = enabledEndpoint(fallbackID, in: payload),
              let oldBaseURL = URL(string: current.BaseUrl),
              let newBaseURL = URL(string: fallback.BaseUrl),
              let requestURL = request.url,
              let rewrittenURL = rewrite(requestURL, from: oldBaseURL, to: newBaseURL)
        else { return nil }
        cache.selectedEndpointId = fallback.Id
        self.cache = cache
        consecutiveFailures = 0
        lastSwitchAt = Date()
        install(cache, payload: payload)
        if !usingBuiltInFallback { persist(cache) }
        var retry = request
        retry.url = rewrittenURL
        retry.setValue("1", forHTTPHeaderField: "X-App-Node-Retry")
        return retry
    }

    private var shouldRefresh: Bool {
        guard let cache, let payload else { return true }
        if !Calendar.current.isDate(cache.fetchedAt, inSameDayAs: Date()) { return true }
        let interval = TimeInterval(min(max(payload.RefreshSeconds, 300), 86_400))
        return Date().timeIntervalSince(cache.fetchedAt) >= interval
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let stored = try? decoder.decode(AppRoutingCache.self, from: data),
              let verifiedPayload = try? verify(stored.response),
              enabledEndpoint(stored.selectedEndpointId, in: verifiedPayload) != nil else { return }
        cache = stored
        payload = verifiedPayload
        install(stored, payload: verifiedPayload)
    }

    private func startNetworkObservation() {
        let observer = AppRoutingPathObserver()
        pathObserver = observer
        observer.start {
            Task {
                await AppAPIRouter.shared.networkPathDidChange()
            }
        }
    }

    private func completeInitialSelection() {
        guard !completedInitialSelection else { return }
        completedInitialSelection = true
        let waiters = initialSelectionWaiters
        initialSelectionWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func networkPathDidChange() async {
        guard hasObservedInitialNetworkPath else {
            hasObservedInitialNetworkPath = true
            return
        }
        guard didBootstrap else { return }
        if let lastProbeAt,
           Date().timeIntervalSince(lastProbeAt) < 5 {
            return
        }
        try? await Task.sleep(for: .milliseconds(500))
        await probeAvailableEndpoints(force: true)
    }

    private func probeAvailableEndpoints(
        preferredEndpointID: String? = nil,
        force: Bool = false
    ) async {
        guard let payload, var cache else { return }
        guard !isProbing else {
            needsProbeAfterCurrent = true
            return
        }
        if !force,
           let lastProbeAt,
           Date().timeIntervalSince(lastProbeAt) < 5 {
            return
        }
        isProbing = true
        defer {
            isProbing = false
            lastProbeAt = Date()
            if needsProbeAfterCurrent {
                needsProbeAfterCurrent = false
                Task { await self.probeAvailableEndpoints(force: true) }
            }
        }

        // 测试地址只用于诊断，不参与正常主备选择。
        let endpoints = payload.Endpoints.filter { $0.Enabled && $0.role != .test }
        let measurements = await withTaskGroup(
            of: AppRoutingProbeMeasurement?.self,
            returning: [AppRoutingProbeMeasurement].self
        ) { group in
            for endpoint in endpoints {
                group.addTask {
                    await Self.probe(endpoint)
                }
            }
            var values: [AppRoutingProbeMeasurement] = []
            for await measurement in group {
                if let measurement {
                    values.append(measurement)
                }
            }
            return values
        }

        guard let currentCache = self.cache,
              currentCache.fetchedAt == cache.fetchedAt,
              currentCache.selectedEndpointId == cache.selectedEndpointId,
              self.payload?.ConfigVersion == payload.ConfigVersion else {
            return
        }
        let preferred = preferredEndpointID ?? cache.selectedEndpointId
        let selectedID = AppRoutingEndpointSelector.select(
            measurements: measurements,
            preferredEndpointID: preferred
        ) ?? preferred
        guard enabledEndpoint(selectedID, in: payload) != nil else { return }
        cache.selectedEndpointId = selectedID
        self.cache = cache
        consecutiveFailures = 0
        install(cache, payload: payload)
        if !usingBuiltInFallback { persist(cache) }
    }

    private static func probe(
        _ endpoint: AppRoutingEndpoint
    ) async -> AppRoutingProbeMeasurement? {
        guard let baseURL = URL(string: endpoint.BaseUrl) else { return nil }
        var request = URLRequest(
            url: baseURL.appending(path: endpoint.HealthPath)
        )
        request.httpMethod = "GET"
        request.timeoutInterval = 1.5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 1.5
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let startedAt = Date()
        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { return nil }
            return AppRoutingProbeMeasurement(
                endpointID: endpoint.Id,
                latency: Date().timeIntervalSince(startedAt)
            )
        } catch {
            return nil
        }
    }

    private static func probeDetailed(
        _ endpoint: AppRoutingEndpoint
    ) async -> AppRoutingProbeMeasurement? {
        guard let baseURL = URL(string: endpoint.BaseUrl) else { return nil }
        var request = URLRequest(url: baseURL.appending(path: endpoint.HealthPath))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let startedAt = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            return AppRoutingProbeMeasurement(
                endpointID: endpoint.Id,
                latency: Date().timeIntervalSince(startedAt),
                statusCode: statusCode,
                succeeded: statusCode.map { (200..<300).contains($0) } == true
            )
        } catch {
            return AppRoutingProbeMeasurement(
                endpointID: endpoint.Id,
                latency: Date().timeIntervalSince(startedAt),
                succeeded: false
            )
        }
    }

    private func installBuiltInFallbackIfNeeded() {
        guard payload == nil || cache == nil else { return }
        let endpoints = [
            AppRoutingEndpoint(
                Id: "cn-primary", BaseUrl: "https://gateway.jaronsoft.com/ais",
                HealthPath: "/api/ais/runtime/ping", Enabled: true, Priority: 10,
                FallbackEndpointIds: ["global-primary"], Role: "primary", DisplayName: "Primary API"
            ),
            AppRoutingEndpoint(
                Id: "global-primary", BaseUrl: "https://ais.get-free.net",
                HealthPath: "/api/ais/runtime/ping", Enabled: true, Priority: 10,
                FallbackEndpointIds: ["cn-primary"], Role: "backup", DisplayName: "Backup API"
            )
        ]
        let fallbackPayload = AppRoutingPayload(
            SchemaVersion: 1, ConfigVersion: 0, IssuedAt: "built-in",
            RefreshSeconds: 300, ConsecutiveFailures: 1, CooldownSeconds: 60,
            DefaultEndpointId: "global-primary", Products: ["pixarivo", "ais"], Endpoints: endpoints
        )
        let response = AppRoutingDiscoveryResponse(
            EnvelopeVersion: 1, ResolvedCountry: "unknown", RecommendedEndpointId: "global-primary",
            ResolvedAt: "built-in", SignedPayload: "", KeyId: "built-in", Signature: ""
        )
        payload = fallbackPayload
        cache = AppRoutingCache(response: response, fetchedAt: Date(), selectedEndpointId: "global-primary")
        usingBuiltInFallback = true
        install(cache!, payload: fallbackPayload)
    }

    private func verify(_ response: AppRoutingDiscoveryResponse) throws -> AppRoutingPayload {
        guard response.EnvelopeVersion == 1,
              let payloadData = Self.decodeBase64URL(response.SignedPayload),
              let signature = Self.decodeBase64URL(response.Signature),
              let configuredKeyID = Bundle.main.object(forInfoDictionaryKey: "AISRoutingKeyId") as? String,
              response.KeyId == configuredKeyID,
              let publicKeyValue = Bundle.main.object(forInfoDictionaryKey: "AISRoutingPublicKey") as? String,
              let publicKeyData = Data(base64Encoded: publicKeyValue),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData),
              publicKey.isValidSignature(signature, for: payloadData)
        else { throw URLError(.secureConnectionFailed) }
        let result = try decoder.decode(AppRoutingPayload.self, from: payloadData)
        guard result.SchemaVersion == 1,
              result.Products?.contains(product) != false,
              !result.Endpoints.filter({ $0.Enabled }).isEmpty,
              result.Endpoints.filter({ $0.Enabled }).allSatisfy(Self.isAllowedEndpoint)
        else { throw URLError(.unsupportedURL) }
        return result
    }

    private func enabledEndpoint(_ id: String, in payload: AppRoutingPayload) -> AppRoutingEndpoint? {
        payload.Endpoints.first { $0.Enabled && $0.Id == id }
    }

    private func install(_ cache: AppRoutingCache, payload: AppRoutingPayload) {
        guard let endpoint = enabledEndpoint(cache.selectedEndpointId, in: payload),
              let url = URL(string: endpoint.BaseUrl) else { return }
        AppAPIRoutingSnapshot.install(
            baseURL: url,
            endpointID: endpoint.Id,
            role: endpoint.role,
            displayName: endpoint.displayName,
            configVersion: payload.ConfigVersion,
            fetchedAt: cache.fetchedAt
        )
    }

    private func persist(_ cache: AppRoutingCache) {
        guard let data = try? encoder.encode(cache) else { return }
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
    }

    private var cacheURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appending(path: "AppAPIRouting").appending(path: "\(product.isEmpty ? "default" : product).json")
    }

    private func isRetryable(statusCode: Int?, error: Error?) -> Bool {
        if let statusCode { return statusCode == 502 || statusCode == 503 || statusCode == 504 }
        guard let error else { return false }
        let nsError = error as NSError
        let code = (error as? URLError)?.code
            ?? (nsError.domain == NSURLErrorDomain ? URLError.Code(rawValue: nsError.code) : nil)
        return code == .cannotFindHost || code == .cannotConnectToHost
            || code == .dnsLookupFailed || code == .timedOut
            || code == .secureConnectionFailed || code == .networkConnectionLost
    }

    private func rewrite(_ url: URL, from oldBase: URL, to newBase: URL) -> URL? {
        let source = oldBase.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let absolute = url.absoluteString
        guard absolute.hasPrefix(source) else { return nil }
        let suffix = String(absolute.dropFirst(source.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(newBase.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(suffix)")
    }

    private static func isAllowedEndpoint(_ endpoint: AppRoutingEndpoint) -> Bool {
        guard let url = URL(string: endpoint.BaseUrl),
              url.scheme == "https" else { return false }
        let normalized = endpoint.BaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalized == "https://gateway.jaronsoft.com/ais"
            || normalized == "https://ais.get-free.net"
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        return Data(base64Encoded: base64)
    }
}
