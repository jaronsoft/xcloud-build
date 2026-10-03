import Combine
import Foundation
import MetricKit
import UIKit

struct DeveloperNetworkLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let method: String
    let path: String
    let statusCode: Int?
    let durationMilliseconds: Int
    let succeeded: Bool
    let message: String
}

@MainActor
final class DeveloperNetworkLogStore: ObservableObject {
    @Published private(set) var entries: [DeveloperNetworkLogEntry] = []

    func record(
        startedAt: Date,
        method: String,
        path: String,
        statusCode: Int?,
        succeeded: Bool,
        message: String
    ) {
        guard AppConfiguration.showsNetworkDiagnostics else { return }
        let duration = max(0, Int(Date.now.timeIntervalSince(startedAt) * 1_000))
        let entry = DeveloperNetworkLogEntry(
            timestamp: .now,
            method: method,
            path: path,
            statusCode: statusCode,
            durationMilliseconds: duration,
            succeeded: succeeded,
            message: message
        )
        entries.insert(entry, at: 0)
        if entries.count > 200 {
            entries.removeLast(entries.count - 200)
        }
    }

    func clear() {
        entries.removeAll()
    }

    var exportText: String {
        entries.reversed().map(text(for:))
        .joined(separator: "\n")
    }

    func text(for entry: DeveloperNetworkLogEntry) -> String {
        let status = entry.statusCode.map(String.init) ?? "NETWORK"
        return "[\(entry.timestamp.formatted(.iso8601))] \(entry.method) \(entry.path) · \(status) · \(entry.durationMilliseconds)ms · \(entry.message)"
    }
}

struct ClientDiagnosticEvent: Codable, Identifiable, Sendable {
    let id: String
    let eventType: String
    let occurredAt: String
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let deviceModel: String
    let locale: String
    let errorDomain: String?
    let errorCode: String?
    let message: String?
    let diagnosticPayload: String?

    enum CodingKeys: String, CodingKey {
        case id = "ClientEventId"
        case eventType = "EventType"
        case occurredAt = "OccurredAt"
        case appVersion = "AppVersion"
        case buildNumber = "BuildNumber"
        case osVersion = "OsVersion"
        case deviceModel = "DeviceModel"
        case locale = "Locale"
        case errorDomain = "ErrorDomain"
        case errorCode = "ErrorCode"
        case message = "Message"
        case diagnosticPayload = "DiagnosticPayload"
    }
}

enum DiagnosticSanitizer {
    static func sanitize(_ value: String, limit: Int = 1_000) -> String {
        var result = value
        result = replacing(#"(?i)Bearer\s+[A-Za-z0-9._~+\-/]+=*"#, in: result, with: "Bearer [REDACTED]")
        result = replacing(#"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#, in: result, with: "[REDACTED_TOKEN]")
        result = replacing(#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, in: result, with: "[REDACTED_EMAIL]")
        result = replacing(#"(?i)/invite/[A-Za-z0-9_-]{8,}"#, in: result, with: "/invite/[REDACTED]")
        return String(result.prefix(limit))
    }

    private static func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }
}

/// 正式包使用 MetricKit 接收系统崩溃诊断，并将脱敏事件保存在有界本地队列中。
enum DiagnosticConsent {
    static let key = "mosa.shareDiagnostics"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }
}

@MainActor
final class DiagnosticsReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsReporter()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var events: [ClientDiagnosticEvent] = []
    private var started = false
    private var subscribed = false
    private var enabled: Bool {
        DiagnosticConsent.isEnabled()
    }

    private override init() {
        super.init()
        if enabled {
            events = load().filter { event in
                guard let date = ISO8601DateFormatter().date(from: event.occurredAt) else { return false }
                return date >= Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
            }
            persist()
        } else {
            clearQueue()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        updateSubscription()
    }

    func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: DiagnosticConsent.key)
        updateSubscription()
        if !value {
            events.removeAll()
            clearQueue()
        }
    }

    func record(error: Error, context: String) {
        guard enabled else { return }
        let value = error as NSError
        enqueue(eventType: "ERROR", domain: value.domain, code: String(value.code), message: "\(context): \(value.localizedDescription)", payload: nil)
    }

    func pendingBatch(limit: Int = 10) -> [ClientDiagnosticEvent] {
        guard enabled else { return [] }
        return Array(events.prefix(limit))
    }

    func remove(eventIds: [String]) {
        let ids = Set(eventIds)
        events.removeAll { ids.contains($0.id) }
        persist()
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Task { @MainActor in
            for payload in payloads {
                let type: String
                if !(payload.crashDiagnostics?.isEmpty ?? true) {
                    type = "CRASH"
                } else if !(payload.hangDiagnostics?.isEmpty ?? true) {
                    type = "HANG"
                } else if !(payload.cpuExceptionDiagnostics?.isEmpty ?? true) {
                    type = "WATCHDOG"
                } else {
                    type = "ERROR"
                }
                let json = String(data: payload.jsonRepresentation(), encoding: .utf8)
                self.enqueue(eventType: type, domain: "MetricKit", code: nil, message: "Apple system diagnostic payload", payload: json)
            }
        }
    }

    private func enqueue(eventType: String, domain: String?, code: String?, message: String?, payload: String?) {
        guard enabled else { return }
        let event = ClientDiagnosticEvent(
            id: UUID().uuidString.lowercased(),
            eventType: eventType,
            occurredAt: ISO8601DateFormatter().string(from: .now),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model,
            locale: Locale.current.identifier,
            errorDomain: domain.map { DiagnosticSanitizer.sanitize($0, limit: 120) },
            errorCode: code.map { DiagnosticSanitizer.sanitize($0, limit: 80) },
            message: message.map { DiagnosticSanitizer.sanitize($0) },
            diagnosticPayload: payload.map { DiagnosticSanitizer.sanitize($0, limit: 60_000) }
        )
        events.insert(event, at: 0)
        if events.count > 20 { events.removeLast(events.count - 20) }
        persist()
    }

    private func load() -> [ClientDiagnosticEvent] {
        guard let data = try? Data(contentsOf: queueURL),
              let values = try? decoder.decode([ClientDiagnosticEvent].self, from: data) else { return [] }
        return values
    }

    private func persist() {
        guard enabled else {
            clearQueue()
            return
        }
        guard let data = try? encoder.encode(events) else { return }
        try? FileManager.default.createDirectory(at: queueURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: queueURL, options: .atomic)
    }

    private func updateSubscription() {
        if started && enabled && !subscribed {
            MXMetricManager.shared.add(self)
            subscribed = true
        } else if subscribed && !enabled {
            MXMetricManager.shared.remove(self)
            subscribed = false
        }
    }

    private func clearQueue() {
        try? FileManager.default.removeItem(at: queueURL)
    }

    private var queueURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MOSA", isDirectory: true).appendingPathComponent("diagnostics-v1.json")
    }
}
