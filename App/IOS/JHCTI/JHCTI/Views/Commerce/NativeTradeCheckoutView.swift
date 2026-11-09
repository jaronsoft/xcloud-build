import SwiftUI

@MainActor enum NativeTradeRecoveryStore {
    private static func validKey(_ key: String) -> Bool {
        let prefix = "jhcti.native.trade-order-attempt.v1."
        let suffix = String(key.dropFirst(prefix.count))
        return key.hasPrefix(prefix) && suffix.count == 64 && suffix.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    static func read(_ key: String) -> (exists: Bool, attempt: NativeTradeOrderAttempt?) {
        guard validKey(key), UserDefaults.standard.object(forKey: key) != nil else { return (false, nil) }
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(NativeTradeOrderAttempt.self, from: data), value.isValid else { return (true, nil) }
        return (true, value)
    }

    static func save(_ key: String, legacyKey: String? = nil, attempt: NativeTradeOrderAttempt) -> Bool {
        guard validKey(key), attempt.isValid else { return false }
        let current = read(key)
        if current.exists { return current.attempt == attempt }
        if let legacyKey, read(legacyKey).exists { return false }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(attempt) else { return false }
        UserDefaults.standard.set(data, forKey: key)
        return UserDefaults.standard.data(forKey: key) == data
    }

    static func clear(_ key: String, expected: NativeTradeOrderAttempt) -> Bool {
        guard read(key).attempt == expected else { return false }
        UserDefaults.standard.removeObject(forKey: key)
        return UserDefaults.standard.object(forKey: key) == nil
    }
}

struct NativeTradeOrderAttempt: Codable, Equatable {
    let idempotencyKey: String
    let quoteID: String
    let addressID: String
    var expectedOrderDigest: String? = nil

    var isValid: Bool {
        idempotencyKey.range(of: "^[A-Za-z0-9._:-]{16,100}$", options: .regularExpression)?.upperBound == idempotencyKey.endIndex
            && Int64(quoteID).map { $0 > 0 && String($0) == quoteID } == true
            && (addressID == "0" || Int64(addressID).map { $0 > 0 && String($0) == addressID } == true)
            && (expectedOrderDigest == nil || (expectedOrderDigest?.count == 64
                && expectedOrderDigest?.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil))
    }
}


private func nativeTradeQuoteAvailable(_ expiresAt: Any?, now: Date = Date()) -> Bool {
    nativeBusinessTimestamp(expiresAt).map { $0 > now } ?? false
}

struct NativeTradeCheckoutView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    let cartItems: [[String: Any]]
    var onRecoveryResolved: () -> Void = {}
    @State private var regions: [[String: Any]] = []
    @State private var addresses: [[String: Any]] = []
    @State private var stores: [[String: Any]] = []
    @State private var coupons: [[String: Any]] = []
    @State private var selectedAddressID = ""
    @State private var selectedRegionCode = ""
    @State private var selectedStoreIDs: [String: String] = [:]
    @State private var selectedCouponID = ""
    @State private var pointsToUse = "0"
    @State private var pointsBalance: Int64?
    @State private var pointsDebt: Int64?
    @State private var pointsSummaryError = false
    @State private var pointsSummaryRevision = 0
    @State private var quote: [String: Any]?
    @State private var quoteNow = Date()
    @State private var quoteSequence = 0
    @State private var quoteOperation = 0
    @State private var orderActionSequence = 0
    @State private var quoteRequestStamp: String?
    @State private var pageVisible = true
    @State private var order: [String: Any]?
    @State private var recoveryAttempt: NativeTradeOrderAttempt?
    @State private var legacyRecoveryNeedsReconciliation = false
    @State private var idempotencyKey = UUID().uuidString
    @State private var loading = false
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var addAddress = false
    @State private var editingAddressID = ""
    @State private var addressCreateRequestID = UUID().uuidString
    @State private var pendingDeleteAddressID = ""
    @State private var confirmDeleteAddress = false
    @State private var recipient = ""
    @State private var phone = ""
    @State private var detailAddress = ""
    @State private var revision = 0
    @State private var ownerToken: String?
    @State private var featureEnabled = false

