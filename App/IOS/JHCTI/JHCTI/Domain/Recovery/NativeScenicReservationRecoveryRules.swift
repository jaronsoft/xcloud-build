import Foundation
import CryptoKit

enum NativeScenicReservationRecoveryRules {
    static func reservationStorageKey(token: String, resourceID: String, sessionID: String, date: String) -> String {
        let principalHash = SHA256.hash(data: Data(reservationPrincipal(token).utf8)).map { String(format: "%02x", $0) }.joined()
        return "jhcti.reservation.v2.\(principalHash).\(resourceID).\(sessionID).\(date)"
    }

    static func legacyReservationStorageKey(token: String, resourceID: String, sessionID: String, date: String) -> String {
        let fingerprint = "\(reservationPrincipal(token))|\(resourceID)|\(sessionID)|\(date)"
        return "jhcti.reservation." + SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func reservationRecoveryIndexKey(token: String, resourceID: String) -> String {
        "jhcti.reservation-index.v1." + legacyReservationStorageKey(token: token, resourceID: resourceID,
            sessionID: "0", date: "").replacingOccurrences(of: "jhcti.reservation.", with: "")
    }

    // 新版标记保留可枚举的预约坐标，供冷启动按账号和景点安全查回原请求。
    static func reservationAttemptMarkers(token: String, resourceID: String,
        legacyCandidates: [(sessionId: String, date: String)])
        -> [(storageKey: String, sessionId: String, reservationDate: String, idempotencyKey: String)]? {
        let principalHash = SHA256.hash(data: Data(reservationPrincipal(token).utf8)).map { String(format: "%02x", $0) }.joined()
        let prefix = "jhcti.reservation.v2.\(principalHash).\(resourceID)."
        let keys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        var markers: [(storageKey: String, sessionId: String, reservationDate: String, idempotencyKey: String)] = []
        for storageKey in keys {
            let parts = storageKey.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, let sessionNumber = Int64(parts[0]), sessionNumber >= 0,
                  parts[1].range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil,
                  let requestKey = UserDefaults.standard.string(forKey: storageKey),
                  requestKey.range(of: "^[A-Za-z0-9._:-]{8,80}$", options: .regularExpression) != nil else { return nil }
            markers.append((storageKey, parts[0], parts[1], requestKey))
        }
        for candidate in legacyCandidates {
            guard let sessionNumber = Int64(candidate.sessionId), sessionNumber >= 0,
                  candidate.date.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil else { continue }
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.calendar = Calendar(identifier: .gregorian)
            dateFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.isLenient = false
            guard let date = dateFormatter.date(from: candidate.date),
                  dateFormatter.string(from: date) == candidate.date else { continue }
            let storageKey = legacyReservationStorageKey(token: token, resourceID: resourceID,
                sessionID: candidate.sessionId, date: candidate.date)
            guard let requestKey = UserDefaults.standard.string(forKey: storageKey) else { continue }
            guard requestKey.range(of: "^[A-Za-z0-9._:-]{8,80}$", options: .regularExpression) != nil else { return nil }
            if !markers.contains(where: { $0.storageKey == storageKey }) {
                markers.append((storageKey, candidate.sessionId, candidate.date, requestKey))
            }
        }
        return markers
    }

    static func normalizedIdentityNumber(_ value: String, now: Date = Date()) -> String? {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.range(of: "^[1-9][0-9]{16}[0-9X]$", options: .regularExpression) != nil else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.isLenient = false
        let birthDate = String(code.dropFirst(6).prefix(8))
        guard let date = dateFormatter.date(from: birthDate), dateFormatter.string(from: date) == birthDate,
              birthDate <= dateFormatter.string(from: now) else { return nil }
        let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
        let checks = Array("10X98765432")
        let sum = zip(code.prefix(17).compactMap(\.wholeNumberValue), weights).reduce(0) { $0 + $1.0 * $1.1 }
        return checks[sum % 11] == code.last ? code : nil
    }

    static func isValidIdentityNumber(_ value: String) -> Bool { normalizedIdentityNumber(value) != nil }

    // 仅用 JWT 主体隔离本机恢复键；预约身份和资格仍由服务端验证。
    private static func reservationPrincipal(_ token: String) -> String {
        let parts = token.split(separator: ".")
        if parts.count == 3 {
            var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            if let data = Data(base64Encoded: payload),
               let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let subject = claims["sub"] as? String, !subject.isEmpty { return subject }
        }
        return SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
