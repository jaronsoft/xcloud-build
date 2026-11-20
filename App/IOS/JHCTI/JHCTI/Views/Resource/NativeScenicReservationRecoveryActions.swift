import SwiftUI

@MainActor
extension ResourceDetailView {
    func invalidateScenicRecovery() {
        scenicRecoverySequence += 1; scenicRecoveryChecking = false
        scenicRecoveryResults = []; scenicRecoveryMessage = nil; scenicRecoveryClear = nil
        scenicRecoveryPending = false; scenicRecoveryLegacy = false
    }

    func recoverScenicReservations(includeLegacy: Bool = false) async {
        guard item.resourceType == "ScenicSpot", scenePhase == .active, !reservationBusy, !scenicRecoveryChecking,
              let resourceNumber = Int64(item.id), resourceNumber > 0, String(resourceNumber) == item.id,
              let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else { return }
        let indexKey = NativeScenicReservationRecoveryRules.reservationRecoveryIndexKey(token: token, resourceID: item.id)
        let snapshot = UserDefaults.standard.string(forKey: indexKey)
        scenicRecoveryPending = UserDefaults.standard.object(forKey: indexKey) != nil
        let allLegacy = UserDefaults.standard.dictionaryRepresentation().compactMap { key, value -> (String, String)? in
            guard key.range(of: "^jhcti\\.reservation\\.[0-9a-f]{64}$", options: .regularExpression) != nil,
                  let request = value as? String, request.range(of: "^[A-Za-z0-9._:-]{8,80}$", options: .regularExpression) != nil else { return nil }
            return (key, request)
        }.sorted { $0.0 < $1.0 }
        scenicRecoveryLegacy = !allLegacy.isEmpty
        var candidates: [(String, String)] = []
        if let snapshot {
            let parts = snapshot.components(separatedBy: "|")
            guard parts.count == 2, parts[0].range(of: "^jhcti\\.reservation\\.([0-9a-f]{64}|v2\\.[0-9a-f]{64}\\.[1-9][0-9]*\\.[0-9]+\\.[0-9]{4}-[0-9]{2}-[0-9]{2})$", options: .regularExpression) != nil,
                  parts[1].range(of: "^[A-Za-z0-9._:-]{8,80}$", options: .regularExpression) != nil else {
                scenicRecoveryMessage = "预约恢复索引异常，请先核对行程，确认后可清理索引。"; return
            }
            candidates = [(parts[0], parts[1])]
        } else if scenicRecoveryPending {
            scenicRecoveryMessage = "无法读取本机预约恢复索引，请先在行程中核对记录。"; return
        }
        if includeLegacy && snapshot == nil {
            guard allLegacy.count <= 100 else { scenicRecoveryMessage = "本机旧记录较多，请先在行程中核对本人预约。旧标记已保留。"; return }
            candidates += allLegacy.filter { legacy in !candidates.contains { $0.0 == legacy.0 } }
        }
        guard !candidates.isEmpty else { return }
        scenicRecoverySequence += 1; let operation = scenicRecoverySequence
        scenicRecoveryChecking = true; scenicRecoveryResults = []; scenicRecoveryMessage = "正在核对原请求，无需重新选择日期或场次。"
        func current() -> Bool {
            operation == scenicRecoverySequence && scenePhase == .active && !reservationBusy
                && nativeTourismPrincipal(store.session?.accessToken) == principal
                && UserDefaults.standard.string(forKey: indexKey) == snapshot
        }
        defer { if operation == scenicRecoverySequence { scenicRecoveryChecking = false } }
        var confirmed: [[String: Any]] = []
        var resolved: [(String, String)] = []
        do {
            for (storageKey, key) in candidates {
                guard current() else { return }
                let value = try await MobileAPI(store: store).get("/api/JHCTITourismReservation/GetMineByIdempotencyKey?resourceId=\(item.id)&idempotencyKey=\(key)",
                    authenticated: true, expectedPrincipal: principal)
                guard current() else { return }
                // 旧哈希键需由本人查询结果反算原键后才能确认并清理。
                guard var result = value as? [String: Any], Self.scenicRecoveryMatches(result, token: token, resourceID: item.id, storageKey: storageKey) else { continue }
                let stored = UserDefaults.standard.string(forKey: storageKey)
                guard stored == key || (stored == nil && snapshot == storageKey + "|" + key) else { continue }
                result["CredentialCode"] = ""; result["IdentityNumberMasked"] = nil
                confirmed.append(result); resolved.append((storageKey, key))
            }
            guard current() else { return }
            for (storageKey, key) in resolved {
                if UserDefaults.standard.string(forKey: storageKey) == key { UserDefaults.standard.removeObject(forKey: storageKey) }
                if snapshot == storageKey + "|" + key, UserDefaults.standard.string(forKey: storageKey) == nil {
                    UserDefaults.standard.removeObject(forKey: indexKey)
                }
            }
            scenicRecoveryResults = confirmed
            scenicRecoveryPending = UserDefaults.standard.object(forKey: indexKey) != nil
            scenicRecoveryLegacy = allLegacy.contains { UserDefaults.standard.string(forKey: $0.0) != nil }
            scenicRecoveryMessage = scenicRecoveryPending ? "上次预约仍待确认，暂未查到不代表未提交。请保留标记，稍后重试或核对行程。"
                : confirmed.isEmpty ? "未查到与此账号、景点和原请求键匹配的预约。旧标记可能属于其他账号或景点，已保留；请先核对行程。"
                : "已核对原预约。入园二维码及最新状态请在行程中查看。未匹配的旧标记已保留。"
        } catch {
            if current() { scenicRecoveryMessage = "暂时无法核对原预约，恢复标记已保留，请稍后重试。" }
        }
    }

