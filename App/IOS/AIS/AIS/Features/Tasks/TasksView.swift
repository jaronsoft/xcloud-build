import Observation
import SwiftUI

struct TasksView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AISAppDataStore.self) private var appData
    let model: TasksViewModel
    let onContinueEditing: (AISTaskJob) -> Void
    @State private var presentsLogin = false
    @State private var selectedTask: AISTaskJob?
    @State private var sortOrder = TaskSortOrder.newestFirst

    var body: some View {
        ZStack {
            AISPageBackground()

            if session.isRestoring {
                ProgressView("common.loading")
                    .tint(AISTheme.accentSecondary)
            } else if !session.isAuthenticated {
                signedOutContent
            } else if model.isInitialLoading {
                ProgressView("tasks.loading")
                    .tint(AISTheme.accentSecondary)
            } else {
                taskContent
            }
        }
        .navigationTitle("tab.tasks")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $presentsLogin) {
            LoginView()
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(
                job: task,
                estimateSeconds: appData.durationEstimates.seconds(
                    for: task.jobType
                ),
                onDeleted: {
                    Task {
                        await model.load(
                            session: session,
                            showsLoading: false,
                            force: true
                        )
                    }
                },
                onContinueEditing: onContinueEditing
            )
        }
    }

    private var signedOutContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(AISTheme.auroraGradient)
                .frame(width: 88, height: 88)
                .background(AISTheme.accent.opacity(0.08), in: Circle())
            Text("tasks.signin.title")
                .font(.title2.bold())
            Text("tasks.signin.subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                presentsLogin = true
            } label: {
                Text("account.signin")
                    .aisPrimaryButton()
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 420)
        .padding(24)
    }

    private var taskContent: some View {
        GeometryReader { proxy in
            ScrollView {
                taskLayout(availableSize: proxy.size)
            }
            .refreshable {
                await model.load(
                    session: session,
                    showsLoading: false,
                    force: true
                )
            }
        }
    }

    private func taskLayout(availableSize: CGSize) -> some View {
        let columnCount = AISResponsiveLayout.taskColumns(for: availableSize)
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
            count: columnCount
        )

        return LazyVStack(spacing: 14) {
            summary

            if let errorMessage = model.errorMessage,
               model.tasks.isEmpty {
                errorState(errorMessage)
            } else if model.tasks.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(sortedTasks) { task in
                        AISTaskCard(
                            task: task,
                            estimateSeconds: appData.durationEstimates.seconds(
                                for: task.jobType
                            ),
                            onOpen: { selectedTask = task }
                        )
                    }
                }
            }
        }
        .frame(
            maxWidth: AISResponsiveLayout.taskMaximumContentWidth(
                for: availableSize
            )
        )
        .padding(
            .horizontal,
            AISResponsiveLayout.horizontalPadding(for: availableSize.width)
        )
        .padding(.top, 10)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
    }

    private var sortedTasks: [AISTaskJob] {
        model.tasks.sorted { lhs, rhs in
            guard lhs.id != rhs.id else { return false }
            return sortOrder == .newestFirst
                ? lhs.isNewer(than: rhs)
                : rhs.isNewer(than: lhs)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("tasks.title")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("tasks.subtitle")
                        .font(.subheadline)
                        .foregroundStyle(AISTheme.muted)
                }
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    if model.hasActiveTasks {
                        ProgressView()
                            .tint(AISTheme.accentSecondary)
                    }
                    Menu {
                        Picker("tasks.sort.title", selection: $sortOrder) {
                            ForEach(TaskSortOrder.allCases) { order in
                                Label(order.title, systemImage: order.icon)
                                    .tag(order)
                            }
                        }
                    } label: {
                        Label(sortOrder.title, systemImage: sortOrder.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AISTheme.accentSecondary)
                    }
                    .buttonStyle(.bordered)
                    .tint(AISTheme.accentSecondary)
                    .accessibilityLabel("tasks.sort.title")
                }
            }

            HStack(spacing: 10) {
                TaskMetric(
                    value: model.activeCount,
                    title: "tasks.metric.active",
                    color: AISTheme.accent
                )
                TaskMetric(
                    value: model.completedCount,
                    title: "tasks.metric.completed",
                    color: Color(red: 0.18, green: 0.55, blue: 0.32)
                )
                TaskMetric(
                    value: model.tasks.count,
                    title: "tasks.metric.total",
                    color: AISTheme.accentWarm
                )
            }
        }
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AISTheme.line.opacity(0.55), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars.inverse")
                .font(.system(size: 34))
                .foregroundStyle(AISTheme.accentSecondary)
            Text("tasks.empty")
                .font(.headline)
            Text("tasks.empty.subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .aisSurface(cornerRadius: 24)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(AISTheme.accentWarm)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("templates.retry") {
                Task {
                    await model.load(session: session, showsLoading: true)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AISTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 20)
        .aisSurface(cornerRadius: 24)
    }
}

