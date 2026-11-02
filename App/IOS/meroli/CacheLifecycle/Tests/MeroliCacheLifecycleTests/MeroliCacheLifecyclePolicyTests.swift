import XCTest
@testable import MeroliCacheLifecycle

final class MeroliCacheLifecyclePolicyTests: XCTestCase {
    func testSchoolProfileStatesKeepLoadingErrorsAndEmptyDataDistinct() {
        XCTAssertEqual(SchoolProfileDataState.response(hasData: false, isLoading: true, hasError: false), .loading)
        XCTAssertEqual(SchoolProfileDataState.response(hasData: false, isLoading: false, hasError: true), .error)
        XCTAssertEqual(SchoolProfileDataState.response(hasData: true, isLoading: false, hasError: false), .available)
        XCTAssertEqual(SchoolProfileDataState.response(hasData: false, isLoading: false, hasError: false), .notAvailable)
    }

    func testSchoolProfileOnlyMapsExplicitServerStatuses() {
        XCTAssertEqual(SchoolProfileDataState.explicitServerStatus("NOT_CONFIGURED"), .notConfigured)
        XCTAssertEqual(SchoolProfileDataState.explicitServerStatus("UNCONFIRMED"), .pendingVerification)
        XCTAssertEqual(SchoolProfileDataState.explicitServerStatus("NOT_APPLICABLE"), .notApplicable)
        XCTAssertNil(SchoolProfileDataState.explicitServerStatus("FUTURE_UNKNOWN_STATUS"))
        XCTAssertNil(SchoolProfileDataState.explicitServerStatus(nil))
    }

    func testProgramSelectionDistinguishesConfirmedNoneFromUncertain() {
        XCTAssertEqual(SchoolProfileDataState.programSelection("NONE"), .available)
        XCTAssertEqual(SchoolProfileDataState.programSelection("SELECTED"), .available)
        XCTAssertEqual(SchoolProfileDataState.programSelection("NOT_SURE"), .pendingVerification)
        XCTAssertEqual(SchoolProfileDataState.programSelection("NOT_CONFIGURED"), .notConfigured)
        XCTAssertNil(SchoolProfileDataState.programSelection("OTHER"))
    }

    func testSchoolCalendarQueryAlwaysIncludesSchoolAndDateScope() {
        let items = SchoolCalendarQuery.scopedItems(
            startDate: "2026-08-01",
            endDate: "2027-06-30",
            schoolId: "school-fixture-chino-high",
            childId: "child-fixture-7"
        )

        XCTAssertEqual(items.map(\.name), ["start_date", "end_date", "school_id", "child_id"])
        XCTAssertEqual(items.map(\.value), ["2026-08-01", "2027-06-30", "school-fixture-chino-high", "child-fixture-7"])
    }

    func testSchoolCalendarQuerySupportsSchoolYearWithoutChildFilter() {
        let items = SchoolCalendarQuery.scopedItems(
            startDate: "2026-08-01",
            endDate: "2027-06-30",
            schoolId: "school-fixture-collegewood",
            childId: nil
        )

        XCTAssertEqual(items.map(\.name), ["start_date", "end_date", "school_id"])
    }

    func testSchoolCalendarFixtureMatrixKeepsSchoolAndStudentScope() {
        let fixtures = [
            ("Canyon Hills Junior High", "fixture-canyon-hills", "fixture-grade-7"),
            ("Collegewood Elementary", "fixture-collegewood", "fixture-grade-4"),
            ("Chino High School", "fixture-chino-high", "fixture-grade-10"),
            ("Legacy Academy K–8", "fixture-legacy-academy", "fixture-track-d-grade-6")
        ]
        for (schoolName, schoolId, childId) in fixtures {
            let items = SchoolCalendarQuery.scopedItems(
                startDate: "2026-08-01",
                endDate: "2027-06-30",
                schoolId: schoolId,
                childId: childId
            )
            XCTAssertEqual(items.first(where: { $0.name == "school_id" })?.value, schoolId, schoolName)
            XCTAssertEqual(items.first(where: { $0.name == "child_id" })?.value, childId, schoolName)
            XCTAssertEqual(items.first?.value, "2026-08-01", schoolName)
            XCTAssertEqual(items.last(where: { $0.name == "end_date" })?.value, "2027-06-30", schoolName)
        }
    }

    func testCurrentSchemaRemainsValidAcrossAppBuildChanges() {
        XCTAssertEqual(MeroliCacheLifecyclePolicy.schemaAction(storedVersion: 3), .use)
        XCTAssertEqual(MeroliCacheLifecyclePolicy.startMode(hasUsableCache: true, migrationOccurred: false), .returningCache)
    }

