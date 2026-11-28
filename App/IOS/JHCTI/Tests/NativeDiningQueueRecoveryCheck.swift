import Foundation

@main
struct NativeDiningQueueRecoveryCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionID = "9007199254740993"
        let entryID = "9007199254740994"
        let storeID = "11"
        let day = "2026-11-28"
        let operation = NativeDiningQueueAttempt(action: .complete, storeID: storeID, date: day,
            sessionID: sessionID, entryID: entryID, number: 21)
        let storage = try NativeDiningQueueRecovery(principal: "account:session", storeID: storeID, directory: directory)
        let reopened = try NativeDiningQueueRecovery(principal: "account:session", storeID: storeID, directory: directory)
        let otherStore = try NativeDiningQueueRecovery(principal: "account:session", storeID: "12", directory: directory)
        let otherSession = try NativeDiningQueueRecovery(principal: "account:new", storeID: storeID, directory: directory)
        try storage.add(operation)
        let saved = try reopened.read()
        let isolatedStore = try otherStore.read()
        let isolatedSession = try otherSession.read()
        precondition(saved == operation && isolatedStore == nil && isolatedSession == nil)

        let stale = NativeDiningQueueAttempt(action: .complete, storeID: storeID, date: day,
            sessionID: sessionID, entryID: entryID, number: 21)
        do {
            try storage.remove(stale)
            preconditionFailure("旧回执不能清除本次操作")
        } catch let error as CocoaError { precondition(error.code == .fileReadCorruptFile) }
        precondition(operation.matchesReceipt(entryID) && !operation.matchesReceipt(sessionID))
        precondition(NativeDiningQueueAttempt.dateValue("2026-02-30") == nil)
        precondition(nativeQueueDayMatches("2026-11-27T16:00:00Z", day))
        precondition(!nativeQueueDayMatches("2026-11-28T29:00:00", day))

        let call = NativeDiningQueueAttempt(action: .call, storeID: storeID, date: day, sessionID: sessionID,
            entryID: nil, number: nil)
        var row: [String: Any] = ["Id": entryID, "SessionId": sessionID, "StoreId": storeID, "QueueDate": day,
            "QueueNumber": 21, "Status": "Called", "UserId": "1", "GuestName": "模拟顾客", "GuestPhone": "12345678",
            "GuestCount": 2, "CreateTime": "2026-11-28T09:00:00"]
        precondition(call.matchesReceipt(row))
        let page = ["Page": 2, "PageSize": 20, "DataCount": 21, "Data": [row]] as [String: Any]
        precondition(nativeDiningQueuePage(page, page: 2, pageSize: 20, sessionID: sessionID, storeID: storeID, queueDate: day)?.rows.count == 1)
        var truncated = page
        truncated["Data"] = [[String: Any]]()
        precondition(nativeDiningQueuePage(truncated, page: 2, pageSize: 20, sessionID: sessionID, storeID: storeID, queueDate: day) == nil)
        row["sessionId"] = "123"
        precondition(!call.matchesReceipt(row))
        try reopened.remove(operation)
        let removed = try storage.read()
        precondition(removed == nil)
        print("iOS 餐饮排队核对校验通过")
    }
}
