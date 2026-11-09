import Foundation
import CoreFoundation

func nativeTicketAttendeeMaxLength(_ type: String) -> Int {
    switch type {
    case "IdentityNumber": 18
    case "Phone": 24
    default: 200
    }
}

func nativeTicketAttendeeInput(_ value: String, type: String) -> String {
    let maximum = nativeTicketAttendeeMaxLength(type)
    var result = ""
    var length = 0
    for character in value {
        let characterLength = String(character).utf16.count
        guard length + characterLength <= maximum else { break }
        result.append(character)
        length += characterLength
    }
    return result
}

func nativeTicketRealNameFieldsValid(_ raw: Any?) -> Bool {
    guard let fields = raw as? [[String: Any]], fields.count <= 12 else { return false }
    var keys = Set<String>()
    for field in fields {
        guard let key = field["Key"] as? String,
              let range = key.range(of: "^[A-Za-z][A-Za-z0-9_]{0,39}$", options: .regularExpression),
              range.lowerBound == key.startIndex, range.upperBound == key.endIndex, keys.insert(key.lowercased()).inserted,
              let label = field["Label"] as? String, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              label.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 60,
              let type = field["Type"] as? String, ["Text", "Phone", "IdentityNumber"].contains(type),
              let required = field["Required"] as? NSNumber, CFGetTypeID(required) == CFBooleanGetTypeID() else { return false }
    }
    return true
}

func nativeTicketAccountIdentityKeys(_ raw: Any?) -> Set<String> {
    guard nativeTicketRealNameFieldsValid(raw), let fields = raw as? [[String: Any]],
          let identity = fields.first(where: { $0["Type"] as? String == "IdentityNumber" }) else { return [] }
    var keys: Set<String> = [(identity["Key"] as! String).lowercased()]
    if let name = fields.first(where: {
        ["name", "realname", "attendeename"].contains(($0["Key"] as! String).lowercased()) || $0["Label"] as? String == "姓名"
    }) { keys.insert((name["Key"] as! String).lowercased()) }
    return keys
}

// 首位账号资料由服务端填入；移除大小写不同的旧输入，避免把脱敏值或旧证件写入请求快照。
func nativeTicketAccountAttendees(_ attendees: [[String: String]], keys: Set<String>) -> [[String: String]] {
    attendees.enumerated().map { index, answers in
        index == 0 ? answers.filter { !keys.contains($0.key.lowercased()) } : answers
    }
}

// 只校验填写契约；证件号真实性和账号实名资格仍由服务端判断。
func nativeTicketAttendeeError(_ raw: Any?, attendees: [[String: String]], quantity: Int, accountIdentityKeys: Set<String> = []) -> String? {
    guard nativeTicketRealNameFieldsValid(raw) else { return "购票人资料要求暂时无法读取，请重新查询门票。" }
    guard (1...100).contains(quantity), attendees.count == quantity else { return "购票人资料不完整，请重新填写。" }
    let fields = raw as! [[String: Any]]; let keys = Set(fields.map { ($0["Key"] as! String).lowercased() })
    for (index, answers) in attendees.enumerated() {
        if Set(answers.keys.map { $0.lowercased() }).count != answers.count || answers.keys.contains(where: { !keys.contains($0.lowercased()) }) {
            return "购票人资料要求已变化，请重新查询门票后填写。"
        }
        for field in fields {
            let key = field["Key"] as! String; let label = field["Label"] as! String
            if index == 0 && accountIdentityKeys.contains(key.lowercased()) { continue }
            let value = (answers.first { $0.key.lowercased() == key.lowercased() }?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                if field["Required"] as? Bool == true { return "请填写第\(index + 1)位购票人的\(label)。" }
                continue
            }
            if value.utf16.count > 200 { return "第\(index + 1)位购票人的“\(label)”不能超过200个字符。" }
            if field["Type"] as? String == "Phone" && !nativeSignupPhoneIsValid(value) {
                return "第\(index + 1)位购票人的“\(label)”手机号格式无效。"
            }
            if field["Type"] as? String == "IdentityNumber" && !nativeSignupIdentityIsValid(value) {
                return "第\(index + 1)位购票人的“\(label)”格式无效，请检查证件号码。"
            }
        }
    }
    return nil
}
