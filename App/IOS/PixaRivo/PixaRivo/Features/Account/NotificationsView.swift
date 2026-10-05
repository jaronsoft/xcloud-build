import SwiftUI
import UIKit
import UserNotifications

struct PixaNotificationsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PixaNotificationStore.self) private var notifications
    @Environment(PixaNavigationStore.self) private var navigation
    @State private var showsPermissionPrompt = false
    @State private var selectedNotification: PixaUserNotification?
    @State private var pendingDeletion: PixaUserNotification?
    @State private var showsDeleteError = false

    var body: some View {
        List {
            if notifications.items.isEmpty && !notifications.isLoading {
                ContentUnavailableView(
                    "notification.center.empty.title",
                    systemImage: "bell.slash",
                    description: Text("notification.center.empty.message")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(notifications.items) { item in
                    Button {
                        Task { await notifications.markRead(item, session: session) }
                        if item.referenceType == "daily_visit_gift" {
                            navigation.openNotificationRoute(
                                "transactions",
                                referenceID: item.referenceID,
                                notificationID: item.id
                            )
                        } else {
                            selectedNotification = item
                        }
                    } label: {
                        notificationRow(item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeletion = item
                        } label: {
                            Label("notification.delete.action", systemImage: "trash")
                        }
                    }
                    .onAppear {
                        guard item.id == notifications.items.last?.id else { return }
                        Task { await notifications.loadMore(session: session) }
                    }
                }
                if notifications.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section("notification.settings.title") {
                Toggle(
                    "notification.settings.new_templates",
                    isOn: Binding(
                        get: { notifications.receivesNewTemplateNotifications },
                        set: { enabled in
                            Task {
                                await notifications.setReceivesNewTemplateNotifications(
                                    enabled,
                                    session: session
                                )
                            }
                        }
                    )
                )
                .disabled(notifications.isUpdatingPreferences)

                Button {
                    Task {
                        let status = await PixaPushNotificationService.shared.authorizationStatus()
                        if status == .notDetermined {
                            showsPermissionPrompt = true
                        } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            await UIApplication.shared.open(url)
                        }
                    }
                } label: {
                    Label("notification.settings.manage", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("notification.center.title")
        .toolbar {
            if notifications.unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("notification.center.read_all") {
                        Task { await notifications.markAllRead(session: session) }
                    }
                }
            }
        }
        .refreshable { await notifications.refresh(session: session) }
        .task { await notifications.refresh(session: session) }
        .sheet(isPresented: $showsPermissionPrompt) {
            PixaNotificationPermissionPrompt {
                Task {
                    let authorized = await PixaPushNotificationService.shared.requestAuthorizationAndRegister()
                    if authorized {
                        await PixaPushNotificationService.shared.synchronize(session: session)
                    }
                }
            }
        }
        .sheet(item: $selectedNotification) { item in
            NavigationStack {
                PixaNotificationDetailView(item: item) {
                    selectedNotification = nil
                    let route = item.referenceType == "daily_visit_gift"
                        || item.type.lowercased().hasPrefix("recharge")
                        ? "transactions"
                        : item.route
                    navigation.openNotificationRoute(
                        route,
                        referenceID: item.referenceID,
                        notificationID: item.id
                    )
                }
            }
        }
        .alert(
            "notification.delete.title",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { item in
            Button("common.cancel", role: .cancel) {}
            Button("notification.delete.confirm", role: .destructive) {
                Task {
                    let deleted = await notifications.delete(item, session: session)
                    if !deleted { showsDeleteError = true }
                }
            }
        } message: { _ in
            Text("notification.delete.message")
        }
        .alert("notification.delete.failed", isPresented: $showsDeleteError) {
            Button("common.ok", role: .cancel) {}
        }
        .alert(
            "notification.settings.update_failed",
            isPresented: Binding(
                get: { notifications.preferenceUpdateFailed },
                set: { if !$0 { notifications.clearPreferenceUpdateError() } }
            )
        ) {
            Button("common.ok", role: .cancel) {}
        }
    }

    private func notificationRow(_ item: PixaUserNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: item.type))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PixaTheme.accent)
                .frame(width: 36, height: 36)
                .background(PixaTheme.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(PixaTheme.ink)
                    Spacer(minLength: 8)
                    if !item.isRead {
                        Circle()
                            .fill(PixaTheme.accent)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel(Text("notification.center.unread"))
                    }
                }
                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(relativeDate(item.createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func icon(for type: String) -> String {
        if type.hasPrefix("points") || type.hasPrefix("recharge") || type.hasPrefix("refund") {
            return "sparkles"
        }
        if type.hasPrefix("membership") || type.hasPrefix("subscription") {
            return "crown.fill"
        }
        if type.hasPrefix("job") {
            return type.hasSuffix("failed") ? "exclamationmark.triangle.fill" : "photo.fill"
        }
        if type.hasPrefix("template") {
            return "rectangle.stack.fill"
        }
        return "bell.fill"
    }

    private func relativeDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return value }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }
}

private struct PixaNotificationDetailView: View {
    let item: PixaUserNotification
    let openRelatedContent: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(item.title)
                    .font(.title2.bold())
                    .foregroundStyle(PixaTheme.ink)
                Text(item.body)
                    .font(.body)
                    .foregroundStyle(PixaTheme.ink)
                    .textSelection(.enabled)
                Label(formattedDate(item.createdAt), systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let route = item.route, !route.isEmpty, route.lowercased() != "notifications" {
                    Button("notification.detail.open_related", action: openRelatedContent)
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("notification.detail.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("common.done") { dismiss() }
            }
        }
    }

    private func formattedDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) else {
            return value
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
