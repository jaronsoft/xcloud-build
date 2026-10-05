import CryptoKit
import Foundation
import UIKit

extension Notification.Name {
    static let pixaAvatarCacheDidChange = Notification.Name("PixaAvatarCacheDidChange")
}

actor PixaAvatarCache {
    static let shared = PixaAvatarCache()

    private let fileManager = FileManager.default

    private var directory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "PixaRivoAvatars", directoryHint: .isDirectory)
    }

    func image(userID: String, url: URL) async throws -> UIImage {
        let fileURL = fileURL(userID: userID)
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            return image
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 45
        )
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        request.setValue(PixaMediaRegion.headerValue, forHTTPHeaderField: "X-AIS-Media-Region")
        request.setValue(PixaMediaRegion.preferenceHeaderValue, forHTTPHeaderField: "X-AIS-Media-Region-Preference")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        try persist(data, at: fileURL)
        return image
    }

    func replace(data: Data, userID: String) async {
        guard UIImage(data: data) != nil else { return }
        try? persist(data, at: fileURL(userID: userID))
        await notify(userID: userID)
    }

    func remove(userID: String) async {
        try? fileManager.removeItem(at: fileURL(userID: userID))
        await notify(userID: userID)
    }

    private func persist(_ data: Data, at url: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var resourceURL = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(values)
        try data.write(to: url, options: .atomic)
    }

    private func fileURL(userID: String) -> URL {
        let digest = SHA256.hash(data: Data(userID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appending(path: "\(digest).avatar")
    }

    private func notify(userID: String) async {
        await MainActor.run {
            NotificationCenter.default.post(name: .pixaAvatarCacheDidChange, object: userID)
        }
    }
}
