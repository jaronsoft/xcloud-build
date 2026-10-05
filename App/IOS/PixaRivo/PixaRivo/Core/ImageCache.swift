import CryptoKit
import Foundation
import UIKit

struct PixaImageCacheStatistics: Sendable {
    let physicalByteCount: Int64
    let fileCount: Int
    let updatedAt: Date
}

actor PixaImageCache {
    static let shared = PixaImageCache()

    private let fileManager = FileManager.default
    private let session: URLSession
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60
    private let maximumDiskSize: Int64 = 512 * 1_024 * 1_024
    private let targetDiskSize: Int64 = 384 * 1_024 * 1_024
    private var inFlightTasks: [String: Task<Data, Error>] = [:]

    private struct DiskEntry {
        let data: Data
        let isFresh: Bool
    }

    private var cacheDirectory: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "PixaRivoRemoteImages", directoryHint: .isDirectory)
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    func image(for request: PixaResolvedImageRequest) async throws -> UIImage {
        let startedAt = Date.now
        let data = try await data(for: request, startedAt: startedAt)
        guard let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
        return image
    }

    func image(
        for request: PixaResolvedImageRequest,
        fallback fallbackRequest: PixaResolvedImageRequest?
    ) async throws -> UIImage {
        do {
            return try await image(for: request)
        } catch {
            guard !Task.isCancelled,
                  let fallbackRequest,
                  fallbackRequest.url != request.url else { throw error }
            // CDN 图片处理规则偶发不可用时，仍可直接读取服务端返回的原始 HTTPS URL。
            return try await image(for: fallbackRequest)
        }
    }

    func statistics() -> PixaImageCacheStatistics {
        let files = cachedFiles()
        return PixaImageCacheStatistics(
            physicalByteCount: files.reduce(0) { $0 + allocatedSize(of: $1) },
            fileCount: files.count,
            updatedAt: .now
        )
    }

    func clear() throws {
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
        if fileManager.fileExists(atPath: cacheDirectory.path()) {
            try fileManager.removeItem(at: cacheDirectory)
        }
    }

    func data(for request: PixaResolvedImageRequest) async throws -> Data {
        try await data(for: request, startedAt: .now)
    }

    private func data(for request: PixaResolvedImageRequest, startedAt: Date) async throws -> Data {
        let key = "\(PixaMediaRegion.headerValue)|\(request.url.absoluteString)"
        let fileURL = cachedFileURL(for: request.url)
        if let cached = diskEntry(at: fileURL) {
            await record(
                request,
                source: cached.isFresh ? "disk" : "disk-stale",
                bytes: cached.data.count,
                startedAt: startedAt
            )
            if !cached.isFresh {
                // 过期图片仍先用于首屏，后台更新缓存，避免离线或弱网时出现空白卡片。
                Task { await refreshSilently(request, fileURL: fileURL, key: key) }
            }
            return cached.data
        }
        if let task = inFlightTasks[key] {
            let data = try await task.value
            await record(request, source: "in-flight", bytes: data.count, startedAt: startedAt)
            return data
        }
        let task = Task<Data, Error> {
            var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
            urlRequest.setValue("image/*", forHTTPHeaderField: "Accept")
            urlRequest.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
            urlRequest.setValue(PixaMediaRegion.headerValue, forHTTPHeaderField: "X-AIS-Media-Region")
            urlRequest.setValue(PixaMediaRegion.preferenceHeaderValue, forHTTPHeaderField: "X-AIS-Media-Region-Preference")
            let (data, response) = try await session.data(for: urlRequest)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  UIImage(data: data) != nil else { throw URLError(.cannotDecodeContentData) }
            return data
        }
        inFlightTasks[key] = task
        do {
            let data = try await task.value
            inFlightTasks[key] = nil
            try persist(data, at: fileURL)
            trimDiskCacheIfNeeded()
            await record(request, source: "network", bytes: data.count, startedAt: startedAt)
            return data
        } catch {
            inFlightTasks[key] = nil
            await record(request, source: "failed", bytes: 0, startedAt: startedAt)
            throw error
        }
    }

    private func diskEntry(at url: URL) -> DiskEntry? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = values.contentModificationDate,
              let data = try? Data(contentsOf: url),
              UIImage(data: data) != nil else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return DiskEntry(
            data: data,
            isFresh: Date.now.timeIntervalSince(date) <= maxAge
        )
    }

    private func refreshSilently(
        _ request: PixaResolvedImageRequest,
        fileURL: URL,
        key: String
    ) async {
        guard inFlightTasks[key] == nil else { return }
        let task = Task<Data, Error> {
            var urlRequest = URLRequest(
                url: request.url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 45
            )
            urlRequest.setValue("image/*", forHTTPHeaderField: "Accept")
            urlRequest.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
            urlRequest.setValue(
                PixaMediaRegion.headerValue,
                forHTTPHeaderField: "X-AIS-Media-Region"
            )
            urlRequest.setValue(
                PixaMediaRegion.preferenceHeaderValue,
                forHTTPHeaderField: "X-AIS-Media-Region-Preference"
            )
            let (data, response) = try await session.data(for: urlRequest)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  UIImage(data: data) != nil else {
                throw URLError(.cannotDecodeContentData)
            }
            return data
        }
        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        guard let data = try? await task.value else { return }
        try? persist(data, at: fileURL)
    }

    private func persist(_ data: Data, at url: URL) throws {
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func cachedFileURL(for url: URL) -> URL {
        // 同一资源地址在不同媒体区域可能返回不同 CDN 内容，缓存键必须隔离区域。
        let value = "\(PixaMediaRegion.headerValue)|\(url.absoluteString)"
        let digest = SHA256.hash(data: Data(value.utf8))
        return cacheDirectory.appending(path: digest.map { String(format: "%02x", $0) }.joined())
    }

    private func cachedFiles() -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func allocatedSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }

    private func trimDiskCacheIfNeeded() {
        let files = cachedFiles()
        var size = files.reduce(Int64.zero) { $0 + allocatedSize(of: $1) }
        guard size > maximumDiskSize else { return }
        let oldestFirst = files.sorted {
            let left = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let right = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (left ?? .distantPast) < (right ?? .distantPast)
        }
        for file in oldestFirst where size > targetDiskSize {
            let bytes = allocatedSize(of: file)
            try? fileManager.removeItem(at: file)
            size -= bytes
        }
    }

    private func record(_ request: PixaResolvedImageRequest, source: String, bytes: Int, startedAt: Date) async {
        await NetworkDiagnosticsStore.shared.recordImageCache(
            ImageCacheDiagnosticEntry(
                timestamp: .now,
                requestedPreset: request.requestedPreset.rawValue,
                appliedPreset: request.appliedPreset.rawValue,
                pixelWidth: request.pixelWidth,
                resourceKind: request.resourceKind,
                source: source,
                transformed: request.transformed,
                host: request.url.host ?? "unknown",
                path: request.url.path,
                byteCount: bytes,
                durationMilliseconds: max(0, Int(Date.now.timeIntervalSince(startedAt) * 1_000))
            )
        )
    }
}
