import SwiftUI
import UIKit

struct MemoryDetailView: View {
    let memory: AISMemoryItem

    var body: some View {
        List {
            Section("memory.detail.content") {
                Text(memory.content)
                    .textSelection(.enabled)
                LabeledContent("memory.detail.status") {
                    Text(LocalizedStringKey(memory.statusLocalizationKey))
                }
                LabeledContent("memory.detail.scope") {
                    Text(LocalizedStringKey(memory.scopeLocalizationKey))
                }
                LabeledContent("memory.editor.category") {
                    Text(LocalizedStringKey(memory.categoryLocalizationKey))
                }
                LabeledContent("memory.editor.priority") {
                    Text(LocalizedStringKey(memory.priorityLocalizationKey))
                }
                LabeledContent(
                    "memory.detail.evidence",
                    value: String(memory.evidenceCount)
                )
                LabeledContent(
                    "memory.detail.applied",
                    value: String(memory.applyCount)
                )
            }
            Section("memory.detail.sources") {
                if memory.sourceSummary.isEmpty {
                    Text("memory.detail.sources.empty")
                        .foregroundStyle(.secondary)
                }
                ForEach(memory.sourceSummary) { source in
                    sourceCard(source)
                }
            }
        }
        .navigationTitle("memory.detail.title")
    }

    private func sourceCard(
        _ source: AISMemorySourceSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MemorySourcePreview(source: source)
            Text(source.title ?? source.sourceScene ?? source.sourceType ?? "—")
                .font(.headline)
            if let date = source.sourceOccurredAt ?? source.createTime {
                Text(date, format: .dateTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let description = source.description ?? source.sourceText,
               !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
            if !source.keywords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(source.keywords, id: \.self) { keyword in
                            Text(keyword)
                                .font(.caption2.bold())
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.secondary.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
            if let reason = source.extractReason, !reason.isEmpty {
                Label {
                    Text(reason)
                } icon: {
                    Image(systemName: "sparkles")
                }
                .font(.caption)
                .foregroundStyle(.indigo)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MemorySourcePreview: View {
    let source: AISMemorySourceSummary
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let url = source.resultURL {
                Link(destination: url) {
                    previewContent()
                }
                .accessibilityLabel("memory.source.open_result")
            } else {
                placeholder(
                    icon: "photo",
                    title: "memory.source.no_preview"
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.secondary.opacity(0.15))
        }
        .task(id: source.resultURL) {
            await loadImageIfNeeded()
        }
    }

    @ViewBuilder
    private func previewContent() -> some View {
        if source.mediaType == "video" {
            placeholder(
                icon: "play.rectangle.fill",
                title: "memory.source.open_video"
            )
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if didFail {
            placeholder(
                icon: "photo.badge.exclamationmark",
                title: "memory.source.preview_failed"
            )
        } else {
            ZStack {
                Color.secondary.opacity(0.06)
                ProgressView()
            }
        }
    }

    private func placeholder(
        icon: String,
        title: LocalizedStringKey
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
            Text(title)
                .font(.caption.bold())
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.secondary.opacity(0.06))
    }

    private func loadImageIfNeeded() async {
        image = nil
        didFail = false
        guard source.mediaType != "video",
              let url = source.resultURL else { return }
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: configuration)
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled,
                  let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode,
                  let loadedImage = UIImage(data: data) else {
                didFail = true
                return
            }
            image = loadedImage
        } catch {
            guard !Task.isCancelled else { return }
            didFail = true
        }
    }
}
