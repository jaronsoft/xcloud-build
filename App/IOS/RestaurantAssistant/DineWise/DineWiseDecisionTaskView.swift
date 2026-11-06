import SwiftUI

struct DineWiseDecisionTaskView: View {
    let store: DineWiseStore
    let token: String
    let role: String
    let userID: String
    let submissions: [DineWiseSubmission]
    let members: [DineWiseMember]

    @State private var recommendations: [DineWiseRecommendation] = []
    @State private var tasks: [DineWiseTask] = []
    @State private var sourceID = ""
    @State private var title = ""
    @State private var rationale = ""
    @State private var steps = ""
    @State private var targetRole = "manager"
    @State private var reasons: [String: String] = [:]
    @State private var remindDates: [String: String] = [:]
    @State private var assignees: [String: String] = [:]
    @State private var taskNotes: [String: String] = [:]
    @State private var keys: [String: String] = [:]
    @State private var busy = false
    @State private var message = ""
    @State private var workspace = ""

    private let api = DineWiseAPI()
    private let roles = ["manager", "chef", "purchaser", "operator"]

    private var confirmed: [DineWiseSubmission] {
        submissions.filter { item in item.Status == "confirmed"
            && (role == "owner" || item.SubmittedByUserId == userID && item.SubmittedRole == role) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("建议与任务").font(.title2.bold())
                Spacer()
                Button("刷新") { refresh() }.disabled(busy)
            }
            Text("\(store.Mode == "demo" ? "演示数据" : "试用门店") · 建议须引用已确认资料；岗位任务仅对具体执行人可见。")
                .font(.footnote).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            if !confirmed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("从已确认资料提出建议").font(.headline)
                    Picker("证据资料", selection: $sourceID) {
                        Text("请选择").tag("")
                        ForEach(confirmed) { item in
                            Text("\(item.BusinessDate) · \(kindName(item.Kind)) · \(item.Id)")
                                .tag(item.Id)
                        }
                    }
                    TextField("标题", text: $title).textFieldStyle(.roundedBorder)
                    TextField("依据与问题", text: $rationale, axis: .vertical)
                        .lineLimit(3...6).textFieldStyle(.roundedBorder)
                    TextField("人工执行步骤", text: $steps, axis: .vertical)
                        .lineLimit(3...6).textFieldStyle(.roundedBorder)
                    Picker("目标岗位", selection: $targetRole) {
                        ForEach(roles, id: \.self) { Text(roleName($0)).tag($0) }
                    }
                    Button("提交建议") { propose() }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || sourceID.isEmpty || title.trimmingCharacters(in: .whitespaces).isEmpty
                            || rationale.trimmingCharacters(in: .whitespaces).isEmpty
                            || steps.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Text("当前列表尚无可引用的已确认资料。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("建议").font(.headline)
            if recommendations.isEmpty { Text("暂无当前岗位可见的建议。") }
            ForEach(recommendations) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.Title).font(.headline)
                    Text("\(recommendationStatus(item.Status)) · 证据资料 \(item.SourceSubmissionId)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.Rationale)
                    Text("步骤：\(item.Steps)")
                    Text("目标：\(roleName(item.TargetRole))")
                    if let reason = item.DecisionReason, !reason.isEmpty {
                        Text("决策原因：\(reason)")
                    }
                    if let remind = item.RemindOn { Text("稍后日期：\(remind)") }
                    if role == "owner" && ["pending_decision", "postponed"].contains(item.Status) {
                        TextField("决定说明", text: binding(reasons, key: item.Id) { reasons = $0 })
                            .textFieldStyle(.roundedBorder)
                        Picker("执行人", selection: binding(assignees, key: item.Id) { assignees = $0 }) {
                            Text("稍后分派").tag("")
                            ForEach(members.filter { $0.Enabled && $0.Role == item.TargetRole }) { member in
                                Text(member.Email ?? member.UserId).tag(member.UserId)
                            }
                        }
                        TextField("稍后提醒日期 YYYY-MM-DD", text: binding(remindDates, key: item.Id) { remindDates = $0 })
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("确认并建任务") { decide(item, action: "confirm") }
                                .disabled(busy)
                            Button("否决") { decide(item, action: "reject") }
                                .disabled(busy || (reasons[item.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                            Button("稍后") { decide(item, action: "postpone") }
                                .disabled(busy || (reasons[item.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                                    || (remindDates[item.Id] ?? "").isEmpty)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .dineWiseCard()
            }
            Text("岗位任务").font(.headline)
            if tasks.isEmpty { Text("暂无当前岗位可见的任务。") }
            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.Title).font(.headline)
                    Text("\(taskStatus(task.Status)) · \(roleName(task.TargetRole))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("步骤：\(task.Steps)")
                    if let receipt = task.Receipt { Text("执行回执：\(receipt)") }
                    if let note = task.ReviewNote { Text("老板复核：\(note)") }
                    if ["pending_assignment", "pending_execution", "in_progress", "pending_review"].contains(task.Status) {
                        if role == "owner" && task.Status == "pending_assignment" {
                            Picker("执行人", selection: binding(assignees, key: task.Id) { assignees = $0 }) {
                                Text("请选择").tag("")
                                ForEach(members.filter { $0.Enabled && $0.Role == task.TargetRole }) { member in
                                    Text(member.Email ?? member.UserId).tag(member.UserId)
                                }
                            }
                        }
                        TextField("实际回执或复核说明", text: binding(taskNotes, key: task.Id) { taskNotes = $0 }, axis: .vertical)
                            .lineLimit(2...5).textFieldStyle(.roundedBorder)
                        if role == "owner" {
                            HStack {
                                if task.Status == "pending_assignment" {
                                    Button("指派") { act(task, action: "assign") }
                                        .disabled(busy || (assignees[task.Id] ?? "").isEmpty)
                                }
                                if task.Status == "pending_review" {
                                    Button("复核完成") { act(task, action: "complete") }.disabled(busy)
                                    Button("退回重做") { act(task, action: "rework") }
                                        .disabled(busy || (taskNotes[task.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                                Button("取消任务", role: .destructive) { act(task, action: "cancel") }
                                    .disabled(busy || (taskNotes[task.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            HStack {
                                if task.Status == "pending_execution" {
                                    Button("开始执行") { act(task, action: "start") }.disabled(busy)
                                }
                                if ["pending_execution", "in_progress"].contains(task.Status) {
                                    Button("提交回执") { act(task, action: "receipt") }
                                        .disabled(busy || (taskNotes[task.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .dineWiseCard()
            }
        }
        .padding()
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .task(id: "\(store.Id):\(role)") {
            workspace = "\(store.Id):\(role)"
            recommendations = []
            tasks = []
            keys = [:]
            busy = false
            refresh()
        }
    }

    private func binding(_ values: [String: String], key: String,
                         update: @escaping ([String: String]) -> Void) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { value in
            var next = values; next[key] = value; update(next)
        })
    }

    private func requestKey(_ signature: String) -> String {
        if let key = keys[signature] { return key }
        let key = UUID().uuidString
        keys[signature] = key
        return key
    }

    private func refresh() {
        let requestedWorkspace = "\(store.Id):\(role)"
        Task {
            do {
                async let nextRecommendations = api.recommendations(storeID: store.Id, token: token, role: role)
                async let nextTasks = api.tasks(storeID: store.Id, token: token, role: role)
                let (loadedRecommendations, loadedTasks) = try await (nextRecommendations, nextTasks)
                if workspace == requestedWorkspace {
                    recommendations = loadedRecommendations
                    tasks = loadedTasks
                }
            } catch {
                if workspace == requestedWorkspace { message = error.localizedDescription }
            }
        }
    }

    private func propose() {
        let requestedWorkspace = "\(store.Id):\(role)"
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRationale = rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSteps = steps.trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = "propose:\(sourceID):\(trimmedTitle):\(trimmedRationale):\(trimmedSteps):\(targetRole)"
        let key = requestKey(signature)
        busy = true; message = ""
        Task {
            defer { if workspace == requestedWorkspace { busy = false } }
            do {
                _ = try await api.proposeRecommendation(storeID: store.Id, token: token,
                    role: role, sourceSubmissionID: sourceID, title: trimmedTitle,
                    rationale: trimmedRationale, steps: trimmedSteps, targetRole: targetRole,
                    idempotencyKey: key)
                if workspace == requestedWorkspace {
                    keys[signature] = nil
                    sourceID = ""; title = ""; rationale = ""; steps = ""
                    refresh(); message = "建议已提交，等待老板决定。"
                }
            } catch {
                if workspace == requestedWorkspace { message = error.localizedDescription }
            }
        }
    }

    private func decide(_ item: DineWiseRecommendation, action: String) {
        let requestedWorkspace = "\(store.Id):\(role)"
        let reason = (reasons[item.Id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let remindOn = action == "postpone" ? remindDates[item.Id] : nil
        let assignee = action == "confirm" ? assignees[item.Id] : nil
        let signature = "decision:\(item.Id):\(item.Version):\(action):\(reason):\(remindOn ?? ""):\(assignee ?? "")"
        let key = requestKey(signature)
        busy = true; message = ""
        Task {
            defer { if workspace == requestedWorkspace { busy = false } }
            do {
                _ = try await api.decideRecommendation(storeID: store.Id,
                    recommendationID: item.Id, token: token, role: role, version: item.Version,
                    action: action, reason: reason, remindOn: remindOn,
                    assignedUserID: assignee?.isEmpty == false ? assignee : nil,
                    idempotencyKey: key)
                if workspace == requestedWorkspace {
                    keys[signature] = nil
                    refresh(); message = "老板决定已保存。"
                }
            } catch {
                if workspace == requestedWorkspace { message = error.localizedDescription }
            }
        }
    }

    private func act(_ task: DineWiseTask, action: String) {
        let requestedWorkspace = "\(store.Id):\(role)"
        let note = (taskNotes[task.Id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let assignee = action == "assign" ? assignees[task.Id] : nil
        let signature = "task:\(task.Id):\(task.Version):\(action):\(note):\(assignee ?? "")"
        let key = requestKey(signature)
        busy = true; message = ""
        Task {
            defer { if workspace == requestedWorkspace { busy = false } }
            do {
                _ = try await api.taskAction(storeID: store.Id, taskID: task.Id,
                    token: token, role: role, version: task.Version, action: action,
                    note: note, assignedUserID: assignee, idempotencyKey: key)
                if workspace == requestedWorkspace {
                    keys[signature] = nil
                    refresh(); message = "任务状态已更新。"
                }
            } catch {
                if workspace == requestedWorkspace { message = error.localizedDescription }
            }
        }
    }

    private func roleName(_ code: String) -> String {
        ["manager": "店长", "chef": "厨师长", "purchaser": "采购", "operator": "门店运营"][code] ?? code
    }

    private func kindName(_ code: String) -> String {
        ["operating": "经营资料", "purchase": "采购资料", "kitchen": "后厨反馈", "operations": "运营反馈"][code] ?? code
    }

    private func recommendationStatus(_ code: String) -> String {
        ["pending_decision": "待老板决策", "confirmed": "已确认", "rejected": "已否决",
         "postponed": "稍后处理"][code] ?? "状态未知"
    }

    private func taskStatus(_ code: String) -> String {
        ["pending_assignment": "待分派", "pending_execution": "待执行",
         "in_progress": "执行中", "pending_review": "待老板复核",
         "completed": "已完成", "cancelled": "已取消"][code] ?? "状态未知"
    }
}

private extension View {
    func dineWiseCard() -> some View {
        padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
