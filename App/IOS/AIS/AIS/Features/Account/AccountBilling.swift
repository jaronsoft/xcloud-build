import Observation
import SwiftUI

struct AISBalanceSummary: Codable {
    let balancePoints: Int
    let subscriptionPoints: Int
    let frozenPoints: Int
    let availablePoints: Int
    let effectiveMembershipBenefitName: String?
    let subscriptionPointsExpiresAt: String?
    let rechargeMembershipDiscountPercent: Decimal?
    let subscriptionDiscountPercent: Decimal?
    let effectiveDiscountPercent: Decimal?
    let effectiveBenefitName: String?
    let effectiveBenefitSource: String?
    let discountPolicy: String?

    private enum CodingKeys: String, CodingKey {
        case balancePoints
        case subscriptionPoints
        case frozenPoints
        case availablePoints
        case effectiveMembershipBenefitName
        case subscriptionPointsExpiresAt
        case rechargeMembershipDiscountPercent
        case subscriptionDiscountPercent
        case effectiveDiscountPercent
        case effectiveBenefitName
        case effectiveBenefitSource
        case discountPolicy
    }
}

struct AISMembershipSummary: Codable {
    let currentLevelCode: String?
    let currentLevelName: String?
    let currentDiscountPercent: Decimal
    let nextLevelName: String?
    let remainingAmount: Decimal
    let recommendedPackages: [AISRechargePackage]

    private enum CodingKeys: String, CodingKey {
        case currentLevelCode = "CurrentLevelCode"
        case currentLevelName = "CurrentLevelName"
        case currentDiscountPercent = "CurrentDiscountPercent"
        case nextLevelName = "NextLevelName"
        case remainingAmount = "RemainingAmount"
        case recommendedPackages = "RecommendedPackages"
    }
}

struct AISRechargePackage: Codable, Identifiable, Sendable {
    let packageKey: String?
    let appleProductId: String?
    let iosEnabled: Bool
    let regions: [String]
    let sort: Int
    let ruleVersion: String?
    let amount: Decimal
    let points: Int

    var id: String {
        packageKey ?? appleProductId ?? "\(amount)-\(points)"
    }

    private enum CodingKeys: String, CodingKey {
        case packageKey = "PackageKey"
        case appleProductId = "AppleProductId"
        case iosEnabled = "IosEnabled"
        case regions = "Regions"
        case sort = "Sort"
        case ruleVersion = "RuleVersion"
        case amount = "Amount"
        case points = "Points"
    }
}

struct AISPointTransaction: Codable, Identifiable, Sendable {
    let id: String
    let changePoints: Int
    let balance: Int
    let status: String
    let remark: String?
    let createTime: String

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case changePoints = "ChangePoints"
        case balance = "Balance"
        case status = "Status"
        case remark = "Remark"
        case createTime = "CreateTime"
    }
}

struct AISPointTransactionSummary: Codable, Sendable {
    let date: String
    let recharge: Int
    let consumption: Int
    let frozen: Int
    let gift: Int
    let reward: Int
    let other: Int

    private enum CodingKeys: String, CodingKey {
        case date = "Date", recharge = "Recharge", consumption = "Consumption"
        case frozen = "Frozen", gift = "Gift", reward = "Reward", other = "Other"
    }

    func points(for category: String) -> Int {
        switch category {
        case "recharge": recharge
        case "consumption": consumption
        case "frozen": frozen
        case "gift": gift
        case "reward": reward
        default: other
        }
    }
}

@MainActor
@Observable
final class AccountBillingViewModel {
    private let api = APIClient()

    private(set) var balance: AISBalanceSummary?
    private(set) var membership: AISMembershipSummary?
    private(set) var transactions: [AISPointTransaction] = []
    private(set) var transactionSummary: AISPointTransactionSummary?
    private(set) var isLoading = false
    private(set) var isLoadingMoreTransactions = false
    private(set) var hasMoreTransactions = false
    private(set) var transactionLoadError: String?
    private(set) var errorMessage: String?
    private(set) var isRefreshingSummary = false
    private(set) var isRefreshingBalance = false
    private var transactionPage = 0
    private var transactionTotal = 0
    private var transactionStartDate: String?
    private var transactionEndDate: String?
    private var transactionCategory: String?
    private let transactionPageSize = 20

