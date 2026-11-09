import SwiftUI
import UIKit

struct ActivityRegistrationCard: View {
    let recoveryPending: Bool
    let recoveryChecking: Bool
    let receipt: [String: Any]?
    let activityName: String
    let sessionName: String
    let receiptPrincipalMatches: Bool
    let sceneIsActive: Bool
    @Binding var credentialCopyNotice: String?
    let registrationEnabled: Bool?
    let isAuthenticated: Bool
    let remainingQuota: Int?
    let loading: Bool
    let configurationError: String?
    let sessions: [[String: Any]]
    let chosenSession: [String: Any]?
    let remainingSeats: Int
    let fields: [[String: Any]]
    let quantity: Int
    let configuredLimit: Int
    let maxQuantity: Int
    let selectedSessionBookable: Bool
    @Binding var participantAnswers: [[String: String]]
    @Binding var identityConsent: Bool
    let submitError: String?
    let isBusy: Bool
    let onRecover: () -> Void
    let onShowRegistrations: () -> Void
    let onRequestRecoveryClear: () -> Void
    let onRetry: () -> Void
    let onQuantityChange: (Int) -> Void
    let onAnswerChange: (String, String, Int, Int?) -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("活动报名").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
            if recoveryPending {
                Text(isBusy ? "正在提交报名，请稍候…" : "上次报名结果需要核对，暂不能开始新报名。")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                if let submitError { Text(submitError).font(.caption).foregroundStyle(.red) }
                Button(recoveryChecking ? "正在核对…" : "核对报名结果", action: onRecover)
                    .disabled(isBusy || recoveryChecking)
                Button("查看我的报名", action: onShowRegistrations).disabled(isBusy || recoveryChecking)
                Button("已核对记录，清除恢复标记", action: onRequestRecoveryClear)
                    .disabled(isBusy || recoveryChecking)
            } else if let receipt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let now = max(context.date, Date())
                    let resultLabel = receipt["Status"] as? String == "Cancelled" ? "该报名已取消"
                        : receipt["Status"] as? String == "CheckedIn" ? "报名已签到"
                        : activityRegistrationExpired(receipt, now: now) ? "报名已过期" : "报名成功"
                    Text("\(resultLabel)：\(activityName)").foregroundStyle(Brand.primary)
                    Text("场次：\(sessionName) · \(receipt["Quantity"] as? Int ?? 1) 人")
                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                    if sceneIsActive, let code = activityRegistrationReceiptCode(receipt, now: now) {
                        Text("签到码：\(code)").textSelection(.enabled)
                        Button("复制凭证") {
                            guard sceneIsActive, receiptPrincipalMatches,
                                  let currentCode = activityRegistrationReceiptCode(receipt, now: max(now, Date())),
                                  currentCode == code else {
                                credentialCopyNotice = "签到凭证已变化或过期，请刷新后查看。"
                                return
                            }
                            UIPasteboard.general.string = code
                            credentialCopyNotice = "凭证已复制。"
                        }
                        .accessibilityLabel("复制活动签到凭证")
                        if let credentialCopyNotice {
                            Text(credentialCopyNotice).font(.caption).foregroundStyle(Brand.muted)
                        }
                    } else if activityRegistrationExpired(receipt, now: now) {
                        Text("场次已结束，签到凭证已过期。")
                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                    } else {
                        Text("请前往“我的活动报名”查看最新报名状态与签到凭证。")
                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                    }
                }
                Button("查看我的报名记录", action: onShowRegistrations)
            } else if registrationEnabled == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("暂时无法确认活动报名状态，报名入口已关闭。")
                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(.red)
                    Button("重试读取活动报名状态", action: onRetry)
                        .font(.system(size: NativeTypography.size(12), weight: .semibold))
                        .foregroundStyle(Brand.primary)
                }
            } else if registrationEnabled != true {
                Text("暂时不能报名，你仍可查看活动详情。")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            } else if !isAuthenticated {
                Text("请先在“我的”登录并验证手机号，再返回此页报名。")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            } else if remainingQuota == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("暂无法确认本人剩余报名名额，请重试加载。")
                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                    Button("重试读取报名额度", action: onRetry)
                        .font(.system(size: NativeTypography.size(12), weight: .semibold))
                        .foregroundStyle(Brand.primary)
                }
            } else if remainingQuota == 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("您的可报名人数已用完。")
                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                    Text("如果刚取消过报名，可刷新额度后重新报名。")
                        .font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted)
                    Button("刷新报名额度", action: onRetry)
                        .font(.system(size: NativeTypography.size(12), weight: .semibold))
                        .foregroundStyle(Brand.primary)
                        .disabled(loading)
                }
            } else if let configurationError {
                Text(configurationError).font(.footnote).foregroundStyle(Brand.muted)
            } else {
                Text("可报名人数：\(remainingQuota ?? 0)")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                if !sessions.isEmpty, let chosenSession {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前报名场次").font(.system(size: NativeTypography.size(10), weight: .medium)).foregroundStyle(Brand.muted)
                        Text(chosenSession["Name"] as? String ?? "活动场次")
                            .font(.system(size: NativeTypography.size(12), weight: .semibold)).foregroundStyle(Brand.ink)
                        Text("剩余名额 \(remainingSeats) 个").font(.system(size: NativeTypography.size(10))).foregroundStyle(Brand.muted)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
                } else if sessions.isEmpty {
                    Text("剩余名额 \(remainingSeats) 个").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                }
                ActivityRegistrationFormSection(
                    fields: fields,
                    quantity: quantity,
                    remainingQuota: remainingQuota ?? 0,
                    configuredLimit: configuredLimit,
                    maxQuantity: maxQuantity,
                    remainingSeats: remainingSeats,
                    selectedSessionBookable: selectedSessionBookable,
                    requiresSession: !sessions.isEmpty,
                    hasSelectedSession: chosenSession != nil,
                    participantAnswers: $participantAnswers,
                    identityConsent: $identityConsent,
                    submitError: submitError,
                    isBusy: isBusy,
                    onQuantityChange: onQuantityChange,
                    onAnswerChange: onAnswerChange,
                    onSubmit: onSubmit)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .disabled(isBusy)
    }
}
