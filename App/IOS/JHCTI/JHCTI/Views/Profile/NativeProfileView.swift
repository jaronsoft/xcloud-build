import SwiftUI
import CoreFoundation
import AVFoundation
import AVKit
import Combine
import VisionKit
import MapKit
import CoreLocation
import CryptoKit
import PhotosUI
import CoreTransferable
import ImageIO
import UIKit
import WebKit
import UniformTypeIdentifiers

struct ProfileView: View {
    @ObservedObject var store: SessionStore
    let couponCenterRequested: Bool
    let onCouponCenterRequestHandled: () -> Void
    @StateObject private var profileRuntime: NativeProfileSummaryRuntime
    @State private var aboutOpen = false
    @State private var authOpen = false
    @State private var allServicesOpen = false
    @State private var activityRegistrationsOpen = false
    @State private var activityVerificationOpen = false
    @State private var ticketVerificationOpen = false
    @State private var couponVerificationOpen = false
    @State private var favoritesOpen = false
    @State private var memberLedgerOpen = false
    @State private var productReviewsOpen = false
    @State private var commerceOrdersOpen = false
    @State private var ticketOrdersOpen = false
    @State private var couponsOpen = false
    @State private var diningPackageOrdersOpen = false
    @State private var supportTicketsOpen = false
    @State private var merchantOnboardingOpen = false
    @State private var bookingOrdersOpen = false
    @State private var bookingOrdersKind = "hotel"
    @State private var identityConsentOpen = false
    @State private var accountCancellationOpen = false
    @State private var accountCancellationWarningOpen = false
    @State private var accountCancellationPrincipal: String?
    @State private var cartOpen = false
    @State private var addressBookOpen = false
    @State private var merchantWorkbenchOpen = false
    @State private var restaurantWorkbenchOpen = false
    @State private var serviceNotice: String?
    @State private var phone = ""
    @State private var password = ""
    @State private var smsCode = ""
    @State private var captchaAnswer = ""
    @State private var captchaKey = ""
    @State private var captchaImage: Data?
    @State private var smsMode = false
    @State private var recoveryMode = false
    @State private var smsEnabled = false
    @State private var recoveryEnabled = false
    @State private var recoveryPassword = ""
    @State private var recoveryPasswordConfirm = ""
    @State private var countdown = 0
    @State private var countdownGeneration = 0
    @State private var authRequestGeneration = 0
    @State private var captchaRequestGeneration = 0
    @State private var consent = true
    @State private var agreements: [AgreementContent] = []
    @State private var shownAgreement: AgreementContent?
    @State private var error: String?
    @State private var busy = false
    @State private var sendingPhoneCode = false
    @State private var loggingOut = false
    @State private var loginEnabled = false
    @State private var cacheBytes = 0
    @State private var cacheManagementOpen = false
    @State private var clearImageCacheSelected = true
    @State private var clearDataCacheSelected = true
    @State private var clearOtherCacheSelected = true

    init(store: SessionStore, couponCenterRequested: Bool, onCouponCenterRequestHandled: @escaping () -> Void) {
        self.store = store
        self.couponCenterRequested = couponCenterRequested
        self.onCouponCenterRequestHandled = onCouponCenterRequestHandled
        _profileRuntime = StateObject(wrappedValue: NativeProfileSummaryRuntime(store: store))
    }

    private var displayName: String {
        let name = profileRuntime.tourismProfile?["PendingDisplayName"] as? String ?? profileRuntime.tourismProfile?["DisplayName"] as? String ?? ""
        return name.isEmpty ? (store.session?.userName.isEmpty == false ? store.session!.userName : "欢迎来到悦行江都") : name
    }

    private var avatarURL: URL? {
        let path = profileRuntime.tourismProfile?["PendingAvatarUrl"] as? String ?? profileRuntime.tourismProfile?["AvatarUrl"] as? String
        return MobileAPI(store: store).mediaURL(path)
    }

    private var profileSubtitle: String? {
        guard store.session != nil else { return "注册或登录后，可同步个人服务" }
        return profileRuntime.tourismProfile?["ProfileReviewStatus"] as? String == "Pending"
            ? "资料审核中；审核通过后对外生效" : nil
    }

    private var termsAgreement: AgreementContent? {
        agreements.first(where: { $0.kind == "Terms" })
    }

