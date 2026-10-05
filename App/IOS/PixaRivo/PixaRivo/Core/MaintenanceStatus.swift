import Foundation

extension Notification.Name {
    static let pixaMaintenanceBlocked = Notification.Name("PixaRivo.MaintenanceBlocked")
}

struct PixaMaintenanceStatus: Decodable, Sendable {
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
        let isChinese = AppLanguage.apiValue.lowercased().hasPrefix("zh")
        let message = self.message ?? (isChinese ? messageZh : messageEn)
        let fallback = AppLanguage.localized("maintenance.default_message")
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let restoreAt,
              let date = parser.date(from: restoreAt) ?? ISO8601DateFormatter().date(from: restoreAt) else {
            return message?.isEmpty == false ? message! : fallback
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(message?.isEmpty == false ? message! : fallback)\n\(AppLanguage.localized("maintenance.restore_at")): \(formatter.string(from: date)) (\(TimeZone.current.identifier))"
    }
}

enum PixaMaintenanceService {
    static func load() async -> PixaMaintenanceStatus? {
        let api = APIClient()
        return try? await api.get("/api/ais/maintenance", forceRefresh: true)
    }

    static func checkGeneration() async -> PixaMaintenanceStatus? {
        guard let status = await load(), status.enabled else { return nil }
        return status
    }
}
