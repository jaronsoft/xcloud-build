import SwiftUI
import Combine
import VisionKit
import MapKit
import CoreLocation
import CryptoKit
import PhotosUI
import CoreTransferable
import WebKit
import UniformTypeIdentifiers


@MainActor
enum NativeTypography {
    private static var accessibilityScale: CGFloat = 1

    static func size(_ original: CGFloat) -> CGFloat {
        let standard: CGFloat
        switch original {
        case ..<10.5: standard = 12
        case ..<14: standard = 14
        case ..<16: standard = 16
        case ..<19: standard = 18
        case ..<21: standard = 20
        case ..<22: standard = 22
        case ...25: standard = 24
        case 30: standard = 32
        case 34: standard = 36
        default: standard = original
        }
        return standard * accessibilityScale
    }

    static func configuredSize(_ original: CGFloat) -> CGFloat {
        original * accessibilityScale
    }

    static func update(for size: DynamicTypeSize) {
        switch size {
        case .xSmall: accessibilityScale = 0.9
        case .small: accessibilityScale = 0.95
        case .medium, .large: accessibilityScale = 1
        case .xLarge: accessibilityScale = 1.12
        case .xxLarge: accessibilityScale = 1.24
        case .xxxLarge: accessibilityScale = 1.36
        case .accessibility1: accessibilityScale = 1.5
        case .accessibility2: accessibilityScale = 1.65
        case .accessibility3: accessibilityScale = 1.8
        case .accessibility4: accessibilityScale = 1.95
        case .accessibility5: accessibilityScale = 2.1
        @unknown default: accessibilityScale = 1
        }
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onInitialHomeReady: () -> Void
    @StateObject private var store = SessionStore()
    @State private var selectedTab = 0
    @State private var couponCenterRequested = false
    @State private var mapBackRequest = 0
    @State private var homeResetRequest = 0
    @State private var mapDetailActive = false
    @State private var discoveryKeyword = ""
    @State private var homePaneDestination: HomePaneDestination?
    @State private var foldedHomePaneDestination: HomePaneDestination?

    var body: some View {
        GeometryReader { geometry in
            // 以可用窗口宽度和横向比例判断双栏，适配系统未提供铰链状态的模拟器。
            let isWideEnough = geometry.size.width / max(geometry.size.height, 1) >= 1.15
            let isExpanded = horizontalSizeClass == .regular && isWideEnough && geometry.size.width >= 700
            let layout = Group {
                if isExpanded {
                    expandedLayout(width: geometry.size.width)
                } else {
                    compactLayout
                }
            }
            // 折叠态与展开态使用独立视图身份，避免 NavigationStack 保留已消失的右侧详情或系统侧栏。
            .id(isExpanded ? "duo-expanded" : "single-screen")
            .onChange(of: isExpanded, initial: true) { wasExpanded, expanded in
                if expanded {
                    if selectedTab == 0 { selectedTab = 1 }
                    if let destination = foldedHomePaneDestination {
                        homePaneDestination = destination
                        foldedHomePaneDestination = nil
                    }
                } else if wasExpanded {
                    foldedHomePaneDestination = homePaneDestination
                    resetToCompactHome()
                }
            }
            // 按当前可用窗口判断折叠屏布局，避免模拟器或系统未提供铰链状态时漏掉展开态。
            layout
                .environment(\.horizontalSizeClass, isExpanded ? .regular : .compact)
        }
        .onChange(of: dynamicTypeSize, initial: true) { _, size in
            NativeTypography.update(for: size)
        }
        .tint(Brand.primary)
        .simultaneousGesture(DragGesture(minimumDistance: 36)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard selectedTab == 1, mapDetailActive,
                      horizontal > 72, horizontal > abs(vertical) * 1.35 else { return }
                mapBackRequest += 1
            })
        // 根视图统一关闭系统 Tab 侧栏适配；单屏始终使用全宽内容和应用自绘底部导航。
        .toolbar(.hidden, for: .tabBar)
    }

    private func resetToCompactHome() {
        selectedTab = 0
        homePaneDestination = nil
        mapDetailActive = false
        homeResetRequest += 1
    }

    private func clearHomePaneDestination() {
        homePaneDestination = nil
        foldedHomePaneDestination = nil
    }

    private func openHomePaneDestination(_ destination: HomePaneDestination) {
        foldedHomePaneDestination = nil
        homePaneDestination = destination
    }

