import SwiftUI

struct KnowledgeRegistrationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = KnowledgeRegistrationStore()
    @State private var isEditing = false
    @State private var userName = ""
    @State private var password = ""
    @State private var confirmedPassword = ""
    @State private var email = ""
    @State private var mobile = ""
    @State private var companyName = ""
    @State private var captcha = ""
    @State private var privacyAccepted = false
    @State private var termsAccepted = false
    @State private var showsCancelConfirmation = false
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.hasSavedApplication && !isEditing {
                    statusContent
                } else {
                    applicationForm
                }
            }
            .navigationTitle("registration.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
            .overlay {
                if store.isWorking {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 14))
                }
            }
            .task {
                if store.hasSavedApplication {
                    await store.restoreStatus()
                } else if store.captchaImage == nil {
                    await store.loadCaptcha()
                }
            }
            .confirmationDialog(
                "registration.cancel_confirm",
                isPresented: $showsCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("registration.cancel_action", role: .destructive) {
                    Task { await store.cancel() }
                }
                Button("common.cancel", role: .cancel) {}
            }
        }
    }

    private var applicationForm: some View {
        Form {
            Section {
                TextField("registration.username", text: $userName)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("registration.password", text: $password)
                    .textContentType(.newPassword)
                SecureField("registration.password_confirm", text: $confirmedPassword)
                    .textContentType(.newPassword)
            } header: {
                Text("registration.account_section")
            } footer: {
                Text("registration.password_hint")
            }

            Section("registration.contact_section") {
                TextField("registration.email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("registration.mobile", text: $mobile)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                TextField("registration.company", text: $companyName)
                    .textContentType(.organizationName)
            }

            Section {
                if let image = store.captchaImage {
                    Button {
                        Task {
                            captcha = ""
                            await store.loadCaptcha()
                        }
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("registration.captcha_refresh")
                } else {
                    Button("registration.captcha_refresh") {
                        Task { await store.loadCaptcha() }
                    }
                }
                TextField("registration.captcha", text: $captcha)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            } header: {
                Text("registration.verification_section")
            } footer: {
                Text("registration.captcha_hint")
            }

            Section {
                Toggle("registration.privacy_accept", isOn: $privacyAccepted)
                Toggle("registration.terms_accept", isOn: $termsAccepted)
                Link("privacy.policy", destination: AppEnvironment.privacyURL)
            } footer: {
                Text("registration.payment_notice")
            }

            if let message = validationMessage ?? store.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    Text(store.canResubmit ? "registration.resubmit" : "registration.submit")
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.isWorking)
            }
        }
    }

    private var statusContent: some View {
        List {
            if let status = store.status {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: statusIcon(status.Status))
                            .font(.system(size: 42))
                            .foregroundStyle(statusColor(status.Status))
                        Text(statusTitle(status.Status))
                            .font(.title3.bold())
                        Text(statusMessage(status))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                Section("registration.details") {
                    LabeledContent("registration.application_id", value: status.ApplicationId.rawValue)
                    LabeledContent("registration.company", value: status.CompanyName)
                    LabeledContent("registration.email", value: status.MaskedEmail)
                    LabeledContent("registration.mobile", value: status.MaskedMobile)
                }
                Section {
                    Button("registration.refresh", systemImage: "arrow.clockwise") {
                        Task { await store.restoreStatus() }
                    }
                    if store.canResubmit {
                        Button("registration.edit_resubmit", systemImage: "pencil") {
                            isEditing = true
                            Task { await store.loadCaptcha() }
                        }
                    }
                    if store.canCancel {
                        Button(
                            "registration.cancel_action",
                            systemImage: "xmark.circle",
                            role: .destructive
                        ) {
                            showsCancelConfirmation = true
                        }
                    }
                }
                if let warning = store.warningMessage {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } else if let error = store.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Button("common.retry") {
                        Task { await store.restoreStatus() }
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            Section {
                Text("registration.payment_notice")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .refreshable { await store.restoreStatus() }
    }

    private func submit() async {
        validationMessage = nil
        guard password == confirmedPassword else {
            validationMessage = String(localized: "registration.password_mismatch")
            return
        }
        if await store.submit(
            userName: userName,
            password: password,
            email: email,
            mobile: mobile,
            companyName: companyName,
            captcha: captcha,
            privacyAccepted: privacyAccepted,
            termsAccepted: termsAccepted
        ) {
            password = ""
            confirmedPassword = ""
            captcha = ""
            isEditing = false
        }
    }

    private func statusTitle(_ status: String) -> LocalizedStringKey {
        LocalizedStringKey("registration.status.\(status.lowercased()).title")
    }

    private func statusMessage(_ status: KnowledgeRegistrationStatus) -> String {
        let key = "registration.status.\(status.Status.lowercased()).message"
        let localized = String(localized: String.LocalizationValue(key))
        return localized == key ? status.StatusMessage : localized
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "Approved": "checkmark.seal.fill"
        case "Rejected", "Cancelled": "xmark.circle.fill"
        case "ProvisionFailed": "exclamationmark.triangle.fill"
        case "Contacted", "AwaitingPayment": "person.crop.circle.badge.checkmark"
        default: "clock.fill"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Approved": .green
        case "Rejected", "Cancelled", "ProvisionFailed": .orange
        default: AIKTheme.accent
        }
    }
}
