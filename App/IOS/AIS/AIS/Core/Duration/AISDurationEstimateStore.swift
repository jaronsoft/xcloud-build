import Foundation
import Observation

struct AISDurationEstimateSummary: Codable, Sendable {
    let estimates: [AISDurationEstimate]

    private enum CodingKeys: String, CodingKey {
        case estimates = "Estimates"
    }
}

struct AISDurationEstimate: Codable, Identifiable, Sendable {
    var id: String { jobType }
    let jobType: String
    let percentile80Seconds: Int
    let averageSeconds: Int
    let sampleCount: Int
    let isFallback: Bool

    private enum CodingKeys: String, CodingKey {
        case jobType = "JobType"
        case percentile80Seconds = "Percentile80Seconds"
        case averageSeconds = "AverageSeconds"
        case sampleCount = "SampleCount"
        case isFallback = "IsFallback"
    }

    static func fallback(jobType: String, seconds: Int) -> Self {
        Self(
            jobType: jobType,
            percentile80Seconds: seconds,
            averageSeconds: seconds,
            sampleCount: 0,
            isFallback: true
        )
    }
}

enum AISDurationTextFormatter {
    static func approximate(seconds: Int) -> String {
        let value = max(1, seconds)
        if value < 60 {
            return String.localizedStringWithFormat(
                String(localized: "duration.approximate.seconds"),
                value
            )
        }
        if value < 60 * 60 {
            return String.localizedStringWithFormat(
                String(localized: "duration.approximate.minutes"),
                Int(ceil(Double(value) / 60))
            )
        }
        let hours = value / 3_600
        let minutes = Int(ceil(Double(value % 3_600) / 60))
        if minutes == 0 {
            return String.localizedStringWithFormat(
                String(localized: "duration.approximate.hours"),
                hours
            )
        }
        return String.localizedStringWithFormat(
            String(localized: "duration.approximate.hours_minutes"),
            hours,
            minutes
        )
    }

    static func countdown(seconds: Int) -> String {
        let value = max(0, seconds)
        if value < 60 * 60 {
            return String(format: "%02d:%02d", value / 60, value % 60)
        }
        return String.localizedStringWithFormat(
            String(localized: "duration.remaining.hours_minutes"),
            value / 3_600,
            (value % 3_600) / 60
        )
    }
}

enum AISCountdownPresentation: Equatable {
    case remaining(Int)
    case overdue

    static func resolve(
        startedAt: Date,
        estimateSeconds: Int,
        now: Date
    ) -> Self {
        let elapsed = max(0, Int(now.timeIntervalSince(startedAt)))
        let remaining = max(0, estimateSeconds - elapsed)
        return remaining > 0 ? .remaining(remaining) : .overdue
    }
}

actor AISDurationEstimatePersistence {
    struct Snapshot: Codable, Sendable {
        let estimates: [AISDurationEstimate]
        let refreshedAt: Date
    }

    private let fileManager: FileManager
    private let fileURL: URL

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL
            ?? fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            .appending(path: "AIS", directoryHint: .isDirectory)
            .appending(path: "duration-estimates.json")
    }

    func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func write(_ snapshot: Snapshot) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = directory
            try? mutableDirectory.setResourceValues(values)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 耗时数据持久化失败不能阻断任何 AI 功能。
        }
    }
}

@MainActor
@Observable
final class AISDurationEstimateStore {
    typealias Fetcher = (String?) async throws -> AISDurationEstimateSummary

    private static let defaultEstimates = [
        AISDurationEstimate.fallback(
            jobType: "image_generate",
            seconds: 60
        ),
        AISDurationEstimate.fallback(jobType: "image_edit", seconds: 60),
        AISDurationEstimate.fallback(
            jobType: "style_template_generate",
            seconds: 60
        ),
        AISDurationEstimate.fallback(jobType: "video_generate", seconds: 240),
        AISDurationEstimate.fallback(jobType: "prompt_optimize", seconds: 20),
        AISDurationEstimate.fallback(jobType: "result_analysis", seconds: 20),
        AISDurationEstimate.fallback(jobType: "image_understand", seconds: 60)
    ]

    private(set) var estimates: [String: AISDurationEstimate]
    private let persistence: AISDurationEstimatePersistence
    private let fetcher: Fetcher
    private let calendar: Calendar
    private var persistedRefreshDate: Date?
    private var attemptedRefreshDay: Date?
    private var attemptedWithAccessToken = false
    private var hasLoadedPersistence = false
    private var isRefreshing = false

    init(
        persistence: AISDurationEstimatePersistence =
            AISDurationEstimatePersistence(),
        calendar: Calendar = .current,
        fetcher: Fetcher? = nil
    ) {
        self.persistence = persistence
        self.calendar = calendar
        self.estimates = Self.dictionary(Self.defaultEstimates)
        self.fetcher = fetcher ?? { accessToken in
            try await APIClient().get(
                "/api/ais/usage/duration-estimates",
                accessToken: accessToken
            )
        }
    }

    func estimate(for jobType: String) -> AISDurationEstimate? {
        estimates[jobType.lowercased()]
    }

    func seconds(for jobType: String) -> Int? {
        estimate(for: jobType)?.percentile80Seconds
    }

    func load(accessToken: String?, now: Date = .now) async {
        if !hasLoadedPersistence {
            hasLoadedPersistence = true
            if let snapshot = await persistence.read(),
               !snapshot.estimates.isEmpty {
                estimates = Self.dictionary(snapshot.estimates)
                persistedRefreshDate = snapshot.refreshedAt
            }
        }
        await refreshIfNeeded(accessToken: accessToken, now: now)
    }

    func refreshIfNeeded(accessToken: String?, now: Date = .now) async {
        let day = calendar.startOfDay(for: now)
        if let attemptedRefreshDay,
           calendar.isDate(attemptedRefreshDay, inSameDayAs: day),
           attemptedWithAccessToken || accessToken == nil {
            return
        }
        if let persistedRefreshDate,
           calendar.isDate(persistedRefreshDate, inSameDayAs: day) {
            return
        }
        guard !isRefreshing else { return }
        attemptedRefreshDay = day
        attemptedWithAccessToken = accessToken != nil
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let summary = try await fetcher(accessToken)
            guard !summary.estimates.isEmpty else { return }
            estimates = Self.dictionary(summary.estimates)
            persistedRefreshDate = now
            await persistence.write(
                .init(estimates: summary.estimates, refreshedAt: now)
            )
        } catch {
            // 网络失败时继续使用持久化数据或内置默认值。
        }
    }

    private static func dictionary(
        _ values: [AISDurationEstimate]
    ) -> [String: AISDurationEstimate] {
        var result: [String: AISDurationEstimate] = [:]
        for value in defaultEstimates + values {
            result[value.jobType.lowercased()] = value
        }
        return result
    }
}