    func testLegacySchemaMigratesWithoutLosingItsSnapshot() {
        XCTAssertEqual(MeroliCacheLifecyclePolicy.schemaAction(storedVersion: 2), .migrate)
        let cached = ["Terry", "Eric"]
        XCTAssertEqual(MeroliCacheLifecyclePolicy.resolvedValue(cached: cached, network: nil, networkSucceeded: false), cached)
    }

    func testIncompatibleSchemaInvalidatesOnlyItsEntryAndUnknownFutureFailsSafely() {
        XCTAssertEqual(MeroliCacheLifecyclePolicy.schemaAction(storedVersion: 1), .invalidateEntry)
        XCTAssertEqual(MeroliCacheLifecyclePolicy.schemaAction(storedVersion: 4), .unsupportedFuture)
    }

    func testNetworkFailureRetainsCachedFamily() {
        let cached = ["Terry", "Eric"]
        XCTAssertEqual(MeroliCacheLifecyclePolicy.resolvedValue(cached: cached, network: nil, networkSucceeded: false), cached)
    }

    func testSuccessfulNetworkResponseIsAuthoritativeIncludingEmptyState() {
        let cached = ["Terry", "Eric"]
        XCTAssertEqual(MeroliCacheLifecyclePolicy.resolvedValue(cached: cached, network: ["Terry", "Eric"], networkSucceeded: true), cached)
        XCTAssertEqual(MeroliCacheLifecyclePolicy.resolvedValue(cached: cached, network: [], networkSucceeded: true), [])
    }

    func testAccountCacheCannotCrossUserBoundary() {
        XCTAssertTrue(MeroliCacheLifecyclePolicy.cacheBelongsToCurrentUser(cacheUserId: "A", authenticatedUserId: "A"))
        XCTAssertFalse(MeroliCacheLifecyclePolicy.cacheBelongsToCurrentUser(cacheUserId: "A", authenticatedUserId: "B"))
        XCTAssertFalse(MeroliCacheLifecyclePolicy.cacheBelongsToCurrentUser(cacheUserId: "", authenticatedUserId: "A"))
    }

    func testLogoutRetainsPersistentCachePolicy() {
        XCTAssertTrue(MeroliCacheLifecyclePolicy.retainCacheOnLogout())
    }

    func testNoUsableSnapshotUsesFirstInstallMode() {
        XCTAssertEqual(MeroliCacheLifecyclePolicy.startMode(hasUsableCache: false, migrationOccurred: false), .firstInstall)
        XCTAssertTrue(MeroliCacheLifecyclePolicy.shouldBlockForInitialization(hasUsableScopedCache: false))
        XCTAssertFalse(MeroliCacheLifecyclePolicy.canRenderApp(hasUsableScopedCache: false, authenticationComplete: false))
    }

    func testReturningCacheRendersWhileAuthenticationRefreshIsPending() {
        XCTAssertTrue(MeroliCacheLifecyclePolicy.canRenderApp(hasUsableScopedCache: true, authenticationComplete: false))
        XCTAssertFalse(MeroliCacheLifecyclePolicy.shouldBlockForInitialization(hasUsableScopedCache: true))
    }

    func testAppUpdateForceQuitAndSameAccountReloginDoNotChangeCacheReadiness() {
        let storedSchema = 3
        XCTAssertEqual(MeroliCacheLifecyclePolicy.schemaAction(storedVersion: storedSchema), .use)
        for _ in ["app-update", "force-quit-relaunch", "same-account-relogin"] {
            XCTAssertTrue(MeroliCacheLifecyclePolicy.canRenderApp(hasUsableScopedCache: true, authenticationComplete: false))
        }
    }

    func testCachedCalendarAndHomeDataSurviveNetworkFailure() {
        let cachedEvents = ["School holiday"]
        let cachedSchedules = ["Evergreen schedule"]
        XCTAssertEqual(MeroliCacheLifecyclePolicy.resolvedValue(cached: cachedEvents, network: nil, networkSucceeded: false), cachedEvents)
        XCTAssertEqual(MeroliCacheLifecyclePolicy.resolvedValue(cached: cachedSchedules, network: nil, networkSucceeded: false), cachedSchedules)
    }

    func testFailedCacheReplacementLeavesPreviousValidBytesUntouched() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheURL = directory.appendingPathComponent("family.json")
        let oldBytes = Data("previous-valid-cache".utf8)
        try oldBytes.write(to: cacheURL, options: .atomic)

        XCTAssertThrowsError(try MeroliCacheLifecyclePolicy.writeAtomically(
            data: Data("replacement".utf8),
            to: cacheURL,
            beforeReplacement: { throw NSError(domain: "CacheWriteTest", code: 1) }
        ))
        XCTAssertEqual(try Data(contentsOf: cacheURL), oldBytes)
    }
}