    func load(session: SessionStore, force: Bool = false) async {
        async let summaryLoaded: Bool = loadSummary(
            session: session,
            force: force
        )
        async let transactionsLoaded: Void = loadTransactionsForCurrentUser(
            session: session,
            force: force
        )
        _ = await (summaryLoaded, transactionsLoaded)
    }

    @discardableResult
    func loadSummary(
        session: SessionStore,
        force: Bool = false
    ) async -> Bool {
        guard let token = await session.validAccessToken(),
              let userID = session.user?.id else {
            reset()
            return false
        }
        guard !isRefreshingSummary else { return false }
        isRefreshingSummary = true
        errorMessage = nil
        defer { isRefreshingSummary = false }

        let scope = "user:\(userID)"
        async let balanceResult: Bool = loadBalance(
            token: token,
            scope: scope,
            force: force
        )
        async let membershipResult: Bool = loadMembership(
            token: token,
            scope: scope,
            force: force
        )
        let result = await (balanceResult, membershipResult)
        return result.0 && result.1
    }

    @discardableResult
    func loadBalanceOnly(
        session: SessionStore,
        force: Bool = false
    ) async -> Bool {
        guard let token = await session.validAccessToken(),
              let userID = session.user?.id else {
            balance = nil
            return false
        }
        guard !isRefreshingBalance else { return false }
        isRefreshingBalance = true
        defer { isRefreshingBalance = false }
        return await loadBalance(
            token: token,
            scope: "user:\(userID)",
            force: force
        )
    }

    func loadMoreTransactions(session: SessionStore) async {
        guard hasMoreTransactions, !isLoadingMoreTransactions,
              let token = await session.validAccessToken(),
              let userID = session.user?.id else {
            return
        }
        isLoadingMoreTransactions = true
        transactionLoadError = nil
        defer { isLoadingMoreTransactions = false }
        await loadTransactionPage(
            page: transactionPage + 1,
            token: token,
            scope: "user:\(userID)",
            force: false,
            appends: true
        )
    }

    func refreshTransactions(session: SessionStore) async {
        guard !isLoadingMoreTransactions,
              let token = await session.validAccessToken(),
              let userID = session.user?.id else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        transactionLoadError = nil
        await loadTransactionPage(
            page: 1,
            token: token,
            scope: "user:\(userID)",
            force: true,
            appends: false
        )
    }

    func filterTransactions(startDate: String?, endDate: String?, category: String?, session: SessionStore) async {
        transactionStartDate = startDate
        transactionEndDate = endDate
        transactionCategory = category
        transactions = []
        transactionPage = 0
        await refreshTransactions(session: session)
    }

    func refreshTransactionSummary(session: SessionStore) async {
        guard let token = await session.validAccessToken() else { return }
        do {
            transactionSummary = try await api.get(
                "/api/ais/billing/transactions/today-summary",
                accessToken: token
            )
        } catch {
            transactionSummary = nil
        }
    }

