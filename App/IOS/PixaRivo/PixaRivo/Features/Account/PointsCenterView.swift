import Observation
import SwiftUI
import UIKit

private struct PromotionCodeRequest: Encodable { let code: String }

@MainActor
@Observable
private final class PromotionCodeViewModel {
    private let api = APIClient()
    var code = ""
    private(set) var isWorking = false
    private(set) var message: String?
    private(set) var succeeded = false

    func redeem(session: SessionStore) async {
        guard let token = await session.validAccessToken(), !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isWorking = true
        message = nil
        succeeded = false
        defer { isWorking = false }
        do {
            let points: Int = try await api.post(
                "/api/ais/recharge/redeem",
                body: PromotionCodeRequest(code: code.trimmingCharacters(in: .whitespacesAndNewlines)),
                token: token
            )
            succeeded = true
            message = String.localizedStringWithFormat(AppLanguage.localized("promo.success"), points)
            code = ""
            NotificationCenter.default.post(name: .pixaBalanceDidChange, object: nil)
        } catch {
            message = error.localizedDescription
        }
    }
}

struct PointsCenterView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case subscription, recharge, code, invitation
        var id: String { rawValue }
    }

    @State private var selectedTab: Tab

    init(initialTab: Tab = .subscription) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("points.center.title", selection: $selectedTab) {
                Text("points.center.subscription").tag(Tab.subscription)
                Text("points.center.recharge").tag(Tab.recharge)
                Text("points.center.code").tag(Tab.code)
                Text("points.center.invitation").tag(Tab.invitation)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            switch selectedTab {
            case .subscription:
                RechargeStoreKitView(mode: .subscription)
            case .recharge:
                RechargeStoreKitView(mode: .recharge)
            case .code:
                PromotionCodeView()
            case .invitation:
                InvitationView()
            }
        }
        .background(PixaTheme.paper.ignoresSafeArea())
        .navigationTitle("points.center.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct PromotionCodeView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = PromotionCodeViewModel()

    var body: some View {
        Form {
            Section {
                TextField("promo.placeholder", text: $model.code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button {
                    Task { await model.redeem(session: session) }
                } label: {
                    if model.isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("promo.redeem").frame(maxWidth: .infinity)
                    }
                }
                .disabled(model.isWorking || model.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("promo.input")
            } footer: {
                Text("promo.hint")
            }
            if let message = model.message {
                Section {
                    Label(message, systemImage: model.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(model.succeeded ? .green : .red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PixaTheme.paper)
    }
}

struct InvitationOverview: Decodable, Sendable {
    let inviteCode: String?
    let referralCount: Int
    let registrationRewardPoints: Int
    let commissionRate: Double
    let protectionDays: Int
    let bindingPolicy: String?

    private enum CodingKeys: String, CodingKey {
        case inviteCode, referralCount
        case registrationRewardPoints, commissionRate, protectionDays, bindingPolicy
        case inviteCodeUpper = "InviteCode"
        case referralCountUpper = "ReferralCount"
        case registrationRewardPointsUpper = "RegistrationRewardPoints"
        case commissionRateUpper = "CommissionRate"
        case protectionDaysUpper = "ProtectionDays"
        case bindingPolicyUpper = "BindingPolicy"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        inviteCode = try box.decodeIfPresent(String.self, forKey: .inviteCode)
            ?? box.decodeIfPresent(String.self, forKey: .inviteCodeUpper)
        referralCount = try box.decodeIfPresent(Int.self, forKey: .referralCount)
            ?? box.decodeIfPresent(Int.self, forKey: .referralCountUpper) ?? 0
        registrationRewardPoints = try box.decodeIfPresent(Int.self, forKey: .registrationRewardPoints)
            ?? box.decodeIfPresent(Int.self, forKey: .registrationRewardPointsUpper) ?? 0
        commissionRate = try box.decodeIfPresent(Double.self, forKey: .commissionRate)
            ?? box.decodeIfPresent(Double.self, forKey: .commissionRateUpper) ?? 0
        protectionDays = try box.decodeIfPresent(Int.self, forKey: .protectionDays)
            ?? box.decodeIfPresent(Int.self, forKey: .protectionDaysUpper) ?? 0
        bindingPolicy = try box.decodeIfPresent(String.self, forKey: .bindingPolicy)
            ?? box.decodeIfPresent(String.self, forKey: .bindingPolicyUpper)
    }
}

private struct InvitationQRCode: Decodable, Sendable {
    let dataURL: String
    let content: String

    private enum CodingKeys: String, CodingKey {
        case dataURL, content
        case dataURLUpper = "DataUrl"
        case contentUpper = "Content"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        dataURL = try box.decodeIfPresent(String.self, forKey: .dataURL)
            ?? box.decode(String.self, forKey: .dataURLUpper)
        content = try box.decodeIfPresent(String.self, forKey: .content)
            ?? box.decode(String.self, forKey: .contentUpper)
    }
}

@MainActor
@Observable
private final class InvitationViewModel {
    private let api = APIClient()
    private(set) var overview: InvitationOverview?
    private(set) var qrCode: InvitationQRCode?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var inviteURL: URL? { qrCode.flatMap { URL(string: $0.content) } }
    var qrImage: UIImage? {
        guard let dataURL = qrCode?.dataURL,
              let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else { return nil }
        return UIImage(data: data)
    }

    func load(session: SessionStore) async {
        guard let token = await session.validAccessToken(), !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let overview: InvitationOverview = api.get("/api/ais/promotion/overview", token: token)
            async let qrCode: InvitationQRCode = api.get("/api/ais/promotion/inviteqrcode", token: token)
            self.overview = try await overview
            self.qrCode = try await qrCode
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct InvitationView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var model = InvitationViewModel()
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                invitationHeader
                VStack(spacing: 14) {
                    qrCode
                    inviteCode
                    rewardBenefits
                    actionButtons
                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 18)
            }
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.9))
            }
            .shadow(color: PixaTheme.ink.opacity(0.06), radius: 18, y: 8)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .contentMargins(.bottom, 90, for: .scrollContent)
        .task { await model.load(session: session) }
    }

    private var invitationHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image("BrandIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: PixaTheme.accent.opacity(0.18), radius: 8, y: 4)
                Text("invitation.title")
                    .font(.title3.bold())
                    .foregroundStyle(PixaTheme.ink)
            }
            Text("invitation.subtitle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background {
            LinearGradient(
                colors: [PixaTheme.accent.opacity(0.12), PixaTheme.accent.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var qrCode: some View {
        if let image = model.qrImage {
            VStack(spacing: 10) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 176, height: 176)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(PixaTheme.accent.opacity(0.16))
                    }
                    .shadow(color: PixaTheme.ink.opacity(0.07), radius: 12, y: 5)
                Text("invitation.scan_hint")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if model.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(PixaTheme.accent)
                Text("loading.invitation.title")
                    .font(.subheadline.weight(.semibold))
                Text("loading.invitation.message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 196, height: 196)
        }
    }

    private var inviteCode: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("invitation.code_title")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(model.overview?.inviteCode ?? "—")
                    .font(.headline.bold().monospaced())
                    .foregroundStyle(PixaTheme.accent)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 34)

            Label(
                String.localizedStringWithFormat(
                    AppLanguage.localized("invitation.people"),
                    model.overview?.referralCount ?? 0
                ),
                systemImage: "person.2.fill"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(PixaTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    guard let inviteCode = model.overview?.inviteCode?.nilIfEmpty else { return }
                    UIPasteboard.general.string = inviteCode
                    copied = true
                } label: {
                    Label(
                        copied ? "invitation.copied" : "invitation.copy",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(PixaTheme.accent)
                    .background(PixaTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.overview?.inviteCode?.nilIfEmpty == nil)

                if let url = model.inviteURL {
                    Button {
                        guard let target = xShareURL(inviteURL: url) else { return }
                        openURL(target)
                    } label: {
                        Label("invitation.share_x", systemImage: "at")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(.white)
                            .background(.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let url = model.inviteURL {
                ShareLink(
                    item: url,
                    subject: Text("invitation.share.subject"),
                    message: Text(String.localizedStringWithFormat(
                        AppLanguage.localized("invitation.share.message"),
                        model.overview?.inviteCode ?? ""
                    ))
                ) {
                    Label("invitation.share_more", systemImage: "square.and.arrow.up")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(.white)
                        .background(PixaTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rewardBenefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                String.localizedStringWithFormat(
                    AppLanguage.localized("invitation.registration_reward"),
                    model.overview?.registrationRewardPoints ?? 0
                ),
                systemImage: "gift.fill"
            )
            Label(
                String.localizedStringWithFormat(
                    AppLanguage.localized("invitation.commission"),
                    model.overview?.commissionRate ?? 0
                ),
                systemImage: "chart.line.uptrend.xyaxis"
            )
            Label("invitation.gallery_reward", systemImage: "photo.badge.checkmark")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(PixaTheme.ink.opacity(0.78))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func xShareURL(inviteURL: URL) -> URL? {
        var sharedComponents = URLComponents(url: inviteURL, resolvingAgainstBaseURL: false)
        sharedComponents?.queryItems = [URLQueryItem(name: "source", value: "x")]
        guard let sharedURL = sharedComponents?.url else { return nil }

        let code = model.overview?.inviteCode ?? ""
        let message = String.localizedStringWithFormat(
            AppLanguage.localized("invitation.share.x_message"),
            code
        )
        var target = URLComponents(string: "https://x.com/intent/post")
        target?.queryItems = [
            URLQueryItem(name: "text", value: message),
            URLQueryItem(name: "url", value: sharedURL.absoluteString),
        ]
        return target?.url
    }
}