    private var cartIDs: [String] { cartItems.compactMap { validID($0["Id"]) } }
    private var hasPhysicalItems: Bool { cartItems.contains { ($0["DeliveryType"] as? String ?? "Physical") == "Physical" } }
    private var merchants: [(String, String)] {
        var result: [(String, String)] = []
        for item in cartItems {
            guard let id = validID(item["MerchantId"]), !result.contains(where: { $0.0 == id }) else { continue }
            result.append((id, item["MerchantName"] as? String ?? "商户"))
        }
        return result
    }
    private var selectedAddress: [String: Any]? { availableAddresses.first { validID($0["Id"]) == selectedAddressID } }
    private var availableAddresses: [[String: Any]] {
        addresses.filter { address in
            guard validID(address["Id"]) != nil, let code = address["RegionCode"] as? String else { return false }
            return regions.contains { ($0["RegionCode"] as? String) == code }
        }
    }
    private var addressRegionOptions: [[String: Any]] {
        var options = regions
        if !editingAddressID.isEmpty,
           let address = addresses.first(where: { validID($0["Id"]) == editingAddressID }),
           let code = address["RegionCode"] as? String,
           !options.contains(where: { ($0["RegionCode"] as? String) == code }) {
            options.append(["RegionCode": code, "RegionName": address["RegionName"] as? String ?? code])
        }
        return options
    }
    private var compatibleCoupons: [[String: Any]] {
        coupons.filter { ["Platform", "Merchant"].contains($0["CampaignType"] as? String ?? "") && validID($0["Id"]) != nil }
    }
    private var quoteItems: [[String: Any]] { quote?["Items"] as? [[String: Any]] ?? [] }

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
    private var hasPromotion: Bool { cartItems.contains { ($0["PromotionId"] as? String)?.isEmpty == false } }
    private var selectedPlatformCoupon: Bool {
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

    @MainActor private func loadPointsSummary() async {
        let requestRevision = pointsSummaryRevision
        guard let token = store.session?.accessToken else {
            pointsBalance = nil; pointsDebt = nil; pointsSummaryError = false; pointsToUse = "0"
            return
        }
        do {
            guard let summary = try await MobileAPI(store: store).get(
                "/api/JHCTIMemberProgram/GetMySummary", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any],
                  let balanceText = nativeMemberLedgerString(summary, "PointsBalance"),
                  let balance = Int64(balanceText), balance >= 0,
                  let debtText = nativeMemberLedgerString(summary, "PointsDebt"),
                  let debt = Int64(debtText), debt >= 0,
                  store.session?.accessToken == token, pointsSummaryRevision == requestRevision else {
                throw MobileAPIError.unavailable("积分摘要无效")
            }
            pointsBalance = debt > 0 ? 0 : balance
            pointsDebt = debt
            pointsSummaryError = false
            if debt > 0 { pointsToUse = "0"; invalidateQuote() }
        } catch {
            guard store.session?.accessToken == token, pointsSummaryRevision == requestRevision else { return }
            pointsBalance = nil; pointsDebt = nil; pointsSummaryError = true
            pointsToUse = "0"; invalidateQuote()
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

    private func validID(_ value: Any?) -> String? {
        guard let value = value as? String, let parsed = Int64(value), parsed > 0 else { return nil }
        return value
    }

    private func money(_ raw: Any?) -> String? {
        guard let cents = nativeTradeMoneyCents(raw) else { return nil }
        return "\(cents / 100).\(String(format: "%02lld", cents % 100))"
    }

    private func quoteInputStamp() -> String? {
        let value: [String: Any] = ["CartItemIds": cartIDs, "AddressId": hasPhysicalItems ? selectedAddressID : "0",
            "RegionCode": hasPhysicalItems ? (selectedAddress?["RegionCode"] as? String ?? "") : "DIGITAL",
            "Stores": selectedStoreIDs, "Coupon": selectedCouponID, "Points": pointsToUse]
        return (try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys))?.base64EncodedString()
    }

    private func invalidateQuote() {
        quoteSequence += 1; quote = nil; quoteRequestStamp = nil; idempotencyKey = UUID().uuidString
    }

    private func beginAddressCreate() {
        editingAddressID = ""; recipient = ""; phone = ""; detailAddress = ""
        selectedRegionCode = regions.first?["RegionCode"] as? String ?? ""
        addressCreateRequestID = UUID().uuidString; addAddress = true; error = nil
    }

    private func beginAddressEdit(_ address: [String: Any]) {
        guard let id = validID(address["Id"]) else { error = "地址编号无效，请重新读取结算信息。"; return }
        editingAddressID = id
        recipient = address["RecipientName"] as? String ?? ""
        phone = address["PhoneNumber"] as? String ?? ""
        detailAddress = address["DetailAddress"] as? String ?? ""
        selectedRegionCode = address["RegionCode"] as? String ?? ""
        addAddress = true; error = nil
    }

    private func clearAddressEditor() {
        editingAddressID = ""; recipient = ""; phone = ""; detailAddress = ""
        selectedRegionCode = ""; addAddress = false
    }

    @MainActor private func load() async {
        let token = store.session?.accessToken
        if hasPromotion && (!selectedCouponID.isEmpty || pointsToUse != "0") {
            selectedCouponID = ""; pointsToUse = "0"; invalidateQuote()
        }
        invalidateQuote(); quoteOperation += 1; orderActionSequence += 1
        if ownerToken != token {
            ownerToken = token; addresses = []; quote = nil; order = nil
            selectedAddressID = ""; selectedRegionCode = ""; clearAddressEditor()
            addressCreateRequestID = UUID().uuidString; pendingDeleteAddressID = ""; confirmDeleteAddress = false
            selectedStoreIDs = [:]; selectedCouponID = ""; pointsToUse = "0"
        }
        guard let token else { error = "请先登录并选择有效商品。"; return }
        loading = true; busy = false; featureEnabled = false; error = nil; notice = nil; quote = nil; order = nil
        recoveryAttempt = nil
        legacyRecoveryNeedsReconciliation = false
        let storageKey = nativeTradeRecoveryStorageKey(accessToken: token)
        let legacyStorageKey = nativeLegacyTradeRecoveryStorageKey(accessToken: token)
        let current = NativeTradeRecoveryStore.read(storageKey)
        let legacy = NativeTradeRecoveryStore.read(legacyStorageKey)
        if current.exists || legacy.exists {
            let isLegacy = !current.exists
            let savedKey = isLegacy ? legacyStorageKey : storageKey
            guard let attempt = isLegacy ? legacy.attempt : current.attempt else {
                error = "发现无法安全读取的商城订单恢复标记。为避免重复下单，请先核对本人订单。"
                loading = false
                return
            }
            recoveryAttempt = attempt
            legacyRecoveryNeedsReconciliation = isLegacy
            do {
                let recovered = try await MobileAPI(store: store).get(
                    "/api/JHCTITradeOrder/GetMyOrderByIdempotencyKey?idempotencyKey=\(attempt.idempotencyKey)", authenticated: true,
                    expectedPrincipal: nativeTourismPrincipal(token)
                ) as? [String: Any]
                guard !Task.isCancelled, store.session?.accessToken == token else { return }
                if let recovered, nativeTradeRecoveryMatches(recovered, digest: attempt.expectedOrderDigest) {
                    guard NativeTradeRecoveryStore.clear(savedKey, expected: attempt) else {
                        notice = "恢复记录已变化或未能清理，请重新读取结算信息后核对。"; loading = false; return
                    }
                    order = recovered; recoveryAttempt = nil
                    legacyRecoveryNeedsReconciliation = false
                    onRecoveryResolved()
                } else {
                    notice = isLegacy
                        ? "旧版恢复记录未保存账号身份，当前账号查单未确认。为避免重复建单，已停止自动重试；请切换到可能下单的账号核对订单，或联系平台处理。"
                        : attempt.expectedOrderDigest == nil
                            ? "旧版请求缺少报价摘要。点击下方按钮后，服务端会按原幂等号、报价和收货地址核对；不会重复创建订单。"
                            : "上次下单请求仍待核对；请重试原请求，勿重新创建订单。"
                }
            } catch {
                guard !Task.isCancelled, store.session?.accessToken == token else { return }
                notice = isLegacy
                    ? "旧版恢复记录暂时无法核对，已停止自动重试以避免重复建单。请稍后刷新本人订单，或联系平台处理。"
                    : attempt.expectedOrderDigest == nil
                        ? "旧版请求缺少报价摘要，原请求未能核对。恢复记录已保留；请重试原请求，系统会通过服务端幂等校验避免重复创建。"
                    : "上次下单请求暂时无法确认；重试会沿用原幂等请求。"
            }
            if recoveryAttempt != nil || order != nil {
                loading = false
                return
            }
        }
        guard !cartIDs.isEmpty else { error = "购物车中没有可结算商品。"; loading = false; return }
        featureEnabled = false
        let api = MobileAPI(store: store)
        do {
            let checkoutAccess = await api.featureAccessState("F-ECOM-003")
            guard store.session?.accessToken == token else { return }
            featureEnabled = checkoutAccess == .open
            if !featureEnabled {
                notice = checkoutAccess.message(featureName: "商品订购", action: "不能获取报价或创建订单。")
                loading = false
                return
            }
            let principal = nativeTourismPrincipal(token)
            let regionValue = try await api.postJSON("/api/JHCTICart/GetCheckoutRegions", body: cartIDs, authenticated: true,
                expectedPrincipal: principal)
            let storeValue = try await api.postJSON("/api/JHCTITradeOrder/GetStoreOptions", body: cartIDs, authenticated: true,
                expectedPrincipal: principal)
            let addressValue = try await api.get("/api/JHCTITradeOrder/GetMyAddresses", authenticated: true,
                expectedPrincipal: principal)
            let couponValue = try await api.get("/api/JHCTICouponClaim/GetMyCheckoutCoupons?page=1&pageSize=100", authenticated: true,
                expectedPrincipal: principal)
            guard store.session?.accessToken == token else { return }
            regions = regionValue as? [[String: Any]] ?? []
            stores = storeValue as? [[String: Any]] ?? []
            addresses = addressValue as? [[String: Any]] ?? []
            let couponPage = couponValue as? [String: Any] ?? [:]
            coupons = (couponPage["data"] as? [[String: Any]]) ?? (couponPage["Data"] as? [[String: Any]]) ?? []
            if !hasPhysicalItems { selectedRegionCode = "DIGITAL" }
            if selectedAddressID.isEmpty, let first = availableAddresses.first,
               let id = validID(first["Id"]) { selectedAddressID = id }
            if hasPhysicalItems, selectedRegionCode.isEmpty, let first = regions.first {
                selectedRegionCode = first["RegionCode"] as? String ?? ""
            }
            for (merchantID, _) in merchants where selectedStoreIDs[merchantID] == nil {
                selectedStoreIDs[merchantID] = stores.first(where: { validID($0["MerchantId"]) == merchantID }).flatMap { validID($0["StoreId"]) } ?? ""
            }
        } catch { if store.session?.accessToken == token { self.error = error.localizedDescription } }
        if store.session?.accessToken == token { loading = false }
    }

    @MainActor private func saveAddress() async {
        guard !busy, let token = store.session?.accessToken,
              let region = addressRegionOptions.first(where: { ($0["RegionCode"] as? String) == selectedRegionCode }) else { return }
        busy = true; error = nil
        do {
            var body: [String: Any] = [
                "RecipientName": recipient.trimmingCharacters(in: .whitespacesAndNewlines),
                "PhoneNumber": phone.trimmingCharacters(in: .whitespacesAndNewlines), "RegionCode": selectedRegionCode,
                "RegionName": region["RegionName"] as? String ?? "", "DetailAddress": detailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
            if editingAddressID.isEmpty { body["RequestId"] = addressCreateRequestID }
            else { body["Id"] = editingAddressID }
            let response = try await MobileAPI(store: store).post("/api/JHCTITradeOrder/SaveMyAddress", body: body,
                authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any]
            guard store.session?.accessToken == token, let response, let id = validID(response["Id"]) else {
                throw MobileAPIError.unavailable("地址保存结果无法确认，请重新读取地址后继续。")
            }
            addresses.removeAll { validID($0["Id"]) == id }; addresses.append(response)
            selectedAddressID = id; clearAddressEditor(); addressCreateRequestID = UUID().uuidString; invalidateQuote()
        } catch { if store.session?.accessToken == token { self.error = error.localizedDescription } }
        if store.session?.accessToken == token { busy = false }
    }

    @MainActor private func deleteAddress(id: String) async {
        guard !busy, validID(id) != nil, let token = store.session?.accessToken else { error = "地址或登录状态无效，请刷新后重试。"; return }
        busy = true; error = nil
        do {
            let result = try await MobileAPI(store: store).post("/api/JHCTITradeOrder/DeleteMyAddress", body: ["Id": id],
                authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? Bool
            guard store.session?.accessToken == token, result == true else { throw MobileAPIError.unavailable("地址删除结果无法确认，请重新读取地址。") }
            addresses.removeAll { validID($0["Id"]) == id }
            if selectedAddressID == id { selectedAddressID = ""; invalidateQuote() }
            if editingAddressID == id { clearAddressEditor() }
            pendingDeleteAddressID = ""
        } catch { if store.session?.accessToken == token { self.error = error.localizedDescription } }
        if store.session?.accessToken == token { busy = false }
    }

    @MainActor private func requestQuote() async {
        guard !busy, !loading, pageVisible, scenePhase == .active, featureEnabled, recoveryAttempt == nil, order == nil,
              let token = store.session?.accessToken, !cartIDs.isEmpty, cartIDs.count <= 100 else { return }
        if hasPromotion && !selectedCouponID.isEmpty {
            error = "所选商品正在参加限时促销，不能与优惠券或消费券叠加使用。"; return
        }
        if hasPhysicalItems && selectedAddress == nil { error = "请选择支持当前商品配送范围的本人收货地址。"; return }
        let regionCode = hasPhysicalItems ? (selectedAddress?["RegionCode"] as? String ?? "") : "DIGITAL"
        let selections = merchants.compactMap { merchantID, _ -> [String: String]? in
            guard let storeID = selectedStoreIDs[merchantID], !storeID.isEmpty else { return nil }
            return ["MerchantId": merchantID, "StoreId": storeID]
        }
        guard selections.count == merchants.count else { error = "请为每个商户选择履约门店。"; return }
        guard let points = Int64(pointsToUse), points >= 0 else { error = "积分数量必须为非负整数。"; return }
        if let pointsError = pointsValidationError(points) { error = pointsError; return }
        invalidateQuote(); let sequence = quoteSequence; let stamp = quoteInputStamp()
        quoteOperation += 1; let operation = quoteOperation
        busy = true; error = nil
        defer { if store.session?.accessToken == token && quoteOperation == operation { busy = false } }
        do {
            let accessState = await MobileAPI(store: store).featureAccessState("F-ECOM-003", forceRefresh: true)
            guard !Task.isCancelled, pageVisible, scenePhase == .active, quoteSequence == sequence,
                  quoteInputStamp() == stamp, store.session?.accessToken == token else { return }
            featureEnabled = accessState == .open
            guard featureEnabled else {
                error = accessState.message(featureName: "商品订购", action: "当前未请求结算报价。")
                return
            }
            let result = try await MobileAPI(store: store).post("/api/JHCTITradeOrder/Quote", body: [
                "CartItemIds": cartIDs, "RegionCode": regionCode, "StoreSelections": selections,
                "CouponClaimId": selectedCouponID.isEmpty ? NSNull() : selectedCouponID as Any,
                "PointsToUse": String(points)
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any]
            guard !Task.isCancelled, pageVisible, scenePhase == .active, quoteSequence == sequence,
                  quoteInputStamp() == stamp, store.session?.accessToken == token else { return }
            guard let result, nativeTradeQuoteMatches(result, cartIDs: cartIDs, region: regionCode,
                    stores: selectedStoreIDs, coupon: selectedCouponID, points: String(points)),
                  nativeTradeQuoteAvailable(result["ExpiresAt"]) else { throw MobileAPIError.unavailable("报价格式或有效期异常，请重新获取最新报价。") }
            quote = result; quoteRequestStamp = stamp; quoteNow = Date(); idempotencyKey = UUID().uuidString
        } catch {
            if pageVisible && scenePhase == .active && quoteSequence == sequence && store.session?.accessToken == token {
                self.error = error.localizedDescription
            }
        }
    }

    private func pointsValidationError(_ points: Int64) -> String? {
        guard points > 0 else { return nil }
        if hasPromotion { return "当前商品促销不可与积分叠加，请调整优惠后重试。" }
        if selectedPlatformCoupon { return "平台消费券不可与积分叠加，请调整优惠后重试。" }
        guard !pointsSummaryError, let pointsBalance, let pointsDebt else {
            return "积分余额尚未确认，当前不能使用积分。请重新读取后重试。"
        }
        if pointsDebt > 0 { return "存在积分欠额，当前不能抵扣；后续积分奖励将优先抵扣欠额。" }
        if points > pointsBalance { return "使用积分超过当前可用余额，请调整后重试。" }
        return nil
    }

    @MainActor private func createOrder() async {
        guard !busy, !loading, pageVisible, scenePhase == .active, featureEnabled,
              recoveryAttempt == nil, order == nil, let token = store.session?.accessToken, let quote,
              let quoteID = nativeCartID(quote["QuoteId"]) else { return }
        guard quoteRequestStamp != nil, quoteRequestStamp == quoteInputStamp(),
              nativeTradeQuoteMatches(quote, cartIDs: cartIDs,
                  region: hasPhysicalItems ? (selectedAddress?["RegionCode"] as? String ?? "") : "DIGITAL",
                  stores: selectedStoreIDs, coupon: selectedCouponID, points: pointsToUse),
              nativeTradeQuoteAvailable(quote["ExpiresAt"]) else {
            error = "报价已失效或结算选择已变化，请重新获取最新报价。"; invalidateQuote(); return
        }
        guard let digest = nativeTradeQuoteOrderDigest(quote) else { error = "原报价摘要无法核对，请重新获取报价。"; return }
        let attempt = NativeTradeOrderAttempt(idempotencyKey: idempotencyKey, quoteID: quoteID,
            addressID: hasPhysicalItems ? selectedAddressID : "0", expectedOrderDigest: digest)
        guard attempt.isValid else {
            error = "本次下单参数无效，尚未提交订单。"; return
        }
        orderActionSequence += 1; let action = orderActionSequence
        busy = true; error = nil
        defer { if orderActionSequence == action && store.session?.accessToken == token { busy = false } }
        let accessState = await MobileAPI(store: store).featureAccessState("F-ECOM-003", forceRefresh: true)
        guard !Task.isCancelled, orderActionSequence == action, pageVisible, scenePhase == .active,
              quoteRequestStamp == quoteInputStamp(), store.session?.accessToken == token else { return }
        featureEnabled = accessState == .open
        guard featureEnabled else {
            error = accessState.message(featureName: "商品订购", action: "当前未创建新订单。")
            return
        }
        let storageKey = nativeTradeRecoveryStorageKey(accessToken: token)
        guard NativeTradeRecoveryStore.save(storageKey, legacyKey: nativeLegacyTradeRecoveryStorageKey(accessToken: token), attempt: attempt) else {
            error = "已有下单请求尚未确认，或恢复记录未能保存。请先重新读取并核对原请求。"; return
        }
        recoveryAttempt = attempt
        do {
            let response = try await MobileAPI(store: store).post("/api/JHCTITradeOrder/Create", body: [
                "IdempotencyKey": attempt.idempotencyKey, "QuoteId": attempt.quoteID,
                "AddressId": attempt.addressID
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any]
            guard !Task.isCancelled, orderActionSequence == action, store.session?.accessToken == token else { return }
            guard let response, nativeTradeOrderMatchesQuote(response, quote: quote) else {
                throw MobileAPIError.unavailable("订单回执与报价无法核对，请保留原请求并查询本人订单。")
            }
            guard NativeTradeRecoveryStore.clear(storageKey, expected: attempt) else {
                throw MobileAPIError.unavailable("恢复记录已变化或未能清理，请重新读取后核对订单。")
            }
            order = response; recoveryAttempt = nil
            onRecoveryResolved()
        } catch { if orderActionSequence == action && store.session?.accessToken == token { self.error = error.localizedDescription + "；可重试同一请求核对，系统会按幂等号避免重复建单。" } }
    }

    @MainActor private func retryOrder(_ attempt: NativeTradeOrderAttempt) async {
        guard !busy, !loading, pageVisible, scenePhase == .active, !legacyRecoveryNeedsReconciliation,
              recoveryAttempt == attempt, attempt.isValid, let token = store.session?.accessToken else { return }
        let storageKey = nativeTradeRecoveryStorageKey(accessToken: token)
        guard NativeTradeRecoveryStore.read(storageKey).attempt == attempt,
              NativeTradeRecoveryStore.save(storageKey, attempt: attempt) else {
            error = "设备未能保存原订单恢复编号；请求尚未重试。"; return
        }
        orderActionSequence += 1; let action = orderActionSequence
        busy = true; error = nil
        defer { if orderActionSequence == action && store.session?.accessToken == token { busy = false } }
        do {
            let response = try await MobileAPI(store: store).post("/api/JHCTITradeOrder/Create", body: [
                "IdempotencyKey": attempt.idempotencyKey, "QuoteId": attempt.quoteID, "AddressId": attempt.addressID
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any]
            guard !Task.isCancelled, orderActionSequence == action, store.session?.accessToken == token else { return }
            guard let response,
                  nativeTradeRecoveryMatches(response, digest: attempt.expectedOrderDigest)
                    || (attempt.expectedOrderDigest == nil && nativeTradeLegacyRecoveryMatches(response, quoteID: attempt.quoteID)) else {
                throw MobileAPIError.unavailable("原下单请求回执仍未确认，请稍后重试。")
            }
            guard NativeTradeRecoveryStore.clear(storageKey, expected: attempt) else {
                throw MobileAPIError.unavailable("恢复记录已变化或未能清理，请重新读取后核对。")
            }
            order = response; recoveryAttempt = nil
            onRecoveryResolved()
        } catch { if orderActionSequence == action && store.session?.accessToken == token { self.error = error.localizedDescription } }
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
