import XCTest
@testable import MeroliCacheLifecycle

final class MeroliCacheLifecyclePolicyTests: XCTestCase {
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
