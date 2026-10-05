import Foundation

extension Notification.Name {
    static let aisMaintenanceBlocked = Notification.Name("AIS.MaintenanceBlocked")
}

struct AISMaintenanceStatus: Decodable, Sendable {
    let enabled: Bool
    let restoreAt: String?
    let messageZh: String?
    let messageEn: String?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case enabled = "Enabled"
        case restoreAt = "RestoreAt"
        case messageZh = "MessageZh"
        case messageEn = "MessageEn"
        case message = "Message"
    }

    var notice: String {
        let message = self.message ?? AISLocalization.value(
            zh: messageZh ?? "服务器维护中，生成功能暂不可用。",
            en: messageEn ?? "Generation is temporarily unavailable while we perform server maintenance."
        )
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let restoreAt,
              let date = parser.date(from: restoreAt) ?? ISO8601DateFormatter().date(from: restoreAt) else { return message }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(message)\n\(String(localized: "maintenance.restore_at")): \(formatter.string(from: date)) (\(TimeZone.current.identifier))"
    }
}

enum AISMaintenanceService {
    static func load() async -> AISMaintenanceStatus? {
        let api = APIClient()
        return try? await api.get("/api/ais/maintenance")
    }

    static func checkGeneration() async -> AISMaintenanceStatus? {
        guard let status = await load(), status.enabled else { return nil }
        return status
    }
}
