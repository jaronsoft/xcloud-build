import Foundation
import CryptoKit
import UIKit

@MainActor
final class NativePublicCache {
    static let shared = NativePublicCache()
    private let files = FileManager.default
    private let memory = NSCache<NSString, UIImage>()
    private let root: URL
    private let dataTTL: TimeInterval = 5 * 60
    private let maxImageBytes = 12 * 1024 * 1024

    private init() {
        root = files.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JHCTIPublicCache", isDirectory: true)
        memory.totalCostLimit = 24 * 1024 * 1024
        try? files.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func file(_ key: String, in directory: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = root.appendingPathComponent(directory, isDirectory: true)
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name)
    }

    func publicData(for key: String, allowStale: Bool = false) -> Any? {
        let url = file(key, in: "data")
        guard let data = try? Data(contentsOf: url),
              let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              envelope["version"] as? Int == 1,
              let fetchedAt = envelope["fetchedAt"] as? TimeInterval,
              Date().timeIntervalSince1970 - fetchedAt >= 0,
              allowStale || Date().timeIntervalSince1970 - fetchedAt < dataTTL else { return nil }
        return envelope["value"]
    }

    func savePublicData(_ value: Any, for key: String) {
        let envelope: [String: Any] = ["version": 1, "fetchedAt": Date().timeIntervalSince1970, "value": value]
        guard JSONSerialization.isValidJSONObject(envelope),
              let data = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        try? data.write(to: file(key, in: "data"), options: .atomic)
        prune("data", maxFiles: 80, maxBytes: 12 * 1024 * 1024)
    }

    func thumbnail(for url: URL?, width: Int) async -> UIImage? {
        guard let url else { return nil }
        for candidate in nativeImageCandidates(url.absoluteString, width: width) {
            guard !Task.isCancelled else { return nil }
            let image = await image(for: URL(string: candidate))
            guard !Task.isCancelled else { return nil }
            if let image { return image }
        }
        return nil
    }

    func image(for url: URL?) async -> UIImage? {
        guard let url, url.scheme == "https" else { return nil }
        let key = url.absoluteString as NSString
        if let image = memory.object(forKey: key) { return image }
        let cachedFile = file(url.absoluteString, in: "images")
        if let data = try? Data(contentsOf: cachedFile), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key, cost: data.count)
            return image
        }
        try? files.removeItem(at: cachedFile)
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              !data.isEmpty, data.count <= maxImageBytes,
              let image = UIImage(data: data) else { return nil }
        try? data.write(to: cachedFile, options: .atomic)
        memory.setObject(image, forKey: key, cost: data.count)
        prune("images", maxFiles: 200, maxBytes: 60 * 1024 * 1024)
        return image
    }

    func sizeBytes() -> Int {
        let enumerator = files.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey])
        return (enumerator?.allObjects as? [URL] ?? []).reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func sizeBytes(in directory: String) -> Int {
        let folder = root.appendingPathComponent(directory, isDirectory: true)
        let enumerator = files.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        return (enumerator?.allObjects as? [URL] ?? []).reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func clearImages() {
        memory.removeAllObjects()
        clearDirectory("images")
    }

    func clearData() { clearDirectory("data") }

    private func clearDirectory(_ directory: String) {
        let folder = root.appendingPathComponent(directory, isDirectory: true)
        try? files.removeItem(at: folder)
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func clear() {
        memory.removeAllObjects()
        try? files.removeItem(at: root)
        try? files.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func prune(_ directory: String, maxFiles: Int, maxBytes: Int) {
        let folder = root.appendingPathComponent(directory, isDirectory: true)
        let urls = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        let ordered = urls.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) <
            ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        var bytes = ordered.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        var count = ordered.count
        for url in ordered where count > maxFiles || bytes > maxBytes {
            bytes -= (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            count -= 1
            try? files.removeItem(at: url)
        }
    }
}
