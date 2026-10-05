import Foundation
import Observation

struct NetworkDiagnosticEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let method: String
    let path: String
    let address: String
    let statusCode: Int?
    let durationMilliseconds: Int
    let succeeded: Bool
    let message: String
    let details: String
}

struct ImageCacheDiagnosticEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let requestedPreset: String
    let appliedPreset: String
    let pixelWidth: Int?
    let resourceKind: PixaImageResourceKind
    let source: String
    let transformed: Bool
    let host: String
    let path: String
    let byteCount: Int
    let durationMilliseconds: Int

    var logMessage: String {
        "requestedPreset=\(requestedPreset) appliedPreset=\(appliedPreset) "
            + "pixelWidth=\(pixelWidth.map(String.init) ?? "original") kind=\(resourceKind.rawValue) "
            + "source=\(source) transformed=\(transformed) host=\(host) path=\(path) "
            + "bytes=\(byteCount) durationMs=\(durationMilliseconds)"
    }
}

@MainActor
@Observable
final class NetworkDiagnosticsStore {
    static let shared = NetworkDiagnosticsStore()

    private(set) var entries: [NetworkDiagnosticEntry] = []
    private(set) var imageCacheEntries: [ImageCacheDiagnosticEntry] = []
    private(set) var systemLogs: [String] = []

    private init() {
        recordSystemLog(tag: "BOOT", "PixaRivo diagnostics initialized.")
    }

    func record(
        startedAt: Date,
        request: URLRequest,
        statusCode: Int?,
        succeeded: Bool,
        message: String,
        details: String? = nil
    ) {
        let entry = NetworkDiagnosticEntry(
            timestamp: .now,
            method: request.httpMethod ?? "GET",
            path: Self.sanitizedPath(for: request.url),
            address: Self.sanitizedAddress(for: request.url),
            statusCode: statusCode,
            durationMilliseconds: max(0, Int(Date.now.timeIntervalSince(startedAt) * 1_000)),
            succeeded: succeeded,
            message: Self.sanitizedMessage(message),
            details: Self.sanitizedMessage(details ?? message, maximumLength: 12_000)
        )
        entries.insert(entry, at: 0)
        if entries.count > 200 { entries.removeLast(entries.count - 200) }
    }

    func recordImageCache(_ entry: ImageCacheDiagnosticEntry) {
        imageCacheEntries.insert(entry, at: 0)
        if imageCacheEntries.count > 300 { imageCacheEntries.removeLast(imageCacheEntries.count - 300) }
    }

    func recordSystemLog(tag: String = "SYSTEM", _ message: String) {
        systemLogs.insert("[\(tag)] \(Self.sanitizedMessage(message))", at: 0)
        if systemLogs.count > 300 { systemLogs.removeLast(systemLogs.count - 300) }
    }

    func clear() {
        entries.removeAll()
        imageCacheEntries.removeAll()
        systemLogs.removeAll()
    }

    var exportText: String {
        var lines = [
            "PixaRivo \(AppConfiguration.releaseLabel)",
            "API Node \(AppAPIRoutingSnapshot.displayName)",
            "System \(ProcessInfo.processInfo.operatingSystemVersionString)",
            ""
        ]
        lines += systemLogs.reversed()
        lines += imageCacheEntries.reversed().map { "[IMAGE_CACHE] \($0.logMessage)" }
        lines += entries.reversed().map(text(for:))
        return lines.joined(separator: "\n")
    }

    var errorExportText: String {
        let failedEntries = entries.filter { !$0.succeeded }.reversed()
        var sections = [
            "PixaRivo \(AppConfiguration.releaseLabel)",
            "API Node \(AppAPIRoutingSnapshot.displayName)",
            "System \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Failed Requests \(failedEntries.count)"
        ]
        sections += failedEntries.map { detailText(for: $0) }
        return sections.joined(separator: "\n\n---\n\n")
    }

    var hasFailedEntries: Bool {
        entries.contains { !$0.succeeded }
    }

    /// 将脱敏内容写入临时文本文件，确保系统分享面板导出的是附件而不是普通文本链接。
    func makeExportFileURL(name: String, content: String) -> URL? {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("PixaRivo-Diagnostics", isDirectory: true)
        let timestamp = ISO8601DateFormatter()
            .string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let fileURL = directory.appendingPathComponent("\(name)-\(timestamp).txt")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            recordSystemLog(tag: "DIAGNOSTICS_EXPORT", "Failed to create export file: \(error.localizedDescription)")
            return nil
        }
    }

    func text(for entry: NetworkDiagnosticEntry) -> String {
        "[\(entry.timestamp.formatted(.iso8601))] \(entry.method) \(entry.address) · "
            + "\(entry.statusCode.map(String.init) ?? "NETWORK") · \(entry.durationMilliseconds)ms · \(entry.message)"
    }

    func detailText(for entry: NetworkDiagnosticEntry) -> String {
        text(for: entry) + "\n\n" + entry.details
    }

    nonisolated static func sanitizedPath(for url: URL?) -> String {
        guard let url else { return "—" }
        var components = URLComponents()
        components.path = url.path
        return components.path.isEmpty ? "/" : components.path
    }

    nonisolated static func sanitizedAddress(for url: URL?) -> String {
        guard let url else { return "—" }
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = url.path.isEmpty ? "/" : url.path
        return components.string ?? sanitizedPath(for: url)
    }

    nonisolated static func sanitizedMessage(_ value: String, maximumLength: Int = 1_000) -> String {
        var result = value
        for (pattern, replacement) in [
            (#"(?i)Bearer\s+[A-Za-z0-9._~+\-/]+=*"#, "Bearer [REDACTED]"),
            (#"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#, "[REDACTED_TOKEN]"),
            (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[REDACTED_EMAIL]")
        ] {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            result = expression.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }
        return String(result.prefix(maximumLength))
    }

    nonisolated static func sanitizedBody(_ data: Data?, maximumLength: Int = 12_000) -> String {
        guard let data, !data.isEmpty else { return "<empty>" }
        if let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
            let redacted = redactJSON(object)
            if let json = try? JSONSerialization.data(withJSONObject: redacted, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: json, encoding: .utf8) {
                return truncated(text, maximumLength: maximumLength)
            }
        }
        let text = String(data: data, encoding: .utf8) ?? "<(data.count) bytes of non-text data>"
        return truncated(sanitizedMessage(text, maximumLength: maximumLength), maximumLength: maximumLength)
    }

    nonisolated private static func redactJSON(_ value: Any) -> Any {
        let sensitiveKeys = Set([
            "authorization", "cookie", "set-cookie", "x-api-key", "accessToken", "refreshToken",
            "token", "password", "secret", "privateKey", "signingPrivateKey"
        ].map { $0.lowercased() })
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                result[item.key] = sensitiveKeys.contains(item.key.lowercased())
                    ? "[REDACTED]"
                    : redactJSON(item.value)
            }
        }
        if let array = value as? [Any] { return array.map(redactJSON) }
        if let string = value as? String { return sanitizedMessage(string, maximumLength: 12_000) }
        return value
    }

    nonisolated private static func truncated(_ value: String, maximumLength: Int) -> String {
        guard value.count > maximumLength else { return value }
        return String(value.prefix(maximumLength)) + "\n[TRUNCATED]"
    }
}
