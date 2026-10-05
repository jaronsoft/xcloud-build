import Foundation
import Observation

struct AIKDiagnosticEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let method: String
    let path: String
    let statusCode: Int?
    let durationMilliseconds: Int
    let message: String
}

@MainActor
@Observable
final class AIKDiagnosticsStore {
    static let shared = AIKDiagnosticsStore()
    private(set) var entries: [AIKDiagnosticEntry] = []
    private let fileURL = FileManager.default.urls(
        for: .cachesDirectory,
        in: .userDomainMask
    )[0].appending(path: "AIKDiagnostics.json")

    private init() {
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? JSONDecoder().decode([AIKDiagnosticEntry].self, from: data) else {
            return
        }
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
        entries = values.filter { $0.timestamp >= cutoff }
    }

    func record(
        startedAt: Date,
        request: URLRequest,
        statusCode: Int?,
        message: String
    ) {
        let entry = AIKDiagnosticEntry(
            id: UUID(),
            timestamp: .now,
            method: request.httpMethod ?? "GET",
            path: request.url?.path ?? "—",
            statusCode: statusCode,
            durationMilliseconds: max(0, Int(Date.now.timeIntervalSince(startedAt) * 1_000)),
            message: Self.sanitize(message)
        )
        entries.insert(entry, at: 0)
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
        entries = Array(entries.filter { $0.timestamp >= cutoff }.prefix(500))
        persist()
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    var exportText: String {
        entries.reversed().map {
            "[\($0.timestamp.formatted(.iso8601))] \($0.method) \($0.path) "
                + "\($0.statusCode.map(String.init) ?? "NETWORK") "
                + "\($0.durationMilliseconds)ms \($0.message)"
        }.joined(separator: "\n")
    }

    private func persist() {
        guard var data = try? JSONEncoder().encode(entries) else { return }
        while data.count > 2 * 1_024 * 1_024, !entries.isEmpty {
            entries.removeLast()
            guard let next = try? JSONEncoder().encode(entries) else { return }
            data = next
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func sanitize(_ value: String) -> String {
        var output = value
        for pattern in [
            #"(?i)Bearer\s+\S+"#,
            #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#,
            #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            #"[?&][^\s]+"#,
        ] {
            output = output.replacingOccurrences(
                of: pattern,
                with: "[REDACTED]",
                options: .regularExpression
            )
        }
        return String(output.prefix(500))
    }
}
