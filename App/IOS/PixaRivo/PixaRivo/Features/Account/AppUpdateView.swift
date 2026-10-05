import SwiftUI

struct PixaAppUpdateView: View {
    @Environment(PixaAppUpdateStore.self) private var appUpdate
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                LabeledContent(
                    "app_update.current_version",
                    value: AppConfiguration.releaseLabel
                )

                if let release = appUpdate.response?.CurrentRelease {
                    LabeledContent {
                        Text("\(release.VersionName) (Build \(release.BuildNumber))")
                    } label: {
                        Text("app_update.latest_version")
                    }
                }

                LabeledContent {
                    statusView
                } label: {
                    Text("app_update.status")
                }
            }

            if let release = appUpdate.availableRelease {
                if let notes = release.ReleaseNotesMarkdown?.nilIfEmpty {
                    Section("app_update.release_notes") {
                        Text(
                            (try? AttributedString(
                                markdown: notes,
                                options: .init(
                                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                                )
                            ))
                                ?? AttributedString(notes)
                        )
                        .textSelection(.enabled)
                    }
                }

                Section {
                    Button {
                        openURL(storeURL(for: release))
                    } label: {
                        Label("app_update.open_app_store", systemImage: "arrow.up.right.square")
                    }
                }
            }

            Section {
                Button {
                    Task {
                        await appUpdate.check(force: true)
                        appUpdate.acknowledgeCurrentUpdate()
                    }
                } label: {
                    HStack {
                        Label("app_update.check_again", systemImage: "arrow.clockwise")
                        Spacer()
                        if appUpdate.isChecking {
                            ProgressView()
                        }
                    }
                }
                .disabled(appUpdate.isChecking)
            }
        }
        .navigationTitle("app_update.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await appUpdate.check(force: true)
            appUpdate.acknowledgeCurrentUpdate()
        }
        .refreshable {
            await appUpdate.check(force: true)
            appUpdate.acknowledgeCurrentUpdate()
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if appUpdate.isChecking {
            Text("app_update.checking")
                .foregroundStyle(.secondary)
        } else if appUpdate.availableRelease != nil {
            Text("app_update.available")
                .foregroundStyle(PixaTheme.accent)
        } else if appUpdate.isUnavailable {
            Text("app_update.unavailable")
                .foregroundStyle(.secondary)
        } else if appUpdate.didFinishCheck {
            Text("app_update.up_to_date")
                .foregroundStyle(.secondary)
        } else {
            Text("app_update.not_checked")
                .foregroundStyle(.secondary)
        }
    }

    private func storeURL(for release: PixaAppReleaseSummary) -> URL {
        guard let value = release.StoreUrl?.nilIfEmpty,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return AppConfiguration.appStoreURL
        }
        return url
    }
}
