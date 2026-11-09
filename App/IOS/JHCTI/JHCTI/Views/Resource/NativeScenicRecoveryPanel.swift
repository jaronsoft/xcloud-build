import SwiftUI

struct NativeScenicRecoveryPanel: View {
    let pending: Bool
    let legacy: Bool
    let checking: Bool
    let busy: Bool
    let message: String?
    let results: [[String: Any]]
    let reservationStatus: ([String: Any]) -> String
    let onCheck: () -> Void
    let onOpenJourney: () -> Void
    let onRequestClear: () -> Void

    @ViewBuilder var body: some View {
        if pending || legacy || !results.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("预约结果核对").font(.headline)
                Text(message ?? "本机保留了旧预约请求，可核对此景点的本人预约。其他账号或景点的标记会保留。")
                    .font(.caption).foregroundStyle(Brand.muted)
                ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                    Text("\(result["ReservationDate"] as? String ?? "") · \(result["SessionName"] as? String ?? "预约场次") · \(reservationStatus(result))")
                        .font(.subheadline)
                }
                Button(checking ? "正在核对…" : "核对本机原预约", action: onCheck)
                    .disabled(checking || busy)
                Button("查看我的行程", action: onOpenJourney)
                if pending {
                    Button("已核对行程，清理本机索引", action: onRequestClear)
                        .disabled(checking || busy)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12)).padding(.bottom, 12)
        }
    }
}

struct NativeScenicRecoveryConfirmation: View {
    let isPresented: Bool
    let onKeep: () -> Void
    let onConfirmClear: () -> Void

    @ViewBuilder var body: some View {
        if isPresented {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 18) {
                    Text("清理待确认预约索引？").font(.headline)
                    Text("请先核对行程。清理索引不会取消预约，也不会删除其他旧请求；未核对就再次预约可能重复占位。")
                        .font(.subheadline).foregroundStyle(Brand.muted)
                    HStack {
                        Button("保留", action: onKeep).frame(maxWidth: .infinity)
                        Button("确认清理", action: onConfirmClear).frame(maxWidth: .infinity)
                    }
                }
                .padding(24).background(.white, in: RoundedRectangle(cornerRadius: 18)).padding(28)
            }
        }
    }
}
