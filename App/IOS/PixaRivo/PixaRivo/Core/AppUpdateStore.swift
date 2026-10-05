import Foundation
import Observation

private struct PixaAppReleaseCheckRequest: Encodable {
    let ProductKey: String
    let Platform: String
    let PackageName: String
    let Channel: String
    let VersionName: String
    let BuildNumber: String
    let Language: String
    let InstalledResources: [PixaInstalledAppResource]
}

private struct PixaInstalledAppResource: Encodable {
    let ResourceKey: String
    let Version: String
}

struct PixaAppReleaseCheckResponse: Decodable {
    let Status: String
    let CanRun: Bool
    let CurrentRelease: PixaAppReleaseSummary?
    let CheckedAt: String?
}

struct PixaAppReleaseSummary: Decodable {
    let VersionName: String
    let BuildNumber: String
    let ReleaseSequence: Int64
    let ReleaseNotesMarkdown: String?
    let StoreUrl: String?
}

@MainActor
@Observable
final class PixaAppUpdateStore {
    private static let lastCheckKey = "pixarivo.app_update.last_check"
    private static let acknowledgedReleaseKey = "pixarivo.app_update.acknowledged_release"
    private static let automaticCheckInterval: TimeInterval = 60 * 60

    private(set) var response: PixaAppReleaseCheckResponse?
    private(set) var isChecking = false
    private(set) var didFinishCheck = false
    private(set) var checkFailed = false
    private var acknowledgedReleaseIdentity: String?

    init() {
        acknowledgedReleaseIdentity = UserDefaults.standard.string(
            forKey: Self.acknowledgedReleaseKey
        )
    }

    var availableRelease: PixaAppReleaseSummary? {
        guard let response, let release = response.CurrentRelease else {
            return nil
        }
        if response.Status == "UpdateAvailable" || response.Status == "UpdateRequired" {
            return release
        }
        // 早期已发布版本可能尚未补录到发布中心，此时服务端返回 Unknown，客户端再按版本号兜底判断。
        if response.Status == "Unknown", Self.isNewerThanInstalled(release) {
            return release
        }
        return nil
    }

    var hasUnseenUpdate: Bool {
        guard let identity = availableReleaseIdentity else { return false }
        return acknowledgedReleaseIdentity != identity
    }

    var isUnavailable: Bool {
        if checkFailed { return true }
        guard didFinishCheck, let response else { return false }
        return response.Status == "Unknown" && response.CurrentRelease == nil
    }

    func check(force: Bool = false) async {
        guard !isChecking else { return }
        if !force,
           response != nil,
           let lastCheck = UserDefaults.standard.object(
               forKey: Self.lastCheckKey
           ) as? Date,
           Date.now.timeIntervalSince(lastCheck) < Self.automaticCheckInterval {
            return
        }

        isChecking = true
        checkFailed = false
        defer {
            isChecking = false
            didFinishCheck = true
        }

        do {
            let request = PixaAppReleaseCheckRequest(
                ProductKey: "com.wekarepartners.pixarivo",
                Platform: "ios",
                PackageName: Bundle.main.bundleIdentifier ?? "com.wekarepartners.pixarivo",
                Channel: "stable",
                VersionName: Self.currentVersion,
                BuildNumber: Self.currentBuild,
                Language: AppLanguage.apiValue,
                InstalledResources: []
            )
            let result: PixaAppReleaseCheckResponse = try await APIClient().post(
                "/api/AppRelease/Check",
                body: request
            )
            response = result
            UserDefaults.standard.set(Date.now, forKey: Self.lastCheckKey)
        } catch is CancellationError {
            return
        } catch {
            // 接口不存在或请求失败时清除旧结果，避免用过期状态继续显示更新红点。
            response = nil
            checkFailed = true
        }
    }

    func acknowledgeCurrentUpdate() {
        guard let identity = availableReleaseIdentity else { return }
        acknowledgedReleaseIdentity = identity
        UserDefaults.standard.set(identity, forKey: Self.acknowledgedReleaseKey)
    }

    static var currentVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
    }

    static var currentBuild: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
    }

    private var availableReleaseIdentity: String? {
        guard let release = availableRelease else { return nil }
        return "\(release.VersionName)|\(release.BuildNumber)|\(release.ReleaseSequence)"
    }

    private static func isNewerThanInstalled(_ release: PixaAppReleaseSummary) -> Bool {
        let versionComparison = release.VersionName.compare(
            currentVersion,
            options: .numeric
        )
        if versionComparison == .orderedDescending {
            return true
        }
        guard versionComparison == .orderedSame else { return false }
        return release.BuildNumber.compare(currentBuild, options: .numeric)
            == .orderedDescending
    }
}
