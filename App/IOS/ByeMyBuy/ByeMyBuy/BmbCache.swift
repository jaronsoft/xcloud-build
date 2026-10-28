import CryptoKit
import SwiftUI
import UIKit

struct BmbDiagnosticEntry: Identifiable, Sendable {
    let id = UUID()
    let time = Date()
    let kind: String
    let summary: String
}

actor BmbDiagnostics {
    static let shared = BmbDiagnostics()
    private var entries: [BmbDiagnosticEntry] = []

    func record(_ kind: String, _ summary: String) {
        entries.insert(BmbDiagnosticEntry(kind: kind, summary: summary), at: 0)
        if entries.count > 150 { entries.removeLast(entries.count - 150) }
    }

    func snapshot() -> [BmbDiagnosticEntry] { entries }
    func clear() { entries.removeAll() }
}

actor BmbCache {
    static let shared = BmbCache()

    private let files = FileManager.default
    private var imageLoads: [String: Task<UIImage?, Never>] = [:]
    private let root: URL

    private init() {
        var cacheRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ByeMyBuyCache", isDirectory: true)
        root = cacheRoot
        try? files.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? cacheRoot.setResourceValues(values)
    }

    private func folder(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? files.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func file(_ key: String, in name: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder(name).appendingPathComponent(digest)
    }

    func data(for key: String) -> Data? { try? Data(contentsOf: file(key, in: "Data")) }
    func storeData(_ data: Data, for key: String) { try? data.write(to: file(key, in: "Data"), options: .atomic) }
    func image(for url: URL) -> UIImage? {
        if let cached = BmbImageMemoryCache.shared.image(for: url) { return cached }
        guard let data = try? Data(contentsOf: file(url.absoluteString, in: "Images")) else { return nil }
        guard let image = UIImage(data: data) else { return nil }
        BmbImageMemoryCache.shared.store(image, for: url)
        return image
    }
    func storeImage(_ data: Data, for url: URL) {
        guard let image = UIImage(data: data) else { return }
        BmbImageMemoryCache.shared.store(image, for: url)
        try? data.write(to: file(url.absoluteString, in: "Images"), options: .atomic)
    }

    func loadImage(original: URL, preset: BmbImagePreset) async -> UIImage? {
        let deliveryURL = BmbImageDelivery.resolve(original, preset: preset)
        if let cached = image(for: deliveryURL) {
            await BmbDiagnostics.shared.record("IMAGE", "cache · \(preset) · \(deliveryURL.host ?? "unknown")")
            return cached
        }
        if deliveryURL != original, let cached = image(for: original) {
            await BmbDiagnostics.shared.record("IMAGE", "cache · original fallback · \(original.host ?? "unknown")")
            return cached
        }
        let key = deliveryURL.absoluteString
        if let running = imageLoads[key] { return await running.value }
        // 下载任务独立于卡片生命周期，滑出屏幕时仍完成缓存写入。
        let task = Task<UIImage?, Never> {
            for candidate in deliveryURL == original ? [original] : [deliveryURL, original] {
                do {
                    var request = URLRequest(url: candidate)
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200,
                          let fresh = UIImage(data: data) else { continue }
                    storeImage(data, for: candidate)
                    await BmbDiagnostics.shared.record("IMAGE", "network · \(preset) · \(candidate == original && deliveryURL != original ? "original fallback" : "resized") · \(data.count) B · \(candidate.host ?? "unknown")")
                    return fresh
                } catch {
                    await BmbDiagnostics.shared.record("IMAGE", "failed · \(preset) · \(candidate.host ?? "unknown")")
                }
            }
            return nil
        }
        imageLoads[key] = task
        let result = await task.value
        imageLoads[key] = nil
        return result
    }

    func sizes() -> (data: Int64, images: Int64) {
        (size(of: "Data"), size(of: "Images"))
    }

    private func size(of name: String) -> Int64 {
        let path = folder(name)
        let urls = (try? files.contentsOfDirectory(at: path, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func clearData() { clear("Data") }
    func clearImages() { clear("Images") }
    private func clear(_ name: String) {
        if name == "Images" { BmbImageMemoryCache.shared.clear() }
        let path = folder(name)
        for url in (try? files.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)) ?? [] {
            try? files.removeItem(at: url)
        }
    }
}

private final class BmbImageMemoryCache: @unchecked Sendable {
    static let shared = BmbImageMemoryCache()
    private let images = NSCache<NSString, UIImage>()

    private init() { images.countLimit = 100 }

    func image(for url: URL) -> UIImage? { images.object(forKey: url.absoluteString as NSString) }
    func store(_ image: UIImage, for url: URL) { images.setObject(image, forKey: url.absoluteString as NSString) }
    func clear() { images.removeAllObjects() }
}

enum BmbImagePreset {
    case list, detail, thumbnail

    var cloudflareRule: String {
        switch self {
        case .list: "w600"
        case .detail: "detail1200"
        case .thumbnail: "w200"
        }
    }

    var tencentWidth: Int {
        switch self {
        case .list: 600
        case .detail: 1200
        case .thumbnail: 200
        }
    }
}

enum BmbImageDelivery {
    static func resolve(_ original: URL, preset: BmbImagePreset) -> URL {
        guard original.scheme?.lowercased() == "https",
              let host = original.host?.lowercased(),
              original.path.hasPrefix("/byemybuy/products/") || original.path.hasPrefix("/byemybuy/avatars/"),
              !original.absoluteString.contains("imageMogr2/"),
              !original.absoluteString.contains("imageView2/"),
              var components = URLComponents(url: original, resolvingAgainstBaseURL: false),
              (components.queryItems ?? []).allSatisfy({ $0.name == "v" || $0.name == "version" || $0.name == "preset" }),
              !(components.queryItems ?? []).contains(where: { $0.name == "preset" }) else { return original }
        if host == "www.get-free.net" || host == "get-free.net" {
            components.host = "cdn.get-free.net"
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "preset", value: preset.cloudflareRule)]
            return components.url ?? original
        }
        // 腾讯云只处理 ByeMyBuy 自有上传路径，其他外链保持原样。
        if !host.hasSuffix(".get-free.net") && host != "get-free.net" {
            return URL(string: original.absoluteString + (original.query == nil ? "?" : "&") + "imageMogr2/thumbnail/\(preset.tencentWidth)x") ?? original
        }
        return original
    }
}

struct BmbCachedImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: Placeholder
    let loadingLabel: LocalizedStringKey?
    let contentMode: ContentMode
    let onImageLoaded: ((CGSize) -> Void)?
    let preset: BmbImagePreset
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var requestedURL: URL?
    @State private var isVisible = false

    init(url: URL?, loadingLabel: LocalizedStringKey? = nil, contentMode: ContentMode = .fill,
         preset: BmbImagePreset = .detail,
         onImageLoaded: ((CGSize) -> Void)? = nil, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.loadingLabel = loadingLabel
        self.contentMode = contentMode
        self.preset = preset
        self.onImageLoaded = onImageLoaded
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode) }
            else if isLoading, let loadingLabel {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(loadingLabel).font(.caption).foregroundStyle(BmbTheme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { placeholder }
        }
        .onAppear {
            isVisible = true
            loadIfNeeded()
        }
        .onDisappear { isVisible = false }
        .onChange(of: url) { _, _ in
            image = nil
            requestedURL = nil
            if isVisible { loadIfNeeded() }
        }
    }

    private func loadIfNeeded() {
        guard let url, url.scheme == "https", requestedURL != url else { return }
        requestedURL = url
        let deliveryURL = BmbImageDelivery.resolve(url, preset: preset)
        if let cached = BmbImageMemoryCache.shared.image(for: deliveryURL)
            ?? BmbImageMemoryCache.shared.image(for: url) {
            image = cached
            onImageLoaded?(cached.size)
            return
        }
        isLoading = true
        Task {
            let loaded = await BmbCache.shared.loadImage(original: url, preset: preset)
            guard requestedURL == url else { return }
            image = loaded
            isLoading = false
            if let loaded { onImageLoaded?(loaded.size) }
            else { requestedURL = nil }
        }
    }
}
