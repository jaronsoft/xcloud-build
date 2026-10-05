import SwiftUI

struct MarkdownMessageView: View {
    let content: String

    private var segments: [MarkdownSegment] {
        MarkdownContentParser.parse(
            content,
            baseURL: AppEnvironment.current.apiBaseURL
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { segment in
                switch segment {
                case let .text(markdown):
                    Text(MarkdownContentParser.attributedText(markdown))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(alignment: .leading)
                case let .image(alt, url):
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 560)
                        case .failure:
                            ContentUnavailableView(
                                "chat.image_failed",
                                systemImage: "photo.badge.exclamationmark",
                                description: Text(alt)
                            )
                            .frame(minHeight: 120)
                        default:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                    .background(AIKTheme.background, in: .rect(cornerRadius: 12))
                    .clipShape(.rect(cornerRadius: 12))
                    .accessibilityLabel(alt.isEmpty ? String(localized: "chat.image") : alt)
                }
            }
        }
    }
}
