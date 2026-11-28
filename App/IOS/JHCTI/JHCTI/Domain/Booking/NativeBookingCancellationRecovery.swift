import Foundation
import CryptoKit

struct NativeBookingCancellationAttempt: Codable, Equatable, Identifiable {
    let id: String
    let previousRequestedAt: String?
    let nonce: UUID

    init(order: [String: Any]) {
        id = order["Id"] as? String ?? ""
        previousRequestedAt = order["CancelRequestedAt"] as? String
        nonce = UUID()
    }

    var isValid: Bool {
        Int64(id).map { $0 > 0 && String($0) == id } == true
            && (previousRequestedAt == nil || nativeBusinessTimestamp(previousRequestedAt) != nil)
    }

    func hasProgress(_ order: [String: Any]) -> Bool {
        guard order["Id"] as? String == id else { return false }
        if ["Closed", "CancellationReview", "RefundProcessing", "GroupRefundProcessing", "Refunded"]
            .contains(order["Status"] as? String ?? "") { return true }
        guard let current = nativeBusinessTimestamp(order["CancelRequestedAt"]) else { return false }
        return current != nativeBusinessTimestamp(previousRequestedAt)
    }
}

struct NativeBookingCancellationRecovery {
    private struct Record: Codable {
        let scope: String
        let attempts: [NativeBookingCancellationAttempt]
    }

    let scope: String
    let file: URL

    init(principal: String, kind: String, directory: URL? = nil) throws {
        guard !principal.isEmpty, ["hotel", "route"].contains(kind) else { throw CocoaError(.fileReadCorruptFile) }
        guard let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BookingCancellation", isDirectory: true) else { throw CocoaError(.fileReadNoSuchFile) }
        scope = SHA256.hash(data: Data(principal.utf8)).map { String(format: "%02x", $0) }.joined()
        file = root.appendingPathComponent("\(kind)-v1.json")
    }

    func read() throws -> [NativeBookingCancellationAttempt] {
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard !record.scope.isEmpty, record.attempts.allSatisfy(\.isValid),
              Set(record.attempts.map(\.id)).count == record.attempts.count else { throw CocoaError(.fileReadCorruptFile) }
        return record.scope == scope ? record.attempts : []
    }

    func add(_ attempt: NativeBookingCancellationAttempt) throws -> [NativeBookingCancellationAttempt] {
        let attempts = try read()
        guard attempt.isValid, !attempts.contains(where: { $0.id == attempt.id }) else { throw CocoaError(.fileWriteFileExists) }
        return try write(attempts + [attempt])
    }

    func remove(_ attempt: NativeBookingCancellationAttempt) throws -> [NativeBookingCancellationAttempt] {
        let attempts = try read()
        guard attempts.contains(attempt) else { throw CocoaError(.fileReadCorruptFile) }
        return try write(attempts.filter { $0 != attempt })
    }

    private func write(_ attempts: [NativeBookingCancellationAttempt]) throws -> [NativeBookingCancellationAttempt] {
        var directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try directory.setResourceValues(resources)
        // 在原连接发出取消前写入完整记录。任一写入失败都保留可核对状态。
        let data = try JSONEncoder().encode(Record(scope: scope, attempts: attempts))
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        guard try read() == attempts else { throw CocoaError(.fileWriteUnknown) }
        return attempts
    }
}
