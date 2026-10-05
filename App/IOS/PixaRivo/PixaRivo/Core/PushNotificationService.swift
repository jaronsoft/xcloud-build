import Foundation
import Observation
import UIKit
import UserNotifications

extension Notification.Name {
    static let pixaRemoteNotificationReceived = Notification.Name("PixaRemoteNotificationReceived")
    static let pixaRemoteNotificationOpened = Notification.Name("PixaRemoteNotificationOpened")
    static let pixaPushDeviceTokenChanged = Notification.Name("PixaPushDeviceTokenChanged")
}

struct PixaNotificationDestination: Sendable, Equatable {
    let route: String?
    let referenceID: String?
    let referenceType: String?
    let notificationID: String?
    let isDigest: Bool
}

@MainActor
final class PixaNotificationLaunchTargetStore {
    static let shared = PixaNotificationLaunchTargetStore()
    private var pending: PixaNotificationDestination?

    func save(_ destination: PixaNotificationDestination) {
        pending = destination
    }

    func take() -> PixaNotificationDestination? {
        defer { pending = nil }
        return pending
    }
}

struct PixaPushConfig: Decodable {
    let enabled: Bool
    let bundleID: String

    private enum CodingKeys: String, CodingKey {
        case enabled = "Enabled"
        case bundleID = "BundleId"
    }
}

struct PixaPushDeviceRequest: Encodable {
    let deviceToken: String
    let bundleID: String
    let environment: String
    let appVersion: String
    let locale: String
    let timeZoneId: String

    private enum CodingKeys: String, CodingKey {
        case deviceToken = "DeviceToken"
        case bundleID = "BundleId"
        case environment = "Environment"
        case appVersion = "AppVersion"
        case locale = "Locale"
        case timeZoneId = "TimeZoneId"
    }
}

struct PixaPushDeviceResponse: Decodable {
    let id: String

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
    }
}

struct PixaUserNotification: Decodable, Identifiable, Hashable {
    let id: String
    let type: String
    let title: String
    let body: String
    let route: String?
    let referenceID: String?
    let referenceType: String?
    let isRead: Bool
    let readAt: String?
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case type = "Type"
        case title = "Title"
        case body = "Body"
        case route = "Route"
        case referenceID = "ReferenceId"
        case referenceType = "ReferenceType"
        case isRead = "IsRead"
        case readAt = "ReadAt"
        case createdAt = "CreatedAt"
    }
}

struct PixaNotificationPreferences: Codable {
    let receivesNewTemplateNotifications: Bool

    private enum CodingKeys: String, CodingKey {
        case receivesNewTemplateNotifications = "ReceiveNewTemplateNotifications"
    }
}

@MainActor
@Observable
final class PixaNotificationStore {
    private let api = APIClient()
    private(set) var items: [PixaUserNotification] = []
    private(set) var unreadCount = 0
    private(set) var isLoading = false
    private(set) var hasMore = true
    private(set) var receivesNewTemplateNotifications = true
    private(set) var isUpdatingPreferences = false
    private(set) var preferenceUpdateFailed = false
    private var page = 1

    func refresh(session: SessionStore) async {
        page = 1
        hasMore = true
        async let notificationsTask: Void = load(session: session, reset: true)
        async let preferencesTask: Void = refreshPreferences(session: session)
        _ = await (notificationsTask, preferencesTask)
    }

    func refreshPreferences(session: SessionStore) async {
        guard let token = await session.validAccessToken() else { return }
        do {
            let preferences: PixaNotificationPreferences = try await api.get(
                "/api/ais/notifications/preferences",
                token: token,
                forceRefresh: true
            )
            receivesNewTemplateNotifications = preferences.receivesNewTemplateNotifications
        } catch {
            // 偏好读取失败时保留当前值，避免短暂网络异常造成开关跳动。
        }
    }

