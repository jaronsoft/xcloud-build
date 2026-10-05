import SwiftUI
import Network

struct SupportToolsView: View {
    let onClearTenantCache: () -> Void
    @State private var diagnostics = AIKDiagnosticsStore.shared
    @State private var testMessages: [String] = []
    @State private var testing = false

    var body: some View {
        NavigationStack {
            List {
                Section("tools.network") {
                    Button("tools.test") {
                        Task { await testConnection() }
                    }
                    .disabled(testing)
                    if testing { ProgressView() }
                    ForEach(testMessages, id: \.self) { Text($0) }
                    ForEach(diagnostics.entries.prefix(100)) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(entry.method) \(entry.path)")
                            Text("\(entry.statusCode.map(String.init) ?? "NETWORK") · \(entry.durationMilliseconds)ms")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ShareLink(item: diagnostics.exportText) {
                        Label("tools.export", systemImage: "square.and.arrow.up")
                    }
                    Button("tools.clear_logs", role: .destructive) { diagnostics.clear() }
                }
                Section("tools.cache") {
                    LabeledContent(
                        "tools.http_cache",
                        value: ByteCountFormatter.string(
                            fromByteCount: Int64(URLCache.shared.currentDiskUsage),
                            countStyle: .file
                        )
                    )
                    Button("tools.clear_cache", role: .destructive) {
                        URLCache.shared.removeAllCachedResponses()
                        onClearTenantCache()
                    }
                }
            }
            .navigationTitle("tools.title")
        }
    }

    private func testConnection() async {
        testing = true
        testMessages.removeAll()
        defer { testing = false }
        let network = await currentNetworkStatus()
        testMessages.append("网络状态 · \(network)")
        let client = APIClient()
        do {
            let start = Date.now
            let _: String = try await client.get("/auth/snowflake", as: String.self)
            testMessages.append("API 连通 · \(elapsed(from: start))ms")
        } catch {
            testMessages.append("API 失败 · \(error.localizedDescription)")
        }
        do {
            let start = Date.now
            let _: TenantPage = try await client.get(
                "/KnowledgeAccess/PublicTenants",
                queryItems: [
                    URLQueryItem(name: "page", value: "1"),
                    URLQueryItem(name: "size", value: "1"),
                ],
                as: TenantPage.self
            )
            testMessages.append("租户接口 · \(elapsed(from: start))ms")
        } catch {
            testMessages.append("租户接口失败 · \(error.localizedDescription)")
        }
        do {
            var request = try client.makeRequest(
                path: "/KnowledgeChat/StreamAsk",
                method: "POST",
                context: .anonymous
            )
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(#"{"Question":"","TenantId":"0"}"#.utf8)
            let start = Date.now
            let (_, response) = try await client.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            testMessages.append("SSE 建连 · HTTP \(status) · \(elapsed(from: start))ms")
        } catch {
            testMessages.append("SSE 建连失败 · \(error.localizedDescription)")
        }
    }

    private func elapsed(from start: Date) -> Int {
        Int(Date.now.timeIntervalSince(start) * 1_000)
    }

    private func currentNetworkStatus() async -> String {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.wekarepartners.aik.network-diagnostic")
            monitor.pathUpdateHandler = { path in
                let value = path.status == .satisfied
                    ? (path.isExpensive ? "可用（蜂窝/热点）" : "可用")
                    : "不可用"
                monitor.cancel()
                continuation.resume(returning: value)
            }
            monitor.start(queue: queue)
        }
    }
}
