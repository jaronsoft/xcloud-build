import SwiftUI
import AuthenticationServices
import CryptoKit

struct AccountView: View {
    @EnvironmentObject private var session: BmbSession
    @AppStorage("bmb.theme") private var themePreference = "system"
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var appleDelegate: BmbAppleDelegate?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("YOUR PROFILE").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                Text("Account").font(.system(size: 35, weight: .black, design: .rounded))
                Picker("Appearance", selection: $themePreference) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }.pickerStyle(.segmented)
                if session.isLoggedIn {
                    BmbCard {
                        VStack(alignment: .leading, spacing: 15) {
                            Text(session.profile?.DisplayName ?? "Friend").font(.headline)
                            Text(session.profile?.Email ?? session.profile?.Phone ?? "—").font(.caption).foregroundStyle(BmbTheme.muted)
                            Divider()
                            Text("Verify and bind email").font(.headline)
                            TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
                            HStack {
                                TextField("Code", text: $code).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                Button("Send code") { Task { await sendCode() } }.font(.caption.bold())
                            }
                            Button("Bind email") { Task { await bindEmail() } }.font(.subheadline.bold())
                            Divider()
                            Button("Link Apple account") { Task { await bindApple() } }.font(.subheadline.bold())
                            Divider()
                            SecureField("Set password", text: $password).textFieldStyle(.roundedBorder)
                            Button("Set password") { Task { await setPassword() } }.font(.subheadline.bold())
                            if let message { Text(message).font(.caption).foregroundStyle(.green) }
                            Divider()
                            Button("Sign out") { session.logout() }.font(.subheadline)
                            Button("Delete account", role: .destructive) { confirmDelete = true }.font(.subheadline)
                        }
                    }
                } else {
                    BmbCard { VStack(alignment: .leading, spacing: 18) {
                        Text("Sign in to keep every decision in one place.")
                        BmbPrimaryButton(title: "Sign in") { session.showLogin = true }
                    } }
                }
            }.padding(20)
        }
        .background(BmbTheme.paper)
        .navigationBarHidden(true)
        .task(id: session.token) { await session.loadProfile() }
        .confirmationDialog("Delete your account and its content?", isPresented: $confirmDelete) {
            Button("Delete account", role: .destructive) { Task { await delete() } }
        }
    }
    private func sendCode() async {
        do { try await session.sendCode(email); message = String(localized: "Code sent") }
        catch { message = error.localizedDescription }
    }
    private func bindEmail() async {
        guard let token = session.token else { return }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/auth/bind-email", method: "POST", body: ["Email": email, "Code": code], token: token)
            await session.loadProfile(); message = String(localized: "Email bound")
        } catch { message = error.localizedDescription }
    }
    private func setPassword() async {
        guard let token = session.token else { return }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/auth/set-password", method: "POST", body: ["Password": password], token: token)
            password = ""; message = String(localized: "Password set")
        } catch { message = error.localizedDescription }
    }
    private func bindApple() async {
        guard let token = session.token else { return }
        do {
            let nonce = try await session.appleNonce()
            let hash = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hash
            let coordinator = BmbAppleDelegate()
            coordinator.completion = { credential in
                Task { @MainActor in
                    guard let data = credential.identityToken, let identityToken = String(data: data, encoding: .utf8) else {
                        message = "Apple identity token is missing."; return
                    }
                    do {
                        let _: BmbAcknowledgement = try await session.api.call("/auth/bind-apple", method: "POST", body: ["IdentityToken": identityToken, "Nonce": nonce], token: token)
                        message = String(localized: "Apple account linked")
                    } catch { message = error.localizedDescription }
                }
            }
            coordinator.failure = { error in message = error.localizedDescription }
            appleDelegate = coordinator
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator
            controller.performRequests()
        } catch { message = error.localizedDescription }
    }
    private func delete() async {
        do { try await session.deleteAccount() }
        catch { message = error.localizedDescription }
    }
}
