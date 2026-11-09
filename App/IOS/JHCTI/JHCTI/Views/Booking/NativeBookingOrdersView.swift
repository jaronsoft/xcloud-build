import SwiftUI

struct NativeBookingOrdersView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var kind: String
    @State private var rows: [[String: Any]] = []
    @State private var selectedOrder: [String: Any]?
    @State private var page = 1
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var requestSequence = 0
    @State private var detailReadTask: Task<Void, Never>?
    @State private var ownerContactRevealed = false
    @State private var cancellationConfirmationOrder: [String: Any]?
    @State private var cancellingOrderId = ""
    @State private var busyPaymentOrderId = ""
    @State private var paymentNotice: String?

    init(store: SessionStore, initialKind: String) {
        self.store = store
        _kind = State(initialValue: initialKind)
    }

    private var endpoint: String {
        kind == "hotel" ? "/api/JHCTIHotelBooking/GetMyOrderPage" : "/api/JHCTITravelRouteBooking/GetMyOrderPage"
    }

    private func isValidOrder(_ order: [String: Any], expectedId: String? = nil) -> Bool {
        guard let id = order["Id"] as? String,
              Int64(id).map({ $0 > 0 && String($0) == id }) == true,
              expectedId == nil || id == expectedId,
              let orderNo = order["OrderNo"] as? String, !orderNo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let status = order["Status"] as? String else { return false }
        func positiveStringId(_ key: String) -> Bool {
            guard let value = order[key] as? String, let number = Int64(value) else { return false }
            return number > 0 && String(number) == value
        }
        func nonemptyText(_ key: String) -> Bool {
            guard let value = order[key] as? String else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        func validAmount(_ key: String) -> Bool {
            guard let value = order[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return false }
            return value.doubleValue.isFinite && value.doubleValue >= 0
        }
        func validBool(_ key: String) -> Bool {
            guard let value = order[key] as? NSNumber else { return false }
            return CFGetTypeID(value) == CFBooleanGetTypeID()
        }
        func validInteger(_ key: String, range: ClosedRange<Int>) -> Bool {
            guard let value = order[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite, value.doubleValue.rounded() == value.doubleValue,
                  value.doubleValue >= Double(range.lowerBound), value.doubleValue <= Double(range.upperBound) else { return false }
            return true
        }
        func nullableText(_ key: String) -> Bool {
            guard let value = order[key] else { return false }
            return value is NSNull || value is String
        }
        func nullableDate(_ key: String) -> Bool {
            guard let value = order[key] else { return false }
            return value is NSNull || paymentDeadline(value) != nil
        }
        func nullablePaymentStatus(_ key: String) -> Bool {
            guard let value = order[key] else { return false }
            if value is NSNull { return true }
            return (value as? String).map { ["Creating", "RequiresAction", "Processing", "Unknown", "Paid", "PaidUnmatched", "Failed", "Closed", "ConflictingStatus"].contains($0) } == true
        }
        func moneySnapshotIsConsistent(pointsUsed: Int64) -> Bool {
            guard let amount = order["Amount"] as? NSNumber,
                  let discount = order["PointsDiscountAmount"] as? NSNumber,
                  let cash = order["CashPayableAmount"] as? NSNumber,
                  CFGetTypeID(amount) != CFBooleanGetTypeID(), CFGetTypeID(discount) != CFBooleanGetTypeID(), CFGetTypeID(cash) != CFBooleanGetTypeID() else { return false }
            let amountCents = (amount.doubleValue * 100).rounded()
            let discountCents = (discount.doubleValue * 100).rounded()
            let cashCents = (cash.doubleValue * 100).rounded()
            guard amountCents.isFinite, discountCents.isFinite, cashCents.isFinite,
                  abs(amount.doubleValue * 100 - amountCents) < 0.001,
                  abs(discount.doubleValue * 100 - discountCents) < 0.001,
                  abs(cash.doubleValue * 100 - cashCents) < 0.001,
                  amountCents > 0, discountCents <= amountCents,
                  amountCents == discountCents + cashCents else { return false }
            let currency = (order["Currency"] as? String ?? "").uppercased()
            if currency != "CNY" { return pointsUsed == 0 && discountCents == 0 }
            return discountCents == Double(pointsUsed) && discountCents * 2 <= amountCents
        }
        let knownCancellationModes = kind == "hotel"
            ? ["ManualReview", "FreeBeforeCheckIn"]
            : ["ManualReview", "FreeBeforeDeparture"]
        guard nonemptyText(kind == "hotel" ? "HotelName" : "RouteName"),
              nonemptyText("Currency"),
              positiveStringId(kind == "hotel" ? "HotelId" : "RouteId"),
              validAmount("Amount"), validAmount("PointsDiscountAmount"), validAmount("CashPayableAmount"),
              let pointsText = order["PointsUsed"] as? String,
              let pointsUsed = Int64(pointsText), pointsUsed >= 0, String(pointsUsed) == pointsText,
              paymentDeadline(order["PaymentExpiresAt"]) != nil,
              paymentDeadline(order["CreateTime"]) != nil,
              let cancellationMode = order["CancellationMode"] as? String,
              knownCancellationModes.contains(cancellationMode),
              validBool("HasUnavailablePayment"), validBool("HasUnmatchedPayment"),
              validBool("IsFreeCancellationAvailable"),
              nullableDate("CancelRequestedAt"), nullableDate("FreeCancellationDeadline"),
              nullablePaymentStatus("PaymentStatus"), nullableText("PaymentProvider"), nullableText("PaymentScene"),
              nullableText("CancellationReviewRemark") else { return false }
        if status == "CancellationReview", paymentDeadline(order["CancelRequestedAt"]) == nil { return false }
        let hasUnavailablePayment = (order["HasUnavailablePayment"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } == true
        if !hasUnavailablePayment, !moneySnapshotIsConsistent(pointsUsed: pointsUsed) { return false }
        if cancellationMode == (kind == "hotel" ? "FreeBeforeCheckIn" : "FreeBeforeDeparture"),
           paymentDeadline(order["FreeCancellationDeadline"]) == nil, !hasUnavailablePayment { return false }
        if kind == "hotel" {
            guard positiveStringId("RoomTypeId"), nonemptyText("RoomTypeName"),
                  validInteger("RoomCount", range: 1...10), validInteger("GuestCount", range: 1...20),
                  paymentDeadline(order["CheckIn"]) != nil, paymentDeadline(order["CheckOut"]) != nil,
                  nonemptyText("ContactName"), nonemptyText("ContactPhone"),
                  nullableText("OwnerContactName"), nullableText("OwnerContactPhone") else { return false }
        } else {
            guard positiveStringId("SessionId"), validInteger("GuestCount", range: 1...20),
                  paymentDeadline(order["DepartureDate"]) != nil,
                  validBool("CanRefundUnmatchedPayment") else { return false }
        }
        let knownStatuses = kind == "hotel"
            ? ["PendingPayment", "Paid", "Closed", "CancellationReview", "RefundProcessing", "Refunded", "PaymentReview"]
            : ["PendingPayment", "Paid", "Closed", "CancellationReview", "RefundProcessing", "Refunded", "GroupRefundProcessing", "PaymentReview"]
        guard knownStatuses.contains(status) else { return false }
        return true
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
            .navigationTitle(selectedOrder == nil ? "我的预订订单" : "预订订单详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedOrder != nil { Button("返回") {
                        requestSequence += 1; detailReadTask?.cancel(); detailReadTask = nil
                        loading = false; self.selectedOrder = nil; ownerContactRevealed = false; error = nil
                    } }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .task(id: "\(kind)-\(store.session?.accessToken ?? "")") { await load(reset: true) }
            .onChange(of: store.session?.accessToken) { _, _ in
                detailReadTask?.cancel(); detailReadTask = nil
                requestSequence += 1; rows = []; selectedOrder = nil; total = 0; page = 1
                error = nil; loading = false; ownerContactRevealed = false; paymentNotice = nil; busyPaymentOrderId = ""
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    ownerContactRevealed = false
                    if busyPaymentOrderId.isEmpty {
                        requestSequence += 1; detailReadTask?.cancel(); detailReadTask = nil; loading = false
                    }
                    return
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard scenePhase == .active, busyPaymentOrderId.isEmpty else { return }
                    if let id = selectedOrder?["Id"] as? String { await loadOrder(id: id) }
                    else { await load(reset: true) }
                }
            }
            .onDisappear { detailReadTask?.cancel(); detailReadTask = nil; requestSequence += 1; rows = []; selectedOrder = nil; loading = false; ownerContactRevealed = false; paymentNotice = nil }
            .confirmationDialog(cancellationConfirmationOrder.map { bookingCancellationTitle($0) } ?? "确认订单操作",
                isPresented: Binding(get: { cancellationConfirmationOrder != nil }, set: { if !$0 { cancellationConfirmationOrder = nil } }),
                titleVisibility: .visible) {
                Button("确认继续", role: .destructive) {
                    if let order = cancellationConfirmationOrder { Task { await cancelOrder(order) } }
                    cancellationConfirmationOrder = nil
                }
                Button("返回", role: .cancel) { cancellationConfirmationOrder = nil }
            } message: {
                Text(cancellationConfirmationOrder.map { bookingCancellationConfirmation($0, kind: kind) } ?? "")
            }
        }
    }

    private var orderList: some View {
        VStack(spacing: 0) {
            Picker("订单类型", selection: $kind) {
                Text("住宿订单").tag("hotel")
                Text("旅游线路").tag("route")
            }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 10)
            Text("共 \(total) 笔\(kind == "hotel" ? "住宿" : "线路")订单")
                .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 6)
            if loading && rows.isEmpty {
                ProgressView("正在读取订单…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, rows.isEmpty {
                ContentUnavailableView(error, systemImage: "exclamationmark.arrow.circlepath", description: Text("检查登录状态后下拉重试。"))
            } else if rows.isEmpty {
                ContentUnavailableView(kind == "hotel" ? "暂无住宿订单" : "暂无旅游线路订单",
                    systemImage: "ticket", description: Text("本人预订记录会显示在这里。"))
            } else {
                List {
                    if kind == "route", let paymentNotice {
                        Text(paymentNotice).font(.system(size: NativeTypography.size(13))).foregroundStyle(Brand.primary)
                            .listRowBackground(Brand.background)
                    }
                    ForEach(rows.indices, id: \.self) { index in
                        orderCard(rows[index])
                            .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                            .listRowSeparator(.hidden).listRowBackground(Brand.background)
                    }
                    if rows.count < total {
                        Button(loading ? "正在加载…" : "加载更多") { Task { await load(reset: false) } }
                            .frame(maxWidth: .infinity).listRowBackground(Brand.background).disabled(loading)
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden).background(Brand.background)
                    .refreshable { await load(reset: true) }
            }
            if let error, !rows.isEmpty { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red).padding(8) }
        }
    }

    private func orderCard(_ order: [String: Any]) -> some View {
        let name = kind == "hotel" ? order["HotelName"] as? String ?? "住宿订单" : order["RouteName"] as? String ?? "旅游线路订单"
        let subtitle = kind == "hotel"
            ? "\(order["RoomTypeName"] as? String ?? "房型待确认") · \(order["RoomCount"] as? Int ?? 1) 间 · \(order["GuestCount"] as? Int ?? 1) 人"
            : "出发时间：\(bookingBusinessDateTime(order["DepartureDate"]) ?? "待确认") · \(order["GuestCount"] as? Int ?? 1) 人"
        return VStack(alignment: .leading, spacing: 0) {
            Button { openOrder(id: order["Id"] as? String ?? "") } label: {
                VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(order["OrderNo"] as? String ?? name).font(.system(size: NativeTypography.size(14), weight: .semibold))
                    Spacer()
                    Text(bookingStatus(order["Status"] as? String ?? "", paymentStatus: order["PaymentStatus"] as? String ?? ""))
                        .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.primary)
                }
                Text(name).font(.system(size: NativeTypography.size(14), weight: .medium)).foregroundStyle(Brand.ink)
                Text(subtitle).font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted).lineLimit(2)
                if kind == "route" {
                    Text("下单时间：\(bookingBusinessDateTime(order["CreateTime"]) ?? "待确认")")
                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                }
                if kind == "hotel" {
                    Text("入住 \(order["CheckIn"] as? String ?? "日期待确认")  ·  离店 \(order["CheckOut"] as? String ?? "日期待确认")")
                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted).lineLimit(1)
                }
                Text("金额 \(order["Currency"] as? String ?? "CNY") \(money(order["CashPayableAmount"] ?? order["Amount"]))")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                Text("查看订单详情 ›").font(.system(size: NativeTypography.size(12), weight: .semibold)).foregroundStyle(Brand.primary)
                }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(bookingOrderListNotices(order, kind: kind).enumerated()), id: \.offset) { entry in
                        Text(entry.element).font(.system(size: NativeTypography.size(12))).foregroundStyle(.orange)
                    }
                    if let rule = bookingCancellationRule(order, kind: kind) {
                        Text(rule).font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                    }
                    HStack(spacing: 10) {
                        if bookingCanStartAlipayPayment(order, kind: kind) {
                            Button(busyPaymentOrderId == (order["Id"] as? String ?? "") ? "正在查询…" :
                                ((order["PaymentStatus"] as? String ?? "").isEmpty ? "继续支付" : "查询并继续原支付")) {
                                Task { await startAlipayPayment(order: order) }
                            }.disabled(!busyPaymentOrderId.isEmpty || !cancellingOrderId.isEmpty || loading)
                        }
                        if bookingCanRequestCancellation(order, kind: kind) {
                            Button(cancellingOrderId == (order["Id"] as? String ?? "")
                                ? "正在提交…" : bookingCancellationTitle(order), role: .destructive) {
                                cancellationConfirmationOrder = order
                            }.disabled(!cancellingOrderId.isEmpty || !busyPaymentOrderId.isEmpty || loading)
                        }
                    }.font(.system(size: NativeTypography.size(13), weight: .semibold))
            }.padding(.horizontal, 13).padding(.bottom, 13)
        }.background(.white, in: RoundedRectangle(cornerRadius: 11))
    }

    private func orderDetail(_ order: [String: Any]) -> some View {
        let name = kind == "hotel" ? order["HotelName"] as? String ?? "住宿订单" : order["RouteName"] as? String ?? "旅游线路订单"
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(order["OrderNo"] as? String ?? name).font(.system(size: NativeTypography.size(16), weight: .bold))
                    Text(name).font(.system(size: NativeTypography.size(14), weight: .medium))
                    Text("状态：\(bookingStatus(order["Status"] as? String ?? "", paymentStatus: order["PaymentStatus"] as? String ?? ""))")
                    Text("金额：\(order["Currency"] as? String ?? "CNY") \(money(order["CashPayableAmount"] ?? order["Amount"]))")
                }.font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 11))
                if (order["Status"] as? String) == "PendingPayment" {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("支付方式").font(.system(size: NativeTypography.size(14), weight: .semibold))
                        Text("支付宝将通过安全网页跳转；返回应用后请刷新本人订单状态。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        if let paymentNotice { Text(paymentNotice).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary) }
                        let paymentStatus = order["PaymentStatus"] as? String ?? ""
                        if kind == "route", order["HasUnmatchedPayment"] as? Bool != true, paymentStatus == "RequiresAction" {
                            Text("原支付单仍可继续操作，当前不能关闭订单或释放班期名额。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(.orange)
                        }
                        if bookingCanStartAlipayPayment(order, kind: kind) {
                            Button(busyPaymentOrderId == (order["Id"] as? String ?? "")
                                ? "正在查询原支付…" : (paymentStatus.isEmpty ? "使用支付宝支付" : "查询并继续支付宝支付")) {
                                Task { await startAlipayPayment(order: order) }
                            }
                            .font(.system(size: NativeTypography.size(14), weight: .semibold))
                            .disabled(!busyPaymentOrderId.isEmpty || !cancellingOrderId.isEmpty || loading)
                        } else {
                            Text(bookingPaymentStatusNotice(paymentStatus, provider: order["PaymentProvider"] as? String,
                                scene: order["PaymentScene"] as? String, kind: kind,
                                unavailable: order["HasUnavailablePayment"] as? Bool == true,
                                unmatched: order["HasUnmatchedPayment"] as? Bool == true))
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                        }
                        Button("刷新本人订单状态") { openOrder(id: order["Id"] as? String ?? "") }
                            .font(.system(size: NativeTypography.size(14), weight: .semibold))
                            .disabled(!busyPaymentOrderId.isEmpty || loading)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 11))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind == "hotel" ? "住宿安排" : "出行安排").font(.system(size: NativeTypography.size(14), weight: .semibold))
                    if kind == "hotel" {
                        Text("房型：\(order["RoomTypeName"] as? String ?? "待确认")")
                        Text("入住：\(order["CheckIn"] as? String ?? "待确认")")
                        Text("离店：\(order["CheckOut"] as? String ?? "待确认")")
                        Text("房间：\(order["RoomCount"] as? Int ?? 1) 间 · 入住人数：\(order["GuestCount"] as? Int ?? 1) 人")
                        Text("联系人：\(order["ContactName"] as? String ?? "已加密") · \(order["ContactPhone"] as? String ?? "已加密")")
                        if ownerContactRevealed {
                            Text("完整入住联系人：\(order["OwnerContactName"] as? String ?? "暂无") · \(order["OwnerContactPhone"] as? String ?? "暂无")")
                                .font(.system(size: NativeTypography.size(14), weight: .medium)).foregroundStyle(Brand.primary)
                        }
                        Button(ownerContactRevealed ? "隐藏完整入住联系人" : "查看完整入住联系人") {
                            ownerContactRevealed.toggle()
                        }
                        .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.primary)
                    } else {
                        Text("出发时间：\(bookingBusinessDateTime(order["DepartureDate"]) ?? "待确认")")
                        Text("出行人数：\(order["GuestCount"] as? Int ?? 1) 人")
                    }
                }.font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 11))
                if let cancellationRule = bookingCancellationRule(order, kind: kind) {
                    Text(cancellationRule).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 11))
                }
                if let remark = order["CancellationReviewRemark"] as? String, !remark.isEmpty {
                    Text("取消申请处理意见：\(remark)").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 11))
                }
                if bookingCanRequestCancellation(order, kind: kind) {
                    Button {
                        cancellationConfirmationOrder = order
                    } label: {
                        Text(cancellingOrderId == (order["Id"] as? String ?? "") ? "正在提交…" : bookingCancellationTitle(order))
                            .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(12).background(Brand.primary, in: RoundedRectangle(cornerRadius: 10))
                    }.disabled(loading || !cancellingOrderId.isEmpty || !busyPaymentOrderId.isEmpty)
                }
                if let error { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red) }
            }.padding(14)
        }.refreshable { await loadOrder(id: order["Id"] as? String ?? "") }
    }

    private func load(reset: Bool) async {
        guard let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token) else { rows = []; error = "请先登录文旅账号。"; return }
        if reset { requestSequence += 1; page = 1; total = 0 }
        let sequence = requestSequence; let targetPage = reset ? 1 : page + 1
        loading = true; error = nil
        do {
            guard let result = try await MobileAPI(store: store).get("\(endpoint)?page=\(targetPage)&pageSize=20", authenticated: true, expectedPrincipal: requestedPrincipal) as? [String: Any] else {
                throw MobileAPIError.unavailable("预订订单响应格式异常，请刷新后重试。")
            }
            guard store.session?.accessToken == token, requestSequence == sequence else { return }
            guard let pageResult = nativeBookingOrderPage(result, page: targetPage, pageSize: 20) else {
                throw MobileAPIError.unavailable("预订订单分页回执无效，请刷新后重试。")
            }
            let data = pageResult.rows
            let normalizedData = data.map(normalizedNativeBookingPaymentStatus)
            guard normalizedData.allSatisfy({ isValidOrder($0) }),
                  Set(normalizedData.compactMap { $0["Id"] as? String }).count == normalizedData.count else {
                throw MobileAPIError.unavailable("预订订单记录或编号异常，请刷新后重试。")
            }
            let updatedRows = reset ? normalizedData : rows + normalizedData
            guard Set(updatedRows.compactMap { $0["Id"] as? String }).count == updatedRows.count,
                  pageResult.total >= updatedRows.count else {
                throw MobileAPIError.unavailable("预订订单分页数据不一致，请刷新后重试。")
            }
            rows = updatedRows
            total = pageResult.total
            page = targetPage
        } catch is CancellationError { return
        } catch { if store.session?.accessToken == token, requestSequence == sequence { self.error = error.localizedDescription } }
        if requestSequence == sequence { loading = false }
    }

    private func loadOrder(id: String) async {
        guard !id.isEmpty, let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token) else { error = "请重新登录后查看订单。"; return }
        requestSequence += 1; let sequence = requestSequence; loading = true; error = nil; paymentNotice = nil
        do {
            let detailEndpoint = kind == "hotel" ? "/api/JHCTIHotelBooking/GetMyOrder" : "/api/JHCTITravelRouteBooking/GetMyOrder"
            let response = try await MobileAPI(store: store).get("\(detailEndpoint)?id=\(id)", authenticated: true, expectedPrincipal: requestedPrincipal) as? [String: Any]
            let order = response.map(normalizedNativeBookingPaymentStatus)
            guard store.session?.accessToken == token, requestSequence == sequence,
                  let order, isValidOrder(order, expectedId: id) else {
                throw MobileAPIError.unavailable("预订订单详情回执与当前订单不一致，请刷新后重试。")
            }
            ownerContactRevealed = false
            selectedOrder = order
        } catch is CancellationError { return
        } catch { if store.session?.accessToken == token, requestSequence == sequence { self.error = error.localizedDescription } }
        if requestSequence == sequence { loading = false }
    }

    private func openOrder(id: String) {
        detailReadTask?.cancel()
        detailReadTask = Task { await loadOrder(id: id) }
    }

    @MainActor private func startAlipayPayment(order: [String: Any]) async {
        guard let orderId = order["Id"] as? String, let parsedId = Int64(orderId), parsedId > 0,
              let token = store.session?.accessToken, let requestedPrincipal = nativeTourismPrincipal(token), busyPaymentOrderId.isEmpty,
              bookingCanStartAlipayPayment(order, kind: kind) else {
            error = "当前订单或支付状态不适合发起此支付，请刷新本人订单状态。"; return
        }
        let requestedKind = kind
        let activeSequence = requestSequence
        busyPaymentOrderId = orderId; error = nil; paymentNotice = nil
        defer { if busyPaymentOrderId == orderId { busyPaymentOrderId = "" } }
        do {
            let controller = kind == "hotel" ? "JHCTIHotelBooking" : "JHCTITravelRouteBooking"
            guard let payment = try await MobileAPI(store: store).post("/api/\(controller)/CreateOrderPayment", body: [
                "OrderId": orderId, "Provider": "alipay", "Scene": "wap"
            ], authenticated: true, expectedPrincipal: requestedPrincipal) as? [String: Any], store.session?.accessToken == token,
                  requestSequence == activeSequence,
                  (selectedOrder?["Id"] as? String == orderId || rows.contains(where: { $0["Id"] as? String == orderId })) else {
                throw MobileAPIError.unavailable("支付响应无效或订单页面已变化，请刷新本人订单状态。")
            }
            guard let expectedCashCents = nativeMoneyCents(order["CashPayableAmount"]),
                  let expectedCurrency = order["Currency"] as? String,
                  let url = nativeAlipayPaymentApprovalURL(payment, expectedCashCents: expectedCashCents,
                    expectedCurrency: expectedCurrency) else {
                throw MobileAPIError.unavailable("支付回执金额、币种或支付地址与订单不匹配，请刷新本人订单状态。")
            }
            try requireNativePaymentLaunchDeadline(order["PaymentExpiresAt"])
            let opened = await withCheckedContinuation { continuation in
                openURL(url) { accepted in continuation.resume(returning: accepted) }
            }
            if opened {
                paymentNotice = "已打开支付宝支付页面。完成后返回此页并刷新本人订单状态。"
            } else {
                throw MobileAPIError.unavailable("设备未能打开支付页面；请刷新本人订单状态后再继续。")
            }
        } catch {
            guard store.session?.accessToken == token, requestSequence == activeSequence, kind == requestedKind else { return }
            if requestedKind == "route" {
                let wasOrderDetailOpen = selectedOrder?["Id"] as? String == orderId
                if wasOrderDetailOpen { await loadOrder(id: orderId) }
                else { await load(reset: true) }
                guard store.session?.accessToken == token, kind == requestedKind else { return }
            }
            self.error = "\(error.localizedDescription)。支付结果可能尚未同步，请刷新本人订单状态核对；为避免重复扣款，不会自动再次支付。"
        }
    }

    private func cancelOrder(_ order: [String: Any]) async {
        guard let id = order["Id"] as? String, !id.isEmpty,
              let token = store.session?.accessToken, let requestedPrincipal = nativeTourismPrincipal(token), cancellingOrderId.isEmpty else { return }
        let requestedKind = kind
        cancellingOrderId = id; error = nil
        defer { if cancellingOrderId == id { cancellingOrderId = "" } }
        do {
            let path: String
            if kind == "hotel", (order["Status"] as? String) == "PendingPayment" {
                path = "/api/JHCTIHotelBooking/CancelMyPendingOrder?id=\(id)"
            } else {
                let controller = kind == "hotel" ? "JHCTIHotelBooking" : "JHCTITravelRouteBooking"
                path = "/api/\(controller)/RequestCancellation?id=\(id)"
            }
            let receipt = try await MobileAPI(store: store).post(path, body: [:], authenticated: true, expectedPrincipal: requestedPrincipal) as? String
            guard store.session?.accessToken == token else { return }
            guard receipt == id else { throw MobileAPIError.unavailable("取消回执与当前订单不一致，请刷新状态核对") }
            if selectedOrder?["Id"] as? String == id { await loadOrder(id: id) }
            else { await load(reset: true) }
        } catch {
            guard store.session?.accessToken == token, kind == requestedKind else { return }
            if requestedKind == "route" {
                let wasOrderDetailOpen = selectedOrder?["Id"] as? String == id
                if wasOrderDetailOpen { await loadOrder(id: id) }
                else { await load(reset: true) }
                guard store.session?.accessToken == token, kind == requestedKind else { return }
                let latest = wasOrderDetailOpen ? selectedOrder : rows.first(where: { $0["Id"] as? String == id })
                if let latest, (latest["Status"] as? String) != (order["Status"] as? String) {
                    self.error = "订单状态已更新，请查看订单。"
                    return
                }
            }
            self.error = "\(error.localizedDescription)。请刷新订单核对；为避免重复提交，不会自动再次申请。"
        }
    }

    private func bookingStatus(_ value: String, paymentStatus: String) -> String {
        if paymentStatus == "ConflictingStatus" { return "支付信息冲突待核对" }
        if paymentStatus == "PaidUnmatched" { return "收款待核对" }
        if ["Creating", "Unknown", "Processing"].contains(paymentStatus) { return "支付结果确认中" }
        return ["PendingPayment": "待支付", "Paid": kind == "hotel" ? "已支付，待入住" : "已支付，待出行",
                "PaymentReview": "收款待核对", "CancellationReview": "取消审核中", "RefundProcessing": "退款处理中",
                "GroupRefundProcessing": "未成团，退款处理中", "Refunded": "已退款", "Closed": "已关闭"][value] ?? "状态待确认"
    }

    private func money(_ value: Any?) -> String {
        if let number = value as? NSNumber { return String(format: "%.2f", number.doubleValue) }
        if let text = value as? String, let number = Double(text) { return String(format: "%.2f", number) }
        return "金额待确认"
    }
}

