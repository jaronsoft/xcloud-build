import SwiftUI
import UIKit

struct NativeCouponsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var statusFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .largeTitle) private var couponAmountFontSize: CGFloat = 32
    @ObservedObject var store: SessionStore
    let onLogin: () -> Void
    @State private var tab = "claim"
    @State private var status = ""
    @State private var campaigns = [[String: Any]]()
    @State private var coupons = [[String: Any]]()
    @State private var campaignPage = 1
    @State private var couponPage = 1
    @State private var campaignTotal = 0
    @State private var couponTotal = 0
    @State private var loading = false
    @State private var loadingMore = false
    @State private var claimingID = ""
    @State private var receiptAttempts = [String: String]()
    @State private var receiptNotice: String?
    @State private var receiptTask: Task<Void, Never>?
    @State private var error: String?
    @State private var retryPage: Int?
    @State private var retryTab: String?
    @State private var notice: String?
    @State private var claimFeedback: CouponClaimFeedback?
    @State private var pendingCampaign: [String: Any]?
    @State private var identityNotReady = false
    @State private var identityProfileOpen = false
    @State private var qrImage: Data?
    @State private var qrTitle = "消费券"
    @State private var qrLoadingID = ""
    @State private var qrErrorID = ""
    @State private var revision = 0
    @State private var requestSequence = 0

    private let pageSize = 20
    // 原回执查询和领券共用服务端准入队列。
    private let couponClaimTimeout: TimeInterval = 45
    private let statuses = [("", "全部"), ("Available", "可使用"), ("Reserved", "使用中"), ("Redeemed", "已使用"), ("Expired", "已过期")]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                headerAction(symbol: "xmark", label: "关闭消费券") { dismiss() }
                Spacer(minLength: 0)
                Text("优惠券与消费券")
                    .font(.system(size: NativeTypography.size(16), weight: .semibold))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                headerAction(symbol: "arrow.clockwise", label: "刷新消费券", disabled: loading) { revision += 1 }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Brand.background)
            HStack(spacing: 0) {
                tabButton("claim", title: "领券中心")
                tabButton("mine", title: "我的券包")
            }.padding(.horizontal, 16)
            if tab == "claim", let claimFeedback {
                couponWarning(title: claimFeedback.title, message: claimFeedback.message) {
                    if claimFeedback != .rejected {
                        Button("查看券包") { status = ""; switchTab("mine") }
                            .buttonStyle(.bordered).tint(Brand.primary)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("商户优惠券用于商城结算；平台消费券按活动规则领取和核销。")
                        .font(.caption).foregroundStyle(Brand.muted)
                    if tab == "claim" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.session == nil ? "登录后才能领取消费券" : "实名领取")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                            Text("领券前需登记实名资料、验证手机号，并同意本活动使用实名资料。")
                                .font(.footnote).foregroundStyle(Brand.ink)
                            if store.session == nil {
                                Button("登录文旅账号", action: onLogin).buttonStyle(.borderedProminent)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Brand.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        if store.session == nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("登录后查看我的消费券").font(.headline)
                                Text("登录文旅账号后，可查看券码、使用状态和有效期。")
                                    .font(.caption).foregroundStyle(Brand.muted)
                                Button("登录文旅账号", action: onLogin).buttonStyle(.borderedProminent)
                            }.merchantCard()
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(statuses, id: \.0) { value, label in
                                        let selected = status == value
                                        Button {
                                            guard !selected else { return }
                                            status = value; revision += 1
                                        } label: {
                                            Text(label)
                                                .font(.system(size: statusFontSize, weight: .medium))
                                                .fixedSize()
                                                .frame(minWidth: 54)
                                                .padding(.horizontal, 4)
                                                .frame(minHeight: 34)
                                                .foregroundStyle(selected ? Color.white : Brand.ink)
                                                .background(selected ? Brand.primary : Brand.primary.opacity(0.09), in: Capsule())
                                                .frame(minHeight: 44)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityAddTraits(selected ? .isSelected : [])
                                    }
                                }
                            }
                        }
                    }
                    if let notice { Text(notice).font(.caption).foregroundStyle(Brand.primary).merchantCard() }
                    if loading && (tab == "claim" ? campaigns.isEmpty : coupons.isEmpty) {
                        ProgressView(tab == "claim" ? "正在读取领券活动…" : "正在读取我的消费券…")
                            .frame(maxWidth: .infinity).padding(24)
                    }
                    if retryTab == "mine", tab == "mine", let retryPage {
                        couponWarning(title: status.isEmpty ? "暂时无法加载券包" : "暂时无法加载\(statuses.first { $0.0 == status }?.1 ?? "")的券",
                                      message: "请稍后再试。") {
                            Button("重新加载") { Task { await loadCoupons(page: retryPage) } }
                                .buttonStyle(.bordered).tint(Brand.primary).disabled(loading)
                        }
                    } else if let error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.caption).foregroundStyle(.red)
                            if retryTab == tab, let retryPage {
                                Button("重试当前页") {
                                    Task {
                                        if tab == "claim" { await loadCampaigns(page: retryPage) }
                                        else { await loadCoupons(page: retryPage) }
                                    }
                                }.buttonStyle(.bordered).disabled(loading)
                            }
                        }.merchantCard()
                    }
                    if tab == "claim" {
                        if !campaigns.isEmpty {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(campaigns.indices, id: \.self) { index in
                                        campaignCard(campaigns[index], now: context.date)
                                    }
                                }
                            }
                        }
                        if !loading && error == nil && campaigns.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("当前没有可领取的消费券活动。")
                                    .font(.caption).foregroundStyle(Brand.ink)
                                Text("只有处于活动时段且仍有库存的活动会显示在这里。")
                                    .font(.caption2).foregroundStyle(Brand.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).merchantCard()
                        }
                        if retryTab != tab, campaigns.count < campaignTotal {
                            Button(loadingMore ? "正在加载…" : "加载更多活动") { Task { await loadCampaigns(page: campaignPage + 1) } }
                                .disabled(loadingMore).frame(maxWidth: .infinity)
                        }
                    } else if store.session != nil {
                        if !receiptAttempts.isEmpty || receiptNotice != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                if !receiptAttempts.isEmpty {
                                    Text("有领取结果待核对。").font(.caption).foregroundStyle(Brand.ink)
                                    Button(receiptTask != nil ? "核对中…" : "核对领取结果") {
                                        guard receiptTask == nil else { return }
                                        receiptTask = Task { await checkClaimReceipts() }
                                    }.buttonStyle(.bordered).tint(Brand.primary).disabled(receiptTask != nil)
                                }
                                if let receiptNotice { Text(receiptNotice).font(.caption).foregroundStyle(Brand.ink) }
                            }.frame(maxWidth: .infinity, alignment: .leading).merchantCard()
                        }
                        ForEach(coupons.indices, id: \.self) { index in couponCard(coupons[index]) }
                        if !loading && error == nil && coupons.isEmpty {
                            Text("这个分类暂时没有消费券。")
                                .font(.caption).foregroundStyle(Brand.muted).merchantCard()
                        }
                        if retryTab != tab, coupons.count < couponTotal {
                            Button(loadingMore ? "正在加载…" : "加载更多消费券") { Task { await loadCoupons(page: couponPage + 1) } }
                                .disabled(loadingMore).frame(maxWidth: .infinity)
                        }
                    }
                    Text("适用商品、使用门槛和最终核销结果以活动规则及服务端校验为准。")
                        .font(.caption2).foregroundStyle(Brand.muted)
                }.padding(16)
            }.background(Brand.background)
        }
        .accessibilityHidden(pendingCampaign != nil)
        .overlay {
            if pendingCampaign != nil { claimConsentDialog }
        }
        .task(id: "\(revision)-\(tab)-\(status)-\(store.session?.accessToken ?? "")") {
            if tab == "claim" { await loadCampaigns(page: 1) }
            else { await loadCoupons(page: 1) }
        }
        .onChange(of: store.session?.accessToken) { _, _ in
            receiptTask?.cancel(); receiptAttempts = [:]; receiptNotice = nil
            requestSequence += 1; coupons = []; qrImage = nil; claimingID = ""
            error = nil; retryPage = nil; retryTab = nil; pendingCampaign = nil; claimFeedback = nil
            if tab == "mine" { revision += 1 }
        }
        .onChange(of: tab) { _, _ in receiptTask?.cancel(); receiptNotice = nil }
        .onDisappear { receiptTask?.cancel() }
        .alert("领券前请完成账号实名", isPresented: $identityNotReady) {
            Button("前往实名") { identityProfileOpen = true }
            Button("暂不领取", role: .cancel) {}
        } message: {
            Text("请填写本人的姓名和身份证号码。")
        }
        .sheet(isPresented: $identityProfileOpen) {
            NativeIdentityConsentView(store: store)
        }
        .sheet(isPresented: Binding(get: { qrImage != nil }, set: { if !$0 { qrImage = nil } })) {
            NavigationStack {
                VStack(spacing: 14) {
                    Text(qrTitle).font(.headline)
                    if let qrImage, let image = UIImage(data: qrImage) {
                        Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                            .frame(maxWidth: 280, maxHeight: 280).padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("请让商户扫码核验；核销结果以服务端确认为准。")
                        .font(.caption).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Brand.background).navigationTitle("出示消费券")
                    .toolbar { Button("关闭") { qrImage = nil } }
            }
        }
    }

    private enum CouponClaimFeedback {
        case limitReached, uncertain, rejected

        var title: String {
            switch self {
            case .limitReached: "已领满本活动的券"
            case .uncertain: "暂未确认是否领到"
            case .rejected: "本次未能领券"
            }
        }

        var message: String {
            switch self {
            case .limitReached: "你已领完本活动每人可领的张数，可到「我的券包」查看。"
            case .uncertain: "请先查看「我的券包」。如果没有这张券，可以回到活动再试一次。"
            case .rejected: "请刷新活动后再试。"
            }
        }
    }

    private func couponWarning<Actions: View>(title: String, message: String,
                                                @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3).foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(Brand.ink)
                Text(message).font(.subheadline).foregroundStyle(Brand.ink)
                actions()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.45)))
        .accessibilityElement(children: .contain)
    }

    private var claimConsentDialog: some View {
        GeometryReader { page in
            ZStack {
                Color.black.opacity(0.32).ignoresSafeArea().accessibilityHidden(true)
                VStack(spacing: 12) {
                    Image(systemName: "person.text.rectangle")
                        .font(.title2).foregroundStyle(Brand.primary)
                        .accessibilityHidden(true)
                    Text("实名资料使用确认")
                        .font(.headline).foregroundStyle(Brand.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("本活动将使用你的实名资料，确认你能否领券及还能领几张。")
                        .font(.subheadline).foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(role: .cancel) { pendingCampaign = nil } label: {
                            Text("暂不领取").frame(maxWidth: .infinity, minHeight: 36)
                        }.buttonStyle(.bordered)
                        Button {
                            guard let campaign = pendingCampaign else { return }
                            pendingCampaign = nil
                            Task { await submitClaim(campaign, identityConsent: true) }
                        } label: {
                            Text("同意领取").frame(maxWidth: .infinity, minHeight: 36)
                        }.buttonStyle(.borderedProminent)
                    }.tint(Brand.primary)
                }
                .multilineTextAlignment(.center)
                .padding(20)
                .frame(width: min(page.size.width * 0.9, 480))
                .background(.background, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityElement(children: .contain)
                .accessibilityAction(.escape) { pendingCampaign = nil }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func headerAction(symbol: String, label: String, disabled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.primary)
                .frame(width: 36, height: 36)
                .background(Brand.primary.opacity(0.1), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(disabled)
    }

    private func switchTab(_ value: String) {
        tab = value; error = nil; retryPage = nil; retryTab = nil; notice = nil; claimFeedback = nil
    }

    private func tabButton(_ value: String, title: String) -> some View {
        Button { switchTab(value) } label: {
            Text(title).font(.system(size: NativeTypography.size(14), weight: tab == value ? .semibold : .regular))
                .foregroundStyle(tab == value ? Brand.primary : Brand.muted)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .overlay(alignment: .bottom) { if tab == value { Brand.primary.frame(height: 2) } }
        }.buttonStyle(.plain)
    }

    private func couponTicket<Detail: View>(amount: Decimal?, minimum: Decimal?, available: Bool = true,
                                           @ViewBuilder detail: () -> Detail) -> some View {
        let valueWidth: CGFloat = 94
        let valueBackground = available
            ? Color(red: 234.0 / 255, green: 245.0 / 255, blue: 240.0 / 255)
            : Color(uiColor: .tertiarySystemFill)
        let value = VStack(spacing: 3) {
            if let amount {
                VStack(spacing: 0) {
                    Text("¥").font(.caption.weight(.semibold))
                    Text(verbatim: moneyText(amount))
                        .font(.system(size: couponAmountFontSize, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(available ? Brand.primary : Color(uiColor: .secondaryLabel))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("面额 \(moneyText(amount)) 元")
            } else {
                Text("金额待确认").font(.caption.weight(.semibold))
            }
            Text(minimum.map { $0 > 0 ? "满\(moneyText($0))元可用" : "无门槛" } ?? "门槛待确认")
                .font(.caption2)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(available ? Brand.ink.opacity(0.8) : Color(uiColor: .secondaryLabel))
        .padding(.horizontal, 7)
        .padding(.vertical, 12)

        let details = detail().padding(12).frame(maxWidth: .infinity, alignment: .leading)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    value.frame(maxWidth: .infinity).background(valueBackground)
                    details
                }
            } else {
                HStack(spacing: 0) {
                    value.frame(width: valueWidth)
                    details
                }
                .background(alignment: .leading) { valueBackground.frame(width: valueWidth) }
            }
        }
        .background(available ? Color.white : Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private func campaignCard(_ item: [String: Any], now: Date) -> some View {
        let id = display(field(item, "Id")) ?? ""
        let amount = couponMoney(field(item, "CouponAmount"))
        let minimum = couponMoney(field(item, "MinimumSpend"))
        let remaining = integer(field(item, "RemainingQuantity"))
        let canClaim = store.session != nil
        let remainingTime = display(field(item, "EndsAt"))
            .flatMap(nativeBusinessDateTime)?.timeIntervalSince(now)
        let expired = remainingTime.map { $0 <= 0 } ?? false
        let countdown = remainingTime.map { $0 > 0 ? "距结束 \(nativeActivityCountdown($0))" : "活动已结束" }
            ?? "截止时间待确认"
        couponTicket(amount: amount, minimum: minimum) {
            VStack(alignment: .leading, spacing: 5) {
                Text(display(field(item, "Name")) ?? "平台消费券")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                Text("领取后 \(integer(field(item, "ValidityDays"))) 天有效 · 每人限领 \(integer(field(item, "PerUserLimit"))) 张")
                    .font(.caption).foregroundStyle(Brand.muted)
                Text("\(countdown) · 剩余 \(remaining) 张")
                    .font(.caption.monospacedDigit()).foregroundStyle(Brand.muted)
                Button(claimingID == id ? "领取中…" : expired ? "已结束" : remaining <= 0 ? "已领完" : canClaim ? "立即领取" : "请先登录") {
                    Task { await prepareClaim(item) }
                }.buttonStyle(.borderedProminent).disabled(loading || expired || !canClaim || claimingID != "" || id.isEmpty || amount == nil || minimum == nil || remaining <= 0)
            }
        }
    }

    @ViewBuilder private func couponCard(_ item: [String: Any]) -> some View {
        let id = display(field(item, "Id")) ?? ""
        let type = display(field(item, "CampaignType")) ?? ""
        let state = display(field(item, "Status")) ?? ""
        let amount = couponMoney(field(item, "CouponAmount"))
        let minimum = couponMoney(field(item, "MinimumSpend"))
        let available = state == "Available"
        let ink = available ? Brand.ink : Color(uiColor: .secondaryLabel)
        let label = ["Available": "可使用", "Reserved": "使用中", "Redeemed": "已使用", "Expired": "已过期"][state] ?? "状态待确认"
        let details = VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    couponTitle(item, type: type).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    couponStatusBadge(label, available: available)
                }
                VStack(alignment: .leading, spacing: 4) {
                    couponTitle(item, type: type)
                    couponStatusBadge(label, available: available)
                }
            }
            Text("有效期至 \(dateText(field(item, "ValidUntil")))")
                .font(.footnote).foregroundStyle(ink)
            if available {
                Text("领取时间 \(dateText(field(item, "ClaimedAt")))")
                    .font(.footnote).foregroundStyle(ink)
            } else {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("领取时间 \(dateText(field(item, "ClaimedAt")))")
                        if state == "Redeemed" {
                            Text("使用时间 \(display(field(item, "UsedAt")) == nil ? "时间未记录" : dateText(field(item, "UsedAt")))")
                            Text("使用地点 \(display(field(item, "UsedLocation")) ?? "地点未记录")")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                } label: {
                    Text("查看详情").fontWeight(.semibold)
                }
                .font(.footnote).tint(ink)
            }
            if state == "Available" && type == "Merchant" {
                Text("商城结算时选择使用，不支持现场扫码核销。")
                    .font(.caption).foregroundStyle(Brand.muted)
            } else if state == "Available" && type == "District" {
                Text("政府消费券按活动规则核验，当前券包不提供平台扫码入口。")
                    .font(.caption).foregroundStyle(Brand.muted)
            } else if state == "Available" && type == "Platform" {
                let actions = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                actions {
                    Button(qrLoadingID == id ? "正在生成…" : "出示核销二维码") { Task { await showQr(item) } }
                        .disabled(qrLoadingID != "")
                    if let code = display(field(item, "CouponCode")), !code.isEmpty {
                        Button("复制券码") { UIPasteboard.general.string = code; notice = "券码已复制。" }
                    }
                }.font(.caption)
                if qrErrorID == id {
                    Button("二维码暂不可用，重试") { Task { await showQr(item) } }
                        .font(.caption).foregroundStyle(.red)
                }
            } else if state == "Available" {
                Text("券类型暂无法确认，请联系平台核对后再使用。")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        couponTicket(amount: amount, minimum: minimum, available: available) { details.foregroundStyle(ink) }
    }

    private func couponTitle(_ item: [String: Any], type: String) -> some View {
        Text("\(couponType(type)) · \(display(field(item, "CampaignName")) ?? "未命名券")")
            .font(.subheadline.weight(.semibold))
    }

    private func couponStatusBadge(_ label: String, available: Bool) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(available ? Brand.primary.opacity(0.12) : Color(uiColor: .systemGray5), in: Capsule())
    }

    @MainActor private func closeCampaignList() {
        campaigns = []; campaignPage = 1; campaignTotal = 0
        pendingCampaign = nil; identityNotReady = false
        retryPage = nil; retryTab = nil
        error = "消费券功能暂未开放，可到「我的券包」查看领取结果。"
    }

    @MainActor private func loadCampaigns(page target: Int) async {
        requestSequence += 1; let sequence = requestSequence
        loading = true; error = nil; retryPage = nil; retryTab = nil
        if target == 1 { campaigns = []; campaignTotal = 0 }
        else { loadingMore = true }
        defer { if sequence == requestSequence { loading = false; loadingMore = false } }
        do {
            let api = MobileAPI(store: store)
            let access = try await api.get("/api/JHCTIFeatureAccess/GetPublicStatus?featureId=F-OPS-012") as? [String: Any]
            guard sequence == requestSequence else { return }
            guard access?["Status"] as? String == "Open", access?["IsEnabled"] as? Bool == true else {
                closeCampaignList(); return
            }
            let result = try await api.get("/api/JHCTICouponClaim/GetClaimableCampaigns?page=\(target)&pageSize=\(pageSize)") as? [String: Any]
            guard sequence == requestSequence else { return }
            guard let rows = (result?["data"] ?? result?["Data"] ?? result?["Items"] ?? result?["items"]) as? [[String: Any]] else {
                throw MobileAPIError.unavailable("领券活动分页回执无效")
            }
            campaigns = target == 1 ? rows : campaigns + rows
            campaignPage = target
            campaignTotal = integer(result?["dataCount"] ?? result?["DataCount"] ?? result?["total"] ?? result?["Total"])
        } catch {
            guard sequence == requestSequence else { return }
            if (error as? MobileAPIError)?.httpStatusCode == 403 {
                closeCampaignList()
            } else {
                self.error = error.localizedDescription; retryPage = target; retryTab = "claim"
            }
        }
    }

    @MainActor private func loadCoupons(page target: Int) async {
        guard let token = store.session?.accessToken else { coupons = []; couponTotal = 0; loading = false; return }
        if target == 1 { receiptAttempts = storedClaimAttempts(principal: MobileAPI(store: store).nativeTourismPrincipal(token)) }
        requestSequence += 1; let sequence = requestSequence
        loading = true; error = nil; retryPage = nil; retryTab = nil
        if target == 1 { coupons = []; couponTotal = 0; qrImage = nil }
        else { loadingMore = true }
        defer { if sequence == requestSequence { loading = false; loadingMore = false } }
        do {
            let filter = status.isEmpty ? "" : "&status=\(status)"
            let result = try await MobileAPI(store: store).get("/api/JHCTICouponClaim/GetMyCouponPage?page=\(target)&pageSize=\(pageSize)\(filter)", authenticated: true) as? [String: Any]
            guard sequence == requestSequence, store.session?.accessToken == token else { return }
            guard let result,
                  let rows = (result["data"] ?? result["Data"] ?? result["Items"] ?? result["items"]) as? [[String: Any]] else {
                throw MobileAPIError.unavailable("我的消费券分页回执无效")
            }
            coupons = target == 1 ? rows : coupons + rows
            couponPage = target
            couponTotal = integer(result["dataCount"] ?? result["DataCount"] ?? result["total"] ?? result["Total"])
        } catch {
            if sequence == requestSequence, store.session?.accessToken == token {
                self.error = "暂时无法加载券包"
                retryPage = target; retryTab = "mine"
            }
        }
    }

    private func couponClaimAttemptPrefix(_ principal: String) -> String { "jhcti.coupon.claim.attempt.v1.\(principal)." }

    private func couponClaimStoragePrincipal(_ principal: String) -> String {
        guard let separator = principal.firstIndex(of: ":") else { return principal }
        let subject = String(principal[..<separator])
        guard let number = Int64(subject), number > 0, String(number) == subject else { return principal }
        return "account:\(subject)"
    }

    private func validStoredClaimRequest(_ value: Any?) -> String? {
        guard let request = value as? String,
              request.range(of: "^[A-Za-z0-9._:-]{16,80}$", options: .regularExpression) != nil else { return nil }
        return request
    }

    private func storedClaimAttempts(principal: String) -> [String: String] {
        let prefix = couponClaimAttemptPrefix(couponClaimStoragePrincipal(principal))
        let legacyPrefix = couponClaimAttemptPrefix(principal)
        let defaults = UserDefaults.standard
        let entries = defaults.dictionaryRepresentation()
        var attempts = [String: String]()
        for (key, value) in entries {
            let matchedPrefix = key.hasPrefix(prefix) ? prefix : legacyPrefix
            guard key.hasPrefix(matchedPrefix), let request = validStoredClaimRequest(value) else { continue }
            let id = String(key.dropFirst(matchedPrefix.count))
            guard let number = Int64(id), number > 0, String(number) == id else { continue }
            if matchedPrefix == prefix {
                attempts[id] = request
            } else if entries[prefix + id] == nil {
                // 旧会话的记录先复制到账号名下，收到确认后再按原号清理。
                defaults.set(request, forKey: prefix + id)
                attempts[id] = request
            }
        }
        return attempts
    }

    private func saveClaimAttempt(principal: String, campaignID: String) -> String? {
        let key = couponClaimAttemptPrefix(couponClaimStoragePrincipal(principal)) + campaignID
        let legacyKey = couponClaimAttemptPrefix(principal) + campaignID
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: key) ?? defaults.object(forKey: legacyKey) ?? "coupon-\(UUID().uuidString)"
        guard let request = validStoredClaimRequest(stored) else { return nil }
        defaults.set(request, forKey: key)
        return defaults.string(forKey: key) == request ? request : nil
    }

    @discardableResult private func clearClaimAttempt(principal: String, campaignID: String, request: String) -> Bool {
        let defaults = UserDefaults.standard
        let keys = Set([couponClaimAttemptPrefix(couponClaimStoragePrincipal(principal)) + campaignID,
                        couponClaimAttemptPrefix(principal) + campaignID])
        let matching = keys.filter { defaults.string(forKey: $0) == request }
        for key in matching { defaults.removeObject(forKey: key) }
        return !matching.isEmpty
    }

    private func matchClaimReceipts(_ response: Any, to attempts: [String: String]) throws -> [String: String] {
        let invalid = MobileAPIError.unavailable("领券回执格式无效。")
        guard let rows = response as? [[String: Any]], rows.count <= attempts.count else { throw invalid }
        var matched = [String: String]()
        var couponIDs = Set<String>()
        for row in rows {
            func read(_ key: String) throws -> String? {
                let alias = key.prefix(1).lowercased() + key.dropFirst()
                if let upper = row[key], let lower = row[alias],
                   !(upper is String && (upper as? String) == (lower as? String)) { throw invalid }
                return (row[key] ?? row[alias]) as? String
            }
            guard let couponID = try read("Id"), let value = Int64(couponID), value > 0, String(value) == couponID,
                  couponIDs.insert(couponID).inserted, let campaignID = try read("CampaignId"), matched[campaignID] == nil,
                  let requestID = try read("RequestId"), attempts[campaignID] == requestID else { throw invalid }
            matched[campaignID] = requestID
        }
        return matched
    }

    @MainActor private func checkClaimReceipts() async {
        defer { receiptTask = nil }
        guard tab == "mine", !Task.isCancelled, let token = store.session?.accessToken else { return }
        let api = MobileAPI(store: store)
        let principal = api.nativeTourismPrincipal(token)
        let attempts = storedClaimAttempts(principal: principal)
        let campaignIDs = attempts.keys.sorted()
        var confirmed = 0
        receiptNotice = nil
        let active = { !Task.isCancelled && store.session?.accessToken == token && tab == "mine" }
        do {
            for offset in stride(from: 0, to: campaignIDs.count, by: 20) {
                guard active() else { return }
                let batch = Dictionary(uniqueKeysWithValues: campaignIDs.dropFirst(offset).prefix(20).compactMap { id in
                    attempts[id].map { (id, $0) }
                })
                let body = batch.map { ["CampaignId": $0.key, "RequestId": $0.value] }
                let response = try await api.postJSON("/api/JHCTICouponClaim/GetMyClaimReceipts", body: body,
                    authenticated: true, expectedPrincipal: principal, requireExplicitResponse: true,
                    timeoutInterval: couponClaimTimeout)
                guard active() else { return }
                let matched = try matchClaimReceipts(response, to: batch)
                let recovered = matched.filter { id, request in
                    clearClaimAttempt(principal: principal, campaignID: id, request: request)
                }
                receiptAttempts = storedClaimAttempts(principal: principal)
                guard !recovered.isEmpty else { continue }
                confirmed += recovered.count
                receiptNotice = "已确认领取 \(confirmed) 张消费券。"
                status = ""; revision += 1
            }
            if confirmed == 0, !attempts.isEmpty {
                receiptNotice = "暂未查到对应的领券结果，可稍后再核对。"
            }
        } catch {
            guard active() else { return }
            receiptNotice = confirmed > 0
                ? "已确认领取 \(confirmed) 张消费券，其余结果暂时无法核对。"
                : "暂时无法核对领券结果，请稍后重试。"
        }
    }

    @MainActor private func prepareClaim(_ campaign: [String: Any]) async {
        guard !loading else { return }
        guard let token = store.session?.accessToken else { onLogin(); return }
        let id = display(campaign["Id"]) ?? ""
        guard Int64(id).map({ $0 > 0 }) == true, claimingID.isEmpty else { return }
        let sequence = requestSequence
        do {
            let profile = try await MobileAPI(store: store).get("/api/JHCTITourismAuth/GetMyTicketIdentityProfile", authenticated: true) as? [String: Any]
            guard store.session?.accessToken == token, sequence == requestSequence else { return }
            guard nativeTicketIdentityProfileValid(profile) else {
                throw MobileAPIError.unavailable("实名资料状态格式异常，请重新读取。")
            }
            guard nativeTicketIdentityBookingEligible(profile) else { identityNotReady = true; return }
            pendingCampaign = campaign
        } catch { if sequence == requestSequence { self.error = error.localizedDescription } }
    }

    @MainActor private func submitClaim(_ campaign: [String: Any], identityConsent: Bool) async {
        guard !loading else { return }
        guard let token = store.session?.accessToken else { onLogin(); return }
        let id = display(field(campaign, "Id")) ?? ""
        guard Int64(id).map({ $0 > 0 }) == true, claimingID.isEmpty,
              campaigns.contains(where: { display(field($0, "Id")) == id }) else { return }
        let principal = MobileAPI(store: store).nativeTourismPrincipal(token)
        guard let requestID = saveClaimAttempt(principal: principal, campaignID: id) else {
            claimFeedback = .rejected
            return
        }
        claimingID = id; error = nil; notice = nil; claimFeedback = nil
        defer { if store.session?.accessToken == token, claimingID == id { claimingID = "" } }
        do {
            let api = MobileAPI(store: store)
            let sendClaim = {
                let receipt = try await api.post("/api/JHCTICouponClaim/Claim", body: [
                    "CampaignId": id, "RequestId": requestID, "IdentityConsent": identityConsent
                ], authenticated: true, expectedPrincipal: principal, timeoutInterval: couponClaimTimeout,
                   requireExplicitResponse: true) as? [String: Any]
                guard let claimID = (receipt?["Id"] ?? receipt?["id"]) as? String,
                      let number = Int64(claimID), number > 0, String(number) == claimID else {
                    throw MobileAPIError.transient(message: "领券结果未确认，请稍后查询。", retryAfterSeconds: nil)
                }
            }
            do {
                try await sendClaim()
            } catch {
                guard let delay = couponClaimRetryDelay(for: error), store.session?.accessToken == token else { throw error }
                notice = "正在确认领券结果，请稍等…"
                try await Task.sleep(for: .milliseconds(delay))
                guard store.session?.accessToken == token else { throw MobileAPIError.unavailable("登录账号已变化，请重新操作") }
                try await sendClaim()
            }
            guard store.session?.accessToken == token else { return }
            clearClaimAttempt(principal: principal, campaignID: id, request: requestID)
            notice = "领取成功，已放入我的消费券。"
            requestSequence += 1
            await loadCampaigns(page: 1)
            if tab == "mine" { await loadCoupons(page: 1) }
        } catch {
            guard store.session?.accessToken == token, !Task.isCancelled else { return }
            notice = nil
            if (error as? MobileAPIError)?.httpStatusCode == 403, error.localizedDescription == "功能待开放" {
                if tab == "claim" {
                    requestSequence += 1
                    loading = false; loadingMore = false
                    closeCampaignList()
                }
            } else if error.localizedDescription == "已达到该活动每人领取上限" {
                claimFeedback = .limitReached
            } else if couponClaimRetryDelay(for: error) != nil {
                claimFeedback = .uncertain
            } else {
                claimFeedback = .rejected
            }
        }
    }

    private func couponClaimRetryDelay(for error: Error) -> Int? {
        switch error {
        case let MobileAPIError.transient(_, retryAfterSeconds):
            return min(60, max(0, retryAfterSeconds ?? 0)) * 1000 + Int.random(in: 250...1000)
        case let MobileAPIError.rejected(statusCode, _, retryAfterSeconds) where statusCode == 408 || statusCode == 429 || statusCode >= 500:
            return min(60, max(0, retryAfterSeconds ?? 0)) * 1000 + Int.random(in: 250...1000)
        default:
            return nil
        }
    }

    @MainActor private func showQr(_ coupon: [String: Any]) async {
        guard let token = store.session?.accessToken else { onLogin(); return }
        let id = display(field(coupon, "Id")) ?? ""
        guard Int64(id).map({ $0 > 0 }) == true, qrLoadingID.isEmpty else { return }
        qrLoadingID = id; qrErrorID = ""
        defer { if qrLoadingID == id { qrLoadingID = "" } }
        do {
            guard let value = try await MobileAPI(store: store).get("/api/JHCTICouponClaim/GetMyCouponQr?couponClaimId=\(id)", authenticated: true) as? String,
                  value.hasPrefix("data:image/png;base64,"),
                  let image = Data(base64Encoded: String(value.dropFirst("data:image/png;base64,".count))),
                  store.session?.accessToken == token else { throw MobileAPIError.unavailable("消费券二维码回执无效") }
            qrTitle = display(field(coupon, "CampaignName")) ?? "平台消费券"
            qrImage = image
        } catch { qrErrorID = id; self.error = error.localizedDescription }
    }

    private func display(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return String(describing: value)
    }
    private func field(_ item: [String: Any], _ key: String) -> Any? {
        item[key] ?? item[key.prefix(1).lowercased() + String(key.dropFirst())]
    }
    private func integer(_ value: Any?) -> Int { (value as? Int) ?? Int(display(value) ?? "") ?? 0 }
    private func couponMoney(_ value: Any?) -> Decimal? {
        guard let text = display(value), let amount = Decimal(string: text), amount >= 0,
              amount <= Decimal(string: "999999999999.99")! else { return nil }
        var source = amount; var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .plain)
        return rounded == amount ? amount : nil
    }
    private func moneyText(_ value: Decimal) -> String {
        let text = NSDecimalNumber(decimal: value).stringValue
        return text.hasSuffix(".00") ? String(text.dropLast(3)) : text.hasSuffix("0") && text.contains(".") ? String(text.dropLast()) : text
    }
    private func dateText(_ value: Any?) -> String {
        (display(value) ?? "時間未提供").replacingOccurrences(of: "T", with: " ").prefix(16).description
    }
    private func couponType(_ type: String) -> String {
        ["Platform": "平台消费券", "Merchant": "商户优惠券", "District": "政府消费券"][type] ?? "券类型待确认"
    }
}
