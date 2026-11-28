import Foundation
import ImageIO

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
    // 兼容旧凭证中的分钟格式，保留新凭证返回的秒及小数秒。
    let pattern = #"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d{1,7})?)?(?:Z|[+-]\d{2}:?\d{2})?$"#
    guard text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
    return nativeBusinessDateTime(text)
}

func activityRegistrationReceiptCode(_ item: [String: Any], now: Date) -> String? {
    guard !activityRegistrationCredentialUnavailable(item, now: now),
          let code = item["CredentialCode"] as? String,
          !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return code
}

func activityRegistrationQrPng(_ value: Any?) -> Data? {
    let prefix = "data:image/png;base64,"
    guard let value = value as? String, value.hasPrefix(prefix),
          let data = Data(base64Encoded: String(value.dropFirst(prefix.count))),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetType(source) as String? == "public.png",
          CGImageSourceGetStatus(source) == .statusComplete,
          CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return nil }
    return data
}
