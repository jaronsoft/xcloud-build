import SwiftUI

struct NativeFeaturePendingView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SessionStore
    let featureId: String
    @State private var status = "PendingConfirmation"
    @State private var loading = true
    @State private var failed = false
    @State private var revision = 0

    private var title: String {
        ["F-TKT-002": "景区门票", "F-TKT-004": "门票核销", "F-TKT-006": "活动报名",
         "F-FNB-002": "餐饮预约", "F-FNB-003": "餐饮排队", "F-FNB-007": "餐饮团购",
         "F-ECOM-003": "商品结算", "F-OPS-012": "平台消费券", "F-OPS-005": "限时促销"][featureId] ?? "服务状态"
    }

    private var statusTitle: String {
        if loading { return "正在读取开放状态" }
        if failed { return "状态暂不可查询" }
        switch status {
        case "Open": return "服务端开关已开启"
        case "Closed": return "暂未开放"
        default: return "待确认开放"
        }
    }

    private var explanation: String {
        if loading { return "正在读取服务端开放状态。" }
        if failed { return "暂时无法读取服务端状态，客户端按未开放处理。请重试。" }
        switch status {
        case "Open": return "服务端开放开关已开启，请返回业务页面继续使用。"
        case "Closed": return "服务端当前关闭该功能；开放后，平台会按实际状态更新入口。"
        default: return "该功能的开放状态尚未配置。功能范围确认并完成服务端配置后，平台会按实际状态开放入口。"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "clock").font(.system(size: NativeTypography.size(36))).foregroundStyle(Brand.primary)
                    .frame(width: 76, height: 76).background(Brand.primary.opacity(0.08), in: Circle())
                Text("服务状态").font(.caption).foregroundStyle(Brand.muted)
                Text(title).font(.title2.bold()).foregroundStyle(Brand.primary)
                Text(statusTitle).font(.subheadline.weight(.semibold)).foregroundStyle(failed ? .red : Brand.primary)
                Text(explanation).font(.system(size: NativeTypography.size(16))).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
                if loading { ProgressView() }
                if failed { Button("重试读取状态") { revision += 1 }.buttonStyle(.borderedProminent).tint(Brand.primary) }
                Button(status == "Open" && !failed ? "返回业务页面" : "返回上一页") { dismiss() }
                    .buttonStyle(.borderedProminent).tint(Brand.primary)
                Spacer(minLength: 0)
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.background)
            .navigationTitle("服务状态").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .task(id: revision) { await load() }
        }
    }

    @MainActor private func load() async {
        loading = true; failed = false
        do {
            guard let value = try await MobileAPI(store: store).get("/api/JHCTIFeatureAccess/GetPublicStatus?featureId=\(featureId)") as? [String: Any],
                  let configured = value["IsConfigured"] as? Bool, let enabled = value["IsEnabled"] as? Bool else {
                throw MobileAPIError.unavailable("开放状态回执无效")
            }
            try Task.checkCancellation()
            status = enabled && configured ? "Open" : configured ? "Closed" : "PendingConfirmation"
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
        guard !Task.isCancelled else { return }
        loading = false
    }
}
