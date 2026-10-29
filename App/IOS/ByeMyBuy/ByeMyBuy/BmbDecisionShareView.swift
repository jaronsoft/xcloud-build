import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

struct BmbDecisionShareView: View {
    let decision: BmbDecision
    var isPublished = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: BmbSession
    @State private var copied = false
    @State private var shareImage: BmbShareImage?
    @State private var error: String?

    private var shareURL: URL? { URL(string: decision.ShareUrl) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if isPublished {
                    Label("Published!", systemImage: "checkmark.circle.fill")
                        .font(.title.bold()).foregroundStyle(BmbTheme.ink)
                    Text("Your personal link is ready to share.")
                        .foregroundStyle(BmbTheme.muted)
                } else {
                    Text("Share this decision").font(.title2.bold())
                }

                BmbCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(decision.Question).font(.headline)
                        ForEach(Array(decision.Products.enumerated()), id: \.offset) { index, product in
                            Text(decision.Mode == "pick_one" ? "\(index == 0 ? "A" : "B"). \(product.Title)" : product.Title)
                                .font(.subheadline).foregroundStyle(BmbTheme.muted)
                        }
                        Text("Your link").font(.caption.bold()).foregroundStyle(BmbTheme.muted)
                        Text(decision.ShareUrl)
                            .font(.footnote).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Button {
                    UIPasteboard.general.string = decision.ShareUrl
                    copied = true
                    Task { await session.api.track("share_action", shareToken: decision.ShareToken, token: session.token) }
                } label: {
                    Label(copied ? "Link copied" : "Copy link", systemImage: copied ? "checkmark" : "link")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(BmbTheme.ink)

                if let shareURL {
                    ShareLink(item: shareURL) {
                        Label("More sharing options", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .simultaneousGesture(TapGesture().onEnded { Task { await session.api.track("share_action", shareToken: decision.ShareToken, token: session.token) } })
                }

                Button {
                    var components = URLComponents(string: "https://x.com/intent/tweet")
                    components?.queryItems = [
                        URLQueryItem(name: "text", value: decision.Question),
                        URLQueryItem(name: "url", value: decision.ShareUrl)
                    ]
                    if let url = components?.url { UIApplication.shared.open(url) }
                    Task { await session.api.track("share_action", shareToken: decision.ShareToken, token: session.token) }
                } label: {
                    Label("Share to X", systemImage: "arrow.up.right")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)

                Button {
                    let renderer = ImageRenderer(content: BmbShareCard(decision: decision))
                    renderer.scale = 2
                    if let image = renderer.uiImage {
                        shareImage = BmbShareImage(image: image)
                        Task { await session.api.track("share_action", shareToken: decision.ShareToken, token: session.token) }
                    } else {
                        error = BmbLanguage.localized("Could not create the share image.")
                    }
                } label: {
                    Label("Create share image", systemImage: "photo")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)

                if let error { Text(error).font(.caption).foregroundStyle(.red) }

                if isPublished {
                    NavigationLink {
                        DecisionView(shareToken: decision.ShareToken)
                    } label: {
                        Text("View decision").frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .background(BmbTheme.paper)
        .navigationTitle(isPublished ? "Decision published" : "Share")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        .sheet(item: $shareImage) { item in
            BmbImageActivityView(image: item.image)
        }
    }
}

private struct BmbShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct BmbImageActivityView: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct BmbShareCard: View {
    let decision: BmbDecision

    private var qrImage: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(decision.ShareUrl.utf8)
        filter.correctionLevel = "M"
        let context = CIContext()
        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            HStack {
                Image(systemName: "bag.fill")
                    .font(.system(size: 38)).foregroundStyle(Color(red: 0.27, green: 0.41, blue: 0.24))
                Text("ByeMyBuy").font(.system(size: 36, weight: .black, design: .rounded))
            }
            Text("THINK. ASK. DECIDE.")
                .font(.system(size: 16, weight: .bold)).tracking(3)
                .foregroundStyle(Color(red: 0.38, green: 0.48, blue: 0.34))
            Spacer(minLength: 20)
            Text(decision.Question.isEmpty ? BmbLanguage.localized("What do you think?") : decision.Question)
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.12, green: 0.17, blue: 0.13))
                .lineLimit(5).minimumScaleFactor(0.65)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(decision.Products.enumerated()), id: \.offset) { index, product in
                    Text(decision.Mode == "pick_one" ? "\(index == 0 ? "A" : "B")  \(product.Title)" : product.Title)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .foregroundStyle(Color(red: 0.12, green: 0.17, blue: 0.13))
                }
            }
            Spacer(minLength: 20)
            HStack(alignment: .bottom, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scan to join the decision")
                        .font(.system(size: 21, weight: .bold))
                    Text(decision.ShareUrl)
                        .font(.system(size: 14))
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 160, height: 160)
                }
            }
        }
        .padding(48)
        .frame(width: 720, height: 960)
        .background(Color(red: 0.91, green: 0.95, blue: 0.82))
    }
}
