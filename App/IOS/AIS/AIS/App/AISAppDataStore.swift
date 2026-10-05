import Foundation
import Observation

struct AISAccountProfile: Codable {
    let email: String?
    let displayName: String?
    let countryCode: String?
    let effectiveMembershipLevel: String?
    let effectiveMembershipBenefitCode: String?
    let effectiveMembershipBenefitName: String?

    private enum CodingKeys: String, CodingKey {
        case email = "Email"
        case emailLower = "email"
        case displayName = "DisplayName"
        case displayNameLower = "displayName"
        case countryCode = "CountryCode"
        case countryCodeLower = "countryCode"
        case effectiveMembershipLevel = "EffectiveMembershipLevel"
        case effectiveMembershipLevelLower = "effectiveMembershipLevel"
        case effectiveMembershipBenefitCode = "EffectiveMembershipBenefitCode"
        case effectiveMembershipBenefitCodeLower =
            "effectiveMembershipBenefitCode"
        case effectiveMembershipBenefitName = "EffectiveMembershipBenefitName"
        case effectiveMembershipBenefitNameLower =
            "effectiveMembershipBenefitName"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        email = try values.decodeIfPresent(String.self, forKey: .email)
            ?? values.decodeIfPresent(String.self, forKey: .emailLower)
        displayName = try values.decodeIfPresent(
            String.self,
            forKey: .displayName
        ) ?? values.decodeIfPresent(String.self, forKey: .displayNameLower)
        countryCode = try values.decodeIfPresent(
            String.self,
            forKey: .countryCode
        ) ?? values.decodeIfPresent(String.self, forKey: .countryCodeLower)
        effectiveMembershipLevel = try values.decodeIfPresent(
            String.self,
            forKey: .effectiveMembershipLevel
        ) ?? values.decodeIfPresent(
            String.self,
            forKey: .effectiveMembershipLevelLower
        )
        effectiveMembershipBenefitCode = try values.decodeIfPresent(
            String.self,
            forKey: .effectiveMembershipBenefitCode
        ) ?? values.decodeIfPresent(
            String.self,
            forKey: .effectiveMembershipBenefitCodeLower
        )
        effectiveMembershipBenefitName = try values.decodeIfPresent(
            String.self,
            forKey: .effectiveMembershipBenefitName
        ) ?? values.decodeIfPresent(
            String.self,
            forKey: .effectiveMembershipBenefitNameLower
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(email, forKey: .emailLower)
        try values.encodeIfPresent(displayName, forKey: .displayNameLower)
        try values.encodeIfPresent(countryCode, forKey: .countryCodeLower)
        try values.encodeIfPresent(
            effectiveMembershipLevel,
            forKey: .effectiveMembershipLevelLower
        )
        try values.encodeIfPresent(
            effectiveMembershipBenefitCode,
            forKey: .effectiveMembershipBenefitCodeLower
        )
        try values.encodeIfPresent(
            effectiveMembershipBenefitName,
            forKey: .effectiveMembershipBenefitNameLower
        )
    }
}

@MainActor
@Observable
final class AISTemplateCategoriesStore {
    private let api = APIClient()

    private(set) var groups: [StyleTemplateFilterGroup] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var loadGeneration = 0

