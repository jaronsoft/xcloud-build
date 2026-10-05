import Foundation
import UIKit

extension Notification.Name {
    static let pixaBackgroundSubmissionsChanged = Notification.Name(
        "PixaBackgroundSubmissionsChanged"
    )
    static let pixaBackgroundSubmissionCompleted = Notification.Name(
        "PixaBackgroundSubmissionCompleted"
    )
}

struct PixaBackgroundSubmissionCompletion: Sendable {
    let jobID: String?
    let title: String
    let aspectRatio: String
}

final class PixaBackgroundTransferManager: NSObject, @unchecked Sendable {
    static let shared = PixaBackgroundTransferManager()
    static let sessionIdentifier = "com.wekarepartners.pixarivo.creation-uploads"
    private static let confirmationValidityInterval: TimeInterval = 30 * 60
    private static let confirmationFutureTolerance: TimeInterval = 5 * 60
    private static let rateLimitRetryDelays: [TimeInterval] = [5, 15]

    private struct StoredSlot: Codable {
        let slotKey: String
        let slotIndex: Int
        let name: String
        let fileExtension: String
        let mimeType: String
        var assetID: String?
        var uploadBodyFilename: String?
        let uploadByteCount: Int64?
    }

    private struct UploadProgress {
        let sentBytes: Int64
        let totalBytes: Int64
    }

    private struct AggregateUploadProgress {
        let sentBytes: Int64
        let totalBytes: Int64
        let isDeterminate: Bool
    }

    private struct StoredSubmission: Codable {
        let id: String
        let userID: String
        let templateID: String
        let templateKey: String
        let templateName: String
        var slots: [StoredSlot]
        let textValues: [String: String]
        let language: String
        let aspectRatio: String
        let resolution: String
        let recommendToGallery: Bool
        let promoMarkEnabled: Bool
        let selectedDisplayModelKey: String?
        let pricingRulesVersion: String?
        let localCalculatedPoints: Int
        let previewFilename: String?
        let createdAt: Date
        var confirmedAt: Date?
        var clientInstanceID: String?
        var clientAppVersion: String?
        var phase: PixaCreationSubmissionPhase
        var errorMessage: String?
        var failureAction: PixaCreationSubmissionFailureAction?
        var attempts: [String: Int]
    }

    private struct SubmissionBody: Encodable {
        let clientRequestId: String
        let clientConfirmedAt: String
        let clientInstanceId: String
        let clientAppVersion: String
        let sourceAssetId: String?
        let referenceAssetIds: [String]
        let textValues: [String: String]
        let entry: String
        let language: String
        let aspectRatio: String
        let resolution: String
        let additionalRequirement: String
        let recommendToGallery: Bool
        let promoMarkEnabled: Bool
        let selectedDisplayModelKey: String?
        let clientSnapshot: SubmissionSnapshot
        let pricingRulesVersion: String?
        let localCalculatedPoints: Int
    }

    private struct SubmissionSnapshot: Encodable {
        let templateKey: String
        let templateName: String
        let imageSlots: [SubmissionSlotSnapshot]
        let textValues: [String: String]
        let selectedAspectRatio: String
        let selectedResolution: String
        let recommendToGallery: Bool
        let promoMarkEnabled: Bool
    }

    private struct SubmissionSlotSnapshot: Encodable {
        let slotKey: String
        let slotIndex: Int
        let name: String
        let assetId: String
    }

    private enum TaskKind: String {
        case upload
        case submit
    }

    private struct TaskKey: Hashable {
        let submissionID: String
        let kind: TaskKind
        let slotKey: String?

        var description: String {
            [submissionID, kind.rawValue, slotKey ?? ""].joined(separator: "|")
        }

        init(submissionID: String, kind: TaskKind, slotKey: String? = nil) {
            self.submissionID = submissionID
            self.kind = kind
            self.slotKey = slotKey
        }

        init?(_ description: String?) {
            guard let description else { return nil }
            let values = description.split(separator: "|", omittingEmptySubsequences: false)
            guard values.count == 3, let kind = TaskKind(rawValue: String(values[1])) else {
                return nil
            }
            submissionID = String(values[0])
            self.kind = kind
            slotKey = values[2].isEmpty ? nil : String(values[2])
        }
    }

    private final class BackgroundEventsCompletion: @unchecked Sendable {
        let handler: () -> Void

        init(_ handler: @escaping () -> Void) {
            self.handler = handler
        }
    }

