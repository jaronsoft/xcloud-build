import Foundation
import Security

extension Notification.Name {
    static let dineWiseSessionExpired = Notification.Name("DineWiseSessionExpired")
}

struct DineWiseBusinessHoursPeriod: Codable {
    let OpensAt: String
    let ClosesAt: String
}

struct DineWiseBusinessHoursDay: Codable {
    let DayOfWeek: Int
    let Periods: [DineWiseBusinessHoursPeriod]
}

let dineWiseWeekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
private let dineWiseReadRequestTimeout: TimeInterval = 30

func dineWiseFormatTimestamp(_ value: String, timeZoneID: String?) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = parser.date(from: value) ?? {
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value)
    }()
    guard let date else { return "\(value) UTC" }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    if let timeZoneID, let timeZone = TimeZone(identifier: timeZoneID) {
        formatter.timeZone = timeZone
        return "\(formatter.string(from: date))（门店时间）"
    }
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return "\(formatter.string(from: date)) UTC"
}

func dineWiseTextOriginName(_ value: String?) -> String {
    switch value {
    case "speech_transcription": "语音转写"
    case "image_ocr": "图片文字识别"
    case "mixed": "手工文字、语音或图片识别混合"
    default: "手工输入"
    }
}

func dineWiseBusinessHoursText(_ days: [DineWiseBusinessHoursDay]?) -> [String] {
    dineWiseWeekdays.indices.map { index in
        days?.first(where: { $0.DayOfWeek == index + 1 })?.Periods
            .map { "\($0.OpensAt)-\($0.ClosesAt)" }.joined(separator: ", ") ?? ""
    }
}

func dineWiseBusinessHoursSummary(_ days: [DineWiseBusinessHoursDay]?) -> String {
    guard days != nil else { return "未填写" }
    return dineWiseBusinessHoursText(days).enumerated().map { index, value in
        "\(dineWiseWeekdays[index]) \(value.isEmpty ? "休息" : value)"
    }.joined(separator: " · ")
}

func dineWiseBusinessHoursPayload(_ values: [String]) -> [DineWiseBusinessHoursDay]? {
    guard values.count == 7 else { return nil }
    let pattern = "^(?:[01]\\d|2[0-3]):[0-5]\\d-(?:[01]\\d|2[0-3]):[0-5]\\d$"
    var days: [DineWiseBusinessHoursDay] = []
    var intervals: [(start: Int, end: Int)] = []
    for (index, value) in values.enumerated() {
        let items = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard items.count <= 4 else { return nil }
        var periods: [DineWiseBusinessHoursPeriod] = []
        for item in items {
            guard item.range(of: pattern, options: .regularExpression) != nil else { return nil }
            let pair = item.split(separator: "-", maxSplits: 1).map(String.init)
            let times = pair.map { value in
                let parts = value.split(separator: ":").compactMap { Int($0) }
                return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
            }
            guard times[0] != times[1] else { return nil }
            let absoluteStart = index * 1440 + times[0]
            var absoluteEnd = index * 1440 + times[1]
            if times[1] < times[0] { absoluteEnd += 1440 }
            intervals.append((absoluteStart, absoluteEnd))
            periods.append(DineWiseBusinessHoursPeriod(OpensAt: pair[0], ClosesAt: pair[1]))
        }
        days.append(DineWiseBusinessHoursDay(DayOfWeek: index + 1, Periods: periods))
    }
    let expanded = intervals.flatMap { interval in
        [(-10080, -10080), (0, 0), (10080, 10080)].map { offset in
            (start: interval.start + offset.0, end: interval.end + offset.1)
        }
    }.sorted { $0.start < $1.start }
    var furthestEnd = expanded.first?.end ?? Int.min
    for interval in expanded.dropFirst() {
        guard interval.start >= furthestEnd else { return nil }
        furthestEnd = max(furthestEnd, interval.end)
    }
    return days
}

struct DineWiseStore: Decodable, Identifiable {
    let Id: String
    let Name: String
    let Mode: String
    let Roles: [String]
    let BusinessType: String?
    let Address: String?
    let Latitude: Double?
    let Longitude: Double?
    let Introduction: String?
    let PaymentMethods: [String]?
    let HasPhoto: Bool?
    let TimeZone: String?
    let BusinessDayCutoffMinutes: Int?
    let BusinessHours: [DineWiseBusinessHoursDay]?
    let ProfileVersion: Int?

    var id: String { Id }
}

struct DineWiseCustomerConsentPage: Decodable {
    let Items: [DineWiseCustomerConsent]
    let NextBeforeId: String?
    let TodayNewAuthorizedCount: Int?
}

struct DineWiseCustomerTouchDraftPage: Decodable {
    let Items: [DineWiseCustomerTouchDraft]
}

struct DineWiseCustomerTouchOutcomePage: Decodable {
    let Items: [DineWiseCustomerTouchOutcome]
}

struct DineWiseCustomerTouchOutcome: Decodable, Identifiable {
    let Id: String
    let TouchDraftId: String
    let OutcomeType: String
    let OccurredBusinessDate: String
    let EvidenceKind: String
    let EvidenceReference: String
    let Status: String
    let ReviewReasonCode: String?
    let Version: Int
    let CreatedAtUtc: String
    let ReviewedAtUtc: String?

    var id: String { Id }
}

struct DineWiseCustomerTouchDraft: Decodable, Identifiable {
    let Id: String
    let ConsentId: String
    let Purpose: String
    let Channel: String?
    let Content: String
    let Status: String
    let Version: Int
    let CreatedAtUtc: String
    let ReportedSentAtUtc: String?

    var id: String { Id }
}

struct DineWiseCustomerConsent: Decodable, Identifiable {
    let Id: String
    let CustomerReference: String
    let Purposes: [String]
    let ConsentNoticeVersion: String
    let ConsentSource: String
    let ConsentedAtUtc: String
    let BirthdayMonthDay: String?
    let LastVisitBusinessDate: String?
    let RetainUntilBusinessDate: String
    let Status: String
    let Version: Int

    var id: String { Id }
}

struct DineWiseWeatherForecast: Decodable {
    let Area: String
    let UpdatedAtUtc: String
    let Source: String
    let Days: [DineWiseWeatherDay]
}

struct DineWiseWeatherDay: Decodable, Identifiable {
    let Date: String
    let Condition: String
    let MinC: Double
    let MaxC: Double
    let RainChance: Int
    var id: String { Date }
}

struct DineWiseOperatorStore: Decodable, Identifiable {
    let Id: String
    let Name: String
    let BusinessType: String
    let OwnerEmail: String
    let OwnerUsername: String?
    let Address: String
    let Introduction: String?
    let HasPhoto: Bool
    let PaymentMethods: [String]
    let BusinessHours: [DineWiseBusinessHoursDay]?

    var id: String { Id }
}

struct DineWiseOperatorCharge: Decodable, Identifiable {
    let Id: String
    let StoreName: String?
    let CustomerLabel: String?
    let Channel: String
    let AmountFen: Int64
    let PaidAtUtc: String
    let Status: String
    let ReviewReason: String?
    let HasVoucherFile: Bool?
    let VoucherFileName: String?

    var id: String { Id }
}

struct DineWiseSession: Decodable, Sendable {
    let UserId: String
    let AccessToken: String
    let RefreshToken: String
    let AccessTokenExpiresInSeconds: Int
    let Email: String
    let Username: String?
}

struct DineWisePushDeviceSummary: Decodable {
    let Id: String
    let Platform: String
    let Environment: String
    let LastSeenAtUtc: String
}

struct DineWiseAppleNonce: Decodable {
    let Nonce: String
}

struct DineWiseEmailBindingResponse: Decodable {
    let Email: String
}

struct DineWiseOperatorSession: Decodable {
    let OperatorId: String?
    let Username: String
    let AccessToken: String
}

struct DineWiseMember: Decodable, Identifiable {
    let Id: String
    let UserId: String
    let Email: String?
    let Username: String?
    let Role: String
    let Enabled: Bool

    var id: String { Id }
}

struct DineWiseMemberEvent: Decodable, Identifiable {
    let Id: String
    let Role: String
    let Action: String
    let Actor: String
    let Reason: String
    let ActedAtUtc: String
    var id: String { Id }
}

struct DineWiseMemberInvitation: Decodable, Identifiable {
    let Id: String
    let StoreId: String
    let StoreName: String
    let StoreTimeZone: String?
    let Mode: String
    let Email: String
    let Role: String
    let Status: String
    let ExpiresAtUtc: String
    let EmailDelivered: Bool
    let EmailSending: Bool?
    var id: String { Id }
}

struct DineWiseSubmission: Decodable, Identifiable {
    let Id: String
    let StoreId: String
    let Mode: String
    let SubmittedByUserId: String
    let SubmittedRole: String
    let Kind: String
    let PurchasePlanId: String?
    let PreparationPlanId: String?
    let FeedbackCategory: String?
    let OccurredAtUtc: String?
    let BusinessDate: String
    let OriginalText: String
    let TextOrigin: String?
    let RecognitionFailureCode: String?
    let Status: String
    let Version: Int

    var id: String { Id }
}

struct DineWiseFeedbackItem: Decodable, Identifiable {
    let SubmissionId: String
    let Category: String
    let OccurredAtUtc: String?
    let OriginalText: String
    let TextOrigin: String?
    let SubmittedRole: String
    let Status: String
    var id: String { SubmissionId }
}

struct DineWiseFeedbackOverview: Decodable {
    let StoreId: String
    let Mode: String
    let BusinessDate: String
    let PendingReviewCount: Int
    let ConfirmedCount: Int
    let FilteredCount: Int?
    let SupportsListFilters: Bool?
    let Breakdowns: [DineWiseFeedbackBreakdown]
    let Items: [DineWiseFeedbackItem]
    let HasMore: Bool?
    let NextCursor: String?
}

struct DineWiseFeedbackBreakdown: Decodable, Identifiable {
    let Category: String
    let SubmittedRole: String
    let Status: String
    let Count: Int
    var id: String { "\(Category)-\(SubmittedRole)-\(Status)" }
}

struct DineWiseSubmissionField: Decodable, Identifiable {
    let FieldKey: String
    let OriginalValue: String?
    let OriginalUnit: String?
    let CurrentValue: String
    let CurrentUnit: String?
    let NormalizedValue: String?
    let NormalizedUnit: String?

    var id: String { FieldKey }
}

struct DineWiseSubmissionDetail: Decodable {
    let Submission: DineWiseSubmission
    let Fields: [DineWiseSubmissionField]
    let RequiredFieldKeys: [String]?
    let LinkedPurchasePlanItems: [DineWisePurchasePlanItem]?
    let LinkedPurchasePlanUnavailableReason: String?
    let LinkedPreparationPlanUnavailableReason: String?
    let Files: [DineWiseSubmissionFile]
}

struct DineWiseSubmissionReviewEvent: Decodable, Identifiable {
    let Id: String
    let Version: Int
    let Action: String
    let FieldKey: String?
    let PreviousValue: String?
    let NewValue: String?
    let PreviousUnit: String?
    let NewUnit: String?
    let Reason: String?
    let ActorUserId: String
    let ActedAt: String

    var id: String { Id }
}

struct DineWiseSubmissionReviewEventPage: Decodable {
    let Items: [DineWiseSubmissionReviewEvent]
    let NextBeforeId: String?
}

