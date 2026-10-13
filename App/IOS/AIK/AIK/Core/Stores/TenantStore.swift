import Foundation
import Observation

@MainActor
@Observable
final class TenantStore {
    private(set) var tenants: [TenantSummary] = []
    private(set) var selectedTenant: TenantSummary?
    private(set) var recentTenants: [TenantSummary] = []
    private(set) var pinnedTenantIDs: Set<String> = []
    var orderedRecentTenants: [TenantSummary] {
        recentTenants.filter { isPinned($0) } + recentTenants.filter { !isPinned($0) }
    }
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

    func removeRecentTenant(_ tenant: TenantSummary) {
        recentTenants.removeAll { $0.id == tenant.id }
        pinnedTenantIDs.remove(tenant.id)
        persist(Array(pinnedTenantIDs), key: Keys.pinnedTenantIDs)
        persist(recentTenants, key: Keys.recentTenants)
    }

    func isPinned(_ tenant: TenantSummary) -> Bool {
        pinnedTenantIDs.contains(tenant.id)
    }

    func togglePinned(_ tenant: TenantSummary) {
        guard recentTenants.contains(where: { $0.id == tenant.id }) else { return }
        if isPinned(tenant) {
            pinnedTenantIDs.remove(tenant.id)
        } else {
            pinnedTenantIDs.insert(tenant.id)
        }
        trimRecentTenants()
        persist(Array(pinnedTenantIDs), key: Keys.pinnedTenantIDs)
        persist(recentTenants, key: Keys.recentTenants)
    }

    func reset() {
        switchTenant()
        tenants = []
        recentTenants = []
        pinnedTenantIDs = []
        defaults.removeObject(forKey: Keys.recentTenants)
        defaults.removeObject(forKey: Keys.pinnedTenantIDs)
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
        trimRecentTenants()
        persist(recentTenants, key: Keys.recentTenants)
    }

    private func trimRecentTenants() {
        // 置顶记录不被新访问挤出，其余记录继续保留最近六条。
        let recentIDs = Set(recentTenants.filter { !isPinned($0) }.prefix(6).map(\.id))
        recentTenants.removeAll { !isPinned($0) && !recentIDs.contains($0.id) }
    }

    private func restoreRecentTenants() {
        if let data = defaults.data(forKey: Keys.pinnedTenantIDs),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            pinnedTenantIDs = Set(decoded)
        }
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
        static let pinnedTenantIDs = "aik.pinned-tenant-ids"
    }
}
