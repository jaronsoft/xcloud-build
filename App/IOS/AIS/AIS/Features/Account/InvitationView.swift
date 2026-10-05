import Observation
import SwiftUI
import UIKit

struct AISInvitationOverview: Codable {
    let inviteCode: String?
    let referralCount: Int

    private enum CodingKeys: String, CodingKey {
        case inviteCode = "InviteCode"
        case referralCount = "ReferralCount"
    }
}

struct AISInvitationQRCode: Codable {
    let dataURL: String
    let content: String

    private enum CodingKeys: String, CodingKey {
        case dataURL = "DataUrl"
        case content = "Content"
    }
}

struct AISReferralUser: Codable, Identifiable {
    let id: String
    let userName: String
    let avatarURL: String?
    let registeredAt: Date
    let recommendationStatus: String

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case userName = "UserName"
        case avatarURL = "AvatarUrl"
        case registeredAt = "RegisteredAt"
        case recommendationStatus = "RecommendationStatus"
    }
}

@MainActor
@Observable
final class InvitationViewModel {
    private let api: APIClient
    private let pageSize = 20

    private(set) var overview: AISInvitationOverview?
    private(set) var qrCode: AISInvitationQRCode?
    private(set) var referrals: [AISReferralUser] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var errorMessage: String?
    private var page = 0

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    var inviteURL: URL? {
        guard let value = qrCode?.content,
              let url = URL(string: value) else {
            return nil
        }
        return url
    }

    var qrImage: UIImage? {
        guard let dataURL = qrCode?.dataURL,
              let comma = dataURL.firstIndex(of: ",") else {
            return nil
        }
        let encoded = String(dataURL[dataURL.index(after: comma)...])
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return UIImage(data: data)
    }

