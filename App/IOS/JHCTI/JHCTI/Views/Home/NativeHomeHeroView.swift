import SwiftUI
import UIKit

private func bannerColor(_ value: String?, fallback: Color) -> Color {
    guard let value, value.count == 7, value.first == "#",
          let rgb = UInt64(value.dropFirst(), radix: 16) else { return fallback }
    return Color(.sRGB, red: Double((rgb >> 16) & 0xff) / 255,
                 green: Double((rgb >> 8) & 0xff) / 255, blue: Double(rgb & 0xff) / 255, opacity: 1)
}

private func bannerFontWeight(_ weight: Int) -> Font.Weight {
    switch weight {
    case ..<450: .regular
    case ..<550: .medium
    case ..<650: .semibold
    case ..<750: .bold
    default: .heavy
    }
}

private func bannerTitleFontDesign(_ value: String?) -> Font.Design {
    switch value {
    case "SystemSans", "Inherit": .default
    default: .serif
    }
}

@MainActor
private func bannerLineSpacing(fontSize: CGFloat, multiplier: CGFloat, isSerif: Bool) -> CGFloat {
    let scaledSize = NativeTypography.configuredSize(fontSize)
    let systemFont = UIFont.systemFont(ofSize: scaledSize)
    let design: UIFontDescriptor.SystemDesign = isSerif ? .serif : .default
    let font = systemFont.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: scaledSize) } ?? systemFont
    // SwiftUI 的 lineSpacing 是在字体自然行高上追加间距，因此先扣除系统字体自带行高。
    return scaledSize * multiplier - font.lineHeight
}

private func bannerTextAlignment(_ value: String?) -> TextAlignment {
    switch value?.lowercased() {
    case "center": .center
    case "right": .trailing
    default: .leading
    }
}

