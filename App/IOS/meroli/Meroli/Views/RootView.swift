import SwiftUI
import AuthenticationServices
import CryptoKit
import UIKit

private enum MeroliColor {
    static let ink = Color(red: 23 / 255, green: 63 / 255, blue: 58 / 255)
    static let canvas = Color(red: 1, green: 253 / 255, blue: 248 / 255)
    static let muted = Color(red: 73 / 255, green: 102 / 255, blue: 97 / 255)
    static let secondary = Color(red: 92 / 255, green: 102 / 255, blue: 96 / 255)
    static let line = Color(red: 212 / 255, green: 223 / 255, blue: 218 / 255)
    static let gold = Color(red: 239 / 255, green: 181 / 255, blue: 62 / 255)
    static let coral = Color(red: 190 / 255, green: 77 / 255, blue: 64 / 255)
    static let paleGreen = Color(red: 235 / 255, green: 243 / 255, blue: 238 / 255)
    static let childIdentity = [
        Color(red: 196 / 255, green: 85 / 255, blue: 59 / 255),
        Color(red: 78 / 255, green: 121 / 255, blue: 167 / 255),
        Color(red: 46 / 255, green: 158 / 255, blue: 143 / 255),
        Color(red: 140 / 255, green: 107 / 255, blue: 184 / 255),
        Color(red: 217 / 255, green: 145 / 255, blue: 59 / 255),
        Color(red: 91 / 255, green: 140 / 255, blue: 90 / 255)
    ]
}

private func externalWebURL(_ value: String?) -> URL? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty,
          let components = URLComponents(string: value),
          ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
          components.host != nil else { return nil }
    return components.url
}

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage("meroli.hasCompletedNetworkGuide") private var hasCompletedNetworkGuide = false
    @State private var isStartupSplashVisible = true

    var body: some View {
        ZStack {
            MeroliColor.canvas.ignoresSafeArea()
            Group {
                if !hasCompletedNetworkGuide {
                    NetworkAccessGuideView {
                        hasCompletedNetworkGuide = true
                        Task { await session.restore() }
                    }
                } else {
                    switch session.phase {
                    case .restoring: LoadingView()
                    case .restoreUnavailable: SessionRestoreUnavailableView()
                    case .signedOut: SignInView()
                    case .signedIn: FamilyTabView()
                    }
                }
            }
            if isStartupSplashVisible {
                StartupSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MeroliColor.canvas.ignoresSafeArea())
        .tint(MeroliColor.ink)
        .animation(.easeInOut(duration: 0.2), value: session.phase)
        .sheet(isPresented: Binding(
            get: { session.pendingPasswordResetToken != nil },
            set: { if !$0 { session.dismissPasswordReset() } }
        )) {
            if let token = session.pendingPasswordResetToken {
                PasswordResetConfirmationView(token: token)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 850_000_000)
            withAnimation(.easeOut(duration: 0.22)) {
                isStartupSplashVisible = false
            }
            if hasCompletedNetworkGuide {
                await session.restore()
            }
        }
        .onOpenURL { session.handleIncomingURL($0) }
    }
}

private struct StartupSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var markIsVisible = false
    @State private var haloIsVisible = false
    @State private var titleIsVisible = false

    var body: some View {
        ZStack {
            MeroliColor.canvas.ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(MeroliColor.gold.opacity(0.75), lineWidth: 1.5)
                        .frame(width: 146, height: 146)
                        .scaleEffect(haloIsVisible ? 1.12 : 0.72)
                        .opacity(haloIsVisible ? 0 : 0.9)

                    Image("MeroliMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 112, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                        .shadow(color: MeroliColor.ink.opacity(0.16), radius: 18, y: 8)
                        .scaleEffect(markIsVisible ? 1 : 0.72)
                        .offset(y: markIsVisible ? 0 : 12)
                        .opacity(markIsVisible ? 1 : 0)
                }

                Text("Meroli")
                    .font(.system(size: 31, weight: .bold, design: .serif))
                    .foregroundStyle(MeroliColor.ink)
                    .opacity(titleIsVisible ? 1 : 0)
                    .offset(y: titleIsVisible ? 0 : 7)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Meroli")
        }
        .onAppear {
            if reduceMotion {
                markIsVisible = true
                haloIsVisible = true
                titleIsVisible = true
                return
            }

            withAnimation(.spring(response: 0.62, dampingFraction: 0.68)) {
                markIsVisible = true
            }
            withAnimation(.easeOut(duration: 0.72)) {
                haloIsVisible = true
            }
            withAnimation(.easeOut(duration: 0.32).delay(0.18)) {
                titleIsVisible = true
            }
        }
        .accessibilityHidden(true)
    }
}

private struct NetworkAccessGuideView: View {
    @Environment(SessionStore.self) private var session
    let onContinue: () -> Void

