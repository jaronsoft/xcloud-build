import SwiftUI

struct NativeIdentityConsentView: View {
    private let revokeExplanation = "撤回后，办理新的实名购票和实名消费券业务需重新授权。已登记的实名资料仍加密保留，历史订单按原规则处理。"

    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var profile: [String: Any]?
    @State private var profileOwner: String?
    @State private var loading = false
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var confirmRevoke = false
    @State private var revokeConfirmationPrincipal: String?
    @State private var realName = ""
    @State private var identityNumber = ""
    @State private var identityConsent = false
    @State private var operation = 0
    @State private var readTask: Task<Void, Never>?
    @State private var readTaskGeneration = 0
    @State private var writeTask: Task<Void, Never>?
    @State private var writeTaskGeneration = 0
    @State private var pageVisible = false

    private var principal: String? { nativeTourismPrincipal(store.session?.accessToken) }
    private var hasConsent: Bool { profile?["HasConsent"] as? Bool == true }
    private var consentStatus: String {
        if profile?["HasProfile"] as? Bool == true && profile?["IsIdentityDataReadable"] as? Bool != true {
            return hasConsent ? "已授权，资料暂不可读" : "资料暂不可读"
        }
        guard hasConsent else { return "未授权" }
        return profile?["IsConsentCurrent"] as? Bool == false ? "已授权（告知版本已更新）" : "已授权"
    }
    private var version: Int64 {
        nativeTicketIdentityVersion(profile) ?? -1
    }
    private var canFillIdentity: Bool {
        profile?["IsPhoneVerified"] as? Bool == true
            && profile?["IsIdentityDataReadable"] as? Bool == true
            && !nativeTicketIdentityBookingEligible(profile)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let profile, profileOwner == principal {
                        identityStatusCard(profile)
                        if canFillIdentity {
                            identityForm(hasProfile: profile["HasProfile"] as? Bool == true)
                        }
                        if hasConsent { revokeCard }
                    } else if busy {
                        ProgressView("正在提交…")
                    } else if let error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.circle")
                                .foregroundStyle(Brand.ink)
                                .lineSpacing(3)
                            Button("重新读取状态", systemImage: "arrow.clockwise") { startLoad() }
                                .buttonStyle(.bordered)
                                .tint(Brand.primary)
                                .disabled(loading || busy)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    } else {
                        ProgressView("正在读取实名资料…")
                    }
                    if let notice { Text(notice).foregroundStyle(Brand.primary) }
                }
                .font(.system(size: NativeTypography.configuredSize(15)))
                .foregroundStyle(Brand.ink)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.background)
            .navigationTitle("实名资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .alert("撤回授权？", isPresented: Binding(
                get: { confirmRevoke && revokeConfirmationPrincipal == principal },
                set: { confirmRevoke = $0 })) {
                Button("确认撤回", role: .destructive) {
                    let expectedPrincipal = revokeConfirmationPrincipal
                    confirmRevoke = false
                    revokeConfirmationPrincipal = nil
                    startRevoke(expectedPrincipal: expectedPrincipal)
                }
                Button("暂不撤回", role: .cancel) { revokeConfirmationPrincipal = nil }
            } message: {
                Text(revokeExplanation)
            }
            .onAppear {
                pageVisible = true
                startLoad()
            }
            .onDisappear {
                pageVisible = false
                invalidate()
            }
            .onChange(of: principal) { _, _ in
                invalidate()
                startLoad()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { startLoad() }
                else { invalidate() }
            }
        }
    }

    private func identityStatusCard(_ profile: [String: Any]) -> some View {
        let hasProfile = profile["HasProfile"] as? Bool == true
        let dataReadable = profile["IsIdentityDataReadable"] as? Bool == true
        let phoneVerified = profile["IsPhoneVerified"] as? Bool == true
        let authorized = hasConsent && profile["IsConsentCurrent"] as? Bool == true && dataReadable
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if authorized { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
                        Text(consentStatus)
                    }
                    .font(.system(size: NativeTypography.configuredSize(16), weight: .semibold))
                    .foregroundStyle(authorized ? Brand.primary : Brand.ink)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("实名授权状态：\(consentStatus)")
                    .accessibilityAddTraits(.isHeader)
                    Text(phoneVerified ? "手机号已验证" : "手机号未验证")
                        .font(.system(size: NativeTypography.configuredSize(13)))
                        .foregroundStyle(Brand.muted)
                }
                Spacer(minLength: 0)
                Button {
                    startLoad()
                } label: {
                    Label("重新读取授权状态", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Brand.primary)
                .disabled(loading || busy)
            }
            if hasProfile {
                consentRow("实名姓名", detail: dataReadable ? profile["MaskedRealName"] as? String ?? "不可读取" : "不可读取")
                consentRow("身份证号", detail: dataReadable ? profile["MaskedIdentityNumber"] as? String ?? "不可读取" : "不可读取")
            }
            if let consentedAt = profile["ConsentedAt"] as? String, !consentedAt.isEmpty {
                consentRow("授权时间", detail: bookingBusinessDateTime(consentedAt) ?? consentedAt)
            }
            if hasProfile && !dataReadable {
                Text("实名资料已保存，但当前无法安全读取。请联系平台处理；修复前不能用于新的实名业务或重新授权。已产生订单的资料快照仍按原规则保留。")
                    .foregroundStyle(Brand.muted)
            }
            if !phoneVerified {
                Text("请先使用绑定手机号通过短信验证码登录，再填写实名资料。")
                    .foregroundStyle(Brand.muted)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private var revokeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("授权管理").fontWeight(.semibold).accessibilityAddTraits(.isHeader)
            Text(revokeExplanation)
                .font(.system(size: NativeTypography.configuredSize(13)))
                .foregroundStyle(Brand.muted)
            Button(role: .destructive) {
                guard let principal else { return }
                revokeConfirmationPrincipal = principal
                confirmRevoke = true
            } label: {
                Text("撤回授权")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(busy || loading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func identityForm(hasProfile: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(hasProfile ? "重新授权请填写原登记资料。" : "请按本人身份证填写。")
                .foregroundStyle(Brand.muted)
            identityField("姓名") {
                TextField("姓名", text: $realName, prompt: Text("本人真实姓名").foregroundStyle(Brand.muted))
                    .textContentType(.name).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
            }
            identityField("身份证号") {
                TextField("身份证号", text: $identityNumber, prompt: Text("18 位居民身份证号码").foregroundStyle(Brand.muted))
                    .keyboardType(.asciiCapable).textInputAutocapitalization(.characters).autocorrectionDisabled().privacySensitive()
            }
            Divider().overlay(Brand.border)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("同意实名资料授权", isOn: $identityConsent)
                    .fontWeight(.semibold)
                    .tint(Brand.primary)
                Text("姓名和身份证号将加密保存，用于实名购票、入园核验和实名消费券资格校验。可在此撤回授权，历史订单资料按原规则保留。")
                    .font(.system(size: NativeTypography.configuredSize(13)))
                    .foregroundStyle(Brand.muted)
                    .lineSpacing(3)
            }
            if let error { Text(error).foregroundStyle(.red) }
            Button {
                startSaveProfile()
            } label: {
                Text("保存并授权").fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.primary)
            .disabled(busy || loading || !identityConsent)
            Text("现场核验时，请本人出示实体身份证。登记后如需更正，请联系客服。")
                .font(.system(size: NativeTypography.configuredSize(13)))
                .foregroundStyle(Brand.muted)
                .lineSpacing(3)
        }
        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func identityField<Field: View>(_ title: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).fontWeight(.semibold).accessibilityHidden(true)
            field()
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .background(Brand.background, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9).strokeBorder(Brand.border)
                        .allowsHitTesting(false)
                }
        }
    }

    private func consentRow(_ title: String, detail: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(Brand.muted)
            Spacer(minLength: 16)
            Text(detail).foregroundStyle(Brand.ink).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Brand.border.frame(height: 1) }
    }

    private func clearEditor() {
        realName = ""; identityNumber = ""; identityConsent = false
    }

    @MainActor private func invalidate() {
        cancelReadTask()
        cancelWriteTask()
        operation += 1; clearEditor(); profile = nil; profileOwner = nil
        confirmRevoke = false; revokeConfirmationPrincipal = nil; loading = false; busy = false
        error = nil; notice = nil
    }

    @MainActor private func cancelReadTask() {
        readTaskGeneration += 1
        readTask?.cancel()
        readTask = nil
    }

    @MainActor private func startLoad() {
        guard pageVisible, scenePhase == .active else { return }
        cancelReadTask()
        cancelWriteTask()
        let generation = readTaskGeneration
        readTask = Task {
            await load()
            if readTaskGeneration == generation { readTask = nil }
        }
    }

    @MainActor private func cancelWriteTask() {
        writeTaskGeneration += 1
        writeTask?.cancel()
        writeTask = nil
    }

    @MainActor private func startSaveProfile() {
        guard writeTask == nil else { return }
        let generation = writeTaskGeneration
        writeTask = Task {
            await saveProfile()
            if writeTaskGeneration == generation { writeTask = nil }
        }
    }

    @MainActor private func startRevoke(expectedPrincipal: String?) {
        guard writeTask == nil else { return }
        let generation = writeTaskGeneration
        writeTask = Task {
            await revoke(expectedPrincipal: expectedPrincipal)
            if writeTaskGeneration == generation { writeTask = nil }
        }
    }

    private func isCurrent(_ expectedOperation: Int, principal expectedPrincipal: String) -> Bool {
        !Task.isCancelled && pageVisible && scenePhase == .active && operation == expectedOperation && principal == expectedPrincipal
    }

    @MainActor private func load() async {
        operation += 1; let requestedOperation = operation; clearEditor()
        profile = nil; profileOwner = nil; error = nil; notice = nil; busy = false; loading = false
        guard let token = store.session?.accessToken, let requestedPrincipal = nativeTourismPrincipal(token) else {
            error = "请先登录文旅账号。"; return
        }
        loading = true
        defer { if isCurrent(requestedOperation, principal: requestedPrincipal) { loading = false } }
        do {
            let value = try await MobileAPI(store: store).get("/api/JHCTITourismAuth/GetMyTicketIdentityProfile", authenticated: true,
                expectedPrincipal: requestedPrincipal) as? [String: Any]
            guard isCurrent(requestedOperation, principal: requestedPrincipal) else { return }
            guard let value, nativeTicketIdentityProfileValid(value) else {
                throw MobileAPIError.unavailable("实名资料授权状态格式异常")
            }
            profile = value; profileOwner = requestedPrincipal
        } catch {
            if isCurrent(requestedOperation, principal: requestedPrincipal) { self.error = error.localizedDescription }
        }
    }

    @MainActor private func saveProfile() async {
        guard !busy, !loading, pageVisible, scenePhase == .active, nativeTicketIdentityProfileValid(profile),
              canFillIdentity, version >= 0, let requestedPrincipal = principal,
              profileOwner == requestedPrincipal else { return }
        if let message = nativeTicketIdentityInputError(name: realName, number: identityNumber, consent: identityConsent) {
            error = message; return
        }
        let previousVersion = version
        let body: [String: Any] = ["RealName": realName.trimmingCharacters(in: .whitespacesAndNewlines),
            "IdentityNumber": identityNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            "IdentityConsent": true, "Version": previousVersion]
        operation += 1; let requestedOperation = operation
        busy = true; error = nil; notice = nil; clearEditor(); profile = nil; profileOwner = nil
        defer { if isCurrent(requestedOperation, principal: requestedPrincipal) { busy = false } }
        do {
            let result = try await MobileAPI(store: store).post("/api/JHCTITourismAuth/SaveMyTicketIdentityProfile",
                body: body, authenticated: true, expectedPrincipal: requestedPrincipal) as? [String: Any]
            guard isCurrent(requestedOperation, principal: requestedPrincipal) else { return }
            guard nativeTicketIdentitySaveReceiptValid(result, previousVersion: previousVersion) else {
                throw MobileAPIError.unavailable("实名资料保存回执异常")
            }
            profile = result; profileOwner = requestedPrincipal
        } catch {
            if isCurrent(requestedOperation, principal: requestedPrincipal) {
                if case let MobileAPIError.rejected(statusCode, message, _) = error, [400, 409].contains(statusCode) {
                    self.error = message
                } else {
                    self.error = "保存结果待确认。请先重新读取状态。如显示已登记，无需再次提交。"
                }
            }
        }
    }

    @MainActor private func revoke(expectedPrincipal: String?) async {
        guard !busy, !loading, pageVisible, scenePhase == .active, hasConsent, version > 0, let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token),
              expectedPrincipal == requestedPrincipal, principal == requestedPrincipal, profileOwner == requestedPrincipal else { return }
        operation += 1; let requestedOperation = operation; let previousVersion = version
        busy = true; error = nil; notice = nil; clearEditor(); profile = nil; profileOwner = nil
        defer { if isCurrent(requestedOperation, principal: requestedPrincipal) { busy = false } }
        do {
            let result = try await MobileAPI(store: store).post(
                "/api/JHCTITourismAuth/RevokeMyTicketIdentityConsent",
                body: ["Version": previousVersion], authenticated: true, expectedPrincipal: requestedPrincipal) as? [String: Any]
            guard isCurrent(requestedOperation, principal: requestedPrincipal) else { return }
            guard let result, nativeTicketIdentityRevokeReceiptValid(result, previousVersion: previousVersion) else {
                throw MobileAPIError.unavailable("撤回结果无法确认，请重新读取授权状态")
            }
            profile = result; profileOwner = requestedPrincipal
            notice = "实名资料授权已撤回。"
        } catch {
            if isCurrent(requestedOperation, principal: requestedPrincipal) { self.error = "撤回结果暂未确认，请重新读取实名资料状态后再操作。" }
        }
    }
}
