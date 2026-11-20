import SwiftUI

struct ActivityRegistrationConfirmationOverlay: View {
    let pendingDeletion: [String: Any]?
    let pendingCancellation: [String: Any]?
    let deleteBusy: Bool
    let cancelBusy: Bool
    let onKeepDeletion: () -> Void
    let onConfirmDeletion: ([String: Any]) -> Void
    let onKeepCancellation: () -> Void
    let onConfirmCancellation: ([String: Any]) -> Void

    @ViewBuilder var body: some View {
        if let pendingDeletion {
            confirmationOverlay(
                title: "删除过期报名",
                message: "该活动场次已结束，删除后将从报名记录中移除。",
                secondaryTitle: "保留",
                primaryTitle: deleteBusy ? "正在删除…" : "删除",
                primaryDisabled: deleteBusy,
                onBackdropTap: onKeepDeletion,
                onSecondary: onKeepDeletion,
                onPrimary: { onConfirmDeletion(pendingDeletion) }
            )
        } else if let pendingCancellation {
            let rawName = pendingCancellation["ActivityName"] as? String ?? ""
            let activityName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            confirmationOverlay(
                title: "取消活动报名",
                message: "确定取消“\(activityName.isEmpty ? "文旅活动" : activityName)”的报名吗？取消后将按活动规则释放名额。",
                secondaryTitle: "暂不取消",
                primaryTitle: cancelBusy ? "正在取消…" : "确认取消",
                primaryDisabled: cancelBusy,
                onBackdropTap: { if !cancelBusy { onKeepCancellation() } },
                onSecondary: onKeepCancellation,
                onPrimary: { onConfirmCancellation(pendingCancellation) }
            )
        }
    }

    private func confirmationOverlay(title: String, message: String, secondaryTitle: String,
                                     primaryTitle: String, primaryDisabled: Bool,
                                     onBackdropTap: @escaping () -> Void,
                                     onSecondary: @escaping () -> Void,
                                     onPrimary: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.48).ignoresSafeArea().onTapGesture(perform: onBackdropTap)
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: NativeTypography.size(17), weight: .semibold))
                    .foregroundStyle(Color(red: 0.15, green: 0.23, blue: 0.21))
                    .padding(.top, 22)
                Text(message)
                    .font(.system(size: NativeTypography.size(14)))
                    .foregroundStyle(Color(red: 0.54, green: 0.56, blue: 0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22).padding(.vertical, 16)
                Rectangle().fill(Color(red: 0.91, green: 0.92, blue: 0.92)).frame(height: 1)
                HStack(spacing: 0) {
                    Button(secondaryTitle, action: onSecondary)
                        .font(.system(size: NativeTypography.size(15), weight: .medium))
                        .foregroundStyle(Color(red: 0.15, green: 0.23, blue: 0.21))
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .disabled(primaryDisabled)
                    Rectangle().fill(Color(red: 0.91, green: 0.92, blue: 0.92)).frame(width: 1, height: 54)
                    Button(primaryTitle, role: .destructive, action: onPrimary)
                        .font(.system(size: NativeTypography.size(15), weight: .semibold))
                        .foregroundStyle(Color(red: 0.70, green: 0.34, blue: 0.29))
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .disabled(primaryDisabled)
                }
            }
            .frame(maxWidth: 340)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
        }
        .transition(.opacity)
        .zIndex(100)
    }
}
