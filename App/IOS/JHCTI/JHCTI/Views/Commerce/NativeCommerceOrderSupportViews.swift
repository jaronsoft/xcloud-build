import SwiftUI
import PhotosUI
import UIKit

struct NativeBuyerAfterSaleView: View {
    @ObservedObject var store: SessionStore
    let order: [String: Any]
    @State private var cases: [[String: Any]] = []
    @State private var selectedCase: [String: Any]?
    @State private var draftItem: [String: Any]?
    @State private var requestType = "RefundOnly"
    @State private var quantity = 1
    @State private var reason = "商品质量问题"
    @State private var description = ""
    @State private var evidenceUrls: [String] = []
    @State private var photos: [PhotosPickerItem] = []
    @State private var message = ""
    @State private var carrier = ""
    @State private var trackingNumber = ""
    @State private var loading = false
    @State private var busy = false
    @State private var error: String?
    @State private var needsVerification = false
    @State private var verificationNoMatch = false
    @State private var requestAttemptStored = false
    @State private var retryAuthorized = false
    @State private var uncertainCaseID = ""
    @State private var uncertainReadbackVerified = false
    @State private var sequence = 0
    @State private var caseReadSequence = 0
    @State private var caseReadTask: Task<Void, Never>?

    private let reasons = ["商品质量问题", "商品错发/漏发", "物流问题", "不想要了", "其他"]
    private let activeStatuses: Set<String> = ["PendingReview", "Negotiating", "ReturnRequired", "ReturnInTransit", "ReturnReceived", "ApprovedForRefund", "RefundProcessing"]

