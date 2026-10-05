import Observation
import SwiftUI

private struct MembershipTier: Decodable, Identifiable, Sendable {
    let code: String
    let name: String
    let thresholdAmount: Decimal
    let discountPercent: Decimal
    var id: String { code }

    private enum CodingKeys: String, CodingKey {
        case code = "Code", codeLower = "code"
        case name = "Name", nameLower = "name"
        case thresholdAmount = "ThresholdAmount", thresholdAmountLower = "thresholdAmount"
        case discountPercent = "DiscountPercent", discountPercentLower = "discountPercent"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        code = try values.decodeIfPresent(String.self, forKey: .code)
            ?? values.decodeIfPresent(String.self, forKey: .codeLower) ?? UUID().uuidString
        name = try values.decodeIfPresent(String.self, forKey: .name)
            ?? values.decodeIfPresent(String.self, forKey: .nameLower) ?? code
        thresholdAmount = try values.decodeIfPresent(Decimal.self, forKey: .thresholdAmount)
            ?? values.decodeIfPresent(Decimal.self, forKey: .thresholdAmountLower) ?? 0
        discountPercent = try values.decodeIfPresent(Decimal.self, forKey: .discountPercent)
            ?? values.decodeIfPresent(Decimal.self, forKey: .discountPercentLower) ?? 0
    }
}

private struct MembershipProgress: Decodable, Sendable {
    let currency: String
    let countryCode: String
    let currentLevelName: String?
    let currentLevelCode: String?
    let currentDiscountPercent: Decimal
    let nextLevelName: String?
    let nextLevelCode: String?
    let nextThresholdAmount: Decimal?
    let cumulativeRechargeAmount: Decimal
    let remainingAmount: Decimal
    let membershipLevelSource: String?
    let tiers: [MembershipTier]

    private enum CodingKeys: String, CodingKey {
        case currency = "Currency", currencyLower = "currency"
        case countryCode = "CountryCode", countryCodeLower = "countryCode"
        case currentLevelName = "CurrentLevelName", currentLevelNameLower = "currentLevelName"
        case currentLevelCode = "CurrentLevelCode", currentLevelCodeLower = "currentLevelCode"
        case currentDiscountPercent = "CurrentDiscountPercent", currentDiscountPercentLower = "currentDiscountPercent"
        case nextLevelName = "NextLevelName", nextLevelNameLower = "nextLevelName"
        case nextLevelCode = "NextLevelCode", nextLevelCodeLower = "nextLevelCode"
        case nextThresholdAmount = "NextThresholdAmount", nextThresholdAmountLower = "nextThresholdAmount"
        case cumulativeRechargeAmount = "CumulativeRechargeAmount", cumulativeRechargeAmountLower = "cumulativeRechargeAmount"
        case remainingAmount = "RemainingAmount", remainingAmountLower = "remainingAmount"
        case membershipLevelSource = "MembershipLevelSource", membershipLevelSourceLower = "membershipLevelSource"
        case tiers = "Tiers", tiersLower = "tiers"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currency = try values.decodeIfPresent(String.self, forKey: .currency)
            ?? values.decodeIfPresent(String.self, forKey: .currencyLower) ?? "USD"
        countryCode = try values.decodeIfPresent(String.self, forKey: .countryCode)
            ?? values.decodeIfPresent(String.self, forKey: .countryCodeLower) ?? "US"
        currentLevelName = try values.decodeIfPresent(String.self, forKey: .currentLevelName)
            ?? values.decodeIfPresent(String.self, forKey: .currentLevelNameLower)
        currentLevelCode = try values.decodeIfPresent(String.self, forKey: .currentLevelCode)
            ?? values.decodeIfPresent(String.self, forKey: .currentLevelCodeLower)
        currentDiscountPercent = try values.decodeIfPresent(Decimal.self, forKey: .currentDiscountPercent)
            ?? values.decodeIfPresent(Decimal.self, forKey: .currentDiscountPercentLower) ?? 0
        nextLevelName = try values.decodeIfPresent(String.self, forKey: .nextLevelName)
            ?? values.decodeIfPresent(String.self, forKey: .nextLevelNameLower)
        nextLevelCode = try values.decodeIfPresent(String.self, forKey: .nextLevelCode)
            ?? values.decodeIfPresent(String.self, forKey: .nextLevelCodeLower)
        nextThresholdAmount = try values.decodeIfPresent(Decimal.self, forKey: .nextThresholdAmount)
            ?? values.decodeIfPresent(Decimal.self, forKey: .nextThresholdAmountLower)
        cumulativeRechargeAmount = try values.decodeIfPresent(Decimal.self, forKey: .cumulativeRechargeAmount)
            ?? values.decodeIfPresent(Decimal.self, forKey: .cumulativeRechargeAmountLower) ?? 0
        remainingAmount = try values.decodeIfPresent(Decimal.self, forKey: .remainingAmount)
            ?? values.decodeIfPresent(Decimal.self, forKey: .remainingAmountLower) ?? 0
        membershipLevelSource = try values.decodeIfPresent(String.self, forKey: .membershipLevelSource)
            ?? values.decodeIfPresent(String.self, forKey: .membershipLevelSourceLower)
        tiers = try values.decodeIfPresent([MembershipTier].self, forKey: .tiers)
            ?? values.decodeIfPresent([MembershipTier].self, forKey: .tiersLower) ?? []
    }
}

