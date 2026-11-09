import Foundation
import CoreFoundation
import CryptoKit

// 按服务端 decimal(12,2) 范围转为分，不把显示层四舍五入后的数字当作交易依据。
func nativeTradeMoneyCents(_ raw: Any?) -> Int64? {
    let text: String
    if let number = raw as? NSNumber {
        guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        text = (number as? NSDecimalNumber)?.stringValue ?? String(number.doubleValue)
    } else if let value = raw as? String,
              let range = value.range(of: "^(0|[1-9][0-9]*)(\\.[0-9]+)?$", options: .regularExpression),
              range.lowerBound == value.startIndex, range.upperBound == value.endIndex {
        text = value
    } else { return nil }
    guard let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
          amount >= 0, amount <= Decimal(string: "9999999999.99")! else { return nil }
    var cents = amount * 100; var integral = Decimal()
    NSDecimalRound(&integral, &cents, 0, .plain)
    guard integral == cents else { return nil }
    return NSDecimalNumber(decimal: integral).int64Value
}

private func tradeSnapshotID(_ raw: Any?, zero: Bool = false) -> String? {
    guard let text = raw as? String, let value = Int64(text), value >= (zero ? 0 : 1), String(value) == text else { return nil }
    return text
}

func nativeTradePointInput(_ text: String) -> String? {
    if text.isEmpty { return "0" }
    guard text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int64(text), value >= 0 else { return nil }
    return String(value)
}

private func tradeSnapshotQuantity(_ raw: Any?) -> Int64? {
    guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
          value.doubleValue.rounded() == value.doubleValue, (1...99).contains(value.doubleValue) else { return nil }
    return value.int64Value
}

private func tradeSnapshotTrue(_ raw: Any?) -> Bool {
    guard let value = raw as? NSNumber else { return false }
    return CFGetTypeID(value) == CFBooleanGetTypeID() && value.boolValue
}

private struct TradeSnapshotLine: Hashable {
    let product: String; let sku: String; let store: String; let name: String; let code: String
    let quantity: Int64; let price: Int64; let amount: Int64; let delivery: String
}

