import SwiftUI
import UIKit

@main
struct ByeMyBuyApp: App {
    @StateObject private var session = BmbSession()
    @State private var incomingToken: BmbTokenItem?
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var unread = 0
    @AppStorage("bmb.theme") private var themePreference = "system"

    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house") }
                NavigationStack { ExploreView() }
                    .tabItem { Label("Explore", systemImage: "square.grid.2x2") }
                NavigationStack { MineView() }
                    .tabItem { Label("My decisions", systemImage: "square.stack") }
                NavigationStack { BmbNotificationsView() }
                    .tabItem { Label(BmbEngagementCopy.text("Messages", "消息"), systemImage: "bell") }.badge(unread)
                NavigationStack { AccountView() }
                    .tabItem { Label("Account", systemImage: "person.crop.circle") }
            }
            .tint(BmbTheme.ink)
            .preferredColorScheme(themePreference == "system" ? nil : themePreference == "dark" ? .dark : .light)
            .overlay {
                if showSplash {
                    BmbSplashView { showSplash = false }
                        .transition(.opacity)
                }
            }
            .environmentObject(session)
            .task(id: "\(scenePhase)-\(session.token ?? "")") {
                guard scenePhase == .active, let token = session.token else { unread = 0; return }
                while !Task.isCancelled {
                    do {
                        let result: BmbUnread = try await session.api.call("/notifications/unread", token: token)
                        unread = result.Count
                    } catch { }
                    do { try await Task.sleep(for: .seconds(60)) } catch { break }
                }
            }
            .sheet(isPresented: $session.showLogin) {
                NavigationStack { LoginView() }.environmentObject(session)
            }
            .sheet(item: $incomingToken) { token in
                NavigationStack { DecisionView(shareToken: token.value) }.environmentObject(session)
            }
            .onOpenURL { url in
                if url.host == "byemybuy.get-free.net", url.path.hasPrefix("/d/") {
                    incomingToken = BmbTokenItem(value: String(url.path.dropFirst(3)))
                }
            }
        }
    }
}

struct BmbTokenItem: Identifiable {
    let value: String
    var id: String { value }
}

enum BmbTheme {
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
    static let paper = adaptive(light: UIColor(red: 0.973, green: 0.961, blue: 0.933, alpha: 1), dark: UIColor(red: 0.078, green: 0.11, blue: 0.094, alpha: 1))
    static let ink = adaptive(light: UIColor(red: 0.125, green: 0.149, blue: 0.137, alpha: 1), dark: UIColor(red: 0.957, green: 0.965, blue: 0.937, alpha: 1))
    static let lime = adaptive(light: UIColor(red: 0.843, green: 0.937, blue: 0.545, alpha: 1), dark: UIColor(red: 0.788, green: 0.906, blue: 0.467, alpha: 1))
    static let muted = adaptive(light: UIColor(red: 0.45, green: 0.51, blue: 0.44, alpha: 1), dark: UIColor(red: 0.659, green: 0.718, blue: 0.667, alpha: 1))
    static let card = adaptive(light: UIColor(red: 0.998, green: 0.996, blue: 0.977, alpha: 1), dark: UIColor(red: 0.114, green: 0.157, blue: 0.133, alpha: 1))
    static let hero = adaptive(light: UIColor(red: 0.91, green: 0.95, blue: 0.82, alpha: 1), dark: UIColor(red: 0.153, green: 0.224, blue: 0.173, alpha: 1))
}

enum BmbMoney {
    static func number(_ amount: Double) -> String {
        amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
    }

    static func display(_ amount: Double, currency: String?) -> String {
        [currency, number(amount)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct BmbCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(BmbTheme.card, in: RoundedRectangle(cornerRadius: 23))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(BmbTheme.ink.opacity(0.07)))
    }
}

struct BmbPrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Image(systemName: "arrow.right") }
                .font(.system(size: 15, weight: .bold))
                .padding(17).foregroundStyle(Color(red: 0.125, green: 0.169, blue: 0.141))
                .background(BmbTheme.lime, in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }
}

struct BmbProductCard: View {
    let product: BmbProduct
    let label: String?
    var body: some View {
        BmbCard {
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 17).fill(BmbTheme.hero)
                        if let image = product.ImageUrl, let url = URL(string: image) {
                            BmbCachedImage(url: url) {
                                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.brown.opacity(0.4))
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 52)).foregroundStyle(.brown.opacity(0.4))
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                        if let label { Text(label).font(.caption.bold()).padding(9).background(.white, in: RoundedRectangle(cornerRadius: 8)).padding(10) }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 17))
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.Title.isEmpty ? "Your next find" : product.Title).font(.headline).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let model = product.Model, !model.isEmpty {
                        Text(model).font(.caption).foregroundStyle(BmbTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let price = product.Price {
                        Text(BmbMoney.display(price, currency: product.Currency)).font(.subheadline.bold())
                    }
                }
                if let tags = product.Tags, !tags.isEmpty {
                    Text(tags.map { "#\($0)" }.joined(separator: "  ")).font(.caption).foregroundStyle(BmbTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let link = product.Url, let url = URL(string: link) {
                    Link(destination: url) { Label("View at store", systemImage: "arrow.up.right").font(.caption.bold()).foregroundStyle(.green) }
                }
            }
        }
    }
}

