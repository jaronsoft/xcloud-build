import SwiftUI

struct NativeAccountCancellationView: View {
    @ObservedObject var store: SessionStore
    let expectedPrincipal: String?
    let onCompleted: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""
    @State private var busy = false
    @State private var error: String?

    private var principal: String? { nativeTourismPrincipal(store.session?.accessToken) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("注销文旅账号")
                        .font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif)).foregroundStyle(Brand.ink)
                    Text("注销会立即停用当前账号并撤销全部登录会话。订单和必要审计记录仍按业务及法定要求保留，头像会进入清理队列；如存在已建档人脸资料，将在 30 天内删除。当前规则会保留手机号唯一记录，原手机号暂不能重新注册。注销后无法恢复。")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    Text("输入“注销”确认继续")
                        .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
                    TextField("注销", text: $confirmationText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                    if let error { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red) }
                    Button(role: .destructive) { Task { await cancelAccount() } } label: {
                        HStack { Spacer(); Text(busy ? "正在注销…" : "立即注销"); Spacer() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(busy || confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) != "注销")
                }
                .padding(18)
            }
            .background(Brand.background)
            .navigationTitle("账号管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }.disabled(busy)
                }
            }
            .task(id: principal) {
                confirmationText = ""; error = nil
                if (principal == nil || principal != expectedPrincipal) && !busy { dismiss() }
            }
        }
    }

    @MainActor private func cancelAccount() async {
        guard !busy, confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == "注销",
              let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token),
              principal == requestedPrincipal, requestedPrincipal == expectedPrincipal else {
            error = "请确认仍登录原文旅账号后重试。"
            return
        }
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await MobileAPI(store: store).post(
                "/api/JHCTITourismAuth/CancelMyAccount", body: [:], authenticated: true,
                expectedPrincipal: requestedPrincipal)
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else {
                dismiss()
                return
            }
            store.clear()
            onCompleted("文旅账号已注销；全部登录会话已撤销。")
        } catch {
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else {
                dismiss()
                return
            }
            let statusCode = (error as? MobileAPIError)?.httpStatusCode
            let outcomeUnknown = statusCode.map { !(400...499).contains($0) || $0 == 408 || $0 == 429 } ?? true
            if outcomeUnknown {
                store.clear()
                onCompleted("注销结果暂无法确认，本机已退出该账号。请重新登录核对账号状态；如仍可登录，可再次发起注销。")
            } else {
                self.error = error.localizedDescription
            }
        }
    }
}