struct DineWiseRecommendation: Decodable, Identifiable {
    let Id: String
    let StoreId: String
    let Mode: String
    let SourceSubmissionId: String
    let SourceVersion: Int?
    let Title: String
    let Rationale: String
    let CalculationBasis: String?
    let ConfidenceLevel: String?
    let ConfidenceReason: String?
    let Steps: String
    let TargetRole: String
    let Status: String
    let Version: Int
    let DecisionReason: String?
    let RemindOn: String?
    let TaskId: String?
    let SourceInvalidatedAt: String?
    let InvalidationReason: String?
    let ValidUntilOn: String?
    let ReplacesRecommendationId: String?
    let SupersededByRecommendationId: String?

    var id: String { Id }
}

struct DineWiseTask: Decodable, Identifiable {
    let Id: String
    let StoreId: String
    let Mode: String
    let SourceType: String?
    let MeetingOn: String?
    let Title: String
    let Steps: String
    let TargetRole: String
    let AssignedUserId: String?
    let Status: String
    let Version: Int
    let Receipt: String?
    let LatestProgressNote: String?
    let LatestProgressAtUtc: String?
    let ReviewNote: String?
    let DueOn: String?
    let EscalationRule: String?
    let EscalatedAtUtc: String?
    let IsOverdue: Bool?
    let SourceInvalidatedAt: String?
    let InvalidationReason: String?

    var id: String { Id }
}

struct DineWiseMeetingProgressSummary: Decodable {
    let WeekStartOn: String
    let WeekEndOn: String
    let TotalCount: Int
    let PendingAssignmentCount: Int
    let PendingExecutionCount: Int
    let InProgressCount: Int
    let PendingReviewCount: Int
    let OverdueCount: Int
    let CompletedCount: Int
    let CancelledCount: Int
}

struct DineWiseTaskEventHistory: Decodable {
    let TaskId: String
    let HasOlder: Bool
    let Items: [DineWiseTaskEvent]
}

struct DineWiseTaskEvent: Decodable, Identifiable {
    let Id: String
    let Action: String
    let ActorType: String
    let ActorLabel: String
    let Version: Int
    let Note: String?
    let DueOn: String?
    let ActedAtUtc: String

    var id: String { Id }
}

struct DineWiseTaskNotification: Decodable, Identifiable {
    let Id: String
    let TaskId: String
    let TaskTitle: String
    let Action: String
    let TaskStatus: String
    let Note: String?
    let CreatedAtUtc: String
    let IsRead: Bool

    var id: String { Id }
}

struct DineWisePreparationPlanItem: Codable, Sendable {
    let IngredientName: String
    let Unit: String
    let MinimumQuantity: Decimal
    let MaximumQuantity: Decimal
    let Basis: String
}

struct DineWisePreparationPlan: Decodable, Identifiable {
    let Id: String
    let TaskId: String
    let BusinessDate: String
    let Status: String
    let Version: Int
    let Items: [DineWisePreparationPlanItem]
    let SourceInvalidated: Bool
    let WasReassigned: Bool?
    let PurchasePlanId: String?
    let KitchenOutcomePendingCount: Int
    let KitchenOutcomeConfirmedCount: Int
    var id: String { Id }
}

struct DineWisePurchasePlan: Decodable, Identifiable {
    let Id: String
    let PreparationPlanId: String
    let BusinessDate: String
    let Status: String
    let Version: Int
    let Items: [DineWisePreparationPlanItem]
    let OrderItems: [DineWisePurchasePlanItem]
    let ConfirmedAtUtc: String?
    let SourceInvalidated: Bool
    let UnavailableReason: String?
    let ActualPurchasePendingCount: Int
    let ActualPurchaseConfirmedCount: Int
    let StockDeducted: Bool
    let OrderPlaced: Bool
    var id: String { Id }
}

struct DineWisePurchasePlanItem: Codable, Sendable {
    let IngredientName: String
    let Unit: String
    let OrderQuantity: Decimal
    let CurrentStockQuantity: Decimal?
    let InTransitQuantity: Decimal?
    let ReservedQuantity: Decimal?
    let InventoryCheck: String
    let SupplierName: String
    let PackageSpecification: String
    let QuantityReason: String
}

struct DineWisePurchaseInventoryInput: Encodable, Sendable {
    let IngredientName: String
    let Unit: String
    let CurrentStockQuantity: Decimal?
    let InTransitQuantity: Decimal?
    let ReservedQuantity: Decimal?
}

struct DineWisePurchaseSuggestionPreview: Decodable, Sendable {
    let StoreId: String
    let PurchasePlanId: String
    let Version: Int
    let Items: [DineWisePurchaseSuggestionPreviewItem]
    let Formula: String
    let Limitation: String
}

struct DineWisePurchaseSuggestionPreviewItem: Decodable, Sendable {
    let IngredientName: String
    let Unit: String
    let CanCalculate: Bool
    let AvailableForPlanQuantity: Decimal?
    let SuggestedMinimumQuantity: Decimal?
    let SuggestedMaximumQuantity: Decimal?
    let UnavailableReason: String?
}

struct DineWiseOwnerTodayItem: Decodable {
    let type: String
    let Id: String
    let Title: String

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case Id
        case Title
    }
}

struct DineWiseOwnerTodaySummary: Decodable {
    let StoreId: String
    let Mode: String
    let Items: [DineWiseOwnerTodayItem]
    let HasMoreItems: Bool?
    let Yesterday: DineWiseDailyReport?
    let TaskProgress: [DineWiseOwnerTodayRoleProgress]?
    let PendingSubmissionReviewCount: Int?
}

struct DineWiseOwnerTodayRoleProgress: Decodable, Identifiable {
    let Role: String
    let CompletedCount: Int
    let TotalCount: Int
    var id: String { Role }
}

struct DineWiseTaskReview: Decodable, Identifiable {
    let Id: String
    let TaskId: String
    let StoreId: String
    let Mode: String
    let Status: String
    let Version: Int
    let DueOn: String
    let MetricKey: String?
    let MetricUnit: String?
    let BeforeBusinessDate: String?
    let BeforeValue: String?
    let AfterBusinessDate: String?
    let AfterValue: String?
    let Conclusion: String?
    let NextStep: String?
    let SourceInvalidatedAt: String?
    let InvalidationReason: String?

    var id: String { Id }
}

struct DineWiseReportSourceCandidate: Decodable, Identifiable {
    let SourceSubmissionId: String
    let SourceVersion: Int
    let SubmittedRole: String
    var id: String { SourceSubmissionId }
}

struct DineWiseDailyReportSnapshotInfo: Decodable {
    let Id: String
    let Revision: Int
    let Status: String
    let RuleVersion: String
    let GeneratedAtUtc: String
    let InvalidatedAtUtc: String?
    let InvalidatedReason: String?
}

struct DineWiseDailyReport: Decodable {
    let StoreId: String
    let Mode: String
    let BusinessDate: String
    let ConfirmedOperatingCount: Int
    let RevenueYuan: Decimal?
    let Orders: Int?
    let Tables: Int?
    let RevenuePerTableYuan: Decimal?
    let SourceSubmissionId: String?
    let SourceVersion: Int?
    let DuplicateSources: [DineWiseReportSourceCandidate]?
    let MissingReasons: [String]
    let Snapshot: DineWiseDailyReportSnapshotInfo?
}

struct DineWiseWeeklyReportDay: Decodable, Identifiable {
    let BusinessDate: String
    let IsScheduledOpen: Bool?
    let ConfirmedOperatingCount: Int
    let DuplicateSources: [DineWiseReportSourceCandidate]?
    let RevenueYuan: Decimal?
    let Orders: Int?
    let Tables: Int?
    let SourceSubmissionId: String?
    let SourceVersion: Int?
    let MissingReasons: [String]

    var id: String { BusinessDate }
}

struct DineWiseWeeklyReport: Decodable {
    let StoreId: String
    let Mode: String
    let WeekStart: String
    let WeekEnd: String
    let ConfirmedRevenueSubtotalYuan: Decimal
    let RevenueCoveredDays: Int
    let UniqueSourceDays: Int
    let DuplicateSourceDays: Int
    let NoSourceDays: Int
    let CalendarVersion: Int?
    let ScheduledOpenDays: Int?
    let MissingOpenDays: Int?
    let PendingOpenDays: Int?
    let ClosedSourceDays: Int?
    let CompleteWeekRevenueYuan: Decimal?
    let IsCompleteBusinessWeek: Bool
    let Days: [DineWiseWeeklyReportDay]
    let MissingReasons: [String]
}

struct DineWiseMonthlyReport: Decodable {
    let StoreId: String
    let Mode: String
    let MonthStart: String
    let MonthEnd: String
    let ConfirmedRevenueSubtotalYuan: Decimal
    let RevenueCoveredDays: Int
    let CalendarConfiguredDays: Int
    let ScheduledOpenDays: Int?
    let MissingOpenDays: Int?
    let PendingOpenDays: Int?
    let ClosedSourceDays: Int?
    let CompleteMonthRevenueYuan: Decimal?
    let IsCompleteBusinessMonth: Bool
    let ConfirmedPurchaseSourceCount: Int
    let PricedPurchaseSourceCount: Int
    let ComparablePurchasePriceCount: Int
    let ConfirmedPurchaseAmountSubtotalYuan: Decimal
    let Purchases: [DineWiseMonthlyPurchaseItem]
    let Channels: [DineWiseMonthlyChannelSummary]?
    let DishCosts: [DineWiseMonthlyDishCost]?
    let ChannelDishCosts: [DineWiseMonthlyChannelDishCostSummary]?
    let PriceScenarioRegion: String?
    let Days: [DineWiseWeeklyReportDay]
    let MissingReasons: [String]
}

struct DineWiseMonthlyChannelDishCostSummary: Decodable, Identifiable {
    let ChannelCode: String?
    let RecordedBusinessDayCount: Int
    let RecordedSalesSourceCount: Int
    let RecordedDishRowCount: Int
    let EstimatedDishRowCount: Int
    let UnestimatedDishRowCount: Int
    let RecordedIngredientCostSubtotalYuan: Decimal?
    var id: String { ChannelCode ?? "unassigned" }
}

struct DineWiseMonthlyDishCost: Decodable, Identifiable {
    let BusinessDate: String
    let DishName: String
    let ChannelCode: String?
    let RecipeVersion: String?
    let SoldPortions: Int64?
    let SalesSourceId: String?
    let SalesSourceVersion: Int?
    let SalesSources: [DineWiseReportSourceCandidate]
    let RecipeSources: [DineWiseReportSourceCandidate]
    let Ingredients: [DineWiseMonthlyIngredientCostLine]
    let EstimatedIngredientCostYuan: Decimal?
    let EstimatedIngredientCostPerServingYuan: Decimal?
    let RegionalScenarioCostYuan: Decimal?
    let RegionalScenarioImpactYuan: Decimal?
    let RegionalScenarioMissingReasons: [String]
    let MissingReasons: [String]
    var id: String { "\(BusinessDate)-\(DishName)-\(ChannelCode ?? "unassigned")" }
}

