import Foundation
import CoreFoundation

// 客户端业务时间按服务端 DateTime 的有效年月日范围解析，避免系统日期格式化器悄悄归一化非法值。
func nativeBusinessDateTime(_ value: String) -> Date? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = #"^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(\.\d{1,7})?)?(Z|[+-]\d{2}:?\d{2})?)?$"#
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = expression.firstMatch(in: text, range: fullRange), match.range == fullRange else { return nil }
    func capture(_ index: Int) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
    guard let year = Int(capture(1) ?? ""), (1...9999).contains(year),
          let month = Int(capture(2) ?? ""), let day = Int(capture(3) ?? ""),
          let hour = Int(capture(4) ?? "0"), let minute = Int(capture(5) ?? "0"),
          let second = Int(capture(6) ?? "0"), (0...23).contains(hour),
          (0...59).contains(minute), (0...59).contains(second) else { return nil }

    let rawZone = capture(8) ?? ""
    let timeZone: TimeZone
    if rawZone.isEmpty {
        guard let beijing = TimeZone(identifier: "Asia/Shanghai") else { return nil }
        timeZone = beijing
    } else if rawZone.lowercased() == "z" {
        timeZone = TimeZone(secondsFromGMT: 0)!
    } else {
        guard rawZone.range(of: #"^[+-](\d{2}):?(\d{2})$"#, options: .regularExpression) != nil,
              let sign = rawZone.first.map({ $0 == "-" ? -1 : 1 }),
              let offsetHour = Int(rawZone[rawZone.index(after: rawZone.startIndex)..<rawZone.index(rawZone.startIndex, offsetBy: 3)]),
              let offsetMinute = Int(rawZone.suffix(2)), offsetHour <= 14, offsetMinute <= 59,
              offsetHour != 14 || offsetMinute == 0,
              let parsedZone = TimeZone(secondsFromGMT: sign * (offsetHour * 3600 + offsetMinute * 60)) else { return nil }
        timeZone = parsedZone
    }

    let fractionDigits = capture(7)?.dropFirst() ?? ""
    let nanosecond = Int(String(fractionDigits).padding(toLength: 9, withPad: "0", startingAt: 0)) ?? 0
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    let components = DateComponents(year: year, month: month, day: day, hour: hour,
                                    minute: minute, second: second, nanosecond: 0)
    guard let date = calendar.date(from: components) else { return nil }
    let verified = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    guard verified.year == year, verified.month == month, verified.day == day,
          verified.hour == hour, verified.minute == minute, verified.second == second else { return nil }
    return date.addingTimeInterval(Double(nanosecond) / 1_000_000_000)
}

// 交易期限和场次截止必须精确到秒，避免将日期值当作当天零点放行。
func nativeBusinessTimestamp(_ value: Any?) -> Date? {
    guard let raw = value as? String else { return nil }
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.range(of: #"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:?\d{2})?$"#, options: .regularExpression) != nil else { return nil }
    return nativeBusinessDateTime(text)
}

private func nativeActivityQuotaField(_ quota: [String: Any], pascalName: String, camelName: String) -> Any? {
    let hasPascal = quota.keys.contains(pascalName)
    let hasCamel = quota.keys.contains(camelName)
    guard hasPascal || hasCamel else { return nil }
    guard hasPascal, hasCamel else {
        let value = hasPascal ? quota[pascalName] : quota[camelName]
        return value.flatMap { $0 is NSNull ? nil : $0 }
    }
    guard let pascalValue = quota[pascalName], !(pascalValue is NSNull),
          let camelValue = quota[camelName], !(camelValue is NSNull) else { return nil }
    if let first = pascalValue as? NSNumber, let second = camelValue as? NSNumber,
       CFGetTypeID(first) != CFBooleanGetTypeID(), CFGetTypeID(second) != CFBooleanGetTypeID() {
        return first.decimalValue == second.decimalValue ? pascalValue : nil
    }
    if let first = pascalValue as? String, let second = camelValue as? String {
        return first == second ? pascalValue : nil
    }
    return nil
}

private func nativeActivityQuotaInteger(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let numericValue = number.doubleValue
    guard numericValue.isFinite, numericValue >= 0, numericValue <= Double(Int32.max), numericValue.rounded(.towardZero) == numericValue else { return nil }
    return Int(numericValue)
}

func nativeActivityRegistrationQuotaRemaining(_ raw: Any?, activityID: String) -> Int? {
    guard let quota = raw as? [String: Any],
          nativeActivityQuotaField(quota, pascalName: "ActivityId", camelName: "activityId") as? String == activityID,
          let maximum = nativeActivityQuotaInteger(nativeActivityQuotaField(quota, pascalName: "MaxPerUser", camelName: "maxPerUser")),
          (1...100).contains(maximum),
          let registered = nativeActivityQuotaInteger(nativeActivityQuotaField(quota, pascalName: "RegisteredQuantity", camelName: "registeredQuantity")),
          let remaining = nativeActivityQuotaInteger(nativeActivityQuotaField(quota, pascalName: "RemainingQuantity", camelName: "remainingQuantity")),
          remaining == max(0, maximum - registered) else { return nil }
    return remaining
}

private func nativePublicActivityID(_ value: Any?) -> String? {
    guard let id = value as? String, let number = Int64(id), number > 0, String(number) == id else { return nil }
    return id
}

private func nativePublicActivityCapacity(_ value: Any?, maximum: Double) -> Int? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= maximum,
          number.doubleValue.rounded(.towardZero) == number.doubleValue else { return nil }
    return number.intValue
}

