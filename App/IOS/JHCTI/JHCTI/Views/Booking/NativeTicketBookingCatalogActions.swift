import Foundation

@MainActor
extension NativeTicketBookingView {
    func expireCatalog(_ deadline: Date, now: Date = Date()) {
        guard !Task.isCancelled, pageVisible, scenePhase == .active,
              catalogExpiresAt == deadline, deadline <= now else { return }
        // 仅在最近停售或开场边界重读目录，待确认订单仍保留原请求恢复资料。
        catalogExpiresAt = nil; catalogSequence += 1; tickets = []; loading = true; catalogRevision += 1
    }

    func loadTickets() async {
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

    func loadNextSaleStartTime(sequence: Int) async {
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

    func ticketCatalogEmptyMessage() -> String {
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
}
