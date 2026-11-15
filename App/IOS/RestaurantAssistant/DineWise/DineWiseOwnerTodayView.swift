import SwiftUI

struct DineWiseOwnerTodayView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    let store: DineWiseStore
    let token: String
    let onOpen: (String, DineWiseOwnerTodayItem?, String?) -> Void

    private let api = DineWiseAPI()
    @State private var records: [DineWiseOwnerTodayItem] = []
    @State private var loading = true
    @State private var refreshInFlight = false
    @State private var error = ""
    @State private var requestGeneration = 0
    @State private var yesterday: DineWiseDailyReport?
    @State private var taskProgress: [DineWiseOwnerTodayRoleProgress] = []
    @State private var pendingSubmissionReviewCount: Int?
    @State private var meetingProgress: DineWiseMeetingProgressSummary?
    @State private var hasMoreItems = false

    private struct TodayItem: Identifiable {
        let id: String
        let record: DineWiseOwnerTodayItem
        let label: String
        let title: String
        let detail: String
    }

    private var items: [TodayItem] {
        records.prefix(6).compactMap { item in
            let presentation: (String, String)? = switch item.type {
            case "escalated_task": ("逾期", "已提醒老板，请重新指派或处理")
            case "pending_assignment": ("分派", "等待老板指定执行人")
            case "due_decision": ("提醒", "稍后处理的建议已到提醒日期，请重新决策")
            case "pending_decision": ("决策", "等待确认、否决或稍后处理")
            case "pending_review": ("复核", "执行人已提交回执，等待老板复核")
            case "due_review": ("复盘", "观察期已到，请按实际资料记录结果")
            case "invalidated_task": ("需确认", "关联资料已失效，请重新确认任务")
            default: nil
            }
            guard let presentation else { return nil }
            return TodayItem(id: "\(item.type)-\(item.Id)", record: item, label: presentation.0,
                             title: item.Title, detail: presentation.1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今天先处理什么").font(.headline)
                Spacer()
                if !loading && error.isEmpty {
                    Text("待办 \(records.count)\(hasMoreItems ? "+" : "")")
                        .font(.caption.weight(.semibold)).foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(DineWiseTheme.accent(for: colorScheme).opacity(0.09), in: Capsule())
                }
                Button("刷新") { Task { await refresh() } }.disabled(loading || refreshInFlight)
            }
            Text("优先展示逾期、待分派、到期提醒、待决策、待复核和到期复盘，最多 6 项；更多记录可到建议与任务中查看。")
                .font(.subheadline).foregroundStyle(.secondary)
            if loading { ProgressView("正在加载待办…") }
            if !error.isEmpty {
                Text(error).font(.footnote).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
            }
            if !loading && error.isEmpty && items.isEmpty {
                Text("当前没有待办，可继续查看建议与任务。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !loading && error.isEmpty {
                ForEach(items) { item in
                    Button { onOpen("suggestions", item.record, nil) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(item.label).font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color(red: 0.12, green: 0.29, blue: 0.23), in: Capsule())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.subheadline.bold()).foregroundStyle(.primary)
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                }
            }
            yesterdaySummary
            pendingSubmissionSummary
            roleProgressSummary
            meetingProgressSummary
            HStack {
                Button("查看建议与任务") { onOpen("suggestions", nil, nil) }
                Button("经营报告") { onOpen("report", nil, nil) }
                Button("核对资料") { onOpen("materials", nil, nil) }
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .task(id: "\(store.Id):\(store.Mode):\(token):\(scenePhase)") {
            guard scenePhase == .active else { return }
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                if scenePhase == .active { await refresh(silent: true) }
            }
        }
    }

    private func refresh(silent: Bool = false) async {
        if silent && refreshInFlight { return }
        let requestedStoreID = store.Id
        let requestedMode = store.Mode
        let requestedToken = token
        requestGeneration += 1
        let requestedGeneration = requestGeneration
        refreshInFlight = true
        defer {
            if requestGeneration == requestedGeneration {
                refreshInFlight = false
                if !silent { loading = false }
            }
        }
        if !silent {
            loading = true
            error = ""
            records = []
            hasMoreItems = false
            yesterday = nil
            taskProgress = []
            pendingSubmissionReviewCount = nil
            meetingProgress = nil
        }
        do {
            let response = try await api.ownerToday(storeID: requestedStoreID, token: requestedToken)
            try Task.checkCancellation()
            guard requestGeneration == requestedGeneration,
                  store.Id == requestedStoreID, store.Mode == requestedMode,
                  token == requestedToken else { return }
            guard response.StoreId == requestedStoreID else {
                throw DineWiseAPIError.failed("门店待办不匹配，请刷新后重试。")
            }
            guard response.Mode == requestedMode else {
                throw DineWiseAPIError.failed("门店数据范围不匹配，请刷新后重试。")
            }
            error = ""
            let progress = response.TaskProgress ?? []
            let progressRoles = progress.map(\.Role)
            guard progress.allSatisfy({ !$0.Role.isEmpty && $0.TotalCount > 0
                && $0.CompletedCount >= 0 && $0.CompletedCount <= $0.TotalCount })
                && Set(progressRoles).count == progressRoles.count
                && (response.PendingSubmissionReviewCount.map { $0 >= 0 } ?? true) else {
                throw DineWiseAPIError.failed("今日摘要计数异常，请刷新后重试。")
            }
            let meetingSummary = response.MeetingProgress
            if let meeting = meetingSummary {
                let counts = [meeting.PendingAssignmentCount, meeting.PendingExecutionCount,
                    meeting.InProgressCount, meeting.PendingReviewCount,
                    meeting.CompletedCount, meeting.CancelledCount]
                guard meeting.TotalCount >= 0 && meeting.OverdueCount >= 0
                    && meeting.OverdueCount <= meeting.TotalCount
                    && counts.allSatisfy({ $0 >= 0 && $0 <= meeting.TotalCount })
                    && counts.reduce(0, +) == meeting.TotalCount else {
                    throw DineWiseAPIError.failed("本周会议事项汇总异常，请刷新后重试。")
                }
            }
            if let daily = response.Yesterday {
                guard daily.StoreId == requestedStoreID, daily.Mode == requestedMode else {
                    throw DineWiseAPIError.failed("昨日经营摘要与当前门店不匹配，请刷新后重试。")
                }
                yesterday = daily
            }
            taskProgress = progress
            pendingSubmissionReviewCount = response.PendingSubmissionReviewCount
            meetingProgress = meetingSummary
            records = response.Items
            hasMoreItems = response.HasMoreItems == true
        } catch is CancellationError {
            return
        } catch {
            guard requestGeneration == requestedGeneration,
                  store.Id == requestedStoreID, store.Mode == requestedMode,
                  token == requestedToken else { return }
            if !silent { self.error = error.localizedDescription }
        }
    }

    private var yesterdaySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("昨日关键数字").font(.headline)
                Spacer()
                Text(yesterdayStatus).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            if loading {
                Text("正在读取昨日经营资料…")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if !error.isEmpty {
                Text("昨日经营摘要暂不可用，请刷新重试。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if let yesterday, yesterday.ConfirmedOperatingCount == 1 {
                HStack(alignment: .top, spacing: 8) {
                    summaryMetric("营业额", amount(yesterday.RevenueYuan))
                    summaryMetric("桌数", count(yesterday.Tables, unit: "桌"))
                    summaryMetric("桌均", amount(yesterday.RevenuePerTableYuan))
                }
                Text("仅展示已确认经营资料；缺项以“—”表示，不估算成本或利润。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text((yesterday?.ConfirmedOperatingCount ?? 0) > 1
                     ? "昨日有多份已确认经营资料，请先在经营报告核对来源；此处不会重复相加。"
                     : "昨日暂无已确认经营资料，确认后会在此显示营业额、桌数和桌均。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var yesterdayStatus: String {
        guard let yesterday else {
            if loading { return "读取中" }
            return error.isEmpty ? "暂无数据" : "读取失败"
        }
        switch yesterday.ConfirmedOperatingCount {
        case 0: return "待资料确认"
        case 1: return "已确认 · \(yesterday.BusinessDate)"
        default: return "多份来源待核对"
        }
    }

    private var roleProgressSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("岗位完成情况").font(.headline)
                Spacer()
                Text("今日截止任务").font(.caption).foregroundStyle(.secondary)
            }
            if loading {
                Text("正在读取岗位任务…")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if !error.isEmpty {
                Text("岗位任务暂不可用，请刷新重试。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if taskProgress.isEmpty {
                Text("今天没有已指派且截止的岗位任务。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 7) {
                    ForEach(taskProgress) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(item.CompletedCount)/\(item.TotalCount)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .lineLimit(1).minimumScaleFactor(0.75)
                            Text(roleName(item.Role)).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("只统计来源有效、已指派且今天截止的任务；待老板复核仍计为未完成。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var meetingProgressSummary: some View {
        Button { onOpen("suggestions", nil, nil) } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("本周会议事项").font(.headline).foregroundStyle(.primary)
                    if let meetingProgress {
                        Text(meetingProgress.TotalCount == 0
                             ? "\(meetingProgress.WeekStartOn) 至 \(meetingProgress.WeekEndOn) · 暂无事项"
                             : "\(meetingProgress.WeekStartOn) 至 \(meetingProgress.WeekEndOn) · 已完成 \(meetingProgress.CompletedCount)，未完成 \(meetingProgress.TotalCount - meetingProgress.CompletedCount - meetingProgress.CancelledCount)，已取消 \(meetingProgress.CancelledCount)")
                            .font(.caption).foregroundStyle(.secondary)
                        if meetingProgress.OverdueCount > 0 || meetingProgress.PendingReviewCount > 0 {
                            Text("其中逾期 \(meetingProgress.OverdueCount) 项 · 等待老板复核 \(meetingProgress.PendingReviewCount) 项")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(loading ? "正在读取周会进度…" : "周会进度暂不可用，可进入建议与任务查看。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Text("查看").font(.caption.weight(.semibold))
                    .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var pendingSubmissionSummary: some View {
        Button { onOpen("materials", nil, "pending_review") } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("待核对资料").font(.headline).foregroundStyle(.primary)
                    Text(pendingSubmissionDetail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(pendingSubmissionReviewCount.map(String.init) ?? (loading ? "读取中" : "—"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开资料页核对待确认资料")
    }

    private var pendingSubmissionDetail: String {
        guard let pendingSubmissionReviewCount else {
            if loading { return "正在读取核对数量…" }
            if !error.isEmpty { return "核对数量暂不可用，请刷新重试。" }
            return "当前服务未返回核对数量，可打开资料页查看。"
        }
        return pendingSubmissionReviewCount == 0
            ? "目前没有等待人工核对的资料。"
            : "有 \(pendingSubmissionReviewCount) 份资料等待人工核对。"
    }

    private func roleName(_ code: String) -> String {
        switch code {
        case "chef": return "厨师长"
        case "purchaser": return "采购"
        case "operator": return "运营"
        case "manager": return "店长"
        default: return code
        }
    }

    private func summaryMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 19, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.72)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(DineWiseTheme.inset, in: RoundedRectangle(cornerRadius: 13))
    }

    private func amount(_ value: Decimal?) -> String {
        value.map { $0.formatted(.currency(code: "CNY").locale(Locale(identifier: "zh_CN"))) } ?? "—"
    }

    private func count(_ value: Int?, unit: String) -> String {
        value.map { "\($0)\(unit)" } ?? "—"
    }
}
