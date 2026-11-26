import SwiftUI
import UIKit

struct NativeCouponsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let onLogin: () -> Void
    @State private var tab = "claim"
    @State private var status = "Available"
    @State private var campaigns = [[String: Any]]()
    @State private var coupons = [[String: Any]]()
    @State private var campaignPage = 1
    @State private var couponPage = 1
    @State private var campaignTotal = 0
    @State private var couponTotal = 0
    @State private var loading = false
    @State private var loadingMore = false
    @State private var claimingID = ""
    @State private var requestIDs = [String: String]()
    @State private var error: String?
    @State private var retryPage: Int?
    @State private var retryTab: String?
    @State private var notice: String?
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
    private let statuses = [("Available", "可使用"), ("Reserved", "使用中"), ("Redeemed", "已使用"), ("Expired", "已过期")]

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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("商户优惠券用于商城结算；平台消费券按活动规则领取和核销。")
                        .font(.caption).foregroundStyle(Brand.muted)
                    if tab == "mine" {
                        if store.session == nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("登录后查看我的消费券").font(.headline)
                                Text("登录文旅账号后，可查看券码、使用状态和有效期。")
                                    .font(.caption).foregroundStyle(Brand.muted)
                                Button("登录文旅账号", action: onLogin).buttonStyle(.borderedProminent)
                            }.merchantCard()
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack { ForEach(statuses, id: \.0) { value, label in
                                    Button(label) { status = value; revision += 1 }
                                        .buttonStyle(.bordered).tint(status == value ? Brand.primary : Brand.muted)
                                } }
                            }
                        }
                    }
                    if let notice { Text(notice).font(.caption).foregroundStyle(Brand.primary).merchantCard() }
                    if loading && (tab == "claim" ? campaigns.isEmpty : coupons.isEmpty) {
                        ProgressView(tab == "claim" ? "正在读取领券活动…" : "正在读取我的消费券…")
                            .frame(maxWidth: .infinity).padding(24)
                    }
                    if let error {
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
                        if store.session == nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("登录后才能领取消费券").font(.headline)
                                Text("所有消费券均需完成账号实名资料登记、手机号验证和本活动授权后才能领取；平台仅核对资料格式及活动规则，不做权威身份核验。")
                                    .font(.caption).foregroundStyle(Brand.muted)
                                Button("登录文旅账号", action: onLogin).buttonStyle(.borderedProminent)
                            }.merchantCard()
                        }
                        ForEach(campaigns.indices, id: \.self) { index in campaignCard(campaigns[index]) }
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
        .task(id: "\(revision)-\(tab)-\(status)-\(store.session?.accessToken ?? "")") {
            if tab == "claim" { await loadCampaigns(page: 1) }
            else { await loadCoupons(page: 1) }
        }
        .onChange(of: store.session?.accessToken) { _, _ in
            requestSequence += 1; coupons = []; qrImage = nil; claimingID = ""; requestIDs = [:]
            error = nil; retryPage = nil; retryTab = nil
            if tab == "mine" { revision += 1 }
        }
        .confirmationDialog("本活动实名资料使用告知", isPresented: Binding(
            get: { pendingCampaign != nil }, set: { if !$0 { pendingCampaign = nil } }
        ), titleVisibility: .visible) {
            Button("同意本活动用途并领取") {
                guard let campaign = pendingCampaign else { return }
                pendingCampaign = nil
                Task { await submitClaim(campaign, identityConsent: true) }
            }
            Button("暂不领取", role: .cancel) { pendingCampaign = nil }
        } message: {
            Text("我同意本活动为资格及身份证限额校验使用账号实名资料；身份证原文不会写入领取记录或日志。此校验不代表权威身份认证。")
        }
        .alert("实名资料未就绪", isPresented: $identityNotReady) {
            Button("去填写实名资料") { identityProfileOpen = true }
            Button("暂不领取", role: .cancel) {}
        } message: {
            Text("当前通过手机号验证账号。请填写本人真实姓名和身份证号码。平台只校验格式，不核实证件真伪。填写不实会影响后续权益。")
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

    private func tabButton(_ value: String, title: String) -> some View {
        Button { tab = value; error = nil; retryPage = nil; retryTab = nil; notice = nil } label: {
            Text(title).font(.system(size: NativeTypography.size(14), weight: tab == value ? .semibold : .regular))
                .foregroundStyle(tab == value ? Brand.primary : Brand.muted)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .overlay(alignment: .bottom) { if tab == value { Brand.primary.frame(height: 2) } }
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func campaignCard(_ item: [String: Any]) -> some View {
        let id = display(field(item, "Id")) ?? ""
        let amount = couponMoney(field(item, "CouponAmount"))
        let minimum = couponMoney(field(item, "MinimumSpend"))
        let remaining = integer(field(item, "RemainingQuantity"))
        let canClaim = store.session != nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(verbatim: amount.map { "¥\(moneyText($0))" } ?? "金额待确认")
                    .font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif)).foregroundStyle(Brand.primary)
                Spacer()
                Text(minimum.map { $0 > 0 ? "满\(moneyText($0))元可用" : "无门槛" } ?? "门槛待确认")
                    .font(.caption).foregroundStyle(Brand.muted)
            }
            Text(display(field(item, "Name")) ?? "平台消费券").font(.headline)
            Text("领取后 \(integer(field(item, "ValidityDays"))) 天有效 · 每人限领 \(integer(field(item, "PerUserLimit"))) 张")
                .font(.caption).foregroundStyle(Brand.muted)
            Text("实名领取：需完成账号实名资料登记、手机号验证和本活动授权。")
                .font(.caption).foregroundStyle(Brand.muted)
            Text("活动截止 \(dateText(field(item, "EndsAt"))) · 剩余 \(remaining) 张")
                .font(.caption).foregroundStyle(Brand.muted)
            Button(claimingID == id ? "领取中…" : remaining <= 0 ? "已领完" : canClaim ? "立即领取" : "请先登录") {
                Task { await prepareClaim(item) }
            }.buttonStyle(.borderedProminent).disabled(!canClaim || claimingID != "" || id.isEmpty || amount == nil || minimum == nil || remaining <= 0)
        }.merchantCard()
    }

    @ViewBuilder private func couponCard(_ item: [String: Any]) -> some View {
        let id = display(field(item, "Id")) ?? ""
        let type = display(field(item, "CampaignType")) ?? ""
        let state = display(field(item, "Status")) ?? ""
        let label = ["Available": "可使用", "Reserved": "使用中", "Redeemed": "已使用", "Expired": "已过期"][state] ?? "状态待确认"
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(verbatim: couponMoney(field(item, "CouponAmount")).map { "¥\(moneyText($0))" } ?? "金额待确认")
                    .font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif)).foregroundStyle(Brand.primary)
                Spacer()
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(Brand.primary)
            }
            Text("\(couponType(type)) · \(display(field(item, "CampaignName")) ?? "未命名券")").font(.headline)
            Text(couponMoney(field(item, "MinimumSpend")).map { $0 > 0 ? "满\(moneyText($0))元可用" : "无门槛" } ?? "门槛待确认")
                .font(.caption).foregroundStyle(Brand.muted)
            Text("领取时间 \(dateText(field(item, "ClaimedAt"))) · 有效期至 \(dateText(field(item, "ValidUntil")))")
                .font(.caption).foregroundStyle(Brand.muted)
            if state == "Available" && type == "Merchant" {
                Text("商城结算时选择使用，不支持现场扫码核销。")
                    .font(.caption).foregroundStyle(Brand.muted)
            } else if state == "Available" && type == "District" {
                Text("政府消费券按活动规则核验，当前券包不提供平台扫码入口。")
                    .font(.caption).foregroundStyle(Brand.muted)
            } else if state == "Available" && type == "Platform" {
                HStack {
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
        }.merchantCard()
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
                campaigns = []; campaignTotal = 0; error = "消费券功能暂未开放。"; return
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
            if sequence == requestSequence {
                self.error = error.localizedDescription
                retryPage = target; retryTab = "claim"
            }
        }
    }

    @MainActor private func loadCoupons(page target: Int) async {
        guard let token = store.session?.accessToken else { coupons = []; couponTotal = 0; loading = false; return }
        requestSequence += 1; let sequence = requestSequence
        loading = true; error = nil; retryPage = nil; retryTab = nil
        if target == 1 { coupons = []; couponTotal = 0; qrImage = nil }
        else { loadingMore = true }
        defer { if sequence == requestSequence { loading = false; loadingMore = false } }
        do {
            let encoded = status.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Available"
            let result = try await MobileAPI(store: store).get("/api/JHCTICouponClaim/GetMyCouponPage?page=\(target)&pageSize=\(pageSize)&status=\(encoded)", authenticated: true) as? [String: Any]
            guard sequence == requestSequence, store.session?.accessToken == token else { return }
            guard let result,
                  let rows = (result["data"] ?? result["Data"] ?? result["Items"] ?? result["items"]) as? [[String: Any]] else {
                throw MobileAPIError.unavailable("我的消费券分页回执无效")
            }
            coupons = target == 1 ? rows : coupons + rows
            couponPage = target
            couponTotal = integer(result["dataCount"] ?? result["DataCount"] ?? result["total"] ?? result["Total"])
        } catch {
            if sequence == requestSequence {
                self.error = error.localizedDescription
                retryPage = target; retryTab = "mine"
            }
        }
    }

    @MainActor private func prepareClaim(_ campaign: [String: Any]) async {
        guard let token = store.session?.accessToken else { onLogin(); return }
        let id = display(campaign["Id"]) ?? ""
        guard Int64(id).map({ $0 > 0 }) == true, claimingID.isEmpty else { return }
        do {
            let profile = try await MobileAPI(store: store).get("/api/JHCTITourismAuth/GetMyTicketIdentityProfile", authenticated: true) as? [String: Any]
            guard store.session?.accessToken == token else { return }
            guard nativeTicketIdentityProfileValid(profile) else {
                throw MobileAPIError.unavailable("实名资料状态格式异常，请重新读取。")
            }
            guard nativeTicketIdentityBookingEligible(profile) else { identityNotReady = true; return }
            pendingCampaign = campaign
        } catch { self.error = error.localizedDescription }
    }

    @MainActor private func submitClaim(_ campaign: [String: Any], identityConsent: Bool) async {
        guard let token = store.session?.accessToken else { onLogin(); return }
        let id = display(field(campaign, "Id")) ?? ""
        guard Int64(id).map({ $0 > 0 }) == true, claimingID.isEmpty else { return }
        let principal = MobileAPI(store: store).nativeTourismPrincipal(token)
        let attemptKey = "jhcti.coupon.claim.attempt.v1.\(principal).\(id)"
        if UserDefaults.standard.object(forKey: attemptKey) != nil,
           UserDefaults.standard.string(forKey: attemptKey) == nil {
            error = "设备上的领券请求记录无法读取，请检查存储空间后重试；本次未提交。"
            return
        }
        let requestID = requestIDs[id] ?? UserDefaults.standard.string(forKey: attemptKey) ?? "coupon-\(UUID().uuidString)"
        UserDefaults.standard.set(requestID, forKey: attemptKey)
        guard UserDefaults.standard.string(forKey: attemptKey) == requestID else {
            error = "设备暂时无法保存领券请求编号，请检查存储空间后重试；本次未提交。"
            return
        }
        requestIDs[id] = requestID; claimingID = id; error = nil; notice = nil
        defer { if claimingID == id { claimingID = "" } }
        do {
            let api = MobileAPI(store: store)
            let sendClaim = {
                try await api.post("/api/JHCTICouponClaim/Claim", body: [
                    "CampaignId": id, "RequestId": requestID, "IdentityConsent": identityConsent
                ], authenticated: true, timeoutInterval: 45)
            }
            do {
                _ = try await sendClaim()
            } catch {
                guard let delay = couponClaimRetryDelay(for: error), store.session?.accessToken == token else { throw error }
                notice = "请求暂时繁忙，稍后将使用同一请求编号自动重试一次。"
                try await Task.sleep(for: .milliseconds(delay))
                guard store.session?.accessToken == token else { throw MobileAPIError.unavailable("登录账号已变化，请重新操作") }
                _ = try await sendClaim()
            }
            guard store.session?.accessToken == token else { return }
            requestIDs.removeValue(forKey: id)
            UserDefaults.standard.removeObject(forKey: attemptKey)
            notice = "领取成功，已放入我的消费券。"
            requestSequence += 1
            await loadCampaigns(page: 1)
            if tab == "mine" { await loadCoupons(page: 1) }
        } catch { self.error = "\(error.localizedDescription)；如请求结果未确认，重试会复用同一请求号。" }
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
