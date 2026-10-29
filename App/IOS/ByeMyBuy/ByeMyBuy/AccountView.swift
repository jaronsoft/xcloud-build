import SwiftUI
import AuthenticationServices
import CryptoKit
import PhotosUI
import UIKit

struct AccountView: View {
    @EnvironmentObject private var session: BmbSession
    @AppStorage("bmb.theme") private var themePreference = "system"
    @AppStorage("bmb.app_language") private var appLanguage = "system"
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var codeSending = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var confirmDeleteFinal = false
    @State private var showSecurity = false
    @State private var appleDelegate: BmbAppleDelegate?
    @State private var displayName = ""
    @State private var showNicknameEditor = false
    @State private var nicknameError: String?
    @State private var preferredCurrency = BmbCurrency.defaultCode
    @State private var countryCode = ""
    @AppStorage("bmb.debug_unlocked") private var debugUnlocked = false
    @State private var showingDiagnostics: BmbDiagnosticPage?
    @State private var debugStatus: String?
    @State private var profileNotice: String?
    @State private var cropImage: UIImage?
    @State private var showAvatarCrop = false
    @State private var selectedAvatar: PhotosPickerItem?
    @State private var profileSaving = false

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
                    if session.isLoggedIn {
                        Menu {
                            ForEach(BmbCurrency.codes, id: \.self) { code in
                                Button { Task { await saveCurrency(code) } } label: {
                                    Text(BmbCurrency.label(code))
                                }
                            }
                        } label: {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("My currency").font(.caption2).foregroundStyle(BmbTheme.muted)
                                Text(BmbCurrency.label(preferredCurrency)).font(.caption.bold())
                                    .foregroundStyle(BmbTheme.ink).lineLimit(1)
                            }
                            .padding(.horizontal, 8).frame(height: 44)
                            .background(BmbTheme.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(profileSaving)
                    }
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
                    Button {
                        message = nil
                        showSecurity = true
                    } label: {
                        BmbCard {
                            HStack {
                                Label("Account & security", systemImage: "lock.shield")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold())
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(BmbTheme.ink)
                        }
                    }
                    .buttonStyle(.plain)
                    if let message { Text(message).font(.caption).foregroundStyle(.green) }
                } else {
                    BmbCard { VStack(alignment: .leading, spacing: 18) {
                        Text("Sign in to keep every decision in one place.")
                        BmbPrimaryButton(title: "Sign in") { session.showLogin = true }
                    } }
                }
                languageCard
                NavigationLink(destination: CacheManagementView()) {
                    BmbCard {
                        HStack {
                            Label("Clear cache", systemImage: "externaldrive")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold())
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(BmbTheme.ink)
                    }
                }
                .buttonStyle(.plain)
                legalCard
                if debugUnlocked { diagnosticsCard }
                if session.isLoggedIn {
                    Button("Sign out") { session.logout() }
                        .font(.subheadline.bold())
                        .foregroundStyle(BmbTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(BmbTheme.card, in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(BmbTheme.ink.opacity(0.07)))
                        .buttonStyle(.plain)
                }
            }.padding(20)
        }
        .background(BmbTheme.paper)
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showSecurity) { securityPage }
        .task(id: session.token) {
            await session.loadProfile()
            preferredCurrency = session.profile?.DefaultCurrency ?? "USD"
            countryCode = session.profile?.CountryCode ?? ""
        }
        .refreshable {
            await session.loadProfile()
        }
        .onChange(of: session.profile?.DisplayName) { _, value in
            if !showNicknameEditor { displayName = value ?? "" }
        }
        .onChange(of: session.profile?.DefaultCurrency) { _, value in preferredCurrency = value ?? "USD" }
        .onChange(of: session.profile?.CountryCode) { _, value in countryCode = value ?? "" }
        .onChange(of: selectedAvatar) { _, item in
            guard let item else { return }
            Task { await prepareAvatar(item) }
        }
        .sheet(isPresented: $showAvatarCrop, onDismiss: { cropImage = nil; selectedAvatar = nil }) {
            if let cropImage {
                BmbAvatarCropView(image: cropImage) { cropped in
                    showAvatarCrop = false
                    Task { await uploadAvatar(cropped) }
                }
            }
        }
        .alert("Profile review", isPresented: Binding(get: { profileNotice != nil }, set: { if !$0 { profileNotice = nil } })) {
            Button("OK", role: .cancel) { profileNotice = nil }
        } message: { Text(profileNotice ?? "") }
        .sheet(item: $showingDiagnostics) { page in BmbDiagnosticsView(page: page) }
        .sheet(isPresented: $showNicknameEditor) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Nickname").font(.caption.bold()).foregroundStyle(BmbTheme.muted)
                    TextField("Nickname", text: $displayName)
                        .textContentType(.nickname)
                        .textFieldStyle(.roundedBorder)
                    if let nicknameError {
                        Text(nicknameError).font(.caption).foregroundStyle(.red)
                    }
                    Spacer()
                }
                .padding(20)
                .background(BmbTheme.paper)
                .navigationTitle("Edit nickname")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showNicknameEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save nickname") { Task { await saveName() } }
                            .disabled(profileSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || displayName.count > 80 || displayName == session.profile?.DisplayName)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var languageCard: some View {
        BmbCard {
            Menu {
                Button { appLanguage = "system" } label: {
                    Label("Follow device", systemImage: appLanguage == "system" ? "checkmark.circle.fill" : "iphone")
                }
                Button { appLanguage = "zh" } label: {
                    Label("简体中文", systemImage: appLanguage == "zh" ? "checkmark.circle.fill" : "character.bubble")
                }
                Button { appLanguage = "en" } label: {
                    Label("English", systemImage: appLanguage == "en" ? "checkmark.circle.fill" : "character.bubble")
                }
            } label: {
                HStack {
                    Label("App language", systemImage: "globe")
                    Spacer()
                    Text(languagePreferenceName)
                        .foregroundStyle(BmbTheme.muted)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(BmbTheme.muted)
                }
                .font(.subheadline)
                .foregroundStyle(BmbTheme.ink)
            }
        }
    }

    private var languagePreferenceName: LocalizedStringKey {
        switch appLanguage {
        case "zh": "简体中文"
        case "en": "English"
        default: "Follow device"
        }
    }

    private var profileCard: some View {
        BmbCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("YOUR DETAILS").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                HStack(spacing: 14) {
                    Group {
                        if let avatarUrl = session.profile?.AvatarUrl, let url = URL(string: avatarUrl) {
                            BmbCachedImage(url: url, preset: .thumbnail) { Circle().fill(.green.opacity(0.15)) }
                        } else {
                            Text(String((session.profile?.DisplayName ?? "B").prefix(1)))
                                .font(.title.bold()).frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.green.opacity(0.15))
                        }
                    }
                    .frame(width: 70, height: 70).clipShape(Circle())
                    .overlay {
                        PhotosPicker(selection: $selectedAvatar, matching: .images) {
                            Circle().fill(.clear).frame(width: 70, height: 70).contentShape(Circle())
                        }
                        .accessibilityLabel("Change photo")
                        .disabled(profileSaving)
                    }
                    .contextMenu {
                        if session.profile?.AvatarUrl != nil {
                            Button("Remove avatar", role: .destructive) { Task { await removeAvatar() } }
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Button {
                            displayName = session.profile?.DisplayName ?? ""
                            nicknameError = nil
                            showNicknameEditor = true
                        } label: {
                            HStack(spacing: 6) {
                                Text(session.profile?.DisplayName ?? BmbLanguage.localized("Your profile"))
                                    .lineLimit(1)
                                Image(systemName: "pencil").font(.caption2)
                                    .foregroundStyle(BmbTheme.muted)
                            }
                            .font(.headline)
                            .foregroundStyle(BmbTheme.ink)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit nickname")
                        if session.profile?.NicknameReviewPending == true || session.profile?.AvatarReviewPending == true {
                            Text("Profile changes awaiting review").font(.caption).foregroundStyle(BmbTheme.muted)
                        }
                        Text(session.profile?.Email ?? session.profile?.Phone ?? "—")
                            .font(.caption).foregroundStyle(BmbTheme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var securityPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BmbCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(session.profile?.Email == nil ? LocalizedStringKey("Add email") : LocalizedStringKey("Change email"))
                            .font(.headline)
                        if let currentEmail = session.profile?.Email {
                            Text(currentEmail).font(.subheadline).foregroundStyle(BmbTheme.muted)
                        }
                        TextField("New email", text: $email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = BmbEmailCodeCooldown.remaining(at: context.date)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Code", text: $code).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                    Button(codeSending ? BmbLanguage.localized("Sending…") : remaining > 0 ? String(format: BmbLanguage.localized("Resend in %ds"), remaining) : BmbLanguage.localized("Send code")) {
                                        Task { await sendCode() }
                                    }
                                    .font(.caption.bold())
                                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || codeSending || remaining > 0 || email == session.profile?.Email)
                                }
                                if remaining > 0 {
                                    Text("Code sent. Check your inbox and enter it here.")
                                        .font(.caption).foregroundStyle(BmbTheme.muted)
                                }
                            }
                        }
                        BmbPrimaryButton(title: session.profile?.Email == nil ? "Bind email" : "Update email") {
                            Task { await bindEmail() }
                        }
                        .disabled(email.isEmpty || code.isEmpty || email == session.profile?.Email)
                    }
                }
                if session.profile?.Email != nil {
                    BmbCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Set password").font(.headline)
                            SecureField("Set password", text: $password).textFieldStyle(.roundedBorder)
                            Text("At least 8 characters").font(.caption).foregroundStyle(BmbTheme.muted)
                            BmbPrimaryButton(title: "Set password") { Task { await setPassword() } }
                                .disabled(password.count < 8)
                        }
                    }
                    BmbCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Apple sign-in").font(.headline)
                            BmbAppleLinkButton { Task { await bindApple() } }
                                .frame(height: 50)
                                .accessibilityLabel("Link Apple account")
                        }
                    }
                }
                BmbCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Service region").font(.headline)
                        Text("Choose where your images are served.")
                            .font(.caption).foregroundStyle(BmbTheme.muted)
                        HStack(spacing: 9) {
                            regionButton("CN", title: "China")
                            regionButton("XX", title: "International")
                        }
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.green) }
                BmbCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Button("Delete account", role: .destructive) { confirmDelete = true }
                            .font(.subheadline.bold())
                    }
                }
            }
            .padding(20)
        }
        .background(BmbTheme.paper)
        .navigationTitle("Account & security")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .confirmationDialog("Delete your account and its content?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Continue to delete", role: .destructive) { confirmDeleteFinal = true }
        }
        .alert("Delete account permanently?", isPresented: $confirmDeleteFinal) {
            Button("Delete account", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your account and its content cannot be restored.")
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
                Divider()
                HStack {
                    Label("Version", systemImage: "info.circle")
                        .foregroundStyle(BmbTheme.ink)
                    Spacer()
                    Text(appVersionLabel).foregroundStyle(BmbTheme.muted)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .onTapGesture(count: 5) { debugUnlocked = true }
            }
        }
    }

    private var diagnosticsCard: some View {
        BmbCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Diagnostics").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                Button { Task { await checkConnection() } } label: {
                    HStack {
                        Label("Check connection", systemImage: "network")
                        Spacer()
                        Image(systemName: "arrow.clockwise").font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .font(.subheadline).foregroundStyle(BmbTheme.ink)
                }
                .buttonStyle(.plain)
                if let debugStatus {
                    Text(debugStatus).font(.caption).foregroundStyle(BmbTheme.muted)
                }
                Divider()
                diagnosticsLink("Request logs", symbol: "arrow.left.arrow.right", page: .requests)
                Divider()
                diagnosticsLink("Image logs", symbol: "photo", page: .images)
            }
        }
    }

    private func legalLink(_ title: LocalizedStringKey, path: String, symbol: String) -> some View {
        let language = BmbLanguage.code == "zh" ? "zh-CN" : "en"
        return Link(destination: URL(string: "https://byemybuy.get-free.net/\(path)/?lang=\(language)")!) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.bold())
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .font(.subheadline).foregroundStyle(BmbTheme.ink)
        }
    }
    private func diagnosticsLink(_ title: LocalizedStringKey, symbol: String, page: BmbDiagnosticPage) -> some View {
        Button { showingDiagnostics = page } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold())
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .font(.subheadline).foregroundStyle(BmbTheme.ink)
        }
        .buttonStyle(.plain)
    }
    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(BmbEngagementCopy.text("Build", "构建")) \(build))"
    }
    private func regionButton(_ code: String, title: LocalizedStringKey) -> some View {
        let selected = (countryCode.uppercased() == "CN" ? "CN" : "XX") == code
        return Button { Task { await saveCountry(code) } } label: {
            HStack(spacing: 6) {
                if selected { Image(systemName: "checkmark.circle.fill") }
                Text(title)
            }
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(selected ? BmbTheme.lime : BmbTheme.paper, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(BmbTheme.ink)
        }
        .buttonStyle(.plain)
        .disabled(profileSaving || selected)
    }
    private func checkConnection() async {
        debugStatus = BmbLanguage.localized("Checking connection…")
        let start = Date()
        do {
            let _: BmbDebugConfig = try await session.api.call("/config")
            debugStatus = "\(BmbLanguage.localized("Service available")) · \(Int(Date().timeIntervalSince(start) * 1000)) ms"
        } catch { debugStatus = BmbLanguage.localized("Service unavailable") }
    }
    private func saveName() async {
        guard let token = session.token else { return }
        profileSaving = true; defer { profileSaving = false }
        do {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 80 else {
                message = BmbLanguage.localized("Nickname must contain 1 to 80 characters.")
                return
            }
            let _: BmbAcknowledgement = try await session.api.call("/auth/me", method: "PUT", body: ["DisplayName": name], token: token)
            await session.loadProfile()
            showNicknameEditor = false
            profileNotice = BmbLanguage.localized("Nickname submitted for review. Your current name stays visible until approved.")
        } catch { nicknameError = error.localizedDescription }
    }
    private func saveCurrency(_ code: String) async {
        guard let token = session.token else { return }
        let previous = preferredCurrency
        preferredCurrency = code
        profileSaving = true; defer { profileSaving = false }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/auth/me", method: "PUT", body: ["DefaultCurrency": code], token: token)
            await session.loadProfile(); message = BmbLanguage.localized("Default currency saved")
        } catch { preferredCurrency = previous; message = error.localizedDescription }
    }
    private func saveCountry(_ code: String) async {
        guard let token = session.token else { return }
        profileSaving = true; defer { profileSaving = false }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/auth/me/country", method: "PUT", body: ["CountryCode": code], token: token)
            await session.loadProfile()
            countryCode = code
            message = BmbLanguage.localized("Service region updated")
        } catch { message = error.localizedDescription }
    }
    private func prepareAvatar(_ item: PhotosPickerItem) async {
        profileSaving = true; defer { profileSaving = false; selectedAvatar = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                throw BmbError(message: BmbLanguage.localized("Could not read this photo."))
            }
            cropImage = image
            showAvatarCrop = true
        } catch { message = error.localizedDescription }
    }
    private func uploadAvatar(_ image: UIImage) async {
        guard let token = session.token else { return }
        profileSaving = true; defer { profileSaving = false }
        do {
            guard let jpeg = image.jpegData(compressionQuality: 0.78) else {
                throw BmbError(message: BmbLanguage.localized("Could not read this photo."))
            }
            _ = try await session.api.uploadAvatarImage(jpeg, token: token)
            await session.loadProfile()
            profileNotice = BmbLanguage.localized("Photo submitted for review. Your current photo stays visible until approved.")
        } catch { profileNotice = error.localizedDescription }
    }
    private func removeAvatar() async {
        guard let token = session.token else { return }
        profileSaving = true; defer { profileSaving = false }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/auth/me/avatar", method: "DELETE", token: token)
            await session.loadProfile(); message = BmbLanguage.localized("Photo removed")
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
            let changingEmail = session.profile?.Email != nil
            await session.loadProfile()
            email = ""; code = ""
            message = changingEmail ? BmbLanguage.localized("Email updated") : BmbLanguage.localized("Email bound")
        } catch { message = error.localizedDescription }
    }
    private func setPassword() async {
        guard let token = session.token else { return }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/auth/set-password", method: "POST", body: ["Password": password], token: token)
            password = ""; message = BmbLanguage.localized("Password set")
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
                        message = BmbLanguage.localized("Apple identity token is missing."); return
                    }
                    do {
                        let _: BmbAcknowledgement = try await session.api.call("/auth/bind-apple", method: "POST", body: ["IdentityToken": identityToken, "Nonce": nonce], token: token)
                        message = BmbLanguage.localized("Apple account linked")
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
        do { try await session.deleteAccount(); showSecurity = false }
        catch { message = error.localizedDescription }
    }
}

