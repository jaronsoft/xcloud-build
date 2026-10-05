import Foundation

enum MarkdownSegment: Identifiable, Equatable, Sendable {
    case text(String)
    case image(alt: String, url: URL)

    var id: String {
        switch self {
        case let .text(value):
            "text-\(value.hashValue)"
        case let .image(alt, url):
            "image-\(alt)-\(url.absoluteString)"
        }
    }
}

enum MarkdownContentParser {
    private static let imagePattern = #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)"#

    static func attributedText(_ markdown: String) -> AttributedString {
        let lines = markdown.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        var result = AttributedString()
        var index = 0

        while index < lines.count {
            let startsFence = lines[index]
                .trimmingCharacters(in: .whitespaces)
                .hasPrefix("```")
            var blockEnd = index
            if startsFence {
                blockEnd += 1
                while blockEnd < lines.count {
                    if lines[blockEnd]
                        .trimmingCharacters(in: .whitespaces)
                        .hasPrefix("```") {
                        break
                    }
                    blockEnd += 1
                }
                blockEnd = min(blockEnd, lines.count - 1)
            }

            let block = lines[index...blockEnd].joined(separator: "\n")
            result += (
                try? AttributedString(
                    markdown: block,
                    options: .init(interpretedSyntax: .full)
                )
            ) ?? AttributedString(block)
            if blockEnd < lines.count - 1 {
                result += AttributedString("\n")
            }
            index = blockEnd + 1
        }

        return result
    }

    static func parse(_ markdown: String, baseURL: URL) -> [MarkdownSegment] {
        guard let expression = try? NSRegularExpression(pattern: imagePattern) else {
            return [.text(markdown)]
        }
        let source = markdown as NSString
        let matches = expression.matches(
            in: markdown,
            range: NSRange(location: 0, length: source.length)
        )
        guard !matches.isEmpty else { return [.text(markdown)] }

        var segments: [MarkdownSegment] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                segments.append(
                    .text(
                        source.substring(
                            with: NSRange(
                                location: cursor,
                                length: match.range.location - cursor
                            )
                        )
                    )
                )
            }
            let alt = match.range(at: 1).location == NSNotFound
                ? ""
                : source.substring(with: match.range(at: 1))
            let value = source.substring(with: match.range(at: 2))
            if let url = normalizedURL(value, baseURL: baseURL) {
                segments.append(.image(alt: alt, url: url))
            } else {
                segments.append(.text(source.substring(with: match.range)))
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < source.length {
            segments.append(
                .text(
                    source.substring(
                        with: NSRange(location: cursor, length: source.length - cursor)
                    )
                )
            )
        }
        return segments
    }

    private static func normalizedURL(_ value: String, baseURL: URL) -> URL? {
        if let absolute = URL(string: value), absolute.scheme != nil {
            return absolute
        }
        var root = baseURL
        if root.lastPathComponent.lowercased() == "api" {
            root.deleteLastPathComponent()
        }
        return URL(string: value, relativeTo: root)?.absoluteURL
    }
}
