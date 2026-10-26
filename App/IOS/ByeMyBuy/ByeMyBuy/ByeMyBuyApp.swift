import SwiftUI
import UIKit

@main
struct ByeMyBuyApp: App {
    @StateObject private var session = BmbSession()
    @State private var incomingToken: BmbTokenItem?
    @State private var showSplash = true
    @AppStorage("bmb.theme") private var themePreference = "system"

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { HomeView() }
                    .tabItem { Label("Home", systemImage: "house") }
                NavigationStack { ExploreView() }
                    .tabItem { Label("Explore", systemImage: "square.grid.2x2") }
                NavigationStack { MineView() }
                    .tabItem { Label("My decisions", systemImage: "square.stack") }
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
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 17).fill(BmbTheme.hero)
                    if let image = product.ImageUrl, let url = URL(string: image) {
                        AsyncImage(url: url) { result in
                            result.resizable().scaledToFit()
                        } placeholder: { Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.brown.opacity(0.4)) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    } else {
                        Image(systemName: "sparkles").font(.system(size: 52)).foregroundStyle(.brown.opacity(0.4))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if let label { Text(label).font(.caption.bold()).padding(9).background(.white, in: RoundedRectangle(cornerRadius: 8)).padding(10) }
                }
                .frame(height: 210)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(product.Title.isEmpty ? "Your next find" : product.Title).font(.headline).lineLimit(2)
                        if let model = product.Model, !model.isEmpty { Text(model).font(.caption).foregroundStyle(BmbTheme.muted) }
                    }
                    Spacer()
                    if let price = product.Price { Text("\(product.Currency ?? "") \(price, specifier: "%.2f")").font(.subheadline.bold()) }
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
    @State private var running = false
    var body: some View {
        ZStack {
            BmbTheme.paper.ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    Text("BUY").font(.headline.bold()).tracking(3).foregroundStyle(BmbTheme.muted)
                        .offset(x: 100, y: 45).opacity(running ? 0 : 1)
                    Image("SplashBag").resizable().frame(width: 122, height: 122)
                        .clipShape(RoundedRectangle(cornerRadius: 27))
                        .offset(x: running ? 0 : -85)
                        .rotationEffect(.degrees(running ? 0 : -12))
                    Text("−").font(.system(size: 43, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color(red: 1, green: 0.447, blue: 0.353), in: Circle())
                        .offset(x: running ? 54 : 165, y: -52)
                        .opacity(running ? 1 : 0)
                }.frame(height: 180)
                Text("ByeMyBuy").font(.system(size: 29, weight: .black, design: .rounded))
                Text("Ask a friend first?").font(.subheadline).foregroundStyle(BmbTheme.muted)
            }
            VStack { Spacer(); Text("Tap to skip").font(.caption).foregroundStyle(BmbTheme.muted).padding(.bottom, 26) }
        }
        .contentShape(Rectangle()).onTapGesture { dismiss() }
        .task {
            if reduceMotion { dismiss(); return }
            withAnimation(.spring(response: 0.75, dampingFraction: 0.62)) { running = true }
            try? await Task.sleep(for: .milliseconds(1500))
            dismiss()
        }
    }
}
