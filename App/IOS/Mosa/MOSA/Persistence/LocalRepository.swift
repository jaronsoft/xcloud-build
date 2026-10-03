import CryptoKit
import Foundation

struct LocalRepositoryError: LocalizedError {
    enum Operation {
        case read
        case write
        case delete
    }

    let operation: Operation
    let file: String
    let underlyingError: Error

    var errorDescription: String? {
        switch operation {
        case .read:
            return "MOSA could not read your saved records on this iPhone. The original file was kept unchanged."
        case .write:
            return "MOSA could not save this record on this iPhone. Your changes are still here. Check available storage and try again."
        case .delete:
            return "Your cloud account was deleted, but MOSA could not remove all local files. Delete and reinstall the app before using this device again."
        }
    }
}

@MainActor
final class LocalRepository {
    private struct ShareCardCacheMetadata: Codable {
        let sourceKey: String
    }

    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = root.appendingPathComponent("MOSA", isDirectory: true)
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadProfile() -> LocalProfile? {
        try? load(LocalProfile.self, from: "profile.json")
    }

    func saveProfile(_ profile: LocalProfile?) {
        try? save(profile, to: "profile.json")
    }

    func loadRecords() throws -> [LocalRecord] {
        try load([LocalRecord].self, from: "records.json") ?? []
    }

    func saveRecords(_ records: [LocalRecord]) throws {
        try save(records, to: "records.json")
    }

    func loadLifeStages() -> [LocalLifeStage] {
        (try? load([LocalLifeStage].self, from: "life-stages.json")) ?? []
    }

    func saveLifeStages(_ stages: [LocalLifeStage]) {
        try? save(stages, to: "life-stages.json")
    }

    func loadAnnualWorks() -> [LocalAnnualWork] {
        (try? load([LocalAnnualWork].self, from: "annual-works.json")) ?? []
    }

    func saveAnnualWorks(_ works: [LocalAnnualWork]) {
        try? save(works, to: "annual-works.json")
    }

    /// 账户删除成功后移除整个 MOSA 应用数据目录，避免遗漏图片缓存或后续新增的本地文件。
    func deleteAllData() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    /// 分享卡按登录账号隔离，避免同一台设备切换账号时展示另一位用户的私密图片。
    func loadShareCardImage(year: Int, account: String) -> Data? {
        let imageURL = shareCardCacheDirectory(account: account)
            .appendingPathComponent("\(year).png")
        return try? Data(contentsOf: imageURL)
    }

    func hasCurrentShareCardImage(year: Int, account: String, sourceKey: String) -> Bool {
        let directory = shareCardCacheDirectory(account: account)
        let imageURL = directory.appendingPathComponent("\(year).png")
        let metadataURL = directory.appendingPathComponent("\(year).json")
        guard fileManager.fileExists(atPath: imageURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? decoder.decode(ShareCardCacheMetadata.self, from: data) else {
            return false
        }
        return metadata.sourceKey == sourceKey
    }

    /// 先完成图片原子写入，再更新版本标记；下载或写入失败时旧缓存始终可继续使用。
    func saveShareCardImage(_ imageData: Data, year: Int, account: String, sourceKey: String) throws {
        let directory = shareCardCacheDirectory(account: account)
        let imageURL = directory.appendingPathComponent("\(year).png")
        let metadataURL = directory.appendingPathComponent("\(year).json")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try imageData.write(to: imageURL, options: [.atomic, .completeFileProtection])
            let metadata = try encoder.encode(ShareCardCacheMetadata(sourceKey: sourceKey))
            try metadata.write(to: metadataURL, options: [.atomic, .completeFileProtection])
        } catch {
            throw LocalRepositoryError(operation: .write, file: imageURL.lastPathComponent, underlyingError: error)
        }
    }

    private func shareCardCacheDirectory(account: String) -> URL {
        // 以账号摘要作为目录名，防止私密分享卡在文件系统中暴露账号标识。
        let identifier = SHA256.hash(data: Data(account.lowercased().utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory
            .appendingPathComponent("share-card-cache", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
    }

    private func load<Value: Decodable>(_ type: Value.Type, from file: String) throws -> Value? {
        let url = directory.appendingPathComponent(file)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(type, from: data)
        } catch {
            throw LocalRepositoryError(operation: .read, file: file, underlyingError: error)
        }
    }

    private func save<Value: Encodable>(_ value: Value?, to file: String) throws {
        let url = directory.appendingPathComponent(file)
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            guard let value else {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
                return
            }
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            throw LocalRepositoryError(operation: .write, file: file, underlyingError: error)
        }
    }
}
