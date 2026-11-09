import Foundation
import CoreFoundation

private func nativeTicketPageID(_ raw: Any?) -> String? {
    guard let value = raw as? String, let id = Int64(value), id > 0, String(id) == value else { return nil }
    return value
}

private func nativeTicketPageAliasedID(_ object: [String: Any], keys: [String]) -> String? {
    let values = keys.compactMap { object[$0] }
    guard !values.isEmpty else { return nil }
    var ids: [String] = []
    for value in values {
        guard let id = nativeTicketPageID(value) else { return nil }
        ids.append(id)
    }
    guard let first = ids.first, ids.allSatisfy({ $0 == first }) else { return nil }
    return first
}

private func nativeTicketPageRows(_ raw: Any?) -> [[String: Any]]? {
    guard let raw, !(raw is NSNull), let values = raw as? [Any] else { return nil }
    var rows: [[String: Any]] = []
    rows.reserveCapacity(values.count)
    for value in values {
        guard let row = value as? [String: Any] else { return nil }
        rows.append(row)
    }
    return rows
}

private func nativeTicketPageAliasedRows(_ response: [String: Any]) -> [[String: Any]]? {
    let keys = ["Items", "items", "List", "list", "Data", "data"]
    let values = keys.compactMap { response[$0] }
    guard !values.isEmpty else { return nil }
    var candidates: [[[String: Any]]] = []
    for value in values {
        guard let rows = nativeTicketPageRows(value) else { return nil }
        candidates.append(rows)
    }
    guard let first = candidates.first else { return nil }
    for candidate in candidates.dropFirst() {
        guard let left = try? JSONSerialization.data(withJSONObject: first, options: [.sortedKeys]),
              let right = try? JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys]),
              left == right else { return nil }
    }
    return first
}

private func nativeTicketPageOptionalRows(_ raw: Any?) -> [[String: Any]]? {
    guard let raw, !(raw is NSNull) else { return [] }
    return nativeTicketPageRows(raw)
}

private func nativeTicketPageAliasedOptionalRows(_ object: [String: Any], keys: [String]) -> [[String: Any]]? {
    let values = keys.compactMap { object[$0] }
    guard !values.isEmpty else { return [] }
    var candidates: [[[String: Any]]] = []
    for value in values {
        guard let rows = nativeTicketPageOptionalRows(value) else { return nil }
        candidates.append(rows)
    }
    guard let first = candidates.first else { return [] }
    for candidate in candidates.dropFirst() {
        guard let left = try? JSONSerialization.data(withJSONObject: first, options: [.sortedKeys]),
              let right = try? JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys]),
              left == right else { return nil }
    }
    return first
}

private func nativeTicketPageTotal(_ raw: Any?) -> Int? {
    if let text = raw as? String {
        guard text.range(of: "^[0-9]+$", options: .regularExpression) != nil else { return nil }
        return Int(text)
    }
    guard let number = raw as? NSNumber else { return nil }
    let type = String(cString: number.objCType)
    guard type != "c", type != "B", number.doubleValue.isFinite,
          number.doubleValue >= 0, number.doubleValue <= Double(Int.max),
          number.doubleValue.rounded(.towardZero) == number.doubleValue else { return nil }
    return number.intValue
}

private func nativeTicketPageAliasedTotal(_ response: [String: Any]) -> Int? {
    let keys = ["dataCount", "DataCount", "total", "Total"]
    let values = keys.compactMap { response[$0] }
    guard !values.isEmpty else { return nil }
    var candidates: [Int] = []
    for value in values {
        guard let total = nativeTicketPageTotal(value) else { return nil }
        candidates.append(total)
    }
    guard let first = candidates.first, candidates.allSatisfy({ $0 == first }) else { return nil }
    return first
}

internal func nativeTicketOrderPage(_ response: [String: Any], pageSize: Int) -> (items: [[String: Any]], total: Int)? {
    guard pageSize > 0,
          let items = nativeTicketPageAliasedRows(response), items.count <= pageSize,
          let total = nativeTicketPageAliasedTotal(response), total >= items.count else { return nil }

    var orderIDs = Set<String>()
    for order in items {
        guard let orderID = nativeTicketPageAliasedID(order, keys: ["Id", "id"]), orderIDs.insert(orderID).inserted else { return nil }
        let lines = nativeTicketPageAliasedOptionalRows(order, keys: ["Lines", "lines"])
        guard let lines else { return nil }
        var lineIDs = Set<String>()
        var credentialIDs = Set<String>()
        for line in lines {
            guard let lineID = nativeTicketPageAliasedID(line, keys: ["Id", "id"]), lineIDs.insert(lineID).inserted,
                  nativeTicketPageAliasedID(line, keys: ["TicketTypeId", "ticketTypeId"]) != nil,
                  nativeTicketPageAliasedID(line, keys: ["SessionId", "sessionId"]) != nil,
                  let credentials = nativeTicketPageAliasedOptionalRows(line, keys: ["Credentials", "credentials"]) else { return nil }
            for credential in credentials {
                guard let credentialID = nativeTicketPageAliasedID(credential, keys: ["Id", "id"]),
                      credentialIDs.insert(credentialID).inserted else { return nil }
            }
        }

        guard let refunds = nativeTicketPageAliasedOptionalRows(order, keys: ["Refunds", "refunds"]) else { return nil }
        var refundIDs = Set<String>()
        for refund in refunds {
            guard let refundID = nativeTicketPageAliasedID(refund, keys: ["Id", "id"]), refundIDs.insert(refundID).inserted,
                  nativeTicketPageAliasedID(refund, keys: ["OrderId", "orderId"]) == orderID else { return nil }
        }
    }
    return (items, total)
}