@MainActor
@Observable
final class TasksViewModel {
    private let api = APIClient()
    private(set) var tasks: [AISTaskJob] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasLoadedTasks = false
    private var isRequesting = false

    /// 首次请求尚未完成时保持加载态，避免凭据恢复期间误展示空任务页。
    var isInitialLoading: Bool {
        tasks.isEmpty && !hasLoadedTasks
    }

    var hasActiveTasks: Bool {
        tasks.contains(where: \.isActive)
    }

    var activeCount: Int {
        tasks.filter(\.isActive).count
    }

    var completedCount: Int {
        tasks.count {
            $0.status.lowercased() == "succeeded"
                || $0.status.lowercased() == "completed"
        }
    }

    func load(
        session: SessionStore,
        showsLoading: Bool,
        force: Bool = false
    ) async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        guard let accessToken = await session.validAccessToken() else {
            reset()
            return
        }
        if showsLoading {
            isLoading = true
        }
        defer { isLoading = false }

        let userID = session.user?.id ?? "unknown"
        let cacheKey = AISResponseCache.key(
            scope: "user:\(userID)",
            resource: "tasks-v2",
            parameters: ["group": "media", "page": "1", "size": "30"]
        )
        if !force,
           let cached = await AISResponseCache.shared.read(
               PageResponse<AISTaskJob>.self,
               key: cacheKey,
               allowsStale: true
           ) {
            if tasks != cached.value.items {
                tasks = cached.value.items
            }
            hasLoadedTasks = true
            if cached.isFresh && !hasActiveTasks {
                errorMessage = nil
                return
            }
        }

        do {
            let page: PageResponse<AISTaskJob> = try await api.get(
                "/api/ais/jobs",
                query: [
                    URLQueryItem(name: "page", value: "1"),
                    URLQueryItem(name: "size", value: "30"),
                    URLQueryItem(name: "jobGroup", value: "media"),
                    URLQueryItem(name: "includeTotal", value: "false"),
                    URLQueryItem(name: "summaryOnly", value: "true")
                ],
                accessToken: accessToken
            )
            if tasks != page.items {
                tasks = page.items
            }
            hasLoadedTasks = true
            await AISResponseCache.shared.write(page, key: cacheKey)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            hasLoadedTasks = true
            errorMessage = error.localizedDescription
        }
    }

    /// 使用 Redis 优先的轻量状态接口更新指定任务，返回任务是否已进入终态。
    func refreshStatus(
        session: SessionStore,
        jobID: String
    ) async -> Bool {
        guard let accessToken = await session.validAccessToken() else {
            return false
        }
        do {
            let snapshot: AISTaskStatusSnapshot = try await api.get(
                "/api/ais/jobs/\(jobID)/status",
                accessToken: accessToken
            )
            if let index = tasks.firstIndex(where: { $0.id == jobID }) {
                tasks[index].status = snapshot.status
                tasks[index].progress = snapshot.progress
                tasks[index].errorMessage =
                    snapshot.errorMessage ?? tasks[index].errorMessage
                tasks[index].startedAt =
                    snapshot.startedAt ?? tasks[index].startedAt
                tasks[index].finishedAt =
                    snapshot.finishedAt ?? tasks[index].finishedAt
                if let resultAssetID = snapshot.resultAssetID {
                    tasks[index].resultAssetId = resultAssetID
                }
                if let resultURL = snapshot.resultURL {
                    tasks[index].resultURL = resultURL
                }
            }
            return !Self.isActiveStatus(snapshot.status)
        } catch is CancellationError {
            return false
        } catch {
            // 单次状态读取失败保留现有任务状态，下一轮继续尝试。
            return false
        }
    }

    var activeJobIDs: [String] {
        tasks.filter(\.isActive).map(\.id)
    }

    private static func isActiveStatus(_ status: String) -> Bool {
        switch status.lowercased() {
        case "queued", "pending", "processing", "running":
            true
        default:
            false
        }
    }

    func reset() {
        tasks = []
        isLoading = false
        errorMessage = nil
        hasLoadedTasks = false
    }
}

