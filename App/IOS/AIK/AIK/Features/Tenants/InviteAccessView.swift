import SwiftUI

struct InviteAccessView: View {
    let session: SessionStore
    let tenants: TenantStore

    @Environment(\.dismiss) private var dismiss
    @State private var model = InviteAccessModel()
    @State private var input = ""
    @State private var captcha = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("invite.input", text: $input, axis: .vertical)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("invite.resolve") {
                        Task {
                            if await model.resolve(
                                input,
                                session: session,
                                tenants: tenants
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.isWorking || input.isEmpty)
                } footer: {
                    Text("invite.hint")
                }

                if let tenant = model.pendingTenant {
                    Section("invite.space") {
                        LabeledContent("invite.tenant", value: tenant.TenantName)
                        if let agent = tenant.AgentName {
                            LabeledContent("invite.agent", value: agent)
                        }
                    }
                }

                if let image = model.captchaImage {
                    Section("invite.captcha") {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .contentShape(.rect)
                            .onTapGesture {
                                Task { await model.loadCaptcha(session: session) }
                            }
                        TextField("invite.captcha_input", text: $captcha)
                            .keyboardType(.numberPad)
                        Button("invite.enter") {
                            Task {
                                if await model.validateCaptcha(
                                    captcha,
                                    session: session,
                                    tenants: tenants
                                ) {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(captcha.isEmpty || model.isWorking)
                    }
                }

                if let error = model.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("invite.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
            .overlay {
                if model.isWorking {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 14))
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .aikOpenInvite)
            ) { notification in
                guard let reference = notification.object as? InviteReference else {
                    return
                }
                input = reference.accessCode ?? reference.code ?? reference.tenantID ?? ""
            }
        }
    }
}

@MainActor
@Observable
final class InviteAccessModel {
    var isWorking = false
    var errorMessage: String?
    var pendingTenant: TenantSummary?
    var captchaImage: UIImage?

    private var captchaKey: String?
    private var pendingCode: String?

    func resolve(
        _ input: String,
        session: SessionStore,
        tenants: TenantStore
    ) async -> Bool {
        guard let reference = InviteLinkParser.parse(input) else {
            errorMessage = String(localized: "invite.invalid")
            return false
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            if let accessCode = reference.accessCode {
                let tenant: TenantSummary = try await session.client.post(
                    "/KnowledgeAccess/ResolveSpace",
                    body: SpaceAccessRequest(AccessCode: accessCode),
                    as: TenantSummary.self
                )
                if session.mode == .system {
                    return await tenants.select(tenant, session: session)
                }
                guard tenant.IsAnonymousAllowed == true else {
                    pendingTenant = tenant
                    throw APIError.server(String(localized: "invite.login_required"))
                }
                pendingTenant = tenant
                pendingCode = nil
                await loadCaptcha(session: session)
                return false
            }
            if let code = reference.code {
                let status: InviteStatus = try await session.client.get(
                    "/KnowledgeMember/GetCodeStatus",
                    queryItems: [
                        URLQueryItem(name: "code", value: code),
                        URLQueryItem(name: "mark", value: "record"),
                    ],
                    as: InviteStatus.self
                )
                guard status.IsValid == true, let tenant = status.Tenant else {
                    throw APIError.server(String(localized: "invite.invalid"))
                }
                session.establishGuest(
                    token: status.Token ?? "GUEST-\(UUID().uuidString)",
                    inviteCode: code
                )
                tenants.selectGuest(tenant)
                return true
            }

            guard let tenantID = reference.tenantID else {
                throw APIError.server(String(localized: "invite.invalid"))
            }
            let info: TenantPublicInfo = try await session.client.get(
                "/KnowledgeMember/GetTenantPublicInfo",
                queryItems: [URLQueryItem(name: "tenantId", value: tenantID)],
                as: TenantPublicInfo.self
            )
            if session.mode == .system {
                return await tenants.select(info.summary, session: session)
            }
            guard info.IsAnonymousAllowed == true else {
                pendingTenant = info.summary
                throw APIError.server(String(localized: "invite.login_required"))
            }
            pendingTenant = info.summary
            pendingCode = nil
            await loadCaptcha(session: session)
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loadCaptcha(session: SessionStore) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let key: String = try await session.client.get(
                "/auth/snowflake",
                as: String.self
            )
            let base64: String = try await session.client.getLegacyResponse(
                "/auth/generate-captcha",
                queryItems: [URLQueryItem(name: "keyid", value: key)],
                as: String.self
            )
            guard let data = Data(base64Encoded: base64),
                  let image = UIImage(data: data) else {
                throw APIError.invalidResponse
            }
            captchaKey = key
            captchaImage = image
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func validateCaptcha(
        _ value: String,
        session: SessionStore,
        tenants: TenantStore
    ) async -> Bool {
        guard let captchaKey, let pendingTenant else {
            return false
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let request = try session.client.makeRequest(
                path: "/auth/validate-captcha",
                method: "POST",
                queryItems: [
                    URLQueryItem(name: "keyid", value: captchaKey),
                    URLQueryItem(name: "captcha", value: value),
                ],
                context: .anonymous
            )
            let data = try await session.client.rawData(for: request)
            let envelope = try JSONDecoder().decode(
                MessageEnvelope<Bool>.self,
                from: data
            )
            guard envelope.success, envelope.response == true else {
                throw APIError.server(
                    envelope.msg ?? String(localized: "invite.captcha_error")
                )
            }
            session.establishGuest(
                token: "GUEST-\(UUID().uuidString)",
                inviteCode: pendingCode
            )
            tenants.selectGuest(pendingTenant)
            return true
        } catch {
            errorMessage = error.localizedDescription
            await loadCaptcha(session: session)
            return false
        }
    }
}
