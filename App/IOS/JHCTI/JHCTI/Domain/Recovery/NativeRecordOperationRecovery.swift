import CryptoKit
import Foundation

enum ActivityRegistrationAction: String, Codable {
    case cancel = "CancelRegistration"
    case delete = "DeleteExpiredMyRegistration"

    var label: String { self == .cancel ? "取消报名" : "删除过期报名" }
}

struct NativeRecordOperationAttempt<Action: Codable & Equatable>: Codable, Equatable {
    let id: String
    let action: Action
    var marker = UUID()

    var valid: Bool { Int64(id).map { $0 > 0 && String($0) == id } == true }
    func matchesReceipt(_ value: Any) -> Bool { (value as? String) == id }
}

enum ActivityRegistrationReadStatus: String {
    case registered = "Registered"
    case cancelled = "Cancelled"
    case checkedIn = "CheckedIn"
    case unavailable = "Unavailable"
}

struct NativeRecordOperationRecovery<Action: Codable & Equatable> {
    private let file: URL

    fileprivate init(principal: String, folder: String, directory: URL?) throws {
        guard !principal.isEmpty,
              let root = (directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)?
                .appendingPathComponent(folder, isDirectory: true) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let digest = SHA256.hash(data: Data(principal.utf8)).map { String(format: "%02x", $0) }.joined()
        file = root.appendingPathComponent("\(digest)-v1.json")
    }

    func read() throws -> NativeRecordOperationAttempt<Action>? {
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        let attempt = try JSONDecoder().decode(NativeRecordOperationAttempt<Action>.self, from: data)
        guard attempt.valid else { throw CocoaError(.fileReadCorruptFile) }
        return attempt
    }

    func add(_ attempt: NativeRecordOperationAttempt<Action>) throws {
        guard try read() == nil, attempt.valid else { throw CocoaError(.fileWriteFileExists) }
        var directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try directory.setResourceValues(attributes)
        // 先原子写入核对标记，页面或进程重开仍可核对原操作。
        try JSONEncoder().encode(attempt).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        guard try read() == attempt else { throw CocoaError(.fileWriteUnknown) }
    }

    func remove(_ attempt: NativeRecordOperationAttempt<Action>) throws {
        guard try read() == attempt else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.removeItem(at: file)
        guard try read() == nil else { throw CocoaError(.fileWriteUnknown) }
    }
}

typealias ActivityRegistrationAttempt = NativeRecordOperationAttempt<ActivityRegistrationAction>
typealias ActivityRegistrationRecovery = NativeRecordOperationRecovery<ActivityRegistrationAction>

extension NativeRecordOperationRecovery where Action == ActivityRegistrationAction {
    init(principal: String, directory: URL? = nil) throws {
        try self.init(principal: principal, folder: "ActivityRegistrationRecovery", directory: directory)
    }
}

enum TourismReservationAction: String, Codable {
    case cancel = "CancelMine"
    case delete = "DeleteExpiredMine"

    var label: String { self == .cancel ? "取消预约" : "删除过期预约" }
}

enum TourismReservationReadStatus: String {
    case reserved = "Reserved"
    case cancelled = "Cancelled"
    case checkedIn = "CheckedIn"
    case unavailable = "Unavailable"
}

typealias TourismReservationAttempt = NativeRecordOperationAttempt<TourismReservationAction>
typealias TourismReservationRecovery = NativeRecordOperationRecovery<TourismReservationAction>

extension NativeRecordOperationRecovery where Action == TourismReservationAction {
    init(principal: String, directory: URL? = nil) throws {
        try self.init(principal: principal, folder: "TourismReservationRecovery", directory: directory)
    }
}