    private var privacyAgreement: AgreementContent? {
        agreements.first(where: { $0.kind == "Privacy" })
    }

    private var loginAvailable: Bool {
        loginEnabled || smsEnabled || recoveryEnabled
    }

    private var loginPrompt: String {
        loginAvailable ? "登录后同步个人收藏、票券和行程信息。" : "文旅账号登录功能暂未开放；公开内容仍可浏览。"
    }

    private func openWorkAccess(_ title: String) {
        switch title {
        case "商户工作台": merchantWorkbenchOpen = true
        case "餐饮工作台": restaurantWorkbenchOpen = true
        case "活动现场签到": activityVerificationOpen = true
        case "门票核销": ticketVerificationOpen = true
        case "平台消费券核销": couponVerificationOpen = true
        default: serviceNotice = title + "原生工作台正在完善"
        }
    }

    private func clearAccountAuthSecrets() {
        authRequestGeneration &+= 1
        captchaRequestGeneration &+= 1
        countdownGeneration &+= 1
        phone = ""; password = ""; smsCode = ""; captchaAnswer = ""; captchaKey = ""
        captchaImage = nil; recoveryPassword = ""; recoveryPasswordConfirm = ""
        smsMode = false; recoveryMode = false; countdown = 0; sendingPhoneCode = false
        consent = true; shownAgreement = nil; error = nil
    }

    private func openAccountService(_ name: String) {
        allServicesOpen = false
        switch name {
        case "我的活动报名":
            if store.session == nil { serviceNotice = "请先登录文旅账号，再查看活动报名记录。" }
            else { activityRegistrationsOpen = true }
        case "我的收藏":
            if store.session == nil { serviceNotice = "请先登录文旅账号，再查看个人收藏。" }
            else { favoritesOpen = true }
        case "积分与成长值":
            if store.session == nil { serviceNotice = "请先登录文旅账号，再查看积分与成长值。" }
            else { memberLedgerOpen = true }
        case "我的商品评价":
            if store.session == nil { serviceNotice = "请先登录文旅账号，再查看商品评价。" }
            else { productReviewsOpen = true }
        case "门票核销":
            if store.session == nil { serviceNotice = "请先登录已获授权的文旅工作人员账号，再使用门票核销。" }
            else { ticketVerificationOpen = true }
        case "我的消费券": couponsOpen = true
        default: serviceNotice = name + "原生页面正在完善"
        }
    }

    private func openHelpService(_ name: String) {
        allServicesOpen = false
        switch name {
        case "客服与反馈":
            guard store.session != nil else { serviceNotice = "请先登录文旅账号，再提交问题或查看处理进度。"; return }
            supportTicketsOpen = true
        case "商户入驻":
            guard store.session != nil else { serviceNotice = "请先登录文旅账号，再提交商户入驻申请。"; return }
            merchantOnboardingOpen = true
        default: serviceNotice = name + "原生页面正在完善"
        }
    }

