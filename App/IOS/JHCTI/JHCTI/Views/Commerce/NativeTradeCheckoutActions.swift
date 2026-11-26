import SwiftUI

extension NativeTradeCheckoutView {
    @MainActor func loadPointsSummary() async {
        let requestRevision = pointsSummaryRevision
        guard let token = store.session?.accessToken else {
            pointsBalance = nil; pointsDebt = nil; pointsSummaryError = false; pointsToUse = "0"
            return
        }
        do {
            guard let summary = try await MobileAPI(store: store).get(
                "/api/JHCTIMemberProgram/GetMySummary", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any],
                  let balanceText = nativeMemberPointSummaryString(summary, "PointsBalance"),
                  let balance = Int64(balanceText), balance >= 0,
                  let debtText = nativeMemberPointSummaryString(summary, "PointsDebt"),
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

    func quoteInputStamp() -> String? {
        let value: [String: Any] = ["CartItemIds": cartIDs, "AddressId": hasPhysicalItems ? selectedAddressID : "0",
            "RegionCode": hasPhysicalItems ? (selectedAddress?["RegionCode"] as? String ?? "") : "DIGITAL",
            "Stores": selectedStoreIDs, "Coupon": selectedCouponID, "Points": pointsToUse]
        return (try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys))?.base64EncodedString()
    }

    func invalidateQuote() {
        quoteSequence += 1; quote = nil; quoteRequestStamp = nil; idempotencyKey = UUID().uuidString
    }

    func beginAddressCreate() {
        editingAddressID = ""; recipient = ""; phone = ""; detailAddress = ""
        selectedRegionCode = regions.first?["RegionCode"] as? String ?? ""
        addressCreateRequestID = UUID().uuidString; addAddress = true; error = nil
    }

    func beginAddressEdit(_ address: [String: Any]) {
        guard let id = validID(address["Id"]) else { error = "地址编号无效，请重新读取结算信息。"; return }
        editingAddressID = id
        recipient = address["RecipientName"] as? String ?? ""
        phone = address["PhoneNumber"] as? String ?? ""
        detailAddress = address["DetailAddress"] as? String ?? ""
        selectedRegionCode = address["RegionCode"] as? String ?? ""
        addAddress = true; error = nil
    }

    func clearAddressEditor() {
        editingAddressID = ""; recipient = ""; phone = ""; detailAddress = ""
        selectedRegionCode = ""; addAddress = false
    }

    @MainActor func load() async {
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

    @MainActor func saveAddress() async {
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

    @MainActor func deleteAddress(id: String) async {
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

    @MainActor func requestQuote() async {
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

    func pointsValidationError(_ points: Int64) -> String? {
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

    @MainActor func createOrder() async {
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

    @MainActor func retryOrder(_ attempt: NativeTradeOrderAttempt) async {
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