    func clearScenicRecoveryIndex() {
        guard let target = scenicRecoveryClear, !reservationBusy, !scenicRecoveryChecking, scenePhase == .active,
              nativeTourismPrincipal(store.session?.accessToken) == target.2,
              let snapshot = target.1, UserDefaults.standard.string(forKey: target.0) == snapshot else { return }
        scenicRecoverySequence += 1
        UserDefaults.standard.removeObject(forKey: target.0)
        scenicRecoveryPending = UserDefaults.standard.object(forKey: target.0) != nil
        scenicRecoveryClear = nil
        scenicRecoveryMessage = scenicRecoveryPending ? "本机索引尚未清理，请稍后重试。" : "本机索引已清理，原请求键仍保留，不会取消服务端预约。"
    }

    static func scenicRecoveryMatches(_ result: [String: Any], token: String, resourceID: String, storageKey: String) -> Bool {
        guard let id = result["Id"] as? String, let number = Int64(id), number > 0, String(number) == id,
              result["ResourceId"] as? String == resourceID, let session = result["SessionId"] as? String,
              let sessionNumber = Int64(session), sessionNumber >= 0, String(sessionNumber) == session,
              let date = result["ReservationDate"] as? String, let instant = paymentDeadline(date + " 00:00:00"),
              ["Reserved", "Cancelled", "CheckedIn"].contains(result["Status"] as? String ?? ""),
              !(result["SessionName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: instant) == date
            && (NativeScenicReservationRecoveryRules.reservationStorageKey(token: token, resourceID: resourceID, sessionID: session, date: date) == storageKey
                || NativeScenicReservationRecoveryRules.legacyReservationStorageKey(token: token, resourceID: resourceID, sessionID: session, date: date) == storageKey)
    }

    static func reservationStatus(_ result: [String: Any]) -> String {
        if result["Status"] as? String == "Cancelled" { return "已取消" }
        if result["Status"] as? String == "CheckedIn" { return "已入园" }
        guard let text = result["EndTime"] as? String, !text.hasPrefix("0001-01-01"),
              let end = paymentDeadline(text) else { return "已预约（时间待核对）" }
        return end <= Date() ? "已过期" : "已预约"
    }
}
