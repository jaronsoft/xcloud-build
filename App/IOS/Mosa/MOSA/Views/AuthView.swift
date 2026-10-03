import SwiftUI

struct AuthView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case login
        case register
        case reset
        var id: Self { self }
    }

    @EnvironmentObject private var store: MosaStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode = Mode.login
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var displayName = ""
    @State private var message: String?
    @State private var isError = false
    @State private var busy = false
    @State private var cooldown = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "MOSA account")
                Text(title)
                    .font(.system(size: 40, weight: .medium, design: .serif))

                Picker("Account action", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.rawValue.capitalized).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in message = nil }

                VStack(alignment: .leading, spacing: 16) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textFieldStyle(.roundedBorder)

                    if mode == .register {
                        TextField("Name (optional)", text: $displayName)
                            .textContentType(.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    if mode != .login {
                        HStack {
                            TextField("Email code", text: $code)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: code) { _, value in
                                    code = String(value.filter(\.isNumber).prefix(6))
                                }
                            Button(cooldown > 0 ? "\(cooldown)s" : "Send code") {
                                Task { await requestCode() }
                            }
                            .disabled(busy || cooldown > 0)
                        }
                    }

                    SecureField(mode == .reset ? "New password" : "Password", text: $password)
                        .textContentType(mode == .login ? .password : .newPassword)
                        .textFieldStyle(.roundedBorder)

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(isError ? Color.red : MosaPalette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(MosaPalette.paperSecondary, in: RoundedRectangle(cornerRadius: 12))
                    }

                    Button(busy ? "Please wait…" : actionTitle) {
                        Task { await submit() }
                    }
                    .buttonStyle(MosaPrimaryButtonStyle())
                    .disabled(busy)
                }
                .mosaCard()

                Text("Your account is separate from the MOSA administration system. Passwords and verification codes are never stored in local record files.")
                    .font(.caption)
                    .foregroundStyle(MosaPalette.muted)
                    .multilineTextAlignment(.center)
                CompanyFooter().frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .mosaPage()
        .task(id: cooldown) {
            guard cooldown > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { cooldown = max(0, cooldown - 1) }
        }
    }

    private var title: String {
        switch mode {
        case .login: "Welcome back."
        case .register: "Keep your days with you."
        case .reset: "Reset your password."
        }
    }

    private var actionTitle: String {
        switch mode {
        case .login: "Sign in"
        case .register: "Create account"
        case .reset: "Update password"
        }
    }

    private func requestCode() async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else {
            showValidationError("Enter your email address.")
            return
        }

        busy = true
        defer { busy = false }
        do {
            message = try await store.sendCode(email: normalizedEmail, purpose: mode == .reset ? "reset" : "register")
            isError = false
            cooldown = 60
        } catch let error as APIError {
            message = error.message
            isError = true
            cooldown = error.retryAfterSeconds ?? 0
        } catch {
            message = "The request could not be completed."
            isError = true
        }
    }

    private func submit() async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else {
            showValidationError("Enter your email address.")
            return
        }
        guard password.count >= 8 else {
            showValidationError("Password must be at least 8 characters.")
            return
        }
        guard mode == .login || code.count == 6 else {
            showValidationError("Enter the 6-digit email code.")
            return
        }

        busy = true
        defer { busy = false }
        do {
            switch mode {
            case .login:
                try await store.login(email: normalizedEmail, password: password)
            case .register:
                try await store.register(email: normalizedEmail, code: code, password: password, displayName: displayName)
            case .reset:
                message = try await store.resetPassword(email: normalizedEmail, code: code, password: password)
                isError = false
                mode = .login
                return
            }
            dismiss()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "The request could not be completed."
            isError = true
        }
    }

    private func showValidationError(_ text: String) {
        message = text
        isError = true
    }
}
