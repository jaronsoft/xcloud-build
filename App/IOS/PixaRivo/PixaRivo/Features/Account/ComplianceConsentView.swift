import SwiftUI

struct ComplianceConsentView: View {
    @Environment(SessionStore.self) private var session
    @State private var remainingSeconds = 3

    private var canAccept: Bool {
        remainingSeconds == 0
            && !session.isAcceptingComplianceConsent
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        header
                        documentCard(
                            icon: "hand.raised.fill",
                            title: "compliance.privacy.title",
                            summary: "compliance.privacy.summary",
                            url: AppConfiguration.privacyURL
                        )
                        documentCard(
                            icon: "photo.on.rectangle.angled",
                            title: "compliance.upload.title",
                            summary: "compliance.upload.summary",
                            url: AppConfiguration.uploadComplianceURL
                        )
                        documentCard(
                            icon: "rectangle.stack.badge.person.crop",
                            title: "compliance.gallery.title",
                            summary: "compliance.gallery.summary",
                            url: AppConfiguration.galleryIntellectualPropertyURL
                        )
                        documentCard(
                            icon: "doc.text.fill",
                            title: "compliance.terms.title",
                            summary: "compliance.terms.summary",
                            url: AppConfiguration.termsURL
                        )
                        Text("compliance.confirmation")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    .padding(20)
                }

                actionArea
            }
            .background(PixaTheme.paper)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                remainingSeconds = 3
                for second in stride(from: 2, through: 0, by: -1) {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    remainingSeconds = second
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("compliance.title")
                .font(.largeTitle.bold())
            Text("compliance.subtitle")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private func documentCard(
        icon: String,
        title: LocalizedStringKey,
        summary: LocalizedStringKey,
        url: URL
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(PixaTheme.ink)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: url) {
                Label("compliance.read_full", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PixaTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pixaSurface(cornerRadius: 16)
    }

    private var actionArea: some View {
        VStack(spacing: 10) {
            if let error = session.complianceConsentError?.nilIfEmpty {
                VStack(spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("compliance.retry") {
                        Task { await session.refreshComplianceConsent() }
                    }
                    .font(.caption.bold())
                }
            }

            Button {
                Task { _ = await session.acceptComplianceConsent() }
            } label: {
                HStack(spacing: 8) {
                    if session.isAcceptingComplianceConsent {
                        ProgressView().tint(.white)
                    }
                    actionTitle
                }
            }
            .pixaPrimaryButton(isEnabled: canAccept)
            .disabled(!canAccept)

            Button("compliance.decline") { session.signOut() }
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var actionTitle: Text {
        if remainingSeconds > 0 {
            return Text(
                verbatim: String.localizedStringWithFormat(
                    AppLanguage.localized("compliance.wait"),
                    remainingSeconds
                )
            )
        }
        return Text("compliance.accept")
    }
}
