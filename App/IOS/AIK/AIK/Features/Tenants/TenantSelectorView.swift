import SwiftUI

struct TenantSelectorView: View {
    let session: SessionStore
    let store: TenantStore

    @State private var searchText = ""
    @State private var showsInvite = false

    private var filteredTenants: [TenantSummary] {
        guard !searchText.isEmpty else { return store.tenants }
        return store.tenants.filter {
            $0.TenantName.localizedCaseInsensitiveContains(searchText)
                || ($0.AgentName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.tenants.isEmpty {
                    ProgressView("tenant.loading")
                } else if let error = store.errorMessage, store.tenants.isEmpty {
                    ContentUnavailableView {
                        Label("tenant.load_failed", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("common.retry") {
                            Task { await store.loadTenants(session: session) }
                        }
                    }
                } else if store.tenants.isEmpty {
                    ContentUnavailableView(
                        "tenant.empty",
                        systemImage: "building.2",
                        description: Text("tenant.empty_hint")
                    )
                } else {
                    List {
                        if !store.recentTenants.isEmpty && searchText.isEmpty {
                            Section("tenant.recent") {
                                ForEach(store.recentTenants) { tenant in
                                    tenantRow(tenant)
                                }
                            }
                        }

                        Section("tenant.all") {
                            ForEach(filteredTenants) { tenant in
                                tenantRow(tenant)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await store.loadTenants(session: session)
                    }
                }
            }
            .navigationTitle("tenant.title")
            .searchable(text: $searchText, prompt: "tenant.search")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("tenant.invite", systemImage: "link") {
                        showsInvite = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let name = session.user?.RealName ?? session.user?.UserName {
                            Text(name)
                        }
                        Link(destination: AppEnvironment.privacyURL) {
                            Label("privacy.policy", systemImage: "hand.raised")
                        }
                        .accessibilityLabel("privacy.policy")
                        Divider()
                        Button("account.logout", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            store.reset()
                            session.logout()
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .task {
                if store.tenants.isEmpty {
                    await store.loadTenants(session: session)
                }
            }
        }
        .sheet(isPresented: $showsInvite) {
            InviteAccessView(session: session, tenants: store)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .aikOpenInvite)
        ) { notification in
            showsInvite = true
        }
    }

    @ViewBuilder
    private func tenantRow(_ tenant: TenantSummary) -> some View {
        Button {
            Task { _ = await store.select(tenant, session: session) }
        } label: {
            HStack(spacing: 14) {
                AsyncImage(url: URL(string: tenant.AgentLogo ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "building.2.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(AIKTheme.gradient())
                }
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(tenant.AgentName ?? tenant.TenantName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("用户编号：\(tenant.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(store.isLoading)
    }
}
