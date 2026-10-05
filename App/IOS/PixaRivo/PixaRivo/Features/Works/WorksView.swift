import SwiftUI

private enum WorksSortOrder: String {
    case newest
    case oldest
}

private struct WorksPage: Sendable {
    let items: [TaskJob]
    let total: Int
}

@MainActor @Observable
private final class WorksStore {
    private let api = APIClient()
    private let pageSize = 30

    var items: [TaskJob] = []
    var total = 0
    var isLoading = false
    var isLoadingMore = false
    var loadMoreError: String?
    var errorMessage: String?
    private var loadedPage = 0
    private var reachedEnd = false
    private var reloadRevision = 0
    private var reloadTask: Task<WorksPage, Error>?
    private var lastPullRefreshAt: Date?

    var hasMore: Bool { !reachedEnd && items.count < total }

    func refreshFromPull(session: SessionStore) async {
        let now = Date.now
        guard !isLoading, !isLoadingMore else { return }
        if let lastPullRefreshAt, now.timeIntervalSince(lastPullRefreshAt) < 2 {
            return
        }
        lastPullRefreshAt = now
        await reload(session: session, forceRefresh: true)
    }

    func reload(session: SessionStore, forceRefresh: Bool = false) async {
        reloadRevision += 1
        let revision = reloadRevision
        reloadTask?.cancel()
        isLoading = true
        defer {
            if revision == reloadRevision {
                reloadTask = nil
                isLoading = false
            }
        }
        guard let userID = session.user?.id else {
            reset()
            return
        }
        if !forceRefresh {
            if !items.isEmpty { return }
            if let cached = await cachedPage(userID: userID) {
                guard revision == reloadRevision, !Task.isCancelled else { return }
                applyFirstPage(cached, preservingExisting: false)
                errorMessage = nil
                return
            }
        }
        guard let token = await session.validAccessToken() else {
            guard revision == reloadRevision else { return }
            if session.isAuthenticated {
                errorMessage = AppLanguage.localized("auth.session_refresh_failed")
            } else {
                reset()
            }
            return
        }
        guard revision == reloadRevision, !Task.isCancelled else { return }
        let requestTask = Task {
            try await page(
                1,
                token: token,
                userID: userID,
                forceRefresh: forceRefresh
            )
        }
        reloadTask = requestTask
        do {
            let response = try await withTaskCancellationHandler {
                try await requestTask.value
            } onCancel: {
                requestTask.cancel()
            }
            guard !Task.isCancelled, revision == reloadRevision else { return }
            applyFirstPage(response, preservingExisting: !items.isEmpty)
            loadMoreError = nil
            errorMessage = nil
        } catch {
            guard revision == reloadRevision, !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadNextPage(session: SessionStore) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }

        let revision = reloadRevision
        guard let userID = session.user?.id else { return }
        guard let token = await session.validAccessToken() else {
            if session.isAuthenticated {
                loadMoreError = AppLanguage.localized("auth.session_refresh_failed")
            }
            return
        }
        do {
            let nextPage = loadedPage + 1
            let response = try await page(nextPage, token: token, userID: userID)
            guard !Task.isCancelled, revision == reloadRevision else { return }
            let existingIDs = Set(items.map(\.id))
            items.append(contentsOf: response.items.filter { !existingIDs.contains($0.id) })
            total = response.total
            loadedPage = nextPage
            reachedEnd = response.items.count < pageSize || items.count >= total
        } catch {
            guard revision == reloadRevision, !Self.isCancellation(error) else { return }
            loadMoreError = error.localizedDescription
        }
    }

    private func page(
        _ page: Int,
        token: String,
        userID: String,
        forceRefresh: Bool = false
    ) async throws -> WorksPage {
        let response: PageResponse<TaskJob> = try await api.getCached(
            "/api/ais/jobs",
            query: pageQuery(page),
            token: token,
            forceRefresh: forceRefresh,
            cacheScope: "works-user-\(userID)"
        )
        return WorksPage(items: response.items, total: response.total)
    }

    private func cachedPage(userID: String) async -> WorksPage? {
        guard let response: PageResponse<TaskJob> = await api.cachedValue(
            PageResponse<TaskJob>.self,
            path: "/api/ais/jobs",
            query: pageQuery(1),
            cacheScope: "works-user-\(userID)"
        ) else { return nil }
        return WorksPage(items: response.items, total: response.total)
    }

    private func pageQuery(_ page: Int) -> [URLQueryItem] {
        [
            .init(name: "page", value: String(page)),
            .init(name: "size", value: String(pageSize)),
            .init(name: "jobType", value: "style_template_generate"),
            .init(name: "includeTotal", value: "true"),
            .init(name: "summaryOnly", value: "true")
        ]
    }

