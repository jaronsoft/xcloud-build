import SwiftUI

struct ResourceDetailReviewForm: View {
    let isLoggedIn: Bool
    let isLoading: Bool
    let featureState: NativePublicFeatureAccessState
    let error: String?
    let review: [String: Any]?
    let reviewBusy: Bool
    let appealBusy: Bool
    @Binding var rating: Int
    @Binding var content: String
    @Binding var appealContent: String
    let onRetry: () -> Void
    let onSubmitReview: () -> Void
    let onSubmitAppeal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("我的评价").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
            if !isLoggedIn {
                Text(featureState == .open
                    ? "登录文旅账号后，可在个人中心打开登录页并提交评价。"
                    : featureState.message(featureName: "评价功能", action: "暂不能提交新评价"))
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                if featureState == .unavailable || featureState == .pendingConfirmation {
                    Button("重试读取", action: onRetry)
                        .font(.system(size: NativeTypography.size(14), weight: .semibold))
                }
            } else if isLoading {
                ProgressView("正在读取本人评价…").font(.system(size: NativeTypography.size(14)))
            } else if let error {
                Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                Button("重试读取", action: onRetry)
                    .font(.system(size: NativeTypography.size(14), weight: .semibold))
            } else if let review {
                let reviewStatus = (review["ReviewStatus"] as? Int) ?? -1
                let appealStatus = (review["AppealStatus"] as? Int) ?? 0
                let reviewStatusText = [0: "审核中", 1: "已通过", 2: "未通过"][reviewStatus] ?? "状态更新中"
                Text("\(reviewStatusText) · \(String(repeating: "★", count: max(0, min(5, (review["Rating"] as? Int) ?? 0))))")
                    .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.primary)
                Text(review["Content"] as? String ?? "").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
                if let remark = review["ReviewRemark"] as? String, !remark.isEmpty {
                    Text("审核意见：\(remark)").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                }
                if let reply = review["Reply"] as? String, !reply.isEmpty {
                    Text("商家回复：\(reply)")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                        .textSelection(.enabled)
                }
                if reviewStatus == 2 {
                    Text("申诉状态：\([0: "未申诉", 1: "申诉处理中", 2: "申诉已通过", 3: "申诉未通过"][appealStatus] ?? "状态更新中")")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    if let response = review["AppealResponse"] as? String, !response.isEmpty {
                        Text("处理意见：\(response)")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            .textSelection(.enabled)
                    }
                    if appealStatus != 1 {
                        TextField("填写申诉说明（5 至 2000 字）", text: $appealContent, axis: .vertical)
                            .lineLimit(3...6).textFieldStyle(.roundedBorder)
                        Button(appealBusy ? "正在提交…" : "提交申诉", action: onSubmitAppeal)
                            .disabled(appealBusy || !(5...2000).contains(appealContent.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count))
                    }
                }
            } else if featureState != .open {
                Text(featureState.message(featureName: "评价功能", action: "暂不能提交新评价"))
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                if featureState == .unavailable || featureState == .pendingConfirmation {
                    Button("重试读取", action: onRetry)
                        .font(.system(size: NativeTypography.size(14), weight: .semibold))
                }
            } else {
                Text("每个账号对同一景点只能评价一次；评价审核通过后公开展示。")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                HStack(spacing: 8) {
                    Text("评分")
                    ForEach(1...5, id: \.self) { value in
                        Button(value <= rating ? "★" : "☆") { rating = value }
                            .buttonStyle(.plain).foregroundStyle(Brand.primary)
                            .accessibilityLabel("\(value)分")
                            .accessibilityValue(rating == value ? "已选中" : "未选中")
                            .accessibilityAddTraits(rating == value ? .isSelected : [])
                    }
                }
                .font(.system(size: NativeTypography.size(16)))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("评价评分")
                Text("\(rating) 分")
                    .font(.system(size: NativeTypography.size(13)))
                    .foregroundStyle(Brand.muted)
                TextField("分享真实体验（最多 2000 字）", text: $content, axis: .vertical)
                    .lineLimit(3...6).textFieldStyle(.roundedBorder)
                Button(reviewBusy ? "正在提交…" : "提交评价", action: onSubmitReview)
                    .disabled(reviewBusy || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || content.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 2000)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
    }
}
