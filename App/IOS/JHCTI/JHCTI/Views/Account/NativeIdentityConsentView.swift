import SwiftUI

struct NativeIdentityConsentView: View {
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
    @State private var editorOpen = false
    @State private var operation = 0
    @State private var readTask: Task<Void, Never>?
    @State private var readTaskGeneration = 0
    @State private var writeTask: Task<Void, Never>?
    @State private var writeTaskGeneration = 0
    @State private var pageVisible = true

    private var principal: String? { nativeTourismPrincipal(store.session?.accessToken) }
    private var hasConsent: Bool { profile?["HasConsent"] as? Bool == true }
    private var consentStatus: String {
        guard hasConsent else { return "未授权" }
        return profile?["IsConsentCurrent"] as? Bool == false ? "已授权（告知版本已更新）" : "已授权"
    }
    private var version: Int64 {
        nativeTicketIdentityVersion(profile) ?? -1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("实名资料仅用于需要实名的购票业务。撤回后，后续实名购票需重新授权；已产生订单中的资料快照按原规则保留。")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    if loading {
                        ProgressView("正在读取授权记录…").frame(maxWidth: .infinity, alignment: .leading)
                    } else if let profile, profileOwner == principal {
                        VStack(alignment: .leading, spacing: 10) {
                            consentRow("授权状态", detail: consentStatus)
                            consentRow("实名姓名", detail: profile["MaskedRealName"] as? String ?? "未登记")
                            consentRow("身份证号", detail: profile["MaskedIdentityNumber"] as? String ?? "未登记")
                            consentRow("告知版本", detail: profile["ConsentVersion"] as? String ?? "—")
                            consentRow("授权时间", detail: profile["ConsentedAt"] as? String ?? "—")
                            if hasConsent {
                                Button(role: .destructive) {
                                    guard let principal else { return }
                                    revokeConfirmationPrincipal = principal
                                    confirmRevoke = true
                                } label: {
                                    HStack { Spacer(); Text(busy ? "正在撤回…" : "撤回实名资料授权"); Spacer() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(busy || loading)
                            } else {
                                Text("当前没有有效的实名资料授权，请先登记或重新授权后再购买实名门票。")
                                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            }
                            if profile["IsPhoneVerified"] as? Bool != true {
                                Text("请先返回个人中心验证绑定手机号，再登记实名购票资料。")
                                    .font(.footnote).foregroundStyle(Brand.muted)
                            } else if profile["IsConsentCurrent"] as? Bool != true {
                                if editorOpen {
                                    Text(profile["HasProfile"] as? Bool == true ? "重新授权时请填写原登记资料；如需更正，请联系客服核验。" : "请填写本人资料。登记后不能自行更改，如需更正请联系客服核验。")
                                        .font(.footnote).foregroundStyle(Brand.muted)
                                    TextField("真实姓名", text: $realName).textContentType(.name)
                                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                                    TextField("18 位居民身份证号码", text: $identityNumber)
                                        .keyboardType(.asciiCapable).textInputAutocapitalization(.characters).autocorrectionDisabled().privacySensitive()
                                    Toggle("我同意为实名购票及入园核验加密保存姓名和身份证号码。可在此撤回授权，历史订单资料按原规则保留。", isOn: $identityConsent)
                                        .font(.footnote)
                                    Button(busy ? "正在保存…" : "同意并保存实名资料") { startSaveProfile() }
                                        .buttonStyle(.borderedProminent).disabled(busy || loading)
                                    Button("取消填写") { clearEditor() }.disabled(busy)
                                } else {
                                    Button(profile["HasProfile"] as? Bool == true ? "重新授权实名资料" : "登记实名购票资料") {
                                        clearEditor(); editorOpen = true; error = nil; notice = nil
                                    }.buttonStyle(.borderedProminent).disabled(busy || loading)
                                }
                            }
                        }
                        .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let error { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red) }
                    if let notice { Text(notice).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary) }
                    Button("重新读取") { startLoad() }
                        .disabled(loading || busy)
                }
                .padding(16)
            }
            .background(Brand.background)
            .navigationTitle("实名资料授权")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .confirmationDialog("撤回实名资料授权？", isPresented: Binding(
                get: { confirmRevoke && revokeConfirmationPrincipal == principal },
                set: { presented in
                    confirmRevoke = presented
                    if !presented { revokeConfirmationPrincipal = nil }
                }), titleVisibility: .visible) {
                Button("确认撤回", role: .destructive) {
                    let expectedPrincipal = revokeConfirmationPrincipal
                    confirmRevoke = false
                    startRevoke(expectedPrincipal: expectedPrincipal)
                }
                Button("暂不撤回", role: .cancel) { }
            } message: {
                Text("撤回后，之后的实名购票需要重新授权；已产生订单的资料快照仍会保留。")
            }
            .task(id: principal) {
                confirmRevoke = false
                revokeConfirmationPrincipal = nil
                startLoad()
            }
            .onAppear { pageVisible = true }
            .onDisappear { invalidate() }
            .onChange(of: principal) { _, _ in
                cancelReadTask()
                cancelWriteTask()
                operation += 1
                clearEditor(); profile = nil; profileOwner = nil
                loading = false; busy = false; error = nil; notice = nil
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { pageVisible = true; startLoad() }
                else { invalidate() }
            }
        }
    }

    private func consentRow(_ title: String, detail: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(Brand.muted)
            Spacer(minLength: 16)
            Text(detail).foregroundStyle(Brand.ink).multilineTextAlignment(.trailing)
        }
        .font(.system(size: NativeTypography.size(14)))
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Brand.border.frame(height: 1) }
    }

    private func clearEditor() {
        realName = ""; identityNumber = ""; identityConsent = false; editorOpen = false
    }

    @MainActor private func invalidate() {
        cancelReadTask()
        cancelWriteTask()
        operation += 1; pageVisible = false; clearEditor(); profile = nil; profileOwner = nil
        confirmRevoke = false; revokeConfirmationPrincipal = nil; loading = false; busy = false
        error = nil; notice = nil
    }

    @MainActor private func cancelReadTask() {
        readTaskGeneration += 1
        readTask?.cancel()
        readTask = nil
    }

    @MainActor private func startLoad() {
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
        if isCurrent(requestedOperation, principal: requestedPrincipal) { loading = false }
    }

    @MainActor private func saveProfile() async {
        guard !busy, !loading, pageVisible, scenePhase == .active, nativeTicketIdentityProfileValid(profile),
              profile?["IsPhoneVerified"] as? Bool == true, editorOpen, version >= 0, let requestedPrincipal = principal,
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
            profile = result; profileOwner = requestedPrincipal; notice = "实名购票资料已登记并授权。"
        } catch {
            if isCurrent(requestedOperation, principal: requestedPrincipal) {
                self.error = "保存结果暂未确认，请重新读取实名资料状态后再操作；如已登记需更正，请联系客服。"
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
            guard let result, nativeTicketIdentityProfileValid(result), result["HasConsent"] as? Bool == false,
                  (nativeTicketIdentityVersion(result) ?? -1) > previousVersion else {
                throw MobileAPIError.unavailable("撤回结果无法确认，请重新读取授权状态")
            }
            profile = result; profileOwner = requestedPrincipal
            notice = "实名资料授权已撤回。"
        } catch {
            if isCurrent(requestedOperation, principal: requestedPrincipal) { self.error = "撤回结果暂未确认，请重新读取实名资料状态后再操作。" }
        }
    }
}