// 活动名额回执必须覆盖详情中的全部场次，避免部分或重复数据让旧名额开放报名。
func nativePublicActivityAvailabilityMatches(detail: [String: Any], availability: [String: Any]?) -> Bool {
    guard let activityID = nativePublicActivityID(detail["Id"]), let availability,
          availability["ActivityId"] as? String == activityID,
          nativePublicActivityCapacity(availability["RemainingCapacity"], maximum: 9_007_199_254_740_991) != nil,
          let detailSessions = detail["Sessions"] as? [[String: Any]],
          let liveSessions = availability["Sessions"] as? [[String: Any]] else { return false }
    var detailIDs = Set<String>()
    for session in detailSessions {
        guard let sessionID = nativePublicActivityID(session["Id"]), detailIDs.insert(sessionID).inserted else { return false }
    }
    var liveIDs = Set<String>()
    for session in liveSessions {
        guard let sessionID = nativePublicActivityID(session["Id"]), liveIDs.insert(sessionID).inserted,
              nativePublicActivityCapacity(session["RemainingCapacity"], maximum: 1_000_000) != nil,
              let enabled = session["IsEnabled"] as? NSNumber, CFGetTypeID(enabled) == CFBooleanGetTypeID(),
              let endTime = session["EndTime"] as? String, !endTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    }
    return detailIDs == liveIDs
}

// 活动与门票采用相同手机号格式，保持两处填写提示与服务端允许字符一致。
func nativeSignupPhoneIsValid(_ value: String) -> Bool {
    let digits = value.utf8.filter { (48...57).contains($0) }.count
    return (7...24).contains(value.utf16.count) && (7...20).contains(digits)
        && value.range(of: "^[0-9+() -]+$", options: .regularExpression) != nil
}

func nativeActivitySignupMaxLength(_ type: String) -> Int {
    switch type {
    case "Phone": 24
    case "IdentityNumber": 18
    default: 500
    }
}

// 按 API 与其余客户端使用的 UTF-16 长度截断，同时避免切开代理对。
func nativeActivitySignupTruncate(_ value: String, maxLength: Int) -> String {
    guard maxLength > 0 else { return "" }
    var scalars = String.UnicodeScalarView()
    var length = 0
    for scalar in value.unicodeScalars {
        let scalarLength = scalar.value > 0xFFFF ? 2 : 1
        guard length + scalarLength <= maxLength else { break }
        scalars.append(scalar)
        length += scalarLength
    }
    return String(scalars)
}