    private let stateQueue = DispatchQueue(label: "com.wekarepartners.pixarivo.background-transfer-state")
    private let fileManager = FileManager.default
    private var submissions: [String: StoredSubmission] = [:]
    private var responseData: [Int: Data] = [:]
    private var responseStatus: [Int: Int] = [:]
    private var uploadProgress: [TaskKey: UploadProgress] = [:]
    private var lastNotifiedPercent: [String: Int] = [:]
    private var requiresWorksReconciliation = false
    private var backgroundEventsCompletion: BackgroundEventsCompletion?
    private var didFinishBackgroundEvents = false

    private static var currentClientInstanceID: String {
        let key = "pixarivo.client_instance_id"
        if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
            return value
        }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    private static var currentClientAppVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "unknown"
        return "\(version) (Build \(build))"
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.sessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        configuration.httpMaximumConnectionsPerHost = 3
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.wekarepartners.pixarivo.background-transfer-delegate"
        delegateQueue.maxConcurrentOperationCount = 1
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: delegateQueue
        )
    }()

    private override init() {
        super.init()
        submissions = loadSubmissions()
        let staleIDs = submissions.values
            .filter { Self.isAcceptedDuplicateMessage($0.errorMessage) }
            .map(\.id)
        if !staleIDs.isEmpty {
            // 历史版本可能把服务端防重成功响应保存为失败项，升级后只清理这类明确的幽灵记录。
            for id in staleIDs {
                submissions[id] = nil
                removeSubmissionFiles(id: id)
            }
            requiresWorksReconciliation = true
            persist()
        }
    }

    func restore() {
        _ = session
        resumePendingTransfers()
    }

    func handleEvents(completionHandler: @escaping () -> Void) {
        let completion = BackgroundEventsCompletion(completionHandler)
        stateQueue.async {
            if self.didFinishBackgroundEvents {
                self.didFinishBackgroundEvents = false
                DispatchQueue.main.async { completion.handler() }
                return
            }
            self.backgroundEventsCompletion = completion
        }
    }

    func currentItems() -> [PixaCreationSubmissionItem] {
        stateQueue.sync {
            submissions.values
                .sorted { $0.createdAt > $1.createdAt }
                .map { submission in
                    let progress = aggregateUploadProgress(for: submission)
                    return PixaCreationSubmissionItem(
                        id: submission.id,
                        title: submission.templateName,
                        aspectRatio: submission.aspectRatio,
                        previewData: submission.previewFilename.flatMap {
                            try? Data(contentsOf: rootDirectory.appending(path: $0))
                        },
                        createdAt: submission.createdAt,
                        phase: submission.phase,
                        errorMessage: submission.errorMessage,
                        failureAction: submission.failureAction
                            ?? inferredFailureAction(for: submission),
                        sentBytes: progress.sentBytes,
                        totalBytes: progress.totalBytes,
                        isProgressDeterminate: progress.isDeterminate
                    )
                }
        }
    }

    func consumeWorksReconciliationRequest() -> Bool {
        stateQueue.sync {
            let required = requiresWorksReconciliation
            requiresWorksReconciliation = false
            return required
        }
    }

    func enqueue(
        _ payload: PixaQueuedComposition,
        userID: String,
        accessToken: String
    ) {
        // 用户刚确认创作便切到后台时，先保留短暂执行时间，确保请求体和后台传输任务都已创建。
        let preparationTask = UIApplication.shared.beginBackgroundTask(
            withName: "PixaRivoPrepareUpload"
        )
        stateQueue.async {
            guard self.submissions[payload.clientRequestID] == nil else {
                self.endPreparationTask(preparationTask)
                return
            }
            do {
                try self.ensureRootDirectory()
                let previewFilename = try self.writePreview(payload)
                var slots: [StoredSlot] = []
                for slot in payload.slots {
                    let bodyFilename = try self.writeUploadBody(
                        slot: slot,
                        submissionID: payload.clientRequestID
                    )
                    let uploadByteCount = bodyFilename.flatMap {
                        self.fileSize(at: self.rootDirectory.appending(path: $0))
                    }
                    slots.append(
                        StoredSlot(
                            slotKey: slot.slotKey,
                            slotIndex: slot.slotIndex,
                            name: slot.name,
                            fileExtension: slot.fileExtension,
                            mimeType: slot.mimeType,
                            assetID: slot.assetID,
                            uploadBodyFilename: bodyFilename,
                            uploadByteCount: uploadByteCount
                        )
                    )
                }
                self.submissions[payload.clientRequestID] = StoredSubmission(
                    id: payload.clientRequestID,
                    userID: userID,
                    templateID: payload.templateID,
                    templateKey: payload.templateKey,
                    templateName: payload.templateName,
                    slots: slots,
                    textValues: payload.textValues,
                    language: payload.language,
                    aspectRatio: payload.aspectRatio,
                    resolution: payload.resolution,
                    recommendToGallery: payload.recommendToGallery,
                    promoMarkEnabled: payload.promoMarkEnabled,
                    selectedDisplayModelKey: payload.selectedDisplayModelKey,
                    pricingRulesVersion: payload.pricingRulesVersion,
                    localCalculatedPoints: payload.localCalculatedPoints,
                    previewFilename: previewFilename,
                    createdAt: .now,
                    confirmedAt: .now,
                    clientInstanceID: Self.currentClientInstanceID,
                    clientAppVersion: Self.currentClientAppVersion,
                    phase: .uploading,
                    errorMessage: nil,
                    failureAction: nil,
                    attempts: [:]
                )
                self.persist()
                self.notifyChanged()
                self.scheduleMissingTransfers(
                    submissionID: payload.clientRequestID,
                    accessToken: accessToken,
                    completion: { self.endPreparationTask(preparationTask) }
                )
            } catch {
                self.storePreparationFailure(payload, userID: userID, error: error)
                self.endPreparationTask(preparationTask)
            }
        }
    }

    func retry(id: String, accessToken: String) {
        stateQueue.async {
            guard var submission = self.submissions[id] else { return }
            submission.phase = submission.slots.allSatisfy { $0.assetID != nil }
                ? .submitting : .uploading
            submission.errorMessage = nil
            submission.failureAction = nil
            submission.attempts = [:]
            submission.confirmedAt = .now
            submission.clientInstanceID = Self.currentClientInstanceID
            submission.clientAppVersion = Self.currentClientAppVersion
            self.submissions[id] = submission
            self.clearProgress(submissionID: id)
            self.persist()
            self.notifyChanged()
            self.scheduleMissingTransfers(submissionID: id, accessToken: accessToken)
        }
    }

    func cancel(id: String) {
        stateQueue.async {
            self.session.getAllTasks { tasks in
                tasks.filter { TaskKey($0.taskDescription)?.submissionID == id }
                    .forEach { $0.cancel() }
            }
            self.removeSubmission(id: id)
        }
    }

    func reset() {
        stateQueue.async {
            let ids = Set(self.submissions.keys)
            self.session.getAllTasks { tasks in
                tasks.filter {
                    guard let id = TaskKey($0.taskDescription)?.submissionID else { return false }
                    return ids.contains(id)
                }.forEach { $0.cancel() }
            }
            for id in ids { self.removeSubmissionFiles(id: id) }
            self.submissions.removeAll()
            self.uploadProgress.removeAll()
            self.lastNotifiedPercent.removeAll()
            self.persist()
            self.notifyChanged()
        }
    }

    private func resumePendingTransfers() {
        stateQueue.async {
            guard let stored = PixaCredentialStore.load() else {
                self.notifyChanged()
                return
            }
            let pendingSubmissionIDs = self.submissions.values
                .filter { $0.userID == stored.user.id && $0.phase != .failed }
                .map(\.id)
            for submissionID in pendingSubmissionIDs {
                guard let submission = self.submissions[submissionID] else { continue }
                guard self.hasFreshConfirmation(submission) else {
                    self.requireFreshConfirmation(submissionID: submissionID)
                    continue
                }
                self.scheduleMissingTransfers(
                    submissionID: submissionID,
                    accessToken: stored.accessToken
                )
            }
            self.notifyChanged()
        }
    }

    private func scheduleMissingTransfers(
        submissionID: String,
        accessToken: String,
        completion: (() -> Void)? = nil
    ) {
        session.getAllTasks { tasks in
            let activeKeys = Set(tasks.compactMap { TaskKey($0.taskDescription) })
            self.stateQueue.async {
                self.restoreProgress(from: tasks, submissionID: submissionID)
                self.scheduleMissingTransfers(
                    submissionID: submissionID,
                    accessToken: accessToken,
                    activeKeys: activeKeys
                )
                completion?()
            }
        }
    }

    private func scheduleMissingTransfers(
        submissionID: String,
        accessToken: String,
        activeKeys: Set<TaskKey>
    ) {
        guard var submission = submissions[submissionID], submission.phase != .failed else {
            return
        }
        let pendingSlots = submission.slots.filter { $0.assetID == nil }
        if !pendingSlots.isEmpty {
            submission.phase = .uploading
            submissions[submissionID] = submission
            persist()
            for slot in pendingSlots {
                let key = TaskKey(
                    submissionID: submissionID,
                    kind: .upload,
                    slotKey: slot.slotKey
                )
                guard !activeKeys.contains(key),
                      let filename = slot.uploadBodyFilename else { continue }
                scheduleUpload(
                    submission: submission,
                    slot: slot,
                    bodyURL: rootDirectory.appending(path: filename),
                    key: key,
                    accessToken: accessToken
                )
            }
            notifyChanged()
            return
        }

        submission.phase = .submitting
        submissions[submissionID] = submission
        persist()
        let key = TaskKey(submissionID: submissionID, kind: .submit)
        guard !activeKeys.contains(key) else {
            notifyChanged()
            return
        }
        scheduleSubmission(submission, accessToken: accessToken)
    }

    private func scheduleSubmission(
        _ submission: StoredSubmission,
        accessToken: String
    ) {
        guard hasFreshConfirmation(submission) else {
            requireFreshConfirmation(submissionID: submission.id)
            return
        }
        let key = TaskKey(submissionID: submission.id, kind: .submit)
        do {
            let bodyURL = try writeSubmissionBody(submission)
            var request = makeRequest(
                path: "/api/ais/style-templates/\(submission.templateID)/generate",
                accessToken: accessToken
            )
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(
                submission.clientAppVersion ?? Self.currentClientAppVersion,
                forHTTPHeaderField: "X-Client-Version"
            )
            request.setValue(
                submission.clientInstanceID ?? Self.currentClientInstanceID,
                forHTTPHeaderField: "X-Client-Instance"
            )
            request.timeoutInterval = 180
            let task = session.uploadTask(with: request, fromFile: bodyURL)
            task.taskDescription = key.description
            task.resume()
            notifyChanged()
        } catch {
            fail(
                submissionID: submission.id,
                message: error.localizedDescription,
                action: .retry
            )
        }
    }

    private func scheduleTransfer(_ key: TaskKey, accessToken: String) {
        guard let submission = submissions[key.submissionID], submission.phase != .failed else {
            return
        }
        switch key.kind {
        case .upload:
            guard let slotKey = key.slotKey,
                  let slot = submission.slots.first(where: { $0.slotKey == slotKey }),
                  slot.assetID == nil,
                  let filename = slot.uploadBodyFilename else { return }
            scheduleUpload(
                submission: submission,
                slot: slot,
                bodyURL: rootDirectory.appending(path: filename),
                key: key,
                accessToken: accessToken
            )
        case .submit:
            guard submission.slots.allSatisfy({ $0.assetID != nil }) else { return }
            scheduleSubmission(submission, accessToken: accessToken)
        }
    }

    private func scheduleUpload(
        submission: StoredSubmission,
        slot: StoredSlot,
        bodyURL: URL,
        key: TaskKey,
        accessToken: String
    ) {
        guard fileManager.fileExists(atPath: bodyURL.path) else {
            fail(
                submissionID: submission.id,
                message: AppLanguage.localized("submission.upload_failed"),
                action: nil
            )
            return
        }
        let boundary = "PixaRivo-\(submission.id)-\(safeFilename(slot.slotKey))"
        var request = makeRequest(path: "/api/ais/assets", accessToken: accessToken)
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.timeoutInterval = 180
        let task = session.uploadTask(with: request, fromFile: bodyURL)
        task.taskDescription = key.description
        task.resume()
    }

    private func makeRequest(path: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: AppConfiguration.apiBaseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(AppLanguage.isChinese ? "zh-CN" : "en-US", forHTTPHeaderField: "Accept-Language")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        request.setValue(PixaMediaRegion.headerValue, forHTTPHeaderField: "X-AIS-Media-Region")
        request.setValue(PixaMediaRegion.preferenceHeaderValue, forHTTPHeaderField: "X-AIS-Media-Region-Preference")
        return request
    }

    private func writePreview(_ payload: PixaQueuedComposition) throws -> String? {
        guard let data = payload.previewData else { return nil }
        let filename = "\(payload.clientRequestID)-preview.jpg"
        try data.write(to: rootDirectory.appending(path: filename), options: .atomic)
        return filename
    }

    private func writeUploadBody(
        slot: PixaQueuedTemplateSlot,
        submissionID: String
    ) throws -> String? {
        guard slot.assetID == nil, let data = slot.data else { return nil }
        let boundary = "PixaRivo-\(submissionID)-\(safeFilename(slot.slotKey))"
        var body = Data()
        let fields = [
            "assetType": "reference",
            "referenceRole": "template_image_slot",
            "preserveMode": "reference",
            "displayName": slot.name,
            "userNote": slot.name
        ]
        for (key, value) in fields {
            body.appendUTF8(
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n"
            )
        }
        body.appendUTF8(
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename(slot.slotKey)).\(slot.fileExtension)\"\r\nContent-Type: \(slot.mimeType)\r\n\r\n"
        )
        body.append(data)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        let filename = "\(submissionID)-upload-\(safeFilename(slot.slotKey)).body"
        try body.write(to: rootDirectory.appending(path: filename), options: .atomic)
        return filename
    }

    private func writeSubmissionBody(_ submission: StoredSubmission) throws -> URL {
        guard let confirmedAt = submission.confirmedAt else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        let assetIDs = submission.slots.compactMap(\.assetID)
        let snapshots = submission.slots.compactMap { slot -> SubmissionSlotSnapshot? in
            guard let assetID = slot.assetID else { return nil }
            return SubmissionSlotSnapshot(
                slotKey: slot.slotKey,
                slotIndex: slot.slotIndex,
                name: slot.name,
                assetId: assetID
            )
        }
        let body = SubmissionBody(
            clientRequestId: submission.id,
            clientConfirmedAt: confirmedAt.ISO8601Format(),
            clientInstanceId: submission.clientInstanceID ?? Self.currentClientInstanceID,
            clientAppVersion: submission.clientAppVersion ?? Self.currentClientAppVersion,
            sourceAssetId: assetIDs.first,
            referenceAssetIds: assetIDs,
            textValues: submission.textValues,
            entry: "pixarivo_ios",
            language: submission.language,
            aspectRatio: submission.aspectRatio,
            resolution: submission.resolution,
            additionalRequirement: "",
            recommendToGallery: submission.recommendToGallery,
            promoMarkEnabled: submission.promoMarkEnabled,
            selectedDisplayModelKey: submission.selectedDisplayModelKey,
            clientSnapshot: SubmissionSnapshot(
                templateKey: submission.templateKey,
                templateName: submission.templateName,
                imageSlots: snapshots,
                textValues: submission.textValues,
                selectedAspectRatio: submission.aspectRatio,
                selectedResolution: submission.resolution,
                recommendToGallery: submission.recommendToGallery,
                promoMarkEnabled: submission.promoMarkEnabled
            ),
            pricingRulesVersion: submission.pricingRulesVersion,
            localCalculatedPoints: submission.localCalculatedPoints
        )
        let data = try JSONEncoder().encode(body)
        let url = rootDirectory.appending(path: "\(submission.id)-submit.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func processCompletion(
        task: URLSessionTask,
        error: Error?,
        data: Data,
        statusCode: Int?
    ) {
        guard let key = TaskKey(task.taskDescription), submissions[key.submissionID] != nil else {
            return
        }
        if key.kind == .upload,
           let envelope = try? JSONDecoder().decode(
               APIEnvelope<AssetUploadResult>.self,
               from: data
           ),
           envelope.success,
           let asset = envelope.response,
           !asset.id.isEmpty {
            // 后台会话恢复时状态回调可能缺失；只要服务端已返回资产 ID，就应视为上传完成并继续提交。
            completeUpload(key: key, asset: asset, task: task)
            return
        }
        if key.kind == .submit,
           let envelope = try? JSONDecoder().decode(
               APIEnvelope<CompositionResult>.self,
               from: data
           ),
           let result = envelope.response,
           !result.jobID.isEmpty {
            completeSubmission(key: key, jobID: result.jobID)
            return
        }
        if key.kind == .submit, Self.isAcceptedDuplicateMessage(responseMessage(data)) {
            completeSubmission(key: key, jobID: nil)
            return
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return
        }
        let resolvedStatusCode = statusCode
            ?? (task.response as? HTTPURLResponse)?.statusCode
        if resolvedStatusCode == 401 {
            refreshCredentialsAndRetry(key: key, rejectedToken: bearerToken(from: task))
            return
        }
        if let error {
            retryOrFail(key: key, message: error.localizedDescription, retryable: true)
            return
        }
        guard let resolvedStatusCode, (200..<300).contains(resolvedStatusCode) else {
            let message = responseMessage(data)
                ?? HTTPURLResponse.localizedString(forStatusCode: resolvedStatusCode ?? 0)
            retryOrFail(
                key: key,
                message: message,
                retryable: resolvedStatusCode.map {
                    $0 >= 500 || $0 == 408 || $0 == 429
                } ?? true,
                useRateLimitBackoff: resolvedStatusCode == 429
            )
            return
        }

        switch key.kind {
        case .upload:
            retryOrFail(
                key: key,
                message: responseMessage(data)
                    ?? AppLanguage.localized("submission.upload_failed"),
                retryable: false
            )
        case .submit:
            retryOrFail(
                key: key,
                message: responseMessage(data) ?? APIError.invalidResponse.localizedDescription,
                retryable: false
            )
        }
    }

    private func completeUpload(
        key: TaskKey,
        asset: AssetUploadResult,
        task: URLSessionTask
    ) {
        guard let slotKey = key.slotKey,
              var submission = submissions[key.submissionID],
              let index = submission.slots.firstIndex(where: { $0.slotKey == slotKey }) else {
            return
        }
        submission.slots[index].assetID = asset.id
        if let filename = submission.slots[index].uploadBodyFilename {
            try? fileManager.removeItem(at: rootDirectory.appending(path: filename))
        }
        submission.slots[index].uploadBodyFilename = nil
        submission.attempts[key.description] = nil
        submissions[key.submissionID] = submission
        persist()
        notifyChanged()
        if submission.slots.allSatisfy({ $0.assetID != nil }) {
            submission.phase = .submitting
            submissions[key.submissionID] = submission
            persist()
            scheduleSubmission(
                submission,
                accessToken: PixaCredentialStore.load()?.accessToken
                    ?? bearerToken(from: task) ?? ""
            )
        }
    }

    private func completeSubmission(key: TaskKey, jobID: String?) {
        guard let submission = submissions[key.submissionID] else { return }
        let completion = PixaBackgroundSubmissionCompletion(
            jobID: jobID,
            title: submission.templateName,
            aspectRatio: submission.aspectRatio
        )
        removeSubmission(id: key.submissionID)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .pixaBackgroundSubmissionCompleted,
                object: completion
            )
            NotificationCenter.default.post(name: .pixaBalanceDidChange, object: nil)
        }
    }

    private func retryOrFail(
        key: TaskKey,
        message: String,
        retryable: Bool,
        useRateLimitBackoff: Bool = false
    ) {
        guard var submission = submissions[key.submissionID] else { return }
        let attempts = (submission.attempts[key.description] ?? 0) + 1
        submission.attempts[key.description] = attempts
        submissions[key.submissionID] = submission
        persist()
        if retryable, attempts < 3,
           let token = PixaCredentialStore.load()?.accessToken {
            if useRateLimitBackoff {
                let delay = Self.rateLimitRetryDelays[
                    min(attempts - 1, Self.rateLimitRetryDelays.count - 1)
                ]
                // 限流窗口尚未恢复时延迟重试，避免后台上传立即重放同一请求。
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled, let self else { return }
                    self.stateQueue.async { [weak self] in
                        guard let self, self.submissions[key.submissionID] != nil else {
                            return
                        }
                        self.scheduleTransfer(key, accessToken: token)
                    }
                }
                return
            }
            scheduleTransfer(key, accessToken: token)
            return
        }
        fail(
            submissionID: key.submissionID,
            message: message,
            action: retryable ? .retry : classifyFailureAction(message)
        )
    }

    private func refreshCredentialsAndRetry(key: TaskKey, rejectedToken: String?) {
        Task {
            let outcome = await PixaCredentialRecovery.shared.refreshAccessToken(
                rejectedAccessToken: rejectedToken
            )
            self.stateQueue.async {
                switch outcome {
                case let .available(token):
                    self.scheduleTransfer(key, accessToken: token)
                case .preserved:
                    self.fail(
                        submissionID: key.submissionID,
                        message: AppLanguage.localized("auth.session_invalid"),
                        action: .retry
                    )
                case .rejected:
                    break
                }
            }
        }
    }

    private func fail(
        submissionID: String,
        message: String,
        action: PixaCreationSubmissionFailureAction?
    ) {
        guard var submission = submissions[submissionID] else { return }
        submission.phase = .failed
        submission.errorMessage = action == .reviewTemplate
            ? AppLanguage.localized("editor.pricing.changed") : message
        submission.failureAction = action
        submissions[submissionID] = submission
        persist()
        notifyChanged()
    }

    private func classifyFailureAction(
        _ message: String
    ) -> PixaCreationSubmissionFailureAction? {
        if message.hasPrefix("PRICE_CHANGED|") || message == "PRICE_CHANGED" {
            return .reviewTemplate
        }
        let normalized = message.lowercased()
        if normalized.contains("points_not_enough")
            || normalized.contains("insufficient")
            || message.contains("积分不足") {
            return .buyPoints
        }
        if message.contains("参考图不存在或无权访问")
            || normalized.contains("reference image does not exist")
            || normalized.contains("reference image unavailable") {
            return .retry
        }
        return nil
    }

    private func inferredFailureAction(
        for submission: StoredSubmission
    ) -> PixaCreationSubmissionFailureAction? {
        guard submission.phase == .failed, let message = submission.errorMessage else {
            return nil
        }
        return classifyFailureAction(message)
    }

    private func responseMessage(_ data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(APIEnvelope<EmptyResponse>.self, from: data) else {
            return nil
        }
        guard let code = envelope.extra?.messageCode, !code.isEmpty else {
            return envelope.message
        }
        let key = "api.\(code.uppercased())"
        let localized = AppLanguage.localized(key)
        guard localized != key else { return envelope.message }
        return envelope.extra?.messageParams.reduce(localized) { message, entry in
            message.replacingOccurrences(of: "{\(entry.key)}", with: entry.value.text)
        } ?? localized
    }

    private func bearerToken(from task: URLSessionTask) -> String? {
        guard let authorization = task.originalRequest?.value(
            forHTTPHeaderField: "Authorization"
        ), authorization.hasPrefix("Bearer ") else { return nil }
        return String(authorization.dropFirst("Bearer ".count))
    }

    private func storePreparationFailure(
        _ payload: PixaQueuedComposition,
        userID: String,
        error: Error
    ) {
        submissions[payload.clientRequestID] = StoredSubmission(
            id: payload.clientRequestID,
            userID: userID,
            templateID: payload.templateID,
            templateKey: payload.templateKey,
            templateName: payload.templateName,
            slots: payload.slots.map {
                StoredSlot(
                    slotKey: $0.slotKey,
                    slotIndex: $0.slotIndex,
                    name: $0.name,
                    fileExtension: $0.fileExtension,
                    mimeType: $0.mimeType,
                    assetID: $0.assetID,
                    uploadBodyFilename: nil,
                    uploadByteCount: nil
                )
            },
            textValues: payload.textValues,
            language: payload.language,
            aspectRatio: payload.aspectRatio,
            resolution: payload.resolution,
            recommendToGallery: payload.recommendToGallery,
            promoMarkEnabled: payload.promoMarkEnabled,
            selectedDisplayModelKey: payload.selectedDisplayModelKey,
            pricingRulesVersion: payload.pricingRulesVersion,
            localCalculatedPoints: payload.localCalculatedPoints,
            previewFilename: nil,
            createdAt: .now,
            confirmedAt: nil,
            clientInstanceID: Self.currentClientInstanceID,
            clientAppVersion: Self.currentClientAppVersion,
            phase: .failed,
            errorMessage: error.localizedDescription,
            failureAction: nil,
            attempts: [:]
        )
        persist()
        notifyChanged()
    }

    private func hasFreshConfirmation(
        _ submission: StoredSubmission,
        now: Date = .now
    ) -> Bool {
        guard let confirmedAt = submission.confirmedAt else { return false }
        let age = now.timeIntervalSince(confirmedAt)
        return age >= -Self.confirmationFutureTolerance
            && age <= Self.confirmationValidityInterval
    }

    private func requireFreshConfirmation(submissionID: String) {
        guard var submission = submissions[submissionID] else { return }
        submission.phase = .failed
        submission.errorMessage = AppLanguage.localized("submission.confirmation_expired")
        submission.failureAction = .retry
        submissions[submissionID] = submission
        session.getAllTasks { tasks in
            tasks.filter {
                TaskKey($0.taskDescription)?.submissionID == submissionID
            }.forEach { $0.cancel() }
        }
        persist()
        notifyChanged()
    }

    private func removeSubmission(id: String) {
        guard submissions.removeValue(forKey: id) != nil else { return }
        clearProgress(submissionID: id)
        removeSubmissionFiles(id: id)
        persist()
        notifyChanged()
    }

    private func removeSubmissionFiles(id: String) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("\(id)-") {
            try? fileManager.removeItem(at: file)
        }
    }

    private var rootDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "PixaRivoBackgroundUploads", directoryHint: .isDirectory)
    }

    private var indexURL: URL { rootDirectory.appending(path: "submissions.json") }

    private func ensureRootDirectory() throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = rootDirectory
        try? directory.setResourceValues(values)
    }

    private func endPreparationTask(_ task: UIBackgroundTaskIdentifier) {
        guard task != .invalid else { return }
        DispatchQueue.main.async {
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    private func loadSubmissions() -> [String: StoredSubmission] {
        guard let data = try? Data(contentsOf: indexURL),
              let values = try? JSONDecoder().decode([StoredSubmission].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
    }

    private func aggregateUploadProgress(
        for submission: StoredSubmission
    ) -> AggregateUploadProgress {
        let localSlots = submission.slots.filter {
            $0.uploadByteCount != nil || $0.uploadBodyFilename != nil
        }
        guard !localSlots.isEmpty else {
            return AggregateUploadProgress(sentBytes: 0, totalBytes: 0, isDeterminate: false)
        }

        var sentBytes: Int64 = 0
        var totalBytes: Int64 = 0
        for slot in localSlots {
            let key = TaskKey(
                submissionID: submission.id,
                kind: .upload,
                slotKey: slot.slotKey
            )
            let storedTotal = slot.uploadByteCount
                ?? slot.uploadBodyFilename.flatMap {
                    fileSize(at: rootDirectory.appending(path: $0))
                }
            guard let storedTotal, storedTotal > 0 else {
                return AggregateUploadProgress(
                    sentBytes: sentBytes,
                    totalBytes: totalBytes,
                    isDeterminate: false
                )
            }
            totalBytes += storedTotal
            if slot.assetID != nil {
                sentBytes += storedTotal
            } else if let progress = uploadProgress[key] {
                sentBytes += min(storedTotal, max(0, progress.sentBytes))
            }
        }
        return AggregateUploadProgress(
            sentBytes: min(sentBytes, totalBytes),
            totalBytes: totalBytes,
            isDeterminate: totalBytes > 0
        )
    }

    private func restoreProgress(from tasks: [URLSessionTask], submissionID: String) {
        for task in tasks {
            guard let key = TaskKey(task.taskDescription),
                  key.submissionID == submissionID,
                  key.kind == .upload,
                  task.countOfBytesExpectedToSend > 0 else { continue }
            uploadProgress[key] = UploadProgress(
                sentBytes: max(0, task.countOfBytesSent),
                totalBytes: task.countOfBytesExpectedToSend
            )
        }
    }

    private func clearProgress(submissionID: String) {
        uploadProgress = uploadProgress.filter { $0.key.submissionID != submissionID }
        lastNotifiedPercent[submissionID] = nil
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              size > 0 else { return nil }
        return Int64(size)
    }

    private func updateProgress(
        key: TaskKey,
        sentBytes: Int64,
        totalBytes: Int64
    ) {
        guard key.kind == .upload,
              totalBytes > 0,
              let submission = submissions[key.submissionID] else { return }
        uploadProgress[key] = UploadProgress(
            sentBytes: max(0, sentBytes),
            totalBytes: totalBytes
        )
        let aggregate = aggregateUploadProgress(for: submission)
        guard aggregate.isDeterminate, aggregate.totalBytes > 0 else { return }
        let percent = Int(
            min(100, max(0, Double(aggregate.sentBytes) / Double(aggregate.totalBytes) * 100))
        )
        guard lastNotifiedPercent[key.submissionID] != percent else { return }
        lastNotifiedPercent[key.submissionID] = percent
        notifyChanged()
    }

    private static func isAcceptedDuplicateMessage(_ message: String?) -> Bool {
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return message == "任务已提交，请勿重复操作"
            || message == "A generation job is already submitted"
    }

    private func persist() {
        do {
            try ensureRootDirectory()
            let data = try JSONEncoder().encode(Array(submissions.values))
            try data.write(to: indexURL, options: .atomic)
        } catch {
            // 队列持久化失败时保留内存状态，当前进程仍可继续传输。
        }
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .pixaBackgroundSubmissionsChanged,
                object: nil
            )
        }
    }

    private func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
    }
}

