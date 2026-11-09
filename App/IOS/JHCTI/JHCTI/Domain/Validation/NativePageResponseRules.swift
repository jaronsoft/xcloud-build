import CoreFoundation
import Foundation

func nativeDiningReservationManagementPage(_ response: [String: Any], page: Int, pageSize: Int,
                                          storeID: String) -> (rows: [[String: Any]], total: Int)? {
    guard page > 0, pageSize > 0, Int64(storeID).map({ $0 > 0 }) == true else { return nil }
    func integer(_ value: Any?, allowString: Bool = false, allowZero: Bool = false) -> Int? {
        if allowString, let text = value as? String {
            guard text.range(of: "^[0-9]+$", options: .regularExpression) != nil,
                  let parsed = Int(text), parsed <= Int32.max,
                  allowZero ? parsed >= 0 : parsed > 0 else { return nil }
            return parsed
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
              allowZero ? number.doubleValue >= 0 : number.doubleValue > 0,
              number.doubleValue <= Double(Int32.max) else { return nil }
        return number.intValue
    }
    func consistent(_ source: [String: Any], keys: [String], validate: (Any) -> Bool) -> (Bool, Any?) {
        let present = keys.compactMap { key -> Any? in source.keys.contains(key) ? source[key] : nil }
        guard let first = present.first, validate(first),
              let firstData = try? JSONSerialization.data(withJSONObject: first, options: [.sortedKeys, .fragmentsAllowed]) else { return (false, nil) }
        for candidate in present.dropFirst() {
            guard validate(candidate) else { return (false, nil) }
            if let left = first as? NSNumber, let right = candidate as? NSNumber,
               CFGetTypeID(left) != CFBooleanGetTypeID(), CFGetTypeID(right) != CFBooleanGetTypeID() {
                guard left.decimalValue == right.decimalValue else { return (false, nil) }
            } else {
                guard let candidateData = try? JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys, .fragmentsAllowed]),
                      candidateData == firstData else { return (false, nil) }
            }
        }
        return (true, first)
    }
    func stringField(_ row: [String: Any], _ name: String, nullable: Bool = false,
                     validate: (String) -> Bool = { _ in true }) -> (Bool, Any?) {
        let camel = String(name.prefix(1).lowercased() + name.dropFirst())
        return consistent(row, keys: [name, camel]) { value in
            if nullable, value is NSNull { return true }
            guard let text = value as? String else { return false }
            return validate(text)
        }
    }
    func isBusinessDateTime(_ value: String) -> Bool {
        guard value.count >= 19 else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: value) != nil || ISO8601DateFormatter().date(from: value) != nil { return true }
        let wallClock = DateFormatter()
        wallClock.calendar = Calendar(identifier: .gregorian)
        wallClock.timeZone = TimeZone(identifier: "Asia/Shanghai")
        wallClock.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let suffix = String(value.dropFirst(19))
        let fractionIsValid = suffix.isEmpty || suffix.range(of: "^\\.[0-9]{1,7}$", options: .regularExpression) != nil
        wallClock.isLenient = false
        return fractionIsValid && wallClock.date(from: String(value.prefix(19))) != nil
    }
    let pageValue = consistent(response, keys: ["Page", "page"]) { integer($0) != nil }
    let sizeValue = consistent(response, keys: ["PageSize", "pageSize"]) { integer($0) != nil }
    guard pageValue.0, sizeValue.0,
          integer(pageValue.1) == page, integer(sizeValue.1) == pageSize else { return nil }
    let rowValue = consistent(response, keys: ["Items", "items", "List", "list", "Data", "data"]) {
        $0 is [[String: Any]]
    }
    guard rowValue.0, let rawRows = rowValue.1 as? [[String: Any]], rawRows.count <= pageSize else { return nil }
    let totalValue = consistent(response, keys: ["DataCount", "dataCount", "Total", "total"]) {
        integer($0, allowString: true, allowZero: true) != nil
    }
    guard totalValue.0, let total = integer(totalValue.1, allowString: true, allowZero: true),
          total >= rawRows.count else { return nil }
    let offset = (page - 1).multipliedReportingOverflow(by: pageSize)
    let pageCount = total / pageSize + (total % pageSize == 0 ? 0 : 1)
    guard !offset.overflow, page <= max(1, pageCount),
          rawRows.count == min(pageSize, max(0, total - offset.partialValue)) else { return nil }

    let allowedStatuses: Set<String> = ["Pending", "Confirmed", "Declined", "Cancelled"]
    var identifiers = Set<String>()
    var normalizedRows: [[String: Any]] = []
    for row in rawRows {
        let id = stringField(row, "Id") { Int64($0).map { $0 > 0 } == true && $0.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil }
        let rowStoreID = stringField(row, "StoreId") { Int64($0) == Int64(storeID) && $0.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil }
        let slotID = stringField(row, "SlotId") { Int64($0).map { $0 > 0 } == true && $0.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil }
        let userID = stringField(row, "UserId") { Int64($0).map { $0 > 0 } == true && $0.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil }
        let serviceDate = stringField(row, "ServiceDate", validate: isBusinessDateTime)
        let startTime = stringField(row, "StartTime", validate: isDiningReservationTime)
        let endTime = stringField(row, "EndTime", validate: isDiningReservationTime)
        let tableTypeID = stringField(row, "TableTypeId", nullable: true) { Int64($0).map { $0 > 0 } == true && $0.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil }
        let tableTypeName = stringField(row, "TableTypeName", nullable: true)
        let guestName = stringField(row, "GuestName") { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let guestPhone = stringField(row, "GuestPhone") { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let guestCount = consistent(row, keys: ["GuestCount", "guestCount"]) { integer($0) != nil }
        let reservationStatus = stringField(row, "Status") { allowedStatuses.contains($0) }
        let guestNote = stringField(row, "GuestNote", nullable: true)
        let handleNote = stringField(row, "HandleNote", nullable: true)
        let createTime = stringField(row, "CreateTime", validate: isBusinessDateTime)
        guard id.0, rowStoreID.0, slotID.0, userID.0, serviceDate.0, startTime.0, endTime.0,
              tableTypeID.0, tableTypeName.0, guestName.0, guestPhone.0, guestCount.0,
              reservationStatus.0, guestNote.0, handleNote.0, createTime.0,
              let idText = id.1 as? String, identifiers.insert(idText).inserted,
              let guestCountValue = integer(guestCount.1), let statusText = reservationStatus.1 as? String,
              let startText = startTime.1 as? String, let endText = endTime.1 as? String,
              let idValue = id.1, let storeIDValue = rowStoreID.1, let slotIDValue = slotID.1,
              let userIDValue = userID.1, let serviceDateValue = serviceDate.1,
              let tableTypeIDValue = tableTypeID.1, let tableTypeNameValue = tableTypeName.1,
              let guestNameValue = guestName.1, let guestPhoneValue = guestPhone.1,
              let guestNoteValue = guestNote.1, let handleNoteValue = handleNote.1, let createTimeValue = createTime.1,
              (startText.isEmpty && endText.isEmpty) || (!startText.isEmpty && !endText.isEmpty) else { return nil }
        normalizedRows.append([
            "Id": idValue, "StoreId": storeIDValue, "SlotId": slotIDValue, "UserId": userIDValue,
            "ServiceDate": serviceDateValue, "StartTime": startText, "EndTime": endText,
            "TableTypeId": tableTypeIDValue, "TableTypeName": tableTypeNameValue,
            "GuestName": guestNameValue, "GuestPhone": guestPhoneValue, "GuestCount": guestCountValue,
            "Status": statusText, "GuestNote": guestNoteValue, "HandleNote": handleNoteValue, "CreateTime": createTimeValue
        ])
    }
    return (normalizedRows, total)
}

private func isDiningReservationTime(_ value: String) -> Bool {
    if value.isEmpty { return true }
    return value.range(of: "^(?:[01][0-9]|2[0-3]):[0-5][0-9](?::[0-5][0-9])?$", options: .regularExpression) != nil
}

func nativeDiningMenuPage(_ categoryResponse: Any, dishResponse: [String: Any], page: Int, pageSize: Int,
                                  storeID: String, existingDishes: [[String: Any]]) -> (categories: [[String: Any]], dishes: [[String: Any]], total: Int)? {
    guard page > 0, pageSize > 0, Int64(storeID).map({ $0 > 0 }) == true,
          storeID.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
          let rawCategories = categoryResponse as? [[String: Any]] else { return nil }
    func integer(_ value: Any?, allowString: Bool = false) -> Int? {
        if allowString, let text = value as? String {
            guard text.range(of: "^[0-9]+$", options: .regularExpression) != nil, let result = Int(text), result >= 0 else { return nil }
            return result
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue >= 0, number.doubleValue <= Double(Int32.max) else { return nil }
        return number.intValue
    }
    func same(_ left: Any, _ right: Any) -> Bool {
        if let lhs = left as? NSNumber, let rhs = right as? NSNumber,
           CFGetTypeID(lhs) != CFBooleanGetTypeID(), CFGetTypeID(rhs) != CFBooleanGetTypeID() {
            return lhs.decimalValue == rhs.decimalValue
        }
        guard let leftData = try? JSONSerialization.data(withJSONObject: left, options: [.sortedKeys, .fragmentsAllowed]),
              let rightData = try? JSONSerialization.data(withJSONObject: right, options: [.sortedKeys, .fragmentsAllowed]) else { return false }
        return leftData == rightData
    }
    func consistent(_ source: [String: Any], _ keys: [String], validate: (Any) -> Bool) -> (Bool, Any?) {
        let values = keys.compactMap { key in source.keys.contains(key) ? source[key] : nil }
        guard let first = values.first, validate(first), values.dropFirst().allSatisfy({ validate($0) && same(first, $0) }) else { return (false, nil) }
        return (true, first)
    }
    func field(_ row: [String: Any], _ name: String, nullable: Bool = false,
               validate: (String) -> Bool = { _ in true }) -> (Bool, Any?) {
        let lower = String(name.prefix(1).lowercased() + name.dropFirst())
        return consistent(row, [name, lower]) { value in
            if nullable, value is NSNull { return true }
            guard let text = value as? String else { return false }
            return validate(text)
        }
    }
    func validID(_ value: String) -> Bool {
        value.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil && Int64(value).map({ $0 > 0 }) == true
    }
    func validIntegerField(_ row: [String: Any], _ name: String) -> Int? {
        let lower = String(name.prefix(1).lowercased() + name.dropFirst())
        let result = consistent(row, [name, lower]) { integer($0) != nil }
        guard result.0 else { return nil }
        return integer(result.1)
    }
    func validBooleanField(_ row: [String: Any], _ name: String) -> Bool? {
        let lower = String(name.prefix(1).lowercased() + name.dropFirst())
        let result = consistent(row, [name, lower]) {
            guard let number = $0 as? NSNumber else { return false }
            return CFGetTypeID(number) == CFBooleanGetTypeID()
        }
        guard result.0, let value = result.1 as? Bool else { return nil }
        return value
    }
    var categoryIDs = Set<String>()
    for category in rawCategories {
        let id = field(category, "Id", validate: validID)
        let categoryStore = field(category, "StoreId") { $0 == storeID }
        let name = field(category, "Name") { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard id.0, categoryStore.0, name.0,
              let idText = id.1 as? String, validIntegerField(category, "Version") != nil,
              validIntegerField(category, "SortOrder") != nil, validBooleanField(category, "IsEnabled") != nil,
              categoryIDs.insert(idText).inserted else { return nil }
    }

    let wrappedKeys = ["Data", "data"].filter { dishResponse.keys.contains($0) }
    let wrappedValues = wrappedKeys.compactMap { dishResponse[$0] }
    if wrappedValues.contains(where: { !($0 is [String: Any]) && !($0 is [[String: Any]]) }) { return nil }
    let wrapped = wrappedValues.compactMap { $0 as? [String: Any] }
    if !wrapped.isEmpty && wrappedValues.contains(where: { $0 is [[String: Any]] }) { return nil }
    let envelope: [String: Any]
    if let first = wrapped.first {
        guard wrapped.dropFirst().allSatisfy({ same(first, $0) }) else { return nil }
        envelope = first
    } else { envelope = dishResponse }
    let pageField = consistent(envelope, ["Page", "page"]) { integer($0).map({ $0 > 0 }) == true }
    let sizeField = consistent(envelope, ["PageSize", "pageSize"]) { integer($0).map({ $0 > 0 }) == true }
    guard pageField.0, sizeField.0, integer(pageField.1) == page, integer(sizeField.1) == pageSize else { return nil }
    let rowValue = consistent(envelope, ["Items", "items", "List", "list", "Data", "data"]) { $0 is [[String: Any]] }
    guard rowValue.0, let rows = rowValue.1 as? [[String: Any]] else { return nil }
    let totalValue = consistent(envelope, ["DataCount", "dataCount", "Total", "total"]) { integer($0, allowString: true) != nil }
    guard totalValue.0, let total = integer(totalValue.1, allowString: true) else { return nil }
    let offset = (page - 1).multipliedReportingOverflow(by: pageSize)
    guard !offset.overflow, rows.count <= pageSize,
          rows.count == min(pageSize, max(0, total - offset.partialValue)),
          page <= max(1, total / pageSize + (total % pageSize == 0 ? 0 : 1)),
          !(page > 1 && rows.isEmpty && existingDishes.count < total) else { return nil }

    var dishIDs = Set(existingDishes.compactMap { $0["Id"] as? String })
    for dish in rows {
        let id = field(dish, "Id", validate: validID)
        let store = field(dish, "StoreId") { $0 == storeID }
        let category = field(dish, "CategoryId", validate: validID)
        let name = field(dish, "Name") { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let description = field(dish, "Description", nullable: true)
        let image = field(dish, "ImageUrl", nullable: true)
        let skusValue = consistent(dish, ["Skus", "skus"]) { $0 is [[String: Any]] }
        guard id.0, store.0, category.0, name.0, description.0, image.0, skusValue.0,
              let idText = id.1 as? String, dishIDs.insert(idText).inserted,
              validIntegerField(dish, "Version") != nil, validIntegerField(dish, "SortOrder") != nil,
              validBooleanField(dish, "IsAvailable") != nil, let skus = skusValue.1 as? [[String: Any]] else { return nil }
        var skuIDs = Set<String>()
        for sku in skus {
            let skuID = field(sku, "Id", validate: validID)
            let skuName = field(sku, "Name") { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let price = consistent(sku, ["Price", "price"]) { value in
                guard let amount = value as? NSNumber, CFGetTypeID(amount) != CFBooleanGetTypeID() else { return false }
                return amount.doubleValue.isFinite && amount.decimalValue >= 0
            }
            guard skuID.0, skuName.0, price.0, let skuIDText = skuID.1 as? String,
                  skuIDs.insert(skuIDText).inserted, validIntegerField(sku, "SortOrder") != nil,
                  validBooleanField(sku, "IsAvailable") != nil else { return nil }
        }
    }
    guard total >= existingDishes.count + rows.count else { return nil }
    return (rawCategories, rows, total)
}

func nativeBookingOrderPage(_ response: [String: Any], page: Int, pageSize: Int) -> (rows: [[String: Any]], total: Int)? {
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
    let rawRows = ["Items", "items", "List", "list", "Data", "data"].compactMap { response[$0] }
    guard !rawRows.isEmpty else { return nil }
    var rowCandidates: [[[String: Any]]] = []
    for value in rawRows {
        guard let values = value as? [[String: Any]], values.count <= pageSize else { return nil }
        rowCandidates.append(values)
    }
    guard let rows = rowCandidates.first else { return nil }
    for candidate in rowCandidates.dropFirst() {
        guard let left = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
              let right = try? JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys]),
              left == right else { return nil }
    }

    let rawTotals = ["DataCount", "dataCount", "Total", "total"].compactMap { response[$0] }
    guard !rawTotals.isEmpty else { return nil }
    var totals: [Int] = []
    for value in rawTotals {
        if let text = value as? String {
            guard text.range(of: "^[0-9]+$", options: .regularExpression) != nil,
                  let total = Int(text), total <= Int32.max else { return nil }
            totals.append(total)
        } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue >= 0,
                  number.doubleValue.rounded(.towardZero) == number.doubleValue,
                  number.doubleValue <= Double(Int32.max) {
            totals.append(number.intValue)
        } else {
            return nil
        }
    }
    let offset = (page - 1).multipliedReportingOverflow(by: pageSize)
    guard let total = totals.first, totals.allSatisfy({ $0 == total }), total >= rows.count,
          !offset.overflow, page <= max(1, total / pageSize + (total % pageSize == 0 ? 0 : 1)),
          rows.count == min(pageSize, max(0, total - offset.partialValue)) else { return nil }
    return (rows, total)
}

func nativeActivityRegistrationPageTotal(_ response: [String: Any], rowCount: Int) -> Int? {
    let raw = ["dataCount", "DataCount", "total", "Total"]
        .compactMap { response[$0] }
        .first { !($0 is NSNull) }
    guard let raw else { return rowCount }
    let count: Int?
    if let text = raw as? String {
        guard text.range(of: "^[0-9]+$", options: .regularExpression) != nil else { return nil }
        count = Int(text)
    } else if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= 9_007_199_254_740_991,
              value.rounded(.towardZero) == value else { return nil }
        count = Int(value)
    } else {
        count = nil
    }
    guard let count, count >= rowCount else { return nil }
    return count
}

func nativeTourismReservationPageTotal(_ response: [String: Any], rowCount: Int) -> Int? {
    let raw = ["DataCount", "dataCount", "Total", "total"]
        .compactMap { response[$0] }
        .first { !($0 is NSNull) }
    guard let raw else { return rowCount }
    let count: Int?
    if let text = raw as? String {
        guard text.range(of: "^[0-9]+$", options: .regularExpression) != nil,
              let value = Int64(text), value <= 9_007_199_254_740_991 else { return nil }
        count = Int(exactly: value)
    } else if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= 9_007_199_254_740_991,
              value.rounded(.towardZero) == value else { return nil }
        count = Int(value)
    } else {
        count = nil
    }
    guard let count, count >= rowCount else { return nil }
    return count
}

enum NativeFavoritePageOutOfRangeError: LocalizedError {
    case outOfRange

    var errorDescription: String? { "收藏数量已更新，正在返回第一页。" }
}

func nativeFavoritePageTotal(_ response: [String: Any], page: Int, pageSize: Int, rowCount: Int) throws -> Int {
    guard page > 0, pageSize > 0, pageSize <= 100, rowCount >= 0 else {
        throw MobileAPIError.unavailable("收藏分页请求参数异常，请重新加载。")
    }
    func integer(_ keys: [String], allowZero: Bool = true) -> Int? {
        let rawValues = keys.compactMap { response[$0] }
        guard !rawValues.isEmpty else { return nil }
        let values = rawValues.compactMap { value -> Int? in
            if let text = value as? String {
                guard text.range(of: "^[0-9]+$", options: .regularExpression) != nil else { return nil }
                return Int(text)
            }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
                  number.doubleValue <= 9_007_199_254_740_991,
                  allowZero ? number.doubleValue >= 0 : number.doubleValue > 0 else { return nil }
            return Int(number.doubleValue)
        }
        guard values.count == rawValues.count, let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
    guard integer(["Page", "page"], allowZero: false) == page,
          integer(["PageSize", "pageSize"], allowZero: false) == pageSize,
          let total = integer(["DataCount", "dataCount", "Total", "total"]), total >= rowCount,
          let pageCount = integer(["PageCount", "pageCount"]),
          pageCount == total / pageSize + (total % pageSize == 0 ? 0 : 1) else {
        throw MobileAPIError.unavailable("收藏列表分页信息与请求不一致，请重新加载。")
    }
    if page > max(1, pageCount) { throw NativeFavoritePageOutOfRangeError.outOfRange }
    let offset = (page - 1).multipliedReportingOverflow(by: pageSize)
    guard !offset.overflow,
          rowCount == min(pageSize, max(0, total - offset.partialValue)) else {
        throw MobileAPIError.unavailable("收藏列表当前页记录数异常，请重新加载。")
    }
    return total
}

func nativeMerchantOnboardingPage(_ response: [String: Any], page: Int, pageSize: Int) -> (rows: [[String: Any]], total: Int)? {
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
    guard metadata(["Page", "page"]) == page, metadata(["PageSize", "pageSize"]) == pageSize else { return nil }
    let rowValues = ["Items", "items", "List", "list", "Data", "data"]
        .compactMap { response[$0] }
    guard !rowValues.isEmpty else { return nil }
    var rowCandidates: [[[String: Any]]] = []
    for value in rowValues {
        guard let rows = value as? [[String: Any]] else { return nil }
        rowCandidates.append(rows)
    }
    guard let rows = rowCandidates.first,
          let firstRowsData = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]) else { return nil }
    for candidate in rowCandidates.dropFirst() {
        guard let candidateData = try? JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys]),
              candidateData == firstRowsData else { return nil }
    }

    let totalValues = ["DataCount", "dataCount", "Total", "total"].compactMap { response[$0] }
    guard !totalValues.isEmpty else { return nil }
    var totals: [Int] = []
    for value in totalValues {
        let total: Int?
        if let text = value as? String {
            guard text.range(of: "^[0-9]+$", options: .regularExpression) != nil else { return nil }
            total = Int(text)
        } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let raw = number.doubleValue
            guard raw.isFinite, raw >= 0, raw <= 9_007_199_254_740_991,
                  raw.rounded(.towardZero) == raw else { return nil }
            total = Int(raw)
        } else {
            total = nil
        }
        guard let total else { return nil }
        totals.append(total)
    }
    guard let total = totals.first, totals.allSatisfy({ $0 == total }),
          let expectedRows = nativeReportExpectedRows(page: page, total: total, pageSize: pageSize),
          rows.count == expectedRows else { return nil }

    let allowedStatuses: Set<String> = ["PendingReview", "SupplementRequired", "Approved", "Rejected"]
    var identifiers = Set<String>()
    var normalizedRows: [[String: Any]] = []
    for row in rows {
        func field(_ name: String) -> Any? {
            let camel = String(name.prefix(1).lowercased()) + String(name.dropFirst())
            let values = [name, camel].compactMap { row[$0] }
            guard let first = values.first else { return nil }
            guard values.dropFirst().allSatisfy({ candidate in
                if let left = first as? NSNumber, let right = candidate as? NSNumber,
                   CFGetTypeID(left) != CFBooleanGetTypeID(), CFGetTypeID(right) != CFBooleanGetTypeID() {
                    return left.doubleValue == right.doubleValue
                }
                guard let lhs = try? JSONSerialization.data(withJSONObject: ["v": first], options: [.sortedKeys]),
                      let rhs = try? JSONSerialization.data(withJSONObject: ["v": candidate], options: [.sortedKeys]) else { return false }
                return lhs == rhs
            }) else { return nil }
            return first
        }
        guard let id = field("Id") as? String, let numericId = Int64(id), numericId > 0,
              String(numericId) == id, identifiers.insert(id).inserted,
              let versionValue = field("Version") as? NSNumber, CFGetTypeID(versionValue) != CFBooleanGetTypeID(),
              versionValue.doubleValue.isFinite, versionValue.doubleValue >= 0,
              versionValue.doubleValue <= 9_007_199_254_740_991,
              versionValue.doubleValue.rounded(.towardZero) == versionValue.doubleValue,
              let merchantName = field("MerchantName") as? String, !merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let status = field("Status") as? String, allowedStatuses.contains(status),
              let reviewStage = field("ReviewStage") as? String, ["District", "Operations"].contains(reviewStage),
              let identityType = field("ApplicantIdentityType") as? String, ["SiteServer", "Tourism"].contains(identityType) else { return nil }
        var normalized = row
        normalized["Id"] = id
        normalized["Version"] = Int(versionValue.int64Value)
        normalized["MerchantName"] = merchantName
        normalized["Status"] = status
        normalized["ReviewStage"] = reviewStage
        normalized["ApplicantIdentityType"] = identityType
        normalizedRows.append(normalized)
    }
    return (normalizedRows, total)
}

func nativeFavoriteResourceID(_ row: [String: Any]) -> String? {
    let keys = ["Id", "id"].filter { row[$0] != nil && !(row[$0] is NSNull) }
    let values = keys.compactMap { row[$0] as? String }
    guard !values.isEmpty, values.count == keys.count, Set(values).count == 1,
          let id = values.first, let number = Int64(id), number > 0, String(number) == id else { return nil }
    return id
}
