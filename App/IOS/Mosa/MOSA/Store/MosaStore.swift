import Combine
import Foundation
import UIKit

private struct EmptyRecordValidationError: LocalizedError {
    var errorDescription: String? {
        "Add a note or choose a color."
    }
}

enum CloudSyncResult: Equatable {
    case completed
    case completedWithFailures(Int)
    case alreadyRunning
    case signInRequired
    case profileRequired
    case cancelled
    case failed(String)

    var message: String {
        switch self {
        case .completed:
            return "Sync completed. Network requests are shown below."
        case .completedWithFailures(let count):
            return "Sync completed, but \(count) local item(s) could not be uploaded."
        case .alreadyRunning:
            return "A sync is already running."
        case .signInRequired:
            return "Sign in from Profile before syncing with the cloud."
        case .profileRequired:
            return "Save your profile settings before syncing."
        case .cancelled:
            return "Sync was cancelled."
        case .failed(let message):
            return "Sync failed: \(message)"
        }
    }

    var succeeded: Bool {
        switch self {
        case .completed:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class MosaStore: ObservableObject {
    @Published private(set) var profile: LocalProfile?
    @Published private(set) var records: [LocalRecord]
    @Published private(set) var lifeStages: [LocalLifeStage]
    @Published private(set) var annualWorks: [LocalAnnualWork]
    @Published private(set) var artworkGenerationPolicy: ArtworkGenerationPolicy?
    @Published private(set) var session: AuthSession?
    @Published private(set) var publicConfiguration: PublicAppConfiguration
    @Published private(set) var isSyncing = false
    @Published var lastDeletedDate: String?
    @Published var notice: String?
    @Published var pendingGuestImport: [LocalRecord] = []
    let developerLogs: DeveloperNetworkLogStore

    private let repository: LocalRepository
    private let sessionStore: KeychainSessionStore
    private let api: APIClient
    private let publicConfigurationService: PublicConfigurationService
    private var prefetchingShareCardKeys = Set<String>()

    convenience init() {
        self.init(
            repository: LocalRepository(),
            sessionStore: KeychainSessionStore(),
            startsDiagnostics: true
        )
    }

    init(
        repository: LocalRepository,
        sessionStore: KeychainSessionStore,
        startsDiagnostics: Bool
    ) {
        let developerLogs = DeveloperNetworkLogStore()
        let publicConfigurationService = PublicConfigurationService()
        self.repository = repository
        self.sessionStore = sessionStore
        self.developerLogs = developerLogs
        self.publicConfigurationService = publicConfigurationService
        self.api = APIClient(sessionStore: sessionStore, developerLogs: developerLogs)
        if startsDiagnostics {
            DiagnosticsReporter.shared.start()
        }
        publicConfiguration = PublicConfigurationService.cachedOrDefault()
        profile = repository.loadProfile()
        var recordLoadError: String?
        let loadedRecords: [LocalRecord]
        do {
            loadedRecords = try repository.loadRecords()
        } catch {
            loadedRecords = []
            recordLoadError = (error as? LocalizedError)?.errorDescription
                ?? "MOSA could not read your saved records on this iPhone."
        }
        records = loadedRecords.map { record in
            var recovered = record
            if recovered.syncState == .syncing { recovered.syncState = .syncFailed }
            return recovered
        }
        .filter(Self.isValidLocalRecord)
        lifeStages = repository.loadLifeStages().map { stage in
            var recovered = stage
            if recovered.syncState == .syncing { recovered.syncState = .syncFailed }
            return recovered
        }
        annualWorks = repository.loadAnnualWorks().map { work in
            var recovered = work
            if recovered.syncState == .syncing { recovered.syncState = .syncFailed }
            return recovered
        }
        artworkGenerationPolicy = nil
        session = sessionStore.load()
        notice = recordLoadError
        if recordLoadError == nil, records != loadedRecords {
            do {
                try repository.saveRecords(records)
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                    ?? "MOSA could not update your saved records on this iPhone."
            }
        }
    }

    func refreshPublicConfiguration() async {
        publicConfiguration = await publicConfigurationService.refresh()
    }

    var isSignedIn: Bool { session != nil }
    var visibleRecords: [LocalRecord] {
        records.filter { !$0.deleted }.sorted { $0.recordDate > $1.recordDate }
    }

    func setup(displayName: String, startYear: Int) {
        let value = LocalProfile(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            locale: "en",
            timezone: TimeZone.autoupdatingCurrent.identifier,
            startYear: startYear,
            initializedAt: .now
        )
        profile = value
        repository.saveProfile(value)
    }

    func sendCode(email: String, purpose: String) async throws -> String {
        try await api.sendEmailCode(email: email, purpose: purpose)
    }

    func login(email: String, password: String) async throws {
        let result = try await api.login(email: email, password: password)
        completeAuthentication(result, email: email)
    }

    func register(email: String, code: String, password: String, displayName: String) async throws {
        let result = try await api.register(
            email: email,
            code: code,
            password: password,
            displayName: displayName
        )
        completeAuthentication(result, email: email)
    }

    func resetPassword(email: String, code: String, password: String) async throws -> String {
        try await api.resetPassword(email: email, code: code, password: password)
    }

    func logout() async {
        await api.logout()
        sessionStore.save(nil)
        session = nil
        artworkGenerationPolicy = nil
    }

    func deleteAccount(password: String) async throws {
        _ = try await api.deleteAccount(password: password)

        sessionStore.save(nil)
        do {
            try repository.deleteAllData()
        } catch {
            clearAccountState(notice: "Your cloud account was deleted, but MOSA could not remove all local files. Delete and reinstall the app before using this device again.")
            throw LocalRepositoryError(
                operation: .delete,
                file: "MOSA",
                underlyingError: error
            )
        }
        clearAccountState()
    }

    private func clearAccountState(notice message: String = "Your MOSA account and associated data have been permanently deleted.") {
        session = nil
        profile = nil
        records = []
        lifeStages = []
        annualWorks = []
        artworkGenerationPolicy = nil
        pendingGuestImport = []
        lastDeletedDate = nil
        isSyncing = false
        UserDefaults.standard.set(false, forKey: "mosa.initialBackfillOffered")
        DiagnosticsReporter.shared.setEnabled(false)
        developerLogs.clear()
        notice = message
    }

    func createInvitationURL() async throws -> URL {
        guard isSignedIn else { throw APIError(message: "Sign in before creating an invitation.", code: nil, statusCode: 401, retryAfterSeconds: nil) }
        let invitation = try await api.createInvitation()
        guard let path = invitation.invitePath,
              let url = URL(string: path, relativeTo: AppConfiguration.h5BaseURL)?.absoluteURL else {
            throw APIError(message: "The invitation link could not be created.", code: nil, statusCode: 500, retryAfterSeconds: nil)
        }
        return url
    }

    func saveProfile(displayName: String, startYear: Int) async {
        guard var value = profile else { return }
        value.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        value.timezone = TimeZone.autoupdatingCurrent.identifier
        let earliestStageYear = lifeStages.filter { !$0.deleted }.compactMap { Int($0.startMonth.prefix(4)) }.min()
        let earliestRecordYear = records.filter { !$0.deleted }.compactMap { Int($0.recordDate.prefix(4)) }.min()
        value.startYear = [startYear, earliestStageYear ?? startYear, earliestRecordYear ?? startYear].min() ?? startYear
        profile = value
        repository.saveProfile(value)
        guard isSignedIn else { return }
        if let cloud = try? await api.saveProfile(value) {
            profile = cloud.localValue
            repository.saveProfile(profile)
        }
    }

    func record(for date: String) -> LocalRecord? {
        records.first { $0.recordDate == date && !$0.deleted }
    }

    func colors(for date: String) -> [String] {
        CanvasResolver.colors(date: date, record: record(for: date), stages: lifeStages)
    }

    func colorResolution(for date: String) -> CanvasColorResolution {
        CanvasResolver.resolve(date: date, record: record(for: date), stages: lifeStages)
    }

    func saveRecord(
        date: String,
        note: String,
        intentionalBlank: Bool,
        colorCodes: [String],
        tagNames: [String],
        emotions: [LocalEmotion] = [],
        emotionIntensity: EmotionIntensity? = nil,
        blankSource: String? = nil
    ) async throws {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard intentionalBlank || !colorCodes.isEmpty || !trimmedNote.isEmpty else {
            throw EmptyRecordValidationError()
        }
        let existing = records.first { $0.recordDate == date }
        let now = Date()
        let value = LocalRecord(
            id: existing?.id ?? UUID().uuidString,
            recordDate: date,
            note: trimmedNote,
            isIntentionalBlank: intentionalBlank,
            colorCodes: intentionalBlank ? [] : Array(colorCodes.prefix(3)),
            emotions: Array(emotions.prefix(3)),
            emotionIntensity: emotions.isEmpty ? nil : emotionIntensity,
            blankSource: blankSource,
            tagNames: Array(tagNames.prefix(5)),
            version: (existing?.version ?? 0) + 1,
            serverVersion: existing?.serverVersion,
            syncState: isSignedIn ? .syncing : .localOnly,
            deleted: false,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try commitRecord(value)
        guard isSignedIn else { return }
        await syncSavedRecord(value)
    }

    private func syncSavedRecord(_ value: LocalRecord) async {
        do {
            let cloud = try await api.saveRecord(value)
            guard var current = records.first(where: { $0.recordDate == value.recordDate }),
                  current.version == value.version else { return }
            current.serverVersion = cloud.version
            current.syncState = .synced
            upsert(current)
        } catch {
            guard var current = records.first(where: { $0.recordDate == value.recordDate }),
                  current.version == value.version else { return }
            current.syncState = .syncFailed
            upsert(current)
        }
    }

    func deleteRecord(date: String) async {
        guard var value = records.first(where: { $0.recordDate == date }) else { return }
        value.deleted = true
        value.version += 1
        value.updatedAt = .now
        value.syncState = isSignedIn ? .syncing : .localOnly
        upsert(value)
        lastDeletedDate = date
        guard isSignedIn else { return }
        do {
            let cloud = try await api.deleteRecord(date: date)
            value.serverVersion = cloud.version
            value.syncState = .synced
        } catch {
            value.syncState = .syncFailed
        }
        upsert(value)
    }

    func restoreRecord(date: String) async {
        guard var value = records.first(where: { $0.recordDate == date }) else { return }
        value.deleted = false
        value.version += 1
        value.updatedAt = .now
        value.syncState = isSignedIn ? .syncing : .localOnly
        upsert(value)
        lastDeletedDate = nil
        guard isSignedIn else { return }
        do {
            let cloud = try await api.restoreRecord(date: date)
            value.serverVersion = cloud.version
            value.syncState = .synced
        } catch {
            value.syncState = .syncFailed
        }
        upsert(value)
    }

    func saveLifeStage(id: String?, name: String, startMonth: String, endMonth: String, colorCodes: [String], presetCode: String?) async throws {
        let editingID = id ?? UUID().uuidString
        guard startMonth <= endMonth else { throw APIError(message: "Choose a valid month range.", code: "MOSA_STAGE_INVALID_RANGE", statusCode: 409, retryAfterSeconds: nil) }
        let normalizedColors = Array(colorCodes.filter { !$0.isEmpty }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(3))
        guard !normalizedColors.isEmpty else { throw APIError(message: "Choose one to three stage colors.", code: "MOSA_STAGE_INVALID_COLOR", statusCode: 409, retryAfterSeconds: nil) }
        let existing = lifeStages.first { $0.id == editingID }
        let now = Date.now
        let stage = LocalLifeStage(id: editingID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), startMonth: startMonth, endMonth: endMonth, colorCode: normalizedColors[0], colorCodes: normalizedColors, presetCode: presetCode, version: (existing?.version ?? 0) + 1, serverVersion: existing?.serverVersion, syncState: isSignedIn ? .syncing : .localOnly, deleted: false, createdAt: existing?.createdAt ?? now, updatedAt: now)
        let override = LifeStageRangeResolver.override(
            stages: lifeStages,
            with: stage,
            now: now,
            syncState: isSignedIn ? .syncing : .localOnly
        )
        lifeStages = override.stages
        persistLifeStages()
        if var currentProfile = profile, let stageStartYear = Int(startMonth.prefix(4)), stageStartYear < currentProfile.startYear {
            currentProfile.startYear = stageStartYear
            profile = currentProfile
            repository.saveProfile(currentProfile)
        }
        guard isSignedIn else { return }
        do {
            _ = try await api.saveLifeStage(stage)
            let cloudStages = (try await api.getLifeStages()).map(\.localValue)
            let pending = lifeStages.filter {
                !override.touchedIDs.contains($0.id) && [.localOnly, .syncFailed].contains($0.syncState)
            }
            lifeStages = (cloudStages + pending).sorted { $0.startMonth < $1.startMonth }
            persistLifeStages()
        } catch {
            lifeStages = lifeStages.map {
                guard override.touchedIDs.contains($0.id) else { return $0 }
                var failed = $0
                failed.syncState = .syncFailed
                return failed
            }
            persistLifeStages()
            throw error
        }
    }

    func deleteLifeStage(id: String) async {
        guard var stage = lifeStages.first(where: { $0.id == id }) else { return }
        if !isSignedIn || stage.serverVersion == nil {
            lifeStages.removeAll { $0.id == id }
            persistLifeStages()
            return
        }
        stage.deleted = true
        stage.syncState = .syncing
        stage.updatedAt = .now
        upsert(stage)
        do {
            _ = try await api.deleteLifeStage(stage)
            lifeStages.removeAll { $0.id == id }
        } catch {
            stage.syncState = .syncFailed
            upsert(stage)
        }
        persistLifeStages()
    }

    func saveAnnualTitle(year: Int, title: String) async {
        let existing = annualWorks.first { $0.year == year }
        var work = LocalAnnualWork(
            year: year,
            cloudID: existing?.cloudID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            version: (existing?.version ?? 0) + 1,
            serverVersion: existing?.serverVersion,
            syncState: isSignedIn ? .syncing : .localOnly,
            updatedAt: .now,
            generationStatus: existing?.generationStatus,
            taskID: existing?.taskID,
            imageURL: existing?.imageURL,
            includeNotes: existing?.includeNotes,
            inputHash: existing?.inputHash,
            worldDnaVersion: existing?.worldDnaVersion,
            errorCode: existing?.errorCode,
            themeType: existing?.themeType,
            promptFingerprint: existing?.promptFingerprint,
            isYearToDate: existing?.isYearToDate,
            periodEnd: existing?.periodEnd,
            workflowID: existing?.workflowID,
            workflowStatus: existing?.workflowStatus,
            currentStage: existing?.currentStage,
            failedStage: existing?.failedStage,
            retryable: existing?.retryable,
            shareCardAvailable: existing?.shareCardAvailable,
            shareCardURL: existing?.shareCardURL
        )
        upsert(work)
        guard isSignedIn else { return }
        do {
            work = (try await api.saveAnnualTitle(work)).localValue
        } catch {
            work.syncState = .syncFailed
        }
        upsert(work)
    }

    func generateAnnualArtwork(
        year: Int,
        includeNotes: Bool,
        themeType: ArtworkTheme
    ) async throws {
        guard isSignedIn else { throw APIError(message: "Sign in before generating an annual artwork.", code: "MOSA_SIGN_IN_REQUIRED", statusCode: 401, retryAfterSeconds: nil) }
        let work = try await api.generateAnnualArtwork(
            year: year,
            includeNotes: includeNotes,
            themeType: themeType
        ).localValue
        upsert(work)
        await refreshArtworkGenerationPolicy()
    }

    func refreshGallery() async {
        guard isSignedIn else { return }
        do {
            for cloud in try await api.getGallery() { upsert(cloud.localValue) }
            prefetchShareCardImages()
        } catch { }
        await refreshArtworkGenerationPolicy()
    }

    func refreshArtworkGenerationPolicy() async {
        guard isSignedIn else {
            artworkGenerationPolicy = nil
            return
        }
        artworkGenerationPolicy = try? await api.getArtworkGenerationPolicy()
    }

    func annualArtworkImage(
        year: Int,
        onProgress: @escaping @MainActor @Sendable (ArtworkImageDownloadProgress) -> Void
    ) async throws -> Data {
        try await api.getAnnualArtworkImage(year: year, onProgress: onProgress)
    }

    func shareCardImage(
        year: Int,
        onProgress: @escaping @MainActor @Sendable (ArtworkImageDownloadProgress) -> Void
    ) async throws -> Data {
        try await api.getShareCardImage(year: year, onProgress: onProgress)
    }

    func cachedShareCardImage(year: Int) -> Data? {
        guard let account = shareCardCacheAccount else { return nil }
        return repository.loadShareCardImage(year: year, account: account)
    }

    func hasCurrentShareCardImage(_ work: LocalAnnualWork) -> Bool {
        guard let account = shareCardCacheAccount,
              work.shareCardAvailable == true else { return false }
        return repository.hasCurrentShareCardImage(
            year: work.year,
            account: account,
            sourceKey: shareCardCacheSourceKey(for: work)
        )
    }

    func refreshShareCardImageCache(
        for work: LocalAnnualWork,
        onProgress: @escaping @MainActor @Sendable (ArtworkImageDownloadProgress) -> Void = { _ in }
    ) async throws -> Data {
        guard let account = shareCardCacheAccount, work.shareCardAvailable == true else {
            throw APIError(message: "The share card image is unavailable.", code: "MOSA_SHARE_CARD_IMAGE_UNAVAILABLE", statusCode: 0, retryAfterSeconds: nil)
        }
        let sourceKey = shareCardCacheSourceKey(for: work)
        if repository.hasCurrentShareCardImage(year: work.year, account: account, sourceKey: sourceKey),
           let cached = repository.loadShareCardImage(year: work.year, account: account) {
            return cached
        }
        let data = try await shareCardImage(year: work.year, onProgress: onProgress)
        guard UIImage(data: data) != nil else {
            throw APIError(message: "The share card image could not be decoded.", code: "MOSA_SHARE_CARD_IMAGE_INVALID", statusCode: 0, retryAfterSeconds: nil)
        }
        try repository.saveShareCardImage(data, year: work.year, account: account, sourceKey: sourceKey)
        return data
    }

    func importPendingGuestData() async throws {
        guard let profile, !pendingGuestImport.isEmpty else { return }
        let result = try await api.importGuestData(profile: profile, records: pendingGuestImport)
        let conflicts = Set(result.conflictDates)
        records = records.map { record in
            guard pendingGuestImport.contains(where: { $0.id == record.id }) else { return record }
            var updated = record
            if !conflicts.contains(record.recordDate) { updated.syncState = .synced }
            return updated
        }
        persistRecords()
        pendingGuestImport = []
        notice = result.conflictCount > 0
            ? "\(result.importedCount) imported. \(result.conflictCount) cloud dates were kept unchanged."
            : "\(result.importedCount) local records were imported."
        await syncWithCloud()
    }

    func skipGuestImport() async {
        pendingGuestImport = []
        await syncWithCloud()
    }

    @discardableResult
    func syncWithCloud() async -> CloudSyncResult {
        guard !isSyncing else { return .alreadyRunning }
        guard isSignedIn else { return .signInRequired }
        guard var profile else { return .profileRequired }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await api.refreshSessionIfNeeded()
            session = sessionStore.load()
            let deviceTimezone = TimeZone.autoupdatingCurrent.identifier
            if profile.timezone != deviceTimezone {
                profile.timezone = deviceTimezone
                self.profile = profile
                repository.saveProfile(profile)
                profile = try await api.saveProfile(profile).localValue
                self.profile = profile
                repository.saveProfile(profile)
            }
            await api.uploadPendingDiagnostics()
        } catch {
            if error is CancellationError { return .cancelled }
            if sessionStore.load() == nil {
                session = nil
                notice = "Your session has expired. Sign in again to continue syncing."
                return .signInRequired
            }
            return .failed(error.localizedDescription)
        }

        let validRecords = records.filter(Self.isValidLocalRecord)
        if validRecords.count != records.count {
            records = validRecords
            persistRecords()
        }

        var failedUploadCount = 0
        for failed in records.filter({ $0.syncState == .syncFailed }) {
            if Task.isCancelled { return .cancelled }
            guard var syncing = records.first(where: {
                $0.recordDate == failed.recordDate && $0.version == failed.version
            }) else { continue }
            syncing.syncState = .syncing
            upsert(syncing)
            do {
                let cloud = failed.deleted
                    ? try await api.deleteRecord(date: failed.recordDate)
                    : try await api.saveRecord(failed)
                guard var updated = records.first(where: {
                    $0.recordDate == failed.recordDate && $0.version == failed.version
                }) else { continue }
                updated.serverVersion = cloud.version
                updated.syncState = .synced
                upsert(updated)
            } catch {
                if var current = records.first(where: {
                    $0.recordDate == failed.recordDate && $0.version == failed.version
                }) {
                    current.syncState = .syncFailed
                    upsert(current)
                }
                if error is CancellationError { return .cancelled }
                failedUploadCount += 1
                continue
            }
        }

        for pending in lifeStages.filter({ [.localOnly, .syncFailed].contains($0.syncState) }) {
            if Task.isCancelled { return .cancelled }
            do {
                if pending.deleted {
                    _ = try await api.deleteLifeStage(pending)
                    lifeStages.removeAll { $0.id == pending.id }
                } else {
                    let cloud = try await api.saveLifeStage(pending).localValue
                    if cloud.id != pending.id { lifeStages.removeAll { $0.id == pending.id } }
                    upsert(cloud)
                }
            } catch {
                if error is CancellationError { return .cancelled }
                failedUploadCount += 1
            }
        }

        for pending in annualWorks.filter({ [.localOnly, .syncFailed].contains($0.syncState) }) {
            if Task.isCancelled { return .cancelled }
            do {
                upsert(try await api.saveAnnualTitle(pending).localValue)
            } catch {
                if error is CancellationError { return .cancelled }
                failedUploadCount += 1
            }
        }

        do {
            let cloud = try await api.getRecords(
                from: "\(profile.startYear)-01-01",
                to: DateSupport.key(.now)
            )
            merge(cloudRecords: cloud)
            let cloudStages = (try await api.getLifeStages()).map(\.localValue)
            let cloudWorks = (try await api.getGallery()).map(\.localValue)
            artworkGenerationPolicy = try? await api.getArtworkGenerationPolicy()
            merge(cloudStages: cloudStages)
            merge(cloudWorks: cloudWorks)
            prefetchShareCardImages()
        } catch {
            if error is CancellationError { return .cancelled }
            if sessionStore.load() == nil {
                session = nil
                notice = "Your session has expired. Sign in again to continue syncing."
                return .signInRequired
            }
            return .failed(error.localizedDescription)
        }
        return failedUploadCount == 0 ? .completed : .completedWithFailures(failedUploadCount)
    }

    private func completeAuthentication(_ result: AuthResult, email: String) {
        let auth = AuthSession(
            token: result.token.token,
            refreshToken: result.token.refreshToken,
            email: result.profile.email.isEmpty ? email : result.profile.email,
            refreshedAt: .now
        )
        sessionStore.save(auth)
        session = auth
        let localOnly = records.filter { !$0.deleted && $0.syncState == .localOnly }
        if profile != nil, !localOnly.isEmpty {
            pendingGuestImport = localOnly
        } else {
            profile = result.profile.localValue
            repository.saveProfile(profile)
            Task { await syncWithCloud() }
        }
    }

    private func upsert(_ record: LocalRecord) {
        do {
            try commitRecord(record)
        } catch {
            notice = (error as? LocalizedError)?.errorDescription
                ?? "MOSA could not update your saved records on this iPhone."
        }
    }

    private func commitRecord(_ record: LocalRecord) throws {
        let previousRecords = records
        if let index = records.firstIndex(where: { $0.recordDate == record.recordDate }) {
            records[index] = record
        } else {
            records.append(record)
        }
        records.sort { $0.recordDate < $1.recordDate }
        do {
            try repository.saveRecords(records)
        } catch {
            records = previousRecords
            throw error
        }
    }

    private func upsert(_ stage: LocalLifeStage) {
        if let index = lifeStages.firstIndex(where: { $0.id == stage.id }) { lifeStages[index] = stage } else { lifeStages.append(stage) }
        lifeStages.sort { $0.startMonth < $1.startMonth }
        persistLifeStages()
    }

    private func upsert(_ work: LocalAnnualWork) {
        if let index = annualWorks.firstIndex(where: { $0.year == work.year }) { annualWorks[index] = work } else { annualWorks.append(work) }
        annualWorks.sort { $0.year > $1.year }
        persistAnnualWorks()
    }

    private func merge(cloudRecords: [CloudRecord]) {
        var merged = Dictionary(uniqueKeysWithValues: records.map { ($0.recordDate, $0) })
        for cloud in cloudRecords {
            let date = String(cloud.recordDate.prefix(10))
            let local = merged[date]
            if let local, [.localOnly, .syncing, .syncFailed].contains(local.syncState) { continue }
            if let local, (local.serverVersion ?? 0) > cloud.version { continue }
            merged[date] = cloud.localValue(existingID: local?.id)
        }
        records = merged.values.sorted { $0.recordDate < $1.recordDate }
        persistRecords()
    }

    private func persistRecords() {
        do {
            try repository.saveRecords(records)
        } catch {
            notice = (error as? LocalizedError)?.errorDescription
                ?? "MOSA could not update your saved records on this iPhone."
        }
    }

    private func persistLifeStages() { repository.saveLifeStages(lifeStages) }
    private func persistAnnualWorks() { repository.saveAnnualWorks(annualWorks) }

    private var shareCardCacheAccount: String? {
        let email = session?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? nil : email
    }

    private func shareCardCacheSourceKey(for work: LocalAnnualWork) -> String {
        work.workflowID ?? work.shareCardURL ?? work.inputHash ?? "version:\(work.version)"
    }

    private func prefetchShareCardImages() {
        for work in annualWorks where work.shareCardAvailable == true && !hasCurrentShareCardImage(work) {
            let key = "\(work.year):\(shareCardCacheSourceKey(for: work))"
            guard prefetchingShareCardKeys.insert(key).inserted else { continue }
            Task { [weak self] in
                guard let self else { return }
                defer { self.prefetchingShareCardKeys.remove(key) }
                _ = try? await self.refreshShareCardImageCache(for: work)
            }
        }
    }

    private func merge(cloudStages: [LocalLifeStage]) {
        let pending = lifeStages.filter { [.localOnly, .syncing, .syncFailed].contains($0.syncState) }
        let pendingIDs = Set(pending.map(\.id))
        lifeStages = (cloudStages.filter { !pendingIDs.contains($0.id) } + pending)
            .sorted { $0.startMonth < $1.startMonth }
        persistLifeStages()
    }

    private func merge(cloudWorks: [LocalAnnualWork]) {
        for work in cloudWorks {
            if annualWorks.contains(where: { $0.year == work.year && [.localOnly, .syncing, .syncFailed].contains($0.syncState) }) { continue }
            upsert(work)
        }
    }

    private static func isValidLocalRecord(_ record: LocalRecord) -> Bool {
        record.deleted
            || record.isIntentionalBlank
            || !record.colorCodes.isEmpty
            || !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
