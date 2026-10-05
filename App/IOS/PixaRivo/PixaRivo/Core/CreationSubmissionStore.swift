import Foundation
import Observation

enum PixaCreationSubmissionPhase: String, Codable, Sendable {
    case uploading
    case submitting
    case failed
}

enum PixaCreationSubmissionFailureAction: String, Codable, Sendable {
    case retry
    case reviewTemplate
    case buyPoints
}

struct PixaCreationSubmissionItem: Identifiable, Sendable {
    let id: String
    let title: String
    let aspectRatio: String
    let previewData: Data?
    let createdAt: Date
    var phase: PixaCreationSubmissionPhase
    var errorMessage: String?
    var failureAction: PixaCreationSubmissionFailureAction?
    let sentBytes: Int64
    let totalBytes: Int64
    let isProgressDeterminate: Bool

    var isAwaitingAssetConfirmation: Bool {
        phase == .uploading && isProgressDeterminate
            && totalBytes > 0 && sentBytes >= totalBytes
    }

    var uploadProgress: Double? {
        guard phase == .uploading, isProgressDeterminate,
              totalBytes > 0, !isAwaitingAssetConfirmation else {
            return nil
        }
        return min(1, max(0, Double(sentBytes) / Double(totalBytes)))
    }
}

struct PixaQueuedTemplateSlot: Sendable {
    let slotKey: String
    let slotIndex: Int
    let name: String
    let fileExtension: String
    let mimeType: String
    let data: Data?
    var assetID: String?
}

struct PixaQueuedComposition: Sendable {
    let clientRequestID: String
    let templateID: String
    let templateKey: String
    let templateName: String
    var slots: [PixaQueuedTemplateSlot]
    let textValues: [String: String]
    let language: String
    let aspectRatio: String
    let resolution: String
    let recommendToGallery: Bool
    let promoMarkEnabled: Bool
    let selectedDisplayModelKey: String?
    let pricingRulesVersion: String?
    let localCalculatedPoints: Int
    let previewData: Data?
}

@MainActor
@Observable
final class PixaCreationSubmissionStore {
    private(set) var items: [PixaCreationSubmissionItem] = []
    private var requiresWorksReconciliation = false

    init() {
        refresh()
        requiresWorksReconciliation = PixaBackgroundTransferManager.shared
            .consumeWorksReconciliationRequest()
    }

    func enqueue(
        _ payload: PixaQueuedComposition,
        session: SessionStore,
        workActivity: PixaWorkActivityStore,
        navigation: PixaNavigationStore
    ) {
        guard let userID = session.user?.id,
              let token = PixaCredentialStore.load()?.accessToken else { return }
        PixaBackgroundTransferManager.shared.enqueue(
            payload,
            userID: userID,
            accessToken: token
        )
        refresh()
    }

    func retry(
        id: String,
        session: SessionStore,
        workActivity: PixaWorkActivityStore,
        navigation: PixaNavigationStore
    ) {
        guard let token = PixaCredentialStore.load()?.accessToken else { return }
        PixaBackgroundTransferManager.shared.retry(id: id, accessToken: token)
        refresh()
    }

    func cancel(id: String) {
        PixaBackgroundTransferManager.shared.cancel(id: id)
        refresh()
    }

    func reset() {
        PixaBackgroundTransferManager.shared.reset()
        refresh()
    }

    func refresh() {
        items = PixaBackgroundTransferManager.shared.currentItems()
    }

    func consumeWorksReconciliationRequest() -> Bool {
        let required = requiresWorksReconciliation
        requiresWorksReconciliation = false
        return required
    }
}
