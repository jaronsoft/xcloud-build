import SwiftUI
import Combine
import AVFoundation
import AVKit
import CoreFoundation
import UIKit

// 按公开 DTO 的真实媒体字段取封面，保留旧字段兼容其他内容模块。
func catalogCover(_ item: [String: Any]) -> String? {
    for key in ["CoverImageUrl", "coverImageUrl", "ImageUrl", "imageUrl", "MediaUrls", "mediaUrls",
                "ImageUrls", "imageUrls", "ImagesList", "imagesList", "CoverUrl", "coverUrl"] {
        let candidates: [String]
        if let value = item[key] as? String {
            if value.hasPrefix("["), let data = value.data(using: .utf8),
               let urls = try? JSONSerialization.jsonObject(with: data) as? [String] {
                candidates = urls
            } else { candidates = [value] }
        }
        else { candidates = item[key] as? [String] ?? [] }
        if let cover = candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return cover
        }
    }
    return nil
}

struct NativeThemeCover: View {
    var imageName = "Quick4"
    var label = "主题插画"
    @State private var previewing = false

    var body: some View {
        Image(imageName).resizable().scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            .contentShape(Rectangle()).onTapGesture { previewing = true }
            .overlay(alignment: .bottomTrailing) {
                Text(label).font(.system(size: 11)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule()).padding(10)
            }
            .accessibilityLabel("\(label)，点击查看大图")
            .accessibilityAddTraits(.isButton)
            .fullScreenCover(isPresented: $previewing) {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    Image(imageName).resizable().scaledToFit()
                    Button("关闭") { previewing = false }
                        .foregroundStyle(.white).padding()
                        .accessibilityLabel("关闭\(label)预览")
                }
            }
    }
}

struct NativeProductGallery: View {
    let store: SessionStore
    let detail: [String: Any]?
    let fallback: String?
    var imageLabel = "商品"
    var height: CGFloat = 350
    var fallbackAsset: String? = nil
    var fallbackLabel: String? = nil
    @State private var index = 0
    @State private var previewIndex = 0
    @State private var previewing = false
    private var urls: [URL] {
        let paths = detail?["MediaUrls"] as? [String] ?? detail?["mediaUrls"] as? [String] ?? []
        var seen = Set<String>()
        let resolved = paths.compactMap { path -> URL? in
            guard !path.hasPrefix("//"), !path.contains("\\"), path.count <= 2048,
                  path.rangeOfCharacter(from: .controlCharacters) == nil,
                  let url = MobileAPI(store: store).mediaURL(path), seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }
        if resolved.isEmpty, let fallback = MobileAPI(store: store).mediaURL(fallback) { return [fallback] }
        return Array(resolved.prefix(20))
    }
    var body: some View {
        Group {
            if urls.isEmpty, let fallbackAsset {
                NativeThemeCover(imageName: fallbackAsset, label: fallbackLabel ?? "主题插画")
                    .frame(height: height)
            } else if urls.isEmpty { Brand.background.frame(height: height) }
            else {
                TabView(selection: $index) {
                    ForEach(Array(urls.enumerated()), id: \.element) { page, url in
                        NativeProductPhoto(url: url, fullSize: false, onOpen: { previewIndex = page; previewing = true },
                                           imageLabel: imageLabel, fallbackAsset: fallbackAsset, fallbackLabel: fallbackLabel)
                            .accessibilityLabel("\(imageLabel)图片\(page + 1)，点击查看大图").tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never)).frame(height: height)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(min(index + 1, urls.count)) / \(urls.count)")
                        .accessibilityLabel("第\(min(index + 1, urls.count))张，共\(urls.count)张")
                        .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(.white).background(.black.opacity(0.5), in: Capsule())
                        .padding(.trailing, 16).padding(.bottom, 25).allowsHitTesting(false)
                }
            }
        }
        .onChange(of: urls) { _, _ in index = 0; previewing = false }
        .fullScreenCover(isPresented: $previewing) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                TabView(selection: $previewIndex) {
                    ForEach(Array(urls.enumerated()), id: \.element) { page, url in
                        NativeProductPhoto(url: url, fullSize: true, onOpen: { previewing = false }, imageLabel: imageLabel,
                                           fallbackAsset: fallbackAsset, fallbackLabel: fallbackLabel).tag(page)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                HStack {
                    Text("\(min(previewIndex + 1, urls.count)) / \(urls.count)")
                        .accessibilityLabel("第\(min(previewIndex + 1, urls.count))张，共\(urls.count)张")
                        .font(.system(size: 14))
                    Spacer()
                    Button("关闭") { previewing = false }.accessibilityLabel("关闭\(imageLabel)图片大图")
                }.foregroundStyle(.white).padding()
            }
        }
    }
}

