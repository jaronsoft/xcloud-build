import XCTest
import UIKit
@testable import MOSA

final class MosaV21RulesTests: XCTestCase {
    @MainActor
    func testAuthenticatedImageRefreshesTokenAndRetriesAfterUnauthorized() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticatedImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let sessionStore = MemorySessionStore(
            AuthSession(token: "expired-token", refreshToken: "refresh-token", email: "test@example.com")
        )
        defer {
            AuthenticatedImageURLProtocol.reset()
        }
        AuthenticatedImageURLProtocol.reset()

        let client = APIClient(
            baseURL: URL(string: "https://mosa.test/")!,
            urlSession: session,
            sessionStore: sessionStore,
            developerLogs: DeveloperNetworkLogStore()
        )
        let data = try await client.getShareCardImage(year: 2026) { _ in }

        XCTAssertEqual(data, Data("PNG".utf8))
        XCTAssertEqual(AuthenticatedImageURLProtocol.imageAuthorizationHeaders, ["Bearer expired-token", "Bearer refreshed-token"])
        XCTAssertEqual(AuthenticatedImageURLProtocol.refreshRequestCount, 1)
        XCTAssertEqual(sessionStore.load()?.token, "refreshed-token")
    }

    @MainActor
    func testConcurrentAuthenticatedImagesShareOneTokenRefresh() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticatedImageURLProtocol.self]
        let sessionStore = MemorySessionStore(
            AuthSession(token: "expired-token", refreshToken: "refresh-token", email: "test@example.com")
        )
        AuthenticatedImageURLProtocol.reset()
        defer { AuthenticatedImageURLProtocol.reset() }
        let client = APIClient(
            baseURL: URL(string: "https://mosa.test/")!,
            urlSession: URLSession(configuration: configuration),
            sessionStore: sessionStore,
            developerLogs: DeveloperNetworkLogStore()
        )

        async let first = client.getAnnualArtworkImage(year: 2025) { _ in }
        async let second = client.getShareCardImage(year: 2026) { _ in }
        let values = try await [first, second]

        XCTAssertEqual(values, [Data("PNG".utf8), Data("PNG".utf8)])
        XCTAssertEqual(AuthenticatedImageURLProtocol.refreshRequestCount, 1)
        XCTAssertEqual(AuthenticatedImageURLProtocol.imageAuthorizationHeaders.filter { $0 == "Bearer expired-token" }.count, 2)
        XCTAssertEqual(AuthenticatedImageURLProtocol.imageAuthorizationHeaders.filter { $0 == "Bearer refreshed-token" }.count, 2)
    }

    func testArtworkDownloadProgressUsesPercentOnlyWithKnownContentLength() {
        XCTAssertEqual(
            ArtworkImageDownloadProgress(receivedBytes: 25, expectedBytes: 100).fractionCompleted,
            0.25
        )
        XCTAssertEqual(
            ArtworkImageDownloadProgress(receivedBytes: 140, expectedBytes: 100).fractionCompleted,
            1
        )
        XCTAssertNil(ArtworkImageDownloadProgress(receivedBytes: 25, expectedBytes: nil).fractionCompleted)
        XCTAssertNil(ArtworkImageDownloadProgress(receivedBytes: 25, expectedBytes: 0).fractionCompleted)
    }

    func testArtworkShareFileContainsOnlyProvidedPNGData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MosaArtworkShareTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let image = try XCTUnwrap(UIImage(systemName: "photo"))
        let pngData = try XCTUnwrap(image.pngData())
        let fileURL = try ArtworkImageShareFile.write(pngData: pngData, year: 2026, directory: directory)

        XCTAssertEqual(fileURL.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: fileURL), pngData)
        XCTAssertNotNil(UIImage(data: try Data(contentsOf: fileURL)))
        XCTAssertFalse(fileURL.lastPathComponent.contains("http"))
    }

    func testCanvasResolverSupportsZeroToThreeColorsInOrder() {
        let date = "2024-06-15"
        XCTAssertEqual(CanvasResolver.colors(date: date, record: nil, stages: []), [])
        for count in 1...3 {
            let colors = Array(["#D9948A", "#E2C466", "#7FA7C6"].prefix(count))
            XCTAssertEqual(CanvasResolver.colors(date: date, record: record(date: date, colors: colors), stages: []), colors)
        }
    }

    func testDailyCanvasIgnoresStageBackgroundsUnlessPreviewOptsIn() {
        let stage = lifeStage(start: "2024-01", end: "2024-12", color: "#87B78F")
        let daily = record(date: "2024-06-15", colors: ["#D9948A", "#7FA7C6"])
        XCTAssertEqual(CanvasResolver.colors(date: daily.recordDate, record: daily, stages: [stage]), ["#D9948A", "#7FA7C6"])
        XCTAssertEqual(CanvasResolver.colors(date: daily.recordDate, record: nil, stages: [stage]), [])
        XCTAssertEqual(CanvasResolver.resolve(date: daily.recordDate, record: daily, stages: [stage]).source, .daily)
        XCTAssertEqual(CanvasResolver.resolve(date: daily.recordDate, record: nil, stages: [stage]).source, .none)
        XCTAssertEqual(
            CanvasResolver.colors(
                date: daily.recordDate,
                record: nil,
                stages: [stage],
                includeStageBackgrounds: true
            ),
            ["#87B78F"]
        )
        XCTAssertEqual(
            CanvasResolver.resolve(
                date: daily.recordDate,
                record: nil,
                stages: [stage],
                includeStageBackgrounds: true
            ).source,
            .stage
        )
    }

    func testLegacyIntentionalBlankRemainsWhite() {
        var blank = record(date: "2024-06-15", colors: ["#D9948A"])
        blank.isIntentionalBlank = true
        XCTAssertEqual(CanvasResolver.colors(date: blank.recordDate, record: blank, stages: [lifeStage(start: "2024-01", end: "2024-12", color: "#87B78F")]), [])
    }

    func testGalleryIncludesPastAndCurrentYearsWithDailyRecords() {
        let values = GalleryResolver.years(
            records: [
                record(date: "2022-04-03", colors: ["#D9948A"]),
                record(date: "2026-07-30", colors: ["#87B78F"])
            ],
            stages: [lifeStage(start: "2023-01", end: "2024-12", color: "#87B78F")],
            startYear: 2021,
            currentYear: 2026
        )
        XCTAssertEqual(values, [2026, 2022])
    }

    func testArtworkThemesAndGenerationPolicyMatchH5Contract() throws {
        XCTAssertEqual(ArtworkTheme.allCases.map(\.rawValue), [
            "Mountain", "Forest", "Ocean", "Lake", "Desert", "AbstractPortrait"
        ])

        let data = Data("""
        {
          "Enabled": true,
          "MonthlyLimit": 1,
          "Used": 1,
          "Remaining": 0,
          "QuotaMonth": "2026-07",
          "NextResetAt": "2026-08-01T00:00:00+08:00",
          "Timezone": "Asia/Shanghai"
        }
        """.utf8)
        let policy = try JSONDecoder().decode(ArtworkGenerationPolicy.self, from: data)
        XCTAssertTrue(policy.quotaReached)
        XCTAssertEqual(policy.timezone, "Asia/Shanghai")
    }

    func testYearBoundaryContainsOneHundredElevenSelectableYears() {
        let currentYear = 2026
        XCTAssertEqual(Array((currentYear - 110)...currentYear).count, 111)
        XCTAssertEqual(currentYear - 110, 1916)
    }

    func testUnnamedStageUsesItsRangeAndPortraitYearsLoadInBatches() {
        var stage = lifeStage(start: "1982-02", end: "1984-02", color: "#87B78F")
        stage.name = "   "

        XCTAssertEqual(stage.displayTitle, "1982-02 — 1984-02")
        XCTAssertEqual(
            PortraitYearPagination.visibleYears([2026, 2025, 2024, 2023, 2022], count: 3),
            [2026, 2025, 2024]
        )
    }

    @MainActor
    func testSavingEarlierUnnamedStageExpandsLocalCanvasStartYear() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MosaLifeStageTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalRepository(directory: root)
        repository.saveProfile(LocalProfile(
            displayName: "MOSA Tester",
            locale: "en",
            timezone: "UTC",
            startYear: 2020,
            initializedAt: .now
        ))
        let store = MosaStore(
            repository: repository,
            sessionStore: KeychainSessionStore(service: "com.wekarepartners.mosa.tests.\(UUID().uuidString)"),
            startsDiagnostics: false
        )

        try await store.saveLifeStage(
            id: nil,
            name: "   ",
            startMonth: "1982-02",
            endMonth: "1984-02",
            colorCodes: ["#87B78F"],
            presetCode: nil
        )
        await store.saveProfile(displayName: "MOSA Tester", startYear: 2025)

        XCTAssertEqual(store.profile?.startYear, 1982)
        XCTAssertEqual(store.lifeStages.first?.name, "")
    }

    func testNewLifeStageSplitsTheCoveredRange() {
        var original = lifeStage(start: "2024-01", end: "2024-12", color: "#87B78F")
        original.id = "original"
        var replacement = lifeStage(start: "2024-04", end: "2024-06", color: "#D9948A")
        replacement.id = "replacement"

        let result = LifeStageRangeResolver.override(
            stages: [original],
            with: replacement,
            now: .now,
            syncState: .localOnly,
            createID: { "right" }
        )

        XCTAssertEqual(result.stages.map { [$0.id, $0.startMonth, $0.endMonth] }, [
            ["original", "2024-01", "2024-03"],
            ["replacement", "2024-04", "2024-06"],
            ["right", "2024-07", "2024-12"]
        ])
    }

    func testDateKeyUsesTheUsersNaturalDayAcrossChinaAndUnitedStates() throws {
        let instant = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T06:30:00Z")
        )
        let china = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let pacific = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        XCTAssertEqual(DateSupport.key(instant, timeZone: china), "2026-07-24")
        XCTAssertEqual(DateSupport.key(instant, timeZone: pacific), "2026-07-23")
        XCTAssertEqual(
            DateSupport.readable("2026-07-23", timeZone: pacific),
            "Thursday, July 23, 2026"
        )
    }

    func testMonthCellsKeepDateKeysStableInChinaAndUnitedStates() throws {
        let china = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let pacific = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        for timeZone in [china, pacific] {
            let keys = DateSupport.monthCells(year: 2026, month: 7, timeZone: timeZone)
                .compactMap { $0 }
                .map { DateSupport.key($0, timeZone: timeZone) }

            XCTAssertEqual(keys.first, "2026-07-01")
            XCTAssertEqual(keys.last, "2026-07-31")
            XCTAssertEqual(Set(keys).count, 31)
        }
    }

    func testPublicConfigurationRejectsUnsupportedOrInsecureValues() throws {
        let valid = PublicAppConfiguration.defaultValue
        XCTAssertTrue(valid.isValid)

        let data = try JSONEncoder().encode(valid)
        let decoded = try JSONDecoder().decode(PublicAppConfiguration.self, from: data)
        XCTAssertEqual(decoded, valid)

        let insecure = PublicAppConfiguration(
            schemaVersion: 1,
            revision: "test",
            maintenance: false,
            minimumVersion: valid.minimumVersion,
            recommendedVersion: valid.recommendedVersion,
            announcement: nil,
            featureFlags: [:],
            supportUrl: URL(string: "http://example.com")!,
            refreshAfterSeconds: 300
        )
        XCTAssertFalse(insecure.isValid)
    }

    func testDeveloperNetworkLogIncludesDomainAndOnlySafeQueryItems() {
        let value = APIClient.developerLogURL(
            baseURL: URL(string: "https://api.wekarepartners.com")!,
            path: "v1/mosa/records",
            queryItems: [
                URLQueryItem(name: "from", value: "2026-01-01"),
                URLQueryItem(name: "to", value: "2026-12-31"),
                URLQueryItem(name: "token", value: "secret")
            ]
        )

        XCTAssertEqual(
            value,
            "https://api.wekarepartners.com/api/v1/mosa/records?from=2026-01-01&to=2026-12-31"
        )
        XCTAssertFalse(value.contains("secret"))
    }

    func testCloudSyncResultExplainsSkippedAndCompletedSyncs() {
        XCTAssertEqual(
            CloudSyncResult.signInRequired.message,
            "Sign in from Profile before syncing with the cloud."
        )
        XCTAssertFalse(CloudSyncResult.signInRequired.succeeded)
        XCTAssertTrue(CloudSyncResult.completed.succeeded)
        XCTAssertTrue(CloudSyncResult.completedWithFailures(2).message.contains("2 local item(s)"))
    }

    func testCloudRecordRecognizesAnAlreadySavedLocalRecord() {
        let local = LocalRecord(
            id: "local-record",
            recordDate: "2026-07-25",
            note: "A saved day",
            isIntentionalBlank: false,
            colorCodes: ["#D46F65"],
            emotions: [
                LocalEmotion(
                    emotionCode: .anger,
                    role: .primary,
                    colorCode: "#D46F65"
                )
            ],
            emotionIntensity: .clear,
            tagNames: ["Family"],
            version: 2,
            serverVersion: 1,
            syncState: .syncFailed,
            deleted: false,
            createdAt: .now,
            updatedAt: .now
        )
        let cloud = cloudRecord(
            note: "A saved day",
            version: 2,
            tagNames: ["family"]
        )

        XCTAssertTrue(cloud.hasSameContent(as: local))
    }

    func testCloudRecordRejectsDifferentContentDuringConflictRecovery() {
        let cloud = cloudRecord(
            note: "Older cloud edit",
            version: 2,
            tagNames: []
        )
        var local = cloud.localValue(existingID: "local-record")
        local.note = "Newest local edit"
        local.serverVersion = 1
        local.syncState = .syncFailed

        XCTAssertFalse(cloud.hasSameContent(as: local))
    }

    func testDiagnosticSanitizerRemovesSensitiveValues() {
        let value = DiagnosticSanitizer.sanitize(
            "Bearer secret-token user@example.com /invite/abcdefghijklmnopqrstuvwxyz012345"
        )
        XCTAssertFalse(value.contains("secret-token"))
        XCTAssertFalse(value.contains("user@example.com"))
        XCTAssertFalse(value.contains("abcdefghijklmnopqrstuvwxyz012345"))
    }

    func testDiagnosticConsentDefaultsToDisabled() {
        let suiteName = "MosaDiagnosticConsentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(DiagnosticConsent.isEnabled(in: defaults))
        defaults.set(true, forKey: DiagnosticConsent.key)
        XCTAssertTrue(DiagnosticConsent.isEnabled(in: defaults))
    }

    func testEmotionCatalogHasEightUniqueColorsAndIcons() {
        XCTAssertEqual(MosaPalette.emotions.count, 8)
        XCTAssertEqual(Set(MosaPalette.emotions.map(\.code)).count, 8)
        XCTAssertEqual(Set(MosaPalette.emotions.map(\.hex)).count, 8)
        XCTAssertEqual(Set(MosaPalette.emotions.map(\.iconName)).count, 8)
        XCTAssertEqual(MosaPalette.emotion(forHex: "#d46f65")?.code, .anger)
    }

    @MainActor
    func testLocalRepositoryPersistsRecordsAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MosaLocalRepositoryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalRepository(directory: directory)
        let expected = record(date: "2026-07-26", colors: ["#D9948A"])

        try repository.saveRecords([expected])

        let saved = try XCTUnwrap(repository.loadRecords().first)
        XCTAssertEqual(saved.id, expected.id)
        XCTAssertEqual(saved.recordDate, expected.recordDate)
        XCTAssertEqual(saved.colorCodes, expected.colorCodes)
        XCTAssertLessThan(abs(saved.createdAt.timeIntervalSince(expected.createdAt)), 1)
        XCTAssertLessThan(abs(saved.updatedAt.timeIntervalSince(expected.updatedAt)), 1)
    }

    @MainActor
    func testLocalRepositoryReportsCorruptRecordsWithoutOverwritingThem() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MosaLocalRepositoryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recordsURL = directory.appendingPathComponent("records.json")
        let corruptData = Data("{not-json".utf8)
        try corruptData.write(to: recordsURL)
        let repository = LocalRepository(directory: directory)

        XCTAssertThrowsError(try repository.loadRecords())
        XCTAssertEqual(try Data(contentsOf: recordsURL), corruptData)
    }

    @MainActor
    func testLocalRepositoryDeletesAllAccountDataAndCaches() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MosaAccountDeletionTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalRepository(directory: directory)
        let expected = record(date: "2026-08-20", colors: ["#D9948A"])
        try repository.saveRecords([expected])
        try repository.saveShareCardImage(
            Data("private-card".utf8),
            year: 2026,
            account: "delete@example.com",
            sourceKey: "private-workflow"
        )

        try repository.deleteAllData()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(try repository.loadRecords().isEmpty)
        XCTAssertNil(repository.loadShareCardImage(year: 2026, account: "delete@example.com"))
    }

    @MainActor
    func testShareCardCacheKeepsOldImageUntilNewImageAndSeparatesAccounts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MosaShareCardCacheTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalRepository(directory: directory)

        try repository.saveShareCardImage(Data("old-card".utf8), year: 2026, account: "first@example.com", sourceKey: "workflow-1")
        XCTAssertEqual(repository.loadShareCardImage(year: 2026, account: "first@example.com"), Data("old-card".utf8))
        XCTAssertTrue(repository.hasCurrentShareCardImage(year: 2026, account: "first@example.com", sourceKey: "workflow-1"))
        XCTAssertFalse(repository.hasCurrentShareCardImage(year: 2026, account: "first@example.com", sourceKey: "workflow-2"))
        XCTAssertNil(repository.loadShareCardImage(year: 2026, account: "second@example.com"))

        try repository.saveShareCardImage(Data("new-card".utf8), year: 2026, account: "first@example.com", sourceKey: "workflow-2")
        XCTAssertEqual(repository.loadShareCardImage(year: 2026, account: "first@example.com"), Data("new-card".utf8))
        XCTAssertTrue(repository.hasCurrentShareCardImage(year: 2026, account: "first@example.com", sourceKey: "workflow-2"))
    }

    @MainActor
    func testStoreRollsBackMemoryWhenLocalRecordWriteFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MosaLocalRepositoryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blockingFile = root.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blockingFile)
        let repository = LocalRepository(
            directory: blockingFile.appendingPathComponent("MOSA")
        )
        let sessionStore = KeychainSessionStore(
            service: "com.wekarepartners.mosa.tests.\(UUID().uuidString)"
        )
        let store = MosaStore(
            repository: repository,
            sessionStore: sessionStore,
            startsDiagnostics: false
        )

        do {
            try await store.saveRecord(
                date: "2026-07-26",
                note: "Keep this draft",
                intentionalBlank: false,
                colorCodes: [],
                tagNames: []
            )
            XCTFail("Expected the local write to fail.")
        } catch {
            XCTAssertNotNil(error as? LocalRepositoryError)
        }

        XCTAssertNil(store.record(for: "2026-07-26"))
    }

    private func record(date: String, colors: [String]) -> LocalRecord {
        LocalRecord(id: UUID().uuidString, recordDate: date, note: "", isIntentionalBlank: false, colorCodes: colors, tagNames: [], version: 1, serverVersion: nil, syncState: .localOnly, deleted: false, createdAt: .now, updatedAt: .now)
    }

    private func lifeStage(start: String, end: String, color: String) -> LocalLifeStage {
        LocalLifeStage(id: UUID().uuidString, name: "Stage", startMonth: start, endMonth: end, colorCode: color, version: 1, serverVersion: nil, syncState: .localOnly, deleted: false, createdAt: .now, updatedAt: .now)
    }

    private func cloudRecord(note: String, version: Int, tagNames: [String]) -> CloudRecord {
        CloudRecord(
            id: "cloud-record",
            recordDate: "2026-07-25",
            note: note,
            isIntentionalBlank: false,
            version: version,
            isDeleted: false,
            colorCodes: ["#D46F65"],
            emotions: [
                LocalEmotion(
                    emotionCode: .anger,
                    role: .primary,
                    colorCode: "#D46F65"
                )
            ],
            emotionIntensity: .clear,
            blankSource: nil,
            hasLegacyUnmappedColors: false,
            tags: tagNames.enumerated().map { index, name in
                CloudTag(id: String(index + 1), name: name)
            },
            createTime: "2026-07-25T00:00:00Z",
            modifyTime: "2026-07-25T01:00:00Z"
        )
    }
}