private enum TaskSortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .newestFirst: "tasks.sort.newest"
        case .oldestFirst: "tasks.sort.oldest"
        }
    }

    var icon: String {
        switch self {
        case .newestFirst: "arrow.down"
        case .oldestFirst: "arrow.up"
        }
    }
}

private struct TaskMetric: View {
    let value: Int
    let title: LocalizedStringKey
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value, format: .number)
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            AISTheme.line.opacity(0.13),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }
}

private struct AISTaskCard: View {
    let task: AISTaskJob
    let estimateSeconds: Int?
    let onOpen: () -> Void

    private var status: AISTaskStatus {
        AISTaskStatus(rawValue: task.status)
    }

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    thumbnail

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Label(jobTypeTitle, systemImage: jobTypeIcon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AISTheme.muted)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(status.title)
                                .font(.caption2.bold())
                                .foregroundStyle(status.textColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(status.fillColor, in: Capsule())
                        }

                        Text(displayTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AISTheme.accentSecondary)
                            .lineLimit(2)

                        statusContent
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.formattedCreationTime)
                    Text(
                        String(
                            format: String(localized: "tasks.number"),
                            task.id
                        )
                    )
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .textSelection(.enabled)
                }
                Spacer()
                if task.pointCost > 0 {
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "tasks.points"),
                            task.pointCost
                        )
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(AISTheme.muted)
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AISTheme.line.opacity(0.5), lineWidth: 1)
        }
        .accessibilityAction(named: Text("tasks.detail.title"), onOpen)
    }

    @ViewBuilder
    private var statusContent: some View {
        if task.isActive {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    ProgressView(value: Double(task.progress), total: 100)
                        .tint(status.color)
                    Text("\(task.progress)%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(status.textColor)
                }
                if AISTaskDurationPresentation.isQueued(task.status) {
                    Text("tasks.queued")
                        .font(.caption2)
                        .foregroundStyle(AISTheme.muted)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let remainingText = remainingText(at: context.date) {
                            Text(remainingText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(AISTheme.muted)
                        }
                    }
                }
            }
        } else if status == .failed, let message = task.errorMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(AISTheme.muted)
                .lineLimit(2)
        } else if status == .succeeded {
            Group {
                if let requirement = task.userRequirement.nilIfEmpty {
                    Text(requirement)
                } else {
                    Text(status.helper)
                }
            }
            .font(.caption)
            .foregroundStyle(AISTheme.muted)
            .lineLimit(2)
            .frame(minHeight: 32, alignment: .topLeading)
        } else {
            HStack(spacing: 5) {
                Image(systemName: status.icon)
                Text(status.helper)
            }
            .font(.caption)
            .foregroundStyle(status.textColor)
        }
    }

    private var thumbnail: some View {
        AISCachedAsyncImage(
            url: task.mediaURL,
            preset: .thumbnail,
            module: .tasks
        ) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            default:
                ZStack {
                    Color(uiColor: .tertiarySystemGroupedBackground)
                    Image(systemName: jobTypeIcon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AISTheme.muted)
                }
            }
        }
        .frame(width: 88, height: 88)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(AISTheme.line.opacity(0.65), lineWidth: 1)
        }
    }

    private var displayTitle: String {
        let value = task.title.isEmpty ? task.userRequirement : task.title
        return value.isEmpty ? jobTypeTitle : value
    }

    private func remainingText(at date: Date) -> String? {
        switch AISTaskDurationPresentation.resolve(
            status: task.status,
            startedAt: task.startedDate,
            estimateSeconds: estimateSeconds,
            now: date
        ) {
        case let .remaining(seconds):
            return String.localizedStringWithFormat(
                String(localized: "tasks.remaining"),
                AISDurationTextFormatter.countdown(seconds: seconds)
            )
        case .overdue:
            return String(localized: "tasks.estimate.overdue")
        case .queued:
            return String(localized: "tasks.queued")
        case .unavailable:
            return nil
        }
    }

    private var jobTypeTitle: String {
        switch task.jobType.lowercased() {
        case "image_generate":
            String(localized: "tasks.type.image")
        case "image_edit":
            String(localized: "tasks.type.edit")
        case "style_template_generate":
            String(localized: "tasks.type.template")
        case "video_generate":
            String(localized: "tasks.type.video")
        default:
            String(localized: "tasks.type.other")
        }
    }

    private var jobTypeIcon: String {
        switch task.jobType.lowercased() {
        case "image_edit":
            "slider.horizontal.3"
        case "style_template_generate":
            "rectangle.grid.2x2"
        case "video_generate":
            "play.rectangle"
        default:
            "photo.on.rectangle.angled"
        }
    }
}

