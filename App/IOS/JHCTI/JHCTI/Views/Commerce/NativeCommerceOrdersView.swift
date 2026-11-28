import SwiftUI
import PhotosUI
import UIKit

struct NativeCommerceOrdersView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showTradePaymentPage = false
    @State private var rows: [[String: Any]] = []
    @State private var selectedOrder: [String: Any]?
    @State private var status = ""
    @State private var page = 1
    @State private var total = 0
    @State private var loading = false
    @State private var receiptRecovery: NativeShipmentReceiptState = .unavailable
    @State private var receiptPrincipal: String?
    @State private var verifiedReceipt: UUID?
    @State private var receiptProposal: ReceiptProposal?
    @State private var receiptTask: Task<Void, Never>?
    @State private var receiptSequence = 0
    @State private var busyPaymentOrderId = ""
    @State private var paymentNotice: String?
    @State private var digitalDeliveryNotice: String?
    @State private var error: String?
    @State private var requestSequence = 0
    @State private var reviewReadSequence = 0
    @State private var detailReadTask: Task<Void, Never>?
    @State private var reviewReadTask: Task<Void, Never>?
    @State private var reviewUploadTask: Task<Void, Never>?
    @State private var reviewUploadSequence = 0
    @State private var reviewSubmitTask: Task<Void, Never>?
    @State private var reviewSubmitSequence = 0
    @State private var reviewsEnabled = false
    @State private var reviewStatusLoading = false
    @State private var reviewStatusError: String?
    @State private var reviewedOrderItemIds = Set<String>()
    @State private var pendingReviewItemIds = Set<String>()
    @State private var reviewDraftItemId: String?
    @State private var reviewRating = 5
    @State private var reviewContent = ""
    @State private var reviewMediaUrls: [String] = []
    @State private var selectedReviewPhotos: [PhotosPickerItem] = []
    @State private var uploadingReviewPhotos = false
    @State private var submittingReview = false
    @State private var reviewNeedsVerification = false
    @State private var reviewMessage: String?

    private let filters = [("", "全部"), ("PendingPayment", "待付款"), ("PendingShipment", "待发货"), ("Shipped", "已发货"),
                           ("PendingPickup", "待自提"), ("Completed", "已完成"), ("Closed", "已关闭")]

    private struct ReceiptProposal {
        let orderID: String
        let shipmentID: String
        let principal: String
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selectedOrder {
                    orderDetail(selectedOrder)
                } else {
                    orderList
                }
            }
            .background(Brand.background)
            .navigationTitle(selectedOrder == nil ? "我的商城订单" : "订单履约详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedOrder != nil { Button("返回") { closeOrderDetail() } }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .sheet(isPresented: $showTradePaymentPage, onDismiss: {
                if let id = selectedOrder?["Id"] as? String { openOrder(id: id) }
            }) {
                NativeTradePaymentView(store: store, orderId: selectedOrder?["Id"] as? String ?? "")
            }
            .task(id: "\(nativeTourismPrincipal(store.session?.accessToken) ?? "")-\(status)") { await loadOrders(reset: true) }
            .confirmationDialog("确认收货", isPresented: Binding(get: { receiptProposal != nil }, set: { if !$0 { receiptProposal = nil } }),
                                titleVisibility: .visible, presenting: receiptProposal) { proposal in
                Button("确认收货") { startReceipt(proposal) }
                Button("返回", role: .cancel) {}
            } message: { _ in
                Text("请确认已经收到这张履约单发出的商品。")
            }
            .onChange(of: nativeTourismPrincipal(store.session?.accessToken)) { _, _ in
                detailReadTask?.cancel(); detailReadTask = nil
                reviewReadTask?.cancel(); reviewReadTask = nil
                reviewReadSequence += 1
                requestSequence += 1; rows = []; selectedOrder = nil; total = 0; page = 1
                resetReceipt()
                error = nil; loading = false; digitalDeliveryNotice = nil
                reviewsEnabled = false; reviewStatusLoading = false; reviewStatusError = nil
                reviewedOrderItemIds = []; pendingReviewItemIds = []; clearReviewDraft(queueImages: false)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    resetReceipt()
                    if selectedOrder != nil {
                        detailReadTask?.cancel(); detailReadTask = nil
                        requestSequence += 1; loading = false
                    }
                } else if let id = selectedOrder?["Id"] as? String {
                    openOrder(id: id)
                }
            }
            .onDisappear {
                resetReceipt()
                detailReadTask?.cancel(); detailReadTask = nil
                reviewReadTask?.cancel(); reviewReadTask = nil
                reviewReadSequence += 1
                requestSequence += 1; rows = []; selectedOrder = nil
                clearReviewDraft(queueImages: true)
            }
        }
    }

    private var orderList: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(filters, id: \.0) { filter in
                        Button(filter.1) { status = filter.0 }
                            .font(.system(size: NativeTypography.size(14), weight: .semibold))
                            .foregroundStyle(status == filter.0 ? .white : Brand.primary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(status == filter.0 ? Brand.primary : .white, in: Capsule())
                            .buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 10)
            }
            if loading && rows.isEmpty {
                ProgressView("正在读取商城订单…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, rows.isEmpty {
                ContentUnavailableView(error, systemImage: "exclamationmark.arrow.circlepath", description: Text("检查登录状态后下拉重试。"))
            } else if rows.isEmpty {
                ContentUnavailableView("暂无商城订单", systemImage: "shippingbox", description: Text("商城订单及履约记录会显示在这里。"))
            } else {
                List {
                    ForEach(rows.indices, id: \.self) { index in
                        orderCard(rows[index])
                            .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                            .listRowSeparator(.hidden).listRowBackground(Brand.background)
                    }
                    if rows.count < total {
                        Button(loading ? "正在加载…" : "加载更多") { Task { await loadOrders(reset: false) } }
                            .frame(maxWidth: .infinity).listRowBackground(Brand.background).disabled(loading)
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden).background(Brand.background)
                .refreshable { await loadOrders(reset: true) }
            }
            if let error, !rows.isEmpty { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red).padding(8) }
        }
    }

    private func orderCard(_ order: [String: Any]) -> some View {
        let orderId = order["Id"] as? String ?? ""
        let items = order["Items"] as? [[String: Any]] ?? []
        return Button { openOrder(id: orderId) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(order["OrderNo"] as? String ?? "商城订单").font(.system(size: NativeTypography.size(14), weight: .semibold))
                    Spacer()
                    Text(orderStatus(order["Status"] as? String ?? ""))
                        .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.primary)
                }
                Text(items.prefix(2).map { "\($0["ProductName"] as? String ?? "商品") × \($0["Quantity"] as? Int ?? 1)" }.joined(separator: "、"))
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink).lineLimit(2)
                Text("实付 \(order["Currency"] as? String ?? "CNY") \(money(order["PayableAmount"]))  ·  \(order["CreateTime"] as? String ?? "时间待提供")")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted).lineLimit(1)
                Text("查看订单及物流轨迹 ›").font(.system(size: NativeTypography.size(12), weight: .semibold)).foregroundStyle(Brand.primary)
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 11))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain)
    }

    private func orderDetail(_ order: [String: Any]) -> some View {
        let orderId = order["Id"] as? String ?? ""
        let paymentStatus = order["PaymentStatus"] as? String
        let items = order["Items"] as? [[String: Any]] ?? []
        let shipments = (try? readNativeBuyerShipments(order, orderID: orderId)) ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(order["OrderNo"] as? String ?? "商城订单").font(.system(size: NativeTypography.size(18), weight: .bold))
                    Text("状态：\(orderStatus(order["Status"] as? String ?? ""))")
                    Text("实付：\(order["Currency"] as? String ?? "CNY") \(money(order["PayableAmount"]))")
                }.font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 11))
                if order["Status"] as? String == "PendingPayment" {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("支付方式").font(.system(size: NativeTypography.size(14), weight: .semibold))
                        Text("支付宝将通过安全网页跳转；返回应用后请查询服务端订单状态。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        Button("打开独立支付页面") { showTradePaymentPage = true }
                            .font(.system(size: NativeTypography.size(14), weight: .semibold))
                        if let paymentNotice { Text(paymentNotice).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary) }
                        if paymentStatus == nil || paymentStatus == "RequiresAction" {
                            Button(busyPaymentOrderId == orderId ? "正在准备支付宝…" : "使用支付宝支付") {
                                Task { await startAlipayPayment(orderId: orderId) }
                            }
                            .font(.system(size: NativeTypography.size(14), weight: .semibold))
                            .disabled(!busyPaymentOrderId.isEmpty || loading || orderId.isEmpty)
                        } else {
                            Text(paymentStatusNotice(paymentStatus!))
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Color.red)
                        }
                        Button("我已完成支付，查询订单状态") { openOrder(id: orderId) }
                            .font(.system(size: NativeTypography.size(14), weight: .semibold))
                            .disabled(!busyPaymentOrderId.isEmpty || loading || orderId.isEmpty)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 11))
                }
                NativeCommerceOrderItemsSection(
                    orderStatus: order["Status"] as? String ?? "",
                    items: items,
                    reviewsEnabled: reviewsEnabled,
                    reviewStatusLoading: reviewStatusLoading,
                    reviewStatusError: reviewStatusError,
                    reviewedOrderItemIds: reviewedOrderItemIds,
                    pendingReviewItemIds: pendingReviewItemIds,
                    reviewDraftItemId: reviewDraftItemId,
                    uploadingReviewPhotos: uploadingReviewPhotos,
                    submittingReview: submittingReview,
                    reviewNeedsVerification: reviewNeedsVerification,
                    reviewMessage: reviewMessage,
                    reviewRating: $reviewRating,
                    reviewContent: $reviewContent,
                    reviewMediaUrls: $reviewMediaUrls,
                    selectedReviewPhotos: $selectedReviewPhotos,
                    onClearDraft: { clearReviewDraft(queueImages: true) },
                    onRemoveImage: removeReviewImage,
                    onVerifyReview: {
                        reviewReadTask?.cancel()
                        reviewReadTask = Task { await verifyReviewSubmission() }
                    },
                    onStartReview: { startReviewSubmission(itemId: $0) },
                    onStartDraft: startReviewDraft,
                    onReloadStatus: {
                        reviewReadTask?.cancel()
                        reviewReadTask = Task { await loadReviewStatus(for: order) }
                    })
                if ["PendingShipment", "PendingPickup", "Shipped", "Completed"].contains(order["Status"] as? String ?? "") {
                    NativeBuyerAfterSaleView(store: store, order: order)
                }
                NativeCommerceDigitalDeliverySection(orderStatus: order["Status"] as? String ?? "",
                    items: items, notice: $digitalDeliveryNotice)
                NativeCommerceShipmentsSection(shipments: shipments, recovery: receiptRecovery,
                    verifiedReceipt: verifiedReceipt, busy: loading || receiptTask != nil,
                    onVerify: { openOrder(id: orderId, allowReceiptRetry: true) },
                    onConfirm: { shipment in
                        guard scenePhase == .active, let principal = receiptPrincipal,
                              nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
                        receiptProposal = ReceiptProposal(orderID: orderId, shipmentID: shipment.id, principal: principal)
                    })
                if let error { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red) }
                Button("刷新订单与物流") { openOrder(id: order["Id"] as? String ?? "") }
                    .font(.system(size: NativeTypography.size(14), weight: .semibold)).frame(maxWidth: .infinity).padding(10)
                    .disabled(loading || receiptTask != nil)
            }.padding(14)
        }.refreshable {
            guard receiptTask == nil else { return }
            detailReadTask?.cancel(); detailReadTask = nil
            reviewReadTask?.cancel(); reviewReadTask = nil
            await loadOrder(id: order["Id"] as? String ?? "")
        }
            .onChange(of: selectedReviewPhotos) { _, items in
                guard !items.isEmpty, let itemId = reviewDraftItemId else { return }
                cancelReviewUpload()
                reviewUploadSequence += 1
                let sequence = reviewUploadSequence
                reviewUploadTask = Task { await uploadReviewPhotos(items, orderItemId: itemId, sequence: sequence) }
            }
    }

    private func paymentStatusNotice(_ status: String) -> String {
        switch status {
        case "Creating", "Processing": return "原支付请求仍在处理中，请勿重复付款；可刷新订单查看最新状态。"
        case "Unknown", "PaidUnmatched": return "原支付结果待核对，请勿重复付款；可刷新订单查看最新状态。"
        case "Failed", "Closed": return "原支付尝试已结束。请刷新订单核对后再处理，当前不支持再次发起支付。"
        default: return "支付状态与待付款订单不一致，请刷新订单核对；当前不支持再次发起支付。"
        }
    }

    private func loadOrders(reset: Bool) async {
        guard let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token) else { rows = []; error = "请先登录文旅账号。"; return }
        if reset { requestSequence += 1; page = 1; total = 0 }
        let sequence = requestSequence
        let targetPage = reset ? 1 : page + 1
        loading = true; error = nil
        do {
            let result = try await MobileAPI(store: store).get("/api/JHCTITradeOrder/GetMyOrderPage?page=\(targetPage)&pageSize=20&status=\(status)", authenticated: true, expectedPrincipal: requestedPrincipal) as? [String: Any]
                ?? [:]
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal, requestSequence == sequence else { return }
            guard let parsedPage = nativeBookingOrderPage(result, page: targetPage, pageSize: 20) else {
                throw MobileAPIError.unavailable("商城订单分页回执无效")
            }
            let data = parsedPage.rows
            let responseTotal = parsedPage.total
            let ids = data.compactMap { order -> String? in
                let values = ["Id", "id"].compactMap { order[$0] }
                guard !values.isEmpty, values.allSatisfy({ $0 is String }),
                      let first = values.first as? String,
                      values.allSatisfy({ ($0 as? String) == first }) else { return nil }
                return first
            }
            guard responseTotal >= (reset ? 0 : rows.count) + data.count,
                  data.count <= 20, ids.count == data.count,
                  ids.allSatisfy({ Int64($0).map { $0 > 0 } == true }), Set(ids).count == ids.count else {
                throw MobileAPIError.unavailable("商城订单分页回执无效")
            }
            rows = reset ? data : rows + data
            total = responseTotal
            page = targetPage
        } catch { if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal, requestSequence == sequence { self.error = error.localizedDescription } }
        if requestSequence == sequence { loading = false }
    }

    private func loadOrder(id: String, allowReceiptRetry: Bool = false) async {
        guard trackingID(id), let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token) else { error = "请重新登录后查看订单。"; return }
        verifiedReceipt = nil; receiptProposal = nil
        requestSequence += 1; let sequence = requestSequence; loading = true; error = nil; paymentNotice = nil; digitalDeliveryNotice = nil
        defer { if requestSequence == sequence { loading = false } }
        do {
            let result = try await MobileAPI(store: store).get("/api/JHCTITradeOrder/GetMyOrder?id=\(id)",
                authenticated: true, expectedPrincipal: requestedPrincipal, requireExplicitResponse: true)
            guard !Task.isCancelled, nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal, requestSequence == sequence else { return }
            guard var order = result as? [String: Any] else { throw MobileAPIError.unavailable("订单详情格式无效") }
            let shipments = try readNativeBuyerShipments(order, orderID: id)
            order["Id"] = id
            let storage = nativeShipmentReceiptStore(principal: requestedPrincipal, orderID: id)
            let recovery = storage.read()
            if let attempt = recovery.attempt, let shipment = shipments.first(where: { $0.id == attempt.shipmentID }) {
                if shipment.delivered { _ = storage.clear(recovery) }
                if allowReceiptRetry && shipment.canConfirm { verifiedReceipt = attempt.marker }
            }
            receiptRecovery = storage.read(); receiptPrincipal = requestedPrincipal
            selectedOrder = order
            await loadReviewStatus(for: order)
        } catch {
            if !Task.isCancelled, nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal, requestSequence == sequence {
                self.error = error.localizedDescription
            }
        }
    }

    private func loadReviewStatus(for order: [String: Any]) async {
        guard order["Status"] as? String == "Completed",
              let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token),
              let items = order["Items"] as? [[String: Any]] else {
            reviewsEnabled = false; reviewStatusLoading = false; reviewStatusError = nil; reviewedOrderItemIds = []; pendingReviewItemIds = []
            return
        }
        reviewsEnabled = false; reviewStatusLoading = true; reviewStatusError = nil; reviewedOrderItemIds = []
        let ids = Array(Set(items.compactMap { $0["Id"] as? String }.filter(validProductReviewItemID))).sorted()
        pendingReviewItemIds = Set(ids.filter {
            nativeProductReviewRecoveryStore(principal: requestedPrincipal, itemID: $0).read() != .ready
        })
        let orderId = order["Id"] as? String ?? ""
        reviewReadSequence += 1
        let sequence = reviewReadSequence
        do {
            let api = MobileAPI(store: store)
            let accessState = await api.featureAccessState("USER-REVIEWS", forceRefresh: true)
            try Task.checkCancellation()
            guard sequence == reviewReadSequence,
                  nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal,
                  selectedOrder?["Id"] as? String == orderId else {
                if sequence == reviewReadSequence { reviewStatusLoading = false }
                return
            }
            switch accessState {
            case .open:
                break
            case .closed, .pendingConfirmation:
                reviewsEnabled = false
                reviewStatusLoading = false
                return
            case .unavailable:
                throw MobileAPIError.unavailable("评价功能开放状态暂时无法确认，请重试")
            }
            var reviewed = Set<String>()
            for start in stride(from: 0, to: ids.count, by: 200) {
                let batch = Array(ids[start..<min(start + 200, ids.count)])
                let result = try await api.postJSON("/api/JHCTIProductReview/GetMineReviewedOrderItemIds",
                    body: batch, authenticated: true, expectedPrincipal: requestedPrincipal, requireExplicitResponse: true)
                guard !Task.isCancelled, sequence == reviewReadSequence,
                    nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal,
                    selectedOrder?["Id"] as? String == orderId else {
                    throw MobileAPIError.unavailable("评价状态响应无效或登录账号已变化")
                }
                reviewed.formUnion(try readNativeReviewedProductItems(result, requested: batch))
            }
            guard !Task.isCancelled, sequence == reviewReadSequence,
                  nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal,
                  selectedOrder?["Id"] as? String == orderId else { return }
            for itemID in reviewed {
                let recovery = nativeProductReviewRecoveryStore(principal: requestedPrincipal, itemID: itemID)
                _ = recovery.clear(recovery.read())
            }
            pendingReviewItemIds.subtract(reviewed)
            reviewedOrderItemIds.formUnion(reviewed)
            if let itemID = reviewDraftItemId, reviewed.contains(itemID) { clearReviewDraft(queueImages: false) }
            reviewsEnabled = true
        } catch {
            if !Task.isCancelled, sequence == reviewReadSequence,
               nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal,
               selectedOrder?["Id"] as? String == orderId {
                reviewStatusError = "评价状态暂不可读取；为避免重复评价，入口已暂时关闭。"
            }
        }
        if sequence == reviewReadSequence { reviewStatusLoading = false }
    }

    private func clearReviewDraft(queueImages: Bool) {
        let mayQueue = queueImages && !submittingReview && !reviewNeedsVerification
        reviewSubmitSequence += 1
        reviewSubmitTask?.cancel(); reviewSubmitTask = nil
        submittingReview = false
        cancelReviewUpload()
        if mayQueue { queueReviewImageCleanup(reviewMediaUrls) }
        reviewDraftItemId = nil; reviewRating = 5; reviewContent = ""; reviewMediaUrls = []
        selectedReviewPhotos = []; reviewNeedsVerification = false; reviewMessage = nil
    }

    private func cancelReviewUpload() {
        reviewUploadSequence += 1
        reviewUploadTask?.cancel(); reviewUploadTask = nil
        uploadingReviewPhotos = false
        selectedReviewPhotos = []
    }

    private func startReviewDraft(itemId: String) {
        guard validProductReviewItemID(itemId), !reviewedOrderItemIds.contains(itemId),
              !submittingReview, !uploadingReviewPhotos, !reviewStatusLoading,
              let principal = nativeTourismPrincipal(store.session?.accessToken) else { return }
        let pending = nativeProductReviewRecoveryStore(principal: principal, itemID: itemId).read() != .ready
        guard reviewsEnabled || pending else { return }
        clearReviewDraft(queueImages: true)
        reviewDraftItemId = itemId; reviewRating = 5; reviewContent = ""
        if pending { pendingReviewItemIds.insert(itemId) }
        reviewNeedsVerification = pending
        reviewMessage = pending ? "此前评价结果待核对，请先读取该商品的本人评价状态。" : nil
    }

    private func queueReviewImageCleanup(_ urls: [String]) {
        guard !urls.isEmpty, let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token) else { return }
        Task {
            _ = try? await MobileAPI(store: store).post("/api/JHCTIProductReview/QueueMyReviewImageCleanup",
                body: ["FileUrls": Array(Array(Set(urls)).prefix(9))], authenticated: true, expectedPrincipal: requestedPrincipal)
        }
    }

    private func removeReviewImage(_ url: String) {
        guard !submittingReview, !uploadingReviewPhotos, !reviewNeedsVerification, !reviewStatusLoading else { return }
        queueReviewImageCleanup([url]); reviewMediaUrls.removeAll { $0 == url }; reviewMessage = nil
    }

    private func uploadReviewPhotos(_ items: [PhotosPickerItem], orderItemId: String, sequence: Int) async {
        guard !items.isEmpty, !uploadingReviewPhotos, !submittingReview, !reviewNeedsVerification, !reviewStatusLoading,
              sequence == reviewUploadSequence, reviewDraftItemId == orderItemId, let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token) else { return }
        let capacity = max(0, 9 - reviewMediaUrls.count)
        guard capacity > 0 else { reviewMessage = "评价图片最多添加 9 张。"; selectedReviewPhotos = []; reviewUploadTask = nil; return }
        uploadingReviewPhotos = true; reviewMessage = nil
        defer {
            if sequence == reviewUploadSequence {
                uploadingReviewPhotos = false; selectedReviewPhotos = []; reviewUploadTask = nil
            }
        }
        do {
            for item in items.prefix(capacity) {
                try Task.checkCancellation()
                guard let source = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: source) else {
                    throw MobileAPIError.unavailable("所选图片无法读取，请重新选择")
                }
                try Task.checkCancellation()
                let scale = min(1, 1920 / max(image.size.width, image.size.height))
                let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
                let renderer = UIGraphicsImageRenderer(size: size)
                var quality: CGFloat = 0.82
                var data = renderer.jpegData(withCompressionQuality: quality) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                while data.count > 5 * 1024 * 1024 && quality > 0.5 {
                    quality -= 0.08
                    data = renderer.jpegData(withCompressionQuality: quality) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                }
                guard data.count <= 5 * 1024 * 1024 else { throw MobileAPIError.unavailable("图片压缩后仍超过 5 MB") }
                let url = try await MobileAPI(store: store).uploadMyProductReviewImage(data, expectedPrincipal: requestedPrincipal)
                guard !Task.isCancelled else {
                    if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal {
                        queueReviewImageCleanup([url])
                    }
                    return
                }
                guard sequence == reviewUploadSequence else { return }
                guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal, reviewDraftItemId == orderItemId else { return }
                if !reviewMediaUrls.contains(url) { reviewMediaUrls.append(url) }
            }
        } catch {
            if !Task.isCancelled, sequence == reviewUploadSequence,
               nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal, reviewDraftItemId == orderItemId {
                reviewMessage = "\(error.localizedDescription)。已上传图片仍保留在表单中，可核对图片列表后重新选择。"
            }
        }
    }

    private func verifyReviewSubmission() async {
        guard let itemId = reviewDraftItemId, reviewNeedsVerification, !submittingReview,
              let requestedPrincipal = nativeTourismPrincipal(store.session?.accessToken) else { return }
        let recovery = nativeProductReviewRecoveryStore(principal: requestedPrincipal, itemID: itemId)
        let pending = recovery.read()
        reviewStatusLoading = true; reviewMessage = nil
        reviewReadSequence += 1
        let sequence = reviewReadSequence
        defer { if sequence == reviewReadSequence { reviewStatusLoading = false } }
        do {
            let result = try await MobileAPI(store: store).postJSON("/api/JHCTIProductReview/GetMineReviewedOrderItemIds",
                body: [itemId], authenticated: true, expectedPrincipal: requestedPrincipal, requireExplicitResponse: true)
            guard !Task.isCancelled,
                sequence == reviewReadSequence,
                nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal,
                reviewDraftItemId == itemId else {
                throw MobileAPIError.unavailable("评价状态响应无效或登录账号已变化")
            }
            if try readNativeReviewedProductItems(result, requested: [itemId]).contains(itemId) {
                _ = recovery.clear(pending)
                pendingReviewItemIds.remove(itemId)
                reviewedOrderItemIds.insert(itemId); clearReviewDraft(queueImages: false)
                reviewStatusError = nil
            } else {
                guard pending == .ready ? recovery.read() == .ready : recovery.clear(pending) else {
                    throw MobileAPIError.unavailable("暂时无法解除本机评价保护")
                }
                pendingReviewItemIds.remove(itemId)
                reviewNeedsVerification = false
                reviewMessage = reviewsEnabled ? "暂未查到已提交评价，可确认后提交。" : "暂未查到已提交评价，恢复开放后可重新填写。"
            }
        } catch {
            if !Task.isCancelled, sequence == reviewReadSequence,
               nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal,
               reviewDraftItemId == itemId {
                reviewMessage = "评价状态仍无法确认，请稍后重试核对；核对前不会自动重发。"
            }
        }
    }

    private func openOrder(id: String, allowReceiptRetry: Bool = false) {
        guard receiptTask == nil else { return }
        detailReadTask?.cancel()
        reviewReadTask?.cancel(); reviewReadTask = nil
        reviewReadSequence += 1
        detailReadTask = Task { await loadOrder(id: id, allowReceiptRetry: allowReceiptRetry) }
    }

    private func closeOrderDetail() {
        resetReceipt()
        detailReadTask?.cancel(); detailReadTask = nil
        reviewReadTask?.cancel(); reviewReadTask = nil
        reviewReadSequence += 1
        requestSequence += 1
        clearReviewDraft(queueImages: true); selectedOrder = nil; error = nil
    }

    private func startReviewSubmission(itemId: String) {
        guard reviewSubmitTask == nil else { return }
        reviewSubmitSequence += 1
        let sequence = reviewSubmitSequence
        reviewSubmitTask = Task { await submitProductReview(itemId: itemId, sequence: sequence) }
    }

    private func submitProductReview(itemId: String, sequence: Int) async {
        let content = reviewContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reviewsEnabled, reviewDraftItemId == itemId, !submittingReview, !uploadingReviewPhotos,
              !reviewNeedsVerification, !reviewStatusLoading, !reviewedOrderItemIds.contains(itemId),
              content.utf16.count >= 2, content.utf16.count <= 2000, let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token) else {
            if content.utf16.count < 2 || content.utf16.count > 2000 { reviewMessage = "评价内容须为 2 至 2000 个字符。" }
            if sequence == reviewSubmitSequence { reviewSubmitTask = nil; submittingReview = false }
            return
        }
        let recovery = nativeProductReviewRecoveryStore(principal: requestedPrincipal, itemID: itemId)
        let marker = NativeProductReviewRecoveryMarker(itemID: itemId)
        guard recovery.save(marker) else {
            pendingReviewItemIds.insert(itemId)
            reviewNeedsVerification = true
            reviewMessage = "未能保存评价保护记录，评价未发送。请核对状态后重试。"
            if sequence == reviewSubmitSequence { reviewSubmitTask = nil }
            return
        }
        pendingReviewItemIds.insert(itemId)
        submittingReview = true; reviewMessage = nil
        defer {
            if sequence == reviewSubmitSequence {
                reviewSubmitTask = nil
                submittingReview = false
            }
        }
        do {
            let result = try await MobileAPI(store: store).post("/api/JHCTIProductReview/Submit", body: [
                "OrderItemId": itemId, "Rating": reviewRating, "Content": content, "MediaUrls": reviewMediaUrls
            ], authenticated: true, expectedPrincipal: requestedPrincipal, canRefresh: false, requireExplicitResponse: true)
            guard nativeProductReviewReceiptMatches(result, itemID: itemId) else {
                throw MobileAPIError.unavailable("评价回执无法确认，请核对本人评价状态")
            }
            _ = recovery.clear(.pending(marker))
            guard !Task.isCancelled, sequence == reviewSubmitSequence,
                  nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else {
                throw MobileAPIError.unavailable("评价回执无法确认，请核对本人评价状态")
            }
            reviewSubmitTask = nil
            pendingReviewItemIds.remove(itemId)
            reviewedOrderItemIds.insert(itemId); clearReviewDraft(queueImages: false); reviewStatusError = nil
        } catch {
            guard !Task.isCancelled, sequence == reviewSubmitSequence,
                  nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            reviewNeedsVerification = true
            reviewMessage = "\(error.localizedDescription)。请先核对评价状态，确认前不会自动重复提交。"
        }
    }

    @MainActor private func startAlipayPayment(orderId: String) async {
        guard let parsedID = Int64(orderId), parsedID > 0,
              let order = selectedOrder, order["Id"] as? String == orderId,
              let token = store.session?.accessToken, let requestedPrincipal = nativeTourismPrincipal(token), busyPaymentOrderId.isEmpty else {
            error = "订单或登录状态无效，请刷新后重试。"; return
        }
        guard let paymentDeadline = nativeBusinessTimestamp(order["PaymentExpiresAt"]), paymentDeadline > Date() else {
            error = "支付期限暂无法确认，请刷新订单状态后再试。"; return
        }
        busyPaymentOrderId = orderId; error = nil; paymentNotice = nil
        defer { busyPaymentOrderId = "" }
        do {
            guard let payment = try await MobileAPI(store: store).post("/api/JHCTITradeOrder/CreatePayment", body: [
                "OrderId": orderId, "Provider": "alipay", "Scene": "wap"
            ], authenticated: true, expectedPrincipal: requestedPrincipal) as? [String: Any],
                  nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else {
                throw MobileAPIError.unavailable("支付响应无效或登录账号已变化，请刷新订单核对。")
            }
            guard payment["Status"] as? String == "RequiresAction",
                  let rawURL = payment["ApprovalUrl"] as? String,
                  let url = URL(string: rawURL), url.scheme?.lowercased() == "https",
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
                throw MobileAPIError.unavailable("支付渠道未返回有效的 HTTPS 支付地址，请刷新订单核对。")
            }
            try requireNativePaymentLaunchDeadline(order["PaymentExpiresAt"])
            let opened = await withCheckedContinuation { continuation in
                openURL(url) { accepted in continuation.resume(returning: accepted) }
            }
            if opened {
                paymentNotice = "已打开支付宝支付页面。完成后返回此页，查询服务端订单状态。"
            } else {
                throw MobileAPIError.unavailable("设备未能打开支付页面；请查询订单状态后再继续。")
            }
        } catch {
            if store.session?.accessToken == token { self.error = error.localizedDescription }
        }
    }

    private func resetReceipt() {
        receiptSequence += 1
        receiptTask?.cancel(); receiptTask = nil
        receiptProposal = nil; verifiedReceipt = nil; receiptPrincipal = nil
        receiptRecovery = .unavailable
    }

    private func startReceipt(_ proposal: ReceiptProposal) {
        receiptProposal = nil
        guard receiptTask == nil, !loading, scenePhase == .active,
              receiptPrincipal == proposal.principal,
              nativeTourismPrincipal(store.session?.accessToken) == proposal.principal,
              let order = selectedOrder,
              let shipments = try? readNativeBuyerShipments(order, orderID: proposal.orderID),
              let shipment = shipments.first(where: { $0.id == proposal.shipmentID }) else { return }
        let storage = nativeShipmentReceiptStore(principal: proposal.principal, orderID: proposal.orderID)
        let current = storage.read()
        receiptRecovery = current
        guard current.canConfirm(shipment, verified: verifiedReceipt) else { return }
        verifiedReceipt = nil
        if current == .ready {
            guard storage.save(NativeShipmentReceiptAttempt(shipmentID: shipment.id)) else {
                receiptRecovery = storage.read()
                error = "设备无法保存收货待核对记录，确认请求未发送。"
                return
            }
            receiptRecovery = storage.read()
        }
        receiptSequence += 1
        let sequence = receiptSequence
        let detailRevision = requestSequence
        error = nil
        receiptTask = Task { await confirmReceipt(proposal, sequence: sequence, detailRevision: detailRevision) }
    }

    private func confirmReceipt(_ proposal: ReceiptProposal, sequence: Int, detailRevision: Int) async {
        defer { if receiptSequence == sequence { receiptTask = nil } }
        func isCurrent() -> Bool {
            !Task.isCancelled && scenePhase == .active && receiptSequence == sequence
                && nativeTourismPrincipal(store.session?.accessToken) == proposal.principal
                && selectedOrder?["Id"] as? String == proposal.orderID
        }
        guard isCurrent(), requestSequence == detailRevision else { return }
        do {
            let receipt = try await MobileAPI(store: store).post("/api/JHCTITradeOrder/ConfirmShipmentReceipt?shipmentId=\(proposal.shipmentID)",
                body: [:], authenticated: true, expectedPrincipal: proposal.principal, canRefresh: false, requireExplicitResponse: true)
            guard receipt as? String == proposal.shipmentID else { throw MobileAPIError.unavailable("收货回执与原履约单不一致。") }
            guard isCurrent(), requestSequence == detailRevision else { return }
            await loadOrder(id: proposal.orderID)
        } catch {
            if isCurrent(), requestSequence == detailRevision { self.error = "收货结果待核对，请重新读取原履约状态。" }
        }
    }

    private func orderStatus(_ value: String) -> String {
        ["PendingPayment": "待付款", "PendingShipment": "待发货", "Shipped": "已发货", "PendingPickup": "待自提", "Completed": "已完成", "Closed": "已关闭", "Refunded": "已退款"][value] ?? "状态待核对"
    }


    private func money(_ value: Any?) -> String {
        if let number = value as? NSNumber { return String(format: "%.2f", number.doubleValue) }
        if let text = value as? String, let number = Double(text) { return String(format: "%.2f", number) }
        return "金额待提供"
    }
}
