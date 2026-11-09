import SwiftUI

struct NativeTicketBookingView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let resourceId: String
    let resourceName: String
    let admissionType: String
    var initialTicketTypeID: String? = nil
    @State private var tickets: [[String: Any]] = []
    @State private var ticketId = ""
    @State private var sessionId = ""
    @State private var quantity = 1
    @State private var attendees: [[String: String]] = [[:]]
    @State private var identityConsent = false
    @State private var identityProfileOpen = false
    @State private var ticketIdentityProfile: [String: Any]?
    @State private var ticketIdentityOwner = ""
    @State private var ticketIdentityLoading = false
    @State private var ticketIdentityError: String?
    @State private var ticketIdentitySequence = 0
    @State private var ticketIdentityRevision = 0
    @State private var pendingTicketIdentityConfirmation: String?
    @State private var loading = true
    @State private var submitting = false
    @State private var error: String?
    @State private var receipt: [String: Any]?
    @State private var ticketOrdersOpen = false
    @State private var idempotencyKey = ""
    @State private var pendingBody: [String: Any]?
    @State private var pendingExpectedAmountCents: Int?
    @State private var pendingRecoveryData: Data?
    @State private var submitSequence = 0
    @State private var pageVisible = true
    @State private var recoveryStorageKey = ""
    @State private var recoveryNotice: String?
    @State private var recoveryBlocked = false
    @State private var pointsToUse = "0"
    @State private var pointsBalance: Int64?
    @State private var pointsDebt: Int64?
    @State private var pointsSummaryError = false
    @State private var pointsSummaryRevision = 0
    @State private var catalogRevision = 0
    @State private var catalogSequence = 0
    @State private var catalogLoaded = false
    @State private var catalogNotice = ""
    @State private var nextSaleStartTime: Date?
    @State private var nextSaleLookupPending = false
    @State private var nextSaleLookupError: String?
    @State private var bookingOwnerPrincipal: String?
    @State private var catalogExpiresAt: Date?
    @State private var dailyQuota: [String: Any]?
    @State private var dailyQuotaOwner = ""
    @State private var dailyQuotaLoading = false
    @State private var dailyQuotaError: String?
    @State private var dailyQuotaSequence = 0
    @State private var dailyQuotaRevision = 0

    private var selectedTicket: [String: Any]? { tickets.first { $0["Id"] as? String == ticketId } }
    private var ticketFields: [[String: Any]] { selectedTicket?["RealNameFields"] as? [[String: Any]] ?? [] }
    private var selectedSession: [String: Any]? { sessions.first { $0["Id"] as? String == sessionId } }
    private var sessions: [[String: Any]] {
        let minimum = max(1, selectedTicket?["MinPerOrder"] as? Int ?? 1)
        return nativeTicketSelectableSessions(selectedTicket, minimumQuantity: minimum)
    }
    private var maximumQuantity: Int {
        min(selectedTicket?["MaxPerOrder"] as? Int ?? 1, selectedSession?["RemainingInventory"] as? Int ?? 1,
            pendingBody == nil ? dailyQuotaRemaining ?? 0 : 100)
    }
    private var dailyQuotaContext: String {
        guard pendingBody == nil, receipt == nil, pageVisible, scenePhase == .active,
              let principal = nativeTourismPrincipal(store.session?.accessToken),
              let ticket = selectedTicket, let session = selectedSession else { return "" }
        return "\(principal)|\(ticketId)|\(sessionId)|\(ticket["MaxPerUserPerDay"] ?? "")|\(session["StartTime"] ?? "")|\(catalogSequence)|\(dailyQuotaRevision)"
    }
    private var dailyQuotaRemaining: Int? {
        guard !dailyQuotaContext.isEmpty, dailyQuotaOwner == dailyQuotaContext,
              let date = nativeTicketVisitDate(selectedSession?["StartTime"], parseTime: paymentDeadline),
              let limit = selectedTicket?["MaxPerUserPerDay"] as? Int else { return nil }
        return nativeTicketDailyQuotaRemaining(dailyQuota, ticketID: ticketId, sessionID: sessionId, visitDate: date, dailyLimit: limit)
    }
    private var estimatedAmount: Double {
        ((selectedTicket?["Price"] as? NSNumber)?.doubleValue ?? 0) * Double(quantity)
    }
    private var maximumPoints: Int64 {
        min(pointsBalance ?? 0, maximumPointsForHalfAmount(estimatedAmount))
    }
    private var requiresIdentityConsent: Bool {
        !accountIdentityKeys.isEmpty || ticketFields.contains { field in
            (field["Type"] as? String == "IdentityNumber")
                && ((field["Required"] as? Bool == true)
                    || attendees.contains { !($0[field["Key"] as? String ?? ""] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
    }
    private var hasIdentityField: Bool { ticketFields.contains { $0["Type"] as? String == "IdentityNumber" } }

    private var accountIdentityKeys: Set<String> { nativeTicketAccountIdentityKeys(selectedTicket?["RealNameFields"]) }
    private var ticketIdentityContext: String {
        guard pendingBody == nil, receipt == nil, pageVisible, scenePhase == .active, !identityProfileOpen,
              !accountIdentityKeys.isEmpty, let principal = nativeTourismPrincipal(store.session?.accessToken) else { return "" }
        return "\(principal)|\(ticketId)|\(catalogSequence)|\(ticketIdentityRevision)"
    }
    private var ticketIdentityReady: Bool {
        !ticketIdentityContext.isEmpty && ticketIdentityOwner == ticketIdentityContext
            && nativeTicketIdentityBookingEligible(ticketIdentityProfile)
    }
    private var ticketIdentityConfirmation: String? {
        guard ticketIdentityReady,
              let principal = nativeTourismPrincipal(store.session?.accessToken),
              let version = nativeTicketIdentityVersion(ticketIdentityProfile),
              let name = ticketIdentityProfile?["MaskedRealName"] as? String,
              let number = ticketIdentityProfile?["MaskedIdentityNumber"] as? String else { return nil }
        return "\(principal)|\(ticketId)|\(sessionId)|\(catalogSequence)|\(version)|\(name)|\(number)"
    }

    var body: some View {
        Form {
                if let receipt {
                    Section("订单已核对") {
                        Text(resourceName).font(.headline)
                        Text("订单编号：\(receipt["OrderNo"] as? String ?? receipt["Id"] as? String ?? "已生成")")
                        Text("状态：\(nativeTicketBookingReceiptStatus(receipt["Status"] as? String ?? "") ?? "状态待核对")")
                        Text("订单现金金额：¥\(Self.money(receipt["CashPayableAmount"] ?? receipt["Amount"]))")
                        Text(receipt["Status"] as? String == "PendingPayment"
                            ? "可打开“我的 → 门票订单”查看并继续支付。"
                            : "可打开“我的 → 门票订单”查看票券及最新处理进度。")
                        Button("查看我的门票订单") { ticketOrdersOpen = true }
                    }
                } else if loading {
                    Section { ProgressView("正在读取可售门票…") }
                } else if recoveryBlocked {
                    Section("购票请求待核对") {
                        Text(recoveryNotice ?? "为避免重复下单，暂时无法继续购票。请先查看本人门票订单。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("查看我的门票订单") { ticketOrdersOpen = true }
                    }
                } else if tickets.isEmpty && pendingBody == nil && !recoveryBlocked {
                    if let error {
                        Section("门票暂时无法读取") {
                            Text(error)
                            Button("重新查询") { Task { await loadTickets() } }
                        }
                    } else if nextSaleLookupPending {
                        Section("正在确认开售时间") {
                            ProgressView("票种目录已加载，正在查询下一次开售时间。")
                        }
                    } else if let nextSaleLookupError {
                        Section("开售时间暂时无法确认") {
                            Text(nextSaleLookupError)
                            Button("重试") { Task { await loadNextSaleStartTime(sequence: catalogSequence) } }
                        }
                    } else {
                        Section("当前暂无可售门票") {
                            Text(ticketCatalogEmptyMessage())
                            Button("重新查询") { Task { await loadTickets() } }
                            Button("返回景点详情", role: .cancel) { dismiss() }
                        }
                    }
                } else {
                    if let recoveryNotice {
                        Section("上次订单待核对") {
                            Text(recoveryNotice + "可以稍后离开查看门票订单；原请求会加密保留。")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("查看我的门票订单") { ticketOrdersOpen = true }
                        }
                    }
                    if !catalogNotice.isEmpty { Section { Text(catalogNotice).foregroundStyle(.orange) } }
                    NativeTicketSelectionSection(tickets: tickets, sessions: sessions,
                        selectionLocked: pendingBody != nil || submitting, pendingOrder: pendingBody != nil,
                        submitting: submitting, maximumQuantity: maximumQuantity,
                        dailyQuotaRemaining: dailyQuotaRemaining, dailyQuotaLoading: dailyQuotaLoading,
                        dailyQuotaError: dailyQuotaError, formatMoney: Self.money, formatDate: Self.displayDate,
                        onRetryDailyQuota: { dailyQuotaRevision += 1; catalogRevision += 1 },
                        ticketId: $ticketId, sessionId: $sessionId, quantity: $quantity)
                    Section("积分抵扣") {
                        Text("每 100 积分抵 1 元，最多抵订单金额的 50%；仅 CNY 订单可用。")
                            .font(.footnote).foregroundStyle(.secondary)
                        TextField("本次使用积分（默认 0）", text: $pointsToUse)
                            .keyboardType(.numberPad)
                            .disabled(pendingBody != nil || submitting || pointsBalance == nil
                                || pointsDebt != 0 || pointsSummaryError)
                            .onChange(of: pointsToUse) { _, _ in resetRequest() }
                        if let pointsDebt, pointsDebt > 0 {
                            Text("存在积分欠额（\(pointsDebt)），当前不能抵扣；后续奖励将优先抵扣欠额。")
                                .font(.footnote).foregroundStyle(.orange)
                        } else if let pointsBalance, pointsDebt == 0 {
                            Text("可用积分：\(pointsBalance) · 本单最多可用 \(maximumPoints)")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if pointsSummaryError {
                            Text("积分余额暂不可用；可按 0 积分继续购票。")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("重新读取积分余额") { pointsSummaryRevision += 1 }
                        } else if store.session == nil {
                            Text("登录后查看可用积分。")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("正在读取积分余额…").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    NativeTicketAttendeeFormSection(fields: ticketFields, quantity: quantity, attendees: $attendees,
                        accountIdentityKeys: accountIdentityKeys,
                        showsAccountIdentitySection: pendingBody == nil && ticketFields.contains(where: { $0["Type"] as? String == "IdentityNumber" }),
                        identityStatusText: ticketIdentityReady ? (pendingTicketIdentityConfirmation == ticketIdentityConfirmation
                            ? "实名资料已重新核对；请确认下方信息后再次点击提交订单。"
                            : "请核对下方脱敏实名资料，再点击提交订单继续。")
                            : "请先验证绑定手机号、登记本人实名资料并确认当前授权，再继续购票。",
                        identityProfileReady: ticketIdentityReady,
                        identityProfile: ticketIdentityProfile, identityLoading: ticketIdentityLoading,
                        identityError: ticketIdentityError, submitting: submitting, pendingBodyExists: pendingBody != nil,
                        hasIdentityField: hasIdentityField,
                        identityConsent: $identityConsent, onRetryIdentity: { ticketIdentityRevision += 1 },
                        onOpenIdentityProfile: { identityProfileOpen = true }, attendeeBinding: attendeeBinding)
                    if let error {
                        Section {
                            Text(error).foregroundStyle(.red)
                            if pendingBody != nil {
                                Button("查看我的门票订单") { ticketOrdersOpen = true }
                            }
                        }
                    }
                    Section {
                        Button(submitting ? "正在提交…" : pendingBody == nil ? "提交订单" : "按原请求重试 / 核对") {
                            Task { await submitOrder() }
                        }
                        .disabled(submitting || loading || recoveryBlocked || (pendingBody == nil && (selectedSession == nil
                            || (!accountIdentityKeys.isEmpty && !ticketIdentityReady)
                            || dailyQuotaRemaining == nil || maximumQuantity < (selectedTicket?["MinPerOrder"] as? Int ?? 1)
                            || quantity > maximumQuantity)) || (store.session == nil))
                        if store.session == nil {
                            Text("请先在“我的”登录文旅账号后再购票。").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $identityProfileOpen) { NativeIdentityConsentView(store: store) }
            .sheet(isPresented: $ticketOrdersOpen) { NativeTicketOrdersView(store: store) }
            .navigationTitle("购买门票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(pendingBody == nil ? "关闭" : "稍后核对") { dismiss() }.disabled(submitting)
                }
            }
            .task(id: "\(resourceId)-\(catalogRevision)") { await loadTickets() }
            .task(id: dailyQuotaContext) { await loadDailyQuota() }
            .task(id: ticketIdentityContext) { await loadTicketIdentityProfile() }
            .task(id: catalogExpiresAt) {
                guard let deadline = catalogExpiresAt else { return }
                do {
                    while deadline > Date() {
                        try await Task.sleep(nanoseconds: UInt64(max(0.001, min(3600, deadline.timeIntervalSinceNow)) * 1_000_000_000))
                    }
                    expireCatalog(deadline)
                } catch { }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { catalogRevision += 1; pointsSummaryRevision += 1 }
                else {
                    submitSequence += 1; submitting = false
                    catalogSequence += 1; tickets = []; loading = true; catalogExpiresAt = nil
                    if pendingBody == nil { attendees = [[:]]; identityConsent = false; pointsToUse = "0" }
                }
            }
            .onDisappear {
                pageVisible = false; submitSequence += 1; submitting = false
                catalogSequence += 1
                if pendingBody == nil { attendees = [[:]]; identityConsent = false; pointsToUse = "0" }
            }
            .onAppear {
                pageVisible = true
                if bookingOwnerPrincipal == nil { bookingOwnerPrincipal = nativeTourismPrincipal(store.session?.accessToken) }
            }
            .task(id: "\(store.session?.accessToken ?? "")-\(pointsSummaryRevision)") {
                await loadPointsSummary()
            }
            .onChange(of: store.session?.accessToken) { _, newToken in
                submitSequence += 1; submitting = false; receipt = nil
                catalogSequence += 1; catalogRevision += 1
                pointsSummaryRevision += 1
                let newPrincipal = nativeTourismPrincipal(newToken)
                if bookingOwnerPrincipal != newPrincipal {
                    bookingOwnerPrincipal = newPrincipal
                    pointsToUse = "0"; pointsBalance = nil; pointsDebt = nil; pointsSummaryError = false
                    attendees = [[:]]; identityConsent = false; ticketId = ""; sessionId = ""
                    resetRequest()
                }
                guard pendingBody != nil else { return }
                let currentKey = newToken.map { nativeTicketOrderRecoveryStorageKey(accessToken: $0, resourceID: resourceId) } ?? ""
                guard currentKey != recoveryStorageKey else { return }
                pendingBody = nil; pendingExpectedAmountCents = nil; pendingRecoveryData = nil
                idempotencyKey = ""; attendees = [[:]]; identityConsent = false
                ticketId = ""; sessionId = ""
                recoveryBlocked = true
                recoveryNotice = "账号已切换，页面内的购票资料已清除。原请求仍按原账号安全保存，请登录原账号后重新打开此景点核对。"
                error = nil
            }
            .onChange(of: ticketId) { _, _ in ticketChanged() }
            .onChange(of: sessionId) { _, _ in sessionChanged() }
            .onChange(of: quantity) { _, newValue in
                guard pendingBody == nil else { return }
                attendees = Array(attendees.prefix(newValue)) + Array(repeating: [:], count: max(0, newValue - attendees.count))
                pointsToUse = "0"
                resetRequest()
            }
    }

    private func attendeeBinding(_ index: Int, key: String) -> Binding<String> {
        let type = ticketFields.first(where: { $0["Key"] as? String == key })?["Type"] as? String ?? "Text"
        return Binding(get: { attendees.indices.contains(index) ? attendees[index][key] ?? "" : "" }, set: { value in
            guard attendees.indices.contains(index), pendingBody == nil else { return }
            attendees[index][key] = nativeTicketAttendeeInput(value, type: type)
            error = nil
        })
    }

    private func ticketChanged() {
        guard pendingBody == nil else { return }
        if !ticketId.isEmpty && !loading { catalogNotice = "" }
        sessionId = sessions.first?["Id"] as? String ?? ""
        quantity = max(1, selectedTicket?["MinPerOrder"] as? Int ?? 1)
        attendees = Array(repeating: [:], count: max(1, quantity))
        identityConsent = false
        pointsToUse = "0"
        resetRequest()
    }

    private func sessionChanged() {
        guard pendingBody == nil else { return }
        if !sessionId.isEmpty && !loading { catalogNotice = "" }
        let minimum = max(1, selectedTicket?["MinPerOrder"] as? Int ?? 1)
        quantity = max(minimum, min(quantity, maximumQuantity))
        attendees = Array(repeating: [:], count: max(1, quantity))
        identityConsent = false
        pointsToUse = "0"
        resetRequest()
    }

    @MainActor private func loadPointsSummary() async {
        let requestRevision = pointsSummaryRevision
        guard let token = store.session?.accessToken, !token.isEmpty else {
            pointsBalance = nil; pointsDebt = nil; pointsSummaryError = false; pointsToUse = "0"
            return
        }
        pointsBalance = nil; pointsDebt = nil; pointsSummaryError = false
        do {
            guard let summary = try await MobileAPI(store: store).get(
                "/api/JHCTIMemberProgram/GetMySummary", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any],
                  let balance = nativeMemberLedgerString(summary, "PointsBalance").flatMap(Int64.init), balance >= 0,
                  let debt = nativeMemberLedgerString(summary, "PointsDebt").flatMap(Int64.init), debt >= 0,
                  nativeTourismPrincipal(store.session?.accessToken) == nativeTourismPrincipal(token),
                  pointsSummaryRevision == requestRevision else {
                throw MobileAPIError.unavailable("积分摘要无效")
            }
            pointsBalance = debt > 0 ? 0 : balance; pointsDebt = debt; pointsSummaryError = false
            if debt > 0 { pointsToUse = "0"; resetRequest() }
        } catch {
            guard nativeTourismPrincipal(store.session?.accessToken) == nativeTourismPrincipal(token),
                  pointsSummaryRevision == requestRevision else { return }
            pointsBalance = nil; pointsDebt = nil; pointsSummaryError = true
        }
    }

    private func pointsValidationError(_ points: Int64) -> String? {
        guard points >= 0 else { return "积分数量必须为非负整数。" }
        guard points > 0 else { return nil }
        guard !pointsSummaryError, let pointsBalance, let pointsDebt else {
            return "积分余额尚未确认，当前不能使用积分。请重新读取后重试。"
        }
        if pointsDebt > 0 { return "存在积分欠额，当前不能抵扣；后续奖励将优先抵扣欠额。" }
        if points > pointsBalance { return "使用积分超过当前可用余额，请调整后重试。" }
        if points > maximumPoints { return "本次积分超过订单金额 50% 对应上限（\(maximumPoints)）。" }
        return nil
    }

    private func pointsValue(_ value: Any?) -> Int64? {
        if let text = value as? String { return Int64(text) }
        guard let number = value as? NSNumber else { return nil }
        let decimal = number.decimalValue
        guard decimal >= 0, decimal <= Decimal(Int64.max) else { return nil }
        var rounded = Decimal()
        var source = decimal
        NSDecimalRound(&rounded, &source, 0, .down)
        guard rounded == decimal else { return nil }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    private func resetRequest() {
        if pendingBody == nil { idempotencyKey = ""; error = nil }
    }

    private func loadTicketIdentityProfile() async {
        ticketIdentitySequence += 1; let operation = ticketIdentitySequence
        let context = ticketIdentityContext
        ticketIdentityProfile = nil; ticketIdentityOwner = ""; ticketIdentityLoading = false; ticketIdentityError = nil
        guard !context.isEmpty, let principal = nativeTourismPrincipal(store.session?.accessToken) else { return }
        ticketIdentityLoading = true
        func current() -> Bool { !Task.isCancelled && operation == ticketIdentitySequence && ticketIdentityContext == context }
        defer { if operation == ticketIdentitySequence { ticketIdentityLoading = false } }
        do {
            let result = try await MobileAPI(store: store).get("/api/JHCTITourismAuth/GetMyTicketIdentityProfile",
                authenticated: true, expectedPrincipal: principal) as? [String: Any]
            guard current() else { return }
            guard nativeTicketIdentityProfileValid(result) else { throw MobileAPIError.unavailable("账号实名资料状态异常") }
            ticketIdentityProfile = result; ticketIdentityOwner = context
        } catch {
            if current() { ticketIdentityError = "账号实名资料暂时无法确认，请重新核对后继续。" }
        }
    }

    private func loadDailyQuota() async {
        dailyQuotaSequence += 1; let operation = dailyQuotaSequence
        let context = dailyQuotaContext
        dailyQuota = nil; dailyQuotaOwner = ""; dailyQuotaError = nil; dailyQuotaLoading = false
        guard !context.isEmpty, let token = store.session?.accessToken,
              let visitDate = nativeTicketVisitDate(selectedSession?["StartTime"], parseTime: paymentDeadline),
              let limit = selectedTicket?["MaxPerUserPerDay"] as? Int else { return }
        let ticket = ticketId; let session = sessionId
        dailyQuotaLoading = true
        func isCurrent() -> Bool { !Task.isCancelled && operation == dailyQuotaSequence && dailyQuotaContext == context }
        defer { if operation == dailyQuotaSequence { dailyQuotaLoading = false } }
        do {
            let value = try await MobileAPI(store: store).get(
                "/api/JHCTITicket/GetMyDailyQuota?ticketTypeId=\(ticket)&sessionId=\(session)", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any]
            guard isCurrent() else { return }
            guard let remaining = nativeTicketDailyQuotaRemaining(value, ticketID: ticket, sessionID: session,
                visitDate: visitDate, dailyLimit: limit) else { throw MobileAPIError.unavailable("限购额度回执异常") }
            dailyQuota = value; dailyQuotaOwner = context
            let minimum = selectedTicket?["MinPerOrder"] as? Int ?? 1
            if remaining >= minimum && quantity > remaining { quantity = remaining }
        } catch {
            if isCurrent() { dailyQuotaError = "本人限购额度暂时无法确认，请重新查询。" }
        }
    }

    private func expireCatalog(_ deadline: Date, now: Date = Date()) {
        guard !Task.isCancelled, pageVisible, scenePhase == .active,
              catalogExpiresAt == deadline, deadline <= now else { return }
        // 仅在最近停售/开场边界重读一次，原待确认订单资料仍用于原请求恢复。
        catalogExpiresAt = nil; catalogSequence += 1; tickets = []; loading = true; catalogRevision += 1
    }

    private func loadTickets() async {
        catalogSequence += 1; let operation = catalogSequence
        let previousTicketId = ticketId; let previousSessionId = sessionId; let previousQuantity = quantity
        let previousAttendees = attendees; let previousIdentityConsent = identityConsent
        let preserveSelection = catalogLoaded
        let token = store.session?.accessToken
        loading = true; error = nil; catalogNotice = ""; tickets = []; catalogExpiresAt = nil
        nextSaleStartTime = nil; nextSaleLookupPending = false; nextSaleLookupError = nil
        if let token = store.session?.accessToken { restorePendingAttempt(accessToken: token) }
        do {
            let featureState = await MobileAPI(store: store).featureAccessState("F-TKT-002", forceRefresh: true)
            guard operation == catalogSequence,
                  nativeTourismPrincipal(store.session?.accessToken) == nativeTourismPrincipal(token) else { return }
            guard featureState == .open else {
                throw MobileAPIError.unavailable(featureState.message(featureName: "景区门票", action: "请返回景点详情。"))
            }
            let value = try await MobileAPI(store: store).get("/api/JHCTITicket/GetPublicTicketTypes?resourceId=\(resourceId)")
            guard operation == catalogSequence,
                  nativeTourismPrincipal(store.session?.accessToken) == nativeTourismPrincipal(token) else { return }
            guard let rows = value as? [[String: Any]] else { throw MobileAPIError.unavailable("门票目录数据异常，请重新查询。") }
            guard let available = nativeTicketCatalogSnapshot(rows, resourceID: resourceId, now: Date(), parseTime: paymentDeadline) else {
                throw MobileAPIError.unavailable("门票信息暂时无法确认，请重新查询。")
            }
            tickets = available
            catalogExpiresAt = nativeTicketCatalogDeadline(available, parseTime: paymentDeadline)
            if pendingBody == nil, !recoveryBlocked {
                let selection = nativeTicketResumeSelection(tickets, ticketId: previousTicketId, sessionId: previousSessionId,
                    quantity: previousQuantity, preserve: preserveSelection, preferredTicketID: initialTicketTypeID)
                ticketId = selection.ticketId; sessionId = selection.sessionId; quantity = selection.quantity
                if selection.ticketId == previousTicketId, selection.sessionId == previousSessionId,
                   selection.quantity == previousQuantity {
                    attendees = Array(previousAttendees.prefix(quantity))
                        + Array(repeating: [:], count: max(0, quantity - previousAttendees.count))
                    identityConsent = previousIdentityConsent
                } else {
                    attendees = Array(repeating: [:], count: quantity); identityConsent = false
                }
                catalogNotice = selection.notice
            }
            catalogLoaded = true
        } catch {
            if operation == catalogSequence,
               nativeTourismPrincipal(store.session?.accessToken) == nativeTourismPrincipal(token) {
                self.error = error.localizedDescription
            }
        }
        if operation == catalogSequence {
            loading = false
            if error == nil { await loadNextSaleStartTime(sequence: operation) }
        }
    }

    private func loadNextSaleStartTime(sequence: Int) async {
        guard sequence == catalogSequence, pageVisible, scenePhase == .active else { return }
        let requestStartedAt = Date()
        nextSaleLookupPending = true
        nextSaleLookupError = nil
        do {
            let value = try await MobileAPI(store: store).get(
                "/api/JHCTITicket/GetNextPublicSaleStartTime?resourceId=\(resourceId)")
            guard !Task.isCancelled, sequence == catalogSequence, pageVisible,
                  scenePhase == .active else { return }
            if let start = paymentDeadline(value), start > requestStartedAt {
                nextSaleStartTime = start
                if catalogExpiresAt == nil || start < catalogExpiresAt! { catalogExpiresAt = start }
            }
        } catch {
            guard !Task.isCancelled, sequence == catalogSequence, pageVisible else { return }
            nextSaleLookupError = "暂时无法确认下一次开售时间，请检查网络后重试。"
        }
        if sequence == catalogSequence { nextSaleLookupPending = false }
    }

    private func ticketCatalogEmptyMessage() -> String {
        if let nextSaleStartTime {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return "预计 \(formatter.string(from: nextSaleStartTime)) 开售，届时将自动刷新。"
        }
        if admissionType == "Paid" {
            return "该景点实行收费入园，目前暂无可购买的门票。请稍后再来查看。"
        }
        if admissionType == "PaidReservation" {
            return "该景点需预约并收费入园，目前暂无可购买的门票。请稍后再来查看。"
        }
        return "暂时没有可购买的门票，您可以稍后重新查询，或返回景点详情了解开放与预约信息。"
    }

    private func restorePendingAttempt(accessToken: String) {
        let key = nativeTicketOrderRecoveryStorageKey(accessToken: accessToken, resourceID: resourceId)
        recoveryStorageKey = key
        guard !key.isEmpty, store.hasTicketOrderAttempt(for: key) else { return }
        guard let data = store.readTicketOrderAttempt(for: key),
              let attempt = try? JSONDecoder().decode(NativeTicketOrderAttempt.self, from: data),
              attempt.isValid, attempt.resourceID == resourceId,
              let body = (try? JSONSerialization.jsonObject(with: attempt.requestBody)) as? [String: Any],
              pointsValue(body["PointsToUse"]).map({ $0 >= 0 }) == true,
              let lines = body["Lines"] as? [[String: Any]], lines.count == 1, let line = lines.first,
              let ticketId = line["TicketTypeId"] as? String, Int64(ticketId).map({ $0 > 0 }) == true,
              let sessionId = line["SessionId"] as? String, Int64(sessionId).map({ $0 > 0 }) == true,
              let quantity = nativeTicketSnapshotQuantity(line["Quantity"]),
              let savedAttendees = line["Attendees"] as? [[String: String]], savedAttendees.count == quantity else {
            recoveryBlocked = true
            recoveryNotice = "上次购票请求存在但无法安全读取。为避免重复下单，已暂停新购票；请先查看本人门票订单。"
            return
        }
        pendingBody = body; pendingRecoveryData = data; idempotencyKey = attempt.idempotencyKey
        pendingExpectedAmountCents = attempt.expectedAmountCents
        self.ticketId = ticketId; self.sessionId = sessionId; self.quantity = quantity
        attendees = savedAttendees
        identityConsent = body["IdentityConsent"] as? Bool ?? false
        recoveryNotice = "检测到此景点存在尚未确认的购票请求。继续时将复用加密保存的原请求号和购票资料。"
    }

    private func submitOrder() async {
        guard !submitting, !loading, !recoveryBlocked, receipt == nil, pageVisible, scenePhase == .active else { return }
        guard let session = store.session else { error = "请先登录文旅账号后再购票。"; return }
        if pendingBody != nil {
            let currentKey = nativeTicketOrderRecoveryStorageKey(accessToken: session.accessToken, resourceID: resourceId)
            guard !currentKey.isEmpty, currentKey == recoveryStorageKey else {
                pendingBody = nil; pendingExpectedAmountCents = nil; pendingRecoveryData = nil
                idempotencyKey = ""; attendees = [[:]]; identityConsent = false
                ticketId = ""; sessionId = ""; recoveryBlocked = true
                recoveryNotice = "账号已切换，页面内的购票资料已清除。原请求仍按原账号安全保存，请登录原账号后重新打开此景点核对。"
                error = nil
                return
            }
        }
        let request: [String: Any]
        let requestTicketId: String
        let requestSessionId: String
        let requestQuantity: Int
        let requestPoints: Int64
        let expectedCents: Int
        if let pendingBody, let expected = pendingExpectedAmountCents,
           let lines = pendingBody["Lines"] as? [[String: Any]], let line = lines.first,
           let savedTicketId = line["TicketTypeId"] as? String,
           let savedSessionId = line["SessionId"] as? String,
           let savedQuantity = line["Quantity"] as? Int,
           let savedPoints = pointsValue(pendingBody["PointsToUse"]), savedPoints >= 0,
           pendingBody["IdempotencyKey"] as? String == idempotencyKey {
            request = pendingBody; requestTicketId = savedTicketId
            requestSessionId = savedSessionId; requestQuantity = savedQuantity
            requestPoints = savedPoints; expectedCents = expected
        } else {
            guard let ticket = selectedTicket, let selectedSession,
                  let confirmedSessionID = selectedSession["Id"] as? String,
                  confirmedSessionID == sessionId else { error = "请选择有余票的入园场次。"; return }
            let accountKeys = nativeTicketAccountIdentityKeys(ticket["RealNameFields"])
            guard let current = nativeTicketCatalogSnapshot([ticket], resourceID: resourceId, now: Date(), parseTime: paymentDeadline)?.first,
                  let currentSessions = current["Sessions"] as? [[String: Any]],
                  currentSessions.contains(where: { $0["Id"] as? String == confirmedSessionID }) else {
                error = "票种已停售、场次已开始或门票信息已变化，请重新查询后再购票。"; return
            }
            if !accountKeys.isEmpty {
                guard ticketIdentityReady, let currentIdentity = ticketIdentityConfirmation else {
                    error = "账号实名资料暂不可用，请重新核对后继续。"; return
                }
                guard let pendingIdentity = pendingTicketIdentityConfirmation else {
                    pendingTicketIdentityConfirmation = currentIdentity
                    ticketIdentityRevision += 1
                    error = "正在重新核对实名资料；请核对页面显示的脱敏信息后再次点击提交订单。"
                    return
                }
                guard pendingIdentity == currentIdentity else {
                    pendingTicketIdentityConfirmation = currentIdentity
                    ticketIdentityRevision += 1
                    error = "实名资料已变化，请核对更新后的脱敏信息后再次点击提交订单。"
                    return
                }
                pendingTicketIdentityConfirmation = nil
            }
            guard let quota = dailyQuotaRemaining, quantity <= quota else {
                error = "本人剩余限购额度不足或尚未确认，请重新查询限购额度。"; return
            }
            let minimum = max(1, ticket["MinPerOrder"] as? Int ?? 1)
            guard quantity >= minimum, quantity <= maximumQuantity else { error = "当前余票不足或购票数量超出限制。"; return }
            guard accountKeys.isEmpty || ticketIdentityReady else {
                error = "账号实名资料及当前授权尚未确认，请先登记或重新核对实名状态。"; return
            }
            let orderAttendees = nativeTicketAccountAttendees(Array(attendees.prefix(quantity)), keys: accountKeys)
            if let message = nativeTicketAttendeeError(ticket["RealNameFields"], attendees: orderAttendees, quantity: quantity, accountIdentityKeys: accountKeys) {
                error = message; return
            }
            if requiresIdentityConsent && !identityConsent { error = "请先单独同意本次购票实名信息授权。"; return }
            guard let points = Int64(pointsToUse), points >= 0 else {
                error = "积分数量必须为有效非负整数。"; return
            }
            if let pointsError = pointsValidationError(points) { error = pointsError; return }
            idempotencyKey = "ticket-\(UUID().uuidString)"
            let line: [String: Any] = ["TicketTypeId": ticketId, "SessionId": confirmedSessionID,
                "Quantity": quantity, "UseAccountIdentityForFirstAttendee": !accountKeys.isEmpty,
                "Attendees": orderAttendees]
            let body: [String: Any] = ["IdempotencyKey": idempotencyKey, "IdentityConsent": identityConsent,
                "PointsToUse": String(points), "Lines": [line]]
            guard let total = nativeTicketSaleTotalCents(ticket["Price"], quantity: quantity),
                  nativeCartID(ticketId) != nil, nativeCartID(confirmedSessionID) != nil,
                  let cents = Int(exactly: total), let bodyData = try? JSONSerialization.data(withJSONObject: body),
                  let token = store.session?.accessToken else { error = "购票请求数据无效，请重新选择。"; return }
            submitting = true
            let featureState = await MobileAPI(store: store).featureAccessState("F-TKT-002", forceRefresh: true)
            guard !Task.isCancelled, pageVisible, scenePhase == .active,
                  store.session?.accessToken == token, nativeCartID(ticket["Id"]) == ticketId,
                  sessionId == confirmedSessionID else { submitting = false; return }
            submitting = false
            guard featureState == .open else {
                error = featureState.message(featureName: "景区门票", action: "当前未创建新订单。")
                return
            }
            let storageKey = nativeTicketOrderRecoveryStorageKey(accessToken: token, resourceID: resourceId)
            let attempt = NativeTicketOrderAttempt(idempotencyKey: idempotencyKey, resourceID: resourceId,
                expectedAmountCents: cents, requestBody: bodyData)
            guard !storageKey.isEmpty, attempt.isValid,
                  let encodedAttempt = try? JSONEncoder().encode(attempt),
                  store.saveTicketOrderAttempt(encodedAttempt, for: storageKey) else {
                idempotencyKey = ""; recoveryBlocked = true
                error = "无法安全保存或已有待确认购票请求，本次未提交订单。请关闭后重新打开此景点核对。"; return
            }
            recoveryStorageKey = storageKey
            pendingExpectedAmountCents = cents; pendingBody = body; pendingRecoveryData = encodedAttempt; request = body
            requestTicketId = ticketId; requestSessionId = confirmedSessionID
            requestQuantity = quantity; requestPoints = points; expectedCents = cents
        }
        guard let savedData = pendingRecoveryData, store.readTicketOrderAttempt(for: recoveryStorageKey) == savedData,
              let requestKey = request["IdempotencyKey"] as? String else {
            recoveryBlocked = true; error = "购票恢复记录已变化或无法读取，请关闭后重新打开此景点核对。"; return
        }
        let savedKey = recoveryStorageKey
        submitSequence += 1; let operation = submitSequence
        submitting = true; error = nil
        func isCurrent() -> Bool {
            !Task.isCancelled && pageVisible && scenePhase == .active && submitSequence == operation
                && store.session?.accessToken == session.accessToken && recoveryStorageKey == savedKey && pendingRecoveryData == savedData
        }
        defer { if submitSequence == operation { submitting = false } }
        do {
            let result: Any
            do {
                result = try await MobileAPI(store: store).post("/api/JHCTITicket/CreateOrder", body: request, authenticated: true,
                    expectedPrincipal: nativeTourismPrincipal(session.accessToken))
            } catch {
                guard isCurrent() else { return }
                // 请求结果不确定时按原幂等键查询本人订单；不会自动创建第二笔订单。
                result = try await MobileAPI(store: store).get("/api/JHCTITicket/GetMyOrderByIdempotencyKey?idempotencyKey=\(requestKey)", authenticated: true,
                    expectedPrincipal: nativeTourismPrincipal(session.accessToken))
            }
            guard isCurrent() else { return }
            guard let order = result as? [String: Any],
                  nativeTicketBookingReceiptStatus(order["Status"] as? String ?? "") != nil,
                  nativeTicketOrderSnapshotMatches(order, ticketID: requestTicketId, sessionID: requestSessionId,
                      quantity: requestQuantity, expectedCents: Int64(expectedCents), expectedPoints: requestPoints) else {
                throw MobileAPIError.unavailable("订单回执与本次票种、场次或数量不一致。请在门票订单中核对后再操作。")
            }
            guard store.clearTicketOrderAttempt(for: savedKey, expected: savedData) else {
                recoveryBlocked = true
                throw MobileAPIError.unavailable("购票恢复记录已变化或未能清理，请关闭后重新打开此景点核对。")
            }
            receipt = order
            pendingBody = nil
            pendingRecoveryData = nil
            pendingExpectedAmountCents = nil
            recoveryNotice = nil
            recoveryBlocked = false
            idempotencyKey = ""
        } catch {
            if isCurrent() { self.error = "订单结果暂未确认。可按原请求重试或稍后在门票订单中核对；不会更换请求号。\n\(error.localizedDescription)" }
        }
    }

    private static func date(_ value: String) -> Date {
        // WebAPI 统一输出无时区业务时间，按上海时区解释并兼容带偏移的历史响应。
        paymentDeadline(value) ?? .distantPast
    }

    private static func displayDate(_ value: String) -> String {
        let date = date(value); guard date != .distantPast else { return "时间待确认" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func money(_ value: Any?) -> String {
        String(format: "%.2f", (value as? NSNumber)?.doubleValue ?? 0)
    }
}

private func nativeTicketResumeSelection(_ tickets: [[String: Any]], ticketId: String, sessionId: String,
                                       quantity: Int, preserve: Bool, now: Date = Date(), preferredTicketID: String? = nil)
    -> (ticketId: String, sessionId: String, quantity: Int, notice: String) {
    func id(_ item: [String: Any]) -> String {
        guard let text = item["Id"] as? String, let number = Int64(text), number > 0, String(number) == text else { return "" }
        return text
    }
    let ticket: [String: Any]?
    if preserve { ticket = tickets.first { id($0) == ticketId && !ticketId.isEmpty } }
    else if let preferredTicketID, !preferredTicketID.isEmpty {
        ticket = tickets.first { id($0) == preferredTicketID }
    } else { ticket = tickets.first { !id($0).isEmpty } }
    guard let ticket else {
        let notice = preserve && !ticketId.isEmpty ? "原选择票种已不可售，请重新选择票种和场次。"
            : (!(preferredTicketID ?? "").isEmpty ? "搜索中的门票已不可售，请返回景点重新选择。" : "")
        return ("", "", 1, notice)
    }
    let minimum = max(1, ticket["MinPerOrder"] as? Int ?? 1)
    let sessions = nativeTicketSelectableSessions(ticket, minimumQuantity: minimum, now: now, parseTime: paymentDeadline)
        .filter { !id($0).isEmpty }
    let session = preserve ? sessions.first { id($0) == sessionId && !sessionId.isEmpty } : sessions.first
    guard let session else {
        let notice = preserve && !sessionId.isEmpty ? "原选择入园场次已不可售，请重新选择场次。"
            : (!(preferredTicketID ?? "").isEmpty ? "搜索中的门票暂无可预约场次，请返回景点重新选择。" : "")
        return (id(ticket), "", minimum, notice)
    }
    let maximum = min(ticket["MaxPerOrder"] as? Int ?? minimum, session["RemainingInventory"] as? Int ?? minimum)
    return (id(ticket), id(session), preserve ? max(minimum, min(quantity, maximum)) : minimum, "")
}

private func nativeTicketSelectableSessions(_ ticket: [String: Any]?, minimumQuantity: Int, now: Date = Date(),
                                            parseTime: (String) -> Date? = { paymentDeadline($0) }) -> [[String: Any]] {
    (ticket?["Sessions"] as? [[String: Any]] ?? []).filter { session in
        session["IsEnabled"] as? Bool == true
            && (session["RemainingInventory"] as? Int ?? 0) >= minimumQuantity
            && parseTime(session["StartTime"] as? String ?? "").map { $0 > now } == true
    }
}

func nativeTourismReservationStatus(_ status: String, expired: Bool) -> String {
    if status == "Reserved" && expired { return "已过期" }
    return ["Reserved": "已预约", "CheckedIn": "已入园", "Cancelled": "已取消"][status] ?? "状态待核对"
}