private struct BmbDebugConfig: Decodable { let AdsEnabled: Bool? }

private enum BmbDiagnosticPage: String, Identifiable {
    case requests = "API"
    case images = "IMAGE"

    var id: String { rawValue }
    var title: LocalizedStringKey { self == .requests ? "Request logs" : "Image logs" }
    var emptyMessage: LocalizedStringKey { self == .requests ? "No request logs yet" : "No image logs yet" }
}

private struct BmbDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var entries: [BmbDiagnosticEntry] = []
    let page: BmbDiagnosticPage

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty { Text(page.emptyMessage).foregroundStyle(BmbTheme.muted) }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.summary).font(.caption).textSelection(.enabled)
                        Text(entry.time.formatted(date: .abbreviated, time: .standard))
                            .font(.caption2).foregroundStyle(BmbTheme.muted)
                    }
                }
            }
            .navigationTitle(page.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear logs") { Task { await BmbDiagnostics.shared.clear(kind: page.rawValue); await reload() } }
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await reload()
                    do { try await Task.sleep(for: .seconds(2)) } catch { break }
                }
            }
        }
    }

    private func reload() async { entries = await BmbDiagnostics.shared.snapshot(kind: page.rawValue) }
}

private struct BmbAppleLinkButton: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) { context.coordinator.action = action }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}

