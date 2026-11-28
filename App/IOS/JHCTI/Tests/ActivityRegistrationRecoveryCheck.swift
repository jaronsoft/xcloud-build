import Foundation

@main
struct ActivityRegistrationRecoveryCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = try ActivityRegistrationRecovery(principal: "visitor:session", directory: directory)
        let reopened = try ActivityRegistrationRecovery(principal: "visitor:session", directory: directory)
        let other = try ActivityRegistrationRecovery(principal: "visitor:another-session", directory: directory)
        let attempt = ActivityRegistrationAttempt(id: "9007199254740993", action: .delete)
        precondition(attempt.valid && attempt.matchesReceipt(attempt.id) && !attempt.matchesReceipt(9007199254740993 as Int64))
        try initial.add(attempt)
        let persisted = try reopened.read()
        let otherValue = try other.read()
        precondition(persisted == attempt && otherValue == nil)
        let laterAttempt = ActivityRegistrationAttempt(id: attempt.id, action: .delete)
        do {
            try reopened.remove(laterAttempt)
            preconditionFailure("不同操作的回执不能清除原记录")
        } catch let error as CocoaError {
            precondition(error.code == .fileReadCorruptFile)
        }
        try reopened.remove(attempt)
        let cleared = try initial.read()
        precondition(cleared == nil)
        precondition(ActivityRegistrationReadStatus(rawValue: "Registered") == .registered)
        precondition(ActivityRegistrationReadStatus(rawValue: "Unavailable") == .unavailable)
        precondition(ActivityRegistrationReadStatus(rawValue: "Unknown") == nil)
        print("iOS 活动报名核对验证通过")
    }
}
