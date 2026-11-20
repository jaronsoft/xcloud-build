import Foundation

@MainActor
extension DiningPublicDetailView {
    func loadQueue() async {
        queueRequestSequence += 1
        let requestSequence = queueRequestSequence
        let sessionToken = store.session?.accessToken
        guard Int64(id).map({ $0 > 0 }) == true else {
            if requestSequence == queueRequestSequence { queueState = "error"; queueError = "门店编号无效" }
            return
        }
        queueState = "loading"; queueError = nil; queueSession = nil
        do {
            let access = await MobileAPI(store: store).featureAccessState("F-FNB-003", forceRefresh: true)
            try Task.checkCancellation()
            guard requestSequence == queueRequestSequence, store.session?.accessToken == sessionToken else { return }
            switch access {
            case .open:
                break
            case .closed, .pendingConfirmation:
                queueState = "disabled"
                if store.session != nil { _ = await loadQueueEntries() }
                return
            case .unavailable:
                throw MobileAPIError.unavailable("排队功能开放状态暂时无法确认，请重试")
            }
            let result = try await MobileAPI(store: store).get("/api/JHCTIDining/GetOpenQueueStatus?storeId=\(id)")
            guard requestSequence == queueRequestSequence, store.session?.accessToken == sessionToken else { return }
            if result is NSNull { queueSession = nil }
            else if let value = result as? [String: Any], Self.string(value["StoreId"] ?? value["storeId"]) == id {
                queueSession = value
            } else { throw MobileAPIError.unavailable("排队状态数据与当前门店不匹配") }
            queueState = "open"
            if store.session != nil { _ = await loadQueueEntries() }
        } catch is CancellationError {
            return
        } catch {
            guard requestSequence == queueRequestSequence, store.session?.accessToken == sessionToken else { return }
            queueState = "error"; queueError = error.localizedDescription
        }
    }

    func loadQueueEntries() async -> [[String: Any]]? {
        queueEntriesRequestSequence += 1
        let requestSequence = queueEntriesRequestSequence
        guard let session = store.session else {
            if requestSequence == queueEntriesRequestSequence { queueEntries = []; queueError = nil }
            return []
        }
        queueError = nil
        do {
            let value = try await MobileAPI(store: store).get("/api/JHCTIDining/GetMyQueueEntries?storeId=\(id)", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(session.accessToken))
            guard requestSequence == queueEntriesRequestSequence,
                  store.session?.accessToken == session.accessToken else { return nil }
            guard let rows = value as? [[String: Any]], rows.allSatisfy({
                Self.string($0["StoreId"] ?? $0["storeId"]) == id
                    && Int64(Self.string($0["Id"] ?? $0["id"])).map({ $0 > 0 }) == true
                    && ["Waiting", "Called", "Completed", "Missed", "Cancelled"].contains($0["Status"] as? String ?? $0["status"] as? String ?? "")
            }) else { throw MobileAPIError.unavailable("本人排队记录格式异常，请刷新重试") }
            queueEntries = rows
            return rows
        } catch is CancellationError {
            return nil
        } catch {
            if requestSequence == queueEntriesRequestSequence,
               store.session?.accessToken == session.accessToken { queueError = error.localizedDescription }
            return nil
        }
    }

