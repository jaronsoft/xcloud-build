import Foundation
import Observation

@MainActor
@Observable
final class TenantStore {
    private(set) var tenants: [TenantSummary] = []
    private(set) var selectedTenant: TenantSummary?
    private(set) var recentTenants: [TenantSummary] = []
    var isLoading = false
    var errorMessage: String?

    private let client: APIClient
    private let defaults: UserDefaults

    init(
        client: APIClient = APIClient(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults
        restoreRecentTenants()
    }

    func loadTenants(
        session: SessionStore,
        keyword: String = "",
        selectsDefaultTenant: Bool = false
    ) async {
        guard session.mode == .system else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var context = session.context
            context.tenantID = nil
            let list: [TenantSummary] = try await client.get(
                "/KnowledgeAccess/MyTenants",
                context: context,
                as: [TenantSummary].self
            )
            tenants = list
            if selectsDefaultTenant,
               selectedTenant == nil,
               let defaultTenant = list.first {
                _ = await select(defaultTenant, session: session)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPublicTenants(keyword: String = "") async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page: TenantPage = try await client.get(
                "/KnowledgeAccess/PublicTenants",
                queryItems: [
                    URLQueryItem(name: "page", value: "1"),
                    URLQueryItem(name: "size", value: "100"),
                    URLQueryItem(name: "key", value: keyword),
                ],
                as: TenantPage.self
            )
            tenants = page.data
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resolveStandaloneTenant() async -> TenantSummary? {
        do {
            let runtime: TenancyPublicContext = try await client.get(
                "/Tenancy/public-context",
                as: TenancyPublicContext.self
            )
            guard runtime.Mode == "Standalone",
                  let tenantID = runtime.KnowledgeTenantId else {
                return nil
            }
            let info: TenantPublicInfo = try await client.get(
                "/KnowledgeMember/GetTenantPublicInfo",
                queryItems: [URLQueryItem(name: "tenantId", value: tenantID)],
                as: TenantPublicInfo.self
            )
            tenants = [info.summary]
            return info.summary
        } catch {
            // 兼容尚未提供运行上下文接口的旧服务端，保留原访问码流程。
            return nil
        }
    }

    func select(_ tenant: TenantSummary, session: SessionStore) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var context = session.context
            context.tenantID = tenant.id
            let info: TenantPublicInfo = try await client.get(
                "/KnowledgeMember/GetTenantPublicInfo",
                queryItems: [URLQueryItem(name: "tenantId", value: tenant.id)],
                context: context,
                as: TenantPublicInfo.self
            )
            setSelected(info.summary)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func selectGuest(_ tenant: TenantSummary) {
        setSelected(tenant)
    }

    func switchTenant() {
        selectedTenant = nil
        defaults.removeObject(forKey: Keys.selectedTenant)
    }

    func clearDirectoryCache() {
        tenants = []
    }

    func reset() {
        switchTenant()
        tenants = []
        recentTenants = []
        defaults.removeObject(forKey: Keys.recentTenants)
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("aik.skipped-session.") {
            defaults.removeObject(forKey: key)
        }
    }

    func prepareForSignedOut() {
        switchTenant()
        tenants = []
    }

    func context(for session: SessionStore) -> APIRequestContext {
        var context = session.context
        context.tenantID = selectedTenant?.id
        return context
    }

    private func setSelected(_ tenant: TenantSummary) {
        selectedTenant = tenant
        persist(tenant, key: Keys.selectedTenant)
        recentTenants.removeAll { $0.id == tenant.id }
        recentTenants.insert(tenant, at: 0)
        recentTenants = Array(recentTenants.prefix(6))
        if let data = try? JSONEncoder().encode(recentTenants) {
            defaults.set(data, forKey: Keys.recentTenants)
        }
    }

    private func restoreRecentTenants() {
        if let data = defaults.data(forKey: Keys.recentTenants),
           let decoded = try? JSONDecoder().decode(
               [TenantSummary].self,
               from: data
           ) {
            recentTenants = decoded
        }
        if let data = defaults.data(forKey: Keys.selectedTenant),
           let decoded = try? JSONDecoder().decode(
               TenantSummary.self,
               from: data
           ) {
            selectedTenant = decoded
        }
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private enum Keys {
        static let selectedTenant = "aik.selected-tenant"
        static let recentTenants = "aik.recent-tenants"
    }
}
