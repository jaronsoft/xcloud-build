import SwiftUI
import UIKit

struct NativeProfileAuthenticationForm: View {
    let loginEnabled: Bool
    let smsEnabled: Bool
    let recoveryEnabled: Bool
    let captchaImage: Data?
    let captchaKeyPresent: Bool
    let countdown: Int
    let sendingPhoneCode: Bool
    let busy: Bool
    let agreementsAccepted: Bool
    @Binding var smsMode: Bool
    @Binding var recoveryMode: Bool
    @Binding var phone: String
    @Binding var password: String
    @Binding var smsCode: String
    @Binding var captchaAnswer: String
    @Binding var recoveryPassword: String
    @Binding var recoveryPasswordConfirm: String
    @Binding var consent: Bool
    @Binding var error: String?
    let onLoadCaptcha: () -> Void
    let onSendPhoneCode: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("注册或登录")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.ink)
            HStack(spacing: 18) {
                if smsEnabled {
                    Button("短信验证码") { smsMode = true; recoveryMode = false; error = nil; onLoadCaptcha() }
                        .foregroundStyle(smsMode ? Brand.primary : Brand.muted)
                        .frame(minHeight: 44).contentShape(Rectangle())
                        .disabled(busy || sendingPhoneCode)
                }
                if loginEnabled {
                    Button("手机号密码") { smsMode = false; recoveryMode = false; error = nil }
                        .foregroundStyle(smsMode || recoveryMode ? Brand.muted : Brand.primary)
                        .frame(minHeight: 44).contentShape(Rectangle())
                        .disabled(busy || sendingPhoneCode)
                }
                if recoveryEnabled {
                    Button("找回密码") { recoveryMode = true; smsMode = false; smsCode = ""; error = nil; onLoadCaptcha() }
                        .foregroundStyle(recoveryMode ? Brand.primary : Brand.muted)
                        .frame(minHeight: 44).contentShape(Rectangle())
                        .disabled(busy || sendingPhoneCode)
                }
            }
            .font(.system(size: NativeTypography.size(14), weight: .semibold))
            TextField("请输入已绑定的手机号", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .padding(12)
                .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                .disabled(busy || sendingPhoneCode)
                .onChange(of: phone) { _, value in
                    if value.unicodeScalars.count > 11 { phone = String(value.unicodeScalars.prefix(11)) }
                }
            if smsMode || recoveryMode {
                if countdown == 0 {
                    HStack {
                        TextField("图形验证码", text: $captchaAnswer)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                            .disabled(busy || sendingPhoneCode)
                            .onChange(of: captchaAnswer) { _, value in
                                if value.unicodeScalars.count > 8 { captchaAnswer = String(value.unicodeScalars.prefix(8)) }
                            }
                        Button(action: onLoadCaptcha) {
                            if let captchaImage, let image = UIImage(data: captchaImage) {
                                Image(uiImage: image).resizable().scaledToFit().frame(width: 100, height: 42)
                            } else { Text("点击刷新").frame(width: 100, height: 42) }
                        }
                        .disabled(busy || sendingPhoneCode)
                    }
                }
                HStack {
                    TextField("请输入 6 位短信验证码", text: $smsCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding(12)
                        .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                        .disabled(busy || sendingPhoneCode)
                        .onChange(of: smsCode) { _, value in
                            if value.unicodeScalars.count > 6 { smsCode = String(value.unicodeScalars.prefix(6)) }
                        }
                    Button(action: onSendPhoneCode) {
                        HStack(spacing: 6) {
                            if sendingPhoneCode { ProgressView().controlSize(.small).tint(Brand.primary) }
                            Text(sendingPhoneCode ? "发送中…" : countdown > 0 ? "\(countdown) 秒" : "获取验证码")
                        }
                        .frame(minWidth: 88, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .disabled(busy || sendingPhoneCode || countdown > 0 || !captchaKeyPresent || captchaAnswer.isEmpty || (!recoveryMode && !consent))
                }
                if recoveryMode {
                    SecureField("设置新密码", text: $recoveryPassword)
                        .textContentType(.newPassword)
                        .padding(12).background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                        .disabled(busy || sendingPhoneCode)
                        .onChange(of: recoveryPassword) { _, value in
                            if value.unicodeScalars.count > 128 { recoveryPassword = String(value.unicodeScalars.prefix(128)) }
                        }
                    SecureField("确认新密码", text: $recoveryPasswordConfirm)
                        .textContentType(.newPassword)
                        .padding(12).background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                        .disabled(busy || sendingPhoneCode)
                        .onChange(of: recoveryPasswordConfirm) { _, value in
                            if value.unicodeScalars.count > 128 { recoveryPasswordConfirm = String(value.unicodeScalars.prefix(128)) }
                        }
                }
            } else {
                SecureField("请输入密码", text: $password)
                    .textContentType(.password)
                    .padding(12)
                    .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                    .disabled(busy || sendingPhoneCode)
                    .onChange(of: password) { _, value in
                        if value.unicodeScalars.count > 128 { password = String(value.unicodeScalars.prefix(128)) }
                    }
            }
            if !recoveryMode {
                Toggle("我已阅读并同意用户协议与隐私政策", isOn: $consent)
                    .font(.system(size: NativeTypography.size(14))).tint(Brand.primary)
                    .disabled(busy || sendingPhoneCode)
            }
            if let error { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red) }
            if !loginEnabled && !smsEnabled && !recoveryEnabled {
                Text("文旅账号登录暂未开放")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
            }
            Button(action: onSubmit) {
                HStack(spacing: 8) {
                    if busy { ProgressView().controlSize(.small).tint(.white) }
                    Text(busy ? (recoveryMode ? "正在重置…" : "正在登录…") : recoveryMode ? "重置密码" : smsMode ? "同意协议并登录或注册" : "同意协议并登录")
                }
                .frame(maxWidth: .infinity).frame(minHeight: 48)
                .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .disabled(!(recoveryMode ? recoveryEnabled : smsMode ? smsEnabled : loginEnabled) || busy || sendingPhoneCode || (!recoveryMode && (!consent || !agreementsAccepted)) || phone.isEmpty ||
                      (recoveryMode ? smsCode.count != 6 || recoveryPassword.isEmpty || recoveryPasswordConfirm.isEmpty : smsMode ? smsCode.count != 6 : password.isEmpty))
            .font(.system(size: NativeTypography.size(14), weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .background((recoveryMode ? recoveryEnabled : smsMode ? smsEnabled : loginEnabled) && !busy && (recoveryMode || consent && agreementsAccepted) && !phone.isEmpty &&
                        (recoveryMode ? smsCode.count == 6 && !recoveryPassword.isEmpty && !recoveryPasswordConfirm.isEmpty : smsMode ? smsCode.count == 6 : !password.isEmpty) ? Brand.primary : Brand.muted,
                        in: RoundedRectangle(cornerRadius: 9))
            .buttonStyle(.plain)
            Text(recoveryMode ? "验证码发送响应不会确认手机号是否已注册；密码须为 8 至 128 位，并同时包含英文字母和数字。" : smsMode ? "使用短信验证码登录；新手机号将按平台配置注册。" : "使用已设置密码的文旅账号登录；未设置密码请使用短信验证码。")
                .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
        }
        .font(.system(size: NativeTypography.size(14)))
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}