    func setReceivesNewTemplateNotifications(
        _ enabled: Bool,
        session: SessionStore
    ) async {
        guard !isUpdatingPreferences,
              let token = await session.validAccessToken() else { return }
        let previousValue = receivesNewTemplateNotifications
        receivesNewTemplateNotifications = enabled
        isUpdatingPreferences = true
        preferenceUpdateFailed = false
        defer { isUpdatingPreferences = false }
        do {
            let preferences: PixaNotificationPreferences = try await api.post(
                "/api/ais/notifications/preferences",
                body: PixaNotificationPreferences(
                    receivesNewTemplateNotifications: enabled
                ),
                token: token
            )
            receivesNewTemplateNotifications = preferences.receivesNewTemplateNotifications
        } catch {
            receivesNewTemplateNotifications = previousValue
            preferenceUpdateFailed = true
        }
    }

    func clearPreferenceUpdateError() {
        preferenceUpdateFailed = false
    }

    func loadMore(session: SessionStore) async {
        guard hasMore, !isLoading else { return }
        await load(session: session, reset: false)
    }

    func refreshUnreadCount(session: SessionStore) async {
        guard let token = await session.validAccessToken() else {
            reset()
            return
        }
        do {
            let count: Int = try await api.get(
                "/api/ais/notifications/unread-count",
                token: token,
                forceRefresh: true
            )
            unreadCount = max(0, count)
            await updateApplicationBadge()
        } catch {
            // 未读数短暂刷新失败时保留现有角标。
        }
    }

    func markRead(_ item: PixaUserNotification, session: SessionStore) async {
        guard !item.isRead, let token = await session.validAccessToken() else { return }
        do {
            let _: Bool = try await api.post(
                "/api/ais/notifications/\(item.id)/read",
                body: EmptyRequest(),
                token: token
            )
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = PixaUserNotification(
                    id: item.id,
                    type: item.type,
                    title: item.title,
                    body: item.body,
                    route: item.route,
                    referenceID: item.referenceID,
                    referenceType: item.referenceType,
                    isRead: true,
                    readAt: ISO8601DateFormatter().string(from: .now),
                    createdAt: item.createdAt
                )
            }
            unreadCount = max(0, unreadCount - 1)
            await updateApplicationBadge()
        } catch {
            // 保持未读状态，用户可稍后重试。
        }
    }

    func markRead(id: String, session: SessionStore) async {
        guard let token = await session.validAccessToken() else { return }
        if let item = items.first(where: { $0.id == id }) {
            await markRead(item, session: session)
            return
        }
        do {
            let _: Bool = try await api.post(
                "/api/ais/notifications/\(id)/read",
                body: EmptyRequest(),
                token: token
            )
            await refreshUnreadCount(session: session)
        } catch {
            // 系统通知稍后仍可通过站内通知中心再次标记已读。
        }
    }

    func markAllRead(session: SessionStore) async {
        guard let token = await session.validAccessToken() else { return }
        do {
            let _: Int = try await api.post(
                "/api/ais/notifications/read-all",
                body: EmptyRequest(),
                token: token
            )
            items = items.map {
                PixaUserNotification(
                    id: $0.id,
                    type: $0.type,
                    title: $0.title,
                    body: $0.body,
                    route: $0.route,
                    referenceID: $0.referenceID,
                    referenceType: $0.referenceType,
                    isRead: true,
                    readAt: $0.readAt ?? ISO8601DateFormatter().string(from: .now),
                    createdAt: $0.createdAt
                )
            }
            unreadCount = 0
            await updateApplicationBadge()
        } catch {
            // 保持原状态，避免本地已读与服务器不一致。
        }
    }

    func delete(_ item: PixaUserNotification, session: SessionStore) async -> Bool {
        guard let token = await session.validAccessToken() else { return false }
        do {
            let deleted: Bool = try await api.delete(
                "/api/ais/notifications/\(item.id)",
                token: token
            )
            guard deleted else { return false }
            items.removeAll { $0.id == item.id }
            if !item.isRead {
                unreadCount = max(0, unreadCount - 1)
                await updateApplicationBadge()
            }
            return true
        } catch {
            // 服务端删除失败时保留消息，避免造成已删除的错觉。
            return false
        }
    }

    func reset() {
        items = []
        unreadCount = 0
        page = 1
        hasMore = true
        receivesNewTemplateNotifications = true
        isUpdatingPreferences = false
        preferenceUpdateFailed = false
        Task { await updateApplicationBadge() }
    }

    private func load(session: SessionStore, reset: Bool) async {
        guard let token = await session.validAccessToken(), !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response: PageResponse<PixaUserNotification> = try await api.get(
                "/api/ais/notifications",
                query: [
                    .init(name: "page", value: String(page)),
                    .init(name: "size", value: "20")
                ],
                token: token,
                forceRefresh: true
            )
            if reset {
                items = response.items
            } else {
                let existing = Set(items.map(\.id))
                items.append(contentsOf: response.items.filter { !existing.contains($0.id) })
            }
            hasMore = items.count < response.total
            if hasMore { page += 1 }
            unreadCount = items.filter { !$0.isRead }.count
            await refreshUnreadCount(session: session)
        } catch {
            // 消息中心保留已加载内容，允许用户下拉重试。
        }
    }

    private func updateApplicationBadge() async {
        try? await UNUserNotificationCenter.current().setBadgeCount(unreadCount)
    }
}