    private var zh: Bool { session.usesChinese }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(MeroliColor.paleGreen)
                    .frame(width: 142, height: 142)
                Image(systemName: "wifi")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(MeroliColor.ink)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(MeroliColor.gold)
                    .background(MeroliColor.canvas, in: Circle())
                    .offset(x: 48, y: 46)
            }

            VStack(spacing: 10) {
                Text("Meroli")
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(MeroliColor.ink)
                Text(zh ? "连接网络，整理校园信息" : "Connect to keep school life in sync")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MeroliColor.ink)
                    .multilineTextAlignment(.center)
                Text(zh
                     ? "Meroli 需要互联网来安全登录，并同步孩子、学校和每日安排。请连接 Wi-Fi，或在系统设置中允许 Meroli 使用蜂窝数据。"
                     : "Meroli uses the internet to sign you in and sync your children, schools, and daily schedules. Connect to Wi-Fi or allow cellular data in Settings.")
                    .font(.body)
                    .foregroundStyle(MeroliColor.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 420)

            Spacer()

            VStack(spacing: 14) {
                Button(action: onContinue) {
                    Text(zh ? "继续并连接" : "Continue and connect")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                        .foregroundStyle(.white)
                        .background(MeroliColor.ink, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)

                Button {
                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(settingsURL)
                } label: {
                    Text(zh ? "打开 Meroli 的系统设置" : "Open Meroli Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MeroliColor.ink)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MeroliColor.canvas.ignoresSafeArea())
    }
}

private struct SessionRestoreUnavailableView: View {
    @Environment(SessionStore.self) private var session
    private var zh: Bool { session.usesChinese }

    var body: some View {
        VStack(spacing: 18) {
            Image("MeroliMark")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(zh ? "暂时无法连接 Meroli" : "Meroli is temporarily unavailable")
                .font(.title3.weight(.semibold))
                .foregroundStyle(MeroliColor.ink)
            Text(session.errorMessage ?? (zh ? "请检查网络后重试。" : "Check your connection and try again."))
                .font(.subheadline)
                .foregroundStyle(MeroliColor.muted)
                .multilineTextAlignment(.center)
            Button {
                Task { await session.restore() }
            } label: {
                HStack {
                    if session.isRestoringSession { ProgressView().tint(.white) }
                    Text(zh ? "重试连接" : "Try again")
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .foregroundStyle(.white)
                .background(MeroliColor.ink, in: RoundedRectangle(cornerRadius: 15))
            }
            .disabled(session.isRestoringSession)
            Button(zh ? "使用其他账户登录" : "Sign in with another account") {
                Task { await session.logout() }
            }
            .disabled(session.isRestoringSession)
        }
        .padding(26)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MeroliColor.canvas.ignoresSafeArea())
    }
}

private struct LoadingView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            MeroliColor.canvas.ignoresSafeArea()

            ZStack {
                Circle()
                    .stroke(MeroliColor.gold.opacity(isAnimating ? 0.08 : 0.3), lineWidth: 1.5)
                    .frame(width: 136, height: 136)
                    .scaleEffect(isAnimating ? 1.34 : 0.92)

                ForEach(0..<8, id: \.self) { ray in
                    Capsule()
                        .fill(MeroliColor.gold.opacity(isAnimating ? 0.28 : 0.72))
                        .frame(width: 3, height: 10)
                        .offset(y: -76)
                        .rotationEffect(.degrees(Double(ray) * 45))
                }
                .scaleEffect(isAnimating ? 1.1 : 0.86)
                .rotationEffect(.degrees(isAnimating ? 22.5 : 0))
            }

            VStack(spacing: 14) {
                Image("MeroliMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .scaleEffect(isAnimating ? 1 : 0.94)
                    .shadow(color: MeroliColor.ink.opacity(0.18), radius: 18, y: 9)

                Text("Meroli")
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(MeroliColor.ink)
                Text(session.usesChinese ? "每日校园安排" : "Your School Daily")
                    .font(.subheadline)
                    .foregroundStyle(MeroliColor.muted)
                ProgressView(value: session.initializationProgress)
                    .progressViewStyle(.linear)
                    .tint(MeroliColor.ink)
                    .frame(width: 220)
                    .padding(.top, 8)
                Text(session.usesChinese ? "正在下载初始化数据…" : "Downloading startup data…")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(MeroliColor.muted)
                Text("\(Int(session.initializationProgress * 100))%")
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .foregroundStyle(MeroliColor.ink)
                    .contentTransition(.numericText())
            }
            .offset(y: isAnimating ? -4 : 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: session.initializationProgress)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

private struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var createAccount = false
    @State private var showsPasswordReset = false
    @State private var appleRawNonce: String?
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }
    private var zh: Bool { session.usesChinese }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 13) {
                    Image("MeroliMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meroli")
                            .font(.system(.title2, design: .serif, weight: .bold))
                            .foregroundStyle(MeroliColor.ink)
                        Text(zh ? "每日校园安排" : "Your School Daily")
                            .font(.subheadline)
                            .foregroundStyle(MeroliColor.muted)
                    }
                }
                .padding(.bottom, 43)

                Text(createAccount ? (zh ? "创建家庭账户" : "Create your family account") : (zh ? "欢迎回来" : "Welcome back"))
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(MeroliColor.ink)
                Text(zh ? "从一个共享的家庭账户开始。" : "Start with one shared family account.")
                    .font(.body)
                    .foregroundStyle(MeroliColor.muted)
                    .padding(.top, 8)
                    .padding(.bottom, 27)

                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(zh ? "邮箱" : "Email")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MeroliColor.ink)
                        TextField("name@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = .password }
                            .textFieldStyle(MeroliFieldStyle())
                            .accessibilityIdentifier("meroli.email")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(zh ? "密码" : "Password")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MeroliColor.ink)
                        SecureField(zh ? "输入密码" : "Enter password", text: $password)
                            .textContentType(createAccount ? .newPassword : .password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($focusedField, equals: .password)
                            .onSubmit(submit)
                            .textFieldStyle(MeroliFieldStyle())
                            .accessibilityIdentifier("meroli.password")
                    }
                }

                if let error = session.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(MeroliColor.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 15)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                Button(action: submit) {
                    HStack(spacing: 10) {
                        if session.isAuthenticating { ProgressView().tint(.white) }
                        Text(createAccount ? (zh ? "创建账户" : "Create account") : (zh ? "登录" : "Sign in"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 54)
                    .foregroundStyle(.white)
                    .background(MeroliColor.ink, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .disabled(session.isAuthenticating)
                .padding(.top, 22)
                .accessibilityIdentifier("meroli.submit")

                MeroliAppleAuthorizationButton(
                    type: .signIn,
                    title: zh ? "通过 Apple 登录" : "Sign in with Apple",
                    height: 52,
                    accessibilityIdentifier: "meroli.signInWithApple",
                    onRequest: { request in
                        let nonce = AppleNonce.generate()
                        appleRawNonce = nonce
                        request.nonce = AppleNonce.sha256(nonce)
                        request.requestedScopes = [.email, .fullName]
                    },
                    onCompletion: { result in
                        guard case .success(let authorization) = result,
                              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                              let tokenData = credential.identityToken,
                              let token = String(data: tokenData, encoding: .utf8),
                              let nonce = appleRawNonce else {
                            if case .failure(let error) = result { session.errorMessage = error.localizedDescription }
                            return
                        }
                        Task { await session.signInWithApple(identityToken: token, rawNonce: nonce) }
                    }
                )
                .padding(.top, 14)

                if !createAccount {
                    Button(zh ? "忘记密码？" : "Forgot password?") { showsPasswordReset = true }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                        .accessibilityIdentifier("meroli.passwordReset")
                }

                Button {
                    createAccount.toggle()
                    session.errorMessage = nil
                } label: {
                    HStack(spacing: 5) {
                        Text(createAccount ? (zh ? "已有账户？" : "Already have an account?") : (zh ? "还没有账户？" : "New to Meroli?"))
                            .foregroundStyle(MeroliColor.muted)
                        Text(createAccount ? (zh ? "登录" : "Sign in") : (zh ? "创建账户" : "Create one"))
                            .fontWeight(.semibold)
                            .foregroundStyle(MeroliColor.ink)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 26)
            .padding(.top, 40)
            .padding(.bottom, 34)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MeroliColor.canvas)
        .sheet(isPresented: $showsPasswordReset) {
            PasswordResetRequestView(email: $email)
                .presentationDetents([.medium])
        }
    }

    private func submit() {
        focusedField = nil
        Task { await session.signIn(email: email, password: password, createAccount: createAccount) }
    }
}

private struct PasswordResetRequestView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Binding var email: String
    @State private var isSending = false
    @State private var sent = false
    private var zh: Bool { session.usesChinese }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(zh ? "输入账户邮箱，我们会发送密码重置说明。" : "Enter your account email and we’ll send password reset instructions.")
                    .font(.body)
                    .foregroundStyle(MeroliColor.muted)
                TextField("name@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(MeroliFieldStyle())
                    .disabled(sent)
                if sent {
                    Label(zh ? "如果账户存在，重置说明将发送到邮箱。" : "If an account exists, reset instructions will be sent by email.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(MeroliColor.ink)
                } else if let error = session.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral)
                }
                Button {
                    isSending = true
                    Task {
                        sent = await session.requestPasswordReset(email: email)
                        isSending = false
                    }
                } label: {
                    HStack {
                        if isSending { ProgressView().tint(.white) }
                        Text(zh ? "发送说明" : "Send instructions")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .foregroundStyle(.white)
                    .background(MeroliColor.ink, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .disabled(isSending || sent)
                Spacer(minLength: 0)
            }
            .padding(22)
            .background(MeroliColor.canvas.ignoresSafeArea())
            .navigationTitle(zh ? "重置密码" : "Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "完成" : "Done") { dismiss() } } }
        }
    }
}

private struct PasswordResetConfirmationView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let token: String
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isCompleted = false
    private var zh: Bool { session.usesChinese }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(zh ? "设置新的 Meroli 密码。" : "Choose a new password for your Meroli account.")
                        .font(.body)
                        .foregroundStyle(MeroliColor.muted)
                    if isCompleted {
                        Label(zh ? "密码已更新，请使用新密码登录。" : "Password updated. Sign in with your new password.", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(MeroliColor.ink)
                        Button(zh ? "完成" : "Done") { dismiss() }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                            .foregroundStyle(.white)
                            .background(MeroliColor.ink, in: RoundedRectangle(cornerRadius: 13))
                    } else {
                        SecureField(zh ? "新密码（至少 6 位）" : "New password (at least 6 characters)", text: $password)
                            .textContentType(.newPassword)
                            .textFieldStyle(MeroliFieldStyle())
                        SecureField(zh ? "再次输入新密码" : "Confirm new password", text: $confirmation)
                            .textContentType(.newPassword)
                            .textFieldStyle(MeroliFieldStyle())
                        if let error = session.errorMessage {
                            Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral)
                        }
                        Button {
                            guard password == confirmation else {
                                session.errorMessage = zh ? "两次输入的密码不一致。" : "The passwords do not match."
                                return
                            }
                            Task { isCompleted = await session.confirmPasswordReset(token: token, newPassword: password) }
                        } label: {
                            HStack {
                                if session.isAuthenticating { ProgressView().tint(.white) }
                                Text(zh ? "更新密码" : "Update password")
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                            .foregroundStyle(.white)
                            .background(MeroliColor.ink, in: RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(.plain)
                        .disabled(session.isAuthenticating || password.utf16.count < 6 || confirmation.isEmpty)
                    }
                }
                .padding(22)
            }
            .background(MeroliColor.canvas.ignoresSafeArea())
            .navigationTitle(zh ? "重置密码" : "Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "关闭" : "Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct FamilyTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = 0
    private var zh: Bool { session.usesChinese }
    private let selectedTabColor = Color(red: 30 / 255.0, green: 70 / 255.0, blue: 52 / 255.0)

    var body: some View {
        TabView(selection: $selected) {
            HomeScreen(showFamily: { selected = 2 })
                .tag(0)
                .tabItem { Label(zh ? "首页" : "Home", systemImage: "sun.max") }
            CalendarScreen()
                .tag(1)
                .tabItem { Label(zh ? "日历" : "Calendar", systemImage: "calendar") }
            SchoolsScreen()
                .tag(2)
                .tabItem { Label(zh ? "学校" : "Schools", systemImage: "building.2") }
            SettingsScreen()
                .tag(3)
                .tabItem { Label(zh ? "设置" : "Settings", systemImage: "gearshape") }
        }
        .tint(selectedTabColor)
        .toolbarBackground(MeroliColor.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, session.phase == .signedIn else { return }
            Task { await session.loadFamily() }
        }
    }
}

private struct MeroliChildFilter: View {
    let children: [ChildDTO]
    let enrollments: [EnrollmentDTO]
    let schools: [ParentSchoolDTO]
    @Binding var selection: String
    let zh: Bool
    @State private var hasMoreChildren = false

    private var displayNames: [String: String] {
        MeroliChildIdentity.displayNames(children: children, enrollments: enrollments, schools: schools, zh: zh)
    }

    private var identityColors: [String: Color] {
        MeroliChildIdentity.colors(for: children)
    }

    var body: some View {
        HStack(spacing: 8) {
            optionButton(title: zh ? "全部" : "All", id: "", accessibilityId: "meroli.childFilter.all")
            GeometryReader { viewport in
                ZStack(alignment: .trailing) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(children) { child in
                                childButton(child)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.vertical, 2)
                        .padding(.trailing, 12)
                        .background {
                            GeometryReader { content in
                                Color.clear.preference(key: HomeChipContentWidthPreferenceKey.self, value: content.size.width)
                            }
                        }
                    }
                    if hasMoreChildren {
                        LinearGradient(colors: [.clear, HomePalette.canvas], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 22)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .onPreferenceChange(HomeChipContentWidthPreferenceKey.self) { contentWidth in
                    hasMoreChildren = contentWidth > viewport.size.width + 1
                }
            }
            .frame(height: 48)
        }
        .accessibilityElement(children: .contain)
    }

    private func optionButton(title: String, id: String, accessibilityId: String) -> some View {
        let isSelected = selection == id
        let brand = HomePalette.brand
        return Button { selection = id } label: {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .foregroundStyle(isSelected ? .white : HomePalette.primary)
                .background(isSelected ? brand : HomePalette.surface, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? brand : HomePalette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(accessibilityId)
    }

    private func childButton(_ child: ChildDTO) -> some View {
        let isSelected = selection == child.id
        let title = displayNames[child.id] ?? child.nickname
        return Button { selection = child.id } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(identityColors[child.id] ?? HomePalette.tertiary)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(isSelected ? .white : .clear, lineWidth: 1))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 240, alignment: .leading)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .foregroundStyle(isSelected ? .white : HomePalette.primary)
            .background(isSelected ? HomePalette.brand : HomePalette.surface, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? HomePalette.brand : HomePalette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("meroli.childFilter.\(child.id)")
    }
}

private struct HomeChipContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HomeUpcomingDayGroup: Identifiable {
    let dateKey: String
    let schedules: [DailyScheduleDTO]
    let importantEvents: [ParentEventDTO]
    let ordinaryEvents: [ParentEventDTO]

    var id: String { dateKey }
}

private struct HomeScheduleStatusStyle {
    let label: String
    let foreground: Color
    let background: Color
}

private struct HomeEventVisualStyle {
    let tag: String?
    let foreground: Color
    let accent: Color
    let background: Color
}

private struct HomeEventBundle: Identifiable {
    let key: String
    let childIdFilter: String?
    let isShared: Bool
    var events: [ParentEventDTO]

    var id: String { key }
}

private enum HomePalette {
    static let canvas = Color(red: 246 / 255.0, green: 243 / 255.0, blue: 234 / 255.0)
    static let surface = Color.white
    static let surface2 = Color(red: 239 / 255.0, green: 235 / 255.0, blue: 223 / 255.0)
    static let primary = Color(red: 31 / 255.0, green: 42 / 255.0, blue: 34 / 255.0)
    static let secondary = Color(red: 92 / 255.0, green: 102 / 255.0, blue: 96 / 255.0)
    static let tertiary = Color(red: 138 / 255.0, green: 146 / 255.0, blue: 140 / 255.0)
    static let line = Color(red: 229 / 255.0, green: 224 / 255.0, blue: 210 / 255.0)
    static let brand = Color(red: 30 / 255.0, green: 70 / 255.0, blue: 52 / 255.0)
    static let brandPale = Color(red: 238 / 255.0, green: 244 / 255.0, blue: 239 / 255.0)
    static let amber = Color(red: 180 / 255.0, green: 83 / 255.0, blue: 9 / 255.0)
    static let amberAccent = Color(red: 229 / 255.0, green: 168 / 255.0, blue: 59 / 255.0)
    static let amberPale = Color(red: 247 / 255.0, green: 234 / 255.0, blue: 212 / 255.0)
    static let destructive = Color(red: 192 / 255.0, green: 57 / 255.0, blue: 43 / 255.0)
    static let destructivePale = Color(red: 246 / 255.0, green: 222 / 255.0, blue: 218 / 255.0)
    static let blue = Color(red: 47 / 255.0, green: 109 / 255.0, blue: 168 / 255.0)
    static let purple = Color(red: 124 / 255.0, green: 92 / 255.0, blue: 191 / 255.0)
}

private struct HomeScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let showFamily: () -> Void
    @State private var date = Date()
    @AppStorage("meroli.home.childId") private var selectedChildId = ""
    @State private var selectedEvent: ParentEventDTO?
    @State private var expandedHomeEventBundles: Set<String> = []
    private var zh: Bool { session.usesChinese }
    private var schoolCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = session.schoolTimezone(for: selectedChildId.isEmpty ? nil : selectedChildId)
        calendar.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        return calendar
    }
    private var selectedSchedules: [DailyScheduleDTO] {
        selectedChildId.isEmpty ? session.dailySchedules : session.dailySchedules.filter { $0.childId == selectedChildId }
    }
    private var childrenWithoutSchoolToday: [DailyScheduleDTO] {
        selectedSchedules.filter(isHomeNonInstructionalDay)
    }
    private var selectedFutureSchedules: [DailyScheduleDTO] {
        selectedChildId.isEmpty ? session.futureDailySchedules : session.futureDailySchedules.filter { $0.childId == selectedChildId }
    }
    private var importantFutureSchedules: [DailyScheduleDTO] {
        let horizonDates = Set((1...7).map { dateKey(offset: $0, childId: selectedChildId.isEmpty ? nil : selectedChildId) })
        return selectedFutureSchedules.filter { item in
            guard horizonDates.contains(item.date) else { return false }
            let status = item.status.uppercased()
            let scheduleType = item.scheduleType?.uppercased() ?? ""
            guard !["WEEKEND", "OUTSIDE_SCHOOL_YEAR"].contains(scheduleType) else { return false }

            if item.date == dateKey(offset: 1, childId: selectedChildId.isEmpty ? nil : selectedChildId) {
                if status == "NO_SCHOOL" { return true }
                guard status == "OK" else { return false }
                return isAuthoritativeScheduleException(item) || allSelectedChildrenDismissed
            }

            return status == "NO_SCHOOL" || isAuthoritativeScheduleException(item)
        }
    }
    private var visibleEvents: [ParentEventDTO] {
        MeroliEventPresentation.sorted(selectedChildId.isEmpty
            ? session.homeEvents
            : session.homeEvents.filter { $0.children.contains { $0.id == selectedChildId } })
    }
    private var todayEvents: [ParentEventDTO] {
        todayEventBundles.flatMap(\.events)
    }
    private var todayEventBundles: [HomeEventBundle] {
        var bundles: [String: HomeEventBundle] = [:]
        let todayKey = dateKey(offset: 0, childId: selectedChildId.isEmpty ? nil : selectedChildId)

        func append(_ event: ParentEventDTO, key: String, childId: String?, shared: Bool) {
            var bundle = bundles[key] ?? HomeEventBundle(key: key, childIdFilter: childId, isShared: shared, events: [])
            bundle.events.append(event)
            bundles[key] = bundle
        }

        for event in visibleEvents where eventOccurs(event, offsets: 0...0) {
            if event.scopeType.uppercased() == "DISTRICT" && event.children.count > 1 {
                append(event, key: "\(todayKey)|shared", childId: selectedChildId.isEmpty ? nil : selectedChildId, shared: true)
                continue
            }

            if event.children.isEmpty {
                append(event, key: "\(todayKey)|unassigned", childId: nil, shared: false)
                continue
            }

            for (index, child) in event.children.enumerated()
                where selectedChildId.isEmpty || child.id == selectedChildId {
                guard !isScheduleDuplicate(event, for: child.id) else { continue }
                let schoolId = event.schools.first(where: { $0.id == child.schoolId })?.id
                    ?? (event.schools.count == event.children.count ? event.schools[index].id : event.schools.first?.id)
                    ?? ""
                let key = "\(todayKey)|\(child.id)|\(schoolId)"
                append(event, key: key, childId: child.id, shared: false)
            }
        }

        let childOrder = Dictionary(uniqueKeysWithValues: session.children.enumerated().map { ($1.id, $0) })
        return bundles.values
            .map { bundle in
                var sorted = bundle
                sorted.events = MeroliEventPresentation.sorted(sorted.events)
                return sorted
            }
            .sorted { left, right in
                if left.isShared != right.isShared { return !left.isShared }
                let leftChildOrder = left.childIdFilter.flatMap { childOrder[$0] } ?? Int.max
                let rightChildOrder = right.childIdFilter.flatMap { childOrder[$0] } ?? Int.max
                if leftChildOrder != rightChildOrder { return leftChildOrder < rightChildOrder }
                return left.key < right.key
            }
    }
    private var allTomorrowEvents: [ParentEventDTO] {
        visibleEvents.filter {
            $0.startDate > dateKey(offset: 0, childId: selectedChildId.isEmpty ? nil : selectedChildId)
                && eventOccurs($0, offsets: 1...1)
        }
    }
    private var importantTomorrowEvents: [ParentEventDTO] {
        allTomorrowEvents.filter(isHomeUpcomingEvent)
    }
    private var ordinaryTomorrowEvents: [ParentEventDTO] {
        allTomorrowEvents.filter { !isHomeUpcomingEvent($0) }
    }
    private var thisWeekEvents: [ParentEventDTO] {
        let earlierEventIds = Set(allTomorrowEvents.map(\.id))
        return visibleEvents.filter {
            !earlierEventIds.contains($0.id)
                && $0.startDate > dateKey(offset: 0, childId: selectedChildId.isEmpty ? nil : selectedChildId)
                && eventOccurs($0, offsets: 2...7)
                && isHomeUpcomingEvent($0)
        }
    }
    private var upcomingDayGroups: [HomeUpcomingDayGroup] {
        let schedulesByDate = Dictionary(grouping: importantFutureSchedules, by: \.date)
        let tomorrowKey = dateKey(offset: 1, childId: selectedChildId.isEmpty ? nil : selectedChildId)
        let importantByDate = Dictionary(grouping: importantTomorrowEvents + thisWeekEvents, by: \.startDate)
        let ordinaryTomorrowByDate = Dictionary(grouping: ordinaryTomorrowEvents, by: \.startDate)
        let dates = Set(schedulesByDate.keys)
            .union(importantByDate.keys)
            .union(ordinaryTomorrowByDate.keys)
            .sorted()

        return dates.compactMap { dateKey in
            let schedules = (schedulesByDate[dateKey] ?? []).sorted { left, right in
                if left.childName != right.childName { return left.childName.localizedStandardCompare(right.childName) == .orderedAscending }
                return left.childId < right.childId
            }
            let importantEvents = (importantByDate[dateKey] ?? []).filter { event in
                !isUpcomingScheduleDuplicate(event, schedules: schedules)
            }
            let ordinaryEvents = dateKey == tomorrowKey
                ? (ordinaryTomorrowByDate[dateKey] ?? []).filter { event in
                    !isUpcomingScheduleDuplicate(event, schedules: schedules)
                }
                : []
            guard !schedules.isEmpty || !importantEvents.isEmpty || !ordinaryEvents.isEmpty else { return nil }
            return HomeUpcomingDayGroup(
                dateKey: dateKey,
                schedules: schedules,
                importantEvents: importantEvents,
                ordinaryEvents: ordinaryEvents
            )
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button { date = schoolCalendar.date(byAdding: .day, value: -1, to: date) ?? date; refresh() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel(zh ? "前一天" : "Previous day")
                        Spacer()
                        Text(schoolDateLabel(date))
                            .font(.headline.monospacedDigit())
                        Spacer()
                        Button { date = schoolCalendar.date(byAdding: .day, value: 1, to: date) ?? date; refresh() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .accessibilityLabel(zh ? "后一天" : "Next day")
                    }
                    if session.children.count > 1 {
                        MeroliChildFilter(children: session.children, enrollments: session.enrollments, schools: session.schools, selection: $selectedChildId, zh: zh)
                        .onChange(of: selectedChildId) { _, _ in
                            date = schoolCalendar.startOfDay(for: .now)
                            refresh()
                        }
                    }
                    sectionHeading(zh ? "今天的安排" : "Today's Schedule")
                    if let error = session.homeErrorMessage, !session.dailySchedules.isEmpty {
                        homeErrorCard(error)
                    }
                    if session.isLoadingFamily || session.isLoadingHome {
                        ProgressView(zh ? "正在读取学校安排…" : "Loading school schedules…").frame(maxWidth: .infinity, minHeight: 120)
                    } else if let error = session.homeErrorMessage, session.dailySchedules.isEmpty {
                        homeErrorCard(error)
                    } else if selectedSchedules.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(zh ? "还没有可显示的孩子学校安排。添加孩子并设置学校后，这里会显示每日安排。" : "No school schedules yet. Add a child and school to see their daily plans here.")
                                .foregroundStyle(HomePalette.secondary)
                            Button(action: showFamily) {
                                Label(zh ? "添加孩子" : "Add a child", systemImage: "person.crop.circle.badge.plus")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(HomePalette.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("meroli.home.addChild")
                        }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        ForEach(selectedSchedules) { item in
                            if selectedChildId.isEmpty {
                                compactHomeSchedule(item)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 8) {
                                                Circle().fill(childIdentityColor(for: item.childId)).frame(width: 9, height: 9).accessibilityHidden(true)
                                                Text(item.childName).font(.headline).foregroundStyle(HomePalette.primary)
                                            }
                                            Text(item.schoolName ?? (zh ? "未设置学校" : "No school selected"))
                                                .font(.subheadline).foregroundStyle(HomePalette.secondary)
                                            if item.date != dateKey(offset: 0) {
                                                Text(schoolLocalDateNote(item.date, childId: item.childId))
                                                    .font(.caption2).foregroundStyle(HomePalette.tertiary)
                                            }
                                        }
                                        Spacer()
                                        homeScheduleStatusPill(item)
                                    }
                                    if isHomeNonInstructionalDay(item) {
                                        Label(zh ? "这一天没有常规上课" : "No regular school on this day", systemImage: "sun.max")
                                            .font(.subheadline.weight(.semibold)).foregroundStyle(HomePalette.primary)
                                        if session.isLoadingNextInstructionalDay {
                                            ProgressView(zh ? "正在查找下一次上课日…" : "Finding the next school day…")
                                        } else if let nextDay = session.nextInstructionalDays.first(where: { $0.childId == item.childId }) {
                                            if let nextDate = nextDay.date {
                                                Text((zh ? "下一次上课：" : "Next school day: ")
                                                    + nextInstructionalDateLabel(nextDate, childId: item.childId))
                                                    .font(.subheadline).foregroundStyle(HomePalette.secondary)
                                            } else {
                                                Text(zh ? "未来 21 天内暂无上课日。" : "No school day in the next 21 days.")
                                                    .font(.subheadline).foregroundStyle(HomePalette.secondary)
                                            }
                                        } else if !selectedChildId.isEmpty, let nextDate = session.nextInstructionalDay {
                                            Text((zh ? "下一次上课：" : "Next school day: ")
                                                + nextInstructionalDateLabel(nextDate, childId: item.childId))
                                                .font(.subheadline).foregroundStyle(HomePalette.secondary)
                                        } else if let error = session.nextInstructionalDayErrorMessage {
                                            Text(error).font(.subheadline).foregroundStyle(HomePalette.destructive)
                                        }
                                        ForEach(item.eventTitles, id: \.self) { title in
                                            Label(title, systemImage: "calendar")
                                                .font(.subheadline).foregroundStyle(HomePalette.secondary)
                                        }
                                    } else if item.status == "OK" {
                                        compactHomeTimePair(item)
                                        if item.firstPeriodCode == "P0", item.arrivalLabel != "PERIOD_0_START" {
                                            Text(zh ? "包含第0节" : "Includes Period 0")
                                                .font(.caption.weight(.medium)).foregroundStyle(HomePalette.secondary)
                                        }
                                        if session.homeEventsErrorMessage != nil, !item.eventTitles.isEmpty {
                                            ForEach(item.eventTitles, id: \.self) { title in
                                                Label(title, systemImage: "calendar.badge.exclamationmark")
                                                    .font(.subheadline).foregroundStyle(HomePalette.secondary)
                                            }
                                        }
                                    } else {
                                        Text(statusLabel(item.status))
                                            .font(.subheadline).foregroundStyle(HomePalette.secondary)
                                    }
                                }
                                .padding(16).background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
                    sectionHeading(zh ? "今天需要知道" : "Today's Need to Know")
                    if let error = session.homeEventsErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(HomePalette.destructive)
                    }
                    if session.isLoadingHomeEvents && todayEvents.isEmpty {
                        ProgressView(zh ? "正在读取今天的动态…" : "Loading today's updates…")
                    } else if todayEvents.isEmpty {
                        Text(zh ? "今天暂无需要特别留意的动态。" : "No important updates for today.")
                            .font(.subheadline).foregroundStyle(HomePalette.secondary)
                    } else {
                        todayHomeEventList(todayEventBundles)
                    }
                    sectionHeading(zh ? "接下来需要知道" : "Upcoming")
                    if session.isLoadingFutureSchedules && importantFutureSchedules.isEmpty {
                        ProgressView(zh ? "正在读取接下来的作息…" : "Loading upcoming schedules…")
                    }
                    if let error = session.futureSchedulesErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(HomePalette.destructive)
                    }
                    if upcomingDayGroups.isEmpty &&
                        !session.isLoadingFutureSchedules && !session.isLoadingHomeEvents &&
                        session.futureSchedulesErrorMessage == nil && session.homeEventsErrorMessage == nil {
                        Text(zh ? "目前没有需要提前留意的安排。" : "No important upcoming items.")
                            .font(.subheadline).foregroundStyle(HomePalette.secondary)
                    }
                    ForEach(upcomingDayGroups) { group in
                        upcomingDayGroup(group)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 24).accessibilityHidden(true)
            }
            .background(HomePalette.canvas.ignoresSafeArea())
            .refreshable {
                session.invalidateFutureDailySchedules()
                await session.loadFamily()
                await session.loadDailySchedules(for: date, childId: selectedChildId.isEmpty ? nil : selectedChildId)
                await loadNextInstructionalDayIfNeeded()
                async let futureSchedules: Void = session.loadFutureDailySchedules(from: date, childId: selectedChildId.isEmpty ? nil : selectedChildId)
                async let homeEvents: Void = loadHomeEvents()
                _ = await (futureSchedules, homeEvents)
            }
            .task { if session.dailySchedules.isEmpty || session.homeEvents.isEmpty || session.futureDailySchedules.isEmpty { refresh() } }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                let today = schoolCalendar.startOfDay(for: .now)
                if !schoolCalendar.isDate(date, inSameDayAs: today) { date = today }
                refresh()
            }
            .onChange(of: session.children.map(\.id)) { _, childIds in
                if !selectedChildId.isEmpty && !childIds.contains(selectedChildId) {
                    selectedChildId = ""
                }
                date = schoolCalendar.startOfDay(for: .now)
                refresh()
            }
            .sheet(item: $selectedEvent) { event in EventDetailSheet(event: event, zh: zh) }
        }
    }

    private func refresh() {
        session.invalidateFutureDailySchedules()
        Task {
            await session.loadDailySchedules(for: date, childId: selectedChildId.isEmpty ? nil : selectedChildId)
            async let futureSchedules: Void = session.loadFutureDailySchedules(from: date, childId: selectedChildId.isEmpty ? nil : selectedChildId)
            async let nextInstructionalDay: Void = loadNextInstructionalDayIfNeeded()
            async let homeEvents: Void = loadHomeEvents()
            _ = await (futureSchedules, nextInstructionalDay, homeEvents)
        }
    }

    private func loadNextInstructionalDayIfNeeded() async {
        guard !childrenWithoutSchoolToday.isEmpty else { return }
        await session.loadNextInstructionalDay(after: date, childId: selectedChildId.isEmpty ? nil : selectedChildId)
    }

    private func loadHomeEvents() async {
        let childIds = selectedChildId.isEmpty ? session.children.map(\.id) : [selectedChildId]
        let startKey = childIds.map { dateKey(offset: 0, childId: $0) }.min() ?? dateKey(offset: 0)
        let endKey = childIds.map { dateKey(offset: 7, childId: $0) }.max() ?? dateKey(offset: 7)
        await session.loadHomeEvents(
            from: dateFromKey(startKey), to: dateFromKey(endKey),
            childId: selectedChildId.isEmpty ? nil : selectedChildId
        )
    }

    private func dateFromKey(_ key: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = schoolCalendar
        formatter.timeZone = schoolCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key) ?? date
    }

    private func dateKey(offset: Int, childId: String? = nil) -> String {
        let referenceOffset = schoolCalendar.dateComponents(
            [.day], from: schoolCalendar.startOfDay(for: .now), to: schoolCalendar.startOfDay(for: date)
        ).day ?? 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = session.schoolTimezone(for: childId)
        let localToday = calendar.startOfDay(for: .now)
        let target = calendar.date(byAdding: .day, value: referenceOffset + offset, to: localToday) ?? localToday
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: target)
    }

    private func eventOccurs(_ event: ParentEventDTO, offsets: ClosedRange<Int>) -> Bool {
        let childIds = selectedChildId.isEmpty ? event.children.map(\.id) : [selectedChildId]
        let targets = childIds.isEmpty ? [nil] : childIds.map(Optional.some)
        return targets.contains { childId in
            offsets.contains { offset in
                eventCovers(event, dateKey: dateKey(offset: offset, childId: childId))
            }
        }
    }

    private var allSelectedChildrenDismissed: Bool {
        let schedules = selectedSchedules
        guard !schedules.isEmpty else { return false }
        let now = Date()
        return schedules.allSatisfy { schedule in
            guard schedule.status.uppercased() == "OK", let dismissal = schedule.dismissalTime else { return false }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = session.schoolTimezone(for: schedule.childId)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            let localToday = formatter.string(from: now)
            guard schedule.date == localToday, dateKey(offset: 0, childId: schedule.childId) == localToday else { return false }
            formatter.dateFormat = "HH:mm"
            return String(dismissal.prefix(5)) <= formatter.string(from: now)
        }
    }

    private func isAuthoritativeScheduleException(_ schedule: DailyScheduleDTO) -> Bool {
        guard schedule.status.uppercased() == "OK",
              let scheduleType = schedule.scheduleType?.uppercased() else { return false }
        return !["", "REGULAR", "REGULAR_DAY", "SCHEDULE_UNAVAILABLE", "SCHEDULE_DATA_UNAVAILABLE", "NON_INSTRUCTIONAL_DAY"].contains(scheduleType)
    }

    private func isHomeNonInstructionalDay(_ schedule: DailyScheduleDTO) -> Bool {
        ["NO_SCHOOL", "NON_INSTRUCTIONAL_DAY"].contains(schedule.status.uppercased())
            || ["NO_SCHOOL", "PUPIL_FREE_DAY", "BREAK", "HOLIDAY", "WEEKEND", "OUTSIDE_SCHOOL_YEAR"].contains((schedule.scheduleType ?? "").uppercased())
    }

    private func isScheduleDuplicate(_ event: ParentEventDTO, for childId: String) -> Bool {
        let type = event.eventType.uppercased()
        let scheduleEventTypes: Set<String> = ["NO_SCHOOL", "PUPIL_FREE_DAY", "BREAK", "HOLIDAY", "MINIMUM_DAY", "LATE_START", "NO_LATE_START", "EARLY_RELEASE"]
        guard scheduleEventTypes.contains(type),
              let schedule = selectedSchedules.first(where: { $0.childId == childId }) else { return false }

        let scheduleType: String
        switch schedule.status.uppercased() {
        case "OK": scheduleType = schedule.scheduleType?.uppercased() ?? ""
        case "NO_SCHOOL": scheduleType = "NO_SCHOOL"
        case "NON_INSTRUCTIONAL_DAY": scheduleType = "NON_INSTRUCTIONAL_DAY"
        default: scheduleType = "SCHEDULE_UNAVAILABLE"
        }
        if ["PUPIL_FREE_DAY", "BREAK", "HOLIDAY"].contains(type) {
            return scheduleType == "NO_SCHOOL"
        }
        return scheduleType == type
    }

    private func isHomeUpcomingEvent(_ event: ParentEventDTO) -> Bool {
        MeroliEventPresentation.isHomeActionRequired(event) || MeroliEventPresentation.isScheduleChange(event)
    }

    private func isUpcomingScheduleDuplicate(_ event: ParentEventDTO, schedules: [DailyScheduleDTO]) -> Bool {
        guard MeroliEventPresentation.isScheduleChange(event) else { return false }
        let eventMeanings = normalizedScheduleMeanings(for: event)
        guard !eventMeanings.isEmpty else { return false }

        let isPureNoSchoolDuplicate = eventMeanings.contains("NO_SCHOOL")
            && !hasAdditionalParentAction(event)
            && (event.scheduleAction.uppercased() == "NO_SCHOOL"
                || ["NO_SCHOOL", "PUPIL_FREE_DAY", "BREAK", "HOLIDAY"].contains(event.eventType.uppercased()))
        if MeroliEventPresentation.isHomeActionRequired(event) && !isPureNoSchoolDuplicate { return false }

        let relevantChildIds = Set(event.children.map(\.id).filter { selectedChildId.isEmpty || $0 == selectedChildId })
        guard !relevantChildIds.isEmpty else { return false }
        let matchedChildIds = Set(schedules.compactMap { schedule -> String? in
            guard event.startDate == schedule.date,
                  relevantChildIds.contains(schedule.childId),
                  !eventMeanings.isDisjoint(with: normalizedScheduleMeanings(for: schedule)) else { return nil }
            return schedule.childId
        })
        return relevantChildIds.isSubset(of: matchedChildIds)
    }

    private func normalizedScheduleMeanings(for event: ParentEventDTO) -> Set<String> {
        let eventType = event.eventType.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let action = event.scheduleAction.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let override = event.scheduleCodeOverride?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let noSchoolTypes: Set<String> = ["NO_SCHOOL", "PUPIL_FREE_DAY", "BREAK", "HOLIDAY"]
        if action == "NO_SCHOOL" || noSchoolTypes.contains(eventType) || noSchoolTypes.contains(override) {
            return ["NO_SCHOOL"]
        }

        var meanings = Set<String>()
        if ["LATE_START", "NO_LATE_START", "EARLY_RELEASE", "MINIMUM_DAY"].contains(eventType) {
            meanings.insert(eventType)
        }
        if !override.isEmpty {
            meanings.insert(normalizedScheduleMeaning(override))
        }
        return meanings
    }

    private func normalizedScheduleMeanings(for schedule: DailyScheduleDTO) -> Set<String> {
        let status = schedule.status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let scheduleType = schedule.scheduleType?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let scheduleCode = schedule.scheduleCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let noSchoolTypes: Set<String> = ["NO_SCHOOL", "NON_INSTRUCTIONAL_DAY", "PUPIL_FREE_DAY", "BREAK", "HOLIDAY"]
        if noSchoolTypes.contains(status) || noSchoolTypes.contains(scheduleType) || noSchoolTypes.contains(scheduleCode) {
            return ["NO_SCHOOL"]
        }

        var meanings = Set<String>()
        if !scheduleType.isEmpty && !["REGULAR", "REGULAR_DAY", "NON_INSTRUCTIONAL_DAY"].contains(scheduleType) {
            meanings.insert(normalizedScheduleMeaning(scheduleType))
        }
        if !scheduleCode.isEmpty && !["REGULAR", "REGULAR_DAY"].contains(scheduleCode) {
            meanings.insert(normalizedScheduleMeaning(scheduleCode))
        }
        return meanings
    }

    private func normalizedScheduleMeaning(_ rawValue: String) -> String {
        ["NO_SCHOOL", "NON_INSTRUCTIONAL_DAY", "PUPIL_FREE_DAY", "BREAK", "HOLIDAY"].contains(rawValue)
            ? "NO_SCHOOL"
            : rawValue
    }

    private func hasAdditionalParentAction(_ event: ParentEventDTO) -> Bool {
        let noActionValues: Set<String> = ["", "NONE", "NO ACTION", "NO ACTION REQUIRED", "无", "无需操作"]
        let sourceAction = event.originalAction ?? event.action
        return !noActionValues.contains(sourceAction.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    private func schoolLocalDateNote(_ key: String, childId: String? = nil) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = session.schoolTimezone(for: childId)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: key) else { return key }
        formatter.dateFormat = zh ? "M月d日 EEEE" : "EEEE, MMM d"
        let label = formatter.string(from: date)
        return zh ? "学校当地日期：\(label)" : "School local date: \(label)"
    }

    private func eventCovers(_ event: ParentEventDTO, dateKey: String) -> Bool {
        event.startDate <= dateKey && (event.endDate ?? event.startDate) >= dateKey
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title).font(.title3.weight(.semibold)).foregroundStyle(HomePalette.brand).padding(.top, 8)
    }

    private func upcomingDateLabel(_ key: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = schoolCalendar
        parser.timeZone = schoolCalendar.timeZone
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.calendar = schoolCalendar
        formatter.timeZone = schoolCalendar.timeZone
        formatter.dateFormat = zh ? "M月d日 EEE" : "EEE, MMM d"
        let dayLabel = formatter.string(from: date)
        guard key == dateKey(offset: 1) else { return dayLabel }
        return zh ? "明天 · \(dayLabel)" : "Tomorrow · \(dayLabel)"
    }

    private func scheduleStatusStyle(_ item: DailyScheduleDTO) -> HomeScheduleStatusStyle {
        let status = item.status.uppercased()
        let type = item.scheduleType?.uppercased() ?? ""
        if status == "NO_SCHOOL" || isHomeNonInstructionalDay(item) {
            return HomeScheduleStatusStyle(
                label: zh ? "停课" : "No school",
                foreground: HomePalette.destructive,
                background: HomePalette.destructivePale
            )
        }
        if status != "OK" {
            return HomeScheduleStatusStyle(
                label: statusLabel(item.status),
                foreground: HomePalette.secondary,
                background: HomePalette.surface2
            )
        }
        if ["", "REGULAR", "REGULAR_DAY"].contains(type) {
            return HomeScheduleStatusStyle(
                label: zh ? "正常上课" : "Normal School",
                foreground: HomePalette.brand,
                background: HomePalette.brandPale
            )
        }
        return HomeScheduleStatusStyle(
            label: compactScheduleStatusLabel(item),
            foreground: HomePalette.amber,
            background: HomePalette.amberPale
        )
    }

    private func homeScheduleStatusPill(_ item: DailyScheduleDTO) -> some View {
        let style = scheduleStatusStyle(item)
        return Text(style.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(style.background, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }

    private func upcomingScheduleCard(_ item: DailyScheduleDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(childIdentityColor(for: item.childId))
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.childName).font(.subheadline.weight(.semibold)).foregroundStyle(HomePalette.primary)
                    Text(item.schoolName ?? (zh ? "未设置学校" : "No school selected"))
                        .font(.caption).foregroundStyle(HomePalette.secondary)
                }
                Spacer(minLength: 4)
                homeScheduleStatusPill(item)
            }
            if isHomeNonInstructionalDay(item) {
                Text(zh ? "这一天没有常规上课" : "No regular school on this day")
                    .font(.subheadline.weight(.medium)).foregroundStyle(HomePalette.primary)
            } else if item.status.uppercased() == "OK" {
                compactHomeTimePair(item)
                if item.firstPeriodCode == "P0", item.arrivalLabel != "PERIOD_0_START" {
                    Text(zh ? "包含第0节" : "Includes Period 0")
                        .font(.caption).foregroundStyle(HomePalette.secondary)
                }
            } else {
                Text(statusLabel(item.status)).font(.subheadline).foregroundStyle(HomePalette.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func upcomingDayGroup(_ group: HomeUpcomingDayGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(upcomingDateLabel(group.dateKey))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomePalette.brand)
                .monospacedDigit()
            VStack(spacing: 8) {
                ForEach(group.schedules) { item in
                    upcomingScheduleCard(item)
                }
                if !group.importantEvents.isEmpty || !group.ordinaryEvents.isEmpty {
                    upcomingEventList(group)
                }
            }
        }
    }

    private func upcomingEventList(_ group: HomeUpcomingDayGroup) -> some View {
        let visibleOrdinary = Array(group.ordinaryEvents.prefix(2))
        let collapsedOrdinary = Array(group.ordinaryEvents.dropFirst(2))
        let visibleEvents = group.importantEvents + visibleOrdinary
        let disclosureKey = "upcoming|\(group.dateKey)"

        return VStack(spacing: 0) {
            ForEach(visibleEvents) { event in
                upcomingEventRow(event)
                if event.id != visibleEvents.last?.id || !collapsedOrdinary.isEmpty {
                    Divider().overlay(HomePalette.line)
                }
            }
            if !collapsedOrdinary.isEmpty {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedHomeEventBundles.contains(disclosureKey) },
                        set: { isExpanded in
                            if isExpanded { expandedHomeEventBundles.insert(disclosureKey) }
                            else { expandedHomeEventBundles.remove(disclosureKey) }
                        }
                    )
                ) {
                    ForEach(collapsedOrdinary) { event in
                        upcomingEventRow(event)
                        if event.id != collapsedOrdinary.last?.id { Divider().overlay(HomePalette.line) }
                    }
                } label: {
                    let includesPersonalEvents = collapsedOrdinary.contains { $0.isPersonal == true }
                    Text(upcomingOverflowLabel(count: collapsedOrdinary.count, includesPersonalEvents: includesPersonalEvents))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomePalette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .tint(HomePalette.brand)
            }
        }
        .padding(.horizontal, 15)
        .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func upcomingOverflowLabel(count: Int, includesPersonalEvents: Bool) -> String {
        if zh {
            return "另外 \(count) 项\(includesPersonalEvents ? "活动" : "学校活动")"
        }
        let noun = includesPersonalEvents ? "activit\(count == 1 ? "y" : "ies")" : "school \(count == 1 ? "activity" : "activities")"
        return "\(count) more \(noun)"
    }

    private func upcomingEventRow(_ event: ParentEventDTO) -> some View {
        Button { selectedEvent = event } label: {
            EventRow(
                event: event,
                zh: zh,
                childIdentityColors: childIdentityColors(for: event),
                showsActionLabel: true,
                showsAllDayLabel: true,
                homeStyle: true
            )
        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
    }

    private func childIdentityColor(for childId: String) -> Color {
        MeroliChildIdentity.color(for: childId, in: session.children)
    }

    private func compactHomeSchedule(_ item: DailyScheduleDTO) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(childIdentityColor(for: item.childId)).frame(width: 9, height: 9).padding(.top, 5).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.childName).font(.subheadline.weight(.semibold)).foregroundStyle(HomePalette.primary)
                    Text(item.schoolName ?? (zh ? "未设置学校" : "No school selected"))
                        .font(.caption).foregroundStyle(HomePalette.secondary)
                    if item.date != dateKey(offset: 0) {
                        Text(schoolLocalDateNote(item.date, childId: item.childId))
                            .font(.caption2).foregroundStyle(HomePalette.tertiary)
                    }
                }
                Spacer(minLength: 4)
                homeScheduleStatusPill(item)
            }

            if isHomeNonInstructionalDay(item) {
                Label(zh ? "这一天没有常规上课" : "No regular school on this day", systemImage: "sun.max")
                    .font(.caption.weight(.medium)).foregroundStyle(HomePalette.primary)
                if session.isLoadingNextInstructionalDay {
                    ProgressView(zh ? "正在查找下一次上课日…" : "Finding the next school day…")
                        .font(.caption)
                } else if let nextDay = session.nextInstructionalDays.first(where: { $0.childId == item.childId }) {
                    if let nextDate = nextDay.date {
                        Text((zh ? "下一次上课：" : "Next school day: ")
                            + nextInstructionalDateLabel(nextDate, childId: item.childId))
                            .font(.caption).foregroundStyle(HomePalette.secondary)
                    } else {
                        Text(zh ? "未来 21 天内暂无上课日。" : "No school day in the next 21 days.")
                            .font(.caption).foregroundStyle(HomePalette.secondary)
                    }
                } else if let error = session.nextInstructionalDayErrorMessage {
                    Text(error).font(.caption).foregroundStyle(HomePalette.destructive)
                }

                ForEach(item.eventTitles, id: \.self) { title in
                    Label(title, systemImage: "calendar")
                        .font(.caption).foregroundStyle(HomePalette.secondary)
                }
            } else if item.status == "OK" {
                compactHomeTimePair(item)
                if item.firstPeriodCode == "P0", item.arrivalLabel != "PERIOD_0_START" {
                    Text(zh ? "包含第0节" : "Includes Period 0")
                        .font(.caption2.weight(.medium)).foregroundStyle(HomePalette.secondary)
                }
                if session.homeEventsErrorMessage != nil, !item.eventTitles.isEmpty {
                    ForEach(item.eventTitles, id: \.self) { title in
                        Label(title, systemImage: "calendar.badge.exclamationmark")
                            .font(.caption).foregroundStyle(HomePalette.secondary)
                    }
                }
            } else {
                Text(statusLabel(item.status)).font(.caption).foregroundStyle(HomePalette.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func compactScheduleStatusLabel(_ item: DailyScheduleDTO) -> String {
        guard item.status == "OK", let scheduleType = item.scheduleType else {
            return statusLabel(item.status)
        }
        let normalizedType = scheduleType.uppercased()
        guard !["", "REGULAR", "REGULAR_DAY"].contains(normalizedType) else {
            return statusLabel(item.status)
        }
        return scheduleTypeLabel(scheduleType)
    }

    @ViewBuilder
    private func compactHomeTimePair(_ item: DailyScheduleDTO) -> some View {
        if let arrival = item.arrivalTime, let dismissal = item.dismissalTime {
            Text("\(arrival.prefix(5))  →  \(dismissal.prefix(5))")
                .font(.headline.monospacedDigit())
                .foregroundStyle(HomePalette.primary)
                .accessibilityLabel(zh
                    ? "\(arrivalTimeLabel(item))：\(arrival)，放学：\(dismissal)"
                    : "\(arrivalTimeLabel(item)): \(arrival), dismissal: \(dismissal)")
        } else if let arrival = item.arrivalTime {
            Text("\(arrivalTimeLabel(item)) · \(arrival.prefix(5))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(HomePalette.primary)
        } else if let dismissal = item.dismissalTime {
            Text("\(zh ? "放学" : "Dismissal") · \(dismissal.prefix(5))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(HomePalette.primary)
        }
    }

    private func childIdentityColors(for event: ParentEventDTO) -> [String: Color] {
        MeroliChildIdentity.colors(for: event, familyChildren: session.children)
    }

    private func todayHomeEventList(_ bundles: [HomeEventBundle]) -> some View {
        VStack(spacing: 0) {
            ForEach(bundles) { bundle in
                homeEventBundleRows(bundle)
                if bundle.id != bundles.last?.id { Divider().overlay(HomePalette.line) }
            }
        }
        .padding(.horizontal, 15)
        .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func homeEventBundleRows(_ bundle: HomeEventBundle) -> some View {
        let important = bundle.events.filter { bundle.isShared || !isCollapsibleHomeActivity($0) }
        let ordinary = bundle.events.filter { !bundle.isShared && isCollapsibleHomeActivity($0) }
        let initiallyVisible = important + Array(ordinary.prefix(2))
        let collapsed = Array(ordinary.dropFirst(2))

        return VStack(spacing: 0) {
            ForEach(initiallyVisible) { event in
                homeEventRow(event, childIdFilter: bundle.childIdFilter)
                if event.id != initiallyVisible.last?.id || !collapsed.isEmpty {
                    Divider().overlay(HomePalette.line)
                }
            }
            if !collapsed.isEmpty {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedHomeEventBundles.contains(bundle.id) },
                        set: { isExpanded in
                            if isExpanded { expandedHomeEventBundles.insert(bundle.id) }
                            else { expandedHomeEventBundles.remove(bundle.id) }
                        }
                    )
                ) {
                    ForEach(collapsed) { event in
                        homeEventRow(event, childIdFilter: bundle.childIdFilter)
                        if event.id != collapsed.last?.id { Divider().overlay(HomePalette.line) }
                    }
                } label: {
                    Text(zh
                        ? "另外 \(collapsed.count) 项学校活动"
                        : "\(collapsed.count) more school \(collapsed.count == 1 ? "activity" : "activities")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomePalette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .tint(HomePalette.brand)
            }
        }
    }

    private func homeEventRow(_ event: ParentEventDTO, childIdFilter: String?) -> some View {
        Button { selectedEvent = event } label: {
            EventRow(
                event: event,
                zh: zh,
                childIdentityColors: childIdentityColors(for: event),
                childIdFilter: childIdFilter,
                showsActionLabel: true,
                homeStyle: true
            )
        }
        .buttonStyle(.plain)
        .padding(.vertical, 9)
    }

    private func isCollapsibleHomeActivity(_ event: ParentEventDTO) -> Bool {
        !MeroliEventPresentation.isHomeActionRequired(event) && !MeroliEventPresentation.isScheduleChange(event)
    }

    private func eventList(_ events: [ParentEventDTO], showsAllDayLabel: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(events) { event in
                Button { selectedEvent = event } label: {
                    EventRow(event: event, zh: zh, childIdentityColors: childIdentityColors(for: event), showsActionLabel: true, showsAllDayLabel: showsAllDayLabel, homeStyle: true)
                }
                    .buttonStyle(.plain)
                    .padding(.vertical, 12)
                if event.id != events.last?.id { Divider().overlay(HomePalette.line) }
            }
        }
        .padding(.horizontal, 15)
        .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func homeErrorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(zh ? "暂时无法读取家庭安排" : "Schedules are unavailable", systemImage: "exclamationmark.triangle")
                .font(.headline).foregroundStyle(HomePalette.destructive)
            Text(error).font(.subheadline).foregroundStyle(HomePalette.secondary)
            Button(zh ? "重试" : "Try again") {
                Task {
                    await session.loadFamily()
                    await session.loadDailySchedules(for: date, childId: selectedChildId.isEmpty ? nil : selectedChildId)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func schoolDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = schoolCalendar
        formatter.timeZone = schoolCalendar.timeZone
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func nextInstructionalDateLabel(_ value: String, childId: String? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = session.schoolTimezone(for: childId)
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return value }
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "OK": return zh ? "正常上课" : "School day"
        case "NO_SCHOOL": return zh ? "不上课" : "No school"
        case "NO_ENROLLMENT": return zh ? "未设置学校" : "No enrollment"
        case "NON_INSTRUCTIONAL_DAY": return zh ? "非上课日" : "Non-instructional day"
        case "EVENT_SCHEDULE_CONFLICT": return zh ? "活动课表冲突" : "Event schedule conflict"
        case "SCHEDULE_TEMPLATE_UNRESOLVED", "SCHEDULE_VARIANT_UNRESOLVED": return zh ? "课表需要确认" : "Schedule needs review"
        case "SCHEDULE_DATA_UNAVAILABLE", "SCHEDULE_UNAVAILABLE", "SCHEDULE_DATA_INCOMPLETE": return zh ? "学校时间待确认" : "School schedule unavailable"
        default: return zh ? "学校时间待确认" : "School schedule unavailable"
        }
    }

    private func scheduleTypeLabel(_ value: String) -> String {
        switch value.uppercased() {
        case "REGULAR", "REGULAR_DAY": return zh ? "正常作息" : "Regular schedule"
        case "NO_SCHOOL", "PUPIL_FREE_DAY", "BREAK", "HOLIDAY": return zh ? "学校不上课" : "No school"
        case "WEEKEND", "OUTSIDE_SCHOOL_YEAR": return zh ? "今天无常规上课" : "No regular school today"
        case "LATE_START": return zh ? "延迟到校" : "Late Start"
        case "NO_LATE_START": return zh ? "不延迟到校" : "No Late Start"
        case "MINIMUM_DAY": return zh ? "提前放学" : "Minimum Day"
        case "EARLY_RELEASE": return zh ? "提前放学" : "Early Release"
        case "WEDNESDAY": return zh ? "周三作息" : "Wednesday schedule"
        case "SPECIAL": return zh ? "特别作息" : "Special schedule"
        default: return zh ? "学校作息" : "School schedule"
        }
    }

    private func scheduleTime(title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(MeroliColor.muted)
            Text(value ?? "—").font(.title3.weight(.semibold)).foregroundStyle(MeroliColor.ink)
        }
    }

    private func scheduleTimePair(_ item: DailyScheduleDTO) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                scheduleTime(title: arrivalTimeLabel(item), value: item.arrivalTime)
                Spacer(minLength: 4)
                scheduleTime(title: zh ? "放学" : "Dismissal", value: item.dismissalTime)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(MeroliColor.ink)

            VStack(alignment: .leading, spacing: 6) {
                scheduleTime(title: arrivalTimeLabel(item), value: item.arrivalTime)
                scheduleTime(title: zh ? "放学" : "Dismissal", value: item.dismissalTime)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(MeroliColor.ink)
        }
    }

    private func arrivalTimeLabel(_ schedule: DailyScheduleDTO) -> String {
        switch schedule.arrivalLabel ?? (schedule.firstPeriodCode == "P0" ? "PERIOD_0_START" : "SCHOOL_START") {
        case "PERIOD_0_START": return zh ? "第0节开始" : "Period 0 starts"
        default: return zh ? "到校" : "Arrival"
        }
    }
}

private struct CalendarScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var month = Date()
    @State private var selectedDate = Date()
    @AppStorage("meroli.calendar.childId") private var selectedChildId = ""
    @State private var selectedEvent: ParentEventDTO?
    @State private var showsPersonalEventEditor = false
    @AppStorage("meroli.calendar.displayMode") private var displayMode = "month"
    private var zh: Bool { session.usesChinese }
    private var schoolCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = session.schoolTimezone(for: selectedChildId.isEmpty ? nil : selectedChildId)
        calendar.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        return calendar
    }
    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.calendar = schoolCalendar
        formatter.timeZone = schoolCalendar.timeZone
        formatter.dateFormat = zh ? "yyyy年M月" : "MMMM yyyy"
        return formatter.string(from: month)
    }
    private var range: (Date, Date) {
        let components = schoolCalendar.dateComponents([.year, .month], from: month)
        let start = schoolCalendar.date(from: components) ?? month
        var next = DateComponents()
        next.month = 1
        next.day = -1
        let end = schoolCalendar.date(byAdding: next, to: start) ?? start
        return (start, end)
    }

    private var visibleCalendarEvents: [ParentEventDTO] {
        MeroliEventPresentation.sortedCalendar(session.calendarEvents)
    }
    private var childDisplayNames: [String: String] {
        MeroliChildIdentity.displayNames(
            children: session.children,
            enrollments: session.enrollments,
            schools: session.schools,
            zh: zh
        )
    }
    private var groupedEvents: [(String, [ParentEventDTO])] {
        let groups = Dictionary(grouping: visibleCalendarEvents, by: \.startDate)
        return groups.keys.sorted().map { ($0, groups[$0, default: []]) }
    }
    private var monthCells: [Date?] {
        guard let dayRange = schoolCalendar.range(of: .day, in: .month, for: month),
              let firstDay = schoolCalendar.date(from: schoolCalendar.dateComponents([.year, .month], from: month)) else { return [] }
        let leading = (schoolCalendar.component(.weekday, from: firstDay) - schoolCalendar.firstWeekday + 7) % 7
        let days = dayRange.compactMap { schoolCalendar.date(byAdding: .day, value: $0 - 1, to: firstDay) }
        return Array<Date?>(repeating: nil, count: leading) + days.map(Optional.some)
    }
    private var selectedDateEvents: [ParentEventDTO] {
        visibleCalendarEvents.filter { eventCovers($0, date: selectedDate) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel(zh ? "上个月" : "Previous month")
                    Spacer()
                    Text(monthTitle).font(.system(.title2, design: .serif, weight: .bold)).foregroundStyle(MeroliColor.ink)
                    Spacer()
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .accessibilityLabel(zh ? "下个月" : "Next month")
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                Picker(zh ? "显示方式" : "View", selection: $displayMode) {
                    Text(zh ? "月历" : "Month").tag("month")
                    Text(zh ? "日程" : "Agenda").tag("agenda")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)

                if session.children.count > 1 {
                    MeroliChildFilter(children: session.children, enrollments: session.enrollments, schools: session.schools, selection: $selectedChildId, zh: zh)
                    .padding(.horizontal, 19)
                    .padding(.top, 8)
                    .onChange(of: selectedChildId) { _, _ in
                        month = monthStart(.now)
                        selectedDate = schoolCalendar.startOfDay(for: .now)
                        Task { await load() }
                    }
                }

                if session.isLoadingCalendar && session.calendarEvents.isEmpty {
                    ProgressView(zh ? "正在读取日历…" : "Loading calendar…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let error = session.errorMessage, session.calendarEvents.isEmpty {
                    VStack(spacing: 14) {
                        Label(zh ? "暂时无法读取日历" : "Calendar unavailable", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundStyle(MeroliColor.ink)
                        Text(error).font(.subheadline).foregroundStyle(MeroliColor.muted).multilineTextAlignment(.center)
                        Button(zh ? "重试" : "Try again") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else if displayMode == "month" {
                    monthCalendar
                    HStack {
                        Text(dateHeading(selectedDate)).font(.headline).foregroundStyle(MeroliColor.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    if selectedDateEvents.isEmpty {
                        Text(zh ? "这一天没有日程。" : "No events on this day.")
                            .font(.subheadline).foregroundStyle(MeroliColor.muted).padding(.horizontal, 18)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(selectedDateEvents) { event in
                                Button { selectedEvent = event } label: {
                                    EventRow(
                                        event: event,
                                        zh: zh,
                                        childIdentityColors: MeroliChildIdentity.colors(for: event, familyChildren: session.children),
                                        childIdFilter: selectedChildId.isEmpty ? nil : selectedChildId,
                                        showsActionLabel: true,
                                        showsAllDayLabel: true
                                    )
                                }
                                    .buttonStyle(.plain).padding(.vertical, 10)
                                if event.id != selectedDateEvents.last?.id { Divider().overlay(MeroliColor.line) }
                            }
                        }
                        .padding(.horizontal, 15)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 18)
                    }
                } else {
                    if groupedEvents.isEmpty {
                        ContentUnavailableView(zh ? "这个月还没有活动" : "No events this month", systemImage: "calendar",
                            description: Text(zh ? "学校公告和家庭日程会显示在这里。" : "School announcements and family events will appear here."))
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(groupedEvents, id: \.0) { date, events in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formattedDate(date)).font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.muted)
                                VStack(spacing: 0) {
                                    ForEach(events) { event in
                                        Button { selectedEvent = event } label: {
                                            EventRow(
                                                event: event,
                                                zh: zh,
                                                childIdentityColors: MeroliChildIdentity.colors(for: event, familyChildren: session.children),
                                                childIdFilter: selectedChildId.isEmpty ? nil : selectedChildId,
                                                showsActionLabel: true,
                                                showsAllDayLabel: true
                                            )
                                        }
                                            .buttonStyle(.plain).padding(.vertical, 10)
                                        if event.id != events.last?.id { Divider().overlay(MeroliColor.line) }
                                    }
                                }
                                .padding(.horizontal, 15)
                                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                }
                }
                .padding(.bottom, 22)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 12).accessibilityHidden(true)
            }
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "日历" : "Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button { showsPersonalEventEditor = true } label: {
                            Image(systemName: "plus").accessibilityLabel(zh ? "添加家庭日程" : "Add family event")
                        }
                        Button(zh ? "今天" : "Today") {
                            month = monthStart(.now)
                            selectedDate = schoolCalendar.startOfDay(for: .now)
                            Task { await load() }
                        }
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: scenePhase) { _, phase in handleCalendarScenePhaseChange(phase) }
            .sheet(item: $selectedEvent) { event in EventDetailSheet(event: event, zh: zh) }
            .sheet(isPresented: $showsPersonalEventEditor) {
                PersonalEventEditor(zh: zh, initialDate: selectedDate) {
                    Task { await load() }
                }
                .environment(session)
            }
            .onChange(of: session.children.map(\.id)) { _, childIds in
                if !selectedChildId.isEmpty && !childIds.contains(selectedChildId) {
                    selectedChildId = ""
                }
                month = monthStart(.now)
                selectedDate = schoolCalendar.startOfDay(for: .now)
                Task { await load() }
            }
        }
    }

    private func shiftMonth(_ amount: Int) {
        month = schoolCalendar.date(byAdding: .month, value: amount, to: month) ?? month
        selectedDate = monthStart(month)
        Task { await load() }
    }

    private func handleCalendarScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active else { return }
        Task { await load() }
    }

    private func load() async {
        let (start, end) = range
        await session.loadCalendar(from: start, to: end, childId: selectedChildId.isEmpty ? nil : selectedChildId)
    }

    private func monthStart(_ date: Date) -> Date {
        let parts = schoolCalendar.dateComponents([.year, .month], from: date)
        return schoolCalendar.date(from: parts) ?? date
    }

    private func formattedDate(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = schoolCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return value }
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    private var monthCalendar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(schoolCalendar.veryShortStandaloneWeekdaySymbols, id: \.self) { day in
                    Text(day).font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.muted).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 3) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, value in
                    if let day = value {
                        let dayEvents = visibleCalendarEvents.filter { eventCovers($0, date: day) }
                        let childMarkers = calendarChildMarkers(for: dayEvents)
                        let eventChildNames = childMarkers.map { childDisplayNames[$0.id] ?? $0.name }
                        let visibleChildMarkers = Array(childMarkers.prefix(3))
                        let additionalChildCount = max(0, childMarkers.count - visibleChildMarkers.count)
                        let isSelected = schoolCalendar.isDate(day, inSameDayAs: selectedDate)
                        Button { selectDay(day) } label: {
                            VStack(spacing: 3) {
                                Text("\(schoolCalendar.component(.day, from: day))")
                                    .font(.subheadline.weight(isSelected ? .bold : .regular))
                                    .foregroundStyle(isSelected ? .white : MeroliColor.ink)
                                HStack(spacing: 3) {
                                    ForEach(visibleChildMarkers) { child in
                                        Circle().fill(MeroliChildIdentity.color(for: child.id, in: session.children))
                                            .frame(width: 6, height: 6)
                                            .overlay(Circle().stroke(isSelected ? .white : .clear, lineWidth: 1))
                                            .accessibilityHidden(true)
                                    }
                                    if !dayEvents.isEmpty && visibleChildMarkers.isEmpty {
                                        Circle().fill(MeroliColor.muted).frame(width: 5, height: 5).accessibilityHidden(true)
                                    }
                                    if additionalChildCount > 0 {
                                        Text("+\(additionalChildCount)")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(isSelected ? .white : MeroliColor.muted)
                                    }
                                }
                                .frame(minHeight: 10)
                                .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(isSelected ? Color(red: 30 / 255, green: 70 / 255, blue: 52 / 255) : .clear, in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(calendarDayAccessibilityLabel(day, events: dayEvents, childNames: eventChildNames))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    } else {
                        Color.clear.frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 18)
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = schoolCalendar
        formatter.timeZone = schoolCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func eventCovers(_ event: ParentEventDTO, date: Date) -> Bool {
        let key = dateKey(date)
        return event.startDate <= key && (event.endDate ?? event.startDate) >= key
    }

    private func calendarChildMarkers(for events: [ParentEventDTO]) -> [ParentEventChildDTO] {
        let children = events.flatMap(\.children).filter { selectedChildId.isEmpty || $0.id == selectedChildId }
        let childrenById = children.reduce(into: [String: ParentEventChildDTO]()) { result, child in
            result[child.id] = child
        }
        return childrenById.values.sorted { $0.id < $1.id }
    }

    private func selectDay(_ day: Date) {
        selectedDate = schoolCalendar.startOfDay(for: day)
        let selectedMonth = monthStart(day)
        guard !schoolCalendar.isDate(selectedMonth, equalTo: month, toGranularity: .month) else { return }
        month = selectedMonth
        Task { await load() }
    }

    private func calendarDayAccessibilityLabel(_ day: Date, events: [ParentEventDTO], childNames: [String]) -> String {
        guard !events.isEmpty else { return dateHeading(day) }
        let count = zh ? "\(events.count) 个活动" : "\(events.count) events"
        let children: String
        if childNames.count > 3 {
            children = zh ? "，\(childNames.count) 个孩子有活动" : ", events for \(childNames.count) children"
        } else if childNames.isEmpty {
            children = zh ? "，学校活动" : ", school events"
        } else {
            children = zh ? "，孩子：\(childNames.joined(separator: "、"))" : ", children: \(childNames.joined(separator: ", "))"
        }
        return zh
            ? "\(dateHeading(day))，\(count)\(children)"
            : "\(dateHeading(day)), \(count)\(children)"
    }

    private func dateHeading(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.calendar = schoolCalendar
        formatter.timeZone = schoolCalendar.timeZone
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

}

private enum MeroliEventPresentation {
    static func sorted(_ events: [ParentEventDTO]) -> [ParentEventDTO] {
        events.sorted {
            let leftPriority = priority($0)
            let rightPriority = priority($1)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            let leftTime = $0.startTime ?? "99:99"
            let rightTime = $1.startTime ?? "99:99"
            if leftTime != rightTime { return leftTime < rightTime }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    static func sortedCalendar(_ events: [ParentEventDTO]) -> [ParentEventDTO] {
        events.sorted {
            let leftPriority = priority($0)
            let rightPriority = priority($1)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            let leftTime = $0.startTime ?? "99:99"
            let rightTime = $1.startTime ?? "99:99"
            if leftTime != rightTime { return leftTime < rightTime }
            let titleOrder = $0.title.localizedStandardCompare($1.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return $0.id < $1.id
        }
    }

    private static func priority(_ event: ParentEventDTO) -> Int {
        if isActionRequired(event) {
            return 0
        }
        let scheduleTypes: Set<String> = ["NO_SCHOOL", "PUPIL_FREE_DAY", "BREAK", "HOLIDAY", "MINIMUM_DAY", "LATE_START", "NO_LATE_START", "EARLY_RELEASE"]
        if scheduleTypes.contains(event.eventType.uppercased()) || (!event.scheduleAction.isEmpty && event.scheduleAction.uppercased() != "NONE") {
            return 1
        }
        return event.startTime == nil ? 3 : 2
    }

    static func isMeaningful(_ event: ParentEventDTO) -> Bool {
        priority(event) <= 2
    }

    static func isActionRequired(_ event: ParentEventDTO) -> Bool {
        ["ACTION_REQUIRED", "CRITICAL_ACTION"].contains(event.parentRelevance.uppercased())
            || ["ACTION_REQUIRED", "DEADLINE"].contains(event.eventType.uppercased())
    }

    static func isHomeActionRequired(_ event: ParentEventDTO) -> Bool {
        let relevance = event.parentRelevance.isEmpty ? event.priority : event.parentRelevance
        return ["ACTION_REQUIRED", "CRITICAL_ACTION"].contains(relevance.uppercased())
            || ["ACTION_REQUIRED", "DEADLINE"].contains(event.eventType.uppercased())
    }

    static func isScheduleChange(_ event: ParentEventDTO) -> Bool {
        let scheduleTypes: Set<String> = ["NO_SCHOOL", "PUPIL_FREE_DAY", "BREAK", "HOLIDAY", "MINIMUM_DAY", "LATE_START", "NO_LATE_START", "EARLY_RELEASE"]
        return scheduleTypes.contains(event.eventType.uppercased())
            || (!event.scheduleAction.isEmpty && event.scheduleAction.uppercased() != "NONE")
    }

    static func sortedUpcoming(_ events: [ParentEventDTO]) -> [ParentEventDTO] {
        events.sorted { left, right in
            let leftPriority = priority(left)
            let rightPriority = priority(right)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            if left.allDay != right.allDay { return !left.allDay }
            let leftTime = left.startTime ?? "99:99"
            let rightTime = right.startTime ?? "99:99"
            if leftTime != rightTime { return leftTime < rightTime }
            let titleOrder = left.title.localizedStandardCompare(right.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return left.id < right.id
        }
    }
}

private enum MeroliGradePresentation {
    private static let order = ["PK", "TK", "K"] + (1...12).map(String.init)

    static func label(_ gradeCode: String, zh: Bool) -> String {
        let normalized = gradeCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "PK": return zh ? "学前班" : "PK"
        case "TK": return zh ? "过渡幼儿园" : "TK"
        case "K": return zh ? "幼儿园" : "Kindergarten"
        default:
            guard let grade = Int(normalized), (1...12).contains(grade) else {
                return zh ? "年级待确认" : "Grade not confirmed"
            }
            return zh ? "\(grade)年级" : "Grade \(grade)"
        }
    }

    static func range(_ grades: [String], zh: Bool) -> String? {
        let available = Set(grades.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })
        let ordered = order.filter { available.contains($0) }
        guard let first = ordered.first, let last = ordered.last else { return nil }
        guard first != last else { return label(first, zh: zh) }
        if !zh { return "Grades \(first)–\(last)" }
        if Int(first) != nil, Int(last) != nil { return "\(first)–\(last)年级" }
        return "\(label(first, zh: true))–\(label(last, zh: true))"
    }

    static func range(minimum: Int, maximum: Int, zh: Bool) -> String {
        let lower = code(for: minimum)
        let upper = code(for: maximum)
        guard lower != upper else { return label(lower, zh: zh) }
        if !zh { return "Grades \(lower)–\(upper)" }
        if minimum > 0, maximum > 0 { return "\(minimum)–\(maximum)年级" }
        return "\(label(lower, zh: true))–\(label(upper, zh: true))"
    }

    private static func code(for grade: Int) -> String {
        switch grade {
        case -2: return "PK"
        case -1: return "TK"
        case 0: return "K"
        default: return String(grade)
        }
    }
}

private enum SchoolYearTransitionPresentation {
    static func isActionable(_ transition: SchoolYearTransitionDTO) -> Bool {
        guard transition.transitionAvailable == true else { return false }
        return transition.targetSchoolYearId != nil
            || transition.graduating
            || transition.finishedK12Available
    }

    static func actionableChildCount(_ transitions: [SchoolYearTransitionDTO]) -> Int {
        Set(transitions.filter { isActionable($0) }.map(\.childId)).count
    }

    static func inactiveStatus(_ transitions: [SchoolYearTransitionDTO], isLoading: Bool, zh: Bool) -> String {
        if isLoading { return zh ? "正在检查学年安排…" : "Checking school year updates…" }
        guard !transitions.isEmpty else {
            return zh ? "目前无需更新" : "Nothing to review right now"
        }

        let dates = Set(transitions
            .compactMap { $0.transitionAvailableDate }
            .filter { !$0.isEmpty })
        guard transitions.allSatisfy({ $0.transitionAvailable != true }) else {
            return zh ? "尚未开放" : "Not available yet"
        }
        guard dates.count == 1, dates.count == transitions.count,
              let dateValue = dates.first,
              let date = parseAvailabilityDate(dateValue) else {
            return zh ? "尚未开放" : "Not available yet"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = zh ? "M月d日" : "MMM d"
        let dateLabel = formatter.string(from: date)
        return zh ? "\(dateLabel)后开放" : "Available after \(dateLabel)"
    }

    private static func parseAvailabilityDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

private enum MeroliChildIdentity {
    private static func orderedIDs(for children: [ChildDTO]) -> [String] {
        Array(Set(children.map(\.id))).sorted()
    }

    static func colors(for children: [ChildDTO]) -> [String: Color] {
        Dictionary(uniqueKeysWithValues: orderedIDs(for: children).enumerated().map { index, childId in
            (childId, MeroliColor.childIdentity[index % MeroliColor.childIdentity.count])
        })
    }

    static func color(for childId: String, in children: [ChildDTO]) -> Color {
        guard let index = orderedIDs(for: children).firstIndex(of: childId) else { return MeroliColor.muted }
        return MeroliColor.childIdentity[index % MeroliColor.childIdentity.count]
    }

    static func colors(for event: ParentEventDTO, familyChildren: [ChildDTO]) -> [String: Color] {
        let familyColors = colors(for: familyChildren)
        return event.children.reduce(into: [String: Color]()) { result, child in
            result[child.id] = familyColors[child.id] ?? MeroliColor.muted
        }
    }

    static func displayNames(
        children: [ChildDTO],
        enrollments: [EnrollmentDTO],
        schools: [ParentSchoolDTO],
        zh: Bool
    ) -> [String: String] {
        let groups = Dictionary(grouping: children, by: { $0.nickname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var names = Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0.nickname) })

        for siblings in groups.values where siblings.count > 1 {
            let currentEnrollments = Dictionary(uniqueKeysWithValues: siblings.compactMap { child in
                enrollments.first(where: { $0.childId == child.id && $0.isCurrent }).map { (child.id, $0) }
            })
            let gradeLabels: [String?] = siblings.map { child in
                guard let gradeCode = currentEnrollments[child.id]?.gradeCode else { return nil }
                let label = MeroliGradePresentation.label(gradeCode, zh: zh)
                return label.isEmpty ? nil : label
            }
            let gradesAreDistinct = gradeLabels.allSatisfy { $0 != nil } && Set(gradeLabels.compactMap { $0 }).count == siblings.count
            let shortSchoolNames = siblings.map { child -> String? in
                guard let enrollment = currentEnrollments[child.id] else { return nil }
                let schoolName = schools.first(where: { $0.id == enrollment.schoolId })?.name ?? enrollment.schoolName
                let shortName = schoolName.split(whereSeparator: \.isWhitespace).prefix(2).joined(separator: " ")
                return shortName.isEmpty ? nil : shortName
            }
            let shortSchoolNamesAreDistinct = shortSchoolNames.allSatisfy { $0 != nil }
                && Set(shortSchoolNames.compactMap { $0 }).count == siblings.count

            for (index, child) in siblings.enumerated() {
                let discriminator: String?
                if gradesAreDistinct {
                    discriminator = gradeLabels[index]
                } else if let enrollment = currentEnrollments[child.id] {
                    let schoolName = schools.first(where: { $0.id == enrollment.schoolId })?.name ?? enrollment.schoolName
                    if shortSchoolNamesAreDistinct {
                        discriminator = shortSchoolNames[index]
                    } else {
                        let fullSchoolName = schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
                        discriminator = fullSchoolName.isEmpty ? nil : fullSchoolName
                    }
                } else {
                    discriminator = nil
                }
                if let discriminator {
                    names[child.id] = "\(child.nickname) · \(discriminator)"
                }
            }
        }
        return names
    }

}

private struct EventRow: View {
    let event: ParentEventDTO
    let zh: Bool
    var childIdentityColors: [String: Color] = [:]
    var childIdFilter: String? = nil
    var showsActionLabel = false
    var showsAllDayLabel = false
    var homeStyle = false

    private var visibleChildren: [ParentEventChildDTO] {
        guard let childIdFilter else { return event.children }
        return event.children.filter { $0.id == childIdFilter }
    }

    private var homeVisualStyle: HomeEventVisualStyle {
        let type = event.eventType.uppercased()
        let action = event.scheduleAction.uppercased()
        let category = (event.category ?? "").uppercased()
        let noSchoolTypes: Set<String> = ["NO_SCHOOL", "PUPIL_FREE_DAY", "BREAK", "HOLIDAY"]

        if noSchoolTypes.contains(type) || action == "NO_SCHOOL" {
            return HomeEventVisualStyle(
                tag: zh ? "停课" : "No school",
                foreground: HomePalette.destructive,
                accent: HomePalette.destructive,
                background: HomePalette.destructivePale
            )
        }
        if MeroliEventPresentation.isScheduleChange(event) {
            return HomeEventVisualStyle(
                tag: zh ? "作息调整" : "Schedule change",
                foreground: HomePalette.amber,
                accent: HomePalette.amberAccent,
                background: HomePalette.amberPale
            )
        }
        if MeroliEventPresentation.isHomeActionRequired(event) {
            return HomeEventVisualStyle(
                tag: zh ? "需处理" : "Action",
                foreground: HomePalette.amber,
                accent: HomePalette.amberAccent,
                background: HomePalette.amberPale
            )
        }

        let knownCategory: (String, Color, Color, Color)?
        if event.isPersonal == true {
            switch category {
            case "CLASS": knownCategory = (zh ? "课程" : "Class", HomePalette.purple, HomePalette.purple, HomePalette.surface2)
            case "ACTIVITY": knownCategory = (zh ? "活动" : "Activity", HomePalette.amber, HomePalette.amberAccent, HomePalette.amberPale)
            case "TRAVEL": knownCategory = (zh ? "出行" : "Travel", HomePalette.blue, HomePalette.blue, HomePalette.surface2)
            case "HEALTH": knownCategory = (zh ? "健康" : "Health", HomePalette.blue, HomePalette.blue, HomePalette.surface2)
            case "FAMILY": knownCategory = (zh ? "家庭" : "Family", HomePalette.purple, HomePalette.purple, HomePalette.surface2)
            default: knownCategory = (zh ? "个人" : "Personal", HomePalette.purple, HomePalette.purple, HomePalette.surface2)
            }
        } else if category == "ACTIVITY" {
            knownCategory = (zh ? "活动" : "Activity", HomePalette.amber, HomePalette.amberAccent, HomePalette.amberPale)
        } else if category == "SPORTS" {
            knownCategory = (zh ? "体育" : "Sports", HomePalette.blue, HomePalette.blue, HomePalette.surface2)
        } else if category == "CLASS" {
            knownCategory = (zh ? "课程" : "Class", HomePalette.purple, HomePalette.purple, HomePalette.surface2)
        } else {
            switch type {
            case "CLUB", "FUNDRAISER": knownCategory = (zh ? "活动" : "Activity", HomePalette.amber, HomePalette.amberAccent, HomePalette.amberPale)
            case "SPORTS": knownCategory = (zh ? "体育" : "Sports", HomePalette.blue, HomePalette.blue, HomePalette.surface2)
            case "MEETING": knownCategory = (zh ? "会议" : "Meeting", HomePalette.blue, HomePalette.blue, HomePalette.surface2)
            default:
                if event.scopeType.uppercased() == "DISTRICT" {
                    knownCategory = (zh ? "学区活动" : "District event", HomePalette.secondary, HomePalette.tertiary, HomePalette.surface2)
                } else if event.scopeType.uppercased() == "SCHOOL" {
                    knownCategory = (zh ? "学校活动" : "School event", HomePalette.secondary, HomePalette.tertiary, HomePalette.surface2)
                } else {
                    knownCategory = nil
                }
            }
        }

        guard let (tag, foreground, accent, background) = knownCategory else {
            return HomeEventVisualStyle(tag: nil, foreground: HomePalette.secondary, accent: HomePalette.tertiary, background: HomePalette.surface2)
        }
        return HomeEventVisualStyle(tag: tag, foreground: foreground, accent: accent, background: background)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(
                homeStyle
                    ? homeVisualStyle.accent
                    : (MeroliEventPresentation.isActionRequired(event) ? MeroliColor.coral : MeroliColor.gold)
            )
                .frame(width: 4)
                .padding(.vertical, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    if event.isPersonal == true, let icon = event.categoryIcon {
                        Text(icon).font(.title3)
                    }
                    Text(event.title)
                        .font(.headline)
                        .foregroundStyle(homeStyle ? HomePalette.primary : MeroliColor.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(homeStyle ? HomePalette.tertiary : MeroliColor.muted)
                }
                HStack(spacing: 6) {
                    if !event.allDay, let start = event.startTime { Text(String(start.prefix(5))) }
                    if showsAllDayLabel && event.allDay { Text(zh ? "全天" : "All day") }
                    if !visibleChildren.isEmpty {
                        ForEach(visibleChildren) { child in
                            Circle().fill(childIdentityColors[child.id] ?? MeroliColor.muted)
                                .frame(width: 7, height: 7).accessibilityHidden(true)
                        }
                        Text(visibleChildren.map { child in
                            guard let school = event.schools.first(where: { $0.id == child.schoolId })?.name, !school.isEmpty else {
                                return child.name
                            }
                            return "\(child.name) · \(school)"
                        }.joined(separator: ", "))
                    } else if !event.schools.isEmpty {
                        Text(event.schools.map(\.name).joined(separator: ", "))
                    }
                }
                .font(.caption)
                .foregroundStyle(homeStyle ? HomePalette.secondary : MeroliColor.muted)
                .monospacedDigit()
                if homeStyle, let tag = homeVisualStyle.tag {
                    Text(tag)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(homeVisualStyle.foreground)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(homeVisualStyle.background, in: Capsule())
                }
                if !homeStyle && showsActionLabel && MeroliEventPresentation.isActionRequired(event) {
                    Text(zh ? "需处理" : "Action")
                        .font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.coral)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(MeroliColor.coral.opacity(0.1), in: Capsule())
                }
                if !event.action.isEmpty {
                    Text(event.action).font(.subheadline).foregroundStyle(homeStyle ? HomePalette.secondary : MeroliColor.coral)
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct PersonalEventEditor: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var location = ""
    @State private var category = "ACTIVITY"
    @State private var childId = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var startTime = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: .now) ?? .now
    @State private var endTime = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: .now) ?? .now
    @State private var allDay = false
    @State private var isSaving = false
    @FocusState private var focusedField: Field?
    let zh: Bool
    let onSaved: () -> Void

    private enum Field { case title, location, notes }

    init(zh: Bool, initialDate: Date, onSaved: @escaping () -> Void) {
        self.zh = zh
        self.onSaved = onSaved
        _startDate = State(initialValue: initialDate)
        _endDate = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(zh ? "日程" : "Event") {
                    TextField(zh ? "日程名称" : "Event title", text: $title)
                        .focused($focusedField, equals: .title).submitLabel(.next)
                    Picker(zh ? "分类" : "Category", selection: $category) {
                        ForEach(categories, id: \.code) { item in
                            Text("\(item.icon)  \(item.title)").tag(item.code)
                        }
                    }
                    Toggle(zh ? "全天" : "All day", isOn: $allDay)
                    DatePicker(zh ? "开始日期" : "Start date", selection: $startDate, displayedComponents: .date)
                    DatePicker(zh ? "结束日期" : "End date", selection: $endDate, in: startDate..., displayedComponents: .date)
                    if !allDay {
                        DatePicker(zh ? "开始时间" : "Start time", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker(zh ? "结束时间" : "End time", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                    Picker(zh ? "关联孩子（可选）" : "Child (optional)", selection: $childId) {
                        Text(zh ? "全家" : "Everyone").tag("")
                        ForEach(session.children) { child in Text(child.nickname).tag(child.id) }
                    }
                }
                Section(zh ? "详情" : "Details") {
                    TextField(zh ? "地点（可选）" : "Location (optional)", text: $location)
                        .focused($focusedField, equals: .location)
                    TextField(zh ? "备注（可选）" : "Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6).focused($focusedField, equals: .notes)
                }
                if let error = session.errorMessage {
                    Section { Text(error).foregroundStyle(MeroliColor.coral) }
                }
                Section {
                    Button {
                        focusedField = nil
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving { ProgressView().padding(.trailing, 7) }
                            Text(zh ? "保存日程" : "Save event")
                            Spacer()
                        }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (!allDay && endTime <= startTime))
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(zh ? "添加家庭日程" : "Add family event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(zh ? "完成" : "Done") { focusedField = nil }
                }
                ToolbarItem(placement: .topBarLeading) { Button(zh ? "取消" : "Cancel") { dismiss() } }
            }
            .background(MeroliColor.canvas)
        }
        .presentationDetents([.large])
    }

    private var categories: [(code: String, icon: String, title: String)] {
        [
            ("CLASS", "📚", zh ? "课程" : "Class"),
            ("ACTIVITY", "⚽", zh ? "活动" : "Activity"),
            ("TRAVEL", "✈️", zh ? "旅行" : "Travel"),
            ("HEALTH", "🩺", zh ? "健康" : "Health"),
            ("FAMILY", "🏠", zh ? "家庭" : "Family"),
            ("OTHER", "✨", zh ? "其他" : "Other")
        ]
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        var payload: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "category": category,
            "start_date": formatter.string(from: startDate),
            "end_date": formatter.string(from: endDate),
            "all_day": allDay,
            "timezone": formatter.timeZone.identifier,
            "location": location,
            "notes": notes
        ]
        if !childId.isEmpty { payload["child_id"] = childId }
        if !allDay {
            payload["start_time"] = timeFormatter.string(from: startTime)
            payload["end_time"] = timeFormatter.string(from: endTime)
        }
        if await session.savePersonalEvent(payload: payload) {
            onSaved()
            dismiss()
        }
    }
}

private struct EventDetailSheet: View {
    @Environment(SessionStore.self) private var session
    let event: ParentEventDTO
    let zh: Bool
    @State private var detail: ParentEventDTO?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(zh ? "正在读取活动详情…" : "Loading event details…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 14) {
                        Text(errorMessage).font(.subheadline).foregroundStyle(MeroliColor.muted).multilineTextAlignment(.center)
                        Button(zh ? "重试" : "Try again") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let detail {
                    detailContent(detail)
                }
            }
            .background(MeroliColor.canvas.ignoresSafeArea())
            .navigationTitle(zh ? "活动详情" : "Event details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { CloseSheetButton(zh: zh) } }
        }
        .task(id: event.id) { await load() }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        switch await session.loadCalendarEvent(id: event.id, isPersonal: event.isPersonal == true) {
        case .success(let loadedEvent): detail = loadedEvent
        case .failure(let error): errorMessage = error.message
        }
        isLoading = false
    }

    private func detailContent(_ event: ParentEventDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(event.title).font(.system(.title, design: .serif, weight: .bold)).foregroundStyle(MeroliColor.ink)
                Label(eventDateLabel(for: event), systemImage: event.allDay ? "calendar" : "clock")
                    .font(.subheadline).foregroundStyle(MeroliColor.muted)
                if zh, let originalTitle = event.originalTitle, !originalTitle.isEmpty, originalTitle != event.title {
                    DisclosureGroup(zh ? "查看英文原标题" : "View original title") {
                        Text(originalTitle).font(.subheadline).foregroundStyle(MeroliColor.ink).padding(.top, 5)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MeroliColor.muted)
                }
                if !event.explanation.isEmpty { Text(event.explanation).font(.body).foregroundStyle(MeroliColor.ink) }
                if zh, let originalExplanation = event.originalExplanation, !originalExplanation.isEmpty,
                   originalExplanation != event.explanation {
                    DisclosureGroup("查看英文原文") {
                        Text(originalExplanation).font(.subheadline).foregroundStyle(MeroliColor.ink).padding(.top, 5)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MeroliColor.muted)
                }
                if !event.action.isEmpty {
                    Label(event.action, systemImage: "checkmark.circle")
                        .font(.body.weight(.medium)).foregroundStyle(MeroliColor.coral)
                }
                if zh, let originalAction = event.originalAction, !originalAction.isEmpty,
                   originalAction != event.action {
                    DisclosureGroup("查看英文行动提示") {
                        Text(originalAction).font(.subheadline).foregroundStyle(MeroliColor.ink).padding(.top, 5)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MeroliColor.muted)
                }
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(MeroliColor.muted)
                }
                if !event.children.isEmpty {
                    Label(event.children.map(\.name).joined(separator: ", "), systemImage: "person.2")
                        .font(.subheadline).foregroundStyle(MeroliColor.muted)
                }
                if !event.schools.isEmpty {
                    Label(event.schools.map(\.name).joined(separator: ", "), systemImage: "building.2")
                        .font(.subheadline).foregroundStyle(MeroliColor.muted)
                }
                if let updatedAt = updatedAtLabel(for: event) {
                    Label(zh ? "资料更新：\(updatedAt)" : "Updated \(updatedAt)", systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(MeroliColor.muted)
                }
                if let sourceURL = officialSourceURL(for: event) {
                    Link(destination: sourceURL) {
                        Label(zh ? "查看官方来源 · \(event.sourceName)" : "Official source · \(event.sourceName)", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
    }

    private func eventDateLabel(for event: ParentEventDTO) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: event.timezone) ?? TimeZone(identifier: "America/Los_Angeles")
        parser.dateFormat = "yyyy-MM-dd"
        guard let start = parser.date(from: event.startDate) else { return event.startDate }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.timeZone = parser.timeZone
        formatter.dateStyle = .long
        let startLabel = formatter.string(from: start)
        let endKey = event.endDate ?? event.startDate
        let endLabel: String
        if endKey != event.startDate, let end = parser.date(from: endKey) {
            endLabel = "–\(formatter.string(from: end))"
        } else {
            endLabel = ""
        }
        let timeLabel = event.allDay
            ? (zh ? "全天" : "All day")
            : [event.startTime.map { String($0.prefix(5)) }, event.endTime.map { String($0.prefix(5)) }].compactMap { $0 }.joined(separator: "–")
        return "\(startLabel)\(endLabel) · \(timeLabel)"
    }

    private func updatedAtLabel(for event: ParentEventDTO) -> String? {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: event.lastUpdatedAt) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.timeZone = TimeZone(identifier: event.timezone) ?? TimeZone(identifier: "America/Los_Angeles")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func officialSourceURL(for event: ParentEventDTO) -> URL? {
        guard let url = URL(string: event.sourceUrl),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }
}

private struct CloseSheetButton: View {
    @Environment(\.dismiss) private var dismiss
    let zh: Bool
    var body: some View { Button(zh ? "完成" : "Done") { dismiss() } }
}

private struct FamilySchoolSummary: Identifiable {
    let schoolId: String
    let schoolName: String
    let districtId: String
    let enrollments: [EnrollmentDTO]
    let school: ParentSchoolDTO?

    var id: String { schoolId }
}

private struct SchoolsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var schoolDetails: [String: ParentSchoolDTO] = [:]
    @State private var showsManagement = false
    @State private var selectedSchoolId = ""
    @State private var selectedSchoolName = ""
    @State private var isLoadingSchools = false
    private var zh: Bool { session.usesChinese }

    private var schoolSummaries: [FamilySchoolSummary] {
        Dictionary(grouping: session.enrollments.filter(\.isCurrent), by: \.schoolId)
            .map { schoolId, enrollments in
                let first = enrollments[0]
                return FamilySchoolSummary(
                    schoolId: schoolId,
                    schoolName: schoolDetails[schoolId]?.name ?? first.schoolName,
                    districtId: schoolDetails[schoolId]?.districtId ?? first.districtId,
                    enrollments: enrollments.sorted { $0.childName.localizedStandardCompare($1.childName) == .orderedAscending },
                    school: schoolDetails[schoolId]
                )
            }
            .sorted { $0.schoolName.localizedStandardCompare($1.schoolName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(zh ? "学校" : "Schools")
                                .font(.system(.largeTitle, design: .serif, weight: .bold)).foregroundStyle(MeroliColor.ink)
                            Text(zh ? "孩子目前就读的学校。" : "Schools currently relevant to your family.")
                                .font(.subheadline).foregroundStyle(MeroliColor.muted)
                        }
                        Spacer(minLength: 4)
                        Button { showsManagement = true } label: {
                            Text(zh ? "管理孩子与学校" : "Manage Children & Schools")
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(MeroliColor.ink)
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(.white, in: Capsule())
                                .overlay(Capsule().stroke(MeroliColor.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("meroli.schools.manage")
                    }

                    if let error = session.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline).foregroundStyle(MeroliColor.coral)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isLoadingSchools && session.enrollments.isEmpty {
                        ProgressView(zh ? "正在读取学校资料…" : "Loading schools…")
                            .frame(maxWidth: .infinity, minHeight: 140)
                    } else if schoolSummaries.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "building.2.crop.circle")
                                .font(.system(.title)).foregroundStyle(MeroliColor.ink)
                            Text(zh ? "还没有关联的在读学校" : "No current schools yet")
                                .font(.headline).foregroundStyle(MeroliColor.ink)
                            Text(zh ? "添加孩子并关联学校后，学校资料会显示在这里。" : "Add a child and link a school to see your family's school information here.")
                                .font(.subheadline).foregroundStyle(MeroliColor.muted)
                            Button { showsManagement = true } label: {
                                Text(zh ? "添加孩子" : "Add child")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 11)
                                    .background(MeroliColor.ink, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 17))
                    } else {
                        VStack(spacing: 12) {
                            ForEach(schoolSummaries) { summary in
                                Button {
                                    selectedSchoolId = summary.schoolId
                                    selectedSchoolName = summary.schoolName
                                } label: {
                                    VStack(alignment: .leading, spacing: 11) {
                                        HStack(alignment: .top, spacing: 8) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                if let district = session.districts.first(where: { $0.id == summary.districtId }) {
                                                    Text(district.name.uppercased())
                                                        .font(.caption2.weight(.semibold)).tracking(0.7)
                                                        .foregroundStyle(MeroliColor.muted)
                                                }
                                                Text(summary.schoolName)
                                                    .font(.system(.title3, design: .serif, weight: .bold))
                                                    .foregroundStyle(MeroliColor.ink)
                                                    .multilineTextAlignment(.leading)
                                                if let gradeRange = officialGradeRange(summary.school?.availableGrades ?? []) {
                                                    Text(gradeRange).font(.caption).foregroundStyle(MeroliColor.muted)
                                                }
                                            }
                                            Spacer(minLength: 2)
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                                .padding(.top, 4)
                                        }

                                        Divider().overlay(MeroliColor.line)

                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(summary.enrollments) { enrollment in
                                                HStack(spacing: 8) {
                                                    Circle().fill(MeroliChildIdentity.color(for: enrollment.childId, in: session.children))
                                                        .frame(width: 9, height: 9).accessibilityHidden(true)
                                                    Text("\(enrollment.childName) · \(localizedGrade(enrollment.gradeCode))")
                                                        .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                }
                                            }
                                        }
                                    }
                                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 17))
                                    .overlay(RoundedRectangle(cornerRadius: 17).stroke(MeroliColor.line, lineWidth: 1))
                                    .contentShape(RoundedRectangle(cornerRadius: 17))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("meroli.schools.\(summary.schoolId)")
                            }
                        }
                    }
                }
                .padding(.horizontal, 19).padding(.top, 16).padding(.bottom, 28)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 12).accessibilityHidden(true)
            }
            .background(MeroliColor.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await loadSchools(forceRefresh: true) }
            .task { await loadSchools(forceRefresh: false) }
            .sheet(isPresented: $showsManagement, onDismiss: {
                Task { await loadSchools(forceRefresh: false) }
            }) {
                FamilyScreen()
            }
            .sheet(isPresented: Binding(
                get: { !selectedSchoolId.isEmpty },
                set: { if !$0 { selectedSchoolId = "" } }
            )) {
                ParentSchoolOverviewSheet(schoolId: selectedSchoolId, schoolName: selectedSchoolName)
            }
        }
    }

    private func loadSchools(forceRefresh: Bool) async {
        isLoadingSchools = true
        defer { isLoadingSchools = false }
        if session.family == nil || forceRefresh {
            await session.loadFamily(forceRefresh: forceRefresh)
        }
        await session.loadSchoolCatalog(forceRefresh: forceRefresh)
        var loadedSchools: [String: ParentSchoolDTO] = [:]
        let schoolIds = Set(session.enrollments.filter(\.isCurrent).map(\.schoolId)).sorted()
        for schoolId in schoolIds {
            if let school = await session.loadSchoolDetails(schoolId: schoolId, forceRefresh: forceRefresh) {
                loadedSchools[schoolId] = school
            }
        }
        schoolDetails = loadedSchools
    }

    private func officialGradeRange(_ grades: [String]) -> String? {
        MeroliGradePresentation.range(grades, zh: zh)
    }

    private func localizedGrade(_ grade: String) -> String {
        MeroliGradePresentation.label(grade, zh: zh)
    }
}

