import Photos
import SwiftUI
import UIKit

private struct PixaPrimaryButtonModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(
                isEnabled ? PixaTheme.accent : PixaTheme.accent.opacity(0.42),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .shadow(
                color: isEnabled ? PixaTheme.accent.opacity(0.18) : .clear,
                radius: 10,
                y: 5
            )
    }
}

extension View {
    func pixaPrimaryButton(isEnabled: Bool = true) -> some View {
        modifier(PixaPrimaryButtonModifier(isEnabled: isEnabled))
    }

    func pixaSurface(cornerRadius: CGFloat = 18) -> some View {
        background(
            Color.white.opacity(0.72),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(PixaTheme.line)
        }
    }
}

struct PixaLoadingStateView: View {
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var minHeight: CGFloat = 220

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 14) {
            brandLoader
            Text(title)
                .font(.headline)
                .foregroundStyle(PixaTheme.ink)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .accessibilityElement(children: .combine)
        .onAppear { updateAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateAnimation() }
    }

    private var brandLoader: some View {
        ZStack {
            Circle()
                .fill(PixaTheme.accent.opacity(0.09))
                .frame(width: 88, height: 88)
                .scaleEffect(isAnimating ? 1.08 : 0.92)
                .opacity(isAnimating ? 0.55 : 1)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.15).repeatForever(autoreverses: true),
                    value: isAnimating
                )

            Circle()
                .stroke(PixaTheme.accent.opacity(0.12), lineWidth: 2)
                .frame(width: 72, height: 72)

            Circle()
                .trim(from: 0.08, to: 0.38)
                .stroke(
                    AngularGradient(
                        colors: [PixaTheme.accent.opacity(0.12), PixaTheme.accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 72, height: 72)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    reduceMotion ? nil : .linear(duration: 1.5).repeatForever(autoreverses: false),
                    value: isAnimating
                )

            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: PixaTheme.accent.opacity(0.2), radius: 8, y: 4)

            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PixaTheme.accent)
                .offset(x: 33, y: -31)
                .scaleEffect(isAnimating ? 1.05 : 0.72)
                .opacity(isAnimating ? 1 : 0.4)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: isAnimating
                )
        }
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
    }

    private func updateAnimation() {
        isAnimating = !reduceMotion
    }
}

