import CryptoKit
import Foundation
import Observation
import SwiftUI

struct AppReleaseCheckRequest: Encodable {
    let ProductKey: String
    let Platform: String
    let PackageName: String
    let Channel: String
    let VersionName: String
    let BuildNumber: String
    let InstalledResources: [InstalledAppResource]
}

struct InstalledAppResource: Codable {
    let ResourceKey: String
    let Version: String
}

struct AppReleaseCheckResponse: Codable {
    let Status: String
    let CanRun: Bool
    let IsTestVersion: Bool
    let ManifestRevision: Int64?
    let CurrentRelease: AppReleaseDescription?
    let Resources: [AppResourceDescription]
    let CheckedAt: Date?
}

struct AppReleaseDescription: Codable {
    let VersionName: String
    let BuildNumber: String
    let ReleaseSequence: Int64
    let IsTestVersion: Bool
    let ReleaseNotesMarkdown: String?
    let PublishedAt: Date?
    let StoreUrl: String?
    let Artifact: AppReleaseArtifact?
}

struct AppReleaseArtifact: Codable {
    let Id: String?
    let FileName: String
    let DownloadUrl: String
    let FileSize: Int64
    let Md5: String
    let Sha256: String
    let MimeType: String?
    let ArchiveFormat: String?
    let ApkEntryName: String?
}

struct AppResourceDescription: Codable, Identifiable {
    var id: String { ResourceKey }
    let ResourceKey: String
    let ResourceName: String
    let Version: String
    let Required: Bool
    let DeliveryMode: String
    let NetworkPolicy: String
    let NeedsUpdate: Bool
    let SortOrder: Int
    let Artifact: AppReleaseArtifact?
}

@MainActor
@Observable
final class AppReleaseStore {
    private let productKey: String
    private let checkPath: String
    private let cacheKey: String
    private let fileManager = FileManager.default
    private(set) var response: AppReleaseCheckResponse?
    private(set) var isChecking = true
    private(set) var requiredResourceError: String?
    var showsOptionalUpdate = false

    init(productKey: String, checkPath: String) {
        self.productKey = productKey
        self.checkPath = checkPath
        cacheKey = "AppRelease.Check.\(productKey)"
        activatePendingResources()
    }

    var blocksApplication: Bool {
        response?.CanRun == false || requiredResourceError != nil
    }

    func check(force: Bool = false) async {
        if !force,
           let lastCheck = UserDefaults.standard.object(
               forKey: "\(cacheKey).LastCheck"
           ) as? Date,
           Date.now.timeIntervalSince(lastCheck) < 3600 {
            return
        }

        isChecking = true
        requiredResourceError = nil
        do {
            let request = AppReleaseCheckRequest(
                ProductKey: productKey,
                Platform: "ios",
                PackageName: Bundle.main.bundleIdentifier ?? "",
                Channel: Self.releaseChannel,
                VersionName: Self.versionName,
                BuildNumber: Self.buildNumber,
                InstalledResources: installedResources()
            )
            let result: AppReleaseCheckResponse = try await APIClient().post(
                checkPath,
                body: request
            )
            response = result
            saveCached(result)
            UserDefaults.standard.set(Date.now, forKey: "\(cacheKey).LastCheck")
            showsOptionalUpdate = result.Status == "UpdateAvailable"
                && !isCurrentReleaseSkipped(result)
            if result.CanRun {
                await updateResources(result.Resources)
            }
        } catch let error as APIError {
            if case let .server(status, _) = error,
               status == 404 || status == 410 {
                // 服务迁移期间旧服务可能没有发布中心接口，此时应静默放行。
                clearCachedRule()
                UserDefaults.standard.set(
                    Date.now,
                    forKey: "\(cacheKey).LastCheck"
                )
            } else {
                response = loadCachedResponse()
                if response?.CanRun == true {
                    requiredResourceError = nil
                }
            }
        } catch {
            // 首次失败放行；只有与当前构建精确绑定的历史强制规则才继续拦截。
            response = loadCachedResponse()
            if response?.CanRun == true {
                requiredResourceError = nil
            }
        }
        isChecking = false
    }

