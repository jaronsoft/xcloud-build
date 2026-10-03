import SwiftUI
import UIKit

struct DeveloperNetworkLogView: View {
    @ObservedObject var logs: DeveloperNetworkLogStore
    @State private var copiedEntryID: UUID?

    var body: some View {
        List {
            Section {
                ShareLink(item: logs.exportText) {
                    Label("Share sanitized logs", systemImage: "square.and.arrow.up")
                }
                .disabled(logs.entries.isEmpty)

                Button("Clear logs", role: .destructive) { logs.clear() }
                    .disabled(logs.entries.isEmpty)
            } footer: {
                Text("Logs stay in memory and are cleared when the app exits. Tokens, passwords, verification codes, request bodies and response bodies are never recorded.")
            }

            Section("Requests") {
                if logs.entries.isEmpty {
                    ContentUnavailableView(
                        "No requests yet",
                        systemImage: "network",
                        description: Text("Use Sync now in Profile or continue using the app to capture API activity.")
                    )
                } else {
                    ForEach(logs.entries) { entry in
                        Button {
                            copy(entry)
                        } label: {
                            logRow(entry)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Copies this log entry")
                    }
                }
            }
        }
        .navigationTitle("Network logs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func logRow(_ entry: DeveloperNetworkLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(entry.method)
                    .font(.caption.monospaced().bold())
                Text(entry.statusCode.map(String.init) ?? "NETWORK")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(statusColor(entry))
                Spacer()
                Text("\(entry.durationMilliseconds)ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(MosaPalette.muted)
            }
            Text(entry.path)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
            Text(entry.message)
                .font(.footnote)
                .foregroundStyle(entry.succeeded ? MosaPalette.muted : Color.red)
                .textSelection(.enabled)
            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                .font(.caption2)
                .foregroundStyle(MosaPalette.muted)
            if copiedEntryID == entry.id {
                Label("Copied", systemImage: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ entry: DeveloperNetworkLogEntry) -> Color {
        guard entry.succeeded else { return .red }
        return .green
    }

    private func copy(_ entry: DeveloperNetworkLogEntry) {
        UIPasteboard.general.string = logs.text(for: entry)
        copiedEntryID = entry.id
        Task {
            try? await Task.sleep(for: .milliseconds(1_200))
            if copiedEntryID == entry.id { copiedEntryID = nil }
        }
    }
}