private func bookingCanStartAlipayPayment(_ order: [String: Any], kind: String) -> Bool {
    guard (order["Status"] as? String) == "PendingPayment",
          order["HasUnavailablePayment"] as? Bool != true,
          order["HasUnmatchedPayment"] as? Bool != true,
          (order["PaymentStatus"] as? String) != "PaidUnmatched" else { return false }
    let status = order["PaymentStatus"] as? String ?? ""
    let provider = (order["PaymentProvider"] as? String ?? "").lowercased()
    let scene = (order["PaymentScene"] as? String ?? "").lowercased()
    if status.isEmpty { return provider.isEmpty && scene.isEmpty }
    guard provider == "alipay", scene == "wap" else { return false }
    if ["RequiresAction", "Creating", "Unknown", "Processing"].contains(status) { return true }
    return kind == "hotel" && ["Failed", "Closed"].contains(status)
}

private func bookingPaymentStatusNotice(_ status: String, provider: String?, scene: String?, kind: String,
    unavailable: Bool, unmatched: Bool) -> String {
    if status == "ConflictingStatus" { return "支付状态信息不一致，请刷新本人订单后再处理；请勿重复付款或取消。" }
    if unavailable { return "订单支付关联异常，已暂停支付；请联系平台核对。" }
    if unmatched || status == "PaidUnmatched" { return "存在渠道收款待核对，请勿再次付款；请联系平台处理。" }
    if !status.isEmpty && ((provider ?? "").lowercased() != "alipay" || (scene ?? "").lowercased() != "wap") {
        return "当前支付尝试不属于支付宝网页支付，请勿重复付款；请刷新本人订单或使用原渠道。"
    }
    if ["Creating", "Unknown", "Processing"].contains(status) { return "原支付结果仍在确认，请勿重复付款；可查询并继续原支付。" }
    if ["Failed", "Closed"].contains(status) && kind != "hotel" { return "原支付已结束，线路订单状态以服务端为准；请刷新本人订单。" }
    if ["Failed", "Closed"].contains(status) { return "原支付已结束，刷新后可按服务端状态重新发起酒店支付。" }
    return "支付状态与待付款订单不一致，请刷新本人订单或联系平台核对。"
}

