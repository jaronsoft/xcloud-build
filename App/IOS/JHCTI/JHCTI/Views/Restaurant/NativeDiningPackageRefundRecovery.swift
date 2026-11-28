import SwiftUI

struct NativeDiningRefundAttempt: Codable, Equatable, Identifiable {
    let orderID: String
    let credentialID: String
    let requestID: String
    var id: String { requestID }

    init(orderID: String, credentialID: String,
         requestID: String = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")) {
        self.orderID = orderID
        self.credentialID = credentialID
        self.requestID = requestID
    }

    var valid: Bool {
        trackingID(orderID) && trackingID(credentialID) && requestID.utf8.count == 32
            && requestID.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && requestID.utf8.contains { $0 != 48 }
    }

    func receipt(_ value: Any) throws -> (number: String, status: String) {
        guard let row = value as? [String: Any],
              trackingField(row, "RequestId") as? String == requestID,
              trackingField(row, "CredentialIds") as? [String] == [credentialID],
              let refund = validatedDiningPackageRefunds([row], expectedOrderID: orderID)?.first,
              refund["CredentialCount"] as? Int == 1,
              let number = refund["RefundNo"] as? String, let status = refund["Status"] as? String else {
            throw MobileAPIError.unavailable("退款回执与原申请不匹配，请重新查询。")
        }
        return (number, status)
    }
}

struct NativeDiningRefundAttempts: NativeMerchantRecoveryRecord {
    let entries: [NativeDiningRefundAttempt]

    var valid: Bool {
        !entries.isEmpty && entries.allSatisfy(\.valid)
            && Set(entries.map(\.credentialID)).count == entries.count
            && Set(entries.map(\.requestID)).count == entries.count
    }
}

@MainActor
final class NativeDiningPackageRefundRecovery: ObservableObject {
    private typealias Storage = NativeMerchantRecoveryStore<NativeDiningRefundAttempts>
    private typealias State = NativeMerchantRecoveryState<NativeDiningRefundAttempts>

    @Published private(set) var attempts: [NativeDiningRefundAttempt]?
    @Published private(set) var busy = false
    @Published private(set) var missingRequestID: String?
    @Published private(set) var message: String?
    private var operation: UUID?

    private func storage(principal: String) -> Storage {
        .init(directoryName: "jhcti-dining-package-refund-v1", principal: principal, merchantID: "buyer")
    }

    private func records(_ state: State) -> [NativeDiningRefundAttempt]? {
        switch state {
        case .ready: []
        case .pending(let record): record.entries
        case .damaged, .unavailable: nil
        }
    }

    func reload(store: SessionStore) {
        guard !busy else { return }
        attempts = nativeTourismPrincipal(store.session?.accessToken).flatMap { records(storage(principal: $0).read()) }
        missingRequestID = nil
    }

    func invalidate() {
        operation = nil; attempts = nil; busy = false; missingRequestID = nil; message = nil
    }

    private func run(store: SessionStore,
                     action: @MainActor (Storage, String, @MainActor () -> Bool) async -> Bool) async -> Bool {
        guard !busy, !Task.isCancelled, let principal = nativeTourismPrincipal(store.session?.accessToken) else { return false }
        let storage = storage(principal: principal)
        let id = UUID()
        operation = id; busy = true; message = nil
        defer {
            if operation == id {
                if nativeTourismPrincipal(store.session?.accessToken) == principal { attempts = records(storage.read()) }
                operation = nil; busy = false
            }
        }
        return await action(storage, principal, {
            self.operation == id && !Task.isCancelled && nativeTourismPrincipal(store.session?.accessToken) == principal
        })
    }

    func submit(_ attempt: NativeDiningRefundAttempt, reason: String, store: SessionStore,
                onDispatched: @MainActor () -> Void) async -> Bool {
        await run(store: store) { storage, principal, current in
            let previous = storage.read()
            guard let records = records(previous), !records.contains(where: { $0.credentialID == attempt.credentialID }) else {
                message = "请先核对原退款申请或恢复本地存储。"; return false
            }
            let next = NativeDiningRefundAttempts(entries: records + [attempt])
            guard storage.replace(previous, with: next) else {
                message = "无法保存待核对记录，退款申请未发送。"; return false
            }
            attempts = next.entries; missingRequestID = nil
            onDispatched()
            do {
                let result = try await MobileAPI(store: store).post("/api/JHCTIDiningPackage/RequestRefund",
                    body: ["OrderId": attempt.orderID, "CredentialIds": [attempt.credentialID],
                           "RequestId": attempt.requestID, "Reason": reason],
                    authenticated: true, expectedPrincipal: principal, canRefresh: false)
                guard current() else { return false }
                let confirmed = try attempt.receipt(result)
                return finish(storage: storage, expected: .pending(next), attempt: attempt, confirmed: confirmed)
            } catch {
                if current() { message = "退款申请结果待核对，请查询原申请。" }
                return false
            }
        }
    }

    func lookup(_ attempt: NativeDiningRefundAttempt, release: Bool, store: SessionStore) async -> Bool {
        await run(store: store) { storage, principal, current in
            let expected = storage.read()
            guard records(expected)?.contains(attempt) == true, !release || missingRequestID == attempt.requestID else { return false }
            missingRequestID = nil
            do {
                let path = "/api/JHCTIDiningPackage/GetMyRefundRequest?orderId=\(attempt.orderID)&requestId=\(attempt.requestID)"
                let response = try await MobileAPI(store: store).get(path, authenticated: true, expectedPrincipal: principal, requireExplicitResponse: true)
                guard current() else { return false }
                if response is NSNull && !release {
                    missingRequestID = attempt.requestID
                    return false
                }
                let confirmed = response is NSNull ? nil : try attempt.receipt(response)
                return finish(storage: storage, expected: expected, attempt: attempt, confirmed: confirmed)
            } catch {
                if current() { message = error.localizedDescription }
                return false
            }
        }
    }

    private func finish(storage: Storage, expected: State, attempt: NativeDiningRefundAttempt,
                        confirmed: (number: String, status: String)?) -> Bool {
        let remaining = records(expected)?.filter { $0 != attempt } ?? []
        let cleared = remaining.isEmpty ? storage.clear(expected)
            : storage.replace(expected, with: NativeDiningRefundAttempts(entries: remaining))
        guard cleared else { message = "待核对记录未能清除，请重新查询。"; return false }
        if let confirmed {
            message = "退款单 \(confirmed.number) · \(nativeDiningRefundStatus(confirmed.status))"
        } else {
            message = "复查未找到原申请。可查看最新凭证状态后重新申请。"
        }
        return true
    }
}

func nativeDiningRefundStatus(_ value: String) -> String {
    ["Requested": "待审核", "Processing": "退款处理中", "Refunded": "已退款", "Rejected": "未通过", "Failed": "退款失败"][value] ?? "状态待确认"
}
