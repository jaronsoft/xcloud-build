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
    @State private var cacheSizes: (data: Int64, images: Int64) = (0, 0)
    @State private var confirmClearData = false
    @State private var confirmClearImages = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("YOUR PROFILE").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                        Text("Account").font(.system(size: 31, weight: .black, design: .rounded))
                        Text("Make this space yours.").font(.system(size: 14)).foregroundStyle(BmbTheme.muted)
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
                    profileCard
                    securityCard
                    if let message { Text(message).font(.caption).foregroundStyle(.green) }
                } else {
                    BmbCard { VStack(alignment: .leading, spacing: 18) {
                        Text("Sign in to keep every decision in one place.")
                        BmbPrimaryButton(title: "Sign in") { session.showLogin = true }
                    } }
                }
                cacheCard
                legalCard
                if session.isLoggedIn {
                    Button("Sign out") { session.logout() }
                        .font(.subheadline.bold()).foregroundStyle(BmbTheme.ink)
                        .frame(maxWidth: .infinity).padding(15)
                        .background(BmbTheme.card, in: RoundedRectangle(cornerRadius: 16))
                    Button("Delete account", role: .destructive) { confirmDelete = true }
                        .font(.caption.bold()).frame(maxWidth: .infinity).padding(8)
                }
            }.padding(20)
        }
        .background(BmbTheme.paper)
        .navigationBarHidden(true)
        .task(id: session.token) {
            await session.loadProfile()
            preferredCurrency = session.profile?.DefaultCurrency ?? "USD"
            cacheSizes = await BmbCache.shared.sizes()
        }
        .refreshable {
            await session.loadProfile()
            cacheSizes = await BmbCache.shared.sizes()
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
        .confirmationDialog("Clear saved data?", isPresented: $confirmClearData) {
            Button("Clear data cache", role: .destructive) { Task { await BmbCache.shared.clearData(); cacheSizes = await BmbCache.shared.sizes() } }
        }
        .confirmationDialog("Clear saved images?", isPresented: $confirmClearImages) {
            Button("Clear image cache", role: .destructive) { Task { await BmbCache.shared.clearImages(); cacheSizes = await BmbCache.shared.sizes() } }
        }
    }

    private var profileCard: some View {
        BmbCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("YOUR DETAILS").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                HStack(spacing: 14) {
                    Group {
                        if let avatarUrl = session.profile?.AvatarUrl, let url = URL(string: avatarUrl) {
                            BmbCachedImage(url: url) { Circle().fill(.green.opacity(0.15)) }
                        } else {
                            Text(String((session.profile?.DisplayName ?? "B").prefix(1)))
                                .font(.title.bold()).frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.green.opacity(0.15))
                        }
                    }.frame(width: 70, height: 70).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.profile?.DisplayName ?? String(localized: "Your profile"))
                            .font(.headline).lineLimit(1)
                        Text(session.profile?.Email ?? session.profile?.Phone ?? "—")
                            .font(.caption).foregroundStyle(BmbTheme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    PhotosPicker(selection: $selectedAvatar, matching: .images) {
                        Image(systemName: "camera").font(.headline)
                            .frame(width: 42, height: 42)
                            .background(BmbTheme.hero, in: Circle())
                    }
                    .accessibilityLabel("Change photo")
                    .disabled(profileSaving)
                }
                if session.profile?.AvatarUrl != nil {
                    Button("Remove avatar") { Task { await removeAvatar() } }
                        .font(.caption).disabled(profileSaving)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nickname").font(.caption.bold()).foregroundStyle(BmbTheme.muted)
                    TextField("Nickname", text: $displayName).textContentType(.nickname).textFieldStyle(.roundedBorder)
                    if displayName != session.profile?.DisplayName {
                        Button("Save nickname") { Task { await saveName() } }
                            .font(.subheadline.bold()).foregroundStyle(.green)
                            .disabled(profileSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Default currency").font(.caption.bold()).foregroundStyle(BmbTheme.muted)
                    Picker("Default currency", selection: $preferredCurrency) {
                        ForEach(BmbCurrency.codes, id: \.self) { code in Text(BmbCurrency.label(code)).tag(code) }
                    }.pickerStyle(.menu).tint(BmbTheme.ink)
                    if preferredCurrency != (session.profile?.DefaultCurrency ?? "USD") {
                        Button("Save currency") { Task { await saveCurrency() } }
                            .font(.subheadline.bold()).foregroundStyle(.green).disabled(profileSaving)
                    }
                }
            }
        }
    }

    private var securityCard: some View {
        BmbCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("SIGN-IN & SECURITY").font(.caption.bold()).tracking(2).foregroundStyle(.green)
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
                Button("Bind email") { Task { await bindEmail() } }
                    .font(.subheadline.bold()).foregroundStyle(.green)
                    .disabled(email.isEmpty || code.isEmpty)
                Divider()
                Button { Task { await bindApple() } } label: {
                    Label("Link Apple account", systemImage: "apple.logo")
                        .font(.subheadline.bold()).foregroundStyle(BmbTheme.ink)
                }
                Divider()
                Text("Set password").font(.headline)
                SecureField("Set password", text: $password).textFieldStyle(.roundedBorder)
                Button("Set password") { Task { await setPassword() } }
                    .font(.subheadline.bold()).foregroundStyle(.green).disabled(password.isEmpty)
            }
        }
    }

    private var cacheCard: some View {
        BmbCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("OFFLINE STORAGE").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                Text("Saved for your next visit").font(.headline)
                HStack {
                    Label("Data cache", systemImage: "doc.text")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: cacheSizes.data, countStyle: .file))
                        .foregroundStyle(BmbTheme.muted)
                }.font(.subheadline)
                HStack {
                    Label("Image cache", systemImage: "photo")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: cacheSizes.images, countStyle: .file))
                        .foregroundStyle(BmbTheme.muted)
                }.font(.subheadline)
                HStack(spacing: 12) {
                    Button("Clear data cache") { confirmClearData = true }
                    Button("Clear image cache") { confirmClearImages = true }
                }.font(.caption.bold()).buttonStyle(.bordered)
            }
        }
    }

    private var legalCard: some View {
        BmbCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("HELP & LEGAL").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                legalLink("Technical support", path: "support", symbol: "questionmark.circle")
                Divider()
                legalLink("Privacy Policy", path: "privacy", symbol: "hand.raised")
                Divider()
                legalLink("Terms of Service", path: "terms", symbol: "doc.text")
            }
        }
    }

    private func legalLink(_ title: LocalizedStringKey, path: String, symbol: String) -> some View {
        let language = Locale.current.language.languageCode?.identifier == "zh" ? "zh-CN" : "en"
        return Link(destination: URL(string: "https://byemybuy.get-free.net/\(path)/?lang=\(language)")!) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.bold())
            }
            .font(.subheadline).foregroundStyle(BmbTheme.ink)
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
