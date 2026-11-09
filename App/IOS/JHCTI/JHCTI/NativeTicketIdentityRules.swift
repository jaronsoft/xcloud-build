import Foundation
import CoreFoundation

func nativeTicketIdentityVersion(_ value: [String: Any]?) -> Int64? {
    guard let number = value?["Version"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          let version = Int64(number.stringValue), version >= 0 else { return nil }
    return version
}

private func nativeTicketIdentityAliasValue(_ value: [String: Any], _ name: String, validate: (Any) -> Bool) -> (Bool, Any?) {
    let camelName = name.prefix(1).lowercased() + String(name.dropFirst())
    guard let canonical = value[name], validate(canonical) else { return (false, nil) }
    guard let alias = value[camelName] else { return (true, canonical) }
    guard validate(alias), nativeTicketIdentityValuesEqual(canonical, alias) else { return (false, nil) }
    return (true, canonical)
}

private func nativeTicketIdentityValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    if lhs is NSNull || rhs is NSNull { return lhs is NSNull && rhs is NSNull }
    if let left = lhs as? String, let right = rhs as? String { return left == right }
    if let left = lhs as? NSNumber, let right = rhs as? NSNumber {
        return CFGetTypeID(left) == CFGetTypeID(right) && left.stringValue == right.stringValue
    }
    return false
}

private func nativeTicketIdentityBoolean(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
}

private func nativeTicketIdentityDate(_ value: Any) -> Bool {
    guard let text = value as? String else { return false }
    return nativeBusinessDateTime(text) != nil
}

func nativeTicketIdentityProfileValid(_ value: [String: Any]?) -> Bool {
    guard let value, nativeTicketIdentityVersion(value) != nil else { return false }
    let hasProfile = nativeTicketIdentityAliasValue(value, "HasProfile", validate: nativeTicketIdentityBoolean)
    let hasConsent = nativeTicketIdentityAliasValue(value, "HasConsent", validate: nativeTicketIdentityBoolean)
    let isConsentCurrent = nativeTicketIdentityAliasValue(value, "IsConsentCurrent", validate: nativeTicketIdentityBoolean)
    let isPhoneVerified = nativeTicketIdentityAliasValue(value, "IsPhoneVerified", validate: nativeTicketIdentityBoolean)
    let consentVersion = nativeTicketIdentityAliasValue(value, "ConsentVersion") {
        $0 is NSNull || (($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }
    let consentedAt = nativeTicketIdentityAliasValue(value, "ConsentedAt") {
        $0 is NSNull || nativeTicketIdentityDate($0)
    }
    let maskedName = nativeTicketIdentityAliasValue(value, "MaskedRealName") { $0 is String }
    let maskedNumber = nativeTicketIdentityAliasValue(value, "MaskedIdentityNumber") { $0 is String }
    let version = nativeTicketIdentityAliasValue(value, "Version") {
        guard let number = $0 as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
        return Int64(number.stringValue).map { $0 >= 0 } ?? false
    }
    let fields = [hasProfile, hasConsent, isConsentCurrent, isPhoneVerified, consentVersion,
                  consentedAt, maskedName, maskedNumber, version]
    guard fields.allSatisfy({ $0.0 }),
          let hasProfileValue = hasProfile.1 as? NSNumber,
          let hasConsentValue = hasConsent.1 as? NSNumber,
          let currentValue = isConsentCurrent.1 as? NSNumber,
          let phoneVerifiedValue = isPhoneVerified.1 as? NSNumber,
          let maskedNameValue = maskedName.1 as? String,
          let maskedNumberValue = maskedNumber.1 as? String else { return false }
    let consentVersionIsNull = consentVersion.1 is NSNull
    let consentedAtIsNull = consentedAt.1 is NSNull
    let hasConsentFlag = hasConsentValue.boolValue
    let hasProfileFlag = hasProfileValue.boolValue
    let currentFlag = currentValue.boolValue
    return (!hasConsentFlag || (hasProfileFlag && !consentVersionIsNull && !consentedAtIsNull))
        && (hasConsentFlag || (!currentFlag && consentVersionIsNull && consentedAtIsNull))
        && (!currentFlag || hasConsentFlag)
        && (!hasProfileFlag || (phoneVerifiedValue.boolValue
            && !maskedNameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !maskedNumberValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        && (hasProfileFlag || (!hasConsentFlag && !currentFlag
            && maskedNameValue.isEmpty && maskedNumberValue.isEmpty))
}

func nativeTicketIdentityInputError(name: String, number: String, consent: Bool) -> String? {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let number = number.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard (2...80).contains(name.utf16.count), !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
        return "请填写 2 至 80 个字符的真实姓名。"
    }
    guard number.range(of: "^[1-9][0-9]{16}[0-9X]$", options: .regularExpression) != nil else {
        return "请填写 18 位居民身份证号码。"
    }
    return consent ? nil : "请先单独同意实名购票资料隐私告知。"
}

func nativeTicketIdentitySaveReceiptValid(_ value: [String: Any]?, previousVersion: Int64) -> Bool {
    nativeTicketIdentityProfileValid(value)
        && value?["HasProfile"] as? Bool == true && value?["IsConsentCurrent"] as? Bool == true
        && (nativeTicketIdentityVersion(value) ?? -1) > previousVersion
}

func nativeTicketIdentityBookingEligible(_ value: [String: Any]?) -> Bool {
    nativeTicketIdentityProfileValid(value) && value?["HasProfile"] as? Bool == true
        && value?["HasConsent"] as? Bool == true && value?["IsConsentCurrent"] as? Bool == true
        && value?["IsPhoneVerified"] as? Bool == true
}
