import SwiftUI

@MainActor
extension ProfileView {
    func loadAgreements() async {
        let api = MobileAPI(store: store)
        do { loginEnabled = try await api.passwordLoginEnabled() }
        catch { if Task.isCancelled { return }; loginEnabled = false }
        do { smsEnabled = try await api.smsLoginEnabled() }
        catch { if Task.isCancelled { return }; smsEnabled = false }
        do {
            guard let enabled = try await api.get("/api/JHCTITourismAuth/GetMemberRegistrationAvailability") as? Bool else {
                throw MobileAPIError.unavailable("会员注册状态回执异常")
            }
            memberRegistrationEnabled = enabled
        } catch {
            if Task.isCancelled { return }
            memberRegistrationEnabled = false
        }
        do { recoveryEnabled = try await api.passwordRecoveryEnabled() }
        catch { if Task.isCancelled { return }; recoveryEnabled = false }
        if Task.isCancelled { return }
        if smsEnabled { smsMode = true; await loadCaptcha() }
        do {
            var loaded: [AgreementContent] = []
            for type in ["Terms", "Privacy"] {
                guard let value = try await api.get("/api/JHCTIUserAgreement/GetCurrent?agreementType=\(type)") as? [String: Any],
                      let id = value["Id"] as? String else { throw MobileAPIError.unavailable("协议尚未发布") }
                loaded.append(AgreementContent(id: id, kind: type,
                    title: value["TitleZh"] as? String ?? type,
                    content: value["ContentZh"] as? String ?? ""))
            }
            if !Task.isCancelled { agreements = loaded }
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    func login() async {
        guard !busy && !sendingPhoneCode else { return }
        guard recoveryMode || agreements.count == 2 else { error = "当前协议尚未加载完成，请刷新后重试"; return }
        busy = true; error = nil
        var passwordResetRequestMayHaveReachedServer = false
        do {
            guard phone.range(of: "^1[3-9][0-9]{9}$", options: .regularExpression) != nil else {
                throw MobileAPIError.unavailable("请输入有效的大陆手机号")
            }
            if recoveryMode {
                guard smsCode.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else {
                    throw MobileAPIError.unavailable("请输入 6 位短信验证码")
                }
                let passwordScalars = Array(recoveryPassword.unicodeScalars)
                let hasAsciiLetter = passwordScalars.contains { (65...90).contains($0.value) || (97...122).contains($0.value) }
                let hasAsciiDigit = passwordScalars.contains { (48...57).contains($0.value) }
                guard passwordScalars.count >= 8 && passwordScalars.count <= 128
                        && recoveryPassword.utf8.count <= 512 && hasAsciiLetter && hasAsciiDigit else {
                    throw MobileAPIError.unavailable("密码为 8 至 128 位，且同时包含英文字母和数字")
                }
                guard recoveryPassword == recoveryPasswordConfirm else {
                    throw MobileAPIError.unavailable("两次输入的密码不一致")
                }
                guard try await MobileAPI(store: store).passwordRecoveryEnabled() else {
                    recoveryEnabled = false
                    throw MobileAPIError.unavailable("密码找回服务暂未开放")
                }
                passwordResetRequestMayHaveReachedServer = true
                try await MobileAPI(store: store).resetPasswordWithPhoneCode(phone: phone, code: smsCode, password: recoveryPassword)
                recoveryMode = false
                smsMode = loginEnabled
                smsCode = ""; password = ""; recoveryPassword = ""; recoveryPasswordConfirm = ""
                error = "密码已重置，请使用新密码登录"
            } else if smsMode {
                guard try await MobileAPI(store: store).smsLoginEnabled() else {
                    smsEnabled = false
                    throw MobileAPIError.unavailable("短信验证码登录暂未开放")
                }
                try await MobileAPI(store: store).loginWithPhoneCode(phone: phone, code: smsCode, agreementIDs: agreements.map(\.id))
                authOpen = false
            } else {
                guard try await MobileAPI(store: store).passwordLoginEnabled() else {
                    loginEnabled = false
                    throw MobileAPIError.unavailable("文旅账号登录暂未开放")
                }
                try await MobileAPI(store: store).login(phone: phone, password: password, agreementIDs: agreements.map(\.id))
                authOpen = false
            }
        } catch {
            if !Task.isCancelled {
                let isDefinitiveClientRejection = (error as? MobileAPIError).map { apiError in
                    guard let statusCode = apiError.httpStatusCode else { return false }
                    return (400..<500).contains(statusCode)
                } ?? false
                let message = error.localizedDescription
                self.error = passwordResetRequestMayHaveReachedServer && !isDefinitiveClientRejection
                    ? "\(message) 若不确定是否完成，请先尝试使用新密码登录；确认无法登录后，再重新获取验证码重置。"
                    : message
            }
        }
        busy = false
    }

    func loadCaptcha() async {
        captchaRequestGeneration &+= 1
        let requestGeneration = captchaRequestGeneration
        do {
            let challenge = try await MobileAPI(store: store).captcha()
            guard requestGeneration == captchaRequestGeneration else { return }
            captchaKey = challenge.key
            captchaImage = challenge.image
            captchaAnswer = ""
        } catch {
            if !Task.isCancelled && requestGeneration == captchaRequestGeneration {
                self.error = error.localizedDescription
            }
        }
    }

    func sendPhoneCode() async {
        guard !busy && !sendingPhoneCode else { return }
        guard phone.range(of: "^1[3-9][0-9]{9}$", options: .regularExpression) != nil else {
            error = "请输入有效的大陆手机号"; return
        }
        authRequestGeneration &+= 1
        let requestGeneration = authRequestGeneration
        sendingPhoneCode = true; error = nil
        do {
            let testCode: String?
            let captcha = captchaAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            if recoveryMode {
                testCode = try await MobileAPI(store: store).sendPasswordRecoveryCode(phone: phone, captchaKey: captchaKey, captcha: captcha)
            } else {
                testCode = try await MobileAPI(store: store).sendPhoneCode(phone: phone, captchaKey: captchaKey, captcha: captcha)
            }
            guard requestGeneration == authRequestGeneration else { return }
            if let testCode, testCode.range(of: "^[0-9]{6}$", options: .regularExpression) != nil { smsCode = testCode }
            countdown = 60
            countdownGeneration &+= 1
            let timerGeneration = countdownGeneration
            Task {
                while countdown > 0 && timerGeneration == countdownGeneration {
                    try? await Task.sleep(for: .seconds(1))
                    guard countdown > 0 && timerGeneration == countdownGeneration else { return }
                    countdown -= 1
                }
            }
        } catch {
            if !Task.isCancelled && requestGeneration == authRequestGeneration {
                self.error = error.localizedDescription
            }
        }
        guard requestGeneration == authRequestGeneration else { return }
        sendingPhoneCode = false
        if !Task.isCancelled && requestGeneration == authRequestGeneration { await loadCaptcha() }
    }
}
