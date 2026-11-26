import SwiftUI
import UIKit

struct NativeAppRelease: Identifiable {
    let version: String
    let build: String
    let notes: String
    let url: URL

    var id: String { "\(version)/\(build)" }
}

@MainActor
final class NativeAppReleases: ObservableObject {
    @Published private(set) var required: NativeAppRelease?
    @Published private(set) var optional: NativeAppRelease?
    @Published private(set) var checking = false
    @Published private(set) var initialCheckFinished = false
    @Published private(set) var manualMessage: String?
    @Published private(set) var checkError: String?
    private var deferredVersions: Set<String> = []
    private var manualRequested = false
    private var refreshRequested = false

    func check(api: MobileAPI, manually: Bool = false) {
        if manually {
            manualRequested = true
            manualMessage = nil
        }
        if checking {
            if !manually { refreshRequested = true }
            return
        }
        checking = true
        checkError = nil
        Task {
            defer {
                if !initialCheckFinished { initialCheckFinished = true }
                checking = false
                manualRequested = false
            }
            repeat {
                refreshRequested = false
                do {
                    try await fetchPolicy(api: api)
                } catch {
                    if !refreshRequested {
                        // 超时或无效回执保留本会话中已确认的强制升级状态。
                        let message = "暂时无法检查更新，请检查网络后重试。"
                        checkError = message
                        if manualRequested { manualMessage = message }
                    }
                }
            } while refreshRequested
        }
    }

    func deferOptional() {
        if let release = optional { deferredVersions.insert(release.id) }
        optional = nil
    }

    private func fetchPolicy(api: MobileAPI) async throws {
        let bundle = Bundle.main
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            throw MobileAPIError.unavailable("读取应用版本失败")
        }
        var endpoint = URLComponents()
        endpoint.path = "/api/JHCTIAppRelease/Check"
        endpoint.queryItems = [.init(name: "platform", value: "ios"), .init(name: "versionName", value: version),
                               .init(name: "buildNumber", value: build)]
        guard let path = endpoint.string,
              let response = try await api.get(path, timeoutInterval: 5) as? [String: Any],
              let status = (response["Status"] ?? response["status"]) as? String else {
            throw MobileAPIError.unavailable("版本检查响应无效")
        }

        // 返回前台后安排了复查，旧响应不再更新升级状态。
        guard !refreshRequested else { return }
        switch status {
        case "UpToDate":
            required = nil
            optional = nil
            if manualRequested { manualMessage = "已是最新版本" }
        case "UpdateAvailable", "UpdateRequired":
            guard let target = (response["Target"] ?? response["target"]) as? [String: Any],
                  let version = text(target, "VersionName", "versionName"),
                  let build = text(target, "BuildNumber", "buildNumber"),
                  let notes = text(target, "ReleaseNotesZh", "releaseNotesZh"),
                  let address = text(target, "UpdateUrl", "updateUrl"),
                  let url = URL(string: address), url.scheme == "https", url.host == "apps.apple.com",
                  url.user == nil, url.password == nil else {
                throw MobileAPIError.unavailable("更新版本响应无效")
            }
            let release = NativeAppRelease(version: version, build: build, notes: notes, url: url)
            if status == "UpdateRequired" {
                optional = nil
                required = release
            } else {
                let shouldOffer = manualRequested || !deferredVersions.contains(release.id) || optional?.id == release.id
                required = nil
                optional = shouldOffer ? release : nil
            }
        default:
            throw MobileAPIError.unavailable("更新状态无效")
        }
    }

    private func text(_ fields: [String: Any], _ pascal: String, _ camel: String) -> String? {
        guard let value = (fields[pascal] ?? fields[camel]) as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

struct NativeAppReleaseView: View {
    @EnvironmentObject private var releases: NativeAppReleases
    @State private var opening = false
    @State private var linkError = false
    let release: NativeAppRelease
    let required: Bool
    let secondaryAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(required ? "需要更新悦行江都" : "发现新版本")
                    .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("版本 \(release.version)").font(.headline)
                if required { Text("请更新到新版本后继续使用。").foregroundStyle(Brand.muted) }
                Text(release.notes).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                if linkError { Text("暂时无法打开 App Store，请稍后重试。").foregroundStyle(.red) }
                if required, let error = releases.checkError { Text(error).foregroundStyle(.red) }
                Button(opening ? "正在打开…" : "立即更新", action: openUpdate)
                    .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(opening)
                Button(required ? (releases.checking ? "正在检查…" : "重新检查") : "稍后更新", action: secondaryAction)
                    .buttonStyle(.bordered).tint(Brand.primary).disabled(required && releases.checking)
            }
            .padding(24).frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background.ignoresSafeArea())
        .foregroundStyle(Brand.ink)
        .onChange(of: release.id) { _, _ in linkError = false }
    }

    private func openUpdate() {
        opening = true
        linkError = false
        Task {
            linkError = !(await UIApplication.shared.open(release.url))
            opening = false
        }
    }
}
