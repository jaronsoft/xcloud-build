import AuthenticationServices
import CryptoKit
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UserNotifications
import UniformTypeIdentifiers
import Vision

private enum DineWiseImageRecognitionError: LocalizedError {
    case invalidImage
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: "所选文件不是可读取的图片，请重新选择或手动录入。"
        case .recognitionFailed: "本机文字识别未完成，请重试或手动录入。"
        }
    }
}

private struct PendingDineWiseRecognitionImage {
    let submissionID: String
    let fileName: String
    let data: Data
    let retryKey: DineWiseSubmissionRetryKey
}

private func dineWiseTextPrefix(_ text: String, maximumUTF16Length: Int) -> (value: String, truncated: Bool) {
    var value = ""
    var remaining = max(0, maximumUTF16Length)
    for character in text {
        let units = String(character).utf16.count
        guard units <= remaining else { return (value, true) }
        value.append(character)
        remaining -= units
    }
    return (value, false)
}

private func dineWiseValidBusinessDate(_ value: String) -> Bool {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let date = formatter.date(from: value) else { return false }
    return formatter.string(from: date) == value
}

private func dineWiseLocalizedTimestamp(_ value: String) -> String {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    guard let date else { return value }
    let display = DateFormatter()
    display.locale = Locale(identifier: "zh_CN")
    display.dateStyle = .medium
    display.timeStyle = .short
    return display.string(from: date)
}

private func dineWiseRecognizeImageText(_ data: Data) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = true
    guard let source = CGImageSourceCreateWithData(data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary) else {
        throw DineWiseImageRecognitionError.invalidImage
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    let orientationValue = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
    let sourceOrientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
    let image: CGImage
    let requestOrientation: CGImagePropertyOrientation
    if max(width, height) > 2048 || width <= 0 || height <= 0 {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: 2048
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw DineWiseImageRecognitionError.invalidImage
        }
        image = thumbnail
        requestOrientation = .up
    } else {
        guard let original = CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCache: true] as CFDictionary) else {
            throw DineWiseImageRecognitionError.invalidImage
        }
        image = original
        requestOrientation = sourceOrientation
    }
    do {
        try VNImageRequestHandler(cgImage: image, orientation: requestOrientation, options: [:]).perform([request])
    } catch {
        throw DineWiseImageRecognitionError.recognitionFailed
    }
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
}

enum DineWiseTheme {
    static let page = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let inset = Color(uiColor: .tertiarySystemGroupedBackground)

    static func accent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.43, green: 0.80, blue: 0.62)
            : Color(red: 0.09, green: 0.43, blue: 0.31)
    }

    static func action(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.42, blue: 0.31)
            : Color(red: 0.08, green: 0.31, blue: 0.23)
    }

    static func gold(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 1, green: 0.78, blue: 0.40)
            : Color(red: 0.88, green: 0.62, blue: 0.22)
    }

    static func surfaceGold(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? gold(for: colorScheme)
            : Color(red: 0.50, green: 0.31, blue: 0.06)
    }

    static func danger(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 1, green: 0.50, blue: 0.55)
            : Color(red: 0.76, green: 0.27, blue: 0.32)
    }

    static func placeholder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.68) : Color(uiColor: .secondaryLabel)
    }

    static func inputSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white
    }
}

struct PendingDineWiseSubmissionKey: Codable {
    let scope: String
    let fingerprint: String
    let key: String
    let createdAt: Date
}

struct DineWiseSubmissionRetryKey {
    let scope: String
    let fingerprint: String
    let key: String
}

func pendingWriteRetryKey(scope: String, payload: [String: String]) -> DineWiseSubmissionRetryKey {
    let encoded = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
    let fingerprint = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
    let storageKey = "DineWise.PendingSubmissionKeys.v1"
    let defaults = UserDefaults.standard
    let now = Date()
    var entries = (try? JSONDecoder().decode([PendingDineWiseSubmissionKey].self,
        from: defaults.data(forKey: storageKey) ?? Data())) ?? []
    if let existing = entries.first(where: { $0.scope == scope && $0.fingerprint == fingerprint }) {
        return DineWiseSubmissionRetryKey(scope: scope, fingerprint: fingerprint, key: existing.key)
    }
    let key = UUID().uuidString
    entries.append(PendingDineWiseSubmissionKey(scope: scope, fingerprint: fingerprint,
                                                 key: key, createdAt: now))
    if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: storageKey) }
    return DineWiseSubmissionRetryKey(scope: scope, fingerprint: fingerprint, key: key)
}

func clearPendingWriteRetryKey(_ retry: DineWiseSubmissionRetryKey) {
    let storageKey = "DineWise.PendingSubmissionKeys.v1"
    let defaults = UserDefaults.standard
    guard let data = defaults.data(forKey: storageKey),
          var entries = try? JSONDecoder().decode([PendingDineWiseSubmissionKey].self, from: data) else { return }
    entries.removeAll { $0.scope == retry.scope && $0.fingerprint == retry.fingerprint }
    if let updated = try? JSONEncoder().encode(entries) { defaults.set(updated, forKey: storageKey) }
}

