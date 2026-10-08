import Foundation
import Observation
import CryptoKit
import Security

enum AppPhase: Equatable {
    case restoring
    case restoreUnavailable
    case signedOut
    case signedIn
}

private enum MeroliLanguage {
    static var preferred: String {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "zh-CN" : "en"
    }
}

struct MeroliPresentationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct CachedAuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let email: String
    let language: String
}

private struct CachedAPIResponse: Codable {
    let data: Data?
    var lastCheckedAt: Date
}

private struct ResponseCacheSummary {
    let itemCount: Int
    let byteCount: Int64
}

private final class DailyAPIResponseCache {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func read(key: String, userId: String) -> CachedAPIResponse? {
        guard let url = fileURL(key: key, userId: userId),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CachedAPIResponse.self, from: data)
    }

    func write(_ response: CachedAPIResponse, key: String, userId: String) {
        guard let url = fileURL(key: key, userId: userId),
              let data = try? encoder.encode(response) else { return }
        try? data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }

    func removeAll(userId: String) {
        guard let directory = directoryURL(userId: userId) else { return }
        try? fileManager.removeItem(at: directory)
    }

    func summary(userId: String) -> ResponseCacheSummary {
        guard let directory = directoryURL(userId: userId),
              let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return ResponseCacheSummary(itemCount: 0, byteCount: 0)
        }
        let byteCount = files.reduce(Int64.zero) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
        return ResponseCacheSummary(itemCount: files.count, byteCount: byteCount)
    }

    private func fileURL(key: String, userId: String) -> URL? {
        guard let directory = directoryURL(userId: userId) else { return nil }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(digest(key)).appendingPathExtension("json")
    }

    private func directoryURL(userId: String) -> URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("Meroli/ResponseCache", isDirectory: true)
            .appendingPathComponent(digest(userId), isDirectory: true)
    }

    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
private struct OnboardingSubscribeReceipt: Codable, Equatable {
    let userId: String
    let idempotencyKey: String
    let nickname: String
    let schoolId: String
    let schoolYearId: String?
    let gradeCode: String
    let selectionStatus: String
    let scheduleVariantCode: String
    let programIds: [String]
}

struct EnrollmentRemovalSnapshot: Codable, Equatable, Identifiable {
    let id: String
    let childId: String
    let schoolId: String
    let schoolYearId: String
    let gradeCode: String
    var status: String

    init(_ enrollment: EnrollmentDTO) {
        id = enrollment.id
        childId = enrollment.childId
        schoolId = enrollment.schoolId
        schoolYearId = enrollment.schoolYearId
        gradeCode = enrollment.gradeCode
        status = enrollment.status
    }
}

struct EnrollmentRemovalReceipt: Codable {
    let userId: String
    let childId: String
    let enrollmentId: String
    let childNickname: String
    let schoolName: String
    let rows: [EnrollmentRemovalSnapshot]
}

struct EnrollmentSchoolChangeReceipt: Codable {
    let userId: String
    let childId: String
    let enrollmentId: String
    let sourceSchoolId: String
    let schoolYearId: String
    let oldGradeCode: String
    let targetSchoolId: String
    let targetSchoolYearId: String?
    let targetGradeCode: String
    let knownEnrollmentIds: [String]
    let selectionStatus: String?
    let programIds: [String]?
}

@MainActor
@Observable
final class SessionStore {
    private(set) var phase: AppPhase = .restoring
    private(set) var email = ""
    private(set) var userId = ""
    private(set) var language = MeroliLanguage.preferred
    private(set) var family: FamilyDTO?
    private(set) var children: [ChildDTO] = []
    private(set) var enrollments: [EnrollmentDTO] = []
    private(set) var schoolYearTransitions: [SchoolYearTransitionDTO] = []
    private(set) var transitionPrograms: [ScheduleProgramDTO] = []
    private(set) var hasLoadedTransitionPrograms = false
    private(set) var districts: [DistrictDTO] = []
    private(set) var schoolYears: [SchoolYearDTO] = []
    private(set) var schools: [ParentSchoolDTO] = []
    private(set) var selectedSchoolDetails: [String: ParentSchoolDTO] = [:]
    private(set) var calendarEvents: [ParentEventDTO] = []
    private(set) var homeEvents: [ParentEventDTO] = []
    private(set) var isLoadingHomeEvents = false
    private(set) var homeEventsErrorMessage: String?
    private(set) var dailySchedules: [DailyScheduleDTO] = []
    private(set) var nextInstructionalDay: String?
    private(set) var nextInstructionalDays: [ChildNextInstructionalDayDTO] = []
    private(set) var isLoadingNextInstructionalDay = false
    private(set) var nextInstructionalDayErrorMessage: String?
    private(set) var tomorrowDailySchedules: [DailyScheduleDTO] = []
    private(set) var isLoadingTomorrowSchedules = false
    private(set) var tomorrowSchedulesErrorMessage: String?
    private(set) var scheduleProfile: ScheduleProfileDTO?
    private(set) var schoolOverview: ParentSchoolOverviewDTO?
    private(set) var schoolOverviewErrorMessage: String?
    private(set) var schoolPerformanceHistory: ParentPerformanceHistoryDTO?
    private(set) var isLoadingSchoolPerformanceHistory = false
    private(set) var schoolPerformanceHistoryErrorMessage: String?
    private(set) var isLoadingFamily = false
    private(set) var isLoadingCatalog = false
    private(set) var catalogErrorMessage: String?
    private(set) var isLoadingSchools = false
    private(set) var isLoadingCalendar = false
    private(set) var isLoadingHome = false
    private(set) var homeErrorMessage: String?
    private(set) var isLoadingSchoolOverview = false
    private(set) var isSavingSchoolYearTransition = false
    private(set) var isAuthenticating = false
    private(set) var isAppleLinked = false
    private(set) var pendingPasswordResetToken: String?
    private(set) var pendingSchoolRemoval: EnrollmentRemovalReceipt?
    private(set) var pendingSchoolChange: EnrollmentSchoolChangeReceipt?
    private(set) var isRestoringSession = false
    private(set) var initializationProgress = 0.0
    private(set) var isSavingChild = false
    private(set) var deletingChildId: String?
    var errorMessage: String?

    @ObservationIgnored private let api: APIClient?
    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var rotationTask: Task<Void, Error>?
    @ObservationIgnored private var isRemovingEnrollment = false
    @ObservationIgnored private var familyLoadGeneration = 0
    @ObservationIgnored private var schoolsLoadGeneration = 0
    @ObservationIgnored private var schoolDirectoryByDistrict: [String: [ParentSchoolDTO]] = [:]
    @ObservationIgnored private var loadedSchoolDistrictId: String?
    @ObservationIgnored private var programsLoadGeneration = 0
    @ObservationIgnored private var calendarLoadGeneration = 0
    @ObservationIgnored private var homeEventsLoadGeneration = 0
    @ObservationIgnored private var dailySchedulesLoadGeneration = 0
    @ObservationIgnored private var tomorrowSchedulesLoadGeneration = 0
    @ObservationIgnored private var schoolOverviewLoadGeneration = 0
    @ObservationIgnored private var performanceHistoryLoadGeneration = 0
    @ObservationIgnored private var lastCalendarRequest: (start: Date, end: Date, childId: String?)?
    @ObservationIgnored private var lastHomeEventsRequest: (start: Date, end: Date, childId: String?)?
    @ObservationIgnored private var lastDailyScheduleDate: Date?
    @ObservationIgnored private var lastDailyScheduleChildId: String?
    @ObservationIgnored private var lastNextInstructionalDayRequest: String?
    @ObservationIgnored private var pendingNextInstructionalDayRequest: String?
    @ObservationIgnored private var nextInstructionalDayLoadGeneration = 0
    @ObservationIgnored private var lastTomorrowScheduleDate: Date?
    @ObservationIgnored private var lastTomorrowScheduleChildId: String?
    @ObservationIgnored private var lastSchoolOverviewId: String?
    @ObservationIgnored private var lastPerformanceHistorySchoolId: String?
    @ObservationIgnored private let decoder: JSONDecoder
    @ObservationIgnored private let responseCache = DailyAPIResponseCache()
    @ObservationIgnored private var inFlightReadRequests: [String: Task<Data, Error>] = [:]
    @ObservationIgnored private var isTrackingInitializationProgress = false
    @ObservationIgnored private var completedInitializationSteps = 0
    @ObservationIgnored private let initializationStepCount = 6