extension PixaBackgroundTransferManager: URLSessionDataDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let key = TaskKey(task.taskDescription) else { return }
        stateQueue.async {
            self.updateProgress(
                key: key,
                sentBytes: totalBytesSent,
                totalBytes: totalBytesExpectedToSend
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        stateQueue.async {
            self.responseStatus[dataTask.taskIdentifier] = (response as? HTTPURLResponse)?.statusCode
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        stateQueue.async {
            self.responseData[dataTask.taskIdentifier, default: Data()].append(data)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        stateQueue.async {
            if let key = TaskKey(task.taskDescription), key.kind == .upload {
                self.uploadProgress[key] = nil
                self.notifyChanged()
            }
            let data = self.responseData.removeValue(forKey: task.taskIdentifier) ?? Data()
            let status = self.responseStatus.removeValue(forKey: task.taskIdentifier)
            self.processCompletion(
                task: task,
                error: error,
                data: data,
                statusCode: status
            )
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        stateQueue.async {
            guard let completion = self.backgroundEventsCompletion else {
                self.didFinishBackgroundEvents = true
                return
            }
            self.backgroundEventsCompletion = nil
            self.didFinishBackgroundEvents = false
            DispatchQueue.main.async { completion.handler() }
        }
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(value.data(using: .utf8) ?? Data())
    }
}
