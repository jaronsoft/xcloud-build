import SwiftUI
import UIKit

struct ActivityDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SessionStore
    let id: String
    @State private var detail: [String: Any]?
    @State private var availability: [String: Any]?
    @State private var registrationEnabled: Bool?
    @State private var remainingQuota: Int?
    @State private var selectedSessionID = ""
    @State private var quantity = 1
    @State private var participantAnswers: [[String: String]] = [[:]]
    @State private var identityConsent = false
    @State private var requestKey = UUID().uuidString
    @State private var receipt: [String: Any]?
    @State private var receiptPrincipal: String?
    @State private var credentialCopyNotice: String?
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @State private var submitError: String?
    @State private var sessionSelectionNotice: String?
    @State private var revision = 0
    @State private var loadSequence = 0
    @State private var submitSequence = 0
    @State private var refreshDeferred = false
    @State private var hasLoaded = false
    @State private var recoveryPending = false
    @State private var recoveryChecking = false
    @State private var recoverySequence = 0
    @State private var recoveryStorageKey = ""
    @State private var recoveryClearTarget: (String, String?, String?, String)?
    @State private var showRecoveryClear = false
    @State private var showRegistrations = false
    @State private var selectedContentTab = "registration"
    @State private var hasRichActivityContent = false

    private var hasActivityIntroduction: Bool {
        let description = (detail?["Description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !description.isEmpty || hasRichActivityContent
    }

    private var fields: [[String: Any]] { detail?["SignupFields"] as? [[String: Any]] ?? [] }
    private var detailTaskKey: String { "\(id)-\(revision)-\(store.session?.accessToken ?? "")" }
    private var sessions: [[String: Any]] { detail?["Sessions"] as? [[String: Any]] ?? [] }
    private var chosenSession: [String: Any]? { sessions.first { $0["Id"] as? String == selectedSessionID } }
    private var remainingSeats: Int {
        if sessions.isEmpty { return availability?["RemainingCapacity"] as? Int ?? 0 }
        let available = availability?["Sessions"] as? [[String: Any]] ?? []
        return available.first { $0["Id"] as? String == selectedSessionID }?["RemainingCapacity"] as? Int ?? 0
    }
    private func sessionAvailability(_ id: String) -> [String: Any]? {
        (availability?["Sessions"] as? [[String: Any]] ?? []).first { $0["Id"] as? String == id }
    }
    private func sessionEndDate(_ value: String) -> Date? {
        nativeBusinessTimestamp(value)
    }
    private func sessionIsBookable(_ row: [String: Any]?, now: Date = Date()) -> Bool {
        guard let row, row["IsEnabled"] as? Bool == true,
              let end = row["EndTime"] as? String,
              let endDate = sessionEndDate(end), endDate > now,
              let seats = row["RemainingCapacity"] as? Int, seats > 0 else { return false }
        return true
    }
    private func sessionUnavailableText(_ row: [String: Any]?, now: Date = Date()) -> String {
        guard let row else { return "名额待核对" }
        if let end = row["EndTime"] as? String, let endDate = sessionEndDate(end), endDate <= now { return "活动已结束" }
        if row["IsEnabled"] as? Bool != true { return "场次已关闭" }
        guard let end = row["EndTime"] as? String, sessionEndDate(end) != nil else { return "时间待核对" }
        if (row["RemainingCapacity"] as? Int ?? 0) < 1 { return "名额已满" }
        return "暂不可报名"
    }
    private func clearSessionDraft(reason: String, original: Bool = false) {
        selectedSessionID = ""
        quantity = 1
        participantAnswers = [[:]]
        identityConsent = false
        requestKey = UUID().uuidString
        submitError = nil
        sessionSelectionNotice = "\(original ? "原选场次" : "所选场次")（\(reason)），报名资料已清空，请重新选择可报名场次。"
    }
    private func handleSessionSelected(_ sessionID: String, seats: Int?) {
        selectedSessionID = sessionID
        sessionSelectionNotice = nil
        let configuredLimit = max(1, (detail?["MaxPerUser"] as? NSNumber)?.intValue ?? 1)
        if let seats {
            let permitted = max(1, min(100, configuredLimit, seats, remainingQuota ?? 1))
            if quantity > permitted { setQuantity(permitted) }
        }
        requestKey = UUID().uuidString
    }
    private func invalidateDetailRequestsOnDisappear() {
        loadSequence += 1
        recoverySequence += 1
        recoveryChecking = false
    }
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active {
            if busy { refreshDeferred = true } else { revision += 1 }
            return
        }
        loadSequence += 1
        if !busy { detail = nil; availability = nil; loading = true }
        else { refreshDeferred = true }
    }
    private func handleBusyChange(_ value: Bool) {
        guard !value, refreshDeferred else { return }
        refreshDeferred = false
        revision += 1
    }
    private func handleActivityIDChange() {
        selectedContentTab = "registration"
        sessionSelectionNotice = nil
    }
    private func handleAccessTokenChange(from oldToken: String?, to newToken: String?) {
        if nativeTourismPrincipal(oldToken) != nativeTourismPrincipal(newToken) {
            submitSequence += 1
            busy = false
            participantAnswers = [[:]]
            quantity = 1
            identityConsent = false
            requestKey = UUID().uuidString
            receipt = nil
            receiptPrincipal = nil
            submitError = nil
            sessionSelectionNotice = nil
            recoverySequence += 1
            recoveryPending = false
            recoveryChecking = false
            recoveryStorageKey = ""
            showRecoveryClear = false
            recoveryClearTarget = nil
            showRegistrations = false
        }
        loadSequence += 1
        revision += 1
    }
    private var selectedSessionBookable: Bool {
        sessions.isEmpty || sessionIsBookable(sessionAvailability(selectedSessionID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if loading { ProgressView("正在加载活动详情…").frame(maxWidth: .infinity).padding(36) }
                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).foregroundStyle(.red)
                        Button("重试加载") { revision += 1 }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
                if let detail {
                    let images = detail["ImageUrls"] as? [String] ?? []
                    NativeProductGallery(store: store, detail: ["MediaUrls": images], fallback: nil,
                                         imageLabel: "活动", height: 250, fallbackAsset: "Quick4",
                                         fallbackLabel: "主题插画")
                        .frame(maxWidth: .infinity)
                    ActivityDetailSummarySection(store: store, activityID: id, detail: detail,
                                                 hasSessions: !sessions.isEmpty)
                    let description = detail["Description"] as? String ?? ""
                    let html = detail["ContentHtml"] as? String ?? ""
                    ActivityDetailContentSection(selectedTab: $selectedContentTab,
                        hasIntroduction: hasActivityIntroduction, description: description,
                        hasRichContent: hasRichActivityContent, html: html, store: store)
                    if !hasActivityIntroduction || selectedContentTab != "content" {
                        if !sessions.isEmpty {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                ActivityDetailSessionSelectionSection(
                                    sessions: sessions,
                                    availabilityRows: availability?["Sessions"] as? [[String: Any]] ?? [],
                                    selectedSessionID: selectedSessionID,
                                    isBusy: busy,
                                    now: context.date,
                                    isBookable: sessionIsBookable,
                                    unavailableText: sessionUnavailableText,
                                    dateRange: dateRange,
                                    onSelect: { sessionID, seats in
                                        handleSessionSelected(sessionID, seats: seats)
                                    })
                            }
                            if let sessionSelectionNotice {
                                Text(sessionSelectionNotice).font(.system(size: NativeTypography.size(12)))
                                    .foregroundStyle(Color(red: 0.70, green: 0.34, blue: 0.29))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        registrationCard
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Brand.background)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        // 活动详情可能位于嵌套导航栈中；单屏折叠态继续隐藏系统 Tab 侧栏，避免盖住左侧内容。
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .simultaneousGesture(DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard value.startLocation.x <= 32,
                      horizontal >= 72, horizontal > abs(vertical) * 1.25 else { return }
                dismiss()
            })
        .task(id: detailTaskKey) {
            await recoverRegistration()
            await load()
        }
        .task(id: id + "-" + selectedSessionID) {
            guard !selectedSessionID.isEmpty,
                  let endText = sessionAvailability(selectedSessionID)?["EndTime"] as? String,
                  let deadline = sessionEndDate(endText) else { return }
            while !Task.isCancelled {
                let remaining = deadline.timeIntervalSinceNow
                if remaining <= 0 { break }
                do {
                    try await Task.sleep(nanoseconds: UInt64(min(remaining, 3_600) * 1_000_000_000))
                } catch { return }
            }
            guard !Task.isCancelled, !selectedSessionID.isEmpty,
                  sessionEndDate(endText).map({ $0 <= Date() }) == true else { return }
            if busy { refreshDeferred = true; return }
            let reason = sessionUnavailableText(sessionAvailability(selectedSessionID), now: Date())
            clearSessionDraft(reason: reason)
        }
        .sheet(isPresented: $showRegistrations) { ActivityRegistrationsView(store: store) }
        .confirmationDialog("确认已核对报名记录？", isPresented: $showRecoveryClear, titleVisibility: .visible) {
            Button("已核对，清除恢复标记", role: .destructive) { clearRegistrationRecovery() }
            Button("保留标记", role: .cancel) { recoveryClearTarget = nil }
        } message: {
            Text("清除标记不会取消服务端报名。请先核对“我的活动报名”，避免重复报名。")
        }
        .onChange(of: scenePhase) { _, phase in handleScenePhaseChange(phase) }
        .onChange(of: id) { _, _ in handleActivityIDChange() }
        .onChange(of: busy) { _, value in handleBusyChange(value) }
        .onChange(of: store.session?.accessToken) { oldToken, newToken in
            handleAccessTokenChange(from: oldToken, to: newToken)
        }
        .onDisappear(perform: invalidateDetailRequestsOnDisappear)
    }

    @ViewBuilder private var registrationCard: some View {
        ActivityRegistrationCard(
            recoveryPending: recoveryPending,
            recoveryChecking: recoveryChecking,
            receipt: receipt,
            activityName: (receipt?["ActivityName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (detail?["Name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "活动",
            sessionName: (receipt?["SessionName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "整体活动",
            receiptPrincipalMatches: nativeTourismPrincipal(store.session?.accessToken) == receiptPrincipal,
            sceneIsActive: scenePhase == .active,
            credentialCopyNotice: $credentialCopyNotice,
            registrationEnabled: registrationEnabled,
            isAuthenticated: store.session != nil,
            remainingQuota: remainingQuota,
            loading: loading,
            configurationError: nativeActivitySignupConfigurationError(detail?["SignupFields"]),
            sessions: sessions,
            chosenSession: chosenSession,
            remainingSeats: remainingSeats,
            fields: fields,
            quantity: quantity,
            configuredLimit: max(1, (detail?["MaxPerUser"] as? NSNumber)?.intValue ?? 1),
            maxQuantity: maxQuantity,
            selectedSessionBookable: selectedSessionBookable,
            participantAnswers: $participantAnswers,
            identityConsent: $identityConsent,
            submitError: submitError,
            isBusy: busy,
            onRecover: { Task { await recoverRegistration() } },
            onShowRegistrations: { showRegistrations = true },
            onRequestRecoveryClear: {
                guard let principal = nativeTourismPrincipal(store.session?.accessToken) else { return }
                let marker = store.activityRegistrationAttempt(for: recoveryStorageKey)
                recoveryClearTarget = (recoveryStorageKey, marker.requestKey, marker.sessionID, principal)
                showRecoveryClear = true
            },
            onRetry: { revision += 1 },
            onQuantityChange: setQuantity,
            onAnswerChange: { value, key, participant, maxLength in
                setAnswer(value, key: key, participant: participant, maxLength: maxLength)
            },
            onSubmit: { Task { await submit() } })
    }

    private var maxQuantity: Int {
        let configuredLimit = max(1, (detail?["MaxPerUser"] as? NSNumber)?.intValue ?? 1)
        return max(1, min(100, configuredLimit, remainingSeats, remainingQuota ?? 1))
    }

    private func setQuantity(_ value: Int) {
        let safeValue = max(1, value)
        if safeValue > participantAnswers.count {
            participantAnswers.append(contentsOf: Array(repeating: [:], count: safeValue - participantAnswers.count))
        } else if safeValue < participantAnswers.count {
            participantAnswers.removeLast(participantAnswers.count - safeValue)
        }
        quantity = safeValue
        requestKey = UUID().uuidString
    }

    private func setAnswer(_ value: String, key: String, participant: Int, maxLength: Int? = nil) {
        guard participantAnswers.indices.contains(participant) else { return }
        participantAnswers[participant][key] = maxLength.map { nativeActivitySignupTruncate(value, maxLength: $0) } ?? value
        requestKey = UUID().uuidString
    }

    private func activityCard(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: NativeTypography.size(18), weight: .semibold)).foregroundStyle(Brand.ink)
            Text(content).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private func dateRange(_ start: Any?, _ end: Any?) -> String {
        let first = start as? String ?? "待公布"
        let last = end as? String ?? "待公布"
        return "\(first) — \(last)"
    }

    private func load() async {
        guard !busy else { refreshDeferred = true; return }
        loadSequence += 1; let operation = loadSequence
        let token = store.session?.accessToken
        let previousSession = selectedSessionID
        loading = true; error = nil; detail = nil; availability = nil; remainingQuota = nil
        registrationEnabled = nil
        hasRichActivityContent = false
        do {
            guard let number = Int64(id), number > 0, String(number) == id else { throw MobileAPIError.unavailable("活动编号无效") }
            guard await MobileAPI(store: store).featureEnabled("MODULE-ACTIVITY") else {
                throw MobileAPIError.unavailable("活动模块暂未开放")
            }
            guard operation == loadSequence, store.session?.accessToken == token else { return }
            let api = MobileAPI(store: store)
            guard var item = try await api.get("/api/JHCTIActivity/GetPublicDetail?id=\(id)") as? [String: Any],
                item["Id"] as? String == id else { throw MobileAPIError.unavailable("活动详情数据异常") }
            guard operation == loadSequence, store.session?.accessToken == token else { return }
            var enabled: Bool?
            do {
                guard let result = try await api.get("/api/JHCTIActivity/GetPublicRegistrationAvailability") as? Bool else {
                    throw MobileAPIError.unavailable("活动报名状态响应格式无效")
                }
                enabled = result
            } catch is CancellationError {
                throw CancellationError()
            } catch { enabled = nil }
            guard operation == loadSequence, store.session?.accessToken == token else { return }
            var fresh: [String: Any]?
            do {
                fresh = try await api.get("/api/JHCTIActivity/GetPublicAvailability?id=\(id)") as? [String: Any]
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                fresh = nil
            }
            guard operation == loadSequence, store.session?.accessToken == token else { return }
            if !nativePublicActivityAvailabilityMatches(detail: item, availability: fresh) {
                let refreshedItem: [String: Any]?
                do {
                    refreshedItem = try await api.get("/api/JHCTIActivity/GetPublicDetail?id=\(id)") as? [String: Any]
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    refreshedItem = nil
                }
                if let refreshedItem, refreshedItem["Id"] as? String == id {
                    item = refreshedItem
                    do {
                        fresh = try await api.get("/api/JHCTIActivity/GetPublicAvailability?id=\(id)") as? [String: Any]
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        fresh = nil
                    }
                }
                guard operation == loadSequence, store.session?.accessToken == token else { return }
            }
            var quotaRemaining: Int?
            if token != nil && enabled == true {
                let quota: Any?
                do {
                    quota = try await api.get("/api/JHCTIActivity/GetMyRegistrationQuota?activityId=\(id)", authenticated: true,
                                              expectedPrincipal: nativeTourismPrincipal(token))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    quota = nil
                }
                quotaRemaining = nativeActivityRegistrationQuotaRemaining(quota, activityID: id)
            }
            guard operation == loadSequence, store.session?.accessToken == token else { return }
            let html = item["ContentHtml"] as? String ?? ""
            let richContentHasContent = await Task.detached(priority: .userInitiated) {
                !html.isEmpty && (!plainTextFromHTML(html).isEmpty || nativeHTMLSourceBlocks(html).contains {
                    if case .image = $0 { return true }; return false
                })
            }.value
            guard operation == loadSequence, store.session?.accessToken == token else { return }
            hasRichActivityContent = richContentHasContent
            detail = item; registrationEnabled = enabled; remainingQuota = quotaRemaining
            availability = nativePublicActivityAvailabilityMatches(detail: item, availability: fresh) ? fresh : nil
            let available = availability?["Sessions"] as? [[String: Any]] ?? []
            let candidates = (item["Sessions"] as? [[String: Any]] ?? []).compactMap { row -> String? in
                guard let sessionID = row["Id"] as? String,
                      sessionIsBookable(available.first { $0["Id"] as? String == sessionID }) else { return nil }
                return sessionID
            }
            let refreshedSelection = hasLoaded ? (candidates.contains(previousSession) ? previousSession : "") : (candidates.first ?? "")
            selectedSessionID = refreshedSelection
            if hasLoaded && !previousSession.isEmpty && refreshedSelection.isEmpty {
                let unavailable = available.first { $0["Id"] as? String == previousSession }
                let reason = sessionUnavailableText(unavailable, now: Date())
                clearSessionDraft(reason: reason, original: true)
            } else if !refreshedSelection.isEmpty {
                sessionSelectionNotice = nil
            }
            let selectedAvailability = available.first { $0["Id"] as? String == selectedSessionID }
            let refreshedSeats = (item["Sessions"] as? [[String: Any]] ?? []).isEmpty
                ? (availability?["RemainingCapacity"] as? Int ?? 0)
                : (selectedAvailability?["RemainingCapacity"] as? Int ?? 0)
            let configuredLimit = max(1, (item["MaxPerUser"] as? NSNumber)?.intValue ?? 1)
            let refreshedLimit = max(1, min(100, configuredLimit, refreshedSeats, quotaRemaining ?? 1))
            if quantity > refreshedLimit { setQuantity(refreshedLimit) }
            hasLoaded = true
            if availability == nil { error = "活动名额暂无法确认，请刷新后重试。" }
        } catch is CancellationError {
            return
        } catch {
            if operation == loadSequence, store.session?.accessToken == token { self.error = error.localizedDescription }
        }
        if operation == loadSequence { loading = false }
    }

    private func submit() async {
        guard detail != nil, !busy, !recoveryPending, let principal = nativeTourismPrincipal(store.session?.accessToken) else { return }
        submitError = nil
        guard (1...100).contains(quantity), participantAnswers.count >= quantity else {
            submitError = "参与者资料不完整，请重新填写。"; return
        }
        guard quantity <= maxQuantity else {
            submitError = "报名人数已超过本活动单人报名上限，请调整人数后重试。"; return
        }
        if let message = nativeActivitySignupAnswerError(detail?["SignupFields"],
            participants: Array(participantAnswers.prefix(quantity)), quantity: quantity) {
            submitError = message; return
        }
        if let message = nativeActivityTextLengthError(fields, participants: Array(participantAnswers.prefix(quantity))) {
            submitError = message; return
        }
        let hasIdentityData = nativeActivityRequiresIdentityConsent(fields, participants: Array(participantAnswers.prefix(quantity)))
        if hasIdentityData && !identityConsent {
            submitError = "请先同意本次身份证实名信息采集"
            return
        }
        submitSequence += 1; let operation = submitSequence
        busy = true
        defer { if operation == submitSequence { busy = false } }
        do {
            let api = MobileAPI(store: store)
            guard (try await api.get("/api/JHCTIActivity/GetPublicRegistrationAvailability") as? Bool) == true else {
                throw MobileAPIError.unavailable("活动暂时不能报名")
            }
            guard let fresh = try await api.get("/api/JHCTIActivity/GetPublicAvailability?id=\(id)") as? [String: Any],
                fresh["ActivityId"] as? String == id else {
                throw MobileAPIError.unavailable("暂无法确认最新报名名额")
            }
            guard let currentDetail = detail,
                  nativePublicActivityAvailabilityMatches(detail: currentDetail, availability: fresh) else {
                throw MobileAPIError.unavailable("活动场次与实时名额不一致，请刷新后重试")
            }
            guard operation == submitSequence, nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
            availability = fresh
            let freshSessions = fresh["Sessions"] as? [[String: Any]] ?? []
            if sessions.isEmpty {
                let freshSeats = fresh["RemainingCapacity"] as? Int ?? 0
                guard freshSeats >= quantity else { throw MobileAPIError.unavailable("当前活动剩余名额不足") }
            } else {
                guard let freshSession = freshSessions.first(where: { $0["Id"] as? String == selectedSessionID }) else {
                    clearSessionDraft(reason: "名额待核对", original: true)
                    throw MobileAPIError.unavailable("暂无法确认所选场次状态")
                }
                guard sessionIsBookable(freshSession) else {
                    let reason = sessionUnavailableText(freshSession, now: Date())
                    clearSessionDraft(reason: reason, original: true)
                    throw MobileAPIError.unavailable(reason)
                }
                let freshSeats = freshSession["RemainingCapacity"] as? Int ?? 0
                guard freshSeats >= quantity else { throw MobileAPIError.unavailable("当前场次剩余名额不足") }
            }
            let quota = try await api.get("/api/JHCTIActivity/GetMyRegistrationQuota?activityId=\(id)", authenticated: true,
                                          expectedPrincipal: principal)
            guard operation == submitSequence, nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
            guard let remainingQuota = nativeActivityRegistrationQuotaRemaining(quota, activityID: id) else {
                throw MobileAPIError.unavailable("暂无法确认本人报名额度，请重新加载后再试。")
            }
            guard remainingQuota >= quantity else {
                throw MobileAPIError.unavailable("您的可报名人数已用完")
            }
            var body: [String: Any] = ["ActivityId": id, "Quantity": quantity,
                                      "IdempotencyKey": requestKey, "IdentityConsent": identityConsent,
                                      "Answers": participantAnswers[0].filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }]
            if quantity > 1 {
                body["Participants"] = participantAnswers.prefix(quantity).map { values in
                    ["Answers": values.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }]
                }
            }
            if !sessions.isEmpty { body["SessionId"] = selectedSessionID }
            guard let token = store.session?.accessToken else { return }
            let storageKey = nativeActivityRegistrationRecoveryKey(token: token, activityID: id)
            let expectedSessionID = sessions.isEmpty ? "" : selectedSessionID
            guard !storageKey.isEmpty, store.saveActivityRegistrationAttempt(requestKey, sessionID: expectedSessionID, for: storageKey) else {
                if store.activityRegistrationAttempt(for: storageKey).exists {
                    recoveryStorageKey = storageKey; recoveryPending = true
                }
                throw MobileAPIError.unavailable("设备暂时无法保存报名恢复标记，本次报名尚未提交。")
            }
            recoveryStorageKey = storageKey; recoveryPending = true
            guard let value = try await api.post("/api/JHCTIActivity/Register", body: body,
                                                  authenticated: true, expectedPrincipal: principal) as? [String: Any] else {
                throw MobileAPIError.unavailable("报名响应异常，请核对报名记录")
            }
            if operation == submitSequence, nativeTourismPrincipal(store.session?.accessToken) == principal {
                guard nativeActivityRecoveryReceiptMatches(value, activityID: id, sessionID: expectedSessionID),
                      value["Quantity"] as? Int == body["Quantity"] as? Int,
                      (value["SessionId"] as? String ?? "") == expectedSessionID else {
                    throw MobileAPIError.unavailable("报名回执与本次请求不一致，请先核对报名记录。")
                }
                receipt = value
                receiptPrincipal = principal
                if store.clearActivityRegistrationAttempt(for: storageKey) { recoveryPending = false; recoveryStorageKey = "" }
                else { submitError = "报名结果已确认，但恢复标记尚未清理，请再次核对。" }
            }
        } catch {
            if operation == submitSequence, nativeTourismPrincipal(store.session?.accessToken) == principal {
                submitError = recoveryPending ? "\(error.localizedDescription)。请先核对上次报名结果，暂不能开始新报名。" : error.localizedDescription
            }
        }
    }

    private func recoverRegistration() async {
        guard !busy, !recoveryChecking, let token = store.session?.accessToken,
              let principal = nativeTourismPrincipal(token) else { return }
        let storageKey = nativeActivityRegistrationRecoveryKey(token: token, activityID: id)
        guard !storageKey.isEmpty else { return }
        let marker = store.activityRegistrationAttempt(for: storageKey)
        guard marker.exists else { recoveryPending = false; recoveryStorageKey = ""; return }
        recoveryPending = true; recoveryStorageKey = storageKey
        guard let key = marker.requestKey else { submitError = "恢复标记暂时无法读取，请先核对我的报名记录。"; return }
        guard let expectedSessionID = marker.sessionID else {
            submitError = "该设备上的旧恢复标记未记录活动场次。请先核对我的报名记录，再手动清除标记。"; return
        }
        recoverySequence += 1; let operation = recoverySequence
        recoveryChecking = true
        defer { if operation == recoverySequence, nativeTourismPrincipal(store.session?.accessToken) == principal { recoveryChecking = false } }
        do {
            let value = try await MobileAPI(store: store).get(
                "/api/JHCTIActivity/GetMyRegistrationByIdempotencyKey?activityId=\(id)&idempotencyKey=\(key)",
                authenticated: true, expectedPrincipal: principal)
            guard operation == recoverySequence, nativeTourismPrincipal(store.session?.accessToken) == principal,
                  recoveryStorageKey == storageKey, store.activityRegistrationAttempt(for: storageKey).requestKey == key,
                  store.activityRegistrationAttempt(for: storageKey).sessionID == expectedSessionID else { return }
            guard let result = value as? [String: Any] else {
                submitError = "暂未查到上次报名结果，请稍后重试核对；这不代表报名未提交。"; return
            }
            guard nativeActivityRecoveryReceiptMatches(result, activityID: id, sessionID: expectedSessionID) else {
                throw MobileAPIError.unavailable("报名核对回执异常，请先查看我的报名记录。")
            }
            receipt = result
            receiptPrincipal = principal
            if store.clearActivityRegistrationAttempt(for: storageKey) {
                recoveryPending = false; recoveryStorageKey = ""; submitError = nil
            } else { submitError = "报名结果已确认，但恢复标记尚未清理，请再次核对。" }
        } catch {
            if operation == recoverySequence, nativeTourismPrincipal(store.session?.accessToken) == principal {
                submitError = "暂时无法核对上次报名，请保留恢复标记并稍后重试。"
            }
        }
    }

    private func clearRegistrationRecovery() {
        guard let target = recoveryClearTarget, !busy, !recoveryChecking, scenePhase == .active,
              nativeTourismPrincipal(store.session?.accessToken) == target.3, recoveryStorageKey == target.0,
              store.activityRegistrationAttempt(for: target.0).requestKey == target.1,
              store.activityRegistrationAttempt(for: target.0).sessionID == target.2 else { return }
        recoverySequence += 1; recoveryClearTarget = nil
        guard store.clearActivityRegistrationAttempt(for: target.0) else { submitError = "无法清除恢复标记，请稍后重试。"; return }
        recoveryPending = false; recoveryStorageKey = ""; receipt = nil; submitError = nil
        requestKey = UUID().uuidString; participantAnswers = [[:]]; quantity = 1; identityConsent = false; revision += 1
    }
}

private func nativeActivityRegistrationRecoveryKey(token: String, activityID: String) -> String {
    guard let number = Int64(activityID), number > 0, String(number) == activityID else { return "" }
    return nativeTicketOrderRecoveryStorageKey(accessToken: token, resourceID: activityID)
        .replacingOccurrences(of: "ticket-order-attempt", with: "activity-registration-attempt")
}

private func nativeActivityRecoveryReceiptMatches(_ item: [String: Any], activityID: String, sessionID: String) -> Bool {
    guard let id = item["Id"] as? String, let number = Int64(id), number > 0, String(number) == id,
          item["ActivityId"] as? String == activityID, let quantity = item["Quantity"] as? Int, (1...100).contains(quantity),
          ["Registered", "Cancelled", "CheckedIn"].contains(item["Status"] as? String ?? ""),
          let activityName = item["ActivityName"] as? String, !activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let sessionName = item["SessionName"] as? String, !sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          item.keys.contains("SessionId") else { return false }
    if sessionID.isEmpty { return item["SessionId"] is NSNull }
    return item["SessionId"] as? String == sessionID
}


private func nativeActivityTextLength(_ value: String) -> Int {
    value.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
}

private func nativeActivityTextLengthError(_ fields: [[String: Any]], participants: [[String: String]]) -> String? {
    for (index, answers) in participants.enumerated() {
        for field in fields where ["Text", "LongText"].contains(field["Type"] as? String ?? "") {
            let key = field["Key"] as? String ?? ""
            if nativeActivityTextLength(answers[key] ?? "") > 500 {
                return "参与者\(index + 1)的“\(field["Label"] as? String ?? key)”不能超过500个字符。"
            }
        }
    }
    return nil
}

func nativeActivityKeyboard(_ type: String) -> UIKeyboardType {
    switch type {
    case "Number": .decimalPad
    case "Phone": .phonePad
    case "IdentityNumber": .asciiCapable
    default: .default
    }
}

struct NativeActivityTextInput: View {
    let label: String
    let type: String
    @Binding var text: String
    private var isText: Bool { type == "Text" || type == "LongText" }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(label, text: $text, axis: type == "LongText" ? .vertical : .horizontal)
                .lineLimit(type == "LongText" ? 3...6 : 1...1)
                .keyboardType(nativeActivityKeyboard(type))
                .textInputAutocapitalization(isText ? .sentences : .never)
                .autocorrectionDisabled(!isText)
                .textFieldStyle(.roundedBorder)
            if isText {
                let count = nativeActivityTextLength(text)
                Text("\(count) / 500").font(.caption)
                    .foregroundStyle(count > 500 ? Color.red : Brand.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
