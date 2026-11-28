import SwiftUI

struct RestaurantQueueManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SessionStore
    let storeID: String
    let storeName: String
    @State private var queueDate = Date()
    @State private var session: NativeDiningQueueSummary?
    @State private var entries: [[String: Any]] = []
    @State private var loadedDate = ""
    @State private var page = 1
    @State private var total = 0
    @State private var loading = true
    @State private var loadingMore = false
    @State private var saving = false
    @State private var error: String?
    @State private var failedPage: Int?
    @State private var notice: String?
    @State private var revision = 0
    @State private var requestGeneration = 0
    @State private var pendingEntry: [String: Any]?
    @State private var pendingAction = NativeDiningQueueAction.complete
    @State private var attempt: NativeDiningQueueAttempt?
    @State private var reviewed: NativeDiningQueueAttempt?
    @State private var storageFailed = false
    @State private var visible = false
    @State private var entryPrincipal: String?
    @State private var actionGeneration = 0

    // 场次页重开时，旧页面仍在等待的写请求也需要先结束。
    @MainActor private static var inFlightWrites = Set<UUID>()

    private let pageSize = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("排队叫号").font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif))
                    Text("\(storeName) · 仅处理当前授权门店的排队场次")
                        .font(.caption).foregroundStyle(Brand.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(Brand.background, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker("排队日期", selection: Binding(get: { queueDate }, set: changeDate), displayedComponents: .date)
                        .environment(\.timeZone, NativeDiningQueueAttempt.zone).disabled(saving)
                    Button("查询所选日期") { revision += 1 }.buttonStyle(.bordered).disabled(saving || loading || loadingMore)
                    if loadedDate != selectedDateText && !loading {
                        Text("日期已修改，请先查询后再操作当前场次。")
                            .font(.caption).foregroundStyle(Brand.muted)
                    }
                }.merchantCard()
                recoveryCard
                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).foregroundStyle(.red)
                        if attempt == nil || failedPage != nil && failedPage != 1 {
                            Button("重试第 \(failedPage ?? 1) 页") {
                                Task { await load(page: failedPage ?? 1) }
                            }.buttonStyle(.bordered).disabled(loading || loadingMore || saving)
                        }
                    }.merchantCard()
                }
                if let notice {
                    Text(notice).font(.caption).foregroundStyle(Brand.primary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
                }
                if loading { ProgressView("正在读取排队记录…").frame(maxWidth: .infinity).padding(24) }
                if !loading && loadedDate == selectedDateText {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session == nil ? "尚未开放排队" : (session?.isOpen == true ? "排队进行中" : "本场已关闭"))
                                    .font(.headline)
                                if let session {
                                    Text(verbatim: "当前叫号 \(display(session.currentNumber) ?? "—") · 等待 \(session.waiting) 组 · 已发号 \(session.lastNumber)")
                                        .font(.caption).foregroundStyle(Brand.muted)
                                } else {
                                    Text("开放排队后，顾客可在公开餐饮页面取号。")
                                        .font(.caption).foregroundStyle(Brand.muted)
                                }
                            }
                            Spacer(minLength: 4)
                            Button(saving ? "处理中…" : (session?.isOpen == true ? "关闭排队" : "开放排队")) {
                                Task { await perform(session?.isOpen == true ? .close : .open) }
                            }.buttonStyle(.borderedProminent).tint(session?.isOpen == true ? .red : Brand.primary)
                                .disabled(!canWrite)
                        }
                        if let session {
                            Button(saving ? "呼叫中…" : "呼叫下一位") { Task { await perform(.call) } }
                                .buttonStyle(.bordered).disabled(!canWrite || !session.isOpen || session.waiting < 1 || session.currentNumber != nil)
                        }
                    }.merchantCard()
                    if session != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("排队记录").font(.headline)
                            if entries.isEmpty { Text("所选日期暂无排队记录。").font(.caption).foregroundStyle(Brand.muted) }
                            ForEach(entries.indices, id: \.self) { index in
                                let entry = entries[index]
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text("\(display(nativeQueueInteger(entry, "QueueNumber")) ?? "—") 号").fontWeight(.semibold)
                                        Spacer()
                                        Text(statusName(nativeQueueString(entry, "Status") ?? ""))
                                            .font(.caption).foregroundStyle(Brand.primary)
                                    }
                                    Text("\(entry["GuestName"] as? String ?? "顾客") · \(display(entry["GuestCount"]) ?? "1") 位")
                                    Text(entry["GuestPhone"] as? String ?? "未留电话").font(.caption).foregroundStyle(Brand.muted)
                                    if let note = entry["HandleNote"] as? String, !note.isEmpty {
                                        Text("备注：\(note)").font(.caption).foregroundStyle(Brand.muted)
                                    }
                                    if nativeQueueString(entry, "Status") == "Called" {
                                        HStack {
                                            Button("完成接待") { pendingEntry = entry; pendingAction = .complete }
                                                .buttonStyle(.bordered).disabled(!canWrite)
                                            Button("标记过号", role: .destructive) { pendingEntry = entry; pendingAction = .missed }
                                                .buttonStyle(.bordered).disabled(!canWrite)
                                        }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                                if index < entries.count - 1 { Divider() }
                            }
                            if entries.count < total && failedPage == nil {
                                Button(loadingMore ? "正在加载…" : "加载更多（\(entries.count)/\(total)）") {
                                    Task { await load(page: page + 1) }
                                }.frame(maxWidth: .infinity).buttonStyle(.bordered)
                                    .disabled(loadingMore || saving || loadedDate != selectedDateText)
                            }
                        }.merchantCard()
                    }
                }
                Text("每次操作都由服务端重新核验餐饮岗位、门店范围和 F-FNB-003 开通状态。")
                    .font(.caption).foregroundStyle(Brand.muted)
            }.padding(16)
        }
        .background(Brand.background)
        .navigationTitle("排队叫号")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(revision)-\(scenePhase)-\(visible)") {
            if canRead { await load(page: 1) }
        }
        .onAppear {
            guard let principal else { dismiss(); return }
            if entryPrincipal == nil { entryPrincipal = principal }
            visible = true
        }
        .onDisappear { visible = false; invalidate() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { invalidate() } }
        .onChange(of: principal) { _, value in
            if value != entryPrincipal { invalidate(); dismiss() }
        }
        .confirmationDialog(pendingAction == .complete ? "确认完成接待？" : "确认标记过号？",
            isPresented: Binding(get: { pendingEntry != nil }, set: { if !$0 { pendingEntry = nil } }),
            titleVisibility: .visible) {
            Button("确认", role: pendingAction == .missed ? .destructive : nil) {
                if let pendingEntry {
                    let action = pendingAction
                    Task { await perform(action, entry: pendingEntry) }
                }
            }
            Button("取消", role: .cancel) { pendingEntry = nil }
        } message: { Text("\(display(pendingEntry?["QueueNumber"]) ?? "—") 号 · \(pendingEntry?["GuestName"] as? String ?? "顾客")") }
    }

    private var principal: String? { nativeTourismPrincipal(store.session?.accessToken) }

    private var canRead: Bool {
        visible && scenePhase == .active && entryPrincipal != nil && principal == entryPrincipal
    }

    private var canWrite: Bool {
        canRead && !loading && !loadingMore && !saving && !storageFailed && attempt == nil
            && error == nil && loadedDate == selectedDateText
    }

    private func originalEntryRead(_ attempt: NativeDiningQueueAttempt) -> Bool {
        guard let entryID = attempt.entryID else { return true }
        return entries.contains { nativeQueueString($0, "Id") == entryID && nativeQueueInteger($0, "QueueNumber") == attempt.number }
    }

    private func originalScopeRead(_ attempt: NativeDiningQueueAttempt) -> Bool {
        canRead && !loading && !loadingMore && !saving && error == nil && reviewed == attempt
            && loadedDate == attempt.date && selectedDateText == attempt.date
            && (attempt.sessionID == nil || attempt.sessionID == session?.id)
    }

    @ViewBuilder private var recoveryCard: some View {
        if storageFailed {
            Text("无法读取本机排队核对记录，当前门店的排队操作已暂停。").foregroundStyle(.red).merchantCard()
        } else if let attempt, !saving {
            VStack(alignment: .leading, spacing: 8) {
                Text("待核对的排队操作").font(.headline)
                Text("\(attempt.date) · \(attempt.action.name)" + (attempt.number.map { " · \($0) 号" } ?? ""))
                    .font(.caption).foregroundStyle(Brand.muted)
                Button("查看原场次") { Task { await review(attempt) } }
                    .buttonStyle(.bordered).disabled(loading || loadingMore)
                Button("已核对，解除保护") { confirm(attempt) }
                    .buttonStyle(.bordered).disabled(!originalScopeRead(attempt) || !originalEntryRead(attempt))
                if originalScopeRead(attempt) && !originalEntryRead(attempt) {
                    Text(entries.count < total ? "请加载更多，查看原排队号码。" : "当前列表中没有原排队号码，请重新读取原场次。")
                        .font(.caption).foregroundStyle(Brand.muted)
                }
            }.merchantCard()
        }
    }

    private func resetQueue() {
        session = nil; entries = []; total = 0; page = 1; loadedDate = ""; failedPage = nil
    }

    private func invalidate() {
        requestGeneration += 1; actionGeneration += 1
        reviewed = nil; pendingEntry = nil; loading = false; loadingMore = false
        resetQueue()
    }

    private func changeDate(_ date: Date) {
        guard !saving, NativeDiningQueueAttempt.dateText(date) != selectedDateText else { return }
        queueDate = date; invalidate(); error = nil; notice = nil
    }

    private func readAttempt(for principal: String) {
        do {
            attempt = try NativeDiningQueueRecovery(principal: principal, storeID: storeID).read()
            storageFailed = false
        } catch {
            attempt = nil; storageFailed = true
        }
    }

    @MainActor private func review(_ attempt: NativeDiningQueueAttempt) async {
        guard canRead, !saving, !loading, !loadingMore,
              let day = NativeDiningQueueAttempt.dateValue(attempt.date) else { return }
        if Self.inFlightWrites.contains(attempt.nonce) {
            notice = "原排队请求仍在处理中，请稍后重新读取原场次。"
            return
        }
        changeDate(day)
        await load(page: 1, review: attempt)
    }

    private func confirm(_ attempt: NativeDiningQueueAttempt) {
        guard originalScopeRead(attempt), originalEntryRead(attempt), let principal else { return }
        do {
            try NativeDiningQueueRecovery(principal: principal, storeID: storeID).remove(attempt)
            self.attempt = nil; reviewed = nil; notice = "已解除排队操作保护。"
        } catch {
            readAttempt(for: principal)
            reviewed = nil; self.error = "无法清除原排队核对记录，请重新读取原场次。"
        }
    }

    @MainActor private func load(page requestedPage: Int, review: NativeDiningQueueAttempt? = nil) async {
        guard canRead, let principal, NativeDiningReservationAttempt.validID(storeID) else { return }
        requestGeneration += 1
        let requestID = requestGeneration
        let requestedDate = selectedDateText
        func isCurrent() -> Bool {
            !Task.isCancelled && canRead && requestGeneration == requestID && selectedDateText == requestedDate
        }
        error = nil; failedPage = nil
        if requestedPage == 1 {
            resetQueue(); reviewed = nil; readAttempt(for: principal)
            loading = true; loadingMore = false
        } else { loadingMore = true }
        defer {
            if requestGeneration == requestID { loading = false; loadingMore = false }
        }
        do {
            let api = MobileAPI(store: store)
            let gate = await api.featureAccessState("F-FNB-003", forceRefresh: true)
            guard isCurrent() else { return }
            guard gate == .open else {
                resetQueue(); reviewed = nil
                error = gate == .unavailable ? "暂时无法确认餐饮排队开放状态。" : "餐饮排队功能待平台开放。"
                return
            }
            let result = try await api.get("/api/JHCTIDining/GetQueueSession?storeId=\(storeID)&queueDate=\(requestedDate)",
                authenticated: true, expectedPrincipal: principal, requireExplicitResponse: true)
            guard isCurrent() else { return }
            let next: NativeDiningQueueSummary?
            if result is NSNull { next = nil }
            else if let row = result as? [String: Any], let summary = NativeDiningQueueSummary(row, storeID: storeID, date: requestedDate) {
                next = summary
            } else { throw MobileAPIError.unavailable("排队场次与当前门店或日期不匹配。") }
            if let review, review != attempt || review.date != requestedDate || review.sessionID != nil && review.sessionID != next?.id {
                throw MobileAPIError.unavailable("读到的场次与原排队操作不一致，请重新查询。")
            }
            if requestedPage > 1 && next?.id != session?.id {
                throw MobileAPIError.unavailable("排队场次已变化，请重新查询。")
            }
            if let next {
                let result = try await api.get("/api/JHCTIDining/GetQueueEntries?sessionId=\(next.id)&page=\(requestedPage)&pageSize=\(pageSize)",
                    authenticated: true, expectedPrincipal: principal, requireExplicitResponse: true)
                guard isCurrent() else { return }
                guard let payload = result as? [String: Any],
                      let parsed = nativeDiningQueuePage(payload, page: requestedPage, pageSize: pageSize,
                        sessionID: next.id, storeID: storeID, queueDate: requestedDate) else {
                    throw MobileAPIError.unavailable("排队记录分页回执异常，请刷新后重试。")
                }
                let all = (requestedPage == 1 ? [] : entries) + parsed.rows
                let ids = all.compactMap { nativeQueueString($0, "Id") }
                let numbers = all.compactMap { nativeQueueInteger($0, "QueueNumber") }
                guard ids.count == all.count, Set(ids).count == all.count, numbers.count == all.count,
                      Set(numbers).count == all.count, parsed.total >= all.count,
                      requestedPage == 1 || parsed.total == total else {
                    throw MobileAPIError.unavailable("排队记录跨页数据不一致，请刷新后重试。")
                }
                entries = all; total = parsed.total
            }
            session = next; loadedDate = requestedDate; page = requestedPage; reviewed = review ?? reviewed
        } catch {
            if isCurrent() {
                if requestedPage == 1 { resetQueue() }
                self.error = error.localizedDescription
                failedPage = requestedPage
            }
        }
    }

    @MainActor private func perform(_ action: NativeDiningQueueAction, entry: [String: Any]? = nil) async {
        pendingEntry = nil
        guard canWrite, let principal else { return }
        if let entry {
            guard nativeQueueString(entry, "SessionId") == session?.id,
                  nativeQueueString(entry, "StoreId") == storeID,
                  nativeQueueDayMatches(nativeQueueString(entry, "QueueDate"), loadedDate),
                  nativeQueueString(entry, "Status") == "Called" else { return }
        }
        let operation = NativeDiningQueueAttempt(action: action, storeID: storeID, date: loadedDate,
            sessionID: session?.id, entryID: entry.flatMap { nativeQueueString($0, "Id") },
            number: entry.flatMap { nativeQueueInteger($0, "QueueNumber") })
        guard operation.isValid else { return }
        do { try NativeDiningQueueRecovery(principal: principal, storeID: storeID).add(operation) }
        catch {
            readAttempt(for: principal)
            self.error = "无法保存排队核对记录，本次操作未发送。"
            return
        }
        attempt = operation; reviewed = nil; saving = true; notice = nil
        Self.inFlightWrites.insert(operation.nonce)
        actionGeneration += 1
        let generation = actionGeneration
        defer { Self.inFlightWrites.remove(operation.nonce); saving = false }
        func isCurrent() -> Bool { !Task.isCancelled && canRead && actionGeneration == generation }
        let path: String
        switch action {
        case .open: path = "OpenQueueSession?storeId=\(storeID)&queueDate=\(operation.date)"
        case .close: path = "CloseQueueSession?id=\(operation.sessionID ?? "")"
        case .call: path = "CallNextQueueEntry?sessionId=\(operation.sessionID ?? "")"
        case .complete: path = "CompleteQueueEntry?id=\(operation.entryID ?? "")"
        case .missed: path = "MarkQueueEntryMissed?id=\(operation.entryID ?? "")&note=原生工作台标记过号"
        }
        do {
            let result = try await MobileAPI(store: store).post("/api/JHCTIDining/\(path)", body: [:], authenticated: true,
                expectedPrincipal: principal, canRefresh: false, requireExplicitResponse: true)
            guard isCurrent() else { return }
            guard operation.matchesReceipt(result) else { throw MobileAPIError.unavailable("排队操作回执与原操作不一致。") }
            try NativeDiningQueueRecovery(principal: principal, storeID: storeID).remove(operation)
            attempt = nil; notice = "\(action.name)操作已完成。"
            await load(page: 1)
        } catch {
            if isCurrent() { notice = "上次操作结果尚未确认，请先核对原排队场次。" }
        }
    }

    private func display(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return String(describing: value)
    }

    private func statusName(_ status: String) -> String {
        ["Waiting": "等待中", "Called": "已叫号", "Completed": "已完成", "Missed": "已过号", "Cancelled": "已取消"][status] ?? status
    }

    private var selectedDateText: String { NativeDiningQueueAttempt.dateText(queueDate) }
}
