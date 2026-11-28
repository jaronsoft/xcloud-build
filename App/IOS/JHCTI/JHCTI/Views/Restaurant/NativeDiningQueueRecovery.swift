import CoreFoundation
import CryptoKit
import Foundation

enum NativeDiningQueueAction: String, Codable {
    case open, close, call, complete, missed

    var name: String {
        switch self {
        case .open: "开放排队"
        case .close: "关闭排队"
        case .call: "呼叫下一位"
        case .complete: "完成接待"
        case .missed: "标记过号"
        }
    }

    var targetsEntry: Bool { self == .complete || self == .missed }
}

struct NativeDiningQueueAttempt: Codable, Equatable {
    let action: NativeDiningQueueAction
    let storeID: String
    let date: String
    let sessionID: String?
    let entryID: String?
    let number: Int?
    var nonce = UUID()

    static let zone = TimeZone(identifier: "Asia/Shanghai")!

    static func dateText(_ date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents(in: zone, from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    static func dateValue(_ text: String) -> Date? {
        guard text.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        return nativeBusinessDateTime(text)
    }

    var isValid: Bool {
        guard NativeDiningReservationAttempt.validID(storeID), Self.dateValue(date) != nil,
              sessionID.map(NativeDiningReservationAttempt.validID) ?? (action == .open) else { return false }
        if action.targetsEntry {
            return entryID.map(NativeDiningReservationAttempt.validID) == true && (number ?? 0) > 0
        }
        return entryID == nil && number == nil
    }

    func matchesReceipt(_ response: Any) -> Bool {
        switch action {
        case .open:
            guard let row = response as? [String: Any], let summary = NativeDiningQueueSummary(row, storeID: storeID, date: date) else { return false }
            return summary.isOpen && (sessionID == nil || sessionID == summary.id)
        case .call:
            guard let row = response as? [String: Any],
                  let id = nativeQueueString(row, "Id"), NativeDiningReservationAttempt.validID(id),
                  let rowSession = nativeQueueString(row, "SessionId"), rowSession == sessionID else { return false }
            return nativeQueueString(row, "StoreId") == storeID
                && nativeQueueDayMatches(nativeQueueString(row, "QueueDate"), date)
                && nativeQueueInteger(row, "QueueNumber").map { $0 > 0 } == true
                && nativeQueueString(row, "Status") == "Called"
        case .close: return (response as? String) == sessionID && sessionID != nil
        case .complete, .missed: return (response as? String) == entryID && entryID != nil
        }
    }
}

private func queueValues(_ row: [String: Any], _ name: String) -> [Any] {
    [row[name], row[name.prefix(1).lowercased() + name.dropFirst()]].compactMap { $0 }
}

func nativeQueueString(_ row: [String: Any], _ name: String) -> String? {
    let values = queueValues(row, name)
    guard let first = values.first as? String, values.allSatisfy({ ($0 as? String) == first }) else { return nil }
    return first
}

func nativeQueueInteger(_ row: [String: Any], _ name: String) -> Int? {
    let values = queueValues(row, name)
    let numbers = values.compactMap { value -> Int? in
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 0, number.doubleValue <= Double(Int32.max),
              number.doubleValue == Double(number.intValue) else { return nil }
        return number.intValue
    }
    guard numbers.count == values.count, let first = numbers.first, numbers.allSatisfy({ $0 == first }) else { return nil }
    return first
}

func nativeQueueDayMatches(_ value: String?, _ date: String) -> Bool {
    guard let value, let instant = nativeBusinessDateTime(value) else { return false }
    return NativeDiningQueueAttempt.dateText(instant) == date
}

struct NativeDiningQueueSummary {
    let id: String
    let isOpen: Bool
    let waiting: Int
    let lastNumber: Int
    let currentNumber: Int?

    init?(_ row: [String: Any], storeID: String, date: String) {
        let flags = queueValues(row, "IsOpen")
        guard let id = nativeQueueString(row, "Id"), NativeDiningReservationAttempt.validID(id),
              nativeQueueString(row, "StoreId") == storeID,
              nativeQueueDayMatches(nativeQueueString(row, "QueueDate"), date),
              let flag = flags.first as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID(),
              flags.allSatisfy({ value in
                  guard let number = value as? NSNumber else { return false }
                  return CFGetTypeID(number) == CFBooleanGetTypeID() && number.boolValue == flag.boolValue
              }),
              let waiting = nativeQueueInteger(row, "WaitingCount"), let last = nativeQueueInteger(row, "LastNumber") else { return nil }
        let current = nativeQueueInteger(row, "CurrentCalledNumber")
        guard (current.map { $0 > 0 } ?? queueValues(row, "CurrentCalledNumber").allSatisfy { $0 is NSNull }) else { return nil }
        self.id = id
        isOpen = flag.boolValue
        self.waiting = waiting
        lastNumber = last
        currentNumber = current
    }
}

struct NativeDiningQueueRecovery {
    private let file: URL
    private let storeID: String

    init(principal: String, storeID: String, directory: URL? = nil) throws {
        guard !principal.isEmpty, NativeDiningReservationAttempt.validID(storeID),
              let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?.appendingPathComponent("DiningQueueRecovery", isDirectory: true) else { throw CocoaError(.fileReadNoSuchFile) }
        let digest = SHA256.hash(data: Data(principal.utf8)).map { String(format: "%02x", $0) }.joined()
        file = root.appendingPathComponent("\(digest)-\(storeID)-v1.json")
        self.storeID = storeID
    }

    func read() throws -> NativeDiningQueueAttempt? {
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        let attempt = try JSONDecoder().decode(NativeDiningQueueAttempt?.self, from: data)
        if let attempt, !attempt.isValid || attempt.storeID != storeID { throw CocoaError(.fileReadCorruptFile) }
        return attempt
    }

    func add(_ attempt: NativeDiningQueueAttempt) throws {
        guard try read() == nil, attempt.isValid, attempt.storeID == storeID else { throw CocoaError(.fileWriteFileExists) }
        try writeDiningRecovery(Optional(attempt), to: file)
        guard try read() == attempt else { throw CocoaError(.fileWriteUnknown) }
    }

    func remove(_ attempt: NativeDiningQueueAttempt) throws {
        guard try read() == attempt else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.removeItem(at: file)
        guard try read() == nil else { throw CocoaError(.fileWriteUnknown) }
    }
}
