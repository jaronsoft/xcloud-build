import CryptoKit
import Foundation
import SwiftUI
import UIKit

enum AISImageCacheModule: String, Codable, CaseIterable, Identifiable, Sendable {
    case tasks
    case galleryTemplates
    case projectsAssets
    case other

    var id: String { rawValue }
}

enum AISImageRequestBuilder {
    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 45
        )
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        if url.host?.caseInsensitiveCompare(
            AppEnvironment.current.apiBaseURL.host ?? ""
        ) == .orderedSame {
            request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
            request.setValue(
                AISMediaRegionRequestContext.headerValue,
                forHTTPHeaderField: "X-AIS-Media-Region"
            )
        }
        return request
    }
}

struct AISCacheModuleStatistics: Identifiable, Sendable {
    let module: AISImageCacheModule
    let byteCount: Int64
    let fileCount: Int

    var id: AISImageCacheModule { module }
}

struct AISImageCacheStatistics: Sendable {
    let modules: [AISCacheModuleStatistics]
    let physicalByteCount: Int64
    let fileCount: Int
    let updatedAt: Date
}

actor AISImageCache {
    static let shared = AISImageCache()

    private let memoryCache = NSCache<NSString, NSData>()
    private let imageMemoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let directoryOverride: URL?
    private let session: URLSession
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60
    private let maximumDiskSize: Int64 = 512 * 1_024 * 1_024
    private let targetDiskSize: Int64 = 384 * 1_024 * 1_024
    private var inFlightTasks: [String: Task<Data, Error>] = [:]
    private var manifest: [String: CacheMetadata]?

    private struct CacheMetadata: Codable {
        var modules: Set<AISImageCacheModule>
        var presets: Set<String>
        var byteCount: Int64
        var lastAccessedAt: Date
    }

    private var cacheDirectory: URL {
        directoryOverride ?? fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        .appending(path: "AISRemoteImages", directoryHint: .isDirectory)
    }

    init(
        cacheDirectory: URL? = nil,
        session: URLSession = .shared
    ) {
        directoryOverride = cacheDirectory
        self.session = session
        imageMemoryCache.totalCostLimit = 128 * 1_024 * 1_024
    }

    private var manifestURL: URL {
        cacheDirectory.appending(path: "manifest.json")
    }

    func data(
        for url: URL,
        module: AISImageCacheModule = .other,
        preset: AISImagePreset = .original,
        request: AISResolvedImageRequest? = nil
    ) async throws -> Data {
        let resolvedRequest = request
            ?? AISImageURLBuilder.resolve(from: url, preset: preset)
        let startedAt = Date.now
        let cacheKey = cacheKey(for: url)
        let fileURL = cachedFileURL(for: url)
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            updateMetadata(
                filename: fileURL.lastPathComponent,
                module: module,
                preset: resolvedRequest?.appliedPreset ?? preset,
                byteCount: Int64(cached.length)
            )
            await record(
                url: url,
                module: module,
                request: resolvedRequest,
                source: "memory-data",
                bytes: cached.length,
                startedAt: startedAt
            )
            return cached as Data
        }

        let existedOnDisk = fileManager.fileExists(atPath: fileURL.path())
        if let data = validDiskData(at: fileURL) {
            memoryCache.setObject(data as NSData, forKey: cacheKey as NSString)
            updateMetadata(
                filename: fileURL.lastPathComponent,
                module: module,
                preset: resolvedRequest?.appliedPreset ?? preset,
                byteCount: Int64(data.count)
            )
            await record(
                url: url,
                module: module,
                request: resolvedRequest,
                source: "disk",
                bytes: data.count,
                startedAt: startedAt
            )
            return data
        }
        if existedOnDisk {
            removeMetadata(filename: fileURL.lastPathComponent)
            await record(
                url: url,
                module: module,
                request: resolvedRequest,
                source: "expired",
                bytes: 0,
                startedAt: startedAt
            )
        }

        if let task = inFlightTasks[cacheKey] {
            let data = try await task.value
            updateMetadata(
                filename: fileURL.lastPathComponent,
                module: module,
                preset: resolvedRequest?.appliedPreset ?? preset,
                byteCount: Int64(data.count)
            )
            await record(
                url: url,
                module: module,
                request: resolvedRequest,
                source: "in-flight",
                bytes: data.count,
                startedAt: startedAt
            )
            return data
        }

        let task = Task<Data, Error> {
            let request = AISImageRequestBuilder.request(for: url)
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  UIImage(data: data) != nil else {
                throw URLError(.cannotDecodeContentData)
            }
            return data
        }
        inFlightTasks[cacheKey] = task

        do {
            let data = try await task.value
            inFlightTasks[cacheKey] = nil
            try persist(data, at: fileURL)
            memoryCache.setObject(data as NSData, forKey: cacheKey as NSString)
            updateMetadata(
                filename: fileURL.lastPathComponent,
                module: module,
                preset: resolvedRequest?.appliedPreset ?? preset,
                byteCount: Int64(data.count)
            )
            await trimDiskCacheIfNeeded()
            await record(
                url: url,
                module: module,
                request: resolvedRequest,
                source: "network",
                bytes: data.count,
                startedAt: startedAt
            )
            return data
        } catch {
            inFlightTasks[cacheKey] = nil
            await record(
                url: url,
                module: module,
                request: resolvedRequest,
                source: AISErrorClassifier.isCancellation(error)
                    ? "cancelled"
                    : "failed",
                bytes: 0,
                startedAt: startedAt
            )
            throw error
        }
    }

    func image(
        for url: URL,
        module: AISImageCacheModule = .other,
        preset: AISImagePreset = .original,
        request: AISResolvedImageRequest? = nil
    ) async throws -> UIImage {
        let resolvedRequest = request
            ?? AISImageURLBuilder.resolve(from: url, preset: preset)
        let startedAt = Date.now
        let cacheKey = cacheKey(for: url)
        if let image = imageMemoryCache.object(forKey: cacheKey as NSString) {
            let fileURL = cachedFileURL(for: url)
            let byteCount = max(
                Int64(image.memoryCost),
                allocatedSize(of: fileURL)
            )
            updateMetadata(
                filename: fileURL.lastPathComponent,
                module: module,
                preset: resolvedRequest?.appliedPreset ?? preset,
                byteCount: byteCount
            )
            await record(
                url: url,
                module: module,
                request: resolvedRequest,
                source: "memory-image",
                bytes: image.memoryCost,
                startedAt: startedAt
            )
            return image
        }
        let data = try await data(
            for: url,
            module: module,
            preset: preset,
            request: resolvedRequest
        )
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        imageMemoryCache.setObject(
            image,
            forKey: cacheKey as NSString,
            cost: image.memoryCost
        )
        return image
    }

    func diskSize() -> Int64 {
        cachedFiles().reduce(0) { partialResult, fileURL in
            partialResult + allocatedSize(of: fileURL)
        }
    }

    func statistics() -> AISImageCacheStatistics {
        let files = cachedFiles()
        let metadata = loadManifest()
        var moduleSizes: [AISImageCacheModule: Int64] = [:]
        var moduleCounts: [AISImageCacheModule: Int] = [:]
        var total: Int64 = 0

        for fileURL in files {
            let size = allocatedSize(of: fileURL)
            total += size
            let modules = metadata[fileURL.lastPathComponent]?.modules
                ?? [.other]
            for module in modules {
                moduleSizes[module, default: 0] += size
                moduleCounts[module, default: 0] += 1
            }
        }

        return AISImageCacheStatistics(
            modules: AISImageCacheModule.allCases.map {
                AISCacheModuleStatistics(
                    module: $0,
                    byteCount: moduleSizes[$0, default: 0],
                    fileCount: moduleCounts[$0, default: 0]
                )
            },
            physicalByteCount: total,
            fileCount: files.count,
            updatedAt: .now
        )
    }

    func clear(module: AISImageCacheModule) async {
        imageMemoryCache.removeAllObjects()
        memoryCache.removeAllObjects()
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
        var metadata = loadManifest()
        for fileURL in cachedFiles() {
            let filename = fileURL.lastPathComponent
            var item = metadata[filename] ?? CacheMetadata(
                modules: [.other],
                presets: [],
                byteCount: allocatedSize(of: fileURL),
                lastAccessedAt: .distantPast
            )
            guard item.modules.contains(module) else { continue }
            item.modules.remove(module)
            if item.modules.isEmpty {
                try? fileManager.removeItem(at: fileURL)
                metadata[filename] = nil
            } else {
                metadata[filename] = item
            }
        }
        manifest = metadata
        saveManifest()
        await NetworkDiagnosticsStore.shared.recordSystemLog(
            tag: "CACHE",
            "Cleared image cache module=\(module.rawValue)."
        )
    }

    func clear() throws {
        memoryCache.removeAllObjects()
        imageMemoryCache.removeAllObjects()
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
        URLCache.shared.removeAllCachedResponses()
        guard fileManager.fileExists(atPath: cacheDirectory.path()) else {
            return
        }
        try fileManager.removeItem(at: cacheDirectory)
        manifest = [:]
    }

    private func validDiskData(at fileURL: URL) -> Data? {
        guard let values = try? fileURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ),
        let modificationDate = values.contentModificationDate,
        Date.now.timeIntervalSince(modificationDate) <= maxAge,
        let data = try? Data(contentsOf: fileURL),
        UIImage(data: data) != nil else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        return data
    }

    private func persist(_ data: Data, at fileURL: URL) throws {
        try fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private func cachedFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(cacheKey(for: url).utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appending(path: filename)
    }

    private nonisolated func cacheKey(for url: URL) -> String {
        "\(AISMediaRegionRequestContext.headerValue)|\(url.absoluteString)"
    }

    private func cachedFiles() -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey
            ],
            options: [.skipsHiddenFiles]
        ))?.filter { $0.lastPathComponent != manifestURL.lastPathComponent }
            ?? []
    }

    private func allocatedSize(of fileURL: URL) -> Int64 {
        guard let values = try? fileURL.resourceValues(
            forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        ) else {
            return 0
        }
        return Int64(
            values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? 0
        )
    }

    private func trimDiskCacheIfNeeded() async {
        let files = cachedFiles()
        var currentSize = files.reduce(Int64.zero) {
            $0 + allocatedSize(of: $1)
        }
        guard currentSize > maximumDiskSize else { return }
        var removedFileCount = 0
        var removedByteCount: Int64 = 0

        let oldestFirst = files.sorted {
            let left = try? $0.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            let right = try? $1.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            return (left ?? .distantPast) < (right ?? .distantPast)
        }
        for fileURL in oldestFirst where currentSize > targetDiskSize {
            let size = allocatedSize(of: fileURL)
            try? fileManager.removeItem(at: fileURL)
            removeMetadata(filename: fileURL.lastPathComponent)
            currentSize -= size
            removedFileCount += 1
            removedByteCount += size
        }
        saveManifest()
        await NetworkDiagnosticsStore.shared.recordSystemLog(
            tag: "CACHE",
            "Trimmed image cache files=\(removedFileCount) "
                + "bytes=\(removedByteCount) remaining=\(currentSize)."
        )
    }

    private func loadManifest() -> [String: CacheMetadata] {
        if let manifest { return manifest }
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode(
                  [String: CacheMetadata].self,
                  from: data
              ) else {
            manifest = [:]
            return [:]
        }
        manifest = decoded
        return decoded
    }

    private func updateMetadata(
        filename: String,
        module: AISImageCacheModule,
        preset: AISImagePreset,
        byteCount: Int64
    ) {
        var values = loadManifest()
        var item = values[filename] ?? CacheMetadata(
            modules: [],
            presets: [],
            byteCount: byteCount,
            lastAccessedAt: .now
        )
        let insertedModule = item.modules.insert(module).inserted
        let insertedPreset = item.presets.insert(preset.rawValue).inserted
        item.byteCount = byteCount
        item.lastAccessedAt = .now
        values[filename] = item
        manifest = values
        if insertedModule || insertedPreset {
            saveManifest()
        }
    }

    private func removeMetadata(filename: String) {
        var values = loadManifest()
        values[filename] = nil
        manifest = values
    }

    private func saveManifest() {
        guard let manifest,
              let data = try? JSONEncoder().encode(manifest) else {
            return
        }
        try? fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func record(
        url: URL,
        module: AISImageCacheModule,
        request: AISResolvedImageRequest?,
        source: String,
        bytes: Int,
        startedAt: Date
    ) async {
        guard AppEnvironment.showsNetworkDiagnostics else { return }
        let digest = SHA256.hash(data: Data(cacheKey(for: url).utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
        let resolvedRequest = request
            ?? AISImageURLBuilder.resolve(from: url, preset: .original)
        let duration = max(
            0,
            Int(Date.now.timeIntervalSince(startedAt) * 1_000)
        )
        await NetworkDiagnosticsStore.shared.recordImageCache(
            ImageCacheDiagnosticEntry(
                timestamp: .now,
                module: module,
                requestedPreset: resolvedRequest?.requestedPreset.rawValue
                    ?? "unknown",
                appliedPreset: resolvedRequest?.appliedPreset.rawValue
                    ?? "unknown",
                pixelWidth: resolvedRequest?.pixelWidth,
                resourceKind: resolvedRequest?.resourceKind ?? .original,
                source: source,
                transformed: resolvedRequest?.transformed ?? false,
                host: url.host ?? "unknown",
                path: url.path,
                cacheKey: digest,
                byteCount: bytes,
                durationMilliseconds: duration
            )
        )
    }
}

struct AISCachedAsyncImage<Content: View>: View {
    let originalURL: URL?
    let preset: AISImagePreset
    let module: AISImageCacheModule
    let content: (AsyncImagePhase) -> Content

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var renderedWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    init(
        url: URL?,
        preset: AISImagePreset = .detail,
        module: AISImageCacheModule = .other,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        originalURL = url
        self.preset = preset
        self.module = module
        self.content = content
    }

    private var usesAdaptiveWidth: Bool {
        preset == .list || preset == .largeList || preset == .thumbnail
    }

    private var request: AISResolvedImageRequest? {
        let targetPixelWidth = usesAdaptiveWidth && renderedWidth > 0
            ? Int(ceil(renderedWidth * displayScale))
            : nil
        return AISImageURLBuilder.resolve(
            from: originalURL,
            preset: preset,
            targetPixelWidth: targetPixelWidth,
            maximumPixelWidth: AISImageURLBuilder
                .maximumAdaptivePixelWidth(for: preset)
        )
    }

    var body: some View {
        content(phase)
            .onAISContentWidthChange { width in
                guard abs(renderedWidth - width) > 1 else { return }
                renderedWidth = width
            }
            .task(id: request?.url) {
                await load()
            }
    }

    private var phase: AsyncImagePhase {
        if let image {
            return .success(Image(uiImage: image))
        }
        if didFail || (!usesAdaptiveWidth && request == nil) {
            return .failure(URLError(.badURL))
        }
        return .empty
    }

    private func load() async {
        image = nil
        didFail = false
        guard let request else {
            if !usesAdaptiveWidth {
                didFail = true
            }
            return
        }

        do {
            let loadedImage = try await AISImageCache.shared.image(
                for: request.url,
                module: module,
                preset: preset,
                request: request
            )
            guard !Task.isCancelled else {
                return
            }
            image = loadedImage
        } catch {
            guard !Task.isCancelled else { return }
            didFail = true
        }
    }
}

private extension UIImage {
    var memoryCost: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
