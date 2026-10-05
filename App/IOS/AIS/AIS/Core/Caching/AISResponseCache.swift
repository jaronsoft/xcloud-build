import CryptoKit
import Foundation

struct AISCacheRead<Value>: @unchecked Sendable {
    let value: Value
    let isFresh: Bool
}

actor AISResponseCache {
    static let shared = AISResponseCache()

    static let standardTTL: TimeInterval = 10 * 60

    private struct Envelope<Value: Codable>: Codable {
        let version: Int
        let savedAt: Date
        let value: Value
    }

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var cacheDirectory: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "AISResponses", directoryHint: .isDirectory)
    }

    func read<Value: Codable>(
        _ type: Value.Type,
        key: String,
        ttl: TimeInterval = standardTTL,
        allowsStale: Bool = false,
        encrypted: Bool = false
    ) -> AISCacheRead<Value>? {
        let url = fileURL(for: key)
        guard let storedData = try? Data(contentsOf: url),
              let data = decode(storedData, encrypted: encrypted),
              let envelope = try? decoder.decode(Envelope<Value>.self, from: data),
              envelope.version == 1 else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        let isFresh = Date.now.timeIntervalSince(envelope.savedAt) <= ttl
        guard isFresh || allowsStale else { return nil }
        return AISCacheRead(value: envelope.value, isFresh: isFresh)
    }

    func write<Value: Codable>(
        _ value: Value,
        key: String,
        encrypted: Bool = false
    ) {
        do {
            try fileManager.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var directory = cacheDirectory
            try? directory.setResourceValues(values)
            let plainData = try encoder.encode(
                Envelope(version: 1, savedAt: .now, value: value)
            )
            let data = try encode(plainData, encrypted: encrypted)
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            // 缓存失败不能阻断主流程，下一次继续读取网络数据。
        }
    }

    func remove(key: String) {
        try? fileManager.removeItem(at: fileURL(for: key))
    }

    func remove(scope: String) {
        let prefix = scopePrefix(scope)
        for url in cachedFiles() where url.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: url)
        }
    }

    func clear() {
        try? fileManager.removeItem(at: cacheDirectory)
    }

    func diskSize() -> Int64 {
        cachedFiles().reduce(0) { partialResult, url in
            let size = (try? url.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
            ))
            return partialResult + Int64(
                size?.totalFileAllocatedSize
                    ?? size?.fileAllocatedSize
                    ?? 0
            )
        }
    }

    func fileCount() -> Int {
        cachedFiles().count
    }

    nonisolated static func key(
        scope: String,
        resource: String,
        parameters: [String: String] = [:]
    ) -> String {
        var scopedParameters = parameters
        scopedParameters["mediaRegion"] = AISMediaRegionRequestContext.headerValue
        let normalized = scopedParameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(scope)|\(resource)|\(normalized)"
    }

    private func fileURL(for key: String) -> URL {
        let scope = key.split(separator: "|", maxSplits: 1).first.map(String.init)
            ?? "public"
        return cacheDirectory.appending(
            path: "\(scopePrefix(scope))-\(digest(key)).json"
        )
    }

    private func scopePrefix(_ scope: String) -> String {
        String(digest(scope).prefix(16))
    }

    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func cachedFiles() -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func encode(_ data: Data, encrypted: Bool) throws -> Data {
        guard encrypted else { return data }
        let keyData = try KeychainStore.loadOrCreateKey(
            account: "ais.response-cache.aes-gcm"
        )
        let sealed = try AES.GCM.seal(data, using: SymmetricKey(data: keyData))
        guard let combined = sealed.combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        return combined
    }

    private func decode(_ data: Data, encrypted: Bool) -> Data? {
        guard encrypted else { return data }
        do {
            let keyData = try KeychainStore.loadOrCreateKey(
                account: "ais.response-cache.aes-gcm"
            )
            let box = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(box, using: SymmetricKey(data: keyData))
        } catch {
            return nil
        }
    }
}