    func submitQueue() async {
        guard !queueBusy, let session = store.session,
              let queueSession, queueSession["IsOpen"] as? Bool == true || queueSession["isOpen"] as? Bool == true else { return }
        let name = queueName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = queuePhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, phone.count <= 40,
              phone.range(of: "^\\+?[0-9()\\-\\s]{6,40}$", options: .regularExpression) != nil else {
            queueError = "请填写有效的联系人姓名和联系电话"; return
        }
        queueBusy = true; queueError = nil
        defer { queueBusy = false }
        let latestQueueEnabled = await MobileAPI(store: store).featureEnabled("F-FNB-003", forceRefresh: true)
        guard store.session?.accessToken == session.accessToken else { queueError = "登录账号已变化，请重新确认后取号。"; return }
        guard latestQueueEnabled else {
            queueState = "disabled"; self.queueSession = nil
            queueError = "餐饮排队已关闭或暂时无法确认，本次没有取号。"
            return
        }
        var mutationConfirmed = false
        let queueAccess = await MobileAPI(store: store).featureAccessState("F-FNB-003", forceRefresh: true)
        guard store.session?.accessToken == session.accessToken else { return }
        guard queueAccess == .open else {
            self.queueSession = nil
            queueState = queueAccess == .closed || queueAccess == .pendingConfirmation ? "disabled" : "error"
            queueError = queueAccess.message(featureName: "餐饮排队功能", action: "暂不取号")
            return
        }
        do {
            let value = try await MobileAPI(store: store).post("/api/JHCTIDining/JoinQueue", body: [
                "StoreId": id, "GuestName": name, "GuestPhone": phone, "GuestCount": queueCount
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(session.accessToken))
            guard store.session?.accessToken == session.accessToken,
                  let receipt = value as? [String: Any],
                  Self.string(receipt["StoreId"] ?? receipt["storeId"]) == id,
                  Int64(Self.string(receipt["Id"] ?? receipt["id"])).map({ $0 > 0 }) == true,
                  (Self.int(receipt["QueueNumber"] ?? receipt["queueNumber"]) ?? 0) > 0,
                  (receipt["Status"] as? String ?? receipt["status"] as? String) == "Waiting" else {
                throw MobileAPIError.unavailable("取号回执无法确认，请刷新本人排队记录")
            }
            mutationConfirmed = true
            queueName = ""; queuePhone = ""
        } catch is CancellationError {
            if !mutationConfirmed, store.session?.accessToken == session.accessToken {
                queueError = "取号请求已取消，结果可能已提交；请刷新本人排队记录核对。"
            }
            return
        } catch {
            if Task.isCancelled {
                if !mutationConfirmed, store.session?.accessToken == session.accessToken {
                    queueError = "取号请求已取消，结果可能已提交；请刷新本人排队记录核对。"
                }
                return
            }
            guard store.session?.accessToken == session.accessToken else { return }
            let refreshed = await loadQueueEntries()
            guard store.session?.accessToken == session.accessToken else { return }
            if refreshed?.contains(where: {
                Self.string($0["StoreId"] ?? $0["storeId"]) == id
                    && ["Waiting", "Called"].contains($0["Status"] as? String ?? $0["status"] as? String ?? "")
            }) == true { queueError = nil }
            else if refreshed == nil { queueError = "取号结果暂无法确认，请刷新本人排队记录" }
            else { queueError = error.localizedDescription }
        }
        if store.session?.accessToken == session.accessToken { await loadQueue() }
    }

    func cancelQueueEntry(_ entryID: String) async {
        guard !queueBusy, let session = store.session, Int64(entryID).map({ $0 > 0 }) == true else { return }
        queueBusy = true; queueError = nil
        defer { queueBusy = false; queueCancelID = "" }
        var mutationConfirmed = false
        do {
            let value = try await MobileAPI(store: store).post("/api/JHCTIDining/CancelMyQueueEntry?id=\(entryID)", body: [:],
                authenticated: true, expectedPrincipal: nativeTourismPrincipal(session.accessToken))
            guard store.session?.accessToken == session.accessToken, Self.string(value) == entryID else {
                throw MobileAPIError.unavailable("取消回执无法确认，请刷新本人排队记录")
            }
            mutationConfirmed = true
        } catch is CancellationError {
            if !mutationConfirmed, store.session?.accessToken == session.accessToken {
                queueError = "取消请求已取消，结果可能已提交；请刷新本人排队记录核对。"
            }
            return
        } catch {
            if Task.isCancelled {
                if !mutationConfirmed, store.session?.accessToken == session.accessToken {
                    queueError = "取消请求已取消，结果可能已提交；请刷新本人排队记录核对。"
                }
                return
            }
            guard store.session?.accessToken == session.accessToken else { return }
            let refreshed = await loadQueueEntries()
            guard store.session?.accessToken == session.accessToken else { return }
            let stillWaiting = refreshed?.contains {
                Self.string($0["Id"] ?? $0["id"]) == entryID
                    && ($0["Status"] as? String ?? $0["status"] as? String ?? "") == "Waiting"
            } == true
            queueError = refreshed == nil ? "取消结果暂无法确认，请刷新本人排队记录" : stillWaiting ? error.localizedDescription : nil
            return
        }
        guard store.session?.accessToken == session.accessToken else { return }
        _ = await loadQueueEntries()
    }
}
