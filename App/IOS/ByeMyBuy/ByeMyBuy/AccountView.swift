import SwiftUI
import AuthenticationServices
import CryptoKit
import PhotosUI
import UIKit

struct AccountView: View {
    @EnvironmentObject private var session: BmbSession
    @AppStorage("bmb.theme") private var themePreference = "system"
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var codeSending = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var appleDelegate: BmbAppleDelegate?
    @State private var displayName = ""
    @State private var preferredCurrency = BmbCurrency.defaultCode
    @State private var selectedAvatar: PhotosPickerItem?
    @State private var profileSaving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("YOUR PROFILE").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                        Text("Account").font(.system(size: 31, weight: .black, design: .rounded))
                    }
                    Spacer()
                    Menu {
                        Button { themePreference = "system" } label: {
                            Label("System", systemImage: themePreference == "system" ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                        }
                        Button { themePreference = "light" } label: {
                            Label("Light", systemImage: themePreference == "light" ? "checkmark.circle.fill" : "sun.max")
                        }
                        Button { themePreference = "dark" } label: {
                            Label("Dark", systemImage: themePreference == "dark" ? "checkmark.circle.fill" : "moon")
                        }
                    } label: {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(BmbTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(BmbTheme.card, in: Circle())
                    }
                    .accessibilityLabel("Appearance")
                }
                if session.isLoggedIn {
                    BmbCard {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack(spacing: 14) {
                                Group {
                                    if let avatarUrl = session.profile?.AvatarUrl, let url = URL(string: avatarUrl) {
                                        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Circle().fill(.green.opacity(0.15)) }
                                    } else {
                                        Text(String((session.profile?.DisplayName ?? "F").prefix(1))).font(.title.bold()).frame(maxWidth: .infinity, maxHeight: .infinity).background(.green.opacity(0.15))
                                    }
                                }.frame(width: 68, height: 68).clipShape(Circle())
                                VStack(alignment: .leading) {
                                    PhotosPicker("Change photo", selection: $selectedAvatar, matching: .images).disabled(profileSaving)
                                    if session.profile?.AvatarUrl != nil { Button("Remove photo") { Task { await removeAvatar() } }.disabled(profileSaving) }
                                }.font(.subheadline)
                            }
                            TextField("Nickname", text: $displayName).textContentType(.nickname).textFieldStyle(.roundedBorder)
                            Button("Save nickname") { Task { await saveName() } }
                                .disabled(profileSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || displayName == session.profile?.DisplayName)
                            Picker("Default currency", selection: $preferredCurrency) {
                                ForEach(BmbCurrency.codes, id: \.self) { code in Text(BmbCurrency.label(code)).tag(code) }
                            }
                            Button("Save currency") { Task { await saveCurrency() } }
                                .disabled(profileSaving || preferredCurrency == (session.profile?.DefaultCurrency ?? "USD"))
                            Text(session.profile?.Email ?? session.profile?.Phone ?? "—").font(.caption).foregroundStyle(BmbTheme.muted)
                            Divider()
                            Text("Verify and bind email").font(.headline)
                            TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let remaining = BmbEmailCodeCooldown.remaining(at: context.date)
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        TextField("Code", text: $code).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
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
        .task(id: session.token) {
            await session.loadProfile()
            preferredCurrency = session.profile?.DefaultCurrency ?? "USD"
        }
        .onChange(of: session.profile?.DisplayName) { _, value in displayName = value ?? "" }
        .onChange(of: session.profile?.DefaultCurrency) { _, value in preferredCurrency = value ?? "USD" }
        .onChange(of: selectedAvatar) { _, item in
            guard let item else { return }
            Task { await changeAvatar(item) }
        }
        .confirmationDialog("Delete your account and its content?", isPresented: $confirmDelete) {
            Button("Delete account", role: .destructive) { Task { await delete() } }
        }
    }
    private func saveName() async {
        guard let token = session.token else { return }
        profileSaving = true; defer { profileSaving = false }
        do {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 80 else { message = "Nickname must contain 1 to 80 characters."; return }
            let _: BmbAcknowledgement = try await session.api.call("/auth/me", method: "PUT", body: ["DisplayName": name], token: token)
            await session.loadProfile(); message = String(localized: "Nickname saved")
        } catch { message = error.localizedDescription }
    }
    private func saveCurrency() async {
        guard let token = session.token else { return }
        profileSaving = true; defer { profileSaving = false }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/auth/me", method: "PUT", body: ["DefaultCurrency": preferredCurrency], token: token)
            await session.loadProfile(); message = String(localized: "Default currency saved")
        } catch { message = error.localizedDescription }
    }
    private func changeAvatar(_ item: PhotosPickerItem) async {
        guard let token = session.token else { return }
        profileSaving = true; defer { profileSaving = false; selectedAvatar = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw BmbError(message: "Could not read this photo.") }
            let scale = min(1, 1024 / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let jpeg = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.82) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            _ = try await session.api.uploadAvatarImage(jpeg, token: token)
            await session.loadProfile(); message = String(localized: "Photo updated")
        } catch { message = error.localizedDescription }
    }
    private func removeAvatar() async {
        guard let token = session.token else { return }
        profileSaving = true; defer { profileSaving = false }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/auth/me/avatar", method: "DELETE", token: token)
            await session.loadProfile(); message = String(localized: "Photo removed")
        } catch { message = error.localizedDescription }
    }
    private func sendCode() async {
        guard !codeSending, BmbEmailCodeCooldown.remaining(at: .now) == 0 else { return }
        codeSending = true
        defer { codeSending = false }
        do { try await session.sendCode(email); BmbEmailCodeCooldown.recordSend(); message = nil }
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
