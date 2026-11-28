import Foundation

@main
struct NativeDiningReservationRecoveryCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = "9007199254740993"
        let principal = "account:session"
        let attempt = NativeDiningReservationAttempt(id: id, storeID: "11", previous: "Pending", target: "Confirmed")
        let otherStore = NativeDiningReservationAttempt(id: "9007199254740994", storeID: "12", previous: "Confirmed", target: "Cancelled")
        let first = try NativeDiningReservationRecovery(principal: "account:session", directory: directory)
        let reopened = try NativeDiningReservationRecovery(principal: "account:session", directory: directory)
        let nextLogin = try NativeDiningReservationRecovery(principal: "account:next-session", directory: directory)
        try first.add(attempt)
        try first.add(otherStore)
        let saved = try reopened.read()
        let nextLoginAttempts = try nextLogin.read()
        precondition(saved == [attempt, otherStore] && nextLoginAttempts.isEmpty)
        precondition(attempt.readStatus(["Id": id, "StoreId": "11", "Status": "Pending"]) == "Pending")
        precondition(attempt.readStatus(["id": id, "storeId": "11", "status": "Confirmed"]) == "Confirmed")
        precondition(attempt.readStatus(["Id": id, "StoreId": "12", "Status": "Confirmed"]) == nil)
        precondition(attempt.readStatus(["Id": id, "id": otherStore.id, "StoreId": "11", "Status": "Confirmed"]) == nil)
        precondition(attempt.readStatus(["Id": id, "StoreId": "11", "Status": "Unknown"]) == nil)
        let differentAttempt = NativeDiningReservationAttempt(id: id, storeID: "11", previous: "Pending", target: "Confirmed")
        do { try first.remove(differentAttempt); preconditionFailure("旧回执不能移除其他尝试") }
        catch let error as CocoaError { precondition(error.code == .fileReadCorruptFile) }
        try first.remove(attempt)
        let remaining = try reopened.read()
        precondition(remaining == [otherStore])
        let withdrawal = NativeDiningReservationAttempt(id: id, storeID: "11", previous: "Pending", target: "Cancelled")
        let owner = try NativeDiningReservationRecovery(principal: "account:session", directory: directory, ownerWithdrawal: true)
        let reopenedOwner = try NativeDiningReservationRecovery(principal: "account:session", directory: directory, ownerWithdrawal: true)
        precondition(withdrawal.isValidForWithdrawal && !withdrawal.isValid)
        do { try owner.add(attempt); preconditionFailure("本人撤回不能复用岗位写入记录") }
        catch let error as CocoaError { precondition(error.code == .fileWriteFileExists) }
        try owner.add(withdrawal)
        let savedWithdrawal = try reopenedOwner.read()
        let savedStaff = try first.read()
        precondition(savedWithdrawal == [withdrawal] && savedStaff == [otherStore])
        let creation = try NativeDiningCreationRecovery(principal: principal, storeID: "11", directory: directory)
        let firstCreation = try creation.prepare(slotID: id, date: "2026-11-28", retry: nil)
        let reopenedCreation = try NativeDiningCreationRecovery(principal: principal, storeID: "11", directory: directory)
        let retried = try reopenedCreation.prepare(slotID: id, date: "2026-11-28", retry: firstCreation)
        precondition(retried == firstCreation)
        let otherCreationStore = try NativeDiningCreationRecovery(principal: principal, storeID: "12", directory: directory)
        let otherCreationSession = try NativeDiningCreationRecovery(principal: "account:new", storeID: "11", directory: directory)
        let storeIsolated = try otherCreationStore.read().isEmpty
        let sessionIsolated = try otherCreationSession.read().isEmpty
        precondition(storeIsolated && sessionIsolated)
        var receipt: [String: Any] = ["StoreId": "11", "SlotId": id, "IdempotencyKey": firstCreation.key,
                                      "ReservationId": NSNull(), "Status": NSNull()]
        let absent = try firstCreation.readReceipt(receipt, storeID: "11")
        precondition(absent == nil)
        receipt["ReservationId"] = id
        receipt["Status"] = "Declined"
        let found = try firstCreation.readReceipt(receipt, storeID: "11")
        precondition(found?.id == id && found?.status == "Declined")
        receipt["status"] = "Pending"
        do { _ = try firstCreation.readReceipt(receipt, storeID: "11"); preconditionFailure("冲突字段不能作为创建回执") }
        catch let error as CocoaError { precondition(error.code == .fileReadCorruptFile) }
        try reopenedCreation.remove(firstCreation)
        print("iOS 餐饮预订核对校验通过")
    }
}
