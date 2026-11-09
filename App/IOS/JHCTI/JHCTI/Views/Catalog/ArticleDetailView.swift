import Foundation
import SwiftUI
import UIKit
import WebKit

private struct NativeArticleWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    let imageURLs: [URL]
    let imageDescriptions: [URL: String]
    let onOpenImage: (URL) -> Void
    @Binding var contentHeight: CGFloat
    @Binding var isLoaded: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight, isLoaded: $isLoaded)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "articleImage")
        contentController.addUserScript(WKUserScript(source: """
        document.addEventListener('click', function(event) {
            var target = event.target instanceof Element ? event.target.closest('img') : null;
            if (!target) return;
            var url = target.currentSrc || target.src;
            if (!url) return;
            event.preventDefault();
            window.webkit.messageHandlers.articleImage.postMessage({ url: url });
        }, true);
        document.querySelectorAll('img').forEach(function(image) { image.style.cursor = 'zoom-in'; });
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.allowedImageURLs = Set(imageURLs)
        context.coordinator.onOpenImage = onOpenImage
        guard context.coordinator.renderedHTML != html else { return }
        context.coordinator.renderedHTML = html
        isLoaded = false
        let sanitized = html
            .replacingOccurrences(of: "(?is)<script\\b[^>]*>.*?</script\\s*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<iframe\\b[^>]*>.*?</iframe\\s*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)\\s+on[a-z]+\\s*=\\s*(['\"]).*?\\1", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)\\s+loading\\s*=\\s*(['\"])lazy\\1", with: "", options: .regularExpression)
        let document = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
        <style>html,body{margin:0;padding:0;background:#f5f8f7;color:#294b45;font:15px -apple-system,BlinkMacSystemFont,sans-serif;line-height:1.75;overflow-wrap:anywhere}body{padding:2px 0}img,video{max-width:100%;height:auto}table{max-width:100%;display:block;overflow-x:auto}p{margin:0 0 12px}a{color:#008f83}</style>
        </head><body>\(sanitized)</body></html>
        """
        view.loadHTMLString(document, baseURL: baseURL)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "articleImage")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var contentHeight: CGFloat
        @Binding var isLoaded: Bool
        var renderedHTML: String?
        var allowedImageURLs = Set<URL>()
        var onOpenImage: ((URL) -> Void)?

        init(contentHeight: Binding<CGFloat>, isLoaded: Binding<Bool>) {
            _contentHeight = contentHeight
            _isLoaded = isLoaded
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { value, _ in
                DispatchQueue.main.async {
                    if let height = value as? NSNumber {
                        self.contentHeight = max(80, CGFloat(height.doubleValue))
                    }
                    self.isLoaded = true
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.isLoaded = true }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.isLoaded = true }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "articleImage",
                  let payload = message.body as? [String: Any],
                  let rawURL = payload["url"] as? String,
                  let url = URL(string: rawURL), allowedImageURLs.contains(url) else { return }
            onOpenImage?(url)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            navigationAction.navigationType == .other ? .allow : .cancel
        }
    }
}