    var body: some View {
        NavigationStack {
            if aboutOpen {
                NativeProfileAboutView { aboutOpen = false }
            } else if !authOpen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("个人中心").font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif))
                            .foregroundStyle(Brand.ink)
                            .padding(.bottom, 2)
                        NativeProfileIdentitySection(
                            displayName: displayName,
                            avatarURL: avatarURL,
                            subtitle: profileSubtitle,
                            isAuthenticated: store.session != nil,
                            memberLevel: profileRuntime.memberLevel,
                            workAccess: profileRuntime.workAccess,
                            onOpenProfile: { if store.session != nil { authOpen = true } }
                        )
                        if store.session == nil {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("文旅账号").font(.system(size: 16, weight: .semibold))
                            Text(loginPrompt)
                                .font(.system(size: 14)).foregroundStyle(Brand.muted)
                            Button("注册或登录") { authOpen = true }
                                .disabled(!loginAvailable)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(minHeight: 48)
                                .background(loginAvailable ? Brand.primary : Brand.muted, in: Capsule())
                                .buttonStyle(.plain)
                                .contentShape(Capsule())
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 11))
                        }
                        if let profileError = profileRuntime.error, store.session != nil {
                            Button("账号资料读取失败，点此重试：\(profileError)") { Task { await profileRuntime.load() } }
                                .font(.system(size: 14)).foregroundStyle(Brand.primary)
                        }
                        NativeProfileCommonServicesSection(
                            onSelect: openCommonService,
                            onShowAll: { allServicesOpen = true }
                        )
                        if store.session != nil && !profileRuntime.workAccess.isEmpty {
                            NativeProfileWorkAccessSection(workAccess: profileRuntime.workAccess, onSelect: openWorkAccess)
                        }
                        if store.session != nil {
                            NativeProfileAccountSettingsHeader { authOpen = true }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("协议与关于")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.muted)
                                .padding(.bottom, 5)
                            if store.session == nil {
                                profileInfoRow("用户服务协议", detail: termsAgreement == nil ? "暂不可用" : "查看 ›") {
                                    shownAgreement = termsAgreement
                                }
                                profileInfoRow("隐私政策", detail: privacyAgreement == nil ? "暂不可用" : "查看 ›") {
                                    shownAgreement = privacyAgreement
                                }
                            }
                            profileInfoRow("实名购票资料授权", detail: "查看记录 ›") {
                                identityConsentOpen = true
                            }
                            profileInfoRow("清理缓存", detail: "\(ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file))  管理 ›") {
                                clearImageCacheSelected = true
                                clearDataCacheSelected = true
                                clearOtherCacheSelected = true
                                cacheManagementOpen = true
                            }
                            profileInfoRow("关于悦行江都", detail: "版本信息  \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0") ›") {
                                aboutOpen = true
                            }
                        }
                        .padding(13)
                        .background(.white, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
                }
                .background(Brand.background)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("‹ 返回个人中心") { authOpen = false }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Brand.primary)
                            .disabled(busy || sendingPhoneCode)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("文旅账号")
                                .font(.system(size: 24, weight: .bold, design: .serif))
                                .foregroundStyle(Brand.ink)
                            Text(loginEnabled ? "登录后同步个人收藏、票券和行程信息" : "登录服务状态由平台运营配置")
                                .font(.system(size: 14)).foregroundStyle(Brand.muted)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("用户协议").font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Brand.ink)
                            if let error, agreements.isEmpty {
                                Text(error).font(.system(size: 14)).foregroundStyle(.red)
                            }
                            if agreements.isEmpty && error == nil {
                                Text("正在读取当前生效版本…")
                                    .font(.system(size: 14)).foregroundStyle(Brand.muted)
                            }
                            ForEach(agreements) { item in
                                Button { shownAgreement = item } label: {
                                    HStack {
                                        Text(item.title).foregroundStyle(Brand.ink)
                                        Spacer()
                                        Text("查看 ›").foregroundStyle(Brand.primary)
                                    }
                                    .font(.system(size: 14)).frame(height: 36)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        if let session = store.session {
                            NativeProfileSessionActionsView(
                                displayName: displayName,
                                phone: profileRuntime.tourismProfile?["MaskedPhoneNumber"] as? String ?? session.userName,
                                loggingOut: loggingOut,
                                busy: busy,
                                onLogout: {
                                    guard !loggingOut else { return }
                                    loggingOut = true
                                    Task {
                                        await MobileAPI(store: store).logout()
                                        clearAccountAuthSecrets()
                                        loggingOut = false
                                    }
                                },
                                onCancelAccount: { accountCancellationWarningOpen = true }
                            )
                        } else {
                            NativeProfileAuthenticationForm(
                                loginEnabled: loginEnabled,
                                smsEnabled: smsEnabled,
                                recoveryEnabled: recoveryEnabled,
                                captchaImage: captchaImage,
                                captchaKeyPresent: !captchaKey.isEmpty,
                                countdown: countdown,
                                sendingPhoneCode: sendingPhoneCode,
                                busy: busy,
                                agreementsAccepted: agreements.count == 2,
                                smsMode: $smsMode,
                                recoveryMode: $recoveryMode,
                                phone: $phone,
                                password: $password,
                                smsCode: $smsCode,
                                captchaAnswer: $captchaAnswer,
                                recoveryPassword: $recoveryPassword,
                                recoveryPasswordConfirm: $recoveryPasswordConfirm,
                                consent: $consent,
                                error: $error,
                                onLoadCaptcha: { Task { await loadCaptcha() } },
                                onSendPhoneCode: { Task { await sendPhoneCode() } },
                                onSubmit: { Task { await login() } }
                            )
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 24)
                }
                .background(Brand.background)
            }
        }
        .task {
            cacheBytes = NativePublicCache.shared.sizeBytes() + URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
            await loadAgreements()
        }
        .task(id: store.session?.accessToken) { await profileRuntime.load() }
        .onChange(of: authOpen) { _, isOpen in
            if isOpen && store.session == nil { consent = true }
        }
            .alert("服务提示", isPresented: Binding(
                get: { serviceNotice != nil },
                set: { if !$0 { serviceNotice = nil } }
            )) { Button("知道了") { serviceNotice = nil } } message: {
                Text(serviceNotice ?? "")
            }
            .alert("确认注销文旅账号？", isPresented: $accountCancellationWarningOpen) {
                Button("暂不注销", role: .cancel) { }
                Button("继续注销", role: .destructive) {
                    accountCancellationPrincipal = store.session.flatMap { nativeTourismPrincipal($0.accessToken) }
                    accountCancellationOpen = true
                }
            } message: {
                Text("注销后将退出全部设备，且无法恢复。订单和必要记录仍按规定保留。继续后还需输入“注销”完成确认。")
            }
            .sheet(isPresented: $cacheManagementOpen) {
                NavigationStack {
                    List {
                        Section("选择要清理的缓存") {
                            Toggle("图片缓存　\(ByteCountFormatter.string(fromByteCount: Int64(NativePublicCache.shared.sizeBytes(in: "images")), countStyle: .file))", isOn: $clearImageCacheSelected)
                            Toggle("数据缓存　\(ByteCountFormatter.string(fromByteCount: Int64(NativePublicCache.shared.sizeBytes(in: "data")), countStyle: .file))", isOn: $clearDataCacheSelected)
                            Toggle("其他缓存　\(ByteCountFormatter.string(fromByteCount: Int64(URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage), countStyle: .file))", isOn: $clearOtherCacheSelected)
                        }
                        Section {
                            Button("清除所选缓存", role: .destructive) {
                                let cache = NativePublicCache.shared
                                if clearImageCacheSelected { cache.clearImages() }
                                if clearDataCacheSelected { cache.clearData() }
                                if clearOtherCacheSelected { URLCache.shared.removeAllCachedResponses() }
                                cacheBytes = cache.sizeBytes() + URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
                                cacheManagementOpen = false
                                serviceNotice = "所选缓存已清理。下次查看时，所需内容会自动重新加载。"
                            }
                            .disabled(!clearImageCacheSelected && !clearDataCacheSelected && !clearOtherCacheSelected)
                        }
                    }
                    .navigationTitle("清理缓存")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { cacheManagementOpen = false } } }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $allServicesOpen) {
                NavigationStack {
                    List {
                        Section("购物与预订") {
                            ForEach(["我的购物车", "收货地址", "我的团购券", "我的住宿订单", "我的旅游线路"], id: \.self) { name in
                                Button(name) {
                                    allServicesOpen = false
                                    guard store.session != nil else { serviceNotice = "请先登录文旅账号，再查看个人服务。"; return }
                                    switch name {
                                    case "我的购物车": cartOpen = true
                                    case "收货地址": addressBookOpen = true
                                    case "我的团购券": diningPackageOrdersOpen = true
                                    default:
                                        bookingOrdersKind = name == "我的住宿订单" ? "hotel" : "route"
                                        bookingOrdersOpen = true
                                    }
                                }
                            }
                        }
                        Section("权益与收藏") {
                            ForEach(["积分与成长值", "我的收藏", "我的活动报名", "我的商品评价", "我的消费券", "门票核销"], id: \.self) { name in
                                Button(name) {
                                    openAccountService(name)
                                }
                            }
                        }
                        Section("帮助与入驻") {
                            ForEach(["客服与反馈", "商户入驻"], id: \.self) { name in
                                Button(name) {
                                    openHelpService(name)
                                }
                            }
                        }
                    }
                    .navigationTitle("全部服务")
                    .toolbar { Button("关闭") { allServicesOpen = false } }
                }
            }
            .sheet(item: $shownAgreement) { item in
                NativeAgreementContentView(agreement: item) { shownAgreement = nil }
            }
            .sheet(isPresented: $activityRegistrationsOpen) {
                ActivityRegistrationsView(store: store)
            }
            .sheet(isPresented: $activityVerificationOpen) {
                ActivityVerificationView(store: store)
            }
            .sheet(isPresented: $ticketVerificationOpen) {
                NativeTicketVerificationView(store: store)
            }
            .sheet(isPresented: $couponVerificationOpen) {
                NativeCouponVerificationView(store: store)
            }
            .sheet(isPresented: $favoritesOpen) {
                NativeFavoritesView(store: store)
            }
            .sheet(isPresented: $memberLedgerOpen) {
                NativeMemberLedgerView(store: store)
            }
            .sheet(isPresented: $productReviewsOpen) {
                NativeProductReviewsView(store: store)
            }
            .sheet(isPresented: $commerceOrdersOpen) {
                NativeCommerceOrdersView(store: store)
            }
            .sheet(isPresented: $ticketOrdersOpen) {
                NativeTicketOrdersView(store: store)
            }
            .sheet(isPresented: $diningPackageOrdersOpen) {
                NativeDiningPackageOrdersView(store: store)
            }
            .sheet(isPresented: $couponsOpen) {
                NativeCouponsView(store: store, onLogin: {
                    couponsOpen = false
                    authOpen = true
                })
            }
            .sheet(isPresented: $supportTicketsOpen) {
                NativeSupportTicketsView(store: store)
            }
            .sheet(isPresented: $merchantOnboardingOpen) {
                NativeMerchantOnboardingView(store: store)
            }
            .sheet(isPresented: $bookingOrdersOpen) {
                NativeBookingOrdersView(store: store, initialKind: bookingOrdersKind)
            }
            .sheet(isPresented: $merchantWorkbenchOpen) {
                MerchantWorkbenchView(store: store)
            }
            .sheet(isPresented: $restaurantWorkbenchOpen) {
                RestaurantWorkbenchView(store: store)
            }
            .sheet(isPresented: $identityConsentOpen) {
                NativeIdentityConsentView(store: store)
            }
            .sheet(isPresented: $accountCancellationOpen) {
                NativeAccountCancellationView(store: store, expectedPrincipal: accountCancellationPrincipal) { message in
                    accountCancellationOpen = false
                    accountCancellationPrincipal = nil
                    authOpen = false
                    clearAccountAuthSecrets()
                    serviceNotice = message
                }
            }
            .sheet(isPresented: $cartOpen) {
                NativeCartView(store: store)
            }
            .sheet(isPresented: $addressBookOpen) {
                NativeTradeAddressBookView(store: store)
            }
            .onChange(of: couponCenterRequested, initial: true) { _, requested in
                if requested {
                    couponsOpen = true
                    onCouponCenterRequestHandled()
                }
            }
    }

    private func openCommonService(_ title: String) {
        if title == "我的订单" {
            guard store.session != nil else { serviceNotice = "请先登录文旅账号，再查看商城订单。"; return }
            commerceOrdersOpen = true
        } else if title == "我的票券" {
            guard store.session != nil else { serviceNotice = "请先登录文旅账号，再查看门票订单和凭证。"; return }
            ticketOrdersOpen = true
        } else if title == "消费券" {
            couponsOpen = true
        } else {
            serviceNotice = "\(title)原生页面正在完善"
        }
    }

    private func profileInfoRow(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Brand.ink)
                Spacer()
                Text(detail).font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            }
            .font(.system(size: NativeTypography.size(14)))
            .frame(height: 43)
            .overlay(alignment: .bottom) { Brand.border.frame(height: 1) }
        }
        .buttonStyle(.plain)
    }

    private func loadAgreements() async {
        let api = MobileAPI(store: store)
        do { loginEnabled = try await api.passwordLoginEnabled() }
        catch { if Task.isCancelled { return }; loginEnabled = false }
        do { smsEnabled = try await api.smsLoginEnabled() }
        catch { if Task.isCancelled { return }; smsEnabled = false }
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

    private func login() async {
        guard !busy && !sendingPhoneCode else { return }
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
        }
        catch {
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

    private func loadCaptcha() async {
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

    private func sendPhoneCode() async {
        guard !busy && !sendingPhoneCode else { return }
        guard phone.range(of: "^1[3-9][0-9]{9}$", options: .regularExpression) != nil else {
            error = "请输入有效的大陆手机号"; return
        }
        guard recoveryMode || agreements.count == 2 && consent else { error = "请先同意当前协议"; return }
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