struct PixaSectionHeader<Trailing: View>: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let trailing: () -> Trailing

    init(
        eyebrow: LocalizedStringKey,
        title: LocalizedStringKey,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(PixaTheme.accent)
                .frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.caption2.bold())
                    .tracking(1.3)
                    .foregroundStyle(PixaTheme.accent)
                Text(title)
                    .font(.system(.title2, design: .serif, weight: .bold))
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension PixaSectionHeader where Trailing == EmptyView {
    init(eyebrow: LocalizedStringKey, title: LocalizedStringKey) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

struct PixaPromptBenefit: Identifiable {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var id: String { icon + String(describing: title) }
}

struct PixaPromptSheet: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let benefits: [PixaPromptBenefit]
    let primaryTitle: LocalizedStringKey
    let secondaryTitle: LocalizedStringKey
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(PixaTheme.ink.opacity(0.16))
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            ZStack {
                Circle()
                    .fill(PixaTheme.accent.opacity(0.1))
                    .frame(width: 86, height: 86)
                Circle()
                    .stroke(PixaTheme.accent.opacity(0.14), lineWidth: 1)
                    .frame(width: 68, height: 68)
                Image(systemName: icon)
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(PixaTheme.accent)
            }
            .padding(.top, 22)

            Text(title)
                .font(.system(.title2, design: .serif, weight: .bold))
                .foregroundStyle(PixaTheme.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 28)
                .padding(.top, 8)

            VStack(spacing: 14) {
                ForEach(benefits) { benefit in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: benefit.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PixaTheme.accent)
                            .frame(width: 34, height: 34)
                            .background(PixaTheme.accent.opacity(0.09), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(benefit.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(PixaTheme.ink)
                            Text(benefit.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
            .pixaSurface(cornerRadius: 16)
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Spacer(minLength: 18)

            Button {
                dismiss()
                onPrimary()
            } label: {
                Text(primaryTitle)
                    .pixaPrimaryButton()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            Button {
                dismiss()
                onSecondary()
            } label: {
                Text(secondaryTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .background(PixaTheme.paper.ignoresSafeArea())
    }
}

struct PixaNotificationPermissionPrompt: View {
    let onEnable: () -> Void
    var onNotNow: () -> Void = {}

    var body: some View {
        PixaPromptSheet(
            icon: "bell.badge.fill",
            title: "notification.permission.title",
            message: "notification.permission.message",
            benefits: [
                PixaPromptBenefit(
                    icon: "photo.badge.checkmark",
                    title: "notification.permission.works.title",
                    message: "notification.permission.works.message"
                ),
                PixaPromptBenefit(
                    icon: "sparkles",
                    title: "notification.permission.points.title",
                    message: "notification.permission.points.message"
                ),
                PixaPromptBenefit(
                    icon: "crown.fill",
                    title: "notification.permission.membership.title",
                    message: "notification.permission.membership.message"
                )
            ],
            primaryTitle: "notification.permission.enable",
            secondaryTitle: "notification.permission.not_now",
            onPrimary: onEnable,
            onSecondary: onNotNow
        )
        .presentationDetents([.height(590)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
        .presentationBackground(PixaTheme.paper)
    }
}

struct PixaPointsBadge: View {
    let points: Int
    var isRefreshing = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption.bold())
            Text(points, format: .number)
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if isRefreshing {
                ProgressView().controlSize(.mini)
            }
            Text("home.points.unit")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
        .foregroundStyle(PixaTheme.accent)
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(PixaTheme.accent.opacity(0.1), in: Capsule())
        .overlay { Capsule().stroke(PixaTheme.accent.opacity(0.2)) }
    }
}

struct PixaMembershipStatusBadge: View {
    let levelCode: String

    var body: some View {
        Image("MembershipLevel\(Self.iconLevel(for: levelCode))")
            .resizable()
            .scaledToFit()
            .frame(width: 22, height: 22)
            .frame(width: 36, height: 36)
            .background(Color.white.opacity(0.72), in: Circle())
            .overlay { Circle().stroke(PixaTheme.line) }
            .accessibilityLabel(Text(levelCode))
    }

    private static func iconLevel(for value: String) -> Int {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "vip": 1
        case "plus": 2
        case "pro": 3
        case "student", "student等级", "学生会员", "学生权益": 4
        case "max": 5
        case "enterprise", "企业": 6
        default: 1
        }
    }
}

@MainActor
struct RemoteArtwork: View {
    let url: URL?
    let aspectRatio: CGFloat
    var preset: PixaImagePreset = .list
    var maximumPixelWidth = 900
    var contentMode: ContentMode = .fill
    var usesIntrinsicAspectRatio = false

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var renderedWidth: CGFloat = 0
    @State private var deliveryRevision = 0
    @State private var displayedSourceURL: URL?
    @Environment(\.displayScale) private var displayScale

    private var request: PixaResolvedImageRequest? {
        _ = deliveryRevision
        let adaptive = preset == .list || preset == .largeList || preset == .thumbnail
        let pixelWidth = adaptive && renderedWidth > 0 ? Int(ceil(renderedWidth * displayScale)) : nil
        return PixaImageURLBuilder.resolve(
            from: url,
            preset: preset,
            targetPixelWidth: pixelWidth,
            maximumPixelWidth: maximumPixelWidth
        )
    }

    var body: some View {
        Color.clear
            .aspectRatio(layoutAspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    ZStack {
                        placeholder
                        if let image {
                            artwork(image, size: proxy.size)
                        } else if !didFail {
                            ProgressView()
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .onAppear { renderedWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in
                        if abs(renderedWidth - width) > 1 { renderedWidth = width }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .background(Color.black.opacity(0.035))
            .task(id: request) { [request, url] in
                await load(request, sourceURL: url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .pixaImageDeliveryDidChange)) { _ in
                deliveryRevision += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .pixaMediaRegionDidChange)) { _ in
                deliveryRevision += 1
            }
    }

    private var layoutAspectRatio: CGFloat {
        guard usesIntrinsicAspectRatio,
              let image,
              image.size.width > 0,
              image.size.height > 0 else {
            return max(0.1, aspectRatio)
        }
        return max(0.1, image.size.width / image.size.height)
    }

    @ViewBuilder
    private func artwork(_ image: UIImage, size: CGSize) -> some View {
        if contentMode == .fit {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
        } else {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        }
    }

    private var placeholder: some View {
        ZStack {
            PixaTheme.paper
            Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary)
        }
    }

    private func load(_ request: PixaResolvedImageRequest?, sourceURL: URL?) async {
        guard !Task.isCancelled else { return }
        if displayedSourceURL != sourceURL {
            image = nil
            displayedSourceURL = nil
        }
        didFail = false
        guard let request else {
            didFail = true
            return
        }
        let fallbackRequest = PixaImageURLBuilder.resolve(from: sourceURL, preset: .original)
        do {
            let loaded = try await PixaImageCache.shared.image(
                for: request,
                fallback: fallbackRequest
            )
            guard !Task.isCancelled else { return }
            image = loaded
            displayedSourceURL = sourceURL
        } catch {
            guard !Task.isCancelled else { return }
            didFail = true
        }
    }
}

struct MasonryLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    init(columns: Int = 2, spacing: CGFloat = 12) {
        self.columns = columns
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading, proposal: ProposedViewSize(width: result.columnWidth, height: nil))
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint], columnWidth: CGFloat) {
        let width = proposal.width ?? 320
        let columnWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        var heights = Array(repeating: CGFloat.zero, count: columns)
        var points: [CGPoint] = []
        for view in subviews {
            let column = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let size = view.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            points.append(CGPoint(x: CGFloat(column) * (columnWidth + spacing), y: heights[column]))
            heights[column] += size.height + spacing
        }
        return (CGSize(width: width, height: max(0, (heights.max() ?? 0) - spacing)), points, columnWidth)
    }
}

@MainActor
struct PixaArtworkPreview: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var didFail = false
    @State private var dismissOffset: CGFloat = 0
    @State private var isDownloading = false
    @State private var downloadAlert: PixaArtworkDownloadAlert?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { proxy in
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: proxy.size.width * zoom,
                                height: proxy.size.height * zoom
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                setZoom(zoom > 1 ? 1 : 2)
                            }
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        zoom = min(5, max(1, settledZoom * value))
                                    }
                                    .onEnded { _ in settledZoom = zoom }
                            )
                    }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(.center)
                } else if didFail {
                    ContentUnavailableView(
                        "network.invalid_response",
                        systemImage: "photo.badge.exclamationmark"
                    )
                    .foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .offset(y: dismissOffset)
        .opacity(max(0.45, 1 - dismissOffset / 500))
        .background(Color.black.ignoresSafeArea())
        .simultaneousGesture(swipeToDismissGesture)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.58), in: Circle())
            }
            .accessibilityLabel(Text("common.close"))
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 18) {
                Button { setZoom(zoom - 0.5) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .accessibilityLabel(Text("preview.zoom_out"))
                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 48)
                Button { setZoom(zoom + 0.5) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .accessibilityLabel(Text("preview.zoom_in"))

                Divider()
                    .frame(height: 22)
                    .overlay(.white.opacity(0.35))

                Button {
                    Task { await downloadOriginal() }
                } label: {
                    HStack(spacing: 6) {
                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.down.to.line")
                        }
                        Text("preview.download_original")
                            .font(.caption.weight(.semibold))
                    }
                }
                .disabled(isDownloading)
                .accessibilityLabel(Text("preview.download_original"))
            }
            .font(.title3)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 48)
            .background(.black.opacity(0.62), in: Capsule())
            .padding(.bottom, 8)
        }
        .task(id: url) { [url] in await load(url) }
        .alert(item: $downloadAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("common.ok"))
            )
        }
    }

    private func setZoom(_ value: CGFloat) {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoom = min(5, max(1, value))
            settledZoom = zoom
        }
    }

    private func downloadOriginal() async {
        guard !isDownloading else { return }
        isDownloading = true
        defer { isDownloading = false }

        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            downloadAlert = .permissionDenied
            return
        }
        guard let request = PixaImageURLBuilder.resolve(from: url, preset: .original) else {
            downloadAlert = .failed
            return
        }

        do {
            let data = try await PixaImageCache.shared.data(for: request)
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: data, options: nil)
            }
            downloadAlert = .saved
        } catch {
            downloadAlert = .failed
        }
    }

    private var swipeToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard zoom <= 1.01,
                      value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                dismissOffset = value.translation.height
            }
            .onEnded { value in
                guard zoom <= 1.01 else {
                    dismissOffset = 0
                    return
                }
                if value.translation.height > 100
                    && abs(value.translation.height) > abs(value.translation.width) {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        dismissOffset = 0
                    }
                }
            }
    }

    private func load(_ sourceURL: URL) async {
        guard !Task.isCancelled else { return }
        image = nil
        didFail = false
        zoom = 1
        settledZoom = 1
        dismissOffset = 0
        guard let request = PixaImageURLBuilder.resolve(
            from: sourceURL,
            preset: .detail,
            maximumPixelWidth: 2_048
        ) else {
            didFail = true
            return
        }
        let fallbackRequest = PixaImageURLBuilder.resolve(from: sourceURL, preset: .original)
        do {
            let loaded = try await PixaImageCache.shared.image(
                for: request,
                fallback: fallbackRequest
            )
            guard !Task.isCancelled else { return }
            image = loaded
        } catch {
            guard !Task.isCancelled else { return }
            didFail = true
        }
    }
}

