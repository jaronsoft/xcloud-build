import Foundation

struct APIEnvelope<Value: Decodable>: Decodable {
    let response: Value
    let success: Bool?
    let msg: String?
}

struct AuthTokens: Decodable {
    let accessToken: String
    let refreshToken: String
}

struct AuthPayload: Decodable {
    let tokens: AuthTokens
}

struct OnboardingSubscribeDTO: Decodable {
    let child: ChildDTO
    let enrollment: EnrollmentDTO
    let scheduleProfile: ScheduleProfileDTO
}

struct RefreshPayload: Decodable {
    let tokens: AuthTokens
}

struct ParentUser: Decodable {
    let id: String
    let email: String
}

struct MePayload: Decodable {
    let user: ParentUser
}

struct PreferencesDTO: Decodable {
    let language: String
    let timezone: String
}

struct MeroliAccountDeleteDTO: Decodable {
    let deleted: Bool
}

struct AppleBindingDTO: Decodable {
    let linked: Bool
}

struct FamilyDTO: Decodable {
    let id: String
    let name: String?
}

struct ChildDTO: Decodable, Identifiable {
    let id: String
    let familyId: String
    let nickname: String
    let createdAt: String
    let updatedAt: String
}

struct DistrictDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let shortName: String
    let state: String
}

struct SchoolYearDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let startDate: String
    let endDate: String
}

struct ParentSchoolDTO: Decodable, Identifiable {
    let id: String
    let districtId: String
    let name: String
    let schoolType: String
    let availableGrades: [String]
    let address: String
    let city: String
    let state: String
    let postalCode: String
    let phone: String?
    let websiteUrl: String?
}

struct EnrollmentDTO: Decodable, Identifiable {
    let id: String
    let childId: String
    let childName: String
    let schoolId: String
    let districtId: String
    let schoolName: String
    let schoolYearId: String
    let schoolYearName: String
    let grade: Int
    let gradeCode: String
    let status: String
    let startedAt: String
    let endedAt: String?

    var isCurrent: Bool { status == "ACTIVE" || status == "GRADUATING" }
}

struct SchoolYearTransitionDTO: Decodable, Identifiable {
    let enrollmentId: String
    var id: String { enrollmentId }
    let childId: String
    let childName: String
    let schoolId: String
    let schoolName: String
    let districtId: String
    let gradeCode: String
    let schoolYearId: String
    let schoolYearLabel: String
    let status: String
    let graduating: Bool
    let finishedK12Available: Bool
    let suggestedGrade: Int?
    let suggestedGradeCode: String?
    let targetSchoolYearId: String?
    let targetSchoolYearLabel: String?
    let transitionAvailable: Bool?
    let transitionAvailableDate: String?
    let programReconfirmationRequired: Bool
}

struct ParentEventDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let originalTitle: String?
    let eventType: String
    let eventCode: String?
    let scopeType: String
    let startDate: String
    let endDate: String?
    let startTime: String?
    let endTime: String?
    let allDay: Bool
    let timezone: String
    let priority: String
    let parentRelevance: String
    let scheduleAction: String
    let scheduleCodeOverride: String?
    let explanation: String
    let action: String
    let location: String?
    let sourceName: String
    let sourceUrl: String
    let lastUpdatedAt: String
    let children: [ParentEventChildDTO]
    let schools: [ParentEventSchoolDTO]
}

struct ParentEventChildDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let schoolId: String
}

struct ParentEventSchoolDTO: Decodable, Identifiable {
    let id: String
    let name: String
}

struct DailyScheduleDTO: Decodable, Identifiable {
    let childId: String
    var id: String { childId }
    let childName: String
    let date: String
    let status: String
    let schoolName: String?
    let schoolYearName: String?
    let grade: Int?
    let scheduleType: String?
    let scheduleCode: String?
    let variantCode: String?
    let firstPeriodCode: String?
    let arrivalLabel: String?
    let explanationKey: String?
    let arrivalTime: String?
    let dismissalTime: String?
    let reason: String?
    let eventTitles: [String]
    let periods: [DailySchedulePeriodDTO]?
}

