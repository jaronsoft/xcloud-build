import SwiftUI
import AuthenticationServices
import CryptoKit
import UIKit

private enum MeroliColor {
    static let ink = Color(red: 23 / 255, green: 63 / 255, blue: 58 / 255)
    static let canvas = Color(red: 1, green: 253 / 255, blue: 248 / 255)
    static let muted = Color(red: 73 / 255, green: 102 / 255, blue: 97 / 255)
    static let line = Color(red: 212 / 255, green: 223 / 255, blue: 218 / 255)
    static let gold = Color(red: 239 / 255, green: 181 / 255, blue: 62 / 255)
    static let coral = Color(red: 190 / 255, green: 77 / 255, blue: 64 / 255)
    static let paleGreen = Color(red: 235 / 255, green: 243 / 255, blue: 238 / 255)
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
                ProgressView()
                    .tint(MeroliColor.ink)
                    .padding(.top, 10)
            }
            .offset(y: isAnimating ? -4 : 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    var body: some View {
        TabView(selection: $selected) {
            HomeScreen(showFamily: { selected = 1 })
                .tag(0)
                .tabItem { Label(zh ? "首页" : "Home", systemImage: "sun.max") }
            FamilyScreen()
                .tag(1)
                .tabItem { Label(zh ? "学校" : "Schools", systemImage: "building.2") }
            CalendarScreen()
                .tag(2)
                .tabItem { Label(zh ? "日历" : "Calendar", systemImage: "calendar") }
            SettingsScreen()
                .tag(3)
                .tabItem { Label(zh ? "设置" : "Settings", systemImage: "gearshape") }
        }
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
    @Binding var selection: String
    let zh: Bool

    var body: some View {
        HStack(spacing: 8) {
            optionButton(title: zh ? "全部" : "All", id: "", accessibilityId: "meroli.childFilter.all")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(children) { child in
                        optionButton(title: child.nickname, id: child.id, accessibilityId: "meroli.childFilter.\(child.id)")
                    }
                }
                .padding(.vertical, 2)
            }
            .contentMargins(.trailing, 2)
        }
        .accessibilityElement(children: .contain)
    }

    private func optionButton(title: String, id: String, accessibilityId: String) -> some View {
        let isSelected = selection == id
        return Button { selection = id } label: {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: id.isEmpty ? nil : 156)
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .foregroundStyle(isSelected ? .white : MeroliColor.ink)
                .background(isSelected ? MeroliColor.ink : .white, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? MeroliColor.ink : MeroliColor.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(accessibilityId)
    }
}