enum AISTaskDurationPresentation: Equatable {
    case queued
    case remaining(Int)
    case overdue
    case unavailable

    static func isQueued(_ status: String) -> Bool {
        ["queued", "pending"].contains(status.lowercased())
    }

    static func resolve(
        status: String,
        startedAt: Date?,
        estimateSeconds: Int?,
        now: Date
    ) -> Self {
        if isQueued(status) {
            return .queued
        }
        guard ["processing", "running"].contains(status.lowercased()),
              let startedAt,
              let estimateSeconds,
              estimateSeconds > 0 else {
            return .unavailable
        }
        let remaining = Int(
            startedAt
                .addingTimeInterval(TimeInterval(estimateSeconds))
                .timeIntervalSince(now)
        )
        return remaining > 0 ? .remaining(remaining) : .overdue
    }
}

private enum AISTaskStatus: Equatable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
    case unknown

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "queued", "pending":
            self = .queued
        case "processing", "running":
            self = .running
        case "succeeded", "completed":
            self = .succeeded
        case "failed":
            self = .failed
        case "cancelled", "canceled":
            self = .cancelled
        default:
            self = .unknown
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .queued: "tasks.status.queued"
        case .running: "tasks.status.running"
        case .succeeded: "tasks.status.succeeded"
        case .failed: "tasks.status.failed"
        case .cancelled: "tasks.status.cancelled"
        case .unknown: "tasks.status.unknown"
        }
    }

    var helper: LocalizedStringKey {
        switch self {
        case .succeeded: "tasks.completed.helper"
        case .failed: "tasks.failed.helper"
        case .cancelled: "tasks.cancelled.helper"
        default: "tasks.processing.helper"
        }
    }

    var icon: String {
        switch self {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        case .queued: "clock.fill"
        case .running: "sparkles"
        case .unknown: "circle.dotted"
        }
    }

    var color: Color {
        switch self {
        case .queued:
            Color(red: 0.55, green: 0.38, blue: 0.08)
        case .running:
            Color(red: 0.10, green: 0.38, blue: 0.62)
        case .succeeded:
            Color(red: 0.05, green: 0.48, blue: 0.27)
        case .failed:
            Color(red: 0.72, green: 0.16, blue: 0.18)
        case .cancelled, .unknown:
            AISTheme.muted
        }
    }

    var textColor: Color { color }

    var fillColor: Color {
        color.opacity(0.11)
    }
}

#Preview("TasksView") {
    NavigationStack {
        TasksView(model: TasksViewModel()) { _ in }
    }
    .environment(SessionStore())
}
