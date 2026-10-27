import Foundation

@MainActor
enum BmbEmailCodeCooldown {
    private static let storageKey = "bmb.emailCodeCooldownUntil"

    static func remaining(at date: Date) -> Int {
        let until = UserDefaults.standard.double(forKey: storageKey)
        return max(0, Int(ceil(until - date.timeIntervalSince1970)))
    }

    static func recordSend() {
        UserDefaults.standard.set(Date().timeIntervalSince1970 + 60, forKey: storageKey)
    }
}
