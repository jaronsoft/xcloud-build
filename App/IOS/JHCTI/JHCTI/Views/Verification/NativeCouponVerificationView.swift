import AVFoundation
import Foundation
import SwiftUI
import VisionKit

struct NativeCouponVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    @State private var merchants: [[String: Any]] = []
    @State private var stores: [[String: Any]] = []
    @State private var selectedMerchantId = ""
    @State private var selectedStoreId = ""
    @State private var code = ""
    @State private var preview: [String: Any]?
    @State private var records: [[String: Any]] = []
    @State private var recordPage = 1
    @State private var recordTotal = 0
    @State private var orderReference = ""
    @State private var actualAmount = ""
    @State private var eligibleAmount = ""
    @State private var actualProductIds: Set<String> = []
    @State private var reverseTarget: [String: Any]?
    @State private var reverseReason = ""
    @State private var loading = true
    @State private var previewing = false
    @State private var confirming = false
    @State private var reversing = false
    @State private var featureOpen = false
    @State private var error: String?
    @State private var scannerOpen = false
    @State private var scannerSessionToken = ""
    @State private var cameraAvailable = false
    @State private var showFeatureStatus = false
    @State private var confirmDialog = false
    @State private var revision = 0
    @State private var requestId: String?
    @State private var requestFingerprint = ""
    @State private var reverseRequestId: String?
    @State private var reverseRequestFingerprint = ""
    @State private var recordRequestSequence = 0
    @State private var previewRequestSequence = 0
    @State private var previewReadTask: Task<Void, Never>?
    @State private var merchantReadTask: Task<Void, Never>?
    @State private var merchantRequestSequence = 0
    @State private var recordReadTask: Task<Void, Never>?

    private var selectedStore: [String: Any]? { stores.first { ($0["Id"] as? String) == selectedStoreId } }
    private var canRedeem: Bool { selectedStore?["CanRedeem"] as? Bool == true }
    private var productRestricted: Bool { preview?["ProductRestricted"] as? Bool == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("仅处理平台消费券。核销权限、券状态和商户门店范围由服务端校验；扫码只读取券码，核对小票并确认后才会核销。")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    GroupBox("授权商户与门店") {
                        VStack(alignment: .leading, spacing: 9) {
                            if loading && merchants.isEmpty { ProgressView("正在读取授权…") }
                            if merchants.isEmpty && !loading {
                                Text(error ?? (featureOpen ? "当前账号没有消费券核销商户授权。" : "平台消费券核销功能暂未开放。"))
                                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(error == nil ? Brand.muted : .red)
                                Button("重新读取") { revision += 1 }
                                if !featureOpen { Button("查看开放状态") { showFeatureStatus = true } }
                            }
                            if !merchants.isEmpty {
                                Menu {
                                    ForEach(merchants.indices, id: \.self) { index in
                                        let item = merchants[index]
                                        Button(item["Name"] as? String ?? "商户") { startSelectingMerchant(item) }
                                    }
                                } label: { selectionLabel("商户", selected: merchants.first { $0["Id"] as? String == selectedMerchantId }?["Name"] as? String ?? "选择商户") }
                                    .disabled(loading || previewing || confirming || reversing)
                                if !stores.isEmpty {
                                    Menu {
                                        ForEach(stores.indices, id: \.self) { index in
                                            let item = stores[index]
                                            Button("\(item["Name"] as? String ?? "门店") · \(item["CanRedeem"] as? Bool == true ? "可核销" : "只读")") {
                                                selectStore(item)
                                            }
                                        }
                                    } label: { selectionLabel("门店", selected: stores.first { $0["Id"] as? String == selectedStoreId }?["Name"] as? String ?? "选择门店") }
                                    .disabled(loading || previewing || confirming || reversing)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if featureOpen && canRedeem {
                        GroupBox("验券与核销") {
                            VStack(alignment: .leading, spacing: 9) {
                                Button("扫描消费券二维码") { Task { await requestScannerAccess() } }
                                    .disabled(previewing || confirming)
                                    .frame(maxWidth: .infinity).padding(9)
                                    .background(Brand.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                if !cameraAvailable { Text("也可手工输入券码；首次扫码会请求相机权限。")
                                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted) }
                                TextField("消费券码（最多 128 字符）", text: $code)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .disabled(confirming)
                                    .onChange(of: code) { _, _ in clearPreview() }
                                Button(previewing ? "正在验券…" : "验券并预览") {
                                    previewReadTask?.cancel()
                                    previewReadTask = Task { await inspect() }
                                }
                                    .buttonStyle(.borderedProminent).tint(Brand.primary)
                                    .disabled(previewing || confirming || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                if let preview {
                                    Divider()
                                    Text(preview["CampaignName"] as? String ?? "平台消费券").font(.system(size: NativeTypography.size(16), weight: .semibold))
                                    Text("优惠 ¥\(money(preview["CouponAmount"]) ?? "—") · 最低消费 ¥\(money(preview["MinimumSpend"]) ?? "—")")
                                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                                    Text("有效期至 \(timeText(preview["ValidUntil"]))").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                                    TextField("小票 / POS 交易单号", text: $orderReference).disabled(confirming).onChange(of: orderReference) { _, _ in resetRequestKey() }
                                    TextField("本次交易金额", text: $actualAmount).keyboardType(.decimalPad).disabled(confirming).onChange(of: actualAmount) { _, _ in resetRequestKey() }
                                    if productRestricted {
                                        Text("选择本次交易中的适用商品").font(.system(size: NativeTypography.size(14), weight: .medium))
                                        ForEach((preview["EligibleProducts"] as? [[String: Any]] ?? []).indices, id: \.self) { index in
                                            let product = (preview["EligibleProducts"] as? [[String: Any]] ?? [])[index]
                                            let id = product["Id"] as? String ?? ""
                                            Toggle(product["Name"] as? String ?? "适用商品", isOn: Binding(
                                                get: { actualProductIds.contains(id) },
                                                set: { value in if value { actualProductIds.insert(id) } else { actualProductIds.remove(id) }; resetRequestKey() }))
                                                .disabled(confirming)
                                        }
                                        TextField("适用商品金额", text: $eligibleAmount).keyboardType(.decimalPad).disabled(confirming).onChange(of: eligibleAmount) { _, _ in resetRequestKey() }
                                    }
                                    Text("请按实际交易凭证填写金额。确认前不会使用消费券。")
                                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                    Button(confirming ? "正在核销…" : "确认核销") { confirmDialog = true }
                                        .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(confirming || !validConfirmation)
                                }
                                if let error { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red) }
                            }.textFieldStyle(.roundedBorder).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if selectedStore?["CanRead"] as? Bool == true {
                        GroupBox("核销记录") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text("共 \(recordTotal) 条").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted); Spacer()
                                    Button("刷新") { startLoadingRecords(page: 1) }.disabled(loading) }
                                if records.isEmpty && loading { ProgressView() }
                                if records.isEmpty && !loading { Text("暂无核销记录。") .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted) }
                                ForEach(records.indices, id: \.self) { index in recordCard(records[index]) }
                                if records.count < recordTotal {
                                    Button("加载更多") { startLoadingRecords(page: recordPage + 1, append: true) }.disabled(loading)
                                }
                                if selectedStore?["CanRead"] as? Bool == true, !records.isEmpty, let error {
                                    Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let target = reverseTarget {
                        GroupBox("撤销这笔核销") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("交易单号：\(target["OrderReference"] as? String ?? "—")。撤销原因会记入核销记录。")
                                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                                TextField("撤销原因（2 至 500 字）", text: $reverseReason, axis: .vertical).lineLimit(3...5).disabled(reversing)
                                if let error { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red) }
                                HStack {
                                    Button("取消") { reverseTarget = nil; reverseReason = "" }.disabled(reversing)
                                    Spacer()
                                    Button(reversing ? "正在撤销…" : "确认撤销", role: .destructive) { Task { await reverseRedemption() } }
                                        .disabled(reversing || reverseReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.padding(16)
            }
            .background(Brand.background)
            .navigationTitle("平台消费券核销").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .confirmationDialog("确认核销这张平台消费券？", isPresented: $confirmDialog, titleVisibility: .visible) {
                Button("确认核销", role: .destructive) { Task { await confirmRedemption() } }
                Button("再核对一下", role: .cancel) {}
            } message: {
                Text("交易单号：\(orderReference.trimmingCharacters(in: .whitespacesAndNewlines))；交易金额：¥\(actualAmount)；预计优惠金额：¥\(estimatedDiscountText)。确认后消费券将立即使用。")
            }
            .sheet(isPresented: $scannerOpen) {
                NativeActivityQrScanner(inputLabel: "消费券码", onCode: { value in
                    guard !scannerSessionToken.isEmpty,
                          store.session?.accessToken == scannerSessionToken else {
                        code = ""; clearPreview(); scannerOpen = false; scannerSessionToken = ""
                        error = "登录账号已变化，请重新读取授权后扫码。"
                        return
                    }
                    let scanned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !scanned.isEmpty && scanned.count <= 128 { code = scanned; clearPreview() }
                    else { code = ""; clearPreview(); error = "未读取到有效消费券码，请手工输入。" }
                    scannerOpen = false; scannerSessionToken = ""
                }, onFailure: { message in
                    if store.session?.accessToken != scannerSessionToken {
                        code = ""; clearPreview(); error = "登录账号已变化，请重新读取授权后扫码。"
                    } else { error = message }
                    cameraAvailable = false; scannerOpen = false; scannerSessionToken = ""
                })
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showFeatureStatus, onDismiss: { revision += 1 }) {
                NativeFeaturePendingView(store: store, featureId: "F-OPS-012")
            }
            .task(id: "\(store.session?.accessToken ?? "")-\(revision)") { await loadData() }
            .onChange(of: store.session?.accessToken) { _, _ in
                previewReadTask?.cancel(); previewReadTask = nil
                merchantReadTask?.cancel(); merchantReadTask = nil
                recordReadTask?.cancel(); recordReadTask = nil
                merchantRequestSequence += 1
                recordRequestSequence += 1; previewRequestSequence += 1
                merchants = []; stores = []; records = []; preview = nil; selectedMerchantId = ""; selectedStoreId = ""
                code = ""; orderReference = ""; actualAmount = ""; eligibleAmount = ""; actualProductIds = []; reverseTarget = nil; error = nil
                resetRequestKey(); reverseRequestId = nil; reverseRequestFingerprint = ""
                previewing = false; confirming = false; reversing = false; confirmDialog = false
                scannerOpen = false; scannerSessionToken = ""
            }
            .onDisappear {
                previewReadTask?.cancel(); previewReadTask = nil
                merchantReadTask?.cancel(); merchantReadTask = nil
                recordReadTask?.cancel(); recordReadTask = nil
                merchantRequestSequence += 1
                recordRequestSequence += 1; previewRequestSequence += 1; previewing = false
                code = ""; preview = nil; requestId = nil; scannerOpen = false; scannerSessionToken = ""
            }
        }
    }

    private var validConfirmation: Bool {
        guard let preview,
              decimal(preview["CouponAmount"]).map({ $0 > 0 }) == true,
              let minimum = decimal(preview["MinimumSpend"]),
              validMoneyText(actualAmount),
              let actual = Decimal(string: actualAmount.trimmingCharacters(in: .whitespacesAndNewlines)), actual > 0,
              actual <= Decimal(string: "999999999999.99")!,
              !orderReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              orderReference.trimmingCharacters(in: .whitespacesAndNewlines).count <= 120 else { return false }
        if productRestricted {
            guard validMoneyText(eligibleAmount),
                  let eligible = Decimal(string: eligibleAmount.trimmingCharacters(in: .whitespacesAndNewlines)),
                  eligible > 0, eligible <= actual, eligible >= minimum,
                  !actualProductIds.isEmpty else { return false }
            let ids = Set((preview["EligibleProducts"] as? [[String: Any]] ?? []).compactMap { $0["Id"] as? String })
            return actualProductIds.isSubset(of: ids)
        }
        return true
    }

    private var estimatedDiscountText: String {
        guard let coupon = decimal(preview?["CouponAmount"]),
              let base = decimal(productRestricted ? eligibleAmount : actualAmount) else { return "—" }
        return NSDecimalNumber(decimal: min(coupon, base)).stringValue
    }

    private func selectionLabel(_ title: String, selected: String) -> some View {
        HStack { Text(title).foregroundStyle(Brand.muted); Spacer(); Text(selected).foregroundStyle(Brand.ink); Image(systemName: "chevron.down").foregroundStyle(Brand.muted) }
            .font(.system(size: NativeTypography.size(14))).padding(10).background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private func recordCard(_ row: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text("交易单号 \(row["OrderReference"] as? String ?? "—")").font(.system(size: NativeTypography.size(14), weight: .medium)); Spacer()
                Text(row["Status"] as? String == "Redeemed" ? "已核销" : "已撤销").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.primary) }
            Text("交易 ¥\(money(row["ActualAmount"]) ?? "—") · 优惠 ¥\(money(row["DiscountAmount"]) ?? "—")")
                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
            Text(timeText(row["RedeemedAt"])).font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            if row["Status"] as? String == "Reversed" {
                Text("撤销：\(row["ReversalReason"] as? String ?? "—") · \(timeText(row["ReversedAt"]))")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            } else if row["CanReverse"] as? Bool == true && selectedStore?["CanReverse"] as? Bool == true {
                Button("撤销核销") { reverseTarget = row; reverseReason = ""; reverseRequestId = nil; reverseRequestFingerprint = "" }
                    .font(.system(size: NativeTypography.size(14), weight: .medium)).foregroundStyle(.red)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
    }

    @MainActor private func loadData() async {
        merchantReadTask?.cancel(); merchantReadTask = nil
        recordReadTask?.cancel(); recordReadTask = nil
        merchantRequestSequence += 1; recordRequestSequence += 1
        guard let token = store.session?.accessToken, !token.isEmpty else {
            loading = false; error = "请使用已获授权的文旅工作人员账号登录。"; return
        }
        loading = true; error = nil
        do {
            guard let status = try await MobileAPI(store: store).get("/api/JHCTIFeatureAccess/GetPublicStatus?featureId=F-OPS-012") as? [String: Any],
                  let enabled = status["IsEnabled"] as? Bool, store.session?.accessToken == token else {
                throw MobileAPIError.unavailable("平台消费券核销开放状态暂不可确认，请重试。")
            }
            featureOpen = enabled
            guard enabled else { merchants = []; stores = []; records = []; loading = false; return }
            guard let page = try await MobileAPI(store: store).get("/api/JHCTICouponClaim/GetRedemptionMerchantOptions?page=1&pageSize=100", authenticated: true) as? [String: Any],
                  let rows = (page["data"] ?? page["Data"]) as? [[String: Any]],
                  store.session?.accessToken == token else { throw MobileAPIError.unavailable("核销商户回执无效，请重试。") }
            guard rows.allSatisfy({ validId($0["Id"]) && (($0["Name"] as? String)?.isEmpty == false) }) else {
                throw MobileAPIError.unavailable("核销商户信息不完整，请刷新重试。")
            }
            merchants = rows
            let selected = rows.first { $0["Id"] as? String == selectedMerchantId } ?? rows.first
            if let selected { await selectMerchant(selected) }
            else { stores = []; records = []; error = "当前账号没有可读取或核销的平台消费券商户授权。" }
        } catch {
            guard !Task.isCancelled else { return }
            if store.session?.accessToken == token { self.error = error.localizedDescription }
        }
        if store.session?.accessToken == token { loading = false }
    }

    @MainActor private func startSelectingMerchant(_ merchant: [String: Any]) {
        merchantReadTask?.cancel()
        merchantRequestSequence += 1
        let sequence = merchantRequestSequence
        merchantReadTask = Task {
            await selectMerchant(merchant)
            if merchantRequestSequence == sequence { merchantReadTask = nil }
        }
    }

    @MainActor private func selectMerchant(_ merchant: [String: Any]) async {
        guard let token = store.session?.accessToken, let merchantId = merchant["Id"] as? String else { return }
        recordReadTask?.cancel(); recordReadTask = nil
        previewReadTask?.cancel(); previewReadTask = nil
        recordRequestSequence += 1; previewRequestSequence += 1; previewing = false
        selectedMerchantId = merchantId; selectedStoreId = ""; stores = []; records = []; preview = nil; error = nil
        do {
            guard let rows = try await MobileAPI(store: store).get("/api/JHCTICouponClaim/GetRedemptionStoreOptions?merchantId=\(merchantId)", authenticated: true) as? [[String: Any]],
                  store.session?.accessToken == token, selectedMerchantId == merchantId,
                  rows.allSatisfy({ validId($0["Id"]) && $0["MerchantId"] as? String == merchantId
                    && $0["IsEnabled"] as? Bool != nil && $0["CanRead"] as? Bool != nil
                    && $0["CanRedeem"] as? Bool != nil && $0["CanReverse"] as? Bool != nil }) else {
                throw MobileAPIError.unavailable("核销门店回执无效，请重试。")
            }
            stores = rows.filter { $0["IsEnabled"] as? Bool == true && ($0["CanRead"] as? Bool == true || $0["CanRedeem"] as? Bool == true) }
            if let storeRow = stores.first(where: { $0["CanRedeem"] as? Bool == true }) ?? stores.first { selectStore(storeRow) }
            else { loading = false }
        } catch {
            guard !Task.isCancelled else { return }
            if store.session?.accessToken == token, selectedMerchantId == merchantId { self.error = error.localizedDescription }
        }
    }

    @MainActor private func selectStore(_ row: [String: Any]) {
        recordReadTask?.cancel(); recordReadTask = nil
        previewReadTask?.cancel(); previewReadTask = nil
        recordRequestSequence += 1; previewRequestSequence += 1; previewing = false
        loading = false
        selectedStoreId = row["Id"] as? String ?? ""; preview = nil; code = ""; records = []; recordPage = 1; recordTotal = 0
        resetRequestKey(); error = nil
        if row["CanRead"] as? Bool == true { startLoadingRecords(page: 1) }
    }

    @MainActor private func inspect() async {
        guard let token = store.session?.accessToken, canRedeem else { error = "请选择具有核销权限的商户门店。"; return }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 128 else { error = "请输入有效消费券码（最多 128 字符）。"; return }
        previewRequestSequence += 1
        let requestSequence = previewRequestSequence
        let merchantId = selectedMerchantId
        let storeId = selectedStoreId
        previewing = true; preview = nil; error = nil
        defer {
            if store.session?.accessToken == token, previewRequestSequence == requestSequence { previewing = false }
            if previewRequestSequence == requestSequence { previewReadTask = nil }
        }
        do {
            let value = try await MobileAPI(store: store).post("/api/JHCTICouponClaim/PreviewRedemption",
                body: ["CouponCode": normalized, "MerchantId": merchantId, "StoreId": storeId], authenticated: true)
            guard store.session?.accessToken == token, previewRequestSequence == requestSequence,
                  selectedMerchantId == merchantId, selectedStoreId == storeId,
                  code.trimmingCharacters(in: .whitespacesAndNewlines) == normalized,
                  let result = value as? [String: Any],
                  !(result["PreviewToken"] as? String ?? "").isEmpty,
                  (result["CampaignName"] as? String)?.isEmpty == false,
                  decimal(result["CouponAmount"]).map({ $0 > 0 }) == true,
                  decimal(result["MinimumSpend"]) != nil,
                  result["ProductRestricted"] as? Bool != true || (result["EligibleProducts"] as? [[String: Any]])?.allSatisfy({
                    validId($0["Id"]) && ($0["Name"] as? String)?.isEmpty == false
                  }) == true else {
                throw MobileAPIError.unavailable("验券回执信息不完整，请重新验券。")
            }
            preview = result; orderReference = ""; actualAmount = ""; eligibleAmount = ""; actualProductIds = []
            resetRequestKey()
        } catch {
            guard !Task.isCancelled else { return }
            if store.session?.accessToken == token, previewRequestSequence == requestSequence,
                selectedMerchantId == merchantId, selectedStoreId == storeId { self.error = error.localizedDescription }
        }
    }

    @MainActor private func confirmRedemption() async {
        guard let preview, canRedeem, validConfirmation, let token = store.session?.accessToken else { return }
        let normalizedOrder = orderReference.trimmingCharacters(in: .whitespacesAndNewlines)
        let actual = Decimal(string: actualAmount.trimmingCharacters(in: .whitespacesAndNewlines))!
        let merchantId = selectedMerchantId
        let storeId = selectedStoreId
        let couponAmount = decimal(preview["CouponAmount"])!
        let eligible = Decimal(string: eligibleAmount.trimmingCharacters(in: .whitespacesAndNewlines))
        let eligibleForDiscount = productRestricted ? eligible! : actual
        let payload: [String: Any] = ["PreviewToken": preview["PreviewToken"] ?? "", "MerchantId": merchantId,
            "StoreId": storeId, "OrderReference": normalizedOrder, "ActualAmount": NSDecimalNumber(decimal: actual),
            "EligibleAmount": productRestricted ? NSDecimalNumber(string: eligibleAmount) : NSNull(),
            "ActualProductIds": productRestricted ? Array(actualProductIds) : []]
        let fingerprint = "\(preview["PreviewToken"] ?? "")|\(merchantId)|\(storeId)|\(normalizedOrder)|\(actualAmount)|\(eligibleAmount)|\(actualProductIds.sorted().joined(separator: ","))"
        if requestFingerprint != fingerprint { requestFingerprint = fingerprint; requestId = UUID().uuidString }
        confirming = true; error = nil
        defer { if store.session?.accessToken == token { confirming = false } }
        do {
            let result = try await MobileAPI(store: store).post("/api/JHCTICouponClaim/ConfirmRedemption",
                body: payload.merging(["RequestId": requestId ?? UUID().uuidString]) { _, new in new }, authenticated: true) as? [String: Any]
            guard store.session?.accessToken == token, let result,
                  validId(result["Id"]), validId(result["CouponClaimId"]),
                  result["CampaignType"] as? String == "Platform", result["Status"] as? String == "Redeemed",
                  result["MerchantId"] as? String == merchantId,
                  result["StoreId"] as? String == storeId,
                  result["OrderReference"] as? String == normalizedOrder,
                  decimal(result["ActualAmount"]) == actual,
                  decimal(result["EligibleAmount"]) == eligibleForDiscount,
                  decimal(result["DiscountAmount"]).map({ $0 > 0 && $0 <= min(couponAmount, eligibleForDiscount) }) == true else {
                throw MobileAPIError.unavailable("核销回执无法确认；请刷新记录核对后再操作。")
            }
            self.preview = nil; code = ""; orderReference = ""; actualAmount = ""; eligibleAmount = ""; actualProductIds = []
            resetRequestKey(); error = "核销成功，优惠 ¥\(money(result["DiscountAmount"]) ?? "—")。"
            if selectedStore?["CanRead"] as? Bool == true { startLoadingRecords(page: 1) }
        } catch {
            guard !Task.isCancelled else { return }
            if store.session?.accessToken == token { self.error = error.localizedDescription }
        }
    }

    @MainActor private func startLoadingRecords(page: Int, append: Bool = false) {
        recordReadTask?.cancel()
        recordReadTask = Task {
            await loadRecords(page: page, append: append)
        }
    }

    @MainActor private func loadRecords(page: Int, append: Bool = false) async {
        guard let token = store.session?.accessToken, validId(selectedMerchantId), validId(selectedStoreId) else { return }
        recordRequestSequence += 1
        let requestSequence = recordRequestSequence
        let merchantId = selectedMerchantId
        let storeId = selectedStoreId
        loading = true
        defer { if store.session?.accessToken == token, recordRequestSequence == requestSequence { loading = false } }
        do {
            guard let value = try await MobileAPI(store: store).get("/api/JHCTICouponClaim/GetRedemptions?merchantId=\(merchantId)&storeId=\(storeId)&page=\(page)&pageSize=20", authenticated: true) as? [String: Any],
                  let rows = (value["data"] ?? value["Data"]) as? [[String: Any]],
                  let total = (value["dataCount"] ?? value["DataCount"]) as? Int,
                  (value["Page"] ?? value["page"]) as? Int == page,
                  (value["PageSize"] ?? value["pageSize"]) as? Int == 20,
                  let expectedRows = nativeReportExpectedRows(page: page, total: total, pageSize: 20),
                  rows.count == expectedRows,
                  (!append || (total == recordTotal && Int64(records.count) == (Int64(page) - 1) * 20)),
                  store.session?.accessToken == token, recordRequestSequence == requestSequence,
                  selectedMerchantId == merchantId, selectedStoreId == storeId,
                  rows.allSatisfy({ validId($0["Id"]) && validId($0["CouponClaimId"])
                    && $0["MerchantId"] as? String == merchantId && $0["StoreId"] as? String == storeId
                    && $0["CampaignType"] as? String == "Platform" && ["Redeemed", "Reversed"].contains($0["Status"] as? String ?? "")
                    && decimal($0["ActualAmount"]).map({ $0 > 0 }) == true && decimal($0["DiscountAmount"]) != nil }) else {
                throw MobileAPIError.unavailable("核销记录回执异常，请刷新重试。")
            }
            records = append ? records + rows : rows; recordPage = page; recordTotal = total
        } catch {
            guard !Task.isCancelled else { return }
            if store.session?.accessToken == token, recordRequestSequence == requestSequence,
                selectedMerchantId == merchantId, selectedStoreId == storeId { self.error = error.localizedDescription }
        }
    }

    @MainActor private func reverseRedemption() async {
        guard let row = reverseTarget, row["CanReverse"] as? Bool == true, selectedStore?["CanReverse"] as? Bool == true,
              row["Status"] as? String == "Redeemed", let token = store.session?.accessToken else { return }
        let reason = reverseReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...500).contains(reason.count), let id = row["Id"] as? String else { error = "撤销原因须为 2 至 500 个字符。"; return }
        let merchantId = selectedMerchantId
        let storeId = selectedStoreId
        let expectedClaimId = row["CouponClaimId"] as? String ?? ""
        let expectedOrder = row["OrderReference"] as? String ?? ""
        let expectedAmount = decimal(row["ActualAmount"])
        let expectedDiscount = decimal(row["DiscountAmount"])
        let fingerprint = "\(id)|\(merchantId)|\(storeId)|\(reason)"
        if reverseRequestFingerprint != fingerprint {
            reverseRequestFingerprint = fingerprint
            reverseRequestId = UUID().uuidString
        }
        reversing = true; error = nil
        defer { if store.session?.accessToken == token { reversing = false } }
        do {
            let value = try await MobileAPI(store: store).post("/api/JHCTICouponClaim/ReverseRedemption", body: [
                "RedemptionId": id, "MerchantId": merchantId, "StoreId": storeId,
                "Reason": reason, "RequestId": reverseRequestId ?? UUID().uuidString], authenticated: true) as? [String: Any]
            guard store.session?.accessToken == token, let value,
                  value["Id"] as? String == id, value["CouponClaimId"] as? String == expectedClaimId,
                  value["CampaignType"] as? String == "Platform", value["Status"] as? String == "Reversed",
                  value["MerchantId"] as? String == merchantId, value["StoreId"] as? String == storeId,
                  value["OrderReference"] as? String == expectedOrder,
                  decimal(value["ActualAmount"]) == expectedAmount,
                  decimal(value["DiscountAmount"]) == expectedDiscount else {
                throw MobileAPIError.unavailable("撤销回执无法确认，请刷新记录核对。")
            }
            reverseTarget = nil; reverseReason = ""; reverseRequestId = nil; reverseRequestFingerprint = ""; startLoadingRecords(page: 1)
        } catch { if store.session?.accessToken == token { self.error = error.localizedDescription } }
    }

    @MainActor private func requestScannerAccess() async {
        guard let token = store.session?.accessToken, !token.isEmpty else { error = "请使用已获授权的文旅工作人员账号登录。"; return }
        guard DataScannerViewController.isSupported else { error = "当前设备不支持扫码，请手工输入券码。"; return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted = status == .authorized ? true : status == .notDetermined ? await AVCaptureDevice.requestAccess(for: .video) : false
        guard store.session?.accessToken == token else {
            scannerOpen = false; scannerSessionToken = ""; code = ""; clearPreview()
            error = "登录账号已变化，请重新读取授权后扫码。"; return
        }
        cameraAvailable = granted && DataScannerViewController.isAvailable
        scannerSessionToken = cameraAvailable ? token : ""
        if cameraAvailable { scannerOpen = true } else { error = "相机权限未开启或设备不可用，请手工输入券码。" }
    }

    private func clearPreview() {
        previewReadTask?.cancel(); previewReadTask = nil
        previewRequestSequence += 1; previewing = false; preview = nil; orderReference = ""; actualAmount = ""; eligibleAmount = ""; actualProductIds = []; resetRequestKey()
    }
    private func resetRequestKey() { requestId = nil; requestFingerprint = "" }
    private func validId(_ value: Any?) -> Bool { (value as? String).flatMap(Int64.init).map { $0 > 0 } == true }
    private func decimal(_ value: Any?) -> Decimal? {
        guard let value else { return nil }
        if let string = value as? String { return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) }
        if let number = value as? NSNumber { return number.decimalValue }
        return nil
    }
    private func validMoneyText(_ text: String) -> Bool {
        text.range(of: "^[0-9]{1,12}(?:\\.[0-9]{1,2})?$", options: .regularExpression) != nil
    }
    private func money(_ value: Any?) -> String? { decimal(value).map { NSDecimalNumber(decimal: $0).stringValue } }
    private func timeText(_ value: Any?) -> String { (value as? String ?? "—").replacingOccurrences(of: "T", with: " ").prefix(16).description }
}
