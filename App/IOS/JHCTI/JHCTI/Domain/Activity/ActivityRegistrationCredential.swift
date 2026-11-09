import Foundation

func activityRegistrationExpired(_ item: [String: Any], now: Date = Date()) -> Bool {
    guard item["Status"] as? String == "Registered" else { return false }
    if item["IsExpired"] as? Bool == true { return true }
    guard let deadline = activityRegistrationCredentialDeadline(item["CredentialExpiresAt"]) else { return false }
    return deadline <= now
}

func activityRegistrationExpiryUnknown(_ item: [String: Any]) -> Bool {
    item["Status"] as? String == "Registered"
        && item["IsExpired"] as? Bool != true
        && activityRegistrationCredentialDeadline(item["CredentialExpiresAt"]) == nil
}

func activityRegistrationCredentialUnavailable(_ item: [String: Any], now: Date = Date()) -> Bool {
    guard item["Status"] as? String == "Registered", item["IsExpired"] as? Bool != true,
          let deadline = activityRegistrationCredentialDeadline(item["CredentialExpiresAt"]) else { return true }
    return deadline <= now
}

func activityRegistrationCredentialDeadline(_ value: Any?) -> Date? {
    guard let value = value as? String else { return nil }
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let canonicalValue = normalizedActivityRegistrationCredentialDeadline(text) else { return nil }
    return paymentDeadline(canonicalValue)
}

private func normalizedActivityRegistrationCredentialDeadline(_ text: String) -> String? {
    let pattern = #"^(\d{4})-(\d{2})-(\d{2})[T\s](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,7}))?)?(Z|([+-])(\d{2}):?(\d{2}))?$"#
    guard let expression = try? NSRegularExpression(pattern: pattern),
          let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    func component(_ group: Int) -> String? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }
    func integer(_ group: Int) -> Int? { component(group).flatMap(Int.init) }
    guard let year = integer(1), let month = integer(2), let day = integer(3),
          let hour = integer(4), let minute = integer(5),
          year > 0, (1...12).contains(month), (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    let second = integer(6) ?? 0
    guard (0...59).contains(second) else { return nil }
    let leapYear = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    let daysInMonth = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
    guard (1...daysInMonth).contains(day) else { return nil }
    let timeZone: String
    if let offsetHour = integer(10), let offsetMinute = integer(11) {
        guard offsetHour <= 14, offsetMinute <= 59, offsetHour < 14 || offsetMinute == 0,
              let sign = component(9) else { return nil }
        timeZone = String(format: "%@%02d:%02d", sign, offsetHour, offsetMinute)
    } else if component(8)?.uppercased() == "Z" {
        timeZone = "Z"
    } else {
        timeZone = "+08:00"
    }
    let fraction = component(7).map { ".\(String(($0 + "000").prefix(3)))" } ?? ""
    let seconds = component(6) ?? "00"
    return "\(component(1)!)-\(component(2)!)-\(component(3)!)T\(component(4)!):\(component(5)!):\(seconds)\(fraction)\(timeZone)"
}

func activityRegistrationReceiptCode(_ item: [String: Any], now: Date) -> String? {
    guard !activityRegistrationCredentialUnavailable(item, now: now),
          let code = item["CredentialCode"] as? String,
          !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return code
}
