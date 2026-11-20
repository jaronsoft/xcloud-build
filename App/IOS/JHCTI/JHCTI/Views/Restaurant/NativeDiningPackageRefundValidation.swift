import Foundation
import CoreFoundation

private let nativeDiningPackageRefundStatuses: Set<String> = ["Requested", "Processing", "Refunded", "Rejected", "Failed"]
private struct NativeDiningPackageInvalidRefundField {}
private let nativeDiningPackageInvalidRefundField = NativeDiningPackageInvalidRefundField()

func validatedDiningPackageRefunds(_ value: Any?, expectedOrderID: String) -> [[String: Any]]? {
    func validID(_ value: Any?) -> String? {
        guard let id = value as? String, id.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
              Int64(id).map({ $0 > 0 }) == true else { return nil }
        return id
    }
    guard validID(expectedOrderID) != nil, let rows = value as? [[String: Any]], rows.count <= 100 else { return nil }

    func equal(_ left: Any, _ right: Any) -> Bool {
        if left is NSNull, right is NSNull { return true }
        if let left = left as? String, let right = right as? String { return left == right }
        if let left = left as? NSNumber, let right = right as? NSNumber {
            let leftBoolean = CFGetTypeID(left) == CFBooleanGetTypeID()
            let rightBoolean = CFGetTypeID(right) == CFBooleanGetTypeID()
            if leftBoolean || rightBoolean { return leftBoolean && rightBoolean && left.boolValue == right.boolValue }
            return left.decimalValue == right.decimalValue
        }
        return false
    }
    func field(_ source: [String: Any], _ name: String) -> (Bool, Any?) {
        let camelName = String(name.prefix(1)).lowercased() + String(name.dropFirst())
        let keys = [name, camelName].filter { source.keys.contains($0) }
        guard let firstKey = keys.first else { return (false, nil) }
        let first = source[firstKey]
        guard keys.dropFirst().allSatisfy({ equal(first, source[$0]!) }) else { return (true, nativeDiningPackageInvalidRefundField) }
        return (true, first)
    }
    func text(_ source: [String: Any], _ name: String, required: Bool = true) -> String? {
        let (present, raw) = field(source, name)
        if !present || raw is NSNull { return required ? nil : "" }
        guard let value = raw as? String,
              !required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
    func validDate(_ source: [String: Any], _ name: String, required: Bool) -> String? {
        guard let value = text(source, name, required: required) else { return nil }
        if value.isEmpty { return required ? nil : "" }
        return nativeBusinessTimestamp(value) == nil ? nil : value
    }

    var ids = Set<String>()
    var result: [[String: Any]] = []
    for row in rows {
        guard let id = validID(field(row, "Id").1), let orderID = validID(field(row, "OrderId").1),
              orderID == expectedOrderID,
              let orderNo = text(row, "OrderNo"), let packageName = text(row, "PackageName"),
              let refundNo = text(row, "RefundNo"),
              let count = field(row, "CredentialCount").1 as? NSNumber, CFGetTypeID(count) != CFBooleanGetTypeID(),
              count.doubleValue.isFinite, count.doubleValue.rounded(.towardZero) == count.doubleValue,
              count.doubleValue > 0, count.doubleValue <= Double(Int32.max),
              let amount = field(row, "Amount").1 as? NSNumber, CFGetTypeID(amount) != CFBooleanGetTypeID(),
              nativeMoneyCents(amount) != nil, amount.decimalValue > 0,
              let status = text(row, "Status"), nativeDiningPackageRefundStatuses.contains(status),
              let reason = text(row, "Reason"),
              let decisionReason = text(row, "DecisionReason", required: false),
              let createdAt = validDate(row, "CreateTime", required: true),
              let reviewedAt = validDate(row, "ReviewedAt", required: false),
              let refundedAt = validDate(row, "RefundedAt", required: false),
              ids.insert(id).inserted else { return nil }
        result.append([
            "Id": id, "OrderId": orderID, "OrderNo": orderNo, "PackageName": packageName,
            "RefundNo": refundNo, "CredentialCount": count.intValue, "Amount": amount,
            "Status": status, "Reason": reason, "DecisionReason": decisionReason,
            "CreateTime": createdAt, "ReviewedAt": reviewedAt.isEmpty ? NSNull() : reviewedAt as Any,
            "RefundedAt": refundedAt.isEmpty ? NSNull() : refundedAt as Any,
        ])
    }
    return result
}
