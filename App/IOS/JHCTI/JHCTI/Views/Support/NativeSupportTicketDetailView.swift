import SwiftUI

struct NativeSupportTicketDetailView: View {
    let store: SessionStore
    let isLoading: Bool
    let detail: [String: Any]?
    let error: String?
    let detailId: String?
    @Binding var reply: String
    let replyAttachments: [String]
    let isSubmitting: Bool
    let isUploading: Bool
    let canEditReply: Bool
    let replyPending: Bool
    let replyLookupLabel: String
    let replyNotice: String?
    let checkingReply: Bool
    let retryOriginalReply: Bool
    @Binding var previewAttachment: URL?
    let replyAttachmentPicker: AnyView
    let onRetry: () -> Void
    let onCheckReply: () -> Void
    let onSubmitReply: () -> Void

    private var replyLocked: Bool { !canEditReply || isSubmitting || isUploading || checkingReply }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在加载工单详情…")
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(categoryName(detail["Category"] as? String ?? "Other")) · \(statusName(detail["Status"] as? String ?? ""))")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            Text(detail["Title"] as? String ?? "客服工单")
                                .font(.system(size: NativeTypography.size(20), weight: .bold))
                            Text("\(detail["TicketNo"] as? String ?? "") · 提交于 \(bookingBusinessDateTime(detail["CreateTime"]) ?? "时间未知")")
                                .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(Brand.background, in: RoundedRectangle(cornerRadius: 12))
                        ForEach(Array((detail["Messages"] as? [[String: Any]] ?? [])
                            .filter { $0["IsInternal"] as? Bool == false
                                && ["User", "Support"].contains($0["SenderType"] as? String ?? "") }
                            .enumerated()), id: \.offset) { _, message in
                            messageCard(message)
                        }
                        if let error { Text(error).foregroundStyle(.red).font(.system(size: NativeTypography.size(14))) }
                        if let replyNotice { Text(replyNotice).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted) }
                        if replyPending {
                            Button(replyLookupLabel, action: onCheckReply)
                                .buttonStyle(.bordered).tint(Brand.primary)
                                .disabled(isSubmitting || isUploading || checkingReply)
                        }
                        if (detail["Status"] as? String) != "Closed" {
                            TextField("补充说明或回复客服", text: $reply, axis: .vertical)
                                .lineLimit(4...8).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10))
                                .disabled(replyLocked)
                                .onChange(of: reply) { _, value in
                                    let limited = nativeLimitUtf16Text(value, maximum: 4000)
                                    if limited != value { reply = limited }
                                }
                            Text("\(reply.utf16.count)/4000").font(.system(size: NativeTypography.size(12)))
                                .foregroundStyle(Brand.muted).frame(maxWidth: .infinity, alignment: .trailing)
                            replyAttachmentPicker.disabled(replyLocked)
                            Button(isSubmitting ? "正在发送…" : retryOriginalReply ? "用原请求号发送" : "发送留言", action: onSubmitReply)
                                .buttonStyle(.borderedProminent).tint(Brand.primary)
                                .disabled(replyLocked
                                    || (reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && replyAttachments.isEmpty))
                        } else {
                            Text("工单已关闭，如仍需帮助，请重新提交问题。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                                .frame(maxWidth: .infinity).padding()
                        }
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 10) {
                    ContentUnavailableView("无法读取工单", systemImage: "message",
                        description: Text(error ?? "请返回列表后重试。"))
                    if let detailId { Button("重试", action: onRetry) }
                }
            }
        }
    }

    private func messageCard(_ message: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\((message["SenderType"] as? String) == "User" ? "我" : "客服") · \(bookingBusinessDateTime(message["CreateTime"]) ?? "时间未知")")
                .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            Text(message["Content"] as? String ?? "").font(.system(size: NativeTypography.size(14)))
            ForEach(Array((message["Attachments"] as? [String] ?? []).enumerated()), id: \.offset) { index, path in
                if let url = MobileAPI(store: store).mediaURL(path) {
                    HStack(spacing: 8) {
                        Button { previewAttachment = url } label: {
                            CachedRemoteImage(url: url) { Color.gray.opacity(0.15) }
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("预览附件图片 \(index + 1)")
                        Link("在浏览器打开", destination: url)
                            .font(.system(size: NativeTypography.size(14))).tint(Brand.primary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background((message["SenderType"] as? String) == "User" ? Color(red: 0.91, green: 0.96, blue: 0.94) : Brand.background,
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func categoryName(_ value: String) -> String {
        ["Order": "订单问题", "Payment": "支付问题", "Account": "账号问题", "Resource": "景点与服务",
         "Data": "资料问题", "Security": "安全问题", "Other": "其他"][value] ?? "其他"
    }

    private func statusName(_ value: String) -> String {
        ["Open": "待处理", "Assigned": "处理中", "PendingUser": "待回复", "Resolved": "已解决", "Closed": "已关闭"][value] ?? "处理中"
    }
}
