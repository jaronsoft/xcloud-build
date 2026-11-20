import SwiftUI

struct MyActivityRegistrationRecordCard: View {
    let item: [String: Any]
    let credentialClock: Date
    let expectedToken: String?
    let qrBusyId: String
    let qrRetry: ActivityRegistrationQrRetry?
    let loading: Bool
    let cancelBusyId: String
    let deleteBusyId: String
    let onCopyCode: (String, String, String?) -> Void
    let onShowQr: (String, String) -> Void
    let onRequestCancellation: ([String: Any]) -> Void
    let onRetryQr: (ActivityRegistrationQrRetry) -> Void
    let onRequestDeletion: ([String: Any]) -> Void
    let onRefresh: () -> Void

    private var id: String { item["Id"] as? String ?? "" }
    private var status: String { item["Status"] as? String ?? "" }
    private var expired: Bool { activityRegistrationExpired(item, now: credentialClock) }
    private var expiryUnknown: Bool { activityRegistrationExpiryUnknown(item) }
    private var credentialUnavailable: Bool { activityRegistrationCredentialUnavailable(item, now: credentialClock) }
    private var statusText: String {
        expired ? "已过期" : expiryUnknown ? "确认状态中" : status == "Registered" ? "已报名"
            : status == "CheckedIn" ? "已签到" : status == "Cancelled" ? "已取消" : "待核对"
    }
    private var statusColor: Color {
        expired ? Color(red: 0.70, green: 0.34, blue: 0.29)
            : expiryUnknown ? Color(red: 0.70, green: 0.47, blue: 0.10)
            : status == "Cancelled" ? .gray
            : status == "CheckedIn" ? Color(red: 0.16, green: 0.48, blue: 0.37)
            : Brand.primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(item["ActivityName"] as? String ?? "活动报名")
                    .font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(statusText).font(.system(size: NativeTypography.size(12), weight: .semibold)).foregroundStyle(statusColor)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(statusColor.opacity(0.10), in: Capsule())
            }
            if let session = item["SessionName"] as? String, !session.isEmpty {
                Label(session, systemImage: "calendar")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
            }
            HStack(spacing: 14) {
                Label("\(item["Quantity"] as? Int ?? 1) 人", systemImage: "person.2")
                Label(activityRegistrationBusinessDateTime(item["CreateTime"]) ?? "—", systemImage: "clock")
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            if let participants = item["Participants"] as? [[String: Any]] {
                ForEach(Array(participants.enumerated()), id: \.offset) { index, participant in
                    let name = (participant["DisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                        ?? "参与者 \(participant["ParticipantNo"] as? Int ?? index + 1)"
                    let participantStatus = activityRegistrationParticipantStatus(participant["Status"])
                    let checkedInAt = activityRegistrationBusinessDateTime(participant["CheckedInAt"])
                    Text("\(name)：\(participantStatus)\(checkedInAt.map { " · \($0)" } ?? "")")
                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                }
            }
            if let cancelledAt = activityRegistrationBusinessDateTime(item["CancelledAt"]) {
                Text("取消时间：\(cancelledAt)").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            }
            if let checkedInAt = activityRegistrationBusinessDateTime(item["CheckedInAt"]) {
                Text("签到时间：\(checkedInAt)").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            }
            if status == "Registered" && !credentialUnavailable {
                if let code = item["CredentialCode"] as? String, !code.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "ticket").foregroundStyle(Brand.primary)
                        Text("签到码").font(.system(size: NativeTypography.size(14), weight: .medium)).foregroundStyle(Brand.muted)
                        Text(code).font(.system(size: NativeTypography.size(14), weight: .semibold, design: .monospaced))
                            .foregroundStyle(Brand.primary).lineLimit(1).minimumScaleFactor(0.75).textSelection(.enabled)
                        Button("复制") { onCopyCode(id, code, expectedToken) }
                            .font(.system(size: NativeTypography.size(12), weight: .semibold)).tint(Brand.primary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    HStack {
                        Button(qrBusyId == id ? "正在生成…" : "出示签到二维码") {
                            onShowQr(id, item["ActivityName"] as? String ?? "活动报名")
                        }
                        .disabled(!qrBusyId.isEmpty)
                        Spacer()
                        if item["CanCancel"] as? Bool == true {
                            Button("取消报名", role: .destructive) { onRequestCancellation(item) }
                                .disabled(loading || !cancelBusyId.isEmpty || !deleteBusyId.isEmpty)
                        }
                    }.font(.system(size: NativeTypography.size(14), weight: .semibold)).tint(Brand.primary)
                    if let qrRetry, qrRetry.registrationID == id, qrRetry.token == expectedToken {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(qrRetry.message).font(.system(size: NativeTypography.size(12))).foregroundStyle(.red)
                            Button("重试显示二维码") { onRetryQr(qrRetry) }
                                .accessibilityLabel("重试显示\(qrRetry.title)签到二维码")
                                .disabled(!qrBusyId.isEmpty)
                        }
                    }
                }
            } else if status == "Registered" && expired {
                Text("活动已结束，签到凭证已失效。")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                Button(deleteBusyId == id ? "正在删除…" : "删除记录", role: .destructive) {
                    onRequestDeletion(item)
                }
                .disabled(loading || !deleteBusyId.isEmpty || !cancelBusyId.isEmpty)
            } else if status == "Registered" && expiryUnknown {
                Text("签到凭证有效期暂无法确认，请刷新报名状态。")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                Button("刷新状态", action: onRefresh).disabled(loading)
            } else if status == "Registered" && item["CanCancel"] as? Bool != true {
                Text("已超过取消时限或已有参与者签到，不可取消")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
            }
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}
