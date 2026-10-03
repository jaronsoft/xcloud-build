import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: MosaStore
    @State private var displayName = ""
    @State private var startYear = Calendar.current.component(.year, from: .now)
    @State private var showsAccount = false
    @State private var showsDeleteAccount = false
    @State private var invitationURL: URL?
    @State private var invitationError: String?
    @State private var creatingInvitation = false
    @State private var syncResult: CloudSyncResult?
    @AppStorage(DiagnosticConsent.key) private var shareDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "Profile")
                Text("Your MOSA settings")
                    .font(.system(size: 40, weight: .medium, design: .serif))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Storage").font(.caption).foregroundStyle(MosaPalette.muted)
                    Text(store.session?.email ?? "Private on this device").font(.title3.bold())
                    Text("\(store.visibleRecords.count) daily records · \(emotionColorCount) emotion colors · \(visibleStageCount) life stages")
                        .font(.subheadline).foregroundStyle(MosaPalette.muted)
                    Text("\(pendingCount) waiting for cloud save")
                        .font(.caption)
                        .foregroundStyle(MosaPalette.muted)
                    if store.isSignedIn {
                        Button {
                            Task {
                                syncResult = nil
                                syncResult = await store.syncWithCloud()
                            }
                        } label: {
                            Label(
                                store.isSyncing ? "Syncing…" : "Sync now",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .buttonStyle(MosaPrimaryButtonStyle())
                        .disabled(store.isSyncing)

                        if let syncResult {
                            Label(
                                syncResult.message,
                                systemImage: syncResult.succeeded
                                    ? "checkmark.circle.fill"
                                    : "exclamationmark.circle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(syncResult.succeeded ? Color.green : Color.orange)
                            .accessibilityIdentifier("profile-sync-result")
                        }

                        Button("Sign out") { Task { await store.logout() } }
                            .buttonStyle(MosaSecondaryButtonStyle())
                    } else {
                        Button("Sign in to sync") { showsAccount = true }
                            .buttonStyle(MosaPrimaryButtonStyle())
                    }
                }
                .mosaCard()

                if store.isSignedIn {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Account")
                        Text("Delete your MOSA account").font(.title3.bold())
                        Text("Permanently remove your account and all associated cloud and device data.")
                            .font(.subheadline)
                            .foregroundStyle(MosaPalette.muted)
                        Button(role: .destructive) {
                            showsDeleteAccount = true
                        } label: {
                            Label("Delete account", systemImage: "trash")
                        }
                        .buttonStyle(MosaSecondaryButtonStyle())
                        .tint(.red)
                    }
                    .mosaCard()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Diagnostics")
                    Toggle("Share crash and error reports", isOn: $shareDiagnostics)
                        .onChange(of: shareDiagnostics) { _, value in
                            DiagnosticsReporter.shared.setEnabled(value)
                        }
                    Text("Off by default. Reports are collected and uploaded only after you turn this on. MOSA removes tokens, email addresses and invitation links; your notes, emotions and canvas are never included. Turning it off deletes pending reports.")
                        .font(.caption)
                        .foregroundStyle(MosaPalette.muted)
                }
                .mosaCard()

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Invite someone")
                    Text("Share MOSA, not your records.").font(.title3.bold())
                    Text("The link lasts 30 days and can be used once. You will not be told who accepts it or what they record.")
                        .font(.subheadline).foregroundStyle(MosaPalette.muted)
                    if let invitationURL {
                        ShareLink(item: invitationURL, subject: Text("MOSA"), message: Text("Create a private canvas for your days.")) {
                            Label("Share private invitation", systemImage: "square.and.arrow.up")
                        }.buttonStyle(MosaPrimaryButtonStyle())
                    } else if store.isSignedIn {
                        Button(creatingInvitation ? "Preparing…" : "Create private invitation") {
                            Task {
                                creatingInvitation = true
                                defer { creatingInvitation = false }
                                do { invitationURL = try await store.createInvitationURL() }
                                catch { invitationError = error.localizedDescription }
                            }
                        }.buttonStyle(MosaSecondaryButtonStyle()).disabled(creatingInvitation)
                    } else {
                        Button("Sign in to invite") { showsAccount = true }.buttonStyle(MosaSecondaryButtonStyle())
                    }
                    if let invitationError { Text(invitationError).font(.caption).foregroundStyle(.red) }
                }
                .mosaCard()

                VStack(alignment: .leading, spacing: 16) {
                    TextField("Name", text: $displayName).textFieldStyle(.roundedBorder)
                    Picker("Start year", selection: $startYear) {
                        ForEach(Array((Calendar.current.component(.year, from: .now) - 110)...Calendar.current.component(.year, from: .now)).reversed(), id: \.self) { Text(String($0)).tag($0) }
                    }
                    .pickerStyle(.menu)
                    LabeledContent("Language", value: "English")
                    Button("Save settings") {
                        Task { await store.saveProfile(displayName: displayName, startYear: startYear) }
                    }
                    .buttonStyle(MosaPrimaryButtonStyle())
                }
                .mosaCard()

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "About")
                    NavigationLink(destination: AboutView()) {
                        ProfileNavigationRow(
                            title: AppConfiguration.releaseLabel,
                            systemImage: "info.circle"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .mosaCard()

                if AppConfiguration.showsNetworkDiagnostics {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Network diagnostics")
                        Text("Inspect sanitized API activity when cloud sync has trouble.")
                            .font(.subheadline)
                            .foregroundStyle(MosaPalette.muted)
                        Divider()
                        NavigationLink(destination: DeveloperNetworkLogView(logs: store.developerLogs)) {
                            ProfileNavigationRow(
                                title: "Network logs",
                                subtitle: "\(store.developerLogs.entries.count)",
                                systemImage: "network"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .mosaCard()
                }

                Link("MOSA website", destination: AppConfiguration.officialSiteURL)
                CompanyFooter().frame(maxWidth: .infinity).padding(.top, 16)
            }
            .padding(20)
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .mosaPage()
        .onAppear {
            displayName = store.profile?.displayName ?? ""
            startYear = store.profile?.startYear ?? Calendar.current.component(.year, from: .now)
        }
        .sheet(isPresented: $showsAccount) {
            NavigationStack {
                AuthView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showsAccount = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showsDeleteAccount) {
            NavigationStack {
                DeleteAccountView()
            }
        }
    }

    private var pendingCount: Int {
        store.records.filter { [.localOnly, .syncing, .syncFailed].contains($0.syncState) }.count
            + store.lifeStages.filter { [.localOnly, .syncing, .syncFailed].contains($0.syncState) }.count
            + store.annualWorks.filter { [.localOnly, .syncing, .syncFailed].contains($0.syncState) }.count
    }

    private var emotionColorCount: Int {
        store.visibleRecords.reduce(0) { count, record in
            count + (record.emotions?.isEmpty == false ? record.emotions!.count : record.colorCodes.count)
        }
    }

    private var visibleStageCount: Int {
        store.lifeStages.filter { !$0.deleted }.count
    }
}

private struct DeleteAccountView: View {
    @EnvironmentObject private var store: MosaStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var deletionConfirmation = ""
    @State private var deleting = false
    @State private var showsFinalConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Permanent deletion") {
                Label("Account deletion is permanent", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text("Your MOSA account, email, cloud records, life stages, invitations, annual artwork, diagnostic reports, and MOSA data stored on this device will be permanently erased.")
                Text("After deletion, neither you nor MOSA can restore this account or its data.")
                    .font(.headline)
                    .foregroundStyle(.red)
            }

            Section("Confirm your identity") {
                SecureField("Current password", text: $password)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                TextField("Type DELETE to confirm", text: $deletionConfirmation)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Text("Enter DELETE exactly to confirm that you understand this action cannot be undone.")
                    .font(.caption)
                    .foregroundStyle(MosaPalette.muted)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(role: .destructive) {
                    showsFinalConfirmation = true
                } label: {
                    HStack {
                        if deleting { ProgressView() }
                        Text(deleting ? "Deleting account…" : "Delete my account permanently")
                    }
                }
                .disabled(password.isEmpty || deletionConfirmation != "DELETE" || deleting)
            }
        }
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(deleting)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(deleting)
            }
        }
        .confirmationDialog(
            "Permanently delete your MOSA account?",
            isPresented: $showsFinalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete account permanently", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently erases your account and associated data. Deleted data cannot be recovered.")
        }
    }

    private func deleteAccount() async {
        deleting = true
        errorMessage = nil
        defer { deleting = false }
        do {
            try await store.deleteAccount(password: password)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProfileNavigationRow: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MosaPalette.navy)
                .frame(width: 38, height: 38)
                .background(MosaPalette.navy.opacity(0.09), in: Circle())

            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 12)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(MosaPalette.muted)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(MosaPalette.muted.opacity(0.7))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

private struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AnimatedMosaicMark()
                    .scaleEffect(0.7)
                    .frame(height: 150)
                    .accessibilityLabel("MOSA animated mosaic logo")

                Text(AppConfiguration.productName)
                    .font(.system(size: 36, weight: .medium, design: .serif))
                Text("A life in pieces, still whole.")
                    .font(.subheadline)
                    .foregroundStyle(MosaPalette.muted)

                VStack(spacing: 0) {
                    AboutRow(label: "Company", value: AppConfiguration.companyName)
                    Divider()
                    AboutRow(label: "Software", value: AppConfiguration.productName)
                    Divider()
                    AboutRow(label: "Version", value: AppConfiguration.releaseLabel)
                }
                .mosaCard()
                .padding(.top, 12)
            }
            .padding(20)
        }
        .navigationTitle("About MOSA")
        .navigationBarTitleDisplayMode(.inline)
        .mosaPage()
    }
}

private struct AboutRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label, value: value)
            .padding(.vertical, 14)
    }
}
