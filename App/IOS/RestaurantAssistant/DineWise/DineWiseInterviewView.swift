import SwiftUI

struct DineWiseInterviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    let store: DineWiseStore
    let token: String
    let section: String
    let onStartInterview: () -> Void
    let onSaved: () -> Void

    @State private var items: [DineWiseInterview] = []
    @State private var hasOlder = false
    @State private var recordsLoaded = false
    @State private var recordsLoading = false
    @State private var businessType = ""
    @State private var storeCount = 1
    @State private var currentTools = ""
    @State private var intervieweeRole = "owner"
    @State private var steps: Set<String> = []
    @State private var demoStartedAt: TimeInterval?
    @State private var demoHasStarted = false
    @State private var demoElapsedBeforePause: TimeInterval = 0
    @State private var demoDurationSeconds: Int?
    @State private var observedOperationType = ""
    @State private var observedOperationStartedAt: TimeInterval?
    @State private var observedOperationElapsedBeforePause: TimeInterval = 0
    @State private var observedOperationDurationSeconds: Int?
    @State private var intervieweeConsentConfirmed = false
    @State private var usefulQuote = ""
    @State private var concernQuote = ""
    @State private var willingData = ""
    @State private var dailyBurden = ""
    @State private var interest = "uncertain"
    @State private var submitWillingness = "uncertain"
    @State private var payWillingness = "uncertain"
    @State private var trialWillingness = "uncertain"
    @State private var pendingKey: String?
    @State private var pendingFingerprint = ""
    @State private var busy = false
    @State private var message = ""
    @State private var messageIsError = false
    @State private var requestGeneration = 0

    private let api = DineWiseAPI()
    private let demoSteps = [
        ("store", "说明演示门店与资料来源"),
        ("upload", "展示资料上传与字段核对"),
        ("report", "展示报告与问题依据"),
        ("notice", "展示提醒的来源和时间"),
        ("source", "记录受访者质疑与反馈")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if section == "demo" {
            VStack(alignment: .leading, spacing: 6) {
                Text("营销演示").font(.title2.bold())
                Text("仅在演示门店记录访谈；不能查看试用门店的经营资料。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("演示路径").font(.headline)
                if let demoStartedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("本次演示用时：\(durationText(demoElapsedBeforePause + ProcessInfo.processInfo.systemUptime - demoStartedAt))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                    }
                } else if let demoDurationSeconds {
                    Text("本次演示用时：\(durationText(TimeInterval(demoDurationSeconds)))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                } else if demoElapsedBeforePause > 0 {
                    Text("本次演示用时：\(durationText(demoElapsedBeforePause))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                } else {
                    Text("开始计时后再勾选实际讲解的步骤。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("应用离开前台时会自动暂停计时，返回后可手动继续。")
                    .font(.caption).foregroundStyle(.secondary)
                Button(demoStartedAt == nil ? "开始／继续计时" : "暂停计时") {
                    if let started = demoStartedAt {
                        demoElapsedBeforePause += ProcessInfo.processInfo.systemUptime - started
                        demoStartedAt = nil
                    } else {
                        demoHasStarted = true
                        demoStartedAt = ProcessInfo.processInfo.systemUptime
                    }
                }
                .buttonStyle(.bordered)
                ForEach(demoSteps, id: \.0) { step in
                    Toggle(step.1, isOn: Binding(
                        get: { steps.contains(step.0) },
                        set: { enabled in
                            guard demoHasStarted else { return }
                            if enabled { steps.insert(step.0) } else { steps.remove(step.0) }
                        }))
                        .font(.subheadline)
                        .disabled(!demoHasStarted)
                }
                Text("暂停后仍可校对步骤，也可直接完成讲解并记录累计用时；只勾选实际完成的步骤。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .interviewCard()
            Button("完成讲解，记录访谈") {
                guard demoHasStarted else { return }
                let elapsed = demoElapsedBeforePause + (demoStartedAt.map {
                    ProcessInfo.processInfo.systemUptime - $0
                } ?? 0)
                demoDurationSeconds = min(3600, max(1, Int(elapsed.rounded())))
                demoElapsedBeforePause = TimeInterval(demoDurationSeconds ?? 0)
                demoStartedAt = nil
                onStartInterview()
            }
                .buttonStyle(.borderedProminent)
                .disabled(steps.isEmpty || !demoHasStarted)
            }

            if section == "interview" {
            VStack(alignment: .leading, spacing: 12) {
                Text("访谈记录").font(.headline)
                Text("保留受访者原话；不要填写姓名、电话或真实门店经营数据。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("我已告知受访者将记录访谈反馈；如实测操作，只记录类型和用时、不记录经营内容，并已取得其同意。",
                       isOn: Binding(get: { intervieweeConsentConfirmed }, set: { consented in
                           intervieweeConsentConfirmed = consented
                           if !consented {
                               observedOperationType = ""; observedOperationStartedAt = nil
                               observedOperationElapsedBeforePause = 0
                               observedOperationDurationSeconds = nil
                           }
                       }))
                Picker("观察的资料提交操作", selection: Binding(
                    get: { observedOperationType },
                    set: { value in
                        observedOperationType = value
                        observedOperationStartedAt = nil
                        observedOperationElapsedBeforePause = 0
                        observedOperationDurationSeconds = nil
                    })) {
                    Text("不记录实测用时").tag("")
                    if ["owner", "manager", "operator"].contains(intervieweeRole) {
                        Text("营业资料提交").tag("operating_submission")
                    }
                    if ["owner", "purchaser"].contains(intervieweeRole) {
                        Text("采购资料提交").tag("purchase_submission")
                    }
                }
                .disabled(observedOperationStartedAt != nil
                    || observedOperationElapsedBeforePause > 0
                    || observedOperationDurationSeconds != nil)
                if !observedOperationType.isEmpty {
                    Text("只记录操作类型和用时，不记录提交的经营内容。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("应用离开前台时会自动暂停计时，返回后可手动继续。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let started = observedOperationStartedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            let elapsed = observedOperationElapsedBeforePause
                                + ProcessInfo.processInfo.systemUptime - started
                            Text("实测用时：\(durationText(elapsed))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                        }
                    } else if let seconds = observedOperationDurationSeconds {
                        Text("实测用时：\(durationText(TimeInterval(seconds)))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                        if seconds == 3600 {
                            Text("已达到 1 小时上限，计时已停止。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if observedOperationElapsedBeforePause > 0 {
                        Text("已暂停：\(durationText(observedOperationElapsedBeforePause))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(observedOperationStartedAt == nil ? "开始／继续计时" : "暂停计时") {
                            if let started = observedOperationStartedAt {
                                observedOperationElapsedBeforePause +=
                                    ProcessInfo.processInfo.systemUptime - started
                                observedOperationStartedAt = nil
                            } else {
                                observedOperationStartedAt = ProcessInfo.processInfo.systemUptime
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(observedOperationDurationSeconds != nil
                            || observedOperationStartedAt == nil && !intervieweeConsentConfirmed)
                        Button("完成计时") {
                            guard let started = observedOperationStartedAt else { return }
                            let elapsed = observedOperationElapsedBeforePause
                                + ProcessInfo.processInfo.systemUptime - started
                            observedOperationDurationSeconds = min(3600, max(1, Int(elapsed.rounded())))
                            observedOperationElapsedBeforePause = TimeInterval(
                                observedOperationDurationSeconds ?? 0)
                            observedOperationStartedAt = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(observedOperationStartedAt == nil)
                    }
                    if observedOperationDurationSeconds != nil
                        || observedOperationElapsedBeforePause > 0 && observedOperationStartedAt == nil {
                        Button("重置实测用时") {
                            observedOperationDurationSeconds = nil
                            observedOperationElapsedBeforePause = 0
                        }
                        .font(.caption)
                    }
                }
                TextField("受访门店业态，例如火锅", text: $businessType)
                    .textFieldStyle(.roundedBorder)
                Stepper("经营门店数：\(storeCount) 家", value: $storeCount, in: 1...9999)
                TextField("现有收银与报表方式", text: $currentTools)
                    .textFieldStyle(.roundedBorder)
                Picker("受访者角色", selection: $intervieweeRole) {
                    ForEach(["owner", "manager", "chef", "purchaser", "operator", "other"], id: \.self) {
                        Text(roleName($0)).tag($0)
                    }
                }
                TextField("觉得有用的原话", text: $usefulQuote, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder)
                TextField("质疑或顾虑的原话", text: $concernQuote, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder)
                TextField("愿意提供的数据及条件", text: $willingData, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                TextField("估计每日操作分钟数（可不填）", text: $dailyBurden)
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                intention("觉得有意思", selection: $interest)
                intention("愿意持续提交资料", selection: $submitWillingness)
                intention("愿意为结果付费", selection: $payWillingness)
                intention("愿意继续试用", selection: $trialWillingness)
                if !message.isEmpty {
                    Text(message).font(.footnote.weight(.medium))
                        .foregroundStyle(messageIsError
                            ? DineWiseTheme.danger(for: colorScheme)
                            : DineWiseTheme.accent(for: colorScheme))
                }
                Button("保存访谈") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || observedOperationStartedAt != nil
                        || observedOperationElapsedBeforePause > 0 && observedOperationDurationSeconds == nil
                        || !intervieweeConsentConfirmed || steps.isEmpty
                        || businessType.trimmingCharacters(in: .whitespaces).isEmpty
                        || currentTools.trimmingCharacters(in: .whitespaces).isEmpty
                        || intervieweeRole.trimmingCharacters(in: .whitespaces).isEmpty
                        || usefulQuote.trimmingCharacters(in: .whitespaces).isEmpty
                            && concernQuote.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .interviewCard()

            }
            if section == "records" {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("我记录的访谈").font(.headline)
                    Spacer()
                    Button("刷新") { refresh() }.disabled(busy)
                }
                if recordsLoading {
                    Text("正在读取访谈记录…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !message.isEmpty {
                    Text(message).font(.footnote.weight(.medium))
                        .foregroundStyle(messageIsError
                            ? DineWiseTheme.danger(for: colorScheme)
                            : DineWiseTheme.accent(for: colorScheme))
                }
                if recordsLoaded && items.isEmpty && message.isEmpty { Text("尚无访谈记录。")
                    .font(.subheadline).foregroundStyle(.secondary) }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(item.BusinessType) · \(item.StoreCount) 家 · \(roleName(item.IntervieweeRole))")
                            .font(.subheadline.bold())
                        Text("脚本 \(item.DemoScriptVersion == "legacy" ? "历史版本" : item.DemoScriptVersion) · 讲解 \(item.DemoSteps.count) 步 · 收银报表：\(item.CurrentTools)")
                            .font(.caption).foregroundStyle(.secondary)
                        if let seconds = item.DemoDurationSeconds {
                            Text("本次演示用时 \(durationText(TimeInterval(seconds)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let type = item.ObservedOperationType,
                           let seconds = item.ObservedOperationDurationSeconds {
                            Text("实测\(operationTypeName(type))用时 \(durationText(TimeInterval(seconds)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(item.IntervieweeConsentConfirmed == true ? "记录许可：已留存" : "历史记录：未留存记录许可")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("兴趣 \(answerName(item.Interest)) · 持续提交 \(answerName(item.SubmitWillingness)) · 付费 \(answerName(item.PayWillingness)) · 试用 \(answerName(item.TrialWillingness))")
                            .font(.caption).foregroundStyle(.secondary)
                        if !item.UsefulQuote.isEmpty { Text("有用：\(item.UsefulQuote)") }
                        if !item.ConcernQuote.isEmpty { Text("质疑：\(item.ConcernQuote)") }
                        if !item.WillingData.isEmpty { Text("愿提供：\(item.WillingData)") }
                        if let minutes = item.DailyBurdenMinutes {
                            Text("估计每日操作 \(minutes) 分钟")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
                if hasOlder {
                    Button(busy ? "正在读取…" : "加载更早的访谈") { loadOlder() }
                        .buttonStyle(.bordered).disabled(busy)
                }
            }
            .interviewCard()
            }
        }
        .task(id: "\(store.Id):\(token):\(section)") {
            requestGeneration += 1
            let generation = requestGeneration
            let requestStoreID = store.Id
            let requestToken = token
            busy = false
            setMessage("")
            if section == "records" {
                items = []
                hasOlder = false
                recordsLoaded = false
                recordsLoading = true
                do {
                    let result = try await api.interviews(storeID: requestStoreID,
                        token: requestToken)
                    if isCurrentRequest(storeID: requestStoreID, token: requestToken,
                        generation: generation) {
                        items = result
                        hasOlder = result.count >= 100
                        recordsLoaded = true
                        recordsLoading = false
                    }
                } catch {
                    if isCurrentRequest(storeID: requestStoreID, token: requestToken,
                        generation: generation) {
                        setMessage(error.localizedDescription, isError: true)
                        recordsLoading = false
                    }
                }
            }
        }
        .task(id: observedOperationStartedAt) {
            guard let started = observedOperationStartedAt else { return }
            while !Task.isCancelled {
                let elapsed = observedOperationElapsedBeforePause
                    + ProcessInfo.processInfo.systemUptime - started
                if elapsed >= 3600 {
                    observedOperationElapsedBeforePause = 3600
                    observedOperationDurationSeconds = 3600
                    observedOperationStartedAt = nil
                    break
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .onChange(of: store.Id) { _, _ in resetForIdentityChange() }
        .onChange(of: token) { _, _ in resetForIdentityChange() }
        .onChange(of: intervieweeRole) { _, _ in
            observedOperationType = ""; observedOperationStartedAt = nil
            observedOperationElapsedBeforePause = 0; observedOperationDurationSeconds = nil
        }
        .onChange(of: section) { _, newSection in
            if newSection != "interview" { intervieweeConsentConfirmed = false }
            if newSection != "interview", let started = observedOperationStartedAt {
                observedOperationElapsedBeforePause += ProcessInfo.processInfo.systemUptime - started
                observedOperationStartedAt = nil
            }
            if newSection != "demo", let started = demoStartedAt {
                demoElapsedBeforePause += ProcessInfo.processInfo.systemUptime - started
                demoStartedAt = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if let started = demoStartedAt {
                demoElapsedBeforePause = min(3600, demoElapsedBeforePause + now - started)
                demoStartedAt = nil
            }
            if let started = observedOperationStartedAt {
                observedOperationElapsedBeforePause = min(
                    3600, observedOperationElapsedBeforePause + now - started)
                if observedOperationElapsedBeforePause >= 3600 {
                    observedOperationDurationSeconds = 3600
                }
                observedOperationStartedAt = nil
            }
        }
    }

    private func intention(_ title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.medium))
            Picker(title, selection: selection) {
                Text("是").tag("yes")
                Text("待定").tag("uncertain")
                Text("否").tag("no")
            }
            .pickerStyle(.segmented)
        }
    }

    private func answerName(_ code: String) -> String {
        ["yes": "是", "uncertain": "待定", "no": "否"][code] ?? "待定"
    }

    private func roleName(_ code: String) -> String {
        ["owner": "老板", "manager": "店长", "chef": "厨师长", "purchaser": "采购",
         "operator": "门店运营", "other": "其他"][code] ?? "其他"
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return seconds >= 60 ? "\(seconds / 60) 分 \(seconds % 60) 秒" : "\(seconds) 秒"
    }

    private func operationTypeName(_ code: String) -> String {
        ["operating_submission": "营业资料提交", "purchase_submission": "采购资料提交"][code]
            ?? "资料操作"
    }

    private func refresh() {
        let storeID = store.Id
        let requestToken = token
        requestGeneration += 1
        let generation = requestGeneration
        busy = true
        recordsLoading = true
        setMessage("")
        Task { @MainActor in
            do {
                let result = try await api.interviews(storeID: storeID, token: requestToken)
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    generation: generation) { items = result; hasOlder = result.count >= 100 }
            }
            catch {
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    generation: generation) { setMessage(error.localizedDescription, isError: true) }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken,
                generation: generation) {
                busy = false
                recordsLoading = false
            }
        }
    }

    private func loadOlder() {
        guard section == "records", !busy, hasOlder,
              let cursor = items.last?.Id else { return }
        let storeID = store.Id
        let requestToken = token
        let generation = requestGeneration
        busy = true
        setMessage("")
        Task { @MainActor in
            defer {
                if isCurrentRequest(storeID: storeID, token: requestToken, generation: generation) {
                    busy = false
                }
            }
            do {
                let older = try await api.interviews(storeID: storeID, token: requestToken,
                    beforeID: cursor)
                guard isCurrentRequest(storeID: storeID, token: requestToken,
                    generation: generation) else { return }
                let existing = Set(items.map(\.Id))
                items.append(contentsOf: older.filter { !existing.contains($0.Id) })
                hasOlder = older.count >= 100
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    generation: generation) { setMessage(error.localizedDescription, isError: true) }
            }
        }
    }

    private func save() {
        let minutes = dailyBurden.isEmpty ? nil : Int(dailyBurden)
        if !dailyBurden.isEmpty && (minutes == nil || minutes! > 240) {
            setMessage("每日操作分钟数须在 0 至 240 之间。", isError: true); return
        }
        let orderedSteps = steps.sorted()
        let fingerprint = [businessType, String(storeCount), currentTools, intervieweeRole,
            orderedSteps.joined(separator: ","), String(demoDurationSeconds ?? 0),
            observedOperationType, String(observedOperationDurationSeconds ?? 0),
            String(intervieweeConsentConfirmed), usefulQuote, concernQuote, willingData,
            dailyBurden, interest, submitWillingness, payWillingness, trialWillingness]
            .joined(separator: "\u{1F}")
        if pendingFingerprint != fingerprint {
            pendingFingerprint = fingerprint
            pendingKey = UUID().uuidString
        }
        let key = pendingKey ?? UUID().uuidString
        pendingKey = key
        let requestStoreID = store.Id
        let requestToken = token
        requestGeneration += 1
        let generation = requestGeneration
        let draft = DineWiseInterviewDraft(
            businessType: businessType.trimmingCharacters(in: .whitespaces),
            storeCount: storeCount, currentTools: currentTools.trimmingCharacters(in: .whitespaces),
            intervieweeRole: intervieweeRole.trimmingCharacters(in: .whitespaces),
            demoSteps: orderedSteps, demoDurationSeconds: demoDurationSeconds,
            observedOperationType: observedOperationDurationSeconds == nil ? nil : observedOperationType,
            observedOperationDurationSeconds: observedOperationDurationSeconds,
            intervieweeConsentConfirmed: intervieweeConsentConfirmed,
            usefulQuote: usefulQuote.trimmingCharacters(in: .whitespaces),
            concernQuote: concernQuote.trimmingCharacters(in: .whitespaces),
            willingData: willingData.trimmingCharacters(in: .whitespaces),
            dailyBurdenMinutes: minutes, interest: interest,
            submitWillingness: submitWillingness, payWillingness: payWillingness,
            trialWillingness: trialWillingness)
        busy = true; setMessage("")
        Task { @MainActor in
            defer {
                if isCurrentRequest(storeID: requestStoreID, token: requestToken,
                    generation: generation) { busy = false }
            }
            do {
                _ = try await api.createInterview(storeID: requestStoreID, token: requestToken,
                    draft: draft, idempotencyKey: key)
                guard isCurrentRequest(storeID: requestStoreID, token: requestToken,
                    generation: generation) else { return }
                pendingKey = nil; pendingFingerprint = ""
                steps = []; demoStartedAt = nil; demoHasStarted = false; demoElapsedBeforePause = 0
                demoDurationSeconds = nil
                observedOperationType = ""; observedOperationStartedAt = nil
                observedOperationElapsedBeforePause = 0; observedOperationDurationSeconds = nil
                intervieweeConsentConfirmed = false
                usefulQuote = ""; concernQuote = ""; willingData = ""; dailyBurden = ""
                setMessage("访谈已保存。")
                onSaved()
            } catch {
                if isCurrentRequest(storeID: requestStoreID, token: requestToken,
                    generation: generation) { setMessage(error.localizedDescription, isError: true) }
            }
        }
    }

    private func resetForIdentityChange() {
        requestGeneration += 1
        items = []; businessType = ""; storeCount = 1; currentTools = ""
        recordsLoaded = false; recordsLoading = false
        intervieweeRole = "owner"; steps = []; intervieweeConsentConfirmed = false; usefulQuote = ""
        concernQuote = ""; willingData = ""; dailyBurden = ""
        interest = "uncertain"; submitWillingness = "uncertain"
        payWillingness = "uncertain"; trialWillingness = "uncertain"
        demoStartedAt = nil; demoHasStarted = false; demoElapsedBeforePause = 0; demoDurationSeconds = nil
        observedOperationType = ""; observedOperationStartedAt = nil
        observedOperationElapsedBeforePause = 0; observedOperationDurationSeconds = nil
        pendingKey = nil; pendingFingerprint = ""; busy = false; setMessage("")
    }

    private func isCurrentRequest(storeID: String, token requestToken: String,
                                  generation: Int) -> Bool {
        store.Id == storeID && token == requestToken && requestGeneration == generation
    }

    private func setMessage(_ value: String, isError: Bool = false) {
        message = value
        messageIsError = isError
    }
}

private extension View {
    func interviewCard() -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}
