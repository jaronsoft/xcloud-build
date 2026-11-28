import CryptoKit
import Foundation

struct NativeDiningReservationAttempt: Codable, Equatable, Identifiable {
    let id: String
    let storeID: String
    let previous: String
    let target: String
    let nonce: UUID

    init(id: String, storeID: String, previous: String, target: String) {
        self.id = id
        self.storeID = storeID
        self.previous = previous
        self.target = target
        nonce = UUID()
    }

    static let statuses = ["Pending", "Confirmed", "Declined", "Cancelled"]

    static func validID(_ value: String) -> Bool {
        Int64(value).map { $0 > 0 && String($0) == value } == true
    }

    var isValid: Bool {
        Self.validID(id) && Self.validID(storeID) && (
            (previous == "Pending" && ["Confirmed", "Declined"].contains(target))
            || (previous == "Confirmed" && target == "Cancelled")
        )
    }

    var isValidForWithdrawal: Bool {
        Self.validID(id) && Self.validID(storeID) && previous == "Pending" && target == "Cancelled"
    }

    func readStatus(_ response: Any) -> String? {
        guard let row = response as? [String: Any] else { return nil }
        func field(_ name: String, _ alias: String) -> String? {
            let values = [row[name], row[alias]].compactMap { $0 }
            guard let first = values.first as? String, values.allSatisfy({ ($0 as? String) == first }) else { return nil }
            return first
        }
        guard field("Id", "id") == id, field("StoreId", "storeId") == storeID,
              let status = field("Status", "status"), Self.statuses.contains(status) else { return nil }
        return status
    }
}

struct NativeDiningReservationRecovery {
    private let file: URL
    private let ownerWithdrawal: Bool

    init(principal: String, directory: URL? = nil, ownerWithdrawal: Bool = false) throws {
        guard !principal.isEmpty, let root = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.appendingPathComponent("DiningReservationRecovery", isDirectory: true) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let scope = SHA256.hash(data: Data(principal.utf8)).map { String(format: "%02x", $0) }.joined()
        self.ownerWithdrawal = ownerWithdrawal
        let name = ownerWithdrawal ? "withdrawal-\(scope)-v1.json" : "\(scope)-v1.json"
        file = root.appendingPathComponent(name)
    }

    private func valid(_ attempt: NativeDiningReservationAttempt) -> Bool {
        ownerWithdrawal ? attempt.isValidForWithdrawal : attempt.isValid
    }

    func read() throws -> [NativeDiningReservationAttempt] {
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        let attempts = try JSONDecoder().decode([NativeDiningReservationAttempt].self, from: data)
        guard attempts.allSatisfy(valid), Set(attempts.map(\.id)).count == attempts.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return attempts
    }

    func add(_ attempt: NativeDiningReservationAttempt) throws {
        let attempts = try read()
        guard valid(attempt), !attempts.contains(where: { $0.id == attempt.id }) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try write(attempts + [attempt])
    }

    func remove(_ attempt: NativeDiningReservationAttempt) throws {
        let attempts = try read()
        guard attempts.contains(attempt) else { throw CocoaError(.fileReadCorruptFile) }
        try write(attempts.filter { $0 != attempt })
    }

    private func write(_ attempts: [NativeDiningReservationAttempt]) throws {
        try writeDiningRecovery(attempts, to: file)
        guard try read() == attempts else { throw CocoaError(.fileWriteUnknown) }
    }
}

func writeDiningRecovery<Value: Encodable>(_ value: Value, to file: URL) throws {
    var directory = file.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var resources = URLResourceValues()
    resources.isExcludedFromBackup = true
    try directory.setResourceValues(resources)
    // 请求发出前原子落盘，让重开页面后仍能找回原提交。
    try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
}

struct NativeDiningCreationAttempt: Codable, Equatable, Identifiable {
    let slotID: String
    let date: String
    let key: String
    var id: String { key }

    init(slotID: String, date: String) {
        self.slotID = slotID
        self.date = date
        key = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    var isValid: Bool {
        NativeDiningReservationAttempt.validID(slotID) && key.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil
            && date.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil
    }

    func readReceipt(_ response: Any, storeID: String) throws -> (id: String, status: String)? {
        guard let row = response as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        func field(_ name: String, _ alias: String) throws -> Any {
            let values = [row[name], row[alias]].compactMap { $0 }
            guard let first = values.first,
                  values.allSatisfy({ candidate in
                      if first is NSNull { return candidate is NSNull }
                      guard let value = first as? String else { return false }
                      return candidate as? String == value
                  }) else { throw CocoaError(.fileReadCorruptFile) }
            return first
        }
        guard try field("StoreId", "storeId") as? String == storeID,
              try field("SlotId", "slotId") as? String == slotID,
              try field("IdempotencyKey", "idempotencyKey") as? String == key else { throw CocoaError(.fileReadCorruptFile) }
        let id = try field("ReservationId", "reservationId")
        let state = try field("Status", "status")
        if id is NSNull && state is NSNull { return nil }
        guard let id = id as? String, NativeDiningReservationAttempt.validID(id),
              let state = state as? String, NativeDiningReservationAttempt.statuses.contains(state) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (id, state)
    }
}

struct NativeDiningCreationRecovery {
    private let file: URL

    init(principal: String, storeID: String, directory: URL? = nil) throws {
        guard !principal.isEmpty, NativeDiningReservationAttempt.validID(storeID),
              let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                  .appendingPathComponent("DiningReservationRecovery", isDirectory: true) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let scope = SHA256.hash(data: Data(principal.utf8)).map { String(format: "%02x", $0) }.joined()
        file = root.appendingPathComponent("creation-\(scope)-\(storeID)-v1.json")
    }

    func read() throws -> [NativeDiningCreationAttempt] {
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        let attempts = try JSONDecoder().decode([NativeDiningCreationAttempt].self, from: data)
        guard attempts.allSatisfy(\.isValid), Set(attempts.map(\.slotID)).count == attempts.count,
              Set(attempts.map(\.key)).count == attempts.count else { throw CocoaError(.fileReadCorruptFile) }
        return attempts
    }

    func prepare(slotID: String, date: String, retry: NativeDiningCreationAttempt?) throws -> NativeDiningCreationAttempt {
        let attempts = try read()
        let previous = attempts.first(where: { $0.slotID == slotID })
        if let retry, retry == previous { return retry }
        let attempt = NativeDiningCreationAttempt(slotID: slotID, date: date)
        guard previous == nil, retry == nil, attempt.isValid else { throw CocoaError(.fileWriteFileExists) }
        try write(attempts + [attempt])
        return attempt
    }

    func remove(_ attempt: NativeDiningCreationAttempt) throws {
        let attempts = try read()
        guard attempts.contains(attempt) else { throw CocoaError(.fileReadCorruptFile) }
        try write(attempts.filter { $0 != attempt })
    }

    private func write(_ attempts: [NativeDiningCreationAttempt]) throws {
        try writeDiningRecovery(attempts, to: file)
        guard try read() == attempts else { throw CocoaError(.fileWriteUnknown) }
    }
}
