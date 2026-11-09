import SwiftUI
import UIKit

struct NativeHTMLImage: View {
    let url: URL
    let description: String
    let onOpen: () -> Void
    @State private var image: UIImage?
    @State private var loading = true
    @State private var retry = 0
    @State private var failed = false
    @State private var imageAspectRatio: CGFloat?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .aspectRatio(max(0.45, min(2.5, image.size.width / max(image.size.height, 1))), contentMode: .fit)
                    .contentShape(Rectangle()).onTapGesture(perform: onOpen)
                    .accessibilityLabel("\(description.isEmpty ? "图文介绍图片" : description)，点击查看大图")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: Text("查看大图")) { onOpen() }
            } else if loading {
                ProgressView().frame(maxWidth: .infinity).aspectRatio(imageAspectRatio, contentMode: .fit)
                    .frame(minHeight: 120)
            } else {
                VStack {
                    Text("图片暂不可用")
                    Button("重新加载") { failed = false; retry += 1 }
                }.font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                    .frame(maxWidth: .infinity).aspectRatio(imageAspectRatio, contentMode: .fit)
                    .frame(minHeight: 120).background(Brand.background)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: "\(url.absoluteString):\(retry)") {
            guard !failed else { return }
            loading = true; image = nil
            let loaded = await NativePublicCache.shared.thumbnail(for: url, width: 800)
            guard !Task.isCancelled else { return }
            if let loaded {
                imageAspectRatio = max(0.45, min(2.5, loaded.size.width / max(loaded.size.height, 1)))
            } else {
                failed = true
            }
            image = loaded; loading = false
        }
        .onDisappear { image = nil; loading = false }
    }
}

struct NativeHTMLContent: View {
    let html: String
    let store: SessionStore
    var fontSize: CGFloat = 13
    @State private var sourceBlocks: [NativeHTMLSourceBlock]?
    @State private var previewIndex = 0
    @State private var previewing = false

    var body: some View {
        let api = MobileAPI(store: store)
        let blocks = (sourceBlocks ?? []).compactMap { block -> NativeHTMLBlock? in
            switch block {
            case .text(let text): return .text(text)
            case .image(let path, let description):
                return api.mediaURL(path).map { .image($0, description: description) }
            }
        }
        Group {
            if sourceBlocks == nil {
                ProgressView("正在整理图文内容…")
                    .frame(maxWidth: .infinity).frame(minHeight: 120)
            } else {
                htmlContent(blocks)
            }
        }
        .task(id: html) {
            previewing = false
            previewIndex = 0
            sourceBlocks = nil
            let parsed = await Task.detached(priority: .userInitiated) {
                nativeHTMLSourceBlocks(html).compactMap { block -> NativeHTMLSourceBlock? in
                    switch block {
                    case .text(let source):
                        let text = plainTextFromHTML(source)
                        return text.isEmpty ? nil : .text(text)
                    case .image:
                        return block
                    }
                }
            }.value
            guard !Task.isCancelled else { return }
            sourceBlocks = parsed
        }
    }

    @ViewBuilder private func htmlContent(_ blocks: [NativeHTMLBlock]) -> some View {
        let urls = blocks.compactMap { block -> URL? in
            if case .image(let url, _) = block { return url }; return nil
        }.reduce(into: [URL]()) { if !$0.contains($1) { $0.append($1) } }
        let descriptions = blocks.reduce(into: [URL: String]()) { result, block in
            if case .image(let url, let description) = block, result[url]?.isEmpty != false, !description.isEmpty {
                result[url] = description
            }
        }
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let source):
                    Text(source).font(.system(size: NativeTypography.size(fontSize))).foregroundStyle(Brand.ink)
                        .lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                case .image(let url, let description):
                    NativeHTMLImage(url: url, description: description) {
                        guard let page = urls.firstIndex(of: url) else { return }
                        previewIndex = page; previewing = true
                    }.id(url)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: html) { _, _ in previewing = false; previewIndex = 0 }
        .fullScreenCover(isPresented: $previewing) {
            NativeHTMLGallery(urls: urls, descriptions: descriptions, initialIndex: previewIndex) { previewing = false }
        }
    }
}

struct NativeHTMLGallery: View {
    let urls: [URL]
    let descriptions: [URL: String]
    let onClose: () -> Void
    @State private var index: Int

    init(urls: [URL], descriptions: [URL: String], initialIndex: Int, onClose: @escaping () -> Void) {
        self.urls = urls; self.descriptions = descriptions; self.onClose = onClose
        _index = State(initialValue: min(max(0, initialIndex), max(0, urls.count - 1)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.element) { page, url in
                    NativeProductPhoto(url: url, fullSize: true, onOpen: onClose, imageLabel: "图文介绍", imageDescription: descriptions[url]).tag(page)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            HStack {
                Text("\(min(index + 1, urls.count)) / \(urls.count)")
                    .accessibilityLabel("第\(min(index + 1, urls.count))张，共\(urls.count)张")
                Spacer()
                Button("关闭", action: onClose).frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("关闭图文图片预览")
            }.font(.system(size: 14)).foregroundStyle(.white).padding(.horizontal)
        }
    }
}
