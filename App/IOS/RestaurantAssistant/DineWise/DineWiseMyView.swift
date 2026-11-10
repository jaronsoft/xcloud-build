import SwiftUI

struct DineWiseMyView: View {
    var body: some View {
        List {
            NavigationLink("关于") { DineWiseAboutView() }
        }
        .navigationTitle("我的")
    }
}

struct DineWiseAboutView: View {
    @State private var tapCount = 0
    @State private var lastTapAt = Date.distantPast
    @State private var showOperatorLogin = false
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"

    var body: some View {
        List {
            Text("餐有数 DineWise")
            Button("版本 \(version)") {
                let now = Date()
                tapCount = now.timeIntervalSince(lastTapAt) <= 5 ? tapCount + 1 : 1
                lastTapAt = now
                if tapCount >= 10 {
                    tapCount = 0
                    showOperatorLogin = true
                }
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("关于")
        .sheet(isPresented: $showOperatorLogin) { DineWiseOperatorLoginView() }
    }
}

private struct DineWiseOperatorLoginView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var session: DineWiseOperatorSession?
    @State private var error = ""
    @State private var busy = false
    private let api = DineWiseAPI()

    var body: some View {
        NavigationStack {
            Form {
                if let session {
                    Section("运营账号") {
                        Text(session.Username)
                        DineWiseOperatorStoreView(token: session.AccessToken)
                        Button("退出运营账号") { self.session = nil }
                    }
                    Section("人工服务收费") {
                        DineWiseOperatorChargeView(token: session.AccessToken,
                            operatorID: session.OperatorId ?? session.Username)
                    }
                } else {
                    Section("餐有数运营登录") {
                        TextField("用户名", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("密码", text: $password)
                        Button("登录") {
                            let loginPassword = password
                            password = ""
                            busy = true
                            error = ""
                            Task { @MainActor in
                                defer { busy = false }
                                do {
                                    session = try await api.operatorLogin(
                                        username: username.trimmingCharacters(in: .whitespaces),
                                        password: loginPassword)
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                        .disabled(busy || username.isEmpty || password.isEmpty)
                    }
                }
                if !error.isEmpty { Text(error).foregroundStyle(DineWiseTheme.danger(for: colorScheme)) }
            }
            .navigationTitle("运营入口")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") { password = ""; session = nil; dismiss() }
            } }
            .onReceive(NotificationCenter.default.publisher(for: .dineWiseOperatorSessionExpired)
                .receive(on: DispatchQueue.main)) { notification in
                    guard let expiredToken = notification.object as? String,
                          session?.AccessToken == expiredToken else { return }
                    session = nil
                    password = ""
                    error = "运营登录已过期，请重新登录。"
                }
        }
    }
}
