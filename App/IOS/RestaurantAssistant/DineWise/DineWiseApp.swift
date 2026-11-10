import UIKit
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let dineWisePushTokenReceived = Notification.Name("DineWisePushTokenReceived")
    static let dineWisePushNotificationOpened = Notification.Name("DineWisePushNotificationOpened")
}

struct DineWisePushRoute {
    let notificationID: String
    let storeID: String
    let taskID: String
    let role: String
}

@MainActor
final class DineWisePushRegistration {
    static let shared = DineWisePushRegistration()
    private(set) var deviceToken = ""
    private(set) var pendingRoute: DineWisePushRoute?

    func requestAuthorization() async throws -> Bool {
        let granted = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    func registerIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func updateDeviceToken(_ token: String) {
        guard !token.isEmpty, token != deviceToken else { return }
        deviceToken = token
        NotificationCenter.default.post(name: .dineWisePushTokenReceived,
            object: nil, userInfo: ["token": token])
    }

    func clearDeviceToken() {
        deviceToken = ""
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    func receivePushRoute(_ userInfo: [String: String]) {
        guard let notificationID = userInfo["notificationId"], !notificationID.isEmpty,
              let taskID = userInfo["taskId"], !taskID.isEmpty else { return }
        guard let storeID = userInfo["storeId"],
              let role = userInfo["role"],
              !storeID.isEmpty, ["owner", "manager", "purchaser"].contains(role) else { return }
        pendingRoute = DineWisePushRoute(notificationID: notificationID,
            storeID: storeID, taskID: taskID, role: role)
        NotificationCenter.default.post(name: .dineWisePushNotificationOpened, object: nil)
    }

    func clearPendingRoute() { pendingRoute = nil }
}

@MainActor
final class DineWiseAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = DineWisePushNotificationDelegate.shared
        return true
    }

    func application(_ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        DineWisePushRegistration.shared.updateDeviceToken(token)
    }

    func application(_ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .dineWisePushRegistrationFailed,
            object: nil)
    }

}

final class DineWisePushNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = DineWisePushNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        var payload: [String: String] = [:]
        for (key, value) in response.notification.request.content.userInfo {
            if let key = key as? String, let value = value as? String { payload[key] = value }
        }
        await MainActor.run { DineWisePushRegistration.shared.receivePushRoute(payload) }
    }
}

extension Notification.Name {
    static let dineWisePushRegistrationFailed = Notification.Name("DineWisePushRegistrationFailed")
}

@main
struct DineWiseApp: App {
    @UIApplicationDelegateAdaptor(DineWiseAppDelegate.self) private var appDelegate
    @State private var showContent = false

    var body: some Scene {
        WindowGroup {
            if showContent {
                ContentView()
            } else {
                DineWiseLaunchAnimationView {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { showContent = true }
                }
            }
        }
    }
}
