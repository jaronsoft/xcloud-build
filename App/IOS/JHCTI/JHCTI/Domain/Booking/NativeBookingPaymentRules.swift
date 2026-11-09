import Foundation
import CoreFoundation

func maximumPointsForHalfAmount(_ amount: Double) -> Int64 {
    guard amount.isFinite, amount > 0 else { return 0 }
    let cents = NSDecimalNumber(value: amount).multiplying(by: NSDecimalNumber(value: 100))
    let wholeCents = cents.rounding(accordingToBehavior: NSDecimalNumberHandler(
        roundingMode: .plain, scale: 0, raiseOnExactness: false,
        raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false))
    let halfPoints = wholeCents.dividing(by: NSDecimalNumber(value: 2))
    let wholePoints = halfPoints.rounding(accordingToBehavior: NSDecimalNumberHandler(
        roundingMode: .down, scale: 0, raiseOnExactness: false,
        raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false))
    let maximum = NSDecimalNumber(value: Int64.max)
    return wholePoints.compare(maximum) == .orderedDescending ? Int64.max : wholePoints.int64Value
}

func nativeMoneyCents(_ value: Any?, roundToCents: Bool = false) -> Int64? {
    let amount: Decimal?
    if let text = value as? String {
        amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    } else if let number = value as? NSNumber {
        amount = number.decimalValue
    } else {
        amount = nil
    }
    guard let amount, amount >= 0, amount <= Decimal(999_999_999) else { return nil }
    let scaled = amount * Decimal(100)
    var rounded = Decimal()
    var source = scaled
    NSDecimalRound(&rounded, &source, 0, .plain)
    guard (roundToCents || rounded == scaled), rounded <= Decimal(Int64.max) else { return nil }
    return NSDecimalNumber(decimal: rounded).int64Value
}

func nativeAlipayPaymentApprovalURL(_ payment: [String: Any], expectedCashCents: Int64?, expectedCurrency: String) -> URL? {
    guard let expectedCashCents, !expectedCurrency.isEmpty,
          let paymentRecordID = payment["PaymentRecordId"] as? String,
          paymentRecordID.range(of: "^[1-9][0-9]*$", options: .regularExpression) != nil,
          Int64(paymentRecordID).map({ $0 > 0 }) == true,
          (payment["Provider"] as? String)?.lowercased() == "alipay",
          payment["Status"] as? String == "RequiresAction",
          let currency = payment["Currency"] as? String,
          currency.caseInsensitiveCompare(expectedCurrency) == .orderedSame,
          let amount = payment["Amount"] as? NSNumber,
          CFGetTypeID(amount) != CFBooleanGetTypeID(),
          nativeMoneyCents(amount) == expectedCashCents,
          let merchantOrderNo = payment["MerchantOrderNo"] as? String,
          !merchantOrderNo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let rawURL = payment["ApprovalUrl"] as? String,
          let url = URL(string: rawURL), url.scheme?.lowercased() == "https",
          let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
    return url
}

func nativeTravelRouteOrderAmount(_ rawPrice: Any?, guestCount: Int) -> Double? {
    guard let number = rawPrice as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    guard (1...20).contains(guestCount),
          let unitPriceCents = nativeMoneyCents(number), (1...9_999_999_999).contains(unitPriceCents) else { return nil }
    let totalCents = unitPriceCents * Int64(guestCount)
    guard (1...99_999_999_900).contains(totalCents) else { return nil }
    return Double(totalCents) / 100
}

func nativeBookingReceiptIntegerMatches(_ raw: Any?, expected: Int) -> Bool {
    guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
    let value = number.doubleValue
    return value.isFinite && value.rounded(.towardZero) == value && value == Double(expected)
}