@MainActor
@Observable
private final class MembershipViewModel {
    private let api = APIClient()
    private(set) var progress: MembershipProgress?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func load(session: SessionStore) async {
        guard let token = await session.validAccessToken(), !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            progress = try await api.get("/api/ais/account/membership-progress", token: token)
        } catch { errorMessage = error.localizedDescription }
    }
}

struct MembershipView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = MembershipViewModel()

    var body: some View {
        ScrollView {
            if let progress = model.progress {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("membership.current").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            membershipBadge(level: currentLevelIndex(progress), size: 54)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(progress.currentLevelName ?? AppLanguage.localized("membership.normal"))
                                    .font(.title.bold())
                                Text("\(progress.countryCode) · \(progress.currency)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            membershipDiscountLabel(progress.currentDiscountPercent)
                        }
                    }
                    .padding(18).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))

                    if let next = progress.nextLevelName {
                        HStack(alignment: .top, spacing: 14) {
                            membershipBadge(level: nextLevelIndex(progress), size: 44)
                            VStack(alignment: .leading, spacing: 9) {
                                Text(String.localizedStringWithFormat(AppLanguage.localized("membership.next"), next)).font(.headline)
                                ProgressView(
                                    value: NSDecimalNumber(decimal: progress.cumulativeRechargeAmount).doubleValue,
                                    total: max(1, NSDecimalNumber(decimal: progress.nextThresholdAmount ?? 1).doubleValue)
                                ).tint(PixaTheme.accent)
                                Text(String.localizedStringWithFormat(
                                    AppLanguage.localized("membership.remaining"),
                                    progress.currency,
                                    NSDecimalNumber(decimal: progress.remainingAmount).doubleValue
                                )).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(18).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("membership.rules").font(.title3.bold()).padding(.bottom, 8)
                        ForEach(Array(progress.tiers.enumerated()), id: \.element.id) { index, tier in
                            HStack(spacing: 12) {
                                membershipBadge(level: index + 1, size: 38)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tier.name).font(.headline)
                                    Text(String.localizedStringWithFormat(
                                        AppLanguage.localized("membership.threshold"),
                                        progress.currency,
                                        NSDecimalNumber(decimal: tier.thresholdAmount).doubleValue
                                    )).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                membershipDiscountLabel(tier.discountPercent)
                            }.padding(.vertical, 12)
                            if tier.id != progress.tiers.last?.id { Divider() }
                        }
                    }
                    .padding(18).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
                }.padding(16)
            } else if model.isLoading {
                PixaLoadingStateView(
                    title: "loading.account.title",
                    message: "loading.account.message"
                )
                .padding(16)
            } else if let error = model.errorMessage {
                ContentUnavailableView {
                    Label("common.error", systemImage: "exclamationmark.circle")
                } description: {
                    Text(error)
                } actions: {
                    Button("common.retry") { Task { await model.load(session: session) } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(PixaTheme.paper.ignoresSafeArea())
        .navigationTitle("membership.title")
        .task { await model.load(session: session) }
    }

    private func currentLevelIndex(_ progress: MembershipProgress) -> Int {
        let code = progress.currentLevelCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = progress.currentLevelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = progress.tiers.firstIndex(where: { tier in
            tier.code.caseInsensitiveCompare(code ?? "") == .orderedSame
                || tier.name.caseInsensitiveCompare(name ?? "") == .orderedSame
        }) {
            return index + 1
        }
        return 1
    }

    private func membershipDiscountLabel(_ value: Decimal) -> some View {
        Text(String.localizedStringWithFormat(
            AppLanguage.localized("membership.discount"),
            NSDecimalNumber(decimal: value).doubleValue
        ))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(PixaTheme.accent)
        .multilineTextAlignment(.trailing)
        .lineLimit(2)
        .minimumScaleFactor(0.78)
        .frame(width: 88, alignment: .trailing)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func nextLevelIndex(_ progress: MembershipProgress) -> Int {
        let code = progress.nextLevelCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = progress.nextLevelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = progress.tiers.firstIndex(where: { tier in
            tier.code.caseInsensitiveCompare(code ?? "") == .orderedSame
                || tier.name.caseInsensitiveCompare(name ?? "") == .orderedSame
        }) {
            return index + 1
        }
        return currentLevelIndex(progress) + 1
    }

    private func membershipBadge(level: Int, size: CGFloat) -> some View {
        Image("MembershipLevel\(min(6, max(1, level)))")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