private struct NativeBannerImage: View {
    let url: URL?
    let fallback: String
    let focusX: CGFloat
    let focusY: CGFloat
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            if let image {
                let scale = max(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                let imageWidth = image.size.width * scale
                let imageHeight = image.size.height * scale
                Image(uiImage: image).resizable()
                    .frame(width: imageWidth, height: imageHeight)
                    .offset(x: (geometry.size.width - imageWidth) * min(1, max(0, focusX)),
                            y: (geometry.size.height - imageHeight) * min(1, max(0, focusY)))
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .clipped()
            } else {
                Image(fallback).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
        }
        .task(id: url) {
            image = nil
            let loaded = await NativePublicCache.shared.thumbnail(for: url, width: 400)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

struct NativeHomeHeroView: View {
    let store: SessionStore
    let slide: [String: Any]?
    let overlay: [String: Any]?
    let bannerSlides: [[String: Any]]
    let bannerDesign: [String: Any]?
    @Binding var bannerIndex: Int
    @Binding var bannerManualPauseUntil: Date
    @Binding var search: String
    let onSearch: (String) -> Void
    let onBannerTap: () -> Void

    var body: some View {
        let searchBar = bannerDesign?["SearchBar"] as? [String: Any] ?? [:]
        let showSearchBar = searchBar["IsVisible"] as? Bool ?? true
        let searchPlaceholder = String((searchBar["Placeholder"] as? String ?? "搜索景点、酒店、美食、活动、商品、线路…").prefix(100))
        let searchCornerRadius = CGFloat(min(48, max(0, (searchBar["CornerRadius"] as? NSNumber)?.doubleValue ?? 28)))
        let searchOpacity = min(1, max(0.5, (searchBar["Opacity"] as? NSNumber)?.doubleValue ?? 0.95))
        let imagePositionX = min(1, max(0, (slide?["ImagePositionX"] as? NSNumber)?.doubleValue ?? 0.5))
        let imagePositionY = min(1, max(0, (slide?["ImagePositionY"] as? NSNumber)?.doubleValue ?? 0.5))
        let slideAltText = (slide?["AltText"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let overlayOpacity = min(0.6, max(0, (slide?["OverlayOpacity"] as? NSNumber)?.doubleValue ?? 0))
        let configuredDecorAltText = (overlay?["DecorAltText"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let decorAltText = configuredDecorAltText.isEmpty ? "首页装饰图片" : configuredDecorAltText
        let title = overlay?["Title"] as? String ?? "龙舞江都\n运来未来"
        let subtitle = overlay?["Subtitle"] as? String ?? "品味千年古韵 · 畅游魅力江都"
        let titleVisible = overlay?["IsTextVisible"] as? Bool ?? true
        let decorVisible = overlay?["IsDecorVisible"] as? Bool ?? true
        let textLeft = CGFloat(min(0.65, max(0.02, (overlay?["TextLeft"] as? NSNumber)?.doubleValue ?? 0.08)))
        let textTop = CGFloat(min(0.5, max(0.18, (overlay?["TextTop"] as? NSNumber)?.doubleValue ?? 0.26)))
        let textBackgroundOpacity = min(0.85, max(0, (overlay?["TextBackgroundOpacity"] as? NSNumber)?.doubleValue ?? 0))
        let decorLeft = CGFloat(min(0.85, max(0, (overlay?["DecorLeft"] as? NSNumber)?.doubleValue ?? 0.55)))
        let decorTop = CGFloat(min(0.55, max(0, (overlay?["DecorTop"] as? NSNumber)?.doubleValue ?? 0.08)))
        let decorWidth = CGFloat(min(0.65, max(0.15, (overlay?["DecorWidth"] as? NSNumber)?.doubleValue ?? 0.4)))
        let decorHeight = CGFloat(min(0.8, max(0.15, (overlay?["DecorHeight"] as? NSNumber)?.doubleValue ?? 0.65)))
        let configuredLayers = (overlay?["OverlayLayerOrder"] as? [String] ?? []).reduce(into: [String]()) {
            if ($1 == "Text" || $1 == "Decor") && !$0.contains($1) { $0.append($1) }
        }
        let overlayLayers = configuredLayers + ["Decor", "Text"].filter { !configuredLayers.contains($0) }
        let textAboveDecor = (overlayLayers.firstIndex(of: "Text") ?? 1) > (overlayLayers.firstIndex(of: "Decor") ?? 0)

        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                NativeBannerImage(url: MobileAPI(store: store).mediaURL(slide?["ImageUrl"] as? String),
                                  fallback: "Hero", focusX: CGFloat(imagePositionX), focusY: CGFloat(imagePositionY))
                    .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        LinearGradient(colors: [Color.white.opacity(0.65), .clear, Brand.background.opacity(0.25)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(Color.black.opacity(overlayOpacity))
                    .accessibilityLabel(slideAltText)
                    .accessibilityHidden(slideAltText.isEmpty)
                if decorVisible {
                    NativeBannerImage(url: MobileAPI(store: store).mediaURL(overlay?["DecorImageUrl"] as? String),
                                      fallback: "Mascots", focusX: 0.5, focusY: 0.5)
                        .frame(width: geometry.size.width * decorWidth, height: geometry.size.height * decorHeight)
                        .padding(.leading, geometry.size.width * decorLeft).padding(.top, geometry.size.height * decorTop)
                        .accessibilityLabel(decorAltText)
                        .zIndex(textAboveDecor ? 3 : 4)
                }
                if titleVisible {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: NativeTypography.configuredSize(CGFloat((overlay?["TitleFontSize"] as? NSNumber)?.doubleValue ?? 35)),
                                          weight: bannerFontWeight(overlay?["TitleFontWeight"] as? Int ?? 700),
                                          design: bannerTitleFontDesign(overlay?["TitleFontFamily"] as? String)))
                            .foregroundStyle(bannerColor(overlay?["TitleColor"] as? String, fallback: Color(red: 20.0 / 255.0, green: 95.0 / 255.0, blue: 99.0 / 255.0)))
                            .multilineTextAlignment(bannerTextAlignment(overlay?["TitleTextAlign"] as? String))
                            .lineSpacing(bannerLineSpacing(
                                fontSize: CGFloat((overlay?["TitleFontSize"] as? NSNumber)?.doubleValue ?? 35),
                                multiplier: CGFloat((overlay?["TitleLineHeight"] as? NSNumber)?.doubleValue ?? 1.15),
                                isSerif: !["SystemSans", "Inherit"].contains(overlay?["TitleFontFamily"] as? String ?? "")
                            ))
                            .tracking(NativeTypography.configuredSize(CGFloat((overlay?["TitleLetterSpacing"] as? NSNumber)?.doubleValue ?? 0)))
                        Text(subtitle)
                            .font(.system(size: NativeTypography.configuredSize(CGFloat((overlay?["SubtitleFontSize"] as? NSNumber)?.doubleValue ?? 12)),
                                          weight: bannerFontWeight(overlay?["SubtitleFontWeight"] as? Int ?? 400),
                                          design: (overlay?["SubtitleFontFamily"] as? String) == "SystemSerif" ? .serif : .default))
                            .foregroundStyle(bannerColor(overlay?["SubtitleColor"] as? String, fallback: Brand.ink))
                            .multilineTextAlignment(bannerTextAlignment(overlay?["SubtitleTextAlign"] as? String))
                            .lineSpacing(bannerLineSpacing(
                                fontSize: CGFloat((overlay?["SubtitleFontSize"] as? NSNumber)?.doubleValue ?? 12),
                                multiplier: CGFloat((overlay?["SubtitleLineHeight"] as? NSNumber)?.doubleValue ?? 1.4),
                                isSerif: (overlay?["SubtitleFontFamily"] as? String) == "SystemSerif"
                            ))
                            .tracking(NativeTypography.configuredSize(CGFloat((overlay?["SubtitleLetterSpacing"] as? NSNumber)?.doubleValue ?? 0)))
                    }
                    .padding(textBackgroundOpacity > 0 ? 8 : 0)
                    .background(bannerColor(overlay?["TextBackgroundColor"] as? String, fallback: .white).opacity(textBackgroundOpacity),
                                in: RoundedRectangle(cornerRadius: textBackgroundOpacity > 0 ? 12 : 0))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(width: geometry.size.width * (1 - textLeft - 0.04), alignment: .leading)
                    .padding(.leading, geometry.size.width * textLeft).padding(.top, geometry.size.height * textTop)
                    .zIndex(textAboveDecor ? 4 : 3)
                }
                if showSearchBar {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Brand.muted)
                        TextField(searchPlaceholder, text: $search)
                            .font(.system(size: NativeTypography.size(13))).submitLabel(.search)
                            .onSubmit { onSearch(search.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                    .padding(.horizontal, 18).frame(height: 46)
                    .background(.white.opacity(searchOpacity), in: RoundedRectangle(cornerRadius: searchCornerRadius))
                    .padding(.horizontal, 22).frame(maxHeight: .infinity, alignment: .bottom)
                }
                if bannerSlides.count > 1 {
                    let indicatorStyle = bannerDesign?["IndicatorStyle"] as? String ?? "Dots"
                    if indicatorStyle == "Numbers" {
                        Text("\(bannerIndex + 1)/\(bannerSlides.count)")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(.black.opacity(0.35), in: Capsule())
                            .padding(.bottom, 80).frame(maxHeight: .infinity, alignment: .bottom)
                    } else if indicatorStyle != "None" {
                        HStack(spacing: 7) {
                            ForEach(bannerSlides.indices, id: \.self) { index in
                                Button {
                                    bannerIndex = index
                                    bannerManualPauseUntil = Date().addingTimeInterval(5)
                                } label: {
                                    Capsule().fill(index == bannerIndex ? Brand.primary : Color.white.opacity(0.7))
                                        .frame(width: index == bannerIndex ? 18 : 7, height: 7)
                                }.buttonStyle(.plain).accessibilityLabel("切换到第 \(index + 1) 张主视觉")
                            }
                        }.padding(.bottom, 80).frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .frame(height: 300)
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard bannerSlides.count > 1, value.startLocation.y < 220,
                      abs(horizontal) >= 36, abs(horizontal) > abs(vertical) * 1.2 else { return }
                let direction = horizontal < 0 ? 1 : -1
                let next = bannerIndex + direction
                let loops = bannerDesign?["Loop"] as? Bool ?? true
                if next < 0 { bannerIndex = loops ? bannerSlides.count - 1 : 0 }
                else if next >= bannerSlides.count { bannerIndex = loops ? 0 : bannerSlides.count - 1 }
                else { bannerIndex = next }
                bannerManualPauseUntil = Date().addingTimeInterval(5)
            })
            .onTapGesture(perform: onBannerTap)
        }
        .frame(height: 300)
    }
}
