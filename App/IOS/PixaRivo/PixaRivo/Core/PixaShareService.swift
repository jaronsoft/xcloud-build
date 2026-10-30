import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct PixaSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

enum PixaShareSource {
    case template
    case gallery
    case work

    var localizedName: String {
        switch self {
        case .template:
            AppLanguage.localized("share.source.template")
        case .gallery:
            AppLanguage.localized("share.source.gallery")
        case .work:
            AppLanguage.localized("share.source.work")
        }
    }
}

@MainActor
enum PixaShareService {
    static func publicURL(source: PixaShareSource, id: String) -> URL? {
        guard source != .work else { return nil }
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        let kind = source == .template ? "template" : "job"
        return URL(string: "https://pixarivo.get-free.net/share/\(kind)/\(id)")
    }

    static func prepare(
        title: String,
        description: String?,
        imageURL: URL?,
        source: PixaShareSource,
        templateID: String? = nil,
        tags: [String] = [],
        publicURL: URL? = nil
    ) async -> PixaSharePayload? {
        guard let request = PixaImageURLBuilder.resolve(
            from: imageURL,
            preset: .detail,
            maximumPixelWidth: 1_200
        ), let image = try? await PixaImageCache.shared.image(for: request) else {
            return nil
        }

        let artwork = PixaShareArtwork(
            title: title,
            description: description?.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source.localizedName,
            image: image,
            appStoreQRCode: makeQRCode(
                AppConfiguration.appStoreURL.absoluteString
            )
        )
        let renderer = ImageRenderer(content: artwork)
        // 分享图固定为 1080px 宽，兼顾微信清晰度和内存、上传体积。
        renderer.scale = 1.5
        guard let result = renderer.uiImage?.pixaOpaqueImage() else { return nil }
        // 公开案例优先展示模板样图与生成图；模板无法读取时保留原有网页卡片。
        var xImage: UIImage?
        if source == .gallery, let templateID,
           let sample = await templateSampleImage(id: templateID) {
            let comparison = PixaComparisonArtwork(sample: sample, result: image, title: title)
            let comparisonRenderer = ImageRenderer(content: comparison)
            comparisonRenderer.scale = 1
            xImage = comparisonRenderer.uiImage?.pixaOpaqueImage()
        }
        var items: [Any] = [PixaShareImageActivityItem(image: result, xImage: xImage, omitsX: publicURL != nil)]
        // X 分享正文包含模板简介；其他渠道继续使用本机海报。
        let xText = makeXText(
            title: title,
            introduction: source == .template ? description : nil,
            source: source,
            tags: tags,
            hasPublicURL: publicURL != nil
        )
        items.append(PixaXTextActivityItem(text: publicURL.map {
            "\(xText)\n\($0.absoluteString)"
        } ?? xText))
        return PixaSharePayload(items: items)
    }

    static func prepareForX(title: String, imageURL: URL?) async -> PixaSharePayload? {
        guard let request = PixaImageURLBuilder.resolve(
            from: imageURL,
            preset: .detail,
            maximumPixelWidth: 1_200
        ), let image = try? await PixaImageCache.shared.image(for: request) else {
            return nil
        }
        // 未公开作品只经系统分享界面传给用户选择的应用，不改变任务的公开状态。
        return PixaSharePayload(items: [image, makeXText(
            title: title,
            introduction: nil,
            source: .work,
            tags: [],
            hasPublicURL: false
        )])
    }

    private static func templateSampleImage(id: String) async -> UIImage? {
        guard !id.isEmpty, id.allSatisfy(\.isNumber),
              let template: StyleTemplate = try? await APIClient().get(
                "/api/ais/style-templates/\(id)",
                query: [.init(name: "language", value: AppLanguage.apiValue)]
              ),
              let url = template.sampleImageURL,
              let request = PixaImageURLBuilder.resolve(
                from: url,
                preset: .detail,
                maximumPixelWidth: 1_200
              ) else { return nil }
        return try? await PixaImageCache.shared.image(for: request)
    }

    private static func makeXText(
        title: String,
        introduction: String?,
        source: PixaShareSource,
        tags: [String],
        hasPublicURL: Bool
    ) -> String {
        // X 按加权字符计算，并将分享链接计为固定长度；额外预留少量空间给系统分享界面。
        let textLimit = 280 - (hasPublicURL ? 24 : 0) - 8
        var hashtags = ["#PixaRivo"]
        let candidates = (source == .template ? [AppLanguage.localized("share.x.template_tag")] : []) + tags
        for tag in candidates {
            let value = String(tag.filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(24))
            guard !value.isEmpty, !hashtags.contains(where: { $0.caseInsensitiveCompare("#\(value)") == .orderedSame }) else { continue }
            let hashtag = "#\(value)"
            guard weightedLength((hashtags + [hashtag]).joined(separator: " ")) <= 72 else { continue }
            hashtags.append(hashtag)
            if hashtags.count == 4 { break }
        }
        let suffix = hashtags.joined(separator: " ")
        let normalizedTitle = normalizedShareText(title)
        let heading = weightedPrefix(
            normalizedTitle.isEmpty ? source.localizedName : normalizedTitle,
            limit: min(90, textLimit - weightedLength(suffix) - 2)
        )
        guard source == .template else { return "\(heading)\n\(suffix)" }
        let normalizedIntroduction = normalizedShareText(introduction ?? "")
        let summary = normalizedIntroduction.isEmpty
            ? AppLanguage.localized("share.x.template_intro")
            : normalizedIntroduction
        let summaryLimit = textLimit - weightedLength(heading) - weightedLength(suffix) - 2
        let shortSummary = weightedPrefix(summary, limit: summaryLimit)
        return "\(heading)\n\(shortSummary)\n\(suffix)"
    }