struct BmbSplashView: View {
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bagX: CGFloat = -170
    @State private var bagRotation = -18.0
    @State private var bagScaleX = 1.0
    @State private var bagScaleY = 1.0
    @State private var badgeX: CGFloat = 175
    @State private var badgeRotation = 25.0
    @State private var badgeOpacity = 0.0
    @State private var buyOpacity = 1.0
    @State private var impact = false
    @State private var surprised = false
    @State private var showingLaunchMark = true
    @State private var finished = false

    var body: some View {
        ZStack {
            BmbTheme.paper.ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Image("LaunchMark").resizable().interpolation(.high)
                        .frame(width: 260, height: 260)
                        .opacity(showingLaunchMark ? 1 : 0)

                    ZStack {
                        Text("BUY")
                            .font(.system(size: 20, weight: .black, design: .rounded)).tracking(3)
                            .foregroundStyle(BmbTheme.ink)
                            .padding(.horizontal, 17).padding(.vertical, 10)
                            .background(BmbTheme.lime, in: RoundedRectangle(cornerRadius: 13))
                            .offset(x: 105, y: 32).opacity(buyOpacity)

                        Image("SplashBag").resizable().interpolation(.high)
                            .frame(width: 142, height: 142)
                            .clipShape(RoundedRectangle(cornerRadius: 31))
                            .scaleEffect(x: bagScaleX, y: bagScaleY)
                            .rotationEffect(.degrees(bagRotation))
                            .offset(x: bagX, y: 18)

                        Text("?!")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 1, green: 0.447, blue: 0.353))
                            .rotationEffect(.degrees(-18))
                            .scaleEffect(impact ? 1 : 0.3)
                            .offset(x: -91, y: -87).opacity(impact ? 1 : 0)
                        Image(systemName: "sparkles")
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(Color(red: 1, green: 0.447, blue: 0.353))
                            .offset(x: 125, y: -94).opacity(impact ? 1 : 0)

                        Text("−").font(.system(size: 48, weight: .black))
                            .foregroundStyle(Color(red: 1, green: 0.973, blue: 0.922))
                            .frame(width: 66, height: 66)
                            .background(Color(red: 1, green: 0.447, blue: 0.353), in: Circle())
                            .overlay(Circle().stroke(BmbTheme.lime, lineWidth: 4))
                            .rotationEffect(.degrees(badgeRotation))
                            .offset(x: badgeX, y: -52).opacity(badgeOpacity)
                    }
                    .opacity(showingLaunchMark ? 0 : 1)
                }.frame(width: 300, height: 260).accessibilityHidden(true)
                Text("ByeMyBuy").font(.system(size: 36, weight: .black, design: .rounded))
                Text(surprised ? String(localized: "Whoa! Ask first.") : String(localized: "Hear what others think?"))
                    .font(.subheadline.weight(.medium)).foregroundStyle(BmbTheme.muted)
                    .opacity(showingLaunchMark ? 0 : 1)
            }
            VStack {
                Spacer()
                Button("Skip animation", action: finish)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BmbTheme.muted)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .padding(.bottom, 18)
            }
        }
        .contentShape(Rectangle()).onTapGesture(perform: finish)
        .task { await play() }
    }

    @MainActor
    private func play() async {
        if reduceMotion { finish(); return }
        guard await pause(120) else { return }
        withAnimation(.easeOut(duration: 0.16)) { showingLaunchMark = false }
        withAnimation(.easeIn(duration: 0.42)) {
            bagX = 54
            bagRotation = 14
        }
        guard await pause(420) else { return }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.52)) {
            badgeX = 82
            badgeRotation = -15
            badgeOpacity = 1
            bagX = 28
            bagRotation = -17
            bagScaleX = 1.17
            bagScaleY = 0.76
            buyOpacity = 0
            impact = true
            surprised = true
        }
        guard await pause(280) else { return }

        withAnimation(.spring(response: 0.48, dampingFraction: 0.42)) {
            bagX = -37
            bagRotation = 15
            bagScaleX = 0.91
            bagScaleY = 1.12
            badgeRotation = 10
            impact = false
        }
        guard await pause(420) else { return }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
            bagX = 0
            bagRotation = 0
            bagScaleX = 1
            bagScaleY = 1
            badgeRotation = 0
        }
        guard await pause(720) else { return }
        finish()
    }

    private func pause(_ milliseconds: Int) async -> Bool {
        do { try await Task.sleep(for: .milliseconds(milliseconds)) }
        catch { return false }
        return !Task.isCancelled && !finished
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        if reduceMotion { dismiss() }
        else { withAnimation(.easeOut(duration: 0.2)) { dismiss() } }
    }
}
