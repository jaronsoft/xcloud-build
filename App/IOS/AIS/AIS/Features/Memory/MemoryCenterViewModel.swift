import Foundation
import Observation

@MainActor
@Observable
final class MemoryCenterViewModel {
    private let service: MemoryService
    private let projectId: String?
    private var pollTask: Task<Void, Never>?

    private(set) var items: [AISMemoryItem] = []
    private(set) var batches: [AISMemoryExtractionBatch] = []
    private(set) var isLoading = false
    private(set) var isWorking = false
    private(set) var hasMore = true
    var keyword = ""
    var category = ""
    var status = ""
    var selectedIDs = Set<String>()
    var errorMessage: String?

    private var page = 1

    init(
        projectId: String? = nil,
        service: MemoryService = MemoryService()
    ) {
        self.projectId = projectId
        self.service = service
    }

    func reload(session: SessionStore) async {
        page = 1
        hasMore = true
        items = []
        await loadNext(session: session)
        await loadBatches(session: session)
    }

    func loadNext(session: SessionStore) async {
        guard !isLoading, hasMore,
              let token = await session.validAccessToken() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.list(
                token: token,
                page: page,
                keyword: keyword,
                category: category,
                status: status,
                projectId: projectId
            )
            items.append(contentsOf: result.items.filter { candidate in
                !items.contains(where: { $0.id == candidate.id })
            })
            hasMore = items.count < result.total
            if hasMore { page += 1 }
            errorMessage = nil
        } catch {
            guard !AISErrorClassifier.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func save(
        draft: AISMemoryDraft,
        editing: AISMemoryItem?,
        session: SessionStore
    ) async -> Bool {
        guard let token = await session.validAccessToken() else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            var normalized = draft
            normalized.projectId = projectId ?? draft.projectId
            if let editing {
                _ = try await service.update(
                    token: token,
                    id: editing.id,
                    draft: normalized
                )
            } else {
                _ = try await service.create(token: token, draft: normalized)
            }
            await reload(session: session)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func change(
        _ memory: AISMemoryItem,
        action: String,
        session: SessionStore
    ) async {
        guard let token = await session.validAccessToken() else { return }
        await perform {
            try await service.changeStatus(
                token: token,
                id: memory.id,
                action: action
            )
        }
        await reload(session: session)
    }

    func delete(
        _ memory: AISMemoryItem,
        session: SessionStore
    ) async {
        guard let token = await session.validAccessToken() else { return }
        await perform {
            try await service.delete(token: token, id: memory.id)
        }
        await reload(session: session)
    }

    func bulk(action: String, session: SessionStore) async {
        guard !selectedIDs.isEmpty,
              let token = await session.validAccessToken() else { return }
        let ids = Array(selectedIDs)
        await perform {
            try await service.bulk(token: token, ids: ids, action: action)
        }
        selectedIDs.removeAll()
        await reload(session: session)
    }

    func startExtraction(session: SessionStore) async {
        guard let token = await session.validAccessToken() else { return }
        await perform {
            _ = try await service.startExtraction(token: token)
        }
        await loadBatches(session: session)
        resumePolling(session: session)
    }

    func loadBatches(session: SessionStore) async {
        guard let token = await session.validAccessToken() else { return }
        do {
            batches = try await service.extractionBatches(token: token).items
        } catch {
            guard !AISErrorClassifier.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func resumePolling(session: SessionStore) {
        stopPolling()
        guard batches.first?.isRunning == true else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { return }
                await self.loadBatches(session: session)
                if self.batches.first?.isRunning != true {
                    await self.reload(session: session)
                    return
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func perform(_ operation: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
            errorMessage = nil
        } catch {
            guard !AISErrorClassifier.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }
}
