import SwiftUI

struct LoginView: View {
    let session: SessionStore
    let tenants: TenantStore

    @State private var account = ""
    @State private var password = ""
    @State private var captcha = ""
    @State private var keepLogin = true
    @State private var showsInvite = false
    @State private var showsRegistration = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 40)
                    AIKBrandMark(size: 92)

                    VStack(spacing: 8) {
                        Text("login.title")
                            .font(.largeTitle.bold())
                        Text("login.subtitle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 16) {
                        TextField("login.account", text: $account)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(AIKTheme.surface, in: .rect(cornerRadius: 14))

                        SecureField("login.password", text: $password)
                            .textContentType(.password)
                            .padding()
                            .background(AIKTheme.surface, in: .rect(cornerRadius: 14))

                        Toggle("login.keep", isOn: $keepLogin)
                            .font(.subheadline)

                        if session.requiresCaptcha {
                            captchaInput
                        }

                        if let error = session.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task {
                                await session.login(
                                    account: account,
                                    password: password,
                                    keepLogin: keepLogin,
                                    captcha: captcha
                                )
                                if session.mode == .system {
                                    tenants.switchTenant()
                                    await tenants.loadTenants(
                                        session: session,
                                        selectsDefaultTenant: true
                                    )
                                } else {
                                    password = ""
                                    captcha = ""
                                }
                            }
                        } label: {
                            HStack {
                                if session.isWorking {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("login.action")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 14))
                        .disabled(session.isWorking)

                        Button("login.invite") {
                            showsInvite = true
                        }
                        .buttonStyle(.borderless)

                        Button("registration.open") {
                            showsRegistration = true
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(maxWidth: 430)

                    Text("login.help")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    Link(destination: AppEnvironment.privacyURL) {
                        Label("privacy.policy", systemImage: "hand.raised")
                            .font(.footnote)
                    }
                    .accessibilityLabel("privacy.policy")

                    Text(AppEnvironment.releaseLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 24)
            }
            .background {
                ZStack {
                    AIKTheme.background
                    Circle()
                        .fill(AIKTheme.accent.opacity(0.12))
                        .frame(width: 340)
                        .blur(radius: 80)
                        .offset(x: -180, y: -300)
                    Circle()
                        .fill(AIKTheme.secondary.opacity(0.1))
                        .frame(width: 360)
                        .blur(radius: 90)
                        .offset(x: 190, y: 330)
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showsInvite) {
            InviteAccessView(session: session, tenants: tenants)
        }
        .sheet(isPresented: $showsRegistration) {
            KnowledgeRegistrationView()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .aikOpenInvite)
        ) { _ in
            showsInvite = true
        }
    }

    private var captchaInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField("login.captcha", text: $captcha)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .padding()
                    .background(AIKTheme.surface, in: .rect(cornerRadius: 14))

                Button {
                    Task {
                        captcha = ""
                        await session.refreshCaptcha()
                    }
                } label: {
                    Group {
                        if session.isLoadingCaptcha {
                            ProgressView()
                        } else if let image = session.captchaImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.title2)
                        }
                    }
                    .frame(width: 112, height: 48)
                    .background(AIKTheme.surface, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("login.captcha_refresh")
            }

            if let error = session.captchaErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("login.captcha_hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
