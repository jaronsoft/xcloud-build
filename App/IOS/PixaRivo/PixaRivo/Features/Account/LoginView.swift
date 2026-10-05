import AuthenticationServices
import SwiftUI

struct LoginView: View {
    var startsWithRegistration = false
    private enum LoginMethod: String, CaseIterable {
        case password
        case code
    }

    private enum FocusedField {
        case email
        case password
        case code
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(PixaReferralAttributionStore.self) private var referralAttribution
    @Environment(PixaNavigationStore.self) private var navigation
    @State private var loginMethod = LoginMethod.password
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var countdown = 0
    @State private var noticeMessage: String?
    @State private var rawAppleNonce: String?
    @FocusState private var focusedField: FocusedField?
    @State private var showsRegistration = false

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSendCode: Bool {
        trimmedEmail.contains("@") && countdown == 0 && !session.isWorking
    }

    private var canSubmit: Bool {
        guard trimmedEmail.contains("@"), !session.isWorking else { return false }
        return loginMethod == .password ? password.nilIfEmpty != nil : code.count == 6
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    authenticationHeader
                    loginForm
                    NavigationLink {
                        RegisterView { dismiss() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("auth.no_account")
                                .foregroundStyle(.secondary)
                            Text("auth.create_account")
                                .fontWeight(.bold)
                                .foregroundStyle(PixaTheme.accent)
                            Image(systemName: "arrow.right")
                                .font(.caption.bold())
                                .foregroundStyle(PixaTheme.accent)
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PixaTheme.paper.ignoresSafeArea())
            .navigationTitle("auth.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        focusedField = nil
                    } label: {
                        Label(
                            "common.dismiss_keyboard",
                            systemImage: "keyboard.chevron.compact.down"
                        )
                    }
                }
            }
            .onChange(of: loginMethod) { _, _ in
                session.errorMessage = nil
                noticeMessage = nil
                focusedField = loginMethod == .password ? .password : .code
            }
            .navigationDestination(isPresented: $showsRegistration) {
                RegisterView { dismiss() }
            }
            .onAppear {
                guard startsWithRegistration || navigation.opensReferralRegistration else { return }
                navigation.opensReferralRegistration = false
                showsRegistration = true
            }
        }
    }

    private var authenticationHeader: some View {
        VStack(spacing: 14) {
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 74, height: 74)
            Text("startup.brand")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
            Text("auth.login_subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var loginForm: some View {
        VStack(spacing: 14) {
            Picker("auth.login_method", selection: $loginMethod) {
                Text("auth.password_login").tag(LoginMethod.password)
                Text("auth.code_login").tag(LoginMethod.code)
            }
            .pickerStyle(.segmented)

            TextField("auth.email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .email)
                .onSubmit {
                    focusedField = loginMethod == .password ? .password : .code
                }
                .pixaAuthField()

            if loginMethod == .code {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        TextField("auth.code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .code)
                            .onChange(of: code) { _, value in
                                code = String(value.filter(\.isNumber).prefix(6))
                            }
                            .pixaAuthField()
                        Button { Task { await sendCode() } } label: {
                            Text(countdown > 0 ? "\(countdown)s" : AppLanguage.localized("auth.send_code"))
                                .font(.caption.bold())
                                .lineLimit(1)
                                .frame(minWidth: 92)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(PixaTheme.accent)
                        .disabled(!canSendCode)
                    }
                    Label("auth.email_code_hint", systemImage: "envelope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("auth.email_code_auto_register_hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 3) {
                        Text("auth.register_agreement")
                        Link("account.terms", destination: AppConfiguration.termsURL)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                SecureField("auth.password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        focusedField = nil
                        if canSubmit { Task { await submit() } }
                    }
                    .pixaAuthField()
            }

            AuthenticationMessageView(
                noticeMessage: noticeMessage,
                errorMessage: session.errorMessage
            )

            Button { Task { await submit() } } label: {
                Group {
                    if session.isWorking { ProgressView().tint(.white) }
                    else { Text("auth.login") }
                }
                .pixaPrimaryButton(isEnabled: canSubmit)
            }
            .disabled(!canSubmit)

            HStack(spacing: 12) {
                Rectangle().fill(.secondary.opacity(0.22)).frame(height: 1)
                Text("auth.or")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Rectangle().fill(.secondary.opacity(0.22)).frame(height: 1)
            }

            SignInWithAppleButton(.signIn) { request in
                let nonce = SessionStore.makeNonce()
                rawAppleNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = SessionStore.sha256(nonce)
            } onCompletion: { result in
                handleAppleResult(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(session.isWorking)

            Text("auth.apple.helper")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18))
    }

    private func sendCode() async {
        guard canSendCode else { return }
        let succeeded = await session.sendEmailCode(email: trimmedEmail, purpose: "login")
        guard succeeded else { return }
        noticeMessage = AppLanguage.localized("auth.code_sent")
        countdown = 60
        Task { @MainActor in
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                countdown -= 1
            }
        }
    }

    private func submit() async {
        let succeeded = loginMethod == .code
            ? await session.signInWithCode(
                email: trimmedEmail,
                code: code,
                inviteAttribution: referralAttribution.validPending()
            )
            : await session.signIn(email: trimmedEmail, password: password)
        if succeeded {
            referralAttribution.clear()
            dismiss()
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let rawAppleNonce else {
                session.errorMessage = AppLanguage.localized("auth.apple.expired")
                return
            }
            Task {
                let succeeded = await session.signInWithApple(
                    credential: credential,
                    rawNonce: rawAppleNonce,
                    inviteAttribution: referralAttribution.validPending()
                )
                if succeeded {
                    referralAttribution.clear()
                    dismiss()
                }
            }
        case let .failure(error):
            rawAppleNonce = nil
            session.errorMessage = PixaAppleAuthorizationErrorPresenter.message(for: error)
        }
    }
}

struct AuthenticationMessageView: View {
    let noticeMessage: String?
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            if let noticeMessage {
                messageCard(
                    noticeMessage,
                    icon: "checkmark.circle.fill",
                    color: .green
                )
            }
            if let errorMessage {
                messageCard(
                    errorMessage,
                    icon: "exclamationmark.triangle.fill",
                    color: .red
                )
            }
        }
    }

    private func messageCard(_ message: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .padding(.top, 1)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundStyle(color)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.14))
        }
    }
}

extension View {
    func pixaAuthField() -> some View {
        padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}