    private func loadBalance(
        token: String,
        scope: String,
        force: Bool
    ) async -> Bool {
        let key = AISResponseCache.key(scope: scope, resource: "balance")
        if !force,
           let cached = await AISResponseCache.shared.read(
               AISBalanceSummary.self,
               key: key,
               allowsStale: true,
               encrypted: true
           ) {
            balance = cached.value
            if cached.isFresh { return true }
        }
        do {
            let value: AISBalanceSummary = try await api.get(
                "/api/ais/balance",
                accessToken: token
            )
            balance = value
            await AISResponseCache.shared.write(value, key: key, encrypted: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func loadMembership(
        token: String,
        scope: String,
        force: Bool
    ) async -> Bool {
        let key = AISResponseCache.key(scope: scope, resource: "membership-ais")
        if !force,
           let cached = await AISResponseCache.shared.read(
               AISMembershipSummary.self,
               key: key,
               allowsStale: true,
               encrypted: true
           ) {
            membership = cached.value
            if cached.isFresh { return true }
        }
        do {
            let previousLevel = membership?.currentLevelCode
            let previousDiscount = membership?.currentDiscountPercent
            let value: AISMembershipSummary = try await api.get(
                "/api/ais/account/membership-progress",
                query: [URLQueryItem(name: "appCode", value: "ais")],
                accessToken: token
            )
            membership = value
            await AISResponseCache.shared.write(value, key: key, encrypted: true)
            if previousLevel != nil
                && (
                    previousLevel != value.currentLevelCode
                        || previousDiscount != value.currentDiscountPercent
                ) {
                NotificationCenter.default.post(
                    name: .aisPricingRulesInvalidated,
                    object: nil
                )
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func loadTransactionsForCurrentUser(
        session: SessionStore,
        force: Bool
    ) async {
        guard let token = await session.validAccessToken(),
              let userID = session.user?.id else {
            transactions = []
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await loadTransactions(
            token: token,
            scope: "user:\(userID)",
            force: force
        )
    }

    private func loadTransactions(
        token: String,
        scope: String,
        force: Bool
    ) async {
        await loadTransactionPage(
            page: 1,
            token: token,
            scope: scope,
            force: force,
            appends: false
        )
    }

    private func loadTransactionPage(
        page: Int,
        token: String,
        scope: String,
        force: Bool,
        appends: Bool
    ) async {
        let language = AISLocalization.isChinese ? "zh" : "en"
        let key = AISResponseCache.key(
            scope: scope,
            resource: "transactions",
            parameters: [
                "page": String(page),
                "size": String(transactionPageSize),
                "lang": language,
                "startDate": transactionStartDate ?? "",
                "endDate": transactionEndDate ?? "",
                "category": transactionCategory ?? ""
            ]
        )
        var appliedCachedPage = false
        if !force,
           let cached = await AISResponseCache.shared.read(
               PageResponse<AISPointTransaction>.self,
               key: key,
               allowsStale: true,
               encrypted: true
           ) {
            applyTransactionPage(cached.value, page: page, appends: appends)
            appliedCachedPage = true
            if cached.isFresh { return }
        }
        do {
            let value: PageResponse<AISPointTransaction> = try await api.get(
                "/api/ais/billing/transactions/query",
                query: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "size", value: String(transactionPageSize)),
                    URLQueryItem(name: "lang", value: language),
                    URLQueryItem(name: "startDate", value: transactionStartDate),
                    URLQueryItem(name: "endDate", value: transactionEndDate),
                    URLQueryItem(name: "category", value: transactionCategory)
                ],
                accessToken: token
            )
            applyTransactionPage(value, page: page, appends: appends)
            await AISResponseCache.shared.write(value, key: key, encrypted: true)
        } catch {
            if appends, !appliedCachedPage {
                transactionLoadError = error.localizedDescription
            } else if !appliedCachedPage {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyTransactionPage(
        _ response: PageResponse<AISPointTransaction>,
        page: Int,
        appends: Bool
    ) {
        if appends {
            var existingIDs = Set(transactions.map(\.id))
            transactions.append(
                contentsOf: response.items.filter { existingIDs.insert($0.id).inserted }
            )
        } else {
            transactions = response.items
        }
        transactionPage = page
        transactionTotal = response.total
        hasMoreTransactions = transactions.count < transactionTotal
            && !response.items.isEmpty
        transactionLoadError = nil
    }

    func reset() {
        balance = nil
        membership = nil
        transactions = []
        transactionSummary = nil
        transactionStartDate = nil
        transactionEndDate = nil
        transactionCategory = nil
        isLoading = false
        isRefreshingSummary = false
        isRefreshingBalance = false
        isLoadingMoreTransactions = false
        hasMoreTransactions = false
        transactionLoadError = nil
        transactionPage = 0
        transactionTotal = 0
        errorMessage = nil
    }
}

struct AccountTransactionsView: View {
    @Environment(SessionStore.self) private var session
    let model: AccountBillingViewModel
    @State private var startDate = Date.now.addingTimeInterval(-29 * 86_400)
    @State private var endDate = Date.now
    @State private var dateError = false
    @State private var selectedCategory = "all"

    private let categories = ["recharge", "consumption", "frozen", "gift", "reward", "other"]

    var body: some View {
        List {
            Section {
                if let summary = model.transactionSummary {
                    Text("account.transactions.today")
                        .font(.headline)
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                        ForEach(categories, id: \.self) { category in
                            Button {
                                selectedCategory = category
                                Task {
                                    await model.filterTransactions(
                                        startDate: summary.date,
                                        endDate: summary.date,
                                        category: category,
                                        session: session
                                    )
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(categoryTitle(for: category))
                                        .font(.caption)
                                    Text(summary.points(for: category).formatted())
                                        .font(.title3.weight(.bold).monospacedDigit())
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(AISTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Section {
                DatePicker("account.transactions.start", selection: $startDate, displayedComponents: .date)
                DatePicker("account.transactions.end_date", selection: $endDate, displayedComponents: .date)
                Picker("account.transactions.filter_category", selection: $selectedCategory) {
                    Text("account.transactions.all_categories").tag("all")
                    ForEach(categories, id: \.self) { category in
                        Text(categoryTitle(for: category))
                            .tag(category)
                    }
                }
                if dateError {
                    Text("account.transactions.range_error")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("account.transactions.search") {
                        let days = Calendar.current.dateComponents(
                            [.day], from: Calendar.current.startOfDay(for: startDate),
                            to: Calendar.current.startOfDay(for: endDate)
                        ).day ?? -1
                        guard days >= 0, days < 90, endDate <= .now else {
                            dateError = true
                            return
                        }
                        dateError = false
                        Task {
                            await model.filterTransactions(startDate: dateString(startDate), endDate: dateString(endDate), category: selectedCategory == "all" ? nil : selectedCategory, session: session)
                        }
                    }
                    Spacer()
                    Button("account.transactions.last_30_days") {
                        dateError = false
                        selectedCategory = "all"
                        Task { await model.filterTransactions(startDate: nil, endDate: nil, category: nil, session: session) }
                    }
                }
            }
            if model.transactions.isEmpty && !model.isLoading {
                ContentUnavailableView(
                    "account.transactions.empty",
                    systemImage: "list.bullet.rectangle"
                )
            }
            ForEach(model.transactions) { transaction in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transaction.remark ?? transaction.status)
                            .font(.subheadline.weight(.semibold))
                        Text(transaction.createTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(
                            transaction.changePoints > 0
                                ? "+\(transaction.changePoints)"
                                : "\(transaction.changePoints)"
                        )
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(
                            transaction.changePoints >= 0 ? .green : AISTheme.accent
                        )
                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "account.balance_after"),
                                transaction.balance
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            transactionFooter
        }
        .navigationTitle("account.transactions")
        .task {
            await model.refreshTransactionSummary(session: session)
            if model.transactions.isEmpty {
                await model.refreshTransactions(session: session)
            }
        }
        .refreshable {
            await model.refreshTransactionSummary(session: session)
            await model.refreshTransactions(session: session)
        }
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func categoryTitle(for category: String) -> LocalizedStringKey {
        switch category {
        case "recharge": "account.transactions.category.recharge"
        case "consumption": "account.transactions.category.consumption"
        case "frozen": "account.transactions.category.frozen"
        case "gift": "account.transactions.category.gift"
        case "reward": "account.transactions.category.reward"
        default: "account.transactions.category.other"
        }
    }

    @ViewBuilder
    private var transactionFooter: some View {
        if let error = model.transactionLoadError {
            VStack(spacing: 8) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("common.retry") {
                    Task {
                        await model.loadMoreTransactions(session: session)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
        } else if model.hasMoreTransactions {
            HStack(spacing: 8) {
                ProgressView()
                Text("account.transactions.loading_more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            .task(id: model.transactions.count) {
                await model.loadMoreTransactions(session: session)
            }
        } else if !model.transactions.isEmpty {
            Text("account.transactions.end")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
        }
    }
}
