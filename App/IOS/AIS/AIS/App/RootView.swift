import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @State private var selection = AppTab.home
    @State private var selectedVisualPreset: AISVisualPreset?
    @State private var pendingSharedJobID: String?
    @State private var pendingEditTask: AISTaskJob?
    @State private var taskModel = TasksViewModel()
    @State private var taskPollingRevision = 0
    @State private var trackedJobIDs: Set<String> = []

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(
                    selection: $selection,
                    selectedPreset: $selectedVisualPreset,
                    pendingSharedJobID: $pendingSharedJobID
                )
            }
            .tabItem {
                Label(
                    "tab.home",
                    systemImage: selection == .home
                        ? "circle.circle.fill"
                        : "circle.circle"
                )
            }
            .tag(AppTab.home)

            NavigationStack {
                TemplatesView {
                    selection = .create
                }
            }
            .tabItem {
                Label(
                    "tab.templates",
                    systemImage: selection == .templates
                        ? "diamond.fill"
                        : "diamond"
                )
            }
            .tag(AppTab.templates)

            NavigationStack {
                CreationView(
                    selectedPreset: selectedVisualPreset,
                    initialTask: pendingEditTask
                )
            }
            .tabItem {
                Image("CreationCoreIcon")
                    .renderingMode(.original)
                    .accessibilityLabel("tab.create")
            }
            .tag(AppTab.create)

            NavigationStack {
                TasksView(model: taskModel) { task in
                    pendingEditTask = task
                    selection = .create
                }
            }
            .tabItem {
                Label(
                    "tab.tasks",
                    systemImage: selection == .tasks
                        ? "clock.fill"
                        : "clock"
                )
            }
            .badge(taskModel.activeCount)
            .tag(AppTab.tasks)

            NavigationStack {
                AccountView()
            }
            .tabItem {
                Label(
                    "tab.account",
                    systemImage: selection == .account
                        ? "person.crop.circle.fill"
                        : "person.crop.circle"
                )
            }
            .tag(AppTab.account)
        }
        .tint(AISTheme.accent)
        .preferredColorScheme(.light)
        .onOpenURL { url in
            guard let jobID = sharedJobID(from: url) else { return }
            pendingSharedJobID = jobID
            selection = .home
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .aisTaskSubmitted)
        ) { notification in
            Task {
                if let jobID = notification.object as? String, !jobID.isEmpty {
                    trackedJobIDs.insert(jobID)
                }
                await taskModel.load(
                    session: session,
                    showsLoading: false,
                    force: true
                )
                // 新任务提交后只重启该任务的轻量状态跟踪，不恢复整表空闲轮询。
                taskPollingRevision &+= 1
            }
        }
        .task(
            id: "\(session.isAuthenticated)-\(selection)-\(taskPollingRevision)"
        ) {
            guard session.isAuthenticated else {
                taskModel.reset()
                trackedJobIDs.removeAll()
                return
            }

            if selection == .tasks {
                await taskModel.load(
                    session: session,
                    showsLoading: taskModel.tasks.isEmpty,
                    force: false
                )
                while !Task.isCancelled && taskModel.hasActiveTasks {
                    var reachedTerminal = false
                    for jobID in taskModel.activeJobIDs {
                        reachedTerminal =
                            await taskModel.refreshStatus(
                                session: session,
                                jobID: jobID
                            ) || reachedTerminal
                    }
                    if reachedTerminal {
                        await taskModel.load(
                            session: session,
                            showsLoading: false,
                            force: true
                        )
                    }
                    if taskModel.hasActiveTasks {
                        try? await Task.sleep(for: .seconds(5))
                    }
                }
                return
            }

            while !Task.isCancelled && !trackedJobIDs.isEmpty {
                var completedJobIDs: [String] = []
                for jobID in trackedJobIDs {
                    if await taskModel.refreshStatus(
                        session: session,
                        jobID: jobID
                    ) {
                        completedJobIDs.append(jobID)
                    }
                }
                if !completedJobIDs.isEmpty {
                    trackedJobIDs.subtract(completedJobIDs)
                    await taskModel.load(
                        session: session,
                        showsLoading: false,
                        force: true
                    )
                }
                if !trackedJobIDs.isEmpty {
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    private func sharedJobID(from url: URL) -> String? {
        guard url.host?.lowercased() == "ais.jaronsoft.com" else {
            return nil
        }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2,
              components[0] == "share",
              components[1].allSatisfy(\.isNumber) else {
            return nil
        }
        return components[1]
    }
}

enum AppTab: Hashable {
    case home
    case templates
    case create
    case tasks
    case account
}

#Preview("RootView - 主轮廓") {
    RootView()
        .environment(SessionStore())
        .environment(AISAppDataStore())
}