private func bookingCanRequestCancellation(_ order: [String: Any], kind: String) -> Bool {
    guard order["HasUnavailablePayment"] as? Bool != true,
          order["HasUnmatchedPayment"] as? Bool != true,
          (order["PaymentStatus"] as? String) != "PaidUnmatched" else { return false }
    let status = order["Status"] as? String ?? ""
    let payment = order["PaymentStatus"] as? String ?? ""
    if status == "PendingPayment" {
        return payment.isEmpty || kind == "hotel" && ["RequiresAction", "Failed", "Closed"].contains(payment)
    }
    return status == "Paid" && payment == "Paid"
}

private func bookingCancellationTitle(_ order: [String: Any]) -> String {
    if (order["Status"] as? String) == "PendingPayment" { return "关闭未支付订单" }
    return "申请取消订单"
}

private func bookingCancellationConfirmation(_ order: [String: Any], kind: String) -> String {
    if (order["Status"] as? String) == "PendingPayment" {
        return kind == "hotel" ? "关闭后会释放预留房间；未支付订单不会产生退款。" : "关闭后会释放预留名额；未支付订单不会产生退款。"
    }
    return "系统会按下单时保存的取消规则处理；符合免费取消条件时按原支付渠道退款，其他情况转平台审核。"
}

func nativeTradePaymentNeedsReconciliation(_ order: [String: Any]) -> Bool {
    order["Status"] as? String == "PendingPayment"
        && ["Creating", "RequiresAction", "Processing", "Unknown", "PaidUnmatched"].contains(order["PaymentStatus"] as? String ?? "")
}