private struct FamilyScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var showsAddChild = false
    @State private var editingChild: ChildDTO?
    @State private var managingSchoolChild: ChildDTO?
    @State private var managingScheduleChild: ChildDTO?
    @State private var viewingSchoolInfo: EnrollmentDTO?
    @State private var childToRemove: ChildDTO?
    @State private var showsRemoveChildConfirmation = false
    @State private var showsSchoolYearUpdate = false
    @State private var scheduleProfiles: [String: ScheduleProfileDTO] = [:]
    private var zh: Bool { session.usesChinese }
    private var actionableTransitionCount: Int {
        SchoolYearTransitionPresentation.actionableChildCount(session.schoolYearTransitions)
    }

    private enum Palette {
        static let canvas = Color(red: 246 / 255.0, green: 243 / 255.0, blue: 234 / 255.0)
        static let surface = Color.white
        static let primary = Color(red: 31 / 255.0, green: 42 / 255.0, blue: 34 / 255.0)
        static let secondary = Color(red: 92 / 255.0, green: 102 / 255.0, blue: 96 / 255.0)
        static let tertiary = Color(red: 138 / 255.0, green: 146 / 255.0, blue: 140 / 255.0)
        static let border = Color(red: 229 / 255.0, green: 224 / 255.0, blue: 210 / 255.0)
        static let brand = Color(red: 30 / 255.0, green: 70 / 255.0, blue: 52 / 255.0)
        static let pale = Color(red: 238 / 255.0, green: 244 / 255.0, blue: 239 / 255.0)
        static let destructive = Color(red: 192 / 255.0, green: 57 / 255.0, blue: 43 / 255.0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let familyName = session.family?.name, !familyName.isEmpty {
                        Text(familyName)
                            .font(.caption)
                            .foregroundStyle(Palette.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let error = session.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if actionableTransitionCount > 0 {
                        Button { showsSchoolYearUpdate = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.forward.calendar")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.brand)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(zh ? "下一学年安排" : "Next school year")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Palette.primary)
                                    Text(zh
                                        ? "\(actionableTransitionCount) 个孩子待确认"
                                        : "\(actionableTransitionCount) \(actionableTransitionCount == 1 ? "child needs" : "children need") review")
                                        .font(.caption)
                                        .foregroundStyle(Palette.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .padding(14)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(zh ? "学年更新" : "School Year Update")
                        .accessibilityHint(zh ? "打开下一学年安排" : "Opens next school year updates")
                        .accessibilityIdentifier("meroli.family.schoolYearReminder")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(zh ? "家庭成员" : "Family members")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.primary)
                            Spacer()
                            Text("\(session.children.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.tertiary)
                                .accessibilityLabel(zh ? "\(session.children.count) 位孩子" : "\(session.children.count) children")
                        }
                        HStack {
                            Spacer()
                            Button { showsAddChild = true } label: {
                                Label(zh ? "添加孩子" : "Add child", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 44)
                                    .foregroundStyle(Palette.brand)
                                    .background(Palette.surface, in: Capsule())
                                    .overlay(Capsule().stroke(Palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("meroli.family.addChild")
                        }
                    }

                    if session.isLoadingFamily && session.children.isEmpty {
                        ProgressView(zh ? "正在读取家庭资料…" : "Loading family…")
                            .frame(maxWidth: .infinity, minHeight: 140)
                    } else if session.children.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(.title))
                                .foregroundStyle(Palette.brand)
                            Text(zh ? "添加家庭成员" : "Add a child to your family")
                                .font(.headline)
                                .foregroundStyle(Palette.primary)
                            Text(zh ? "创建孩子资料后，可以继续关联学校信息。" : "Create a child profile to start building your family's school information.")
                                .font(.subheadline)
                                .foregroundStyle(Palette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button { showsAddChild = true } label: {
                                Label(zh ? "添加孩子" : "Add child", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 15)
                                    .frame(minHeight: 44)
                                    .foregroundStyle(.white)
                                    .background(Palette.brand, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
                    } else {
                        VStack(spacing: 12) {
                            ForEach(session.children) { child in
                                let enrollment = displayedEnrollment(for: child)
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 11) {
                                        Circle()
                                            .fill(MeroliChildIdentity.color(for: child.id, in: session.children))
                                            .frame(width: 13, height: 13)
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(child.nickname)
                                                .font(.headline)
                                                .foregroundStyle(Palette.primary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Spacer()
                                        Button(zh ? "编辑称呼" : "Edit name") { editingChild = child }
                                            .font(.subheadline.weight(.semibold))
                                            .frame(minHeight: 44)
                                            .buttonStyle(.bordered)
                                            .tint(Palette.brand)
                                            .accessibilityIdentifier("meroli.child.\(child.id)")
                                    }

                                    Divider().overlay(Palette.border)

                                    if let enrollment {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Label(enrollment.schoolName, systemImage: "building.2")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Palette.primary)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text(enrollment.status == "AWAITING_NEXT_SCHOOL"
                                                ? (zh ? "等待选择下一所学校 · \(enrollment.schoolYearName) · \(localizedGrade(enrollment.gradeCode))" : "Choosing next school · \(enrollment.schoolYearName) · \(localizedGrade(enrollment.gradeCode))")
                                                : (zh ? "\(localizedGrade(enrollment.gradeCode)) · \(enrollment.schoolYearName)" : "\(localizedGrade(enrollment.gradeCode)) · \(enrollment.schoolYearName)"))
                                                .font(.caption)
                                                .foregroundStyle(Palette.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                            if let profile = scheduleProfiles[child.id] {
                                                Text(programSummary(profile))
                                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        Text(zh ? "尚未关联学校" : "No school linked yet")
                                            .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                    }

                                    HStack(spacing: 8) {
                                        Button { managingSchoolChild = child } label: {
                                            Label(zh ? "学校设置" : "School settings", systemImage: "pencil")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Palette.brand)
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                                .padding(.horizontal, 10)
                                                .background(Palette.pale, in: RoundedRectangle(cornerRadius: 11))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(enrollment?.status == "AWAITING_NEXT_SCHOOL")
                                        .accessibilityIdentifier("meroli.child.school.\(child.id)")

                                        if currentEnrollment(for: child) != nil {
                                            Button { managingScheduleChild = child } label: {
                                                Label(zh ? "作息与项目" : "Schedule & programs", systemImage: "clock")
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(Palette.brand)
                                                    .lineLimit(2)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                                    .padding(.horizontal, 10)
                                                    .background(Palette.pale, in: RoundedRectangle(cornerRadius: 11))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }

                                    if let enrollment {
                                        Button { viewingSchoolInfo = enrollment } label: {
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                Label(zh ? "学校考勤与表现资料" : "Attendance and school information", systemImage: "building.2.crop.circle")
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(Palette.brand)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                Spacer(minLength: 2)
                                                Image(systemName: "chevron.right")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(Palette.brand)
                                                    .accessibilityHidden(true)
                                            }
                                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("meroli.child.schoolInfo.\(child.id)")
                                    }

                                    let previousEnrollments = historicalEnrollments(for: child)
                                    if !previousEnrollments.isEmpty {
                                        DisclosureGroup(zh ? "历史学校" : "Previous schools") {
                                            ForEach(previousEnrollments) { previous in
                                                Text("\(previous.schoolName) · \(previous.schoolYearName) · \(localizedGrade(previous.gradeCode))")
                                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        .font(.caption.weight(.semibold))
                                        .tint(Palette.secondary)
                                    }

                                    Divider().overlay(Palette.border)

                                    Button(role: .destructive) {
                                        childToRemove = child
                                        showsRemoveChildConfirmation = true
                                    } label: {
                                        Label(zh ? "删除孩子" : "Remove Child", systemImage: "person.crop.circle.badge.minus")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(Palette.destructive)
                                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(session.deletingChildId != nil)
                                    .accessibilityLabel(zh ? "删除孩子：\(child.nickname)" : "Remove child: \(child.nickname)")
                                    .accessibilityHint(zh ? "将先显示确认信息" : "Shows a confirmation before removal")
                                    .accessibilityIdentifier("meroli.family.removeChild.\(child.id)")
                                }
                                .padding(16)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(.horizontal, 19)
                .padding(.top, 13)
                .padding(.bottom, 40)
            }
            .background(Palette.canvas)
            .navigationTitle(zh ? "管理孩子与学校" : "Manage Children & Schools")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await session.loadFamily(forceRefresh: true)
                await session.loadSchoolCatalog(forceRefresh: true)
                let districtIds = Set(session.enrollments.filter(\.isCurrent).map(\.districtId))
                for districtId in districtIds {
                    await session.loadSchools(districtId: districtId, forceRefresh: true)
                }
            }
            .task {
                if session.family == nil { await session.loadFamily() }
                await loadProgramProfiles()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await session.loadFamily(forceRefresh: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .tint(Palette.tertiary)
                    .accessibilityLabel(zh ? "刷新家庭" : "Refresh family")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    CloseSheetButton(zh: zh)
                        .frame(minWidth: 44, minHeight: 44)
                        .tint(Palette.brand)
                        .accessibilityIdentifier("meroli.family.done")
                }
            }
            .sheet(isPresented: $showsAddChild, onDismiss: {
                Task {
                    await session.loadFamily(forceRefresh: true)
                    await loadProgramProfiles()
                }
            }) { AddChildSheet() }
            .sheet(item: $editingChild) { child in RenameChildSheet(child: child) }
            .sheet(item: $managingSchoolChild, onDismiss: {
                Task {
                    await session.loadFamily(forceRefresh: true)
                    await loadProgramProfiles()
                }
            }) { child in
                EnrollmentEditorSheet(child: child, current: currentEnrollment(for: child))
            }
            .sheet(item: $managingScheduleChild, onDismiss: {
                Task { await loadProgramProfiles() }
            }) { child in
                if let enrollment = currentEnrollment(for: child) {
                    ScheduleProfileSheet(child: child, schoolId: enrollment.schoolId)
                }
            }
            .sheet(item: $viewingSchoolInfo) { enrollment in
                ParentSchoolOverviewSheet(schoolId: enrollment.schoolId, schoolName: enrollment.schoolName)
            }
            .sheet(isPresented: $showsSchoolYearUpdate) { SchoolYearUpdateScreen() }
            .confirmationDialog(
                childToRemove.map { zh ? "删除\($0.nickname)？" : "Remove \($0.nickname)?" }
                    ?? (zh ? "删除孩子？" : "Remove child?"),
                isPresented: $showsRemoveChildConfirmation,
                titleVisibility: .visible
            ) {
                Button(zh ? "删除孩子" : "Remove Child", role: .destructive) {
                    guard let child = childToRemove else { return }
                    Task {
                        if await session.deleteChild(id: child.id) {
                            await loadProgramProfiles()
                        }
                        childToRemove = nil
                    }
                }
                .disabled(session.deletingChildId != nil)

                Button(zh ? "取消" : "Cancel", role: .cancel) {
                    childToRemove = nil
                }
            } message: {
                Text(zh
                    ? "此孩子将从当前家庭中移除。请确认后继续。"
                    : "This child will be removed from this family. Confirm to continue.")
            }
        }
    }

    private func currentEnrollment(for child: ChildDTO) -> EnrollmentDTO? {
        session.enrollments.first { $0.childId == child.id && $0.isCurrent }
    }

    private func displayedEnrollment(for child: ChildDTO) -> EnrollmentDTO? {
        currentEnrollment(for: child)
            ?? session.enrollments.first { $0.childId == child.id && $0.status == "AWAITING_NEXT_SCHOOL" }
    }

    private func historicalEnrollments(for child: ChildDTO) -> [EnrollmentDTO] {
        session.enrollments
            .filter { $0.childId == child.id && $0.status == "COMPLETED" }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
    }

    private func loadProgramProfiles() async {
        scheduleProfiles = [:]
        for child in session.children {
            guard let enrollment = currentEnrollment(for: child) else { continue }
            await session.loadScheduleProfile(child: child, schoolId: enrollment.schoolId)
            if let profile = session.scheduleProfile, profile.childId == child.id {
                scheduleProfiles[child.id] = profile
            }
        }
    }

    private func programSummary(_ profile: ScheduleProfileDTO) -> String {
        let names = profile.programs
            .filter { profile.programIds.contains($0.id) }
            .map { zh && !$0.displayNameZh.isEmpty ? $0.displayNameZh : $0.displayNameEn }
        if !names.isEmpty { return (zh ? "已选项目：" : "Selected programs: ") + names.joined(separator: " · ") }
        switch profile.selectionStatus.uppercased() {
        case "NONE": return zh ? "未选择课后项目" : "No programs selected"
        case "NOT_SURE": return zh ? "课后项目待确认" : "Programs not confirmed"
        default: return zh ? "项目选择待确认" : "Program selection needs review"
        }
    }

    private func localizedGrade(_ grade: String) -> String {
        MeroliGradePresentation.label(grade, zh: zh)
    }
}

private struct SchoolYearUpdateScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var choosingNextSchool: SchoolYearTransitionDTO?
    @State private var actionError: String?
    private var zh: Bool { session.usesChinese }
    private var transitions: [SchoolYearTransitionDTO] { session.schoolYearTransitions }
    private var availableTransitionCount: Int {
        SchoolYearTransitionPresentation.actionableChildCount(transitions)
    }
    private var unavailableDatesDiffer: Bool {
        Set(transitions.filter { $0.transitionAvailable != true }
            .compactMap(\.transitionAvailableDate)).count > 1
    }
    private var hasUnavailableTransitions: Bool {
        transitions.contains { $0.transitionAvailable != true }
    }

    var body: some View {
        NavigationStack {
            schoolYearContent
            .navigationTitle(zh ? "学年更新" : "School Year Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(zh ? "完成" : "Done") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("meroli.schoolYearUpdate.done")
                }
            }
            .task {
                if session.family == nil { await session.loadFamily() }
            }
            .sheet(item: $choosingNextSchool) { transition in
                NextSchoolTransitionSheet(transition: transition)
            }
        }
    }

    @ViewBuilder
    private var schoolYearContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                schoolYearContentBody
            }
            .padding(18)
        }
        .background(MeroliColor.canvas)
    }

    @ViewBuilder
    private var schoolYearContentBody: some View {
        if session.isLoadingFamily && session.family == nil {
            ProgressView(zh ? "正在读取学年安排…" : "Loading school year updates…")
                .frame(maxWidth: .infinity, minHeight: 150)
        } else if transitions.isEmpty {
            emptySchoolYearState
        } else {
            if hasUnavailableTransitions {
                availabilityExplanation
            }
            if let actionError {
                Text(actionError)
                    .font(.subheadline)
                    .foregroundStyle(MeroliColor.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(transitions) { transition in
                transitionCard(transition)
            }
        }
    }

    private var emptySchoolYearState: some View {
        Text(zh ? "目前没有需要确认的下一学年安排。" : "There are no school year updates to review right now.")
            .font(.subheadline)
            .foregroundStyle(MeroliColor.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private var availabilityExplanation: some View {
        Text(zh
            ? "下一学年安排将在当前学年结束后开放确认。"
            : "Next school year updates will become available after the current school year ends.")
            .font(.subheadline)
            .foregroundStyle(MeroliColor.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func transitionCard(_ transition: SchoolYearTransitionDTO) -> some View {
        let isAvailable = transition.transitionAvailable == true
        let hasTargetYear = transition.targetSchoolYearId != nil
        return VStack(alignment: .leading, spacing: 10) {
            transitionHeader(transition)
            transitionSummary(transition)
            transitionActions(transition, isAvailable: isAvailable, hasTargetYear: hasTargetYear)
            programReconfirmationNotice(transition)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(MeroliColor.line, lineWidth: 1)
        }
    }

    private func transitionHeader(_ transition: SchoolYearTransitionDTO) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(MeroliChildIdentity.color(for: transition.childId, in: session.children))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(transition.childName)
                .font(.headline)
                .foregroundStyle(MeroliColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if shouldShowTransitionUnavailableLabel(transition) {
                Text(zh ? "尚未开放" : "Not open yet")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MeroliColor.muted)
            }
        }
    }

    private func shouldShowTransitionUnavailableLabel(_ transition: SchoolYearTransitionDTO) -> Bool {
        transition.transitionAvailable != true
            || (transition.targetSchoolYearId == nil && !transition.finishedK12Available)
    }

    @ViewBuilder
    private func transitionSummary(_ transition: SchoolYearTransitionDTO) -> some View {
        Text(transition.schoolName)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(MeroliColor.ink)
            .fixedSize(horizontal: false, vertical: true)
        Text(transitionCurrentYearText(transition))
            .font(.caption)
            .foregroundStyle(MeroliColor.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if let targetYearText = transitionTargetYearText(transition) {
            Text(targetYearText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MeroliColor.ink)
        }
        if let targetGradeText = transitionTargetGradeText(transition) {
            Text(targetGradeText)
                .font(.subheadline)
                .foregroundStyle(MeroliColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if unavailableDatesDiffer, let availableDate = transition.transitionAvailableDate {
            Text(transitionAvailabilityDateText(availableDate))
                .font(.caption)
                .foregroundStyle(MeroliColor.muted)
        }
    }

    private func transitionCurrentYearText(_ transition: SchoolYearTransitionDTO) -> String {
        "\(transition.schoolYearLabel) · \(localizedGrade(transition.gradeCode))"
    }

    private func transitionTargetYearText(_ transition: SchoolYearTransitionDTO) -> String? {
        guard let targetYear = transition.targetSchoolYearLabel, !targetYear.isEmpty else { return nil }
        return (zh ? "下一学年 · " : "Next school year · ") + targetYear
    }

    private func transitionTargetGradeText(_ transition: SchoolYearTransitionDTO) -> String? {
        if let suggestedGrade = transition.suggestedGradeCode {
            return (zh ? "建议年级 · " : "Suggested grade · ") + localizedGrade(suggestedGrade)
        }
        guard transition.targetSchoolYearId != nil else { return nil }
        return zh ? "下一学年需要选择学校和年级。" : "Choose a school and grade for next school year."
    }

    private func transitionAvailabilityDateText(_ date: String) -> String {
        (zh ? "可从 " : "Available after ") + date + (zh ? " 确认" : "")
    }

    @ViewBuilder
    private func transitionActions(
        _ transition: SchoolYearTransitionDTO,
        isAvailable: Bool,
        hasTargetYear: Bool
    ) -> some View {
        if isAvailable && hasTargetYear {
            availableTransitionActions(transition)
        } else if !transition.finishedK12Available || !isAvailable {
            unavailableTransitionAction
        }
        if isAvailable && transition.graduating {
            notSureAction(transition)
        }
        if isAvailable && transition.finishedK12Available {
            finishedK12Action(transition)
        }
    }

    @ViewBuilder
    private func availableTransitionActions(_ transition: SchoolYearTransitionDTO) -> some View {
        if transition.suggestedGrade != nil, let targetYearId = transition.targetSchoolYearId {
            Button {
                perform(transition, action: "confirm-grade", targetYearId: targetYearId, grade: transition.suggestedGrade)
            } label: {
                Label(confirmGradeButtonTitle(transition), systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(MeroliColor.ink)
            .disabled(session.isSavingSchoolYearTransition)
        }
        Button {
            choosingNextSchool = transition
        } label: {
            Label(nextSchoolButtonTitle(transition), systemImage: "building.2")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(MeroliColor.ink)
        .disabled(session.isSavingSchoolYearTransition)
    }

    private func confirmGradeButtonTitle(_ transition: SchoolYearTransitionDTO) -> String {
        guard zh else { return "Confirm next grade" }
        return "确认升至\(localizedGrade(transition.suggestedGradeCode ?? ""))"
    }

    private func nextSchoolButtonTitle(_ transition: SchoolYearTransitionDTO) -> String {
        if transition.suggestedGrade == nil {
            return zh ? "选择下一所学校" : "Choose next school"
        }
        return zh ? "选择其他学校" : "Choose another school"
    }

    private var unavailableTransitionAction: some View {
        Button(zh ? "学年更新尚未开放" : "School year update not yet available") {}
            .buttonStyle(.bordered)
            .disabled(true)
            .accessibilityHint(zh ? "可在当前学年结束后确认" : "Available after the current school year ends")
    }

    private func notSureAction(_ transition: SchoolYearTransitionDTO) -> some View {
        Button(zh ? "暂不确定" : "Not sure yet") {
            perform(transition, action: "not-sure")
        }
        .buttonStyle(.bordered)
        .tint(MeroliColor.secondary)
        .disabled(session.isSavingSchoolYearTransition)
    }

    private func finishedK12Action(_ transition: SchoolYearTransitionDTO) -> some View {
        Button(zh ? "已完成 K–12" : "Finished K–12") {
            perform(transition, action: "finished-k12")
        }
        .buttonStyle(.bordered)
        .tint(MeroliColor.secondary)
        .disabled(session.isSavingSchoolYearTransition)
    }

    @ViewBuilder
    private func programReconfirmationNotice(_ transition: SchoolYearTransitionDTO) -> some View {
        if transition.programReconfirmationRequired {
            Text(zh ? "更新后请重新确认作息与项目。" : "Review the schedule and programs after this update.")
                .font(.caption)
                .foregroundStyle(MeroliColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func perform(_ transition: SchoolYearTransitionDTO, action: String, targetYearId: String? = nil, grade: Int? = nil) {
        guard transition.transitionAvailable == true else { return }
        actionError = nil
        Task {
            if !(await session.applySchoolYearTransition(
                childId: transition.childId,
                action: action,
                targetYearId: targetYearId,
                grade: grade
            )) {
                actionError = session.errorMessage ?? (zh ? "学年更新未能保存，请稍后重试。" : "The school year update could not be saved. Try again.")
            }
        }
    }

    private func localizedGrade(_ grade: String) -> String {
        MeroliGradePresentation.label(grade, zh: zh)
    }
}

private struct NextSchoolTransitionSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let transition: SchoolYearTransitionDTO
    @State private var districtId = ""
    @State private var schoolId = ""
    @State private var gradeCode = ""
    @State private var selectionStatus = ""
    @State private var selectedProgramIds: Set<String> = []
    @State private var didLoad = false
    @State private var showsSchoolSearch = false
    private var zh: Bool { session.usesChinese }
    private var school: ParentSchoolDTO? { session.school(for: schoolId) }

    var body: some View {
        NavigationStack {
            Form {
                Section(zh ? "下一学年" : "Next school year") {
                    LabeledContent(zh ? "孩子" : "Child", value: transition.childName)
                    LabeledContent(zh ? "学年" : "School year", value: transition.targetSchoolYearLabel ?? "—")
                }
                Section(zh ? "学校" : "School") {
                    Picker(zh ? "学区" : "District", selection: $districtId) {
                        ForEach(session.districts) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: districtId) { _, value in
                        schoolId = ""
                        gradeCode = ""
                        selectedProgramIds = []
                        Task { await session.loadSchools(districtId: value) }
                    }
                    Button { showsSchoolSearch = true } label: {
                        HStack {
                            Text(zh ? "学校" : "School").foregroundStyle(MeroliColor.ink)
                            Spacer()
                            Text(school?.name ?? (zh ? "搜索并选择学校" : "Search and choose a school"))
                                .foregroundStyle(school == nil ? MeroliColor.muted : MeroliColor.ink)
                            Image(systemName: "magnifyingglass").foregroundStyle(MeroliColor.muted)
                        }
                    }
                    .disabled(districtId.isEmpty || session.isLoadingSchools)
                    if let school {
                        Picker(zh ? "年级" : "Grade", selection: $gradeCode) {
                            Text(zh ? "请选择年级" : "Choose a grade").tag("")
                            ForEach(school.availableGrades, id: \.self) { Text(localizedGrade($0)).tag($0) }
                        }
                    }
                }
                if !schoolId.isEmpty && !session.transitionPrograms.isEmpty {
                    Section(zh ? "重新确认项目" : "Confirm programs") {
                        Picker(zh ? "项目安排" : "Program selection", selection: $selectionStatus) {
                            Text(zh ? "选择项目" : "Select programs").tag("SELECTED")
                            Text(zh ? "没有项目" : "No programs").tag("NONE")
                            Text(zh ? "暂不确定" : "Not sure yet").tag("NOT_SURE")
                        }
                        .pickerStyle(.segmented)
                        if selectionStatus == "SELECTED" {
                            ForEach(session.transitionPrograms) { program in
                                Button {
                                    if selectedProgramIds.contains(program.id) {
                                        selectedProgramIds.remove(program.id)
                                    } else {
                                        selectedProgramIds.insert(program.id)
                                    }
                                } label: {
                                    HStack {
                                        Text(zh ? program.displayNameZh : program.displayNameEn)
                                            .foregroundStyle(MeroliColor.ink)
                                        Spacer()
                                        if selectedProgramIds.contains(program.id) {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(MeroliColor.ink)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selectedProgramIds.contains(program.id) ? .isSelected : [])
                            }
                        }
                    }
                }
                if let error = session.errorMessage {
                    Section { Text(error).font(.footnote).foregroundStyle(MeroliColor.coral) }
                }
                Section {
                    Button(zh ? "确认下一学年学校" : "Confirm next school") { save() }
                        .frame(maxWidth: .infinity)
                        .disabled(session.isSavingSchoolYearTransition || school == nil || gradeCode.isEmpty
                            || transition.targetSchoolYearId == nil || !session.hasLoadedTransitionPrograms
                            || !session.transitionPrograms.isEmpty && (selectionStatus.isEmpty
                                || selectionStatus == "SELECTED" && selectedProgramIds.isEmpty))
                }
            }
            .scrollContentBackground(.hidden)
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "选择下一所学校" : "Choose next school")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "关闭" : "Close") { dismiss() } } }
            .sheet(isPresented: $showsSchoolSearch, onDismiss: {
                guard !districtId.isEmpty else { return }
                Task { await session.loadSchools(districtId: districtId) }
            }) {
                SchoolSearchSheet(districtId: districtId, selectedSchoolId: schoolId) { selected in
                    schoolId = selected.id
                    gradeCode = ""
                    selectionStatus = ""
                    selectedProgramIds = []
                    Task {
                        if let programs = await session.loadTransitionPrograms(
                            schoolId: selected.id,
                            schoolYearId: transition.targetSchoolYearId
                        ) {
                            selectionStatus = programs.isEmpty ? "NONE" : ""
                        }
                    }
                }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        await session.loadSchoolCatalog()
        districtId = session.districts.first(where: { $0.id == transition.districtId })?.id ?? session.districts.first?.id ?? ""
        if !districtId.isEmpty { await session.loadSchools(districtId: districtId) }
    }

    private func save() {
        guard transition.transitionAvailable == true,
              !schoolId.isEmpty,
              let grade = numericGrade(gradeCode),
              let yearId = transition.targetSchoolYearId,
              session.hasLoadedTransitionPrograms,
              !selectionStatus.isEmpty,
              selectionStatus != "SELECTED" || !selectedProgramIds.isEmpty else { return }
        Task {
            let saved = await session.applySchoolYearTransition(childId: transition.childId,
                action: "next-school", targetYearId: yearId, extraPayload: [
                    "school_id": schoolId,
                    "grade": grade,
                    "selection_status": selectionStatus.isEmpty ? "NOT_SURE" : selectionStatus,
                    "program_ids": Array(selectedProgramIds)
                ])
            if saved { dismiss() }
        }
    }

    private func numericGrade(_ code: String) -> Int? {
        switch code {
        case "PK": return -2
        case "TK": return -1
        case "K": return 0
        default: return Int(code)
        }
    }

    private func localizedGrade(_ grade: String) -> String {
        MeroliGradePresentation.label(grade, zh: zh)
    }
}

private struct ScheduleProfileSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let child: ChildDTO
    let schoolId: String
    @State private var selectionStatus = "NOT_SURE"
    @State private var variantCode = "DEFAULT"
    @State private var programIds: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false
    private var zh: Bool { session.usesChinese }
    private var variantOptions: [ScheduleVariantOptionDTO] {
        let options: [ScheduleVariantOptionDTO]
        if let availableVariants = session.scheduleProfile?.availableVariants, !availableVariants.isEmpty {
            options = availableVariants
        } else {
            options = session.scheduleProfile?.availableVariantCodes.map {
                ScheduleVariantOptionDTO(variantCode: $0, variantName: nil)
            } ?? []
        }
        guard options.contains(where: { $0.variantCode == "DEFAULT" }) else {
            return [ScheduleVariantOptionDTO(variantCode: "DEFAULT", variantName: nil)] + options
        }
        return options
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(zh ? "设置 \(child.nickname) 的学校作息" : "Set \(child.nickname)’s school schedule")
                        .font(.system(.title2, design: .serif, weight: .bold)).foregroundStyle(MeroliColor.ink)
                    if isLoading {
                        ProgressView(zh ? "正在读取学校提供的选项…" : "Loading school options…")
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else if let profile = session.scheduleProfile {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(zh ? "课表变体" : "Schedule variant").font(.headline)
                            Picker(zh ? "课表变体" : "Schedule variant", selection: $variantCode) {
                                ForEach(variantOptions.indices, id: \.self) { index in
                                    let option = variantOptions[index]
                                    Text(variantDisplayName(option, index: index)).tag(option.variantCode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text(zh ? "课后项目" : "After-school programs").font(.headline)
                            if profile.programs.isEmpty {
                                Text(zh ? "学校目前没有需要选择的到校时间项目。" : "No arrival-time programs need a selection right now.")
                                    .font(.subheadline).foregroundStyle(MeroliColor.muted)
                            } else {
                                Picker(zh ? "项目选择" : "Program selection", selection: $selectionStatus) {
                                    Text(zh ? "需要选择" : "Select programs").tag("SELECTED")
                                    Text(zh ? "没有项目" : "No programs").tag("NONE")
                                    Text(zh ? "暂不确定" : "Not sure yet").tag("NOT_SURE")
                                }
                                .pickerStyle(.segmented)
                                ForEach(profile.programs) { program in
                                    Toggle(isOn: Binding(
                                        get: { programIds.contains(program.id) },
                                        set: { enabled in
                                            if enabled { programIds.insert(program.id) }
                                            else { programIds.remove(program.id) }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(zh && !program.displayNameZh.isEmpty ? program.displayNameZh : program.displayNameEn)
                                                .font(.subheadline.weight(.medium))
                                            if program.affectsArrivalTime, let period = program.periodCode {
                                                Text(zh ? "影响到校时间 · \(periodLabel(period))" : "Affects arrival · \(periodLabel(period))")
                                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                                            }
                                        }
                                    }
                                    .disabled(selectionStatus != "SELECTED")
                                }
                            }
                        }
                        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                        Text(zh ? "这些选择用于计算每日到校时间；不确定时可以保留默认选项。" : "These choices personalize daily arrival times. You can leave them as unsure.")
                            .font(.footnote).foregroundStyle(MeroliColor.muted)
                    } else if let error = session.errorMessage {
                        Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral)
                    }
                }
                .padding(20)
            }
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "作息偏好" : "Schedule preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(zh ? "取消" : "Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(zh ? "保存" : "Save") { save() }
                        .disabled(isLoading || isSaving || (selectionStatus == "SELECTED" && programIds.isEmpty))
                }
            }
            .task {
                await session.loadScheduleProfile(child: child, schoolId: schoolId)
                if let profile = session.scheduleProfile, profile.childId == child.id, profile.schoolId == schoolId {
                    selectionStatus = profile.programs.isEmpty ? "NONE" : profile.selectionStatus
                    variantCode = profile.scheduleVariantCode
                    programIds = profile.programs.isEmpty ? [] : Set(profile.programIds)
                }
                isLoading = false
            }
        }
    }

    private func variantDisplayName(_ option: ScheduleVariantOptionDTO, index: Int) -> String {
        if option.variantCode == "DEFAULT" { return zh ? "自动匹配学校作息" : "Automatically match school schedule" }
        if let name = option.variantName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return zh ? "作息方案 \(index)" : "Schedule option \(index)"
    }

    private func periodLabel(_ code: String) -> String {
        let normalized = code.uppercased()
        if normalized.first == "P", let number = Int(normalized.dropFirst()) {
            return zh ? "第\(number)节" : "Period \(number)"
        }
        return zh ? "相关课时" : "Related period"
    }

    private func save() {
        isSaving = true
        Task {
            let saved = await session.saveScheduleProfile(child: child, selectionStatus: selectionStatus,
                variantCode: variantCode, programIds: Array(programIds))
            isSaving = false
            if saved { dismiss() }
        }
    }
}

private struct ParentSchoolOverviewSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showsFullBellSchedule = false
    @State private var showsFullPerformance = false
    @State private var editingScheduleChild: ChildDTO?
    @State private var selectedProgramProfiles: [String: ScheduleProfileDTO] = [:]
    let schoolId: String
    let schoolName: String
    private var zh: Bool { session.usesChinese }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(session.schoolOverview?.schoolName ?? schoolName)
                        .font(.system(.title2, design: .serif, weight: .bold)).foregroundStyle(MeroliColor.ink)
                    if session.isLoadingSchoolOverview {
                        ProgressView(zh ? "正在读取学校资料…" : "Loading school information…")
                            .frame(maxWidth: .infinity, minHeight: 140)
                    } else if let overview = session.schoolOverview {
                        let applicableChildren = overview.children ?? []
                        VStack(alignment: .leading, spacing: 10) {
                            Text(zh ? "学校资料" : "School information")
                                .font(.headline).foregroundStyle(MeroliColor.ink)
                            if let minimum = overview.minGrade, let maximum = overview.maxGrade {
                                Text(gradeRange(minimum: minimum, maximum: maximum))
                                    .font(.subheadline).foregroundStyle(MeroliColor.muted)
                            }
                            let addressParts = [overview.address, overview.city, overview.state, overview.postalCode]
                                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            if !addressParts.isEmpty {
                                Label(addressParts.joined(separator: ", "), systemImage: "mappin.and.ellipse")
                                    .font(.subheadline).foregroundStyle(MeroliColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let phone = overview.phone, !phone.isEmpty {
                                let phoneNumber = String(phone.filter { $0.isNumber || $0 == "+" })
                                if let url = URL(string: "tel:\(phoneNumber)") {
                                    Link(destination: url) { Label(phone, systemImage: "phone") }
                                        .font(.subheadline)
                                }
                            }
                            if let url = externalWebURL(overview.websiteUrl) {
                                Link(destination: url) {
                                    Label(zh ? "学校官方网站" : "School website", systemImage: "arrow.up.right.square")
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                        .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        VStack(alignment: .leading, spacing: 10) {
                            Text(zh ? "今日适用的作息" : "Today's applicable schedule")
                                .font(.headline).foregroundStyle(MeroliColor.ink)
                            if applicableChildren.isEmpty {
                                Text(zh
                                    ? "当前家庭没有在读孩子关联到此学校。"
                                    : "No current child in your family is enrolled at this school.")
                                    .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(applicableChildren) { child in
                                    let schedule = overview.dailySchedules?.first(where: { $0.childId == child.childId })
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 8) {
                                            Circle().fill(MeroliChildIdentity.color(for: child.childId, in: session.children))
                                                .frame(width: 9, height: 9).accessibilityHidden(true)
                                            Text(child.childName).font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                            Spacer(minLength: 4)
                                        }
                                        Text(gradeLabel(child.gradeCode))
                                            .font(.caption).foregroundStyle(MeroliColor.muted)
                                        if let schedule {
                                            Text(scheduleSummary(schedule))
                                                .font(.subheadline.weight(.medium)).foregroundStyle(MeroliColor.ink)
                                            if schedule.status == "OK",
                                               let typeLabel = applicableScheduleTypeLabel(schedule.scheduleType),
                                               !["REGULAR", "REGULAR_DAY"].contains((schedule.scheduleType ?? "").uppercased()) {
                                                Text(typeLabel).font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.muted)
                                            }
                                            let appliedNames = applicableProgramNames(for: schedule)
                                            if !appliedNames.isEmpty {
                                                Text(appliedNames.joined(separator: " · "))
                                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                                            }
                                        } else {
                                            Text(zh ? "适用作息暂不可用。" : "Applicable schedule details are not available.")
                                                .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    if child.id != applicableChildren.last?.id {
                                        Divider().overlay(MeroliColor.line)
                                    }
                                }
                            }
                        }
                        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        let bellSchedules = overview.bellSchedules ?? []
                            if let children = overview.children, !children.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(zh ? "已选项目与课程" : "Selected programs & courses")
                                        .font(.headline).foregroundStyle(MeroliColor.ink)
                                    ForEach(children) { child in
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack(spacing: 8) {
                                                Circle().fill(MeroliChildIdentity.color(for: child.childId, in: session.children))
                                                    .frame(width: 9, height: 9).accessibilityHidden(true)
                                                Text(child.childName).font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                            }
                                            if let profile = selectedProgramProfiles[child.childId] {
                                                Text(selectedProgramsSummary(profile))
                                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                                            }
                                            if let familyChild = session.children.first(where: { $0.id == child.childId }),
                                               session.enrollments.contains(where: { $0.childId == child.childId && $0.schoolId == schoolId && $0.isCurrent }) {
                                                Button {
                                                    editingScheduleChild = familyChild
                                                } label: {
                                                    Label(zh ? "编辑作息与项目" : "Edit schedule & programs", systemImage: "slider.horizontal.3")
                                                        .font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        if child.id != children.last?.id { Divider().overlay(MeroliColor.line) }
                                    }
                                }
                                .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white, in: RoundedRectangle(cornerRadius: 17))
                            }
                            if !bellSchedules.isEmpty {
                                Button { showsFullBellSchedule = true } label: {
                                    HStack {
                                        Label(zh ? "查看完整作息表" : "View full bell schedule", systemImage: "list.bullet.rectangle")
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MeroliColor.ink)
                                    .padding(16)
                                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 15))
                                }
                                .buttonStyle(.plain)
                                .sheet(isPresented: $showsFullBellSchedule) {
                                    ParentFullBellScheduleSheet(schoolName: overview.schoolName, schedules: bellSchedules)
                                }
                            }
                        if let attendance = overview.attendance {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(zh ? "考勤与请假" : "Attendance and absence reporting").font(.headline).foregroundStyle(MeroliColor.ink)
                                Text(attendanceMethodLabel(attendance.attendanceMethod))
                                    .font(.subheadline.weight(.semibold))
                                Text(zh ? "Meroli 不会替你向学校提交请假。请以学校官方流程为准。" : "Meroli does not submit absences for you. Follow the school's official process.")
                                    .font(.footnote).foregroundStyle(MeroliColor.muted)
                                if !attendance.absenceInstruction.isEmpty {
                                    infoParagraph(title: zh ? "缺课" : "Absence", text: attendance.absenceInstruction)
                                }
                                if !attendance.lateArrivalInstruction.isEmpty {
                                    infoParagraph(title: zh ? "迟到" : "Late arrival", text: attendance.lateArrivalInstruction)
                                }
                                if !attendance.earlyPickupInstruction.isEmpty {
                                    infoParagraph(title: zh ? "提前接送" : "Early pickup", text: attendance.earlyPickupInstruction)
                                }
                                if let phone = attendance.attendancePhone, !phone.isEmpty {
                                    let phoneNumber = String(phone.filter { $0.isNumber || $0 == "+" })
                                    if let url = URL(string: "tel:\(phoneNumber)") {
                                        Link(destination: url) { Label(phone, systemImage: "phone") }
                                            .font(.subheadline)
                                    }
                                }
                                if let email = attendance.attendanceEmail, !email.isEmpty {
                                    if let url = URL(string: "mailto:\(email)") {
                                        Link(destination: url) { Label(email, systemImage: "envelope") }
                                            .font(.subheadline)
                                    }
                                }
                                if let url = externalWebURL(attendance.attendanceUrl) {
                                    Link(destination: url) { Label(zh ? "打开学校请假页面" : "Open school attendance page", systemImage: "arrow.up.right.square") }
                                        .font(.subheadline.weight(.semibold))
                                }
                                Text((zh ? "最后核实：" : "Last verified: ") + String(attendance.lastVerifiedAt.prefix(10)))
                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                            }
                            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        }
                        if let performance = overview.performance {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(zh ? "学校表现" : "School performance").font(.headline).foregroundStyle(MeroliColor.ink)
                                    Spacer()
                                    Text(performance.academicYear).font(.caption).foregroundStyle(MeroliColor.muted)
                                }
                                Text(zh ? "当前官方数据" : "Current official data")
                                    .font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.muted)
                                Text("\(performance.sourceName) · \(performance.reportingCycle)")
                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                                let summaryCodes = ["ELA", "MATH", "CHRONIC_ABSENTEEISM"]
                                let summaryMetrics = summaryCodes.compactMap { code in
                                    performance.metrics.first { $0.applicable && $0.metricCode == code }
                                }
                                if summaryMetrics.isEmpty {
                                    Text(zh ? "本报告周期未提供优先展示的指标。" : "Priority measures are not included in this reporting cycle.")
                                        .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                }
                                ForEach(summaryMetrics) { metric in
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(metric.presentation?.parentLabel ?? performanceMetricLabel(metric.metricCode))
                                                .font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                            Text(metricSummaryValue(metric))
                                                .font(.caption).foregroundStyle(MeroliColor.muted)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer(minLength: 6)
                                        if metric.officialStatus.uppercased() == "REPORTED",
                                           let level = metric.presentation?.performanceLevelLabel ?? performanceLevelLabel(metric.officialPerformanceLevel) {
                                            if let colorName = performanceColorLabel(metric.officialColor),
                                               performanceColor(metric.officialColor) != nil {
                                                Text("\(colorName) · \(level)")
                                                    .font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                            } else {
                                                Text(level).font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                            }
                                        }
                                    }
                                    .accessibilityElement(children: .combine)
                                    Divider().overlay(MeroliColor.line)
                                }
                                Button {
                                    showsFullPerformance = true
                                } label: {
                                    Label(zh ? "查看完整表现数据" : "Full Performance details", systemImage: "chart.bar.doc.horizontal")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 17))
                            .sheet(isPresented: $showsFullPerformance) {
                                SchoolPerformanceDetailsSheet(schoolId: schoolId, schoolName: overview.schoolName, performance: performance)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(zh ? "学校表现" : "School performance")
                                    .font(.headline).foregroundStyle(MeroliColor.ink)
                                Text(zh ? "官方学校表现数据暂不可用。" : "Official school performance data is not available.")
                                    .font(.subheadline).foregroundStyle(MeroliColor.muted)
                            }
                            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        }
                        if overview.attendance == nil && overview.performance == nil {
                            Text(zh ? "学校尚未发布考勤或表现资料。" : "The school has not published attendance or performance information yet.")
                                .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                    } else if let error = session.schoolOverviewErrorMessage ?? session.errorMessage {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(zh ? "学校资料暂时无法加载" : "School information could not be loaded")
                                .font(.headline).foregroundStyle(MeroliColor.ink)
                            Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral)
                            Button {
                                Task {
                                    await session.loadSchoolOverview(schoolId: schoolId)
                                    await session.loadSchoolPerformanceHistory(schoolId: schoolId)
                                }
                            } label: {
                                Label(zh ? "重试" : "Retry", systemImage: "arrow.clockwise")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .disabled(session.isLoadingSchoolOverview || session.isLoadingSchoolPerformanceHistory)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(17)
                        .background(.white, in: RoundedRectangle(cornerRadius: 17))
                    }
                }
                .padding(20)
            }
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "学校资料" : "School information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "完成" : "Done") { dismiss() } } }
            .task {
                await session.loadSchoolOverview(schoolId: schoolId)
                await session.loadSchoolPerformanceHistory(schoolId: schoolId)
                await loadProgramProfiles()
            }
            .sheet(item: $editingScheduleChild, onDismiss: {
                Task { await loadProgramProfiles() }
            }) { child in
                ScheduleProfileSheet(child: child, schoolId: schoolId)
            }
        }
    }

    private func loadProgramProfiles() async {
        guard let children = session.schoolOverview?.children else { return }
        var profiles: [String: ScheduleProfileDTO] = [:]
        for schoolChild in children {
            guard let child = session.children.first(where: { $0.id == schoolChild.childId }) else { continue }
            await session.loadScheduleProfile(child: child, schoolId: schoolId)
            if let profile = session.scheduleProfile,
               profile.childId == schoolChild.childId,
               profile.schoolId == schoolId {
                profiles[schoolChild.childId] = profile
            }
        }
        selectedProgramProfiles = profiles
    }

    private func selectedProgramsSummary(_ profile: ScheduleProfileDTO) -> String {
        let programNames = profile.programs
            .filter { profile.programIds.contains($0.id) }
            .map { zh && !$0.displayNameZh.isEmpty ? $0.displayNameZh : $0.displayNameEn }
        if !programNames.isEmpty { return (zh ? "已选项目：" : "Selected programs: ") + programNames.joined(separator: " · ") }
        switch profile.selectionStatus.uppercased() {
        case "NONE": return zh ? "未选择课后项目" : "No programs selected"
        case "NOT_SURE": return zh ? "课后项目待确认" : "Programs not confirmed"
        default: return zh ? "项目选择待确认" : "Program selection needs review"
        }
    }

    private func applicableProgramNames(for schedule: DailyScheduleDTO) -> [String] {
        guard let profile = selectedProgramProfiles[schedule.childId] else { return [] }
        let appliedCodes = Set(schedule.appliedPrograms.map { $0.uppercased() })
        return profile.programs
            .filter { appliedCodes.contains($0.code.uppercased()) }
            .map { zh && !$0.displayNameZh.isEmpty ? $0.displayNameZh : $0.displayNameEn }
    }

    private func applicableScheduleTypeLabel(_ scheduleType: String?) -> String? {
        guard let scheduleType else { return nil }
        switch scheduleType.uppercased() {
        case "REGULAR", "REGULAR_DAY": return zh ? "正常作息" : "Regular day"
        case "EARLY_RELEASE": return zh ? "提前放学" : "Early release"
        case "MINIMUM_DAY": return zh ? "短日作息" : "Minimum day"
        case "LATE_START": return zh ? "延迟到校" : "Late start"
        case "NO_LATE_START": return zh ? "不延迟到校" : "No late start"
        case "NO_SCHOOL", "PUPIL_FREE_DAY", "BREAK", "HOLIDAY": return zh ? "学校不上课" : "No school"
        case "WEEKEND", "OUTSIDE_SCHOOL_YEAR": return zh ? "非上课日" : "Non-instructional day"
        case "WEDNESDAY": return zh ? "周三作息" : "Wednesday schedule"
        case "SPECIAL": return zh ? "特别作息" : "Special schedule"
        default: return nil
        }
    }

    private func infoParagraph(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.muted)
            Text(text).font(.subheadline).foregroundStyle(MeroliColor.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func attendanceMethodLabel(_ method: String) -> String {
        switch method.uppercased() {
        case "ONLINE": return zh ? "通过学校网站提交" : "Report through the school website"
        case "PHONE": return zh ? "致电学校考勤办公室" : "Call the school attendance office"
        case "EMAIL": return zh ? "通过电子邮件联系学校" : "Email the school"
        case "ONLINE_OR_PHONE": return zh ? "通过学校网站或电话申报" : "Report online or by phone"
        case "CONTACT_SCHOOL": return zh ? "请联系学校确认办理方式" : "Contact the school for instructions"
        default: return zh ? "请按学校官方说明办理" : "Follow the school's official instructions"
        }
    }

    private func gradeRange(minimum: Int, maximum: Int) -> String {
        MeroliGradePresentation.range(minimum: minimum, maximum: maximum, zh: zh)
    }

    private func gradeLabel(_ grade: String) -> String {
        MeroliGradePresentation.label(grade, zh: zh)
    }

    private func performanceLegend() -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(zh ? "California School Dashboard 官方等级" : "California School Dashboard official levels")
                .font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.ink)
            HStack(spacing: 9) {
                ForEach(["BLUE", "GREEN", "YELLOW", "ORANGE", "RED"], id: \.self) { code in
                    if let color = performanceColor(code), let label = performanceColorLabel(code) {
                        HStack(spacing: 3) {
                            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
                            Text(label).font(.caption2).foregroundStyle(MeroliColor.muted)
                        }
                    }
                }
            }
            Text(zh
                 ? "官方等级综合当前表现与较上一年的变化，不是 Meroli 对学校的评分或排名。"
                 : "Official levels combine current performance and change from the prior year. They are not a Meroli rating or ranking.")
                .font(.caption2).foregroundStyle(MeroliColor.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    private func performanceChangeLabel(_ meaning: String) -> String {
        switch meaning.uppercased() {
        case "IMPROVING": return zh ? "改善" : "Improvement"
        case "DECLINING": return zh ? "下降" : "Decline"
        case "STABLE": return zh ? "变化不大" : "Little change"
        default: return zh ? "官方变化" : "Official change"
        }
    }

    private func performanceStatusLabel(_ status: String) -> String {
        switch status.uppercased() {
        case "REPORTED": return zh ? "已报告" : "Reported"
        case "SUPPRESSED": return zh ? "数据受限" : "Suppressed"
        case "NOT_REPORTED": return zh ? "尚未报告" : "Not reported"
        case "NOT_APPLICABLE": return zh ? "不适用" : "Not applicable"
        case "NOT_AVAILABLE_FOR_CYCLE": return zh ? "本报告周期无此指标" : "Not available this year"
        case "UNAVAILABLE", "NOT_AVAILABLE": return zh ? "官方数据暂不可用" : "Official data unavailable"
        case "LEGACY": return zh ? "旧版数据" : "Legacy data"
        default: return zh ? "官方数据状态" : "Official data status"
        }
    }

    private func performanceMetricLabel(_ code: String) -> String {
        switch code.uppercased() {
        case "ELA": return zh ? "英语语言艺术与读写" : "English Language Arts and Literacy"
        case "MATH": return zh ? "数学" : "Mathematics"
        case "SCIENCE": return zh ? "科学" : "Science"
        case "CHRONIC_ABSENTEEISM": return zh ? "长期缺勤" : "Chronic Absenteeism"
        case "SUSPENSION", "SUSPENSION_RATE": return zh ? "停学率" : "Suspension Rate"
        case "EL_PROGRESS": return zh ? "英语学习者进展" : "English Learner Progress"
        case "GRADUATION", "GRADUATION_RATE": return zh ? "毕业率" : "Graduation Rate"
        case "COLLEGE_CAREER": return zh ? "大学与职业准备" : "College and Career Readiness"
        default: return zh ? "官方表现指标" : "Official performance metric"
        }
    }

    private func performanceTrendLabel(_ state: String) -> String {
        switch state.uppercased() {
        case "IMPROVING": return zh ? "改善" : "Improving"
        case "DECLINING": return zh ? "下降" : "Declining"
        case "STABLE": return zh ? "保持稳定" : "Stable"
        case "METHODOLOGY_PENDING": return zh ? "等待核实官方口径" : "Official methodology pending"
        case "METHODOLOGY_CHANGED": return zh ? "官方方法已变化" : "Official methodology changed"
        case "INSUFFICIENT_DATA": return zh ? "可比较数据不足" : "Insufficient comparable data"
        default: return zh ? "官方历史趋势" : "Official historical trend"
        }
    }

    private func performanceLevelLabel(_ level: String?) -> String? {
        guard let level else { return nil }
        switch level.uppercased() {
        case "VERY_HIGH": return zh ? "很高" : "Very high"
        case "HIGH": return zh ? "高" : "High"
        case "MEDIUM": return zh ? "中等" : "Medium"
        case "LOW": return zh ? "低" : "Low"
        case "VERY_LOW": return zh ? "很低" : "Very low"
        case "NOT_AVAILABLE": return zh ? "暂无数据" : "Not available"
        default: return nil
        }
    }

    private func performanceColorLabel(_ color: String?) -> String? {
        guard let color else { return nil }
        switch color.uppercased() {
        case "BLUE": return zh ? "蓝色" : "Blue"
        case "GREEN": return zh ? "绿色" : "Green"
        case "YELLOW": return zh ? "黄色" : "Yellow"
        case "ORANGE": return zh ? "橙色" : "Orange"
        case "RED": return zh ? "红色" : "Red"
        default: return nil
        }
    }

    private func performanceColor(_ color: String?) -> Color? {
        guard let color else { return nil }
        switch color.uppercased() {
        case "BLUE": return Color(red: 0.00, green: 0.38, blue: 0.68)
        case "GREEN": return Color(red: 0.28, green: 0.52, blue: 0.25)
        case "YELLOW": return Color(red: 0.88, green: 0.69, blue: 0.05)
        case "ORANGE": return Color(red: 0.88, green: 0.38, blue: 0.10)
        case "RED": return Color(red: 0.75, green: 0.14, blue: 0.13)
        default: return nil
        }
    }

    private func displayableOfficialValue(_ metric: ParentPerformanceMetricDTO) -> String {
        let status = metric.officialStatus.uppercased()
        guard status == "REPORTED" || status == "LEGACY" else { return "—" }
        return metric.officialValue ?? "—"
    }

    private func metricSummaryValue(_ metric: ParentPerformanceMetricDTO) -> String {
        let status = metric.officialStatus.uppercased()
        if status == "REPORTED" {
            return metric.presentation?.displayValue ?? metric.officialValue ?? performanceStatusLabel(status)
        }
        if status == "LEGACY", let value = metric.officialValue, !value.isEmpty {
            return performanceLevelLabel(value) ?? (value.uppercased() == "NOT_AVAILABLE"
                ? (zh ? "暂无数据" : "Not available") : value)
        }
        return performanceStatusLabel(status)
    }

    private func performancePointValue(_ point: ParentPerformancePointDTO) -> String {
        switch point.officialStatus.uppercased() {
        case "REPORTED": return point.presentation?.shortValue ?? point.officialValue ?? performanceStatusLabel(point.officialStatus)
        case "LEGACY":
            if let value = point.officialValue { return performanceLevelLabel(value) ?? value }
            return performanceStatusLabel(point.officialStatus)
        default: return performanceStatusLabel(point.officialStatus)
        }
    }

    private func scheduleSummary(_ schedule: DailyScheduleDTO) -> String {
        switch schedule.status {
        case "OK":
            let arrivalLabel = arrivalTimeLabel(schedule)
            return zh
                ? "\(arrivalLabel) \(schedule.arrivalTime ?? "待确认") · 放学 \(schedule.dismissalTime ?? "待确认")"
                : "\(arrivalLabel) \(schedule.arrivalTime ?? "To be confirmed") · Dismissal \(schedule.dismissalTime ?? "To be confirmed")"
        case "NO_SCHOOL":
            return zh ? "不上课" : "No school"
        case "NON_INSTRUCTIONAL_DAY":
            return zh ? "非上课日" : "Non-instructional day"
        case "NO_ENROLLMENT":
            return zh ? "尚未设置在读学校" : "No current school enrollment"
        default:
            return zh ? "学校时间待确认" : "School schedule unavailable"
        }
    }

    private func arrivalTimeLabel(_ schedule: DailyScheduleDTO) -> String {
        switch schedule.arrivalLabel ?? (schedule.firstPeriodCode == "P0" ? "PERIOD_0_START" : "SCHOOL_START") {
        case "PERIOD_0_START": return zh ? "第0节开始" : "Period 0 starts"
        default: return zh ? "到校" : "Arrival"
        }
    }
}

private struct SchoolPerformanceDetailsSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let schoolId: String
    let schoolName: String
    let performance: ParentPerformanceDTO
    private var zh: Bool { session.usesChinese }
    private var metrics: [ParentPerformanceMetricDTO] { performance.metrics.filter(\.applicable) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(schoolName).font(.system(.title2, design: .serif, weight: .bold)).foregroundStyle(MeroliColor.ink)
                        Text(zh ? "当前官方数据 · \(performance.academicYear)" : "Current official data · \(performance.academicYear)")
                            .font(.subheadline).foregroundStyle(MeroliColor.muted)
                        Text("\(performance.sourceName) · \(performance.reportingCycle)")
                            .font(.caption).foregroundStyle(MeroliColor.muted)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(zh ? "当前" : "Current")
                            .font(.headline).foregroundStyle(MeroliColor.ink)
                        if metrics.isEmpty {
                            Text(zh ? "此报告周期没有适用于本校的指标数据。" : "No applicable indicator data is available for this reporting cycle.")
                                .font(.subheadline).foregroundStyle(MeroliColor.muted)
                        }
                        ForEach(metrics) { metric in
                            metricRow(metric)
                            if metric.id != metrics.last?.id { Divider().overlay(MeroliColor.line) }
                        }
                    }
                    .padding(17)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 17))

                    performanceHistorySection

                    VStack(alignment: .leading, spacing: 8) {
                        Text(zh ? "关于这些数据" : "About these results")
                            .font(.headline).foregroundStyle(MeroliColor.ink)
                        if metrics.contains(where: { $0.officialStatus.uppercased() == "REPORTED" && $0.officialColor != nil }) {
                            performanceLegend()
                        }
                        Text(performance.disclaimer).font(.caption).foregroundStyle(MeroliColor.muted)
                        if !performance.publishedAt.isEmpty {
                            Text((zh ? "报告发布：" : "Published: ") + String(performance.publishedAt.prefix(10)))
                                .font(.caption).foregroundStyle(MeroliColor.muted)
                        }
                        if let updated = performance.lastUpdatedAt, !updated.isEmpty {
                            Text((zh ? "数据更新：" : "Data updated: ") + String(updated.prefix(10)))
                                .font(.caption).foregroundStyle(MeroliColor.muted)
                        }
                        if let url = externalWebURL(performance.sourceUrl) {
                            Link(destination: url) {
                                Label(zh ? "查看官方来源" : "View official source", systemImage: "arrow.up.right.square")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .padding(17)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 17))
                }
                .padding(18)
            }
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "学校表现" : "School performance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(zh ? "完成" : "Done") { dismiss() }
                }
            }
        }
    }

    private func metricRow(_ metric: ParentPerformanceMetricDTO) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                Text(metric.presentation?.parentLabel ?? performanceMetricLabel(metric.metricCode))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                Spacer(minLength: 4)
                if metric.officialStatus.uppercased() == "REPORTED",
                   let level = metric.presentation?.performanceLevelLabel ?? performanceLevelLabel(metric.officialPerformanceLevel) {
                    if let color = performanceColor(metric.officialColor), let colorName = performanceColorLabel(metric.officialColor) {
                        HStack(spacing: 5) {
                            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
                            Text("\(colorName) · \(level)").font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                        }
                    } else {
                        Text(level).font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                    }
                }
            }
            let status = metric.officialStatus.uppercased()
            if status == "REPORTED" || status == "LEGACY" {
                Text(metricDisplayValue(metric))
                    .font(.subheadline.weight(.medium)).foregroundStyle(MeroliColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(performanceStatusLabel(metric.officialStatus))
                    .font(.caption).foregroundStyle(MeroliColor.muted)
            } else {
                Text(performanceStatusLabel(metric.officialStatus))
                    .font(.subheadline.weight(.medium)).foregroundStyle(MeroliColor.muted)
            }
            if let presentation = metric.presentation {
                if (presentation.parentDefinition?.isEmpty == false)
                    || (presentation.directionExplanation?.isEmpty == false)
                    || (presentation.displayChange?.isEmpty == false)
                    || !presentation.comparisonValues.isEmpty
                    || (presentation.comparisonSummary?.isEmpty == false) {
                    DisclosureGroup(zh ? "指标说明与比较" : "Measure details and comparisons") {
                        VStack(alignment: .leading, spacing: 7) {
                            if let definition = presentation.parentDefinition, !definition.isEmpty {
                                Text(definition).font(.caption).foregroundStyle(MeroliColor.muted)
                            }
                            if metric.officialStatus.uppercased() == "REPORTED",
                               let change = presentation.displayChange, !change.isEmpty {
                                Text((zh ? "官方变化：" : "Official change: ") + change
                                    + (presentation.changeMeaning.map { " · \(performanceChangeLabel($0))" } ?? ""))
                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                            }
                            ForEach(presentation.comparisonValues) { value in
                                HStack {
                                    Text(value.label).foregroundStyle(MeroliColor.muted)
                                    Spacer()
                                    Text(value.value ?? "—").foregroundStyle(MeroliColor.ink)
                                }
                                .font(.caption)
                            }
                            if let summary = presentation.comparisonSummary, !summary.isEmpty {
                                Text(summary).font(.caption2).foregroundStyle(MeroliColor.muted)
                            }
                            if let direction = presentation.directionExplanation, !direction.isEmpty {
                                Text(direction).font(.caption2).foregroundStyle(MeroliColor.muted)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .font(.caption)
                    .tint(MeroliColor.ink)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var performanceHistorySection: some View {
        if session.isLoadingSchoolPerformanceHistory {
            HStack(spacing: 12) {
                ProgressView()
                Text(zh ? "正在加载历史数据…" : "Loading history…")
                    .font(.subheadline).foregroundStyle(MeroliColor.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(17)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
        } else if let error = session.schoolPerformanceHistoryErrorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Text(zh ? "历史数据暂时无法加载" : "History could not be loaded")
                    .font(.headline).foregroundStyle(MeroliColor.ink)
                Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral)
                Button {
                    Task { await session.loadSchoolPerformanceHistory(schoolId: schoolId) }
                } label: {
                    Label(zh ? "重试" : "Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(session.isLoadingSchoolPerformanceHistory)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(17)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
        } else if let history = session.schoolPerformanceHistory {
            VStack(alignment: .leading, spacing: 10) {
                DisclosureGroup {
                    historyDetails(history)
                        .padding(.top, 8)
                } label: {
                    HStack {
                        Text(zh ? "历史数据" : "History")
                            .font(.headline).foregroundStyle(MeroliColor.ink)
                        Spacer(minLength: 8)
                        Text(zh ? "\(history.cycles.count) 个报告周期" : "\(history.cycles.count) reporting cycles")
                            .font(.caption).foregroundStyle(MeroliColor.muted)
                    }
                }
                .tint(MeroliColor.ink)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(zh ? "历史数据" : "History")
                    .font(.headline).foregroundStyle(MeroliColor.ink)
                Text(zh ? "暂无可用的历史数据。" : "Historical data is not available.")
                    .font(.subheadline).foregroundStyle(MeroliColor.muted)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
        }
    }

    @ViewBuilder
    private func historyDetails(_ history: ParentPerformanceHistoryDTO) -> some View {
        let previousCycles = Array(history.cycles.dropFirst())
        if previousCycles.isEmpty && history.metrics.isEmpty {
            Text(zh ? "目前只有当前报告周期的数据，尚无更多年度记录。" : "Only the current reporting cycle is available; there are no earlier records yet.")
                .font(.subheadline).foregroundStyle(MeroliColor.muted)
        }
        ForEach(previousCycles, id: \.reportingCycle) { cycle in
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(cycle.metrics) { metric in
                        historyMetricRow(metric)
                        if metric.id != cycle.metrics.last?.id { Divider().overlay(MeroliColor.line) }
                    }
                    Text(cycle.disclaimer).font(.caption2).foregroundStyle(MeroliColor.muted)
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text(cycle.academicYear).font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                    Spacer(minLength: 8)
                    Text(cycle.reportingCycle).font(.caption).foregroundStyle(MeroliColor.muted)
                }
            }
            .tint(MeroliColor.ink)
        }
        if !history.metrics.isEmpty {
            DisclosureGroup(zh ? "趋势与可比性" : "Trends and comparability") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(zh
                        ? "以下趋势和可比性说明来自官方数据解释。"
                        : "Trend and comparability notes below come from the official data interpretation.")
                        .font(.caption).foregroundStyle(MeroliColor.muted)
                    ForEach(history.metrics) { trend in
                        historyTrendRow(trend)
                        if trend.id != history.metrics.last?.id { Divider().overlay(MeroliColor.line) }
                    }
                }
                .padding(.top, 8)
            }
            .font(.subheadline.weight(.semibold))
            .tint(MeroliColor.ink)
        }
    }

    private func historyMetricRow(_ metric: ParentPerformanceMetricDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(metric.presentation?.parentLabel ?? performanceMetricLabel(metric.metricCode))
                    .font(.caption).foregroundStyle(MeroliColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 3) {
                    if metric.officialStatus.uppercased() == "REPORTED",
                       let level = metric.presentation?.performanceLevelLabel ?? performanceLevelLabel(metric.officialPerformanceLevel) {
                        Text([performanceColorLabel(metric.officialColor), level].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                    }
                    Text(historyMetricValue(metric))
                        .font(.caption.weight(.medium)).foregroundStyle(MeroliColor.muted)
                        .multilineTextAlignment(.trailing)
                }
            }
            ForEach(metric.presentation?.comparisonValues.filter { $0.scope != "SCHOOL" } ?? []) { value in
                HStack {
                    Text(value.label).foregroundStyle(MeroliColor.muted)
                    Spacer()
                    Text(value.value ?? "—").foregroundStyle(MeroliColor.muted)
                }
                .font(.caption2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func historyTrendRow(_ trend: ParentPerformanceHistoryMetricDTO) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(performanceMetricLabel(trend.metricCode))
                .font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
            if trend.methodologyCompatible,
               trend.historyBreaks.isEmpty,
               trend.trendState.uppercased() != "METHODOLOGY_CHANGED" {
                Text(trend.recentComparisonSummary ?? performanceTrendLabel(trend.trendState))
                    .font(.caption).foregroundStyle(MeroliColor.muted)
            } else {
                Text(zh
                    ? "官方计算口径不可直接比较，未汇总跨口径趋势。"
                    : "The official methodologies are not directly comparable; no cross-method trend is summarized.")
                    .font(.caption).foregroundStyle(MeroliColor.muted)
            }
            ForEach(trend.historyBreaks) { item in
                Label("\(item.afterCycle)–\(item.beforeCycle): \(item.label)", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(MeroliColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(trend.points.prefix(3))) { point in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(point.reportingCycle).foregroundStyle(MeroliColor.muted)
                        Spacer(minLength: 8)
                        Text(historyPointValue(point)).foregroundStyle(MeroliColor.ink)
                            .multilineTextAlignment(.trailing)
                    }
                    let comparisonValues = point.presentation?.comparisonValues.filter { $0.scope != "SCHOOL" } ?? []
                    ForEach(comparisonValues) { value in
                        HStack {
                            Text(value.label).foregroundStyle(MeroliColor.muted)
                            Spacer(minLength: 8)
                            Text(value.value ?? "—").foregroundStyle(MeroliColor.muted)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private func historyMetricValue(_ metric: ParentPerformanceMetricDTO) -> String {
        switch metric.officialStatus.uppercased() {
        case "REPORTED": return metric.presentation?.shortValue ?? metric.officialValue ?? performanceStatusLabel(metric.officialStatus)
        case "LEGACY":
            if let value = metric.officialValue { return performanceLevelLabel(value) ?? value }
            return performanceStatusLabel(metric.officialStatus)
        default: return performanceStatusLabel(metric.officialStatus)
        }
    }

    private func historyPointValue(_ point: ParentPerformancePointDTO) -> String {
        switch point.officialStatus.uppercased() {
        case "REPORTED": return point.presentation?.shortValue ?? point.officialValue ?? performanceStatusLabel(point.officialStatus)
        case "LEGACY":
            if let value = point.officialValue { return performanceLevelLabel(value) ?? value }
            return performanceStatusLabel(point.officialStatus)
        default: return performanceStatusLabel(point.officialStatus)
        }
    }

    private func performanceTrendLabel(_ state: String) -> String {
        switch state.uppercased() {
        case "IMPROVING": return zh ? "改善" : "Improving"
        case "DECLINING": return zh ? "下降" : "Declining"
        case "STABLE": return zh ? "保持稳定" : "Stable"
        case "METHODOLOGY_PENDING": return zh ? "等待核实官方口径" : "Official methodology pending"
        case "METHODOLOGY_CHANGED": return zh ? "官方方法已变化" : "Official methodology changed"
        case "INSUFFICIENT_DATA": return zh ? "可比较数据不足" : "Insufficient comparable data"
        default: return zh ? "官方历史趋势" : "Official historical trend"
        }
    }

    private func performanceLegend() -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(zh ? "California School Dashboard 官方等级" : "California School Dashboard official levels")
                .font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.ink)
            HStack(spacing: 9) {
                ForEach(["BLUE", "GREEN", "YELLOW", "ORANGE", "RED"], id: \.self) { code in
                    if let color = performanceColor(code), let label = performanceColorLabel(code) {
                        HStack(spacing: 3) {
                            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
                            Text(label).font(.caption2).foregroundStyle(MeroliColor.muted)
                        }
                    }
                }
            }
            Text(zh
                ? "官方等级综合当前表现与较上一年的变化，不是 Meroli 对学校的评分或排名。"
                : "Official levels combine current performance and change from the prior year. They are not a Meroli rating or ranking.")
                .font(.caption2).foregroundStyle(MeroliColor.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricDisplayValue(_ metric: ParentPerformanceMetricDTO) -> String {
        switch metric.officialStatus.uppercased() {
        case "REPORTED": return metric.presentation?.displayValue ?? metric.officialValue ?? performanceStatusLabel(metric.officialStatus)
        case "LEGACY":
            if let value = metric.officialValue {
                return performanceLevelLabel(value) ?? (value.uppercased() == "NOT_AVAILABLE"
                    ? (zh ? "暂无数据" : "Not available") : value)
            }
            return performanceStatusLabel(metric.officialStatus)
        default: return performanceStatusLabel(metric.officialStatus)
        }
    }

    private func performanceStatusLabel(_ status: String) -> String {
        switch status.uppercased() {
        case "REPORTED": return zh ? "已报告" : "Reported"
        case "SUPPRESSED": return zh ? "官方未公开" : "Not publicly reported"
        case "NOT_REPORTED": return zh ? "尚未报告" : "Not reported"
        case "NOT_APPLICABLE": return zh ? "不适用" : "Not applicable"
        case "NOT_AVAILABLE_FOR_CYCLE": return zh ? "本报告周期无此指标" : "Not available this cycle"
        case "UNAVAILABLE", "NOT_AVAILABLE": return zh ? "官方数据暂不可用" : "Official data unavailable"
        case "LEGACY": return zh ? "旧版数据" : "Legacy data"
        default: return zh ? "官方数据暂不可用" : "Official data unavailable"
        }
    }

    private func performanceLevelLabel(_ level: String?) -> String? {
        switch level?.uppercased() {
        case "NOT_AVAILABLE": return zh ? "暂无数据" : "Not available"
        case "VERY_LOW": return zh ? "很低" : "Very low"
        case "LOW": return zh ? "低" : "Low"
        case "MEDIUM": return zh ? "中等" : "Medium"
        case "HIGH": return zh ? "高" : "High"
        case "VERY_HIGH": return zh ? "很高" : "Very high"
        default: return nil
        }
    }

    private func performanceMetricLabel(_ code: String) -> String {
        switch code.uppercased() {
        case "ELA": return zh ? "英语语言艺术" : "English Language Arts"
        case "MATH": return zh ? "数学" : "Mathematics"
        case "SCIENCE": return zh ? "科学" : "Science"
        case "CHRONIC_ABSENTEEISM": return zh ? "长期缺勤率" : "Chronic Absenteeism"
        case "SUSPENSION", "SUSPENSION_RATE": return zh ? "停学率" : "Suspension Rate"
        case "EL_PROGRESS": return zh ? "英语学习者进步" : "English Learner Progress"
        case "GRADUATION", "GRADUATION_RATE": return zh ? "毕业率" : "Graduation Rate"
        case "COLLEGE_CAREER": return zh ? "大学与职业准备" : "College/Career Readiness"
        default: return zh ? "官方表现指标" : "Official performance metric"
        }
    }

    private func performanceColorLabel(_ color: String?) -> String? {
        switch color?.uppercased() {
        case "BLUE": return zh ? "蓝色" : "Blue"
        case "GREEN": return zh ? "绿色" : "Green"
        case "YELLOW": return zh ? "黄色" : "Yellow"
        case "ORANGE": return zh ? "橙色" : "Orange"
        case "RED": return zh ? "红色" : "Red"
        default: return nil
        }
    }

    private func performanceColor(_ color: String?) -> Color? {
        switch color?.uppercased() {
        case "BLUE": return Color(red: 0.00, green: 0.38, blue: 0.68)
        case "GREEN": return Color(red: 0.28, green: 0.52, blue: 0.25)
        case "YELLOW": return Color(red: 0.88, green: 0.69, blue: 0.05)
        case "ORANGE": return Color(red: 0.88, green: 0.38, blue: 0.10)
        case "RED": return Color(red: 0.75, green: 0.14, blue: 0.13)
        default: return nil
        }
    }

    private func performanceChangeLabel(_ meaning: String) -> String {
        switch meaning.uppercased() {
        case "IMPROVING": return zh ? "改善" : "Improvement"
        case "DECLINING": return zh ? "下降" : "Decline"
        case "STABLE": return zh ? "变化不大" : "Little change"
        default: return zh ? "官方变化" : "Official change"
        }
    }

}

private struct ParentFullBellScheduleSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let schoolName: String
    let schedules: [ParentBellScheduleDTO]
    private var zh: Bool { session.usesChinese }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(schoolName)
                        .font(.system(.title2, design: .serif, weight: .bold))
                        .foregroundStyle(MeroliColor.ink)
                    ForEach(schedules) { schedule in
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(categoryLabel(schedule.scheduleCategory))
                                    .font(.headline).foregroundStyle(MeroliColor.ink)
                                Text(schedule.name).font(.subheadline).foregroundStyle(MeroliColor.muted)
                                if schedule.effectiveFrom != nil || schedule.effectiveTo != nil {
                                    Text("\(schedule.effectiveFrom ?? "—") – \(schedule.effectiveTo ?? "—")")
                                        .font(.caption).foregroundStyle(MeroliColor.muted)
                                }
                            }
                            ForEach(schedule.variants) { variant in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(variant.name).font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                    HStack {
                                        if let arrival = variant.arrivalTime {
                                            Label(zh ? "到校 \(arrival)" : "Arrival \(arrival)", systemImage: "sunrise")
                                        }
                                        Spacer(minLength: 6)
                                        if let dismissal = variant.dismissalTime {
                                            Label(zh ? "放学 \(dismissal)" : "Dismissal \(dismissal)", systemImage: "sunset")
                                        }
                                    }
                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                                    if variant.periods.isEmpty {
                                        Text(zh ? "学校尚未发布课时详情。" : "Period details have not been published.")
                                            .font(.caption).foregroundStyle(MeroliColor.muted)
                                    } else {
                                        VStack(spacing: 0) {
                                            ForEach(variant.periods) { period in
                                                HStack(spacing: 10) {
                                                    Text(zh && !period.labelZh.isEmpty ? period.labelZh : period.labelEn)
                                                        .font(.subheadline).foregroundStyle(MeroliColor.ink)
                                                    if period.isOptional {
                                                        Text(zh ? "可选" : "Optional")
                                                            .font(.caption2).foregroundStyle(MeroliColor.muted)
                                                    }
                                                    Spacer(minLength: 8)
                                                    Text("\(period.startTime)–\(period.endTime)")
                                                        .font(.caption.monospacedDigit()).foregroundStyle(MeroliColor.muted)
                                                }
                                                .padding(.vertical, 9)
                                                if period.id != variant.periods.last?.id { Divider().overlay(MeroliColor.line) }
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 4)
                                if variant.id != schedule.variants.last?.id { Divider().overlay(MeroliColor.line) }
                            }
                        }
                        .padding(17)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 17))
                    }
                    Text(zh ? "时段以学校当前发布的官方作息为准。" : "Times follow the school’s currently published schedule.")
                        .font(.footnote).foregroundStyle(MeroliColor.muted)
                }
                .padding(20)
            }
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "完整作息表" : "Full Bell Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { CloseSheetButton(zh: zh) } }
        }
        .presentationDetents([.large])
    }

    private func categoryLabel(_ category: String) -> String {
        switch category {
        case "REGULAR": return zh ? "正常上课日" : "Regular day"
        case "LATE_START": return zh ? "延迟到校" : "Late start"
        case "MINIMUM_DAY": return zh ? "短日" : "Minimum day"
        case "EARLY_RELEASE": return zh ? "提前放学" : "Early release"
        case "WEDNESDAY": return zh ? "周三作息" : "Wednesday"
        default: return zh ? "学校作息" : "School schedule"
        }
    }
}

private struct EnrollmentEditorSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let child: ChildDTO
    let current: EnrollmentDTO?
    @State private var districtId = ""
    @State private var schoolId = ""
    @State private var schoolYearId = ""
    @State private var gradeCode = ""
    @State private var schedulePrograms: [ScheduleProgramDTO] = []
    @State private var selectedProgramIds: Set<String> = []
    @State private var selectionStatus = ""
    @State private var isLoadingSchedulePrograms = false
    @State private var hasLoadedSchedulePrograms = false
    @State private var hasLoaded = false
    @State private var confirmingEnrollmentAction = false
    @State private var confirmingSchoolChange = false
    @State private var showsSchoolSearch = false
    @State private var enrollmentAction = "remove"
    private var zh: Bool { session.usesChinese }
    private var selectedSchool: ParentSchoolDTO? { session.school(for: schoolId) }
    private var gradeOptions: [String] {
        var grades = selectedSchool?.availableGrades ?? []
        if !gradeCode.isEmpty && !grades.contains(gradeCode) { grades.append(gradeCode) }
        return grades
    }
    private var selectedYear: SchoolYearDTO? { session.schoolYears.first { $0.id == schoolYearId } }
    private var availableSchoolYears: [SchoolYearDTO] {
        session.schoolYears.filter { $0.districtId == nil || $0.districtId == districtId }
    }
    private var targetCurrentSchoolYear: SchoolYearDTO? {
        guard !districtId.isEmpty else { return nil }
        let timezoneId = session.districts.first(where: { $0.id == districtId })?.timezone
            ?? "America/Los_Angeles"
        guard let timezone = TimeZone(identifier: timezoneId) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let matchingYears = availableSchoolYears.filter { year in
            String(year.startDate.prefix(10)) <= today
                && String(year.endDate.prefix(10)) >= today
        }
        return matchingYears.count == 1 ? matchingYears.first : nil
    }
    private var needsScheduleConfirmation: Bool { current == nil || schoolId != current?.schoolId }
    private var scheduleChoiceIncomplete: Bool {
        needsScheduleConfirmation && (!hasLoadedSchedulePrograms
            || !schedulePrograms.isEmpty && (selectionStatus.isEmpty
                || selectionStatus == "SELECTED" && selectedProgramIds.isEmpty))
    }

    var body: some View {
        NavigationStack {
            Form {
                if session.isLoadingCatalog && (session.districts.isEmpty || session.schoolYears.isEmpty) {
                    Section {
                        ProgressView(zh ? "正在读取学校资料…" : "Loading school information…")
                    }
                } else if let error = session.catalogErrorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(MeroliColor.coral)
                        Button(zh ? "重试" : "Try again") {
                            Task { await session.loadSchoolCatalog() }
                        }
                    }
                } else if session.districts.isEmpty || session.schoolYears.isEmpty {
                    Section {
                        Text(session.districts.isEmpty
                            ? (zh ? "目前还没有开放可选学区。请稍后刷新，或联系 Meroli 支持人员。" : "No school districts are available yet. Refresh later or contact Meroli support.")
                            : (zh ? "学校学年资料暂不可用，请稍后刷新或联系 Meroli 支持人员。" : "School-year information is unavailable. Refresh later or contact Meroli support."))
                            .font(.subheadline)
                            .foregroundStyle(MeroliColor.muted)
                        Button(zh ? "重新读取学校资料" : "Reload school information") {
                            Task { await session.loadSchoolCatalog() }
                        }
                    }
                }
                Section(zh ? "学校" : "School") {
                    Picker(zh ? "学区" : "District", selection: $districtId) {
                        Text(zh ? "选择学区" : "Choose a district").tag("")
                        ForEach(session.districts) { district in
                            Text(district.name).tag(district.id)
                        }
                    }
                    .disabled(session.isLoadingCatalog)
                    .onChange(of: districtId) { _, value in
                        schoolId = ""
                        gradeCode = ""
                        if current == nil || value != current?.districtId {
                            schoolYearId = targetCurrentSchoolYear?.id ?? ""
                        } else {
                            schoolYearId = current?.schoolYearId ?? ""
                        }
                        Task { await session.loadSchools(districtId: value) }
                    }

                    Button { showsSchoolSearch = true } label: {
                        HStack {
                            Text(zh ? "学校" : "School").foregroundStyle(MeroliColor.ink)
                            Spacer()
                            Text(selectedSchool?.name ?? (zh ? "搜索并选择学校" : "Search and choose a school"))
                                .foregroundStyle(selectedSchool == nil ? MeroliColor.muted : MeroliColor.ink)
                            Image(systemName: "magnifyingglass").foregroundStyle(MeroliColor.muted)
                        }
                    }
                    .disabled(districtId.isEmpty || session.isLoadingSchools)
                    .onChange(of: schoolId) { _, value in
                        let grades = session.school(for: value)?.availableGrades ?? []
                        if value != current?.schoolId && !grades.contains(gradeCode) {
                            gradeCode = grades.first ?? ""
                        }
                        if value != current?.schoolId {
                            Task {
                                _ = await session.loadSchoolDetails(schoolId: value)
                                guard schoolId == value else { return }
                                let refreshedGrades = session.school(for: value)?.availableGrades ?? []
                                if !refreshedGrades.contains(gradeCode) { gradeCode = refreshedGrades.first ?? "" }
                                await loadSchedulePrograms(for: value)
                            }
                        } else {
                            schedulePrograms = []
                            selectedProgramIds = []
                            selectionStatus = ""
                            hasLoadedSchedulePrograms = false
                        }
                    }

                    if let school = selectedSchool {
                        Text([school.address, school.city, school.state, school.postalCode]
                            .filter { !$0.isEmpty }
                            .joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(MeroliColor.muted)
                    }
                    if current != nil && schoolId != current?.schoolId && !schoolId.isEmpty {
                        Text(zh ? "保存后会结束原学校记录并保留历史，新学校记录会立即生效。" : "Saving will close the previous school record, keep its history, and activate the new school.")
                            .font(.caption).foregroundStyle(MeroliColor.muted)
                    }
                }

                Section(zh ? "入学资料" : "Enrollment") {
                    Picker(zh ? "学年" : "School year", selection: $schoolYearId) {
                        Text(zh ? "选择学年" : "Choose a school year").tag("")
                        ForEach(availableSchoolYears) { year in Text(year.name).tag(year.id) }
                    }
                    .disabled((current != nil && districtId == current?.districtId) || session.isLoadingCatalog)
                    .onChange(of: schoolYearId) { _, _ in
                        guard needsScheduleConfirmation, !schoolId.isEmpty else { return }
                        Task { await loadSchedulePrograms(for: schoolId) }
                    }

                Picker(zh ? "年级" : "Grade", selection: $gradeCode) {
                        Text(zh ? "选择年级" : "Choose a grade").tag("")
                        ForEach(gradeOptions, id: \.self) { grade in
                            Text(localizedGrade(grade)).tag(grade)
                        }
                    }
                    .disabled(selectedSchool == nil)
                }
                if needsScheduleConfirmation {
                    Section(zh ? "影响到校时间的项目" : "Schedule-affecting programs") {
                        if isLoadingSchedulePrograms {
                            ProgressView(zh ? "正在读取学校项目…" : "Loading school programs…")
                        } else if hasLoadedSchedulePrograms && !schedulePrograms.isEmpty {
                            Text(zh ? "请重新确认会影响到校时间的课程或项目。" : "Confirm any programs that affect arrival time at the new school.")
                                .font(.caption).foregroundStyle(MeroliColor.muted)
                            scheduleChoice("SELECTED", title: zh ? "选择项目" : "Choose programs")
                            scheduleChoice("NONE", title: zh ? "没有项目" : "No programs")
                            scheduleChoice("NOT_SURE", title: zh ? "还不确定" : "Not sure yet")
                            if selectionStatus == "SELECTED" {
                                ForEach(schedulePrograms) { program in
                                    Button {
                                        if selectedProgramIds.contains(program.id) {
                                            selectedProgramIds.remove(program.id)
                                        } else {
                                            selectedProgramIds.insert(program.id)
                                        }
                                    } label: {
                                        HStack {
                                            Text(zh && !program.displayNameZh.isEmpty ? program.displayNameZh : program.displayNameEn)
                                                .foregroundStyle(MeroliColor.ink)
                                            Spacer()
                                            if selectedProgramIds.contains(program.id) {
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(MeroliColor.ink)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else if hasLoadedSchedulePrograms {
                            Text(zh ? "这所学校目前没有需要确认的到校时间项目。" : "This school has no arrival-time programs to confirm.")
                                .font(.caption).foregroundStyle(MeroliColor.muted)
                        }
                    }
                }

                if let error = session.errorMessage {
                    Section { Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral) }
                }

                Section {
                    Button {
                        if current != nil && schoolId != current?.schoolId {
                            confirmingSchoolChange = true
                        } else {
                            save()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if session.isSavingChild { ProgressView().padding(.trailing, 6) }
                            Text(current == nil ? (zh ? "保存学校资料" : "Save school details") : (zh ? "保存变更" : "Save changes"))
                            Spacer()
                        }
                    }
                    .disabled(session.isSavingChild || session.hasPendingSchoolChange(childId: child.id) || selectedSchool == nil || selectedYear == nil || gradeCode.isEmpty || scheduleChoiceIncomplete)
                }
                if current != nil {
                    Section(zh ? "记录管理" : "Enrollment record") {
                        Button(zh ? "结束此学年记录" : "Mark school year completed") {
                            enrollmentAction = "complete"
                            confirmingEnrollmentAction = true
                        }
                        if session.hasPendingSchoolRemoval(childId: child.id) {
                            Button(zh ? "检查移除状态" : "Check removal status") {
                                Task {
                                    if await session.checkPendingSchoolRemoval(childId: child.id) {
                                        dismiss()
                                    }
                                }
                            }
                            Text(zh ? "上次移除结果尚未确认。请只检查状态，不要重复提交。" : "The previous removal is unconfirmed. Check its status; do not submit it again.")
                                .font(.caption).foregroundStyle(MeroliColor.coral)
                        } else {
                            Button(zh ? "从此校移除" : "Remove from school") {
                                enrollmentAction = "remove"
                                confirmingEnrollmentAction = true
                            }
                            .foregroundStyle(MeroliColor.coral)
                            .accessibilityHint(zh ? "只移除此校关联，孩子仍保留在家庭中" : "Removes this school association only; the child remains in your family")
                        }
                    }
                    .disabled(session.isSavingChild)
                    if session.hasPendingSchoolChange(childId: child.id) {
                        Section(zh ? "换校状态待确认" : "School change needs confirmation") {
                            Text(zh ? "为避免重复提交，当前只允许读取服务器状态。" : "Only a read-only status check is available to prevent duplicate changes.")
                                .font(.caption).foregroundStyle(MeroliColor.coral)
                            Button(zh ? "检查换校状态" : "Check school change status") {
                                Task {
                                    if await session.checkPendingSchoolChange(childId: child.id) {
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "\(child.nickname) 的学校" : "\(child.nickname)’s school")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "关闭" : "Close") { dismiss() } } }
            .refreshable {
                _ = await session.loadSchoolCatalog(forceRefresh: true)
                if !districtId.isEmpty {
                    await session.loadSchools(districtId: districtId, forceRefresh: true)
                }
                if !schoolId.isEmpty { _ = await session.loadSchoolDetails(schoolId: schoolId, forceRefresh: true) }
            }
            .sheet(isPresented: $showsSchoolSearch, onDismiss: {
                guard !districtId.isEmpty else { return }
                Task { await session.loadSchools(districtId: districtId) }
            }) {
                SchoolSearchSheet(districtId: districtId, selectedSchoolId: schoolId) { selected in
                    schoolId = selected.id
                }
            }
            .confirmationDialog(enrollmentAction == "remove"
                ? (zh ? "从此校移除孩子？" : "Remove child from this school?")
                : (zh ? "确认更新入学记录？" : "Update this enrollment?"),
                isPresented: $confirmingEnrollmentAction, titleVisibility: .visible) {
                if enrollmentAction == "remove" && session.hasPendingSchoolRemoval(childId: child.id) {
                    Button(zh ? "检查移除状态" : "Check removal status") {
                        Task {
                            if await session.checkPendingSchoolRemoval(childId: child.id) {
                                dismiss()
                            }
                        }
                    }
                } else {
                    Button(enrollmentAction == "remove" ? (zh ? "从此校移除" : "Remove from school") : (zh ? "结束记录" : "Complete record"), role: .destructive) {
                        guard let current else { return }
                        Task {
                            if await session.closeEnrollment(enrollmentId: current.id, action: enrollmentAction) {
                                dismiss()
                            }
                        }
                    }
                }
                Button(zh ? "取消" : "Cancel", role: .cancel) {}
            } message: {
                Text(enrollmentAction == "remove"
                     ? (zh ? "这只会停止孩子与此校的关联；孩子仍保留在家庭中，历史入学记录也会保留。" : "This removes the school association only. The child remains in your family, and the enrollment history is kept.")
                     : (zh ? "这会将当前入学记录标记为已完成，历史记录仍会保留。" : "This marks the enrollment as completed and keeps it in history."))
            }
            .confirmationDialog(zh ? "确认更换学校？" : "Change school?", isPresented: $confirmingSchoolChange, titleVisibility: .visible) {
                Button(zh ? "更换学校并保留历史" : "Change school and keep history") { save() }
                Button(zh ? "取消" : "Cancel", role: .cancel) {}
            } message: {
                Text(zh
                    ? "当前学校记录会结束并保留在历史中，新学校将关联到所选学区的当前学年。"
                    : "The current school record will be completed and kept in history. The new school will use the selected district’s current school year.")
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await session.loadSchoolCatalog()
        if let current {
            districtId = current.districtId
            schoolYearId = current.schoolYearId
            gradeCode = current.gradeCode
            await session.loadSchools(districtId: current.districtId)
            schoolId = current.schoolId
            _ = await session.loadSchoolDetails(schoolId: current.schoolId)
            schedulePrograms = []
            hasLoadedSchedulePrograms = false
            await session.restorePendingSchoolRemoval(childId: child.id)
            await session.restorePendingSchoolChange(childId: child.id)
        } else {
            districtId = session.districts.first?.id ?? ""
            schoolYearId = targetCurrentSchoolYear?.id ?? ""
            if !districtId.isEmpty {
                await session.loadSchools(districtId: districtId)
                schoolId = session.schools.first?.id ?? ""
                gradeCode = selectedSchool?.availableGrades.first ?? ""
                await loadSchedulePrograms(for: schoolId)
            }
        }
    }

    private func loadSchedulePrograms(for targetSchoolId: String) async {
        schedulePrograms = []
        selectedProgramIds = []
        selectionStatus = ""
        hasLoadedSchedulePrograms = false
        guard !targetSchoolId.isEmpty, needsScheduleConfirmation else { return }
        isLoadingSchedulePrograms = true
        defer { isLoadingSchedulePrograms = false }
        guard let programs = await session.loadTransitionPrograms(
            schoolId: targetSchoolId,
            schoolYearId: schoolYearId.isEmpty ? nil : schoolYearId
        ), targetSchoolId == schoolId else { return }
        schedulePrograms = programs
        selectionStatus = programs.isEmpty ? "NONE" : "NOT_SURE"
        hasLoadedSchedulePrograms = true
    }

    private func save() {
        guard let school = selectedSchool, let year = selectedYear else { return }
        Task {
            if await session.saveEnrollment(
                child: child,
                current: current,
                school: school,
                schoolYear: year,
                gradeCode: gradeCode,
                selectionStatus: needsScheduleConfirmation ? selectionStatus : "NOT_SURE",
                programIds: Array(selectedProgramIds)
            ) {
                dismiss()
            }
        }
    }

    private func scheduleChoice(_ value: String, title: String) -> some View {
        Button {
            selectionStatus = value
            if value != "SELECTED" { selectedProgramIds = [] }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if selectionStatus == value { Image(systemName: "checkmark.circle.fill") }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectionStatus == value ? .isSelected : [])
    }

    private func localizedGrade(_ grade: String) -> String {
        MeroliGradePresentation.label(grade, zh: zh)
    }
}

private struct AddChildSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var districtId = ""
    @State private var schoolId = ""
    @State private var gradeCode = ""
    @State private var selectionStatus = ""
    @State private var selectedProgramIds: Set<String> = []
    @State private var showsSchoolSearch = false
    @State private var showsReview = false
    @FocusState private var isFocused: Bool
    private var zh: Bool { session.usesChinese }
    private var selectedSchool: ParentSchoolDTO? { session.school(for: schoolId) }
    private var currentSchoolYear: SchoolYearDTO? {
        guard !districtId.isEmpty else { return nil }
        let timezoneId = session.districts.first(where: { $0.id == districtId })?.timezone
            ?? "America/Los_Angeles"
        guard let timezone = TimeZone(identifier: timezoneId) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let matchingYears = session.schoolYears.filter { year in
            (year.districtId == nil || year.districtId == districtId)
                && String(year.startDate.prefix(10)) <= today
                && String(year.endDate.prefix(10)) >= today
        }
        return matchingYears.count == 1 ? matchingYears.first : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if session.isLoadingCatalog && (session.districts.isEmpty || session.schoolYears.isEmpty) {
                    Section {
                        ProgressView(zh ? "正在读取学校资料…" : "Loading school information…")
                    }
                } else if let error = session.catalogErrorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(MeroliColor.coral)
                        Button(zh ? "重试" : "Try again") {
                            Task { await session.loadSchoolCatalog() }
                        }
                    }
                } else if session.districts.isEmpty || session.schoolYears.isEmpty {
                    Section {
                        Text(session.districts.isEmpty
                            ? (zh ? "目前还没有开放可选学区。请稍后刷新，或联系 Meroli 支持人员。" : "No school districts are available yet. Refresh later or contact Meroli support.")
                            : (zh ? "学校学年资料暂不可用，请稍后刷新或联系 Meroli 支持人员。" : "School-year information is unavailable. Refresh later or contact Meroli support."))
                            .font(.subheadline)
                            .foregroundStyle(MeroliColor.muted)
                        Button(zh ? "重新读取学校资料" : "Reload school information") {
                            Task { await session.loadSchoolCatalog() }
                        }
                    }
                }
                Section {
                    TextField(zh ? "孩子的称呼" : "Child's name", text: $nickname)
                        .textContentType(.name)
                        .textFieldStyle(MeroliFieldStyle())
                        .focused($isFocused)
                        .submitLabel(.next)
                        .accessibilityIdentifier("meroli.child.nickname")
                    Text(zh ? "为保护隐私，可以填写昵称，不需要真实姓名。" : "For privacy, a nickname is enough; a legal name is not required.")
                        .font(.caption).foregroundStyle(MeroliColor.muted)
                }
                Section(zh ? "学校与年级" : "School and grade") {
                    Picker(zh ? "学区" : "District", selection: $districtId) {
                        Text(zh ? "选择学区" : "Choose a district").tag("")
                        ForEach(session.districts) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: districtId) { _, value in
                        schoolId = ""
                        gradeCode = ""
                        selectedProgramIds = []
                        Task { await session.loadSchools(districtId: value) }
                    }
                    Button { showsSchoolSearch = true } label: {
                        HStack {
                            Text(zh ? "学校" : "School").foregroundStyle(MeroliColor.ink)
                            Spacer()
                            Text(selectedSchool?.name ?? (zh ? "搜索并选择学校" : "Search and choose a school"))
                                .foregroundStyle(selectedSchool == nil ? MeroliColor.muted : MeroliColor.ink)
                            Image(systemName: "magnifyingglass").foregroundStyle(MeroliColor.muted)
                        }
                    }
                    .disabled(districtId.isEmpty || session.isLoadingSchools)
                    .onChange(of: schoolId) { _, value in
                        gradeCode = ""
                        selectionStatus = ""
                        selectedProgramIds = []
                        Task {
                            guard !value.isEmpty else { return }
                            _ = await session.loadSchoolDetails(schoolId: value)
                            guard schoolId == value else { return }
                            gradeCode = session.school(for: value)?.availableGrades.first ?? ""
                            if let programs = await session.loadTransitionPrograms(schoolId: value), value == schoolId {
                                selectionStatus = programs.isEmpty ? "NONE" : "NOT_SURE"
                            }
                        }
                    }
                    Picker(zh ? "年级" : "Grade", selection: $gradeCode) {
                        Text(zh ? "选择年级" : "Choose a grade").tag("")
                        ForEach(selectedSchool?.availableGrades ?? [], id: \.self) { grade in
                            Text(localizedGrade(grade)).tag(grade)
                        }
                    }
                    .disabled(selectedSchool == nil)
                }
                if selectedSchool != nil {
                    Section(zh ? "学年" : "School year") {
                        if let currentSchoolYear {
                            Text(currentSchoolYear.name).foregroundStyle(MeroliColor.ink)
                        } else {
                            Label(
                                zh ? "该学区当前没有唯一有效学年，请联系支持人员。" : "A unique current school year is unavailable for this district. Contact support.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.subheadline).foregroundStyle(MeroliColor.coral)
                        }
                    }
                }
                if !schoolId.isEmpty && !session.hasLoadedTransitionPrograms {
                    Section {
                        ProgressView(zh ? "正在读取学校项目…" : "Loading school programs…")
                    }
                } else if !schoolId.isEmpty && !session.transitionPrograms.isEmpty {
                    Section(zh ? "作息项目" : "Schedule programs") {
                        Text(zh ? "选择会影响到校时间的项目；若不确定，可选择‘还不确定’。" : "Choose programs that affect arrival time, or select Not sure.")
                            .font(.caption).foregroundStyle(MeroliColor.muted)
                        choiceButton("SELECTED", title: zh ? "选择项目" : "Choose programs")
                        choiceButton("NONE", title: zh ? "没有项目" : "No programs")
                        choiceButton("NOT_SURE", title: zh ? "还不确定" : "Not sure")
                        if selectionStatus == "SELECTED" {
                            ForEach(session.transitionPrograms) { program in
                                Button {
                                    if selectedProgramIds.contains(program.id) {
                                        selectedProgramIds.remove(program.id)
                                    } else {
                                        selectedProgramIds.insert(program.id)
                                    }
                                } label: {
                                    HStack {
                                        Text(zh && !program.displayNameZh.isEmpty ? program.displayNameZh : program.displayNameEn)
                                        Spacer()
                                        if selectedProgramIds.contains(program.id) {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(MeroliColor.ink)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let error = session.errorMessage {
                    Section { Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral) }
                }
                Section {
                    Button {
                        isFocused = false
                        showsReview = true
                    } label: {
                        HStack {
                            Spacer()
                            Text(zh ? "核对学校资料" : "Review school setup")
                            Spacer()
                        }
                        .foregroundStyle(.white)
                    }
                    .accessibilityIdentifier("meroli.child.review")
                    .listRowBackground(MeroliColor.ink)
                    .disabled(session.isSavingChild || nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || selectedSchool == nil || currentSchoolYear == nil || gradeCode.isEmpty
                        || !session.hasLoadedTransitionPrograms || selectionStatus.isEmpty
                        || (selectionStatus == "SELECTED" && selectedProgramIds.isEmpty))
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "新建孩子资料" : "Add a child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(zh ? "完成" : "Done") { isFocused = false }
                }
                ToolbarItem(placement: .topBarTrailing) { Button(zh ? "取消" : "Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showsSchoolSearch, onDismiss: {
                guard !districtId.isEmpty else { return }
                Task { await session.loadSchools(districtId: districtId) }
            }) {
                SchoolSearchSheet(districtId: districtId, selectedSchoolId: schoolId) { selected in
                    schoolId = selected.id
                    gradeCode = ""
                    selectionStatus = ""
                    selectedProgramIds = []
                }
            }
            .navigationDestination(isPresented: $showsReview) {
                SchoolSetupReviewView(
                    nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                    districtName: session.districts.first(where: { $0.id == districtId })?.name ?? "",
                    schoolName: selectedSchool?.name ?? "",
                    schoolYearName: currentSchoolYear?.name ?? "",
                    gradeName: localizedGrade(gradeCode),
                    programNames: session.transitionPrograms
                        .filter { selectedProgramIds.contains($0.id) }
                        .map { zh && !$0.displayNameZh.isEmpty ? $0.displayNameZh : $0.displayNameEn },
                    selectionStatus: selectionStatus,
                    zh: zh,
                    onConfirm: save
                )
            }
            .refreshable {
                _ = await session.loadSchoolCatalog(forceRefresh: true)
                if !districtId.isEmpty {
                    await session.loadSchools(districtId: districtId, forceRefresh: true)
                }
                if !schoolId.isEmpty { _ = await session.loadSchoolDetails(schoolId: schoolId, forceRefresh: true) }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        isFocused = false
        guard let school = selectedSchool, let schoolYear = currentSchoolYear else { return }
        Task {
            if await session.subscribeChild(
                nickname: nickname,
                school: school,
                schoolYear: schoolYear,
                gradeCode: gradeCode,
                selectionStatus: selectionStatus,
                programIds: selectedProgramIds.sorted()
            ) { dismiss() }
        }
    }

    private func load() async {
        await session.loadSchoolCatalog()
    }

    private func choiceButton(_ value: String, title: String) -> some View {
        Button {
            selectionStatus = value
            if value != "SELECTED" { selectedProgramIds = [] }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if selectionStatus == value { Image(systemName: "checkmark.circle.fill") }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectionStatus == value ? .isSelected : [])
    }

    private func localizedGrade(_ grade: String) -> String {
        MeroliGradePresentation.label(grade, zh: zh)
    }
}

private struct SchoolSetupReviewView: View {
    @Environment(SessionStore.self) private var session
    let nickname: String
    let districtName: String
    let schoolName: String
    let schoolYearName: String
    let gradeName: String
    let programNames: [String]
    let selectionStatus: String
    let zh: Bool
    let onConfirm: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(zh ? "请确认孩子的学校资料" : "Review your child's school setup")
                    .font(.system(.title, design: .serif, weight: .bold))
                    .foregroundStyle(MeroliColor.ink)
                VStack(spacing: 0) {
                    row(zh ? "孩子" : "Child", value: nickname)
                    Divider().overlay(MeroliColor.line)
                    row(zh ? "学区" : "District", value: districtName)
                    Divider().overlay(MeroliColor.line)
                    row(zh ? "学校" : "School", value: schoolName)
                    Divider().overlay(MeroliColor.line)
                    row(zh ? "学年" : "School year", value: schoolYearName)
                    Divider().overlay(MeroliColor.line)
                    row(zh ? "年级" : "Grade", value: gradeName)
                    Divider().overlay(MeroliColor.line)
                    row(zh ? "作息项目" : "Schedule programs", value: programSummary)
                }
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))

                if let error = session.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline).foregroundStyle(MeroliColor.coral)
                }

                Text(zh ? "确认后会将孩子和学校资料保存到家庭中。" : "Confirm to save this child and school setup to your family.")
                    .font(.subheadline).foregroundStyle(MeroliColor.muted)
                Button(action: onConfirm) {
                    HStack {
                        Spacer()
                        if session.isSavingChild { ProgressView().padding(.trailing, 7) }
                        Text(zh ? "确认并添加学校" : "Confirm and add school")
                        Spacer()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minHeight: 52)
                    .background(MeroliColor.ink, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .disabled(session.isSavingChild)
                .accessibilityIdentifier("meroli.child.confirmSetup")
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MeroliColor.canvas.ignoresSafeArea())
        .navigationTitle(zh ? "核对学校资料" : "Review setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var programSummary: String {
        switch selectionStatus {
        case "SELECTED": return programNames.joined(separator: ", ")
        case "NONE": return zh ? "没有会影响到校时间的项目" : "No schedule-affecting programs"
        default: return zh ? "暂不确定" : "Not sure yet"
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title).font(.subheadline).foregroundStyle(MeroliColor.muted)
            Spacer(minLength: 8)
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(MeroliColor.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }
}

private struct RenameChildSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let child: ChildDTO
    @State private var nickname: String
    @FocusState private var isFocused: Bool
    private var zh: Bool { session.usesChinese }

    init(child: ChildDTO) {
        self.child = child
        _nickname = State(initialValue: child.nickname)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(zh ? "修改家庭中显示的称呼。" : "Change the name shown for this child in your family.")
                    .font(.body)
                    .foregroundStyle(MeroliColor.muted)
                TextField(zh ? "孩子的称呼" : "Child's name", text: $nickname)
                    .textContentType(.name)
                    .textFieldStyle(MeroliFieldStyle())
                    .focused($isFocused)
                    .accessibilityIdentifier("meroli.child.nickname")
                if let error = session.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral)
                }
                Button {
                    isFocused = false
                    Task { if await session.renameChild(id: child.id, nickname: nickname) { dismiss() } }
                } label: {
                    HStack {
                        if session.isSavingChild { ProgressView().tint(.white) }
                        Text(zh ? "保存" : "Save changes")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 51)
                    .foregroundStyle(.white)
                    .background(MeroliColor.ink, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(session.isSavingChild)
                Spacer(minLength: 0)
            }
            .padding(22)
            .background(MeroliColor.canvas.ignoresSafeArea())
            .navigationTitle(zh ? "编辑称呼" : "Edit name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "取消" : "Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

private struct SettingsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var isLoggingOut = false
    @State private var showsDeleteAccount = false
    @State private var showsClearCacheConfirmation = false
    @State private var showsSchoolYearUpdate = false
    @State private var showsFamilyManagement = false
    @State private var cacheSummaryVersion = 0
    @State private var appleRawNonce: String?
    private var zh: Bool { session.usesChinese }
    private let destructiveColor = Color(red: 192 / 255.0, green: 57 / 255.0, blue: 43 / 255.0)
    private var actionableSchoolYearChildCount: Int {
        SchoolYearTransitionPresentation.actionableChildCount(session.schoolYearTransitions)
    }
    private var inactiveSchoolYearStatus: String {
        SchoolYearTransitionPresentation.inactiveStatus(
            session.schoolYearTransitions,
            isLoading: session.isLoadingFamily,
            zh: zh
        )
    }
    private var schoolYearReviewStatusText: String {
        let count = actionableSchoolYearChildCount
        if zh { return "\(count) 个孩子待确认" }
        return count == 1 ? "1 child needs review" : "\(count) children need review"
    }
    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
    private var cachedSize: String {
        ByteCountFormatter.string(fromByteCount: session.cachedResponseByteCount, countStyle: .file)
    }

    private var familySettingsSection: some View {
        Section(zh ? "家庭" : "Family") {
            familyManagementRow
            schoolYearUpdateRow
        }
    }

    private var familyManagementRow: some View {
        Button { showsFamilyManagement = true } label: {
            Label(zh ? "管理孩子与学校" : "Manage Children & Schools", systemImage: "person.2")
                .foregroundStyle(MeroliColor.ink)
        }
        .accessibilityIdentifier("meroli.settings.family-management")
        .accessibilityHint(zh ? "管理孩子资料和当前学校" : "Manage children and their current schools")
    }

    @ViewBuilder
    private var schoolYearUpdateRow: some View {
        if actionableSchoolYearChildCount > 0 {
            Button { showsSchoolYearUpdate = true } label: {
                HStack(spacing: 10) {
                    Label(zh ? "学年更新" : "School Year Update", systemImage: "arrow.forward.calendar")
                        .foregroundStyle(MeroliColor.ink)
                    Spacer(minLength: 8)
                    Text(schoolYearReviewStatusText)
                        .font(.caption)
                        .foregroundStyle(MeroliColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MeroliColor.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("meroli.settings.school-year-update")
            .accessibilityHint(zh ? "打开学年更新流程" : "Opens school year updates")
        } else {
            inactiveSchoolYearUpdateRow
        }
    }

    private var inactiveSchoolYearUpdateRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(zh ? "学年更新" : "School Year Update")
                    .foregroundStyle(MeroliColor.secondary)
                Text(inactiveSchoolYearStatus)
                    .font(.caption)
                    .foregroundStyle(MeroliColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("meroli.settings.school-year-update")
    }

    private var appPreferencesSection: some View {
        Section {
            Picker(zh ? "应用语言" : "App language", selection: languageSelection) {
                Text("English").tag("en")
                Text("简体中文").tag("zh-CN")
            }
            LabeledContent(zh ? "版本号" : "Version", value: appVersionLabel)
        } header: {
            Text(zh ? "应用偏好" : "App preferences")
        }
    }

    private var languageSelection: Binding<String> {
        Binding(
            get: { session.language },
            set: { value in Task { await session.setLanguage(value) } }
        )
    }

    private var accountSection: some View {
        Section(zh ? "账户" : "Account") {
            LabeledContent(zh ? "邮箱" : "Email", value: session.email)
            if let family = session.family, !family.id.isEmpty {
                LabeledContent(zh ? "家庭编号" : "Family ID", value: family.id)
            }
            appleAccountControl
            signOutButton
            if let error = session.errorMessage {
                Text(error)
                    .foregroundStyle(MeroliColor.coral)
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var appleAccountControl: some View {
        if session.isAppleLinked {
            Label(zh ? "已绑定 Apple 账号" : "Apple account linked", systemImage: "checkmark.circle.fill")
                .foregroundStyle(MeroliColor.ink)
        } else {
            MeroliAppleAuthorizationButton(
                type: .continue,
                title: zh ? "继续使用 Apple" : "Continue with Apple",
                height: 52,
                accessibilityIdentifier: "meroli.settings.bind-apple",
                onRequest: configureAppleAuthorizationRequest,
                onCompletion: handleAppleAuthorizationResult
            )
        }
    }

    private func configureAppleAuthorizationRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleNonce.generate()
        appleRawNonce = nonce
        request.nonce = AppleNonce.sha256(nonce)
        request.requestedScopes = [.email]
    }

    private func handleAppleAuthorizationResult(_ result: Result<ASAuthorization, any Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              let nonce = appleRawNonce else {
            if case .failure(let error) = result { session.errorMessage = error.localizedDescription }
            return
        }
        Task { await session.bindApple(identityToken: token, rawNonce: nonce) }
    }

    private var signOutButton: some View {
        Button {
            isLoggingOut = true
            Task { await session.logout(); isLoggingOut = false }
        } label: {
            HStack {
                if isLoggingOut { ProgressView().tint(MeroliColor.secondary) }
                Text(zh ? "退出登录" : "Sign out")
            }
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .foregroundStyle(MeroliColor.secondary)
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(MeroliColor.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isLoggingOut)
        .accessibilityIdentifier("meroli.settings.logout")
        .accessibilityHint(zh ? "退出当前账户" : "Signs out of this account")
    }

    private var storageSection: some View {
        Section {
            LabeledContent(zh ? "已缓存数据" : "Cached data", value: cachedResponseSummary)
            Button {
                showsClearCacheConfirmation = true
            } label: {
                Label(zh ? "清理缓存" : "Clear cache", systemImage: "trash")
                    .foregroundStyle(MeroliColor.secondary)
            }
            .accessibilityHint(zh ? "清理本机缓存数据" : "Clears cached data on this device")
        } header: {
            Text(zh ? "存储" : "Storage")
        } footer: {
            Text(zh
                ? "清理后，家庭、学校、日历和作息数据会在下次读取时重新下载。"
                : "Family, school, calendar, and schedule data will download again when next opened.")
        }
    }

    private var cachedResponseSummary: String {
        zh
            ? "\(session.cachedResponseCount) 项 · \(cachedSize)"
            : "\(session.cachedResponseCount) items · \(cachedSize)"
    }

    private var dangerZoneSection: some View {
        Section(zh ? "危险操作" : "Danger zone") {
            Button { showsDeleteAccount = true } label: {
                Text(zh ? "删除账户" : "Delete account")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 7)
                    .foregroundStyle(.white)
                    .background(destructiveColor, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("meroli.settings.delete-account")
            .accessibilityHint(zh ? "永久删除账户前会要求确认" : "You will be asked to confirm before your account is permanently deleted")
            Text(zh
                ? "删除后你将无法再登录。独占家庭的孩子、入学和作息资料会一并删除；其他成员共享的家庭资料会保留。"
                : "You will no longer be able to sign in. Children, enrollments, and schedules in a family used only by you will be deleted. Shared family data will remain for other members.")
                .font(.footnote)
                .foregroundStyle(MeroliColor.muted)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                familySettingsSection
                appPreferencesSection
                accountSection
                storageSection
                dangerZoneSection
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 12).accessibilityHidden(true)
            }
            .scrollContentBackground(.hidden)
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "设置" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsDeleteAccount) { DeleteAccountSheet() }
            .sheet(isPresented: $showsFamilyManagement) { FamilyScreen() }
            .sheet(isPresented: $showsSchoolYearUpdate) { SchoolYearUpdateScreen() }
            .confirmationDialog(
                zh ? "清理本地缓存？" : "Clear local cache?",
                isPresented: $showsClearCacheConfirmation,
                titleVisibility: .visible
            ) {
                Button(zh ? "清理缓存" : "Clear cache") {
                    session.clearCachedRemoteData()
                    cacheSummaryVersion += 1
                }
                Button(zh ? "取消" : "Cancel", role: .cancel) {}
            } message: {
                Text(zh
                    ? "这只会删除本机保存的远端数据，不会退出登录或删除账户资料。"
                    : "This removes remote data saved on this device. It will not sign you out or delete your account.")
            }
        }
        .task {
            await session.loadAppleBinding()
            if session.family == nil { await session.loadFamily() }
        }
    }
}

private struct MeroliAppleAuthorizationButton: View {
    let type: SignInWithAppleButton.Label
    let title: String
    let height: CGFloat
    let accessibilityIdentifier: String
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, any Error>) -> Void

    var body: some View {
        SignInWithAppleButton(type, onRequest: onRequest, onCompletion: onCompletion)
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .clipShape(RoundedRectangle(cornerRadius: min(15, height / 3)))
            .accessibilityLabel(title)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private enum AppleNonce {
    static func generate() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct DeleteAccountSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirming = false
    @State private var isDeleting = false
    @State private var isCheckingAppleBinding = true
    @State private var appleRawNonce: String?
    @State private var appleIdentityToken: String?
    private var zh: Bool { session.usesChinese }
    private let destructiveColor = Color(red: 192 / 255.0, green: 57 / 255.0, blue: 43 / 255.0)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(zh ? "此操作无法撤销。请用当前密码或已绑定的 Apple 账号重新验证。" : "This action cannot be undone. Reauthenticate with your current password or linked Apple account.")
                        .foregroundStyle(MeroliColor.coral)
                    SecureField(zh ? "当前密码" : "Current password", text: $password)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("meroli.delete-account.password")
                }
                if isCheckingAppleBinding {
                    Section { ProgressView(zh ? "正在检查 Apple 绑定…" : "Checking Apple account…") }
                } else if session.isAppleLinked {
                    Section(zh ? "使用 Apple 验证" : "Verify with Apple") {
                        MeroliAppleAuthorizationButton(
                            type: .continue,
                            title: zh ? "继续使用 Apple" : "Continue with Apple",
                            height: 44,
                            accessibilityIdentifier: "meroli.delete-account.verify-apple",
                            onRequest: { request in
                            let nonce = AppleNonce.generate()
                            appleRawNonce = nonce
                            request.nonce = AppleNonce.sha256(nonce)
                            request.requestedScopes = []
                            },
                            onCompletion: { result in
                            guard case .success(let authorization) = result,
                                  let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                                  let tokenData = credential.identityToken,
                                  let token = String(data: tokenData, encoding: .utf8),
                                  appleRawNonce != nil else {
                                if case .failure(let error) = result { session.errorMessage = error.localizedDescription }
                                return
                            }
                            appleIdentityToken = token
                            confirming = true
                            }
                        )
                        .disabled(isDeleting)
                    }
                }
                if let error = session.errorMessage {
                    Section { Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral) }
                }
                Section {
                    Button(role: .destructive) { confirming = true } label: {
                        HStack {
                            Spacer()
                            if isDeleting { ProgressView().padding(.trailing, 7) }
                            Text(zh ? "永久删除账户" : "Permanently delete account")
                            Spacer()
                        }
                    }
                    .disabled(password.isEmpty || isDeleting)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "删除账户" : "Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "取消" : "Cancel") { dismiss() } } }
            .confirmationDialog(zh ? "确定永久删除账户？" : "Permanently delete this account?", isPresented: $confirming, titleVisibility: .visible) {
                Button(zh ? "删除账户" : "Delete account", role: .destructive) {
                    isDeleting = true
                    Task {
                        if await session.deleteAccount(password: password, identityToken: appleIdentityToken, rawNonce: appleRawNonce) { dismiss() }
                        isDeleting = false
                    }
                }
                Button(zh ? "返回" : "Go back", role: .cancel) {}
            } message: {
                Text(zh ? "删除后无法恢复。系统会重新验证当前密码或 Apple 账号。" : "Deleted information cannot be restored. Your password or linked Apple account will be verified again.")
            }
            .task {
                await session.loadAppleBinding()
                isCheckingAppleBinding = false
            }
        }
        .tint(destructiveColor)
        .presentationDetents([.medium, .large])
    }
}

private struct MeroliFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(15)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MeroliColor.line, lineWidth: 1))
    }
}

private struct SchoolSearchSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let districtId: String
    let selectedSchoolId: String
    let onSelect: (ParentSchoolDTO) -> Void
    @State private var searchText = ""
    private var zh: Bool { session.usesChinese }

    var body: some View {
        NavigationStack {
            List {
                if session.isLoadingSchools && session.schools.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView(zh ? "正在搜索学校…" : "Searching schools…")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let error = session.errorMessage, session.schools.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(MeroliColor.coral)
                        Button(zh ? "重试" : "Try again") { Task { await search() } }
                    }
                } else if session.schools.isEmpty {
                    Text(zh ? "没有找到匹配的学校" : "No schools match your search")
                        .foregroundStyle(MeroliColor.muted)
                } else {
                    ForEach(session.schools) { school in
                        Button {
                            onSelect(school)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(school.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(MeroliColor.ink)
                                    let location = [school.city, school.state].filter { !$0.isEmpty }.joined(separator: ", ")
                                    if !location.isEmpty {
                                        Text(location).font(.caption).foregroundStyle(MeroliColor.muted)
                                    }
                                }
                                Spacer(minLength: 8)
                                if school.id == selectedSchoolId {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(MeroliColor.ink)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("meroli.school.option.\(school.id)")
                    }
                }
            }
            .overlay(alignment: .top) {
                if session.isLoadingSchools && !session.schools.isEmpty {
                    ProgressView().padding(.top, 8)
                }
            }
            .searchable(text: $searchText, prompt: zh ? "搜索学校名称" : "Search school names")
            .refreshable {
                await session.loadSchools(districtId: districtId, keyword: searchText, forceRefresh: true)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle(zh ? "选择学校" : "Choose a school")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "完成" : "Done") { dismiss() } } }
            .task(id: searchText) {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await search()
            }
        }
        .presentationDetents([.large])
    }

    private func search() async {
        await session.loadSchools(districtId: districtId, keyword: searchText)
    }
}
