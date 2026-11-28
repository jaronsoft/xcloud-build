import Foundation

struct NativeBuyerShipment: Identifiable {
    let id: String
    let type: String
    let status: String
    let carrier: String?
    let trackingNumber: String?
    let events: [[String: Any]]

    var canConfirm: Bool { type == "Express" && status == "InTransit" }
    var delivered: Bool { type == "Express" && status == "Delivered" }
}

func readNativeBuyerShipments(_ order: [String: Any], orderID: String) throws -> [NativeBuyerShipment] {
    func invalid() -> MobileAPIError { .unavailable("履约记录与原订单不匹配，请重新读取。") }
    guard trackingID(orderID), trackingField(order, "Id") as? String == orderID,
          let rows = trackingField(order, "Fulfillments") as? [[String: Any]] else { throw invalid() }
    var ids = Set<String>()
    return try rows.map { row in
        guard let id = trackingField(row, "Id") as? String, trackingID(id), ids.insert(id).inserted,
              trackingField(row, "OrderId") as? String == orderID,
              let merchantOrderID = trackingField(row, "MerchantOrderId") as? String,
              merchantOrderID == "0" || trackingID(merchantOrderID),
              let type = trackingField(row, "FulfillmentType") as? String, !type.isEmpty,
              let status = trackingField(row, "Status") as? String, !status.isEmpty else { throw invalid() }
        return NativeBuyerShipment(id: id, type: type, status: status,
            carrier: trackingField(row, "CarrierName") as? String,
            trackingNumber: trackingField(row, "TrackingNumber") as? String,
            events: trackingField(row, "Events") as? [[String: Any]] ?? [])
    }
}

struct NativeShipmentReceiptAttempt: NativeMerchantRecoveryRecord {
    let shipmentID: String
    var marker = UUID()
    var valid: Bool { trackingID(shipmentID) }
}

typealias NativeShipmentReceiptState = NativeMerchantRecoveryState<NativeShipmentReceiptAttempt>

func nativeShipmentReceiptStore(principal: String, orderID: String) -> NativeMerchantRecoveryStore<NativeShipmentReceiptAttempt> {
    NativeMerchantRecoveryStore(directoryName: "jhcti-buyer-shipment-receipt", principal: principal, scopeID: orderID)
}

extension NativeMerchantRecoveryState where Record == NativeShipmentReceiptAttempt {
    var attempt: NativeShipmentReceiptAttempt? {
        if case let .pending(attempt) = self { return attempt }
        return nil
    }

    func canConfirm(_ shipment: NativeBuyerShipment, verified: UUID?) -> Bool {
        guard shipment.canConfirm else { return false }
        if self == .ready { return true }
        return attempt?.shipmentID == shipment.id && attempt?.marker == verified
    }
}
