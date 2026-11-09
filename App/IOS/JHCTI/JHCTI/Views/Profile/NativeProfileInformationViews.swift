import SwiftUI

struct AgreementContent: Identifiable {
    let id: String
    let kind: String
    let title: String
    let content: String
}

struct NativeProfileAboutView: View {
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button("‹ 返回个人中心", action: onBack)
                    .font(.system(size: NativeTypography.size(14), weight: .medium))
                    .foregroundStyle(Brand.primary)
                Text("关于悦行江都")
                    .font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif))
                    .foregroundStyle(Brand.ink)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image("Logo").resizable().scaledToFit().frame(width: 52, height: 52)
                        Text("悦行江都")
                            .font(.system(size: NativeTypography.size(18), weight: .semibold))
                            .foregroundStyle(Brand.ink)
                    }
                    Text("发现江都，规划旅程，体验本地文旅生活。")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    Brand.border.frame(height: 1)
                    HStack {
                        Text("当前版本").foregroundStyle(Brand.muted)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                            .foregroundStyle(Brand.ink)
                    }
                    .font(.system(size: NativeTypography.size(14)))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 16).padding(.top, 14)
        }
        .background(Brand.background)
    }
}

struct NativeAgreementContentView: View {
    let agreement: AgreementContent
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(agreement.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(agreement.title)
            .toolbar { Button("关闭", action: onClose) }
        }
    }
}

struct NativeProfileSessionActionsView: View {
    let displayName: String
    let phone: String
    let loggingOut: Bool
    let busy: Bool
    let onLogout: () -> Void
    let onCancelAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(displayName)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.ink)
            Text(phone)
                .font(.system(size: 14)).foregroundStyle(Brand.muted)
            Button(role: .destructive, action: onLogout) {
                HStack(spacing: 7) {
                    if loggingOut { ProgressView().controlSize(.small) }
                    Text(loggingOut ? "正在退出…" : "退出登录")
                        .font(.system(size: NativeTypography.size(16), weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.primary)
            .disabled(loggingOut)
            Button(role: .destructive, action: onCancelAccount) {
                Text("注销文旅账号")
                    .font(.system(size: NativeTypography.size(12), weight: .medium))
                    .padding(.horizontal, 12).frame(minHeight: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(loggingOut || busy)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}
