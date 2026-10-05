import Foundation

struct InviteReference: Equatable, Sendable {
    let tenantID: String?
    let code: String?
    let accessCode: String?
}

enum InviteLinkParser {
    static func parse(_ input: String) -> InviteReference? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let normalizedAccessCode = value
            .replacingOccurrences(of: "-", with: "")
        if normalizedAccessCode.range(of: #"^\d{6}$"#, options: .regularExpression) != nil {
            return InviteReference(tenantID: nil, code: nil, accessCode: normalizedAccessCode)
        }
        if value.allSatisfy(\.isNumber) {
            return InviteReference(tenantID: value, code: nil, accessCode: nil)
        }
        if !value.contains("://") && value.range(of: #"^[A-Z0-9]{8,32}$"#, options: .regularExpression) != nil {
            return InviteReference(tenantID: nil, code: value, accessCode: nil)
        }
        guard let url = URL(string: value) else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        var tenantID = query.first {
            $0.name == "tenantId" || $0.name == "tid"
        }?.value
        var code = query.first {
            $0.name == "code" || $0.name == "ic"
        }?.value
        var accessCode = query.first { $0.name == "accessCode" || $0.name == "ac" }?.value
        let parts = url.pathComponents.filter { $0 != "/" }

        if parts.first?.lowercased() == "s", parts.count > 1 {
            accessCode = parts[1]
        } else if url.scheme?.lowercased() == "aik", url.host?.lowercased() == "space" {
            accessCode = parts.first
        } else if url.scheme?.lowercased() == "aik", url.host?.lowercased() == "tenant" {
            if let first = parts.first, first.allSatisfy(\.isNumber) {
                tenantID = first
            }
            if parts.count > 1 {
                code = parts[1]
            }
        } else if let first = parts.first, first.allSatisfy(\.isNumber) {
            tenantID = first
            if parts.count > 1 {
                code = parts[1]
            }
        }
        guard tenantID != nil || code != nil || accessCode != nil else { return nil }
        return InviteReference(
            tenantID: tenantID,
            code: code,
            accessCode: accessCode.map {
                $0.filter(\.isNumber)
            }
        )
    }
}