struct ArticleDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SessionStore
    let id: String
    var siteID: String? = "1"
    @State private var detail: [String: Any]?
    @State private var error: String?
    @State private var loading = true
    @State private var revision = 0
    @State private var contentHeight: CGFloat = 160
    @State private var articleContentLoaded = false
    @State private var articleImageURLs: [URL] = []
    @State private var articleImageDescriptions: [URL: String] = [:]
    @State private var articlePreviewIndex = 0
    @State private var articlePreviewing = false
    private var resolvedSiteID: String? {
        guard let siteID else { return nil }
        guard siteID.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
              Int64(siteID).map({ $0 > 0 && String($0) == siteID }) == true else { return "1" }
        return siteID
    }
    private var articleSiteQuery: String { resolvedSiteID.map { "&siteid=\($0)" } ?? "" }
    private var articleSiteCacheKey: String { resolvedSiteID ?? "current-tenant" }
    private var articleHTML: String { detail?["Contents"] as? String ?? "暂无正文内容。" }
    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if loading { ProgressView().tint(Brand.primary).frame(maxWidth: .infinity) }
                        if let error {
                            Text(error).foregroundStyle(.red)
                            Button("重试") { revision += 1 }
                        }
                        if let detail {
                            Group {
                                if let cover = MobileAPI(store: store).mediaURL(catalogCover(detail)) {
                                    CachedRemoteImage(url: cover) { Brand.background }
                                        .frame(maxWidth: .infinity).frame(height: 260).clipped()
                                } else {
                                    Brand.background.frame(height: 260)
                                }
                            }
                            .overlay(alignment: .top) {
                                LinearGradient(colors: [.white.opacity(0.68), .white.opacity(0)],
                                               startPoint: .top, endPoint: .bottom).frame(height: 145)
                            }
                            .padding(.horizontal, -16)
                            .padding(.top, -16)
                            Text((detail["ClassName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "江都文旅")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.primary)
                            Text(detail["Title"] as? String ?? "文旅资讯").font(.title2.bold()).foregroundStyle(Brand.ink)
                            if let subtitle = detail["Subtitle"] as? String, !subtitle.isEmpty {
                                Text(subtitle).font(.system(size: 15)).foregroundStyle(Brand.muted)
                            }
                            HStack {
                                Text((detail["Provider"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                                     ?? (detail["Author"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                                     ?? "悦行江都")
                                Spacer()
                                if let publishDate = bookingBusinessDateTime(detail["PublishTime"]).map({ String($0.prefix(10)) }) {
                                    Text(publishDate)
                                }
                            }
                            .font(.system(size: 11)).foregroundStyle(Brand.muted)
                            ZStack {
                                NativeArticleWebView(html: articleHTML,
                                                     baseURL: MobileAPI(store: store).mediaURL("/"),
                                                     imageURLs: articleImageURLs,
                                                     imageDescriptions: articleImageDescriptions,
                                                     onOpenImage: { url in
                                                         guard let index = articleImageURLs.firstIndex(of: url) else { return }
                                                         articlePreviewIndex = index
                                                         articlePreviewing = true
                                                     },
                                                     contentHeight: $contentHeight,
                                                     isLoaded: $articleContentLoaded)
                                    .frame(height: contentHeight)
                                if !articleContentLoaded {
                                    VStack(spacing: 10) {
                                        ProgressView().tint(Brand.primary)
                                        Text("正在加载文章内容…")
                                            .font(.system(size: NativeTypography.size(13))).foregroundStyle(Brand.muted)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 160)
                                    .background(Brand.background)
                                }
                            }
                            if articleContentLoaded {
                                ShareLink(
                                    item: "https://travel.jiangdu.net/subpackages/tourism/article/index?id=\(id)\(articleSiteQuery)",
                                    subject: Text(detail["Title"] as? String ?? "江都文旅资讯"),
                                    message: Text("发现江都文旅资讯，点击查看文章详情。")
                                ) {
                                    Label("分享文章", systemImage: "square.and.arrow.up")
                                        .font(.system(size: NativeTypography.size(14), weight: .semibold))
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .foregroundStyle(.white)
                                        .background(Brand.primary, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                .background(Brand.background)
                .ignoresSafeArea(edges: .top)
            }
        }
        .background(Brand.background)
        .fullScreenCover(isPresented: $articlePreviewing) {
            NativeHTMLGallery(urls: articleImageURLs, descriptions: articleImageDescriptions,
                              initialIndex: articlePreviewIndex) { articlePreviewing = false }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .simultaneousGesture(DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard value.startLocation.x <= 32,
                      horizontal >= 72, horizontal > abs(vertical) * 1.25 else { return }
                dismiss()
            })
        .task(id: articleHTML) {
            articleImageURLs = []
            articleImageDescriptions = [:]
            articlePreviewing = false
            let html = articleHTML
            let sources = await Task.detached(priority: .userInitiated) {
                nativeHTMLSourceBlocks(html).compactMap { block -> (String, String)? in
                    if case .image(let path, let description) = block { return (path, description) }
                    return nil
                }
            }.value
            guard !Task.isCancelled else { return }
            var urls: [URL] = []
            var descriptions: [URL: String] = [:]
            let api = MobileAPI(store: store)
            for (path, description) in sources {
                guard path.count <= 2048, !path.hasPrefix("//"), !path.contains("\\"),
                      path.rangeOfCharacter(from: .controlCharacters) == nil,
                      let url = api.mediaURL(path), !urls.contains(url) else { continue }
                urls.append(url)
                if !description.isEmpty { descriptions[url] = description }
            }
            articleImageURLs = urls
            articleImageDescriptions = descriptions
        }
        .task(id: "\(id):\(articleSiteCacheKey):\(revision)") {
            loading = true; error = nil; detail = nil
            articleContentLoaded = false
            articleImageURLs = []; articleImageDescriptions = [:]; articlePreviewing = false
            do {
                guard !id.isEmpty, id.allSatisfy(\.isNumber) else {
                    throw MobileAPIError.unavailable("内容地址无效")
                }
                guard await MobileAPI(store: store).featureEnabled("MODULE-GUIDE") else {
                    throw MobileAPIError.unavailable("旅游攻略模块暂未开放")
                }
                try Task.checkCancellation()
                guard let loaded = try await MobileAPI(store: store).getPublicCached(
                    "/api/app/articles/Detail?id=\(id)\(articleSiteQuery)",
                    forceRefresh: revision > 0 || resolvedSiteID == nil) as? [String: Any],
                      String(describing: loaded["Id"] ?? "") == id else {
                    throw MobileAPIError.unavailable("内容不存在或已下线")
                }
                try Task.checkCancellation()
                detail = loaded
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            if !Task.isCancelled { loading = false }
        }
    }
}
