import CryptoKit
import SwiftUI

protocol NativeMerchantRecoveryRecord: Codable, Equatable {
    var valid: Bool { get }
}

enum NativeMerchantRecoveryState<Record: NativeMerchantRecoveryRecord>: Equatable {
    case ready, unavailable, damaged, pending(Record)
}

struct NativeMerchantRecoveryStore<Record: NativeMerchantRecoveryRecord> {
    private let directoryName: String
    private let fileName: String

    init(directoryName: String, principal: String, merchantID: String) {
        self.directoryName = directoryName
        let digest = SHA256.hash(data: Data("\(principal):\(merchantID)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        fileName = "\(digest).json"
    }

    private func fileURL() throws -> URL {
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var directory = support.appendingPathComponent(directoryName, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try directory.setResourceValues(resources)
        return directory.appendingPathComponent(fileName)
    }

    func read() -> NativeMerchantRecoveryState<Record> {
        guard let url = try? fileURL() else { return .unavailable }
        do {
            let data = try Data(contentsOf: url)
            guard let record = try? JSONDecoder().decode(Record.self, from: data), record.valid else { return .damaged }
            return .pending(record)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .ready
        } catch { return .unavailable }
    }

    func save(_ record: Record) -> Bool {
        guard read() == .ready, record.valid else { return false }
        do {
            // 发出写请求前原子落盘并读回，应用重新启动后仍能核对原操作。
            try JSONEncoder().encode(record).write(to: fileURL(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return read() == .pending(record)
        } catch { return false }
    }

    func clear(_ state: NativeMerchantRecoveryState<Record>) -> Bool {
        guard state != .ready, state != .unavailable, read() == state else { return false }
        do {
            try FileManager.default.removeItem(at: fileURL())
            return read() == .ready
        } catch { return false }
    }
}

struct NativeMerchantFulfillmentAttempt: NativeMerchantRecoveryRecord {
    enum Kind: String, Codable {
        case express = "Express"
        case selfPickup = "SelfPickup"
        case handover = "Handover"

        var title: String {
            switch self {
            case .express: "登记快递"
            case .selfPickup: "登记到店自提"
            case .handover: "确认自提交付"
            }
        }
    }

    let orderID: String
    let merchantOrderID: String
    let kind: Kind
    let marker: UUID

    init(orderID: String, merchantOrderID: String, kind: Kind) {
        self.orderID = orderID
        self.merchantOrderID = merchantOrderID
        self.kind = kind
        marker = UUID()
    }

    var valid: Bool { trackingID(orderID) && (merchantOrderID == "0" || trackingID(merchantOrderID)) }

    func received(_ value: Any) -> Bool {
        if kind == .handover { return value as? String == orderID }
        guard let row = value as? [String: Any],
              let id = trackingField(row, "Id") as? String, trackingID(id),
              trackingField(row, "OrderId") as? String == orderID,
              trackingField(row, "MerchantOrderId") as? String == merchantOrderID else { return false }
        return trackingField(row, "FulfillmentType") as? String == kind.rawValue
            && trackingField(row, "Status") as? String == (kind == .express ? "InTransit" : "ReadyForPickup")
    }

    func completed(in shipments: [NativeMerchantShipment]) throws -> Bool {
        if kind == .handover {
            guard shipments.count == 1, let shipment = shipments.first, shipment.type == "SelfPickup" else {
                throw MobileAPIError.unavailable("未能核对原自提单，请保留待核对记录。")
            }
            return shipment.status == "PickedUp"
        }
        if shipments.isEmpty { return false }
        guard shipments.count == 1, shipments[0].type == kind.rawValue else {
            throw MobileAPIError.unavailable("实际履约方式与原操作不同，请先核对订单。")
        }
        return true
    }
}

@MainActor
final class NativeMerchantFulfillmentRecovery: ObservableObject {
    @Published private(set) var state = NativeMerchantRecoveryState<NativeMerchantFulfillmentAttempt>.unavailable
    @Published private(set) var busy = false
    @Published private(set) var canRelease = false
    @Published private(set) var message: String?
    private var operationID: UUID?

    func reload(merchantID: String, store: SessionStore) {
        guard !busy else { return }
        state = storage(merchantID: merchantID, store: store)?.read() ?? .unavailable
        canRelease = false; message = nil
    }

    func invalidate() {
        operationID = nil; busy = false
        state = .unavailable; canRelease = false; message = nil
    }

    private func storage(merchantID: String, store: SessionStore) -> NativeMerchantRecoveryStore<NativeMerchantFulfillmentAttempt>? {
        guard trackingID(merchantID), let principal = nativeTourismPrincipal(store.session?.accessToken) else { return nil }
        return .init(directoryName: "jhcti-merchant-fulfillment-v1", principal: principal, merchantID: merchantID)
    }

    private func run(merchantID: String, store: SessionStore,
        action: @MainActor (NativeMerchantRecoveryStore<NativeMerchantFulfillmentAttempt>, String, @MainActor () -> Bool) async -> Bool
    ) async -> Bool {
        guard !busy, !Task.isCancelled, let principal = nativeTourismPrincipal(store.session?.accessToken),
              let storage = storage(merchantID: merchantID, store: store) else { return false }
        let operation = UUID()
        operationID = operation; busy = true; message = nil
        defer {
            if operationID == operation {
                busy = false; operationID = nil
                if nativeTourismPrincipal(store.session?.accessToken) == principal { state = storage.read() }
            }
        }
        let current: @MainActor () -> Bool = {
            self.operationID == operation && !Task.isCancelled && nativeTourismPrincipal(store.session?.accessToken) == principal
        }
        return await action(storage, principal, current)
    }

    func submit(_ attempt: NativeMerchantFulfillmentAttempt, body: [String: String], merchantID: String, store: SessionStore) async -> Bool {
        await run(merchantID: merchantID, store: store) { storage, principal, current in
            guard storage.save(attempt) else {
                message = "无法保存履约待核对记录，本次操作未提交。"; return false
            }
            let pending = NativeMerchantRecoveryState.pending(attempt)
            state = pending; canRelease = false
            do {
                let action = attempt.kind == .handover ? "ConfirmPickup" : "Ship"
                let response = try await MobileAPI(store: store).post(
                    "/api/JHCTIMerchantOrder/\(action)?merchantId=\(merchantID)", body: body,
                    authenticated: true, expectedPrincipal: principal, canRefresh: false)
                guard current() else { return false }
                guard attempt.received(response) else { throw MobileAPIError.unavailable("履约回执与原操作不匹配。") }
                return finish(storage, expected: pending, recorded: true)
            } catch {
                guard current() else { return false }
                if let status = (error as? MobileAPIError)?.httpStatusCode, [400, 404, 422].contains(status), storage.clear(pending) {
                    message = error.localizedDescription
                } else { message = "履约结果尚未确认，请按原订单核对。" }
                return false
            }
        }
    }

    func verify(merchantID: String, store: SessionStore, release: Bool) async -> Bool {
        await run(merchantID: merchantID, store: store) { storage, principal, current in
            guard state == storage.read() else { canRelease = false; return false }
            if state == .damaged && release { return finish(storage, expected: .damaged, recorded: false) }
            guard case let .pending(attempt) = state, !release || canRelease else { return false }
            canRelease = false
            do {
                let value = try await MobileAPI(store: store).get(
                    "/api/JHCTIMerchantOrder/GetFulfillments?merchantId=\(merchantID)&orderId=\(attempt.orderID)&merchantOrderId=\(attempt.merchantOrderID)",
                    authenticated: true, expectedPrincipal: principal)
                guard current() else { return false }
                let shipments = try NativeMerchantShipment.list(value, orderID: attempt.orderID, merchantOrderID: attempt.merchantOrderID)
                let recorded = try attempt.completed(in: shipments)
                if recorded || release { return finish(storage, expected: .pending(attempt), recorded: recorded) }
                canRelease = true
                message = "暂未查到已完成的履约。请先核对实际发货或交付情况。"
            } catch {
                if current() { message = error.localizedDescription }
            }
            return false
        }
    }

    private func finish(_ storage: NativeMerchantRecoveryStore<NativeMerchantFulfillmentAttempt>,
                        expected: NativeMerchantRecoveryState<NativeMerchantFulfillmentAttempt>, recorded: Bool) -> Bool {
        let cleared = storage.clear(expected)
        message = cleared ? (recorded ? "已确认履约操作完成。" : "已解除履约待核对状态。")
            : "待核对记录清理失败，请重新读取。"
        return recorded
    }
}
