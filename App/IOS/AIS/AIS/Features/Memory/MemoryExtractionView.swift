import SwiftUI

struct MemoryExtractionView: View {
    let batches: [AISMemoryExtractionBatch]
    let isWorking: Bool
    let start: () async -> Void
    let showCandidates: () -> Void

    var body: some View {
        List {
            Section {
                Text("memory.extraction.description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await start() }
                } label: {
                    Label(
                        isWorking
                            ? "memory.extraction.running"
                            : "memory.extraction.start",
                        systemImage: "clock.arrow.circlepath"
                    )
                }
                .disabled(isWorking || batches.first?.isRunning == true)
            }
            Section("memory.extraction.history") {
                ForEach(batches) { batch in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(batch.status)
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(batch.processedCount)/\(batch.totalCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(
                            value: Double(batch.processedCount),
                            total: Double(max(1, batch.totalCount))
                        )
                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "memory.extraction.candidates"),
                                batch.candidateCount
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if batch.status == "succeeded",
                           batch.candidateCount > 0 {
                            Button("memory.extraction.view_candidates.short") {
                                showCandidates()
                            }
                            .buttonStyle(.bordered)
                        }
                        if let error = batch.errorSummary {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .navigationTitle("memory.extraction.title")
    }
}
