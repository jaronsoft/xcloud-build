import SwiftUI

struct RestaurantReservationManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let storeID: String
    let storeName: String

    var body: some View {
        let principal = store.session.flatMap { nativeTourismPrincipal($0.accessToken) } ?? ""
        RestaurantReservationManagementContent(store: store, storeID: storeID, storeName: storeName, principal: principal)
            .id("\(principal):\(storeID)")
            .onChange(of: principal) { _, _ in dismiss() }
    }
}

private struct RestaurantReservationManagementContent: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SessionStore
    let storeID: String
    let storeName: String
    let principal: String
    @State private var status = ""
    @State private var rows: [[String: Any]] = []
    @State private var total = 0
    @State private var page = 1
    @State private var loading = false
    @State private var error: String?
    @State private var revision = 0
    @State private var requestGeneration = 0
    @State private var pendingAction: NativeDiningReservationAttempt?
    @State private var attempts: [NativeDiningReservationAttempt] = []
    @State private var storageFailed = false
    @State private var gateOpen = false
    @State private var visible = false
    @State private var actionTask: Task<Void, Never>?
    @State private var actionGeneration = 0
    @State private var releasableAttempt: NativeDiningReservationAttempt?
    @State private var actionMessage: String?

    private let statuses = [("", "全部"), ("Pending", "待处理"), ("Confirmed", "已确认"),
                            ("Declined", "已拒绝"), ("Cancelled", "已取消")]

    var body: some View {
        List {
            Section {
                Text("当前门店：\(storeName)").font(.headline)
                Text("预订功能按平台开关开放；岗位和门店权限由服务端逐次复核。")
                    .font(.caption).foregroundStyle(Brand.muted)
            }
            Section("预订状态") {
                Picker("状态", selection: $status) {
                    ForEach(statuses, id: \.0) { Text($0.1).tag($0.0) }
                }.pickerStyle(.menu).onChange(of: status) { _, _ in rows = []; total = 0; page = 1; revision += 1 }
            }
            if let actionMessage {
                Section { Text(actionMessage).font(.footnote) }
            }
            if storageFailed {
                Section {
                    Text("无法读取本机核对记录，已暂停预订处理。").foregroundStyle(.red)
                    Button("重新读取") { restoreAttempts() }
                }
            }
            if gateOpen && !storageFailed && !attempts.isEmpty {
                Section("待核对的预订") {
                    ForEach(attempts) { attempt in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("预订编号 \(attempt.id)").font(.footnote)
                            if releasableAttempt == attempt {
                                Text("当前仍为\(statusName(attempt.previous))。").font(.caption)
                                Button("重新核对并允许处理") { check(attempt, releaseIfUnchanged: true) }
                            } else {
                                Button("核对原预订") { check(attempt) }
                            }
                        }.disabled(!canOperate)
                    }
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red); Button("重试") { revision += 1 } }
            }
            if loading && rows.isEmpty { Section { ProgressView("正在读取餐饮预订…") } }
            if !loading && rows.isEmpty && error == nil {
                Section { Text("暂无符合条件的预订").foregroundStyle(Brand.muted) }
            }
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                let id = reservationText(row["Id"])
                let state = reservationText(row["Status"])
                Section {
                    HStack { Text("\(reservationText(row["GuestName"], fallback: "顾客")) · \(reservationText(row["GuestCount"], fallback: "0")) 位").font(.headline); Spacer(); Text(statusName(state)).font(.caption).foregroundStyle(Brand.primary) }
                    Text("\(reservationText(row["ServiceDate"], fallback: "日期待确认")) · \(reservationText(row["StartTime"]))–\(reservationText(row["EndTime"]))")
                    Text("联系电话：\(maskedPhone(reservationText(row["GuestPhone"])))")
                    let guestNote = reservationText(row["GuestNote"])
                    if !guestNote.isEmpty { Text("顾客备注：\(guestNote)").font(.caption) }
                    let handleNote = reservationText(row["HandleNote"])
                    if !handleNote.isEmpty { Text("处理备注：\(handleNote)").font(.caption) }
                    if state == "Pending" {
                        HStack {
                            Button("拒绝", role: .destructive) { prepare(id, state, "Declined") }.buttonStyle(.borderless)
                            Button("确认预订") { prepare(id, state, "Confirmed") }.buttonStyle(.borderless)
                        }.disabled(!canSubmit(id))
                    } else if state == "Confirmed" {
                        Button("取消预订", role: .destructive) { prepare(id, state, "Cancelled") }.disabled(!canSubmit(id))
                    }
                }
            }
            if total > 0 {
                Section {
                    HStack {
                        Button("上一页") { rows = []; page -= 1; revision += 1 }.disabled(page <= 1 || loading)
                        Spacer(); Text("第 \(page) 页 · 共 \(total) 条").font(.caption)
                        Spacer(); Button("下一页") { rows = []; page += 1; revision += 1 }
                            .disabled(page >= total / 20 + (total % 20 == 0 ? 0 : 1) || loading)
                    }
                }
            }
        }
        .navigationTitle("餐饮预订管理")
        .confirmationDialog("确认\(actionLabel(pendingAction?.target))此预订？", isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
                Button("确认", role: pendingAction?.target == "Confirmed" ? nil : .destructive) {
                    if let attempt = pendingAction { submit(attempt) }
                }
            }
        .task(id: "\(status)-\(page)-\(revision)-\(scenePhase)") {
            guard scenePhase == .active else { return }
            restoreAttempts()
            await loadReservations()
        }
        .onAppear { visible = true }
        .onDisappear { visible = false; invalidateAction() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { gateOpen = false; invalidateAction() }
        }
    }

    private var currentPrincipal: Bool {
        !principal.isEmpty && store.session.flatMap { nativeTourismPrincipal($0.accessToken) } == principal
    }

    private var canOperate: Bool {
        visible && scenePhase == .active && currentPrincipal && gateOpen && !storageFailed && actionTask == nil
    }

    private func canSubmit(_ id: String) -> Bool {
        canOperate && !loading && !attempts.contains { $0.id == id }
    }

    private func actionLabel(_ target: String?) -> String {
        switch target {
        case "Confirmed": "确认"
        case "Declined": "拒绝"
        case "Cancelled": "取消"
        default: "处理"
        }
    }

    private func prepare(_ id: String, _ previous: String, _ target: String) {
        let attempt = NativeDiningReservationAttempt(id: id, storeID: storeID, previous: previous, target: target)
        if canSubmit(id) && attempt.isValid { pendingAction = attempt }
    }

    private func invalidateAction() {
        actionGeneration += 1
        actionTask?.cancel()
        actionTask = nil
        pendingAction = nil
        releasableAttempt = nil
    }

    private func restoreAttempts() {
        guard currentPrincipal else { return }
        do {
            attempts = try NativeDiningReservationRecovery(principal: principal).read().filter { $0.storeID == storeID }
            storageFailed = false
        } catch {
            storageFailed = true
        }
    }

    private func statusName(_ value: String) -> String {
        statuses.first(where: { $0.0 == value })?.1 ?? "状态待确认"
    }
    private func reservationText(_ value: Any?, fallback: String = "") -> String {
        guard let value, !(value is NSNull) else { return fallback }
        return String(describing: value)
    }
    private func maskedPhone(_ phone: String) -> String {
        guard phone.count >= 7 else { return "已保护" }
        return "\(phone.prefix(3))****\(phone.suffix(4))"
    }
    @MainActor private func loadReservations() async {
        guard currentPrincipal, NativeDiningReservationAttempt.validID(storeID) else { return }
        requestGeneration += 1
        let requestID = requestGeneration
        let requestedPage = page
        let requestedStatus = status
        loading = true; error = nil
        defer {
            if requestGeneration == requestID { loading = false }
        }
        do {
            let gateState = await MobileAPI(store: store).featureAccessState("F-FNB-002", forceRefresh: true)
            guard !Task.isCancelled, requestGeneration == requestID, currentPrincipal else { return }
            gateOpen = gateState == .open
            if gateState != .open {
                rows = []; total = 0; error = "餐饮预订功能待平台开放。"; return
            }
            var path = "/api/JHCTIDining/GetReservations?storeId=\(storeID)&page=\(requestedPage)&pageSize=20"
            if !requestedStatus.isEmpty { path += "&status=\(requestedStatus)" }
            let response = try await MobileAPI(store: store).get(path, authenticated: true, expectedPrincipal: principal)
            guard !Task.isCancelled, requestGeneration == requestID, currentPrincipal else { return }
            guard let response = response as? [String: Any],
                  let parsed = nativeDiningReservationManagementPage(response, page: requestedPage, pageSize: 20, storeID: storeID) else {
                throw MobileAPIError.unavailable("餐饮预订列表数据异常，请刷新后重试")
            }
            rows = parsed.rows; total = parsed.total
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if requestGeneration == requestID, currentPrincipal {
                self.error = error.localizedDescription; rows = []; total = 0
            }
        }
    }
    @MainActor private func submit(_ attempt: NativeDiningReservationAttempt) {
        pendingAction = nil
        guard canSubmit(attempt.id), rows.contains(where: {
            $0["Id"] as? String == attempt.id && $0["Status"] as? String == attempt.previous
        }) else { return }
        let recovery: NativeDiningReservationRecovery
        do {
            recovery = try NativeDiningReservationRecovery(principal: principal)
            try recovery.add(attempt)
            attempts.append(attempt)
        } catch {
            restoreAttempts()
            actionMessage = "未能保存核对记录，未发送处理请求。"
            return
        }
        performAction(failureMessage: "处理结果待核对，请查询原预订。") { generation in
            let path = "/api/JHCTIDining/HandleReservation?id=\(attempt.id)&status=\(attempt.target)"
                + "&expectedStoreId=\(attempt.storeID)&expectedStatus=\(attempt.previous)"
            let result = try await MobileAPI(store: store).post(path, body: [:], authenticated: true,
                expectedPrincipal: principal, canRefresh: false, requireExplicitResponse: true)
            guard actionIsCurrent(generation) else { return }
            guard result as? String == attempt.target else { throw MobileAPIError.unavailable("处理回执异常") }
            try finish(attempt, recovery: recovery, message: "预订\(statusName(attempt.target))。")
        }
    }

    @MainActor private func check(_ attempt: NativeDiningReservationAttempt, releaseIfUnchanged: Bool = false) {
        guard canOperate, attempts.contains(attempt), attempt.storeID == storeID,
              !releaseIfUnchanged || releasableAttempt == attempt else { return }
        releasableAttempt = nil
        performAction(failureMessage: "未确认原预订状态，已保留核对记录。") { generation in
            let path = "/api/JHCTIDining/GetReservationState?storeId=\(attempt.storeID)&id=\(attempt.id)"
            let result = try await MobileAPI(store: store).get(path, authenticated: true,
                expectedPrincipal: principal, requireExplicitResponse: true)
            guard actionIsCurrent(generation) else { return }
            guard let actual = attempt.readStatus(result) else { throw MobileAPIError.unavailable("核对回执异常") }
            if actual == attempt.previous && !releaseIfUnchanged {
                releasableAttempt = attempt
                return
            }
            let message = actual == attempt.previous
                ? "原预订仍为\(statusName(actual))，可按最新状态另行处理。"
                : "原预订当前状态为\(statusName(actual))。"
            try finish(attempt, recovery: NativeDiningReservationRecovery(principal: principal), message: message)
        }
    }

    @MainActor private func performAction(failureMessage: String,
        operation: @escaping @MainActor (Int) async throws -> Void) {
        actionGeneration += 1
        let generation = actionGeneration
        actionMessage = nil
        actionTask = Task { @MainActor in
            defer { if actionGeneration == generation { actionTask = nil } }
            guard actionIsCurrent(generation) else { return }
            do { try await operation(generation) }
            catch { if actionIsCurrent(generation) { actionMessage = failureMessage } }
        }
    }

    private func actionIsCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && actionGeneration == generation && visible && scenePhase == .active && currentPrincipal
    }

    @MainActor private func finish(_ attempt: NativeDiningReservationAttempt, recovery: NativeDiningReservationRecovery,
        message: String) throws {
        try recovery.remove(attempt)
        restoreAttempts()
        actionMessage = message
        rows = []
        revision += 1
    }
}
