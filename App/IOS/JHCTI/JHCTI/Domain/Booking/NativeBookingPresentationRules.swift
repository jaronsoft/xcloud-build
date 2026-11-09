import Foundation

func paymentDeadline(_ value: Any?) -> Date? {
    guard let text = value as? String else { return nil }
    return nativeBusinessDateTime(text)
}


// 采用发起请求时的订单截止快照，拒绝网络回执抵达后已过期或无法确认的支付跳转。
func requireNativePaymentLaunchDeadline(_ value: Any?, now: Date = Date()) throws {
    guard let deadline = nativeBusinessTimestamp(value) else {
        throw MobileAPIError.unavailable("支付期限暂无法确认，本次未打开支付渠道，请查询订单状态。")
    }
    guard deadline > now else {
        throw MobileAPIError.unavailable("支付期限已到，本次未打开支付渠道，请查询订单状态。")
    }
}

func bookingBusinessDateTime(_ value: Any?) -> String? {
    guard let text = value as? String, !text.isEmpty else { return nil }
    let iso = ISO8601DateFormatter()
    for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
        iso.formatOptions = options
        if let date = iso.date(from: text) {
            let output = DateFormatter()
            output.locale = Locale(identifier: "en_US_POSIX")
            output.timeZone = TimeZone(identifier: "Asia/Shanghai")
            output.dateFormat = "yyyy-MM-dd HH:mm"
            return output.string(from: date)
        }
    }
    let local = DateFormatter()
    local.locale = Locale(identifier: "en_US_POSIX")
    local.timeZone = TimeZone(identifier: "Asia/Shanghai")
    for pattern in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
        local.dateFormat = pattern
        if let date = local.date(from: text) {
            let output = DateFormatter()
            output.locale = Locale(identifier: "en_US_POSIX")
            output.timeZone = TimeZone(identifier: "Asia/Shanghai")
            output.dateFormat = "yyyy-MM-dd HH:mm"
            return output.string(from: date)
        }
    }
    return nil
}

func bookingCancellationRule(_ order: [String: Any], kind: String) -> String? {
    let status = order["Status"] as? String ?? ""
    guard ["PendingPayment", "Paid"].contains(status) else { return nil }
    let mode = order["CancellationMode"] as? String ?? "ManualReview"
    let freeMode = kind == "hotel" ? "FreeBeforeCheckIn" : "FreeBeforeDeparture"
    if mode != freeMode {
        return status == "PendingPayment"
            ? "支付后取消需提交申请，由平台审核；审核通过后按原支付渠道退款。"
            : "此订单取消需提交申请，由平台审核；审核通过后按原支付渠道退款。"
    }
    guard let deadline = bookingBusinessDateTime(order["FreeCancellationDeadline"]) else {
        return "免费取消截止时间待确认；取消资格以服务端核验结果为准。"
    }
    if status == "PendingPayment" {
        return kind == "hotel"
            ? "免费取消截止：\(deadline)前；支付后期限内提交按原支付渠道退款，逾期转平台审核。"
            : "支付后取消规则：免费取消截止时间为 \(deadline)；期限内可按原支付渠道退款，逾期提交平台审核。"
    }
    if order["IsFreeCancellationAvailable"] as? Bool == true {
        return "免费取消截止：\(deadline)前；期限内提交按原支付渠道退款，逾期转平台审核。"
    }
    if order["IsFreeCancellationAvailable"] as? Bool == false {
        return "免费取消期限已过（\(deadline)）；提交后由平台审核，不会自动退款。"
    }
    return "免费取消截止：\(deadline)；当前资格待确认，取消方式以服务端核验为准。"
}

func bookingOrderListNotices(_ order: [String: Any], kind: String) -> [String] {
    let status = order["Status"] as? String ?? ""
    let payment = order["PaymentStatus"] as? String ?? ""
    var notices: [String] = []
    if order["HasUnmatchedPayment"] as? Bool == true || payment == "PaidUnmatched" || status == "PaymentReview" {
        notices.append("渠道已反馈收款，但订单需要平台核对。请勿再次付款或提交取消操作，请刷新订单或联系客服核对。")
    }
    if order["HasUnavailablePayment"] as? Bool == true {
        notices.append("订单金额或支付关联异常，暂不能支付、关闭或取消。为避免重复扣款或错误退款，请联系客服核对。")
    }
    if payment == "ConflictingStatus" { notices.append("支付状态信息不一致，请查询订单状态后再继续操作。") }
    if status == "Paid", payment != "Paid", payment != "ConflictingStatus",
       order["HasUnavailablePayment"] as? Bool != true, order["HasUnmatchedPayment"] as? Bool != true {
        notices.append("订单支付状态暂未确认。为避免错误退款，请刷新订单或联系客服核对；当前不能申请取消。")
    }
    if status == "PendingPayment", ["Creating", "Unknown", "Processing"].contains(payment),
       order["HasUnmatchedPayment"] as? Bool != true {
        notices.append("原支付结果尚未确认。查询会继续使用原支付单，不会新建第二笔支付；确认前请勿重复付款，也不能关闭订单释放\(kind == "hotel" ? "预留房间" : "班期名额")。")
    }
    if status == "PendingPayment", payment == "RequiresAction", order["HasUnmatchedPayment"] as? Bool != true {
        notices.append("原支付单仍可继续操作，当前不能关闭订单或释放\(kind == "hotel" ? "预留房间" : "班期名额")。")
    }
    if status == "PendingPayment", ["Paid", "Failed", "Closed"].contains(payment),
       order["HasUnmatchedPayment"] as? Bool != true {
        notices.append("支付流水状态与待支付订单不一致，请刷新核对或联系客服；请勿重复付款或关闭订单。")
    }
    if status == "PendingPayment", let expiresAt = bookingBusinessDateTime(order["PaymentExpiresAt"]) {
        notices.append("支付截止时间：\(expiresAt)；逾期未支付将自动关闭订单并释放\(kind == "hotel" ? "预留房间" : "预留名额")。")
    }
    if status == "CancellationReview" { notices.append("平台正在审核取消申请，请勿重复提交；审核期间\(kind == "hotel" ? "房间" : "班期名额")仍为您保留。") }
    if ["Paid", "RefundProcessing", "Refunded"].contains(status),
       let remark = order["CancellationReviewRemark"] as? String, !remark.isEmpty {
        notices.append("取消审核意见：\(remark)")
    }
    return notices
}


func normalizedNativeBookingPaymentStatus(_ order: [String: Any]) -> [String: Any] {
    var normalized = order
    let pascalCase = order["PaymentStatus"]
    let camelCase = order["paymentStatus"]
    if let pascalCase, let camelCase {
        let valuesMatch: Bool
        if pascalCase is NSNull, camelCase is NSNull {
            valuesMatch = true
        } else if let pascalStatus = pascalCase as? String, let camelStatus = camelCase as? String {
            valuesMatch = pascalStatus == camelStatus
        } else {
            valuesMatch = false
        }
        if !valuesMatch { normalized["PaymentStatus"] = "ConflictingStatus" }
    } else if pascalCase == nil, let camelCase {
        normalized["PaymentStatus"] = camelCase
    }
    return normalized
}
