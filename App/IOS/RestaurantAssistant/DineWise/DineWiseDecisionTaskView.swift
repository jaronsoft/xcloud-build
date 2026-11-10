import SwiftUI
import UIKit

private struct DineWiseEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let detail: String
    let symbol: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                .frame(width: 38, height: 38)
                .background(DineWiseTheme.accent(for: colorScheme).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action).font(.footnote.weight(.semibold)).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DineWiseTheme.inset, in: RoundedRectangle(cornerRadius: 14))
    }
}

private enum DineWiseDecisionTaskScopeError: LocalizedError {
    case mismatch

    var errorDescription: String? {
        "操作回执与当前门店数据范围不匹配，请刷新确认。"
    }
}

struct DineWiseDecisionTaskView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    let store: DineWiseStore
    let token: String
    let role: String
    let userID: String
    let submissions: [DineWiseSubmission]
    let submissionLoadState: String
    let members: [DineWiseMember]
    let focus: DineWiseOwnerTodayItem?
    let onClearFocus: () -> Void
    var pushTaskFocusID = ""
    var onPushTaskFocusConsumed: () -> Void = {}
    var onOpenMaterials: (() -> Void)? = nil
    var onTaskNotificationRead: () -> Void = {}
    let onRetrySubmissions: () -> Void

    @State private var recommendations: [DineWiseRecommendation] = []
    @State private var hasOlderRecommendations = false
    @State private var tasks: [DineWiseTask] = []
    @State private var meetingTasks: [DineWiseTask] = []
    @State private var hasOlderMeetingTasks = false
    @State private var meetingProgress: DineWiseMeetingProgressSummary?
    @State private var meetingTaskFilter = "all"
    @State private var taskNotifications: [DineWiseTaskNotification] = []
    @State private var taskNotificationFocusID = ""
    @State private var taskEventHistories: [String: DineWiseTaskEventHistory] = [:]
    @State private var taskEventExpandedIDs: Set<String> = []
    @State private var taskEventLoadingIDs: Set<String> = []
    @State private var taskEventRequestVersions: [String: Int] = [:]
    @State private var taskEventErrors: [String: String] = [:]
    @State private var hasOlderTasks = false
    @State private var reviews: [DineWiseTaskReview] = []
    @State private var hasOlderReviews = false
    @State private var sourceID = ""
    @State private var title = ""
    @State private var rationale = ""
    @State private var isProposalFormExpanded = false
    @State private var calculationBasis = ""
    @State private var confidenceLevel = ""
    @State private var confidenceReason = ""
    @State private var steps = ""
    @State private var targetRole = "manager"
    @State private var validUntilOn = ""
    @State private var replacesID = ""
    @State private var reasons: [String: String] = [:]
    @State private var remindDates: [String: String] = [:]
    @State private var assignees: [String: String] = [:]
    @State private var taskNotes: [String: String] = [:]
    @State private var dueDates: [String: String] = [:]
    @State private var escalationRules: [String: String] = [:]
    @State private var reviewDueDates: [String: String] = [:]
    @State private var reviewOutcomes: [String: String] = [:]
    @State private var reviewMetricKeys: [String: String] = [:]
    @State private var reviewBeforeIDs: [String: String] = [:]
    @State private var reviewAfterIDs: [String: String] = [:]
    @State private var reviewConfounders: [String: String] = [:]
    @State private var reviewConclusions: [String: String] = [:]
    @State private var reviewNextSteps: [String: String] = [:]
    @State private var isMeetingFormExpanded = false
    @State private var meetingWeek = Date.now
    @State private var meetingDate = Date.now
    @State private var meetingTitle = ""
    @State private var meetingSteps = ""
    @State private var meetingTargetRole = "manager"
    @State private var meetingAssignee = ""
    @State private var meetingDueDate = Date.now
    @State private var meetingHasDueDate = false
    @State private var busy = false
    @State private var message = ""
    @State private var hasLoaded = false
    @State private var listLoadFailed = false
    @State private var loadedListScopeKey = ""
    @State private var workspace = ""
    @State private var loadVersion = 0
    @State private var taskNotificationOpenVersion = 0

    private let api = DineWiseAPI()
    private let roles = ["manager", "chef", "purchaser", "operator"]
    private var accent: Color { DineWiseTheme.accent(for: colorScheme) }
    @State private var messageIsError = false

    private var requestScopeKey: String {
        "\(store.Id):\(store.Mode):\(role):\(userID):\(token):\(focus?.type ?? ""):\(focus?.Id ?? "")"
    }
    private var sessionScopeKey: String { "\(store.Id):\(store.Mode):\(role):\(userID):\(token)" }

    private var listScopeKey: String {
        let submissionVersions = submissions.map { "\($0.Id):\($0.Version)" }.joined(separator: ",")
        return "\(requestScopeKey):\(submissionVersions)"
    }

    private var hasCurrentLists: Bool {
        hasLoaded && !listLoadFailed && loadedListScopeKey == listScopeKey
    }

    private var confirmed: [DineWiseSubmission] {
        submissions.filter { item in item.Status == "confirmed"
            && (role == "owner" || item.SubmittedByUserId == userID && item.SubmittedRole == role) }
    }

    private var sourceSelectionScopeKey: String {
        "\(submissionLoadState):\(confirmed.map(\.Id).joined(separator: ","))"
    }

    private var replaceableRecommendations: [DineWiseRecommendation] {
        guard let source = confirmed.first(where: { $0.Id == sourceID }) else { return [] }
        return recommendations.filter { item in
            item.SourceSubmissionId == sourceID && item.SourceVersion == source.Version
                && item.SourceInvalidatedAt == nil && item.Status != "rejected"
        }
    }

    private var replacementOptionsKey: String {
        "\(hasCurrentLists):\(replaceableRecommendations.map(\.Id).joined(separator: ","))"
    }

    private func sourceVersionChanged(for item: DineWiseRecommendation) -> Bool {
        guard role == "owner", item.SourceInvalidatedAt == nil,
              let source = confirmed.first(where: { $0.Id == item.SourceSubmissionId }),
              let sourceVersion = item.SourceVersion else { return false }
        return source.Version != sourceVersion
    }

    private var focusedRecommendation: Bool {
        ["pending_decision", "due_decision"].contains(focus?.type ?? "")
    }
    private var focusedTask: Bool {
        ["escalated_task", "pending_assignment", "pending_review"].contains(focus?.type ?? "")
    }
    private var focusedReview: Bool { focus?.type == "due_review" }
    private var selectedMeetingWeekStart: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: store.TimeZone ?? "") ?? .current
        let start = calendar.dateInterval(of: .weekOfYear, for: meetingWeek)?.start ?? meetingWeek
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start)
    }
    private var currentMeetingWeekStart: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: store.TimeZone ?? "") ?? .current
        let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start)
    }
    private var selectedMeetingWeekEnd: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: store.TimeZone ?? "") ?? .current
        let interval = calendar.dateInterval(of: .weekOfYear, for: meetingWeek)
        let end = interval?.end.addingTimeInterval(-1) ?? meetingWeek
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: end)
    }
    private var visibleRecommendations: [DineWiseRecommendation] {
        guard let focus else { return recommendations }
        return recommendations.filter { focusedRecommendation && $0.Id == focus.Id }
    }
    private var visibleTasks: [DineWiseTask] {
        if !taskNotificationFocusID.isEmpty,
           let selected = tasks.first(where: { $0.Id == taskNotificationFocusID }) {
            return [selected]
        }
        guard let focus else {
            if role == "owner" {
                let filteredMeetings = meetingTasks.filter { task in
                    switch meetingTaskFilter {
                    case "open": task.Status != "completed" && task.Status != "cancelled"
                    case "completed": task.Status == "completed"
                    case "cancelled": task.Status == "cancelled"
                    default: true
                    }
                }
                let regularTasks = tasks.filter { $0.SourceType != "meeting" }
                let rows = Dictionary((regularTasks + filteredMeetings).map { ($0.Id, $0) },
                    uniquingKeysWith: { current, _ in current }).values
                return rows.sorted {
                    if ($0.SourceType == "meeting") != ($1.SourceType == "meeting") {
                        return $0.SourceType != "meeting"
                    }
                    if $0.Id == taskNotificationFocusID { return true }
                    if $1.Id == taskNotificationFocusID { return false }
                    return $0.Id > $1.Id
                }
            }
            return tasks
        }
        return tasks.filter { focusedTask && $0.Id == focus.Id }
    }
    private func ownerTaskGroupTitle(at index: Int) -> String? {
        guard role == "owner", visibleTasks.indices.contains(index) else { return nil }
        let task = visibleTasks[index]
        guard index == 0 || visibleTasks[index - 1].SourceType != task.SourceType else { return nil }
        return task.SourceType == "meeting" ? "会议事项" : "建议任务"
    }
    private var visibleReviews: [DineWiseTaskReview] {
        guard let focus else { return reviews }
        return reviews.filter { focusedReview && $0.Id == focus.Id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: focus == nil ? "lightbulb.fill" : focusedRecommendation ? "lightbulb" : focusedTask ? "checklist" : "calendar.badge.clock")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 38, height: 38)
                        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(focus == nil ? "建议与任务" : focusedRecommendation ? "建议详情" : focusedTask ? "任务详情" : "到期复盘")
                            .font(.headline.weight(.bold)).foregroundStyle(.primary)
                        Text("建议依据已确认资料，安排下一步经营行动")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("刷新") { refresh() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                        .accessibilityLabel("刷新建议与任务")
                        .disabled(busy)
                }
                HStack(spacing: 6) {
                    Image(systemName: store.Mode == "demo" ? "sparkles" : "checkmark.shield")
                    Text("\(store.Mode == "demo" ? "演示数据" : "试用门店") · \(role == "owner" ? "老板可查看本店全部记录" : "只看本人提交建议与受派任务")")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(store.Mode == "demo" ? DineWiseTheme.surfaceGold(for: colorScheme) : accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background((store.Mode == "demo" ? DineWiseTheme.gold(for: colorScheme) : accent).opacity(0.12), in: Capsule())
            }
            .dineWiseCard()
            if !taskNotifications.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("任务通知").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("最近 \(taskNotifications.count) 条未读").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(taskNotifications) { item in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Button(item.TaskTitle) { openTaskFromNotification(item) }
                                    .font(.subheadline.weight(.medium)).foregroundStyle(accent)
                                    .multilineTextAlignment(.leading).buttonStyle(.plain)
                                Text("\(taskNotificationAction(item.Action)) · \(taskStatus(item.TaskStatus))")
                                    .font(.caption).foregroundStyle(.secondary)
                                if item.Action == "progress", let note = item.Note, !note.isEmpty {
                                    Text(note).font(.footnote).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 4)
                            Button("已读") { markTaskNotificationRead(item) }
                                .font(.caption.weight(.semibold)).disabled(busy)
                        }
                        .padding(.vertical, 6)
                        if item.Id != taskNotifications.last?.Id { Divider() }
                    }
                }
                .padding(14)
                .background(DineWiseTheme.inset, in: RoundedRectangle(cornerRadius: 14))
            }
            if focus != nil {
                HStack {
                    Text("正在处理今日待办").font(.subheadline.bold())
                    Spacer()
                    Button("查看全部") {
                        taskNotificationOpenVersion += 1
                        taskNotificationFocusID = ""; onClearFocus()
                    }
                }
            }
            if !taskNotificationFocusID.isEmpty {
                HStack {
                    Text("正在查看通知中的任务").font(.subheadline.bold())
                    Spacer()
                    Button("查看全部岗位任务") {
                        taskNotificationOpenVersion += 1
                        taskNotificationFocusID = ""
                        if focus != nil { onClearFocus() }
                    }
                }
            }
            if workspace == requestScopeKey && !message.isEmpty {
                Text(message).font(.footnote.weight(.medium))
                    .foregroundStyle(messageIsError ? DineWiseTheme.danger(for: colorScheme) : accent)
            }
            if !hasCurrentLists && (workspace != requestScopeKey || !listLoadFailed) {
                ProgressView("正在读取建议与任务…").font(.footnote)
            }
            if focus == nil && hasCurrentLists && submissionLoadState == "loaded" && !confirmed.isEmpty {
                DisclosureGroup(isExpanded: $isProposalFormExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("证据资料", selection: $sourceID) {
                            Text("请选择").tag("")
                            ForEach(confirmed) { item in
                                Text("\(item.BusinessDate) · \(kindName(item.Kind)) · \(item.Id)")
                                    .tag(item.Id)
                            }
                        }
                        .onChange(of: sourceID) { _, _ in replacesID = "" }
                        TextField("标题", text: $title).textFieldStyle(.roundedBorder)
                        TextField("依据与问题", text: $rationale, axis: .vertical)
                            .lineLimit(3...6).textFieldStyle(.roundedBorder)
                        TextField("计算口径", text: $calculationBasis, axis: .vertical)
                            .lineLimit(2...4).textFieldStyle(.roundedBorder)
                        Picker("人工评估可信度", selection: $confidenceLevel) {
                            Text("请选择").tag("")
                            Text("高").tag("high")
                            Text("中").tag("medium")
                            Text("低").tag("low")
                        }
                        TextField("可信度判断依据", text: $confidenceReason, axis: .vertical)
                            .lineLimit(2...4).textFieldStyle(.roundedBorder)
                        TextField("人工执行步骤", text: $steps, axis: .vertical)
                            .lineLimit(3...6).textFieldStyle(.roundedBorder)
                        Picker("目标岗位", selection: $targetRole) {
                            ForEach(roles, id: \.self) { Text(roleName($0)).tag($0) }
                        }
                        DineWisePlaceholderField("建议有效截止日期 YYYY-MM-DD（可选）",
                                                 isEmpty: validUntilOn.isEmpty) {
                            TextField("", text: $validUntilOn)
                                .textFieldStyle(.plain)
                        }
                        if role == "owner" {
                            Picker("替代同一证据的旧建议", selection: $replacesID) {
                                Text("不替代").tag("")
                                ForEach(replaceableRecommendations) { old in
                                    Text("\(old.Title) · \(old.Id)").tag(old.Id)
                                }
                            }
                        }
                        Button("提交建议") { propose() }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy || sourceID.isEmpty || title.trimmingCharacters(in: .whitespaces).isEmpty
                                || rationale.trimmingCharacters(in: .whitespaces).isEmpty
                                || calculationBasis.trimmingCharacters(in: .whitespaces).isEmpty
                                || confidenceLevel.isEmpty
                                || confidenceReason.trimmingCharacters(in: .whitespaces).isEmpty
                                || steps.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                } label: {
                    Label("从已确认资料提出建议", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                }
            } else if focus == nil && ["idle", "loading"].contains(submissionLoadState) {
                ProgressView("正在读取已确认资料…").font(.footnote)
            } else if focus == nil && submissionLoadState == "error" {
                DineWiseEmptyState(title: "资料暂时无法读取",
                    detail: "读取完成前不会判断门店是否缺少已确认资料。",
                    symbol: "arrow.clockwise", actionTitle: "重试", action: onRetrySubmissions)
            } else if focus == nil && submissionLoadState == "loaded" && hasCurrentLists && confirmed.isEmpty {
                DineWiseEmptyState(title: "先补充门店资料",
                    detail: "建议需要基于已确认的经营资料生成。完成资料确认后，这里会显示可执行的经营建议。",
                    symbol: "doc.text.magnifyingglass", actionTitle: role == "owner" ? "查看资料" : nil,
                    action: onOpenMaterials)
            }
            if focus == nil || focusedRecommendation {
                sectionHeading("建议", symbol: "lightbulb",
                    count: countLabel(visibleRecommendations.count, hasOlder: hasOlderRecommendations))
            }
            if hasCurrentLists && (focus == nil || focusedRecommendation) && visibleRecommendations.isEmpty {
                DineWiseEmptyState(title: "暂无建议",
                    detail: role == "owner" ? "有新的建议时，会在这里说明判断依据和执行步骤。" : "老板确认并指派给你的建议，会显示在这里。",
                    symbol: "lightbulb")
            }
            if hasCurrentLists {
            ForEach(visibleRecommendations) { item in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(recommendationStatus(item.Status))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(recommendationTint(item.Status))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(recommendationTint(item.Status).opacity(0.11), in: Capsule())
                        Text("建议")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    Text(item.Title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Label(roleName(item.TargetRole), systemImage: "person.crop.circle")
                        if let source = confirmed.first(where: { $0.Id == item.SourceSubmissionId }) {
                            Label("\(source.BusinessDate) · \(kindName(source.Kind))", systemImage: "doc.text")
                        } else {
                            Label("来源资料 \(item.SourceSubmissionId)", systemImage: "doc.text")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    Rectangle().fill(Color.secondary.opacity(0.16)).frame(height: 1)
                    if item.SourceInvalidatedAt != nil {
                        Label("\(invalidationName(item.InvalidationReason))，此建议已失效。", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold)).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                        if let next = item.SupersededByRecommendationId {
                            Text("新版建议：\(next)").font(.footnote)
                        }
                    } else if sourceVersionChanged(for: item) {
                        Label("依据资料已有新版本，请刷新后重新生成建议。", systemImage: "arrow.clockwise.circle")
                            .font(.footnote.weight(.semibold)).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                    }
                    if let validUntil = item.ValidUntilOn { Text("建议有效至：\(validUntil)") }
                    if let replaced = item.ReplacesRecommendationId {
                        Text("替代旧建议：\(replaced)").font(.footnote).foregroundStyle(.secondary)
                    }
                    if item.SourceInvalidatedAt == nil && !sourceVersionChanged(for: item) {
                        detailBlock("为什么", symbol: "text.quote", text: item.Rationale)
                        detailBlock("计算口径", symbol: "function",
                            text: item.CalculationBasis ?? "旧建议尚未填写计算口径。",
                            subdued: item.CalculationBasis == nil)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("可信度").font(.subheadline.bold())
                                Text(confidenceLabel(item.ConfidenceLevel))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .foregroundStyle(confidenceTint(item.ConfidenceLevel))
                                    .background(confidenceTint(item.ConfidenceLevel).opacity(0.12), in: Capsule())
                                Text("人工评估").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(item.ConfidenceReason ?? "旧建议尚未填写可信度判断依据。")
                                .font(.subheadline).foregroundStyle(item.ConfidenceReason == nil ? .secondary : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DineWiseTheme.inset, in: RoundedRectangle(cornerRadius: 14))
                        detailBlock("怎么做", symbol: "list.number", text: item.Steps)
                    }
                    if let reason = item.DecisionReason, !reason.isEmpty {
                        detailBlock("决策记录", symbol: "checkmark.seal", text: reason)
                    }
                    if let remind = item.RemindOn {
                        Label("提醒日期：\(remind)", systemImage: "calendar")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if role == "owner" && item.SourceInvalidatedAt == nil && !sourceVersionChanged(for: item)
                        && ["pending_decision", "postponed"].contains(item.Status) {
                        Rectangle().fill(Color.secondary.opacity(0.16)).frame(height: 1)
                        TextField("决定说明", text: binding(reasons, key: item.Id) { reasons = $0 })
                            .textFieldStyle(.roundedBorder)
                        Picker("执行人", selection: binding(assignees, key: item.Id) { assignees = $0 }) {
                            Text("稍后分派").tag("")
                            ForEach(members.filter { $0.Enabled && $0.Role == item.TargetRole }) { member in
                                Text(member.Email ?? member.UserId).tag(member.UserId)
                            }
                        }
                        DineWisePlaceholderField("任务截止日期 YYYY-MM-DD",
                                                 isEmpty: (dueDates[item.Id] ?? "").isEmpty) {
                            TextField("", text: binding(dueDates, key: item.Id) { dueDates = $0 })
                                .textFieldStyle(.plain)
                        }
                        DineWisePlaceholderField("稍后提醒日期 YYYY-MM-DD",
                                                 isEmpty: (remindDates[item.Id] ?? "").isEmpty) {
                            TextField("", text: binding(remindDates, key: item.Id) { remindDates = $0 })
                                .textFieldStyle(.plain)
                        }
                        HStack(spacing: 8) {
                            Button("确认并建任务") { decide(item, action: "confirm") }
                                .buttonStyle(.borderedProminent)
                                .tint(DineWiseTheme.action(for: colorScheme))
                                .disabled(busy || (dueDates[item.Id] ?? "").isEmpty)
                            Button("否决") { decide(item, action: "reject") }
                                .buttonStyle(.bordered)
                                .disabled(busy || (reasons[item.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                            Button("稍后") { decide(item, action: "postpone") }
                                .buttonStyle(.bordered)
                                .disabled(busy || (reasons[item.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                                    || (remindDates[item.Id] ?? "").isEmpty)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.08), lineWidth: 1))
                .overlay(alignment: .leading) {
                    Capsule().fill(accent).frame(width: 3).padding(.vertical, 18)
                }
            }
            }
            if focus == nil && hasCurrentLists && hasOlderRecommendations {
                Button("加载更早的建议") { loadOlderRecommendations() }
                    .buttonStyle(.bordered).disabled(busy)
            }
            if focus == nil || focusedTask || !taskNotificationFocusID.isEmpty {
                sectionHeading(role == "owner" ? "任务进度" : "岗位任务", symbol: "checklist",
                    count: countLabel(visibleTasks.count,
                        hasOlder: hasOlderTasks || hasOlderMeetingTasks))
            }
            if role == "owner", focus == nil, hasCurrentLists {
                HStack(spacing: 8) {
                    Button("上周") { moveMeetingWeek(-1) }.buttonStyle(.bordered)
                    VStack(spacing: 2) {
                        Text("会议周") .font(.caption).foregroundStyle(.secondary)
                        Text("\(selectedMeetingWeekStart)—\(selectedMeetingWeekEnd)")
                            .font(.caption.weight(.semibold))
                    }
                    Button("下周") { moveMeetingWeek(1) }
                        .buttonStyle(.bordered).disabled(selectedMeetingWeekStart >= currentMeetingWeekStart)
                    Button("本周") { resetMeetingWeek() }
                        .buttonStyle(.bordered).disabled(selectedMeetingWeekStart == currentMeetingWeekStart)
                }
                if let meetingProgress {
                    Text("会议事项：已完成 \(meetingProgress.CompletedCount)/\(meetingProgress.TotalCount)，待处理 \(meetingProgress.PendingAssignmentCount + meetingProgress.PendingExecutionCount + meetingProgress.InProgressCount)，逾期 \(meetingProgress.OverdueCount)，待复核 \(meetingProgress.PendingReviewCount)，已取消 \(meetingProgress.CancelledCount)")
                        .font(.footnote).foregroundStyle(.secondary)
                    if meetingProgress.TotalCount > 0 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                meetingTaskFilterButton("全部", count: meetingProgress.TotalCount, value: "all")
                                meetingTaskFilterButton("未完成", count: meetingProgress.TotalCount - meetingProgress.CompletedCount - meetingProgress.CancelledCount, value: "open")
                                meetingTaskFilterButton("已完成", count: meetingProgress.CompletedCount, value: "completed")
                                meetingTaskFilterButton("已取消", count: meetingProgress.CancelledCount, value: "cancelled")
                            }
                        }
                    }
                } else {
                    Text("正在读取会议事项进度…").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if role == "owner", focus == nil, hasCurrentLists {
                DisclosureGroup("新建会议事项", isExpanded: $isMeetingFormExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("直接记录会议交办，不需要先创建经营建议。未指定个人时，所选岗位的授权成员都能接收并由首位开始执行的人接单。")
                            .font(.footnote).foregroundStyle(.secondary)
                        DatePicker("会议日期", selection: $meetingDate, displayedComponents: .date)
                        HStack(spacing: 8) {
                            Button("店长 · 周末排班") {
                                meetingTargetRole = "manager"
                                meetingAssignee = ""
                                meetingTitle = "确认周末排班方案"
                                meetingSteps = "检查周末各时段人员安排，确认关键岗位覆盖，并说明需要调整的班次。"
                            }
                            .buttonStyle(.bordered)
                            Button("采购 · 供应商报价") {
                                meetingTargetRole = "purchaser"
                                meetingAssignee = ""
                                meetingTitle = "核对两家供应商报价"
                                meetingSteps = "核对主要食材规格、含税价格和供货日期，记录差异并附报价来源。"
                            }
                            .buttonStyle(.bordered)
                        }
                        TextField("事项标题", text: $meetingTitle).textFieldStyle(.roundedBorder)
                        TextField("完成标准与说明", text: $meetingSteps, axis: .vertical)
                            .lineLimit(3...6).textFieldStyle(.roundedBorder)
                        Picker("交办岗位", selection: $meetingTargetRole) {
                            Text("店长").tag("manager")
                            Text("采购").tag("purchaser")
                        }
                        if !members.contains(where: { $0.Enabled && $0.Role == meetingTargetRole }) {
                            Text("当前门店没有已授权的\(roleName(meetingTargetRole))成员；事项会留在老板端，完成岗位授权后才能接收。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Picker("负责人（可由岗位成员接单）", selection: $meetingAssignee) {
                            Text("由岗位成员接单").tag("")
                            ForEach(members.filter { $0.Enabled && $0.Role == meetingTargetRole }) { member in
                                Text(member.Email ?? member.Username ?? member.UserId).tag(member.UserId)
                            }
                        }
                        .onChange(of: meetingAssignee) { _, assignee in
                            meetingHasDueDate = !assignee.isEmpty
                        }
                        if meetingAssignee.isEmpty {
                            Toggle("设置完成期限", isOn: $meetingHasDueDate)
                        }
                        if meetingHasDueDate || !meetingAssignee.isEmpty {
                            DatePicker("完成期限", selection: $meetingDueDate, displayedComponents: .date)
                        }
                        Button("创建会议事项") { createMeetingTask() }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy || meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || meetingSteps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.vertical, 6)
                }
                .font(.subheadline.weight(.semibold))
            }
            if hasCurrentLists && (focus == nil || focusedTask || !taskNotificationFocusID.isEmpty) && visibleTasks.isEmpty {
                DineWiseEmptyState(title: "暂无岗位任务",
                    detail: role == "owner" && meetingTaskFilter != "all"
                        ? "当前筛选下没有匹配的会议事项；普通建议任务仍会显示。"
                        : role == "owner" ? "确认并指派建议后，执行进度和回执会显示在这里。" : "获派任务后，可在这里查看步骤并提交执行回执。",
                    symbol: "checklist")
            }
            if hasCurrentLists {
            ForEach(visibleTasks.indices, id: \.self) { index in
                let task = visibleTasks[index]
                if let groupTitle = ownerTaskGroupTitle(at: index) {
                    Text(groupTitle).font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary).padding(.top, index == 0 ? 2 : 8)
                }
                let meetingAssignee = members.first { $0.UserId == task.AssignedUserId }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(task.SourceType == "meeting" && task.Status == "pending_assignment"
                            && task.AssignedUserId == nil ? "待岗位接单" : taskStatus(task.Status))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(taskStatusTint(task.Status))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(taskStatusTint(task.Status).opacity(0.11), in: Capsule())
                        Text(roleName(task.TargetRole)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(task.Title).font(.headline)
                    Text(task.SourceType == "meeting"
                        ? "会议事项 · \(task.MeetingOn ?? "会议日期待补")" : "建议任务")
                        .font(.caption).foregroundStyle(.secondary)
                    if task.SourceType == "meeting" {
                        let assigneeName = role == "owner"
                            ? (meetingAssignee?.Email?.isEmpty == false ? meetingAssignee?.Email
                                : meetingAssignee?.Username) ?? "成员信息不可用"
                            : "本人"
                        Text("负责人：\(task.AssignedUserId == nil ? "待岗位成员接单" : assigneeName)\(role == "owner" && meetingAssignee?.Enabled == false ? "（授权已撤销）" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if task.SourceInvalidatedAt != nil {
                        Text("\(invalidationName(task.InvalidationReason))，暂停执行旧任务。")
                            .font(.footnote.bold()).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                    }
                    if let dueOn = task.DueOn {
                        Text("执行截止：\(dueOn)\(task.IsOverdue == true ? " · 已超时" : "")")
                            .font(.caption).foregroundStyle(task.IsOverdue == true
                                ? DineWiseTheme.danger(for: colorScheme) : .secondary)
                    }
                    if task.EscalatedAtUtc != nil && task.SourceInvalidatedAt == nil {
                        Text("任务已逾期并提醒老板，请重新指派或处理。")
                            .font(.footnote.bold()).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                    }
                    if task.SourceInvalidatedAt == nil {
                        Text("步骤：\(task.Steps)")
                        if role == "operator", task.TargetRole == "operator",
                           ["pending_execution", "in_progress"].contains(task.Status) {
                            Button("复制执行步骤") {
                                UIPasteboard.general.string = task.Steps
                                setMessage("执行步骤已复制；请在目标平台人工操作，确认结果后再提交真实回执。")
                            }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.bordered)
                        }
                    }
                    if let progress = task.LatestProgressNote, !progress.isEmpty {
                        Text("最新进度：\(progress)\(task.LatestProgressAtUtc.map { " · \(taskEventTime($0))" } ?? "")")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .background(DineWiseTheme.inset, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let receipt = task.Receipt { Text("执行回执：\(receipt)") }
                    if let note = task.ReviewNote { Text("老板复核：\(note)") }
                    if role == "owner", task.SourceType == "meeting" {
                        Button(taskEventExpandedIDs.contains(task.Id) ? "收起进度记录" : "查看进度记录") {
                            toggleTaskEventHistory(task)
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if taskEventExpandedIDs.contains(task.Id) {
                            VStack(alignment: .leading, spacing: 8) {
                                if taskEventLoadingIDs.contains(task.Id) {
                                    ProgressView("正在读取进度记录…").font(.footnote)
                                }
                                if let error = taskEventErrors[task.Id] {
                                    Text(error).font(.footnote).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                                }
                                if let history = taskEventHistories[task.Id] {
                                    if history.Items.isEmpty {
                                        Text("暂无操作记录。").font(.footnote).foregroundStyle(.secondary)
                                    }
                                    ForEach(history.Items) { event in
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                Text(taskEventActionLabel(event.Action))
                                                    .font(.subheadline.weight(.semibold))
                                                Spacer(minLength: 4)
                                                Text(taskEventTime(event.ActedAtUtc))
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            let actor = event.ActorLabel.isEmpty ? taskEventActorLabel(event.ActorType) : event.ActorLabel
                                            let actorDescription = actor == taskEventActorLabel(event.ActorType)
                                                ? actor : "\(actor)（\(taskEventActorLabel(event.ActorType))）"
                                            Text("\(actorDescription) · 第 \(event.Version) 版\(event.DueOn.map { " · 截止 \($0)" } ?? "")")
                                                .font(.caption).foregroundStyle(.secondary)
                                            if let note = event.Note, !note.isEmpty {
                                                Text(note).font(.footnote).fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                        if event.Id != history.Items.last?.Id { Divider() }
                                    }
                                    if history.HasOlder {
                                        Button(taskEventLoadingIDs.contains(task.Id)
                                            ? "正在加载…" : "加载更早的进度记录") {
                                            loadOlderTaskEventHistory(task)
                                        }
                                        .font(.footnote.weight(.semibold))
                                        .disabled(taskEventLoadingIDs.contains(task.Id))
                                    }
                                }
                            }
                            .padding(12)
                            .background(DineWiseTheme.inset, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    if ["pending_assignment", "pending_execution", "in_progress", "pending_review"].contains(task.Status) {
                        if role == "owner" && ["pending_assignment", "pending_execution", "in_progress"].contains(task.Status) {
                            let displayedDueOn = dueDates[task.Id] ?? task.DueOn ?? ""
                            Picker("执行人", selection: binding(assignees, key: task.Id) { assignees = $0 }) {
                                Text("请选择").tag("")
                                ForEach(members.filter { $0.Enabled && $0.Role == task.TargetRole }) { member in
                                    Text(member.Email ?? member.UserId).tag(member.UserId)
                                }
                            }
                            DatePicker(displayedDueOn.isEmpty ? "完成期限（未设置）" : "执行截止日期", selection: Binding(
                                get: {
                                    dateFromMeetingOn(dueDates[task.Id] ?? task.DueOn ?? "") ?? .now
                                },
                                set: { date in
                                    let value = localDateString(date)
                                    dueDates[task.Id] = value
                                    if task.SourceType == "meeting", (task.DueOn ?? "").isEmpty,
                                       escalationRules[task.Id] == nil {
                                        escalationRules[task.Id] = "owner_on_overdue"
                                    }
                                }), displayedComponents: .date)
                                .datePickerStyle(.compact)
                            if task.SourceType == "meeting",
                               !displayedDueOn.isEmpty {
                                Button("清除完成期限") {
                                    dueDates[task.Id] = ""
                                    escalationRules[task.Id] = "none"
                                }
                                .buttonStyle(.borderless)
                            }
                            Picker("逾期处理", selection: Binding(
                                get: { escalationRules[task.Id] ?? task.EscalationRule ?? "owner_on_overdue" },
                                set: { escalationRules[task.Id] = $0 })) {
                                Text("逾期提醒老板").tag("owner_on_overdue")
                                Text("仅显示超时").tag("none")
                            }
                        }
                        if role == "owner" && task.SourceType != "meeting" && task.Status == "pending_review" {
                            DineWisePlaceholderField("观察期复盘日期 YYYY-MM-DD",
                                                     isEmpty: (reviewDueDates[task.Id] ?? "").isEmpty) {
                                TextField("", text: binding(reviewDueDates, key: task.Id) { reviewDueDates = $0 })
                                    .textFieldStyle(.plain)
                            }
                        }
                        let roleQueueClaim = role != "owner" && task.SourceType == "meeting"
                            && task.Status == "pending_assignment" && task.AssignedUserId == nil
                        let progressInput = role != "owner" && task.SourceType == "meeting" && task.Status == "in_progress"
                        if !roleQueueClaim {
                            TextField(progressInput ? "本次进度说明（可多次汇报）" : "实际回执或复核说明",
                                      text: binding(taskNotes, key: task.Id) { taskNotes = $0 }, axis: .vertical)
                                .lineLimit(2...5).textFieldStyle(.roundedBorder)
                        }
                        if role == "owner" {
                            HStack {
                                if task.SourceType == "meeting"
                                    && ["pending_assignment", "pending_execution", "in_progress"].contains(task.Status) {
                                    Button("保存期限") { act(task, action: "reschedule") }
                                        .disabled(busy || task.SourceInvalidatedAt != nil
                                            || (dueDates[task.Id] ?? task.DueOn ?? "") == (task.DueOn ?? "")
                                                && (escalationRules[task.Id] ?? task.EscalationRule ?? "none")
                                                    == (task.EscalationRule ?? "none"))
                                }
                                if task.Status == "pending_assignment" {
                                    Button("指派") { act(task, action: "assign") }
                                        .disabled(busy || task.SourceInvalidatedAt != nil
                                            || (assignees[task.Id] ?? "").isEmpty
                                            || (dueDates[task.Id] ?? task.DueOn ?? "").isEmpty)
                                }
                                if ["pending_execution", "in_progress"].contains(task.Status) {
                                    Button("重新指派") { act(task, action: "reassign") }
                                        .disabled(busy || task.SourceInvalidatedAt != nil
                                            || (assignees[task.Id] ?? "").isEmpty
                                            || (dueDates[task.Id] ?? task.DueOn ?? "").isEmpty
                                            || (taskNotes[task.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                                if task.Status == "pending_review" {
                                    if task.SourceType == "meeting" {
                                        Button("确认完成") { act(task, action: "complete") }
                                            .disabled(busy || task.SourceInvalidatedAt != nil
                                                || (taskNotes[task.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                                    } else {
                                        Button("复核完成并设复盘") { act(task, action: "complete") }
                                            .disabled(busy || task.SourceInvalidatedAt != nil
                                                || (reviewDueDates[task.Id] ?? "").isEmpty)
                                    }
                                    Button("退回重做") { act(task, action: "rework") }
                                        .disabled(busy || task.SourceInvalidatedAt != nil
                                            || (taskNotes[task.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                                Button("取消任务", role: .destructive) { act(task, action: "cancel") }
                                    .disabled(busy || (taskNotes[task.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            HStack {
                                if task.Status == "pending_execution" || roleQueueClaim {
                                    Button(roleQueueClaim ? "开始执行并接单" : "开始执行") { act(task, action: "start") }
                                        .disabled(busy || task.SourceInvalidatedAt != nil)
                                }
                                if task.SourceType == "meeting" && task.Status == "in_progress" {
                                    Button("汇报进度") { act(task, action: "progress") }
                                        .disabled(busy || task.SourceInvalidatedAt != nil
                                            || (taskNotes[task.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                                if ["pending_execution", "in_progress"].contains(task.Status) {
                                    Button("提交回执") { act(task, action: "receipt") }
                                        .disabled(busy || task.SourceInvalidatedAt != nil
                                            || (taskNotes[task.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        if role != "owner" && task.SourceType == "meeting"
                            && task.Status == "pending_assignment" && task.AssignedUserId == nil
                            && task.SourceInvalidatedAt == nil {
                            Button("开始执行并接单") { act(task, action: "start") }
                                .buttonStyle(.borderedProminent)
                                .disabled(busy)
                        }
                    }
                }
                .dineWiseCard()
            }
            }
            if focus == nil && hasCurrentLists && hasOlderTasks {
                Button("加载更早的岗位任务") { loadOlderTasks() }
                    .buttonStyle(.bordered).disabled(busy)
            }
            if role == "owner" && focus == nil && hasCurrentLists && hasOlderMeetingTasks {
                Button("加载更早的本周会议事项") { loadOlderMeetingTasks() }
                    .buttonStyle(.bordered).disabled(busy)
            }
            if role == "owner" && (focus == nil || focusedReview) {
                sectionHeading("到期复盘", symbol: "calendar.badge.clock",
                    count: countLabel(visibleReviews.count, hasOlder: hasOlderReviews))
                if hasCurrentLists && visibleReviews.isEmpty {
                    DineWiseEmptyState(title: "暂无到期复盘",
                        detail: "岗位任务进入观察期并到期后，可在这里核对实际资料并记录结果。",
                        symbol: "calendar.badge.clock")
                }
                if hasCurrentLists {
                ForEach(visibleReviews) { review in
                    let task = tasks.first(where: { $0.Id == review.TaskId })
                    let invalidated = review.SourceInvalidatedAt != nil || task?.SourceInvalidatedAt != nil
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reviewStatus(review.Status))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(reviewStatusTint(review.Status))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(reviewStatusTint(review.Status).opacity(0.11), in: Capsule())
                        Text(invalidated ? "资料不足复盘" : task?.Title ?? "任务 \(review.TaskId)")
                            .font(.headline)
                        Text("复盘日期 \(review.DueOn)")
                            .font(.caption).foregroundStyle(.secondary)
                        if review.SourceInvalidatedAt != nil {
                            Text("\(invalidationName(review.InvalidationReason))，不能形成有效对照。")
                                .font(.footnote.bold()).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                        }
                        if review.Status == "reviewed" && review.SourceInvalidatedAt == nil {
                            Text("\(reviewMetricName(review.MetricKey))：\(review.BeforeBusinessDate ?? "") \(review.BeforeValue ?? "") → \(review.AfterBusinessDate ?? "") \(review.AfterValue ?? "") \(reviewMetricUnit(review.MetricKey, unit: review.MetricUnit))")
                            Text("人工结论：\(review.Conclusion ?? "")")
                        }
                        if review.Status == "insufficient" && review.SourceInvalidatedAt == nil {
                            Text("资料不足：\(review.Conclusion ?? "")")
                        }
                        if review.Status == "insufficient" && review.SourceInvalidatedAt != nil {
                            Text(review.Conclusion.map { "资料不足：\($0)" } ?? "原复盘结论失效。")
                        }
                        if let next = review.NextStep {
                            Text("下一步：\(next)")
                        }
                        if review.Status == "due" {
                            Text(invalidated ? "关联建议或来源已失效，只能记录资料不足。" :
                                 "前后资料须跨越任务完成日；同口径差异不代表任务造成的变化。")
                                .font(.footnote).foregroundStyle(.secondary)
                            if !invalidated {
                                Picker("复盘结果", selection: binding(reviewOutcomes, key: review.Id) { reviewOutcomes = $0 }) {
                                    Text("有效对照").tag("reviewed")
                                    Text("资料不足").tag("insufficient")
                                }
                            }
                            let outcome = invalidated ? "insufficient" : (reviewOutcomes[review.Id] ?? "reviewed")
                            if outcome == "reviewed" {
                                Picker("对照字段", selection: binding(reviewMetricKeys, key: review.Id) { reviewMetricKeys = $0 }) {
                                    Text("营业额").tag("revenue_yuan")
                                    Text("订单数").tag("orders")
                                    Text("桌数").tag("tables")
                                    Text("采购数量").tag("purchase_quantity")
                                    Text("采购单价").tag("unit_price_yuan_per_kg")
                                    Text("剩余数量").tag("outcome_quantity")
                                }
                                Picker("观察前已确认资料", selection: binding(reviewBeforeIDs, key: review.Id) { reviewBeforeIDs = $0 }) {
                                    Text("请选择").tag("")
                                    ForEach(confirmed) { source in
                                        Text("\(source.BusinessDate) · \(source.Id)").tag(source.Id)
                                    }
                                }
                                Picker("观察后已确认资料", selection: binding(reviewAfterIDs, key: review.Id) { reviewAfterIDs = $0 }) {
                                    Text("请选择").tag("")
                                    ForEach(confirmed) { source in
                                        Text("\(source.BusinessDate) · \(source.Id)").tag(source.Id)
                                    }
                                }
                            }
                            if !invalidated {
                                TextField("其他影响因素，未知填尚未核实", text: binding(reviewConfounders, key: review.Id) { reviewConfounders = $0 }, axis: .vertical)
                                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                            }
                            TextField(outcome == "reviewed" ? "人工结论" : "资料缺口原因",
                                      text: binding(reviewConclusions, key: review.Id) { reviewConclusions = $0 }, axis: .vertical)
                                .lineLimit(2...4).textFieldStyle(.roundedBorder)
                            TextField("下一步", text: binding(reviewNextSteps, key: review.Id) { reviewNextSteps = $0 }, axis: .vertical)
                                .lineLimit(2...4).textFieldStyle(.roundedBorder)
                            Button("保存复盘") { finishReview(review) }
                                .buttonStyle(.borderedProminent)
                                .disabled(busy || (reviewConclusions[review.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                                    || (reviewNextSteps[review.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                                    || outcome == "reviewed" && (reviewConfounders[review.Id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                                    || outcome == "reviewed" && ((reviewBeforeIDs[review.Id] ?? "").isEmpty
                                        || (reviewAfterIDs[review.Id] ?? "").isEmpty))
                        }
                    }
                    .dineWiseCard()
                }
                }
                if focus == nil && hasCurrentLists && hasOlderReviews {
                    Button("加载更早的复盘") { loadOlderReviews() }
                        .buttonStyle(.bordered).disabled(busy)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .task(id: requestScopeKey) {
            workspace = requestScopeKey
            loadVersion += 1
            setMessage("")
            recommendations = []
            hasOlderRecommendations = false
            tasks = []
            meetingTasks = []
            hasOlderMeetingTasks = false
            taskNotifications = []
            taskNotificationFocusID = ""
            taskEventHistories = [:]; taskEventExpandedIDs = []
            taskEventLoadingIDs = []; taskEventRequestVersions = [:]; taskEventErrors = [:]
            hasOlderTasks = false
            reviews = []
            hasOlderReviews = false
            reasons = [:]; remindDates = [:]; assignees = [:]; taskNotes = [:]
            dueDates = [:]; escalationRules = [:]; reviewDueDates = [:]; reviewOutcomes = [:]
            reviewMetricKeys = [:]; reviewBeforeIDs = [:]; reviewAfterIDs = [:]
            reviewConfounders = [:]; reviewConclusions = [:]; reviewNextSteps = [:]
            validUntilOn = ""; replacesID = ""
            busy = false
            hasLoaded = false
            listLoadFailed = false
            refresh()
        }
        .task(id: "\(requestScopeKey):\(scenePhase)") {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await reloadTaskNotifications()
                if role == "owner", focus == nil, !busy {
                    await refreshMeetingProgress(preservingCurrent: true)
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
            }
        }
        .onChange(of: submissions.map { "\($0.Id):\($0.Version)" }.joined(separator: ",")) { _, _ in
            refresh()
        }
        .task(id: pushTaskFocusID) {
            guard !pushTaskFocusID.isEmpty else { return }
            openTask(taskID: pushTaskFocusID)
            onPushTaskFocusConsumed()
        }
        .onChange(of: selectedMeetingWeekStart) { _, _ in
            taskNotificationOpenVersion += 1
            meetingTaskFilter = "all"
            tasks.removeAll { $0.SourceType == "meeting" && $0.Id != taskNotificationFocusID }
            loadMeetingProgress()
        }
        .onChange(of: sourceSelectionScopeKey) { _, _ in
            guard submissionLoadState == "loaded", !sourceID.isEmpty,
                  !confirmed.contains(where: { $0.Id == sourceID }) else { return }
            sourceID = ""
            replacesID = ""
            setMessage("已选来源资料不再处于已确认状态，请重新选择来源。", isError: true)
        }
        .onChange(of: replacementOptionsKey) { _, _ in
            guard hasCurrentLists, role == "owner", !replacesID.isEmpty,
                  !replaceableRecommendations.contains(where: { $0.Id == replacesID }) else { return }
            replacesID = ""
            setMessage("旧建议已更新，已清除替代关系。")
        }
    }

    private func binding(_ values: [String: String], key: String,
                         update: @escaping ([String: String]) -> Void) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { value in
            var next = values; next[key] = value; update(next)
        })
    }

    private func countLabel(_ count: Int, hasOlder: Bool) -> String {
        "\(count)\(hasOlder ? "+" : "")"
    }

    private func meetingTaskFilterButton(_ title: String, count: Int, value: String) -> some View {
        let selected = meetingTaskFilter == value
        return Button { meetingTaskFilter = value } label: {
            Text("\(title) \(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? accent : Color.primary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(selected ? accent.opacity(0.14) : DineWiseTheme.card,
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "已选中" : "")
    }

    private func sectionHeading(_ title: String, symbol: String, count: String) -> some View {
        HStack(spacing: 8) {
            Capsule().fill(accent).frame(width: 4, height: 18)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
            Text(title).font(.headline.weight(.bold))
            if hasCurrentLists {
                Text(count)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(accent.opacity(0.10), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.top, 5)
    }

    private func detailBlock(_ title: String, symbol: String, text: String,
                             subdued: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(subdued ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DineWiseTheme.inset, in: RoundedRectangle(cornerRadius: 14))
    }

    private func loadOlderRecommendations() {
        guard focus == nil, hasOlderRecommendations, !busy,
              let cursor = recommendations.last?.Id else { return }
        let requestedWorkspace = requestScopeKey
        let requestToken = token
        let requestRole = role
        let requestedLoad = loadVersion
        busy = true
        Task {
            do {
                let older = try await api.recommendations(storeID: store.Id, token: requestToken,
                    role: requestRole, beforeID: cursor, size: 101)
                guard isCurrentWorkspace(requestedWorkspace, token: requestToken) else { return }
                guard loadVersion == requestedLoad else { busy = false; return }
                guard older.allSatisfy({ $0.StoreId == store.Id && $0.Mode == store.Mode }) else {
                    throw DineWiseDecisionTaskScopeError.mismatch
                }
                let existing = Set(recommendations.map(\.Id))
                recommendations.append(contentsOf: older.prefix(100).filter { !existing.contains($0.Id) })
                hasOlderRecommendations = older.count > 100
            } catch {
                if isCurrentWorkspace(requestedWorkspace, token: requestToken), loadVersion == requestedLoad {
                    setMessage(error.localizedDescription, isError: true)
                }
            }
            if isCurrentWorkspace(requestedWorkspace, token: requestToken), loadVersion == requestedLoad {
                busy = false
            }
        }
    }

    private func loadOlderTasks() {
        guard focus == nil, hasOlderTasks, !busy, let cursor = tasks.last?.Id else { return }
        let requestedWorkspace = requestScopeKey
        let requestToken = token
        let requestRole = role
        let requestedLoad = loadVersion
        busy = true
        Task {
            do {
                let older = try await api.tasks(storeID: store.Id, token: requestToken,
                    role: requestRole, beforeID: cursor, size: 101,
                    excludeMeetings: requestRole == "owner")
                guard isCurrentWorkspace(requestedWorkspace, token: requestToken) else { return }
                guard loadVersion == requestedLoad else { busy = false; return }
                guard older.allSatisfy({ $0.StoreId == store.Id && $0.Mode == store.Mode }) else {
                    throw DineWiseDecisionTaskScopeError.mismatch
                }
                let existing = Set(tasks.map(\.Id))
                tasks.append(contentsOf: older.prefix(100).filter { !existing.contains($0.Id) })
                hasOlderTasks = older.count > 100
            } catch {
                if isCurrentWorkspace(requestedWorkspace, token: requestToken), loadVersion == requestedLoad {
                    setMessage(error.localizedDescription, isError: true)
                }
            }
            if isCurrentWorkspace(requestedWorkspace, token: requestToken), loadVersion == requestedLoad {
                busy = false
            }
        }
    }

    private func loadOlderMeetingTasks() {
        guard role == "owner", focus == nil, hasOlderMeetingTasks, !busy,
              let cursor = meetingTasks.last?.Id else { return }
        let requestedWorkspace = requestScopeKey
        let requestToken = token
        let weekStart = selectedMeetingWeekStart
        let requestedLoad = loadVersion
        busy = true
        Task {
            do {
                let older = try await api.tasks(storeID: store.Id, token: requestToken,
                    role: "owner", beforeID: cursor, size: 101,
                    meetingWeekStartOn: weekStart)
                guard isCurrentWorkspace(requestedWorkspace, token: requestToken),
                      selectedMeetingWeekStart == weekStart else { return }
                guard loadVersion == requestedLoad else { busy = false; return }
                guard older.allSatisfy({ $0.StoreId == store.Id && $0.Mode == store.Mode }) else {
                    throw DineWiseDecisionTaskScopeError.mismatch
                }
                let existing = Set(meetingTasks.map(\.Id))
                meetingTasks.append(contentsOf: older.prefix(100).filter { !existing.contains($0.Id) })
                hasOlderMeetingTasks = older.count > 100
            } catch {
                if isCurrentWorkspace(requestedWorkspace, token: requestToken), loadVersion == requestedLoad {
                    setMessage(error.localizedDescription, isError: true)
                }
            }
            if isCurrentWorkspace(requestedWorkspace, token: requestToken), loadVersion == requestedLoad {
                busy = false
            }
        }
    }

    private func loadOlderReviews() {
        guard role == "owner", focus == nil, hasOlderReviews, !busy,
              let cursor = reviews.last?.Id else { return }
        let requestedWorkspace = requestScopeKey
        let requestToken = token
        let requestedLoad = loadVersion
        busy = true
        Task {
            do {
                let older = try await api.taskReviews(storeID: store.Id, token: requestToken,
                    role: "owner", beforeID: cursor, size: 101)
                guard isCurrentWorkspace(requestedWorkspace, token: requestToken) else { return }
                guard loadVersion == requestedLoad else { busy = false; return }
                guard older.allSatisfy({ $0.StoreId == store.Id && $0.Mode == store.Mode }) else {
                    throw DineWiseDecisionTaskScopeError.mismatch
                }
                let existing = Set(reviews.map(\.Id))
                reviews.append(contentsOf: older.prefix(100).filter { !existing.contains($0.Id) })
                hasOlderReviews = older.count > 100
            } catch {
                if isCurrentWorkspace(requestedWorkspace, token: requestToken), loadVersion == requestedLoad {
                    setMessage(error.localizedDescription, isError: true)
                }
            }
            if isCurrentWorkspace(requestedWorkspace, token: requestToken), loadVersion == requestedLoad {
                busy = false
            }
        }
    }

    private func refresh() {
        onRetrySubmissions()
        hasLoaded = false
        listLoadFailed = false
        setMessage("")
        Task { _ = await reload { setMessage($0.localizedDescription, isError: true) } }
    }

    private func reloadTaskNotifications() async {
        guard ["owner", "manager", "purchaser"].contains(role) else { return }
        let requestedWorkspace = requestScopeKey
        guard let rows = try? await api.taskNotifications(storeID: store.Id,
            token: token, role: role), isCurrentWorkspace(requestedWorkspace, token: token) else { return }
        taskNotifications = rows
    }

    private func markTaskNotificationRead(_ item: DineWiseTaskNotification) {
        let requestedWorkspace = requestScopeKey
        Task {
            do {
                _ = try await api.markTaskNotificationRead(storeID: store.Id,
                    notificationID: item.Id, token: token, role: role)
                guard isCurrentWorkspace(requestedWorkspace, token: token) else { return }
                taskNotifications.removeAll { $0.Id == item.Id }
                onTaskNotificationRead()
            } catch {
                guard isCurrentWorkspace(requestedWorkspace, token: token) else { return }
                setMessage(error.localizedDescription, isError: true)
            }
        }
    }

    private func toggleTaskEventHistory(_ task: DineWiseTask) {
        if taskEventExpandedIDs.contains(task.Id) {
            taskEventRequestVersions[task.Id, default: 0] += 1
            taskEventExpandedIDs.remove(task.Id)
            taskEventLoadingIDs.remove(task.Id)
            return
        }
        taskEventExpandedIDs.insert(task.Id)
        Task { await reloadTaskEventHistory(task) }
    }

    private func reloadTaskEventHistory(_ task: DineWiseTask) async {
        taskEventRequestVersions[task.Id, default: 0] += 1
        let requestVersion = taskEventRequestVersions[task.Id, default: 0]
        taskEventLoadingIDs.insert(task.Id)
        taskEventErrors.removeValue(forKey: task.Id)
        let requestedWorkspace = requestScopeKey
        let requestToken = token
        defer {
            if isCurrentWorkspace(requestedWorkspace, token: requestToken),
               taskEventRequestVersions[task.Id] == requestVersion {
                taskEventLoadingIDs.remove(task.Id)
            }
        }
        do {
            let history = try await api.meetingTaskEvents(storeID: store.Id,
                taskID: task.Id, token: requestToken, role: "owner")
            guard isCurrentWorkspace(requestedWorkspace, token: requestToken),
                  taskEventRequestVersions[task.Id] == requestVersion else { return }
            guard history.TaskId == task.Id else {
                throw DineWiseDecisionTaskScopeError.mismatch
            }
            taskEventHistories[task.Id] = history
        } catch {
            guard isCurrentWorkspace(requestedWorkspace, token: requestToken),
                  taskEventRequestVersions[task.Id] == requestVersion else { return }
            taskEventErrors[task.Id] = error.localizedDescription
        }
    }

    private func loadOlderTaskEventHistory(_ task: DineWiseTask) {
        guard let current = taskEventHistories[task.Id], current.HasOlder,
              let beforeID = current.Items.first?.Id,
              !taskEventLoadingIDs.contains(task.Id) else { return }
        taskEventRequestVersions[task.Id, default: 0] += 1
        let requestVersion = taskEventRequestVersions[task.Id, default: 0]
        taskEventLoadingIDs.insert(task.Id)
        taskEventErrors.removeValue(forKey: task.Id)
        let requestedWorkspace = requestScopeKey
        let requestToken = token
        Task {
            defer {
                if isCurrentWorkspace(requestedWorkspace, token: requestToken),
                   taskEventRequestVersions[task.Id] == requestVersion {
                    taskEventLoadingIDs.remove(task.Id)
                }
            }
            do {
                let older = try await api.meetingTaskEvents(storeID: store.Id,
                    taskID: task.Id, token: requestToken, role: "owner", beforeID: beforeID)
                guard isCurrentWorkspace(requestedWorkspace, token: requestToken),
                      taskEventRequestVersions[task.Id] == requestVersion else { return }
                guard older.TaskId == task.Id else {
                    throw DineWiseDecisionTaskScopeError.mismatch
                }
                if let latest = taskEventHistories[task.Id] {
                    taskEventHistories[task.Id] = DineWiseTaskEventHistory(
                        TaskId: older.TaskId, HasOlder: older.HasOlder,
                        Items: older.Items + latest.Items)
                }
            } catch {
                guard isCurrentWorkspace(requestedWorkspace, token: requestToken),
                      taskEventRequestVersions[task.Id] == requestVersion else { return }
                taskEventErrors[task.Id] = error.localizedDescription
            }
        }
    }

    private func openTaskFromNotification(_ item: DineWiseTaskNotification) {
        openTask(taskID: item.TaskId)
    }

    private func openTask(taskID: String) {
        let requestedWorkspace = sessionScopeKey
        taskNotificationOpenVersion += 1
        let openVersion = taskNotificationOpenVersion
        Task {
            do {
                let rows = try await api.tasks(storeID: store.Id, token: token,
                    role: role, focusID: taskID, size: 1)
                guard sessionScopeKey == requestedWorkspace,
                      taskNotificationOpenVersion == openVersion else { return }
                guard let task = rows.first, task.Id == taskID, task.StoreId == store.Id,
                      task.Mode == store.Mode else {
                    setMessage("通知中的事项已变化或不可查看，请刷新任务列表。", isError: true)
                    return
                }
                if role == "owner", task.SourceType == "meeting",
                   let meetingOn = task.MeetingOn, let date = dateFromMeetingOn(meetingOn) {
                    meetingTaskFilter = "all"
                    tasks.removeAll { $0.SourceType == "meeting" && $0.Id != task.Id }
                    meetingWeek = date
                }
                tasks = [task] + tasks.filter { $0.Id != task.Id }
                taskNotificationFocusID = task.Id
            } catch {
                guard sessionScopeKey == requestedWorkspace,
                      taskNotificationOpenVersion == openVersion else { return }
                setMessage(error.localizedDescription, isError: true)
            }
        }
    }

    private func moveMeetingWeek(_ offset: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: store.TimeZone ?? "") ?? .current
        meetingProgress = nil
        meetingTaskFilter = "all"
        taskNotificationFocusID = ""
        meetingWeek = calendar.date(byAdding: .weekOfYear, value: offset, to: meetingWeek) ?? meetingWeek
    }

    private func resetMeetingWeek() {
        meetingProgress = nil
        meetingTaskFilter = "all"
        taskNotificationFocusID = ""
        meetingWeek = .now
    }

    private func dateFromMeetingOn(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: store.TimeZone ?? "") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func loadMeetingProgress(preservingCurrent: Bool = false) {
        Task { await refreshMeetingProgress(preservingCurrent: preservingCurrent) }
    }

    private func refreshMeetingProgress(preservingCurrent: Bool = false) async {
        guard role == "owner" else { return }
        let weekStart = selectedMeetingWeekStart
        let requestedWorkspace = requestScopeKey
        let requestedLoad = loadVersion
        if !preservingCurrent {
            meetingProgress = nil
            meetingTasks = []
            hasOlderMeetingTasks = false
        }
        async let summaryRequest = api.meetingProgress(storeID: store.Id, token: token,
            role: role, weekStartOn: weekStart)
        async let tasksRequest = api.tasks(storeID: store.Id, token: token, role: role,
            size: 101, meetingWeekStartOn: weekStart)
        let summary = try? await summaryRequest
        let weekTasks = try? await tasksRequest
        guard !Task.isCancelled,
              isCurrentWorkspace(requestedWorkspace, token: token),
              selectedMeetingWeekStart == weekStart, loadVersion == requestedLoad,
              !preservingCurrent || !busy else { return }
        guard let summary, let weekTasks,
              weekTasks.allSatisfy({ $0.StoreId == store.Id && $0.Mode == store.Mode }) else {
            if !preservingCurrent {
                meetingProgress = nil
                meetingTasks = []
                hasOlderMeetingTasks = false
            }
            return
        }
        let refreshed = Array(weekTasks.prefix(100))
        let refreshedIDs = Set(refreshed.map(\.Id))
        let previouslyLoadedOlder = meetingTasks.filter { !refreshedIDs.contains($0.Id) }
        meetingProgress = summary
        meetingTasks = refreshed + previouslyLoadedOlder
        hasOlderMeetingTasks = weekTasks.count > 100 || !previouslyLoadedOlder.isEmpty
    }

    private func reload(onFailure: (Error) -> Void) async -> Bool {
        let requestedWorkspace = requestScopeKey
        let requestedListScope = listScopeKey
        let requestStoreID = store.Id
        let requestToken = token
        let requestRole = role
        let recommendationFocusID = focusedRecommendation ? focus?.Id : nil
        let reviewFocusID = focusedReview ? focus?.Id : nil
        let requestedFocus = focus
        let pageSize = requestedFocus == nil ? 101 : 100
        let wantsFocusedTask = focusedTask
        let wantsFocusedReview = focusedReview
        loadVersion += 1
        let requestedLoad = loadVersion
        do {
            async let nextRecommendations = api.recommendations(storeID: requestStoreID,
                token: requestToken, role: requestRole, focusID: recommendationFocusID,
                size: pageSize)
            let loadedReviews = requestRole == "owner"
                ? try await api.taskReviews(storeID: requestStoreID, token: requestToken,
                    role: requestRole, focusID: reviewFocusID, size: pageSize) : []
            let taskFocusID = taskNotificationFocusID.isEmpty
                ? (wantsFocusedTask ? requestedFocus?.Id : wantsFocusedReview
                    ? loadedReviews.first(where: { $0.Id == requestedFocus?.Id })?.TaskId : nil)
                : taskNotificationFocusID
            async let nextTasks = api.tasks(storeID: requestStoreID, token: requestToken,
                role: requestRole, focusID: taskFocusID, size: pageSize,
                excludeMeetings: requestRole == "owner" && taskFocusID == nil
                    && requestedFocus == nil)
            let (loadedRecommendations, loadedTasks) = try await (nextRecommendations, nextTasks)
            let loadedMeetingProgress: DineWiseMeetingProgressSummary?
            if requestRole == "owner" && requestedFocus == nil {
                let weekStart = selectedMeetingWeekStart
                async let summary = api.meetingProgress(storeID: requestStoreID,
                    token: requestToken, role: requestRole, weekStartOn: weekStart)
                async let weekTasks = api.tasks(storeID: requestStoreID, token: requestToken,
                    role: requestRole, size: 101, meetingWeekStartOn: weekStart)
                let loadedSummary = try? await summary
                let loadedMeetingTasks = try? await weekTasks
                if let loadedSummary, let loadedMeetingTasks,
                   loadedMeetingTasks.allSatisfy({ $0.StoreId == requestStoreID && $0.Mode == store.Mode }) {
                    loadedMeetingProgress = loadedSummary
                    meetingTasks = Array(loadedMeetingTasks.prefix(100))
                    hasOlderMeetingTasks = loadedMeetingTasks.count > 100
                } else {
                    loadedMeetingProgress = nil
                    meetingTasks = []
                    hasOlderMeetingTasks = false
                }
            } else {
                loadedMeetingProgress = nil
                meetingTasks = []
                hasOlderMeetingTasks = false
            }
            let loadedTaskNotifications: [DineWiseTaskNotification]
            if ["owner", "manager", "purchaser"].contains(requestRole) {
                loadedTaskNotifications = (try? await api.taskNotifications(storeID: requestStoreID,
                    token: requestToken, role: requestRole)) ?? []
            } else {
                loadedTaskNotifications = []
            }
            guard loadedRecommendations.allSatisfy({ $0.StoreId == requestStoreID && $0.Mode == store.Mode }),
                  loadedTasks.allSatisfy({ $0.StoreId == requestStoreID && $0.Mode == store.Mode }),
                  loadedReviews.allSatisfy({ $0.StoreId == requestStoreID && $0.Mode == store.Mode }) else {
                throw DineWiseDecisionTaskScopeError.mismatch
            }
            guard isCurrentWorkspace(requestedWorkspace, token: requestToken),
                  listScopeKey == requestedListScope, loadVersion == requestedLoad else {
                return false
            }
            recommendations = requestedFocus == nil ? Array(loadedRecommendations.prefix(100)) : loadedRecommendations
            tasks = requestedFocus == nil ? Array(loadedTasks.prefix(100)) : loadedTasks
            if loadedMeetingProgress?.WeekStartOn == selectedMeetingWeekStart {
                meetingProgress = loadedMeetingProgress
            }
            reviews = requestedFocus == nil ? Array(loadedReviews.prefix(100)) : loadedReviews
            taskNotifications = loadedTaskNotifications
            hasOlderRecommendations = requestedFocus == nil && loadedRecommendations.count > 100
            hasOlderTasks = requestedFocus == nil && loadedTasks.count > 100
            hasOlderReviews = requestedFocus == nil && loadedReviews.count > 100
            loadedListScopeKey = requestedListScope
            hasLoaded = true
            listLoadFailed = false
            for task in loadedTasks where dueDates[task.Id] == nil {
                dueDates[task.Id] = task.DueOn ?? ""
            }
            for review in loadedReviews where review.Status == "due" {
                if reviewOutcomes[review.Id] == nil { reviewOutcomes[review.Id] = "reviewed" }
                if reviewMetricKeys[review.Id] == nil { reviewMetricKeys[review.Id] = "revenue_yuan" }
            }
            return true
        } catch {
            guard isCurrentWorkspace(requestedWorkspace, token: requestToken), loadVersion == requestedLoad else {
                return false
            }
            onFailure(error)
            hasLoaded = true
            listLoadFailed = true
            return false
        }
    }

    private func refreshAfterMutation(workspace: String, token requestToken: String,
                                      successMessage: String) async -> Bool {
        guard isCurrentWorkspace(workspace, token: requestToken) else { return false }
        guard await reload(onFailure: { error in
            if isCurrentWorkspace(workspace, token: requestToken) {
                setMessage("操作已保存，但列表刷新失败：\(error.localizedDescription)", isError: true)
            }
        }), isCurrentWorkspace(workspace, token: requestToken) else { return false }
        setMessage(successMessage)
        return true
    }

    private func propose() {
        let requestedWorkspace = requestScopeKey
        let requestStoreID = store.Id
        let requestToken = token
        let requestRole = role
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRationale = rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCalculationBasis = calculationBasis.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfidenceReason = confidenceReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSteps = steps.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestSourceSubmissionID = sourceID
        let requestTargetRole = targetRole
        let until = validUntilOn.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacesID
        var payload = ["SourceSubmissionId": requestSourceSubmissionID,
                       "Title": trimmedTitle, "Rationale": trimmedRationale,
                       "CalculationBasis": trimmedCalculationBasis,
                       "ConfidenceLevel": confidenceLevel,
                       "ConfidenceReason": trimmedConfidenceReason,
                       "Steps": trimmedSteps, "TargetRole": requestTargetRole]
        let requestConfidenceLevel = confidenceLevel
        if !until.isEmpty { payload["ValidUntilOn"] = until }
        if !replacement.isEmpty { payload["ReplacesRecommendationId"] = replacement }
        let retry = pendingWriteRetryKey(
            scope: "\(userID):\(requestStoreID):\(requestRole):recommendation:create",
            payload: payload)
        busy = true; setMessage("")
        Task {
            defer { if isCurrentWorkspace(requestedWorkspace, token: requestToken) { busy = false } }
            do {
                let result = try await api.proposeRecommendation(storeID: requestStoreID, token: requestToken,
                    role: requestRole, sourceSubmissionID: requestSourceSubmissionID, title: trimmedTitle,
                    rationale: trimmedRationale, calculationBasis: trimmedCalculationBasis,
                    confidenceLevel: requestConfidenceLevel, confidenceReason: trimmedConfidenceReason,
                    steps: trimmedSteps, targetRole: requestTargetRole,
                    validUntilOn: until.isEmpty ? nil : until,
                    replacesRecommendationID: replacement.isEmpty ? nil : replacement,
                    idempotencyKey: retry.key)
                guard result.StoreId == requestStoreID, result.Mode == store.Mode else {
                    throw DineWiseDecisionTaskScopeError.mismatch
                }
                if isCurrentWorkspace(requestedWorkspace, token: requestToken) {
                    sourceID = ""; title = ""; rationale = ""; calculationBasis = ""
                    confidenceLevel = ""; confidenceReason = ""; steps = ""
                    validUntilOn = ""; replacesID = ""
                    isProposalFormExpanded = false
                    if await refreshAfterMutation(workspace: requestedWorkspace, token: requestToken,
                        successMessage: "建议已提交，等待老板决定。") {
                        clearPendingWriteRetryKey(retry)
                    }
                }
            } catch {
                if isCurrentWorkspace(requestedWorkspace, token: requestToken) {
                    let description = error.localizedDescription
                    if description.contains("来源资料已变化") || description.contains("建议已失效")
                        || description.contains("建议已变化") {
                        refresh()
                        setMessage("建议或依据资料刚刚变化，已同步刷新资料与建议；请重新核对后操作。",
                            isError: true)
                    } else {
                        setMessage(description, isError: true)
                    }
                }
            }
        }
    }

    private func decide(_ item: DineWiseRecommendation, action: String) {
        let requestedWorkspace = requestScopeKey
        let requestStoreID = store.Id
        let requestToken = token
        let requestRole = role
        let reason = (reasons[item.Id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let remindOn = action == "postpone" ? remindDates[item.Id] : nil
        let assignee = action == "confirm" ? assignees[item.Id] : nil
        let dueOn = action == "confirm" ? dueDates[item.Id] : nil
        var payload = ["Version": String(item.Version), "Action": action, "Reason": reason]
        if let remindOn, !remindOn.isEmpty { payload["RemindOn"] = remindOn }
        if let assignee, !assignee.isEmpty { payload["AssignedUserId"] = assignee }
        if let dueOn, !dueOn.isEmpty { payload["DueOn"] = dueOn }
        let retry = pendingWriteRetryKey(
            scope: "\(userID):\(requestStoreID):\(requestRole):\(item.Id):decision",
            payload: payload)
        busy = true; setMessage("")
        Task {
            defer { if isCurrentWorkspace(requestedWorkspace, token: requestToken) { busy = false } }
            do {
                let result = try await api.decideRecommendation(storeID: requestStoreID,
                    recommendationID: item.Id, token: requestToken, role: requestRole, version: item.Version,
                    action: action, reason: reason, remindOn: remindOn,
                    assignedUserID: assignee?.isEmpty == false ? assignee : nil,
                    dueOn: dueOn,
                    idempotencyKey: retry.key)
                guard result.Id == item.Id, result.StoreId == requestStoreID,
                      result.Mode == store.Mode else {
                    throw DineWiseDecisionTaskScopeError.mismatch
                }
                if isCurrentWorkspace(requestedWorkspace, token: requestToken) {
                    if await refreshAfterMutation(workspace: requestedWorkspace, token: requestToken,
                        successMessage: "老板决定已保存。") {
                        clearPendingWriteRetryKey(retry)
                    }
                }
            } catch {
                if isCurrentWorkspace(requestedWorkspace, token: requestToken) {
                    setMessage(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func createMeetingTask() {
        let requestedWorkspace = requestScopeKey
        let requestStoreID = store.Id
        let requestToken = token
        let target = meetingTargetRole
        let assignee = meetingAssignee.isEmpty ? nil : meetingAssignee
        let meetingOn = localDateString(meetingDate)
        let dueOn = meetingHasDueDate || assignee != nil ? localDateString(meetingDueDate) : nil
        let name = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = meetingSteps.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload = ["MeetingOn": meetingOn, "Title": name,
                       "Steps": detail, "TargetRole": target]
        if let assignee { payload["AssignedUserId"] = assignee }
        if let dueOn { payload["DueOn"] = dueOn }
        let retry = pendingWriteRetryKey(
            scope: "\(userID):\(requestStoreID):owner:meeting-task:create", payload: payload)
        busy = true; setMessage("")
        Task {
            defer { if isCurrentWorkspace(requestedWorkspace, token: requestToken) { busy = false } }
            do {
                let result = try await api.createMeetingTask(storeID: requestStoreID,
                    token: requestToken, role: "owner", meetingOn: meetingOn,
                    title: name, steps: detail, targetRole: target,
                    assignedUserID: assignee, dueOn: dueOn, idempotencyKey: retry.key)
                guard result.StoreId == requestStoreID, result.Mode == store.Mode else {
                    throw DineWiseDecisionTaskScopeError.mismatch
                }
                if isCurrentWorkspace(requestedWorkspace, token: requestToken),
                   await refreshAfterMutation(workspace: requestedWorkspace, token: requestToken,
                                              successMessage: "会议事项已创建。") {
                    meetingTitle = ""; meetingSteps = ""; meetingAssignee = ""
                    meetingHasDueDate = false
                    isMeetingFormExpanded = false
                    clearPendingWriteRetryKey(retry)
                }
            } catch {
                if isCurrentWorkspace(requestedWorkspace, token: requestToken) {
                    setMessage(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func localDateString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 1, parts.day ?? 1)
    }

    private func act(_ task: DineWiseTask, action: String) {
        let requestedWorkspace = requestScopeKey
        let requestStoreID = store.Id
        let requestToken = token
        let requestRole = role
        let note = action == "reschedule" ? ""
            : (taskNotes[task.Id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let assigning = action == "assign" || action == "reassign"
        let rescheduling = action == "reschedule"
        let assignee = assigning ? assignees[task.Id] : nil
        let dueOn = assigning ? (dueDates[task.Id].flatMap { $0.isEmpty ? nil : $0 } ?? task.DueOn)
            : rescheduling ? (dueDates[task.Id] ?? task.DueOn ?? "") : nil
        let escalationRule = assigning || rescheduling
            ? (escalationRules[task.Id] ?? task.EscalationRule ?? "owner_on_overdue") : nil
        let reviewDueOn = action == "complete" && task.SourceType != "meeting"
            ? reviewDueDates[task.Id] : nil
        var payload = ["Version": String(task.Version), "Action": action, "Note": note]
        if let assignee, !assignee.isEmpty { payload["AssignedUserId"] = assignee }
        if rescheduling { payload["DueOn"] = dueOn ?? "" }
        else if let dueOn, !dueOn.isEmpty { payload["DueOn"] = dueOn }
        if let escalationRule, !escalationRule.isEmpty { payload["EscalationRule"] = escalationRule }
        if let reviewDueOn, !reviewDueOn.isEmpty { payload["ReviewDueOn"] = reviewDueOn }
        let retry = pendingWriteRetryKey(
            scope: "\(userID):\(requestStoreID):\(requestRole):task:\(task.Id):action",
            payload: payload)
        busy = true; setMessage("")
        Task {
            defer { if isCurrentWorkspace(requestedWorkspace, token: requestToken) { busy = false } }
            do {
                let result = try await api.taskAction(storeID: requestStoreID, taskID: task.Id,
                    token: requestToken, role: requestRole, version: task.Version, action: action,
                    note: note, assignedUserID: assignee, dueOn: dueOn,
                    reviewDueOn: reviewDueOn, escalationRule: escalationRule, idempotencyKey: retry.key)
                guard result.Id == task.Id, result.StoreId == requestStoreID,
                      result.Mode == store.Mode else {
                    throw DineWiseDecisionTaskScopeError.mismatch
                }
                if action == "progress" { taskNotes[task.Id] = "" }
                if isCurrentWorkspace(requestedWorkspace, token: requestToken) {
                    if requestRole == "owner", task.SourceType == "meeting",
                       taskEventExpandedIDs.contains(task.Id) {
                        await reloadTaskEventHistory(task)
                    }
                    let refreshed = await refreshAfterMutation(workspace: requestedWorkspace, token: requestToken,
                        successMessage: "任务状态已更新。")
                    if refreshed {
                        clearPendingWriteRetryKey(retry)
                    }
                }
            } catch {
                if isCurrentWorkspace(requestedWorkspace, token: requestToken) {
                    setMessage(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func finishReview(_ review: DineWiseTaskReview) {
        let requestedWorkspace = requestScopeKey
        let requestStoreID = store.Id
        let requestToken = token
        let requestRole = role
        let task = tasks.first(where: { $0.Id == review.TaskId })
        let invalidated = review.SourceInvalidatedAt != nil || task?.SourceInvalidatedAt != nil
        let outcome = invalidated ? "insufficient" : (reviewOutcomes[review.Id] ?? "reviewed")
        let metricKey = outcome == "reviewed" ? (reviewMetricKeys[review.Id] ?? "revenue_yuan") : nil
        let beforeID = outcome == "reviewed" ? reviewBeforeIDs[review.Id] : nil
        let afterID = outcome == "reviewed" ? reviewAfterIDs[review.Id] : nil
        let confounders = invalidated ? "" : (reviewConfounders[review.Id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let conclusion = (reviewConclusions[review.Id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let nextStep = (reviewNextSteps[review.Id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var payload = ["Version": String(review.Version), "Outcome": outcome,
                       "Confounders": confounders, "Conclusion": conclusion,
                       "NextStep": nextStep]
        if let metricKey, !metricKey.isEmpty { payload["MetricKey"] = metricKey }
        if let beforeID, !beforeID.isEmpty { payload["BeforeSubmissionId"] = beforeID }
        if let afterID, !afterID.isEmpty { payload["AfterSubmissionId"] = afterID }
        let retry = pendingWriteRetryKey(
            scope: "\(userID):\(requestStoreID):\(requestRole):review:\(review.Id):result",
            payload: payload)
        busy = true; setMessage("")
        Task {
            defer { if isCurrentWorkspace(requestedWorkspace, token: requestToken) { busy = false } }
            do {
                let result = try await api.finishTaskReview(storeID: requestStoreID, reviewID: review.Id,
                    token: requestToken, role: requestRole, version: review.Version, outcome: outcome,
                    metricKey: metricKey, beforeSubmissionID: beforeID,
                    afterSubmissionID: afterID, confounders: confounders,
                    conclusion: conclusion, nextStep: nextStep, idempotencyKey: retry.key)
                guard result.Id == review.Id, result.StoreId == requestStoreID,
                      result.Mode == store.Mode else {
                    throw DineWiseDecisionTaskScopeError.mismatch
                }
                if isCurrentWorkspace(requestedWorkspace, token: requestToken) {
                    if await refreshAfterMutation(workspace: requestedWorkspace, token: requestToken,
                        successMessage: "复盘结果已保存。") {
                        clearPendingWriteRetryKey(retry)
                    }
                }
            } catch {
                if isCurrentWorkspace(requestedWorkspace, token: requestToken) {
                    setMessage(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func roleName(_ code: String) -> String {
        ["manager": "店长", "chef": "厨师长", "purchaser": "采购", "operator": "门店运营"][code] ?? code
    }

    private func isCurrentWorkspace(_ requestedWorkspace: String, token requestToken: String) -> Bool {
        workspace == requestedWorkspace && requestScopeKey == requestedWorkspace
            && token == requestToken
    }

    private func kindName(_ code: String) -> String {
        ["operating": "经营资料", "purchase": "采购资料", "kitchen": "后厨反馈", "operations": "运营反馈"][code] ?? code
    }

    private func recommendationStatus(_ code: String) -> String {
        ["pending_decision": "待老板决策", "confirmed": "已确认", "rejected": "已否决",
         "postponed": "稍后处理"][code] ?? "状态未知"
    }

    private func confidenceLabel(_ code: String?) -> String {
        ["low": "低", "medium": "中", "high": "高"][code ?? ""] ?? "未填写"
    }

    private func confidenceTint(_ code: String?) -> Color {
        switch code {
        case "low": DineWiseTheme.danger(for: colorScheme)
        case "medium": DineWiseTheme.gold(for: colorScheme)
        case "high": accent
        default: .secondary
        }
    }

    private func recommendationTint(_ code: String) -> Color {
        switch code {
        case "pending_decision": DineWiseTheme.gold(for: colorScheme)
        case "confirmed": accent
        case "rejected": DineWiseTheme.danger(for: colorScheme)
        default: .secondary
        }
    }

    private func taskStatusTint(_ code: String) -> Color {
        switch code {
        case "pending_assignment", "pending_execution", "pending_review": DineWiseTheme.gold(for: colorScheme)
        case "in_progress", "completed": accent
        default: .secondary
        }
    }

    private func reviewStatusTint(_ code: String) -> Color {
        switch code {
        case "due": DineWiseTheme.gold(for: colorScheme)
        case "reviewed": accent
        case "insufficient": DineWiseTheme.danger(for: colorScheme)
        default: .secondary
        }
    }

    private func setMessage(_ value: String, isError: Bool = false) {
        message = value
        messageIsError = isError
    }

    private func taskStatus(_ code: String) -> String {
        ["pending_assignment": "待分派", "pending_execution": "待执行",
         "in_progress": "执行中", "pending_review": "待老板复核",
         "completed": "已完成", "cancelled": "已取消"][code] ?? "状态未知"
    }

    private func taskNotificationAction(_ code: String) -> String {
        ["create": "有新的岗位会议事项", "assign": "老板指派了会议事项", "reassign": "会议事项负责人已调整",
         "reschedule": "会议事项期限已调整",
         "start": "负责人已开始执行", "progress": "负责人更新了阶段进度",
         "receipt": "负责人已提交回执",
         "complete": "老板已确认完成", "rework": "老板退回补充",
         "cancel": "会议事项已取消", "escalate": "负责人任务已逾期，提醒处理"][code] ?? "会议事项状态已更新"
    }

    private func taskEventActionLabel(_ code: String) -> String {
        ["create": "创建事项", "assign": "指派负责人", "reassign": "调整负责人", "reschedule": "调整期限",
         "start": "开始执行", "progress": "阶段进度", "receipt": "提交回执", "complete": "确认完成",
         "rework": "退回补充", "cancel": "取消事项", "escalate": "逾期提醒老板"][code] ?? "状态更新"
    }

    private func taskEventActorLabel(_ code: String) -> String {
        code == "owner" ? "老板" : code == "system" ? "系统" : roleName(code)
    }

    private func taskEventTime(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func reviewStatus(_ code: String) -> String {
        ["waiting_observation": "等待观察期", "due": "待复盘",
         "reviewed": "已复盘", "insufficient": "资料不足"][code] ?? "状态未知"
    }

    private func reviewMetricName(_ code: String?) -> String {
        ["revenue_yuan": "营业额", "orders": "订单数", "tables": "桌数",
         "purchase_quantity": "采购数量", "unit_price_yuan_per_kg": "采购单价",
         "outcome_quantity": "剩余数量"][code ?? ""] ?? "对照指标"
    }

    private func reviewMetricUnit(_ metric: String?, unit: String?) -> String {
        switch (metric, unit) {
        case ("revenue_yuan", "yuan"): "元"
        case ("orders", "count"): "单"
        case ("tables", "count"): "桌"
        case ("purchase_quantity", "kg"): "公斤"
        case ("unit_price_yuan_per_kg", "yuan/kg"): "元/公斤"
        case ("outcome_quantity", "portion"): "份"
        case ("outcome_quantity", "piece"): "个"
        case ("outcome_quantity", "kg"): "公斤"
        default: unit ?? ""
        }
    }

    private func invalidationName(_ code: String?) -> String {
        ["source_withdrawn": "来源资料已撤回", "source_changed": "来源资料已变化",
         "expired": "建议已到期", "superseded": "建议已被新版替代"][code ?? ""] ?? "关联建议已失效"
    }
}

private extension View {
    func dineWiseCard() -> some View {
        padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }
}