func nativeTicketPaymentNeedsReconciliation(_ order: [String: Any]) -> Bool {
    order["Status"] as? String == "PaidPendingIssue" || nativeTradePaymentNeedsReconciliation(order)
}

func nativeDiningPackagePaymentNeedsReconciliation(_ order: [String: Any], afterPaymentLaunch: Bool = false) -> Bool {
    if order["HasUnmatchedPayment"] as? Bool == true || order["hasUnmatchedPayment"] as? Bool == true { return true }
    guard order["Status"] as? String == "PendingPayment" else { return false }
    let pendingStatuses: Set<String> = ["Creating", "RequiresAction", "Processing", "Unknown", "PaidUnmatched"]
    let paymentStatus = (order["PaymentStatus"] ?? order["paymentStatus"]) as? String
    let activeStatus = order["ActivePaymentStatus"] as? String
    return pendingStatuses.contains(paymentStatus ?? "") || pendingStatuses.contains(activeStatus ?? "")
        || (afterPaymentLaunch && paymentStatus == nil && activeStatus == nil)
}

// 渠道返回后只读取本人订单；有限预算避免结果未知时持续请求，更不能自动重发支付。
@MainActor
func reconcileNativePaymentOrder(initial: [String: Any], orderID: String,
    read: () async throws -> [String: Any], isCurrent: () -> Bool,
    apply: ([String: Any]) -> Void, exhausted: () -> Void, invalid: () -> Void,
    pending: ([String: Any]) -> Bool = nativeTradePaymentNeedsReconciliation,
    sleep: (Int64) async throws -> Void = { try await Task.sleep(for: .milliseconds($0)) }) async {
    guard isCurrent(), initial["Id"] as? String == orderID, pending(initial) else { return }
    for delay: Int64 in [1500, 2500, 4000, 6000, 10000, 15000] {
        do { try await sleep(delay) } catch { return }
        guard !Task.isCancelled, isCurrent() else { return }
        do {
            let next = try await read()
            guard !Task.isCancelled, isCurrent() else { return }
            guard next["Id"] as? String == orderID else { invalid(); return }
            apply(next)
            if !isCurrent() || !pending(next) { return }
        } catch is CancellationError { return
        } catch {
            if Task.isCancelled || !isCurrent() { return }
        }
    }
    if isCurrent() { exhausted() }
}
