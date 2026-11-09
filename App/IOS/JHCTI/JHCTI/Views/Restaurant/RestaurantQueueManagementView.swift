import SwiftUI

struct RestaurantQueueManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let storeID: String
    let storeName: String
    @State private var queueDate = Calendar.current.startOfDay(for: Date())
    @State private var session: [String: Any]?
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
    @State private var pendingAction = ""

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
                    DatePicker("排队日期", selection: $queueDate, displayedComponents: .date)
                    Button("查询所选日期") { revision += 1 }.buttonStyle(.bordered)
                    if !loadedDate.isEmpty && loadedDate != selectedDateText {
                        Text("日期已修改，请先查询后再操作当前场次。")
                            .font(.caption).foregroundStyle(Brand.muted)
                    }
                }.merchantCard()
                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).foregroundStyle(.red)
                        Button("重试第 \(failedPage ?? 1) 页") {
                            Task { await load(page: failedPage ?? 1) }
                        }.buttonStyle(.bordered).disabled(loading || loadingMore)
                    }.merchantCard()
                }
                if let notice {
                    Text(notice).font(.caption).foregroundStyle(Brand.primary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
                }
                if loading { ProgressView("正在读取排队记录…").frame(maxWidth: .infinity).padding(24) }
                if !loading && (error == nil || session != nil) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session == nil ? "尚未开放排队" : (session?["IsOpen"] as? Bool == true ? "排队进行中" : "本场已关闭"))
                                    .font(.headline)
                                if let session {
                                    Text(verbatim: "当前叫号 \(display(session["CurrentCalledNumber"]) ?? "—") · 等待 \(display(session["WaitingCount"]) ?? "0") 组 · 已发号 \(display(session["LastNumber"]) ?? "0")")
                                        .font(.caption).foregroundStyle(Brand.muted)
                                } else {
                                    Text("开放排队后，顾客可在公开餐饮页面取号。")
                                        .font(.caption).foregroundStyle(Brand.muted)
                                }
                            }
                            Spacer(minLength: 4)
                            Button(saving ? "处理中…" : (session?["IsOpen"] as? Bool == true ? "关闭排队" : "开放排队")) {
                                Task { await changeSession(open: session?["IsOpen"] as? Bool != true) }
                            }.buttonStyle(.borderedProminent).tint(session?["IsOpen"] as? Bool == true ? .red : Brand.primary)
                                .disabled(saving || loadedDate != selectedDateText)
                        }
                        if session != nil {
                            Button(saving ? "呼叫中…" : "呼叫下一位") { Task { await callNext() } }
                                .buttonStyle(.bordered).disabled(saving || loadedDate != selectedDateText || number(session?["WaitingCount"]) < 1)
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
                                        Text("\(display(entry["QueueNumber"]) ?? "—") 号").fontWeight(.semibold)
                                        Spacer()
                                        Text(statusName(entry["Status"] as? String ?? ""))
                                            .font(.caption).foregroundStyle(Brand.primary)
                                    }
                                    Text("\(entry["GuestName"] as? String ?? "顾客") · \(display(entry["GuestCount"]) ?? "1") 位")
                                    Text(entry["GuestPhone"] as? String ?? "未留电话").font(.caption).foregroundStyle(Brand.muted)
                                    if let note = entry["HandleNote"] as? String, !note.isEmpty {
                                        Text("备注：\(note)").font(.caption).foregroundStyle(Brand.muted)
                                    }
                                    if entry["Status"] as? String == "Called" {
                                        HStack {
                                            Button("完成接待") { pendingEntry = entry; pendingAction = "complete" }
                                                .buttonStyle(.bordered).disabled(saving || loadedDate != selectedDateText)
                                            Button("标记过号", role: .destructive) { pendingEntry = entry; pendingAction = "missed" }
                                                .buttonStyle(.bordered).disabled(saving || loadedDate != selectedDateText)
                                        }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                                if index < entries.count - 1 { Divider() }
                            }
                            if entries.count < total && error == nil {
                                Button(loadingMore ? "正在加载…" : "加载更多（\(entries.count)/\(total)）") {
                                    Task { await load(page: page + 1) }
                                }.frame(maxWidth: .infinity).buttonStyle(.bordered)
                                    .disabled(loadingMore || loadedDate != selectedDateText)
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
        .task(id: revision) { await load(page: 1) }
        .onChange(of: store.session?.accessToken) { _, _ in dismiss() }
        .confirmationDialog(pendingAction == "complete" ? "确认完成接待？" : "确认标记过号？",
            isPresented: Binding(get: { pendingEntry != nil }, set: { if !$0 { pendingEntry = nil } }),
            titleVisibility: .visible) {
            Button("确认", role: pendingAction == "missed" ? .destructive : nil) {
                if let pendingEntry { Task { await handle(pendingEntry, action: pendingAction) } }
            }
            Button("取消", role: .cancel) { pendingEntry = nil }
        } message: { Text("\(display(pendingEntry?["QueueNumber"]) ?? "—") 号 · \(pendingEntry?["GuestName"] as? String ?? "顾客")") }
    }

    private func load(page requestedPage: Int) async {
        guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token), storeID.allSatisfy(\.isNumber) else { dismiss(); return }
        requestGeneration += 1
        let requestID = requestGeneration
        let requestedDate = selectedDateText
        if requestedPage == 1 { loading = true; error = nil; failedPage = nil; session = nil; entries = []; total = 0; loadedDate = "" }
        else { loadingMore = true; error = nil; failedPage = nil }
        defer {
            if requestGeneration == requestID, store.session?.accessToken == token {
                loading = false; loadingMore = false
            }
        }
        do {
            let api = MobileAPI(store: store)
            let statusValue = try await api.get("/api/JHCTIDining/GetQueueSession?storeId=\(storeID)&queueDate=\(requestedDate)", authenticated: true,
                expectedPrincipal: principal)
            guard requestGeneration == requestID, store.session?.accessToken == token else { return }
            loadedDate = requestedDate
            if statusValue is NSNull {
                session = nil; entries = []; total = 0; page = 1; failedPage = nil
                loading = false; loadingMore = false
                return
            }
            guard let status = statusValue as? [String: Any] else {
                throw NSError(domain: "JHCTIDining", code: 1, userInfo: [NSLocalizedDescriptionKey: "排队场次回执格式无效"])
            }
            session = status
            guard let sessionID = status["Id"] as? String,
                  sessionID.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
                  sessionID.count < 19 || sessionID <= "9223372036854775807",
                  status["StoreId"] as? String == storeID,
                  let sessionDate = status["QueueDate"] as? String,
                  sessionDate.hasPrefix(requestedDate), bookingBusinessDateTime(sessionDate) != nil else {
                throw NSError(domain: "JHCTIDining", code: 2, userInfo: [NSLocalizedDescriptionKey: "排队场次与当前门店或日期不匹配"])
            }
            let result = try await api.get("/api/JHCTIDining/GetQueueEntries?sessionId=\(sessionID)&page=\(requestedPage)&pageSize=\(pageSize)", authenticated: true,
                expectedPrincipal: principal)
            guard requestGeneration == requestID, store.session?.accessToken == token,
                  let pageData = result as? [String: Any] else { return }
            guard let parsed = nativeDiningQueuePage(pageData, page: requestedPage, pageSize: pageSize,
                sessionID: sessionID, storeID: storeID, queueDate: requestedDate) else {
                throw NSError(domain: "JHCTIDining", code: 3, userInfo: [NSLocalizedDescriptionKey: "排队记录分页回执或记录字段无效，请刷新后重试"])
            }
            let existingRows = requestedPage == 1 ? [] : entries
            if requestedPage > 1, parsed.total != total {
                throw NSError(domain: "JHCTIDining", code: 4, userInfo: [NSLocalizedDescriptionKey: "排队记录总数在分页期间发生变化，请刷新后重试"])
            }
            let updatedRows = existingRows + parsed.rows
            let ids = updatedRows.compactMap { $0["Id"] as? String }
            let queueNumbers = updatedRows.compactMap { $0["QueueNumber"] as? Int }
            guard ids.count == updatedRows.count, Set(ids).count == updatedRows.count,
                  queueNumbers.count == updatedRows.count, Set(queueNumbers).count == updatedRows.count,
                  parsed.total >= updatedRows.count else {
                throw NSError(domain: "JHCTIDining", code: 5, userInfo: [NSLocalizedDescriptionKey: "排队记录跨页数据不一致，请刷新后重试"])
            }
            entries = updatedRows
            total = parsed.total
            page = requestedPage; failedPage = nil
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if requestGeneration == requestID, store.session?.accessToken == token {
                self.error = error.localizedDescription
                failedPage = requestedPage
                if requestedPage == 1 { session = nil; entries = []; total = 0 }
            }
        }
    }

    private func changeSession(open: Bool) async {
        guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else { dismiss(); return }
        saving = true; notice = nil
        defer { saving = false }
        do {
            let date = Calendar.current.dateComponents(in: TimeZone(identifier: "Asia/Shanghai") ?? .current, from: queueDate)
            let dateText = String(format: "%04d-%02d-%02d", date.year ?? 2000, date.month ?? 1, date.day ?? 1)
            let path = open
                ? "/api/JHCTIDining/OpenQueueSession?storeId=\(storeID)&queueDate=\(dateText)"
                : "/api/JHCTIDining/CloseQueueSession?id=\(display(session?["Id"]) ?? "")"
            _ = try await MobileAPI(store: store).post(path, body: [:], authenticated: true, expectedPrincipal: principal)
            if store.session?.accessToken == token { await load(page: 1) }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if store.session?.accessToken == token {
                await load(page: 1)
                notice = "操作結果未獲確認，已刷新场次；请核对当前状态后再操作。\(error.localizedDescription)"
            }
        }
    }

    private func callNext() async {
        guard let id = display(session?["Id"]), let token = store.session?.accessToken,
              let principal = nativeTourismPrincipal(token) else { return }
        saving = true
        defer { saving = false }
        do {
            _ = try await MobileAPI(store: store).post("/api/JHCTIDining/CallNextQueueEntry?sessionId=\(id)", body: [:], authenticated: true,
                expectedPrincipal: principal)
            if store.session?.accessToken == token { await load(page: 1) }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if store.session?.accessToken == token { await load(page: 1); notice = "叫号结果未获确认，已刷新记录。请核对当前叫号后再操作。\(error.localizedDescription)" }
        }
    }

    private func handle(_ entry: [String: Any], action: String) async {
        guard let id = display(entry["Id"]), let token = store.session?.accessToken,
              let principal = nativeTourismPrincipal(token) else { return }
        pendingEntry = nil; saving = true
        defer { saving = false }
        do {
            let path = action == "complete"
                ? "/api/JHCTIDining/CompleteQueueEntry?id=\(id)"
                : "/api/JHCTIDining/MarkQueueEntryMissed?id=\(id)&note=原生工作台标记过号"
            _ = try await MobileAPI(store: store).post(path, body: [:], authenticated: true, expectedPrincipal: principal)
            if store.session?.accessToken == token { await load(page: 1) }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if store.session?.accessToken == token { await load(page: 1); notice = "处理结果未获确认，已刷新记录。请核对状态后再操作。\(error.localizedDescription)" }
        }
    }

    private func display(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return String(describing: value)
    }

    private func number(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        return Int(display(value) ?? "") ?? 0
    }

    private func statusName(_ status: String) -> String {
        ["Waiting": "等待中", "Called": "已叫号", "Completed": "已完成", "Missed": "已过号", "Cancelled": "已取消"][status] ?? status
    }

    private var selectedDateText: String {
        let components = Calendar.current.dateComponents(in: TimeZone(identifier: "Asia/Shanghai") ?? .current, from: queueDate)
        return String(format: "%04d-%02d-%02d", components.year ?? 2000, components.month ?? 1, components.day ?? 1)
    }
}
