import CryptoKit
import Foundation

actor PixaResponseCache {
    static let shared = PixaResponseCache()

    private struct Envelope: Codable {
        let version: Int
        let savedAt: Date
        let data: Data
    }

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var cacheDirectory: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "PixaRivoResponses", directoryHint: .isDirectory)
    }

    func read(key: String) -> Data? {
        let url = fileURL(for: key)
        guard let stored = try? Data(contentsOf: url),
              let envelope = try? decoder.decode(Envelope.self, from: stored),
              envelope.version == 1 else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return envelope.data
    }

    func write(_ data: Data, key: String) {
        do {
            try fileManager.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            var directory = cacheDirectory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
            let stored = try encoder.encode(
                Envelope(version: 1, savedAt: .now, data: data)
            )
            try stored.write(to: fileURL(for: key), options: .atomic)
        } catch {
            // 缓存写入失败不能影响页面正常使用，后续请求仍可继续尝试。
        }
    }

    func clear() {
        if fileManager.fileExists(atPath: cacheDirectory.path()) {
            try? fileManager.removeItem(at: cacheDirectory)
        }
    }

    func statistics() -> (byteCount: Int64, fileCount: Int) {
        let files = (try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let bytes = files.reduce(Int64.zero) { result, url in
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            return result + Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return (bytes, files.count)
    }

    nonisolated static func key(
        path: String,
        query: [URLQueryItem],
        scope: String? = nil
    ) -> String {
        let parameters = query
            .map { "\($0.name)=\($0.value ?? "")" }
            .sorted()
            .joined(separator: "&")
        return [
            path,
            parameters,
            scope ?? "public",
            AppLanguage.apiValue,
            PixaMediaRegion.headerValue
        ].joined(separator: "|")
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDirectory.appending(path: "\(digest).json")
    }
}