@MainActor
final class PixaPushNotificationService {
    static let shared = PixaPushNotificationService()

    private let api = APIClient()
    private(set) var currentDeviceToken: String?
    private(set) var isServerEnabled = false
    private(set) var bundleID = Bundle.main.bundleIdentifier ?? "com.wekarepartners.pixarivo"

    private init() {}

    func refreshConfiguration() async -> Bool {
        do {
            let config: PixaPushConfig = try await api.get("/api/ais/push-devices/config")
            isServerEnabled = config.enabled
            bundleID = config.bundleID
            return config.enabled
        } catch {
            isServerEnabled = false
            return false
        }
    }

    func requestAuthorizationAndRegister() async -> Bool {
        guard await refreshConfiguration() else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let authorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorized = true
        case .notDetermined:
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
        case .denied:
            authorized = false
        @unknown default:
            authorized = false
        }
        // 每次授权流程都向 APNs 获取当前 Token；系统展示权限与 Token 注册彼此独立。
        UIApplication.shared.registerForRemoteNotifications()
        return authorized
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func registerForRemoteNotifications() async {
        guard await refreshConfiguration() else { return }
        // Apple 建议每次启动重新注册，不能依赖本地长期缓存的 Token。
        UIApplication.shared.registerForRemoteNotifications()
    }

    func receiveDeviceToken(_ data: Data) {
        currentDeviceToken = data.map { String(format: "%02x", $0) }.joined()
    }

    func synchronize(session: SessionStore) async {
        guard isServerEnabled,
              let deviceToken = currentDeviceToken,
              let token = await session.validAccessToken() else { return }
        let request = PixaPushDeviceRequest(
            deviceToken: deviceToken,
            bundleID: bundleID,
            environment: environment,
            appVersion: AppConfiguration.releaseLabel,
            locale: AppLanguage.locale.identifier,
            timeZoneId: TimeZone.current.identifier
        )
        let _: PixaPushDeviceResponse? = try? await api.post(
            "/api/ais/push-devices",
            body: request,
            token: token
        )
    }

    func unregister(accessToken: String) async {
        guard let deviceToken = currentDeviceToken else { return }
        let _: Bool? = try? await api.delete(
            "/api/ais/push-devices/current",
            query: [
                .init(name: "deviceToken", value: deviceToken),
                .init(name: "bundleId", value: bundleID),
                .init(name: "environment", value: environment)
            ],
            token: accessToken
        )
    }

    private var environment: String {
#if DEBUG
        "sandbox"
#else
        "production"
#endif
    }
}

private struct EmptyRequest: Encodable {}
