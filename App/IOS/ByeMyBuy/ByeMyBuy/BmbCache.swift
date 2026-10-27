import CryptoKit
import SwiftUI
import UIKit

actor BmbCache {
    static let shared = BmbCache()

    private let files = FileManager.default
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
        guard let data = try? Data(contentsOf: file(url.absoluteString, in: "Images")) else { return nil }
        return UIImage(data: data)
    }
    func storeImage(_ data: Data, for url: URL) {
        guard UIImage(data: data) != nil else { return }
        try? data.write(to: file(url.absoluteString, in: "Images"), options: .atomic)
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
        let path = folder(name)
        for url in (try? files.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)) ?? [] {
            try? files.removeItem(at: url)
        }
    }
}

struct BmbCachedImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: Placeholder
    @State private var image: UIImage?

    init(url: URL?, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { placeholder }
        }
        .task(id: url) {
            image = nil
            guard let url, url.scheme == "https" else { return }
            image = await BmbCache.shared.image(for: url)
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let fresh = UIImage(data: data) else { return }
                await BmbCache.shared.storeImage(data, for: url)
                image = fresh
            } catch { }
        }
    }
}