struct DineWiseMonthlyIngredientCostLine: Decodable, Identifiable {
    let IngredientName: String?
    let IngredientCategory: String?
    let IngredientSpecification: String?
    let RecipeSourceId: String
    let RecipeSourceVersion: Int
    let UsableQuantityKgPerServing: Decimal?
    let IsPieceQuantity: Bool
    let TrimLossPercent: Decimal?
    let PurchaseBusinessDate: String?
    let PurchaseSourceId: String?
    let PurchaseSourceVersion: Int?
    let UnitPriceYuanPerKg: Decimal?
    let EstimatedCostPerServingYuan: Decimal?
    let EstimatedCostYuan: Decimal?
    let MissingReasons: [String]
    let RegionalPriceReference: DineWisePublicPriceReference?
    let RegionalScenarioCostYuan: Decimal?
    let RegionalScenarioImpactYuan: Decimal?
    let RegionalScenarioMissingReason: String?
    var id: String { RecipeSourceId }
}

struct DineWiseMonthlyChannelSummary: Decodable, Identifiable {
    let ChannelCode: String
    let ConfirmedSourceCount: Int
    let UniqueCompleteDays: Int
    let DuplicateDays: Int
    let ComparableBusinessDays: Int
    let ComparableGrossSalesYuan: Decimal?
    let ComparableMerchantSalesYuan: Decimal?
    let ComparableAfterChannelFeesYuan: Decimal?
    let ComparableRefundsYuan: Decimal?
    let ComparableMerchantDiscountYuan: Decimal?
    let ComparablePlatformDiscountYuan: Decimal?
    let ComparableCommissionYuan: Decimal?
    let ComparablePromotionFeeYuan: Decimal?
    let ComparableOrders: Int64?
    let Days: [DineWiseMonthlyChannelDay]
    var id: String { ChannelCode }
}

struct DineWiseMonthlyChannelDay: Decodable, Identifiable {
    let BusinessDate: String
    let ConfirmedSourceCount: Int
    let SourceSubmissionId: String?
    let SourceVersion: Int?
    let GrossSalesYuan: Decimal?
    let RefundsYuan: Decimal?
    let MerchantDiscountYuan: Decimal?
    let PlatformDiscountYuan: Decimal?
    let CommissionYuan: Decimal?
    let PromotionFeeYuan: Decimal?
    let Orders: Int64?
    let DuplicateSources: [DineWiseReportSourceCandidate]
    let MissingReasons: [String]
    var id: String { "\(BusinessDate)-\(SourceSubmissionId ?? "duplicate")" }
}

struct DineWiseMonthlyPurchaseItem: Decodable, Identifiable {
    let SourceSubmissionId: String
    let SourceVersion: Int
    let BusinessDate: String
    let IngredientName: String?
    let IngredientSpecification: String?
    let SupplierName: String?
    let QuantityKg: Decimal?
    let PurchaseQuantity: Decimal?
    let PurchaseQuantityUnit: String?
    let UnitPriceYuanPerKg: Decimal?
    let PreviousComparableSourceId: String?
    let PreviousComparableSourceVersion: Int?
    let PreviousComparableBusinessDate: String?
    let PreviousComparableSupplierName: String?
    let PreviousUnitPriceYuanPerKg: Decimal?
    let UnitPriceChangeYuanPerKg: Decimal?
    let UnitPriceChangePercent: Decimal?
    let PriceComparisonNote: String?
    let RecordedAmountYuan: Decimal?
    let MissingReasons: [String]
    var id: String { SourceSubmissionId }
}

struct DineWiseProblemEvidence: Decodable, Identifiable {
    let SubmissionId: String
    let SourceVersion: Int
    let ConfirmationStatus: String
    let BusinessDate: String
    let OccurredAtUtc: String?
    let SubmittedRole: String
    var id: String { SubmissionId }
}

struct DineWiseProblemFinding: Decodable, Identifiable {
    let Category: String
    let ConfirmedCount: Int
    let RecordedDays: Int
    let FindingText: String
    let CalculationRule: String
    let Assumptions: String
    let ConfidenceLevel: String
    let ConfidenceReason: String
    let NextStep: String
    let Evidence: [DineWiseProblemEvidence]
    var id: String { Category }
}

struct DineWiseProblemSnapshotInfo: Decodable {
    let Id: String
    let Revision: Int
    let Status: String
    let RuleVersion: String
    let GeneratedAtUtc: String
    let InvalidatedAtUtc: String?
    let InvalidatedReason: String?
}

struct DineWiseWeeklyProblemReport: Decodable {
    let StoreId: String
    let Mode: String
    let WeekStart: String
    let WeekEnd: String
    let RuleVersion: String
    let Snapshot: DineWiseProblemSnapshotInfo?
    let PendingReviewCount: Int
    let Findings: [DineWiseProblemFinding]
    let MissingReasons: [String]
}

struct DineWiseWeeklyCalendar: Decodable {
    let StoreId: String
    let Mode: String
    let WeekStart: String
    let WeekEnd: String
    let Configured: Bool
    let OpenDaysMask: Int
    let DefaultOpenDaysMask: Int?
    let Version: Int
    let CanEdit: Bool
}

struct DineWiseNotice: Decodable, Identifiable {
    let Id: String
    let Mode: String
    let Category: String
    let TitleZh: String
    let BodyZh: String
    let SourceName: String
    let SourceUrl: String?
    let LocationName: String
    let ObservedAtUtc: String
    let VerifiedAtUtc: String?
    let ExpiresAtUtc: String
    let Version: Int
    let MyRating: String?
    var id: String { Id }
}

struct DineWisePublicPriceReference: Decodable, Identifiable {
    let Id: String
    let Category: String
    let ItemName: String
    let Specification: String
    let Unit: String
    let RegionName: String
    let PriceYuan: Decimal
    let SourceName: String
    let SourceUrl: String?
    let ObservedAtUtc: String
    let ValidFromUtc: String
    let ExpiresAtUtc: String
    let PreviousPriceYuan: Decimal?
    let PreviousObservedAtUtc: String?
    let PriceChangePercent: Decimal?
    var id: String { Id }
}

struct DineWisePublicActivity: Decodable, Identifiable {
    let Id: String
    let TitleZh: String
    let BodyZh: String
    let SourceName: String
    let SourceUrl: String?
    let LocationName: String
    let ObservedAtUtc: String
    let VerifiedAtUtc: String
    let ValidFromUtc: String
    let ExpiresAtUtc: String
    var id: String { Id }
}

struct DineWiseInterview: Decodable, Identifiable {
    let Id: String
    let BusinessType: String
    let StoreCount: Int
    let CurrentTools: String
    let IntervieweeRole: String
    let DemoSteps: [String]
    let DemoDurationSeconds: Int?
    let ObservedOperationType: String?
    let ObservedOperationDurationSeconds: Int?
    let DemoScriptVersion: String
    let IntervieweeConsentConfirmed: Bool?
    let UsefulQuote: String
    let ConcernQuote: String
    let WillingData: String
    let DailyBurdenMinutes: Int?
    let Interest: String
    let SubmitWillingness: String
    let PayWillingness: String
    let TrialWillingness: String
    let RecordedAtUtc: String
    var id: String { Id }
}

private struct DineWiseInterviewCapabilities: Decodable {
    let IntervieweeConsentConfirmationRequired: Bool
    let ObservedOperationDurationSupported: Bool?
}

struct DineWiseInterviewDraft: Sendable {
    let businessType: String
    let storeCount: Int
    let currentTools: String
    let intervieweeRole: String
    let demoSteps: [String]
    let demoDurationSeconds: Int?
    let observedOperationType: String?
    let observedOperationDurationSeconds: Int?
    let intervieweeConsentConfirmed: Bool
    let usefulQuote: String
    let concernQuote: String
    let willingData: String
    let dailyBurdenMinutes: Int?
    let interest: String
    let submitWillingness: String
    let payWillingness: String
    let trialWillingness: String
}

private struct DineWiseNoticeFeedbackResult: Decodable {
    let NoticeId: String
    let Rating: String
}

struct DineWiseSubmissionFile: Decodable, Identifiable {
    let Id: String
    let FileName: String
    let SizeBytes: Int
    let IsRecognitionOriginal: Bool?

    var id: String { Id }
}

struct DineWiseSubmissionPage: Decodable {
    let Total: Int
    let Items: [DineWiseSubmission]
}

private struct APIEnvelope<Value: Decodable>: Decodable {
    let success: Bool
    let response: Value?
    let msg: String?
    let status: Int?
}

private func dineWiseFailureMessage(_ message: String?, httpStatus: Int,
                                    envelopeStatus: Int?, fallback: String) -> String {
    if httpStatus >= 500 || (envelopeStatus ?? 0) >= 500 {
        return "服务器暂时不可用，请稍后重试。"
    }
    return message ?? fallback
}

private struct EmptyResult: Decodable {}

private func dineWiseStoredJSONLength(_ value: Any) throws -> Int {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    guard let json = String(data: data, encoding: .utf8) else {
        throw DineWiseAPIError.failed("无法检查计划项目内容，请稍后重试。")
    }
    let escapedQuotes = json.replacingOccurrences(of: "\\\"", with: "\\u0022")
    return escapedQuotes.utf16.reduce(into: 0) { length, unit in
        if unit > 0x7e || [0x26, 0x3c, 0x3e, 0x27, 0x2b, 0x60].contains(Int(unit)) {
            // 服务端默认 JSON 编码会将非 ASCII、引号及 HTML/JavaScript 敏感字符转义。
            length += 6
        } else {
            length += 1
        }
    }
}

enum DineWiseAPIError: LocalizedError {
    case invalidURL
    case failed(String)
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .invalidURL: "API 地址无效，请检查应用配置。"
        case let .failed(message): message
        case .sessionExpired: "登录已过期，请重新登录。"
        }
    }
}

struct DineWiseAPI {
    // 仅模拟器允许覆盖 Debug 地址，避免真机调试被 Xcode Scheme 引到本机服务。
    private let baseURL: String = {
        #if DEBUG
            #if targetEnvironment(simulator)
                return Bundle.main.object(forInfoDictionaryKey: "DINEWISE_API_BASE_URL") as? String ?? ""
            #else
                return "https://gateway.jaronsoft.com"
            #endif
        #else
            return Bundle.main.object(forInfoDictionaryKey: "DINEWISE_API_BASE_URL") as? String ?? ""
        #endif
    }()

    private func request<Value: Decodable>(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        token: String? = nil,
        idempotencyKey: String? = nil,
        role: String? = nil
    ) async throws -> Value {
        guard let base = URL(string: baseURL),
              let url = URL(string: "api/restaurant-assistant\(path)", relativeTo: base)?.absoluteURL,
              isAllowedEndpoint(url) else {
            throw DineWiseAPIError.invalidURL
        }
        var accessToken: String?
        if let token {
            accessToken = try await DineWiseSessionStore.shared.resolve(token, base: base)
        }
        let jsonBody = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        for attempt in 0..<2 {
            var request = URLRequest(url: url)
            request.httpMethod = method
            if method == "GET" { request.timeoutInterval = dineWiseReadRequestTimeout }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let accessToken {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
            if let role { request.setValue(role, forHTTPHeaderField: "X-DineWise-Role") }
            request.httpBody = jsonBody
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch let error as URLError where error.code == .timedOut {
                throw DineWiseAPIError.failed("服务器响应超时，请稍后刷新重试。")
            }
            let envelope = try JSONDecoder().decode(APIEnvelope<Value>.self, from: data)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status), envelope.success, let result = envelope.response {
                return result
            }
            if attempt == 0, let token, status == 401 || envelope.status == 401,
               await DineWiseSessionStore.shared.manages(token) {
                accessToken = try await DineWiseSessionStore.shared.resolve(token, base: base, force: true)
                continue
            }
            throw DineWiseAPIError.failed(dineWiseFailureMessage(envelope.msg,
                httpStatus: status, envelopeStatus: envelope.status, fallback: "请求失败"))
        }
        throw DineWiseAPIError.failed("请求失败，请重试。")
    }