private enum PixaArtworkDownloadAlert: String, Identifiable {
    case saved
    case permissionDenied
    case failed

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .saved: "preview.download_saved_title"
        case .permissionDenied, .failed: "preview.download_failed_title"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .saved: "preview.download_saved_message"
        case .permissionDenied: "preview.download_permission_denied"
        case .failed: "preview.download_failed_message"
        }
    }
}

struct TemplateCard: View {
    let template: StyleTemplate
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteArtwork(url: template.imageURL, aspectRatio: template.displayAspectRatio)
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .lineSpacing(1)
                HStack(spacing: 5) {
                    Text(template.aspectRatioText)
                    Text("·")
                    Text(String.localizedStringWithFormat(AppLanguage.localized("template.replace.summary"), template.imageSlots.count, template.textFields.filter(\.enabled).count))
                }
                .font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Label(template.heatScore.formatted(.number.notation(.compactName)), systemImage: "flame")
                    Label(template.viewCount.formatted(.number.notation(.compactName)), systemImage: "eye")
                    Label(template.usageCount.formatted(.number.notation(.compactName)), systemImage: "wand.and.stars")
                    Spacer(minLength: 2)
                    Text(String.localizedStringWithFormat(AppLanguage.localized("points.format"), template.basePointCost)).foregroundStyle(PixaTheme.accent)
                }
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
            }
            .padding(8)
        }
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(PixaTheme.line) }
        .frame(maxWidth: .infinity)
    }
}
