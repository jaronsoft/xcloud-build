import Foundation

enum DateSupport {
    private static func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func keyFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func readableFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en")
        formatter.timeZone = timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }

    static func key(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        keyFormatter(timeZone: timeZone).string(from: date)
    }

    static func date(_ key: String, timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
        keyFormatter(timeZone: timeZone).date(from: key)
    }

    static func readable(_ key: String, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        guard let date = date(key, timeZone: timeZone) else { return key }
        return readableFormatter(timeZone: timeZone).string(from: date)
    }

    static func days(in year: Int, timeZone: TimeZone = .autoupdatingCurrent) -> [Date] {
        let calendar = calendar(timeZone: timeZone)
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let count = calendar.range(of: .day, in: .year, for: start)?.count ?? 365
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func monthCells(
        year: Int,
        month: Int,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> [Date?] {
        let calendar = calendar(timeZone: timeZone)
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let leading = calendar.component(.weekday, from: first) - 1
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let total = Int(ceil(Double(leading + dayCount) / 7.0)) * 7
        return (0..<total).map { index in
            let day = index - leading + 1
            guard day >= 1, day <= dayCount else { return nil }
            return calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
    }
}

extension LocalRecord {
    var status: RecordStatus {
        if isIntentionalBlank { return .intentionalBlank }
        return .recorded
    }
}