// 恢复快照仅保存酒店预订参数，不保存联系人姓名或电话。
func nativeHotelOrderRecoverySnapshotMatches(_ order: [String: Any], snapshotText: String?) -> Bool {
    guard let snapshotText, let data = snapshotText.data(using: .utf8),
          let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let hotelID = snapshot["HotelId"] as? String, !hotelID.isEmpty,
          let roomTypeID = snapshot["RoomTypeId"] as? String, !roomTypeID.isEmpty,
          let checkIn = snapshot["CheckIn"] as? String,
          let checkOut = snapshot["CheckOut"] as? String,
          let roomCount = nativeBookingSnapshotInteger(snapshot["RoomCount"], range: 1...10),
          let guestCount = nativeBookingSnapshotInteger(snapshot["GuestCount"], range: 1...20),
          let pointsText = snapshot["PointsToUse"] as? String,
          let points = Int64(pointsText), points >= 0,
          let amountCentsText = snapshot["AmountCents"] as? String,
          let amountCents = Int64(amountCentsText), amountCents >= 0 else { return false }
    return order["HotelId"] as? String == hotelID
        && order["RoomTypeId"] as? String == roomTypeID
        && String(((order["CheckIn"] as? String) ?? "").prefix(10)) == checkIn
        && String(((order["CheckOut"] as? String) ?? "").prefix(10)) == checkOut
        && nativeBookingReceiptIntegerMatches(order["RoomCount"], expected: roomCount)
        && nativeBookingReceiptIntegerMatches(order["GuestCount"], expected: guestCount)
        && nativePointsOrderSnapshotMatches(order, expectedPoints: points, expectedAmountCents: amountCents)
}

// 线路恢复快照仅保存预订选择和金额，不保存同行人资料。
func nativeTravelRouteOrderRecoverySnapshotMatches(_ order: [String: Any], snapshotText: String?) -> Bool {
    guard let snapshotText, let data = snapshotText.data(using: .utf8),
          let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let routeID = snapshot["RouteId"] as? String,
          routeID.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
          let routeIDValue = Int64(routeID), routeIDValue > 0,
          let sessionID = snapshot["SessionId"] as? String,
          sessionID.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
          let sessionIDValue = Int64(sessionID), sessionIDValue > 0,
          let guestCount = nativeBookingSnapshotInteger(snapshot["GuestCount"], range: 1...20),
          let pointsText = snapshot["PointsToUse"] as? String,
          let points = Int64(pointsText), points >= 0,
          let amountCentsText = snapshot["AmountCents"] as? String,
          let amountCents = Int64(amountCentsText), amountCents >= 0 else { return false }
    return order["RouteId"] as? String == routeID
        && order["SessionId"] as? String == sessionID
        && nativeBookingReceiptIntegerMatches(order["GuestCount"], expected: guestCount)
        && nativePointsOrderSnapshotMatches(order, expectedPoints: points, expectedAmountCents: amountCents)
}

func nativeBookingSnapshotInteger(_ raw: Any?, range: ClosedRange<Int>) -> Int? {
    guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let value = number.doubleValue
    guard value.isFinite, value.rounded(.towardZero) == value,
          value >= Double(range.lowerBound), value <= Double(range.upperBound) else { return nil }
    return Int(value)
}

// 原生下单与幂等恢复共用金额快照门禁，确保积分抵扣、现金应付和订单金额在分币精度内闭合。
func nativePointsOrderSnapshotMatches(
    _ order: [String: Any], expectedPoints: Int64? = nil, expectedAmountCents: Int64? = nil
) -> Bool {
    guard order["Currency"] as? String == "CNY",
          let points = (order["PointsUsed"] as? String).flatMap(Int64.init), points >= 0,
          expectedPoints == nil || expectedPoints == points,
          let amount = nativeMoneyCents(order["Amount"]),
          let discount = nativeMoneyCents(order["PointsDiscountAmount"]),
          let cash = nativeMoneyCents(order["CashPayableAmount"]),
          expectedAmountCents == nil || expectedAmountCents == amount,
          discount == points, amount >= discount else { return false }
    return amount - discount == cash
}

// 幂等请求可能返回已支付、已出票或退款后的原订单，恢复时不能要求仍为待付款。
func nativeTicketBookingReceiptStatus(_ status: String) -> String? {
    switch status {
    case "PendingPayment": return "待付款"
    case "PaidPendingIssue": return "已支付，待出票"
    case "Issued": return "已出票"
    case "Closed": return "已关闭"
    case "PaidIssueFailed": return "已支付，出票待处理"
    case "PartiallyRefunded": return "部分已退款"
    case "Refunded": return "已退款"
    default: return nil
    }
}
