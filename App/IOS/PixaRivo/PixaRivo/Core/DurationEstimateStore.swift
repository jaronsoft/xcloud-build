import Foundation
import Observation

struct PixaDurationEstimateSummary: Decodable, Sendable {
    let estimates: [PixaDurationEstimate]

    private enum CodingKeys: String, CodingKey {
        case estimates = "Estimates"
        case estimatesLower = "estimates"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        estimates = try box.decodeIfPresent([PixaDurationEstimate].self, forKey: .estimates)
            ?? box.decodeIfPresent([PixaDurationEstimate].self, forKey: .estimatesLower)
            ?? []
    }
}

struct PixaDurationEstimate: Codable, Identifiable, Sendable {
    var id: String { jobType }
    let jobType: String
    let percentile80Seconds: Int
    let averageSeconds: Int
    let sampleCount: Int
    let isFallback: Bool

    private enum CodingKeys: String, CodingKey {
        case jobType = "JobType"
        case jobTypeLower = "jobType"
        case percentile80Seconds = "Percentile80Seconds"
        case percentile80SecondsLower = "percentile80Seconds"
        case averageSeconds = "AverageSeconds"
        case averageSecondsLower = "averageSeconds"
        case sampleCount = "SampleCount"
        case sampleCountLower = "sampleCount"
        case isFallback = "IsFallback"
        case isFallbackLower = "isFallback"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        jobType = try box.decodeIfPresent(String.self, forKey: .jobType)
            ?? box.decodeIfPresent(String.self, forKey: .jobTypeLower)
            ?? ""
        percentile80Seconds = try box.decodeIfPresent(Int.self, forKey: .percentile80Seconds)
            ?? box.decodeIfPresent(Int.self, forKey: .percentile80SecondsLower)
            ?? 60
        averageSeconds = try box.decodeIfPresent(Int.self, forKey: .averageSeconds)
            ?? box.decodeIfPresent(Int.self, forKey: .averageSecondsLower)
            ?? percentile80Seconds
        sampleCount = try box.decodeIfPresent(Int.self, forKey: .sampleCount)
            ?? box.decodeIfPresent(Int.self, forKey: .sampleCountLower)
            ?? 0
        isFallback = try box.decodeIfPresent(Bool.self, forKey: .isFallback)
            ?? box.decodeIfPresent(Bool.self, forKey: .isFallbackLower)
            ?? true
    }

    init(
        jobType: String,
        percentile80Seconds: Int,
        averageSeconds: Int,
        sampleCount: Int,
        isFallback: Bool
    ) {
        self.jobType = jobType
        self.percentile80Seconds = percentile80Seconds
        self.averageSeconds = averageSeconds
        self.sampleCount = sampleCount
        self.isFallback = isFallback
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(jobType, forKey: .jobType)
        try box.encode(percentile80Seconds, forKey: .percentile80Seconds)
        try box.encode(averageSeconds, forKey: .averageSeconds)
        try box.encode(sampleCount, forKey: .sampleCount)
        try box.encode(isFallback, forKey: .isFallback)
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

enum PixaDurationTextFormatter {
    static func approximate(seconds: Int) -> String {
        let value = max(1, seconds)
        if value < 60 {
            return String.localizedStringWithFormat(
                AppLanguage.localized("duration.approximate.seconds"),
                value
            )
        }
        if value < 3_600 {
            return String.localizedStringWithFormat(
                AppLanguage.localized("duration.approximate.minutes"),
                Int(ceil(Double(value) / 60))
            )
        }
        let hours = value / 3_600
        let minutes = Int(ceil(Double(value % 3_600) / 60))
        if minutes == 0 {
            return String.localizedStringWithFormat(
                AppLanguage.localized("duration.approximate.hours"),
                hours
            )
        }
        return String.localizedStringWithFormat(
            AppLanguage.localized("duration.approximate.hours_minutes"),
            hours,
            minutes
        )
    }

    static func countdown(seconds: Int) -> String {
        let value = max(0, seconds)
        if value < 3_600 {
            return String(format: "%02d:%02d", value / 60, value % 60)
        }
        return String.localizedStringWithFormat(
            AppLanguage.localized("duration.remaining.hours_minutes"),
            value / 3_600,
            (value % 3_600) / 60
        )
    }
}

enum PixaTaskDurationPresentation: Equatable {
    case queued
    case remaining(Int)
    case overdue
    case unavailable

    static func resolve(
        status: String,
        startedAt: Date?,
        estimateSeconds: Int?,
        now: Date
    ) -> Self {
        let normalizedStatus = status.lowercased()
        if ["queued", "pending"].contains(normalizedStatus) {
            return .queued
        }
        guard ["processing", "running"].contains(normalizedStatus),
              let startedAt,
              let estimateSeconds,
              estimateSeconds > 0 else {
            return .unavailable
        }
        let remaining = Int(
            startedAt
                .addingTimeInterval(TimeInterval(estimateSeconds))
                .timeIntervalSince(now)
        )
        return remaining > 0 ? .remaining(remaining) : .overdue
    }
}

actor PixaDurationEstimatePersistence {
    struct Snapshot: Codable, Sendable {
        let estimates: [PixaDurationEstimate]
        let refreshedAt: Date
    }

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            .appending(path: "PixaRivo", directoryHint: .isDirectory)
            .appending(path: "duration-estimates.json")
    }

    func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func write(_ snapshot: Snapshot) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
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
            // 耗时估算缓存失败不能阻断用户提交生成任务。
        }
    }
}

@MainActor
@Observable
final class PixaDurationEstimateStore {
    private static let defaultEstimate = PixaDurationEstimate.fallback(
        jobType: "style_template_generate",
        seconds: 60
    )

    private(set) var estimates: [String: PixaDurationEstimate] = [
        defaultEstimate.jobType: defaultEstimate
    ]
    private let api = APIClient()
    private let persistence = PixaDurationEstimatePersistence()
    private var persistedRefreshDate: Date?
    private var attemptedRefreshDay: Date?
    private var attemptedWithAccessToken = false
    private var hasLoadedPersistence = false
    private var isRefreshing = false

    func seconds(for jobType: String) -> Int {
        estimates[jobType.lowercased()]?.percentile80Seconds
            ?? Self.defaultEstimate.percentile80Seconds
    }

    func load(accessToken: String?, now: Date = .now) async {
        if !hasLoadedPersistence {
            hasLoadedPersistence = true
            if let snapshot = await persistence.read(), !snapshot.estimates.isEmpty {
                apply(snapshot.estimates)
                persistedRefreshDate = snapshot.refreshedAt
            }
        }
        await refreshIfNeeded(accessToken: accessToken, now: now)
    }

    private func refreshIfNeeded(accessToken: String?, now: Date) async {
        let calendar = Calendar.current
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
            let summary: PixaDurationEstimateSummary = try await api.get(
                "/api/ais/usage/duration-estimates",
                token: accessToken
            )
            guard !summary.estimates.isEmpty else { return }
            apply(summary.estimates)
            persistedRefreshDate = now
            await persistence.write(
                .init(estimates: summary.estimates, refreshedAt: now)
            )
        } catch {
            // 网络失败时继续使用当天缓存或内置的 60 秒默认值。
        }
    }

    private func apply(_ values: [PixaDurationEstimate]) {
        var result = [Self.defaultEstimate.jobType: Self.defaultEstimate]
        for value in values where !value.jobType.isEmpty {
            result[value.jobType.lowercased()] = value
        }
        estimates = result
    }
}