    func customerConsents(storeID: String, token: String, role: String,
                          beforeID: String? = nil, size: Int = 50,
                          purpose: String? = nil, birthdayFrom: String? = nil,
                          birthdayTo: String? = nil,
                          lastVisitBeforeBusinessDate: String? = nil) async throws
        -> DineWiseCustomerConsentPage {
        var query = ["size=\(min(max(size, 1), 100))"]
        if let beforeID { query.append("beforeId=\(beforeID)") }
        if let purpose { query.append("purpose=\(purpose)") }
        if let birthdayFrom { query.append("birthdayFrom=\(birthdayFrom)") }
        if let birthdayTo { query.append("birthdayTo=\(birthdayTo)") }
        if let lastVisitBeforeBusinessDate {
            query.append("lastVisitBeforeBusinessDate=\(lastVisitBeforeBusinessDate)")
        }
        return try await request("/stores/\(storeID)/private-domain/customers?\(query.joined(separator: "&"))",
                                 token: token, role: role)
    }

    func createCustomerConsent(storeID: String, token: String, role: String,
                               customerReference: String, purposes: [String],
                               noticeVersion: String, consentSource: String,
                               birthdayMonthDay: String?, lastVisitBusinessDate: String?,
                               retainUntilBusinessDate: String,
                               idempotencyKey: String) async throws -> DineWiseCustomerConsent {
        var body: [String: Any] = [
            "CustomerReference": customerReference,
            "CustomerHasConsented": true,
            "Purposes": purposes,
            "ConsentNoticeVersion": noticeVersion,
            "ConsentSource": consentSource,
            "RetainUntilBusinessDate": retainUntilBusinessDate
        ]
        if let birthdayMonthDay { body["BirthdayMonthDay"] = birthdayMonthDay }
        if let lastVisitBusinessDate { body["LastVisitBusinessDate"] = lastVisitBusinessDate }
        return try await request("/stores/\(storeID)/private-domain/customers", method: "POST",
            body: body, token: token, idempotencyKey: idempotencyKey, role: role)
    }

    func revokeCustomerConsent(storeID: String, consentID: String, token: String,
                               role: String, version: Int, reason: String) async throws
        -> DineWiseCustomerConsent {
        try await request("/stores/\(storeID)/private-domain/customers/\(consentID)/revoke",
            method: "POST", body: ["Version": version, "Reason": reason],
            token: token, role: role)
    }

    func customerTouchDrafts(storeID: String, consentID: String, token: String,
                             role: String) async throws -> DineWiseCustomerTouchDraftPage {
        try await request("/stores/\(storeID)/private-domain/customers/\(consentID)/touch-drafts",
            token: token, role: role)
    }

    func createCustomerTouchDraft(storeID: String, consentID: String, token: String,
                                  role: String, purpose: String, content: String,
                                  channel: String,
                                  idempotencyKey: String) async throws -> DineWiseCustomerTouchDraft {
        try await request("/stores/\(storeID)/private-domain/customers/\(consentID)/touch-drafts",
            method: "POST", body: ["Purpose": purpose, "Channel": channel, "Content": content], token: token,
            idempotencyKey: idempotencyKey, role: role)
    }

    func updateCustomerTouchDraft(storeID: String, consentID: String, draftID: String,
                                  token: String, role: String, version: Int,
                                  content: String) async throws -> DineWiseCustomerTouchDraft {
        try await request("/stores/\(storeID)/private-domain/customers/\(consentID)/touch-drafts/\(draftID)",
            method: "PUT", body: ["Version": version, "Content": content], token: token, role: role)
    }

    func actOnCustomerTouchDraft(storeID: String, consentID: String, draftID: String,
                                 action: String, token: String, role: String,
                                 version: Int) async throws -> DineWiseCustomerTouchDraft {
        try await request("/stores/\(storeID)/private-domain/customers/\(consentID)/touch-drafts/\(draftID)/\(action)",
            method: "POST", body: ["Version": version], token: token, role: role)
    }

    func customerTouchOutcomes(storeID: String, consentID: String, draftID: String,
                               token: String, role: String) async throws
        -> DineWiseCustomerTouchOutcomePage {
        try await request("/stores/\(storeID)/private-domain/customers/\(consentID)/touch-drafts/\(draftID)/outcomes",
            token: token, role: role)
    }

    func createCustomerTouchOutcome(storeID: String, consentID: String, draftID: String,
                                    token: String, role: String, outcomeType: String,
                                    occurredBusinessDate: String, evidenceReference: String,
                                    idempotencyKey: String) async throws -> DineWiseCustomerTouchOutcome {
        let evidenceKind = outcomeType == "visit" ? "pos_order" : "platform_voucher"
        return try await request("/stores/\(storeID)/private-domain/customers/\(consentID)/touch-drafts/\(draftID)/outcomes",
            method: "POST", body: ["OutcomeType": outcomeType,
                "OccurredBusinessDate": occurredBusinessDate, "EvidenceKind": evidenceKind,
                "EvidenceReference": evidenceReference], token: token,
            idempotencyKey: idempotencyKey, role: role)
    }

    func reviewCustomerTouchOutcome(storeID: String, consentID: String, draftID: String,
                                    outcomeID: String, token: String, version: Int,
                                    action: String, reasonCode: String? = nil) async throws
        -> DineWiseCustomerTouchOutcome {
        var body: [String: Any] = ["Version": version, "Action": action,
                                   "EvidenceChecked": action == "verified"]
        if let reasonCode { body["ReasonCode"] = reasonCode }
        return try await request("/stores/\(storeID)/private-domain/customers/\(consentID)/touch-drafts/\(draftID)/outcomes/\(outcomeID)/review",
            method: "POST", body: body, token: token, role: "owner")
    }

    func sendCode(email: String) async throws {
        let _: EmptyResult = try await request(
            "/auth/email/send-code", method: "POST", body: ["Email": email]
        )
    }

    func login(email: String, code: String) async throws -> DineWiseSession {
        try await request("/auth/email", method: "POST", body: ["Email": email, "Code": code])
    }

    func bindEmail(email: String, code: String, token: String) async throws -> String {
        let result: DineWiseEmailBindingResponse = try await request(
            "/auth/email/bind", method: "POST", body: ["Email": email, "Code": code],
            token: token
        )
        return result.Email
    }

    func register(username: String, password: String) async throws {
        let _: EmptyResult = try await request("/auth/register", method: "POST",
            body: ["Username": username, "Password": password])
    }

    func passwordLogin(username: String, password: String) async throws -> DineWiseSession {
        try await request("/auth/password", method: "POST",
            body: ["Username": username, "Password": password])
    }

    func appleNonce() async throws -> String {
        let result: DineWiseAppleNonce = try await request("/auth/apple/nonce")
        return result.Nonce
    }

    func appleLogin(identityToken: String, authorizationCode: String,
                    nonce: String, displayName: String) async throws -> DineWiseSession {
        try await request("/auth/apple/native", method: "POST", body: [
            "IdentityToken": identityToken, "AuthorizationCode": authorizationCode,
            "Nonce": nonce, "DisplayName": displayName
        ])
    }

    func register(_ session: DineWiseSession) async {
        await DineWiseSessionStore.shared.register(session)
    }

    func restore() async throws -> DineWiseSession? {
        guard let base = URL(string: baseURL),
              let url = URL(string: "api/restaurant-assistant/auth/refresh",
                            relativeTo: base)?.absoluteURL,
              isAllowedEndpoint(url) else { throw DineWiseAPIError.invalidURL }
        return try await DineWiseSessionStore.shared.restore(base: base)
    }

    func hasSavedSession() -> Bool {
        DineWiseRefreshCredential.read() != nil
    }

    func logout(token: String) async {
        guard let base = URL(string: baseURL),
              let url = URL(string: "api/restaurant-assistant/auth/logout", relativeTo: base)?.absoluteURL,
              isAllowedEndpoint(url) else { return }
        await DineWiseSessionStore.shared.revoke(token, base: base)
    }

    func operatorLogin(username: String, password: String) async throws -> DineWiseOperatorSession {
        try await request("/operator/auth/login", method: "POST",
                          body: ["Username": username, "Password": password])
    }

    func operatorStores(token: String, beforeID: String? = nil,
                        size: Int = 100) async throws -> [DineWiseOperatorStore] {
        var query = ["size=\(size)"]
        if let beforeID { query.append("beforeId=\(beforeID)") }
        return try await request("/operator/stores?\(query.joined(separator: "&"))", token: token)
    }

    func operatorCharges(token: String, beforeID: String? = nil,
                         size: Int = 100) async throws -> [DineWiseOperatorCharge] {
        var query = ["size=\(size)"]
        if let beforeID { query.append("beforeId=\(beforeID)") }
        return try await request("/operator/charges?\(query.joined(separator: "&"))", token: token)
    }

    func operatorCreateCharge(token: String, storeID: String?, customerLabel: String?,
                              channel: String, amountFen: Int64, paidAt: Date,
                              voucherReference: String?, note: String?,
                              idempotencyKey: String) async throws -> DineWiseOperatorCharge {
        var body: [String: Any] = [
            "Channel": channel, "AmountFen": amountFen,
            "PaidAtUtc": ISO8601DateFormatter().string(from: paidAt)
        ]
        if let storeID { body["StoreId"] = storeID }
        if let customerLabel { body["CustomerLabel"] = customerLabel }
        if let voucherReference { body["VoucherReference"] = voucherReference }
        if let note { body["Note"] = note }
        return try await request("/operator/charges", method: "POST", body: body,
                                 token: token, idempotencyKey: idempotencyKey)
    }

