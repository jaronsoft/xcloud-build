import SwiftUI

@MainActor final class NativeDiningCreation: ObservableObject {
    @Published private(set) var attempts: [NativeDiningCreationAttempt] = []
    @Published private(set) var storageError = false
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var retry: NativeDiningCreationAttempt?
    private var principal: String?
    private var storeID = ""
    private var task: Task<Void, Never>?
    private var generation = 0

    func configure(principal: String?, storeID: String) {
        generation += 1
        task?.cancel()
        task = nil
        busy = false
        message = nil
        retry = nil
        self.principal = principal
        self.storeID = storeID
        restore()
    }

    func restore() {
        attempts = []
        storageError = false
        guard let principal else { return }
        do { attempts = try recovery(principal).read() }
        catch { storageError = true }
    }

    func blocked(_ slotID: String) -> Bool {
        principal == nil || busy || storageError || attempts.contains { $0.slotID == slotID && $0 != retry }
    }

    func submit(slotID: String, date: String, form: [String: Any], store: SessionStore,
                onAccess: @escaping @MainActor (NativePublicFeatureAccessState) -> Void,
                onResolved: @escaping @MainActor () -> Void) {
        guard !blocked(slotID), let principal, currentPrincipal(store) == principal else { return }
        let retry = retry?.slotID == slotID ? retry : nil
        run(store, principal, failure: "本次提交未确认，请核对原申请。") { generation in
            let api = MobileAPI(store: store)
            let access = await api.featureAccessState("F-FNB-002", forceRefresh: true)
            guard self.isCurrent(generation, store, principal) else { return }
            onAccess(access)
            guard access == .open else { return }
            let attempt: NativeDiningCreationAttempt
            do {
                let recovery = try self.recovery(principal)
                attempt = try recovery.prepare(slotID: slotID, date: date, retry: retry)
                self.attempts = try recovery.read()
            } catch {
                self.restore()
                self.message = "无法保存本次提交编号，未发送预订申请。"
                return
            }
            var body = form
            body["StoreId"] = self.storeID
            body["SlotId"] = slotID
            body["IdempotencyKey"] = attempt.key
            let result = try await api.post("/api/JHCTIDining/CreateReservation", body: body, authenticated: true,
                expectedPrincipal: principal, canRefresh: false, requireExplicitResponse: true)
            guard self.isCurrent(generation, store, principal) else { return }
            guard let id = result as? String, NativeDiningReservationAttempt.validID(id) else {
                throw MobileAPIError.unavailable("预订申请编号无效")
            }
            let receipt = try await self.lookup(attempt, api, principal)
            guard self.isCurrent(generation, store, principal) else { return }
            guard let receipt, receipt.id == id else { throw MobileAPIError.unavailable("回执与提交编号不一致") }
            try self.finish(attempt, receipt, principal, onResolved)
        }
    }

    func check(_ attempt: NativeDiningCreationAttempt, store: SessionStore, onResolved: @escaping @MainActor () -> Void) {
        guard !busy, !storageError, let principal, currentPrincipal(store) == principal, attempts.contains(attempt) else { return }
        run(store, principal, failure: "暂时无法核对原申请，已保留提交记录。") { generation in
            let receipt = try await self.lookup(attempt, MobileAPI(store: store), principal)
            guard self.isCurrent(generation, store, principal) else { return }
            if let receipt { try self.finish(attempt, receipt, principal, onResolved) }
            else { self.retry = attempt }
        }
    }

    private func lookup(_ attempt: NativeDiningCreationAttempt, _ api: MobileAPI, _ principal: String) async throws -> (id: String, status: String)? {
        let requestedStore = storeID
        let path = "/api/JHCTIDining/GetMyReservationCreateReceipt?storeId=\(requestedStore)&slotId=\(attempt.slotID)&idempotencyKey=\(attempt.key)"
        let result = try await api.get(path, authenticated: true, expectedPrincipal: principal, requireExplicitResponse: true)
        return try attempt.readReceipt(result, storeID: requestedStore)
    }

    private func run(_ store: SessionStore, _ principal: String, failure: String, operation: @escaping @MainActor (Int) async throws -> Void) {
        generation += 1
        let requestedGeneration = generation
        busy = true
        message = nil
        retry = nil
        task = Task { @MainActor in
            defer { if self.generation == requestedGeneration { self.busy = false; self.task = nil } }
            guard self.isCurrent(requestedGeneration, store, principal) else { return }
            do { try await operation(requestedGeneration) }
            catch {
                if self.isCurrent(requestedGeneration, store, principal) { self.restore(); self.message = failure }
            }
        }
    }

    private func currentPrincipal(_ store: SessionStore) -> String? {
        store.session.flatMap { nativeTourismPrincipal($0.accessToken) }
    }

    private func isCurrent(_ requestedGeneration: Int, _ store: SessionStore, _ principal: String) -> Bool {
        !Task.isCancelled && generation == requestedGeneration && currentPrincipal(store) == principal
    }

    private func recovery(_ principal: String) throws -> NativeDiningCreationRecovery {
        try NativeDiningCreationRecovery(principal: principal, storeID: storeID)
    }

    private func finish(_ attempt: NativeDiningCreationAttempt, _ receipt: (id: String, status: String), _ principal: String,
                        _ onResolved: @MainActor () -> Void) throws {
        try recovery(principal).remove(attempt)
        restore()
        message = "预订 \(receipt.id) 当前为\(DiningPublicReservationPanel.statusName(receipt.status))。"
        onResolved()
    }
}
