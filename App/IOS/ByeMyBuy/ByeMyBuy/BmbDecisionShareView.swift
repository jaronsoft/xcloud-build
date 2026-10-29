import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit
import Photos

struct BmbDecisionShareView: View {
    let decision: BmbDecision
    var isPublished = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: BmbSession
    @State private var copied = false
    @State private var shareImage: BmbShareImage?
    @State private var preparingImage = false
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
                    Task { await prepareImage(forX: true) }
                } label: {
                    Label("Share to X", systemImage: "arrow.up.right")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .disabled(preparingImage)

                Text("Choose X in the share sheet to include the image and text.")
                    .font(.caption).foregroundStyle(BmbTheme.muted)

                Button {
                    Task { await prepareImage(forX: false) }
                } label: {
                    Label("Create share image", systemImage: "photo")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .disabled(preparingImage)

                if preparingImage { ProgressView("Preparing image…") }

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
            if let caption = item.caption {
                BmbImageActivityView(image: item.image, text: caption)
            } else {
                BmbShareImagePreview(image: item.image) {
                    Task { await session.api.track("share_action", shareToken: decision.ShareToken, token: session.token) }
                }
            }
        }
    }

    @MainActor
    private func prepareImage(forX: Bool) async {
        guard !preparingImage else { return }
        preparingImage = true
        error = nil
        defer { preparingImage = false }
        var image: UIImage?
        // 公开内容复用边缘生成的封面；私密内容只在本机生成，不进入公开图片缓存。
        if decision.Visibility == "public", decision.PublicReviewStatus == "approved",
           let url = URL(string: "https://byemybuy.get-free.net/share-images/\(decision.ShareToken).png") {
            do {
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   http.mimeType == "image/png", data.count <= 5 * 1024 * 1024 {
                    image = UIImage(data: data)
                }
            } catch { /* 边缘服务尚未上线或暂时不可用时，保留本机生成能力。 */ }
        }
        if image == nil {
            let renderer = ImageRenderer(content: BmbShareCard(decision: decision)
                .environment(\.locale, BmbLanguage.locale)
                .environment(\.colorScheme, .light))
            renderer.scale = 2
            image = renderer.uiImage
        }
        guard let image else {
            error = BmbLanguage.localized("Could not create the share image.")
            return
        }
        let caption = forX ? "\(decision.Question)\n\(decision.ShareUrl)" : nil
        shareImage = BmbShareImage(image: image, caption: caption)
        if forX { Task { await session.api.track("share_action", shareToken: decision.ShareToken, token: session.token) } }
    }
}

private struct BmbShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
    var caption: String? = nil
}

private struct BmbShareImagePreview: View {
    let image: UIImage
    let onShare: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false
    @State private var saving = false
    @State private var saved = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .accessibilityLabel(Text("Share image"))
                    Text("Scan the code on the image to join the decision.")
                        .font(.footnote).foregroundStyle(BmbTheme.muted)
                    Button {
                        Task { await saveImage() }
                    } label: {
                        Label(saving ? "Saving…" : saved ? "Saved to Photos" : "Save to Photos", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent).tint(BmbTheme.ink)
                    .disabled(saving || saved)
                    Button {
                        sharing = true
                        onShare()
                    } label: {
                        Label("Share image", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
                }
                .padding(20)
            }
            .background(BmbTheme.paper)
            .navigationTitle("Share image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $sharing) { BmbImageActivityView(image: image) }
        }
        .environment(\.locale, BmbLanguage.locale)
    }

    @MainActor
    private func saveImage() async {
        guard !saving && !saved else { return }
        saving = true
        error = nil
        defer { saving = false }
        // 仅在用户主动保存时申请添加权限，不读取相册中的其他照片。
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            error = BmbLanguage.localized("Allow adding photos in Settings, then try saving again.")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            saved = true
        } catch {
            self.error = BmbLanguage.localized("Could not save the image. Please try again.")
        }
    }
}

private struct BmbImageActivityView: UIViewControllerRepresentable {
    let image: UIImage
    var text: String? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [image]
        if let text { items.append(text) }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
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
