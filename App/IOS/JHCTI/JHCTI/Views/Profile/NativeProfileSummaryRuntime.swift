import Combine
import Foundation

@MainActor
final class NativeProfileSummaryRuntime: ObservableObject {
    @Published private(set) var tourismProfile: [String: Any]?
    @Published private(set) var memberLevel = "普通会员"
    @Published private(set) var workAccess: [String] = []
    @Published private(set) var error: String?

    private let store: SessionStore

    init(store: SessionStore) {
        self.store = store
    }

    func load() async {
        tourismProfile = nil
        memberLevel = "普通会员"
        workAccess = []
        error = nil
        guard let token = store.session?.accessToken, let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        let api = MobileAPI(store: store)
        do {
            let profile = try await api.get("/api/JHCTITourismAuth/GetMyProfile", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any]
            guard store.session?.accessToken == token else { return }
            tourismProfile = profile
        } catch {
            if store.session?.accessToken == token { self.error = error.localizedDescription }
            return
        }
        if let summary = try? await api.get("/api/JHCTIMemberProgram/GetMySummary", authenticated: true,
            expectedPrincipal: expectedPrincipal) as? [String: Any],
           let level = summary["CurrentLevel"] as? [String: Any], let name = level["Name"] as? String,
           !name.isEmpty, store.session?.accessToken == token { memberLevel = name }
        var verified: [String] = []
        if let diningRoles = try? await api.get("/api/JHCTIDining/GetMyWorkRoles", authenticated: true,
            expectedPrincipal: expectedPrincipal) as? [[String: Any]],
           !diningRoles.isEmpty { verified.append("餐饮工作台") }
        if let merchants = try? await api.get("/api/JHCTIMerchant/GetWorkbenchMerchantOptions", authenticated: true,
            expectedPrincipal: expectedPrincipal) as? [[String: Any]],
           !merchants.isEmpty { verified.append("商户工作台") }
        if await api.featureEnabled("F-OPS-012"),
           let coupons = try? await api.get("/api/JHCTICouponClaim/GetRedemptionMerchantOptions?page=1&pageSize=50", authenticated: true) as? [String: Any],
           (coupons["data"] as? [[String: Any]])?.isEmpty == false { verified.append("平台消费券核销") }
        if let activities = try? await api.get("/api/JHCTIActivity/GetMyAssignedVerificationActivities", authenticated: true,
            expectedPrincipal: expectedPrincipal) as? [[String: Any]],
           !activities.isEmpty { verified.append("活动现场签到") }
        if await api.featureEnabled("F-TKT-004"),
           let points = try? await api.get("/api/JHCTITicket/GetMyVerificationPoints", authenticated: true,
            expectedPrincipal: expectedPrincipal) as? [[String: Any]],
           !points.isEmpty { verified.append("门票核销") }
        if store.session?.accessToken == token { workAccess = verified }
    }
}
