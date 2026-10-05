import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct AISSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

enum AISShareArtworkLayout {
    static func imageHeight(
        width: CGFloat,
        imageSize: CGSize
    ) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return width
        }
        return width * imageSize.height / imageSize.width
    }
}

@MainActor
enum AISShareService {
    static let publicOrigin = URL(string: "https://ais.jaronsoft.com")!

    static func prepareLink(
        jobID: String,
        title: String
    ) -> AISSharePayload {
        let url = publicOrigin
            .appending(path: "share")
            .appending(path: jobID)
        return AISSharePayload(items: [title, url])
    }

    static func prepare(
        jobID: String,
        title: String,
        description: String,
        imageURL: URL?
    ) async -> AISSharePayload {
        let url = publicOrigin
            .appending(path: "share")
            .appending(path: jobID)
        UIPasteboard.general.url = url

        var artworkImage: UIImage?
        if let imageURL = AISImageURLBuilder.url(
            from: imageURL,
            preset: .detail
        ),
           let data = try? await AISImageCache.shared.data(for: imageURL),
           let resultImage = UIImage(data: data) {
            let artwork = AISShareArtwork(
                title: title,
                description: description,
                resultImage: resultImage,
                qrCode: makeQRCode(url.absoluteString)
            )
            let renderer = ImageRenderer(content: artwork)
            renderer.scale = UIScreen.main.scale
            artworkImage = renderer.uiImage?.aisOpaqueImage()
        }

        if let artworkImage {
            // 微信会把图片和链接拆成两个分享项；仅发送合成海报可保证二维码和品牌标识完整出现。
            return AISSharePayload(items: [artworkImage])
        }
        return AISSharePayload(items: [url])
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

private struct AISShareArtwork: View {
    let title: String
    let description: String
    let resultImage: UIImage
    let qrCode: UIImage?

    private let artworkWidth: CGFloat = 720
    private let titleColor = Color(
        red: 28 / 255,
        green: 32 / 255,
        blue: 36 / 255
    )
    private let descriptionColor = Color(
        red: 100 / 255,
        green: 108 / 255,
        blue: 114 / 255
    )

    private var artworkHeight: CGFloat {
        AISShareArtworkLayout.imageHeight(
            width: artworkWidth,
            imageSize: resultImage.size
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(uiImage: resultImage)
                .resizable()
                .frame(width: artworkWidth, height: artworkHeight)

            HStack(spacing: 22) {
                Image("BrandIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(titleColor)
                        .lineLimit(2)
                    if !description.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty {
                        Text(description)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(descriptionColor)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 12)

                if let qrCode {
                    Image(uiImage: qrCode)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 116, height: 116)
                        .padding(8)
                        .background(
                            Color.white,
                            in: RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                        )
                }
            }
            .padding(28)
            .frame(width: artworkWidth)
            .background {
                AISShareArtworkFooterBackground()
            }
        }
        .frame(width: artworkWidth)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

private struct AISShareArtworkFooterBackground: View {
    private let baseColor = Color(
        red: 247 / 255,
        green: 248 / 255,
        blue: 248 / 255
    )
    private let blueprintColor = Color(
        red: 128 / 255,
        green: 153 / 255,
        blue: 166 / 255
    )

    var body: some View {
        ZStack {
            baseColor

            LinearGradient(
                colors: [
                    blueprintColor.opacity(0.07),
                    Color.white.opacity(0.24),
                    Color.white.opacity(0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                drawGrid(context: &context, size: size)
                drawBlueprint(context: &context, size: size)
            }
        }
        .clipped()
    }

    private func drawGrid(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let patternWidth = size.width * 0.74
        let spacing: CGFloat = 34
        let gridColor = blueprintColor.opacity(0.045)

        var path = Path()
        var x: CGFloat = 0
        while x <= patternWidth {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }

        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: patternWidth, y: y))
            y += spacing
        }

        context.stroke(
            path,
            with: .color(gridColor),
            lineWidth: 0.7
        )
    }

    private func drawBlueprint(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let lineColor = blueprintColor.opacity(0.085)
        let fineLineColor = blueprintColor.opacity(0.055)
        let anchor = CGPoint(
            x: size.width * 0.09,
            y: size.height * 0.72
        )

        var arcs = Path()
        arcs.addEllipse(
            in: CGRect(
                x: anchor.x - 74,
                y: anchor.y - 74,
                width: 148,
                height: 148
            )
        )
        arcs.addEllipse(
            in: CGRect(
                x: anchor.x - 48,
                y: anchor.y - 48,
                width: 96,
                height: 96
            )
        )
        arcs.move(to: CGPoint(x: 0, y: anchor.y))
        arcs.addLine(to: CGPoint(x: size.width * 0.46, y: anchor.y))
        arcs.move(to: CGPoint(x: anchor.x, y: 0))
        arcs.addLine(to: CGPoint(x: anchor.x, y: size.height))
        context.stroke(
            arcs,
            with: .color(lineColor),
            lineWidth: 0.9
        )

        var floorPlan = Path()
        floorPlan.move(
            to: CGPoint(
                x: size.width * 0.24,
                y: size.height * 0.18
            )
        )
        floorPlan.addLine(
            to: CGPoint(
                x: size.width * 0.54,
                y: size.height * 0.18
            )
        )
        floorPlan.addLine(
            to: CGPoint(
                x: size.width * 0.54,
                y: size.height * 0.48
            )
        )
        floorPlan.addLine(
            to: CGPoint(
                x: size.width * 0.43,
                y: size.height * 0.48
            )
        )
        floorPlan.addLine(
            to: CGPoint(
                x: size.width * 0.43,
                y: size.height * 0.72
            )
        )
        floorPlan.addLine(
            to: CGPoint(
                x: size.width * 0.24,
                y: size.height * 0.72
            )
        )
        floorPlan.closeSubpath()

        floorPlan.move(
            to: CGPoint(
                x: size.width * 0.35,
                y: size.height * 0.18
            )
        )
        floorPlan.addLine(
            to: CGPoint(
                x: size.width * 0.35,
                y: size.height * 0.48
            )
        )
        floorPlan.move(
            to: CGPoint(
                x: size.width * 0.43,
                y: size.height * 0.48
            )
        )
        floorPlan.addLine(
            to: CGPoint(
                x: size.width * 0.54,
                y: size.height * 0.36
            )
        )

        context.stroke(
            floorPlan,
            with: .color(fineLineColor),
            lineWidth: 1
        )
    }
}

struct AISActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
