import Foundation
import Observation

struct NetworkDiagnosticEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let method: String
    let path: String
    let statusCode: Int?
    let durationMilliseconds: Int
    let succeeded: Bool
    let message: String
}

struct SystemLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let tag: String
    let message: String
}

struct ImageCacheDiagnosticEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let module: AISImageCacheModule
    let requestedPreset: String
    let appliedPreset: String
    let pixelWidth: Int?
    let resourceKind: AISImageResourceKind
    let source: String
    let transformed: Bool
    let host: String
    let path: String
    let cacheKey: String
    let byteCount: Int
    let durationMilliseconds: Int

    var logMessage: String {
        "module=\(module.rawValue) requestedPreset=\(requestedPreset) "
            + "appliedPreset=\(appliedPreset) "
            + "pixelWidth=\(pixelWidth.map(String.init) ?? "original") "
            + "kind=\(resourceKind.rawValue) source=\(source) "
            + "transformed=\(transformed) host=\(host) path=\(path) "
            + "key=\(cacheKey) bytes=\(byteCount) "
            + "durationMs=\(durationMilliseconds)"
    }
}

private actor AISPersistentDiagnosticsLog {
    static let shared = AISPersistentDiagnosticsLog()
    static let maximumBytes = 2 * 1_024 * 1_024
    static let retention: TimeInterval = 7 * 24 * 60 * 60

    private let fileManager = FileManager.default
    private var lastPrunedAt = Date.distantPast

    nonisolated static var fileURL: URL {
        FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        .appending(path: "AISDiagnostics", directoryHint: .isDirectory)
        .appending(path: "diagnostics.log")
    }

    func append(_ entry: SystemLogEntry) {
        guard AppEnvironment.showsNetworkDiagnostics else { return }
        pruneIfNeeded()
        let epoch = entry.timestamp.timeIntervalSince1970
        let line = "\(epoch)\t[\(entry.timestamp.formatted(.iso8601))] "
            + "[\(entry.tag)] \(entry.message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = Self.fileURL
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: url.path()) {
            fileManager.createFile(atPath: url.path(), contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
        trimToMaximumSize()
    }

    func clear() {
        try? fileManager.removeItem(at: Self.fileURL)
    }

    nonisolated static func snapshotText() -> String {
        guard let value = try? String(
            contentsOf: fileURL,
            encoding: .utf8
        ) else {
            return ""
        }
        return value
            .split(separator: "\n")
            .map { line in
                guard let tab = line.firstIndex(of: "\t") else {
                    return String(line)
                }
                return String(line[line.index(after: tab)...])
            }
            .joined(separator: "\n")
    }

    private func pruneIfNeeded() {
        guard Date.now.timeIntervalSince(lastPrunedAt) >= 60 else { return }
        lastPrunedAt = .now
        let url = Self.fileURL
        guard let value = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        let cutoff = Date.now.addingTimeInterval(-Self.retention)
            .timeIntervalSince1970
        let retained = value.split(separator: "\n").filter { line in
            guard let tab = line.firstIndex(of: "\t"),
                  let epoch = Double(line[..<tab]) else {
                return false
            }
            return epoch >= cutoff
        }
        let output = retained.isEmpty
            ? ""
            : retained.joined(separator: "\n") + "\n"
        try? output.write(to: url, atomically: true, encoding: .utf8)
    }

    private func trimToMaximumSize() {
        let url = Self.fileURL
        guard let data = try? Data(contentsOf: url),
              data.count > Self.maximumBytes,
              let value = String(data: data, encoding: .utf8) else {
            return
        }
        var kept: [Substring] = []
        var byteCount = 0
        for line in value.split(separator: "\n").reversed() {
            let lineBytes = line.utf8.count + 1
            guard byteCount + lineBytes <= Self.maximumBytes else { break }
            kept.append(line)
            byteCount += lineBytes
        }
        let output = kept.reversed().joined(separator: "\n") + "\n"
        try? output.write(to: url, atomically: true, encoding: .utf8)
    }
}

@MainActor
@Observable
final class NetworkDiagnosticsStore {
    static let shared = NetworkDiagnosticsStore()

    private(set) var entries: [NetworkDiagnosticEntry] = []
    private(set) var systemLogs: [SystemLogEntry] = []
    private(set) var imageCacheEntries: [ImageCacheDiagnosticEntry] = []

    private init() {
        recordSystemLog(tag: "BOOT", "AIS diagnostics log store initialized.")
    }

    func recordSystemLog(tag: String = "SYSTEM", _ message: String) {
        let entry = SystemLogEntry(
            timestamp: .now,
            tag: tag,
            message: Self.sanitizedMessage(message)
        )
        systemLogs.insert(entry, at: 0)
        if systemLogs.count > 300 {
            systemLogs.removeLast(systemLogs.count - 300)
        }
        if AppEnvironment.showsNetworkDiagnostics {
            Task {
                await AISPersistentDiagnosticsLog.shared.append(entry)
            }
        }
    }

    func recordImageCache(_ entry: ImageCacheDiagnosticEntry) {
        imageCacheEntries.insert(entry, at: 0)
        if imageCacheEntries.count > 300 {
            imageCacheEntries.removeLast(imageCacheEntries.count - 300)
        }
        guard AppEnvironment.showsNetworkDiagnostics else { return }
        let persisted = SystemLogEntry(
            timestamp: entry.timestamp,
            tag: "IMAGE_CACHE",
            message: Self.sanitizedMessage(entry.logMessage)
        )
        Task {
            await AISPersistentDiagnosticsLog.shared.append(persisted)
        }
    }

    func record(
        startedAt: Date,
        request: URLRequest,
        statusCode: Int?,
        succeeded: Bool,
        message: String
    ) {
        let entry = NetworkDiagnosticEntry(
            timestamp: .now,
            method: request.httpMethod ?? "GET",
            path: Self.sanitizedPath(for: request.url),
            statusCode: statusCode,
            durationMilliseconds: max(
                0,
                Int(Date.now.timeIntervalSince(startedAt) * 1_000)
            ),
            succeeded: succeeded,
            message: Self.sanitizedMessage(message)
        )
        entries.insert(entry, at: 0)
        if entries.count > 200 {
            entries.removeLast(entries.count - 200)
        }

        recordSystemLog(
            tag: "NETWORK",
            "\(entry.method) \(entry.path) -> \(statusCode.map(String.init) ?? "ERR") (\(entry.durationMilliseconds)ms)"
        )
    }

    func clear() {
        entries.removeAll()
        systemLogs.removeAll()
        imageCacheEntries.removeAll()
        Task {
            await AISPersistentDiagnosticsLog.shared.clear()
        }
        recordSystemLog(tag: "SYSTEM", "Diagnostics log cleared by user.")
    }

    func generateLogFile() async -> URL? {
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileDateStr = timestampFormatter.string(from: Date.now)
        let fileName = "ais_diagnostics_\(fileDateStr).log"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let imageStatistics = await AISImageCache.shared.statistics()
        let responseByteCount = await AISResponseCache.shared.diskSize()
        let responseFileCount = await AISResponseCache.shared.fileCount()

        var content = ""
        content += "========================================================\n"
        content += "AIS SYSTEM & NETWORK DIAGNOSTICS REDACTED LOG FILE\n"
        content += "Generated At: \(Date.now.formatted(.iso8601))\n"
        content += "App Version: \(AppEnvironment.releaseLabel)\n"
        content += "API Target: \(AppEnvironment.current.apiBaseURL.absoluteString)\n"
        content += "OS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        content += "Device Family: iOS\n"
        content += "========================================================\n\n"

        content += "[SECTION 1: CACHE STATISTICS]\n"
        content += "Image Physical: \(imageStatistics.physicalByteCount) bytes / \(imageStatistics.fileCount) files\n"
        for item in imageStatistics.modules {
            content += "Image \(item.module.rawValue): \(item.byteCount) bytes / \(item.fileCount) files\n"
        }
        content += "API Responses: \(responseByteCount) bytes / \(responseFileCount) files\n"
        content += "Updated At: \(imageStatistics.updatedAt.formatted(.iso8601))\n\n"

        content += "[SECTION 2: SYSTEM EVENT LOGS (\(systemLogs.count) ENTRIES)]\n"
        for log in systemLogs.reversed() {
            let timeStr = log.timestamp.formatted(.iso8601)
            content += "[\(timeStr)] [\(log.tag)] \(log.message)\n"
        }
        content += "\n"

        let persistentLog = AISPersistentDiagnosticsLog.snapshotText()
        content += "[SECTION 3: PERSISTED REDACTED LOG (7 DAYS / 2 MB)]\n"
        content += persistentLog.isEmpty ? "No persisted entries.\n" : persistentLog
        content += "\n\n"

        content += "[SECTION 4: IMAGE CACHE EVENTS (\(imageCacheEntries.count) ENTRIES)]\n"
        for entry in imageCacheEntries.reversed() {
            content += "[\(entry.timestamp.formatted(.iso8601))] "
                + "[IMAGE_CACHE] \(entry.logMessage)\n"
        }
        content += "\n"

        content += "[SECTION 5: NETWORK REQUEST LOGS (\(entries.count) ENTRIES)]\n"
        for req in entries.reversed() {
            let timeStr = req.timestamp.formatted(.iso8601)
            let status = req.statusCode.map(String.init) ?? "NETWORK_ERR"
            content += "[\(timeStr)] [\(req.method)] \(req.path) | Status: \(status) | Duration: \(req.durationMilliseconds)ms\n"
            if !req.message.isEmpty {
                content += "   Detail: \(req.message)\n"
            }
        }

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    var exportText: String {
        let header = [
            "AIS \(AppEnvironment.releaseLabel)",
            "API \(AppEnvironment.current.apiBaseURL.absoluteString)",
            "System \(ProcessInfo.processInfo.operatingSystemVersionString)",
            ""
        ]
        return (header + entries.reversed().map(text(for:)))
            .joined(separator: "\n")
    }

    func text(for entry: NetworkDiagnosticEntry) -> String {
        let status = entry.statusCode.map(String.init) ?? "NETWORK"
        return "[\(entry.timestamp.formatted(.iso8601))] "
            + "\(entry.method) \(entry.path) · \(status) · "
            + "\(entry.durationMilliseconds)ms · \(entry.message)"
    }

    private static func sanitizedPath(for url: URL?) -> String {
        guard let url else { return "—" }
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = url.path
        return components.url?.absoluteString ?? url.path
    }

    static func sanitizedMessage(_ value: String) -> String {
        var result = value
        let replacements = [
            (
                #"(?i)Bearer\s+[A-Za-z0-9._~+\-/]+=*"#,
                "Bearer [REDACTED]"
            ),
            (
                #"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#,
                "[REDACTED_TOKEN]"
            ),
            (
                #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
                "[REDACTED_EMAIL]"
            )
        ]
        for (pattern, replacement) in replacements {
            guard let expression = try? NSRegularExpression(
                pattern: pattern
            ) else {
                continue
            }
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: replacement
            )
        }
        return String(result.prefix(1_000))
    }
}
