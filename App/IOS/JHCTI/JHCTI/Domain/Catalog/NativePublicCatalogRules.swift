import Foundation
import CoreFoundation

/** 校验公开目录的 PageModel 分页元数据，避免错误页或不完整页被追加到目录。 */
func nativePublicCatalogPage(_ response: [String: Any], page: Int, pageSize: Int) -> (rows: [[String: Any]], total: Int)? {
    guard page > 0, pageSize > 0 else { return nil }
    func integer(_ value: Any?, allowString: Bool = false) -> Int? {
        if allowString, let text = value as? String {
            guard text.range(of: "^[0-9]+$", options: .regularExpression) != nil,
                  let parsed = Int(text), parsed >= 0, parsed <= Int32.max else { return nil }
            return parsed
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue >= 0, number.doubleValue <= Double(Int32.max) else { return nil }
        return number.intValue
    }
    func consistent(_ keys: [String], parse: (Any?) -> Int?) -> (Bool, Int?) {
        let values = keys.compactMap { response.keys.contains($0) ? response[$0] : nil }
        guard let first = values.first, let parsed = parse(first), values.dropFirst().allSatisfy({ parse($0) == parsed }) else { return (false, nil) }
        return (true, parsed)
    }
    let returnedPage = consistent(["Page", "page"]) { integer($0) }
    let returnedSize = consistent(["PageSize", "pageSize"]) { integer($0) }
    guard returnedPage.0, returnedPage.1 == page, returnedSize.0, returnedSize.1 == pageSize else { return nil }
    let presentRows = ["Items", "items", "List", "list", "Data", "data"]
        .filter { response.keys.contains($0) }.map { response[$0] }
    let rowValues = presentRows.compactMap { $0 as? [[String: Any]] }
    guard !presentRows.isEmpty, rowValues.count == presentRows.count, let rows = rowValues.first,
          rowValues.dropFirst().allSatisfy({ candidate in
              guard let left = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .fragmentsAllowed]),
                    let right = try? JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys, .fragmentsAllowed]) else { return false }
              return left == right
          }) else { return nil }
    let returnedTotal = consistent(["DataCount", "dataCount", "Total", "total"]) { integer($0, allowString: true) }
    let returnedPageCount = consistent(["PageCount", "pageCount"]) { integer($0) }
    guard returnedTotal.0, let total = returnedTotal.1, returnedPageCount.0,
          returnedPageCount.1 == total / pageSize + (total % pageSize == 0 ? 0 : 1),
          rows.count <= pageSize else { return nil }
    let offset = (page - 1).multipliedReportingOverflow(by: pageSize)
    guard !offset.overflow, page <= max(1, total / pageSize + (total % pageSize == 0 ? 0 : 1)),
          rows.count == min(pageSize, max(0, total - offset.partialValue)) else { return nil }
    return (rows, total)
}

func nativePublicArticleRows(_ rows: [[String: Any]]) -> Bool {
    let ids = rows.compactMap { row -> String? in
        let hasPascalId = row.keys.contains("Id")
        let hasCamelId = row.keys.contains("id")
        let value = hasPascalId ? row["Id"] : row["id"]
        guard let id = value as? String, let numericID = Int64(id), numericID > 0,
              String(numericID) == id,
              !(hasPascalId && hasCamelId && (row["id"] as? String) != id) else { return nil }
        return id
    }
    return ids.count == rows.count && Set(ids).count == ids.count
}

