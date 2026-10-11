import Foundation

public enum MeroliCacheStartMode: String, Equatable {
    case firstInstall = "FIRST_INSTALL"
    case returningCache = "RETURNING_CACHE"
    case cacheMigration = "CACHE_MIGRATION"
}

public enum MeroliCacheSchemaAction: Equatable {
    case use
    case migrate
    case invalidateEntry
    case unsupportedFuture
}

public enum MeroliCacheLifecyclePolicy {
    public static let currentSchemaVersion = 3

    public static func schemaAction(storedVersion: Int) -> MeroliCacheSchemaAction {
        if storedVersion == currentSchemaVersion { return .use }
        if storedVersion == 2 { return .migrate }
        if storedVersion < currentSchemaVersion { return .invalidateEntry }
        return .unsupportedFuture
    }

    public static func startMode(hasUsableCache: Bool, migrationOccurred: Bool) -> MeroliCacheStartMode {
        guard hasUsableCache else { return .firstInstall }
        return migrationOccurred ? .cacheMigration : .returningCache
    }

    public static func canRenderApp(hasUsableScopedCache: Bool, authenticationComplete: Bool) -> Bool {
        hasUsableScopedCache || authenticationComplete
    }

    public static func shouldBlockForInitialization(hasUsableScopedCache: Bool) -> Bool {
        !hasUsableScopedCache
    }

    public static func resolvedValue<Value>(
        cached: Value?,
        network: Value?,
        networkSucceeded: Bool
    ) -> Value? {
        networkSucceeded ? network : cached
    }

    public static func cacheBelongsToCurrentUser(cacheUserId: String, authenticatedUserId: String) -> Bool {
        !cacheUserId.isEmpty && cacheUserId == authenticatedUserId
    }

    public static func retainCacheOnLogout() -> Bool { true }

    public static func writeAtomically(
        data: Data,
        to url: URL,
        beforeReplacement: () throws -> Void = {}
    ) throws {
        try beforeReplacement()
        try data.write(to: url, options: .atomic)
    }
}
