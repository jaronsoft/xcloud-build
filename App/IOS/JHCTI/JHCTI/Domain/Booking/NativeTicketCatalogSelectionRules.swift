import Foundation

// 将票种恢复选择与可售场次筛选集中在领域规则中，供预订页面和目录状态共用。
func nativeTicketResumeSelection(_ tickets: [[String: Any]], ticketId: String, sessionId: String,
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

func nativeTicketSelectableSessions(_ ticket: [String: Any]?, minimumQuantity: Int, now: Date = Date(),
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