    private var orderId: String { order["Id"] as? String ?? "" }
    private var principal: String? { nativeTourismPrincipal(store.session?.accessToken) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("我的售后").font(.system(size: NativeTypography.size(14), weight: .semibold))
            if loading && cases.isEmpty { ProgressView("正在读取售后记录…") }
            if let error { Text(error).font(.system(size: NativeTypography.size(12))).foregroundStyle(.red) }
            ForEach(cases.indices, id: \.self) { index in
                caseCard(cases[index])
            }
            if cases.isEmpty && !loading && error == nil { Text("暂无售后申请").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted) }
            if let draftItem {
                let draftProductName = draftItem["ProductName"] as? String ?? "商品"
                let draftQuantity = draftItem["Quantity"] as? Int ?? 1
                VStack(alignment: .leading, spacing: 8) {
                    Text("申请售后 · \(draftProductName)").font(.system(size: NativeTypography.size(13), weight: .semibold))
                    Picker("申请方式", selection: $requestType) {
                        Text("仅退款").tag("RefundOnly")
                        if draftItem["DeliveryType"] as? String == "Physical" { Text("退货退款").tag("ReturnAndRefund") }
                    }.pickerStyle(.segmented).disabled(busy || requestAttemptStored)
                    Stepper("申请数量：\(quantity) / \(draftQuantity)", value: $quantity, in: 1...max(1, draftQuantity)).disabled(busy || requestAttemptStored)
                    Picker("售后原因", selection: $reason) { ForEach(reasons, id: \.self) { Text($0).tag($0) } }.disabled(busy || requestAttemptStored)
                    TextField("补充说明（选填，最多 2000 字）", text: $description, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder).disabled(busy || requestAttemptStored)
                    let evidenceCount = evidenceUrls.count
                    PhotosPicker(selection: $photos, maxSelectionCount: max(1, 8 - evidenceCount), matching: .images) {
                        Text("添加凭证（\(evidenceCount)/8）")
                    }.disabled(busy || requestAttemptStored || evidenceCount >= 8)
                    ForEach(evidenceUrls.indices, id: \.self) { index in
                        let imageNumber = index + 1
                        Text("已添加售后凭证图片 \(imageNumber)")
                            .font(.system(size: NativeTypography.size(11)))
                    }
                    if needsVerification {
                        Text(verificationNoMatch
                             ? "已完整读取本人售后记录，暂未找到该商品申请。请确认申请确实未提交后，再解除保护。"
                             : "提交结果待核对。请先读取完整的本人售后记录；核对前不会重复提交。")
                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(.orange)
                        Button("重新核对申请状态") { Task { await loadCases() } }.disabled(loading || busy)
                        if verificationNoMatch {
                            Button(requestAttemptStored ? "确认无申请，沿用原内容安全重试" : "我已确认不存在该申请，解除保护") {
                                guard requestAttemptStored, let token = store.session?.accessToken,
                                      let draftId = draftItem["Id"] as? String else {
                                    needsVerification = false; verificationNoMatch = false; error = nil
                                    return
                                }
                                let storageKey = nativeBuyerAfterSaleAttemptStorageKey(accessToken: token, orderID: orderId, itemID: draftId)
                                guard let saved = store.afterSaleRequestAttempt(for: storageKey),
                                      let attempt = decodeNativeBuyerAfterSaleAttempt(saved),
                                      let updated = encodeNativeBuyerAfterSaleAttempt(attempt, retryAuthorized: true),
                                      store.updateAfterSaleRequestAttempt(updated, replacing: saved, for: storageKey) else {
                                    error = "无法保存安全重试确认，原申请仍受保护。"
                                    return
                                }
                                retryAuthorized = true; needsVerification = false; verificationNoMatch = false; error = nil
                            }.disabled(loading || busy)
                        }
                    }
                    HStack {
                        Button("取消", role: .cancel) { cancelDraft() }.disabled(busy || requestAttemptStored)
                        Spacer()
                        Button(busy ? "正在提交…" : retryAuthorized ? "沿用原申请编号重试" : needsVerification ? "核对后再提交" : "提交申请") { Task { try? await submit() } }
                            .disabled(busy || loading || needsVerification || error != nil)
                    }
                }.padding(10).background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
            } else if cases.allSatisfy({ !activeStatuses.contains($0["Status"] as? String ?? "") }) {
                ForEach((order["Items"] as? [[String: Any]] ?? []).indices, id: \.self) { index in
                    let item = (order["Items"] as? [[String: Any]] ?? [])[index]
                    let itemId = item["Id"] as? String ?? ""
                    let hasActive = cases.contains { record in
                        activeStatuses.contains(record["Status"] as? String ?? "")
                            && ((record["Items"] as? [[String: Any]] ?? []).contains { $0["OrderItemId"] as? String == itemId })
                    }
                    if !hasActive && !itemId.isEmpty {
                        Button("为\(item["ProductName"] as? String ?? "商品")申请售后") {
                            draftItem = item; quantity = 1; reason = reasons[0]; description = ""
                            requestType = "RefundOnly"; evidenceUrls = []; needsVerification = false; verificationNoMatch = false
                            requestAttemptStored = false; retryAuthorized = false; error = nil
                        }.font(.system(size: NativeTypography.size(12), weight: .semibold)).disabled(loading || busy || needsVerification || error != nil)
                    }
                }
            }
            Button("刷新售后记录") { Task { await loadCases() } }.font(.system(size: NativeTypography.size(12))).disabled(loading || busy)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 11))
            .task(id: "\(principal ?? "")-\(orderId)") { restoreUncertainAction(); await loadCases() }
            .onChange(of: principal) { _, _ in
                cases = []; selectedCase = nil; draftItem = nil; evidenceUrls = []; message = ""
                loading = false; busy = false; needsVerification = false; verificationNoMatch = false; requestAttemptStored = false; retryAuthorized = false; uncertainCaseID = ""; uncertainReadbackVerified = false; error = nil; sequence += 1; caseReadSequence += 1
                caseReadTask?.cancel(); caseReadTask = nil
            }
            .onChange(of: photos) { _, selected in if !selected.isEmpty { Task { try? await upload(selected) } } }
            .onDisappear {
                sequence += 1
                loading = false
                caseReadSequence += 1
                caseReadTask?.cancel(); caseReadTask = nil
            }
    }

    private func toggleCaseDetails(id: String) {
        if selectedCase?["Id"] as? String == id {
            caseReadSequence += 1
            caseReadTask?.cancel()
            caseReadTask = nil
            loading = false
            selectedCase = nil
        } else {
            caseReadTask?.cancel()
            caseReadTask = Task { await loadCase(id: id) }
        }
    }

    @ViewBuilder private func caseCard(_ item: [String: Any]) -> some View {
        let id = item["Id"] as? String ?? ""
        let isSelected = selectedCase?["Id"] as? String == id
        let title = isSelected ? "收起" : "查看进度"
        let caseNumber = item["CaseNo"] as? String ?? "售后申请"
        let caseStatus = item["Status"] as? String ?? ""
        let heading = caseNumber + " · " + afterSaleStatus(caseStatus)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(heading).font(.system(size: NativeTypography.size(12), weight: .semibold))
                Spacer()
                Button(title) { toggleCaseDetails(id: id) }
                    .font(.system(size: NativeTypography.size(12)))
            }
            if isSelected {
                let details = selectedCase ?? item
                let status = details["Status"] as? String ?? ""
                let messages = details["Messages"] as? [[String: Any]] ?? []
                Text(details["Description"] as? String ?? "未填写补充说明")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                if let decision = details["DecisionReason"] as? String, !decision.isEmpty {
                    Text("处理说明：" + decision).font(.system(size: NativeTypography.size(12)))
                }
                ForEach(messages.indices, id: \.self) { index in
                    let entry = messages[index]
                    let sender = entry["SenderType"] as? String == "Customer" ? "我" : "商户/客服"
                    let text = sender + "：" + (entry["Content"] as? String ?? "")
                    Text(text).font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.ink)
                }
                if uncertainCaseID == id {
                    Text("上次操作结果未知。为防止重复留言或物流提交，售后写操作已锁定；请重新读取详情，核对无误后再手动解除保护。")
                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(.orange)
                    Button("重新读取最新详情") { Task { await loadCase(id: id, refresh: true) } }
                        .disabled(busy || loading)
                    Button("已核对且确认未生效，解除保护") {
                        guard let token = store.session?.accessToken else { return }
                        UserDefaults.standard.removeObject(forKey: nativeBuyerAfterSaleLockStorageKey(accessToken: token, orderID: orderId))
                        uncertainCaseID = ""; uncertainReadbackVerified = false
                        error = "重复提交保护已解除；请确认内容后手动重试。"
                    }.disabled(busy || loading || !uncertainReadbackVerified)
                }
                if activeStatuses.contains(status) {
                    TextField("补充留言", text: $message, axis: .vertical).textFieldStyle(.roundedBorder)
                    Button("发送留言") { Task { try? await sendMessage(id: id) } }
                        .disabled(busy || !uncertainCaseID.isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if status == "ReturnRequired" {
                        TextField("退货承运方", text: $carrier).textFieldStyle(.roundedBorder)
                        TextField("退货物流单号", text: $trackingNumber).textFieldStyle(.roundedBorder)
                        Button("提交退货物流") { Task { try? await submitReturn(id: id) } }
                            .disabled(busy || !uncertainCaseID.isEmpty || carrier.isEmpty || trackingNumber.isEmpty)
                    }
                    Button("撤回售后申请", role: .destructive) { Task { try? await closeCase(id: id) } }
                        .disabled(busy || !uncertainCaseID.isEmpty)
                }
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private func loadCases() async {
        sequence += 1; let current = sequence
        guard let token = store.session?.accessToken, let requested = nativeTourismPrincipal(token), !orderId.isEmpty else {
            cases = []; loading = false; error = "请登录后查看售后记录。"; return
        }
        if needsVerification { verificationNoMatch = false }
        loading = true; error = nil
        do {
            let pageSize = 100
            var values: [[String: Any]] = []
            var seenIDs = Set<String>()
            var expectedTotal: Int?
            var page = 1
            repeat {
                guard page <= 100 else { throw MobileAPIError.unavailable("售后记录过多，无法完成完整核对；请联系平台处理") }
                guard let response = try await MobileAPI(store: store).get("/api/JHCTITradeAfterSale/GetMyPage?page=\(page)&pageSize=\(pageSize)", authenticated: true, expectedPrincipal: requested) as? [String: Any],
                      nativeTourismPrincipal(store.session?.accessToken) == requested, sequence == current else { return }
                guard let pageRows = response["data"] as? [[String: Any]] ?? response["Data"] as? [[String: Any]]
                    ?? response["items"] as? [[String: Any]] ?? response["Items"] as? [[String: Any]],
                      pageRows.count <= pageSize else {
                    throw MobileAPIError.unavailable("售后记录分页格式异常，请重新读取")
                }
                let rawTotal = response["dataCount"] ?? response["DataCount"] ?? response["total"] ?? response["Total"]
                let total = (rawTotal as? Int) ?? (rawTotal as? String).flatMap(Int.init)
                guard let total, total >= pageRows.count, total >= 0,
                      expectedTotal == nil || expectedTotal == total else {
                    throw MobileAPIError.unavailable("售后记录分页总数无效或读取期间发生变化")
                }
                expectedTotal = total
                for row in pageRows {
                    let id = row["Id"] as? String ?? ""
                    let rowOrderId = row["OrderId"] as? String ?? ""
                    let merchantOrderId = row["MerchantOrderId"] as? String ?? ""
                    let status = row["Status"] as? String ?? ""
                    let type = row["RequestType"] as? String ?? ""
                    guard Int64(id).map({ $0 > 0 }) == true && Int64(rowOrderId).map({ $0 > 0 }) == true
                        && Int64(merchantOrderId).map({ $0 > 0 }) == true && !status.isEmpty
                        && ["RefundOnly", "ReturnAndRefund"].contains(type), seenIDs.insert(id).inserted else {
                        throw MobileAPIError.unavailable("售后记录编号异常或分页重复，请重新读取")
                    }
                    values.append(row)
                }
                guard values.count <= total, values.count == total || pageRows.count == pageSize else {
                    throw MobileAPIError.unavailable("售后记录未完整返回，请重新读取")
                }
                page += 1
            } while values.count < (expectedTotal ?? 0)
            guard values.count == expectedTotal, seenIDs.count == expectedTotal else {
                throw MobileAPIError.unavailable("售后记录未完整读取，请重新核对")
            }
            let matchingCases = values.filter { $0["OrderId"] as? String == orderId }
            cases = matchingCases
            if needsVerification, let draftId = draftItem?["Id"] as? String {
                var matchedDraft = false
                for candidate in matchingCases {
                    let caseId = candidate["Id"] as? String ?? ""
                    guard let detail = try await MobileAPI(store: store).get("/api/JHCTITradeAfterSale/GetMyCase?id=\(caseId)", authenticated: true, expectedPrincipal: requested) as? [String: Any],
                          nativeTourismPrincipal(store.session?.accessToken) == requested, sequence == current,
                          detail["Id"] as? String == caseId, detail["OrderId"] as? String == orderId else {
                        throw MobileAPIError.unavailable("售后详情无法核对，请稍后重试；不会自动重新提交")
                    }
                    guard let detailItems = detail["Items"] as? [[String: Any]] else {
                        throw MobileAPIError.unavailable("售后详情商品列表不完整，申请结果仍待核对")
                    }
                    if detailItems.contains(where: { $0["OrderItemId"] as? String == draftId }) {
                        let storageKey = nativeBuyerAfterSaleAttemptStorageKey(accessToken: token, orderID: orderId, itemID: draftId)
                        if let saved = store.afterSaleRequestAttempt(for: storageKey) {
                            store.clearAfterSaleRequestAttempt(saved, for: storageKey)
                        }
                        requestAttemptStored = false; retryAuthorized = false
                        draftItem = nil; evidenceUrls = []; selectedCase = detail
                        matchedDraft = true
                        break
                    }
                }
                verificationNoMatch = !matchedDraft
                if matchedDraft { needsVerification = false }
            }
            if let selectedId = selectedCase?["Id"] as? String, let refreshed = cases.first(where: { $0["Id"] as? String == selectedId }) {
                await loadCase(id: selectedId, showLoading: false, fallback: refreshed)
            }
        } catch is CancellationError {
            if sequence == current { loading = false }
            return
        } catch {
            if nativeTourismPrincipal(store.session?.accessToken) == requested, sequence == current {
                cases = []; selectedCase = nil; self.error = "售后记录暂不可确认：\(error.localizedDescription)"
            }
        }
        if sequence == current { loading = false }
    }

    private func loadCase(id: String, showLoading: Bool = true, fallback: [String: Any]? = nil, refresh: Bool = false) async {
        guard let token = store.session?.accessToken, let requested = nativeTourismPrincipal(token), Int64(id).map({ $0 > 0 }) == true else { return }
        if selectedCase?["Id"] as? String == id && showLoading && !refresh { selectedCase = nil; return }
        let verifiesUncertainAction = uncertainCaseID == id
        if verifiesUncertainAction { uncertainReadbackVerified = false }
        caseReadSequence += 1; let current = caseReadSequence
        let shouldShowLoading = showLoading || verifiesUncertainAction
        if shouldShowLoading { loading = true }; error = nil
        do {
            let result = try await MobileAPI(store: store).get("/api/JHCTITradeAfterSale/GetMyCase?id=\(id)", authenticated: true, expectedPrincipal: requested) as? [String: Any]
            guard caseReadSequence == current, nativeTourismPrincipal(store.session?.accessToken) == requested,
                  result?["Id"] as? String == id, result?["OrderId"] as? String == orderId else {
                throw MobileAPIError.unavailable("售后详情编号不匹配，请重新读取")
            }
            selectedCase = result
            if verifiesUncertainAction && uncertainCaseID == id { uncertainReadbackVerified = true }
        } catch is CancellationError {
            return
        } catch {
            if caseReadSequence == current, nativeTourismPrincipal(store.session?.accessToken) == requested {
                if verifiesUncertainAction && uncertainCaseID == id { uncertainReadbackVerified = false }
                self.error = "售后详情暂不可用：\(error.localizedDescription)"; selectedCase = fallback
            }
        }
        if caseReadSequence == current && shouldShowLoading { loading = false }
    }

    private func restoreUncertainAction() {
        guard let token = store.session?.accessToken, !orderId.isEmpty else {
            uncertainCaseID = ""; requestAttemptStored = false; retryAuthorized = false; return
        }
        uncertainCaseID = UserDefaults.standard.string(forKey: nativeBuyerAfterSaleLockStorageKey(accessToken: token, orderID: orderId)) ?? ""
        uncertainReadbackVerified = false
        for item in order["Items"] as? [[String: Any]] ?? [] {
            guard let itemId = item["Id"] as? String else { continue }
            let storageKey = nativeBuyerAfterSaleAttemptStorageKey(accessToken: token, orderID: orderId, itemID: itemId)
            guard let data = store.afterSaleRequestAttempt(for: storageKey) else { continue }
            guard let attempt = decodeNativeBuyerAfterSaleAttempt(data), attempt.orderID == orderId, attempt.itemID == itemId else {
                requestAttemptStored = true; needsVerification = true
                error = "售后申请快照无法读取，保护仍保持锁定；请勿重新填写或提交。"
                break
            }
            let requestItems = attempt.requestBody["Items"] as? [[String: Any]] ?? []
            guard let requestItem = requestItems.first else { continue }
            draftItem = item
            requestType = attempt.requestBody["RequestType"] as? String ?? "RefundOnly"
            quantity = requestItem["Quantity"] as? Int ?? 1
            reason = attempt.requestBody["ReasonCode"] as? String ?? reasons[0]
            description = attempt.requestBody["Description"] as? String ?? ""
            evidenceUrls = attempt.requestBody["EvidenceUrls"] as? [String] ?? []
            requestAttemptStored = true; retryAuthorized = attempt.retryAuthorized
            needsVerification = !attempt.retryAuthorized; verificationNoMatch = false
            break
        }
    }

    private func markUncertain(_ id: String, token: String) {
        uncertainCaseID = id; uncertainReadbackVerified = false
        UserDefaults.standard.set(id, forKey: nativeBuyerAfterSaleLockStorageKey(accessToken: token, orderID: orderId))
    }

    private func upload(_ selections: [PhotosPickerItem]) async throws {
        guard !busy, let item = draftItem, let token = store.session?.accessToken,
              let requested = nativeTourismPrincipal(token) else { photos = []; return }
        busy = true; error = nil
        defer { busy = false; photos = [] }
        do {
            for selection in selections.prefix(max(0, 8 - evidenceUrls.count)) {
                guard let source = try await selection.loadTransferable(type: Data.self), let image = UIImage(data: source) else {
                    throw MobileAPIError.unavailable("无法读取凭证图片，请重新选择")
                }
                let scale = min(1, 1920 / max(image.size.width, image.size.height))
                let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
                let renderer = UIGraphicsImageRenderer(size: size)
                var quality: CGFloat = 0.82
                var data = renderer.jpegData(withCompressionQuality: quality) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                while data.count > 5 * 1024 * 1024 && quality > 0.5 {
                    quality -= 0.08
                    data = renderer.jpegData(withCompressionQuality: quality) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                }
                guard data.count <= 5 * 1024 * 1024 else { throw MobileAPIError.unavailable("凭证图片压缩后仍超过 5 MB") }
                let url = try await MobileAPI(store: store).uploadMyAfterSaleEvidence(data, expectedPrincipal: requested)
                guard nativeTourismPrincipal(store.session?.accessToken) == requested, draftItem?["Id"] as? String == item["Id"] as? String else { return }
                if !evidenceUrls.contains(url) { evidenceUrls.append(url) }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch { if nativeTourismPrincipal(store.session?.accessToken) == requested { self.error = error.localizedDescription } }
    }

    private func submit() async throws {
        guard let item = draftItem, let itemId = item["Id"] as? String,
              let token = store.session?.accessToken, let requested = nativeTourismPrincipal(token), !busy, !loading else { return }
        let storageKey = nativeBuyerAfterSaleAttemptStorageKey(accessToken: token, orderID: orderId, itemID: itemId)
        let attempt: NativeBuyerAfterSaleAttempt
        if let saved = store.afterSaleRequestAttempt(for: storageKey), let existing = decodeNativeBuyerAfterSaleAttempt(saved) {
            guard existing.retryAuthorized || retryAuthorized else {
                self.error = "请先完整核对售后记录并确认没有该申请。"
                needsVerification = true
                return
            }
            attempt = existing
        } else {
            let idempotencyKey = "as-\(UUID().uuidString.lowercased())"
            let body: [String: Any] = ["IdempotencyKey": idempotencyKey, "OrderId": orderId, "RequestType": requestType,
                "Items": [["OrderItemId": itemId, "Quantity": quantity]], "ReasonCode": reason,
                "Description": String(description.prefix(2000)), "EvidenceUrls": evidenceUrls]
            let draft = NativeBuyerAfterSaleAttempt(idempotencyKey: idempotencyKey, orderID: orderId, itemID: itemId,
                createdAt: Date().timeIntervalSince1970, retryAuthorized: false, requestBody: body, storedData: Data())
            guard let saved = encodeNativeBuyerAfterSaleAttempt(draft, retryAuthorized: false),
                  let created = decodeNativeBuyerAfterSaleAttempt(saved),
                  store.saveAfterSaleRequestAttempt(saved, for: storageKey) else {
                self.error = "无法安全保存售后申请快照，申请未发送。"
                return
            }
            attempt = created
            requestAttemptStored = true
        }
        busy = true; error = nil; needsVerification = false; verificationNoMatch = false
        defer { busy = false }
        do {
            _ = try await MobileAPI(store: store).postJSON("/api/JHCTITradeAfterSale/CreateMyRequest", body: attempt.requestBody, authenticated: true, expectedPrincipal: requested)
            guard nativeTourismPrincipal(store.session?.accessToken) == requested else { throw MobileAPIError.unavailable("登录账号已变化，请核对本人售后记录") }
            store.clearAfterSaleRequestAttempt(attempt.storedData, for: storageKey)
            UserDefaults.standard.removeObject(forKey: nativeBuyerAfterSaleLockStorageKey(accessToken: token, orderID: orderId))
            requestAttemptStored = false; retryAuthorized = false
            draftItem = nil; evidenceUrls = []; description = ""
            await loadCases()
        } catch is CancellationError {
            if nativeTourismPrincipal(store.session?.accessToken) == requested {
                self.error = "申请结果待核对：请先读取本人售后记录"
                needsVerification = true
                retryAuthorized = false
            }
            throw CancellationError()
        } catch {
            guard nativeTourismPrincipal(store.session?.accessToken) == requested else { return }
            let status = (error as? MobileAPIError)?.httpStatusCode
            if let status, (400..<500).contains(status), status != 408, status != 429 {
                store.clearAfterSaleRequestAttempt(attempt.storedData, for: storageKey)
                requestAttemptStored = false; retryAuthorized = false; needsVerification = false
                self.error = "申请未能提交：\(error.localizedDescription)"
            } else {
                self.error = "申请结果待核对：\(error.localizedDescription)"
                needsVerification = true; retryAuthorized = false
            }
            await loadCases()
        }
    }

    private func sendMessage(id: String) async throws {
        let content = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, content.count <= 2000, let token = store.session?.accessToken,
              let requested = nativeTourismPrincipal(token), !busy, uncertainCaseID.isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await MobileAPI(store: store).postJSON("/api/JHCTITradeAfterSale/AddMyMessage", body: ["AfterSaleId": id, "Content": content, "EvidenceUrls": []], authenticated: true, expectedPrincipal: requested)
            guard nativeTourismPrincipal(store.session?.accessToken) == requested else { return }
            message = ""; await loadCase(id: id, showLoading: false)
        } catch is CancellationError {
            if nativeTourismPrincipal(store.session?.accessToken) == requested {
                markUncertain(id, token: token)
                self.error = "留言结果待核对，写操作已锁定。请读取详情并确认上次未生效后再手动解除保护。"
            }
            throw CancellationError()
        } catch { if nativeTourismPrincipal(store.session?.accessToken) == requested { markUncertain(id, token: token); self.error = "留言结果待核对，写操作已锁定。请读取详情并确认上次未生效后再手动解除保护。" } }
    }

    private func closeCase(id: String) async throws {
        guard let token = store.session?.accessToken, let requested = nativeTourismPrincipal(token), !busy, uncertainCaseID.isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await MobileAPI(store: store).post("/api/JHCTITradeAfterSale/CloseMyCase?id=\(id)", body: [:], authenticated: true, expectedPrincipal: requested)
            guard nativeTourismPrincipal(store.session?.accessToken) == requested else { return }
            await loadCases()
        } catch is CancellationError {
            if nativeTourismPrincipal(store.session?.accessToken) == requested {
                markUncertain(id, token: token)
                self.error = "撤回结果待核对，写操作已锁定；请读取售后记录核对。"
            }
            throw CancellationError()
        } catch { if nativeTourismPrincipal(store.session?.accessToken) == requested { markUncertain(id, token: token); self.error = "撤回结果待核对，写操作已锁定；请读取售后记录核对。"; await loadCases() } }
    }

    private func submitReturn(id: String) async throws {
        guard !carrier.isEmpty, !trackingNumber.isEmpty, let token = store.session?.accessToken,
              let requested = nativeTourismPrincipal(token), !busy, uncertainCaseID.isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await MobileAPI(store: store).postJSON("/api/JHCTITradeAfterSale/SubmitReturnShipment", body: [
                "AfterSaleId": id, "Carrier": carrier, "TrackingNumber": trackingNumber
            ], authenticated: true, expectedPrincipal: requested)
            guard nativeTourismPrincipal(store.session?.accessToken) == requested else { return }
            carrier = ""; trackingNumber = ""; await loadCase(id: id, showLoading: false)
        } catch is CancellationError {
            if nativeTourismPrincipal(store.session?.accessToken) == requested {
                markUncertain(id, token: token)
                self.error = "退货物流结果待核对，写操作已锁定；请重新读取详情并核对。"
            }
            throw CancellationError()
        } catch { if nativeTourismPrincipal(store.session?.accessToken) == requested { markUncertain(id, token: token); self.error = "退货物流结果待核对，写操作已锁定；请重新读取详情并核对。"; await loadCase(id: id, showLoading: false) } }
    }

    private func cancelDraft() {
        guard !requestAttemptStored else { return }
        let urls = evidenceUrls
        if !urls.isEmpty, let token = store.session?.accessToken,
           let requested = nativeTourismPrincipal(token) {
            Task { _ = try? await MobileAPI(store: store).post("/api/JHCTITradeAfterSale/QueueMyEvidenceCleanup", body: ["FileUrls": urls], authenticated: true, expectedPrincipal: requested) }
        }
        draftItem = nil; evidenceUrls = []; description = ""; needsVerification = false; verificationNoMatch = false
    }

    private func afterSaleStatus(_ value: String) -> String {
        ["PendingReview": "待审核", "Negotiating": "协商中", "ReturnRequired": "待退货", "ReturnInTransit": "退货运输中", "ReturnReceived": "已收退货", "ApprovedForRefund": "待退款", "RefundProcessing": "退款处理中", "Refunded": "已退款", "Rejected": "已拒绝", "Closed": "已关闭"][value] ?? "状态待确认"
    }
}
