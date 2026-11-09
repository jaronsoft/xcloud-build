import CoreFoundation
import Foundation

func nativeDiningQueuePage(_ response: [String: Any], page: Int, pageSize: Int,
                                   sessionID: String, storeID: String, queueDate: String) -> (rows: [[String: Any]], total: Int)? {
    guard page > 0, pageSize > 0, !sessionID.isEmpty, !storeID.isEmpty else { return nil }
    let rowValues = ["Items", "items", "List", "list", "Data", "data"].compactMap { response[$0] }
    guard !rowValues.isEmpty else { return nil }
    var candidates: [[[String: Any]]] = []
    for value in rowValues {
        guard let rows = value as? [[String: Any]], rows.count <= pageSize else { return nil }
        candidates.append(rows)
    }
    guard let rows = candidates.first,
          let firstData = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]) else { return nil }
    for candidate in candidates.dropFirst() {
        guard let candidateData = try? JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys]),
              firstData == candidateData else { return nil }
    }

    func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue >= 0, number.doubleValue <= Double(Int32.max) else { return nil }
        return number.intValue
    }
    func consistentInteger(_ names: [String]) -> Int? {
        let values = names.compactMap { response[$0] }
        guard !values.isEmpty else { return nil }
        let parsed = values.compactMap(integer)
        guard parsed.count == values.count, let first = parsed.first, parsed.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
    guard consistentInteger(["Page", "page"]) == page,
          consistentInteger(["PageSize", "pageSize"]) == pageSize,
          let total = consistentInteger(["DataCount", "dataCount", "Total", "total"]),
          total >= rows.count else { return nil }

    let allowedStatuses: Set<String> = ["Waiting", "Called", "Completed", "Missed", "Cancelled"]
    var ids = Set<String>()
    var queueNumbers = Set<Int>()
    for row in rows {
        func string(_ name: String) -> String? {
            let camel = name.prefix(1).lowercased() + name.dropFirst()
            let keys = [name, String(camel)]
            let values = keys.compactMap { row[$0] }
            guard !values.isEmpty, values.allSatisfy({ $0 is String }),
                  Set(values.compactMap { $0 as? String }).count == 1 else { return nil }
            return values.first as? String
        }
        guard let id = string("Id"), id.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
              id.count < 19 || id <= "9223372036854775807",
              string("SessionId") == sessionID, string("StoreId") == storeID,
              let userID = string("UserId"), userID.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
              userID.count < 19 || userID <= "9223372036854775807",
              let date = string("QueueDate"), date.hasPrefix(queueDate),
              let queueNumber = integer(row["QueueNumber"]), queueNumber > 0,
              let guestName = string("GuestName"), !guestName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, guestName.count <= 80,
              let guestPhone = string("GuestPhone"), !guestPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, guestPhone.count <= 40,
              let guestCount = integer(row["GuestCount"]), (1...30).contains(guestCount),
              let status = string("Status"), allowedStatuses.contains(status),
              let createdAt = string("CreateTime"), bookingBusinessDateTime(createdAt) != nil,
              ids.insert(id).inserted, queueNumbers.insert(queueNumber).inserted else { return nil }
    }
    return (rows, total)
}
