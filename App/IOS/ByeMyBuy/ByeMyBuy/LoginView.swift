import AuthenticationServices
import CryptoKit
import SwiftUI

@MainActor
final class BmbAppleDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    var completion: ((ASAuthorizationAppleIDCredential) -> Void)?
    var failure: ((Error) -> Void)?
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow ?? UIWindow()
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential { completion?(credential) }
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) { failure?(error) }
}

struct LoginView: View {
    @EnvironmentObject private var session: BmbSession
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var usePassword = false
    @State private var busy = false
    @State private var codeSending = false
    @State private var error: String?
    @State private var appleNonce = ""
    @State private var appleDelegate: BmbAppleDelegate?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("BYEMYBUY").font(.caption.bold()).tracking(2)
                        .foregroundStyle(BmbTheme.lime)
                    Text("Good choices begin with a conversation.")
                        .font(.system(size: 36, weight: .black, design: .rounded)).tracking(-1.5)
                        .foregroundStyle(.white)
                    Text("“I would wait until next month.”").font(.subheadline.bold()).padding(13)
                        .foregroundStyle(.white)
                        .background(Color(red: 1, green: 0.447, blue: 0.353), in: RoundedRectangle(cornerRadius: 13))
                }
                .frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
                .padding(28).background(Color(red: 0.141, green: 0.22, blue: 0.176), in: RoundedRectangle(cornerRadius: 25))
                BmbCard {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Sign in").font(.title.bold())
                        Text("Keep every decision in one place.").font(.subheadline).foregroundStyle(BmbTheme.muted)
                        TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
                        if usePassword {
                            SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
                        } else {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let remaining = BmbEmailCodeCooldown.remaining(at: context.date)
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        TextField("Verification code", text: $code).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                        Button(codeSending ? String(localized: "Sending…") : remaining > 0 ? String(format: NSLocalizedString("Resend in %ds", comment: ""), remaining) : String(localized: "Send code")) {
                                            Task { await sendCode() }
                                        }
                                        .font(.caption.bold())
                                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || codeSending || remaining > 0)
                                    }
                                    if remaining > 0 {
                                        Text("Code sent. Check your inbox and enter it here.")
                                            .font(.caption).foregroundStyle(BmbTheme.muted)
                                    }
                                }
                            }
                        }
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        BmbPrimaryButton(title: "Continue") { Task { await login() } }.disabled(busy)
                        Button(usePassword ? "Use an email code" : "Sign in with password") { usePassword.toggle() }
                            .font(.caption.bold()).foregroundStyle(.green)
                        Divider()
                        Button { Task { await signInWithApple() } } label: {
                            HStack { Image(systemName: "apple.logo"); Text("Continue with Apple") }
                                .frame(maxWidth: .infinity).padding(15).background(BmbTheme.ink, in: RoundedRectangle(cornerRadius: 13))
                                .foregroundStyle(.white)
                        }.disabled(busy)
                    }
                }
            }.padding(20)
        }
        .background(BmbTheme.paper)
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
    }

    private func sendCode() async {
        guard !codeSending, BmbEmailCodeCooldown.remaining(at: .now) == 0 else { return }
        codeSending = true
        defer { codeSending = false }
        do { try await session.sendCode(email); BmbEmailCodeCooldown.recordSend(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func login() async {
        busy = true; defer { busy = false }
        do {
            if usePassword { try await session.login(email: email, password: password) }
            else { try await session.login(email: email, code: code) }
            session.showLogin = false; dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func signInWithApple() async {
        busy = true
        do {
            appleNonce = try await session.appleNonce()
            let hashed = SHA256.hash(data: Data(appleNonce.utf8)).map { String(format: "%02x", $0) }.joined()
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashed
            let coordinator = BmbAppleDelegate()
            coordinator.completion = { credential in
                Task { @MainActor in
                    guard let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                        self.error = "Apple identity token is missing."; self.busy = false; return
                    }
                    let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
                    do {
                        try await session.loginApple(identityToken: token, nonce: appleNonce, name: name)
                        session.showLogin = false; dismiss()
                    } catch { self.error = error.localizedDescription }
                    self.busy = false
                }
            }
            coordinator.failure = { error in self.error = error.localizedDescription; self.busy = false }
            appleDelegate = coordinator
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator
            controller.performRequests()
        } catch { self.error = error.localizedDescription; busy = false }
    }
}