    func load(session: SessionStore, force: Bool = false) async {
        guard !isLoading else { return }
        guard let token = await session.validAccessToken() else {
            errorMessage = String(localized: "auth.required")
            return
        }
        if !force, overview != nil, qrCode != nil { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let overview: AISInvitationOverview = api.get(
                "/api/ais/promotion/overview",
                accessToken: token
            )
            async let qrCode: AISInvitationQRCode = api.get(
                "/api/ais/promotion/inviteqrcode",
                accessToken: token
            )
            self.overview = try await overview
            self.qrCode = try await qrCode
            try await loadPage(1, token: token, appends: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore(session: SessionStore) async {
        guard hasMore, !isLoadingMore,
              let token = await session.validAccessToken() else {
            return
        }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            try await loadPage(page + 1, token: token, appends: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPage(
        _ requestedPage: Int,
        token: String,
        appends: Bool
    ) async throws {
        let response: PageResponse<AISReferralUser> = try await api.get(
            "/api/ais/promotion/referrals",
            query: [
                URLQueryItem(name: "page", value: String(requestedPage)),
                URLQueryItem(name: "size", value: String(pageSize))
            ],
            accessToken: token
        )
        referrals = appends ? referrals + response.items : response.items
        page = response.page
        hasMore = referrals.count < response.total
    }
}

struct InvitationView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = InvitationViewModel()
    @State private var sharePayload: AISSharePayload?
    @State private var copied = false
    @State private var isPreparingShare = false

    var body: some View {
        ZStack {
            AISPageBackground()
            if model.isLoading, model.overview == nil {
                ProgressView("common.loading")
            } else {
                content
            }
        }
        .navigationTitle("invitation.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load(session: session)
        }
        .sheet(item: $sharePayload) { payload in
            AISActivityView(items: payload.items)
        }
        .refreshable {
            await model.load(session: session, force: true)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                invitationCard
                referralSection
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
    }

    private var invitationCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 7) {
                Image("BrandIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                Text("invitation.title")
                    .font(.title2.bold())
                Text("invitation.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let qrImage = model.qrImage {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
                Text("invitation.qr_helper")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                invitationValue(
                    title: "invitation.code",
                    value: model.overview?.inviteCode ?? "—"
                )
                invitationValue(
                    title: "invitation.link",
                    value: model.inviteURL?.absoluteString ?? "—"
                )
            }

            HStack(spacing: 10) {
                Button {
                    copyInvitationLink()
                } label: {
                    Label(
                        copied ? "invitation.copied" : "invitation.copy",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.inviteURL == nil)

                Button {
                    Task { await sharePoster() }
                } label: {
                    Label(
                        "invitation.share",
                        systemImage: "square.and.arrow.up"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.qrImage == nil || isPreparingShare)
            }

            if let errorMessage = model.errorMessage {
                VStack(spacing: 10) {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("invitation.retry") {
                        Task {
                            await model.load(session: session, force: true)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .aisSurface(cornerRadius: 26, hasShadow: true)
    }

    private func invitationValue(
        title: LocalizedStringKey,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background(
            Color(uiColor: .tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private var referralSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("invitation.referrals").font(.headline)
                Spacer()
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "invitation.people"),
                        Int64(model.overview?.referralCount ?? 0)
                    )
                )
                .font(.caption.bold())
                .foregroundStyle(AISTheme.accent)
            }

            if model.referrals.isEmpty {
                ContentUnavailableView(
                    "invitation.empty",
                    systemImage: "person.2.badge.plus"
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.referrals) { referral in
                        referralRow(referral)
                        if referral.id != model.referrals.last?.id {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                if model.hasMore {
                    Button {
                        Task { await model.loadMore(session: session) }
                    } label: {
                        if model.isLoadingMore {
                            ProgressView("invitation.loading_more")
                        } else {
                            Text("invitation.load_more")
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("invitation.end")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .aisSurface(cornerRadius: 24)
    }

    private func referralRow(_ referral: AISReferralUser) -> some View {
        HStack(spacing: 12) {
            AISCachedAsyncImage(
                url: URL(string: referral.avatarURL ?? ""),
                preset: .thumbnail,
                module: .other
            ) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 38, height: 38)
            .background(AISTheme.accent.opacity(0.08), in: Circle())
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(referral.userName).font(.subheadline.weight(.semibold))
                Text(
                    referral.registeredAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(
                referral.recommendationStatus == "recharged"
                    ? "invitation.recharged"
                    : "invitation.registered"
            )
            .font(.caption.bold())
            .foregroundStyle(AISTheme.accent)
        }
        .padding(.vertical, 12)
    }

    private func copyInvitationLink() {
        guard let url = model.inviteURL else { return }
        UIPasteboard.general.url = url
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            copied = false
        }
    }

    private func sharePoster() async {
        guard let qrImage = model.qrImage,
              let inviteURL = model.inviteURL else {
            return
        }
        isPreparingShare = true
        defer { isPreparingShare = false }
        let poster = AISInvitationPoster(
            inviteCode: model.overview?.inviteCode ?? "",
            inviteURL: inviteURL,
            qrImage: qrImage
        )
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 2
        guard let image = renderer.uiImage else { return }
        sharePayload = AISSharePayload(items: [image.aisOpaqueImage()])
    }
}

private struct AISInvitationPoster: View {
    let inviteCode: String
    let inviteURL: URL
    let qrImage: UIImage

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    Image("BrandIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("invitation.poster_brand")
                            .font(.system(size: 28, weight: .black))
                        Text("invitation.poster_footer")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.76))
                    }
                    Spacer()
                }
                Text("invitation.poster_title")
                    .font(.system(size: 42, weight: .black))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("invitation.poster_subtitle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.white)
            .padding(48)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.09, blue: 0.18),
                        Color(red: 0.27, green: 0.17, blue: 0.62),
                        AISTheme.accent
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            VStack(spacing: 22) {
                Text("invitation.qr_title")
                    .font(.system(size: 30, weight: .black))
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 390, height: 390)
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 28))
                    .shadow(color: .black.opacity(0.1), radius: 22, y: 8)
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "invitation.code_value"),
                        inviteCode
                    )
                )
                .font(.system(size: 22, weight: .bold))
                Text(inviteURL.absoluteString)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 42)
            .frame(maxWidth: .infinity)
            .background(.white)
        }
        .frame(width: 720, height: 1_000)
        .background(.white)
    }
}

#Preview("InvitationView") {
    NavigationStack {
        InvitationView()
    }
    .environment(SessionStore())
}