    private func applyFirstPage(
        _ response: WorksPage,
        preservingExisting: Bool
    ) {
        if preservingExisting {
            let refreshedIDs = Set(response.items.map(\.id))
            let retainedItems = items.filter { !refreshedIDs.contains($0.id) }
            let merged = response.items + retainedItems
            items = Array(merged.prefix(max(response.total, response.items.count)))
            loadedPage = max(1, loadedPage)
        } else {
            items = response.items
            loadedPage = 1
        }
        total = response.total
        reachedEnd = response.items.count < pageSize || items.count >= total
    }

    func mergeTrackedJobs(_ jobs: [TaskJob]) {
        guard !jobs.isEmpty else { return }
        var merged = items
        for job in jobs {
            if let index = merged.firstIndex(where: { $0.id == job.id }) {
                merged[index] = job
            } else {
                merged.insert(job, at: 0)
                total += 1
            }
        }
        items = merged
        errorMessage = nil
    }

    private func reset() {
        items = []
        total = 0
        loadedPage = 0
        reachedEnd = false
        loadMoreError = nil
        errorMessage = nil
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    func remove(id: String) {
        let originalCount = items.count
        items.removeAll { $0.id == id }
        if items.count < originalCount {
            total = max(0, total - 1)
        }
    }
}
struct WorksView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PixaNavigationStore.self) private var navigation
    @Environment(PixaWorkActivityStore.self) private var workActivity
    @Environment(PixaCreationSubmissionStore.self) private var creationSubmissions
    @Environment(PixaMediaRegionStore.self) private var mediaRegion
    @Environment(PixaDurationEstimateStore.self) private var durationEstimates
    @State private var store = WorksStore()
    @State private var showsLogin = false
    @AppStorage("pixarivo.works.sort_order") private var storedSortOrder = WorksSortOrder.newest.rawValue

    private var sortOrder: WorksSortOrder {
        WorksSortOrder(rawValue: storedSortOrder) ?? .newest
    }

    private var sortOrderLabel: LocalizedStringKey {
        sortOrder == .newest ? "works.sort.newest" : "works.sort.oldest"
    }

    private var sortedItems: [TaskJob] {
        store.items.sorted { lhs, rhs in
            switch sortOrder {
            case .newest:
                rhs.isCreated(before: lhs)
            case .oldest:
                lhs.isCreated(before: rhs)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                compactHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                Group {
                    if !session.isAuthenticated {
                        ContentUnavailableView {
                            Label("works.signin.title", systemImage: "person.crop.circle")
                        } description: {
                            Text("works.signin.message")
                        } actions: {
                            Button("auth.login") { showsLogin = true }
                                .buttonStyle(.borderedProminent)
                                .tint(PixaTheme.ink)
                        }
                    } else if store.isLoading && store.items.isEmpty
                                && creationSubmissions.items.isEmpty
                                && workActivity.pendingWorkPlaceholders.isEmpty {
                        WorksLoadingSkeleton()
                    } else if store.items.isEmpty,
                              creationSubmissions.items.isEmpty,
                              workActivity.pendingWorkPlaceholders.isEmpty,
                              let error = store.errorMessage {
                        ContentUnavailableView {
                            Label("works.load_failed", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("common.retry") {
                                Task { await store.reload(session: session, forceRefresh: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(PixaTheme.accent)
                        }
                    } else if store.items.isEmpty
                                && creationSubmissions.items.isEmpty
                                && workActivity.pendingWorkPlaceholders.isEmpty {
                        ContentUnavailableView("works.empty", systemImage: "photo.stack")
                    } else {
                        ScrollView {
                            if let error = store.errorMessage {
                                syncErrorBanner(error)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 10)
                            }
                            MasonryLayout(columns: 2, spacing: 12) {
                                ForEach(creationSubmissions.items) { submission in
                                    submissionWorkCard(submission)
                                }
                                ForEach(workActivity.pendingWorkPlaceholders.filter { placeholder in
                                    !store.items.contains { $0.id == placeholder.id }
                                }) { placeholder in
                                    submittedWorkPlaceholder(placeholder)
                                }
                                ForEach(sortedItems) { item in
                                    workCard(item)
                                }
                            }
                            .padding(.horizontal, 16)
                            if store.hasMore {
                                loadMoreFooter
                                    .padding(.vertical, 18)
                            } else {
                                Color.clear.frame(height: 20)
                            }
                        }
                        .refreshable {
                            await store.refreshFromPull(session: session)
                        }
                    }
                }
            }
            .background(PixaTheme.paper.ignoresSafeArea())
            .background(
                PixaNavigationPopObserver(
                    revision: navigation.popRevision(for: .works)
                )
            )
            .toolbar(.hidden, for: .navigationBar)
            .task(id: "\(session.user?.id ?? "")|\(mediaRegion.revision)") {
                await store.reload(
                    session: session,
                    forceRefresh: creationSubmissions.consumeWorksReconciliationRequest()
                )
            }
            .onChange(of: navigation.worksRevision) { _, _ in
                Task { await store.reload(session: session, forceRefresh: true) }
            }
            .onChange(of: workActivity.refreshRevision) { _, _ in
                store.mergeTrackedJobs(workActivity.latestJobs)
            }
            .sheet(isPresented: $showsLogin) { LoginView() }
        }
    }

    private var compactHeader: some View {
        PixaSectionHeader(eyebrow: "works.eyebrow", title: "works.title") {
            if session.isAuthenticated {
                HStack(spacing: 8) {
                    Button {
                        Task { await store.reload(session: session, forceRefresh: true) }
                    } label: {
                        if store.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 34, height: 30)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 34, height: 30)
                        }
                    }
                    .foregroundStyle(PixaTheme.accent)
                    .background(.white.opacity(0.76), in: Capsule())
                    .overlay { Capsule().stroke(PixaTheme.line) }
                    .accessibilityLabel(Text("works.refresh"))
                    .disabled(store.isLoading)

                    if store.total > 0 {
                        Text(String.localizedStringWithFormat(
                            AppLanguage.localized("works.count"),
                            store.total
                        ))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)

                        sortMenu
                    }
                }
            }
        }
    }

    private func submissionWorkCard(_ item: PixaCreationSubmissionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PixaGenerationArtworkPlaceholder(
                aspectRatio: submissionAspectRatio(item.aspectRatio)
            )
            Text(item.title.nilIfEmpty ?? AppLanguage.localized("works.untitled"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PixaTheme.ink)
                .lineLimit(2)

            if item.phase == .failed {
                Text(submissionStatusText(item))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    failureActionButton(item)
                    Button("submission.cancel") {
                        creationSubmissions.cancel(id: item.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Text(submissionStatusText(item))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let progress = item.uploadProgress {
                        Text("\(min(99, Int(progress * 100)))%")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(PixaTheme.accent)
                    }
                    PixaGenerationActivityIndicator(statusLabel: submissionStatusKey(item))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
    }

    private func submittedWorkPlaceholder(
        _ item: PixaPendingWorkPlaceholder
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PixaGenerationArtworkPlaceholder(
                aspectRatio: submissionAspectRatio(item.aspectRatio)
            )
            Text(item.title.nilIfEmpty ?? AppLanguage.localized("works.untitled"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PixaTheme.ink)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text("status.queued")
                    .lineLimit(1)
                Spacer(minLength: 4)
                PixaGenerationActivityIndicator(statusLabel: "status.queued")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
    }

    private func submissionAspectRatio(_ value: String) -> CGFloat {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[1] > 0 else { return 0.8 }
        return CGFloat(parts[0] / parts[1])
    }

    private func submissionStatusText(_ item: PixaCreationSubmissionItem) -> String {
        if item.phase == .failed {
            return item.errorMessage ?? AppLanguage.localized("submission.failed")
        }
        if item.isAwaitingAssetConfirmation {
            return AppLanguage.localized("submission.confirming_asset")
        }
        return AppLanguage.localized(
            item.phase == .uploading ? "submission.uploading" : "submission.submitting"
        )
    }

    private func submissionStatusKey(_ item: PixaCreationSubmissionItem) -> LocalizedStringKey {
        if item.phase == .submitting { return "submission.submitting" }
        if item.isAwaitingAssetConfirmation { return "submission.confirming_asset" }
        return "submission.uploading"
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        Group {
            if store.isLoadingMore {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("works.loading_more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .tint(PixaTheme.accent)
            } else if store.loadMoreError != nil {
                Button("common.retry") {
                    Task { await store.loadNextPage(session: session) }
                }
                .buttonStyle(.bordered)
                .tint(PixaTheme.accent)
            } else {
                Button {
                    Task { await store.loadNextPage(session: session) }
                } label: {
                    Label("works.load_more", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(PixaTheme.ink)
            }
        }
        .onAppear {
            guard !store.isLoading, !store.isLoadingMore, store.loadMoreError == nil else {
                return
            }
            Task { await store.loadNextPage(session: session) }
        }
    }

    private func syncErrorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("works.sync_failed")
                    .font(.caption.bold())
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("common.retry") {
                Task { await store.reload(session: session, forceRefresh: true) }
            }
            .font(.caption.bold())
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.18))
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("works.sort.title", selection: $storedSortOrder) {
                Label("works.sort.newest", systemImage: "arrow.down")
                    .tag(WorksSortOrder.newest.rawValue)
                Label("works.sort.oldest", systemImage: "arrow.up")
                    .tag(WorksSortOrder.oldest.rawValue)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption.bold())
                .foregroundStyle(PixaTheme.accent)
                .frame(width: 34, height: 30)
                .background(.white.opacity(0.76), in: Capsule())
                .overlay { Capsule().stroke(PixaTheme.line) }
        }
        .accessibilityLabel(Text("works.sort.title"))
        .accessibilityValue(Text(sortOrderLabel))
    }

    private func workCard(_ item: TaskJob) -> some View {
        let isActive = item.isActive
        return VStack(alignment: .leading) {
            NavigationLink {
                WorkDetailView(job: item) {
                    store.remove(id: item.id)
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .top) {
                        if isActive, item.mediaURL == nil {
                            PixaGenerationArtworkPlaceholder(
                                aspectRatio: item.displayAspectRatio
                            )
                        } else {
                            RemoteArtwork(
                                url: item.mediaURL,
                                aspectRatio: item.displayAspectRatio,
                                preset: .thumbnail,
                                maximumPixelWidth: 600,
                                contentMode: .fit,
                                usesIntrinsicAspectRatio: true
                            )
                            .background(Color.white.opacity(0.72))
                        }
                        if isActive, item.startedDate != nil {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(activeStatusText(item, at: context.date))
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(.black.opacity(0.58), in: Capsule())
                                    .padding(8)
                            }
                        }
                    }
                    Text(item.title.nilIfEmpty ?? AppLanguage.localized("works.untitled"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PixaTheme.ink)
                        .lineLimit(2)
                }
            }
            .buttonStyle(.plain)
            HStack {
                Text(statusText(item.status))
                    .lineLimit(1)
                Spacer()
                if isActive {
                    PixaGenerationActivityIndicator(
                        statusLabel: ["queued", "pending"].contains(item.status.lowercased())
                            ? "status.queued"
                            : "status.processing"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if isActive, item.startedDate != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ProgressView(value: activeProgress(item, at: context.date))
                        .tint(PixaTheme.accent)
                }
                .accessibilityLabel(Text("works.progress"))
            }
        }
        .padding(8)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
    }

    @ViewBuilder
    private func failureActionButton(_ item: PixaCreationSubmissionItem) -> some View {
        switch item.failureAction {
        case .retry:
            Button("common.retry") {
                creationSubmissions.retry(
                    id: item.id,
                    session: session,
                    workActivity: workActivity,
                    navigation: navigation
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(PixaTheme.accent)
        case .reviewTemplate:
            Button("submission.review_template") {
                creationSubmissions.cancel(id: item.id)
                navigation.selectedTab = .templates
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(PixaTheme.accent)
        case .buyPoints:
            Button("editor.points.recharge") {
                creationSubmissions.cancel(id: item.id)
                navigation.pendingAccountRoute = "points"
                navigation.selectedTab = .account
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(PixaTheme.accent)
        case nil:
            EmptyView()
        }
    }

    private func statusText(_ status: String) -> String {
        switch status.lowercased() {
        case "queued", "pending":
            AppLanguage.localized("status.queued")
        case "processing", "running":
            AppLanguage.localized("status.processing")
        case "succeeded", "completed":
            AppLanguage.localized("status.completed")
        case "failed":
            AppLanguage.localized("status.failed")
        case "cancelled", "canceled":
            AppLanguage.localized("status.cancelled")
        default:
            AppLanguage.localized("status.unknown")
        }
    }

    private func activeStatusText(_ item: TaskJob, at date: Date) -> String {
        switch PixaTaskDurationPresentation.resolve(
            status: item.status,
            startedAt: item.startedDate,
            estimateSeconds: durationEstimates.seconds(for: item.jobType),
            now: date
        ) {
        case let .remaining(seconds):
            return String.localizedStringWithFormat(
                AppLanguage.localized("works.duration.remaining"),
                PixaDurationTextFormatter.countdown(seconds: seconds)
            )
        case .overdue:
            guard let startedAt = item.startedDate else {
                return statusText(item.status)
            }
            let elapsedSeconds = max(0, Int(date.timeIntervalSince(startedAt)))
            return String.localizedStringWithFormat(
                AppLanguage.localized("works.duration.overdue"),
                PixaDurationTextFormatter.countdown(seconds: elapsedSeconds)
            )
        case .queued:
            return AppLanguage.localized("status.queued")
        case .unavailable:
            return statusText(item.status)
        }
    }

    private func activeProgress(_ item: TaskJob, at date: Date) -> Double {
        guard let startedAt = item.startedDate else { return 0 }
        let estimate = durationEstimates.seconds(for: item.jobType)
        guard estimate > 0 else { return 0 }
        return min(0.98, max(0, date.timeIntervalSince(startedAt) / Double(estimate)))
    }

}

private struct PixaGenerationArtworkPlaceholder: View {
    let aspectRatio: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                LinearGradient(
                    colors: [Color.white, PixaTheme.paper, PixaTheme.accent.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(PixaTheme.accent.opacity(0.14))
                    .frame(width: width * 0.45)
                    .blur(radius: 18)
                    .position(x: width * 0.18, y: height * 0.2)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.72))
                    .frame(width: width * 0.46, height: height * 0.6)
                    .rotationEffect(.degrees(9))
                    .position(x: width * 0.57, y: height * 0.51)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.86))
                    .frame(width: width * 0.46, height: height * 0.6)
                    .rotationEffect(.degrees(-8))
                    .position(x: width * 0.43, y: height * 0.49)

                VStack(spacing: 0) {
                    ZStack {
                        LinearGradient(
                            colors: [PixaTheme.accent.opacity(0.86), Color.orange.opacity(0.58), Color.pink.opacity(0.38)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Circle()
                            .fill(Color.white.opacity(0.76))
                            .frame(width: width * 0.12)
                            .offset(x: width * 0.1, y: -height * 0.09)
                        Ellipse()
                            .fill(PixaTheme.ink.opacity(0.12))
                            .frame(width: width * 0.54, height: height * 0.22)
                            .rotationEffect(.degrees(-12))
                            .offset(x: -width * 0.05, y: height * 0.13)
                    }
                    .frame(height: height * 0.36)
                    VStack(alignment: .leading, spacing: height * 0.025) {
                        Capsule().fill(PixaTheme.ink.opacity(0.24)).frame(width: width * 0.25, height: 3)
                        Capsule().fill(PixaTheme.ink.opacity(0.12)).frame(width: width * 0.32, height: 3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .padding(width * 0.035)
                .frame(width: width * 0.48, height: height * 0.62)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 1)
                }
                .shadow(color: PixaTheme.ink.opacity(0.12), radius: 14, y: 7)

                Image(systemName: "sparkle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(PixaTheme.accent)
                    .position(x: width * 0.77, y: height * 0.28)
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PixaTheme.accent.opacity(0.62))
                    .position(x: width * 0.23, y: height * 0.7)
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .aspectRatio(max(0.1, aspectRatio), contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

private struct PixaGenerationActivityIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let statusLabel: LocalizedStringKey

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.18, paused: reduceMotion)) { context in
            let activeDot = Int(context.date.timeIntervalSinceReferenceDate / 0.36) % 4
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(PixaTheme.accent.opacity(index == activeDot ? 0.95 : 0.2))
                        .frame(width: index == activeDot ? 13 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.18), value: activeDot)
                }
            }
            .frame(width: 66, alignment: .trailing)
        }
        .accessibilityLabel(Text("works.progress"))
        .accessibilityValue(Text(statusLabel))
    }
}

private struct WorksLoadingSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private let aspectRatios: [CGFloat] = [0.78, 1.12, 1.0, 0.72, 1.18, 0.86]

    var body: some View {
        ScrollView {
            MasonryLayout(columns: 2, spacing: 12) {
                ForEach(Array(aspectRatios.enumerated()), id: \.offset) { _, aspectRatio in
                    skeletonCard(aspectRatio: aspectRatio)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
            .opacity(isPulsing ? 0.48 : 0.82)
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("loading.works.title"))
        .onAppear { updateAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateAnimation() }
    }

    private func skeletonCard(aspectRatio: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PixaTheme.ink.opacity(0.08))
                .aspectRatio(aspectRatio, contentMode: .fit)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(PixaTheme.ink.opacity(0.1))
                .frame(height: 14)
                .padding(.trailing, 28)

            HStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(PixaTheme.ink.opacity(0.07))
                    .frame(height: 9)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(PixaTheme.ink.opacity(0.07))
                    .frame(width: 32, height: 9)
            }
        }
        .padding(8)
        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(PixaTheme.line)
        }
        .accessibilityHidden(true)
    }

    private func updateAnimation() {
        if reduceMotion {
            isPulsing = false
        } else {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
