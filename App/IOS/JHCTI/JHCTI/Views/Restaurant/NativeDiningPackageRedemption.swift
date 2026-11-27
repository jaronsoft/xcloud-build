import Foundation
import SwiftUI

struct NativeDiningRedemptionAttempt: NativeMerchantRecoveryRecord {
    let storeID: String
    let requestID: String

    init(storeID: String, requestID: String = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")) {
        self.storeID = storeID
        self.requestID = requestID
    }

    var valid: Bool {
        trackingID(storeID) && requestID.utf8.count == 32
            && requestID.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && requestID.utf8.contains { $0 != 48 }
    }
}

struct NativeDiningRedemptionReceipt {
    let orderNo: String
    let packageName: String
    let redeemedAt: String

    init(_ value: Any, attempt: NativeDiningRedemptionAttempt) throws {
        guard let row = value as? [String: Any],
              trackingField(row, "StoreId") as? String == attempt.storeID,
              trackingField(row, "RequestId") as? String == attempt.requestID,
              trackingField(row, "Status") as? String == "Redeemed",
              let orderNo = (trackingField(row, "OrderNo") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let packageName = (trackingField(row, "PackageName") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !orderNo.isEmpty, !packageName.isEmpty,
              let time = trackingField(row, "RedeemedAt") as? String,
              let redeemedAt = bookingBusinessDateTime(time.replacingOccurrences(of: " ", with: "T")) else {
            throw MobileAPIError.unavailable("核销回执与原请求不匹配，请重新查询。")
        }
        self.orderNo = orderNo
        self.packageName = packageName
        self.redeemedAt = redeemedAt
    }
}

@MainActor
final class NativeDiningPackageRedemption: ObservableObject {
    typealias State = NativeMerchantRecoveryState<NativeDiningRedemptionAttempt>
    private typealias Storage = NativeMerchantRecoveryStore<NativeDiningRedemptionAttempt>

    @Published private(set) var state = State.unavailable
    @Published private(set) var busy = false
    @Published private(set) var canRelease = false
    @Published private(set) var accessRevoked = false
    @Published private(set) var receipt: NativeDiningRedemptionReceipt?
    @Published private(set) var notice: String?
    private var operationID: UUID?

    private func storage(storeID: String, principal: String) -> Storage {
        .init(directoryName: "jhcti-dining-package-redemption-v1", principal: principal, merchantID: storeID)
    }

    func reload(storeID: String, store: SessionStore) {
        guard trackingID(storeID), let principal = nativeTourismPrincipal(store.session?.accessToken), !busy else { return }
        state = storage(storeID: storeID, principal: principal).read()
        accessRevoked = false; canRelease = false
    }

    func invalidate() {
        operationID = nil; busy = false
        accessRevoked = false; state = .unavailable; canRelease = false
        clearFeedback()
    }

    func clearFeedback() { receipt = nil; notice = nil }

    private func run(storeID: String, store: SessionStore,
        action: @MainActor (Storage, String, @MainActor () -> Bool) async -> Void) async {
        guard !busy, !accessRevoked, !Task.isCancelled, trackingID(storeID),
              let principal = nativeTourismPrincipal(store.session?.accessToken) else { return }
        let storage = storage(storeID: storeID, principal: principal)
        let op = UUID()
        operationID = op; busy = true; clearFeedback()
        defer {
            if operationID == op {
                operationID = nil; busy = false
                if nativeTourismPrincipal(store.session?.accessToken) == principal { state = storage.read() }
            }
        }
        let current: @MainActor () -> Bool = {
            self.operationID == op && !Task.isCancelled && nativeTourismPrincipal(store.session?.accessToken) == principal
        }
        await action(storage, principal, current)
    }

    func submit(code: String, storeID: String, store: SessionStore, onDispatched: @MainActor () -> Void) async {
        guard state == .ready, (1...128).contains(code.utf16.count) else { return }
        await run(storeID: storeID, store: store) { storage, principal, current in
            let attempt = NativeDiningRedemptionAttempt(storeID: storeID)
            guard storage.save(attempt) else { notice = "无法保存待核对记录，核销请求未发送。"; return }
            let expected = State.pending(attempt)
            state = expected; canRelease = false
            onDispatched()
            do {
                let result = try await MobileAPI(store: store).post("/api/JHCTIDiningPackage/Redeem",
                    body: ["StoreId": storeID, "Code": code, "RequestId": attempt.requestID],
                    authenticated: true, expectedPrincipal: principal, canRefresh: false)
                guard current() else { return }
                let confirmed = try NativeDiningRedemptionReceipt(result, attempt: attempt)
                finish(storage: storage, expected: expected, receipt: confirmed)
            } catch {
                guard current() else { return }
                let status = (error as? MobileAPIError)?.httpStatusCode
                if let status, [400, 401, 403, 404].contains(status), storage.clear(expected) {
                    notice = error.localizedDescription
                } else { notice = "核销结果暂时无法确认，请先查询原请求。" }
                accessRevoked = status == 403
            }
        }
    }

    func lookup(storeID: String, store: SessionStore, release: Bool) async {
        await run(storeID: storeID, store: store) { storage, principal, current in
            let expected = storage.read()
            guard expected == state, case let .pending(attempt) = expected, attempt.storeID == storeID,
                  !release || canRelease else { canRelease = false; return }
            canRelease = false
            do {
                let path = "/api/JHCTIDiningPackage/GetRedeemReceipt?storeId=\(attempt.storeID)&requestId=\(attempt.requestID)"
                let value = try await MobileAPI(store: store).get(path, authenticated: true,
                    expectedPrincipal: principal, requireExplicitResponse: true)
                guard current(), storage.read() == expected else { return }
                if value is NSNull && !release {
                    canRelease = true; notice = "暂未查到成功回执，可稍后再查，或请门店负责人核对原请求。"
                    return
                }
                let confirmed = value is NSNull ? nil : try NativeDiningRedemptionReceipt(value, attempt: attempt)
                finish(storage: storage, expected: expected, receipt: confirmed)
            } catch {
                guard current() else { return }
                notice = error.localizedDescription
                accessRevoked = (error as? MobileAPIError)?.httpStatusCode == 403
            }
        }
    }

    private func finish(storage: Storage, expected: State, receipt: NativeDiningRedemptionReceipt?) {
        guard storage.clear(expected) else { notice = "待核对记录未能清除，请重新查询。"; return }
        self.receipt = receipt
        if receipt == nil { notice = "已结束本地等待，可继续处理其他凭证。" }
    }
}
