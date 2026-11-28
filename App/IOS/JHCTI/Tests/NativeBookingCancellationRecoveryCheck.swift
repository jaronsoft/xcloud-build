import Foundation

@main
struct NativeBookingCancellationRecoveryCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = "9007199254740993"
        let previous = "2026-11-27T08:00:00+08:00"
        let order: [String: Any] = ["Id": id, "Status": "Paid", "CancelRequestedAt": previous, "OwnerContactPhone": "private-probe"]
        let attempt = NativeBookingCancellationAttempt(order: order)
        let principal = "test-account:test-session"
        let recovery = try NativeBookingCancellationRecovery(principal: principal, kind: "hotel", directory: directory)
        let sameSession = try NativeBookingCancellationRecovery(principal: principal, kind: "hotel", directory: directory)
        let nextLogin = try NativeBookingCancellationRecovery(principal: "test-account:new-session", kind: "hotel", directory: directory)
        let route = try NativeBookingCancellationRecovery(principal: principal, kind: "route", directory: directory)

        try expect(recovery.read().isEmpty)
        try expect(recovery.add(attempt) == [attempt])
        try expect(sameSession.read() == [attempt])
        try expect(nextLogin.read().isEmpty)
        try expect(route.read().isEmpty)
        let saved = try String(contentsOf: recovery.file, encoding: .utf8)
        precondition(!saved.contains(principal) && !saved.contains("private-probe"))
        precondition(!attempt.hasProgress(["Id": "9007199254740994", "Status": "Refunded"]))
        precondition(!attempt.hasProgress(["Id": id, "Status": "Paid", "CancelRequestedAt": "2026-11-27T00:00:00Z"]))
        precondition(attempt.hasProgress(["Id": id, "Status": "Paid", "CancelRequestedAt": "2026-11-27T00:00:01Z"]))
        precondition(attempt.hasProgress(["Id": id, "Status": "RefundProcessing"]))
        expectFailure { _ = try recovery.add(NativeBookingCancellationAttempt(order: order)) }
        expectFailure { _ = try recovery.remove(NativeBookingCancellationAttempt(order: order)) }
        try expect(recovery.remove(attempt).isEmpty)
        try expect(sameSession.read().isEmpty)
        try Data("损坏记录".utf8).write(to: recovery.file, options: .atomic)
        expectFailure { _ = try recovery.add(attempt) }
        print("iOS 取消恢复记录校验通过")
    }

    static func expect(_ condition: @autoclosure () throws -> Bool) throws {
        let passed = try condition()
        precondition(passed)
    }

    static func expectFailure(_ operation: () throws -> Void) {
        do { try operation(); preconditionFailure("异常操作应保留记录并停止执行") }
        catch { }
    }
}
