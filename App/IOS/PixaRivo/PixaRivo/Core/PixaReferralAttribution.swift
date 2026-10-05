import Foundation
import Observation

struct PixaReferralAttribution: Codable, Equatable, Sendable {
    let inviteCode: String
    let sourceURL: String
    let sourceChannel: String
    let firstVisitedAt: Date
}

@MainActor
@Observable
final class PixaReferralAttributionStore {
    private static let storageKey = "pixarivo.referral.pending"
    private static let attributionLifetime: TimeInterval = 30 * 24 * 60 * 60

    private(set) var pending: PixaReferralAttribution?

    init() {
        pending = Self.loadPending()
    }

    @discardableResult
    func capture(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "pixarivo.get-free.net",
              let inviteCode = Self.inviteCode(from: url) else { return false }
        if let current = validPending(), current.inviteCode != inviteCode {
            // 首个有效来源拥有 30 天归因权，避免后续链接覆盖原邀请人。
            return true
        }
        let source = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("source") == .orderedSame })?
            .value
        let value = PixaReferralAttribution(
            inviteCode: inviteCode,
            sourceURL: url.absoluteString,
            sourceChannel: source?.lowercased() == "x" ? "x_referral" : "referral_link",
            firstVisitedAt: Date()
        )
        pending = value
        persist(value)
        return true
    }

    func validPending(now: Date = Date()) -> PixaReferralAttribution? {
        guard let pending else { return nil }
        guard pending.firstVisitedAt <= now.addingTimeInterval(5 * 60),
              now.timeIntervalSince(pending.firstVisitedAt) <= Self.attributionLifetime else {
            clear()
            return nil
        }
        return pending
    }

    func attribution(matching inviteCode: String) -> PixaReferralAttribution? {
        let normalized = Self.normalize(inviteCode)
        guard let pending = validPending(), pending.inviteCode == normalized else { return nil }
        return pending
    }

    func clear() {
        pending = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func isValidInviteCode(_ value: String) -> Bool {
        let normalized = normalize(value)
        return normalized.range(
            of: #"^AIS-[A-F0-9]{8}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func inviteCode(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0].lowercased() == "ref" else { return nil }
        let code = normalize(parts[1])
        return isValidInviteCode(code) ? code : nil
    }

    private func persist(_ value: PixaReferralAttribution) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func loadPending() -> PixaReferralAttribution? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(PixaReferralAttribution.self, from: data),
              value.firstVisitedAt <= Date().addingTimeInterval(5 * 60),
              Date().timeIntervalSince(value.firstVisitedAt) <= attributionLifetime else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return nil
        }
        return value
    }
}
