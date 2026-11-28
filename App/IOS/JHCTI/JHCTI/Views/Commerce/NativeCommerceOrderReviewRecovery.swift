import Foundation

struct NativeProductReviewRecoveryMarker: NativeMerchantRecoveryRecord {
    let itemID: String
    var marker = UUID()

    var valid: Bool { validProductReviewItemID(itemID) }
}

func validProductReviewItemID(_ id: String) -> Bool {
    Int64(id).map { $0 > 0 && String($0) == id } == true
}

func nativeProductReviewRecoveryStore(principal: String, itemID: String) -> NativeMerchantRecoveryStore<NativeProductReviewRecoveryMarker> {
    NativeMerchantRecoveryStore(directoryName: "jhcti-commerce-review-recovery", principal: principal, scopeID: itemID)
}

func readNativeReviewedProductItems(_ value: Any, requested: [String]) throws -> Set<String> {
    guard let rows = value as? [String] else { throw MobileAPIError.unavailable("本人评价状态格式异常，请重新核对。") }
    let reviewed = Set(rows)
    guard reviewed.count == rows.count, reviewed.isSubset(of: Set(requested)) else {
        throw MobileAPIError.unavailable("本人评价状态与当前订单商品不一致，请重新核对。")
    }
    return reviewed
}

func nativeProductReviewReceiptMatches(_ value: Any, itemID: String) -> Bool {
    guard validProductReviewItemID(itemID), let row = value as? [String: Any] else { return false }
    let ids = ["OrderItemId", "orderItemId"].compactMap { row[$0] }
    return !ids.isEmpty && ids.allSatisfy { $0 as? String == itemID }
}