struct NextInstructionalDayDTO: Decodable {
    let date: String?
}

struct DailySchedulePeriodDTO: Decodable, Identifiable {
    let code: String
    var id: String { code }
    let labelEn: String
    let labelZh: String
    let startTime: String
    let endTime: String
    let isOptional: Bool
    let periodRole: String
}

struct ScheduleProfileDTO: Decodable {
    let childId: String
    let schoolId: String
    let scheduleVariantCode: String
    let selectionStatus: String
    let programIds: [String]
    let availableVariantCodes: [String]
    let availableVariants: [ScheduleVariantOptionDTO]?
    let programs: [ScheduleProgramDTO]
}

struct ScheduleVariantOptionDTO: Decodable, Identifiable {
    let variantCode: String
    let variantName: String?
    var id: String { variantCode }
}

struct ScheduleProgramDTO: Decodable, Identifiable {
    let id: String
    let code: String
    let displayNameEn: String
    let displayNameZh: String
    let affectsArrivalTime: Bool
    let periodCode: String?
}

struct ParentSchoolOverviewDTO: Decodable {
    let schoolId: String
    let schoolName: String
    let schoolType: String?
    let minGrade: Int?
    let maxGrade: Int?
    let address: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let phone: String?
    let websiteUrl: String?
    let children: [ParentSchoolChildDTO]?
    let dailySchedules: [DailyScheduleDTO]?
    let bellSchedules: [ParentBellScheduleDTO]?
    let attendance: ParentAttendanceDTO?
    let performance: ParentPerformanceDTO?
}

struct ParentBellScheduleDTO: Decodable, Identifiable {
    let name: String
    let scheduleCategory: String
    let effectiveFrom: String?
    let effectiveTo: String?
    let variants: [ParentBellScheduleVariantDTO]
    var id: String { "\(scheduleCategory)-\(name)" }
}

struct ParentBellScheduleVariantDTO: Decodable, Identifiable {
    let name: String
    let arrivalTime: String?
    let dismissalTime: String?
    let periods: [DailySchedulePeriodDTO]
    var id: String { name }
}

struct ParentSchoolChildDTO: Decodable, Identifiable {
    let childId: String
    var id: String { childId }
    let childName: String
    let grade: Int
    let gradeCode: String
    let schoolYearName: String?
}

struct ParentAttendanceDTO: Decodable {
    let attendanceMethod: String
    let attendanceUrl: String?
    let attendancePhone: String?
    let attendanceEmail: String?
    let absenceInstruction: String
    let lateArrivalInstruction: String
    let earlyPickupInstruction: String
    let lastVerifiedAt: String
}

struct ParentPerformanceDTO: Decodable {
    let reportingCycle: String
    let academicYear: String
    let populationScope: String
    let availability: String
    let sourceName: String
    let sourceUrl: String
    let publishedAt: String
    let disclaimer: String
    let metrics: [ParentPerformanceMetricDTO]
}

struct ParentPerformanceHistoryDTO: Decodable {
    let schoolId: String
    let schoolName: String
    let latestCycle: String?
    let cycles: [ParentPerformanceDTO]
    let metrics: [ParentPerformanceHistoryMetricDTO]
    let trendPolicy: String?

    private enum CodingKeys: String, CodingKey {
        case schoolId, schoolName, latestCycle, cycles, metrics, trendPolicy
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schoolId = try values.decode(String.self, forKey: .schoolId)
        schoolName = try values.decode(String.self, forKey: .schoolName)
        latestCycle = try values.decodeIfPresent(String.self, forKey: .latestCycle)
        cycles = try values.decodeIfPresent([ParentPerformanceDTO].self, forKey: .cycles) ?? []
        metrics = try values.decodeIfPresent([ParentPerformanceHistoryMetricDTO].self, forKey: .metrics) ?? []
        trendPolicy = try values.decodeIfPresent(String.self, forKey: .trendPolicy)
    }
}

