import AuthenticationServices
import SwiftUI

struct LoginView: View {
    private enum AuthMode {
        case login
        case register
    }

    private enum LoginMethod {
        case password
        case code
    }

    private enum Field {
        case email
        case password
        case code
        case nickname
        case mobile
        case inviteCode
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var session
    @FocusState private var focusedField: Field?

    @State private var mode: AuthMode = .login
    @State private var loginMethod: LoginMethod = .password

    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var nickname = ""
    @State private var country = "CN"
    @State private var mobile = ""
    @State private var inviteCode = ""

    @State private var showsPassword = false
    @State private var rawNonce: String?
    @State private var countdown = 0
    @State private var isSendingCode = false

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSendCode: Bool {
        trimmedEmail.contains("@") && countdown == 0 && !isSendingCode
    }

    private var canSubmit: Bool {
        guard !trimmedEmail.isEmpty, !session.isWorking else { return false }
        if mode == .login {
            if loginMethod == .password {
                return !password.isEmpty
            } else {
                return code.trimmingCharacters(in: .whitespacesAndNewlines).count == 6
            }
        } else {
            return code.trimmingCharacters(in: .whitespacesAndNewlines).count == 6
                && !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    modePicker

                    if let errorMessage = session.errorMessage {
                        errorBanner(message: errorMessage)
                    }

                    emailSignInSection
                    methodDivider
                    socialSignInSection
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background {
                AISPageBackground()
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                session.errorMessage = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        focusedField = nil
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("common.done") {
                        focusedField = nil
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .shadow(
                    color: AISTheme.accent.opacity(0.12),
                    radius: 12,
                    y: 6
                )

            VStack(spacing: 5) {
                Text(mode == .login ? "auth.title" : "auth.tab.register")
                    .font(.system(.title2, design: .rounded, weight: .bold))

                Text("auth.required")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var modePicker: some View {
        Picker("Auth Mode", selection: $mode) {
            Text("auth.tab.login").tag(AuthMode.login)
            Text("auth.tab.register").tag(AuthMode.register)
        }
        .pickerStyle(.segmented)
        .onChange(of: mode) { _, _ in
            session.errorMessage = nil
        }
    }

    private var emailSignInSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if mode == .login {
                HStack(spacing: 0) {
                    Button {
                        loginMethod = .password
                    } label: {
                        VStack(spacing: 6) {
                            Text("auth.method.password")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(loginMethod == .password ? AISTheme.accent : .secondary)
                            Rectangle()
                                .fill(loginMethod == .password ? AISTheme.accent : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    Button {
                        loginMethod = .code
                    } label: {
                        VStack(spacing: 6) {
                            Text("auth.method.code")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(loginMethod == .code ? AISTheme.accent : .secondary)
                            Rectangle()
                                .fill(loginMethod == .code ? AISTheme.accent : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 4)
            }

            VStack(alignment: .leading, spacing: 14) {
                if mode == .register {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            inputLabel("auth.nickname", systemImage: "person")
                            TextField("auth.nickname.placeholder", text: $nickname)
                                .focused($focusedField, equals: .nickname)
                                .modifier(LoginFieldStyle(isFocused: focusedField == .nickname))
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            inputLabel("auth.country", systemImage: "globe")
                            Picker("Country", selection: $country) {
                                Text("中国 / China").tag("CN")
                                Text("美国 / United States").tag("US")
                                Text("英国 / United Kingdom").tag("GB")
                                Text("德国 / Germany").tag("DE")
                                Text("日本 / Japan").tag("JP")
                                Text("其他 / Other").tag("OTHER")
                            }
                            .pickerStyle(.menu)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(
                                Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    inputLabel("auth.email", systemImage: "envelope")
                    TextField("auth.email.placeholder", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .email)
                        .foregroundStyle(.primary)
                        .tint(AISTheme.accent)
                        .modifier(LoginFieldStyle(isFocused: focusedField == .email))
                }

                if mode == .register {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            inputLabel("auth.mobile", systemImage: "phone")
                            TextField("auth.mobile", text: $mobile)
                                .keyboardType(.phonePad)
                                .focused($focusedField, equals: .mobile)
                                .modifier(LoginFieldStyle(isFocused: focusedField == .mobile))
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            inputLabel("auth.invite_code", systemImage: "ticket")
                            TextField("auth.invite_code", text: $inviteCode)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .inviteCode)
                                .modifier(LoginFieldStyle(isFocused: focusedField == .inviteCode))
                        }
                    }
                }

                if mode == .login && loginMethod == .password {
                    VStack(alignment: .leading, spacing: 5) {
                        inputLabel("auth.password", systemImage: "lock")
                        HStack(spacing: 8) {
                            Group {
                                if showsPassword {
                                    TextField("auth.password.placeholder", text: $password)
                                } else {
                                    SecureField("auth.password.placeholder", text: $password)
                                }
                            }
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($focusedField, equals: .password)
                            .onSubmit {
                                submitForm()
                            }

                            Button {
                                showsPassword.toggle()
                            } label: {
                                Image(systemName: showsPassword ? "eye.slash" : "eye")
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .modifier(LoginFieldStyle(isFocused: focusedField == .password))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        inputLabel("auth.code", systemImage: "checkmark.shield")
                        HStack(spacing: 10) {
                            TextField("auth.code.placeholder", text: $code)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .code)
                                .modifier(LoginFieldStyle(isFocused: focusedField == .code))

                            Button {
                                sendCode()
                            } label: {
                                Text(countdown > 0 ? "\(countdown)s" : String(localized: "auth.send_code"))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(canSendCode ? AISTheme.accent : Color.secondary)
                                    .padding(.horizontal, 14)
                                    .frame(height: 50)
                                    .background(
                                        canSendCode ? AISTheme.accent.opacity(0.12) : Color(uiColor: .tertiarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    )
                            }
                            .disabled(!canSendCode)
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button {
                submitForm()
            } label: {
                HStack(spacing: 9) {
                    if session.isWorking {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(
                        session.isWorking
                            ? String(localized: "auth.loading")
                            : mode == .register
                            ? String(localized: "auth.register.submit")
                            : String(localized: "auth.password.signin")
                    )
                    .fontWeight(.semibold)
                }
                .aisPrimaryButton(isEnabled: canSubmit)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)

            switchModeButton
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private var socialSignInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SignInWithAppleButton(.signIn) { request in
                let nonce = SessionStore.makeNonce()
                rawNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = SessionStore.sha256(nonce)
            } onCompletion: { result in
                handleAppleResult(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(session.isWorking)

            Text("auth.apple.helper")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                unavailableProvider("auth.wechat", symbol: "message.fill")
                unavailableProvider("auth.alipay", symbol: "a.circle.fill")
                unavailableProvider("auth.google", symbol: "g.circle.fill")
            }
        }
        .padding(14)
        .aisSurface(cornerRadius: 22, hasShadow: true)
    }

    private var switchModeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                mode = (mode == .login ? .register : .login)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                Text(mode == .login ? "auth.to_register" : "auth.to_login")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(AISTheme.accent)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var methodDivider: some View {
        HStack(spacing: 12) {
            Divider()
            Text("auth.social.divider")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            Divider()
        }
        .accessibilityElement(children: .combine)
    }

    private func unavailableProvider(
        _ title: LocalizedStringKey,
        symbol: String
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.title3)
            Text(title)
                .font(.caption2)
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(
            Color(uiColor: .tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 13)
        )
        .accessibilityElement(children: .combine)
    }

    private func inputLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("auth.error.title")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.35), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
    }

    private func sendCode() {
        guard canSendCode else { return }
        isSendingCode = true
        Task {
            let purpose = (mode == .register ? "register" : "login")
            let ok = await session.sendEmailCode(email: trimmedEmail, purpose: purpose)
            isSendingCode = false
            if ok {
                countdown = 60
                startCountdownTask()
            }
        }
    }

    private func startCountdownTask() {
        Task { @MainActor in
            while countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                countdown -= 1
            }
        }
    }

    private func submitForm() {
        guard canSubmit else { return }
        focusedField = nil
        Task {
            if mode == .login {
                if loginMethod == .password {
                    await session.signIn(
                        email: trimmedEmail,
                        password: password
                    )
                } else {
                    await session.signInWithCode(
                        email: trimmedEmail,
                        code: code.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            } else {
                await session.register(
                    email: trimmedEmail,
                    code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                    nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                    country: country,
                    mobile: mobile.trimmingCharacters(in: .whitespacesAndNewlines),
                    inviteCode: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            closeAfterSuccess()
        }
    }

    private func handleAppleResult(
        _ result: Result<ASAuthorization, any Error>
    ) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential
                as? ASAuthorizationAppleIDCredential,
                  let rawNonce else {
                session.errorMessage = String(localized: "auth.apple.expired")
                return
            }
            Task {
                await session.signInWithApple(
                    credential: credential,
                    rawNonce: rawNonce
                )
                closeAfterSuccess()
            }
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private func closeAfterSuccess() {
        if session.isAuthenticated {
            dismiss()
        }
    }
}

private struct LoginFieldStyle: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        isFocused
                            ? AISTheme.accent
                            : Color.secondary.opacity(0.18),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            }
    }
}

#Preview("LoginView") {
    LoginView()
}