    private func clearCachedRule() {
        response = nil
        showsOptionalUpdate = false
        requiredResourceError = nil
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: "\(cacheKey).Version")
        UserDefaults.standard.removeObject(forKey: "\(cacheKey).Build")
        UserDefaults.standard.removeObject(forKey: "\(cacheKey).Channel")
    }

    func skipCurrentRelease() {
        guard response?.Status == "UpdateAvailable",
              let release = response?.CurrentRelease else {
            return
        }
        UserDefaults.standard.set(
            "\(release.VersionName)|\(release.BuildNumber)|\(release.ReleaseSequence)",
            forKey: "\(cacheKey).Skipped.\(Self.releaseChannel)"
        )
        showsOptionalUpdate = false
    }

    private func isCurrentReleaseSkipped(
        _ value: AppReleaseCheckResponse
    ) -> Bool {
        guard let release = value.CurrentRelease else { return false }
        let identity =
            "\(release.VersionName)|\(release.BuildNumber)|\(release.ReleaseSequence)"
        return UserDefaults.standard.string(
            forKey: "\(cacheKey).Skipped.\(Self.releaseChannel)"
        ) == identity
    }

    func activeResourceURL(for key: String) -> URL? {
        let marker = resourcesRoot
            .appending(path: key, directoryHint: .isDirectory)
            .appending(path: "active.json")
        guard let data = try? Data(contentsOf: marker),
              let active = try? JSONDecoder().decode(
                  ActiveResource.self,
                  from: data
              ) else {
            return nil
        }
        return resourcesRoot
            .appending(path: key, directoryHint: .isDirectory)
            .appending(path: active.version, directoryHint: .isDirectory)
            .appending(path: active.fileName)
    }

    private func updateResources(_ resources: [AppResourceDescription]) async {
        for resource in resources where resource.NeedsUpdate {
            guard resource.DeliveryMode != "OnDemand" else { continue }
            // 当前会话继续使用旧资源，新资源只预下载并在下次冷启动时激活。
            try? await install(resource)
        }
    }

    private func install(_ resource: AppResourceDescription) async throws {
        guard let artifact = resource.Artifact,
              let url = URL(string: artifact.DownloadUrl) else {
            throw AppReleaseResourceError.invalidManifest
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        request.allowsCellularAccess = allowsCellular(
            policy: resource.NetworkPolicy,
            size: artifact.FileSize
        )
        let (temporaryURL, response) = try await URLSession.shared.download(
            for: request
        )
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw AppReleaseResourceError.downloadFailed
        }
        let digest = try sha256(of: temporaryURL)
        guard digest.caseInsensitiveCompare(artifact.Sha256) == .orderedSame else {
            throw AppReleaseResourceError.checksumMismatch
        }

        let resourceRoot = resourcesRoot.appending(
            path: resource.ResourceKey,
            directoryHint: .isDirectory
        )
        let versionRoot = resourceRoot.appending(
            path: resource.Version,
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: versionRoot,
            withIntermediateDirectories: true
        )
        let destination = versionRoot.appending(
            path: safeFileName(artifact.FileName)
        )
        if fileManager.fileExists(atPath: destination.path()) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        let marker = ActiveResource(
            version: resource.Version,
            fileName: destination.lastPathComponent
        )
        let markerData = try JSONEncoder().encode(marker)
        try markerData.write(
            to: resourceRoot.appending(path: "pending.json"),
            options: .atomic
        )
    }

    private func activatePendingResources() {
        guard let roots = try? fileManager.contentsOfDirectory(
            at: resourcesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for root in roots where root.hasDirectoryPath {
            let pending = root.appending(path: "pending.json")
            guard let data = try? Data(contentsOf: pending),
                  let marker = try? JSONDecoder().decode(
                      ActiveResource.self,
                      from: data
                  ) else {
                continue
            }
            let resource = root
                .appending(path: marker.version, directoryHint: .isDirectory)
                .appending(path: marker.fileName)
            guard fileManager.fileExists(atPath: resource.path()) else {
                try? fileManager.removeItem(at: pending)
                continue
            }
            try? data.write(
                to: root.appending(path: "active.json"),
                options: .atomic
            )
            try? fileManager.removeItem(at: pending)
            cleanupOldVersions(in: root, keeping: marker.version)
        }
    }

    private func installedResources() -> [InstalledAppResource] {
        guard let keys = try? fileManager.contentsOfDirectory(
            at: resourcesRoot,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return keys.compactMap { directory in
            let marker = directory.appending(path: "active.json")
            guard let data = try? Data(contentsOf: marker),
                  let active = try? JSONDecoder().decode(
                      ActiveResource.self,
                      from: data
                  ) else {
                return nil
            }
            return InstalledAppResource(
                ResourceKey: directory.lastPathComponent,
                Version: active.version
            )
        }
    }

    private func cleanupOldVersions(in root: URL, keeping version: String) {
        guard var directories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter({ $0.hasDirectoryPath && $0.lastPathComponent != version })
        else {
            return
        }
        directories.sort {
            let left = try? $0.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            let right = try? $1.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            return (left ?? .distantPast) > (right ?? .distantPast)
        }
        for directory in directories.dropFirst() {
            try? fileManager.removeItem(at: directory)
        }
    }

    private func saveCached(_ value: AppReleaseCheckResponse) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Self.versionName, forKey: "\(cacheKey).Version")
        UserDefaults.standard.set(Self.buildNumber, forKey: "\(cacheKey).Build")
        UserDefaults.standard.set(Self.releaseChannel, forKey: "\(cacheKey).Channel")
    }

    private func loadCachedResponse() -> AppReleaseCheckResponse? {
        guard UserDefaults.standard.string(forKey: "\(cacheKey).Version")
                == Self.versionName,
              UserDefaults.standard.string(forKey: "\(cacheKey).Build")
                == Self.buildNumber,
              UserDefaults.standard.string(forKey: "\(cacheKey).Channel")
                == Self.releaseChannel,
              let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }
        return try? JSONDecoder().decode(
            AppReleaseCheckResponse.self,
            from: data
        )
    }

    private func allowsCellular(policy: String, size: Int64) -> Bool {
        switch policy {
        case "WifiOnly": false
        case "AnyNetwork": true
        default: size <= 20 * 1024 * 1024
        }
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func safeFileName(_ value: String) -> String {
        let name = URL(fileURLWithPath: value).lastPathComponent
        return name.isEmpty ? "resource.data" : name
    }

    private var resourcesRoot: URL {
        let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let root = support.appending(
            path: "AppReleaseResources",
            directoryHint: .isDirectory
        )
        try? fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private static var versionName: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
    }

    private static var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "0"
    }

    private static var releaseChannel: String {
        if let configured = Bundle.main.object(
            forInfoDictionaryKey: "AppReleaseChannel"
        ) as? String, configured.lowercased() == "test" {
            return "test"
        }
#if DEBUG
        return "test"
#else
        return "stable"
#endif
    }
}