    private var compactLayout: some View {
        ZStack {
            HomeView(store: store, isVisible: selectedTab == 0, onMap: { clearHomePaneDestination(); selectedTab = 1 }, onBrowse: { clearHomePaneDestination(); selectedTab = 2 },
                     onProfile: { clearHomePaneDestination(); selectedTab = 4 }, onCouponCenter: { clearHomePaneDestination(); selectedTab = 4; couponCenterRequested = true },
                     onSearch: { discoveryKeyword = $0; clearHomePaneDestination(); selectedTab = 2 },
                     onDetailChange: { mapDetailActive = $0 },
                     onInitialLoadComplete: onInitialHomeReady, pinnedHome: false,
                     onPinnedDestination: { openHomePaneDestination($0) })
                .id(homeResetRequest)
                .compactTabPage(isSelected: selectedTab == 0)
            ResourceView(store: store, mapMode: true, initialKeyword: "", backRequest: mapBackRequest,
                         detailActive: $mapDetailActive, mapActive: selectedTab == 1)
                .compactTabPage(isSelected: selectedTab == 1)
            DiscoverView(store: store, initialKeyword: discoveryKeyword, onMap: { selectedTab = 1 })
                .compactTabPage(isSelected: selectedTab == 2)
            JourneyView(store: store, onMap: { selectedTab = 1 }, onProfile: { selectedTab = 4 })
                .compactTabPage(isSelected: selectedTab == 3)
            ProfileView(store: store, couponCenterRequested: couponCenterRequested,
                        onCouponCenterRequestHandled: { couponCenterRequested = false })
                .compactTabPage(isSelected: selectedTab == 4)
            if let destination = homePaneDestination {
                homeDestinationView(destination, isExpanded: false)
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 在单屏容器内再次收敛尺寸类别，避免 Duo 的 regular trait 让子导航恢复侧栏布局。
        .environment(\.horizontalSizeClass, .compact)
        // Duo 单屏可能仍继承 regular trait，显式隐藏系统 Tab 栏，避免右侧菜单挤压当前页面。
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !mapDetailActive {
                HStack(spacing: 0) {
                    ForEach(0..<5) { index in
                        Button {
                            if index == 0 {
                                selectedTab = 0
                                clearHomePaneDestination()
                                homeResetRequest += 1
                            } else if index == 1 && selectedTab == 1 {
                                mapBackRequest += 1
                            } else {
                                clearHomePaneDestination()
                                selectedTab = index
                            }
                        } label: {
                            VStack(spacing: 3) {
                                Image("Tab\(index * 2 + (selectedTab == index ? 1 : 0))")
                                    .resizable().scaledToFit().frame(width: 24, height: 24)
                                Text(["首页", "地图", "发现", "行程", "我的"][index])
                                    .font(.system(size: NativeTypography.size(10)))
                            }
                            .foregroundStyle(selectedTab == index ? Brand.primary : Brand.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .background(.white)
                .overlay(alignment: .top) { Brand.border.frame(height: 1) }
            }
        }
    }

    private func expandedLayout(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            HomeView(store: store, isVisible: true, onMap: { clearHomePaneDestination(); selectedTab = 1 }, onBrowse: { clearHomePaneDestination(); selectedTab = 2 },
                     onProfile: { clearHomePaneDestination(); selectedTab = 4 }, onCouponCenter: { clearHomePaneDestination(); selectedTab = 4; couponCenterRequested = true },
                     onSearch: { discoveryKeyword = $0; clearHomePaneDestination(); selectedTab = 2 },
                     onDetailChange: { mapDetailActive = $0 }, onInitialLoadComplete: onInitialHomeReady,
                     pinnedHome: true, onPinnedDestination: { openHomePaneDestination($0) })
                .id(homeResetRequest)
                .frame(width: min(max(width * 0.38, 350), 470))
                .overlay(alignment: .trailing) { Brand.border.frame(width: 1) }

            VStack(spacing: 0) {
                Group {
                    if let destination = homePaneDestination {
                        homeDestinationView(destination)
                    } else {
                        selectedPaneView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !mapDetailActive { paneTabBar }
            }
        }
        .background(Brand.background)
    }

    @ViewBuilder private var selectedPaneView: some View {
        switch selectedTab {
        case 1:
            ResourceView(store: store, mapMode: true, initialKeyword: "", backRequest: mapBackRequest,
                         detailActive: $mapDetailActive, mapActive: true)
        case 2:
            DiscoverView(store: store, initialKeyword: discoveryKeyword, onMap: { selectedTab = 1 })
        case 3:
            JourneyView(store: store, onMap: { selectedTab = 1 }, onProfile: { selectedTab = 4 })
        default:
            ProfileView(store: store, couponCenterRequested: couponCenterRequested,
                        onCouponCenterRequestHandled: { couponCenterRequested = false })
        }
    }

    @ViewBuilder private func homeDestinationView(_ destination: HomePaneDestination, isExpanded: Bool = true) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        clearHomePaneDestination()
                        mapDetailActive = false
                        if !isExpanded { selectedTab = 0 }
                    } label: {
                        Label("返回", systemImage: "chevron.left")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Brand.background)
                Group {
                    switch destination {
                    case .feature(let id): NativeFeaturePendingView(store: store, featureId: id)
                    case .catalog(let module): CatalogView(store: store, module: module)
                    case .scenic(let item, let guideRouteID): ResourceDetailView(store: store, item: item,
                        onVisibilityChange: { mapDetailActive = $0 }, initialGuideRouteID: guideRouteID)
                    case .activity(let id): ActivityDetailView(store: store, id: id)
                    case .article(let id, let siteID): ArticleDetailView(store: store, id: id, siteID: siteID)
                    case .product(let id): ProductDetailView(store: store, id: id, fallbackCover: nil)
                    case .hotel(let id): HotelPublicDetailView(store: store, id: id)
                    case .dining(let id): DiningPublicDetailView(store: store, id: id)
                    case .travelRoute(let id): TravelRouteDetailView(store: store, id: id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // 单屏详情使用自绘底栏；在详情导航栈再次隐藏系统 Tab 栏，防止 Duo regular trait 生成右侧菜单。
        .environment(\.horizontalSizeClass, isExpanded ? .regular : .compact)
        .toolbar(.hidden, for: .tabBar)
    }

    private var paneTabBar: some View {
        HStack(spacing: 0) {
            ForEach(1..<5) { index in
                Button {
                    if index == 1 && selectedTab == 1 { mapBackRequest += 1 }
                    clearHomePaneDestination()
                    selectedTab = index
                } label: {
                    VStack(spacing: 3) {
                        Image("Tab\(index * 2 + (selectedTab == index && homePaneDestination == nil ? 1 : 0))")
                            .resizable().scaledToFit().frame(width: 24, height: 24)
                        Text(["", "地图", "发现", "行程", "我的"][index])
                            .font(.system(size: NativeTypography.size(10)))
                    }
                    .foregroundStyle(selectedTab == index && homePaneDestination == nil ? Brand.primary : Brand.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 14)
        .background(.white)
        .overlay(alignment: .top) { Brand.border.frame(height: 1) }
    }
}

private extension View {
    func compactTabPage(isSelected: Bool) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }
}

struct NativePageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: NativeTypography.size(25), weight: .bold, design: .serif))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.system(size: NativeTypography.size(12)))
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
}

@MainActor func edgeBackGesture(_ action: @escaping () -> Void) -> some Gesture {
    DragGesture(minimumDistance: 24).onEnded { value in
        let horizontal = value.translation.width
        let vertical = value.translation.height
        guard value.startLocation.x <= 32, horizontal >= 72,
              horizontal > abs(vertical) * 1.25 else { return }
        action()
    }
}

private enum NativeHTMLTextParser {
    static let scriptStyle = try! NSRegularExpression(pattern: "(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>")
    static let blockEnd = try! NSRegularExpression(pattern: "(?i)</(p|div|li|h[1-6]|tr|blockquote|section|article)\\s*>")
    static let lineBreak = try! NSRegularExpression(pattern: "(?i)<br\\s*/?>")
    static let tags = try! NSRegularExpression(pattern: "(?s)<[^>]*>")
    static let entities = try! NSRegularExpression(
        pattern: "(?i)&(#(?:x[0-9a-f]+|[0-9]+)|amp|lt|gt|quot|apos|nbsp|mdash|ndash|hellip|copy|reg);?"
    )
}

func plainTextFromHTML(_ html: String) -> String {
    guard !html.isEmpty else { return "" }
    let source = html as NSString
    var value = NativeHTMLTextParser.scriptStyle.stringByReplacingMatches(
        in: html, range: NSRange(location: 0, length: source.length), withTemplate: ""
    )
    let blockSource = value as NSString
    value = NativeHTMLTextParser.blockEnd.stringByReplacingMatches(
        in: value, range: NSRange(location: 0, length: blockSource.length), withTemplate: "\\n"
    )
    let breakSource = value as NSString
    value = NativeHTMLTextParser.lineBreak.stringByReplacingMatches(
        in: value, range: NSRange(location: 0, length: breakSource.length), withTemplate: "\\n"
    )
    let tagSource = value as NSString
    value = NativeHTMLTextParser.tags.stringByReplacingMatches(
        in: value, range: NSRange(location: 0, length: tagSource.length), withTemplate: " "
    )

    let entitySource = value as NSString
    let entityMatches = NativeHTMLTextParser.entities.matches(
        in: value, range: NSRange(location: 0, length: entitySource.length)
    )
    let decoded = NSMutableString(string: value)
    for match in entityMatches.reversed() {
        let token = entitySource.substring(with: match.range).lowercased()
        let name = token.trimmingCharacters(in: CharacterSet(charactersIn: "&;"))
        let replacement: String
        switch name {
        case "amp": replacement = "&"
        case "lt": replacement = "<"
        case "gt": replacement = ">"
        case "quot": replacement = "\""
        case "apos": replacement = "'"
        case "nbsp": replacement = " "
        case "mdash": replacement = "—"
        case "ndash": replacement = "–"
        case "hellip": replacement = "…"
        case "copy": replacement = "©"
        case "reg": replacement = "®"
        default:
            let digits = String(name.dropFirst(1))
            let scalarValue = digits.first == "x"
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits, radix: 10)
            replacement = scalarValue.flatMap(Unicode.Scalar.init).map(String.init) ?? ""
        }
        decoded.replaceCharacters(in: match.range, with: replacement)
    }
    let normalized = (decoded as String)
        .replacingOccurrences(of: "[\\t\\x0B\\f\\r ]+", with: " ", options: .regularExpression)
        .replacingOccurrences(of: " *\\n *", with: "\\n", options: .regularExpression)
        .replacingOccurrences(of: "\\n{3,}", with: "\\n\\n", options: .regularExpression)
    return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
}

enum NativeHTMLBlock {
    case text(String)
    case image(URL, description: String)
}

enum NativeHTMLSourceBlock: Sendable {
    case text(String)
    case image(String, description: String)
}

func nativeHTMLSourceBlocks(_ html: String) -> [NativeHTMLSourceBlock] {
    guard let imagePattern = try? NSRegularExpression(pattern: "(?is)<img\\b[^>]*>") else {
        return html.isEmpty ? [] : [.text(html)]
    }
    let source = html as NSString
    let matches = imagePattern.matches(in: html, range: NSRange(location: 0, length: source.length))
    var blocks: [NativeHTMLSourceBlock] = []
    var cursor = 0
    for match in matches {
        let before = NSRange(location: cursor, length: match.range.location - cursor)
        if before.length > 0 { blocks.append(.text(source.substring(with: before))) }
        let tag = source.substring(with: match.range)
        if let sourcePattern = try? NSRegularExpression(pattern: "(?is)\\b(?:src|data-src)\\s*=\\s*(['\\\"])(.*?)\\1") {
            let tagSource = tag as NSString
            let path = sourcePattern.matches(in: tag, range: NSRange(location: 0, length: tagSource.length))
                .compactMap { Range($0.range(at: 2), in: tag).map { String(tag[$0]) } }
                .map { $0.replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            let altPattern = try? NSRegularExpression(pattern: "(?is)\\balt\\s*=\\s*(['\\\"])(.*?)\\1")
            let rawDescription = altPattern?.matches(in: tag, range: NSRange(location: 0, length: tagSource.length))
                .compactMap { Range($0.range(at: 2), in: tag).map { String(tag[$0]) } }
                .first ?? ""
            let description = String(plainTextFromHTML(rawDescription).prefix(200))
            if let path { blocks.append(.image(path, description: description)) }
        }
        cursor = match.range.location + match.range.length
    }
    if cursor < source.length { blocks.append(.text(source.substring(from: cursor))) }
    return blocks
}

@MainActor func nativeHTMLBlocks(_ html: String, api: MobileAPI) -> [NativeHTMLBlock] {
    var blocks: [NativeHTMLBlock] = []
    for block in nativeHTMLSourceBlocks(html) {
        switch block {
        case .text(let text): blocks.append(.text(text))
        case .image(let path, let description):
            if let url = api.mediaURL(path) { blocks.append(.image(url, description: description)) }
        }
    }
    return blocks
}

struct NativeRouteThemeImage: View {
    @ObservedObject var store: SessionStore
    let path: String?
    @State private var imageLoaded = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let url = MobileAPI(store: store).mediaURL(path) {
                CachedRemoteImage(url: url, onLoadResult: { imageLoaded = $0 }) {
                    Image("Quick7").resizable().scaledToFill()
                }
            } else {
                Image("Quick7").resizable().scaledToFill()
            }
            if !imageLoaded {
                Text("江都主题插画").font(.system(size: 9)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule()).padding(5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
}

func nativeTourismPrincipalFromToken(_ token: String) -> String {
    let parts = token.split(separator: ".")
    if parts.count == 3 {
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        if let data = Data(base64Encoded: payload),
           let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let subject = claims["sub"] as? String, !subject.isEmpty,
           let sessionId = claims["sid"] as? String, !sessionId.isEmpty { return subject + ":" + sessionId }
    }
    return SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
}

func nativeTourismPrincipal(_ token: String?) -> String? {
    guard let token else { return nil }
    return nativeTourismPrincipalFromToken(token)
}

func nativeLimitUtf16Text(_ value: String, maximum: Int) -> String {
    var output = String.UnicodeScalarView()
    var length = 0
    for scalar in value.unicodeScalars {
        let scalarLength = scalar.value > 0xFFFF ? 2 : 1
        guard length + scalarLength <= maximum else { break }
        output.append(scalar)
        length += scalarLength
    }
    return String(output)
}