private func tradeSnapshotLine(_ value: [String: Any], order: Bool) -> TradeSnapshotLine? {
    guard let product = tradeSnapshotID(value["ProductId"]), let sku = tradeSnapshotID(value["SkuId"]),
          let store = tradeSnapshotID(value["StoreId"], zero: true),
          let name = value["ProductName"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let code = value["SkuCode"] as? String, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let quantity = tradeSnapshotQuantity(value["Quantity"]),
          let price = nativeTradeMoneyCents(value[order ? "UnitPrice" : "CurrentPrice"]),
          let amount = nativeTradeMoneyCents(value[order ? "LineAmount" : "Subtotal"]), price * quantity == amount else { return nil }
    if let raw = value["DeliveryType"], !(raw is String) { return nil }
    let delivery = value["DeliveryType"] as? String ?? "Physical"
    guard !delivery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return TradeSnapshotLine(product: product, sku: sku, store: store,
        name: name.trimmingCharacters(in: .whitespacesAndNewlines), code: code.trimmingCharacters(in: .whitespacesAndNewlines),
        quantity: quantity, price: price, amount: amount, delivery: delivery)
}

private struct TradeQuoteSnapshot {
    let lines: [TradeSnapshotLine]; let ids: [String]; let stores: [String: String]
    let amounts: [Int64]; let points: String; let coupon: String?; let region: String
}

private func tradeSnapshotCoupon(_ value: Any?) -> (valid: Bool, id: String?) {
    if value == nil || value is NSNull || value as? String == "" { return (true, nil) }
    guard let id = tradeSnapshotID(value) else { return (false, nil) }
    return (true, id)
}

private func tradeQuoteSnapshot(_ quote: [String: Any]) -> TradeQuoteSnapshot? {
    guard tradeSnapshotID(quote["QuoteId"]) != nil, let rows = quote["Items"] as? [[String: Any]],
          !rows.isEmpty, rows.count <= 100, let region = quote["RegionCode"] as? String,
          !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let available = tradeSnapshotID(quote["AvailablePoints"], zero: true).flatMap(Int64.init),
          let maximum = tradeSnapshotID(quote["MaximumUsablePoints"], zero: true).flatMap(Int64.init),
          let points = tradeSnapshotID(quote["PointsUsed"], zero: true), let used = Int64(points),
          maximum <= available, used <= maximum else { return nil }
    let amounts = ["ProductAmount", "FreightAmount", "DiscountAmount", "PointsDiscountAmount", "PayableAmount"].compactMap { nativeTradeMoneyCents(quote[$0]) }
    guard amounts.count == 5, amounts[2] <= amounts[0], amounts[2] + amounts[3] <= 999999999999, used == amounts[3],
          maximum <= (amounts[0] + amounts[1] - amounts[2]) / 2,
          amounts[0] + amounts[1] - amounts[2] - amounts[3] == amounts[4] else { return nil }
    var ids: [String] = []; var lines: [TradeSnapshotLine] = []; var stores: [String: String] = [:]
    for row in rows {
        guard let id = tradeSnapshotID(row["Id"]), !ids.contains(id),
              tradeSnapshotTrue(row["IsValid"]), tradeSnapshotTrue(row["IsDeliverable"]),
              let merchant = tradeSnapshotID(row["MerchantId"], zero: true), let line = tradeSnapshotLine(row, order: false) else { return nil }
        if merchant != "0" {
            guard line.store != "0", stores[merchant] == nil || stores[merchant] == line.store else { return nil }
            stores[merchant] = line.store
        } else if line.store != "0" { return nil }
        ids.append(id); lines.append(line)
    }
    let coupon = tradeSnapshotCoupon(quote["CouponClaimId"])
    guard coupon.valid, coupon.id != nil || amounts[2] == 0,
          region.trimmingCharacters(in: .whitespacesAndNewlines) != "DIGITAL" || !lines.contains(where: { $0.delivery == "Physical" }),
          lines.reduce(Int64(0), { $0 + $1.amount }) == amounts[0] else { return nil }
    return TradeQuoteSnapshot(lines: lines, ids: ids, stores: stores, amounts: amounts,
        points: points, coupon: coupon.id, region: region.trimmingCharacters(in: .whitespacesAndNewlines))
}

func nativeTradeQuoteMatches(_ quote: [String: Any], cartIDs: [String], region: String,
                             stores: [String: String], coupon: String, points: String) -> Bool {
    guard let snapshot = tradeQuoteSnapshot(quote), !cartIDs.isEmpty, cartIDs.count <= 100,
          cartIDs.allSatisfy({ tradeSnapshotID($0) != nil }), Set(cartIDs).count == cartIDs.count,
          Set(snapshot.ids) == Set(cartIDs), snapshot.region == region.trimmingCharacters(in: .whitespacesAndNewlines),
          snapshot.stores == stores, snapshot.points == nativeTradePointInput(points) else { return false }
    let expectedCoupon = tradeSnapshotCoupon(coupon)
    return expectedCoupon.valid && expectedCoupon.id == snapshot.coupon
}

private func tradeDigest(_ parts: [String]) -> String {
    let framed = parts.map { part -> String in
        let normalized = part.precomposedStringWithCanonicalMapping
        return "\(normalized.utf8.count):\(normalized)"
    }.joined()
    return SHA256.hash(data: Data(framed.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func tradeOrderDigest(region: String, amounts: [Int64], points: String, coupon: String?, lines: [TradeSnapshotLine]) -> String {
    let lineHashes = lines.map { line in
        tradeDigest([line.product, line.sku, line.store, line.name, line.code, String(line.quantity),
            String(line.price), String(line.amount), line.delivery])
    }.sorted()
    return tradeDigest(["trade-order-snapshot-v1", "CNY", region] + amounts.map(String.init)
        + [points, coupon ?? "", String(lines.count)] + lineHashes)
}

func nativeTradeQuoteOrderDigest(_ quote: [String: Any]) -> String? {
    guard let snapshot = tradeQuoteSnapshot(quote) else { return nil }
    return tradeOrderDigest(region: snapshot.region, amounts: snapshot.amounts, points: snapshot.points,
        coupon: snapshot.coupon, lines: snapshot.lines)
}

// 状态不参与不可变金额摘要，支付后恢复仍可核对同一笔订单。
func nativeTradeOrderDigest(_ order: [String: Any]) -> String? {
    guard tradeSnapshotID(order["Id"]) != nil,
          let number = order["OrderNo"] as? String, !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let status = order["Status"] as? String,
          ["PendingPayment", "PendingShipment", "PendingPickup", "Shipped", "Completed", "Closed"].contains(status),
          order["Currency"] as? String == "CNY", let region = order["RegionCode"] as? String,
          !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let points = tradeSnapshotID(order["PointsUsed"], zero: true), let used = Int64(points),
          let rows = order["Items"] as? [[String: Any]], !rows.isEmpty, rows.count <= 100 else { return nil }
    let amounts = ["ProductAmount", "FreightAmount", "DiscountAmount", "PointsDiscountAmount", "PayableAmount"].compactMap { nativeTradeMoneyCents(order[$0]) }
    let coupon = tradeSnapshotCoupon(order["CouponClaimId"])
    guard amounts.count == 5, coupon.valid, coupon.id != nil || amounts[2] == 0,
          amounts[2] <= amounts[0], amounts[2] + amounts[3] <= 999999999999, used == amounts[3],
          used <= (amounts[0] + amounts[1] - amounts[2]) / 2,
          amounts[0] + amounts[1] - amounts[2] - amounts[3] == amounts[4] else { return nil }
    var lines: [TradeSnapshotLine] = []
    var ids = Set<String>(); var discount: Int64 = 0; var pointsDiscount: Int64 = 0
    for row in rows {
        guard let id = tradeSnapshotID(row["Id"]), ids.insert(id).inserted,
              let line = tradeSnapshotLine(row, order: true),
              let lineDiscount = nativeTradeMoneyCents(row["DiscountAmount"]),
              let linePoints = nativeTradeMoneyCents(row["PointsDiscountAmount"]),
              linePoints <= lineDiscount, lineDiscount - linePoints <= line.amount else { return nil }
        lines.append(line); discount += lineDiscount; pointsDiscount += linePoints
    }
    guard lines.reduce(Int64(0), { $0 + $1.amount }) == amounts[0],
          region != "DIGITAL" || !lines.contains(where: { $0.delivery == "Physical" }),
          discount == amounts[2] + amounts[3], pointsDiscount == amounts[3] else { return nil }
    return tradeOrderDigest(region: region, amounts: amounts, points: points, coupon: coupon.id, lines: lines)
}

func nativeTradeOrderMatchesQuote(_ order: [String: Any], quote: [String: Any]) -> Bool {
    guard order["Status"] as? String == "PendingPayment", let expected = nativeTradeQuoteOrderDigest(quote),
          let actual = nativeTradeOrderDigest(order) else { return false }
    return actual == expected
}

func nativeTradeRecoveryMatches(_ order: [String: Any], digest: String?) -> Bool {
    guard let digest, digest.count == 64,
          let actual = nativeTradeOrderDigest(order) else { return false }
    return actual == digest
}

func nativeTradeLegacyRecoveryMatches(_ order: [String: Any], quoteID: String) -> Bool {
    guard tradeSnapshotID(order["QuoteId"]) == quoteID else { return false }
    return nativeTradeOrderDigest(order) != nil
}