func nativeSignupIdentityIsValid(_ value: String) -> Bool {
    let number = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard number.range(of: "^[1-9][0-9]{16}[0-9X]$", options: .regularExpression) != nil else { return false }
    let digits = Array(number.utf8)
    let year = Int(String(decoding: digits[6..<10], as: UTF8.self))!
    let month = Int(String(decoding: digits[10..<12], as: UTF8.self))!
    let day = Int(String(decoding: digits[12..<14], as: UTF8.self))!
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let birthDate = utc.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
    let birthComponents = utc.dateComponents([.year, .month, .day], from: birthDate)
    guard birthComponents.year == year, birthComponents.month == month, birthComponents.day == day else { return false }
    var beijing = Calendar(identifier: .gregorian)
    beijing.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    guard beijing.startOfDay(for: birthDate) <= beijing.startOfDay(for: Date()) else { return false }
    let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
    let checks = Array("10X98765432")
    let sum = zip(digits.prefix(17), weights).reduce(0) { $0 + Int($1.0 - 48) * $1.1 }
    return checks[sum % 11] == Character(UnicodeScalar(digits[17]))
}

private func nativeActivitySignupNumberIsValid(_ value: String) -> Bool {
    value.range(of: "^(?:[+-]?(?:(?:[0-9][0-9,]*)(?:\\.[0-9]*)?|\\.[0-9]+)|(?:(?:[0-9][0-9,]*)(?:\\.[0-9]*)?|\\.[0-9]+)[+-])$", options: .regularExpression) != nil
}

// 字段缺失或契约不明时暂停采集，不能把损坏的配置当作无需填写资料。
func nativeActivitySignupConfigurationError(_ raw: Any?) -> String? {
    let error = "报名信息暂时无法读取，请重新加载活动后再试。"
    guard let fields = raw as? [[String: Any]], fields.count <= 20 else { return error }
    var keys = Set<String>()
    for field in fields {
        guard let key = field["Key"] as? String,
              let range = key.range(of: "^[A-Za-z_][A-Za-z0-9_]{0,39}$", options: .regularExpression),
              range.lowerBound == key.startIndex, range.upperBound == key.endIndex,
              keys.insert(key.lowercased()).inserted,
              let label = field["Label"] as? String, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              label.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 80,
              let type = field["Type"] as? String, ["Text", "LongText", "Number", "Phone", "IdentityNumber", "Select"].contains(type),
              let required = field["Required"] as? NSNumber, CFGetTypeID(required) == CFBooleanGetTypeID(),
              let options = field["Options"] as? [String] else { return error }
        if type == "Select" {
            guard (1...30).contains(options.count), options.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf16.count <= 80 }) else { return error }
        } else if !options.isEmpty { return error }
    }
    return nil
}

func nativeActivitySignupAnswerError(_ raw: Any?, participants: [[String: String]], quantity: Int) -> String? {
    if let error = nativeActivitySignupConfigurationError(raw) { return error }
    guard (1...100).contains(quantity), participants.count == quantity else { return "参与者资料不完整，请重新填写。" }
    let fields = raw as! [[String: Any]]
    let keys = Set(fields.compactMap { ($0["Key"] as? String)?.lowercased() })
    for (index, answers) in participants.enumerated() {
        if Set(answers.keys.map { $0.lowercased() }).count != answers.count
            || answers.keys.contains(where: { !keys.contains($0.lowercased()) }) { return "报名信息已变化，请重新加载活动后填写。" }
        for field in fields {
            let key = field["Key"] as! String; let label = field["Label"] as! String
            let value = (answers[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                if field["Required"] as? Bool == true { return "请填写参与者\(index + 1)的\(label)" }
                continue
            }
            if field["Type"] as? String == "Phone" {
                if !nativeSignupPhoneIsValid(value) {
                    return "参与者\(index + 1)的“\(label)”手机号格式无效。"
                }
            }
            if field["Type"] as? String == "Number", !nativeActivitySignupNumberIsValid(value) {
                return "参与者\(index + 1)的“\(label)”须填写有效数字。"
            }
            if field["Type"] as? String == "IdentityNumber", !nativeSignupIdentityIsValid(value) {
                return "参与者\(index + 1)的“\(label)”格式无效，请检查证件号码。"
            }
            if field["Type"] as? String == "Select", !(field["Options"] as! [String]).contains(value) {
                return "参与者\(index + 1)的“\(label)”选项已失效，请重新选择。"
            }
        }
    }
    return nil
}

func nativeActivityRequiresIdentityConsent(_ fields: [[String: Any]], participants: [[String: String]]) -> Bool {
    fields.contains { field in
        guard field["Type"] as? String == "IdentityNumber", let key = field["Key"] as? String else { return false }
        return field["Required"] as? Bool == true || participants.contains {
            !($0[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
