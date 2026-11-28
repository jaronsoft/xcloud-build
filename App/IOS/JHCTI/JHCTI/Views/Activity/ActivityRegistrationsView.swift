import SwiftUI

@MainActor private var inFlightRegistrationWrites = Set<UUID>()

struct ActivityRegistrationQrRetry: Equatable {
    let registrationID: String
    let title: String
    let token: String
    let message: String
}

struct ActivityRegistrationsView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [[String: Any]] = []
    @State private var filter = ""
    @State private var page = 1
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var pendingCancellation: [String: Any]?
    @State private var cancelBusyId = ""
    @State private var cancellationToken = ""
    @State private var qrImage: Data?
    @State private var qrTitle = ""
    @State private var qrBusyId = ""
    @State private var qrRetry: ActivityRegistrationQrRetry?
    @State private var revision = 0
    @State private var requestSequence = 0
    @State private var loadedToken = ""
    @State private var credentialClock = Date()
    @State private var qrRegistrationId = ""
    @State private var qrCheckedIn = false
    @State private var qrStatusCountdown = 5
    @State private var qrSequence = 0
    @State private var pendingDeletion: [String: Any]?
    @State private var deletionToken = ""
    @State private var deleteBusyId = ""
    @State private var operationSequence = 0
    @State private var pendingAttempt: ActivityRegistrationAttempt?
    @State private var reviewedAttempt: ActivityRegistrationAttempt?
    @State private var recoveryOwner: String?
    @State private var recoveryStorageFailed = false
    @State private var checkingOutcome = false
    @State private var pageVisible = true
    @State private var canLoadMore = false
    @State private var cancellationNotice: String?

    private let filters = [("", "全部"), ("Registered", "已报名"), ("CheckedIn", "已签到"), ("Cancelled", "已取消")]
    private var principal: String? {
        guard let token = store.session?.accessToken, !token.isEmpty else { return nil }
        return nativeTourismPrincipal(token)
    }
    private var recoveryReady: Bool { recoveryOwner != nil && recoveryOwner == principal && !recoveryStorageFailed }
    private func operationLocked(_ id: String) -> Bool { !recoveryReady || pendingAttempt?.id == id }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ActivityRegistrationSelfCheckIn(store: store) { revision += 1 }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.0) { item in
                            Button(item.1) { filter = item.0; revision += 1 }
                                .accessibilityLabel("筛选\(item.1)活动报名")
                                .accessibilityAddTraits(filter == item.0 ? .isSelected : [])
                                .disabled(!deleteBusyId.isEmpty || !cancelBusyId.isEmpty)
                                .font(.system(size: NativeTypography.size(14), weight: .semibold))
                                .foregroundStyle(filter == item.0 ? .white : Brand.primary)
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                .background(filter == item.0 ? Brand.primary : .white, in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("活动报名状态筛选")
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                List {
                    if rows.isEmpty {
                        let emptyStatusLabel = filter == "Registered" ? "已报名"
                            : filter == "CheckedIn" ? "已签到"
                            : filter == "Cancelled" ? "已取消" : ""
                        Group {
                            if loading { ProgressView("正在读取报名记录…").frame(maxWidth: .infinity).padding(.vertical, 40) }
                            else if let error {
                                VStack(spacing: 8) {
                                    ContentUnavailableView(error, systemImage: "exclamationmark.arrow.circlepath", description: Text("检查登录状态后点击重试。"))
                                    Button("重试") { Task { await load(reset: true) } }
                                        .disabled(loading)
                                }
                            }
                            else { ContentUnavailableView("暂无\(emptyStatusLabel)活动报名记录。", systemImage: "ticket", description: Text("报名成功后，签到凭证会显示在这里。")) }
                        }.listRowSeparator(.hidden).listRowBackground(Brand.background)
                    }
                    ForEach(rows.indices, id: \.self) { index in
                        registrationCard(rows[index])
                            .listRowInsets(EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Brand.background)
                    }
                    if !rows.isEmpty, error == nil {
                        Text("共 \(total) 条报名记录")
                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                            .frame(maxWidth: .infinity).listRowSeparator(.hidden)
                            .listRowBackground(Brand.background)
                    }
                    if canLoadMore {
                        Button(loading ? "正在加载…" : "加载更多") { Task { await load(reset: false) } }
                            .frame(maxWidth: .infinity).listRowBackground(Brand.background)
                            .disabled(loading)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Brand.background)
                .refreshable { await load(reset: true) }
                ActivityCancellationStatusBanner(message: cancellationNotice)
                recoveryControls
                if let error, !rows.isEmpty {
                    VStack(spacing: 4) {
                        Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                        Button("重试") { Task { await load(reset: true) } }
                            .disabled(loading)
                    }.padding(8)
                }
            }
            .background(Brand.background)
            .navigationTitle("我的活动报名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("刷新") { revision += 1 }.disabled(loading || !cancelBusyId.isEmpty || !deleteBusyId.isEmpty) }
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .task(id: "\(store.session?.accessToken ?? "")-\(filter)-\(revision)") { await load(reset: true) }
            .task {
                while !Task.isCancelled {
                    refreshCredentialClock()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            .task(id: qrImage == nil ? nil : qrSequence) {
                guard qrImage != nil, let token = store.session?.accessToken else { return }
                let id = qrRegistrationId
                let sequence = qrSequence
                while canPollQr(id: id, token: token, sequence: sequence) {
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                    catch { return }
                    guard canPollQr(id: id, token: token, sequence: sequence) else { return }
                    if qrStatusCountdown <= 1 {
                        qrStatusCountdown = 5
                        await refreshQrStatus(id: id, token: token, sequence: sequence)
                    } else { qrStatusCountdown -= 1 }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { restoreRecovery(); refreshCredentialClock(); revision += 1 }
                else {
                    requestSequence += 1; clearQr(); rows = []; total = 0; loadedToken = ""; canLoadMore = false; loading = false
                    pendingCancellation = nil; pendingDeletion = nil
                    reviewedAttempt = nil
                }
            }
            .onChange(of: filter) { _, _ in
                clearQr(); pendingCancellation = nil; pendingDeletion = nil
            }
            .onChange(of: store.session?.accessToken) { _, newToken in
                clearQr()
                pendingCancellation = nil; cancellationToken = ""; pendingDeletion = nil; deletionToken = ""
                requestSequence += 1; rows = []; total = 0; loadedToken = ""; loading = false
                canLoadMore = false
                if nativeTourismPrincipal(newToken) != recoveryOwner { resetRecoveryContext(); restoreRecovery() }
            }
            .sheet(isPresented: Binding(get: { qrImage != nil || qrCheckedIn }, set: { if !$0 { closeQrAndRefresh() } })) {
                NavigationStack {
                    VStack(spacing: 12) {
                        Text(qrCheckedIn ? "活动签到成功" : qrTitle).font(.system(size: NativeTypography.size(18), weight: .semibold))
                        if qrCheckedIn {
                            Text("现场核验已完成，报名状态已更新为“已签到”。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                        } else if let qrImage, let image = UIImage(data: qrImage) {
                            Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                                .frame(maxWidth: 280, maxHeight: 280).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                            Text("\(qrStatusCountdown) 秒后自动查询核验状态")
                                .font(.system(size: NativeTypography.size(13))).foregroundStyle(Brand.primary)
                            Text("请向活动现场工作人员出示二维码；未核验时会继续查询。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
                        }
                    }
                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Brand.background)
                    .navigationTitle("活动签到二维码").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("关闭") { closeQrAndRefresh() } }
                }
            }
            .onDisappear {
                pageVisible = false; canLoadMore = false
                requestSequence += 1; rows = []; clearQr(); pendingCancellation = nil
                cancellationToken = ""; pendingDeletion = nil; deletionToken = ""
                resetRecoveryContext()
            }
            .onAppear { pageVisible = true; restoreRecovery() }
            .overlay {
                ActivityRegistrationConfirmationOverlay(
                    pendingDeletion: pendingDeletion,
                    pendingCancellation: pendingCancellation,
                    deleteBusy: !deleteBusyId.isEmpty,
                    cancelBusy: !cancelBusyId.isEmpty,
                    onKeepDeletion: { self.pendingDeletion = nil },
                    onConfirmDeletion: { item in
                        let token = store.session?.accessToken ?? ""
                        deletionToken = token
                        Task { await submit(item, expectedToken: token, action: .delete) }
                    },
                    onKeepCancellation: { self.pendingCancellation = nil },
                    onConfirmCancellation: { item in
                        let token = cancellationToken
                        Task { await submit(item, expectedToken: token, action: .cancel) }
                    }
                )
            }
        }
    }

    private func closeQrAndRefresh() {
        let wasVisible = qrImage != nil || qrCheckedIn
        clearQr()
        if wasVisible && pageVisible && scenePhase == .active { revision += 1 }
    }

    @ViewBuilder private func registrationCard(_ item: [String: Any]) -> some View {
        MyActivityRegistrationRecordCard(
            item: item,
            credentialClock: credentialClock,
            expectedToken: store.session?.accessToken,
            qrBusyId: qrBusyId,
            qrRetry: qrRetry,
            loading: loading,
            cancelBusyId: cancelBusyId,
            deleteBusyId: deleteBusyId,
            credentialLocked: operationLocked(item["Id"] as? String ?? ""),
            mutationBlocked: !recoveryReady || pendingAttempt != nil,
            onCopyCode: { id, code, expectedToken in
                guard pageVisible, scenePhase == .active,
                      !operationLocked(id), let expectedToken, !expectedToken.isEmpty,
                      store.session?.accessToken == expectedToken, loadedToken == expectedToken,
                      let currentItem = rows.first(where: { $0["Id"] as? String == id }),
                      currentItem["Status"] as? String == "Registered",
                      currentItem["CredentialCode"] as? String == code,
                      !activityRegistrationCredentialUnavailable(currentItem, now: Date()) else {
                    cancellationNotice = "签到凭证已变化或过期，请刷新报名记录。"
                    revision += 1
                    return
                }
                UIPasteboard.general.string = code
                cancellationNotice = "签到凭证已复制。"
            },
            onShowQr: { id, title in Task { await showQr(id: id, title: title) } },
            onRequestCancellation: { item in
                cancellationToken = store.session?.accessToken ?? ""
                pendingCancellation = item
            },
            onRetryQr: { retry in
                guard store.session?.accessToken == retry.token else { qrRetry = nil; return }
                Task { await showQr(id: retry.registrationID, title: retry.title) }
            },
            onRequestDeletion: { item in
                deletionToken = store.session?.accessToken ?? ""
                pendingDeletion = item
            },
            onRefresh: { revision += 1 }
        )
    }

    @MainActor private func load(reset: Bool) async {
        guard pageVisible, scenePhase == .active else { return }
        if !reset && (loading || !canLoadMore) { return }
        guard let token = store.session?.accessToken, !token.isEmpty,
              let expectedPrincipal = nativeTourismPrincipal(token) else {
            rows = []; total = 0; canLoadMore = false; loadedToken = ""; error = "请先登录文旅账号，再查看活动报名记录。"; loading = false; return
        }
        let requestedFilter = filter
        let queryFilter = requestedFilter
        if !reset && loadedToken != token { rows = []; total = 0; canLoadMore = false; error = "登录状态已变化，请刷新报名记录。"; return }
        let cursor = reset ? nil : rows.last?["Id"] as? String
        if !reset && cursor.flatMap({ Int64($0) }).map({ $0 > 0 && String($0) == cursor }) != true {
            canLoadMore = false; error = "报名记录游标无效，请刷新后继续。"; return
        }
        clearQr(); pendingCancellation = nil; pendingDeletion = nil
        let targetPage = reset ? 1 : page + 1
        if reset { rows = []; total = 0; page = 1; loadedToken = ""; canLoadMore = false }
        loading = true
        error = nil
        let sequence = requestSequence + 1; requestSequence = sequence
        func isCurrent() -> Bool {
            !Task.isCancelled && sequence == requestSequence && store.session?.accessToken == token
                && filter == requestedFilter && pageVisible && scenePhase == .active
        }
        defer { if isCurrent() { loading = false } }
        do {
            let encodedStatus = queryFilter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let before = cursor.map { "&beforeRegistrationId=\($0)" } ?? ""
            let value = try await MobileAPI(store: store).get("/api/JHCTIActivity/GetMyRegistrationsPage?page=\(targetPage)&pageSize=20&status=\(encodedStatus)\(before)", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any]
            guard isCurrent() else { return }
            guard let value,
                  let data = (value["data"] ?? value["Data"]) as? [[String: Any]] else {
                throw MobileAPIError.unavailable("报名记录响应格式异常")
            }
            guard let count = nativeActivityRegistrationPageTotal(value, rowCount: data.count) else {
                throw MobileAPIError.unavailable("报名数量异常，请刷新后重试。")
            }
            var receivedIds = Set<String>()
            guard data.allSatisfy({ item in
                guard let id = item["Id"] as? String, let number = Int64(id), number > 0, String(number) == id else { return false }
                return receivedIds.insert(id).inserted
            }) else { throw MobileAPIError.unavailable("报名记录编号异常，请刷新后重试。") }
            let existing = Set(rows.compactMap { $0["Id"] as? String })
            let additions = data.filter { !existing.contains($0["Id"] as? String ?? "") }
            if !reset && !data.isEmpty && additions.isEmpty {
                canLoadMore = false; throw MobileAPIError.unavailable("报名列表已变化，请刷新后继续。")
            }
            clearQr()
            rows = reset ? data : rows + additions
            total = max(count, rows.count); page = targetPage; loadedToken = token
            canLoadMore = data.count == 20 && rows.count < total
        } catch {
            if isCurrent() { self.error = error.localizedDescription }
        }
    }

    private var hasOperationInProgress: Bool { checkingOutcome || !cancelBusyId.isEmpty || !deleteBusyId.isEmpty }

    @ViewBuilder private var recoveryControls: some View {
        if recoveryOwner != nil && recoveryOwner == principal {
            if recoveryStorageFailed {
                Text("无法读取本机报名核对记录，报名操作暂不可用。")
                    .font(.footnote).foregroundStyle(Brand.muted)
                Button("重读核对记录") { restoreRecovery() }
            }
            if let attempt = pendingAttempt {
                VStack(alignment: .leading, spacing: 6) {
                    Text("待核对 · \(attempt.action.label) · 报名编号 \(attempt.id)")
                        .font(.footnote).foregroundStyle(Brand.muted)
                    Button("核对原报名") { Task { await checkOutcome() } }
                    if reviewedAttempt == attempt {
                        Button("确认并解除保护") { Task { await checkOutcome(release: true) } }
                    }
                }
                .disabled(hasOperationInProgress)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 6)
            }
        }
    }

    private func resetRecoveryContext() {
        operationSequence += 1
        recoveryOwner = nil; recoveryStorageFailed = false; pendingAttempt = nil; reviewedAttempt = nil
        checkingOutcome = false; cancelBusyId = ""; deleteBusyId = ""; cancellationNotice = nil
    }

    private func restoreRecovery() {
        guard pageVisible, let owner = principal else { return }
        recoveryOwner = owner
        do {
            pendingAttempt = try ActivityRegistrationRecovery(principal: owner).read()
            recoveryStorageFailed = false
        } catch {
            pendingAttempt = nil; recoveryStorageFailed = true
        }
        if reviewedAttempt != pendingAttempt { reviewedAttempt = nil }
    }

    private func finishRecovery(_ recovery: ActivityRegistrationRecovery, attempt: ActivityRegistrationAttempt, message: String) throws {
        try recovery.remove(attempt)
        pendingAttempt = nil; reviewedAttempt = nil; cancellationNotice = message
        requestSequence += 1; rows = []; loadedToken = ""; canLoadMore = false; clearQr(); revision += 1
    }

    @MainActor private func checkOutcome(release: Bool = false) async {
        guard pageVisible, scenePhase == .active, recoveryReady, !hasOperationInProgress,
              let owner = principal, let attempt = pendingAttempt, !release || reviewedAttempt == attempt else { return }
        guard !inFlightRegistrationWrites.contains(attempt.marker) else {
            cancellationNotice = "原报名请求仍在处理中，请稍后核对。"; return
        }
        operationSequence += 1
        let operation = operationSequence
        checkingOutcome = true; reviewedAttempt = nil
        defer { if operation == operationSequence { checkingOutcome = false } }
        func isCurrent() -> Bool {
            !Task.isCancelled && pageVisible && scenePhase == .active
                && operation == operationSequence && principal == owner && pendingAttempt == attempt
        }
        do {
            let raw = try await MobileAPI(store: store).get("/api/JHCTIActivity/GetMyRegistrationStatus?id=\(attempt.id)",
                authenticated: true, expectedPrincipal: owner, requireExplicitResponse: true)
            guard isCurrent() else { return }
            let recovery = try ActivityRegistrationRecovery(principal: owner)
            switch (raw as? String).flatMap(ActivityRegistrationReadStatus.init(rawValue:)) {
            case .registered:
                if release { try finishRecovery(recovery, attempt: attempt, message: "已解除保护。请按最新报名状态操作。") }
                else {
                    reviewedAttempt = attempt
                    cancellationNotice = "原记录仍显示已报名。核对后可恢复该记录的操作。"
                }
            case .cancelled: try finishRecovery(recovery, attempt: attempt, message: "原报名已取消。")
            case .checkedIn: try finishRecovery(recovery, attempt: attempt, message: "原报名已签到。")
            case .unavailable: try finishRecovery(recovery, attempt: attempt, message: "原报名记录已不在列表中。")
            case nil: throw MobileAPIError.unavailable("报名状态回执异常")
            }
        } catch {
            if isCurrent() { cancellationNotice = "暂时无法核对原报名，请稍后重试。" }
        }
    }

    @MainActor private func submit(_ item: [String: Any], expectedToken: String, action: ActivityRegistrationAction) async {
        pendingCancellation = nil; pendingDeletion = nil
        guard pageVisible, scenePhase == .active, recoveryReady, pendingAttempt == nil, !hasOperationInProgress,
              let owner = principal, store.session?.accessToken == expectedToken, loadedToken == expectedToken,
              let id = item["Id"] as? String, let current = rows.first(where: { $0["Id"] as? String == id }) else { return }
        let attempt = ActivityRegistrationAttempt(id: id, action: action)
        let allowed = action == .cancel
            ? current["CanCancel"] as? Bool == true && !activityRegistrationCredentialUnavailable(current)
            : activityRegistrationExpired(current)
        guard attempt.valid, allowed else { return }
        let recovery: ActivityRegistrationRecovery
        do {
            recovery = try ActivityRegistrationRecovery(principal: owner)
            try recovery.add(attempt)
        } catch {
            restoreRecovery(); cancellationNotice = "无法保存报名核对记录，本次操作未发送。"; return
        }
        pendingAttempt = attempt; reviewedAttempt = nil
        if action == .cancel { cancelBusyId = id } else { deleteBusyId = id }
        operationSequence += 1
        let operation = operationSequence
        requestSequence += 1; loading = false; error = nil; cancellationNotice = nil; clearQr()
        inFlightRegistrationWrites.insert(attempt.marker)
        defer {
            inFlightRegistrationWrites.remove(attempt.marker)
            if operation == operationSequence { cancelBusyId = ""; deleteBusyId = "" }
        }
        func isCurrent() -> Bool {
            !Task.isCancelled && pageVisible && scenePhase == .active
                && operation == operationSequence && principal == owner && pendingAttempt == attempt
        }
        do {
            let receipt = try await MobileAPI(store: store).post("/api/JHCTIActivity/\(action.rawValue)?id=\(id)", body: [:],
                authenticated: true, expectedPrincipal: owner, canRefresh: false, requireExplicitResponse: true)
            guard isCurrent() else { return }
            guard attempt.matchesReceipt(receipt) else { throw MobileAPIError.unavailable("报名操作回执不匹配") }
            try finishRecovery(recovery, attempt: attempt, message: action == .cancel ? "报名已取消。" : "过期报名记录已删除。")
        } catch {
            guard isCurrent() else { return }
            if let status = (error as? MobileAPIError)?.httpStatusCode, [400, 403, 409].contains(status),
               (try? finishRecovery(recovery, attempt: attempt, message: error.localizedDescription)) != nil { return }
            cancellationNotice = "\(action.label)结果暂未确认，请核对原报名。"
        }
    }

    private func clearQr() {
        qrSequence += 1; qrImage = nil; qrBusyId = ""; qrRegistrationId = ""; qrCheckedIn = false; qrRetry = nil
    }

    private func refreshCredentialClock() {
        credentialClock = Date()
        guard !qrRegistrationId.isEmpty, !qrCheckedIn else { return }
        if let item = rows.first(where: { $0["Id"] as? String == qrRegistrationId }),
           !activityRegistrationCredentialUnavailable(item, now: credentialClock) { return }
        clearQr()
    }

    private func canPollQr(id: String, token: String, sequence: Int) -> Bool {
        !Task.isCancelled && pageVisible && scenePhase == .active && qrImage != nil
            && qrRegistrationId == id && qrSequence == sequence && store.session?.accessToken == token
            && !operationLocked(id)
    }

    private func refreshQrStatus(id: String, token: String, sequence: Int) async {
        guard canPollQr(id: id, token: token, sequence: sequence),
              let principal = nativeTourismPrincipal(token) else { return }
        do {
            let raw = try await MobileAPI(store: store).get("/api/JHCTIActivity/GetMyRegistrationStatus?id=\(id)",
                authenticated: true, expectedPrincipal: principal, requireExplicitResponse: true)
            guard canPollQr(id: id, token: token, sequence: sequence),
                  let status = (raw as? String).flatMap(ActivityRegistrationReadStatus.init(rawValue:)) else { return }
            switch status {
            case .checkedIn:
                qrCheckedIn = true; qrImage = nil
            case .cancelled, .unavailable:
                closeQrAndRefresh()
            case .registered: break
            }
        } catch {
            // 暂时无法确认时继续核对，二维码到期仍由独立时钟处理。
        }
    }

    @MainActor private func showQr(id: String, title: String) async {
        guard !Task.isCancelled, pageVisible, scenePhase == .active,
              !id.isEmpty, !operationLocked(id), qrBusyId.isEmpty,
              let token = store.session?.accessToken, loadedToken == token,
              let principal = nativeTourismPrincipal(token),
              let item = rows.first(where: { $0["Id"] as? String == id }),
              let code = item["CredentialCode"] as? String,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !activityRegistrationCredentialUnavailable(item) else {
            refreshCredentialClock(); revision += 1; return
        }
        qrSequence += 1; let operation = qrSequence
        qrRegistrationId = id
        qrCheckedIn = false
        qrStatusCountdown = 5
        qrBusyId = id; qrRetry = nil
        defer { if operation == qrSequence { qrBusyId = "" } }
        // 回包只允许更新仍处于当前列表、账号和凭证上下文的请求。
        func currentRow() -> [String: Any]? {
            guard !Task.isCancelled, pageVisible, scenePhase == .active,
                  operation == qrSequence, qrRegistrationId == id, !operationLocked(id),
                  store.session?.accessToken == token, loadedToken == token,
                  let current = rows.first(where: { $0["Id"] as? String == id }),
                  current["Status"] as? String == "Registered", current["CredentialCode"] as? String == code else { return nil }
            return current
        }
        do {
            let value = try await MobileAPI(store: store).get("/api/JHCTIActivity/GetMyRegistrationQr?id=\(id)",
                authenticated: true, expectedPrincipal: principal, requireExplicitResponse: true)
            guard let current = currentRow() else { return }
            let data = activityRegistrationQrPng(value)
            // 回包和图像处理可能跨过活动截止时间，展示前必须重新判定。
            guard !activityRegistrationCredentialUnavailable(current) else {
                clearQr(); credentialClock = Date(); revision += 1; return
            }
            guard !Task.isCancelled else { return }
            guard let data else { throw MobileAPIError.unavailable("活动二维码数据无效，请重试。") }
            qrTitle = title; qrImage = data
        } catch {
            guard let current = currentRow() else { return }
            guard !activityRegistrationCredentialUnavailable(current) else {
                clearQr(); credentialClock = Date(); revision += 1; return
            }
            qrRetry = ActivityRegistrationQrRetry(
                registrationID: id, title: title, token: token, message: error.localizedDescription)
        }
    }
}

private struct ActivityCancellationStatusBanner: View {
    let message: String?

    @ViewBuilder var body: some View {
        if let message {
            Text(message).font(.system(size: NativeTypography.size(13)))
                .foregroundStyle(Brand.primary).padding(.horizontal, 16).padding(.vertical, 8)
        }
    }
}

func activityRegistrationBusinessDateTime(_ value: Any?) -> String? {
    bookingBusinessDateTime(value)
}

func activityRegistrationParticipantStatus(_ value: Any?) -> String {
    switch value as? String {
    case "Registered": return "已报名"
    case "CheckedIn": return "已签到"
    case "Cancelled": return "已取消"
    default: return "待核对"
    }
}