private final class AuthenticatedImageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var imageRequestCount = 0
    private(set) static var imageAuthorizationHeaders: [String] = []
    private(set) static var refreshRequestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if url.path.hasSuffix("/api/v1/mosa/auth/refresh") {
            Self.lock.lock()
            Self.refreshRequestCount += 1
            Self.lock.unlock()
            Thread.sleep(forTimeInterval: 0.05)
            respond(
                status: 200,
                contentType: "application/json",
                data: Data(#"{"success":true,"msg":"","response":{"token":"refreshed-token","RefreshToken":"refreshed-token-value"},"extra":null}"#.utf8)
            )
            return
        }

        Self.lock.lock()
        Self.imageRequestCount += 1
        let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
        Self.imageAuthorizationHeaders.append(authorization)
        Self.lock.unlock()
        if authorization == "Bearer expired-token" {
            respond(status: 401, contentType: "application/json", data: Data())
        } else {
            respond(status: 200, contentType: "image/png", data: Data("PNG".utf8))
        }
    }

    override func stopLoading() {}

    static func reset() {
        lock.lock()
        imageRequestCount = 0
        imageAuthorizationHeaders = []
        refreshRequestCount = 0
        lock.unlock()
    }

    private func respond(status: Int, contentType: String, data: Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType, "Content-Length": String(data.count)]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class MemorySessionStore: SessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?

    init(_ session: AuthSession?) {
        self.session = session
    }

    func load() -> AuthSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    func save(_ session: AuthSession?) {
        lock.lock()
        self.session = session
        lock.unlock()
    }
}