    private static func normalizedShareText(_ value: String) -> String {
        value.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    private static func weightedLength(_ value: String) -> Int {
        value.unicodeScalars.reduce(0) { total, scalar in
            let code = scalar.value
            let singleWeight = code <= 0x10FF || (0x2000...0x200D).contains(code)
                || (0x2010...0x201F).contains(code) || (0x2032...0x2037).contains(code)
            return total + (singleWeight ? 1 : 2)
        }
    }

    private static func weightedPrefix(_ value: String, limit: Int) -> String {
        guard weightedLength(value) > limit else { return value }
        var result = ""
        for character in value {
            guard weightedLength(result) + weightedLength(String(character)) + 2 <= limit else { break }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func makeQRCode(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(
                  output,
                  from: output.extent
              ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

private enum PixaXActivity {
    static func matches(_ activityType: UIActivity.ActivityType?) -> Bool {
        guard let activityType else { return false }
        let identifier = activityType.rawValue.lowercased()
        return identifier.contains("tweetie")
            || identifier.contains("twitter")
            || identifier == "com.x.x.shareextension"
    }
}

private final class PixaShareImageActivityItem: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let xImage: UIImage?
    private let omitsX: Bool

    init(image: UIImage, xImage: UIImage?, omitsX: Bool) {
        self.image = image
        self.xImage = xImage
        self.omitsX = omitsX
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        if PixaXActivity.matches(activityType) { return xImage ?? (omitsX ? nil : image) }
        return image
    }
}

private struct PixaComparisonArtwork: View {
    let sample: UIImage
    let result: UIImage
    let title: String

    private let width: CGFloat = 1_200
    private var isLandscape: Bool { result.size.width > result.size.height * 1.1 }

    var body: some View {
        VStack(spacing: 0) {
            if isLandscape {
                comparisonPanel(sample, label: AppLanguage.isChinese ? "模板样图" : "Template", width: 1_160, height: 425)
                comparisonPanel(result, label: AppLanguage.isChinese ? "生成作品" : "Created", width: 1_160, height: 425)
            } else {
                HStack(spacing: 0) {
                    comparisonPanel(sample, label: AppLanguage.isChinese ? "模板样图" : "Template", width: 580, height: 770)
                    comparisonPanel(result, label: AppLanguage.isChinese ? "生成作品" : "Created", width: 580, height: 770)
                }
            }
            HStack {
                Text(title).font(.system(size: 32, weight: .bold)).lineLimit(1)
                Spacer(minLength: 20)
                Text("PixaRivo").font(.system(size: 25, weight: .bold, design: .serif))
            }
            .foregroundStyle(PixaTheme.ink)
            .padding(.horizontal, 28)
            .frame(height: 80)
        }
        .padding(20)
        .frame(width: width)
        .background(PixaTheme.paper)
        .environment(\.colorScheme, .light)
    }

    private func comparisonPanel(_ image: UIImage, label: String, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
            Text(label)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.68), in: Capsule())
                .padding(16)
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

private final class PixaXTextActivityItem: NSObject, UIActivityItemSource {
    private let text: String

    init(text: String) {
        self.text = text
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        text
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        guard PixaXActivity.matches(activityType) else { return nil }
        return text
    }
}

private struct PixaShareArtwork: View {
    let title: String
    let description: String?
    let source: String
    let image: UIImage
    let appStoreQRCode: UIImage?

    private let width: CGFloat = 720

    private var imageHeight: CGFloat {
        guard image.size.width > 0, image.size.height > 0 else { return width }
        return width * image.size.height / image.size.width
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .frame(width: width, height: imageHeight)

            HStack(spacing: 22) {
                Image("BrandIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 82, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(AppLanguage.localized("share.brand"))
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(PixaTheme.ink)
                        Text(source)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PixaTheme.accent)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(PixaTheme.accent.opacity(0.1), in: Capsule())
                    }
                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(PixaTheme.ink)
                        .lineLimit(2)
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 7) {
                    if let appStoreQRCode {
                        Image(uiImage: appStoreQRCode)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 92, height: 92)
                            .padding(6)
                            .background(
                                Color.white,
                                in: RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                            )
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "apple.logo")
                        Text(AppLanguage.localized("share.app_store"))
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PixaTheme.ink)
                }
            }
            .padding(28)
            .frame(width: width, alignment: .leading)
            .background {
                ZStack {
                    PixaTheme.paper
                    LinearGradient(
                        colors: [PixaTheme.accent.opacity(0.08), .clear],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                }
            }
        }
        .frame(width: width)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

struct PixaActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

struct PixaShareButton: View {
    let isPreparing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isPreparing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .frame(width: 34, height: 34)
            .foregroundStyle(PixaTheme.ink)
            .background(.ultraThinMaterial, in: Circle())
            .overlay { Circle().stroke(PixaTheme.line) }
        }
        .buttonStyle(.plain)
        .disabled(isPreparing)
        .accessibilityLabel("share.action")
    }
}

extension UIImage {
    /// 分享海报不需要透明通道，转为不透明图可降低保存和分享时的解码开销。
    fileprivate func pixaOpaqueImage(backgroundColor: UIColor = .white) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            backgroundColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