    func operatorUploadChargeVoucher(token: String, chargeID: String, fileName: String,
                                     mimeType: String, data: Data,
                                     idempotencyKey: String) async throws -> DineWiseOperatorCharge {
        guard !data.isEmpty, data.count <= 10 * 1024 * 1024,
              Int64(chargeID).map({ $0 > 0 }) == true,
              idempotencyKey.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              (mimeType == "image/jpeg" && fileName == "voucher.jpg"
                || mimeType == "application/pdf" && fileName == "voucher.pdf"),
              let base = URL(string: baseURL),
              let url = URL(string: "api/restaurant-assistant/operator/charges/\(chargeID)/voucher",
                            relativeTo: base)?.absoluteURL,
              isAllowedEndpoint(url) else { throw DineWiseAPIError.invalidURL }
        let boundary = "DineWise-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var accessToken = try await DineWiseSessionStore.shared.resolve(token, base: base)
        for attempt in 0..<2 {
            var upload = URLRequest(url: url)
            upload.httpMethod = "POST"
            upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            upload.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            upload.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
            let (responseData, response) = try await URLSession.shared.upload(for: upload, from: body)
            let envelope = try JSONDecoder().decode(APIEnvelope<DineWiseOperatorCharge>.self,
                                                    from: responseData)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status), envelope.success, let charge = envelope.response {
                return charge
            }
            if attempt == 0, status == 401,
               await DineWiseSessionStore.shared.manages(token) {
                accessToken = try await DineWiseSessionStore.shared.resolve(token, base: base, force: true)
                continue
            }
            throw DineWiseAPIError.failed(dineWiseFailureMessage(envelope.msg,
                httpStatus: status, envelopeStatus: envelope.status, fallback: "收费凭证上传失败"))
        }
        throw DineWiseAPIError.failed("收费凭证上传失败，请重试。")
    }

    func operatorCreateStore(token: String, name: String, businessType: String,
                             ownerEmail: String, address: String, introduction: String,
                             paymentMethods: [String], latitude: Double?, longitude: Double?,
                             businessHours: [DineWiseBusinessHoursDay],
                             cutoffMinutes: Int,
                             idempotencyKey: String) async throws -> DineWiseOperatorStore {
        let hoursPayload = businessHours.map { day in
            ["DayOfWeek": day.DayOfWeek, "Periods": day.Periods.map { period in
                ["OpensAt": period.OpensAt, "ClosesAt": period.ClosesAt]
            }] as [String: Any]
        }
        var body: [String: Any] = [
            "Name": name, "BusinessType": businessType, "OwnerIdentifier": ownerEmail,
            "Address": address, "Introduction": introduction,
            "PaymentMethods": paymentMethods, "TimeZone": TimeZone.current.identifier,
            "BusinessDayCutoffMinutes": cutoffMinutes, "BusinessHours": hoursPayload
        ]
        if let latitude, let longitude {
            body["Latitude"] = latitude
            body["Longitude"] = longitude
        }
        return try await request("/operator/stores", method: "POST", body: body,
                                 token: token, idempotencyKey: idempotencyKey)
    }

    func operatorUploadPhoto(token: String, storeID: String, data: Data) async throws -> DineWiseOperatorStore {
        guard data.count <= 5 * 1024 * 1024 else {
            throw DineWiseAPIError.failed("门店照片不能超过 5 MB。")
        }
        guard let base = URL(string: baseURL),
              let url = URL(string: "api/restaurant-assistant/operator/stores/\(storeID)/photo",
                            relativeTo: base)?.absoluteURL,
              isAllowedEndpoint(url) else { throw DineWiseAPIError.invalidURL }
        let boundary = "DineWise-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"store.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var upload = URLRequest(url: url)
        upload.httpMethod = "POST"
        upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        upload.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (responseData, response) = try await URLSession.shared.upload(for: upload, from: body)
        let envelope = try JSONDecoder().decode(APIEnvelope<DineWiseOperatorStore>.self,
                                                from: responseData)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              envelope.success, let store = envelope.response else {
            throw DineWiseAPIError.failed(dineWiseFailureMessage(envelope.msg,
                httpStatus: status, envelopeStatus: envelope.status, fallback: "门店照片上传失败"))
        }
        return store
    }

    func stores(token: String) async throws -> [DineWiseStore] {
        try await request("/stores", token: token)
    }

    func updateStoreProfile(store: DineWiseStore, name: String, businessType: String,
                            address: String, latitude: Double?, longitude: Double?,
                            introduction: String, paymentMethods: [String],
                            timeZone: String, cutoffMinutes: Int,
                            businessHours: [DineWiseBusinessHoursDay], token: String) async throws -> DineWiseStore {
        let hoursPayload = businessHours.map { day in
            ["DayOfWeek": day.DayOfWeek, "Periods": day.Periods.map { period in
                ["OpensAt": period.OpensAt, "ClosesAt": period.ClosesAt]
            }] as [String: Any]
        }
        let body: [String: Any] = [
            "Version": store.ProfileVersion ?? 1, "Name": name,
            "BusinessType": businessType, "Address": address,
            "Latitude": latitude.map { $0 as Any } ?? NSNull(),
            "Longitude": longitude.map { $0 as Any } ?? NSNull(),
            "Introduction": introduction, "PaymentMethods": paymentMethods,
            "TimeZone": timeZone, "BusinessDayCutoffMinutes": cutoffMinutes,
            "BusinessHours": hoursPayload
        ]
        return try await request("/stores/\(store.Id)", method: "PATCH", body: body,
                                 token: token, role: "owner")
    }

    func uploadStorePhoto(store: DineWiseStore, data: Data, token: String) async throws -> DineWiseStore {
        guard data.count <= 5 * 1024 * 1024,
              let base = URL(string: baseURL),
              let url = URL(string: "api/restaurant-assistant/stores/\(store.Id)/photo",
                            relativeTo: base)?.absoluteURL,
              isAllowedEndpoint(url) else { throw DineWiseAPIError.invalidURL }
        let boundary = "DineWise-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"version\"\r\n\r\n\(store.ProfileVersion ?? 1)\r\n".utf8)
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"store.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var accessToken = try await DineWiseSessionStore.shared.resolve(token, base: base)
        for attempt in 0..<2 {
            var upload = URLRequest(url: url)
            upload.httpMethod = "POST"
            upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            upload.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            upload.setValue("owner", forHTTPHeaderField: "X-DineWise-Role")
            let (responseData, response) = try await URLSession.shared.upload(for: upload, from: body)
            let envelope = try JSONDecoder().decode(APIEnvelope<DineWiseStore>.self, from: responseData)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status), envelope.success, let result = envelope.response { return result }
            if attempt == 0, status == 401 || envelope.status == 401 {
                accessToken = try await DineWiseSessionStore.shared.resolve(token, base: base, force: true)
                continue
            }
            throw DineWiseAPIError.failed(dineWiseFailureMessage(envelope.msg,
                httpStatus: status, envelopeStatus: envelope.status, fallback: "门店照片上传失败"))
        }
        throw DineWiseAPIError.failed("门店照片上传失败，请重试。")
    }

    func deleteStorePhoto(store: DineWiseStore, token: String) async throws -> DineWiseStore {
        try await request("/stores/\(store.Id)/photo?version=\(store.ProfileVersion ?? 1)",
                          method: "DELETE", token: token, role: "owner")
    }

    func storePhoto(storeID: String, token: String) async throws -> Data {
        guard let base = URL(string: baseURL),
              let url = URL(string: "api/restaurant-assistant/stores/\(storeID)/photo",
                            relativeTo: base)?.absoluteURL,
              isAllowedEndpoint(url) else { throw DineWiseAPIError.invalidURL }
        var accessToken = try await DineWiseSessionStore.shared.resolve(token, base: base)
        for attempt in 0..<2 {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = dineWiseReadRequestTimeout
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch let error as URLError where error.code == .timedOut {
                throw DineWiseAPIError.failed("门店照片读取超时，请稍后重试。")
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) { return data }
            if attempt == 0, status == 401,
               await DineWiseSessionStore.shared.manages(token) {
                accessToken = try await DineWiseSessionStore.shared.resolve(token, base: base, force: true)
                continue
            }
            throw DineWiseAPIError.failed("门店照片暂时无法读取（\(status)）。")
        }
        throw DineWiseAPIError.failed("门店照片暂时无法读取，请重试。")
    }

    func weather(token: String?, latitude: Double, longitude: Double) async throws -> DineWiseWeatherForecast {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw DineWiseAPIError.failed("位置坐标无效，请重新获取位置或检查门店档案。")
        }
        let lat = (latitude * 10).rounded() / 10
        let lon = (longitude * 10).rounded() / 10
        return try await request("/weather/forecast?latitude=\(lat)&longitude=\(lon)", token: token)
    }

    func createDemoStore(name: String, token: String, idempotencyKey: String) async throws {
        let _: DineWiseStore = try await request(
            "/stores", method: "POST",
            body: ["Name": name, "TimeZone": TimeZone.current.identifier,
                   "BusinessDayCutoffMinutes": 0],
            token: token, idempotencyKey: idempotencyKey
        )
    }

    func members(storeID: String, token: String) async throws -> [DineWiseMember] {
        try await request("/stores/\(storeID)/members", token: token, role: "owner")
    }

    func memberEvents(storeID: String, token: String, beforeID: String? = nil) async throws -> [DineWiseMemberEvent] {
        var query = "size=50"
        if let beforeID { query += "&beforeId=\(beforeID)" }
        return try await request("/stores/\(storeID)/members/events?\(query)", token: token, role: "owner")
    }

    func restoreMember(storeID: String, memberID: String, token: String,
                       idempotencyKey: String) async throws -> DineWiseMember {
        try await request(
            "/stores/\(storeID)/members/\(memberID)/restore", method: "POST",
            body: ["MemberId": memberID, "Action": "restore"], token: token,
            idempotencyKey: idempotencyKey, role: "owner"
        )
    }

    func grantMember(storeID: String, email: String, role: String, token: String,
                     idempotencyKey: String) async throws -> DineWiseMember {
        try await request(
            "/stores/\(storeID)/members", method: "POST",
            body: ["Identifier": email, "Role": role], token: token,
            idempotencyKey: idempotencyKey, role: "owner"
        )
    }

    func revokeMember(storeID: String, memberID: String, token: String,
                      idempotencyKey: String) async throws {
        let _: EmptyResult = try await request(
            "/stores/\(storeID)/members/\(memberID)", method: "DELETE",
            token: token, idempotencyKey: idempotencyKey, role: "owner"
        )
    }

    func invitations(token: String, beforeID: String? = nil) async throws -> [DineWiseMemberInvitation] {
        var query: [String] = []
        if let beforeID { query.append("beforeId=\(beforeID)") }
        if !query.isEmpty {
            return try await request("/invitations?\(query.joined(separator: "&"))", token: token)
        }
        return try await request("/invitations", token: token)
    }

    func storeInvitations(storeID: String, token: String) async throws -> [DineWiseMemberInvitation] {
        try await request("/stores/\(storeID)/invitations", token: token, role: "owner")
    }

    func inviteMember(storeID: String, email: String, role: String, token: String,
                      idempotencyKey: String) async throws {
        let _: DineWiseMemberInvitation = try await request(
            "/stores/\(storeID)/invitations", method: "POST",
            body: ["Email": email, "Role": role], token: token,
            idempotencyKey: idempotencyKey, role: "owner")
    }

    func resendInvitationEmail(storeID: String, id: String, token: String,
                               idempotencyKey: String) async throws {
        let _: DineWiseMemberInvitation = try await request(
            "/stores/\(storeID)/invitations/\(id)/resend", method: "POST",
            token: token, idempotencyKey: idempotencyKey, role: "owner")
    }

    func resolveInvitation(id: String, action: String, token: String,
                           idempotencyKey: String) async throws {
        let _: DineWiseMemberInvitation = try await request(
            "/invitations/\(id)/\(action)", method: "POST", token: token,
            idempotencyKey: idempotencyKey)
    }

    func cancelInvitation(storeID: String, id: String, token: String,
                          idempotencyKey: String) async throws {
        let _: DineWiseMemberInvitation = try await request(
            "/stores/\(storeID)/invitations/\(id)/cancel", method: "POST",
            token: token, idempotencyKey: idempotencyKey, role: "owner")
    }

    func submissions(storeID: String, token: String, role: String) async throws -> [DineWiseSubmission] {
        (try await submissionPage(storeID: storeID, token: token, role: role)).Items
    }

    func submissionPage(storeID: String, token: String, role: String,
                        planID: String = "", page: Int = 1,
                        preparationPlanID: String = "", status: String = "",
                        focusID: String? = nil) async throws -> DineWiseSubmissionPage {
        let suffix = "?page=\(page)" + (planID.isEmpty ? "" : "&purchasePlanId=\(planID)")
            + (preparationPlanID.isEmpty ? "" : "&preparationPlanId=\(preparationPlanID)")
            + (status.isEmpty ? "" : "&status=\(status)")
            + (focusID.map { "&focusId=\($0)" } ?? "")
        return try await request("/stores/\(storeID)/submissions\(suffix)", token: token, role: role)
    }

    func feedback(storeID: String, token: String, role: String,
                  businessDate: String? = nil, category: String? = nil,
                  status: String? = nil, submittedRole: String? = nil,
                  before: String? = nil) async throws -> DineWiseFeedbackOverview {
        var query: [String] = []
        if let businessDate { query.append("businessDate=\(businessDate)") }
        if let category { query.append("category=\(category)") }
        if let status { query.append("status=\(status)") }
        if let submittedRole { query.append("submittedRole=\(submittedRole)") }
        if let before {
            let encoded = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? before
            query.append("before=\(encoded)")
        }
        let suffix = query.isEmpty ? "" : "?\(query.joined(separator: "&"))"
        return try await request("/stores/\(storeID)/feedback\(suffix)", token: token, role: role)
    }

    func submissionDetail(storeID: String, submissionID: String,
                          token: String, role: String) async throws -> DineWiseSubmissionDetail {
        try await request("/stores/\(storeID)/submissions/\(submissionID)", token: token, role: role)
    }

    func submissionReviewEvents(storeID: String, submissionID: String,
                                token: String, role: String,
                                beforeID: String? = nil) async throws -> DineWiseSubmissionReviewEventPage {
        let suffix = beforeID.map { "?beforeId=\($0)" } ?? ""
        return try await request("/stores/\(storeID)/submissions/\(submissionID)/events\(suffix)",
                                 token: token, role: role)
    }

    func reviewField(storeID: String, submissionID: String, token: String, role: String,
                     version: Int, fieldKey: String, value: String, unit: String,
                     idempotencyKey: String) async throws -> DineWiseSubmissionDetail {
        try await request("/stores/\(storeID)/submissions/\(submissionID)/fields",
                          method: "PATCH", body: ["Version": version, "FieldKey": fieldKey,
                                                  "Value": value, "Unit": unit],
                          token: token, idempotencyKey: idempotencyKey, role: role)
    }

    func finishReview(storeID: String, submissionID: String, token: String, role: String,
                      version: Int, action: String,
                      idempotencyKey: String) async throws -> DineWiseSubmissionDetail {
        try await request("/stores/\(storeID)/submissions/\(submissionID)/\(action)",
                          method: "POST", body: ["Version": version], token: token,
                          idempotencyKey: idempotencyKey, role: role)
    }

    func withdrawSubmission(storeID: String, submissionID: String, token: String,
                            role: String, version: Int, reason: String,
                            idempotencyKey: String) async throws -> DineWiseSubmissionDetail {
        try await request("/stores/\(storeID)/submissions/\(submissionID)/withdraw",
                          method: "POST", body: ["Version": version, "Reason": reason],
                          token: token, idempotencyKey: idempotencyKey, role: role)
    }

    func recommendations(storeID: String, token: String, role: String,
                         focusID: String? = nil, beforeID: String? = nil,
                         size: Int = 100) async throws -> [DineWiseRecommendation] {
        var query: [String] = ["size=\(size)"]
        if let focusID { query.append("focusId=\(focusID)") }
        if let beforeID { query.append("beforeId=\(beforeID)") }
        return try await request("/stores/\(storeID)/recommendations?\(query.joined(separator: "&"))",
                                 token: token, role: role)
    }

    func dailyReport(storeID: String, businessDate: String,
                     token: String) async throws -> DineWiseDailyReport {
        try await request("/stores/\(storeID)/reports/daily?date=\(businessDate)",
                          token: token, role: "owner")
    }

    func saveDailyReportSnapshot(storeID: String, businessDate: String,
                                 token: String) async throws -> DineWiseDailyReport {
        try await request("/stores/\(storeID)/reports/daily/snapshots?date=\(businessDate)",
                          method: "POST", token: token, role: "owner")
    }

    func weeklyReport(storeID: String, weekStart: String,
                      token: String) async throws -> DineWiseWeeklyReport {
        try await request("/stores/\(storeID)/reports/weekly?weekStart=\(weekStart)",
                          token: token, role: "owner")
    }

    func monthlyReport(storeID: String, month: String, region: String? = nil,
                       token: String) async throws -> DineWiseMonthlyReport {
        let encodedRegion = region?.addingPercentEncoding(withAllowedCharacters:
            CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#?")))
        let regionQuery = encodedRegion.map { "&region=\($0)" } ?? ""
        let result: DineWiseMonthlyReport = try await request(
            "/stores/\(storeID)/reports/monthly?month=\(month)\(regionQuery)",
            token: token, role: "owner")
        return result
    }

    func weeklyProblems(storeID: String, weekStart: String,
                        token: String) async throws -> DineWiseWeeklyProblemReport {
        try await request("/stores/\(storeID)/reports/weekly/problems?weekStart=\(weekStart)",
                          token: token, role: "owner")
    }

    func saveWeeklyProblems(storeID: String, weekStart: String,
                            token: String) async throws -> DineWiseWeeklyProblemReport {
        try await request("/stores/\(storeID)/reports/weekly/problems/snapshots?weekStart=\(weekStart)",
                          method: "POST", token: token, role: "owner")
    }

    func weeklyCalendar(storeID: String, weekStart: String,
                        token: String) async throws -> DineWiseWeeklyCalendar {
        try await request("/stores/\(storeID)/calendar/weekly?weekStart=\(weekStart)",
                          token: token, role: "owner")
    }

    func saveWeeklyCalendar(storeID: String, weekStart: String, token: String,
                            mask: Int, version: Int, key: String) async throws -> DineWiseWeeklyCalendar {
        try await request("/stores/\(storeID)/calendar/weekly?weekStart=\(weekStart)",
                          method: "PUT", body: ["OpenDaysMask": mask, "ExpectedVersion": version],
                          token: token, idempotencyKey: key, role: "owner")
    }

    func notices(storeID: String, token: String, role: String) async throws -> [DineWiseNotice] {
        try await request("/stores/\(storeID)/notices", token: token, role: role)
    }

    func publicPriceReferences(region: String) async throws -> [DineWisePublicPriceReference] {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#?"))
        let encoded = region.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return try await request("/public/prices?region=\(encoded)")
    }

    func publicActivities(region: String) async throws -> [DineWisePublicActivity] {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#?"))
        let encoded = region.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return try await request("/public/activities?region=\(encoded)")
    }

    func noticeFeedback(storeID: String, noticeID: String, token: String,
                        version: Int, rating: String, idempotencyKey: String) async throws {
        let _: DineWiseNoticeFeedbackResult = try await request(
            "/stores/\(storeID)/notices/\(noticeID)/feedback", method: "POST",
            body: ["Version": version, "Rating": rating], token: token,
            idempotencyKey: idempotencyKey, role: "owner")
    }

    func interviews(storeID: String, token: String, beforeID: String? = nil,
                    size: Int = 100) async throws -> [DineWiseInterview] {
        var query = ["size=\(size)"]
        if let beforeID { query.append("beforeId=\(beforeID)") }
        return try await request("/demo-stores/\(storeID)/interviews?\(query.joined(separator: "&"))",
                                 token: token, role: "marketer")
    }

    func createInterview(storeID: String, token: String, draft: DineWiseInterviewDraft,
                         idempotencyKey: String) async throws -> DineWiseInterview {
        let capabilities: DineWiseInterviewCapabilities = try await request(
            "/demo-stores/\(storeID)/interviews/capabilities", token: token, role: "marketer")
        guard capabilities.IntervieweeConsentConfirmationRequired else {
            throw DineWiseAPIError.failed("当前服务端尚未启用访谈记录许可核对，未提交访谈。")
        }
        if draft.observedOperationDurationSeconds != nil {
            guard capabilities.ObservedOperationDurationSupported == true else {
                throw DineWiseAPIError.failed("当前服务端尚不支持保存实测操作用时，计时资料已保留，未提交访谈。")
            }
        }
        let result: DineWiseInterview = try await request("/demo-stores/\(storeID)/interviews", method: "POST", body: [
            "BusinessType": draft.businessType, "StoreCount": draft.storeCount,
            "CurrentTools": draft.currentTools, "IntervieweeRole": draft.intervieweeRole,
            "DemoSteps": draft.demoSteps, "DemoDurationSeconds": draft.demoDurationSeconds as Any? ?? NSNull(),
            "ObservedOperationType": draft.observedOperationType as Any? ?? NSNull(),
            "ObservedOperationDurationSeconds": draft.observedOperationDurationSeconds as Any? ?? NSNull(),
            "IntervieweeConsentConfirmed": draft.intervieweeConsentConfirmed,
            "UsefulQuote": draft.usefulQuote,
            "ConcernQuote": draft.concernQuote, "WillingData": draft.willingData,
            "DailyBurdenMinutes": draft.dailyBurdenMinutes as Any? ?? NSNull(),
            "Interest": draft.interest, "SubmitWillingness": draft.submitWillingness,
            "PayWillingness": draft.payWillingness, "TrialWillingness": draft.trialWillingness
        ],
                          token: token, idempotencyKey: idempotencyKey, role: "marketer")
        guard result.IntervieweeConsentConfirmed == true else {
            throw DineWiseAPIError.failed("服务端未返回访谈记录许可回执，请联系管理员核对，避免重复提交。")
        }
        if let seconds = draft.observedOperationDurationSeconds {
            guard result.ObservedOperationType == draft.observedOperationType,
                  result.ObservedOperationDurationSeconds == seconds else {
                throw DineWiseAPIError.failed("服务端未返回相同的实测用时回执，访谈状态未确认；请联系管理员核对后再重试。")
            }
        }
        return result
    }

    func proposeRecommendation(storeID: String, token: String, role: String,
                               sourceSubmissionID: String, title: String, rationale: String,
                               calculationBasis: String, confidenceLevel: String,
                               confidenceReason: String, steps: String, targetRole: String,
                               validUntilOn: String?,
                               replacesRecommendationID: String?,
                               idempotencyKey: String) async throws -> DineWiseRecommendation {
        var body: [String: Any] = [
            "SourceSubmissionId": sourceSubmissionID, "Title": title,
            "Rationale": rationale, "CalculationBasis": calculationBasis,
            "ConfidenceLevel": confidenceLevel, "ConfidenceReason": confidenceReason,
            "Steps": steps, "TargetRole": targetRole
        ]
        if let validUntilOn, !validUntilOn.isEmpty { body["ValidUntilOn"] = validUntilOn }
        if let replacesRecommendationID, !replacesRecommendationID.isEmpty {
            body["ReplacesRecommendationId"] = replacesRecommendationID
        }
        return try await request("/stores/\(storeID)/recommendations", method: "POST",
                                 body: body, token: token, idempotencyKey: idempotencyKey, role: role)
    }

    func decideRecommendation(storeID: String, recommendationID: String,
                              token: String, role: String, version: Int, action: String,
                              reason: String, remindOn: String?, assignedUserID: String?,
                              dueOn: String?,
                              idempotencyKey: String) async throws -> DineWiseRecommendation {
        var body: [String: Any] = ["Version": version, "Action": action, "Reason": reason]
        if let remindOn { body["RemindOn"] = remindOn }
        if let assignedUserID { body["AssignedUserId"] = assignedUserID }
        if let dueOn { body["DueOn"] = dueOn }
        return try await request("/stores/\(storeID)/recommendations/\(recommendationID)/decision",
                                 method: "POST", body: body, token: token,
                                 idempotencyKey: idempotencyKey, role: role)
    }

    func tasks(storeID: String, token: String, role: String,
               focusID: String? = nil, beforeID: String? = nil,
               size: Int = 100, preparationAvailable: Bool = false,
               meetingWeekStartOn: String? = nil,
               excludeMeetings: Bool = false) async throws -> [DineWiseTask] {
        var query: [String] = ["size=\(size)"]
        if preparationAvailable { query.append("preparationAvailable=true") }
        if let meetingWeekStartOn { query.append("meetingWeekStartOn=\(meetingWeekStartOn)") }
        if excludeMeetings { query.append("excludeMeetings=true") }
        if let focusID { query.append("focusId=\(focusID)") }
        if let beforeID { query.append("beforeId=\(beforeID)") }
        return try await request("/stores/\(storeID)/tasks?\(query.joined(separator: "&"))",
                                 token: token, role: role)
    }

    func meetingProgress(storeID: String, token: String, role: String,
                         weekStartOn: String) async throws -> DineWiseMeetingProgressSummary {
        try await request("/stores/\(storeID)/tasks/meeting-progress?weekStartOn=\(weekStartOn)",
                          token: token, role: role)
    }

    func meetingTaskEvents(storeID: String, taskID: String, token: String,
                           role: String, size: Int = 100, beforeID: String? = nil) async throws -> DineWiseTaskEventHistory {
        let cursor = beforeID.map { "&beforeId=\($0)" } ?? ""
        let history: DineWiseTaskEventHistory = try await request(
            "/stores/\(storeID)/tasks/\(taskID)/events?size=\(min(max(size, 1), 200))\(cursor)",
            token: token, role: role)
        return history
    }

    func taskNotifications(storeID: String, token: String,
                           role: String, size: Int = 20) async throws -> [DineWiseTaskNotification] {
        try await request("/stores/\(storeID)/tasks/notifications?unreadOnly=true&size=\(min(max(size, 1), 100))",
                          token: token, role: role)
    }

    func registerPushDevice(token: String, environment: String,
                            accessToken: String) async throws -> DineWisePushDeviceSummary {
        try await request("/push-devices", method: "POST", body: [
            "Platform": "ios", "Environment": environment, "Token": token
        ], token: accessToken)
    }

    func revokePushDevice(id: String, accessToken: String) async throws {
        let _: EmptyResult = try await request("/push-devices/\(id)", method: "DELETE",
            token: accessToken)
    }

    func markTaskNotificationRead(storeID: String, notificationID: String,
                                  token: String, role: String) async throws -> DineWiseTaskNotification {
        try await request("/stores/\(storeID)/tasks/notifications/\(notificationID)/read",
                          method: "POST", token: token, role: role)
    }

    func createMeetingTask(storeID: String, token: String, role: String,
                           meetingOn: String, title: String, steps: String,
                           targetRole: String, assignedUserID: String?, dueOn: String?,
                           idempotencyKey: String) async throws -> DineWiseTask {
        var body: [String: Any] = ["MeetingOn": meetingOn, "Title": title,
                                   "Steps": steps, "TargetRole": targetRole]
        if let assignedUserID { body["AssignedUserId"] = assignedUserID }
        if let dueOn { body["DueOn"] = dueOn }
        return try await request("/stores/\(storeID)/tasks", method: "POST", body: body,
                                 token: token, idempotencyKey: idempotencyKey, role: role)
    }

    func preparationPlans(storeID: String, token: String,
                          role: String, beforeID: String = "") async throws -> [DineWisePreparationPlan] {
        let suffix = beforeID.isEmpty ? "" : "?beforeId=\(beforeID)"
        return try await request("/stores/\(storeID)/preparation-plans\(suffix)", token: token, role: role)
    }

    func purchasePlans(storeID: String, token: String,
                       role: String, beforeID: String = "") async throws -> [DineWisePurchasePlan] {
        let suffix = beforeID.isEmpty ? "" : "?beforeId=\(beforeID)"
        return try await request("/stores/\(storeID)/purchase-plans\(suffix)", token: token, role: role)
    }

    func previewPurchaseSuggestion(storeID: String, planID: String, token: String,
                                   role: String, version: Int,
                                   items: [DineWisePurchaseInventoryInput]) async throws -> DineWisePurchaseSuggestionPreview {
        let payload: [[String: Any]] = items.map { item in
            var row: [String: Any] = ["IngredientName": item.IngredientName,
                                      "Unit": item.Unit]
            if let quantity = item.CurrentStockQuantity {
                row["CurrentStockQuantity"] = NSDecimalNumber(decimal: quantity)
            }
            if let quantity = item.InTransitQuantity {
                row["InTransitQuantity"] = NSDecimalNumber(decimal: quantity)
            }
            if let quantity = item.ReservedQuantity {
                row["ReservedQuantity"] = NSDecimalNumber(decimal: quantity)
            }
            return row
        }
        return try await request("/stores/\(storeID)/purchase-plans/\(planID)/suggestion-preview",
            method: "POST", body: ["Version": version, "Items": payload],
            token: token, role: role)
    }

    func savePreparationPlan(storeID: String, planID: String?, token: String,
                             role: String, taskID: String, businessDate: String,
                             version: Int, items: [DineWisePreparationPlanItem], reason: String,
                             idempotencyKey: String) async throws -> DineWisePreparationPlan {
        let path = "/stores/\(storeID)/preparation-plans" +
            (planID.map { "/\($0)" } ?? "")
        let payload: [[String: Any]] = items.map { item in
            ["IngredientName": item.IngredientName.trimmingCharacters(in: .whitespacesAndNewlines),
             "Unit": item.Unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
             "MinimumQuantity": NSDecimalNumber(decimal: item.MinimumQuantity),
             "MaximumQuantity": NSDecimalNumber(decimal: item.MaximumQuantity),
             "Basis": item.Basis.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        guard try dineWiseStoredJSONLength(payload) <= 12_000 else {
            throw DineWiseAPIError.failed("备菜单内容超过 12,000 字符保存上限，请减少项目或精简名称和人工依据。")
        }
        return try await request(path, method: planID == nil ? "POST" : "PUT",
            body: ["TaskId": taskID, "BusinessDate": businessDate,
                   "Version": version, "Items": payload, "Reason": reason],
            token: token, idempotencyKey: idempotencyKey, role: role)
    }

    func confirmPreparationPlan(storeID: String, planID: String, token: String,
                                role: String, version: Int,
                                idempotencyKey: String) async throws -> DineWisePreparationPlan {
        try await request("/stores/\(storeID)/preparation-plans/\(planID)/confirm",
            method: "POST", body: ["Version": version], token: token,
            idempotencyKey: idempotencyKey, role: role)
    }

    func reviewReassignedPreparationPlan(storeID: String, planID: String, token: String,
                                         role: String, version: Int,
                                         idempotencyKey: String) async throws -> DineWisePreparationPlan {
        try await request("/stores/\(storeID)/preparation-plans/\(planID)/review-reassignment",
            method: "POST", body: ["Version": version], token: token,
            idempotencyKey: idempotencyKey, role: role)
    }

    func savePurchasePlan(storeID: String, planID: String, token: String,
                          role: String, version: Int,
                          items: [DineWisePurchasePlanItem], reason: String,
                          idempotencyKey: String) async throws -> DineWisePurchasePlan {
        let payload: [[String: Any]] = items.map { item in
            ["IngredientName": item.IngredientName.trimmingCharacters(in: .whitespacesAndNewlines),
             "Unit": item.Unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
             "OrderQuantity": NSDecimalNumber(decimal: item.OrderQuantity),
             "InventoryCheck": item.InventoryCheck.trimmingCharacters(in: .whitespacesAndNewlines),
             "SupplierName": item.SupplierName.trimmingCharacters(in: .whitespacesAndNewlines),
             "PackageSpecification": item.PackageSpecification.trimmingCharacters(in: .whitespacesAndNewlines),
             "QuantityReason": item.QuantityReason.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        guard try dineWiseStoredJSONLength(payload) <= 12_000 else {
            throw DineWiseAPIError.failed("订货内容超过 12,000 字符保存上限，请减少项目或精简核对说明。")
        }
        return try await request("/stores/\(storeID)/purchase-plans/\(planID)",
            method: "PUT", body: ["Version": version, "Items": payload, "Reason": reason],
            token: token, idempotencyKey: idempotencyKey, role: role)
    }

    func confirmPurchasePlan(storeID: String, planID: String, token: String,
                             role: String, version: Int,
                             idempotencyKey: String) async throws -> DineWisePurchasePlan {
        try await request("/stores/\(storeID)/purchase-plans/\(planID)/confirm",
            method: "POST", body: ["Version": version], token: token,
            idempotencyKey: idempotencyKey, role: role)
    }

    func ownerToday(storeID: String, token: String) async throws -> DineWiseOwnerTodaySummary {
        try await request("/stores/\(storeID)/today", token: token, role: "owner")
    }

    func taskAction(storeID: String, taskID: String, token: String, role: String,
                    version: Int, action: String, note: String, assignedUserID: String?,
                    dueOn: String?, reviewDueOn: String?, escalationRule: String? = nil,
                    idempotencyKey: String) async throws -> DineWiseTask {
        var body: [String: Any] = ["Version": version, "Action": action, "Note": note]
        if let assignedUserID { body["AssignedUserId"] = assignedUserID }
        if let dueOn { body["DueOn"] = dueOn }
        if let escalationRule { body["EscalationRule"] = escalationRule }
        if let reviewDueOn { body["ReviewDueOn"] = reviewDueOn }
        return try await request("/stores/\(storeID)/tasks/\(taskID)/actions", method: "POST",
                                 body: body, token: token, idempotencyKey: idempotencyKey, role: role)
    }

    func taskReviews(storeID: String, token: String, role: String,
                     focusID: String? = nil, beforeID: String? = nil,
                     size: Int = 100) async throws -> [DineWiseTaskReview] {
        var query: [String] = ["size=\(size)"]
        if let focusID { query.append("focusId=\(focusID)") }
        if let beforeID { query.append("beforeId=\(beforeID)") }
        return try await request("/stores/\(storeID)/reviews?\(query.joined(separator: "&"))",
                                 token: token, role: role)
    }

    func finishTaskReview(storeID: String, reviewID: String, token: String, role: String,
                          version: Int, outcome: String, metricKey: String?,
                          beforeSubmissionID: String?, afterSubmissionID: String?,
                          confounders: String, conclusion: String, nextStep: String,
                          idempotencyKey: String) async throws -> DineWiseTaskReview {
        var body: [String: Any] = ["Version": version, "Outcome": outcome,
                                   "Confounders": confounders, "Conclusion": conclusion,
                                   "NextStep": nextStep]
        if let metricKey { body["MetricKey"] = metricKey }
        if let beforeSubmissionID { body["BeforeSubmissionId"] = beforeSubmissionID }
        if let afterSubmissionID { body["AfterSubmissionId"] = afterSubmissionID }
        return try await request("/stores/\(storeID)/reviews/\(reviewID)/result",
                                 method: "POST", body: body, token: token,
                                 idempotencyKey: idempotencyKey, role: role)
    }

    func submitText(storeID: String, token: String, role: String, kind: String,
                    businessDate: String, originalText: String, feedbackCategory: String?,
                    textOrigin: String,
                    recognitionFailureCode: String?,
                    recognitionFailureImageSha256: String?,
                    occurredAtUtc: String?, purchasePlanId: String?, preparationPlanId: String?,
                    idempotencyKey: String) async throws -> DineWiseSubmission {
        var body: [String: Any] = ["Kind": kind, "BusinessDate": businessDate,
                                   "OriginalText": originalText, "TextOrigin": textOrigin]
        if let recognitionFailureCode { body["RecognitionFailureCode"] = recognitionFailureCode }
        if let recognitionFailureImageSha256 {
            body["RecognitionFailureImageSha256"] = recognitionFailureImageSha256
        }
        if let feedbackCategory, let occurredAtUtc {
            body["FeedbackCategory"] = feedbackCategory
            body["OccurredAtUtc"] = occurredAtUtc
        }
        if let purchasePlanId, kind == "purchase" && role == "purchaser" {
            body["PurchasePlanId"] = purchasePlanId
        }
        if let preparationPlanId, kind == "kitchen" && role == "chef" {
            body["PreparationPlanId"] = preparationPlanId
        }
        return try await request(
            "/stores/\(storeID)/submissions", method: "POST",
            body: body,
            token: token, idempotencyKey: idempotencyKey, role: role
        )
    }

    func files(storeID: String, submissionID: String, token: String,
               role: String) async throws -> [DineWiseSubmissionFile] {
        try await request("/stores/\(storeID)/submissions/\(submissionID)/files",
                          token: token, role: role)
    }

    func deleteFile(storeID: String, submissionID: String, fileID: String,
                    version: Int, token: String, role: String,
                    idempotencyKey: String) async throws {
        let _: DineWiseSubmissionFile = try await request(
            "/stores/\(storeID)/submissions/\(submissionID)/files/\(fileID)?version=\(version)",
            method: "DELETE", token: token, idempotencyKey: idempotencyKey, role: role)
    }

    func uploadFile(storeID: String, submissionID: String, token: String, role: String,
                    fileName: String, data: Data, idempotencyKey: String,
                    isRecognitionOriginal: Bool = false) async throws {
        guard data.count <= 10 * 1024 * 1024 else {
            throw DineWiseAPIError.failed("单个附件不能超过 10 MB。")
        }
        guard let base = URL(string: baseURL),
              let url = URL(string: "api/restaurant-assistant/stores/\(storeID)/submissions/\(submissionID)/files",
                            relativeTo: base)?.absoluteURL,
              isAllowedEndpoint(url) else { throw DineWiseAPIError.invalidURL }
        let boundary = "DineWise-\(UUID().uuidString)"
        let safeName = fileName.replacingOccurrences(of: "\"", with: "_")
        var body = Data()
        if isRecognitionOriginal {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"isRecognitionOriginal\"\r\n\r\ntrue\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var accessToken = try await DineWiseSessionStore.shared.resolve(token, base: base)
        for attempt in 0..<2 {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(role, forHTTPHeaderField: "X-DineWise-Role")
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
            let (responseData, response) = try await URLSession.shared.upload(for: request, from: body)
            let envelope = try JSONDecoder().decode(APIEnvelope<DineWiseSubmissionFile>.self,
                                                    from: responseData)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status), envelope.success, envelope.response != nil { return }
            if attempt == 0, status == 401 || envelope.status == 401,
               await DineWiseSessionStore.shared.manages(token) {
                accessToken = try await DineWiseSessionStore.shared.resolve(token, base: base, force: true)
                continue
            }
            throw DineWiseAPIError.failed(dineWiseFailureMessage(envelope.msg,
                httpStatus: status, envelopeStatus: envelope.status, fallback: "附件上传失败"))
        }
        throw DineWiseAPIError.failed("附件上传失败，请重试。")
    }

    func downloadFile(storeID: String, submissionID: String, fileID: String,
                      token: String, role: String) async throws -> Data {
        guard let base = URL(string: baseURL),
              let url = URL(string: "api/restaurant-assistant/stores/\(storeID)/submissions/\(submissionID)/files/\(fileID)",
                            relativeTo: base)?.absoluteURL,
              isAllowedEndpoint(url) else { throw DineWiseAPIError.invalidURL }
        var accessToken = try await DineWiseSessionStore.shared.resolve(token, base: base)
        for attempt in 0..<2 {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(role, forHTTPHeaderField: "X-DineWise-Role")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status), data.count <= 10 * 1024 * 1024 { return data }
            if attempt == 0, status == 401,
               await DineWiseSessionStore.shared.manages(token) {
                accessToken = try await DineWiseSessionStore.shared.resolve(token, base: base, force: true)
                continue
            }
            throw DineWiseAPIError.failed("附件下载失败。")
        }
        throw DineWiseAPIError.failed("附件下载失败，请重试。")
    }

    private func isAllowedEndpoint(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        #if DEBUG
        return url.scheme == "http" && (url.host == "localhost" || url.host == "127.0.0.1"
            || url.host?.hasPrefix("192.168.") == true || url.host?.hasPrefix("10.") == true)
        #else
        return false
        #endif
    }
}

actor DineWiseSessionStore {
    static let shared = DineWiseSessionStore()

    private var logicalToken: String?
    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt = Date.distantPast
    private var refreshTask: Task<DineWiseSession, Error>?
    private var restoreTask: Task<DineWiseSession, Error>?
    private var restoreTaskID: UUID?
    private var restoreToken: String?

    func register(_ session: DineWiseSession) {
        logicalToken = session.AccessToken
        accessToken = session.AccessToken
        refreshToken = session.RefreshToken
        expiresAt = Date().addingTimeInterval(TimeInterval(session.AccessTokenExpiresInSeconds))
        refreshTask = nil
        restoreTask = nil
        restoreTaskID = nil
        restoreToken = nil
        DineWiseRefreshCredential.save(session.RefreshToken)
    }

    func restore(base: URL) async throws -> DineWiseSession? {
        guard logicalToken == nil,
              let saved = DineWiseRefreshCredential.read() else { return nil }
        guard let url = URL(string: "api/restaurant-assistant/auth/refresh",
                            relativeTo: base)?.absoluteURL else { throw DineWiseAPIError.invalidURL }
        let task: Task<DineWiseSession, Error>
        let taskID: UUID
        if let restoreTask, restoreToken == saved, let restoreTaskID {
            task = restoreTask
            taskID = restoreTaskID
        } else {
            taskID = UUID()
            task = Task {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["RefreshToken": saved])
                let (data, response) = try await URLSession.shared.data(for: request)
                let envelope = try JSONDecoder().decode(APIEnvelope<DineWiseSession>.self, from: data)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status), envelope.success, let session = envelope.response else {
                    if (status == 401 || envelope.status == 401)
                        && DineWiseRefreshCredential.read() == saved {
                        DineWiseRefreshCredential.clear()
                    }
                    throw DineWiseAPIError.failed(dineWiseFailureMessage(envelope.msg,
                        httpStatus: status, envelopeStatus: envelope.status,
                        fallback: "恢复登录失败，请重新获取验证码。"))
                }
                return session
            }
            restoreTask = task
            restoreTaskID = taskID
            restoreToken = saved
        }
        do {
            let session = try await task.value
            if logicalToken == session.AccessToken && refreshToken == session.RefreshToken {
                return session
            }
            guard restoreTaskID == taskID, logicalToken == nil,
                  DineWiseRefreshCredential.read() == saved else {
                clearRestoreTask(ifMatching: taskID)
                return nil
            }
            logicalToken = session.AccessToken
            accessToken = session.AccessToken
            refreshToken = session.RefreshToken
            expiresAt = Date().addingTimeInterval(TimeInterval(session.AccessTokenExpiresInSeconds))
            DineWiseRefreshCredential.save(session.RefreshToken)
            clearRestoreTask(ifMatching: taskID)
            return session
        } catch {
            clearRestoreTask(ifMatching: taskID)
            throw error
        }
    }

    private func clearRestoreTask(ifMatching taskID: UUID) {
        guard restoreTaskID == taskID else { return }
        restoreTask = nil
        restoreTaskID = nil
        restoreToken = nil
    }

    func manages(_ token: String) -> Bool { logicalToken == token }

    func resolve(_ token: String, base: URL, force: Bool = false) async throws -> String {
        guard logicalToken == token, let current = accessToken,
              let refreshToken else { return token }
        if !force && Date() < expiresAt.addingTimeInterval(-300) { return current }
        let task: Task<DineWiseSession, Error>
        if let refreshTask { task = refreshTask }
        else {
            guard let url = URL(string: "api/restaurant-assistant/auth/refresh",
                                relativeTo: base)?.absoluteURL else {
                throw DineWiseAPIError.invalidURL
            }
            task = Task {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["RefreshToken": refreshToken])
                let (data, response) = try await URLSession.shared.data(for: request)
                let envelope = try JSONDecoder().decode(APIEnvelope<DineWiseSession>.self, from: data)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status), envelope.success,
                      let session = envelope.response else {
                    if status == 401 || envelope.status == 401 {
                        throw DineWiseAPIError.sessionExpired
                    }
                    throw DineWiseAPIError.failed(dineWiseFailureMessage(envelope.msg,
                        httpStatus: status, envelopeStatus: envelope.status,
                        fallback: "会话续期失败，请重新登录。"))
                }
                return session
            }
            refreshTask = task
        }
        do {
            let session = try await task.value
            guard logicalToken == token else { throw DineWiseAPIError.failed("会话已更改，请重新登录。") }
            if accessToken == session.AccessToken { return session.AccessToken }
            guard self.refreshToken == refreshToken else {
                throw DineWiseAPIError.failed("会话已更改，请重新登录。")
            }
            accessToken = session.AccessToken
            self.refreshToken = session.RefreshToken
            expiresAt = Date().addingTimeInterval(TimeInterval(session.AccessTokenExpiresInSeconds))
            DineWiseRefreshCredential.save(session.RefreshToken)
            refreshTask = nil
            return session.AccessToken
        } catch {
            if case DineWiseAPIError.sessionExpired = error,
               logicalToken == token, self.refreshToken == refreshToken {
                logicalToken = nil
                accessToken = nil
                self.refreshToken = nil
                expiresAt = .distantPast
                DineWiseRefreshCredential.clear()
                NotificationCenter.default.post(name: .dineWiseSessionExpired, object: nil)
            }
            refreshTask = nil
            throw error
        }
    }

    func revoke(_ token: String, base: URL) async {
        guard logicalToken == token else { return }
        var toRevoke = Set<String>()
        if let refreshToken { toRevoke.insert(refreshToken) }
        let pending = refreshTask
        logicalToken = nil
        accessToken = nil
        refreshToken = nil
        refreshTask = nil
        DineWiseRefreshCredential.clear()
        if let pending, let rotated = try? await pending.value {
            toRevoke.insert(rotated.RefreshToken)
        }
        guard let url = URL(string: "api/restaurant-assistant/auth/logout",
                            relativeTo: base)?.absoluteURL else { return }
        for value in toRevoke {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["RefreshToken": value])
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}

private enum DineWiseRefreshCredential {
    private static let service = "com.jaronsoft.dinewise.merchant.refresh"
    private static let account = "merchant"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        let value = Data(token.utf8)
        let update: [String: Any] = [kSecValueData as String: value]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = value
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