internal func nativeTicketOrderPage(_ response: [String: Any], page: Int, pageSize: Int) -> (items: [[String: Any]], total: Int)? {
    guard page > 0, pageSize > 0 else { return nil }
    func metadata(_ keys: [String]) -> Int? {
        let rawValues = keys.compactMap { response[$0] }
        guard !rawValues.isEmpty else { return nil }
        let values = rawValues.compactMap { value -> Int? in
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
                  number.doubleValue > 0, number.doubleValue <= Double(Int32.max) else { return nil }
            return number.intValue
        }
        guard values.count == rawValues.count, let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
    guard metadata(["Page", "page"]) == page,
          metadata(["PageSize", "pageSize"]) == pageSize else { return nil }
    return nativeTicketOrderPage(response, pageSize: pageSize)
}

internal func nativeTicketOrderDetail(_ response: [String: Any], expectedOrderID: String) -> [String: Any]? {
    guard nativeTicketPageID(expectedOrderID) != nil,
          let page = nativeTicketOrderPage(["data": [response], "dataCount": 1], pageSize: 1),
          let order = page.items.first,
          nativeTicketPageAliasedID(order, keys: ["Id", "id"]) == expectedOrderID else { return nil }
    return order
}

// 票价沿用服务端上限，先转整数分再乘数量，拒绝以展示层舍入修复异常票价。
func nativeTicketSaleTotalCents(_ price: Any?, quantity: Int) -> Int64? {
    guard (1...100).contains(quantity), let unit = nativeTradeMoneyCents(price),
          unit > 0, unit <= 9_999_999_999 else { return nil }
    let total = unit * Int64(quantity)
    return total <= 99_999_999_900 ? total : nil
}

private func ticketSnapshotID(_ raw: Any?) -> String? {
    guard let text = raw as? String, let value = Int64(text), value > 0, String(value) == text else { return nil }
    return text
}

func nativeTicketSnapshotQuantity(_ raw: Any?) -> Int? {
    guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.rounded() == number.doubleValue, (1...100).contains(number.doubleValue) else { return nil }
    return number.intValue
}

func nativeTicketOrderSnapshotMatches(_ order: [String: Any], ticketID: String, sessionID: String,
    quantity: Int, expectedCents: Int64, expectedPoints: Int64) -> Bool {
    guard ticketSnapshotID(ticketID) != nil, ticketSnapshotID(sessionID) != nil,
          ticketSnapshotID(order["Id"]) != nil, order["Currency"] as? String == "CNY",
          let lines = order["Lines"] as? [[String: Any]], lines.count == 1, let line = lines.first,
          ticketSnapshotID(line["Id"]) != nil, line["TicketTypeId"] as? String == ticketID,
          line["SessionId"] as? String == sessionID,
          let name = line["TicketName"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let session = line["SessionName"] as? String, !session.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          nativeTicketSnapshotQuantity(line["Quantity"]) == quantity,
          let total = nativeTicketSaleTotalCents(line["UnitPrice"], quantity: quantity), total == expectedCents,
          nativeTradeMoneyCents(order["Amount"]) == total,
          let pointsText = order["PointsUsed"] as? String, let points = Int64(pointsText), String(points) == pointsText,
          points >= 0, points == expectedPoints, points <= total / 2,
          nativeTradeMoneyCents(order["PointsDiscountAmount"]) == points,
          nativeTradeMoneyCents(order["CashPayableAmount"]) == total - points else { return false }
    return true
}

private func ticketCatalogInteger(_ raw: Any?, maximum: Int) -> Int? {
    guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.rounded() == number.doubleValue, (0...Double(maximum)).contains(number.doubleValue) else { return nil }
    return number.intValue
}

private func nativeTicketBundleItemsValid(_ kind: String, raw: Any?) -> Bool {
    guard let items = raw as? [[String: Any]] else { return false }
    if kind == "Single" { return items.isEmpty }
    guard kind == "Bundle", (1...20).contains(items.count) else { return false }
    return items.allSatisfy { item in
        guard let name = item["Name"] as? String,
              let quantity = ticketCatalogInteger(item["Quantity"], maximum: 100), quantity >= 1 else { return false }
        let description = item["Description"]
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 120
            && (description == nil || description is NSNull
                || description is String && (description as! String).trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 300)
    }
}

// 响应异常与正常无票分开处理；通过后只返回仍在售且有足够余票的场次副本。
func nativeTicketCatalogSnapshot(_ rows: [[String: Any]], resourceID: String, now: Date,
    parseTime: (Any?) -> Date?) -> [[String: Any]]? {
    guard ticketSnapshotID(resourceID) != nil else { return nil }
    var ticketIDs = Set<String>(); var sessionIDs = Set<String>(); var result: [[String: Any]] = []
    for row in rows {
        guard let kind = row["TicketKind"] as? String,
              let priceCents = nativeTradeMoneyCents(row["Price"]), (1...9_999_999_999).contains(priceCents),
              let refundPolicy = row["RefundPolicy"] as? String,
              ["None", "BeforeDeadline", "AnytimeBeforeUse", "ManualReview"].contains(refundPolicy),
              let refundBeforeHours = ticketCatalogInteger(row["RefundBeforeHours"], maximum: 8760),
              (0...8760).contains(refundBeforeHours),
              nativeTicketBundleItemsValid(kind, raw: row["BundleItems"]) else { return nil }
        let rawOriginalPrice = row["OriginalPrice"]
        let originalPriceCents = rawOriginalPrice == nil || rawOriginalPrice is NSNull
            ? nil : nativeTradeMoneyCents(rawOriginalPrice)
        guard rawOriginalPrice == nil || rawOriginalPrice is NSNull
                || originalPriceCents.map({ (0...9_999_999_999).contains($0) }) == true,
              originalPriceCents == nil || originalPriceCents! >= priceCents,
              row["Description"] == nil || row["Description"] is NSNull
                || row["Description"] is String && (row["Description"] as! String).trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 500,
              row["RefundDescription"] == nil || row["RefundDescription"] is NSNull
                || row["RefundDescription"] is String && (row["RefundDescription"] as! String).trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 500 else { return nil }
        guard let id = ticketSnapshotID(row["Id"]), ticketIDs.insert(id).inserted,
              row["ResourceId"] as? String == resourceID,
              let name = row["Name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              nativeTicketRealNameFieldsValid(row["RealNameFields"]),
              nativeTicketSaleTotalCents(row["Price"], quantity: 1) != nil,
              let minimum = nativeTicketSnapshotQuantity(row["MinPerOrder"]),
              let maximum = nativeTicketSnapshotQuantity(row["MaxPerOrder"]), minimum <= maximum,
              let daily = ticketCatalogInteger(row["MaxPerUserPerDay"], maximum: 1000), daily >= maximum,
              let end = parseTime(row["SaleEndTime"]),
              let sessions = row["Sessions"] as? [[String: Any]] else { return nil }
        var available: [[String: Any]] = []
        for session in sessions {
            guard let sessionID = ticketSnapshotID(session["Id"]), sessionIDs.insert(sessionID).inserted,
                  let name = session["Name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let enabled = session["IsEnabled"] as? NSNumber, CFGetTypeID(enabled) == CFBooleanGetTypeID(),
                  let inventory = ticketCatalogInteger(session["Inventory"], maximum: 10_000_000),
                  let sold = ticketCatalogInteger(session["SoldCount"], maximum: inventory),
                  let reserved = ticketCatalogInteger(session["ReservedCount"], maximum: inventory - sold),
                  let remaining = ticketCatalogInteger(session["RemainingInventory"], maximum: inventory),
                  remaining == inventory - sold - reserved,
                  let start = parseTime(session["StartTime"]),
                  let finish = parseTime(session["EndTime"]), finish > start else { return nil }
            if enabled.boolValue && start > now && finish > now && remaining >= minimum { available.append(session) }
        }
        if end > now && !available.isEmpty {
            var value = row; value["Sessions"] = available; result.append(value)
        }
    }
    return result
}

func nativeTicketCatalogDeadline(_ rows: [[String: Any]], parseTime: (Any?) -> Date?) -> Date? {
    rows.flatMap { row in
        [parseTime(row["SaleEndTime"])] + (row["Sessions"] as? [[String: Any]] ?? []).flatMap {
            [parseTime($0["StartTime"]), parseTime($0["EndTime"])]
        }
    }.compactMap { $0 }.min()
}

func nativeTicketVisitDate(_ raw: Any?, parseTime: (Any?) -> Date?) -> String? {
    guard let date = parseTime(raw) else { return nil }
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

// 本人额度只用于当前票种、场次与入园日期，错配或账本不闭合时不得当作可购额度。
func nativeTicketDailyQuotaRemaining(_ quota: [String: Any]?, ticketID: String, sessionID: String,
    visitDate: String, dailyLimit: Int) -> Int? {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
    guard let date = formatter.date(from: visitDate), formatter.string(from: date) == visitDate,
          ticketSnapshotID(ticketID) != nil, ticketSnapshotID(sessionID) != nil,
          let quota, quota["TicketTypeId"] as? String == ticketID, quota["SessionId"] as? String == sessionID,
          quota["VisitDate"] as? String == visitDate, (1...1000).contains(dailyLimit),
          ticketCatalogInteger(quota["DailyLimit"], maximum: 1000) == dailyLimit,
          let used = ticketCatalogInteger(quota["ReservedOrPurchased"], maximum: dailyLimit),
          let remaining = ticketCatalogInteger(quota["RemainingQuantity"], maximum: dailyLimit),
          remaining == dailyLimit - used else { return nil }
    return remaining
}
