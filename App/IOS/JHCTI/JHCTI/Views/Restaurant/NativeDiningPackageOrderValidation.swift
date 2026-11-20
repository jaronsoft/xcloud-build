import Foundation
import CoreFoundation

private struct NativeDiningPackageInvalidField {}
private let nativeDiningPackageInvalidField = NativeDiningPackageInvalidField()

func validatedDiningPackageOrderPage(_ value: Any?, page expectedPage: Int, pageSize: Int) -> (rows: [[String: Any]], total: Int)? {
    func field(_ source: [String: Any], _ name: String) -> (Bool, Any?) {
        let camel = String(name.prefix(1)).lowercased() + String(name.dropFirst())
        let keys = [name, camel].filter { source.keys.contains($0) }
        guard let firstKey = keys.first else { return (false, nil) }
        let first = source[firstKey]
        guard keys.dropFirst().allSatisfy({ key in
            guard let left = try? JSONSerialization.data(withJSONObject: [first], options: [.sortedKeys]),
                  let right = try? JSONSerialization.data(withJSONObject: [source[key]!], options: [.sortedKeys]) else { return false }
            return left == right
        }) else { return (true, nativeDiningPackageInvalidField) }
        return (true, first)
    }
    func id(_ value: Any?) -> String? {
        guard let id = value as? String, id.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
              Int64(id).map({ $0 > 0 }) == true else { return nil }
        return id
    }
    func text(_ source: [String: Any], _ name: String, required: Bool = true) -> String? {
        let (present, raw) = field(source, name)
        if !present || raw is NSNull { return required ? nil : "" }
        guard let result = raw as? String,
              !required || !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return result
    }
    func integer(_ source: [String: Any], _ name: String, min: Int, max: Int) -> Int? {
        guard let number = field(source, name).1 as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue >= Double(min), number.doubleValue <= Double(max) else { return nil }
        return number.intValue
    }
    func money(_ source: [String: Any], _ name: String, positive: Bool = false) -> Decimal? {
        guard let number = field(source, name).1 as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        var amount = number.decimalValue
        var rounded = Decimal()
        NSDecimalRound(&rounded, &amount, 2, .plain)
        guard amount >= 0, amount <= Decimal(999_999_999), (!positive || amount > 0), amount == rounded else { return nil }
        return amount
    }
    func date(_ source: [String: Any], _ name: String, required: Bool) -> String? {
        guard let result = text(source, name, required: required) else { return nil }
        if result.isEmpty { return required ? nil : "" }
        return nativeBusinessTimestamp(result) == nil ? nil : result
    }
    func array(_ source: [String: Any], _ name: String) -> [[String: Any]]? {
        let (present, raw) = field(source, name)
        guard present, let result = raw as? [[String: Any]] else { return nil }
        return result
    }
    func boolean(_ source: [String: Any], _ name: String) -> Bool? {
        guard let number = field(source, name).1 as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    func validOrder(_ order: [String: Any]) -> Bool {
        guard id(field(order, "Id").1) != nil, id(field(order, "PackageId").1) != nil,
              let storeID = id(field(order, "StoreId").1), text(order, "PackageName") != nil,
              text(order, "OrderNo") != nil,
              let unit = money(order, "UnitPrice", positive: true), let amount = money(order, "Amount"),
              let quantity = integer(order, "Quantity", min: 1, max: 10), unit * Decimal(quantity) == amount,
              let currency = text(order, "Currency"), let pointsText = text(order, "PointsUsed"),
              pointsText.range(of: "^(0|[1-9][0-9]*)$", options: .regularExpression) != nil,
              let points = Decimal(string: pointsText), let discount = money(order, "PointsDiscountAmount"),
              let cash = money(order, "CashPayableAmount"), discount + cash == amount,
              discount * 100 == points, discount * 2 <= amount,
              currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "CNY" || (points == 0 && discount == 0),
              let status = text(order, "Status"), ["PendingPayment", "Paid", "Closed", "Refunded"].contains(status),
              boolean(order, "HasUnavailablePayment") != nil,
              boolean(order, "HasUnmatchedPayment") != nil,
              date(order, "PaymentExpiresAt", required: true) != nil,
              let paidAt = date(order, "PaidAt", required: false),
              let items = array(order, "Items"), let credentials = array(order, "Credentials") else { return false }
        if !paidAt.isEmpty && nativeBusinessTimestamp(paidAt) == nil { return false }
        let paymentStatuses: Set<String> = ["Creating", "RequiresAction", "Processing", "Unknown", "Paid", "PaidUnmatched", "Failed", "Closed"]
        for name in ["PaymentStatus", "ActivePaymentStatus"] {
            guard let state = text(order, name, required: false), state.isEmpty || paymentStatuses.contains(state) else { return false }
        }
        for name in ["ActivePaymentProvider", "ActivePaymentScene"] where text(order, name, required: false) == nil { return false }
        var itemIDs = Set<String>()
        for item in items {
            guard let itemID = id(field(item, "Id").1), itemIDs.insert(itemID).inserted,
                  let itemName = text(item, "ItemName"), itemName.count <= 200,
                  text(item, "Specification", required: false) != nil,
                  integer(item, "Quantity", min: 1, max: 10_000) != nil,
                  integer(item, "SortOrder", min: Int.min, max: Int.max) != nil else { return false }
        }
        var credentialIDs = Set<String>()
        let states: Set<String> = ["Active", "RefundPending", "Redeemed", "Refunded"]
        for credential in credentials {
            guard let credentialID = id(field(credential, "Id").1), credentialIDs.insert(credentialID).inserted,
                  let code = text(credential, "Code"), code.count <= 200,
                  id(field(credential, "StoreId").1) == storeID,
                  let state = text(credential, "Status"), states.contains(state),
                  let start = date(credential, "ValidFrom", required: true),
                  let end = date(credential, "ValidUntil", required: true),
                  let startDate = nativeBusinessTimestamp(start), let endDate = nativeBusinessTimestamp(end), endDate >= startDate,
                  let redeemedAt = date(credential, "RedeemedAt", required: false),
                  redeemedAt.isEmpty || nativeBusinessTimestamp(redeemedAt) != nil else { return false }
        }
        return credentials.isEmpty || credentials.count == quantity
    }
    func integer(_ source: [String: Any], keys: [String], min: Int) -> Int? {
        let values = keys.filter { source.keys.contains($0) }.map { source[$0]! }
        guard !values.isEmpty else { return nil }
        let parsed = values.map { raw -> Int? in
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
                  number.doubleValue >= Double(min), number.doubleValue <= Double(Int.max) else { return nil }
            return number.intValue
        }
        guard let first = parsed.first ?? nil, parsed.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
    guard expectedPage > 0, pageSize > 0, let envelope = value as? [String: Any] else { return nil }
    let rowKeys = ["Items", "items", "List", "list", "Data", "data"].filter { envelope.keys.contains($0) }
    guard let firstKey = rowKeys.first, let rows = envelope[firstKey] as? [[String: Any]],
          rowKeys.dropFirst().allSatisfy({ key in
              guard let lhs = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                    let rhs = try? JSONSerialization.data(withJSONObject: envelope[key]!, options: [.sortedKeys]) else { return false }
              return lhs == rhs
          }),
          integer(envelope, keys: ["Page", "page"], min: 1) == expectedPage,
          integer(envelope, keys: ["PageSize", "pageSize"], min: 1) == pageSize,
          let total = integer(envelope, keys: ["DataCount", "dataCount", "Total", "total"], min: 0),
          let pageCount = integer(envelope, keys: ["PageCount", "pageCount"], min: 0),
          Int64(pageCount) == (Int64(total) + Int64(pageSize) - 1) / Int64(pageSize),
          expectedPage <= max(1, pageCount),
          Int64(expectedPage - 1) <= Int64.max / Int64(pageSize),
          Int64(expectedPage - 1) * Int64(pageSize) <= Int64(Int.max),
          rows.count == min(pageSize, max(0, total - Int(Int64(expectedPage - 1) * Int64(pageSize)))) else { return nil }
    var orderIDs = Set<String>()
    guard rows.allSatisfy({ row in
        guard let orderID = id(field(row, "Id").1) else { return false }
        return orderIDs.insert(orderID).inserted && validOrder(row)
    }) else { return nil }
    return (rows, total)
}
