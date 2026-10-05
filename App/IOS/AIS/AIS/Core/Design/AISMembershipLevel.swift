import Foundation

enum AISMembershipLevel {
    static func iconName(code: String?, name: String?) -> String {
        let value = [code, name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
            .lowercased()

        if value.contains("enterprise") || value.contains("企业") {
            return "MembershipLevel6"
        }
        if value.contains("max") {
            return "MembershipLevel5"
        }
        if value.contains("student") || value.contains("学生") {
            return "MembershipLevel4"
        }
        if value.contains("pro") {
            return "MembershipLevel3"
        }
        if value.contains("plus") {
            return "MembershipLevel2"
        }
        return "MembershipLevel1"
    }
}
