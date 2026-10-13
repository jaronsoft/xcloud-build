import Foundation
import XCTest
@testable import AIK

@MainActor
final class PersistenceTests: XCTestCase {
    func testKeychainAndGuestSessionRecovery() async throws {
        let service = "com.wekarepartners.aik.tests.\(UUID().uuidString)"
        let keychain = KeychainStore(service: service)
        defer {
            try? keychain.remove("access-token")
            try? keychain.remove("refresh-token")
            try? keychain.remove("user")
            try? keychain.remove("invite-code")
        }

        let first = SessionStore(keychain: keychain)
        first.establishGuest(token: "guest-token", inviteCode: "INVITE01")

        let restored = SessionStore(keychain: keychain)
        await restored.restore()

        XCTAssertEqual(restored.mode, .guest)
        XCTAssertEqual(restored.accessToken, "guest-token")
        XCTAssertEqual(restored.inviteCode, "INVITE01")
        restored.logout()
        XCTAssertFalse(restored.isAuthenticated)
    }

    func testPinnedTenantsPersistAndSurviveRecentLimit() {
        let suite = "com.wekarepartners.aik.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TenantStore(defaults: defaults)
        func tenant(_ id: String) -> TenantSummary {
            TenantSummary(
                TenantId: FlexibleStringID(id), TenantName: "示例企业",
                AgentName: nil, AgentLogo: nil, WelcomeMessage: nil,
                EnableVoice: false, IsAnonymousAllowed: true
            )
        }
        let pinned = tenant("9223372036854775806")
        store.selectGuest(pinned)
        store.togglePinned(pinned)
        for index in 1...7 { store.selectGuest(tenant(String(index))) }
        XCTAssertEqual(store.orderedRecentTenants.first?.id, pinned.id)
        XCTAssertEqual(store.recentTenants.count, 7)
        let restored = TenantStore(defaults: defaults)
        XCTAssertTrue(restored.isPinned(pinned))
        XCTAssertEqual(restored.orderedRecentTenants.first?.id, pinned.id)
        let latest = tenant("7")
        restored.togglePinned(latest)
        restored.togglePinned(latest)
        XCTAssertFalse(TenantStore(defaults: defaults).isPinned(latest))
        XCTAssertEqual(restored.orderedRecentTenants.first?.id, pinned.id)
        restored.removeRecentTenant(pinned)
        let deleted = TenantStore(defaults: defaults)
        XCTAssertFalse(deleted.isPinned(pinned))
        XCTAssertFalse(deleted.recentTenants.contains { $0.id == pinned.id })
        deleted.togglePinned(latest)
        deleted.reset()
        XCTAssertTrue(TenantStore(defaults: defaults).pinnedTenantIDs.isEmpty)
    }

    func testTenantRecentSelectionAndSwitch() {
        let suite = "com.wekarepartners.aik.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let tenant = TenantSummary(
            TenantId: FlexibleStringID("9223372036854775806"),
            TenantName: "示例企业",
            AgentName: "知识助手",
            AgentLogo: nil,
            WelcomeMessage: nil,
            EnableVoice: false,
            IsAnonymousAllowed: true
        )
        let store = TenantStore(defaults: defaults)
        store.selectGuest(tenant)

        XCTAssertEqual(store.selectedTenant?.id, tenant.id)
        XCTAssertEqual(store.recentTenants.first?.id, tenant.id)

        store.removeRecentTenant(tenant)
        XCTAssertTrue(store.recentTenants.isEmpty)
        XCTAssertEqual(store.selectedTenant?.id, tenant.id)
        XCTAssertTrue(TenantStore(defaults: defaults).recentTenants.isEmpty)

        store.selectGuest(tenant)

        let restored = TenantStore(defaults: defaults)
        XCTAssertEqual(restored.selectedTenant?.id, tenant.id)
        restored.switchTenant()
        XCTAssertNil(restored.selectedTenant)
        XCTAssertEqual(restored.recentTenants.first?.id, tenant.id)

        restored.reset()
        XCTAssertTrue(restored.recentTenants.isEmpty)
    }
}
