import Foundation
import CoreFoundation

func nativeReportExpectedRows(page: Int, total: Int, pageSize: Int) -> Int? {
    guard page > 0, total >= 0, pageSize > 0 else { return nil }
    let offset = (page - 1).multipliedReportingOverflow(by: pageSize)
    guard !offset.overflow, page <= max(1, total / pageSize + (total % pageSize == 0 ? 0 : 1)) else { return nil }
    return min(pageSize, max(0, total - offset.partialValue))
}

/** 校验商户报表页的分页元数据和完整行数，避免异常回执显示成有效汇总。 */
func nativeMerchantReportPage(_ response: [String: Any], page: Int, pageSize: Int) -> [String: Any]? {
    guard page > 0, pageSize > 0 else { return nil }
    let envelopes = ["Data", "data"].compactMap { response[$0] }
    let objects = envelopes.compactMap { $0 as? [String: Any] }
    guard envelopes.isEmpty || objects.count == envelopes.count else { return nil }
    if objects.count > 1 {
        guard let first = try? JSONSerialization.data(withJSONObject: objects[0], options: [.sortedKeys, .fragmentsAllowed]),
              objects.dropFirst().allSatisfy({ candidate in
                  guard let data = try? JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys, .fragmentsAllowed]) else { return false }
                  return data == first
              }) else { return nil }
    }
    let data = objects.first ?? response
    func integer(_ value: Any?, allowZero: Bool) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue >= (allowZero ? 0 : 1), number.doubleValue <= Double(Int32.max) else { return nil }
        return number.intValue
    }
    func consistent(_ names: [String], allowZero: Bool) -> Int? {
        let values = names.compactMap { data[$0] }
        guard let first = values.first, let parsed = integer(first, allowZero: allowZero),
              values.dropFirst().allSatisfy({ integer($0, allowZero: allowZero) == parsed }) else { return nil }
        return parsed
    }
    guard consistent(["Page", "page"], allowZero: false) == page,
          consistent(["PageSize", "pageSize"], allowZero: false) == pageSize,
          let total = consistent(["Total", "total"], allowZero: true) else { return nil }
    let rawRows = ["Items", "items"].compactMap { data[$0] }
    guard !rawRows.isEmpty, let rows = rawRows.first as? [[String: Any]],
          rawRows.count == rawRows.compactMap({ $0 as? [[String: Any]] }).count else { return nil }
    if rawRows.count > 1 {
        guard let first = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .fragmentsAllowed]),
              rawRows.dropFirst().allSatisfy({ candidate in
                  guard let value = candidate as? [[String: Any]],
                        let encoded = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]) else { return false }
                  return encoded == first
              }) else { return nil }
    }
    guard let expectedRows = nativeReportExpectedRows(page: page, total: total, pageSize: pageSize),
          rows.count == expectedRows else { return nil }
    return data
}
