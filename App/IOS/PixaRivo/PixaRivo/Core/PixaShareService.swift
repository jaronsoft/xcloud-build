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
    static func prepare(
        title: String,
        description: String?,
        imageURL: URL?,
        source: PixaShareSource,
        xPrompt: String? = nil
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
        var items: [Any] = [result]
        if let xText = makeXText(title: title, prompt: xPrompt) {
            // 仅在用户选择 X 时返回文字，避免微信等渠道把海报与说明拆成多个分享项。
            items.append(PixaXPromptActivityItem(text: xText))
        }
        return PixaSharePayload(items: items)
    }

    private static func makeXText(title: String, prompt: String?) -> String? {
        let normalizedPrompt = prompt?
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedPrompt, !normalizedPrompt.isEmpty else { return nil }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = String.localizedStringWithFormat(
            AppLanguage.localized("share.x.template_prompt"),
            normalizedTitle
        )
        let suffix = "\n#PixaRivo"
        // 为 X 的媒体分享和不同字符计数规则预留余量，超长公开提示词只截取可读摘要。
        let promptLimit = max(40, 240 - heading.count - suffix.count - 1)
        let summarizedPrompt = normalizedPrompt.count > promptLimit
            ? String(normalizedPrompt.prefix(max(1, promptLimit - 1))) + "…"
            : normalizedPrompt
        return "\(heading)\n\(summarizedPrompt)\(suffix)"
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

private final class PixaXPromptActivityItem: NSObject, UIActivityItemSource {
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
        guard let activityType, Self.isX(activityType) else { return nil }
        return text
    }

    private static func isX(_ activityType: UIActivity.ActivityType) -> Bool {
        let identifier = activityType.rawValue.lowercased()
        return identifier.contains("tweetie")
            || identifier.contains("twitter")
            || identifier == "com.x.x.shareextension"
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
