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
    let programReconfirmationRequired: Bool
}

struct ParentEventDTO: Decodable, Identifiable {
    let id: String
    let title: String
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
    let scheduleCode: String?
    let variantCode: String?
    let arrivalTime: String?
    let dismissalTime: String?
    let reason: String?
    let eventTitles: [String]
    let periods: [DailySchedulePeriodDTO]?
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
    let programs: [ScheduleProgramDTO]
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
    let attendance: ParentAttendanceDTO?
    let performance: ParentPerformanceDTO?
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
}
