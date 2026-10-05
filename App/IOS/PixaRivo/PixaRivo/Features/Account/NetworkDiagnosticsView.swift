import SwiftUI
import UIKit

struct NetworkDiagnosticsView: View {
    @State private var diagnostics = NetworkDiagnosticsStore.shared
    @State private var cacheStatistics: PixaImageCacheStatistics?
    @State private var routingResults: [AppRoutingDiagnosticResult] = []
    @State private var isRefreshingRouting = false
    @State private var routingRefreshFeedbackKey: String?
    @State private var isTestingRouting = false
    @State private var routingTestStartedAt: Date?
    @State private var exportFile: DiagnosticsExportFile?
    @State private var showsClearLogsConfirmation = false
    @Environment(SessionStore.self) private var session
    @State private var generationNodes: [PixaGenerationNode] = []
    @State private var generationNodeMessage: String?
    @State private var isLoadingNodes = false

    var body: some View {
        List {
            Section("diagnostics.overview") {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
                    ForEach(Array(overviewItems.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 2) {
                                Text(item.0)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 2)
                                if item.2 {
                                    routingRefreshButton
                                }
                            }
                            Text(item.1)
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
                if let routingRefreshFeedbackKey {
                    Label {
                        Text(AppLanguage.localized(routingRefreshFeedbackKey))
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Color.orange)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Button {
                    Task { await runRoutingTest() }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("diagnostics.test_results")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            routingRefreshIndicator(isRefreshing: isTestingRouting)
                        }

                        if !routingResults.isEmpty {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                                alignment: .leading,
                                spacing: 8
                            ) {
                                ForEach(routingResults) { result in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(AppLanguage.localized(routingRoleLocalizationKey(result.role)))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                        Text(result.latencyMilliseconds.map { "\($0)ms" }
                                            ?? AppLanguage.localized(result.statusLocalizationKey))
                                            .font(.subheadline)
                                            .foregroundStyle(result.statusColor)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        if isTestingRouting, let routingTestStartedAt {
                            NetworkProbeCountdownView(startedAt: routingTestStartedAt)
                        } else if routingResults.isEmpty {
                            Text("diagnostics.tap_to_test")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isTestingRouting)
                .accessibilityLabel(Text("diagnostics.test_results"))
            }
            Section {
                Button {
                    Task { await loadGenerationNodes() }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("diagnostics.generation_nodes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(isLoadingNodes
                                ? "diagnostics.refreshing_nodes"
                                : "diagnostics.tap_to_refresh_nodes")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if isLoadingNodes && generationNodes.isEmpty {
                            ProgressView()
                        } else if let generationNodeMessage {
                            Text(generationNodeMessage).foregroundStyle(.secondary)
                        } else if generationNodes.isEmpty {
                            Text("diagnostics.no_generation_nodes").foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                                ForEach(generationNodes) { node in
                                    PixaGenerationNodeTile(node: node)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoadingNodes)
                .accessibilityLabel(Text("diagnostics.generation_nodes"))
            }
            Section {
                NavigationLink { NetworkRequestsView() } label: {
                    Label("diagnostics.requests", systemImage: "arrow.left.arrow.right")
                }
                NavigationLink { ImageDiagnosticsView() } label: {
                    Label("diagnostics.images", systemImage: "photo")
                }
                NavigationLink { SystemDiagnosticsView() } label: {
                    Label("diagnostics.system", systemImage: "text.alignleft")
                }
            }
            Section {
                Button {
                    if let url = diagnostics.makeExportFileURL(
                        name: "PixaRivo-Network-Errors",
                        content: diagnostics.errorExportText
                    ) {
                        exportFile = DiagnosticsExportFile(url: url)
                    }
                } label: {
                    Label("diagnostics.export_errors", systemImage: "square.and.arrow.up")
                }
                .disabled(!diagnostics.hasFailedEntries)
                Button {
                    if let url = diagnostics.makeExportFileURL(
                        name: "PixaRivo-Network-Diagnostics",
                        content: diagnostics.exportText
                    ) {
                        exportFile = DiagnosticsExportFile(url: url)
                    }
                } label: {
                    Label("diagnostics.share", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    showsClearLogsConfirmation = true
                } label: {
                    Label("diagnostics.clear_logs", systemImage: "trash")
                }
            }
        }
        .navigationTitle("diagnostics.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            cacheStatistics = await PixaImageCache.shared.statistics()
            async let nodeLoad: Void = loadGenerationNodes()
            await runRoutingTest()
            await nodeLoad
        }
        .sheet(item: $exportFile) { file in
            PixaActivityView(items: [file.url])
        }
        .confirmationDialog(
            "diagnostics.clear_logs.confirm_title",
            isPresented: $showsClearLogsConfirmation,
            titleVisibility: .visible
        ) {
            Button("diagnostics.clear_logs.confirm_action", role: .destructive) {
                diagnostics.clear()
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("diagnostics.clear_logs.confirm_message")
        }
    }

    private var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cacheStatistics?.physicalByteCount ?? 0, countStyle: .file)
    }

    private var overviewItems: [(String, String, Bool)] {
        [
            (AppLanguage.localized("diagnostics.version"), AppConfiguration.releaseLabel, false),
            (AppLanguage.localized("diagnostics.api"), AppConfiguration.apiDisplayName, true),
            ("Routing Version", "v\(AppAPIRoutingSnapshot.configVersion)", false),
            ("Routing Cache", AppAPIRoutingSnapshot.isStale ? "stale" : "fresh", false),
            (AppLanguage.localized("diagnostics.cache.total"), formattedCacheSize, false),
            (AppLanguage.localized("diagnostics.cache.files"), "\(cacheStatistics?.fileCount ?? 0)", false)
        ]
    }

    private var routingRefreshButton: some View {
        Button {
            Task { await refreshAPIRouting() }
        } label: {
            routingRefreshIndicator(isRefreshing: isRefreshingRouting)
        }
        .buttonStyle(.plain)
        .foregroundStyle(PixaTheme.accent)
        .disabled(isRefreshingRouting)
        .accessibilityLabel(Text(AppLanguage.localized(isRefreshingRouting
            ? "diagnostics.refreshing_api_routing"
            : "diagnostics.refresh_api_routing")))
    }

    private func routingRefreshIndicator(isRefreshing: Bool) -> some View {
        Group {
            if isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .frame(width: 28, height: 28)
        .background(PixaTheme.accent.opacity(0.09), in: Circle())
        .contentShape(Circle())
        .foregroundStyle(PixaTheme.accent)
    }

    private func refreshAPIRouting() async {
        guard !isRefreshingRouting else { return }
        isRefreshingRouting = true
        routingRefreshFeedbackKey = nil
        defer { isRefreshingRouting = false }
        let refreshed = await AppAPIRouter.shared.refresh(force: true)
        if !refreshed {
            routingRefreshFeedbackKey = "diagnostics.api_routing_refresh_failed"
        }
    }

    private func runRoutingTest() async {
        guard !isTestingRouting else { return }
        isTestingRouting = true
        routingTestStartedAt = .now
        defer {
            isTestingRouting = false
            routingTestStartedAt = nil
        }
        routingResults = await AppAPIRouter.shared.diagnosticResults()
    }

    private func routingRoleLocalizationKey(_ role: AppRoutingEndpointRole) -> String {
        "diagnostics.routing_role.\(role.rawValue)"
    }

    private func loadGenerationNodes() async {
        guard !isLoadingNodes else { return }
        guard let token = await session.validAccessToken() else {
            generationNodeMessage = AppLanguage.localized("diagnostics.nodes_sign_in")
            return
        }
        isLoadingNodes = true
        defer { isLoadingNodes = false }
        do {
            generationNodes = try await APIClient().get(
                "/api/ais/runtime/generation-nodes", token: token, forceRefresh: true
            )
            generationNodeMessage = nil
        } catch {
            generationNodes = []
            generationNodeMessage = error.localizedDescription
        }
    }
}

private struct PixaGenerationNode: Decodable, Identifiable {
    let name: String
    let activeJobs: Int
    let maxConcurrentJobs: Int
    let runCount: Int64?
    let successCount: Int64?
    let failedCount: Int64?
    var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case activeJobs = "ActiveJobs"
        case maxConcurrentJobs = "MaxConcurrentJobs"
        case runCount = "RunCount"
        case successCount = "SuccessCount"
        case failedCount = "FailedCount"
    }

    var utilization: Double {
        min(1, Double(max(0, activeJobs)) / Double(max(1, maxConcurrentJobs)))
    }

    var statusKey: String {
        if activeJobs <= 0 { return "diagnostics.node_status.idle" }
        if activeJobs >= max(1, maxConcurrentJobs) { return "diagnostics.node_status.full" }
        return "diagnostics.node_status.busy"
    }

    var statusColor: Color {
        if activeJobs <= 0 { return .green }
        if activeJobs >= max(1, maxConcurrentJobs) { return .red }
        return .orange
    }
}

private struct PixaGenerationNodeTile: View {
    let node: PixaGenerationNode

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(node.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Circle()
                    .fill(node.statusColor)
                    .frame(width: 7, height: 7)
            }

            Spacer(minLength: 0)

            Text(AppLanguage.localized(node.statusKey))
                .font(.caption2.weight(.medium))
                .foregroundStyle(node.statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(node.activeJobs)/\(node.maxConcurrentJobs)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                Text("\(node.runCount ?? 0)")
                    .foregroundStyle(.primary)
                Text("/")
                    .foregroundStyle(.tertiary)
                Text("\(node.successCount ?? 0)")
                    .foregroundStyle(.green)
                Text("/")
                    .foregroundStyle(.tertiary)
                Text("\(node.failedCount ?? 0)")
                    .foregroundStyle(.red)
            }
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.65)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [.green, .yellow, .orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geometry.size.width * node.utilization)
                }
            }
            .frame(height: 4)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    colors: [node.statusColor.opacity(0.04), node.statusColor.opacity(0.13)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(node.statusColor.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct NetworkRequestsView: View {
    @State private var diagnostics = NetworkDiagnosticsStore.shared
    @State private var selectedEntry: NetworkDiagnosticEntry?

    var body: some View {
        List {
            if diagnostics.entries.isEmpty {
                Text("diagnostics.empty").foregroundStyle(.secondary)
            } else {
                ForEach(diagnostics.entries) { entry in
                    Button { selectedEntry = entry } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.method).font(.caption.monospaced().bold())
                                Text(entry.statusCode.map(String.init) ?? "ERR")
                                    .foregroundStyle(entry.succeeded ? .green : .red)
                                Spacer()
                                Text(Self.requestTimeFormatter.string(from: entry.timestamp))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text("\(entry.durationMilliseconds)ms").foregroundStyle(.secondary)
                            }
                            Text(entry.address).font(.footnote.monospaced()).lineLimit(2)
                            if !entry.succeeded {
                                Text(entry.message).font(.caption).foregroundStyle(.red).lineLimit(2)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("diagnostics.requests")
        .sheet(item: $selectedEntry) { entry in
            NetworkErrorDetailView(text: diagnostics.detailText(for: entry))
        }
    }

    private static let requestTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct ImageDiagnosticsView: View {
    @State private var diagnostics = NetworkDiagnosticsStore.shared

    var body: some View {
        List {
            if diagnostics.imageCacheEntries.isEmpty {
                Text("diagnostics.empty").foregroundStyle(.secondary)
            } else {
                ForEach(diagnostics.imageCacheEntries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(entry.source).font(.caption.monospaced().bold())
                            Text(entry.pixelWidth.map { "\($0)px" } ?? "original")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))
                        }
                        Text("\(entry.appliedPreset) · \(entry.path)")
                            .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle("diagnostics.images")
    }
}

private struct SystemDiagnosticsView: View {
    @State private var diagnostics = NetworkDiagnosticsStore.shared

    var body: some View {
        List {
            if diagnostics.systemLogs.isEmpty {
                Text("diagnostics.empty").foregroundStyle(.secondary)
            } else {
                ForEach(Array(diagnostics.systemLogs.enumerated()), id: \.offset) { _, entry in
                    Text(entry).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("diagnostics.system")
    }
}

struct NetworkTestView: View {
    @State private var results: [AppRoutingDiagnosticResult] = []
    @State private var isTesting = false
    @State private var testStartedAt: Date?

    var body: some View {
        List {
            Section {
                Text("diagnostics.network_test_description")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    isTesting = true
                    testStartedAt = .now
                    Task {
                        results = await AppAPIRouter.shared.diagnosticResults()
                        isTesting = false
                        testStartedAt = nil
                    }
                } label: {
                    Label(
                        isTesting ? "diagnostics.testing" : "diagnostics.start_test",
                        systemImage: "play.circle"
                    )
                }
                .disabled(isTesting)
                if let testStartedAt {
                    NetworkProbeCountdownView(startedAt: testStartedAt)
                }
            }

            if !results.isEmpty {
                Section("diagnostics.test_results") {
                    ForEach(results) { result in
                        HStack {
                            Label(result.role.displayName, systemImage: result.role == .test ? "stethoscope" : "server.rack")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(AppLanguage.localized(result.statusLocalizationKey))
                                    .foregroundStyle(result.statusColor)
                                if let latency = result.latencyMilliseconds {
                                    Text("\(latency)ms")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("diagnostics.network_test")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NetworkProbeCountdownView: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let remaining = max(0, 10 - Int(elapsed))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundStyle(PixaTheme.accent)
                    Text(remaining > 0
                        ? String(format: AppLanguage.localized("diagnostics.testing_countdown"), remaining)
                        : AppLanguage.localized("diagnostics.testing_finishing"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                ProgressView(value: min(elapsed, 10), total: 10)
                    .tint(PixaTheme.accent)
                    .accessibilityLabel(Text("diagnostics.testing_progress"))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private extension AppRoutingDiagnosticResult {
    var statusColor: Color {
        guard let latencyCategory else { return succeeded ? .green : .red }
        switch latencyCategory {
        case .fast: return .green
        case .normal: return .blue
        case .slow: return .orange
        case .verySlow: return .red
        }
    }
}

private struct DiagnosticsExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct NetworkErrorDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("diagnostics.request_details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Label("diagnostics.copy_request", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}
