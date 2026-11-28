import Foundation

@main
struct TourismReservationRecoveryCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = try TourismReservationRecovery(principal: "visitor:session", directory: directory)
        let reopened = try TourismReservationRecovery(principal: "visitor:session", directory: directory)
        let other = try TourismReservationRecovery(principal: "visitor:other-session", directory: directory)
        let activity = try ActivityRegistrationRecovery(principal: "visitor:session", directory: directory)
        let id = "9007199254740993"
        let attempt = TourismReservationAttempt(id: id, action: .cancel)
        precondition(attempt.valid && attempt.matchesReceipt(id) && !attempt.matchesReceipt(9007199254740993 as Int64))
        precondition(!attempt.matchesReceipt("9007199254740994"))
        try initial.add(attempt)
        let persisted = try reopened.read()
        let otherRecord = try other.read()
        let activityRecord = try activity.read()
        precondition(persisted == attempt && otherRecord == nil && activityRecord == nil)
        do {
            try reopened.remove(TourismReservationAttempt(id: id, action: .cancel))
            preconditionFailure("不同操作标记不能解除核对保护")
        } catch let error as CocoaError {
            precondition(error.code == .fileReadCorruptFile)
        }
        try reopened.remove(attempt)
        let cleared = try initial.read()
        precondition(cleared == nil)
        precondition(TourismReservationReadStatus(rawValue: "Reserved") == .reserved)
        precondition(TourismReservationReadStatus(rawValue: "Unavailable") == .unavailable)
        precondition(TourismReservationReadStatus(rawValue: "Registered") == nil)
        print("iOS 景点预约核对验证通过")
    }
}