struct NativeProductPhoto: View {
    let url: URL
    let fullSize: Bool
    let onOpen: () -> Void
    var imageLabel: String = "商品"
    var imageDescription: String? = nil
    var fallbackAsset: String? = nil
    var fallbackLabel: String? = nil
    @State private var image: UIImage?
    @State private var loading = true
    @State private var retry = 0
    private var accessibleImageDescription: String {
        imageDescription.flatMap { $0.isEmpty ? nil : $0 } ?? "\(imageLabel)图片"
    }
    var body: some View {
        GeometryReader { bounds in
            Group {
                if let image {
                    Image(uiImage: image).resizable()
                        .aspectRatio(contentMode: fullSize ? .fit : .fill)
                        .frame(width: bounds.size.width, height: bounds.size.height).clipped()
                        .contentShape(Rectangle()).onTapGesture(perform: onOpen)
                        .accessibilityLabel("\(accessibleImageDescription)，\(fullSize ? "点击关闭大图" : "点击查看大图")")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: Text(fullSize ? "关闭大图" : "查看大图")) { onOpen() }
                } else if loading {
                    ProgressView().tint(fullSize ? .white : Brand.primary)
                } else if let fallbackAsset {
                    Image(fallbackAsset).resizable()
                        .aspectRatio(contentMode: fullSize ? .fit : .fill)
                        .frame(width: bounds.size.width, height: bounds.size.height).clipped()
                        .contentShape(Rectangle()).onTapGesture(perform: onOpen)
                        .overlay(alignment: .bottomTrailing) {
                            if !fullSize, let fallbackLabel {
                                Text(fallbackLabel).font(.system(size: 11)).foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.black.opacity(0.55), in: Capsule()).padding(10)
                            }
                        }
                } else {
                    VStack(spacing: 10) {
                        Text("图片暂时无法加载").font(.system(size: 13))
                        Button("重新加载") { retry += 1 }
                    }.foregroundStyle(fullSize ? .white : Brand.muted)
                }
            }.frame(width: bounds.size.width, height: bounds.size.height)
        }
        .task(id: retry) {
            loading = true
            let loaded = fullSize ? await NativePublicCache.shared.image(for: url)
                : await NativePublicCache.shared.thumbnail(for: url, width: 800)
            // 重试、切换和离页取消的旧任务不能覆盖当前图片状态。
            guard !Task.isCancelled else { return }
            image = loaded; loading = false
        }
    }
}

struct NativeProductVideoSection: View {
    let store: SessionStore
    let detail: [String: Any]
    @State private var selectedURL: URL?
    private var urls: [URL] {
        let values = detail["VideoUrls"] as? [String] ?? detail["videoUrls"] as? [String] ?? []
        var seen = Set<String>()
        return Array(values.compactMap { raw -> URL? in
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let isSafePath: Bool
            if path.hasPrefix("/") {
                isSafePath = !path.hasPrefix("//")
            } else if let components = URLComponents(string: path) {
                isSafePath = components.scheme?.lowercased() == "https" && components.host != nil
                    && components.user == nil && components.password == nil
            } else {
                isSafePath = false
            }
            guard !path.isEmpty, path.count <= 2048, !path.contains("\\"),
                  path.rangeOfCharacter(from: .controlCharacters) == nil,
                  isSafePath, seen.insert(path).inserted,
                  let url = MobileAPI(store: store).mediaURL(path), url.host != nil else { return nil }
            return url
        }.prefix(20))
    }
    var body: some View {
        if !urls.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("商品视频").font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.ink)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                            Button { selectedURL = url } label: {
                                Label("视频 \(index + 1)", systemImage: "play.circle")
                                    .font(.system(size: 13)).padding(10)
                                    .background(Brand.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                            }.accessibilityLabel("查看商品视频\(index + 1)")
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { selectedURL != nil }, set: { if !$0 { selectedURL = nil } })) {
                if let selectedURL { NativeProductVideoPlayer(url: selectedURL).id(selectedURL) }
            }
        }
    }
}

private struct NativeProductVideoPlayer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let url: URL
    @State private var player: AVPlayer?
    @State private var failed = false
    private let statusClock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text("商品视频").font(.headline); Spacer(); Button("关闭") { dismiss() } }.padding()
            if failed {
                Text("视频暂时无法播放，请重试。").foregroundStyle(Brand.muted)
                Button("重新加载") { load() }
            } else if let player {
                VideoPlayer(player: player).frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit)
            }
            Spacer()
        }
        .onAppear { load() }
        .onReceive(statusClock) { _ in
            if player?.currentItem?.status == .failed { player?.pause(); failed = true }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player?.pause() } }
        .onDisappear {
            // 关闭和离页时释放当前媒体，重新打开由用户再次触发播放。
            player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        }
    }
    private func load() {
        player?.pause(); failed = false
        player = AVPlayer(url: url)
    }
}

func nativeProductPrice(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let price = number.doubleValue
    return price.isFinite && price >= 0 ? price : nil
}
