import SwiftUI
import PhotosUI

struct NativeCommerceOrderItemsSection: View {
    let orderStatus: String
    let items: [[String: Any]]
    let reviewsEnabled: Bool
    let reviewStatusLoading: Bool
    let reviewStatusError: String?
    let reviewedOrderItemIds: Set<String>
    let pendingReviewItemIds: Set<String>
    let reviewDraftItemId: String?
    let uploadingReviewPhotos: Bool
    let submittingReview: Bool
    let reviewNeedsVerification: Bool
    let reviewMessage: String?
    @Binding var reviewRating: Int
    @Binding var reviewContent: String
    @Binding var reviewMediaUrls: [String]
    @Binding var selectedReviewPhotos: [PhotosPickerItem]
    let onClearDraft: () -> Void
    let onRemoveImage: (String) -> Void
    let onVerifyReview: () -> Void
    let onStartReview: (String) -> Void
    let onStartDraft: (String) -> Void
    let onReloadStatus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("商品明细").font(.system(size: NativeTypography.size(14), weight: .semibold))
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let itemId = item["Id"] as? String ?? ""
                let reviewPhotoCount = reviewMediaUrls.count
                let reviewPhotoPickerTitle = uploadingReviewPhotos
                    ? "图片上传中…" : "添加图片（\(reviewPhotoCount)/9）"
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(item["ProductName"] as? String ?? "商品") × \(item["Quantity"] as? Int ?? 1)")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
                    if orderStatus == "Completed", !itemId.isEmpty {
                        if reviewedOrderItemIds.contains(itemId) {
                            Text("已评价").font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.primary)
                        } else if reviewsEnabled || pendingReviewItemIds.contains(itemId) || reviewDraftItemId == itemId {
                            if reviewDraftItemId == itemId {
                                let editingLocked = !reviewsEnabled || submittingReview || uploadingReviewPhotos
                                    || reviewStatusLoading || reviewNeedsVerification
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("商品评分").font(.system(size: NativeTypography.size(14), weight: .medium))
                                    Picker("商品评分", selection: $reviewRating) {
                                        ForEach(1...5, id: \.self) { value in Text("\(value) 星").tag(value) }
                                    }.pickerStyle(.segmented).disabled(editingLocked)
                                    TextField("评价内容（2 至 2000 字）", text: $reviewContent, axis: .vertical)
                                        .lineLimit(3...6).textFieldStyle(.roundedBorder)
                                        .disabled(editingLocked)
                                    HStack(spacing: 8) {
                                        PhotosPicker(selection: $selectedReviewPhotos, maxSelectionCount: max(1, 9 - reviewPhotoCount), matching: .images) {
                                            Text(reviewPhotoPickerTitle)
                                        }.disabled(editingLocked || reviewMediaUrls.count >= 9)
                                        Button("取消", role: .cancel, action: onClearDraft)
                                            .disabled(submittingReview || uploadingReviewPhotos || reviewStatusLoading || reviewNeedsVerification)
                                    }
                                    ForEach(reviewMediaUrls, id: \.self) { url in
                                        HStack {
                                            Text("已添加评价图片").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                            Spacer()
                                            Button("移除") { onRemoveImage(url) }
                                                .font(.system(size: NativeTypography.size(12))).disabled(editingLocked)
                                        }
                                    }
                                    if let reviewMessage {
                                        Text(reviewMessage).font(.system(size: NativeTypography.size(14)))
                                            .foregroundStyle(reviewNeedsVerification ? .orange : .red)
                                    }
                                    HStack {
                                        if reviewNeedsVerification {
                                            Button("核对评价状态", action: onVerifyReview)
                                                .disabled(submittingReview || uploadingReviewPhotos || reviewStatusLoading)
                                        }
                                        Spacer()
                                        Button(submittingReview ? "正在提交…" : "提交评价") {
                                            onStartReview(itemId)
                                        }
                                        .disabled(editingLocked || reviewContent.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count < 2
                                            || reviewContent.utf16.count > 2000)
                                    }
                                }
                                .padding(10).background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                            } else {
                                Button(pendingReviewItemIds.contains(itemId) ? "核对评价状态" : "评价商品") { onStartDraft(itemId) }
                                    .font(.system(size: NativeTypography.size(14), weight: .semibold))
                                    .disabled(submittingReview || uploadingReviewPhotos || reviewStatusLoading)
                            }
                        } else if reviewStatusLoading {
                            Text("正在读取评价状态…").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                        } else if let reviewStatusError {
                            Text(reviewStatusError).font(.system(size: NativeTypography.size(12))).foregroundStyle(.red)
                            Button("重新读取评价状态", action: onReloadStatus)
                                .font(.system(size: NativeTypography.size(12))).disabled(reviewStatusLoading)
                        }
                    }
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 11))
    }
}
