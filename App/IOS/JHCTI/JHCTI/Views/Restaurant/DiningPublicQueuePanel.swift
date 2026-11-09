import SwiftUI

struct DiningPublicQueuePanel: View {
    let state: String
    let errorMessage: String?
    let session: [String: Any]?
    let entries: [[String: Any]]
    let isAuthenticated: Bool
    @Binding var name: String
    @Binding var phone: String
    @Binding var guestCount: Int
    let isBusy: Bool
    let cancellingEntryID: String
    let onRefresh: () -> Void
    let onRetryEntries: () -> Void
    let onJoin: () -> Void
    let onRequestCancel: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("排队取号").font(.headline).foregroundStyle(Brand.ink)
            Text("查看门店叫号进度，取号和本人记录使用文旅账号。")
                .font(.caption).foregroundStyle(Brand.muted)
            if state != "loading" {
                Button("刷新排队状态", action: onRefresh)
                    .font(.caption).disabled(isBusy)
            }
            if state == "loading" {
                ProgressView("正在读取排队状态…")
            } else if state == "disabled" {
                Text("餐饮排队功能暂未开放，暂不能新取号。")
                    .font(.subheadline).foregroundStyle(Brand.muted)
                if isAuthenticated { myQueueEntries }
            } else if state == "error" {
                Text(errorMessage ?? "排队信息暂时无法读取").font(.caption).foregroundStyle(.red)
                Button("重试读取", action: onRefresh).buttonStyle(.bordered)
            } else if let session {
                let isOpen = session["IsOpen"] as? Bool ?? session["isOpen"] as? Bool ?? false
                Text(isOpen ? "正在接收排队号码" : "当前未开放取号")
                    .font(.subheadline.weight(.semibold))
                Text("当前叫号 \(Self.int(session["CurrentCalledNumber"] ?? session["currentCalledNumber"]).map { String($0) } ?? "—")　·　等待 \(Self.int(session["WaitingCount"] ?? session["waitingCount"]) ?? 0) 组")
                    .font(.caption).foregroundStyle(Brand.muted)
                if isOpen {
                    if !isAuthenticated {
                        Text("登录文旅账号后可取号并查看本人记录。")
                            .font(.caption).foregroundStyle(Brand.muted)
                    } else {
                        TextField("联系人姓名", text: $name).textContentType(.name)
                            .textFieldStyle(.roundedBorder).disabled(isBusy)
                        TextField("联系电话", text: $phone).textContentType(.telephoneNumber)
                            .keyboardType(.phonePad).textFieldStyle(.roundedBorder).disabled(isBusy)
                        Stepper("就餐人数：\(guestCount) 位", value: $guestCount, in: 1...30)
                            .disabled(isBusy)
                        Button(isBusy ? "正在取号…" : "立即取号", action: onJoin)
                            .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(isBusy)
                        Text("每个开放场次每位登录用户仅可持有一个等待或已叫号码。")
                            .font(.caption2).foregroundStyle(Brand.muted)
                        myQueueEntries
                    }
                }
            } else {
                Text("门店当前未开放排队取号。")
                    .font(.subheadline).foregroundStyle(Brand.muted)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var myQueueEntries: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("我的本店排队").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
                Button("重新读取本人记录", action: onRetryEntries)
                    .font(.caption).disabled(isBusy)
            } else if entries.isEmpty {
                Text("暂无本店排队记录").font(.caption).foregroundStyle(Brand.muted)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                let entryID = Self.string(entry["Id"] ?? entry["id"])
                let status = entry["Status"] as? String ?? entry["status"] as? String ?? ""
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Self.int(entry["QueueNumber"] ?? entry["queueNumber"]) ?? 0) 号 · \(Self.queueStatusName(status))")
                        .font(.caption.weight(.semibold))
                    Text("\(String((entry["QueueDate"] as? String ?? entry["queueDate"] as? String ?? "").prefix(10)))　·　\(Self.int(entry["GuestCount"] ?? entry["guestCount"]) ?? 0) 位")
                        .font(.caption2).foregroundStyle(Brand.muted)
                    if let note = entry["HandleNote"] as? String ?? entry["handleNote"] as? String, !note.isEmpty {
                        Text(note).font(.caption2).foregroundStyle(Brand.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(Brand.background, in: RoundedRectangle(cornerRadius: 9))
                if status == "Waiting" {
                    Button(isBusy && cancellingEntryID == entryID ? "正在取消…" : "取消等待号码", role: .destructive) {
                        onRequestCancel(entryID)
                    }
                    .disabled(isBusy)
                }
            }
        }
        .padding(.top, 8)
    }

    private static func string(_ value: Any?) -> String {
        (value as? String) ?? (value as? NSNumber)?.stringValue ?? ""
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? Int) ?? (value as? NSNumber)?.intValue
    }

    private static func queueStatusName(_ status: String) -> String {
        ["Waiting": "等待中", "Called": "已叫号", "Completed": "已完成", "Missed": "已过号", "Cancelled": "已取消"][status] ?? "状态更新中"
    }
}
