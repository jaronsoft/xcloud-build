import Observation
import SwiftUI

struct PixaPointTransaction: Decodable, Identifiable, Sendable {
    let id: String
    let changePoints: Int
    let balance: Int
    let status: String
    let remark: String?
    let createTime: String

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case idLower = "id"
        case changePoints = "ChangePoints"
        case changePointsLower = "changePoints"
        case balance = "Balance"
        case balanceLower = "balance"
        case status = "Status"
        case statusLower = "status"
        case remark = "Remark"
        case remarkLower = "remark"
        case createTime = "CreateTime"
        case createTimeLower = "createTime"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decodeFlexibleString(forKey: .id)
            ?? box.decodeFlexibleString(forKey: .idLower)
            ?? UUID().uuidString
        changePoints = try box.decodeIfPresent(Int.self, forKey: .changePoints)
            ?? box.decodeIfPresent(Int.self, forKey: .changePointsLower)
            ?? 0
        balance = try box.decodeIfPresent(Int.self, forKey: .balance)
            ?? box.decodeIfPresent(Int.self, forKey: .balanceLower)
            ?? 0
        status = try box.decodeIfPresent(String.self, forKey: .status)
            ?? box.decodeIfPresent(String.self, forKey: .statusLower)
            ?? ""
        remark = try box.decodeIfPresent(String.self, forKey: .remark)
            ?? box.decodeIfPresent(String.self, forKey: .remarkLower)
        createTime = try box.decodeIfPresent(String.self, forKey: .createTime)
            ?? box.decodeIfPresent(String.self, forKey: .createTimeLower)
            ?? ""
    }
}

private struct PixaPointSummary: Decodable {
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
private final class PixaPointTransactionsViewModel {
    private let api = APIClient()
    private let pageSize = 20
    private var page = 0
    private var total = 0
    private var startDate: String?
    private var endDate: String?
    private var category: String?

    private(set) var transactions: [PixaPointTransaction] = []
    private(set) var summary: PixaPointSummary?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var errorMessage: String?

    func load(session: SessionStore) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        await loadSummary(session: session)
        await loadPage(1, session: session, appends: false)
    }

    func filter(startDate: String?, endDate: String?, category: String?, session: SessionStore) async {
        self.startDate = startDate
        self.endDate = endDate
        self.category = category
        transactions = []
        page = 0
        await load(session: session)
    }

    private func loadSummary(session: SessionStore) async {
        guard let token = await session.validAccessToken() else { return }
        do {
            summary = try await api.get(
                "/api/ais/billing/transactions/today-summary",
                token: token,
                forceRefresh: true
            )
        } catch {
            summary = nil
        }
    }

    func loadMore(session: SessionStore) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }
        await loadPage(page + 1, session: session, appends: true)
    }

    private func loadPage(
        _ requestedPage: Int,
        session: SessionStore,
        appends: Bool
    ) async {
        guard let token = await session.validAccessToken() else {
            transactions = []
            hasMore = false
            return
        }

        do {
            let response: PageResponse<PixaPointTransaction> = try await api.get(
                "/api/ais/billing/transactions/query",
                query: [
                    URLQueryItem(name: "page", value: String(requestedPage)),
                    URLQueryItem(name: "size", value: String(pageSize)),
                    URLQueryItem(name: "lang", value: AppLanguage.apiValue),
                    URLQueryItem(name: "startDate", value: startDate),
                    URLQueryItem(name: "endDate", value: endDate),
                    URLQueryItem(name: "category", value: category)
                ],
                token: token,
                forceRefresh: !appends
            )
            if appends {
                var existingIDs = Set(transactions.map(\.id))
                transactions.append(
                    contentsOf: response.items.filter {
                        existingIDs.insert($0.id).inserted
                    }
                )
            } else {
                transactions = response.items
            }
            page = requestedPage
            total = response.total
            hasMore = transactions.count < total && !response.items.isEmpty
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PixaPointTransactionsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PixaLanguageStore.self) private var language
    @State private var model = PixaPointTransactionsViewModel()
    @State private var startDate = Date.now.addingTimeInterval(-29 * 86_400)
    @State private var endDate = Date.now
    @State private var dateError = false
    @State private var selectedCategory = "all"

    private let categories = ["recharge", "consumption", "frozen", "gift", "reward", "other"]

    var body: some View {
        List {
            summarySection
            dateSection
            if model.isLoading && model.transactions.isEmpty {
                ProgressView("common.loading")
                    .frame(maxWidth: .infinity)
            } else if model.transactions.isEmpty {
                emptyState
            } else {
                ForEach(model.transactions) { transaction in
                    transactionRow(transaction)
                }
            }
            footer
        }
        .scrollContentBackground(.hidden)
        .background(PixaTheme.paper)
        .navigationTitle("account.transactions")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.load(session: session)
        }
        .task(id: language.preference) {
            await model.load(session: session)
        }
    }

    private var summarySection: some View {
        Section {
            if let summary = model.summary {
                Text("account.transactions.today")
                    .font(.headline)
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                    ForEach(categories, id: \.self) { category in
                        Button {
                            selectedCategory = category
                            Task {
                                await model.filter(
                                    startDate: summary.date,
                                    endDate: summary.date,
                                    category: category,
                                    session: session
                                )
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(AppLanguage.localized("account.transactions.category.\(category)"))
                                    .font(.caption)
                                Text(summary.points(for: category).formatted())
                                    .font(.title3.weight(.bold).monospacedDigit())
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(PixaTheme.paper, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var dateSection: some View {
        Section {
            DatePicker("account.transactions.start", selection: $startDate, displayedComponents: .date)
            DatePicker("account.transactions.end_date", selection: $endDate, displayedComponents: .date)
            Picker("account.transactions.filter_category", selection: $selectedCategory) {
                Text("account.transactions.all_categories").tag("all")
                ForEach(categories, id: \.self) { category in
                    Text(AppLanguage.localized("account.transactions.category.\(category)"))
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
                        await model.filter(startDate: dateString(startDate), endDate: dateString(endDate), category: selectedCategory == "all" ? nil : selectedCategory, session: session)
                    }
                }
                Spacer()
                Button("account.transactions.last_30_days") {
                    dateError = false
                    selectedCategory = "all"
                    Task { await model.filter(startDate: nil, endDate: nil, category: nil, session: session) }
                }
            }
        }
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func transactionRow(_ transaction: PixaPointTransaction) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(transaction.remark?.nilIfEmpty ?? transaction.status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PixaTheme.ink)
                Text(transaction.createTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                Text(transaction.changePoints > 0
                     ? "+\(transaction.changePoints)"
                     : "\(transaction.changePoints)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(
                        transaction.changePoints >= 0 ? .green : PixaTheme.accent
                    )
                Text(
                    String.localizedStringWithFormat(
                        AppLanguage.localized("account.balance_after"),
                        transaction.balance
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var footer: some View {
        if !model.transactions.isEmpty, let error = model.errorMessage {
            VStack(spacing: 8) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("common.retry") {
                    Task { await model.load(session: session) }
                }
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
        } else if model.hasMore {
            HStack(spacing: 8) {
                ProgressView()
                Text("account.transactions.loading_more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            .task(id: model.transactions.count) {
                await model.loadMore(session: session)
            }
        } else if !model.transactions.isEmpty {
            Text("account.transactions.end")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let error = model.errorMessage {
            ContentUnavailableView {
                Label("common.error", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("common.retry") {
                    Task { await model.load(session: session) }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "account.transactions.empty.title",
                systemImage: "list.bullet.rectangle",
                description: Text("account.transactions.empty.message")
            )
        }
    }
}
