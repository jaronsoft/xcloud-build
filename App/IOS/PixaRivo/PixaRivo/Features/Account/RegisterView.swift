import AuthenticationServices
import SwiftUI
import UniformTypeIdentifiers

struct RegisterView: View {
    let onAuthenticated: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(PixaReferralAttributionStore.self) private var referralAttribution
    @State private var email = ""
    @State private var code = ""
    @State private var nickname = ""
    @State private var country = Locale.current.region?.identifier == "CN" ? "CN" : "US"
    @State private var mobile = ""
    @State private var inviteCode = ""
    @State private var countdown = 0
    @State private var noticeMessage: String?
    @State private var rawAppleNonce: String?

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSendCode: Bool {
        trimmedEmail.contains("@") && countdown == 0 && !session.isWorking
    }

    private var canSubmit: Bool {
        trimmedEmail.contains("@")
            && nickname.nilIfEmpty != nil
            && code.count == 6
            && !session.isWorking
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(PixaTheme.accent)
                    Text("auth.register_heading")
                        .font(.title2.bold())
                    Text("auth.register_subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    TextField("auth.nickname", text: $nickname)
                        .textContentType(.nickname)
                        .pixaAuthField()

                    TextField("auth.email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .pixaAuthField()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            TextField("auth.code", text: $code)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
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
                    }

                    HStack(spacing: 10) {
                        Picker("auth.country", selection: $country) {
                            Text("auth.country.cn").tag("CN")
                            Text("auth.country.us").tag("US")
                            Text("auth.country.gb").tag("GB")
                            Text("auth.country.de").tag("DE")
                            Text("auth.country.jp").tag("JP")
                            Text("auth.country.other").tag("OTHER")
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))

                        TextField("auth.mobile", text: $mobile)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .pixaAuthField()
                    }

                    HStack(spacing: 10) {
                        TextField("auth.invite_code", text: $inviteCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: inviteCode) { _, value in
                                inviteCode = PixaReferralAttributionStore.normalize(value)
                            }
                            .pixaAuthField()
                        PasteButton(payloadType: String.self) { values in
                            guard let value = values.first else { return }
                            let normalized = PixaReferralAttributionStore.normalize(value)
                            if PixaReferralAttributionStore.isValidInviteCode(normalized) {
                                inviteCode = normalized
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.roundedRectangle)
                        .tint(PixaTheme.accent)
                        .accessibilityLabel(Text("auth.invite_paste"))
                    }

                    HStack(spacing: 3) {
                        Text("auth.register_agreement")
                        Link("account.terms", destination: AppConfiguration.termsURL)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    AuthenticationMessageView(
                        noticeMessage: noticeMessage,
                        errorMessage: session.errorMessage
                    )

                    Button { Task { await submit() } } label: {
                        Group {
                            if session.isWorking { ProgressView().tint(.white) }
                            else { Text("auth.register_submit") }
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

                    SignInWithAppleButton(.signUp) { request in
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

                    Text("auth.apple.register_helper")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PixaTheme.paper.ignoresSafeArea())
        .navigationTitle("auth.register")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            session.errorMessage = nil
            noticeMessage = nil
            if inviteCode.isEmpty, let pending = referralAttribution.validPending() {
                inviteCode = pending.inviteCode
            }
        }
    }

    private func sendCode() async {
        guard canSendCode else { return }
        let succeeded = await session.sendEmailCode(email: trimmedEmail, purpose: "register")
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
        let succeeded = await session.register(
            email: trimmedEmail,
            code: code,
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            country: country,
            mobile: mobile,
            inviteCode: inviteCode,
            inviteAttribution: referralAttribution.attribution(matching: inviteCode)
        )
        if succeeded {
            referralAttribution.clear()
            onAuthenticated()
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
                    inviteAttribution: referralAttribution.attribution(matching: inviteCode)
                )
                if succeeded {
                    referralAttribution.clear()
                    onAuthenticated()
                }
            }
        case let .failure(error):
            rawAppleNonce = nil
            session.errorMessage = PixaAppleAuthorizationErrorPresenter.message(for: error)
        }
    }
}
