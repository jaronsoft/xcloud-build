import Foundation
import CryptoKit

struct NativeTicketOrderAttempt: Codable {
    let idempotencyKey: String
    let resourceID: String
    let expectedAmountCents: Int
    let requestBody: Data

    var isValid: Bool {
        let body = (try? JSONSerialization.jsonObject(with: requestBody)) as? [String: Any]
        return idempotencyKey.range(of: "^[A-Za-z0-9._:-]{16,100}$", options: .regularExpression) != nil
            && Int64(resourceID).map { $0 > 0 } == true && expectedAmountCents >= 0
            && body?["IdempotencyKey"] as? String == idempotencyKey
    }
}

func nativeTicketOrderRecoveryStorageKey(accessToken: String, resourceID: String) -> String {
    let parts = accessToken.split(separator: ".")
    var principal: String?
    if parts.count == 3 {
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        if let data = Data(base64Encoded: payload),
           let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let subject = claims["sub"] as? String, !subject.isEmpty {
            let identity = claims["TourismIdentity"] as? String == "Tourism" ? "Tourism" : "SiteServer"
            principal = "\(identity):\(subject)"
        }
    }
    guard let principal else { return "" }
    let digest = SHA256.hash(data: Data(principal.utf8)).map { String(format: "%02x", $0) }.joined()
    return "jhcti.native.ticket-order-attempt.v1.\(digest).\(resourceID)"
}

func nativeTradeRecoveryStorageKey(accessToken: String) -> String {
    let parts = accessToken.split(separator: ".")
    var principal: String?
    var identity = "SiteServer"
    if parts.count == 3 {
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        if let data = Data(base64Encoded: payload),
           let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            principal = (claims["sub"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            identity = claims["TourismIdentity"] as? String == "Tourism" ? "Tourism" : "SiteServer"
        }
    }
    let subject = principal ?? SHA256.hash(data: Data(accessToken.utf8)).map { String(format: "%02x", $0) }.joined()
    let identityHash = SHA256.hash(data: Data("\(identity):\(subject)".utf8)).map { String(format: "%02x", $0) }.joined()
    return "jhcti.native.trade-order-attempt.v1.\(identityHash)"
}

func nativeLegacyTradeRecoveryStorageKey(accessToken: String) -> String {
    let parts = accessToken.split(separator: ".")
    var principal: String?
    if parts.count == 3 {
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        if let data = Data(base64Encoded: payload),
           let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            principal = (claims["sub"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
    }
    let subject = principal ?? SHA256.hash(data: Data(accessToken.utf8)).map { String(format: "%02x", $0) }.joined()
    let identityHash = SHA256.hash(data: Data(subject.utf8)).map { String(format: "%02x", $0) }.joined()
    return "jhcti.native.trade-order-attempt.v1.\(identityHash)"
}

func nativeMerchantAfterSaleLockStorageKey(accessToken: String, merchantID: String) -> String {
    let parts = accessToken.split(separator: ".")
    var principal: String?
    if parts.count == 3 {
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        if let data = Data(base64Encoded: payload),
           let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let subject = claims["sub"] as? String, !subject.isEmpty {
            let identity = claims["TourismIdentity"] as? String == "Tourism" ? "Tourism" : "SiteServer"
            principal = "\(identity):\(subject)"
        }
    }
    let subject = principal ?? accessToken
    let digest = SHA256.hash(data: Data(subject.utf8)).map { String(format: "%02x", $0) }.joined()
    return "jhcti.native.merchant-aftersale-unknown.v1.\(digest).\(merchantID)"
}

func nativeBuyerAfterSaleLockStorageKey(accessToken: String, orderID: String) -> String {
    let parts = accessToken.split(separator: ".")
    var principal: String?
    if parts.count == 3 {
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        if let data = Data(base64Encoded: payload),
           let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let subject = claims["sub"] as? String, !subject.isEmpty {
            let identity = claims["TourismIdentity"] as? String == "Tourism" ? "Tourism" : "SiteServer"
            principal = "\(identity):\(subject)"
        }
    }
    let subject = principal ?? accessToken
    let digest = SHA256.hash(data: Data(subject.utf8)).map { String(format: "%02x", $0) }.joined()
    return "jhcti.native.buyer-aftersale-unknown.v1.\(digest).\(orderID)"
}

struct NativeBuyerAfterSaleAttempt {
    let idempotencyKey: String
    let orderID: String
    let itemID: String
    let createdAt: Double
    let retryAuthorized: Bool
    let requestBody: [String: Any]
    let storedData: Data
}

func nativeBuyerAfterSaleAttemptStorageKey(accessToken: String, orderID: String, itemID: String) -> String {
    let digest = SHA256.hash(data: Data("\(nativeTourismPrincipalFromToken(accessToken)):\(orderID):\(itemID)".utf8))
        .map { String(format: "%02x", $0) }.joined()
    return "jhcti.native.buyer-aftersale-attempt.v1.\(digest)"
}

func decodeNativeBuyerAfterSaleAttempt(_ data: Data) -> NativeBuyerAfterSaleAttempt? {
    guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let idempotencyKey = value["IdempotencyKey"] as? String,
          idempotencyKey.range(of: "^[A-Za-z0-9._:-]{16,100}$", options: .regularExpression) != nil,
          let orderID = value["OrderId"] as? String, Int64(orderID).map({ $0 > 0 }) == true,
          let itemID = value["OrderItemId"] as? String, Int64(itemID).map({ $0 > 0 }) == true,
          let createdAt = value["CreatedAt"] as? Double, createdAt > 0,
          let requestBody = value["RequestBody"] as? [String: Any],
          requestBody["IdempotencyKey"] as? String == idempotencyKey,
          requestBody["OrderId"] as? String == orderID,
          let requestItems = requestBody["Items"] as? [[String: Any]], requestItems.count == 1,
          requestItems[0]["OrderItemId"] as? String == itemID,
          let quantity = requestItems[0]["Quantity"] as? Int, quantity > 0,
          ["RefundOnly", "ReturnAndRefund"].contains(requestBody["RequestType"] as? String ?? ""),
          requestBody["ReasonCode"] as? String != nil, requestBody["Description"] as? String != nil,
          let evidence = requestBody["EvidenceUrls"] as? [String] else { return nil }
    _ = evidence
    return NativeBuyerAfterSaleAttempt(idempotencyKey: idempotencyKey, orderID: orderID, itemID: itemID,
        createdAt: createdAt, retryAuthorized: value["RetryAuthorized"] as? Bool ?? false,
        requestBody: requestBody, storedData: data)
}

func encodeNativeBuyerAfterSaleAttempt(_ attempt: NativeBuyerAfterSaleAttempt, retryAuthorized: Bool) -> Data? {
    let record: [String: Any] = ["IdempotencyKey": attempt.idempotencyKey, "OrderId": attempt.orderID,
        "OrderItemId": attempt.itemID, "CreatedAt": attempt.createdAt, "RetryAuthorized": retryAuthorized,
        "RequestBody": attempt.requestBody]
    return try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
}
