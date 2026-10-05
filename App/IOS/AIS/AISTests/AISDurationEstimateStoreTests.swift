import Foundation
import Testing
@testable import AIS

private actor DurationFetchRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

struct AISDurationEstimateStoreTests {
    @Test
    @MainActor
    func usesDefaultsWhenInitialRefreshFails() async {
        let persistence = AISDurationEstimatePersistence(
            fileURL: Self.temporaryFileURL()
        )
        let store = AISDurationEstimateStore(
            persistence: persistence,
            fetcher: { _ in throw URLError(.notConnectedToInternet) }
        )

        await store.load(accessToken: nil)

        #expect(store.seconds(for: "image_generate") == 60)
        #expect(store.seconds(for: "prompt_optimize") == 20)
        #expect(store.seconds(for: "image_understand") == 60)
    }

    @Test
    @MainActor
    func refreshesOncePerDayAndAgainOnNextDay() async {
        let recorder = DurationFetchRecorder()
        let persistence = AISDurationEstimatePersistence(
            fileURL: Self.temporaryFileURL()
        )
        let store = AISDurationEstimateStore(
            persistence: persistence,
            calendar: Self.utcCalendar,
            fetcher: { _ in
                await recorder.record()
                return Self.summary(seconds: 35)
            }
        )
        let firstDay = Date(timeIntervalSince1970: 1_800_000_000)

        await store.load(accessToken: nil, now: firstDay)
        await store.refreshIfNeeded(
            accessToken: nil,
            now: firstDay.addingTimeInterval(3_600)
        )
        #expect(await recorder.count == 1)
        #expect(store.seconds(for: "prompt_optimize") == 35)

        await store.refreshIfNeeded(
            accessToken: nil,
            now: firstDay.addingTimeInterval(24 * 60 * 60)
        )
        #expect(await recorder.count == 2)
    }

    @Test
    @MainActor
    func restoresPersistedValuesAndKeepsThemWhenOffline() async {
        let fileURL = Self.temporaryFileURL()
        let persistence = AISDurationEstimatePersistence(fileURL: fileURL)
        let firstDay = Date(timeIntervalSince1970: 1_800_000_000)
        let onlineStore = AISDurationEstimateStore(
            persistence: persistence,
            calendar: Self.utcCalendar,
            fetcher: { _ in Self.summary(seconds: 42) }
        )
        await onlineStore.load(accessToken: nil, now: firstDay)

        let offlineStore = AISDurationEstimateStore(
            persistence: AISDurationEstimatePersistence(fileURL: fileURL),
            calendar: Self.utcCalendar,
            fetcher: { _ in throw URLError(.notConnectedToInternet) }
        )
        await offlineStore.load(
            accessToken: nil,
            now: firstDay.addingTimeInterval(3_600)
        )

        #expect(offlineStore.seconds(for: "prompt_optimize") == 42)
        #expect(offlineStore.seconds(for: "image_edit") == 60)
    }

    @Test
    @MainActor
    func retriesSameDayAfterUserSignsIn() async {
        let recorder = DurationFetchRecorder()
        let store = AISDurationEstimateStore(
            persistence: AISDurationEstimatePersistence(
                fileURL: Self.temporaryFileURL()
            ),
            calendar: Self.utcCalendar,
            fetcher: { accessToken in
                await recorder.record()
                guard accessToken != nil else {
                    throw URLError(.userAuthenticationRequired)
                }
                return Self.summary(seconds: 28)
            }
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        await store.load(accessToken: nil, now: now)
        await store.refreshIfNeeded(accessToken: "token", now: now)

        #expect(await recorder.count == 2)
        #expect(store.seconds(for: "prompt_optimize") == 28)
    }

    @Test
    func taskDurationUsesStartedAtAndHandlesQueueAndOverdue() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(
            AISTaskDurationPresentation.resolve(
                status: "queued",
                startedAt: nil,
                estimateSeconds: 60,
                now: now
            ) == .queued
        )
        #expect(
            AISTaskDurationPresentation.resolve(
                status: "running",
                startedAt: now.addingTimeInterval(-20),
                estimateSeconds: 60,
                now: now
            ) == .remaining(40)
        )
        #expect(
            AISTaskDurationPresentation.resolve(
                status: "processing",
                startedAt: now.addingTimeInterval(-61),
                estimateSeconds: 60,
                now: now
            ) == .overdue
        )
        #expect(
            AISTaskDurationPresentation.resolve(
                status: "running",
                startedAt: nil,
                estimateSeconds: 60,
                now: now
            ) == .unavailable
        )
    }

    @Test
    func countdownAndLongDurationFormattingDoNotMislead() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(
            AISCountdownPresentation.resolve(
                startedAt: now.addingTimeInterval(-5),
                estimateSeconds: 20,
                now: now
            ) == .remaining(15)
        )
        #expect(
            AISCountdownPresentation.resolve(
                startedAt: now.addingTimeInterval(-21),
                estimateSeconds: 20,
                now: now
            ) == .overdue
        )
        #expect(
            AISDurationTextFormatter.countdown(seconds: 28_724)
                .contains(":") == false
        )
    }

    @Test
    func taskDecodesStartedAtForRemainingTimeCalculation() throws {
        let data = Data(
            """
            {
              "Id": "832257117082181",
              "JobType": "image_generate",
              "Status": "running",
              "StartedAt": "2026-07-30T01:00:00Z"
            }
            """.utf8
        )

        let task = try JSONDecoder().decode(AISTaskJob.self, from: data)

        #expect(task.startedDate != nil)
    }

    @Test
    func taskTreatsServerDateWithoutOffsetAsChinaTime() throws {
        let data = Data(
            """
            {
              "Id": "834806548152581",
              "JobType": "style_template_generate",
              "Status": "running",
              "CreateTime": "2026-08-06T08:16:00",
              "StartedAt": "2026-08-06T08:16:00"
            }
            """.utf8
        )
        let task = try JSONDecoder().decode(AISTaskJob.self, from: data)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(
            from: DateComponents(
                year: 2026,
                month: 8,
                day: 6,
                hour: 8,
                minute: 16,
                second: 20
            )
        )!

        #expect(calendar.component(.hour, from: task.creationDate!) == 8)
        #expect(
            AISTaskDurationPresentation.resolve(
                status: task.status,
                startedAt: task.startedDate,
                estimateSeconds: 60,
                now: now
            ) == .remaining(40)
        )
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func summary(seconds: Int) -> AISDurationEstimateSummary {
        AISDurationEstimateSummary(
            estimates: [
                AISDurationEstimate(
                    jobType: "prompt_optimize",
                    percentile80Seconds: seconds,
                    averageSeconds: seconds,
                    sampleCount: 10,
                    isFallback: false
                )
            ]
        )
    }

    private static func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "duration-estimates.json")
    }
}