struct ParentPerformanceMetricDTO: Decodable, Identifiable {
    let metricCode: String
    var id: String { metricCode }
    let metricName: String
    let metricGroup: String
    let officialValue: String?
    let numericValue: Double?
    let unit: String
    let officialStatus: String
    let officialChange: String?
    let officialPerformanceLevel: String?
    let officialColor: String?
    let direction: String?
    let applicable: Bool
    let presentation: ParentPerformancePresentationDTO?
}

struct ParentPerformancePresentationDTO: Decodable {
    let parentLabel: String?
    let parentDefinition: String?
    let officialTerminology: String?
    let unitCode: String?
    let displayValue: String?
    let shortValue: String?
    let displayChange: String?
    let changeMeaning: String?
    let directionExplanation: String?
    let performanceLevelLabel: String?
    let comparisonValues: [ParentPerformanceComparisonValueDTO]
    let comparisonSummary: String?
    let methodologyId: String?

    private enum CodingKeys: String, CodingKey {
        case parentLabel, parentDefinition, officialTerminology, unitCode, displayValue, shortValue
        case displayChange, changeMeaning, directionExplanation, performanceLevelLabel
        case comparisonValues, comparisonSummary, methodologyId
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        parentLabel = try values.decodeIfPresent(String.self, forKey: .parentLabel)
        parentDefinition = try values.decodeIfPresent(String.self, forKey: .parentDefinition)
        officialTerminology = try values.decodeIfPresent(String.self, forKey: .officialTerminology)
        unitCode = try values.decodeIfPresent(String.self, forKey: .unitCode)
        displayValue = try values.decodeIfPresent(String.self, forKey: .displayValue)
        shortValue = try values.decodeIfPresent(String.self, forKey: .shortValue)
        displayChange = try values.decodeIfPresent(String.self, forKey: .displayChange)
        changeMeaning = try values.decodeIfPresent(String.self, forKey: .changeMeaning)
        directionExplanation = try values.decodeIfPresent(String.self, forKey: .directionExplanation)
        performanceLevelLabel = try values.decodeIfPresent(String.self, forKey: .performanceLevelLabel)
        comparisonValues = try values.decodeIfPresent([ParentPerformanceComparisonValueDTO].self, forKey: .comparisonValues) ?? []
        comparisonSummary = try values.decodeIfPresent(String.self, forKey: .comparisonSummary)
        methodologyId = try values.decodeIfPresent(String.self, forKey: .methodologyId)
    }
}

struct ParentPerformanceComparisonValueDTO: Decodable, Identifiable {
    let scope: String
    let label: String
    let value: String?
    let numericValue: Double?
    var id: String { scope }
}

struct ParentPerformanceHistoryMetricDTO: Decodable, Identifiable {
    let metricCode: String
    let trendState: String
    let methodologyCompatible: Bool
    let historyBreaks: [ParentPerformanceHistoryBreakDTO]
    let recentComparisonSummary: String?
    let points: [ParentPerformancePointDTO]
    var id: String { metricCode }
}

struct ParentPerformanceHistoryBreakDTO: Decodable, Identifiable {
    let afterCycle: String
    let beforeCycle: String
    let reason: String
    let label: String
    var id: String { "\(afterCycle)-\(beforeCycle)-\(reason)" }
}

struct ParentPerformancePointDTO: Decodable, Identifiable {
    let reportingCycle: String
    let academicYear: String
    let officialStatus: String
    let officialValue: String?
    let numericValue: Double?
    let unit: String
    let officialPerformanceLevel: String?
    let officialColor: String?
    let direction: String
    let methodologyId: String?
    let district: ParentPerformanceComparisonDTO?
    let state: ParentPerformanceComparisonDTO?
    let presentation: ParentPerformancePresentationDTO?
    var id: String { reportingCycle }
}

struct ParentPerformanceComparisonDTO: Decodable {
    let officialValue: String?
    let numericValue: Double?
    let officialStatus: String?
    let unit: String?
}