private struct BmbAvatarCropView: View {
    let image: UIImage
    let onComplete: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var settledOffset = CGSize.zero

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let cropSize = min(proxy.size.width - 40, 380)
                VStack(spacing: 20) {
                    Spacer(minLength: 10)
                    cropCanvas(size: cropSize, showsGuide: true)
                        .frame(width: cropSize, height: cropSize)
                        .contentShape(Rectangle())
                        .gesture(DragGesture().onChanged { value in
                            offset = clamped(CGSize(width: settledOffset.width + value.translation.width,
                                                    height: settledOffset.height + value.translation.height), size: cropSize)
                        }.onEnded { _ in settledOffset = offset })
                        .simultaneousGesture(MagnificationGesture().onChanged { value in
                            zoom = min(5, max(1, settledZoom * value))
                            offset = clamped(offset, size: cropSize)
                        }.onEnded { _ in settledZoom = zoom; settledOffset = offset })
                        .accessibilityLabel("Crop avatar")
                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: Binding(get: { zoom }, set: { value in
                            zoom = value; settledZoom = value
                            offset = clamped(offset, size: cropSize); settledOffset = offset
                        }), in: 1...5)
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .padding(.horizontal, 28)
                    Text("Drag to position, pinch to zoom.").font(.footnote).foregroundStyle(BmbTheme.muted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BmbTheme.paper.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use photo") { if let result = renderedCrop(size: cropSize) { onComplete(result) } }
                    }
                }
            }
            .navigationTitle("Crop photo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func cropCanvas(size: CGFloat, showsGuide: Bool) -> some View {
        ZStack {
            Color.black
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size, height: size).scaleEffect(zoom).offset(offset)
            if showsGuide {
                Circle().stroke(.white.opacity(0.9), lineWidth: 2).padding(3).allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size).clipped()
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func clamped(_ proposed: CGSize, size: CGFloat) -> CGSize {
        let ratio = image.size.width / max(image.size.height, 1)
        let width = ratio >= 1 ? size * ratio : size
        let height = ratio >= 1 ? size : size / ratio
        let maxX = max(0, (width * zoom - size) / 2)
        let maxY = max(0, (height * zoom - size) / 2)
        return CGSize(width: min(maxX, max(-maxX, proposed.width)),
                      height: min(maxY, max(-maxY, proposed.height)))
    }

    @MainActor private func renderedCrop(size: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: cropCanvas(size: size, showsGuide: false))
        renderer.scale = 1024 / size
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
