import SwiftUI

func nativeTradeQuoteAvailable(_ expiresAt: Any?, now: Date = Date()) -> Bool {
    nativeBusinessTimestamp(expiresAt).map { $0 > now } ?? false
}

struct NativeTradeCheckoutView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.dismiss) private var dismiss
    let cartItems: [[String: Any]]
    var onRecoveryResolved: () -> Void = {}
    @State var regions: [[String: Any]] = []
    @State var addresses: [[String: Any]] = []
    @State var stores: [[String: Any]] = []
    @State var coupons: [[String: Any]] = []
    @State var selectedAddressID = ""
    @State var selectedRegionCode = ""
    @State var selectedStoreIDs: [String: String] = [:]
    @State var selectedCouponID = ""
    @State var pointsToUse = "0"
    @State var pointsBalance: Int64?
    @State var pointsDebt: Int64?
    @State var pointsSummaryError = false
    @State var pointsSummaryRevision = 0
    @State var quote: [String: Any]?
    @State var quoteNow = Date()
    @State var quoteSequence = 0
    @State var quoteOperation = 0
    @State var orderActionSequence = 0
    @State var quoteRequestStamp: String?
    @State var pageVisible = true
    @State var order: [String: Any]?
    @State var recoveryAttempt: NativeTradeOrderAttempt?
    @State var legacyRecoveryNeedsReconciliation = false
    @State var idempotencyKey = UUID().uuidString
    @State var loading = false
    @State var busy = false
    @State var error: String?
    @State var notice: String?
    @State var addAddress = false
    @State var editingAddressID = ""
    @State var addressCreateRequestID = UUID().uuidString
    @State var pendingDeleteAddressID = ""
    @State var confirmDeleteAddress = false
    @State var recipient = ""
    @State var phone = ""
    @State var detailAddress = ""
    @State var revision = 0
    @State var ownerToken: String?
    @State var featureEnabled = false

    var cartIDs: [String] { cartItems.compactMap { validID($0["Id"]) } }
    var hasPhysicalItems: Bool { cartItems.contains { ($0["DeliveryType"] as? String ?? "Physical") == "Physical" } }
    var merchants: [(String, String)] {
        var result: [(String, String)] = []
        for item in cartItems {
            guard let id = validID(item["MerchantId"]), !result.contains(where: { $0.0 == id }) else { continue }
            result.append((id, item["MerchantName"] as? String ?? "商户"))
        }
        return result
    }
    var selectedAddress: [String: Any]? { availableAddresses.first { validID($0["Id"]) == selectedAddressID } }
    var availableAddresses: [[String: Any]] {
        addresses.filter { address in
            guard validID(address["Id"]) != nil, let code = address["RegionCode"] as? String else { return false }
            return regions.contains { ($0["RegionCode"] as? String) == code }
        }
    }
    var addressRegionOptions: [[String: Any]] {
        var options = regions
        if !editingAddressID.isEmpty,
           let address = addresses.first(where: { validID($0["Id"]) == editingAddressID }),
           let code = address["RegionCode"] as? String,
           !options.contains(where: { ($0["RegionCode"] as? String) == code }) {
            options.append(["RegionCode": code, "RegionName": address["RegionName"] as? String ?? code])
        }
        return options
    }
    var compatibleCoupons: [[String: Any]] {
        coupons.filter { ["Platform", "Merchant"].contains($0["CampaignType"] as? String ?? "") && validID($0["Id"]) != nil }
    }
    var quoteItems: [[String: Any]] { quote?["Items"] as? [[String: Any]] ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if loading { ProgressView("正在读取结算信息…").frame(maxWidth: .infinity, alignment: .leading) }
                if let notice { Text(notice).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted) }
                if let error { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
                if let order {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("订单已核对").font(.system(size: NativeTypography.size(18), weight: .semibold)).foregroundStyle(Brand.primary)
                        Text("订单编号：\(order["OrderNo"] as? String ?? order["Id"] as? String ?? "已确认")")
                        Text(order["Status"] as? String == "PendingPayment"
                            ? "订单待付款，可在“我的订单”继续支付。" : "请在“我的订单”查看当前状态和订单详情。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                } else if let recoveryAttempt {
                    checkoutCard("上次商城订单尚未确认") {
                        Text(legacyRecoveryNeedsReconciliation
                            ? "旧版恢复记录未保存账号身份，当前账号查单未确认。为避免重复建单，已锁定重试；请切换到可能下单的账号核对订单，或联系平台处理。"
                            : "重试会使用已保存的报价、地址和原幂等号；不会创建第二笔订单。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        if !legacyRecoveryNeedsReconciliation {
                            Button(busy ? "正在核对原请求…" : "重试原下单请求") { Task { await retryOrder(recoveryAttempt) } }
                                .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(busy || loading)
                        }
                    }
                } else {
                    if hasPhysicalItems {
                        checkoutCard("收货地址") {
                            if addresses.isEmpty {
                                Text("没有适用于本次商品的已保存地址，请添加地址。")
                                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            } else {
                                ForEach(addresses.indices, id: \.self) { index in
                                    let address = addresses[index]
                                    let addressID = validID(address["Id"]) ?? ""
                                    let isCompatible = availableAddresses.contains(where: { validID($0["Id"]) == addressID })
                                    VStack(alignment: .leading, spacing: 6) {
                                        Button {
                                            guard isCompatible else { return }
                                            selectedAddressID = addressID; invalidateQuote()
                                        } label: {
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: selectedAddressID == addressID ? "largecircle.fill.circle" : "circle")
                                                    .foregroundStyle(isCompatible ? Brand.primary : Brand.muted)
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text("\(address["RecipientName"] as? String ?? "收件人") · \(address["PhoneNumber"] as? String ?? "")")
                                                        .font(.system(size: NativeTypography.size(14), weight: .medium)).foregroundStyle(Brand.ink)
                                                    Text("\(address["RegionName"] as? String ?? "") · \(address["DetailAddress"] as? String ?? "")")
                                                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                                                    if !isCompatible { Text("当前商品不支持配送到此地区")
                                                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted) }
                                                }
                                                Spacer(minLength: 0)
                                            }.contentShape(Rectangle())
                                        }.buttonStyle(.plain).disabled(busy || !isCompatible || addressID.isEmpty)
                                        HStack(spacing: 16) {
                                            Button("编辑") { beginAddressEdit(address) }
                                                .font(.system(size: NativeTypography.size(14), weight: .medium)).disabled(busy || addressID.isEmpty)
                                            Button("删除", role: .destructive) {
                                                pendingDeleteAddressID = addressID; confirmDeleteAddress = true
                                            }.font(.system(size: NativeTypography.size(14), weight: .medium)).disabled(busy || addressID.isEmpty)
                                        }
                                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Brand.background, in: RoundedRectangle(cornerRadius: 9))
                                }
                            }
                            Button(addAddress ? "取消编辑地址" : "添加收货地址") {
                                if addAddress { clearAddressEditor() } else { beginAddressCreate() }
                            }
                                .font(.system(size: NativeTypography.size(14), weight: .medium)).foregroundStyle(Brand.primary)
                                .disabled(busy || addresses.count >= 5 && editingAddressID.isEmpty)
                            if addAddress { addressEditor }
                            Text("纯虚拟商品无需收货地址；包含实物商品时需选择支持的配送区域。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        }
                    } else {
                        checkoutCard("虚拟商品交付") {
                            Text("支付成功后可在本人订单中查看平台生成的券码或链接；纯虚拟订单免填地址、运费为 0。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        }
                    }

                    checkoutCard("履约门店") {
                        if merchants.isEmpty { Text("当前商品没有可选择的商户门店。") }
                        ForEach(merchants, id: \.0) { merchant in
                            let (merchantID, merchantName) = merchant
                            let options = stores.filter { validID($0["MerchantId"]) == merchantID }
                            if options.isEmpty {
                                Text("当前商户没有可履约门店。")
                                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            }
                            Picker(merchantName, selection: Binding(get: { selectedStoreIDs[merchantID] ?? "" }, set: {
                                selectedStoreIDs[merchantID] = $0; invalidateQuote()
                            })) {
                                Text("请选择门店").tag("")
                                ForEach(options.indices, id: \.self) { index in
                                    let option = options[index]
                                    Text("\(option["StoreName"] as? String ?? "门店") · \(option["Address"] as? String ?? "")")
                                        .tag(validID(option["StoreId"]) ?? "")
                                }
                            }.pickerStyle(.menu).disabled(busy || options.isEmpty)
                        }
                    }

                    checkoutCard("优惠券与积分") {
                        Picker("优惠券", selection: $selectedCouponID) {
                            Text("不使用优惠券").tag("")
                            ForEach(compatibleCoupons.indices, id: \.self) { index in
                                let coupon = compatibleCoupons[index]
                                let kind = coupon["CampaignType"] as? String == "Merchant" ? "商户优惠券" : "平台消费券"
                                Text("\(kind) · \(coupon["CampaignName"] as? String ?? "优惠券") · ¥\(money(coupon["CouponAmount"]) ?? "待核验")")
                                    .tag(validID(coupon["Id"]) ?? "")
                            }
                        }.pickerStyle(.menu).disabled(busy || !quoteFeatureEnabled || hasPromotion)
                            .onChange(of: selectedCouponID) { _, value in
                                if compatibleCoupons.first(where: { validID($0["Id"]) == value })?["CampaignType"] as? String == "Platform" {
                                    pointsToUse = "0"
                                }
                                invalidateQuote()
                            }
                        if hasPromotion {
                            Text("所选商品正在参加限时促销，不能与优惠券或消费券叠加使用。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        }
                        Text("每 100 积分抵 1 元，最多抵其他优惠后应付金额的 50%；限时商品促销不可叠加优惠券或积分，平台消费券不可与积分叠加。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        TextField("本次使用积分（默认 0）", text: $pointsToUse)
                            .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                            .disabled(busy || hasPromotion || selectedPlatformCoupon || pointsBalance == nil
                                || (pointsDebt.map { $0 > 0 } ?? true) || pointsSummaryError)
                            .onChange(of: pointsToUse) { _, _ in invalidateQuote() }
                        pointsStatusText
                        if pointsSummaryError {
                            Button("重新读取积分余额") { pointsSummaryRevision += 1 }
                                .font(.system(size: NativeTypography.size(14))).disabled(busy)
                        }
                        if !compatibleCoupons.isEmpty { Text("优惠券由服务端复核适用商品、门槛和有效期。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted) }
                    }

                    Button(busy ? "正在处理…" : "获取最新报价") { Task { await requestQuote() } }
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                        .disabled(busy || loading || !quoteFeatureEnabled || (hasPhysicalItems && selectedAddress == nil)
                            || merchants.contains(where: { validID(selectedStoreIDs[$0.0]) == nil }))

                    if let quote {
                        checkoutCard("服务端报价") {
                            ForEach(Array(quoteItems.enumerated()), id: \.offset) { _, item in
                                HStack { Text("\(item["ProductName"] as? String ?? "商品") × \(item["Quantity"] as? Int ?? 0)")
                                    Spacer(); Text("¥\(money(item["Subtotal"]) ?? "待核验")") }
                                    .font(.system(size: NativeTypography.size(14)))
                            }
                            amountRow("商品金额", quote["ProductAmount"])
                            amountRow("运费", quote["FreightAmount"])
                            amountRow("优惠", quote["DiscountAmount"])
                            amountRow("积分抵扣", quote["PointsDiscountAmount"])
                            amountRow("应付金额", quote["PayableAmount"], emphasized: true)
                            Text(nativeTradeQuoteAvailable(quote["ExpiresAt"], now: quoteNow)
                                ? "报价有效期：\(quote["ExpiresAt"] as? String ?? "")。下单时服务端会再次核验价格、库存和资格。"
                                : "报价已到期或有效期无法确认，请重新获取最新报价。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            Button(busy ? "正在创建订单…" : "确认并创建待付款订单") { Task { await createOrder() } }
                                .buttonStyle(.borderedProminent).tint(Brand.primary)
                                .disabled(busy || loading || !quoteFeatureEnabled || recoveryAttempt != nil
                                    || quoteRequestStamp != quoteInputStamp() || !nativeTradeQuoteAvailable(quote["ExpiresAt"], now: quoteNow))
                        }
                    }
                }
                Button("重新读取结算信息") { revision += 1 }.font(.system(size: NativeTypography.size(14))).disabled(busy || loading || order != nil)
            }
            .padding(16)
        }
        .background(Brand.background)
        .navigationTitle("确认商品订单")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(store.session?.accessToken ?? "")-\(revision)") { await load() }
        .task(id: "\(store.session?.accessToken ?? "")-\(pointsSummaryRevision)") { await loadPointsSummary() }
        .task(id: "\(quote?["QuoteId"] as? String ?? "")-\(quote?["ExpiresAt"] as? String ?? "")-\(scenePhase)") {
            quoteNow = Date()
            guard scenePhase == .active, let deadline = nativeBusinessTimestamp(quote?["ExpiresAt"]) else { return }
            while !Task.isCancelled && deadline > Date() {
                do { try await Task.sleep(for: .seconds(min(3600, deadline.timeIntervalSinceNow))) }
                catch { return }
                quoteNow = Date()
            }
        }
        .onAppear { pageVisible = true; quoteNow = Date() }
        .onDisappear { pageVisible = false; invalidateQuote() }
        .onChange(of: scenePhase) { _, phase in
            quoteNow = Date()
            if phase != .active { invalidateQuote() }
        }
        .confirmationDialog("删除这条收货地址？", isPresented: $confirmDeleteAddress, titleVisibility: .visible) {
            Button("删除地址", role: .destructive) { Task { await deleteAddress(id: pendingDeleteAddressID) } }
            Button("取消", role: .cancel) { pendingDeleteAddressID = "" }
        } message: { Text("删除后无法恢复。") }
    }

    private var quoteFeatureEnabled: Bool { featureEnabled }
    var hasPromotion: Bool { cartItems.contains { ($0["PromotionId"] as? String)?.isEmpty == false } }
    var selectedPlatformCoupon: Bool {
        compatibleCoupons.first { validID($0["Id"]) == selectedCouponID }?["CampaignType"] as? String == "Platform"
    }

    @ViewBuilder private var pointsStatusText: some View {
        if store.session == nil {
            Text("登录后查看可用积分。").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
        } else if let pointsDebt, pointsDebt > 0 {
            Text("存在积分欠额（\(pointsDebt)），当前不能抵扣；后续积分奖励将优先抵扣欠额。")
                .font(.system(size: NativeTypography.size(14))).foregroundStyle(.orange)
        } else if let pointsBalance, pointsDebt == 0 {
            Text("可用积分：\(pointsBalance)").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
        } else if pointsSummaryError {
            Text("积分余额暂时无法读取，当前不能使用积分；仍可按 0 积分结算。")
                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
        } else {
            Text("正在读取积分余额…").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
        }
    }

    @ViewBuilder private var addressEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("收件人", text: $recipient).textFieldStyle(.roundedBorder)
                .onChange(of: recipient) { _, _ in if editingAddressID.isEmpty { addressCreateRequestID = UUID().uuidString } }
            TextField("联系电话", text: $phone).keyboardType(.phonePad).textFieldStyle(.roundedBorder)
                .onChange(of: phone) { _, _ in if editingAddressID.isEmpty { addressCreateRequestID = UUID().uuidString } }
            Picker("配送区域", selection: $selectedRegionCode) {
                ForEach(addressRegionOptions.indices, id: \.self) { index in
                    Text(addressRegionOptions[index]["RegionName"] as? String ?? "配送区域")
                        .tag(addressRegionOptions[index]["RegionCode"] as? String ?? "")
                }
            }.pickerStyle(.menu)
                .onChange(of: selectedRegionCode) { _, _ in if editingAddressID.isEmpty { addressCreateRequestID = UUID().uuidString } }
            TextField("详细地址", text: $detailAddress, axis: .vertical).textFieldStyle(.roundedBorder)
                .onChange(of: detailAddress) { _, _ in if editingAddressID.isEmpty { addressCreateRequestID = UUID().uuidString } }
            Button(editingAddressID.isEmpty ? "保存并选择此地址" : "保存地址修改") { Task { await saveAddress() } }
                .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.primary)
                .disabled(busy || recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedRegionCode.isEmpty
                    || detailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func checkoutCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
            content()
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private func amountRow(_ title: String, _ raw: Any?, emphasized: Bool = false) -> some View {
        HStack { Text(title); Spacer(); Text("¥\(money(raw) ?? "待核验")") }
            .font(.system(size: NativeTypography.size(emphasized ? 15 : 12), weight: emphasized ? .semibold : .regular))
            .foregroundStyle(emphasized ? Brand.primary : Brand.ink)
    }

    func validID(_ value: Any?) -> String? {
        guard let value = value as? String, let parsed = Int64(value), parsed > 0 else { return nil }
        return value
    }

    private func money(_ raw: Any?) -> String? {
        guard let cents = nativeTradeMoneyCents(raw) else { return nil }
        return "\(cents / 100).\(String(format: "%02lld", cents % 100))"
    }

}

func nativeTradeAddressID(_ raw: Any?) -> String? {
    let value: Int64?
    if let number = raw as? NSNumber { value = number.int64Value }
    else if let text = raw as? String { value = Int64(text) }
    else { value = nil }
    guard let value, value > 0 else { return nil }
    return String(value)
}
