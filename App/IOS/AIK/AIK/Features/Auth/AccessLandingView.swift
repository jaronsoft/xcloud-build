import SwiftUI
import VisionKit

struct AccessLandingView: View {
    let session: SessionStore
    let tenants: TenantStore
    @State private var accessCode = ""
    @State private var selectedTenant: TenantSummary?
    @State private var showsSystemLogin = false
    @State private var showsRegistration = false
    @State private var showsScanner = false
    @State private var scannedReference: InviteReference?
    @State private var isResolving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("access.code_placeholder", text: $accessCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("access.code_submit", systemImage: "arrow.right.circle.fill") {
                        Task {
                            await open(
                                InviteReference(
                                    tenantID: nil,
                                    code: nil,
                                    accessCode: accessCode
                                )
                            )
                        }
                    }
                    .disabled(accessCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolving)
                } footer: {
                    Text("access.code_hint")
                }
                Section {
                    Button("access.system_login", systemImage: "person.badge.key") {
                        showsSystemLogin = true
                    }
                    Button("access.scan", systemImage: "qrcode.viewfinder") {
                        showsScanner = true
                    }
                    Button("registration.open", systemImage: "person.badge.plus") {
                        showsRegistration = true
                    }
                }
                if !tenants.recentTenants.isEmpty {
                    Section("tenant.recent") {
                        ForEach(tenants.recentTenants) { tenant in
                        Button {
                            scannedReference = nil
                            selectedTenant = tenant
                        } label: {
                            HStack(spacing: 12) {
                                TenantLogo(url: tenant.AgentLogo, size: 44)
                                VStack(alignment: .leading) {
                                    Text(tenant.AgentName ?? tenant.TenantName)
                                        .foregroundStyle(.primary)
                                    Text("access.recent_hint")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    }
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("access.title")
            .overlay {
                if isResolving { ProgressView() }
            }
        }
        .sheet(isPresented: $showsSystemLogin) {
            LoginView(session: session, tenants: tenants)
        }
        .sheet(isPresented: $showsRegistration) {
            KnowledgeRegistrationView()
        }
        .sheet(item: $selectedTenant) { tenant in
            TenantAccessView(
                session: session,
                tenants: tenants,
                tenant: tenant,
                initialInvite: scannedReference?.code
            )
        }
        .sheet(isPresented: $showsScanner) {
            AIKScannerView { value in
                showsScanner = false
                guard let reference = InviteLinkParser.parse(value) else { return }
                scannedReference = reference
                Task { await open(reference) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aikOpenInvite)) {
            guard let reference = $0.object as? InviteReference else { return }
            scannedReference = reference
            Task { await open(reference) }
        }
        .task {
            if selectedTenant == nil {
                selectedTenant = await tenants.resolveStandaloneTenant()
            }
        }
    }

    private func open(_ reference: InviteReference) async {
        scannedReference = reference
        error = nil
        isResolving = true
        defer { isResolving = false }
        if let accessCode = reference.accessCode {
            do {
                selectedTenant = try await session.client.post(
                    "/KnowledgeAccess/ResolveSpace",
                    body: SpaceAccessRequest(AccessCode: accessCode),
                    as: TenantSummary.self
                )
            } catch {
                self.error = error.localizedDescription
            }
            return
        }
        if let tenantID = reference.tenantID,
           let tenant = tenants.tenants.first(where: { $0.id == tenantID }) {
            selectedTenant = tenant
            return
        }
        if let code = reference.code {
            let status: InviteStatus? = try? await session.client.get(
                "/KnowledgeMember/GetCodeStatus",
                queryItems: [URLQueryItem(name: "code", value: code)],
                as: InviteStatus.self
            )
            selectedTenant = status?.Tenant
        } else if let tenantID = reference.tenantID {
            let info: TenantPublicInfo? = try? await session.client.get(
                "/KnowledgeMember/GetTenantPublicInfo",
                queryItems: [URLQueryItem(name: "tenantId", value: tenantID)],
                as: TenantPublicInfo.self
            )
            selectedTenant = info?.summary
        }
    }
}

private struct TenantAccessView: View {
    let session: SessionStore
    let tenants: TenantStore
    let tenant: TenantSummary
    let initialInvite: String?
    @Environment(\.dismiss) private var dismiss
    @State private var mode: String
    @State private var account = ""
    @State private var password = ""
    @State private var invite: String
    @State private var captcha = ""
    @State private var captchaKey: String?
    @State private var captchaImage: UIImage?
    @State private var working = false
    @State private var error: String?

    private var isAnonymousOnly: Bool {
        tenant.IsAnonymousAllowed == true
            && (initialInvite?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    init(
        session: SessionStore,
        tenants: TenantStore,
        tenant: TenantSummary,
        initialInvite: String?
    ) {
        self.session = session
        self.tenants = tenants
        self.tenant = tenant
        self.initialInvite = initialInvite

        let normalizedInvite = initialInvite?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        _invite = State(initialValue: normalizedInvite)
        _mode = State(
            initialValue: !normalizedInvite.isEmpty
                ? "invite"
                : tenant.IsAnonymousAllowed == true ? "anonymous" : "member"
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TenantLogo(url: tenant.AgentLogo, size: 52)
                        VStack(alignment: .leading) {
                            Text(tenant.AgentName ?? tenant.TenantName).font(.headline)
                            Text("用户编号：\(tenant.id)").foregroundStyle(.secondary)
                        }
                    }
                }
                if !isAnonymousOnly {
                    Picker("access.mode", selection: $mode) {
                        Text("access.member").tag("member")
                        Text("access.invite").tag("invite")
                        if tenant.IsAnonymousAllowed == true {
                            Text("access.anonymous").tag("anonymous")
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    if mode == "member" {
                        TextField("login.account", text: $account)
                        SecureField("login.password", text: $password)
                    } else if mode == "invite" {
                        TextField("invite.input", text: $invite)
                    } else {
                        if let captchaImage {
                            Image(uiImage: captchaImage).resizable().scaledToFit()
                                .onTapGesture { Task { await loadCaptcha() } }
                        }
                        TextField("invite.captcha_input", text: $captcha)
                    }
                    Button("access.enter") { Task { await submit() } }
                        .disabled(working)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("access.verify")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
            .onChange(of: mode) { _, value in
                if value == "anonymous" { Task { await loadCaptcha() } }
            }
            .task {
                if mode == "anonymous", captchaImage == nil {
                    await loadCaptcha()
                }
            }
        }
    }

    private func loadCaptcha() async {
        do {
            let key: String = try await session.client.get("/auth/snowflake", as: String.self)
            let base64: String = try await session.client.getLegacyResponse(
                "/auth/generate-captcha",
                queryItems: [URLQueryItem(name: "keyid", value: key)],
                as: String.self
            )
            captchaKey = key
            captchaImage = Data(base64Encoded: base64).flatMap(UIImage.init)
        } catch { self.error = error.localizedDescription }
    }

    private func submit() async {
        working = true
        error = nil
        defer { working = false }
        do {
            let body = KnowledgeAccessSessionRequest(
                TenantId: tenant.TenantId,
                Mode: mode,
                Account: mode == "member" ? account : nil,
                Password: mode == "member" ? password : nil,
                InviteCode: mode == "invite" ? invite : nil,
                CaptchaKey: mode == "anonymous" ? captchaKey : nil,
                Captcha: mode == "anonymous" ? captcha : nil,
                DeviceInfo: UIDevice.current.model
            )
            let response: KnowledgeAccessSession = try await session.client.post(
                "/KnowledgeAccess/Session",
                body: body,
                as: KnowledgeAccessSession.self
            )
            session.establishKnowledgeAccess(
                response,
                inviteCode: mode == "invite" ? invite : nil
            )
            tenants.selectGuest(response.Tenant)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            if mode == "anonymous" { await loadCaptcha() }
        }
    }
}

struct TenantLogo: View {
    let url: String?
    let size: CGFloat
    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "building.2.crop.circle.fill")
                .resizable().foregroundStyle(AIKTheme.gradient())
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.22))
    }
}

private struct AIKScannerView: UIViewControllerRepresentable {
    let onValue: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onValue: onValue) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onValue: (String) -> Void
        init(onValue: @escaping (String) -> Void) { self.onValue = onValue }
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard case let .barcode(code) = addedItems.first,
                  let value = code.payloadStringValue else { return }
            onValue(value)
        }
    }
}
