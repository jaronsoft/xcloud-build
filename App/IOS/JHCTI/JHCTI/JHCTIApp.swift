import SwiftUI

@main
struct JHCTIApp: App {
    @State private var showingSplash = true
    @State private var homeReady = false
    @State private var splashMinimumElapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(onInitialHomeReady: { homeReady = true })
                    .opacity(showingSplash ? 0 : 1)
                    .allowsHitTesting(!showingSplash)
                if showingSplash {
                    SplashView(status: homeReady ? "首页已准备好，即将进入" : "正在加载首页数据…")
                        .task {
                            if !reduceMotion { try? await Task.sleep(for: .milliseconds(1800)) }
                            // 首页使用自身的加载与错误状态；网络请求不能无限延长启动页。
                            splashMinimumElapsed = true
                            showingSplash = false
                        }
                }
            }
            .onChange(of: homeReady) { _, ready in
                if ready && splashMinimumElapsed { showingSplash = false }
            }
            // 原生页面以小程序亮色配色为基准，系统夜间模式不应覆盖文本与控件颜色。
            .preferredColorScheme(.light)
        }
    }
}

private struct SplashView: View {
    let status: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoVisible = false
    @State private var backgroundDrifted = false

    private let bubbles: [(x: CGFloat, y: CGFloat, size: CGFloat, phase: Double)] = [
        (0.13, 0.78, 5, 0.0), (0.33, 0.63, 9, 0.3),
        (0.73, 0.76, 6, 0.7), (0.86, 0.57, 4, 0.2),
        (0.18, 0.38, 7, 0.9), (0.79, 0.30, 5, 1.1)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("SplashBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(reduceMotion ? 1 : 1.055)
                    .offset(x: reduceMotion ? 0 : (backgroundDrifted ? -11 : 11),
                            y: reduceMotion ? 0 : (backgroundDrifted ? 5 : -5))
                    .clipped()
                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        Canvas { context, size in
                            let seconds = timeline.date.timeIntervalSinceReferenceDate
                            // 丝带单独起伏，避免背景整体位移时看起来仍是静态图片。
                            for index in 0..<3 {
                                let wave = sin(seconds * 2.1 + Double(index) * 0.75) * 13
                                let inset = CGFloat(index) * 22
                                var ribbon = Path()
                                ribbon.move(to: CGPoint(x: -24, y: size.height * 0.76 + inset + wave))
                                ribbon.addCurve(
                                    to: CGPoint(x: size.width + 24, y: size.height * 0.48 + inset + wave),
                                    control1: CGPoint(x: size.width * 0.40, y: size.height * 0.66 + inset - wave),
                                    control2: CGPoint(x: size.width * 0.65, y: size.height * 0.76 + inset + wave)
                                )
                                context.stroke(ribbon, with: .color(.white.opacity(index == 0 ? 0.30 : 0.18)), lineWidth: index == 0 ? 2 : 1)
                            }
                            for (index, bubble) in bubbles.enumerated() {
                                let progress = (seconds / 2.1 + bubble.phase).truncatingRemainder(dividingBy: 1)
                                let center = CGPoint(x: size.width * bubble.x,
                                                     y: size.height * bubble.y - 49 * progress)
                                let circle = Path(ellipseIn: CGRect(x: center.x - bubble.size / 2,
                                                                    y: center.y - bubble.size / 2,
                                                                    width: bubble.size, height: bubble.size))
                                let opacity = 0.68 * (1 - progress)
                                if index.isMultiple(of: 3) {
                                    context.fill(circle, with: .color(.white.opacity(opacity * 0.6)))
                                }
                                context.stroke(circle, with: .color(.white.opacity(opacity)), lineWidth: 1)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
                VStack(spacing: 0) {
                    Text("江都 · 一程山水")
                        .font(.system(size: NativeTypography.size(12), weight: .medium))
                        .tracking(4)
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.top, geometry.size.height * 0.18)
                    Rectangle().fill(.white.opacity(0.46)).frame(width: 92, height: 1).padding(.top, 18)
                    Spacer()
                    Image("SplashLogo")
                        .resizable().scaledToFit()
                        .frame(width: 170, height: 170)
                        .scaleEffect(reduceMotion || logoVisible ? 1 : 0.72)
                        .rotationEffect(.degrees(reduceMotion || logoVisible ? 0 : -16))
                        .opacity(reduceMotion || logoVisible ? 1 : 0.35)
                        .background(Circle().fill(.white.opacity(0.055)).frame(width: 192, height: 192))
                        .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1.5).frame(width: 226, height: 226))
                    Text("悦行江都")
                        .font(.system(size: NativeTypography.size(37), weight: .bold))
                        .tracking(3)
                        .foregroundStyle(.white)
                        .padding(.top, 42)
                    Text("发现江都 · 乐享旅程")
                        .font(.system(size: NativeTypography.size(15)))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.top, 12)
                    Spacer()
                    Text("JIANGDU CULTURE & TRAVEL")
                        .font(.system(size: NativeTypography.size(10), weight: .medium))
                        .tracking(2.4)
                        .foregroundStyle(.white.opacity(0.6))
                    VStack(spacing: 10) {
                        ProgressView().progressViewStyle(.linear).tint(.white).frame(width: 168)
                        Text(status).font(.system(size: NativeTypography.size(12))).foregroundStyle(.white.opacity(0.86))
                    }
                    .padding(.top, 18)
                    .padding(.bottom, geometry.size.height * 0.07)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.85, dampingFraction: 0.66).delay(0.1)) { logoVisible = true }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    backgroundDrifted = true
                }
            }
        }
        .ignoresSafeArea()
    }
}

enum Brand {
    static let primary = Color(red: 0.086, green: 0.549, blue: 0.514)
    static let background = Color(red: 0.965, green: 0.977, blue: 0.972)
    static let ink = Color(red: 0.125, green: 0.243, blue: 0.227)
    static let muted = Color(red: 0.46, green: 0.54, blue: 0.52)
    static let border = Color(red: 0.89, green: 0.93, blue: 0.91)
}