func clearPendingWriteRetries(scopePrefix: String) {
    let storageKey = "DineWise.PendingSubmissionKeys.v1"
    let defaults = UserDefaults.standard
    guard let data = defaults.data(forKey: storageKey),
          var entries = try? JSONDecoder().decode([PendingDineWiseSubmissionKey].self, from: data) else { return }
    entries.removeAll { $0.scope.hasPrefix(scopePrefix) }
    if let updated = try? JSONEncoder().encode(entries) { defaults.set(updated, forKey: storageKey) }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    private let api = DineWiseAPI()
    @State private var email = ""
    @State private var verifiedEmail = ""
    @State private var username = ""
    @State private var password = ""
    @State private var authMode = "password"
    @State private var appleNonce = ""
    @State private var code = ""
    @State private var storeName = ""
    @State private var showsEmailBinding = false
    @State private var showsDemoStoreEditor = false
    @State private var token: String?
    @State private var sessionUserID = ""
    @State private var stores: [DineWiseStore] = []
    @State private var selectedStoreID = ""
    @State private var selectedRole = ""
    @State private var unreadMeetingTaskCount = 0
    @State private var pushTaskFocusID = ""
    @State private var pushAuthorizationSummary = "正在读取系统通知权限。"
    @State private var pushSystemAuthorizationDenied = false
    @State private var members: [DineWiseMember] = []
    @State private var memberEvents: [DineWiseMemberEvent] = []
    @State private var memberEventsLoaded = false
    @State private var memberEventsCanLoadMore = false
    @State private var invitations: [DineWiseMemberInvitation] = []
    @State private var hasOlderInvitations = false
    @State private var storeInvitations: [DineWiseMemberInvitation] = []
    @State private var memberEmail = ""
    @State private var memberRole = "manager"
    @State private var memberToRevoke: DineWiseMember?
    @State private var showRevokeAlert = false
    @State private var submissions: [DineWiseSubmission] = []
    @State private var submissionLoadState = "idle"
    @State private var submissionPlanFilter = ""
    @State private var submissionPlanFilterKind = "purchase"
    @State private var submissionStatusFilter = ""
    @State private var focusedSubmissionID = ""
    @State private var submissionPage = 1
    @State private var submissionTotal = 0
    @State private var submissionRequestVersion = 0
    @State private var storeRequestVersion = 0
    @State private var reviewSubmission: DineWiseSubmission?
    @State private var filesBySubmission: [String: [DineWiseSubmissionFile]] = [:]
    @State private var fileUploadRevisions: [String: Int] = [:]
    @State private var exportDocument: DineWiseAttachmentDocument?
    @State private var exportName = ""
    @State private var showFileExporter = false
    @State private var fileTargetSubmissionID: String?
    @State private var recognitionOriginalUploadSubmissionIDs: Set<String> = []
    @State private var showFileImporter = false
    @State private var submissionKind = "operating"
    @State private var purchasePlans: [DineWisePurchasePlan] = []
    @State private var purchasePlanId = ""
    @State private var preparationPlans: [DineWisePreparationPlan] = []
    @State private var preparationPlanId = ""
    @State private var submissionDate = ""
    @State private var originalText = ""
    @State private var textOrigin = "typed"
    @State private var speechTextAppended = false
    @State private var imageOcrTextAppended = false
    @State private var imageOcrInsertSnapshot: String?
    @State private var selectedOcrPhoto: PhotosPickerItem?
    @State private var isRecognizingImage = false
    @State private var imageOcrMessage = ""
    @State private var recognitionFailureCode: String?
    @State private var recognitionFailureImage: Data?
    @State private var recognitionFailureImageName = ""
    @State private var pendingRecognitionUpload: PendingDineWiseRecognitionImage?
    @State private var speechInsertSnapshot: String?
    @State private var originalTextLimitMessage = ""
    @StateObject private var speechTranscriber = DineWiseSpeechTranscriber()
    @State private var feedbackCategory = "complaint"
    @State private var feedbackOccurredAt = Date()
    @State private var pendingSubmissionKey: String?
    @State private var message = ""
    @State private var messageIsError = false
    @State private var canRetrySessionRestore = false
    @State private var isRestoringSession = false
    @State private var busy = false
    @State private var requestVersion = 0
    @State private var pendingKey: String?
    @State private var selectedTab = "preview"
    @State private var todayFocus: DineWiseOwnerTodayItem?
    private var forest: Color {
        colorScheme == .dark
            ? Color(red: 0.38, green: 0.78, blue: 0.61)
            : Color(red: 0.08, green: 0.31, blue: 0.23)
    }
    private var actionGreen: Color {
        DineWiseTheme.action(for: colorScheme)
    }
    private var ink: Color { .primary }
    private var readableSecondary: Color { .secondary }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Circle().fill(forest).frame(width: 6, height: 6)
                                Text("餐有数 DineWise")
                                    .font(.caption2.weight(.bold))
                                    .tracking(1.1)
                                    .foregroundStyle(forest)
                            }
                            Text(token == nil ? guestTitle(selectedTab) : workTitle(selectedTab))
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundStyle(ink)
                            Text(pageSubtitle(selectedTab))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(readableSecondary)
                        }
                        Spacer()
                        Image("LaunchLogo")
                            .resizable()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .shadow(color: forest.opacity(0.16), radius: 10, y: 5)
                    }
                    if !message.isEmpty {
                        Text(message).foregroundStyle(messageIsError
                            ? DineWiseTheme.danger(for: colorScheme) : forest)
                    }
                    if canRetrySessionRestore {
                        Button(isRestoringSession ? "正在恢复登录…" : "重试恢复登录") {
                            Task { await restoreMerchantSession() }
                        }
                        .disabled(isRestoringSession)
                    }
                    if let token {
                        if selectedTab == "my" {
                            mySection(token: token)
                        } else {
                            storeSection(token: token)
                        }
                    } else if selectedTab == "my" {
                        loginSection
                    } else if selectedTab == "preview" {
                        DineWiseGuestHomeView()
                    } else {
                        DineWiseGuestSectionView(section: selectedTab) { selectedTab = "my" }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .id("\(selectedTab):\(selectedStoreID):\(selectedRole)")
            .background(colorScheme == .dark
                ? DineWiseTheme.page
                : Color(red: 0.975, green: 0.969, blue: 0.948))
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        }
        .tint(DineWiseTheme.accent(for: colorScheme))
        .alert("撤回岗位授权？", isPresented: $showRevokeAlert) {
            Button("撤回", role: .destructive) {
                guard let member = memberToRevoke, let token else { return }
                let storeID = selectedStoreID
                let payload = ["MemberId": member.Id, "Action": "revoke"]
                let retry = pendingWriteRetryKey(
                    scope: "\(sessionUserID):\(storeID):member:\(member.Id):revoke",
                    payload: payload)
                perform {
                    try await api.revokeMember(storeID: storeID, memberID: member.Id,
                        token: token, idempotencyKey: retry.key)
                    clearPendingWriteRetryKey(retry)
                    if isCurrent(storeID: storeID, role: "owner", token: token) {
                        members = members.map { item in
                            guard item.Id == member.Id else { return item }
                            return DineWiseMember(Id: item.Id, UserId: item.UserId,
                                Email: item.Email, Username: item.Username, Role: item.Role,
                                Enabled: false)
                        }
                        setMessage("岗位授权已撤回。")
                        do {
                            let result = try await api.members(storeID: storeID, token: token)
                            if isCurrent(storeID: storeID, role: "owner", token: token) { members = result }
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            if isCurrent(storeID: storeID, role: "owner", token: token) {
                                setMessage("岗位授权已撤回；成员列表暂不可刷新，请稍后点“刷新”重试。")
                            }
                        }
                    }
                }
            }
            Button("取消", role: .cancel) { memberToRevoke = nil }
        } message: {
            Text("仅撤销该成员在当前门店的此岗位权限。")
        }
        .sheet(item: $reviewSubmission) { item in
            if let token {
                let reviewStoreID = selectedStoreID
                let reviewRole = selectedRole
                let reviewTimeZone = stores.first(where: { $0.Id == reviewStoreID })?.TimeZone
                DineWiseReviewView(storeID: reviewStoreID, submission: item, token: token,
                    timeZone: reviewTimeZone, role: reviewRole, userID: sessionUserID,
                    uploadRevision: fileUploadRevisions[item.Id] ?? 0, onFilesChanged: {
                        do {
                            let files = try await api.files(storeID: reviewStoreID,
                                submissionID: item.Id, token: token, role: reviewRole)
                            guard isCurrent(storeID: reviewStoreID, role: reviewRole, token: token) else {
                                return false
                            }
                            filesBySubmission[item.Id] = files
                            return true
                        } catch {
                            return false
                        }
                    }) {
                    do {
                        try await refreshSubmissionPage(storeID: reviewStoreID,
                            token: token, role: reviewRole)
                        return true
                    } catch {
                        return false
                    }
                }
            }
        }
        .task {
            await restoreMerchantSession()
            await refreshPushAuthorizationSummary()
            if let accessToken = token, !sessionUserID.isEmpty,
               isPushEnabled(sessionUserID) {
                await registerPushIfEnabled(accessToken: accessToken, userID: sessionUserID)
            }
            await openPendingPushRoute()
        }
        .task(id: "\(token ?? ""):\(selectedStoreID):\(selectedRole):\(selectedTab)") {
            guard let token, !selectedStoreID.isEmpty,
                  ["owner", "manager", "purchaser"].contains(selectedRole) else {
                unreadMeetingTaskCount = 0
                return
            }
            while !Task.isCancelled {
                if let notifications = try? await api.taskNotifications(storeID: selectedStoreID,
                    token: token, role: selectedRole, size: 21), !Task.isCancelled {
                    unreadMeetingTaskCount = notifications.filter { !$0.IsRead }.count
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { speechTranscriber.stop() }
            if phase == .active {
                Task {
                    await refreshStoresAfterResume()
                    await refreshPushAuthorizationSummary()
                    if let accessToken = token, !sessionUserID.isEmpty,
                       isPushEnabled(sessionUserID) {
                        await registerPushIfEnabled(accessToken: accessToken, userID: sessionUserID)
                    }
                }
            }
        }
        .task(id: "\(selectedTab):\(selectedStoreID):\(selectedRole)") {
            speechTranscriber.stop()
            let listTab = selectedRole == "owner" ? "materials" : "upload"
            if (!submissionPlanFilter.isEmpty || !submissionStatusFilter.isEmpty)
                && selectedTab != listTab, let token {
                submissionPlanFilter = ""; submissionStatusFilter = ""; submissionPage = 1
                try? await refreshSubmissionPage(storeID: selectedStoreID,
                    token: token, role: selectedRole)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dineWiseSessionExpired)) { _ in
            guard let expiredToken = token else { return }
            Task { @MainActor in
                guard token == expiredToken,
                      !(await DineWiseSessionStore.shared.manages(expiredToken)) else { return }
                signOut()
                selectedTab = "my"
                setMessage("登录已过期，请重新登录。", isError: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dineWisePushTokenReceived)) { event in
            guard let accessToken = token,
                  let deviceToken = event.userInfo?["token"] as? String else { return }
            Task { await registerPushDevice(deviceToken, accessToken: accessToken) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dineWisePushRegistrationFailed)) { _ in
            pushAuthorizationSummary = "系统未能登记此设备，请稍后重试。"
        }
        .onReceive(NotificationCenter.default.publisher(for: .dineWisePushNotificationOpened)) { _ in
            Task { await openPendingPushRoute() }
        }
        .onChange(of: token) { _, accessToken in
            guard let accessToken, !sessionUserID.isEmpty,
                  isPushEnabled(sessionUserID) else { return }
            Task {
                await registerPushIfEnabled(accessToken: accessToken, userID: sessionUserID)
            }
        }
    }

    @MainActor
    private func restoreMerchantSession() async {
        guard token == nil else { return }
        isRestoringSession = true
        canRetrySessionRestore = false
        setMessage("")
        defer { isRestoringSession = false }
        do {
            guard let session = try await api.restore(), token == nil else { return }
            canRetrySessionRestore = false
            await api.register(session)
            token = session.AccessToken
            sessionUserID = session.UserId
            email = session.Email
            verifiedEmail = session.Email
            username = session.Username ?? ""
            selectedTab = "my"
            let authorized = try await loadAuthorizedStores(token: session.AccessToken)
            if token == session.AccessToken {
                updateStores(authorized)
                let pending = (try? await api.invitations(token: session.AccessToken)) ?? []
                if token == session.AccessToken {
                    invitations = pending
                    hasOlderInvitations = pending.count == 100
                    selectedTab = defaultTab(for: selectedRole)
                }
            }
        } catch {
            if token == nil {
                setMessage(error.localizedDescription, isError: true)
                canRetrySessionRestore = api.hasSavedSession()
            }
        }
    }

    @MainActor
    private func loadAuthorizedStores(token: String) async throws -> [DineWiseStore] {
        storeRequestVersion += 1
        let version = storeRequestVersion
        let authorized = try await api.stores(token: token)
        guard version == storeRequestVersion else { throw CancellationError() }
        return authorized
    }

    @MainActor
    private func refreshStoresAfterResume() async {
        guard let token else { return }
        do {
            let authorized = try await loadAuthorizedStores(token: token)
            if self.token == token { updateStores(authorized) }
        } catch is CancellationError {
            return
        } catch {
            if self.token == token {
                setMessage("门店授权暂不可刷新，请稍后点“刷新门店”重试。", isError: true)
            }
        }
    }

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(red: 0.91, green: 0.70, blue: 0.34))
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                Text("把每天的经营，\n变成下一步行动")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("登录后查看你已获授权的门店与岗位工作台")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(
                LinearGradient(colors: [actionGreen, Color(red: 0.12, green: 0.42, blue: 0.31)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22))

            VStack(alignment: .leading, spacing: 15) {
                HStack {
                Text(authMode == "register" ? "注册餐有数账号" : "登录自己的门店").font(.headline)
                    Spacer()
                    Image(systemName: "lock.shield.fill").foregroundStyle(forest)
                }
                Picker("登录方式", selection: $authMode) {
                    Text("密码登录").tag("password")
                    Text("注册账号").tag("register")
                    Text("邮箱登录").tag("email")
                }
                .pickerStyle(.segmented)
                if authMode != "email" {
                    Text("用户名").font(.subheadline.bold())
                    TextField(text: $username,
                              prompt: Text("用户名").foregroundColor(Color(uiColor: .secondaryLabel))) {
                        Text("用户名")
                    }
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(DineWiseTheme.inset,
                                    in: RoundedRectangle(cornerRadius: 12))
                    Text("密码").font(.subheadline.bold())
                    SecureField(text: $password,
                                prompt: Text(authMode == "register" ? "至少 12 位" : "密码").foregroundColor(Color(uiColor: .secondaryLabel))) {
                        Text("密码")
                    }
                        .textContentType(authMode == "register" ? .newPassword : .password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(DineWiseTheme.inset,
                                    in: RoundedRectangle(cornerRadius: 12))
                    Text(authMode == "register"
                        ? "用户名需为 3–80 位；密码需为 12–128 位。无需邮箱验证，注册后由管理员开通账号。"
                        : "用户名需为 3–80 位，密码最多 128 位。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(authMode == "register" ? "注册并等待开通" : "登录并查看门店") {
                        perform {
                            if authMode == "register" {
                                try await api.register(username: username.trimmingCharacters(in: .whitespaces),
                                                       password: password)
                                password = ""
                                authMode = "password"
                                setMessage("注册成功，账号待后台开通。开通后可用用户名和密码登录。")
                            } else {
                                let session = try await api.passwordLogin(
                                    username: username.trimmingCharacters(in: .whitespaces), password: password)
                                try await applyLogin(session)
                                password = ""
                            }
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.white)
                    .background(actionGreen, in: RoundedRectangle(cornerRadius: 12))
                    .disabled(busy
                        || !(3...80).contains(username.trimmingCharacters(in: .whitespaces).utf16.count)
                        || !(1...128).contains(password.utf16.count)
                        || (authMode == "register" && !(12...128).contains(password.utf16.count)))
                } else {
                Text("邮箱地址").font(.subheadline.bold())
                TextField(text: $email,
                          prompt: Text("邮箱").foregroundColor(Color(uiColor: .secondaryLabel))) {
                    Text("邮箱")
                }
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(DineWiseTheme.inset,
                                in: RoundedRectangle(cornerRadius: 12))
                Button("获取验证码") {
                    perform {
                        try await api.sendCode(email: email.trimmingCharacters(in: .whitespaces))
                        setMessage("验证码已发送，请查收邮箱。")
                    }
                }
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(forest)
                .background(RoundedRectangle(cornerRadius: 12)
                    .stroke(forest.opacity(0.35)))
                .opacity(busy || email.isEmpty ? 0.5 : 1)
                .disabled(busy || email.isEmpty)
                Text("验证码").font(.subheadline.bold())
                TextField(text: $code,
                          prompt: Text("验证码").foregroundColor(Color(uiColor: .secondaryLabel))) {
                    Text("验证码")
                }
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(DineWiseTheme.inset,
                                in: RoundedRectangle(cornerRadius: 12))
                Button("登录并查看门店") {
                    perform {
                        let session = try await api.login(
                            email: email.trimmingCharacters(in: .whitespaces), code: code
                        )
                        try await applyLogin(session)
                        code = ""
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(.white)
                .background(actionGreen, in: RoundedRectangle(cornerRadius: 12))
                .opacity(busy || email.isEmpty || code.isEmpty ? 0.5 : 1)
                .disabled(busy || email.isEmpty || code.isEmpty)
                }
                if !appleNonce.isEmpty {
                    SignInWithAppleButton(.signIn, onRequest: { request in
                        request.requestedScopes = [.fullName, .email]
                        let digest = SHA256.hash(data: Data(appleNonce.utf8))
                        request.nonce = digest.map { String(format: "%02x", $0) }.joined()
                    }, onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                                  let identity = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
                                  let code = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) else {
                                setMessage("Apple 登录凭证不完整，请重试。", isError: true)
                                return
                            }
                            let nonce = appleNonce
                            let displayName = [credential.fullName?.familyName,
                                               credential.fullName?.givenName]
                                .compactMap { $0 }.joined()
                            appleNonce = ""
                            perform {
                                defer { Task { await refreshAppleNonce() } }
                                let session = try await api.appleLogin(identityToken: identity,
                                    authorizationCode: code, nonce: nonce, displayName: displayName)
                                try await applyLogin(session)
                            }
                        case .failure:
                            setMessage("Apple 登录已取消或失败，请重试。", isError: true)
                        }
                    })
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Label("经营资料仅向已获授权的账号开放", systemImage: "checkmark.shield")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("关于餐有数 · 查看版本") { DineWiseAboutView() }
                    .font(.footnote)
                    .foregroundStyle(forest)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 20))
            .task { await refreshAppleNonce() }
        }
    }

    private func refreshAppleNonce() async {
        appleNonce = (try? await api.appleNonce()) ?? ""
    }

    private func applyLogin(_ session: DineWiseSession) async throws {
        updateStores(try await loadAuthorizedStores(token: session.AccessToken))
        await api.register(session)
        token = session.AccessToken
        sessionUserID = session.UserId
        email = session.Email
        verifiedEmail = session.Email
        username = session.Username ?? ""
        if isPushEnabled(session.UserId) {
            await registerPushIfEnabled(accessToken: session.AccessToken, userID: session.UserId)
        }
        let pending = (try? await api.invitations(token: session.AccessToken)) ?? []
        if token == session.AccessToken {
            invitations = pending
            hasOlderInvitations = pending.count == 100
            selectedTab = defaultTab(for: selectedRole)
        }
        await openPendingPushRoute()
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            if token == nil {
                tabButton("今日", symbol: "house", value: "preview")
                tabButton("建议", symbol: "lightbulb", value: "suggestions")
                tabButton("报告", symbol: "chart.bar.xaxis", value: "report")
                tabButton("资料", symbol: "folder", value: "materials")
            } else if selectedRole == "owner" {
                tabButton("今日", symbol: "house", value: "today")
                tabButton("建议", symbol: "lightbulb", value: "suggestions")
                tabButton("报告", symbol: "chart.bar.xaxis", value: "report")
                tabButton("资料", symbol: "folder", value: "materials")
            } else if selectedRole == "marketer" {
                tabButton("演示", symbol: "play.rectangle", value: "demo")
                tabButton("访谈", symbol: "mic", value: "interview")
                tabButton("记录", symbol: "doc.text", value: "records")
            } else if selectedRole == "operator" {
                tabButton("任务", symbol: "checkmark.square", value: "tasks")
                tabButton("上传", symbol: "square.and.arrow.up", value: "upload")
                tabButton("私域", symbol: "person.2", value: "private")
                tabButton("消息", symbol: "bubble.left", value: "messages")
            } else if !selectedRole.isEmpty {
                tabButton("任务", symbol: "checkmark.square", value: "tasks")
                tabButton("上传", symbol: "square.and.arrow.up", value: "upload")
                tabButton("消息", symbol: "bubble.left", value: "messages")
            } else {
                tabButton("门店", symbol: "storefront", value: "work")
            }
            tabButton("我的", symbol: "person.crop.circle", value: "my")
        }
        .padding(.top, 9)
        .padding(.bottom, 5)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(alignment: .top) { Color.black.opacity(0.07).frame(height: 1) }
    }

    private func tabButton(_ title: String, symbol: String, value: String) -> some View {
        let showsTaskUnread = unreadMeetingTaskCount > 0
            && (selectedRole == "owner" && value == "suggestions"
                || ["manager", "purchaser"].contains(selectedRole) && value == "tasks")
        let displayedTitle = showsTaskUnread
            ? "\(title) · \(unreadMeetingTaskCount > 20 ? "20+" : String(unreadMeetingTaskCount))"
            : title
        return Button {
            todayFocus = nil
            selectedTab = value
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 38, height: 27)
                    .background(selectedTab == value ? forest.opacity(0.10) : .clear,
                                in: Capsule())
                Text(displayedTitle).font(.caption2.weight(selectedTab == value ? .semibold : .regular))
            }
            .foregroundStyle(selectedTab == value ? forest : Color.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func defaultTab(for role: String) -> String {
        switch role {
        case "owner": "today"
        case "marketer": "demo"
        case "": "work"
        default: "tasks"
        }
    }

    private func workTitle(_ tab: String) -> String {
        switch tab {
        case "today": "今日"
        case "suggestions": "建议"
        case "report": "报告"
        case "materials": "资料"
        case "tasks": "任务"
        case "upload": "上传"
        case "messages": "消息"
        case "private": "私域"
        case "demo": "演示"
        case "interview": "访谈"
        case "records": "记录"
        case "my": "我的"
        default: roleName(selectedRole)
        }
    }

    private func guestTitle(_ tab: String) -> String {
        switch tab {
        case "suggestions": "建议"
        case "report": "报告"
        case "materials": "资料"
        case "my": "我的"
        default: "今日"
        }
    }

    private func pageSubtitle(_ tab: String) -> String {
        if token == nil {
            switch tab {
            case "suggestions": return "了解建议如何产生与执行"
            case "report": return "先核对资料，再查看经营变化"
            case "materials": return "了解资料从提交到确认的路径"
            case "my": return "登录后查看获授权的门店"
            default:
                return "\(Date.now.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "zh_CN")))) · 先看今天要处理什么"
            }
        }
        switch tab {
        case "suggestions": return "核对依据，再决定下一步"
        case "report": return "查看已确认的经营数据"
        case "materials", "upload": return "提交原始资料，核对后使用"
        case "tasks": return "按岗位处理待办和回执"
        case "messages": return "查看门店提醒与通知"
        case "my": return "管理账号与门店授权"
        default: return "查看当前门店的经营进展"
        }
    }

    private func mySection(token: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("我的").font(.title2.bold())
                Spacer()
                Button("刷新门店") {
                    perform {
                        let updated = try await loadAuthorizedStores(token: token)
                        let pending = try await api.invitations(token: token)
                        if self.token == token {
                            updateStores(updated)
                            invitations = pending
                            hasOlderInvitations = pending.count == 100
                        }
                    }
                }
                .disabled(busy)
            }
            Text(username.isEmpty ? verifiedEmail : username)
                .foregroundStyle(.secondary)
            pushSettingsSection(token: token)
            if verifiedEmail.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsEmailBinding.toggle()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("绑定邮箱").font(.headline)
                                if !showsEmailBinding {
                                    Text("绑定后可接收门店邀请")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: showsEmailBinding ? "chevron.up" : "chevron.down")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showsEmailBinding {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("验证邮箱后，发往此邮箱的门店邀请会显示在当前账号中。")
                                .font(.footnote).foregroundStyle(.secondary)
                            DineWisePlaceholderField("邮箱", isEmpty: email.isEmpty) {
                                TextField("", text: $email)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.plain)
                            }
                            Button("获取验证码") {
                                perform {
                                    try await api.sendCode(email: email.trimmingCharacters(in: .whitespaces))
                                    setMessage("验证码已发送，请查收邮箱。")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(DineWiseTheme.accent(for: colorScheme))
                            .disabled(busy || !email.contains("@"))
                            DineWisePlaceholderField("验证码", isEmpty: code.isEmpty) {
                                TextField("", text: $code)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    .textFieldStyle(.plain)
                            }
                            Button("验证并绑定") {
                                perform {
                                    let bound = try await api.bindEmail(
                                        email: email.trimmingCharacters(in: .whitespaces),
                                        code: code.trimmingCharacters(in: .whitespaces), token: token)
                                    if self.token == token {
                                        email = bound
                                        verifiedEmail = bound
                                        code = ""
                                        showsEmailBinding = false
                                        setMessage("邮箱已绑定，可以在本账号接收门店邀请。")
                                        do {
                                            let pending = try await api.invitations(token: token)
                                            if self.token == token {
                                                invitations = pending
                                                hasOlderInvitations = pending.count == 100
                                            }
                                        } catch is CancellationError {
                                            throw CancellationError()
                                        } catch {
                                            if self.token == token {
                                                setMessage("邮箱已绑定；邀请列表暂不可刷新，请稍后点“刷新门店”重试。",
                                                           isError: true)
                                            }
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DineWiseTheme.action(for: colorScheme))
                            .disabled(busy || !email.contains("@") || code.isEmpty)
                        }
                    }
                }
                .padding(14)
                .background(DineWiseTheme.inset,
                            in: RoundedRectangle(cornerRadius: 14))
            } else {
                Text(verifiedEmail).foregroundStyle(.secondary)
            }
            if !invitations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("待处理的门店邀请").font(.headline)
                    Text("使用当前邮箱确认后，岗位权限才会生效。")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(invitations) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.StoreName).font(.subheadline.bold())
                            Text("\(item.Mode == "demo" ? "演示门店" : "试用门店") · \(roleName(item.Role))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("有效至 \(dineWiseFormatTimestamp(item.ExpiresAtUtc, timeZoneID: item.StoreTimeZone))")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("接受") { resolveInvitation(item, action: "accept", token: token) }
                                Button("拒绝", role: .destructive) {
                                    resolveInvitation(item, action: "decline", token: token)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(busy)
                        }
                        .padding(.vertical, 4)
                    }
                    if hasOlderInvitations {
                        Button(busy ? "正在加载…" : "加载更早邀请") {
                            loadOlderInvitations(token: token)
                        }
                        .disabled(busy)
                    }
                }
                .padding(14)
                .background(DineWiseTheme.inset,
                            in: RoundedRectangle(cornerRadius: 14))
            }
            Text("已获授权门店：\(stores.count) 家")
            ForEach(stores) { store in
                Button {
                    if selectedStoreID == store.Id {
                        selectedTab = defaultTab(for: selectedRole)
                    } else {
                        switchWorkspace(storeID: store.Id, role: store.Roles.first ?? "")
                    }
                } label: {
                    HStack {
                        Text(store.Name)
                        Spacer()
                        Text(store.Mode == "demo" ? "演示" : "试用")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if selectedRole == "owner",
               let selected = stores.first(where: { $0.Id == selectedStoreID }) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("当前门店 · \(selected.Name)").font(.headline)
                    DineWiseStoreProfileEditor(store: selected, token: token) { updated in
                        if isCurrent(storeID: selected.Id, role: "owner", token: token) {
                            stores = stores.map { $0.Id == updated.Id ? updated : $0 }
                        }
                    }
                    .id(selected.Id)
                }
                .padding(14)
                .background(DineWiseTheme.inset,
                            in: RoundedRectangle(cornerRadius: 14))
            }
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsDemoStoreEditor.toggle()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("创建演示门店")
                            Text("使用构造数据预览流程，不代表真实门店")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: showsDemoStoreEditor ? "chevron.up" : "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsDemoStoreEditor ? "已展开" : "已收起")
                .accessibilityHint(showsDemoStoreEditor ? "双击收起演示门店创建表单" : "双击展开演示门店创建表单")
                if showsDemoStoreEditor {
                    DineWisePlaceholderField("演示门店名称", isEmpty: storeName.isEmpty) {
                        TextField("", text: $storeName)
                            .textFieldStyle(.plain)
                            .onChange(of: storeName) { _, _ in pendingKey = nil }
                    }
                    Button("创建演示门店") {
                        perform {
                            let key = pendingKey ?? UUID().uuidString
                            pendingKey = key
                            try await api.createDemoStore(name: storeName, token: token, idempotencyKey: key)
                            if self.token == token {
                                let updated = try await loadAuthorizedStores(token: token)
                                if self.token == token {
                                    updateStores(updated)
                                    storeName = ""
                                    pendingKey = nil
                                    showsDemoStoreEditor = false
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DineWiseTheme.action(for: colorScheme))
                    .disabled(busy || storeName.isEmpty)
                }
            }
            .padding(14)
            .background(DineWiseTheme.inset, in: RoundedRectangle(cornerRadius: 14))
            NavigationLink("关于餐有数 · 查看版本") { DineWiseAboutView() }
            Button("退出登录") { signOut() }
                .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func resolveInvitation(_ item: DineWiseMemberInvitation, action: String, token: String) {
        let payload = ["InvitationId": item.Id, "Action": action]
        let retry = pendingWriteRetryKey(
            scope: "\(sessionUserID):invitation:\(item.Id):\(action)", payload: payload)
        perform {
            try await api.resolveInvitation(id: item.Id, action: action,
                token: token, idempotencyKey: retry.key)
            clearPendingWriteRetryKey(retry)
            if self.token == token {
                let successMessage = action == "accept" ? "已加入门店。" : "已拒绝邀请。"
                setMessage(successMessage)
                do {
                    let pending = try await api.invitations(token: token)
                    if self.token == token {
                        invitations = pending
                        hasOlderInvitations = pending.count == 100
                    }
                    if action == "accept" {
                        let updated = try await loadAuthorizedStores(token: token)
                        if self.token == token { updateStores(updated) }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if self.token == token {
                        setMessage("\(successMessage) 列表暂不可刷新，请稍后点“刷新门店”重试。",
                                   isError: true)
                    }
                }
            }
        }
    }

    private func pushSettingsSection(token: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("任务提醒").font(.headline)
            Text(pushAuthorizationSummary).font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("开启或刷新系统提醒") {
                    Task {
                        do {
                            let granted = try await DineWisePushRegistration.shared.requestAuthorization()
                            if granted {
                                UserDefaults.standard.set(true, forKey: pushEnabledKey(sessionUserID))
                                pushAuthorizationSummary = "系统通知已允许，正在登记此设备。"
                                let deviceToken = DineWisePushRegistration.shared.deviceToken
                                if !deviceToken.isEmpty {
                                    await registerPushDevice(deviceToken, accessToken: token)
                                }
                            } else {
                                UserDefaults.standard.set(false, forKey: pushEnabledKey(sessionUserID))
                                pushSystemAuthorizationDenied = true
                                let revoked = await revokeSavedPushDevice(accessToken: token,
                                    userID: sessionUserID)
                                pushAuthorizationSummary = revoked
                                    ? "尚未允许通知，可在 iPhone 设置中为餐有数开启。"
                                    : "尚未允许通知；服务端登记撤销失败，联网后返回应用会重试。"
                            }
                        } catch {
                            pushAuthorizationSummary = "系统通知设置未完成，请稍后重试。"
                        }
                    }
                }
                .buttonStyle(.bordered)
                Button("停用此设备", role: .destructive) {
                    Task { await revokePushDevice(accessToken: token) }
                }
                .buttonStyle(.bordered)
            }
            if pushSystemAuthorizationDenied {
                Button("前往 iPhone 设置") {
                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(settingsURL)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .task { await refreshPushAuthorizationSummary() }
    }

    @MainActor
    private func refreshPushAuthorizationSummary() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard isPushEnabled(sessionUserID) else {
            var revoked = UserDefaults.standard.string(forKey: pushDeviceKey(sessionUserID)) == nil
            if let accessToken = token, !sessionUserID.isEmpty {
                revoked = await revokeSavedPushDevice(accessToken: accessToken,
                    userID: sessionUserID)
            }
            pushSystemAuthorizationDenied = settings.authorizationStatus == .denied
            pushAuthorizationSummary = revoked
                ? "此设备的系统任务提醒已停用。"
                : "此设备提醒已停用；可重试清理服务端设备登记。"
            return
        }
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            pushSystemAuthorizationDenied = false
            let savedDeviceID = UserDefaults.standard.string(forKey: pushDeviceKey(sessionUserID))
            pushAuthorizationSummary = savedDeviceID == nil
                ? "系统通知已允许；此设备将在收到 APNs 令牌后登记。"
                : "系统通知已授权，设备登记完成；提醒送达还取决于服务端推送配置。"
        case .denied:
            pushSystemAuthorizationDenied = true
            let accessToken = token
            if let accessToken, !sessionUserID.isEmpty {
                _ = await revokeSavedPushDevice(accessToken: accessToken, userID: sessionUserID)
            }
            pushAuthorizationSummary = UserDefaults.standard.string(
                forKey: pushDeviceKey(sessionUserID)) == nil
                ? "系统通知未允许；应用内启用偏好已保留，重新允许后会恢复登记。"
                : "系统通知未允许；服务端登记撤销失败，联网后返回应用会重试。"
        case .notDetermined:
            pushSystemAuthorizationDenied = false
            pushAuthorizationSummary = "按下方按钮后才会请求系统通知权限。"
        @unknown default:
            pushSystemAuthorizationDenied = false
            pushAuthorizationSummary = "无法读取系统通知权限状态。"
        }
    }

    @MainActor
    private func registerPushIfEnabled(accessToken: String, userID: String) async {
        guard token == accessToken, sessionUserID == userID,
              isPushEnabled(userID) else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard token == accessToken, sessionUserID == userID,
              isPushEnabled(userID),
              [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            return
        }
        await DineWisePushRegistration.shared.registerIfAuthorized()
        guard token == accessToken, sessionUserID == userID,
              isPushEnabled(userID) else { return }
        let deviceToken = DineWisePushRegistration.shared.deviceToken
        if !deviceToken.isEmpty { await registerPushDevice(deviceToken, accessToken: accessToken) }
    }

    @MainActor
    private func registerPushDevice(_ deviceToken: String, accessToken: String) async {
        let userID = sessionUserID
        guard self.token == accessToken, !userID.isEmpty,
              isPushEnabled(userID) else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard self.token == accessToken, sessionUserID == userID,
              isPushEnabled(userID),
              [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            return
        }
        #if DEBUG
            let environment = "development"
        #else
            let environment = "production"
        #endif
        do {
            let device = try await api.registerPushDevice(token: deviceToken,
                environment: environment, accessToken: accessToken)
            guard self.token == accessToken, sessionUserID == userID,
                  isPushEnabled(userID) else {
                do {
                    try await api.revokePushDevice(id: device.Id, accessToken: accessToken)
                    if UserDefaults.standard.string(forKey: pushDeviceKey(userID)) == device.Id {
                        UserDefaults.standard.removeObject(forKey: pushDeviceKey(userID))
                    }
                } catch {
                    UserDefaults.standard.set(device.Id, forKey: pushDeviceKey(userID))
                }
                return
            }
            UserDefaults.standard.set(device.Id, forKey: pushDeviceKey(userID))
            pushAuthorizationSummary = "系统通知已授权，设备登记完成；提醒送达还取决于服务端推送配置。"
        } catch {
            pushAuthorizationSummary = "设备登记失败；站内提醒仍可在任务页查看。"
        }
    }

    @MainActor
    private func revokePushDevice(accessToken: String) async {
        UserDefaults.standard.set(false, forKey: pushEnabledKey(sessionUserID))
        if !(await revokeSavedPushDevice(accessToken: accessToken, userID: sessionUserID)) {
            pushAuthorizationSummary = "设备停用失败，请联网后重试。"
            return
        }
        DineWisePushRegistration.shared.clearDeviceToken()
        pushAuthorizationSummary = "此设备已停用系统任务提醒。"
    }

    @MainActor
    private func revokeSavedPushDevice(accessToken: String, userID: String) async -> Bool {
        let key = pushDeviceKey(userID)
        guard let deviceID = UserDefaults.standard.string(forKey: key) else { return true }
        do {
            try await api.revokePushDevice(id: deviceID, accessToken: accessToken)
            if UserDefaults.standard.string(forKey: key) == deviceID {
                UserDefaults.standard.removeObject(forKey: key)
            }
            return true
        } catch {
            return false
        }
    }

    private func pushDeviceKey(_ userID: String) -> String {
        "DineWise.PushDevice.\(userID)"
    }

    private func pushEnabledKey(_ userID: String) -> String {
        "DineWise.PushEnabled.\(userID)"
    }

    private func isPushEnabled(_ userID: String) -> Bool {
        let key = pushEnabledKey(userID)
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.bool(forKey: key)
        }
        return UserDefaults.standard.string(forKey: pushDeviceKey(userID)) != nil
    }

    @MainActor
    private func openPendingPushRoute() async {
        guard let accessToken = token,
              let route = DineWisePushRegistration.shared.pendingRoute else { return }
        guard let store = stores.first(where: { $0.Id == route.storeID }),
              store.Roles.contains(route.role) else {
            DineWisePushRegistration.shared.clearPendingRoute()
            setMessage("此提醒对应的门店岗位授权已变化，请刷新门店列表。", isError: true)
            return
        }
        DineWisePushRegistration.shared.clearPendingRoute()
        switchWorkspace(storeID: store.Id, role: route.role)
        selectedTab = route.role == "owner" ? "suggestions" : "tasks"
        pushTaskFocusID = route.taskID
        do {
            _ = try await api.markTaskNotificationRead(storeID: store.Id,
                notificationID: route.notificationID, token: accessToken, role: route.role)
            if token == accessToken, selectedStoreID == store.Id, selectedRole == route.role,
               unreadMeetingTaskCount <= 20 {
                unreadMeetingTaskCount = max(0, unreadMeetingTaskCount - 1)
            }
        } catch {
            if token == accessToken, selectedStoreID == store.Id, selectedRole == route.role {
                setMessage(error.localizedDescription, isError: true)
            }
        }
    }

    private func loadOlderInvitations(token: String) {
        guard hasOlderInvitations, !busy, let cursor = invitations.last?.Id else { return }
        perform {
            let older = try await api.invitations(token: token, beforeID: cursor)
            guard self.token == token else { return }
            let existing = Set(invitations.map(\.Id))
            invitations.append(contentsOf: older.filter { !existing.contains($0.Id) })
            hasOlderInvitations = older.count == 100
        }
    }

    private func signOut() {
        if let token {
            let userID = sessionUserID
            Task {
                let key = pushDeviceKey(userID)
                if let deviceID = UserDefaults.standard.string(forKey: key) {
                    do {
                        try await api.revokePushDevice(id: deviceID, accessToken: token)
                        UserDefaults.standard.removeObject(forKey: key)
                    } catch { }
                }
                await api.logout(token: token)
            }
            DineWisePushRegistration.shared.clearDeviceToken()
        }
        requestVersion += 1
        storeRequestVersion += 1
        busy = false
        token = nil
        verifiedEmail = ""
        sessionUserID = ""
        pushTaskFocusID = ""
        stores = []
        selectedStoreID = ""
        selectedRole = ""
        selectedTab = "preview"
        members = []
        memberEvents = []; memberEventsLoaded = false; memberEventsCanLoadMore = false
        invitations = []
        hasOlderInvitations = false
        storeInvitations = []
        submissions = []
        submissionLoadState = "idle"
        purchasePlans = []
        purchasePlanId = ""
        preparationPlans = []; preparationPlanId = ""
        filesBySubmission = [:]
        fileUploadRevisions = [:]
        exportDocument = nil
        showFileExporter = false
        fileTargetSubmissionID = nil
        recognitionOriginalUploadSubmissionIDs = []
        showFileImporter = false
        memberToRevoke = nil
        showRevokeAlert = false
        reviewSubmission = nil
        memberEmail = ""
        submissionDate = ""
        originalText = ""
        originalTextLimitMessage = ""
        textOrigin = "typed"; speechTextAppended = false; imageOcrTextAppended = false
        imageOcrInsertSnapshot = nil; selectedOcrPhoto = nil; isRecognizingImage = false
        imageOcrMessage = ""; speechInsertSnapshot = nil
        recognitionFailureCode = nil
        recognitionFailureImage = nil; recognitionFailureImageName = ""
        pendingRecognitionUpload = nil
        pendingSubmissionKey = nil
        storeName = ""
        pendingKey = nil
        showsEmailBinding = false
        showsDemoStoreEditor = false
        setMessage("")
    }

    private func storeSection(token: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if stores.isEmpty {
                Text("暂无获授权门店，可先创建演示门店。")
                    .foregroundStyle(.secondary)
            } else if stores.count > 1 {
                HStack {
                    Text("切换门店").font(.subheadline.bold())
                    Spacer()
                    Picker("切换门店", selection: Binding(
                        get: { selectedStoreID },
                        set: { nextID in
                            if let next = stores.first(where: { $0.Id == nextID }) {
                                switchWorkspace(storeID: next.Id, role: next.Roles.first ?? "")
                            }
                        })) {
                        ForEach(stores) { store in
                            Text("\(store.Name) · \(store.Mode == "demo" ? "演示" : "试用")")
                                .tag(store.Id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 14))
            }
            if let selected = stores.first(where: { $0.Id == selectedStoreID }) {
                HStack(spacing: 8) {
                    Text(selected.Name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(selected.Mode == "demo" ? "演示数据" : "试用门店")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(selected.Mode == "demo" ? forest : Color.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(selected.Mode == "demo" ? forest.opacity(0.09) : Color.secondary.opacity(0.08),
                                    in: Capsule())
                    Spacer(minLength: 4)
                    if selected.Roles.count > 1 {
                        Picker("切换岗位", selection: Binding(
                            get: { selectedRole },
                            set: { switchWorkspace(storeID: selected.Id, role: $0) })) {
                            ForEach(selected.Roles, id: \.self) { role in
                                Text(roleName(role)).tag(role)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding(12)
                .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 14))
                if selectedRole == "owner" {
                    if selectedTab == "suggestions" {
                        DineWiseNoticeView(store: selected, token: token, role: selectedRole,
                            userID: sessionUserID)
                            .id("\(token):\(selected.Id):owner:notices")
                        DineWiseDecisionTaskView(store: selected, token: token, role: selectedRole,
                            userID: sessionUserID, submissions: submissions,
                            submissionLoadState: submissionLoadState, members: members,
                            focus: todayFocus, onClearFocus: { todayFocus = nil },
                            pushTaskFocusID: pushTaskFocusID,
                            onPushTaskFocusConsumed: { pushTaskFocusID = "" },
                            onOpenMaterials: { selectedTab = "materials" },
                            onTaskNotificationRead: {
                                if unreadMeetingTaskCount <= 20 {
                                    unreadMeetingTaskCount = max(0, unreadMeetingTaskCount - 1)
                                }
                            },
                            onRetrySubmissions: {
                                perform { try await refreshSubmissionPage(storeID: selected.Id,
                                    token: token, role: selectedRole) }
                            })
                            .id("\(token):\(selected.Id):owner:tasks")
                    } else if selectedTab == "report" {
                        DineWiseDailyReportView(store: selected, token: token, userID: sessionUserID)
                            .id("\(token):\(selected.Id):owner:report")
                    } else if selectedTab == "materials" {
                        submissionSection(store: selected, token: token)
                        DineWisePreparationPlanView(store: selected, token: token,
                            role: "owner", userID: sessionUserID, onRecordPurchase: nil,
                            onRecordOutcome: nil,
                            onViewOutcomes: { plan in
                                openLinkedOutcomes(plan, storeID: selected.Id, token: token)
                            },
                            onViewPurchases: { plan in
                                openLinkedPurchases(plan, storeID: selected.Id, token: token)
                            })
                            .id("\(token):\(selected.Id):owner:preparation")
                        memberSection(store: selected, token: token)
                        DineWiseCustomerConsentView(store: selected, token: token,
                            role: "owner", userID: sessionUserID)
                            .id("\(token):\(selected.Id):owner:customer-consents")
                    } else {
                        DineWiseOwnerTodayView(store: selected, token: token) { tab, focus, statusFilter in
                            todayFocus = focus
                            if let statusFilter {
                                submissionStatusFilter = statusFilter
                                submissionPage = 1
                            }
                            selectedTab = tab
                            if statusFilter != nil {
                                let role = selectedRole
                                perform { try await refreshSubmissionPage(storeID: selected.Id,
                                    token: token, role: role) }
                            }
                        }
                            .id("\(token):\(selected.Id):owner:today")
                        DineWiseWeatherView(token: token, storeLatitude: selected.Latitude,
                            storeLongitude: selected.Longitude, storeTimeZone: selected.TimeZone)
                            .id("\(token):\(selected.Id):owner:weather")
                        DineWiseFeedbackView(store: selected, token: token, role: "owner",
                            onOpenSubmission: { submissionID in
                                submissionPlanFilter = ""
                                submissionPlanFilterKind = "purchase"
                                submissionStatusFilter = ""
                                submissionPage = 1
                                focusedSubmissionID = submissionID
                                selectedTab = "materials"
                                perform { try await refreshSubmissionPage(storeID: selected.Id,
                                    token: token, role: "owner", focusID: submissionID) }
                            })
                            .id("\(token):\(selected.Id):owner:feedback")
                    }
                } else if selectedRole == "marketer" {
                    DineWiseInterviewView(store: selected, token: token, section: selectedTab,
                        onStartInterview: { selectedTab = "interview" },
                        onSaved: {
                            if isCurrent(storeID: selected.Id, role: "marketer", token: token) {
                                selectedTab = "records"
                            }
                        })
                    .id("\(token):\(selected.Id):marketer")
                } else if selectedRole == "operator" && selectedTab == "private" {
                    DineWiseCustomerConsentView(store: selected, token: token,
                        role: selectedRole, userID: sessionUserID)
                        .id("\(token):\(selected.Id):operator:customer-consents")
                } else if selectedTab == "upload" {
                    submissionSection(store: selected, token: token)
                } else if selectedTab == "messages" {
                    DineWiseNoticeView(store: selected, token: token, role: selectedRole,
                        userID: sessionUserID)
                        .id("\(token):\(selected.Id):\(selectedRole):notices")
                } else if !selectedRole.isEmpty {
                    if selectedRole == "manager" {
                        DineWiseFeedbackView(store: selected, token: token, role: "manager")
                            .id("\(token):\(selected.Id):manager:feedback")
                    }
                    DineWiseDecisionTaskView(store: selected, token: token, role: selectedRole,
                        userID: sessionUserID, submissions: submissions,
                        submissionLoadState: submissionLoadState, members: members,
                        focus: nil, onClearFocus: {},
                        pushTaskFocusID: pushTaskFocusID,
                        onPushTaskFocusConsumed: { pushTaskFocusID = "" },
                        onTaskNotificationRead: {
                            if unreadMeetingTaskCount <= 20 {
                                unreadMeetingTaskCount = max(0, unreadMeetingTaskCount - 1)
                            }
                        },
                        onRetrySubmissions: {
                            perform { try await refreshSubmissionPage(storeID: selected.Id,
                                token: token, role: selectedRole) }
                        })
                        .id("\(token):\(selected.Id):\(selectedRole):tasks")
                    if selectedRole == "chef" || selectedRole == "purchaser" {
                        DineWisePreparationPlanView(store: selected, token: token,
                            role: selectedRole, userID: sessionUserID, onRecordPurchase: { plan in
                                guard isCurrent(storeID: selected.Id, role: "purchaser", token: token) else { return }
                                submissionPlanFilter = ""; submissionPage = 1
                                purchasePlans = [plan] + purchasePlans.filter { $0.Id != plan.Id }
                                purchasePlanId = plan.Id; submissionKind = "purchase"
                                pendingSubmissionKey = nil; selectedTab = "upload"
                            }, onRecordOutcome: { plan in
                                guard isCurrent(storeID: selected.Id, role: "chef", token: token) else { return }
                                preparationPlans = [plan] + preparationPlans.filter { $0.Id != plan.Id }
                                preparationPlanId = plan.Id; submissionDate = plan.BusinessDate
                                submissionKind = "kitchen"; feedbackCategory = "leftover"
                                pendingSubmissionKey = nil; selectedTab = "upload"
                            }, onViewOutcomes: { plan in
                                openLinkedOutcomes(plan, storeID: selected.Id, token: token)
                            }, onViewPurchases: { plan in
                                openLinkedPurchases(plan, storeID: selected.Id, token: token)
                            })
                            .id("\(token):\(selected.Id):\(selectedRole):preparation")
                    }
                }
            }
        }
        .task(id: "\(token):\(selectedStoreID):\(selectedRole)") {
            guard let selected = stores.first(where: { $0.Id == selectedStoreID }) else { return }
            let role = selectedRole
            if role == "owner" {
                do {
                    let result = try await api.members(storeID: selected.Id, token: token)
                    if isCurrent(storeID: selected.Id, role: role, token: token) { members = result }
                    let pending = try await api.storeInvitations(storeID: selected.Id, token: token)
                    if isCurrent(storeID: selected.Id, role: role, token: token) {
                        storeInvitations = pending
                    }
                } catch is CancellationError { }
                catch {
                    if isCurrent(storeID: selected.Id, role: role, token: token) {
                        setMessage(error.localizedDescription, isError: true)
                    }
                }
            }
            if !submissionKinds(for: role).isEmpty {
                do {
                    try await refreshSubmissionPage(storeID: selected.Id, token: token, role: role)
                } catch is CancellationError { }
                catch {
                    if isCurrent(storeID: selected.Id, role: role, token: token) {
                        setMessage(error.localizedDescription, isError: true)
                    }
                }
            }
        }
    }

    private func submissionSection(store: DineWiseStore, token: String) -> some View {
        let kinds = submissionKinds(for: selectedRole)
        let kind = kinds.contains(submissionKind) ? submissionKind : kinds.first ?? ""
        let invalidSelectedPurchasePlan = kind == "purchase" && selectedRole == "purchaser"
            && !purchasePlanId.isEmpty && !purchasePlans.contains(where: { $0.Id == purchasePlanId
                && canLinkPurchasePlan($0) })
        let isKitchenOutcome = kind == "kitchen" && selectedRole == "chef"
            && ["leftover", "sold_out"].contains(feedbackCategory)
        let invalidSelectedPreparationPlan = isKitchenOutcome
            && !preparationPlans.contains(where: { $0.Id == preparationPlanId
                && $0.BusinessDate == submissionDate && canLinkPreparationPlan($0) })
        return ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("资料与反馈").font(.title2.bold())
                Spacer()
                Button("刷新") {
                    let role = selectedRole
                    perform {
                        try await refreshSubmissionPage(storeID: store.Id, token: token, role: role)
                    }
                }
                .disabled(busy)
            }
            if !submissionPlanFilter.isEmpty {
                Text("\(submissionPlanFilterKind == "purchase" ? "订货计划" : "备菜单") \(submissionPlanFilter) 的关联\(submissionPlanFilterKind == "purchase" ? "进货资料" : "后厨记录")").font(.headline)
                Text("\(selectedRole == "owner" ? "本店全部关联资料" : "仅当前岗位由本人提交的关联资料") · 共 \(submissionTotal) 份")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("查看全部资料") {
                    submissionPlanFilter = ""; submissionPage = 1
                    let role = selectedRole
                    perform { try await refreshSubmissionPage(storeID: store.Id, token: token, role: role) }
                }.buttonStyle(.bordered)
            }
            Picker("资料状态", selection: $submissionStatusFilter) {
                Text("全部资料").tag("")
                Text("只看待核对").tag("pending_review")
            }
            .onChange(of: submissionStatusFilter) { _, _ in
                submissionPage = 1
                let role = selectedRole
                perform { try await refreshSubmissionPage(storeID: store.Id, token: token, role: role) }
            }
            Text("原始文字待核对确认后才能用于经营报告。图片和报表附件可作核对凭证，暂不自动识别。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("资料类型", selection: $submissionKind) {
                ForEach(kinds, id: \.self) { item in
                    Text(kindName(item)).tag(item)
                }
            }
            .onChange(of: submissionKind) { _, _ in pendingSubmissionKey = nil }
            DineWisePlaceholderField("营业日期 YYYY-MM-DD", isEmpty: submissionDate.isEmpty) {
                TextField("", text: $submissionDate)
                    .textFieldStyle(.plain)
                    .onChange(of: submissionDate) { _, _ in pendingSubmissionKey = nil }
            }
            if kind == "channel_settlement" {
                Text("每个渠道、每个营业日单独提交；按平台或收银结算单填写原文并上传凭证。退款、优惠承担方和费用需逐项核对，确认后才进入月报。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if kind == "recipe" {
                Text("每条资料记录一道菜的一种食材；同一配方版本须逐种食材提交并填写生效营业日。确认后，月报仅在配方、唯一销量和近 90 天最近唯一同规格公斤进价齐备时估算逐菜食材成本；资料重复或不全时不计算。估算不代表全店耗用或毛利。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if kind == "dish_sales" {
                Text("按营业日和菜品录入已核对的售出份数，每个菜品每天一条。月报会在唯一销量、当日有效配方和近 90 天最近唯一同规格公斤进价齐备时估算逐菜食材成本；重复或资料不全时不计算。估算不代表全店耗用或毛利。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if kind == "purchase" && selectedRole == "purchaser" {
                Picker("关联订货计划", selection: $purchasePlanId) {
                    Text("不关联计划").tag("")
                    if invalidSelectedPurchasePlan {
                        Text("原计划不在可关联列表").tag(purchasePlanId)
                    }
                    ForEach(purchasePlans.filter(canLinkPurchasePlan)) { plan in
                        Text("\(plan.BusinessDate) · 计划 \(plan.Id)").tag(plan.Id)
                    }
                }
                .onChange(of: purchasePlanId) { _, _ in pendingSubmissionKey = nil }
                Button("刷新订货计划") {
                    let role = selectedRole
                    perform {
                        let plans = try await api.purchasePlans(storeID: store.Id, token: token, role: role)
                        if isCurrent(storeID: store.Id, role: role, token: token) { purchasePlans = plans }
                    }
                }
                if invalidSelectedPurchasePlan {
                    Text("所选订货计划不在当前可关联列表中；请刷新或重新选择，也可明确选择“不关联计划”。")
                        .font(.footnote).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                }
                if let plan = purchasePlans.first(where: { $0.Id == purchasePlanId
                    && canLinkPurchasePlan($0) }) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("订货计划参考 · \(plan.BusinessDate)").font(.subheadline.bold())
                        ForEach(Array(plan.OrderItems.enumerated()), id: \.offset) { _, item in
                            if item.OrderQuantity > 0 {
                                let unit = ["kg": "公斤", "piece": "件", "portion": "份"][item.Unit] ?? item.Unit
                                Text("\(item.IngredientName)：拟订 \(NSDecimalNumber(decimal: item.OrderQuantity).stringValue) \(unit)"
                                    + (item.PackageSpecification.isEmpty ? "" : " · \(item.PackageSpecification)")
                                    + (item.SupplierName.isEmpty ? "" : " · 拟选 \(item.SupplierName)"))
                            }
                        }
                        Text("以上是计划数量；实际进货数量、单价与供应商以进货单为准。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                if !purchasePlanId.isEmpty {
                    Text("关联后请核对食材、规格、数量、每公斤单价与供应商，并上传进货单附件，才能确认实际进货资料。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if kind == "kitchen" || kind == "operations" {
                Picker("反馈分类", selection: $feedbackCategory) {
                    ForEach(["complaint", "return", "personnel", "equipment", "other"]
                        + (selectedRole == "chef" ? ["leftover", "sold_out"] : []), id: \.self) { category in
                        Text(feedbackName(category)).tag(category)
                    }
                }
                .onChange(of: feedbackCategory) { _, _ in pendingSubmissionKey = nil }
                if selectedRole == "chef" && ["leftover", "sold_out"].contains(feedbackCategory) {
                    Picker("关联备菜单", selection: $preparationPlanId) {
                        Text("请选择同日备菜单").tag("")
                        if !preparationPlanId.isEmpty && invalidSelectedPreparationPlan {
                            Text("原计划不可关联").tag(preparationPlanId)
                        }
                        ForEach(preparationPlans.filter(canLinkPreparationPlan)) { plan in
                            Text("\(plan.BusinessDate) · 备菜单 \(plan.Id)").tag(plan.Id)
                        }
                    }
                    .onChange(of: preparationPlanId) { _, id in
                        if let plan = preparationPlans.first(where: { $0.Id == id }) {
                            submissionDate = plan.BusinessDate
                        }
                        pendingSubmissionKey = nil
                    }
                    Button("刷新备菜单") {
                        perform {
                            let plans = try await api.preparationPlans(storeID: store.Id, token: token, role: "chef")
                            if isCurrent(storeID: store.Id, role: "chef", token: token) { preparationPlans = plans }
                        }
                    }
                    if invalidSelectedPreparationPlan {
                        Text("请选择本人同日已确认且来源有效的备菜单。")
                            .font(.footnote).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                    }
                    Text("请写明菜品、实际剩余或沽清情况与发生时间；数量和原因以现场记录为准，提交后仍需人工核对。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                DineWiseDateTimePickerField(title: "发生时间（设备当地时间）",
                    selection: $feedbackOccurredAt,
                    displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: feedbackOccurredAt) { _, _ in pendingSubmissionKey = nil }
                Text("只记录现场事实与原话；人员反馈不自动判断离职或责任。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            TextEditor(text: Binding(get: { originalText }, set: { value in
                let limited = dineWiseTextPrefix(value, maximumUTF16Length: 4000)
                originalText = limited.value
                originalTextLimitMessage = limited.truncated
                    ? "原始内容最多 4,000 字，超出部分未加入。"
                    : ""
            }))
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))
                .onChange(of: originalText) { _, value in
                    pendingSubmissionKey = nil
                    if value.utf16.count < 4000 { originalTextLimitMessage = "" }
                    if speechInsertSnapshot == value { speechInsertSnapshot = nil }
                    else if imageOcrInsertSnapshot == value { imageOcrInsertSnapshot = nil }
                    else if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        speechTextAppended = false
                        imageOcrTextAppended = false
                        textOrigin = "typed"
                    } else {
                        textOrigin = speechTextAppended || imageOcrTextAppended ? "mixed" : "typed"
                    }
                }
            HStack {
                Text("原文长度 \(originalText.utf16.count) / 4,000")
                Spacer()
                if !originalTextLimitMessage.isEmpty {
                    Text(originalTextLimitMessage)
                        .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            PhotosPicker(selection: $selectedOcrPhoto, matching: .images) {
                Label("从图片识别原文", systemImage: "text.viewfinder")
            }
            .disabled(isRecognizingImage)
            .onChange(of: selectedOcrPhoto) { _, selection in
                guard let selection else { return }
                let requestedStoreID = selectedStoreID
                let requestedRole = selectedRole
                let requestedToken = token
                isRecognizingImage = true
                imageOcrMessage = ""
                recognitionFailureCode = nil
                recognitionFailureImage = nil; recognitionFailureImageName = ""
                let fileExtension = selection.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let sourceImageName = "识别原图.\(fileExtension)"
                Task {
                    var sourceImageData: Data?
                    defer {
                        if isCurrent(storeID: requestedStoreID, role: requestedRole, token: requestedToken) {
                            isRecognizingImage = false
                            selectedOcrPhoto = nil
                        }
                    }
                    do {
                        guard let data = try await selection.loadTransferable(type: Data.self) else {
                            if isCurrent(storeID: requestedStoreID, role: requestedRole, token: requestedToken) {
                                recognitionFailureCode = "image_unreadable"
                                imageOcrMessage = "图片无效或超过 10 MB，请重新选择。"
                            }
                            return
                        }
                        sourceImageData = data
                        guard data.count <= 10 * 1024 * 1024 else {
                            if isCurrent(storeID: requestedStoreID, role: requestedRole, token: requestedToken) {
                                recognitionFailureCode = "image_unreadable"
                                imageOcrMessage = "图片超过 10 MB 附件上限；请压缩后重新选择，原图不会被上传。"
                            }
                            return
                        }
                        let recognized = try await Task.detached(priority: .userInitiated) {
                            try dineWiseRecognizeImageText(data)
                        }.value.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard isCurrent(storeID: requestedStoreID, role: requestedRole, token: requestedToken) else { return }
                        guard !recognized.isEmpty else {
                            recognitionFailureCode = "no_text_detected"
                            recognitionFailureImage = data; recognitionFailureImageName = sourceImageName
                            imageOcrMessage = "没有识别到文字，请换一张清晰图片或手动录入。"
                            return
                        }
                        let existingText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let baseText = originalText.trimmingCharacters(in: .newlines)
                        let separator = existingText.isEmpty ? "" : "\n"
                        let available = max(0, 4000 - baseText.utf16.count - separator.utf16.count)
                        let appendResult = dineWiseTextPrefix(recognized, maximumUTF16Length: available)
                        guard !appendResult.value.isEmpty else {
                            recognitionFailureCode = nil
                            imageOcrMessage = "原始内容已达到 4,000 字上限，未加入本次识别结果；请先精简或分次录入。"
                            return
                        }
                        let nextText = "\(baseText)\(separator)\(appendResult.value)"
                        imageOcrTextAppended = true
                        recognitionFailureCode = nil
                        recognitionFailureImage = nil; recognitionFailureImageName = ""
                        imageOcrInsertSnapshot = nextText
                        originalTextLimitMessage = ""
                        textOrigin = existingText.isEmpty && !speechTextAppended ? "image_ocr" : "mixed"
                        originalText = nextText
                        imageOcrMessage = appendResult.truncated
                            ? "识别结果超出 4,000 字限制，已加入可容纳部分；请核对并分次补录余下内容。"
                            : "识别结果已加入原文，请核对后再提交。图片仅在本机处理。"
                        pendingSubmissionKey = nil
                    } catch let error as DineWiseImageRecognitionError {
                        if isCurrent(storeID: requestedStoreID, role: requestedRole, token: requestedToken) {
                            recognitionFailureCode = error == .invalidImage ? "image_unreadable" : "recognition_failed"
                            recognitionFailureImage = sourceImageData
                            recognitionFailureImageName = sourceImageData == nil ? "" : sourceImageName
                            imageOcrMessage = error.localizedDescription
                        }
                    } catch {
                        if isCurrent(storeID: requestedStoreID, role: requestedRole, token: requestedToken) {
                            recognitionFailureCode = "image_unreadable"
                            recognitionFailureImage = sourceImageData
                            recognitionFailureImageName = sourceImageData == nil ? "" : sourceImageName
                            imageOcrMessage = "无法读取所选图片，请重新选择或手动录入。"
                        }
                    }
                }
            }
            if isRecognizingImage {
                ProgressView("正在识别图片…")
            }
            Text("图片识别始终在本机进行；仅识别失败并提交资料时，原图才作为加密附件上传。")
                .font(.footnote).foregroundStyle(.secondary)
            if !imageOcrMessage.isEmpty {
                Text(imageOcrMessage).font(.footnote).foregroundStyle(.secondary)
            }
            if recognitionFailureCode != nil {
                Text(recognitionFailureImage == nil
                    ? "提交时只附带异常类别；请重新选择可读取且不超过 10 MB 的原图附件后再确认。"
                    : "提交时会将原图作为加密附件保存到当前资料，供获授权门店成员核对；异常类别仅作排查提示。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let pendingRecognitionUpload {
                VStack(alignment: .leading, spacing: 8) {
                    Text("资料已提交，识别原图尚未保存。")
                    Text("请保持页面打开并重试上传。单个附件最大 10 MB；原图不可读时，可从资料附件入口重新选择。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("重试上传原图") {
                        retryRecognitionUpload(pendingRecognitionUpload,
                            storeID: store.Id, token: token, role: selectedRole)
                    }
                    .disabled(busy)
                }
                .padding(10)
                .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 12))
            }
            if textOrigin != "typed" {
                Text("文字来源：\(dineWiseTextOriginName(textOrigin)) · 提交前请核对原文。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Button(speechTranscriber.isRecording ? "结束语音输入" : "语音转写") {
                    speechTranscriber.toggle()
                }
                .disabled(speechTranscriber.isPreparing)
                Text("仅使用离线识别；提交前请核对文字。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !speechTranscriber.message.isEmpty {
                Text(speechTranscriber.message).font(.footnote).foregroundStyle(.secondary)
            }
            if !speechTranscriber.transcription.isEmpty {
                TextEditor(text: $speechTranscriber.transcription)
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))
                    .accessibilityLabel("语音转写，请核对")
                Button("加入原始资料") {
                    let existingText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let separator = existingText.isEmpty ? "" : "\n"
                    let speechText = speechTranscriber.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
                    let available = max(0, 4000 - existingText.utf16.count - separator.utf16.count)
                    let appendResult = dineWiseTextPrefix(speechText, maximumUTF16Length: available)
                    guard !appendResult.truncated else {
                        originalTextLimitMessage = "剩余空间不足，语音草稿未加入；请先精简原文后重试。"
                        return
                    }
                    let nextText = "\(existingText)\(separator)\(appendResult.value)"
                    originalTextLimitMessage = ""
                    speechTextAppended = true
                    speechInsertSnapshot = nextText
                    textOrigin = existingText.isEmpty ? "speech_transcription" : "mixed"
                    originalText = nextText
                    speechTranscriber.transcription = ""
                }
                .disabled(speechTranscriber.transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button("提交待核对资料") {
                let role = selectedRole
                let date = submissionDate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard dineWiseValidBusinessDate(date) else {
                    setMessage("营业日期无效，请按 YYYY-MM-DD 填写真实日期。", isError: true)
                    return
                }
                let text = originalText
                let source = textOrigin
                let recognitionFailure = recognitionFailureCode
                let recognitionImage = recognitionFailure == nil ? nil : recognitionFailureImage
                let recognitionImageSha256 = recognitionImage.map {
                    SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
                }
                let recognitionImageName = recognitionFailureImageName
                let category = kind == "kitchen" || kind == "operations" ? feedbackCategory : nil
                let occurredAt = category == nil ? nil : ISO8601DateFormatter().string(from: feedbackOccurredAt)
                let linkedPlanId = kind == "purchase" && role == "purchaser" && !purchasePlanId.isEmpty
                    ? purchasePlanId : nil
                let linkedPreparationId = isKitchenOutcome ? preparationPlanId : nil
                var payload = ["Kind": kind, "BusinessDate": date, "OriginalText": text,
                    "TextOrigin": source]
                if let recognitionFailure { payload["RecognitionFailureCode"] = recognitionFailure }
                if let recognitionImageSha256 {
                    payload["RecognitionFailureImageSha256"] = recognitionImageSha256
                }
                if let category, let occurredAt {
                    payload["FeedbackCategory"] = category
                    payload["OccurredAtUtc"] = occurredAt
                }
                if let linkedPlanId { payload["PurchasePlanId"] = linkedPlanId }
                if let linkedPreparationId { payload["PreparationPlanId"] = linkedPreparationId }
                let retry = pendingWriteRetryKey(
                    scope: "\(sessionUserID):\(store.Id):\(role)", payload: payload)
                pendingSubmissionKey = retry.key
                perform {
                    let submitted = try await api.submitText(storeID: store.Id, token: token,
                        role: role, kind: kind, businessDate: date,
                        originalText: text, feedbackCategory: category,
                        textOrigin: source,
                        recognitionFailureCode: recognitionFailure,
                        recognitionFailureImageSha256: recognitionImageSha256,
                        occurredAtUtc: occurredAt, purchasePlanId: linkedPlanId,
                        preparationPlanId: linkedPreparationId,
                        idempotencyKey: retry.key)
                    clearPendingWriteRetryKey(retry)
                    guard isCurrent(storeID: store.Id, role: role, token: token) else { return }
                    var recognitionUploadFailed = false
                    var recognitionImageUploaded = false
                    if isCurrent(storeID: store.Id, role: role, token: token) {
                        // 收到写入成功回执后即结束原草稿，列表刷新失败不能诱发重复提交。
                        if pendingSubmissionKey == retry.key {
                            originalText = ""
                            originalTextLimitMessage = ""
                            textOrigin = "typed"; speechTextAppended = false; imageOcrTextAppended = false
                            imageOcrInsertSnapshot = nil; selectedOcrPhoto = nil; isRecognizingImage = false
                            imageOcrMessage = ""; speechInsertSnapshot = nil
                            recognitionFailureCode = nil
                            recognitionFailureImage = nil; recognitionFailureImageName = ""
                            purchasePlanId = ""
                            preparationPlanId = ""
                            pendingSubmissionKey = nil
                        }
                        if recognitionFailure != nil, let recognitionImage {
                            let digest = recognitionImageSha256 ?? SHA256.hash(data: recognitionImage)
                                .map { String(format: "%02x", $0) }.joined()
                            let fileName = recognitionImageName.isEmpty ? "识别原图.jpg" : recognitionImageName
                            let uploadPayload = ["Operation": "upload_file", "FileName": fileName,
                                "SizeBytes": String(recognitionImage.count), "Sha256": digest,
                                "IsRecognitionOriginal": "true"]
                            let uploadRetry = pendingWriteRetryKey(
                                scope: "\(sessionUserID):\(store.Id):\(role):\(submitted.Id):file",
                                payload: uploadPayload)
                            let pending = PendingDineWiseRecognitionImage(
                                submissionID: submitted.Id,
                                fileName: fileName,
                                data: recognitionImage,
                                retryKey: uploadRetry)
                            pendingRecognitionUpload = pending
                            do {
                                try await api.uploadFile(storeID: store.Id,
                                    submissionID: submitted.Id, token: token, role: role,
                                    fileName: pending.fileName, data: pending.data,
                                    idempotencyKey: pending.retryKey.key,
                                    isRecognitionOriginal: true)
                                clearPendingWriteRetryKey(pending.retryKey)
                                recognitionImageUploaded = true
                                if isCurrent(storeID: store.Id, role: role, token: token),
                                   pendingRecognitionUpload?.retryKey.key == pending.retryKey.key {
                                    pendingRecognitionUpload = nil
                                }
                            } catch {
                                recognitionUploadFailed = true
                                setMessage("资料已提交，但识别原图上传失败；可在本页重试。", isError: true)
                            }
                        } else if recognitionFailure != nil {
                            setMessage("资料与异常类别已提交；原图不可读取或超过 10 MB，请在资料附件入口重新选择原图后再确认。", isError: true)
                        }
                        let refreshVersion = submissionRequestVersion + 1
                        do {
                            try await refreshSubmissionPage(storeID: store.Id, token: token, role: role)
                            if refreshVersion == submissionRequestVersion
                                && isCurrent(storeID: store.Id, role: role, token: token) {
                                if !recognitionUploadFailed && recognitionFailure == nil {
                                    setMessage("资料已提交，等待核对。")
                                } else if recognitionImageUploaded {
                                    setMessage("资料和识别原图已保存，等待核对。")
                                }
                            }
                        } catch {
                            if refreshVersion == submissionRequestVersion
                                && isCurrent(storeID: store.Id, role: role, token: token) {
                                setMessage("资料已提交，但资料列表刷新失败；请点重试。", isError: true)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || pendingRecognitionUpload != nil || isRecognizingImage || invalidSelectedPurchasePlan || invalidSelectedPreparationPlan || submissionDate.isEmpty
                || originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if submissionLoadState == "idle" || submissionLoadState == "loading" {
                ProgressView("正在读取资料…")
            } else if submissionLoadState == "error" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("资料列表读取失败").font(.subheadline.weight(.semibold))
                    if !message.isEmpty {
                        Text(message).font(.footnote)
                            .foregroundStyle(messageIsError
                                ? DineWiseTheme.danger(for: colorScheme)
                                : DineWiseTheme.accent(for: colorScheme))
                    }
                    Button("重试") {
                        let role = selectedRole
                        perform { try await refreshSubmissionPage(storeID: store.Id,
                            token: token, role: role) }
                    }
                    .buttonStyle(.bordered)
                }
            } else if submissions.isEmpty {
                Text(submissionStatusFilter == "pending_review"
                     ? "当前没有待核对资料。" : "暂无当前岗位可见的提交记录。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(submissions) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(kindName(item.Kind)) · \(item.BusinessDate)").font(.headline)
                    Text("\(roleName(item.SubmittedRole)) · \(submissionStatus(item.Status))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let linkedPlanId = item.PurchasePlanId {
                        Text("关联订货计划 \(linkedPlanId) · 实际进货资料")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let linkedPreparationId = item.PreparationPlanId {
                        Text("关联备菜单 \(linkedPreparationId) · 现场结果待核对")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let category = item.FeedbackCategory {
                        Text("\(feedbackName(category)) · \(item.OccurredAtUtc.map { dineWiseFormatTimestamp($0, timeZoneID: store.TimeZone) } ?? "发生时间待补")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if item.Status == "withdrawn" {
                        Text("原始资料已撤回，不再展示原文和附件。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(item.OriginalText)
                    }
                    Button("核对字段") { reviewSubmission = item }
                        .buttonStyle(.bordered)
                    if item.Status != "withdrawn" {
                        VStack(alignment: .leading, spacing: 8) {
                            if item.Status == "pending_review" && item.SubmittedByUserId == sessionUserID
                                && item.SubmittedRole == selectedRole && item.RecognitionFailureCode != nil
                                && !(filesBySubmission[item.Id] ?? []).contains(where: { $0.IsRecognitionOriginal == true }) {
                                Toggle("将所选图片标记为识别失败原图", isOn: Binding(
                                    get: { recognitionOriginalUploadSubmissionIDs.contains(item.Id) },
                                    set: { selected in
                                        if selected { recognitionOriginalUploadSubmissionIDs.insert(item.Id) }
                                        else { recognitionOriginalUploadSubmissionIDs.remove(item.Id) }
                                    }))
                                .font(.caption)
                                if recognitionOriginalUploadSubmissionIDs.contains(item.Id) {
                                    Text("请尽量选择提交时识别的同一张原图；若本资料保存了摘要，服务端会比对。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                Button("查看附件") {
                                    let role = selectedRole
                                    perform {
                                        let files = try await api.files(storeID: store.Id,
                                            submissionID: item.Id, token: token, role: role)
                                        if isCurrent(storeID: store.Id, role: role, token: token) {
                                            filesBySubmission[item.Id] = files
                                        }
                                    }
                                }
                                if item.Status == "pending_review" && item.SubmittedByUserId == sessionUserID
                                    && item.SubmittedRole == selectedRole {
                                    Button("上传附件") {
                                        fileTargetSubmissionID = item.Id
                                        showFileImporter = true
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if item.Status != "withdrawn" { ForEach(filesBySubmission[item.Id] ?? []) { file in
                        Button("下载 \(file.FileName)\(file.IsRecognitionOriginal == true ? " · 识别原图" : "") · \(file.SizeBytes / 1024) KB") {
                            let role = selectedRole
                            perform {
                                let data = try await api.downloadFile(storeID: store.Id,
                                    submissionID: item.Id, fileID: file.Id,
                                    token: token, role: role)
                                if isCurrent(storeID: store.Id, role: role, token: token) {
                                    exportName = file.FileName
                                    exportDocument = DineWiseAttachmentDocument(data: data)
                                    showFileExporter = true
                                }
                            }
                        }
                        .font(.caption)
                    } }
                }
                    .id("submission-\(item.Id)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if submissionLoadState == "loaded" && submissionTotal > 20 {
                HStack {
                    Button("上一页") {
                        submissionPage -= 1
                        let role = selectedRole
                        perform { try await refreshSubmissionPage(storeID: store.Id, token: token, role: role) }
                    }.disabled(submissionPage <= 1)
                    Text("第 \(submissionPage) 页 · 共 \(submissionTotal) 份")
                    Button("下一页") {
                        submissionPage += 1
                        let role = selectedRole
                        perform { try await refreshSubmissionPage(storeID: store.Id, token: token, role: role) }
                    }.disabled(submissionPage * 20 >= submissionTotal)
                }.buttonStyle(.bordered)
            }
        }
        .padding()
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .task(id: "\(store.Id):\(selectedRole):\(token)") {
            if selectedRole == "chef" {
                let plans = try? await api.preparationPlans(storeID: store.Id, token: token, role: "chef")
                if let plans, isCurrent(storeID: store.Id, role: "chef", token: token) {
                    preparationPlans = plans
                }
            }
            guard selectedRole == "purchaser" else { return }
            let plans = try? await api.purchasePlans(storeID: store.Id, token: token, role: "purchaser")
            if let plans, isCurrent(storeID: store.Id, role: "purchaser", token: token) {
                purchasePlans = plans
            }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: recognitionOriginalUploadSubmissionIDs.contains(fileTargetSubmissionID ?? "")
                        ? [.image] : [.item]) { result in
            guard let submissionID = fileTargetSubmissionID else { return }
            fileTargetSubmissionID = nil
            let isRecognitionOriginal = recognitionOriginalUploadSubmissionIDs.contains(submissionID)
            switch result {
            case .success(let url):
                let role = selectedRole
                perform {
                    guard url.startAccessingSecurityScopedResource() else {
                        throw DineWiseAPIError.failed("无法读取所选文件。")
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                       size > 10 * 1024 * 1024 {
                        throw DineWiseAPIError.failed("单个附件不能超过 10 MB。")
                    }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    var data = Data()
                    while data.count <= 10 * 1024 * 1024 {
                        let chunk = try handle.read(upToCount:
                            min(8192, 10 * 1024 * 1024 + 1 - data.count)) ?? Data()
                        if chunk.isEmpty { break }
                        data.append(chunk)
                    }
                    if data.count > 10 * 1024 * 1024 {
                        throw DineWiseAPIError.failed("单个附件不能超过 10 MB。")
                    }
                    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    let fileName = url.lastPathComponent
                    let retry = pendingWriteRetryKey(
                        scope: "\(sessionUserID):\(store.Id):\(role):\(submissionID):file",
                        payload: ["Operation": "upload_file", "FileName": fileName,
                                  "SizeBytes": String(data.count), "Sha256": digest,
                                  "IsRecognitionOriginal": String(isRecognitionOriginal)])
                    try await api.uploadFile(storeID: store.Id, submissionID: submissionID,
                        token: token, role: role, fileName: fileName,
                        data: data, idempotencyKey: retry.key,
                        isRecognitionOriginal: isRecognitionOriginal)
                    if isCurrent(storeID: store.Id, role: role, token: token) {
                        if isRecognitionOriginal { recognitionOriginalUploadSubmissionIDs.remove(submissionID) }
                        fileUploadRevisions[submissionID, default: 0] += 1
                        let files = try await api.files(
                            storeID: store.Id, submissionID: submissionID,
                            token: token, role: role)
                        if isCurrent(storeID: store.Id, role: role, token: token) {
                            filesBySubmission[submissionID] = files
                            clearPendingWriteRetryKey(retry)
                        }
                    }
                }
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    setMessage(error.localizedDescription, isError: true)
                }
            }
        }
        .fileExporter(isPresented: $showFileExporter, document: exportDocument,
                      contentType: .data, defaultFilename: exportName) { result in
            if case .failure(let error) = result { setMessage(error.localizedDescription, isError: true) }
            exportDocument = nil
        }
        .onChange(of: submissions.map(\.Id) + [focusedSubmissionID]) { _, _ in
            guard !focusedSubmissionID.isEmpty,
                  submissions.contains(where: { $0.Id == focusedSubmissionID }) else { return }
            let targetID = focusedSubmissionID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                proxy.scrollTo("submission-\(targetID)", anchor: .center)
                focusedSubmissionID = ""
            }
        }
        }
    }

    private func submissionKinds(for role: String) -> [String] {
        switch role {
        case "owner": ["operating", "channel_settlement", "dish_sales", "recipe", "purchase"]
        case "manager": ["operating", "dish_sales", "kitchen", "operations"]
        case "chef": ["kitchen", "recipe"]
        case "purchaser": ["purchase"]
        case "operator": ["operations"]
        default: []
        }
    }

    private func kindName(_ kind: String) -> String {
        switch kind {
        case "operating": "经营资料"
        case "channel_settlement": "渠道结算"
        case "recipe": "菜品配方"
        case "dish_sales": "菜品销量"
        case "purchase": "采购资料"
        case "kitchen": "后厨反馈"
        case "operations": "运营反馈"
        default: kind
        }
    }

    private func feedbackName(_ category: String) -> String {
        switch category {
        case "complaint": "客诉"
        case "return": "退菜"
        case "personnel": "人员"
        case "equipment": "设备"
        case "leftover": "备菜剩余"
        case "sold_out": "菜品沽清"
        default: "其他"
        }
    }

    private func submissionStatus(_ status: String) -> String {
        switch status {
        case "pending_review": "待核对"
        case "confirmed": "已确认"
        case "abandoned": "已放弃"
        case "withdrawn": "已撤回"
        default: "状态未知"
        }
    }

    private func memberSection(store: DineWiseStore, token: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("岗位授权").font(.title2.bold())
                Spacer()
                Button("刷新") {
                    perform {
                        let result = try await api.members(storeID: store.Id, token: token)
                        let pending = try await api.storeInvitations(storeID: store.Id, token: token)
                        if isCurrent(storeID: store.Id, role: "owner", token: token) {
                            members = result
                            storeInvitations = pending
                        }
                    }
                }
                .disabled(busy)
            }
            Text("岗位授权由门店老板在餐有数中管理；账号已停用时，需先联系平台管理员重新开通账号。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(memberEventsLoaded ? "刷新岗位变更记录" : "查看岗位变更记录") {
                perform {
                    let result = try await api.memberEvents(storeID: store.Id, token: token)
                    if isCurrent(storeID: store.Id, role: "owner", token: token) {
                        memberEvents = result
                        memberEventsLoaded = true
                        memberEventsCanLoadMore = result.count == 50
                    }
                }
            }
            .disabled(busy)
            if memberEventsLoaded {
                if memberEvents.isEmpty {
                    Text("暂无岗位变更记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(memberEvents) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(dineWiseMemberActionName(event.Action)) · \(roleName(event.Role))")
                                .font(.subheadline.weight(.medium))
                            Text("\(event.Actor == "store_owner" ? "门店老板" : "受邀成员") · \(event.Reason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(dineWiseLocalizedTimestamp(event.ActedAtUtc))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if memberEventsCanLoadMore, let beforeID = memberEvents.last?.Id {
                        Button("查看更多记录") {
                            perform {
                                let older = try await api.memberEvents(storeID: store.Id,
                                    token: token, beforeID: beforeID)
                                if isCurrent(storeID: store.Id, role: "owner", token: token) {
                                    let existing = Set(memberEvents.map(\.Id))
                                    memberEvents.append(contentsOf: older.filter { !existing.contains($0.Id) })
                                    memberEventsCanLoadMore = older.count == 50
                                }
                            }
                        }
                        .disabled(busy)
                    }
                }
            }
            ForEach(members) { member in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(member.Username ?? member.Email ?? "账号已停用")
                        Text("\(roleName(member.Role)) · \(member.Enabled ? "有效" : "已撤回")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if member.Enabled && member.Role != "owner" {
                        Button("撤回", role: .destructive) {
                            memberToRevoke = member
                            showRevokeAlert = true
                        }
                        .disabled(busy)
                    } else if !member.Enabled && member.Role != "owner" {
                        Button("恢复") {
                            let payload = ["MemberId": member.Id, "Action": "restore"]
                            let retry = pendingWriteRetryKey(
                                scope: "\(sessionUserID):\(store.Id):member:\(member.Id):restore", payload: payload)
                            perform {
                                _ = try await api.restoreMember(storeID: store.Id, memberID: member.Id,
                                    token: token, idempotencyKey: retry.key)
                                clearPendingWriteRetryKey(retry)
                                if isCurrent(storeID: store.Id, role: "owner", token: token) {
                                    members = members.map { item in
                                        guard item.Id == member.Id else { return item }
                                        return DineWiseMember(Id: item.Id, UserId: item.UserId,
                                            Email: item.Email, Username: item.Username,
                                            Role: item.Role, Enabled: true)
                                    }
                                    setMessage("岗位已恢复。")
                                    do { members = try await api.members(storeID: store.Id, token: token) }
                                    catch { setMessage("岗位已恢复；成员列表暂不可刷新，请稍后点“刷新”重试。") }
                                }
                            }
                        }
                        .disabled(busy)
                    }
                }
                .padding(.vertical, 5)
            }
            if members.isEmpty {
                Text("暂无成员记录，或正在加载。")
                    .foregroundStyle(.secondary)
            }
            TextField("成员用户名或邮箱", text: $memberEmail)
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
            Picker("授予岗位", selection: $memberRole) {
                ForEach(["manager", "chef", "purchaser", "operator"]
                    + (store.Mode == "demo" ? ["marketer"] : []), id: \.self) { role in
                    Text(roleName(role)).tag(role)
                }
            }
            Button("授予岗位") {
                let requestedEmail = memberEmail.trimmingCharacters(in: .whitespaces)
                let requestedRole = memberRole
                let payload = ["Identifier": requestedEmail, "Role": requestedRole]
                let retry = pendingWriteRetryKey(
                    scope: "\(sessionUserID):\(store.Id):member:grant", payload: payload)
                perform {
                    let granted = try await api.grantMember(storeID: store.Id, email: requestedEmail,
                        role: requestedRole, token: token, idempotencyKey: retry.key)
                    clearPendingWriteRetryKey(retry)
                    if isCurrent(storeID: store.Id, role: "owner", token: token) {
                        members = [granted] + members.filter { $0.Id != granted.Id }
                        memberEmail = ""
                        setMessage("岗位已授予。")
                        do {
                            let result = try await api.members(storeID: store.Id, token: token)
                            if isCurrent(storeID: store.Id, role: "owner", token: token) { members = result }
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            if isCurrent(storeID: store.Id, role: "owner", token: token) {
                                setMessage("岗位已授予；成员列表暂不可刷新，请稍后点“刷新”重试。")
                            }
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || memberEmail.isEmpty)
            Button("邀请未登录成员") {
                let requestedEmail = memberEmail.trimmingCharacters(in: .whitespaces).lowercased()
                let role = memberRole
                let payload = ["Email": requestedEmail, "Role": role]
                let retry = pendingWriteRetryKey(
                    scope: "\(sessionUserID):\(store.Id):invitation:create", payload: payload)
                perform {
                    try await api.inviteMember(storeID: store.Id, email: requestedEmail,
                        role: role, token: token, idempotencyKey: retry.key)
                    clearPendingWriteRetryKey(retry)
                    if isCurrent(storeID: store.Id, role: "owner", token: token) {
                        memberEmail = ""
                        let successMessage = "邀请邮件已提交，待成员确认。"
                        setMessage(successMessage)
                        do {
                            let pending = try await api.storeInvitations(storeID: store.Id,
                                token: token)
                            if isCurrent(storeID: store.Id, role: "owner", token: token) {
                                storeInvitations = pending
                            }
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            if isCurrent(storeID: store.Id, role: "owner", token: token) {
                                setMessage("\(successMessage) 邀请列表暂不可刷新，请稍后点“刷新”重试。",
                                           isError: true)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(busy || !memberEmail.contains("@"))
            ForEach(storeInvitations.filter { $0.Status == "pending" }) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.Email)
                        Text("\(roleName(item.Role)) · 待接受")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(item.EmailDelivered ? "通知已发送"
                            : item.EmailSending == true ? "邮件发送中" : "邮件待重试")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("有效至 \(dineWiseFormatTimestamp(item.ExpiresAtUtc, timeZoneID: item.StoreTimeZone))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !item.EmailDelivered && item.EmailSending != true {
                        Button("重试发送") {
                            let payload = ["InvitationId": item.Id, "Action": "resend_email"]
                            let retry = pendingWriteRetryKey(
                                scope: "\(sessionUserID):\(store.Id):invitation:\(item.Id):resend-email",
                                payload: payload)
                            perform {
                                try await api.resendInvitationEmail(storeID: store.Id,
                                    id: item.Id, token: token, idempotencyKey: retry.key)
                                clearPendingWriteRetryKey(retry)
                                guard isCurrent(storeID: store.Id, role: "owner", token: token) else { return }
                                setMessage("邀请邮件已重新提交。")
                                do {
                                    let pending = try await api.storeInvitations(storeID: store.Id,
                                        token: token)
                                    if isCurrent(storeID: store.Id, role: "owner", token: token) {
                                        storeInvitations = pending
                                    }
                                } catch is CancellationError {
                                    throw CancellationError()
                                } catch {
                                    if isCurrent(storeID: store.Id, role: "owner", token: token) {
                                        setMessage("邮件已提交；邀请列表暂不可刷新，请稍后刷新。",
                                                   isError: true)
                                    }
                                }
                            }
                        }
                        .disabled(busy)
                    }
                    Button("撤回邀请", role: .destructive) {
                        let payload = ["InvitationId": item.Id, "Action": "cancel"]
                        let retry = pendingWriteRetryKey(
                            scope: "\(sessionUserID):\(store.Id):invitation:\(item.Id):cancel",
                            payload: payload)
                        perform {
                            try await api.cancelInvitation(storeID: store.Id, id: item.Id,
                                token: token, idempotencyKey: retry.key)
                            clearPendingWriteRetryKey(retry)
                            if isCurrent(storeID: store.Id, role: "owner", token: token) {
                                setMessage("邀请已撤回。")
                                do {
                                    let pending = try await api.storeInvitations(storeID: store.Id,
                                        token: token)
                                    if isCurrent(storeID: store.Id, role: "owner", token: token) {
                                        storeInvitations = pending
                                    }
                                } catch is CancellationError {
                                    throw CancellationError()
                                } catch {
                                    if isCurrent(storeID: store.Id, role: "owner", token: token) {
                                        setMessage("邀请已撤回；列表暂不可刷新，请稍后点“刷新”重试。",
                                                   isError: true)
                                    }
                                }
                            }
                        }
                    }
                    .disabled(busy)
                }
            }
        }
        .padding()
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func updateStores(_ updated: [DineWiseStore]) {
        stores = updated
        if !updated.contains(where: { $0.Id == selectedStoreID }) {
            switchWorkspace(storeID: updated.first?.Id ?? "",
                            role: updated.first?.Roles.first ?? "")
        } else if let selected = updated.first(where: { $0.Id == selectedStoreID }),
                  !selected.Roles.contains(selectedRole) {
            switchWorkspace(storeID: selectedStoreID, role: selected.Roles.first ?? "")
        }
    }

    private func canLinkPurchasePlan(_ plan: DineWisePurchasePlan) -> Bool {
        plan.Status == "confirmed" && !plan.SourceInvalidated
            && plan.OrderItems.contains(where: { $0.OrderQuantity > 0 })
    }

    private func canLinkPreparationPlan(_ plan: DineWisePreparationPlan) -> Bool {
        plan.Status == "confirmed" && !plan.SourceInvalidated
    }

    private func roleName(_ role: String) -> String {
        switch role {
        case "owner": "老板"
        case "manager": "店长"
        case "chef": "厨师长"
        case "purchaser": "采购"
        case "operator": "门店运营"
        case "marketer": "营销"
        default: role.isEmpty ? "未授权" : role
        }
    }

    private func dineWiseMemberActionName(_ action: String) -> String {
        switch action {
        case "grant": "授予岗位"
        case "revoke": "撤回岗位"
        case "restore": "恢复岗位"
        default: "岗位变更"
        }
    }

    private func isCurrent(storeID: String, role: String, token: String) -> Bool {
        self.token == token && selectedStoreID == storeID && selectedRole == role
    }

    private func refreshSubmissionPage(storeID: String, token: String, role: String,
                                       focusID: String? = nil) async throws {
        submissionRequestVersion += 1
        let requestVersion = submissionRequestVersion
        let planID = submissionPlanFilter
        let planKind = submissionPlanFilterKind
        let statusFilter = submissionStatusFilter
        let page = submissionPage
        if isCurrent(storeID: storeID, role: role, token: token) {
            submissionLoadState = "loading"
        }
        do {
            let result = try await api.submissionPage(storeID: storeID, token: token,
                role: role, planID: planKind == "purchase" ? planID : "", page: page,
                preparationPlanID: planKind == "preparation" ? planID : "",
                status: statusFilter, focusID: focusID)
            if requestVersion == submissionRequestVersion
                && isCurrent(storeID: storeID, role: role, token: token)
                && submissionPlanFilter == planID && submissionPlanFilterKind == planKind
                && submissionStatusFilter == statusFilter
                && submissionPage == page {
                submissionTotal = result.Total
                submissions = result.Items
                submissionLoadState = "loaded"
            }
        } catch {
            if requestVersion == submissionRequestVersion
                && isCurrent(storeID: storeID, role: role, token: token)
                && submissionPlanFilter == planID && submissionPlanFilterKind == planKind
                && submissionStatusFilter == statusFilter && submissionPage == page {
                submissionLoadState = "error"
            }
            throw error
        }
    }

    private func openLinkedPurchases(_ plan: DineWisePurchasePlan, storeID: String, token: String) {
        guard isCurrent(storeID: storeID, role: selectedRole, token: token),
              selectedRole == "owner" || selectedRole == "purchaser" else { return }
        submissionPlanFilter = plan.Id
        submissionPlanFilterKind = "purchase"
        submissionPage = 1
        selectedTab = selectedRole == "owner" ? "materials" : "upload"
        let role = selectedRole
        perform { try await refreshSubmissionPage(storeID: storeID, token: token, role: role) }
    }

    private func openLinkedOutcomes(_ plan: DineWisePreparationPlan, storeID: String, token: String) {
        guard isCurrent(storeID: storeID, role: selectedRole, token: token),
              selectedRole == "owner" || selectedRole == "chef" else { return }
        submissionPlanFilterKind = "preparation"
        submissionPlanFilter = plan.Id
        submissionPage = 1
        selectedTab = selectedRole == "owner" ? "materials" : "upload"
        let role = selectedRole
        perform { try await refreshSubmissionPage(storeID: storeID, token: token, role: role) }
    }

    private func switchWorkspace(storeID: String, role: String) {
        todayFocus = nil
        guard selectedStoreID != storeID || selectedRole != role else { return }
        pushTaskFocusID = ""
        requestVersion += 1
        submissionRequestVersion += 1
        busy = false
        setMessage("")
        selectedStoreID = storeID
        selectedRole = role
        selectedTab = defaultTab(for: role)
        submissionStatusFilter = ""
        focusedSubmissionID = ""
        submissionKind = submissionKinds(for: role).first ?? "operating"
        members = []
        memberEvents = []; memberEventsLoaded = false; memberEventsCanLoadMore = false
        storeInvitations = []
        submissions = []
        submissionPlanFilter = ""
        submissionPage = 1
        submissionTotal = 0
        submissionLoadState = "idle"
        purchasePlans = []
        purchasePlanId = ""
        preparationPlans = []; preparationPlanId = ""
        filesBySubmission = [:]
        fileUploadRevisions = [:]
        exportDocument = nil
        showFileExporter = false
        fileTargetSubmissionID = nil
        recognitionOriginalUploadSubmissionIDs = []
        showFileImporter = false
        reviewSubmission = nil
        memberToRevoke = nil
        showRevokeAlert = false
        memberRole = "manager"
        memberEmail = ""
        submissionDate = ""
        originalText = ""
        originalTextLimitMessage = ""
        textOrigin = "typed"; speechTextAppended = false; imageOcrTextAppended = false
        imageOcrInsertSnapshot = nil; selectedOcrPhoto = nil; isRecognizingImage = false
        imageOcrMessage = ""; speechInsertSnapshot = nil
        recognitionFailureCode = nil
        recognitionFailureImage = nil; recognitionFailureImageName = ""
        pendingRecognitionUpload = nil
        feedbackCategory = "complaint"
        feedbackOccurredAt = Date()
        pendingSubmissionKey = nil
        storeName = ""
        pendingKey = nil
        showsEmailBinding = false
        showsDemoStoreEditor = false
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        requestVersion += 1
        let version = requestVersion
        let requestedToken = token
        let requestedStoreID = selectedStoreID
        let requestedRole = selectedRole
        busy = true
        setMessage("")
        Task { @MainActor in
            guard version == requestVersion && requestedToken == token &&
                    requestedStoreID == selectedStoreID && requestedRole == selectedRole else { return }
            defer { if version == requestVersion { busy = false } }
            do { try await action() }
            catch is CancellationError { }
            catch {
                if version == requestVersion && requestedToken == token &&
                    requestedStoreID == selectedStoreID && requestedRole == selectedRole {
                    setMessage(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func retryRecognitionUpload(_ pending: PendingDineWiseRecognitionImage,
        storeID: String, token: String, role: String) {
        perform {
            try await api.uploadFile(storeID: storeID, submissionID: pending.submissionID,
                token: token, role: role, fileName: pending.fileName, data: pending.data,
                idempotencyKey: pending.retryKey.key, isRecognitionOriginal: true)
            clearPendingWriteRetryKey(pending.retryKey)
            guard isCurrent(storeID: storeID, role: role, token: token),
                  pendingRecognitionUpload?.retryKey.key == pending.retryKey.key else { return }
            pendingRecognitionUpload = nil
            do {
                try await refreshSubmissionPage(storeID: storeID, token: token, role: role)
                if isCurrent(storeID: storeID, role: role, token: token) {
                    setMessage("资料和识别原图已保存，等待核对。")
                }
            } catch {
                setMessage("识别原图已保存，但资料列表刷新失败；请点重试。", isError: true)
            }
        }
    }

    private func setMessage(_ value: String, isError: Bool = false) {
        message = value
        messageIsError = isError
    }
}

private struct DineWiseBusinessHoursDraftPeriod: Identifiable {
    let id = UUID()
    var opensAt: Date
    var closesAt: Date
}

private func dineWiseDateForTime(_ value: String) -> Date {
    let parts = value.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return Date(timeIntervalSince1970: 0) }
    var components = DateComponents()
    components.year = 2001
    components.month = 1
    components.day = 1
    components.hour = parts[0]
    components.minute = parts[1]
    return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
}

private func dineWiseTimeString(_ value: Date) -> String {
    let components = Calendar.current.dateComponents([.hour, .minute], from: value)
    return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
}

private func dineWiseMinutesForTime(_ value: Date) -> Int {
    let components = Calendar.current.dateComponents([.hour, .minute], from: value)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
}

private enum DineWiseStoreProfileSection: Equatable {
    case basic
    case schedule
    case photo
}

private struct DineWiseStoreProfileEditor: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: DineWiseStore
    let token: String
    let onSaved: (DineWiseStore) -> Void
    @State private var name: String
    @State private var businessType: String
    @State private var address: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var introduction: String
    @State private var payments: Set<String>
    @State private var cutoff: String
    @State private var businessHours: [[DineWiseBusinessHoursDraftPeriod]]
    @State private var expandedBusinessDay: Int?
    @State private var expandedEditorSection: DineWiseStoreProfileSection?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var saving = false
    @State private var message = ""
    @State private var messageIsError = false
    @State private var saveSectionForNextVersion: DineWiseStoreProfileSection?
    @StateObject private var location = DineWiseLocationProvider()
    private let paymentOptions = ["wechat_pay": "微信支付", "alipay": "支付宝",
        "cash": "现金", "bank_card": "银行卡", "other": "其他"]

    init(store: DineWiseStore, token: String, onSaved: @escaping (DineWiseStore) -> Void) {
        self.store = store; self.token = token; self.onSaved = onSaved
        _name = State(initialValue: store.Name)
        _businessType = State(initialValue: store.BusinessType ?? "")
        _address = State(initialValue: store.Address ?? "")
        _latitude = State(initialValue: store.Latitude)
        _longitude = State(initialValue: store.Longitude)
        _introduction = State(initialValue: store.Introduction ?? "")
        _payments = State(initialValue: Set(store.PaymentMethods ?? []))
        _cutoff = State(initialValue: String(store.BusinessDayCutoffMinutes ?? 0))
        _businessHours = State(initialValue: dineWiseBusinessHoursText(store.BusinessHours).map { day in
            day.split(separator: ",").compactMap { segment in
                let pair = segment.split(separator: "-", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { return nil }
                return DineWiseBusinessHoursDraftPeriod(
                    opensAt: dineWiseDateForTime(pair[0].trimmingCharacters(in: .whitespaces)),
                    closesAt: dineWiseDateForTime(pair[1].trimmingCharacters(in: .whitespaces)))
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            editorSectionButton("门店基本资料", summary: basicProfileSummary,
                                expanded: expandedEditorSection == .basic) {
                toggleEditorSection(.basic)
            }
            if expandedEditorSection == .basic {
                VStack(alignment: .leading, spacing: 10) {
                    DineWisePlaceholderField("门店名称", isEmpty: name.isEmpty) {
                        TextField("", text: $name).textFieldStyle(.plain)
                    }
                    DineWisePlaceholderField("餐饮业态", isEmpty: businessType.isEmpty) {
                        TextField("", text: $businessType).textFieldStyle(.plain)
                    }
                    DineWisePlaceholderField("门店地址", isEmpty: address.isEmpty) {
                        TextField("", text: $address).textFieldStyle(.plain)
                    }
                    Text("定位仅在您点选并授权后获取；地址仍可手动填写。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("使用当前位置") { location.request() }
                        .buttonStyle(.bordered)
                    if let latitude, let longitude {
                        Text("位置：\(latitude, specifier: "%.6f"), \(longitude, specifier: "%.6f")（WGS84）")
                            .font(.footnote)
                        Button("清除定位，仅保留手填地址") {
                            self.latitude = nil; self.longitude = nil; location.clear()
                        }
                        .buttonStyle(.bordered)
                    }
                    if !location.error.isEmpty {
                        Text("\(location.error)；可手动填写地址继续。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    DineWisePlaceholderField("门店介绍", isEmpty: introduction.isEmpty,
                                             alignment: .topLeading, topPadding: 8) {
                        TextField("", text: $introduction, axis: .vertical)
                            .lineLimit(2...5).textFieldStyle(.plain)
                    }
                    ForEach(Array(paymentOptions.keys.sorted()), id: \.self) { key in
                        Toggle(paymentOptions[key] ?? key, isOn: Binding(
                            get: { payments.contains(key) },
                            set: { enabled in
                                if enabled { payments.insert(key) } else { payments.remove(key) }
                            }))
                    }
                }
                .padding(10)
                .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 12))
            }

            editorSectionButton("营业日期与时段", summary: businessHoursSummary,
                                expanded: expandedEditorSection == .schedule) {
                toggleEditorSection(.schedule)
            }
            if expandedEditorSection == .schedule {
                VStack(alignment: .leading, spacing: 10) {
                    Text("营业日期自动按门店时区记录；新建门店默认使用设备系统时区，无需手动设置。")
                        .font(.footnote).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button("全周连续营业") { applyBusinessHoursWeekPreset(periods: ["09:00-22:00"]) }
                                .buttonStyle(.bordered)
                            Button("全周午晚市") {
                                applyBusinessHoursWeekPreset(periods: ["09:00-14:00", "17:00-22:00"])
                            }
                            .buttonStyle(.bordered)
                        }
                        Button("全周早午晚市") {
                            applyBusinessHoursWeekPreset(periods: ["07:00-10:00", "11:00-14:00", "17:00-22:00"])
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("快速设置整周后，点选日期可查看摘要或展开调整。")
                        .font(.caption).foregroundStyle(.secondary)
                    DineWiseDateTimePickerField(title: "营业日切分时间", selection: Binding(
                        get: { dineWiseDateForTime(cutoffClockText) },
                        set: { cutoff = String(dineWiseMinutesForTime($0)) }),
                        displayedComponents: .hourAndMinute,
                        quickTimes: ["00:00", "02:00", "04:00", "06:00"])
                    Text("每天从此时间开始计入新的营业日。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("每天最多 4 段；关闭营业表示休息。打烊早于开门表示次日打烊，时段不能重叠。")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(dineWiseWeekdays.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedBusinessDay = expandedBusinessDay == index ? nil : index
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(dineWiseWeekdays[index])
                                            .font(.subheadline.weight(.semibold))
                                        Text(businessHoursDaySummary(index))
                                            .font(.footnote).foregroundStyle(.secondary)
                                            .lineLimit(1).minimumScaleFactor(0.75)
                                        Spacer(minLength: 4)
                                        Image(systemName: expandedBusinessDay == index ? "chevron.up" : "chevron.down")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(dineWiseWeekdays[index])，\(businessHoursDaySummary(index))")
                                .accessibilityValue(expandedBusinessDay == index ? "已展开" : "已收起")
                                .accessibilityHint("双击\(expandedBusinessDay == index ? "收起" : "展开")此日营业时段")
                                Spacer()
                                Toggle("营业", isOn: Binding(
                                    get: { !businessHours[index].isEmpty },
                                    set: { isOpen in
                                        if isOpen {
                                            if businessHours[index].isEmpty { addBusinessPeriod(dayIndex: index) }
                                            expandedBusinessDay = index
                                        } else {
                                            businessHours[index] = []
                                            if expandedBusinessDay == index { expandedBusinessDay = nil }
                                        }
                                    }))
                                .labelsHidden()
                                .accessibilityLabel("\(dineWiseWeekdays[index])营业状态")
                                .accessibilityValue(businessHours[index].isEmpty ? "休息" : "营业")
                                .accessibilityHint("双击切换该日是否营业")
                            }
                            if expandedBusinessDay == index {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Button("连续营业") {
                                            applyBusinessHoursPreset(dayIndex: index, periods: ["09:00-22:00"])
                                        }
                                        .buttonStyle(.bordered)
                                        Button("午晚市") {
                                            applyBusinessHoursPreset(dayIndex: index,
                                                periods: ["09:00-14:00", "17:00-22:00"])
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    Button("早午晚市") {
                                        applyBusinessHoursPreset(dayIndex: index,
                                            periods: ["07:00-10:00", "11:00-14:00", "17:00-22:00"])
                                    }
                                    .buttonStyle(.bordered)
                                    Text("快捷替换当天").font(.caption).foregroundStyle(.secondary)
                                }
                                Menu {
                                    Button("全周") {
                                        copyBusinessHours(dayIndex: index, targetDays: Array(dineWiseWeekdays.indices),
                                            targetName: "全周")
                                    }
                                    Divider()
                                    Button("周一至周五") {
                                        copyBusinessHours(dayIndex: index, targetDays: Array(0...4), targetName: "工作日")
                                    }
                                    Button("周六、周日") {
                                        copyBusinessHours(dayIndex: index, targetDays: Array(5...6), targetName: "周末")
                                    }
                                    Divider()
                                    ForEach(dineWiseWeekdays.indices.filter { $0 != index }, id: \.self) { targetDay in
                                        Button(dineWiseWeekdays[targetDay]) {
                                            copyBusinessHours(dayIndex: index, targetDays: [targetDay],
                                                targetName: dineWiseWeekdays[targetDay])
                                        }
                                    }
                                } label: {
                                    Label("复制到…", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                .disabled(businessHours[index].isEmpty)
                                Text("复制仅修改草稿，仍需保存。")
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(businessHours[index]) { period in
                                    let periodNumber = (businessHours[index].firstIndex(where: { $0.id == period.id }) ?? 0) + 1
                                    HStack(spacing: 8) {
                                        DineWiseDateTimePickerField(title: "开门",
                                            accessibilityTitle: "\(dineWiseWeekdays[index])时段\(periodNumber)开门时间",
                                            selection: Binding(
                                                get: { businessPeriod(id: period.id, dayIndex: index)?.opensAt ?? period.opensAt },
                                                set: { updateBusinessPeriod(id: period.id, dayIndex: index, opensAt: $0) }),
                                            displayedComponents: .hourAndMinute,
                                            quickTimes: ["07:00", "08:00", "09:00", "10:00", "11:00", "17:00",
                                                         "06:00", "08:30", "09:30", "12:00", "14:00", "16:00",
                                                         "18:00", "19:00"],
                                            validationMessage: { businessHoursValidationMessage(
                                                id: period.id, dayIndex: index, opensAt: $0) })
                                            .frame(maxWidth: .infinity)
                                        DineWiseDateTimePickerField(title: "打烊",
                                                accessibilityTitle: "\(dineWiseWeekdays[index])时段\(periodNumber)打烊时间",
                                                selection: Binding(
                                                    get: { businessPeriod(id: period.id, dayIndex: index)?.closesAt ?? period.closesAt },
                                                    set: { updateBusinessPeriod(id: period.id, dayIndex: index, closesAt: $0) }),
                                                displayedComponents: .hourAndMinute,
                                                quickTimes: ["14:00", "17:00", "18:00", "21:00", "22:00", "23:00",
                                                             "12:00", "13:00", "14:30", "15:00", "16:00", "19:00",
                                                             "20:00", "22:30"],
                                                validationMessage: { businessHoursValidationMessage(
                                                    id: period.id, dayIndex: index, closesAt: $0) })
                                            .frame(maxWidth: .infinity)
                                        Button("移除时段", systemImage: "minus.circle", role: .destructive) {
                                            removeBusinessPeriod(id: period.id, dayIndex: index)
                                        }
                                        .labelStyle(.iconOnly)
                                        .buttonStyle(.borderless)
                                    }
                                    .padding(8)
                                    .background(DineWiseTheme.inset,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                if !businessHours[index].isEmpty, businessHours[index].count < 4 {
                                    Button("添加时段", systemImage: "plus.circle") {
                                        addBusinessPeriod(dayIndex: index)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(10)
                        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(10)
                .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 12))
            }

            editorSectionButton("门店照片", summary: photoSummary,
                                expanded: expandedEditorSection == .photo) {
                toggleEditorSection(.photo)
            }
            if expandedEditorSection == .photo {
                VStack(alignment: .leading, spacing: 10) {
                    if store.HasPhoto == true {
                        DineWiseStorePhotoPreview(store: store, token: token)
                    }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("选择门店照片", systemImage: "photo")
                    }
                    .onChange(of: selectedPhoto) { _, selection in
                        guard let selection else { return }
                        Task {
                            guard let data = try? await selection.loadTransferable(type: Data.self),
                                  let image = UIImage(data: data),
                                  let jpeg = image.jpegData(compressionQuality: 0.82),
                                  jpeg.count <= 5 * 1024 * 1024 else {
                                message = "请选择有效图片，压缩后不超过 5 MB。"; messageIsError = true
                                photoData = nil; return
                            }
                            photoData = jpeg; message = "照片已选择。"; messageIsError = false
                        }
                    }
                    if photoData != nil {
                        Button("上传所选照片") { uploadPhoto() }
                            .buttonStyle(.bordered).disabled(saving)
                    }
                    if store.HasPhoto == true {
                        Button("删除门店照片", role: .destructive) { deletePhoto() }
                            .disabled(saving)
                    }
                }
                .padding(10)
                .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 12))
            }

            if expandedEditorSection == .basic {
                Button(saving ? "正在保存…" : "保存基本资料") { save(section: .basic) }
                    .buttonStyle(.borderedProminent)
                    .tint(DineWiseTheme.action(for: colorScheme))
                    .disabled(saving)
            } else if expandedEditorSection == .schedule {
                Button(saving ? "正在保存…" : "保存营业时段") { save(section: .schedule) }
                    .buttonStyle(.borderedProminent)
                    .tint(DineWiseTheme.action(for: colorScheme))
                    .disabled(saving)
            }
            if !message.isEmpty {
                Text(message).font(.footnote)
                    .foregroundStyle(messageIsError
                        ? DineWiseTheme.danger(for: colorScheme)
                        : DineWiseTheme.accent(for: colorScheme))
            }
        }
        .onChange(of: location.latitude) { _, value in if let value { latitude = value } }
        .onChange(of: location.longitude) { _, value in if let value { longitude = value } }
        .onChange(of: store.ProfileVersion) { _, _ in
            if let savedSection = saveSectionForNextVersion {
                switch savedSection {
                case .basic: syncBasicDraft(from: store)
                case .schedule: syncScheduleDraft(from: store)
                case .photo: break
                }
                saveSectionForNextVersion = nil
            } else {
                syncBasicDraft(from: store)
                syncScheduleDraft(from: store)
                expandedEditorSection = nil
            }
        }
    }

    private var basicProfileSummary: String {
        let completedCount = [businessType, address, introduction]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
        let paymentSummary = payments.isEmpty ? "需设置顾客支付方式" : "支付方式已设置"
        return "\(basicDraftIsDirty ? "有未保存修改 · " : "")业态、地址、介绍已填写 \(completedCount)/3 项 · \(paymentSummary)"
    }

    private var businessHoursSummary: String {
        let configuredDays = businessHours.filter { !$0.isEmpty }.count
        let summary = configuredDays == 0 ? "尚未配置营业时段" : "\(configuredDays)/7 天有营业时段"
        return "\(scheduleDraftIsDirty ? "有未保存修改 · " : "")\(summary) · 自动按门店时区"
    }

    private var basicDraftIsDirty: Bool {
        name != store.Name || businessType != (store.BusinessType ?? "")
            || address != (store.Address ?? "") || latitude != store.Latitude
            || longitude != store.Longitude || introduction != (store.Introduction ?? "")
            || payments != Set(store.PaymentMethods ?? [])
    }

    private var scheduleDraftIsDirty: Bool {
        cutoff != String(store.BusinessDayCutoffMinutes ?? 0)
            || businessHoursText != dineWiseBusinessHoursText(store.BusinessHours)
    }

    private var photoSummary: String {
        switch store.HasPhoto {
        case true: "已上传门店照片"
        case false: "尚未上传门店照片"
        case nil: "照片状态暂不可用"
        }
    }

    private var businessHoursText: [String] {
        businessHours.map { periods in
            periods.map { "\(dineWiseTimeString($0.opensAt))-\(dineWiseTimeString($0.closesAt))" }
                .joined(separator: ", ")
        }
    }

    private func businessHoursDaySummary(_ index: Int) -> String {
        let periods = businessHours[index]
        guard !periods.isEmpty else { return "休息" }
        return periods.map { "\(dineWiseTimeString($0.opensAt))-\(dineWiseTimeString($0.closesAt))" }
            .joined(separator: " · ")
    }

    private var cutoffClockText: String {
        let minutes = Int(cutoff) ?? 0
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func businessPeriod(id: UUID, dayIndex: Int) -> DineWiseBusinessHoursDraftPeriod? {
        businessHours[dayIndex].first { $0.id == id }
    }

    private func businessHoursValidationMessage(id: UUID, dayIndex: Int,
                                                opensAt: Date? = nil,
                                                closesAt: Date? = nil) -> String? {
        guard let periodIndex = businessHours[dayIndex].firstIndex(where: { $0.id == id }) else {
            return "该营业时段已变化，请重新选择。"
        }
        var candidate = businessHoursText
        var periods = businessHours[dayIndex]
        if let opensAt { periods[periodIndex].opensAt = opensAt }
        if let closesAt { periods[periodIndex].closesAt = closesAt }
        candidate[dayIndex] = periods.map {
            "\(dineWiseTimeString($0.opensAt))-\(dineWiseTimeString($0.closesAt))"
        }.joined(separator: ", ")
        return dineWiseBusinessHoursPayload(candidate) == nil
            ? "与其他营业时段冲突，请调整时间后重试。" : nil
    }

    private func updateBusinessPeriod(id: UUID, dayIndex: Int,
                                      opensAt: Date? = nil, closesAt: Date? = nil) {
        guard let periodIndex = businessHours[dayIndex].firstIndex(where: { $0.id == id }) else { return }
        var updatedDays = businessHours
        if let opensAt { updatedDays[dayIndex][periodIndex].opensAt = opensAt }
        if let closesAt { updatedDays[dayIndex][periodIndex].closesAt = closesAt }
        businessHours = updatedDays
        if dineWiseBusinessHoursPayload(businessHoursText) == nil {
            message = "当前时段与其他营业时间冲突或开门、打烊时间相同，请调整后再保存。"
            messageIsError = true
        } else {
            message = ""
            messageIsError = false
        }
    }

    private func removeBusinessPeriod(id: UUID, dayIndex: Int) {
        businessHours[dayIndex].removeAll { $0.id == id }
        message = ""
        messageIsError = false
    }

    private func applyBusinessHoursPreset(dayIndex: Int, periods: [String]) {
        let candidate = businessHoursText.enumerated().map { index, value in
            index == dayIndex ? periods.joined(separator: ", ") : value
        }
        guard dineWiseBusinessHoursPayload(candidate) != nil else {
            message = "该快捷时段与相邻营业日冲突，请先调整相关时段。"
            messageIsError = true
            return
        }
        businessHours[dayIndex] = periods.compactMap { value in
            let pair = value.split(separator: "-", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            return DineWiseBusinessHoursDraftPeriod(
                opensAt: dineWiseDateForTime(pair[0]), closesAt: dineWiseDateForTime(pair[1]))
        }
        message = ""
        messageIsError = false
    }

    private func copyBusinessHours(dayIndex: Int, targetDays: [Int], targetName: String) {
        let source = businessHours[dayIndex]
        guard !source.isEmpty else { return }
        var candidate = businessHoursText
        for targetDay in targetDays where targetDay != dayIndex {
            candidate[targetDay] = candidate[dayIndex]
        }
        guard dineWiseBusinessHoursPayload(candidate) != nil else {
            message = "复制到\(targetName)后会与现有营业时段冲突，请先调整时段。"
            messageIsError = true
            return
        }
        var updated = businessHours
        for targetDay in targetDays where targetDay != dayIndex {
            updated[targetDay] = source.map { DineWiseBusinessHoursDraftPeriod(
                opensAt: $0.opensAt, closesAt: $0.closesAt) }
        }
        businessHours = updated
        message = "已复制到\(targetName)；确认后再保存门店资料。"
        messageIsError = false
    }

    private func applyBusinessHoursWeekPreset(periods: [String]) {
        let candidate = Array(repeating: periods.joined(separator: ", "), count: 7)
        guard dineWiseBusinessHoursPayload(candidate) != nil else {
            message = "该快捷时段与现有营业安排冲突，请先调整时段。"
            messageIsError = true
            return
        }
        businessHours = Array(repeating: periods.map { value in
            let pair = value.split(separator: "-", maxSplits: 1).map(String.init)
            return DineWiseBusinessHoursDraftPeriod(
                opensAt: dineWiseDateForTime(pair[0]), closesAt: dineWiseDateForTime(pair[1]))
        }, count: 7)
        message = ""
        messageIsError = false
    }

    private func addBusinessPeriod(dayIndex: Int) {
        guard businessHours[dayIndex].count < 4 else { return }
        let defaults = businessHours[dayIndex].isEmpty
            ? ["09:00-22:00", "09:00-14:00", "17:00-23:00", "00:00-06:00", "06:00-09:00"]
            : ["17:00-23:00", "09:00-14:00", "00:00-06:00", "06:00-09:00", "09:00-22:00"]
        for value in defaults {
            var candidate = businessHoursText
            candidate[dayIndex] = [candidate[dayIndex], value]
                .filter { !$0.isEmpty }.joined(separator: ", ")
            guard dineWiseBusinessHoursPayload(candidate) != nil else { continue }
            let pair = value.split(separator: "-", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            businessHours[dayIndex].append(DineWiseBusinessHoursDraftPeriod(
                opensAt: dineWiseDateForTime(pair[0]), closesAt: dineWiseDateForTime(pair[1])))
            message = ""
            messageIsError = false
            return
        }
        message = "该营业日没有可添加的不重叠时段，请先调整现有时段。"
        messageIsError = true
    }

    private func toggleEditorSection(_ section: DineWiseStoreProfileSection) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedEditorSection = expandedEditorSection == section ? nil : section
        }
    }

    private func editorSectionButton(_ title: String, summary: String, expanded: Bool,
                                     action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? "已展开" : "已收起")
        .accessibilityHint(expanded ? "双击收起编辑内容" : "双击展开编辑内容")
    }

    private func save(section: DineWiseStoreProfileSection) {
        let isBasic = section == .basic
        let paymentMethods = isBasic ? Array(payments) : (store.PaymentMethods ?? [])
        guard !paymentMethods.isEmpty else {
            message = "请先在门店基本资料中选择至少一种顾客可用支付方式。"
            messageIsError = true
            expandedEditorSection = .basic
            return
        }
        let minutes = isBasic ? (store.BusinessDayCutoffMinutes ?? 0) : Int(cutoff)
        guard let minutes, (0...1439).contains(minutes) else {
            message = "营业日切分分钟需为 0—1439。"; messageIsError = true; return
        }
        let timeZoneID = store.TimeZone ?? TimeZone.current.identifier
        guard TimeZone(identifier: timeZoneID) != nil else {
            message = "当前门店营业时区无效，请刷新门店资料后重试。"; messageIsError = true; return
        }
        let hours = isBasic ? (store.BusinessHours ?? []) : dineWiseBusinessHoursPayload(businessHoursText)
        guard let hours else {
            message = "请检查营业时段：每天最多 4 段，开门和打烊时间不能相同，且各时段不能重叠。"
            messageIsError = true; return
        }
        saving = true; message = ""; messageIsError = false
        Task {
            do {
                let updated = try await DineWiseAPI().updateStoreProfile(store: store,
                    name: isBasic ? name : store.Name,
                    businessType: isBasic ? businessType : (store.BusinessType ?? ""),
                    address: isBasic ? address : (store.Address ?? ""),
                    latitude: isBasic ? latitude : store.Latitude,
                    longitude: isBasic ? longitude : store.Longitude,
                    introduction: isBasic ? introduction : (store.Introduction ?? ""),
                    paymentMethods: paymentMethods,
                    timeZone: timeZoneID, cutoffMinutes: minutes,
                    businessHours: hours, token: token)
                saveSectionForNextVersion = section
                onSaved(updated); message = "已保存。"; messageIsError = false
            } catch { message = error.localizedDescription; messageIsError = true }
            saving = false
        }
    }

    private func syncBasicDraft(from store: DineWiseStore) {
        name = store.Name
        businessType = store.BusinessType ?? ""
        address = store.Address ?? ""
        latitude = store.Latitude
        longitude = store.Longitude
        introduction = store.Introduction ?? ""
        payments = Set(store.PaymentMethods ?? [])
    }

    private func syncScheduleDraft(from store: DineWiseStore) {
        cutoff = String(store.BusinessDayCutoffMinutes ?? 0)
        businessHours = dineWiseBusinessHoursText(store.BusinessHours).map { day in
            day.split(separator: ",").compactMap { segment in
                let pair = segment.split(separator: "-", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { return nil }
                return DineWiseBusinessHoursDraftPeriod(
                    opensAt: dineWiseDateForTime(pair[0].trimmingCharacters(in: .whitespaces)),
                    closesAt: dineWiseDateForTime(pair[1].trimmingCharacters(in: .whitespaces)))
            }
        }
    }

    private func uploadPhoto() {
        guard let photoData else { return }
        saving = true; message = ""; messageIsError = false
        Task {
            do {
                let updated = try await DineWiseAPI().uploadStorePhoto(store: store,
                    data: photoData, token: token)
                saveSectionForNextVersion = .photo
                onSaved(updated); self.photoData = nil; selectedPhoto = nil
                message = "门店照片已更新。"; messageIsError = false
            } catch { message = error.localizedDescription; messageIsError = true }
            saving = false
        }
    }

    private func deletePhoto() {
        saving = true; message = ""; messageIsError = false
        Task {
            do {
                let updated = try await DineWiseAPI().deleteStorePhoto(store: store, token: token)
                saveSectionForNextVersion = .photo
                onSaved(updated); message = "门店照片已删除。"; messageIsError = false
            } catch { message = error.localizedDescription; messageIsError = true }
            saving = false
        }
    }
}

private struct DineWiseStorePhotoPreview: View {
    let store: DineWiseStore
    let token: String
    @State private var photo: UIImage?
    @State private var message = ""

    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if !message.isEmpty {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            } else {
                ProgressView("正在加载门店照片…")
            }
        }
        .task(id: "\(store.Id):\(store.ProfileVersion ?? 1)") {
            photo = nil; message = ""
            do {
                let data = try await DineWiseAPI().storePhoto(storeID: store.Id, token: token)
                guard !Task.isCancelled else { return }
                guard let image = UIImage(data: data) else {
                    message = "门店照片格式暂时无法显示。"; return
                }
                photo = image
            } catch {
                if !Task.isCancelled { message = error.localizedDescription }
            }
        }
    }
}