private struct HomeScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let showFamily: () -> Void
    @State private var date = Date()
    @AppStorage("meroli.home.childId") private var selectedChildId = ""
    @State private var selectedEvent: ParentEventDTO?
    private var zh: Bool { session.usesChinese }
    private var schoolCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = session.schoolTimezone(for: selectedChildId.isEmpty ? nil : selectedChildId)
        return calendar
    }
    private var selectedSchedules: [DailyScheduleDTO] {
        selectedChildId.isEmpty ? session.dailySchedules : session.dailySchedules.filter { $0.childId == selectedChildId }
    }
    private var childrenWithoutSchoolToday: [DailyScheduleDTO] {
        selectedSchedules.filter { $0.status == "NO_SCHOOL" || $0.status == "NON_INSTRUCTIONAL_DAY" }
    }
    private var selectedTomorrowSchedules: [DailyScheduleDTO] {
        selectedChildId.isEmpty ? session.tomorrowDailySchedules : session.tomorrowDailySchedules.filter { $0.childId == selectedChildId }
    }
    private var visibleEvents: [ParentEventDTO] {
        MeroliEventPresentation.sorted(selectedChildId.isEmpty
            ? session.homeEvents
            : session.homeEvents.filter { $0.children.contains { $0.id == selectedChildId } })
    }
    private var todayEvents: [ParentEventDTO] {
        visibleEvents.filter { eventOccurs($0, offsets: 0...0) }
    }
    private var tomorrowEvents: [ParentEventDTO] {
        visibleEvents.filter { eventOccurs($0, offsets: 1...1) }
    }
    private var thisWeekEvents: [ParentEventDTO] {
        let earlierEventIds = Set(todayEvents.map(\.id) + tomorrowEvents.map(\.id))
        return visibleEvents.filter {
            !earlierEventIds.contains($0.id)
                && eventOccurs($0, offsets: 2...7)
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Meroli")
                        .font(.system(.headline, design: .serif, weight: .bold)).foregroundStyle(MeroliColor.ink)
                    Text(zh ? "今天的上学安排" : "Today at school")
                        .font(.system(.largeTitle, design: .serif, weight: .bold)).foregroundStyle(MeroliColor.ink)
                    HStack {
                        Button { date = schoolCalendar.date(byAdding: .day, value: -1, to: date) ?? date; refresh() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel(zh ? "前一天" : "Previous day")
                        Spacer()
                        Text(schoolDateLabel(date))
                            .font(.headline)
                        Spacer()
                        Button { date = schoolCalendar.date(byAdding: .day, value: 1, to: date) ?? date; refresh() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .accessibilityLabel(zh ? "后一天" : "Next day")
                    }
                    if session.children.count > 1 {
                        MeroliChildFilter(children: session.children, selection: $selectedChildId, zh: zh)
                        .onChange(of: selectedChildId) { _, _ in
                            date = schoolCalendar.startOfDay(for: .now)
                            refresh()
                        }
                    }
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
                                .foregroundStyle(MeroliColor.muted)
                            Button(action: showFamily) {
                                Label(zh ? "添加孩子" : "Add a child", systemImage: "person.crop.circle.badge.plus")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MeroliColor.ink)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("meroli.home.addChild")
                        }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        sectionHeading(zh ? "今天" : "Today")
                        ForEach(selectedSchedules) { item in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.childName).font(.headline).foregroundStyle(MeroliColor.ink)
                                        Text(item.schoolName ?? (zh ? "未设置学校" : "No school selected"))
                                            .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                        if item.date != dateKey(offset: 0) {
                                            Text(schoolLocalDateNote(item.date))
                                                .font(.caption2).foregroundStyle(MeroliColor.muted)
                                        }
                                    }
                                    Spacer()
                                    Text(statusLabel(item.status)).font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(MeroliColor.paleGreen, in: Capsule())
                                }
                                if item.status == "NO_SCHOOL" || item.status == "NON_INSTRUCTIONAL_DAY" {
                                    Label(zh ? "这一天没有常规上课" : "No regular school on this day", systemImage: "sun.max")
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                    if session.isLoadingNextInstructionalDay {
                                        ProgressView(zh ? "正在查找下一次上课日…" : "Finding the next school day…")
                                    } else if let nextDay = session.nextInstructionalDays.first(where: { $0.childId == item.childId }) {
                                        if let nextDate = nextDay.date {
                                            Text((zh ? "下一次上课：" : "Next school day: ")
                                                + nextInstructionalDateLabel(nextDate, childId: item.childId))
                                                .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                        } else {
                                            Text(zh ? "未来 21 天内暂无上课日。" : "No school day in the next 21 days.")
                                                .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                        }
                                    } else if !selectedChildId.isEmpty, let nextDate = session.nextInstructionalDay {
                                        Text((zh ? "下一次上课：" : "Next school day: ")
                                            + nextInstructionalDateLabel(nextDate, childId: item.childId))
                                            .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                    } else if let error = session.nextInstructionalDayErrorMessage {
                                        Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral)
                                    }
                                    ForEach(item.eventTitles, id: \.self) { title in
                                        Label(title, systemImage: "calendar")
                                            .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                    }
                                } else if item.status == "OK" {
                                    HStack(spacing: 20) {
                                        scheduleTime(title: arrivalTimeLabel(item), value: item.arrivalTime)
                                        scheduleTime(title: zh ? "放学" : "Dismissal", value: item.dismissalTime)
                                    }
                                    if let scheduleType = item.scheduleType {
                                        Text(scheduleTypeLabel(scheduleType))
                                            .font(.caption).foregroundStyle(MeroliColor.muted)
                                    }
                                    if let periods = item.periods, !periods.isEmpty {
                                        VStack(spacing: 0) {
                                            ForEach(periods) { period in
                                                HStack(spacing: 10) {
                                                    Text(zh && !period.labelZh.isEmpty ? period.labelZh : period.labelEn)
                                                        .font(.caption.weight(.medium)).foregroundStyle(MeroliColor.ink)
                                                    Spacer(minLength: 4)
                                                    Text("\(period.startTime)–\(period.endTime)")
                                                        .font(.caption.monospacedDigit()).foregroundStyle(MeroliColor.muted)
                                                    if period.isOptional {
                                                        Text(zh ? "可选" : "Optional").font(.caption2).foregroundStyle(MeroliColor.muted)
                                                    }
                                                }
                                                .padding(.vertical, 7)
                                                if period.id != periods.last?.id { Divider().overlay(MeroliColor.line) }
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                    if session.homeEventsErrorMessage != nil, !item.eventTitles.isEmpty {
                                        ForEach(item.eventTitles, id: \.self) { title in
                                            Label(title, systemImage: "calendar.badge.exclamationmark")
                                                .font(.subheadline)
                                        }
                                    }
                                } else {
                                    Text(statusLabel(item.status))
                                        .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                }
                            }
                            .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    if let error = session.homeEventsErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(MeroliColor.coral)
                    }
                    if !todayEvents.isEmpty {
                        sectionHeading(zh ? "今天学校动态" : "Today’s School Updates")
                        eventList(todayEvents)
                    }
                    sectionHeading(zh ? "明天" : "Tomorrow")
                    if session.isLoadingTomorrowSchedules && selectedTomorrowSchedules.isEmpty {
                        ProgressView(zh ? "正在读取明天的作息…" : "Loading tomorrow’s schedules…")
                    }
                    if let error = session.tomorrowSchedulesErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(MeroliColor.coral)
                    }
                    ForEach(selectedTomorrowSchedules) { item in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.childName).font(.headline).foregroundStyle(MeroliColor.ink)
                                    Text(item.schoolName ?? (zh ? "未设置学校" : "No school selected"))
                                        .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                    if item.date != dateKey(offset: 1) {
                                        Text(schoolLocalDateNote(item.date))
                                            .font(.caption2).foregroundStyle(MeroliColor.muted)
                                    }
                                }
                                Spacer()
                                Text(statusLabel(item.status)).font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(MeroliColor.paleGreen, in: Capsule())
                            }
                            if item.status == "OK" {
                                HStack(spacing: 20) {
                                    scheduleTime(title: arrivalTimeLabel(item), value: item.arrivalTime)
                                    scheduleTime(title: zh ? "放学" : "Dismissal", value: item.dismissalTime)
                                }
                                if let scheduleType = item.scheduleType {
                                    Text(scheduleTypeLabel(scheduleType)).font(.caption).foregroundStyle(MeroliColor.muted)
                                }
                            }
                            if session.homeEventsErrorMessage != nil, !item.eventTitles.isEmpty {
                                ForEach(item.eventTitles, id: \.self) { title in
                                    Label(title, systemImage: "calendar.badge.exclamationmark")
                                        .font(.subheadline)
                                }
                            }
                        }
                        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if tomorrowEvents.isEmpty && selectedTomorrowSchedules.isEmpty && !session.isLoadingTomorrowSchedules {
                        Text(zh ? "明天暂时没有学校动态。" : "No school updates for tomorrow.")
                            .font(.subheadline).foregroundStyle(MeroliColor.muted)
                    }
                    if !tomorrowEvents.isEmpty { eventList(tomorrowEvents) }
                    sectionHeading(zh ? "本周" : "This Week")
                    if thisWeekEvents.isEmpty {
                        Text(zh ? "后续暂无学校动态。" : "No further school updates this week.")
                            .font(.subheadline).foregroundStyle(MeroliColor.muted)
                    } else { eventList(thisWeekEvents) }
                }
                .padding(20)
            }
            .background(MeroliColor.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel(zh ? "刷新日历" : "Refresh calendar")
                }
            }
            .refreshable {
                await session.loadFamily()
                await session.loadDailySchedules(for: date, childId: selectedChildId.isEmpty ? nil : selectedChildId)
                await loadNextInstructionalDayIfNeeded()
                await session.loadTomorrowDailySchedules(for: tomorrowDate, childId: selectedChildId.isEmpty ? nil : selectedChildId)
                await loadHomeEvents()
            }
            .task { if session.dailySchedules.isEmpty || session.homeEvents.isEmpty { refresh() } }
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
        Task {
            await session.loadDailySchedules(for: date, childId: selectedChildId.isEmpty ? nil : selectedChildId)
            await loadNextInstructionalDayIfNeeded()
            await session.loadTomorrowDailySchedules(for: tomorrowDate, childId: selectedChildId.isEmpty ? nil : selectedChildId)
            await loadHomeEvents()
        }
    }

    private func loadNextInstructionalDayIfNeeded() async {
        guard !childrenWithoutSchoolToday.isEmpty else { return }
        await session.loadNextInstructionalDay(after: date, childId: selectedChildId.isEmpty ? nil : selectedChildId)
    }

    private var tomorrowDate: Date {
        schoolCalendar.date(byAdding: .day, value: 1, to: date) ?? date
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

    private func schoolLocalDateNote(_ key: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.calendar = schoolCalendar
        formatter.timeZone = schoolCalendar.timeZone
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
        Text(title).font(.title3.weight(.semibold)).foregroundStyle(MeroliColor.ink).padding(.top, 8)
    }

    private func eventList(_ events: [ParentEventDTO]) -> some View {
        VStack(spacing: 0) {
            ForEach(events) { event in
                Button { selectedEvent = event } label: { EventRow(event: event, zh: zh) }
                    .buttonStyle(.plain)
                    .padding(.vertical, 12)
                if event.id != events.last?.id { Divider().overlay(MeroliColor.line) }
            }
        }
        .padding(.horizontal, 15)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func homeErrorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(zh ? "暂时无法读取家庭安排" : "Schedules are unavailable", systemImage: "exclamationmark.triangle")
                .font(.headline).foregroundStyle(MeroliColor.coral)
            Text(error).font(.subheadline).foregroundStyle(MeroliColor.muted)
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
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
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
        case "SCHEDULE_DATA_UNAVAILABLE", "SCHEDULE_UNAVAILABLE", "SCHEDULE_DATA_INCOMPLETE": return zh ? "暂无可靠课表" : "Schedule unavailable"
        default: return zh ? "暂无课表" : "Schedule unavailable"
        }
    }

    private func scheduleTypeLabel(_ value: String) -> String {
        switch value.uppercased() {
        case "REGULAR", "REGULAR_DAY": return zh ? "正常作息" : "Regular schedule"
        case "LATE_START": return zh ? "延迟到校作息" : "Late start schedule"
        case "MINIMUM_DAY": return zh ? "短日作息" : "Minimum day schedule"
        case "EARLY_RELEASE": return zh ? "提前放学作息" : "Early release schedule"
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
    @AppStorage("meroli.calendar.displayMode") private var displayMode = "month"
    private var zh: Bool { session.usesChinese }
    private var schoolCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = session.schoolTimezone(for: selectedChildId.isEmpty ? nil : selectedChildId)
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
    private var groupedEvents: [(String, [ParentEventDTO])] {
        let groups = Dictionary(grouping: MeroliEventPresentation.sorted(session.calendarEvents), by: \.startDate)
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
        MeroliEventPresentation.sorted(session.calendarEvents.filter { eventCovers($0, date: selectedDate) })
    }
    private var selectedWeek: [Date] {
        let parts = schoolCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        guard let start = schoolCalendar.date(from: parts) else { return [selectedDate] }
        return (0..<7).compactMap { schoolCalendar.date(byAdding: .day, value: $0, to: start) }
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
                    MeroliChildFilter(children: session.children, selection: $selectedChildId, zh: zh)
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
                        Text(zh ? "这一天没有学校日程。" : "No school events on this day.")
                            .font(.subheadline).foregroundStyle(MeroliColor.muted).padding(.horizontal, 18)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(selectedDateEvents) { event in
                                Button { selectedEvent = event } label: { EventRow(event: event, zh: zh) }
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
                                        Button { selectedEvent = event } label: { EventRow(event: event, zh: zh) }
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
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "日历" : "Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(zh ? "今天" : "Today") {
                        month = monthStart(.now)
                        selectedDate = schoolCalendar.startOfDay(for: .now)
                        Task { await load() }
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await load() } }
            }
            .sheet(item: $selectedEvent) { event in EventDetailSheet(event: event, zh: zh) }
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
                        let dayEvents = session.calendarEvents.filter { eventCovers($0, date: day) }
                        Button { selectDay(day) } label: {
                            VStack(spacing: 3) {
                                Text("\(schoolCalendar.component(.day, from: day))")
                                    .font(.subheadline.weight(schoolCalendar.isDate(day, inSameDayAs: selectedDate) ? .bold : .regular))
                                    .foregroundStyle(schoolCalendar.isDate(day, inSameDayAs: selectedDate) ? .white : MeroliColor.ink)
                                Circle().fill(dayEvents.isEmpty ? .clear : MeroliColor.gold).frame(width: 5, height: 5)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(schoolCalendar.isDate(day, inSameDayAs: selectedDate) ? MeroliColor.ink : .clear, in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(dateHeading(day) + (dayEvents.isEmpty ? "" : (zh ? "，有活动" : ", events")))
                        .accessibilityAddTraits(schoolCalendar.isDate(day, inSameDayAs: selectedDate) ? .isSelected : [])
                    } else {
                        Color.clear.frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(selectedWeek, id: \.timeIntervalSince1970) { day in
                    let dayEvents = session.calendarEvents.filter { eventCovers($0, date: day) }
                    Button { selectDay(day) } label: {
                        VStack(spacing: 4) {
                            Text(weekdayLabel(day))
                                .font(.caption2).foregroundStyle(MeroliColor.muted)
                            Text("\(schoolCalendar.component(.day, from: day))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(schoolCalendar.isDate(day, inSameDayAs: selectedDate) ? .white : MeroliColor.ink)
                            Circle().fill(dayEvents.isEmpty ? .clear : MeroliColor.gold).frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(schoolCalendar.isDate(day, inSameDayAs: selectedDate) ? MeroliColor.ink : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dateHeading(day) + (dayEvents.isEmpty ? "" : (zh ? "，有活动" : ", events")))
                    .accessibilityAddTraits(schoolCalendar.isDate(day, inSameDayAs: selectedDate) ? .isSelected : [])
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

    private func selectDay(_ day: Date) {
        selectedDate = schoolCalendar.startOfDay(for: day)
        let selectedMonth = monthStart(day)
        guard !schoolCalendar.isDate(selectedMonth, equalTo: month, toGranularity: .month) else { return }
        month = selectedMonth
        Task { await load() }
    }

    private func dateHeading(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.calendar = schoolCalendar
        formatter.timeZone = schoolCalendar.timeZone
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    private func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.calendar = schoolCalendar
        formatter.timeZone = schoolCalendar.timeZone
        formatter.dateFormat = "EEEEE"
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

    private static func priority(_ event: ParentEventDTO) -> Int {
        if event.parentRelevance.uppercased() == "ACTION_REQUIRED" || ["ACTION_REQUIRED", "DEADLINE"].contains(event.eventType.uppercased()) {
            return 0
        }
        let scheduleTypes: Set<String> = ["NO_SCHOOL", "PUPIL_FREE_DAY", "BREAK", "HOLIDAY", "MINIMUM_DAY", "LATE_START", "NO_LATE_START", "EARLY_RELEASE"]
        if scheduleTypes.contains(event.eventType.uppercased()) || (!event.scheduleAction.isEmpty && event.scheduleAction.uppercased() != "NONE") {
            return 1
        }
        return event.startTime == nil ? 3 : 2
    }
}

private struct EventRow: View {
    let event: ParentEventDTO
    let zh: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(event.parentRelevance == "ACTION_REQUIRED" ? MeroliColor.coral : MeroliColor.gold)
                .frame(width: 4)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(event.title).font(.headline).foregroundStyle(MeroliColor.ink).multilineTextAlignment(.leading)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.muted)
                }
                HStack(spacing: 6) {
                    if !event.allDay, let start = event.startTime { Text(String(start.prefix(5))) }
                    if !event.children.isEmpty {
                        Text(event.children.map { child in
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
                .foregroundStyle(MeroliColor.muted)
                if !event.action.isEmpty {
                    Text(event.action).font(.subheadline).foregroundStyle(MeroliColor.coral).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
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
        switch await session.loadCalendarEvent(id: event.id) {
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
                if let originalTitle = event.originalTitle, !originalTitle.isEmpty, originalTitle != event.title {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(zh ? "来源标题" : "Source title").font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.muted)
                        Text(originalTitle).font(.subheadline).foregroundStyle(MeroliColor.ink)
                    }
                }
                if !event.explanation.isEmpty { Text(event.explanation).font(.body).foregroundStyle(MeroliColor.ink) }
                if !event.action.isEmpty {
                    Label(event.action, systemImage: "checkmark.circle")
                        .font(.body.weight(.medium)).foregroundStyle(MeroliColor.coral)
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

private struct FamilyScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var showsAddChild = false
    @State private var editingChild: ChildDTO?
    @State private var managingSchoolChild: ChildDTO?
    @State private var managingScheduleChild: ChildDTO?
    @State private var viewingSchoolInfo: EnrollmentDTO?
    @State private var choosingNextSchool: SchoolYearTransitionDTO?
    private var zh: Bool { session.usesChinese }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Text(zh ? "学校" : "Schools")
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(MeroliColor.ink)
                        Spacer()
                        Button { Task { await session.loadFamily() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 40, height: 40)
                                .background(.white, in: Circle())
                        }
                        .accessibilityLabel(zh ? "刷新家庭" : "Refresh family")
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(zh ? "孩子的学校" : "Your schools")
                            .font(.system(.largeTitle, design: .serif, weight: .bold))
                            .foregroundStyle(MeroliColor.ink)
                        Text(session.family?.name?.isEmpty == false ? session.family!.name! : session.email)
                            .font(.subheadline)
                            .foregroundStyle(MeroliColor.muted)
                    }

                    if let error = session.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(MeroliColor.coral)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !session.schoolYearTransitions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(zh ? "下一学年安排" : "Next school year", systemImage: "arrow.forward.calendar")
                                .font(.headline)
                                .foregroundStyle(MeroliColor.ink)
                            ForEach(session.schoolYearTransitions) { transition in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(transition.childName)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(MeroliColor.ink)
                                            Text(transition.graduating
                                                 ? (zh ? "即将完成当前学校阶段 · \(transition.schoolName)" : "Finishing this school stage · \(transition.schoolName)")
                                                 : (zh ? "\(transition.schoolName) · \(transition.schoolYearLabel) 升至 \(transition.suggestedGradeCode.map(localizedGrade) ?? localizedGrade(transition.gradeCode))" : "\(transition.schoolName) · \(transition.schoolYearLabel) to grade \(transition.suggestedGradeCode ?? transition.gradeCode)"))
                                                .font(.caption)
                                                .foregroundStyle(MeroliColor.muted)
                                        }
                                        Spacer(minLength: 0)
                                        if let year = transition.targetSchoolYearLabel {
                                            Text(year).font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                        }
                                    }
                                    if transition.graduating {
                                        HStack {
                                            if transition.targetSchoolYearId != nil {
                                                Button(zh ? "选择下一所学校" : "Choose next school") {
                                                    choosingNextSchool = transition
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .tint(MeroliColor.ink)
                                            }
                                            Button(zh ? "暂不确定" : "Not sure yet") {
                                                Task { _ = await session.applySchoolYearTransition(childId: transition.childId, action: "not-sure") }
                                            }
                                            .buttonStyle(.bordered)
                                            if transition.finishedK12Available {
                                                Button(zh ? "已完成 K–12" : "Finished K–12") {
                                                    Task { _ = await session.applySchoolYearTransition(childId: transition.childId, action: "finished-k12") }
                                                }
                                                .buttonStyle(.bordered)
                                            }
                                        }
                                        .disabled(session.isSavingSchoolYearTransition || transition.transitionAvailable != true)
                                    } else if let targetYearId = transition.targetSchoolYearId, let grade = transition.suggestedGrade {
                                        Button {
                                            Task {
                                                _ = await session.applySchoolYearTransition(childId: transition.childId,
                                                    action: "confirm-grade", targetYearId: targetYearId, grade: grade)
                                            }
                                        } label: {
                                            Label(zh ? "确认升至\(transition.suggestedGradeCode.map(localizedGrade) ?? "下一")" : "Confirm grade \(transition.suggestedGradeCode ?? "")",
                                                systemImage: "checkmark.circle")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(MeroliColor.ink)
                                        .disabled(session.isSavingSchoolYearTransition || transition.transitionAvailable != true)
                                    }
                                    if transition.transitionAvailable != true {
                                        Text(zh
                                             ? "可在当前学年结束后（\(transition.transitionAvailableDate ?? "")）确认下一学年安排。"
                                             : "You can confirm next year after this school year ends (\(transition.transitionAvailableDate ?? "")).")
                                            .font(.caption)
                                            .foregroundStyle(MeroliColor.muted)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                            Text(zh ? "升年级后需要重新确认作息和课后项目。" : "Schedule and after-school programs need reconfirmation each school year.")
                                .font(.caption)
                                .foregroundStyle(MeroliColor.muted)
                        }
                        .padding(15)
                        .background(.white, in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(MeroliColor.line, lineWidth: 1))
                    }

                    HStack {
                        Text(zh ? "家庭成员" : "Children")
                            .font(.system(.title3, design: .serif, weight: .bold))
                            .foregroundStyle(MeroliColor.ink)
                        Spacer()
                        Text("\(session.children.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MeroliColor.muted)
                    }

                    if session.isLoadingFamily && session.children.isEmpty {
                        ProgressView(zh ? "正在读取家庭资料…" : "Loading family…")
                            .frame(maxWidth: .infinity, minHeight: 140)
                    } else if session.children.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(.title))
                                .foregroundStyle(MeroliColor.ink)
                            Text(zh ? "添加家庭成员" : "Add a child to your family")
                                .font(.headline)
                                .foregroundStyle(MeroliColor.ink)
                            Text(zh ? "创建孩子资料后，可以继续关联学校信息。" : "Create a child profile to start building your family's school information.")
                                .font(.subheadline)
                                .foregroundStyle(MeroliColor.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Button { showsAddChild = true } label: {
                                Label(zh ? "添加孩子" : "Add child", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 11)
                                    .foregroundStyle(.white)
                                    .background(MeroliColor.ink, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(MeroliColor.line, lineWidth: 1))
                    } else {
                        VStack(spacing: 11) {
                            ForEach(session.children) { child in
                                VStack(alignment: .leading, spacing: 0) {
                                    Button { editingChild = child } label: {
                                        HStack(spacing: 13) {
                                            Image(systemName: "person.fill")
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(MeroliColor.ink)
                                                .frame(width: 46, height: 46)
                                                .background(MeroliColor.paleGreen, in: Circle())
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(child.nickname)
                                                    .font(.headline)
                                                    .foregroundStyle(MeroliColor.ink)
                                                Text(zh ? "家庭成员 · 编辑称呼" : "Family member · Edit name")
                                                    .font(.caption)
                                                    .foregroundStyle(MeroliColor.muted)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(MeroliColor.muted)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("meroli.child.\(child.id)")

                                    Divider().overlay(MeroliColor.line).padding(.vertical, 12)

                                    Button { managingSchoolChild = child } label: {
                                        HStack(spacing: 9) {
                                            Image(systemName: "building.2")
                                                .foregroundStyle(MeroliColor.ink)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(displayedEnrollment(for: child)?.schoolName ?? (zh ? "尚未关联学校" : "No school linked yet"))
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(MeroliColor.ink)
                                                Text(displayedEnrollment(for: child).map {
                                                    $0.status == "AWAITING_NEXT_SCHOOL"
                                                        ? (zh ? "等待选择下一所学校 · \($0.schoolYearName) · \(localizedGrade($0.gradeCode))" : "Choose the next school · \($0.schoolYearName) · Grade \($0.gradeCode)")
                                                        : "\($0.schoolYearName) · \(localizedGrade($0.gradeCode))"
                                                } ?? (zh ? "添加孩子的学校与年级" : "Add this child’s school and grade"))
                                                    .font(.caption)
                                                    .foregroundStyle(MeroliColor.muted)
                                            }
                                            Spacer()
                                            Text(displayedEnrollment(for: child) == nil ? (zh ? "添加" : "Add") : (zh ? "管理" : "Manage"))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(MeroliColor.ink)
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(MeroliColor.muted)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(displayedEnrollment(for: child)?.status == "AWAITING_NEXT_SCHOOL")
                                    .accessibilityIdentifier("meroli.child.school.\(child.id)")

                                    if let enrollment = displayedEnrollment(for: child) {
                                        Button { viewingSchoolInfo = enrollment } label: {
                                            Label(zh ? "学校考勤与表现资料" : "Attendance and school information", systemImage: "building.2.crop.circle")
                                                .font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 11)
                                    }

                                    let previousEnrollments = historicalEnrollments(for: child)
                                    if !previousEnrollments.isEmpty {
                                        Divider().overlay(MeroliColor.line).padding(.vertical, 12)
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(zh ? "历史学校" : "Previous schools")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(MeroliColor.muted)
                                            ForEach(previousEnrollments) { enrollment in
                                                HStack(alignment: .top, spacing: 9) {
                                                    Image(systemName: "building.2.crop.circle")
                                                        .foregroundStyle(MeroliColor.muted)
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(enrollment.schoolName)
                                                            .font(.subheadline.weight(.medium))
                                                            .foregroundStyle(MeroliColor.ink)
                                                        Text("\(enrollment.schoolYearName) · \(localizedGrade(enrollment.gradeCode))")
                                                            .font(.caption)
                                                            .foregroundStyle(MeroliColor.muted)
                                                    }
                                                    Spacer(minLength: 0)
                                                }
                                            }
                                        }
                                    }

                                    if currentEnrollment(for: child) != nil {
                                        Divider().overlay(MeroliColor.line).padding(.vertical, 12)
                                        Button { managingScheduleChild = child } label: {
                                            HStack(spacing: 9) {
                                                Image(systemName: "clock.badge.checkmark").foregroundStyle(MeroliColor.ink)
                                                Text(zh ? "个性化作息与课后项目" : "Schedule and after-school programs")
                                                    .font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                                Spacer()
                                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.muted)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(14)
                                .background(.white, in: RoundedRectangle(cornerRadius: 15))
                                .overlay(RoundedRectangle(cornerRadius: 15).stroke(MeroliColor.line.opacity(0.75), lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(.horizontal, 19)
                .padding(.top, 13)
                .padding(.bottom, 28)
            }
            .background(MeroliColor.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await session.loadFamily() }
            .task { if session.family == nil { await session.loadFamily() } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsAddChild = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                        .accessibilityLabel(zh ? "添加孩子" : "Add child")
                }
            }
            .sheet(isPresented: $showsAddChild) { AddChildSheet() }
            .sheet(item: $editingChild) { child in RenameChildSheet(child: child) }
            .sheet(item: $managingSchoolChild) { child in
                EnrollmentEditorSheet(child: child, current: currentEnrollment(for: child))
            }
            .sheet(item: $managingScheduleChild) { child in
                if let enrollment = currentEnrollment(for: child) {
                    ScheduleProfileSheet(child: child, schoolId: enrollment.schoolId)
                }
            }
            .sheet(item: $viewingSchoolInfo) { enrollment in
                ParentSchoolOverviewSheet(schoolId: enrollment.schoolId, schoolName: enrollment.schoolName)
            }
            .sheet(item: $choosingNextSchool) { transition in
                NextSchoolTransitionSheet(transition: transition)
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

    private func localizedGrade(_ grade: String) -> String {
        guard zh else { return grade == "K" ? "Kindergarten" : grade }
        switch grade {
        case "PK": return "学前班"
        case "TK": return "过渡幼儿园"
        case "K": return "幼儿园"
        default: return "\(grade) 年级"
        }
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
    private var school: ParentSchoolDTO? { session.schools.first { $0.id == schoolId } }

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
                    Section(zh ? "课后项目（可选）" : "After-school programs (optional)") {
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
                        if let programs = await session.loadTransitionPrograms(schoolId: selected.id,
                            schoolYearId: transition.targetSchoolYearId), programs.isEmpty {
                            selectionStatus = "NONE"
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
        guard let grade = numericGrade(gradeCode), let yearId = transition.targetSchoolYearId else { return }
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
        guard zh else { return grade == "K" ? "Kindergarten" : grade }
        switch grade {
        case "PK": return "学前班"
        case "TK": return "过渡幼儿园"
        case "K": return "幼儿园"
        default: return "\(grade) 年级"
        }
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
                            if let children = overview.children, !children.isEmpty {
                                Divider().overlay(MeroliColor.line)
                                Text(zh ? "关联孩子" : "Following for")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                ForEach(children) { child in
                                    HStack {
                                        Text(child.childName).foregroundStyle(MeroliColor.ink)
                                        Spacer()
                                        Text(gradeLabel(child.gradeCode))
                                            .foregroundStyle(MeroliColor.muted)
                                        if let year = child.schoolYearName, !year.isEmpty {
                                            Text(year).foregroundStyle(MeroliColor.muted)
                                        }
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                        .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        if let schedules = overview.dailySchedules, !schedules.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(zh ? "今天的学校作息" : "Today’s school schedule")
                                    .font(.headline).foregroundStyle(MeroliColor.ink)
                                ForEach(schedules) { schedule in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(schedule.childName).font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                        Text(scheduleSummary(schedule))
                                            .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                    }
                                    if schedule.id != schedules.last?.id { Divider().overlay(MeroliColor.line) }
                                }
                            }
                            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        } else {
                            Text(zh ? "学校时间待确认" : "School schedule unavailable")
                                .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        }
                        if let bellSchedules = overview.bellSchedules, !bellSchedules.isEmpty {
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
                                Text(performance.availability == "LEGACY"
                                    ? (zh ? "旧版学校概览" : "Legacy school overview")
                                    : "\(performance.sourceName) · \(performance.reportingCycle)")
                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                                if performance.metrics.contains(where: { $0.officialColor != nil }) {
                                    performanceLegend()
                                }
                                ForEach(performance.metrics) { metric in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .top) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(metric.presentation?.parentLabel ?? metric.metricName)
                                                    .font(.subheadline.weight(.medium)).foregroundStyle(MeroliColor.ink)
                                                Text(performanceStatusLabel(metric.officialStatus))
                                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                                                if let definition = metric.presentation?.parentDefinition, !definition.isEmpty {
                                                    Text(definition).font(.caption).foregroundStyle(MeroliColor.muted)
                                                }
                                            }
                                            Spacer(minLength: 12)
                                            VStack(alignment: .trailing, spacing: 4) {
                                                if let level = metric.presentation?.performanceLevelLabel ?? performanceLevelLabel(metric.officialPerformanceLevel),
                                                   let colorName = performanceColorLabel(metric.officialColor),
                                                   let color = performanceColor(metric.officialColor) {
                                                    HStack(spacing: 5) {
                                                        Circle().fill(color).frame(width: 8, height: 8)
                                                        Text("\(colorName) · \(level)")
                                                            .font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                                    }
                                                } else if let level = metric.presentation?.performanceLevelLabel ?? performanceLevelLabel(metric.officialPerformanceLevel) {
                                                    Text(level).font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                                }
                                                Text(metric.presentation?.displayValue ?? displayableOfficialValue(metric))
                                                    .font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
                                            }
                                        }
                                        if let change = metric.presentation?.displayChange, !change.isEmpty {
                                            Text((zh ? "官方变化：" : "Official change: ") + change
                                                + (metric.presentation?.changeMeaning.map { " · \(performanceChangeLabel($0))" } ?? ""))
                                                .font(.caption).foregroundStyle(MeroliColor.muted)
                                        }
                                        if let presentation = metric.presentation {
                                            ForEach(presentation.comparisonValues) { value in
                                                HStack {
                                                    Text(value.label).foregroundStyle(MeroliColor.muted)
                                                    Spacer()
                                                    Text(value.value ?? "—").foregroundStyle(MeroliColor.ink)
                                                }
                                                .font(.caption)
                                            }
                                            if !presentation.comparisonValues.isEmpty,
                                               let summary = presentation.comparisonSummary, !summary.isEmpty {
                                                Text(summary).font(.caption2).foregroundStyle(MeroliColor.muted)
                                            }
                                            if let direction = presentation.directionExplanation, !direction.isEmpty {
                                                Text(direction).font(.caption2).foregroundStyle(MeroliColor.muted)
                                            }
                                        }
                                    }
                                    Divider().overlay(MeroliColor.line)
                                }
                                Text(performance.disclaimer).font(.caption).foregroundStyle(MeroliColor.muted)
                                if let url = externalWebURL(performance.sourceUrl) {
                                    Link(destination: url) { Label(zh ? "查看官方来源" : "View official source", systemImage: "arrow.up.right.square") }
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        }
                        if session.isLoadingSchoolPerformanceHistory {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text(zh ? "正在加载历年表现…" : "Loading performance history…")
                                    .font(.subheadline).foregroundStyle(MeroliColor.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(17)
                            .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        } else if let historyError = session.schoolPerformanceHistoryErrorMessage {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(zh ? "历年表现暂时无法加载" : "Performance history could not be loaded")
                                    .font(.headline).foregroundStyle(MeroliColor.ink)
                                Text(historyError)
                                    .font(.subheadline).foregroundStyle(MeroliColor.coral)
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
                        } else if let history = session.schoolPerformanceHistory,
                                  history.cycles.count > 1 || !history.metrics.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(zh ? "历年官方表现" : "Official performance history")
                                    .font(.system(.title3, design: .serif, weight: .bold)).foregroundStyle(MeroliColor.ink)
                                if history.cycles.contains(where: { cycle in cycle.metrics.contains(where: { $0.officialColor != nil }) }) {
                                    performanceLegend()
                                }
                                ForEach(history.cycles.dropFirst(), id: \.reportingCycle) { cycle in
                                    DisclosureGroup {
                                        VStack(alignment: .leading, spacing: 9) {
                                            ForEach(cycle.metrics) { metric in
                                                VStack(alignment: .leading, spacing: 5) {
                                                    HStack(alignment: .top) {
                                                        Text(metric.presentation?.parentLabel ?? metric.metricName)
                                                            .font(.caption).foregroundStyle(MeroliColor.ink)
                                                        Spacer(minLength: 12)
                                                        VStack(alignment: .trailing, spacing: 3) {
                                                            if let level = metric.presentation?.performanceLevelLabel ?? performanceLevelLabel(metric.officialPerformanceLevel),
                                                               let colorName = performanceColorLabel(metric.officialColor),
                                                               let color = performanceColor(metric.officialColor) {
                                                                HStack(spacing: 4) {
                                                                    Circle().fill(color).frame(width: 7, height: 7)
                                                                    Text("\(colorName) · \(level)")
                                                                        .font(.caption2.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                                                }
                                                            } else if let level = metric.presentation?.performanceLevelLabel ?? performanceLevelLabel(metric.officialPerformanceLevel) {
                                                                Text(level).font(.caption2.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                                            }
                                                            Text(metric.presentation?.shortValue ?? displayableOfficialValue(metric))
                                                                .font(.caption.weight(.semibold)).multilineTextAlignment(.trailing)
                                                        }
                                                    }
                                                    ForEach(metric.presentation?.comparisonValues.filter { $0.scope != "SCHOOL" } ?? []) { value in
                                                        HStack {
                                                            Text(value.label).foregroundStyle(MeroliColor.muted)
                                                            Spacer()
                                                            Text(value.value ?? "—").foregroundStyle(MeroliColor.ink)
                                                        }
                                                        .font(.caption2)
                                                    }
                                                }
                                            }
                                            Text(cycle.disclaimer).font(.caption2).foregroundStyle(MeroliColor.muted)
                                        }
                                        .padding(.top, 8)
                                    } label: {
                                        HStack {
                                            Text(cycle.academicYear).font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                            Spacer()
                                            Text(cycle.reportingCycle).font(.caption).foregroundStyle(MeroliColor.muted)
                                        }
                                    }
                                    .tint(MeroliColor.ink)
                                    Divider().overlay(MeroliColor.line)
                                }
                                if !history.metrics.isEmpty {
                                    Text(zh ? "趋势与可比性" : "Trends and comparability")
                                        .font(.headline).foregroundStyle(MeroliColor.ink)
                                        .padding(.top, 4)
                                    ForEach(history.metrics) { trend in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(performanceMetricLabel(trend.metricCode))
                                                .font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                            Text(trend.recentComparisonSummary ?? performanceTrendLabel(trend.trendState))
                                                .font(.caption).foregroundStyle(MeroliColor.muted)
                                            ForEach(trend.historyBreaks) { item in
                                                Label("\(item.afterCycle)–\(item.beforeCycle): \(item.label)", systemImage: "info.circle")
                                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                                            }
                                            ForEach(Array(trend.points.prefix(3))) { point in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack {
                                                        Text(point.reportingCycle).foregroundStyle(MeroliColor.muted)
                                                        Spacer()
                                                        Text(point.presentation?.shortValue ?? point.officialValue ?? performanceStatusLabel(point.officialStatus))
                                                            .foregroundStyle(MeroliColor.ink)
                                                    }
                                                    let comparisonValues = point.presentation?.comparisonValues.filter { $0.scope != "SCHOOL" } ?? []
                                                    if !comparisonValues.isEmpty {
                                                        HStack(spacing: 12) {
                                                            ForEach(comparisonValues) { value in
                                                                Text("\(value.label) · \(value.value ?? "—")")
                                                                    .foregroundStyle(MeroliColor.muted)
                                                            }
                                                        }
                                                    }
                                                }
                                                .font(.caption)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                        Divider().overlay(MeroliColor.line)
                                    }
                                }
                            }
                            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        } else if session.schoolPerformanceHistory != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(zh ? "历年官方表现" : "Official performance history")
                                    .font(.headline).foregroundStyle(MeroliColor.ink)
                                Text(zh ? "学校目前只有本报告周期的资料，尚无更多年度数据可供比较。" : "Only the current reporting cycle is available. There is not enough historical data to compare yet.")
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
            }
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
        "\(gradeLabel(gradeCode(minimum)))–\(gradeLabel(gradeCode(maximum)))"
    }

    private func gradeCode(_ grade: Int) -> String {
        switch grade {
        case -2: return "PK"
        case -1: return "TK"
        case 0: return "K"
        default: return String(grade)
        }
    }

    private func gradeLabel(_ grade: String) -> String {
        guard zh else { return grade == "K" ? "Kindergarten" : grade }
        switch grade {
        case "PK": return "学前班"
        case "TK": return "过渡幼儿园"
        case "K": return "幼儿园"
        default: return "\(grade) 年级"
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
                            Circle().fill(color).frame(width: 7, height: 7)
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
        case "VERY_HIGH": return zh ? "表现突出" : "Very high"
        case "HIGH": return zh ? "表现较好" : "High"
        case "MEDIUM": return zh ? "中等" : "Medium"
        case "LOW": return zh ? "需要关注" : "Low"
        case "VERY_LOW": return zh ? "表现较弱" : "Very low"
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
    private var selectedSchool: ParentSchoolDTO? { session.schools.first { $0.id == schoolId } }
    private var selectedYear: SchoolYearDTO? { session.schoolYears.first { $0.id == schoolYearId } }
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
                        let grades = session.schools.first(where: { $0.id == value })?.availableGrades ?? []
                        if !grades.contains(gradeCode) { gradeCode = grades.first ?? "" }
                        if value != current?.schoolId {
                            Task { await loadSchedulePrograms(for: value) }
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
                        ForEach(session.schoolYears) { year in Text(year.name).tag(year.id) }
                    }
                    .disabled(current != nil || session.isLoadingCatalog)
                    .onChange(of: schoolYearId) { _, _ in
                        guard current == nil, !schoolId.isEmpty else { return }
                        Task { await loadSchedulePrograms(for: schoolId) }
                    }

                    Picker(zh ? "年级" : "Grade", selection: $gradeCode) {
                        Text(zh ? "选择年级" : "Choose a grade").tag("")
                        ForEach(selectedSchool?.availableGrades ?? [], id: \.self) { grade in
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
                            Button(zh ? "移除此校关联" : "Remove this school") {
                                enrollmentAction = "remove"
                                confirmingEnrollmentAction = true
                            }
                            .foregroundStyle(MeroliColor.coral)
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
            .sheet(isPresented: $showsSchoolSearch, onDismiss: {
                guard !districtId.isEmpty else { return }
                Task { await session.loadSchools(districtId: districtId) }
            }) {
                SchoolSearchSheet(districtId: districtId, selectedSchoolId: schoolId) { selected in
                    schoolId = selected.id
                }
            }
            .confirmationDialog(zh ? "确认更新入学记录？" : "Update this enrollment?", isPresented: $confirmingEnrollmentAction, titleVisibility: .visible) {
                if enrollmentAction == "remove" && session.hasPendingSchoolRemoval(childId: child.id) {
                    Button(zh ? "检查移除状态" : "Check removal status") {
                        Task {
                            if await session.checkPendingSchoolRemoval(childId: child.id) {
                                dismiss()
                            }
                        }
                    }
                } else {
                    Button(enrollmentAction == "remove" ? (zh ? "移除关联" : "Remove school") : (zh ? "结束记录" : "Complete record"), role: .destructive) {
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
                     ? (zh ? "这会停止该学校的日历和作息关联，历史记录仍会保留。" : "This stops the school calendar and schedule association. The enrollment history remains.")
                     : (zh ? "这会将当前入学记录标记为已完成，历史记录仍会保留。" : "This marks the enrollment as completed and keeps it in history."))
            }
            .confirmationDialog(zh ? "确认更换学校？" : "Change school?", isPresented: $confirmingSchoolChange, titleVisibility: .visible) {
                Button(zh ? "更换学校并保留历史" : "Change school and keep history") { save() }
                Button(zh ? "取消" : "Cancel", role: .cancel) {}
            } message: {
                Text(zh ? "当前学校记录会结束并保留在历史中，新学校将关联到当前学年。" : "The current school record will be completed and kept in history. The new school will use the current school year.")
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
            schedulePrograms = []
            hasLoadedSchedulePrograms = false
            await session.restorePendingSchoolRemoval(childId: child.id)
            await session.restorePendingSchoolChange(childId: child.id)
        } else {
            districtId = session.districts.first?.id ?? ""
            schoolYearId = session.schoolYears.first?.id ?? ""
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
        selectionStatus = programs.isEmpty ? "NONE" : ""
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
        guard zh else { return grade == "K" ? "Kindergarten" : grade }
        switch grade {
        case "PK": return "学前班"
        case "TK": return "过渡幼儿园"
        case "K": return "幼儿园"
        default: return "\(grade) 年级"
        }
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
    @FocusState private var isFocused: Bool
    private var zh: Bool { session.usesChinese }
    private var selectedSchool: ParentSchoolDTO? { session.schools.first { $0.id == schoolId } }

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
                            if let programs = await session.loadTransitionPrograms(schoolId: value), programs.isEmpty {
                                selectionStatus = "NONE"
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
                if !schoolId.isEmpty && !session.transitionPrograms.isEmpty {
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
                    Button(action: save) {
                        HStack {
                            Spacer()
                            if session.isSavingChild { ProgressView().padding(.trailing, 7) }
                            Text(zh ? "创建孩子并保存学校资料" : "Create child and save school")
                            Spacer()
                        }
                        .foregroundStyle(.white)
                    }
                    .listRowBackground(MeroliColor.ink)
                    .disabled(session.isSavingChild || selectedSchool == nil || gradeCode.isEmpty
                        || !session.hasLoadedTransitionPrograms || selectionStatus.isEmpty
                        || (selectionStatus == "SELECTED" && selectedProgramIds.isEmpty))
                }
            }
            .scrollContentBackground(.hidden)
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "新建孩子资料" : "Add a child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "取消" : "Cancel") { dismiss() } } }
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
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        isFocused = false
        guard let school = selectedSchool else { return }
        Task {
            if await session.subscribeChild(
                nickname: nickname,
                school: school,
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
        guard zh else { return grade == "K" ? "Kindergarten" : grade }
        switch grade {
        case "PK": return "学前班"
        case "TK": return "过渡幼儿园"
        case "K": return "幼儿园"
        default: return "\(grade) 年级"
        }
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
    @State private var appleRawNonce: String?
    private var zh: Bool { session.usesChinese }

    var body: some View {
        NavigationStack {
            List {
                Section(zh ? "账户" : "Account") {
                    LabeledContent(zh ? "邮箱" : "Email", value: session.email)
                    if session.isAppleLinked {
                        Label(zh ? "已绑定 Apple 账号" : "Apple account linked", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(MeroliColor.ink)
                    } else {
                        MeroliAppleAuthorizationButton(
                            type: .continue,
                            title: zh ? "继续使用 Apple" : "Continue with Apple",
                            height: 44,
                            accessibilityIdentifier: "meroli.settings.bind-apple",
                            onRequest: { request in
                            let nonce = AppleNonce.generate()
                            appleRawNonce = nonce
                            request.nonce = AppleNonce.sha256(nonce)
                            request.requestedScopes = [.email]
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
                            Task { await session.bindApple(identityToken: token, rawNonce: nonce) }
                            }
                        )
                    }
                    if let family = session.family, !family.id.isEmpty {
                        LabeledContent(zh ? "家庭编号" : "Family ID", value: family.id)
                    }
                }
                Section(zh ? "语言" : "Language") {
                    Picker(zh ? "应用语言" : "App language", selection: Binding(
                        get: { session.language },
                        set: { value in Task { await session.setLanguage(value) } }
                    )) {
                        Text("English").tag("en")
                        Text("简体中文").tag("zh-CN")
                    }
                }
                if let error = session.errorMessage {
                    Section { Text(error).foregroundStyle(MeroliColor.coral).font(.subheadline) }
                }
                Section {
                    Button(role: .destructive) {
                        isLoggingOut = true
                        Task { await session.logout(); isLoggingOut = false }
                    } label: {
                        HStack {
                            Text(zh ? "退出登录" : "Sign out")
                            Spacer()
                            if isLoggingOut { ProgressView() }
                        }
                    }
                    .disabled(isLoggingOut)
                    .accessibilityIdentifier("meroli.settings.logout")
                }
                Section {
                    Button(role: .destructive) { showsDeleteAccount = true } label: {
                        Text(zh ? "删除账户" : "Delete account")
                    }
                    .accessibilityIdentifier("meroli.settings.delete-account")
                } footer: {
                    Text(zh ? "删除后你将无法再登录。独占家庭的孩子、入学和作息资料会一并删除；其他成员共享的家庭资料会保留。" : "You will no longer be able to sign in. Children, enrollments, and schedules in a family used only by you will be deleted. Shared family data will remain for other members.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "设置" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsDeleteAccount) { DeleteAccountSheet() }
        }
        .task { await session.loadAppleBinding() }
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
        ZStack {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                    .font(.body.weight(.medium))
                Text(title)
                    .font(.body.weight(.medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .background(.black, in: RoundedRectangle(cornerRadius: min(15, height / 3)))
            .accessibilityHidden(true)

            SignInWithAppleButton(type, onRequest: onRequest, onCompletion: onCompletion)
                .signInWithAppleButtonStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: height)
                .opacity(0.015)
                .accessibilityLabel(title)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .clipShape(RoundedRectangle(cornerRadius: min(15, height / 3)))
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