/** 校验附近活动分页和关键展示字段，避免坏回执被误显示为“附近暂无活动”。 */
func nativeNearbyActivityRows(_ response: [String: Any], page: Int, pageSize: Int) -> [[String: Any]]? {
    guard let parsed = nativePublicCatalogPage(response, page: page, pageSize: pageSize) else { return nil }
    var ids = Set<String>()
    for row in parsed.rows {
        let hasId = row.keys.contains("Id")
        let hasLowerId = row.keys.contains("id")
        guard let id = nativeCartID(hasId ? row["Id"] : row["id"]),
              !(hasId && hasLowerId && nativeCartID(row["id"]) != id),
              ids.insert(id).inserted else { return nil }

        let hasName = row.keys.contains("Name")
        let hasLowerName = row.keys.contains("name")
        guard let name = (hasName ? row["Name"] : row["name"]) as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !(hasName && hasLowerName && (row["name"] as? String) != name) else { return nil }

        let hasDistance = row.keys.contains("DistanceKm")
        let hasLowerDistance = row.keys.contains("distanceKm")
        if hasDistance || hasLowerDistance {
            let value = hasDistance ? row["DistanceKm"] : row["distanceKm"]
            if !(value is NSNull) {
                guard let number = value as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
            }
            if hasDistance && hasLowerDistance {
                guard let lowerValue = row["distanceKm"] else { return nil }
                if value is NSNull {
                    guard lowerValue is NSNull else { return nil }
                } else {
                    guard let number = value as? NSNumber, let lower = lowerValue as? NSNumber,
                          CFGetTypeID(number) != CFBooleanGetTypeID(), CFGetTypeID(lower) != CFBooleanGetTypeID(),
                          lower.doubleValue.isFinite,
                          lower.doubleValue == number.doubleValue else { return nil }
                }
            }
        }
    }
    return parsed.rows
}

/** 校验统一搜索的分页回执和业务结果字段，避免把缺页或错误结构显示为合法空结果。 */
func nativeSearchResultPage(_ response: [String: Any], page: Int, pageSize: Int) -> (rows: [[String: Any]], total: Int, pageCount: Int)? {
    guard let catalog = nativePublicCatalogPage(response, page: page, pageSize: pageSize), pageSize > 0 else { return nil }
    let pageCountValues = ["PageCount", "pageCount"].compactMap { response.keys.contains($0) ? response[$0] : nil }
    guard let firstPageCount = pageCountValues.first as? NSNumber,
          CFGetTypeID(firstPageCount) != CFBooleanGetTypeID(),
          firstPageCount.doubleValue.isFinite, firstPageCount.doubleValue.rounded(.towardZero) == firstPageCount.doubleValue,
          firstPageCount.doubleValue >= 0, firstPageCount.doubleValue <= Double(Int32.max),
          pageCountValues.dropFirst().allSatisfy({ value in
              guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
              return number.intValue == firstPageCount.intValue && number.doubleValue == firstPageCount.doubleValue
          }) else { return nil }
    let expectedPageCount = (catalog.total + pageSize - 1) / pageSize
    guard firstPageCount.intValue == expectedPageCount else { return nil }

    let supportedTypes: Set<String> = ["ScenicSpot", "GuideRoute", "Ticket", "Article", "Activity", "Product", "Hotel", "TravelRoute", "DiningStore"]
    func stringField(_ row: [String: Any], pascal: String, camel: String) -> String? {
        let values = [pascal, camel].compactMap { row.keys.contains($0) ? row[$0] : nil }
        guard let first = values.first as? String, values.dropFirst().allSatisfy({ ($0 as? String) == first }) else { return nil }
        return first
    }
    var keys = Set<String>()
    for row in catalog.rows {
        guard let id = stringField(row, pascal: "Id", camel: "id"), let numericID = Int64(id), numericID > 0,
              String(numericID) == id,
              let type = stringField(row, pascal: "Type", camel: "type"),
              supportedTypes.contains(where: { $0.caseInsensitiveCompare(type) == .orderedSame }),
              let title = stringField(row, pascal: "Title", camel: "title"), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let targetPath = stringField(row, pascal: "TargetPath", camel: "targetPath"), targetPath.hasPrefix("/") else { return nil }
        if !keys.insert("\(type.lowercased()):\(id)").inserted { return nil }
    }
    return (catalog.rows, catalog.total, firstPageCount.intValue)
}