struct AppReleaseGate: View {
    @Bindable var store: AppReleaseStore
    let content: AnyView
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            content
            if store.blocksApplication {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                    Text("release.update_required")
                        .font(.title2.bold())
                    if let release = store.response?.CurrentRelease {
                        Text(
                            String(
                                format: String(localized: "release.current_version"),
                                release.VersionName
                            )
                        )
                        .foregroundStyle(.secondary)
                        releaseNotes(release.ReleaseNotesMarkdown)
                    }
                    if let error = store.requiredResourceError {
                        Text(error)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    if let value = store.response?.CurrentRelease?.StoreUrl,
                       let url = URL(string: value) {
                        Button("release.open_app_store") {
                            openURL(url)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("release.retry") {
                        Task { await store.check(force: true) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(28)
            }
        }
        .sheet(isPresented: $store.showsOptionalUpdate) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("release.update_available").font(.title2.bold())
                    if let release = store.response?.CurrentRelease {
                        Text(
                            String(
                                format: String(localized: "release.current_version"),
                                release.VersionName
                            )
                        )
                        releaseNotes(release.ReleaseNotesMarkdown)
                        if let value = release.StoreUrl,
                           let url = URL(string: value) {
                            Button("release.update_now") { openURL(url) }
                                .buttonStyle(.borderedProminent)
                        }
                        Button("release.skip_version") {
                            store.skipCurrentRelease()
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                }
                .padding()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("release.remind_later") {
                            store.showsOptionalUpdate = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func releaseNotes(_ markdown: String?) -> some View {
        if let markdown, !markdown.isEmpty {
            ScrollView {
                Text((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ActiveResource: Codable {
    let version: String
    let fileName: String
}

private enum AppReleaseResourceError: LocalizedError {
    case invalidManifest
    case downloadFailed
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidManifest: String(localized: "release.resource_invalid")
        case .downloadFailed: String(localized: "release.resource_download_failed")
        case .checksumMismatch: String(localized: "release.resource_checksum_failed")
        }
    }
}
