import SwiftUI

struct AgreementContent: Identifiable {
    let id: String
    let kind: String
    let title: String
    let content: String
}

struct NativeProfileAboutView: View {
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button("‹ 返回个人中心", action: onBack)
                    .font(.system(size: NativeTypography.size(14), weight: .medium))
                    .foregroundStyle(Brand.primary)
                Text("关于悦行江都")
                    .font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif))
                    .foregroundStyle(Brand.ink)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image("Logo").resizable().scaledToFit().frame(width: 52, height: 52)
                        Text("悦行江都")
                            .font(.system(size: NativeTypography.size(18), weight: .semibold))
                            .foregroundStyle(Brand.ink)
                    }
                    Text("发现江都，规划旅程，体验本地文旅生活。")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    Brand.border.frame(height: 1)
                    HStack {
                        Text("当前版本").foregroundStyle(Brand.muted)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                            .foregroundStyle(Brand.ink)
                    }
                    .font(.system(size: NativeTypography.size(14)))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 16).padding(.top, 14)
        }
        .background(Brand.background)
    }
}

struct NativeAgreementContentView: View {
    let agreement: AgreementContent
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(agreement.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(agreement.title)
            .toolbar { Button("关闭", action: onClose) }
        }
    }
}

struct NativeProfileSessionActionsView: View {
    @ObservedObject var store: SessionStore
    let displayName: String
    let phone: String
    let profileVersion: Int64?
    let loggingOut: Bool
    let busy: Bool
    let onLogout: () -> Void
    let onCancelAccount: () -> Void
    let onProfileUpdated: ([String: Any]) -> Void
    let onReloadProfile: () -> Void
    @State private var phoneChangeOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(displayName)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.ink)
            Text(phone)
                .font(.system(size: 14)).foregroundStyle(Brand.muted)
            Button("更换手机号") { phoneChangeOpen = true }
                .font(.system(size: 13, weight: .medium))
                .disabled(loggingOut || busy || profileVersion == nil)
            Button(role: .destructive, action: onLogout) {
                HStack(spacing: 7) {
                    if loggingOut { ProgressView().controlSize(.small) }
                    Text(loggingOut ? "正在退出…" : "退出登录")
                        .font(.system(size: NativeTypography.size(16), weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.primary)
            .disabled(loggingOut)
            Button(role: .destructive, action: onCancelAccount) {
                Text("注销文旅账号")
                    .font(.system(size: NativeTypography.size(12), weight: .medium))
                    .padding(.horizontal, 12).frame(minHeight: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(loggingOut || busy)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $phoneChangeOpen) {
            if let profileVersion {
                NativeProfilePhoneChangeView(store: store, profileVersion: profileVersion,
                    onUpdated: onProfileUpdated, onReload: onReloadProfile)
            }
        }
    }
}

private struct NativeProfilePhoneChangeView: View {
    @ObservedObject var store: SessionStore
    let profileVersion: Int64
    let onUpdated: ([String: Any]) -> Void
    let onReload: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var currentPhone = ""
    @State private var newPhone = ""
    @State private var currentCode = ""
    @State private var newCode = ""
    @State private var busy = false
    @State private var error: String?
    @State private var mustReload = false

    var body: some View {
        NavigationStack {
            Form {
                Section("验证当前手机号") {
                    TextField("当前手机号", text: $currentPhone).keyboardType(.numberPad).textContentType(.telephoneNumber)
                        .disabled(busy || mustReload)
                        .onChange(of: currentPhone) { _, _ in currentCode = "" }
                    TextField("当前号码验证码", text: $currentCode).keyboardType(.numberPad)
                        .disabled(busy || mustReload)
                    NativeProfilePhoneCodeSender(store: store, phone: currentPhone, purpose: "current",
                        disabled: busy || mustReload)
                }
                Section("验证新手机号") {
                    TextField("新手机号", text: $newPhone).keyboardType(.numberPad).textContentType(.telephoneNumber)
                        .disabled(busy || mustReload)
                        .onChange(of: newPhone) { _, _ in newCode = "" }
                    TextField("新号码验证码", text: $newCode).keyboardType(.numberPad)
                        .disabled(busy || mustReload)
                    NativeProfilePhoneCodeSender(store: store, phone: newPhone, purpose: "new",
                        disabled: busy || mustReload)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Button(busy ? "正在更新…" : mustReload ? "重新读取账号资料" : "确认更换手机号") {
                    if mustReload { onReload(); dismiss(); return }
                    Task { await submit() }
                }
                .disabled(mustReload ? false : busy || !validPhone(currentPhone) || !validPhone(newPhone)
                          || currentCode.count != 6 || newCode.count != 6)
            }
            .navigationTitle("更换手机号")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }

    private func validPhone(_ value: String) -> Bool {
        value.range(of: "^1[3-9][0-9]{9}$", options: .regularExpression) != nil
    }

    private func submit() async {
        guard !busy, let token = store.session?.accessToken,
              let principal = nativeTourismPrincipal(token) else { error = "登录账号不可用，请重新登录"; return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let profile = try await MobileAPI(store: store).changePhoneNumber(currentPhone: currentPhone,
                currentCode: currentCode, newPhone: newPhone, newCode: newCode,
                version: profileVersion, expectedPrincipal: principal)
            guard store.session?.accessToken == token else { error = "登录账号已变化，请重新读取资料"; mustReload = true; return }
            onUpdated(profile)
            dismiss()
        } catch {
            if (error as? MobileAPIError)?.httpStatusCode == 409 {
                self.error = "本次更换未执行，账号手机号未更改。\(error.localizedDescription) 请重新读取账号资料后再继续。"
            } else {
                self.error = "手机号更换结果暂不可确认；请重新读取账号资料核对绑定状态，不要直接重复提交。\(error.localizedDescription)"
            }
            mustReload = true
        }
    }
}

private struct NativeProfilePhoneCodeSender: View {
    @ObservedObject var store: SessionStore
    let phone: String
    let purpose: String
    let disabled: Bool
    @State private var captchaKey = ""
    @State private var captcha = ""
    @State private var image: Data?
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("图形验证码", text: $captcha).textInputAutocapitalization(.never)
                if let image, let uiImage = UIImage(data: image) {
                    Image(uiImage: uiImage).resizable().scaledToFit().frame(width: 92, height: 38)
                        .onTapGesture { if !disabled { Task { await loadCaptcha() } } }
                } else {
                    Button("加载/刷新图形码") { Task { await loadCaptcha() } }.disabled(disabled)
                }
            }
            Button(busy ? "处理中…" : purpose == "current" ? "发送当前号码验证码" : "发送新号码验证码") {
                Task { await sendCode() }
            }
            .disabled(disabled || busy || captchaKey.isEmpty || captcha.isEmpty || phone.count != 11)
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .task { await loadCaptcha() }
    }

    private func loadCaptcha() async {
        busy = true; captchaKey = ""; image = nil; captcha = ""
        defer { busy = false }
        do {
            let value = try await MobileAPI(store: store).captcha()
            captchaKey = value.key; image = value.image
        } catch { message = error.localizedDescription }
    }

    private func sendCode() async {
        guard phone.range(of: "^1[3-9][0-9]{9}$", options: .regularExpression) != nil else {
            message = "请输入有效的大陆手机号"; return
        }
        guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else {
            message = "登录账号已变化，请重新操作"; return
        }
        busy = true; message = nil
        defer { busy = false }
        do {
            let code = try await MobileAPI(store: store).sendPhoneChangeCode(phone: phone, purpose: purpose,
                captchaKey: captchaKey, captcha: captcha, expectedPrincipal: principal)
            guard store.session?.accessToken == token else { message = "登录账号已变化，请重新操作"; return }
            if let code, !code.isEmpty { message = "验证码已发送（Development：\(code)）" }
            else { message = "验证码已发送，请查收短信" }
            await loadCaptcha()
        } catch {
            if let status = (error as? MobileAPIError)?.httpStatusCode,
               (400..<500).contains(status), status != 408, status != 429 {
                message = "验证码发送请求已被拒绝：\(error.localizedDescription)"
            } else {
                message = "验证码发送状态暂无法确认。若已收到短信，请填写验证码继续；否则先核对状态再决定是否重发：\(error.localizedDescription)"
            }
            await loadCaptcha()
        }
    }
}