    init() {
        api = try? APIClient()
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    var cachedResponseCount: Int { responseCache.summary(userId: userId).itemCount }
    var cachedResponseByteCount: Int64 { responseCache.summary(userId: userId).byteCount }

    func school(for id: String) -> ParentSchoolDTO? {
        selectedSchoolDetails[id] ?? schools.first { $0.id == id }
    }

    func clearCachedRemoteData() {
        guard !userId.isEmpty else { return }
        responseCache.removeAll(userId: userId)
        schoolDirectoryByDistrict.removeAll()
        selectedSchoolDetails.removeAll()
        loadedSchoolDistrictId = nil
    }

    var usesChinese: Bool { language == "zh-CN" }

    func restore() async {
        guard !isRestoringSession else { return }
        isRestoringSession = true
        defer { isRestoringSession = false }
        if let cached = KeychainRefreshToken.readSession() {
            accessToken = cached.accessToken
            userId = cached.userId
            email = cached.email
            language = cached.language
            await refreshCachedLanguagePreference()
            if phase == .signedOut { return }
            await finishSessionRestore()
            if phase == .signedIn { await resumePendingSubscription() }
            return
        }
        guard let refreshToken = KeychainRefreshToken.read() else {
            phase = .signedOut
            return
        }
        do {
            try await rotate(refreshToken: refreshToken)
            try await loadIdentity()
            await finishSessionRestore()
            if phase == .signedIn { await resumePendingSubscription() }
        } catch {
            if requiresReauthentication(error) {
                clearLocalSession()
                phase = .signedOut
            } else {
                phase = .restoreUnavailable
            }
            errorMessage = message(for: error)
        }
    }

    func signIn(email: String, password: String, createAccount: Bool) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            errorMessage = usesChinese ? "请输入邮箱和密码。" : "Enter your email and password."
            return
        }
        errorMessage = nil
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let path = createAccount ? "auth/register" : "auth/login"
            var payload: [String: String] = ["email": normalizedEmail, "password": password]
            if createAccount {
                payload["language"] = usesChinese ? "zh-CN" : "en"
            }
            let data = try await send(path: path, method: "POST", json: payload)
            let response = try decoder.decode(APIEnvelope<AuthPayload>.self, from: data)
            try store(tokens: response.response.tokens)
            try await loadIdentity()
            await finishSessionRestore()
        } catch {
            errorMessage = message(for: error)
        }
    }

    func signInWithApple(identityToken: String, rawNonce: String) async {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }
        do {
            let data = try await send(path: "auth/apple", method: "POST", json: [
                "identity_token": identityToken,
                "raw_nonce": rawNonce,
                "language": usesChinese ? "zh-CN" : "en"
            ])
            let response = try decoder.decode(APIEnvelope<AuthPayload>.self, from: data)
            try store(tokens: response.response.tokens)
            try await loadIdentity()
            await finishSessionRestore()
        } catch {
            if (error as? APIClientError)?.statusCode == 409 {
                errorMessage = usesChinese
                    ? "此 Apple 账号关联了已有 Meroli 邮箱，请先使用原方式登录，再到设置中绑定 Apple。"
                    : "This Apple account uses an existing Meroli email. Sign in with your original method, then link Apple in Settings."
            } else if (error as? APIClientError)?.statusCode == 422 {
                errorMessage = usesChinese ? "Apple 未提供已验证邮箱，请先创建邮箱账户后再绑定 Apple。" : "Apple did not provide a verified email. Create an email account first, then link Apple."
            } else {
                errorMessage = message(for: error)
            }
        }
    }

    func loadAppleBinding() async {
        do {
            let data = try await authorized(path: "auth/apple/binding")
            isAppleLinked = try decoder.decode(APIEnvelope<AppleBindingDTO>.self, from: data).response.linked
        } catch { errorMessage = message(for: error) }
    }

    func bindApple(identityToken: String, rawNonce: String) async {
        do {
            let data = try await authorized(path: "auth/apple/bind", method: "POST", json: [
                "identity_token": identityToken,
                "raw_nonce": rawNonce
            ])
            isAppleLinked = try decoder.decode(APIEnvelope<AppleBindingDTO>.self, from: data).response.linked
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIClientError)?.statusCode == 409
                ? (usesChinese ? "Apple 绑定与现有账户关联冲突，请确认当前登录的 Apple 账号和 Meroli 账户。" : "This Apple binding conflicts with an existing account link. Check the Apple account and Meroli account you're using.")
                : message(for: error)
        }
    }

    func loadFamily(forceRefresh: Bool = false) async {
        guard phase == .signedIn || accessToken != nil else { return }
        familyLoadGeneration += 1
        let generation = familyLoadGeneration
        isLoadingFamily = true
        defer {
            if generation == familyLoadGeneration { isLoadingFamily = false }
        }
        do {
            let familyData = try await authorized(path: "family", forceRefresh: forceRefresh)
            let familyResult = try decoder.decode(APIEnvelope<FamilyDTO>.self, from: familyData).response
            completeInitializationStep()
            let childData = try await authorized(path: "children", forceRefresh: forceRefresh)
            let childrenResult = try decoder.decode(APIEnvelope<[ChildDTO]>.self, from: childData).response
            completeInitializationStep()
            let enrollmentData = try await authorized(path: "enrollments", forceRefresh: forceRefresh)
            let enrollmentsResult = try decoder.decode(APIEnvelope<[EnrollmentDTO]>.self, from: enrollmentData).response
            completeInitializationStep()
            let transitionData = try await authorized(path: "school-year-transition/preview", forceRefresh: forceRefresh)
            let transitionsResult = try decoder.decode(APIEnvelope<[SchoolYearTransitionDTO]>.self, from: transitionData).response
            completeInitializationStep()
            guard generation == familyLoadGeneration, accessToken != nil else { return }
            family = familyResult
            children = childrenResult
            enrollments = enrollmentsResult
            schoolYearTransitions = transitionsResult
            homeErrorMessage = nil
            errorMessage = nil
        } catch {
            guard generation == familyLoadGeneration else { return }
            let failureMessage = message(for: error)
            if (error as? APIClientError)?.statusCode == 401 {
                clearLocalSession()
                phase = .signedOut
            }
            homeErrorMessage = failureMessage
            errorMessage = failureMessage
        }
    }

    @discardableResult
    func loadSchoolCatalog(forceRefresh: Bool = false) async -> Bool {
        isLoadingCatalog = true
        catalogErrorMessage = nil
        defer { isLoadingCatalog = false }
        do {
            async let districtData = send(path: "districts", forceRefresh: forceRefresh)
            async let yearData = send(path: "school-years", forceRefresh: forceRefresh)
            districts = try decoder.decode(APIEnvelope<[DistrictDTO]>.self, from: await districtData).response
            completeInitializationStep()
            schoolYears = try decoder.decode(APIEnvelope<[SchoolYearDTO]>.self, from: await yearData).response
            completeInitializationStep()
            catalogErrorMessage = nil
            return true
        } catch {
            catalogErrorMessage = message(for: error)
            return false
        }
    }

    func loadSchoolDetails(schoolId: String, forceRefresh: Bool = false) async -> ParentSchoolDTO? {
        guard !schoolId.isEmpty else { return nil }
        if !forceRefresh, let cached = selectedSchoolDetails[schoolId] { return cached }
        do {
            let data = try await send(path: "schools/\(schoolId)", forceRefresh: forceRefresh)
            let result = try decoder.decode(APIEnvelope<ParentSchoolDTO>.self, from: data).response
            selectedSchoolDetails[schoolId] = result
            return result
        } catch {
            errorMessage = message(for: error)
            return selectedSchoolDetails[schoolId] ?? schools.first { $0.id == schoolId }
        }
    }

    private func finishSessionRestore() async {
        isTrackingInitializationProgress = true
        completedInitializationSteps = 0
        initializationProgress = 0
        defer { isTrackingInitializationProgress = false }
        phase = .restoring
        await loadFamily()
        guard phase != .signedOut else { return }
        guard homeErrorMessage == nil else {
            errorMessage = homeErrorMessage
            phase = .restoreUnavailable
            return
        }

        let catalogLoaded = await loadSchoolCatalog()
        let hasCurrentEnrollment = enrollments.contains(where: \.isCurrent)
        guard catalogLoaded || !hasCurrentEnrollment else {
            errorMessage = catalogErrorMessage
            phase = .restoreUnavailable
            return
        }
        initializationProgress = 1
        phase = .signedIn
    }

    private func completeInitializationStep() {
        guard isTrackingInitializationProgress else { return }
        completedInitializationSteps = min(completedInitializationSteps + 1, initializationStepCount)
        initializationProgress = Double(completedInitializationSteps) / Double(initializationStepCount)
    }

    func schoolTimezone(for childId: String? = nil) -> TimeZone {
        let enrollment = enrollments.first {
            $0.isCurrent && (childId == nil || $0.childId == childId)
        }
        let identifier = enrollment.flatMap { enrollment in
            districts.first(where: { $0.id == enrollment.districtId })?.timezone
        }
        return TimeZone(identifier: identifier ?? "")
            ?? TimeZone(identifier: "America/Los_Angeles")
            ?? .current
    }

    func loadSchools(districtId: String, keyword: String = "", forceRefresh: Bool = false) async {
        schoolsLoadGeneration += 1
        let generation = schoolsLoadGeneration
        errorMessage = nil
        guard !districtId.isEmpty else {
            schools = []
            loadedSchoolDistrictId = nil
            isLoadingSchools = false
            return
        }
        if loadedSchoolDistrictId != districtId {
            schools = []
            loadedSchoolDistrictId = districtId
        }
        if !forceRefresh, let directory = schoolDirectoryByDistrict[districtId] {
            schools = filterSchools(directory, keyword: keyword)
            isLoadingSchools = false
            return
        }
        isLoadingSchools = true
        defer {
            if generation == schoolsLoadGeneration { isLoadingSchools = false }
        }
        do {
            let data = try await send(path: "districts/\(districtId)/schools", forceRefresh: forceRefresh)
            let directory = try decoder.decode(APIEnvelope<[ParentSchoolDTO]>.self, from: data).response
            guard generation == schoolsLoadGeneration else { return }
            schoolDirectoryByDistrict[districtId] = directory
            schools = filterSchools(directory, keyword: keyword)
        } catch {
            guard generation == schoolsLoadGeneration else { return }
            errorMessage = message(for: error)
        }
    }

    private func filterSchools(_ directory: [ParentSchoolDTO], keyword: String) -> [ParentSchoolDTO] {
        let normalizedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !normalizedKeyword.isEmpty else { return directory }
        return directory.filter { school in
            [school.name, school.city, school.state]
                .joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(normalizedKeyword)
        }
    }

    func loadTransitionPrograms(schoolId: String, schoolYearId: String? = nil) async -> [ScheduleProgramDTO]? {
        programsLoadGeneration += 1
        let generation = programsLoadGeneration
        transitionPrograms = []
        hasLoadedTransitionPrograms = false
        guard !schoolId.isEmpty else { return nil }
        do {
            var query: [URLQueryItem] = []
            if let schoolYearId, !schoolYearId.isEmpty {
                query.append(URLQueryItem(name: "schoolYearId", value: schoolYearId))
            }
            let data = try await send(path: "schools/\(schoolId)/schedule-programs", query: query)
            let result = try decoder.decode(APIEnvelope<[ScheduleProgramDTO]>.self, from: data).response
            guard generation == programsLoadGeneration else { return nil }
            transitionPrograms = result
            hasLoadedTransitionPrograms = true
            return result
        } catch {
            guard generation == programsLoadGeneration else { return nil }
            errorMessage = message(for: error)
            return nil
        }
    }

    func loadCalendar(from startDate: Date, to endDate: Date, childId: String? = nil) async {
        guard accessToken != nil else { return }
        lastCalendarRequest = (startDate, endDate, childId)
        calendarLoadGeneration += 1
        let generation = calendarLoadGeneration
        isLoadingCalendar = true
        calendarEvents = []
        errorMessage = nil
        defer {
            if generation == calendarLoadGeneration { isLoadingCalendar = false }
        }
        var query = [
            URLQueryItem(name: "start_date", value: schoolDateString(startDate, childId: childId)),
            URLQueryItem(name: "end_date", value: schoolDateString(endDate, childId: childId))
        ]
        if let childId { query.append(URLQueryItem(name: "child_id", value: childId)) }
        do {
            let data = try await authorized(path: "calendar", query: query, forceRefresh: true)
            let result = try decoder.decode(APIEnvelope<[ParentEventDTO]>.self, from: data).response
            guard generation == calendarLoadGeneration, accessToken != nil else { return }
            calendarEvents = result
            errorMessage = nil
        } catch {
            guard generation == calendarLoadGeneration else { return }
            errorMessage = message(for: error)
        }
    }

    func loadCalendarEvent(id: String, isPersonal: Bool = false) async -> Result<ParentEventDTO, MeroliPresentationError> {
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else {
            return .failure(MeroliPresentationError(message: usesChinese ? "活动编号无效。" : "This event ID is invalid."))
        }
        do {
            let path = "\(isPersonal ? "personal-events" : "events")/\(id)"
            let data = try await authorized(path: path)
            let event = try decoder.decode(APIEnvelope<ParentEventDTO>.self, from: data).response
            return .success(event)
        } catch let error as APIClientError where error.statusCode == 404 {
            return .failure(MeroliPresentationError(message: usesChinese ? "此活动已不再适用于你的家庭。" : "This event is no longer available to your family."))
        } catch {
            return .failure(MeroliPresentationError(message: message(for: error)))
        }
    }

    func savePersonalEvent(id: String? = nil, payload: [String: Any]) async -> Bool {
        do {
            let path = id.map { "personal-events/\($0)" } ?? "personal-events"
            let data = try await authorized(path: path, method: id == nil ? "POST" : "PATCH", json: payload)
            _ = try decoder.decode(APIEnvelope<ParentEventDTO>.self, from: data).response
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func deletePersonalEvent(id: String) async -> Bool {
        do {
            _ = try await authorized(path: "personal-events/\(id)", method: "DELETE")
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func loadHomeEvents(from startDate: Date, to endDate: Date, childId: String? = nil) async {
        guard accessToken != nil else { return }
        lastHomeEventsRequest = (startDate, endDate, childId)
        homeEventsLoadGeneration += 1
        let generation = homeEventsLoadGeneration
        isLoadingHomeEvents = true
        defer {
            if generation == homeEventsLoadGeneration { isLoadingHomeEvents = false }
        }
        var query = [
            URLQueryItem(name: "start_date", value: schoolDateString(startDate, childId: childId)),
            URLQueryItem(name: "end_date", value: schoolDateString(endDate, childId: childId))
        ]
        if let childId { query.append(URLQueryItem(name: "child_id", value: childId)) }
        do {
            let data = try await authorized(path: "calendar", query: query, forceRefresh: true)
            let result = try decoder.decode(APIEnvelope<[ParentEventDTO]>.self, from: data).response
            guard generation == homeEventsLoadGeneration, accessToken != nil else { return }
            homeEvents = result
            homeEventsErrorMessage = nil
        } catch {
            guard generation == homeEventsLoadGeneration else { return }
            homeEventsErrorMessage = message(for: error)
        }
    }

    func loadDailySchedules(for date: Date, childId: String? = nil) async {
        guard api != nil, accessToken != nil else { return }
        lastDailyScheduleDate = date
        lastDailyScheduleChildId = childId
        dailySchedulesLoadGeneration += 1
        let generation = dailySchedulesLoadGeneration
        isLoadingHome = true
        defer {
            if generation == dailySchedulesLoadGeneration { isLoadingHome = false }
        }
        do {
            let value = schoolDateString(date, childId: childId)
            var query = [URLQueryItem(name: "date", value: value)]
            if let childId { query.append(URLQueryItem(name: "child_id", value: childId)) }
            let data = try await authorized(path: "daily-schedules", query: query)
            let items = try decoder.decode(APIEnvelope<[DailyScheduleDTO]>.self, from: data).response
            guard generation == dailySchedulesLoadGeneration, accessToken != nil else { return }
            dailySchedules = items
            homeErrorMessage = nil
            errorMessage = nil
        } catch {
            guard generation == dailySchedulesLoadGeneration else { return }
            homeErrorMessage = message(for: error)
            errorMessage = message(for: error)
        }
    }

    func loadNextInstructionalDay(after date: Date, childId: String? = nil) async {
        guard api != nil, accessToken != nil else { return }
        let value = schoolDateString(date, childId: childId)
        let requestKey = "\(value)|\(childId ?? "")"
        guard lastNextInstructionalDayRequest != requestKey, pendingNextInstructionalDayRequest != requestKey else { return }
        nextInstructionalDayLoadGeneration += 1
        let generation = nextInstructionalDayLoadGeneration
        pendingNextInstructionalDayRequest = requestKey
        nextInstructionalDay = nil
        nextInstructionalDays = []
        isLoadingNextInstructionalDay = true
        nextInstructionalDayErrorMessage = nil
        defer {
            if generation == nextInstructionalDayLoadGeneration {
                pendingNextInstructionalDayRequest = nil
                isLoadingNextInstructionalDay = false
            }
        }
        var query = [URLQueryItem(name: "date", value: value)]
        if let childId { query.append(URLQueryItem(name: "child_id", value: childId)) }
        do {
            let data = try await authorized(path: "next-instructional-day", query: query)
            let result = try decoder.decode(APIEnvelope<NextInstructionalDayDTO>.self, from: data).response
            guard generation == nextInstructionalDayLoadGeneration, accessToken != nil else { return }
            nextInstructionalDay = result.date
            nextInstructionalDays = result.children ?? []
            lastNextInstructionalDayRequest = requestKey
        } catch {
            if generation == nextInstructionalDayLoadGeneration {
                nextInstructionalDayErrorMessage = message(for: error)
            }
        }
    }

    func loadTomorrowDailySchedules(for date: Date, childId: String? = nil) async {
        guard api != nil, accessToken != nil else { return }
        lastTomorrowScheduleDate = date
        lastTomorrowScheduleChildId = childId
        tomorrowSchedulesLoadGeneration += 1
        let generation = tomorrowSchedulesLoadGeneration
        isLoadingTomorrowSchedules = true
        defer {
            if generation == tomorrowSchedulesLoadGeneration { isLoadingTomorrowSchedules = false }
        }
        do {
            let value = schoolDateString(date, childId: childId)
            var query = [URLQueryItem(name: "date", value: value)]
            if let childId { query.append(URLQueryItem(name: "child_id", value: childId)) }
            let data = try await authorized(path: "daily-schedules", query: query)
            let items = try decoder.decode(APIEnvelope<[DailyScheduleDTO]>.self, from: data).response
            guard generation == tomorrowSchedulesLoadGeneration, accessToken != nil else { return }
            tomorrowDailySchedules = items
            tomorrowSchedulesErrorMessage = nil
        } catch {
            guard generation == tomorrowSchedulesLoadGeneration else { return }
            tomorrowSchedulesErrorMessage = message(for: error)
        }
    }

    func loadScheduleProfile(child: ChildDTO, schoolId: String) async {
        scheduleProfile = nil
        do {
            let data = try await authorized(path: "children/\(child.id)/schedule-profile",
                query: [URLQueryItem(name: "school_id", value: schoolId)])
            scheduleProfile = try decoder.decode(APIEnvelope<ScheduleProfileDTO>.self, from: data).response
        } catch {
            errorMessage = message(for: error)
        }
    }

    func loadSchoolOverview(schoolId: String) async {
        lastSchoolOverviewId = schoolId
        schoolOverviewLoadGeneration += 1
        let generation = schoolOverviewLoadGeneration
        schoolOverview = nil
        schoolOverviewErrorMessage = nil
        errorMessage = nil
        isLoadingSchoolOverview = true
        defer {
            if generation == schoolOverviewLoadGeneration {
                isLoadingSchoolOverview = false
            }
        }
        do {
            let data = try await authorized(path: "schools/\(schoolId)/overview")
            let overview = try decoder.decode(APIEnvelope<ParentSchoolOverviewDTO>.self, from: data).response
            guard overview.schoolId == schoolId else { throw APIClientError.invalidResponse }
            guard generation == schoolOverviewLoadGeneration, accessToken != nil else { return }
            schoolOverview = overview
            schoolOverviewErrorMessage = nil
            errorMessage = nil
        } catch {
            guard generation == schoolOverviewLoadGeneration else { return }
            schoolOverviewErrorMessage = message(for: error)
            errorMessage = message(for: error)
        }
    }

    func loadSchoolPerformanceHistory(schoolId: String) async {
        lastPerformanceHistorySchoolId = schoolId
        performanceHistoryLoadGeneration += 1
        let generation = performanceHistoryLoadGeneration
        schoolPerformanceHistory = nil
        schoolPerformanceHistoryErrorMessage = nil
        isLoadingSchoolPerformanceHistory = true
        defer {
            if generation == performanceHistoryLoadGeneration {
                isLoadingSchoolPerformanceHistory = false
            }
        }
        do {
            let data = try await authorized(path: "schools/\(schoolId)/performance/history")
            let history = try decoder.decode(APIEnvelope<ParentPerformanceHistoryDTO>.self, from: data).response
            guard history.schoolId == schoolId else { throw APIClientError.invalidResponse }
            guard generation == performanceHistoryLoadGeneration, accessToken != nil else { return }
            schoolPerformanceHistory = history
        } catch {
            guard generation == performanceHistoryLoadGeneration else { return }
            schoolPerformanceHistory = nil
            schoolPerformanceHistoryErrorMessage = message(for: error)
        }
    }

    func applySchoolYearTransition(childId: String, action: String, targetYearId: String? = nil, grade: Int? = nil, extraPayload: [String: Any] = [:]) async -> Bool {
        isSavingSchoolYearTransition = true
        defer { isSavingSchoolYearTransition = false }
        var payload: [String: Any] = [:]
        if let targetYearId { payload["target_school_year_id"] = targetYearId }
        if let grade { payload["target_grade"] = grade }
        payload.merge(extraPayload) { _, new in new }
        do {
            _ = try await authorized(path: "school-year-transition/\(childId)/\(action)",
                method: "POST", json: payload.isEmpty ? nil : payload)
            await loadFamily()
            errorMessage = nil
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func saveScheduleProfile(child: ChildDTO, selectionStatus: String, variantCode: String, programIds: [String]) async -> Bool {
        do {
            let data = try await authorized(path: "children/\(child.id)/schedule-profile", method: "PUT", json: [
                "school_id": scheduleProfile?.schoolId ?? "",
                "schedule_variant_code": variantCode,
                "selection_status": selectionStatus,
                "program_ids": selectionStatus == "SELECTED" ? programIds : []
            ])
            scheduleProfile = try decoder.decode(APIEnvelope<ScheduleProfileDTO>.self, from: data).response
            errorMessage = nil
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func saveEnrollment(
        child: ChildDTO,
        current: EnrollmentDTO?,
        school: ParentSchoolDTO,
        schoolYear: SchoolYearDTO,
        gradeCode: String,
        selectionStatus: String = "NOT_SURE",
        programIds: [String] = []
    ) async -> Bool {
        guard let grade = gradeNumber(for: gradeCode) else {
            errorMessage = usesChinese ? "请选择有效年级。" : "Choose a valid grade."
            return false
        }
        isSavingChild = true
        errorMessage = nil
        defer { isSavingChild = false }
        if hasPendingSchoolRemoval(childId: child.id) {
            errorMessage = usesChinese
                ? "此孩子的学校关联操作尚待确认，请先检查状态。"
                : "A school enrollment operation for this child is unconfirmed. Check its status first."
            return false
        }
        if hasPendingSchoolChange(childId: child.id) {
            if let receipt = KeychainRefreshToken.readSchoolChangeReceipt(key: schoolChangeKey(childId: child.id)) {
                pendingSchoolChange = receipt
                _ = await reconcileSchoolChange(childId: child.id)
            }
            if pendingSchoolChange != nil || KeychainRefreshToken.receiptExists(key: schoolChangeKey(childId: child.id)) {
                errorMessage = usesChinese
                    ? "换校操作尚待确认，已禁止重复保存。请先检查状态。"
                    : "The school change is unconfirmed. Saving is blocked; check its status first."
                return false
            }
        }
        do {
            let data: Data
            if let current {
                if current.schoolId == school.id {
                    data = try await authorized(path: "enrollments/\(current.id)", method: "PATCH", json: ["grade": grade])
                } else {
                    let key = schoolChangeKey(childId: child.id)
                    if KeychainRefreshToken.receiptExists(key: key) {
                        guard let pending = KeychainRefreshToken.readSchoolChangeReceipt(key: key) else {
                            errorMessage = usesChinese ? "换校回执无法读取，请勿重复提交。" : "The saved school-change receipt cannot be read. Do not submit again."
                            return false
                        }
                        pendingSchoolChange = pending
                        _ = await reconcileSchoolChange(childId: child.id)
                        errorMessage = usesChinese
                            ? "上次换校操作尚待核实，请先检查状态。"
                            : "A previous school change is still unconfirmed. Check its status first."
                        return false
                    }
                    let fresh = try await fetchEnrollments()
                    guard let source = fresh.first(where: {
                        $0.id == current.id && $0.childId == child.id && $0.schoolId == current.schoolId
                    }), source.isCurrent, source.schoolYearId == current.schoolYearId else {
                        throw APIClientError.unacceptableStatusCode(409)
                    }
                    let receipt = EnrollmentSchoolChangeReceipt(
                        userId: userId,
                        childId: child.id,
                        enrollmentId: source.id,
                        sourceSchoolId: source.schoolId,
                        schoolYearId: source.schoolYearId,
                        oldGradeCode: source.gradeCode,
                        targetSchoolId: school.id,
                        targetSchoolYearId: schoolYear.id,
                        targetGradeCode: gradeCode,
                        knownEnrollmentIds: fresh.filter { $0.childId == child.id }.map(\.id).sorted(),
                        selectionStatus: selectionStatus,
                        programIds: selectionStatus == "SELECTED" ? programIds.sorted() : []
                    )
                    guard KeychainRefreshToken.saveSchoolChangeReceipt(receipt, key: key) else {
                        throw APIClientError.secureStorageUnavailable
                    }
                    pendingSchoolChange = receipt
                    do {
                        _ = try await authorized(path: "enrollments/\(current.id)/school-settings", method: "PUT", json: [
                            "school_id": school.id,
                            "school_year_id": schoolYear.id,
                            "grade": grade,
                            "selection_status": selectionStatus,
                            "program_ids": selectionStatus == "SELECTED" ? programIds.sorted() : []
                        ])
                    } catch let error as APIClientError where [401, 403, 404, 422].contains(error.statusCode ?? 0) {
                        _ = KeychainRefreshToken.deleteReceipt(key: key)
                        pendingSchoolChange = nil
                        throw error
                    } catch {
                        _ = await reconcileSchoolChange(childId: child.id)
                        return pendingSchoolChange == nil
                    }
                    _ = await reconcileSchoolChange(childId: child.id)
                    return pendingSchoolChange == nil
                }
            } else {
                data = try await authorized(path: "enrollments", method: "POST", json: [
                    "child_id": child.id,
                    "school_id": school.id,
                    "school_year_id": schoolYear.id,
                    "grade": grade,
                    "selection_status": selectionStatus,
                    "program_ids": selectionStatus == "SELECTED" ? programIds.sorted() : []
                ])
            }
            let enrollment = try decoder.decode(APIEnvelope<EnrollmentDTO>.self, from: data).response
            if let index = enrollments.firstIndex(where: { $0.id == enrollment.id }) {
                enrollments[index] = enrollment
            } else {
                enrollments.append(enrollment)
            }
            if let old = current, old.id != enrollment.id,
               let index = enrollments.firstIndex(where: { $0.id == old.id }) {
                enrollments[index] = EnrollmentDTO(
                    id: old.id, childId: old.childId, childName: old.childName,
                    schoolId: old.schoolId, districtId: old.districtId, schoolName: old.schoolName,
                    schoolYearId: old.schoolYearId, schoolYearName: old.schoolYearName,
                    grade: old.grade, gradeCode: old.gradeCode, status: "COMPLETED",
                    startedAt: old.startedAt, endedAt: enrollment.startedAt
                )
            }
            await loadDailySchedules(for: Date())
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func subscribeChild(
        nickname: String,
        school: ParentSchoolDTO,
        schoolYear: SchoolYearDTO,
        gradeCode: String,
        selectionStatus: String,
        programIds: [String]
    ) async -> Bool {
        guard gradeNumber(for: gradeCode) != nil else {
            errorMessage = usesChinese ? "请选择有效年级。" : "Choose a valid grade."
            return false
        }
        let normalizedName = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              selectionStatus == "SELECTED" && !programIds.isEmpty
                || selectionStatus != "SELECTED" && programIds.isEmpty else {
            errorMessage = usesChinese ? "请填写称呼并完成作息项目选择。" : "Enter a name and complete the schedule choice."
            return false
        }
        let key = onboardingKey()
        let receipt: OnboardingSubscribeReceipt
        if KeychainRefreshToken.receiptExists(key: key) {
            guard let saved = KeychainRefreshToken.readOnboardingReceipt(key: key),
                  saved.userId == userId,
                  saved.nickname == normalizedName,
                  saved.schoolId == school.id,
                  (saved.schoolYearId == nil || saved.schoolYearId == schoolYear.id),
                  saved.gradeCode == gradeCode,
                  saved.selectionStatus == selectionStatus,
                  saved.programIds == programIds.sorted() else {
                errorMessage = usesChinese
                    ? "上次建档提交尚待核实。请使用相同资料重试，或稍后重新打开应用。"
                    : "A previous setup is unresolved. Retry with the same details or reopen the app later."
                return false
            }
            receipt = saved
        } else {
            receipt = OnboardingSubscribeReceipt(
                userId: userId,
                idempotencyKey: UUID().uuidString.lowercased(),
                nickname: normalizedName,
                schoolId: school.id,
                schoolYearId: schoolYear.id,
                gradeCode: gradeCode,
                selectionStatus: selectionStatus,
                scheduleVariantCode: "DEFAULT",
                programIds: programIds.sorted()
            )
            guard KeychainRefreshToken.saveOnboardingReceipt(receipt, key: key) else {
                errorMessage = APIClientError.secureStorageUnavailable.localizedDescription
                return false
            }
        }
        return await dispatchSubscription(receipt)
    }

    private func resumePendingSubscription() async {
        let key = onboardingKey()
        guard KeychainRefreshToken.receiptExists(key: key),
              let receipt = KeychainRefreshToken.readOnboardingReceipt(key: key),
              receipt.userId == userId else { return }
        _ = await dispatchSubscription(receipt)
    }

    private func dispatchSubscription(_ receipt: OnboardingSubscribeReceipt) async -> Bool {
        guard let grade = gradeNumber(for: receipt.gradeCode) else { return false }
        isSavingChild = true
        errorMessage = nil
        defer { isSavingChild = false }
        do {
            guard let accessToken else { throw APIClientError.unacceptableStatusCode(401) }
            var request: [String: Any] = [
                "nickname": receipt.nickname,
                "school_id": receipt.schoolId,
                "grade": grade,
                "selection_status": receipt.selectionStatus,
                "schedule_variant_code": receipt.scheduleVariantCode,
                "program_ids": receipt.programIds
            ]
            if let schoolYearId = receipt.schoolYearId {
                request["school_year_id"] = schoolYearId
            }
            let data = try await send(
                path: "onboarding/subscribe",
                method: "POST",
                authorization: accessToken,
                json: request,
                headers: ["Idempotency-Key": receipt.idempotencyKey]
            )
            _ = try decoder.decode(APIEnvelope<OnboardingSubscribeDTO>.self, from: data).response
            guard KeychainRefreshToken.deleteReceipt(key: onboardingKey()) else {
                throw APIClientError.secureStorageUnavailable
            }
            await loadFamily()
            await loadDailySchedules(for: Date())
            errorMessage = nil
            return true
        } catch let error as APIClientError where error.statusCode == 422 {
            _ = KeychainRefreshToken.deleteReceipt(key: onboardingKey())
            errorMessage = message(for: error)
            return false
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func closeEnrollment(enrollmentId: String, action: String) async -> Bool {
        if action == "remove" {
            return await removeEnrollmentOnce(enrollmentId: enrollmentId)
        }
        isSavingChild = true
        defer { isSavingChild = false }
        do {
            _ = try await authorized(path: "enrollments/\(enrollmentId)/\(action)", method: "POST")
            await loadFamily()
            await loadDailySchedules(for: Date())
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func restorePendingSchoolRemoval(childId: String) async {
        guard !userId.isEmpty else { return }
        let key = schoolRemovalKey(childId: childId)
        guard let receipt = KeychainRefreshToken.readReceipt(key: key),
              receipt.userId == userId,
              receipt.childId == childId else {
            pendingSchoolRemoval = nil
            return
        }
        pendingSchoolRemoval = receipt
        _ = await reconcileSchoolRemoval(childId: childId)
    }

    func restorePendingSchoolChange(childId: String) async {
        guard !userId.isEmpty else { return }
        let key = schoolChangeKey(childId: childId)
        guard KeychainRefreshToken.receiptExists(key: key) else {
            pendingSchoolChange = nil
            return
        }
        guard let receipt = KeychainRefreshToken.readSchoolChangeReceipt(key: key),
              receipt.userId == userId, receipt.childId == childId else {
            errorMessage = usesChinese ? "换校回执无法读取，请勿重复提交。" : "The saved school-change receipt cannot be read. Do not submit again."
            return
        }
        pendingSchoolChange = receipt
        _ = await reconcileSchoolChange(childId: childId)
    }

    func checkPendingSchoolChange(childId: String) async -> Bool {
        await reconcileSchoolChange(childId: childId)
    }

    func hasPendingSchoolChange(childId: String) -> Bool {
        pendingSchoolChange?.childId == childId
            || KeychainRefreshToken.receiptExists(key: schoolChangeKey(childId: childId))
    }

    func checkPendingSchoolRemoval(childId: String) async -> Bool {
        await reconcileSchoolRemoval(childId: childId)
    }

    func hasPendingSchoolRemoval(childId: String) -> Bool {
        pendingSchoolRemoval?.childId == childId
            || KeychainRefreshToken.receiptExists(key: schoolRemovalKey(childId: childId))
    }

    private func removeEnrollmentOnce(enrollmentId: String) async -> Bool {
        guard !isRemovingEnrollment else { return false }
        isRemovingEnrollment = true
        defer { isRemovingEnrollment = false }
        isSavingChild = true
        errorMessage = nil
        defer { isSavingChild = false }
        do {
            guard let target = enrollments.first(where: { $0.id == enrollmentId }) else {
                throw APIClientError.unacceptableStatusCode(404)
            }
            let key = schoolRemovalKey(childId: target.childId)
            guard !hasPendingSchoolChange(childId: target.childId) else {
                errorMessage = usesChinese
                    ? "孩子有一项换校操作尚待确认，请先检查换校状态。"
                    : "A school change for this child is unconfirmed. Check its status first."
                return false
            }
            if KeychainRefreshToken.receiptExists(key: key) {
                guard let existing = KeychainRefreshToken.readReceipt(key: key) else {
                    errorMessage = usesChinese ? "移除回执无法读取，请勿重复提交。" : "The saved removal receipt cannot be read. Do not submit again."
                    return false
                }
                pendingSchoolRemoval = existing
                _ = await reconcileSchoolRemoval(childId: target.childId)
                if pendingSchoolRemoval != nil { return false }
                errorMessage = usesChinese ? "已核实关联状态，请重新打开学校资料后查看。" : "The enrollment status was checked. Reopen the school details to review it."
                return false
            }

            let actual = try await fetchEnrollments()
            guard let current = actual.first(where: {
                $0.id == enrollmentId && $0.childId == target.childId && $0.schoolId == target.schoolId
            }), current.isCurrent else {
                throw APIClientError.unacceptableStatusCode(409)
            }
            let child = try await fetchChild(id: target.childId)
            let receipt = EnrollmentRemovalReceipt(
                userId: userId,
                childId: child.id,
                enrollmentId: enrollmentId,
                childNickname: child.nickname,
                schoolName: current.schoolName,
                rows: actual.filter { $0.childId == child.id }
                    .map(EnrollmentRemovalSnapshot.init)
                    .sorted { $0.id < $1.id }
            )
            guard KeychainRefreshToken.saveReceipt(receipt, key: key) else {
                throw APIClientError.secureStorageUnavailable
            }
            pendingSchoolRemoval = receipt

            do {
                _ = try await authorized(path: "enrollments/\(enrollmentId)/remove", method: "POST")
            } catch let error as APIClientError where [401, 403, 404, 422].contains(error.statusCode ?? 0) {
                _ = KeychainRefreshToken.deleteReceipt(key: key)
                pendingSchoolRemoval = nil
                throw error
            } catch {
                errorMessage = message(for: error)
                return await reconcileSchoolRemoval(childId: child.id)
            }
            return await reconcileSchoolRemoval(childId: child.id)
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    private func reconcileSchoolRemoval(childId: String) async -> Bool {
        guard let receipt = pendingSchoolRemoval ?? KeychainRefreshToken.readReceipt(key: schoolRemovalKey(childId: childId)),
              receipt.userId == userId, receipt.childId == childId else { return false }
        do {
            let child = try await fetchChild(id: childId)
            guard child.id == childId else {
                errorMessage = usesChinese ? "暂时无法确认孩子的学校记录状态，请稍后重试。" : "The school record status could not be confirmed. Try again shortly."
                return false
            }
            let current = try await fetchEnrollments().filter { $0.childId == childId }
                .map(EnrollmentRemovalSnapshot.init).sorted { $0.id < $1.id }
            let expected = receipt.rows.map { row -> EnrollmentRemovalSnapshot in
                var updated = row
                if row.id == receipt.enrollmentId { updated.status = "REMOVED" }
                return updated
            }.sorted { $0.id < $1.id }
            guard current == expected else {
                pendingSchoolRemoval = receipt
                errorMessage = usesChinese
                    ? "移除结果仍待确认。为避免重复操作，请只检查状态，不要再次移除。"
                    : "Removal is still unconfirmed. Check the status; do not submit the removal again."
                return false
            }
            _ = KeychainRefreshToken.deleteReceipt(key: schoolRemovalKey(childId: childId))
            pendingSchoolRemoval = nil
            errorMessage = nil
            await loadFamily()
            await loadDailySchedules(for: Date())
            return true
        } catch {
            pendingSchoolRemoval = receipt
            errorMessage = usesChinese
                ? "暂时无法确认移除结果。请稍后检查状态，不要重复提交。"
                : "The removal result could not be checked. Try a read-only status check later; do not submit again."
            return false
        }
    }

    private func fetchEnrollments() async throws -> [EnrollmentDTO] {
        let data = try await authorized(path: "enrollments")
        return try decoder.decode(APIEnvelope<[EnrollmentDTO]>.self, from: data).response
    }

    private func fetchChild(id: String) async throws -> ChildDTO {
        let data = try await authorized(path: "children/\(id)")
        return try decoder.decode(APIEnvelope<ChildDTO>.self, from: data).response
    }

    private func fetchScheduleProfile(childId: String, schoolId: String) async throws -> ScheduleProfileDTO {
        let data = try await authorized(
            path: "children/\(childId)/schedule-profile",
            query: [URLQueryItem(name: "school_id", value: schoolId)]
        )
        return try decoder.decode(APIEnvelope<ScheduleProfileDTO>.self, from: data).response
    }

    private func reconcileSchoolChange(childId: String) async -> Bool {
        guard let receipt = pendingSchoolChange ?? KeychainRefreshToken.readSchoolChangeReceipt(key: schoolChangeKey(childId: childId)),
              receipt.userId == userId, receipt.childId == childId else { return false }
        do {
            let child = try await fetchChild(id: childId)
            let rows = try await fetchEnrollments().filter { $0.childId == childId }
            let prior = rows.first { $0.id == receipt.enrollmentId }
            let additions = rows.filter { !receipt.knownEnrollmentIds.contains($0.id) }
            let activeTargets = rows.filter { $0.schoolId == receipt.targetSchoolId && $0.isCurrent }
            guard child.id == childId,
                  let prior,
                  prior.status == "COMPLETED",
                  prior.schoolId == receipt.sourceSchoolId,
                  prior.schoolYearId == receipt.schoolYearId,
                  prior.gradeCode == receipt.oldGradeCode,
                  additions.count == 1,
                  let next = additions.first,
                  next.status == "ACTIVE",
                  next.schoolId == receipt.targetSchoolId,
                  next.schoolYearId == (receipt.targetSchoolYearId ?? receipt.schoolYearId),
                  next.gradeCode == receipt.targetGradeCode,
                  activeTargets.filter({ $0.status == "ACTIVE" }).count == 1 else {
                pendingSchoolChange = receipt
                errorMessage = usesChinese
                    ? "换校结果尚未核实。请只检查状态，不要重复提交。"
                    : "The school change is unconfirmed. Check its status; do not submit it again."
                return false
            }
            if let expectedStatus = receipt.selectionStatus {
                let profile = try await fetchScheduleProfile(childId: childId, schoolId: receipt.targetSchoolId)
                let expectedPrograms = (receipt.programIds ?? []).sorted()
                guard profile.selectionStatus == expectedStatus,
                      profile.programIds.sorted() == expectedPrograms else {
                    pendingSchoolChange = receipt
                    errorMessage = usesChinese
                        ? "新学校的作息项目尚未确认完成，请只检查状态，不要重复换校。"
                        : "The new school's schedule choices are not confirmed. Check status; do not repeat the school change."
                    return false
                }
            }
            _ = KeychainRefreshToken.deleteReceipt(key: schoolChangeKey(childId: childId))
            pendingSchoolChange = nil
            errorMessage = nil
            await loadFamily()
            await loadDailySchedules(for: Date())
            return true
        } catch {
            pendingSchoolChange = receipt
            errorMessage = usesChinese
                ? "暂时无法确认换校结果。请稍后检查状态，不要重复提交。"
                : "The school change could not be verified. Check its status later; do not submit again."
            return false
        }
    }

    private func schoolRemovalKey(childId: String) -> String {
        "school-remove.\(userId).\(childId)"
    }

    private func onboardingKey() -> String {
        "onboarding-subscribe.\(userId)"
    }

    private func schoolChangeKey(childId: String) -> String {
        "school-change.\(userId).\(childId)"
    }

    func createChild(nickname: String) async -> Bool {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = usesChinese ? "请输入孩子的称呼。" : "Enter a name for your child."
            return false
        }
        isSavingChild = true
        errorMessage = nil
        defer { isSavingChild = false }
        do {
            let data = try await authorized(path: "children", method: "POST", json: ["nickname": name])
            let child = try decoder.decode(APIEnvelope<ChildDTO>.self, from: data).response
            children.append(child)
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func renameChild(id: String, nickname: String) async -> Bool {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = usesChinese ? "请输入孩子的称呼。" : "Enter a name for your child."
            return false
        }
        isSavingChild = true
        errorMessage = nil
        defer { isSavingChild = false }
        do {
            let data = try await authorized(path: "children/\(id)", method: "PATCH", json: ["nickname": name])
            let updated = try decoder.decode(APIEnvelope<ChildDTO>.self, from: data).response
            if let index = children.firstIndex(where: { $0.id == id }) { children[index] = updated }
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func deleteChild(id: String) async -> Bool {
        guard deletingChildId == nil else { return false }
        guard children.contains(where: { $0.id == id }) else {
            errorMessage = usesChinese ? "无法找到这位家庭成员，请刷新后重试。" : "This family member could not be found. Refresh and try again."
            return false
        }

        deletingChildId = id
        errorMessage = nil
        defer { deletingChildId = nil }

        do {
            let data = try await authorized(path: "children/\(id)", method: "DELETE")
            let deleted = try decoder.decode(APIEnvelope<Bool>.self, from: data).response
            guard deleted else {
                errorMessage = usesChinese ? "孩子未能从家庭中移除，请稍后重试。" : "The child could not be removed from the family. Try again shortly."
                return false
            }

            scheduleProfile = nil
            transitionPrograms = []
            hasLoadedTransitionPrograms = false
            await loadFamily(forceRefresh: true)
            guard phase == .signedIn, family != nil else { return false }
            guard !children.contains(where: { $0.id == id }) else {
                if errorMessage == nil {
                    errorMessage = usesChinese ? "移除结果已提交，但家庭资料尚未更新。请刷新后确认。" : "The removal was submitted, but family details have not refreshed. Refresh to confirm."
                }
                return false
            }
            return true
        } catch {
            if requiresReauthentication(error) {
                clearLocalSession()
                phase = .signedOut
            }
            errorMessage = message(for: error)
            return false
        }
    }

    func setLanguage(_ value: String) async {
        guard ["en", "zh-CN"].contains(value) else { return }
        errorMessage = nil
        do {
            let data = try await authorized(path: "preferences", method: "PATCH", json: ["language": value])
            let updatedLanguage = try decoder.decode(APIEnvelope<PreferencesDTO>.self, from: data).response.language
            let languageChanged = language != updatedLanguage
            language = updatedLanguage
            persistCachedSession()
            if languageChanged { await reloadLocalizedContent() }
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func reloadLocalizedContent() async {
        if let request = lastCalendarRequest {
            await loadCalendar(from: request.start, to: request.end, childId: request.childId)
        }
        if let request = lastHomeEventsRequest {
            await loadHomeEvents(from: request.start, to: request.end, childId: request.childId)
        }
        if let date = lastDailyScheduleDate {
            await loadDailySchedules(for: date, childId: lastDailyScheduleChildId)
        }
        if let date = lastTomorrowScheduleDate {
            await loadTomorrowDailySchedules(for: date, childId: lastTomorrowScheduleChildId)
        }
        if let schoolId = lastSchoolOverviewId { await loadSchoolOverview(schoolId: schoolId) }
        if let schoolId = lastPerformanceHistorySchoolId {
            await loadSchoolPerformanceHistory(schoolId: schoolId)
        }
    }

    func requestPasswordReset(email: String) async -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else {
            errorMessage = usesChinese ? "请输入邮箱地址。" : "Enter your email address."
            return false
        }
        errorMessage = nil
        do {
            _ = try await send(path: "auth/password-reset/request", method: "POST", json: ["email": normalizedEmail])
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "meroli",
              components.host?.lowercased() == "reset-password",
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              (32...256).contains(token.utf16.count),
              token.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-").contains($0) }) else { return }
        pendingPasswordResetToken = token
        errorMessage = nil
    }

    func dismissPasswordReset() {
        pendingPasswordResetToken = nil
        errorMessage = nil
    }

    func confirmPasswordReset(token: String, newPassword: String) async -> Bool {
        guard (32...256).contains(token.utf16.count),
              (6...256).contains(newPassword.utf16.count) else {
            errorMessage = usesChinese ? "重置链接无效，或新密码长度不符合要求。" : "The reset link is invalid or the new password length is not allowed."
            return false
        }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }
        do {
            _ = try await send(path: "auth/password-reset/confirm", method: "POST", json: [
                "token": token,
                "new_password": newPassword
            ])
            clearLocalSession()
            phase = .signedOut
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func logout() async {
        if let refreshToken = KeychainRefreshToken.read() {
            _ = try? await send(path: "auth/logout", method: "POST", json: ["refresh_token": refreshToken])
        }
        clearLocalSession()
        phase = .signedOut
        errorMessage = nil
    }

    func deleteAccount(password: String = "", identityToken: String? = nil, rawNonce: String? = nil) async -> Bool {
        guard !password.isEmpty || identityToken != nil && rawNonce != nil else {
            errorMessage = usesChinese ? "请使用当前密码或已绑定的 Apple 账号重新验证。" : "Reauthenticate with your password or linked Apple account."
            return false
        }
        isSavingChild = true
        errorMessage = nil
        defer { isSavingChild = false }
        do {
            var payload = ["password": password]
            if let identityToken, let rawNonce {
                payload["identity_token"] = identityToken
                payload["raw_nonce"] = rawNonce
            }
            let data = try await authorized(path: "auth/account", method: "DELETE", json: payload)
            let result = try decoder.decode(APIEnvelope<MeroliAccountDeleteDTO>.self, from: data).response
            guard result.deleted else { throw APIClientError.invalidResponse }
            clearLocalSession()
            phase = .signedOut
            errorMessage = nil
            return true
        } catch let error as APIClientError where error.statusCode == 401 {
            errorMessage = usesChinese
                ? "验证失败。请检查密码，或使用已绑定的 Apple 账号重新验证。"
                : "Verification failed. Check your password or reauthenticate with your linked Apple account."
            return false
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    private func loadIdentity() async throws {
        let profileData = try await authorized(path: "auth/me")
        let user = try decoder.decode(APIEnvelope<MePayload>.self, from: profileData).response.user
        userId = user.id
        email = user.email
        let preferencesData = try await authorized(path: "preferences")
        language = try decoder.decode(APIEnvelope<PreferencesDTO>.self, from: preferencesData).response.language
        persistCachedSession()
    }

    private func refreshCachedLanguagePreference() async {
        do {
            let data = try await authorized(path: "preferences")
            let preference = try decoder.decode(APIEnvelope<PreferencesDTO>.self, from: data).response
            guard ["en", "zh-CN"].contains(preference.language) else { return }
            let languageChanged = language != preference.language
            language = preference.language
            persistCachedSession()
            if languageChanged { await reloadLocalizedContent() }
        } catch {
            if requiresReauthentication(error) {
                clearLocalSession()
                phase = .signedOut
            }
        }
    }

    private func authorized(
        path: String,
        method: String = "GET",
        json: [String: Any]? = nil,
        query: [URLQueryItem] = [],
        forceRefresh: Bool = false
    ) async throws -> Data {
        guard let token = accessToken else { throw APIClientError.unacceptableStatusCode(401) }
        do {
            return try await send(path: path, method: method, authorization: token, json: json, query: query, forceRefresh: forceRefresh)
        } catch let error as APIClientError where error.statusCode == 401 {
            guard method == "GET" else { throw error }
            if let currentToken = accessToken, currentToken != token {
                return try await send(path: path, method: method, authorization: currentToken, json: json, query: query, forceRefresh: forceRefresh)
            }
            guard let refreshToken = KeychainRefreshToken.read() else { throw error }
            try await rotate(refreshToken: refreshToken)
            guard let newToken = accessToken else { throw error }
            do {
                return try await send(path: path, method: method, authorization: newToken, json: json, query: query, forceRefresh: forceRefresh)
            } catch let retryError as APIClientError where retryError.statusCode == 401 {
                clearLocalSession()
                phase = .signedOut
                throw retryError
            }
        }
    }

    private func rotate(refreshToken: String) async throws {
        if let rotationTask {
            try await rotationTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { throw APIClientError.invalidResponse }
            try await self.performRotation(refreshToken: refreshToken)
        }
        rotationTask = task
        defer { rotationTask = nil }
        try await task.value
    }

    private func performRotation(refreshToken: String) async throws {
        let data = try await send(path: "auth/refresh", method: "POST", json: ["refresh_token": refreshToken])
        let response = try decoder.decode(APIEnvelope<RefreshPayload>.self, from: data)
        try store(tokens: response.response.tokens)
    }

    private func store(tokens: AuthTokens) throws {
        guard !tokens.accessToken.isEmpty, !tokens.refreshToken.isEmpty else {
            throw APIClientError.invalidResponse
        }
        guard KeychainRefreshToken.save(tokens.refreshToken) else {
            throw APIClientError.secureStorageUnavailable
        }
        accessToken = tokens.accessToken
        persistCachedSession(refreshToken: tokens.refreshToken)
    }

    private func persistCachedSession(refreshToken: String? = nil) {
        guard !userId.isEmpty, !email.isEmpty,
              let accessToken,
              let storedRefreshToken = refreshToken ?? KeychainRefreshToken.read() else { return }
        let cached = CachedAuthSession(
            accessToken: accessToken,
            refreshToken: storedRefreshToken,
            userId: userId,
            email: email,
            language: language
        )
        _ = KeychainRefreshToken.saveSession(cached)
    }

    private func send(
        path: String,
        method: String = "GET",
        authorization: String? = nil,
        json: [String: Any]? = nil,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        forceRefresh: Bool = false
    ) async throws -> Data {
        guard let api else { throw APIClientError.invalidBaseURL }
        let isCacheableRead = method.uppercased() == "GET" && !userId.isEmpty
        let cacheUserId = isCacheableRead ? userId : nil
        let key = cacheKey(path: path, query: query)
        let inFlightKey = cacheUserId.map { "\($0)|\(key)" } ?? key
        let cached = cacheUserId.flatMap { responseCache.read(key: key, userId: $0) }
        let now = Date()
        if !forceRefresh, let data = cached?.data {
            return data
        }
        if !forceRefresh, let pending = inFlightReadRequests[inFlightKey] {
            return try await pending.value
        }
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        let request = Task {
            try await api.request(path: path, method: method, query: query, authorization: authorization, headers: headers, body: body)
        }
        if isCacheableRead { inFlightReadRequests[inFlightKey] = request }
        do {
            let data = try await request.value
            if isCacheableRead { inFlightReadRequests[inFlightKey] = nil }
            if let cacheUserId, userId == cacheUserId {
                responseCache.write(CachedAPIResponse(data: data, lastCheckedAt: now), key: key, userId: userId)
            } else if method.uppercased() != "GET", !userId.isEmpty {
                responseCache.removeAll(userId: userId)
                schoolDirectoryByDistrict.removeAll()
                selectedSchoolDetails.removeAll()
            }
            return data
        } catch {
            if isCacheableRead { inFlightReadRequests[inFlightKey] = nil }
            if let statusCode = (error as? APIClientError)?.statusCode, statusCode < 500 {
                throw error
            }
            if let cacheUserId, userId == cacheUserId {
                if let cached, let data = cached.data {
                    responseCache.write(CachedAPIResponse(data: data, lastCheckedAt: now), key: key, userId: cacheUserId)
                    return data
                }
            }
            throw error
        }
    }

    private func cacheKey(path: String, query: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.queryItems = query.sorted {
            if $0.name != $1.name { return $0.name < $1.name }
            return ($0.value ?? "") < ($1.value ?? "")
        }
        return path + "?" + (components.percentEncodedQuery ?? "")
    }

    private func clearLocalSession() {
        if !userId.isEmpty { responseCache.removeAll(userId: userId) }
        schoolDirectoryByDistrict.removeAll()
        selectedSchoolDetails.removeAll()
        loadedSchoolDistrictId = nil
        inFlightReadRequests.values.forEach { $0.cancel() }
        inFlightReadRequests.removeAll()
        familyLoadGeneration += 1
        schoolsLoadGeneration += 1
        programsLoadGeneration += 1
        calendarLoadGeneration += 1
        homeEventsLoadGeneration += 1
        dailySchedulesLoadGeneration += 1
        nextInstructionalDayLoadGeneration += 1
        tomorrowSchedulesLoadGeneration += 1
        schoolOverviewLoadGeneration += 1
        performanceHistoryLoadGeneration += 1
        rotationTask?.cancel()
        rotationTask = nil
        lastCalendarRequest = nil
        lastHomeEventsRequest = nil
        lastDailyScheduleDate = nil
        lastDailyScheduleChildId = nil
        lastNextInstructionalDayRequest = nil
        pendingNextInstructionalDayRequest = nil
        lastTomorrowScheduleDate = nil
        lastTomorrowScheduleChildId = nil
        lastSchoolOverviewId = nil
        lastPerformanceHistorySchoolId = nil
        accessToken = nil
        _ = KeychainRefreshToken.delete()
        _ = KeychainRefreshToken.deleteSession()
        email = ""
        userId = ""
        language = MeroliLanguage.preferred
        family = nil
        children = []
        enrollments = []
        schoolYearTransitions = []
        transitionPrograms = []
        hasLoadedTransitionPrograms = false
        districts = []
        schoolYears = []
        catalogErrorMessage = nil
        schools = []
        calendarEvents = []
        homeEvents = []
        homeEventsErrorMessage = nil
        dailySchedules = []
        nextInstructionalDay = nil
        nextInstructionalDays = []
        nextInstructionalDayErrorMessage = nil
        tomorrowDailySchedules = []
        tomorrowSchedulesErrorMessage = nil
        scheduleProfile = nil
        schoolOverview = nil
        schoolOverviewErrorMessage = nil
        schoolPerformanceHistory = nil
        schoolPerformanceHistoryErrorMessage = nil
        pendingSchoolRemoval = nil
        pendingSchoolChange = nil
        isAppleLinked = false
        homeErrorMessage = nil
        isLoadingFamily = false
        isLoadingSchools = false
        isLoadingCalendar = false
        isLoadingHome = false
        isLoadingNextInstructionalDay = false
        isLoadingHomeEvents = false
        isLoadingTomorrowSchedules = false
        isLoadingSchoolOverview = false
        isLoadingSchoolPerformanceHistory = false
    }

    private func requiresReauthentication(_ error: Error) -> Bool {
        guard let apiError = error as? APIClientError else { return false }
        return apiError.statusCode == 401 || apiError.statusCode == 403
    }

    private func message(for error: Error) -> String {
        guard let apiError = error as? APIClientError else {
            return usesChinese ? "网络暂时不可用，请检查连接后重试。" : "The network is unavailable. Check your connection and try again."
        }
        switch apiError {
        case .invalidBaseURL:
            return usesChinese ? "尚未配置 Meroli API 地址。" : "The Meroli API address is not configured."
        case .invalidRequestPath, .invalidResponse:
            return usesChinese ? "暂时无法读取 Meroli 数据，请稍后重试。" : "Meroli data could not be loaded. Try again shortly."
        case .secureStorageUnavailable:
            return usesChinese ? "无法安全保存登录状态，请解锁设备后重试。" : "The secure sign-in state could not be saved. Unlock your device and try again."
        case let .unacceptableStatusCode(status):
            if status == 401 { return usesChinese ? "邮箱或密码不正确，或登录已过期。" : "The email or password is incorrect, or your session expired." }
            if status == 409 { return usesChinese ? "此邮箱已注册，请直接登录。" : "This email is already registered. Sign in instead." }
            if status == 422 { return usesChinese ? "请检查输入的信息。" : "Check the information you entered." }
            return usesChinese ? "Meroli 服务暂时无法完成请求（\(status)）。" : "Meroli could not complete the request (\(status))."
        }
    }

    private func gradeNumber(for code: String) -> Int? {
        switch code {
        case "PK": return -2
        case "TK": return -1
        case "K": return 0
        default: return Int(code).flatMap { (1...12).contains($0) ? $0 : nil }
        }
    }

    private func schoolDateString(_ date: Date, childId: String? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = schoolTimezone(for: childId)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private enum KeychainRefreshToken {
    private static let service = "com.wekarepartners.meroli.app"
    private static let account = "refresh-token"
    private static let sessionAccount = "auth-session-v1"

    static func readSession() -> CachedAuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let session = try? JSONDecoder().decode(CachedAuthSession.self, from: data),
              !session.accessToken.isEmpty, !session.refreshToken.isEmpty,
              !session.userId.isEmpty, !session.email.isEmpty else { return nil }
        return session
    }

    static func saveSession(_ session: CachedAuthSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionAccount
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            insert[kSecValueData as String] = data
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func readReceipt(key: String) -> EnrollmentRemovalReceipt? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(EnrollmentRemovalReceipt.self, from: data)
    }

    static func readOnboardingReceipt(key: String) -> OnboardingSubscribeReceipt? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(OnboardingSubscribeReceipt.self, from: data)
    }

    static func saveOnboardingReceipt(_ receipt: OnboardingSubscribeReceipt, key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(receipt) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            insert[kSecValueData as String] = data
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func receiptExists(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    static func readSchoolChangeReceipt(key: String) -> EnrollmentSchoolChangeReceipt? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(EnrollmentSchoolChangeReceipt.self, from: data)
    }

    static func saveSchoolChangeReceipt(_ receipt: EnrollmentSchoolChangeReceipt, key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(receipt) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            insert[kSecValueData as String] = data
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func saveReceipt(_ receipt: EnrollmentRemovalReceipt, key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(receipt) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            insert[kSecValueData as String] = data
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    @discardableResult
    static func deleteReceipt(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    @discardableResult
    static func deleteSession() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            attributes.forEach { insert[$0.key] = $0.value }
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    @discardableResult
    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