    @discardableResult
    func load(region: StyleTemplateMarketRegion, force: Bool = false) async -> Bool {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        let key = AISResponseCache.key(
            scope: "public",
            resource: "style-template-filter-groups",
            parameters: ["region": region.rawValue]
        )
        if !force,
           let cached = await AISResponseCache.shared.read(
               [StyleTemplateFilterGroup].self,
               key: key,
               allowsStale: true
           ) {
            guard generation == loadGeneration else { return false }
            groups = cached.value
            if cached.isFresh { return true }
        }
        do {
            let latest: [StyleTemplateFilterGroup] = try await api.get(
                "/api/ais/style-templates/categories",
                query: [
                    URLQueryItem(name: "templateType", value: "image"),
                    URLQueryItem(name: "region", value: region.rawValue)
                ]
            )
            guard generation == loadGeneration else { return false }
            groups = latest
            await AISResponseCache.shared.write(latest, key: key)
            return true
        } catch {
            if generation == loadGeneration {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }
}

@MainActor
@Observable
final class AISAppDataStore {
    enum UserDataState: Equatable {
        case idle
        case loading
        case ready
        case failed
    }

    let billing = AccountBillingViewModel()
    let configuration = AISCreationConfigurationStore()
    let pricingRules = AISPricingRulesStore()
    let templateCategories = AISTemplateCategoriesStore()
    let durationEstimates = AISDurationEstimateStore()

    private let api = APIClient()
    private(set) var profile: AISAccountProfile?
    private(set) var userDataState = UserDataState.idle
    private(set) var isRefreshingPoints = false
    private var loadedUserID: String?
    private var pendingBalanceRefresh = false
    private var pendingFullUserRefresh = false

    var isRefreshingUserData: Bool {
        userDataState == .loading || isRefreshingPoints
    }

    var isGenerationReady: Bool {
        userDataState == .ready
            && !isRefreshingPoints
            && profile != nil
            && billing.balance != nil
            && billing.membership != nil
            && !configuration.isLoading
            && configuration.canSubmit
            && !pricingRules.isLoading
            && pricingRules.rules != nil
    }

    var generationLoadFailed: Bool {
        userDataState == .failed
            || configuration.errorMessage != nil
            || pricingRules.errorMessage != nil
    }

    func preload(session: SessionStore) async {
        guard session.isAuthenticated, let userID = session.user?.id else {
            resetUserData()
            async let configurationLoad: Void = loadCreationConfiguration(
                session: session,
                force: false
            )
            async let categoryLoad: Bool = templateCategories.load(
                region: .current
            )
            _ = await (configurationLoad, categoryLoad)
            return
        }
        if loadedUserID != userID {
            reset()
            loadedUserID = userID
        }

        async let userRefresh: Void = refreshUserData(
            session: session,
            force: true
        )
        async let configurationLoad: Void = loadCreationConfiguration(
            session: session,
            force: false
        )
        async let pricingLoad: Void = loadPricingRules(
            session: session,
            force: false
        )
        async let categoryLoad: Bool = templateCategories.load(
            region: .current
        )
        _ = await (
            userRefresh,
            configurationLoad,
            pricingLoad,
            categoryLoad
        )
    }

    func refreshUserData(
        session: SessionStore,
        force: Bool = true
    ) async {
        guard session.isAuthenticated, let userID = session.user?.id else {
            resetUserData()
            return
        }
        guard userDataState != .loading else {
            pendingFullUserRefresh = true
            return
        }
        loadedUserID = userID
        userDataState = .loading

        async let profileLoaded = loadProfile(
            session: session,
            userID: userID,
            force: force
        )
        async let summaryLoaded = billing.loadSummary(
            session: session,
            force: force
        )
        let result = await (profileLoaded, summaryLoaded)
        userDataState = result.0 && result.1 ? .ready : .failed

        if pendingFullUserRefresh {
            pendingFullUserRefresh = false
            await refreshUserData(session: session, force: true)
        } else if pendingBalanceRefresh {
            pendingBalanceRefresh = false
            await refreshPoints(session: session)
        }
    }

    func refreshPoints(session: SessionStore) async {
        guard session.isAuthenticated else {
            resetUserData()
            return
        }
        guard userDataState != .loading else {
            pendingBalanceRefresh = true
            return
        }
        guard !isRefreshingPoints else {
            pendingBalanceRefresh = true
            return
        }
        isRefreshingPoints = true
        let loaded = await billing.loadBalanceOnly(
            session: session,
            force: true
        )
        isRefreshingPoints = false
        if !loaded {
            userDataState = .failed
        }

        if pendingBalanceRefresh {
            pendingBalanceRefresh = false
            await refreshPoints(session: session)
        }
    }

    func refreshAfterRecharge(session: SessionStore) async {
        await refreshUserData(session: session, force: true)
    }

    func retryGenerationPrerequisites(session: SessionStore) async {
        async let userRefresh: Void = refreshUserData(
            session: session,
            force: true
        )
        async let configurationLoad: Void = loadCreationConfiguration(
            session: session,
            force: true
        )
        async let pricingLoad: Void = loadPricingRules(
            session: session,
            force: true
        )
        _ = await (userRefresh, configurationLoad, pricingLoad)
    }

    func refreshPricingRules(session: SessionStore) async {
        await loadPricingRules(session: session, force: true)
    }

    private func loadProfile(
        session: SessionStore,
        userID: String,
        force: Bool
    ) async -> Bool {
        let key = AISResponseCache.key(
            scope: "user:\(userID)",
            resource: "account-profile"
        )
        if let cached = await AISResponseCache.shared.read(
            AISAccountProfile.self,
            key: key,
            allowsStale: true,
            encrypted: true
        ) {
            applyProfile(cached.value, to: session)
            if cached.isFresh && !force { return true }
        }
        guard let token = await session.validAccessToken() else {
            return false
        }
        do {
            let latest: AISAccountProfile = try await api.get(
                "/api/ais/account",
                accessToken: token
            )
            applyProfile(latest, to: session)
            await AISResponseCache.shared.write(
                latest,
                key: key,
                encrypted: true
            )
            return true
        } catch {
            return false
        }
    }

    private func applyProfile(
        _ value: AISAccountProfile,
        to session: SessionStore
    ) {
        profile = value
        session.applyAccountProfile(
            email: value.email,
            displayName: value.displayName,
            countryCode: value.countryCode
        )
    }

    private func loadCreationConfiguration(
        session: SessionStore,
        force: Bool
    ) async {
        let token = await session.validAccessToken()
        await configuration.load(
            userID: session.user?.id,
            accessToken: token,
            force: force
        )
    }

    private func loadPricingRules(
        session: SessionStore,
        force: Bool
    ) async {
        let token = await session.validAccessToken()
        await pricingRules.load(
            userID: session.user?.id,
            accessToken: token,
            force: force
        )
    }

    func reset() {
        resetUserData()
        configuration.reset()
    }

    private func resetUserData() {
        profile = nil
        userDataState = .idle
        isRefreshingPoints = false
        loadedUserID = nil
        pendingBalanceRefresh = false
        pendingFullUserRefresh = false
        billing.reset()
        pricingRules.reset()
    }
}
