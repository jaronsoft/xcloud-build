import SwiftUI

struct BmbMessage: Decodable, Identifiable {
    let Id: String
    let `Type`: String
    let IsRead: Bool
    let EventCount: Int
    let Available: Bool
    let ShareToken: String?
    let CreateTime: String
    var id: String { Id }
}
struct BmbMessagePage: Decodable { let Items: [BmbMessage]; let Total: Int }
struct BmbUnread: Decodable { let Count: Int }
struct BmbPreferences: Codable {
    var DigestEmail: Bool
    var ResultEmail: Bool
    var ReminderEmail: Bool
    var Language: String
    var TimeZone: String
    var HasEmail: Bool
}
struct BmbFeedback: Decodable, Identifiable {
    let Id: String
    let Body: String
    let Status: String
    var id: String { Id }
}
enum BmbEngagementCopy {
    static func date(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(BmbLanguage.locale))
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(BmbLanguage.locale)) ?? value
    }
    static func text(_ en: String, _ zh: String) -> String { BmbLanguage.code == "zh" ? zh : en }
    static let reasons = [
        "useful": ("Useful", "确实用得上"), "value": ("Good value", "性价比合适"),
        "quality": ("Quality", "看重品质"), "frequent": ("Use it often", "经常会用"),
        "long_term": ("Long-term use", "能用很久"), "expensive": ("Too expensive", "价格偏高"),
        "duplicate": ("Already have similar", "已有类似的"), "wait": ("Wait for now", "建议再等等"),
        "uncertain": ("Not sure I need it", "用途不明确"), "extra_cost": ("Ongoing costs", "后续花费多"),
        "fit": ("Better fit", "更符合需求"), "comfort": ("More comfortable", "更舒适"),
        "design": ("Prefer the design", "更喜欢外观")
    ]
    static func reason(_ code: String) -> String { guard let value = reasons[code] else { return code }; return text(value.0, value.1) }
    static func finalChoice(_ code: String) -> String {
        let values = ["bought": ("Bought", "已购买"), "passed": ("Passed", "已放弃"), "switched": ("Switched", "换了商品"), "waiting": ("Waiting", "暂缓中")]
        guard let value = values[code] else { return code }
        return text(value.0, value.1)
    }
    static func message(_ type: String) -> String {
        let values = ["votes": ("New votes", "有人参与了你的投票"), "comment": ("A new suggestion", "收到新建议"), "offer": ("A new price tip", "收到用户报价"), "target_price": ("A price tip meets your target", "用户报价达到目标价"), "reminder": ("Time to revisit your decision", "到了重新考虑的时间"), "result": ("A followed decision has a result", "关注的决策有结果了"), "public_approved": ("Explore submission approved", "发现页申请已通过"), "public_rejected": ("Explore submission declined", "发现页申请未通过"), "comment_approved": ("Comment approved", "评论已通过"), "comment_rejected": ("Comment declined", "评论未通过"), "offer_approved": ("Price tip approved", "报价已通过"), "offer_rejected": ("Price tip declined", "报价未通过"), "feedback_approved": ("Feedback approved", "结果反馈已通过"), "feedback_rejected": ("Feedback declined", "结果反馈未通过")]
        let value = values[type] ?? ("Decision update", "决策新动态")
        return text(value.0, value.1)
    }
}

struct BmbNotificationsView: View {
    var preferencesOnly = false
    @EnvironmentObject private var session: BmbSession
    @State private var items: [BmbMessage] = []
    @State private var preferences: BmbPreferences?
    @State private var page = 1
    @State private var total = 0
    @State private var error: String?
    @State private var savingPreferences = false
    private func t(_ en: String, _ zh: String) -> String { BmbEngagementCopy.text(en, zh) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("BYEMYBUY COMMUNITY").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                Text(preferencesOnly ? t("Email notifications", "邮件通知") : t("Messages", "消息中心"))
                    .font(.system(size: 31, weight: .black, design: .rounded))
            }
            if !session.isLoggedIn { BmbCard { VStack(alignment: .leading, spacing: 12) {
                Text(t("Sign in to see your updates.", "登录后查看与你有关的消息。"))
                Button(t("Sign in", "登录")) { session.showLogin = true }
                    .font(.subheadline.bold()).padding(.horizontal, 20).frame(height: 44)
                    .background(BmbTheme.lime, in: Capsule())
            } } }
            else {
                if !preferencesOnly {
                    Button(t("Mark all read", "全部已读")) { Task { await read(nil) } }.font(.subheadline.bold())
                    if items.isEmpty { BmbCard { Text(t("No messages yet", "暂无消息")) } }
                    ForEach(items) { item in
                        if item.Available, let token = item.ShareToken {
                            NavigationLink { DecisionView(shareToken: token).task { await read(item.Id) } } label: { BmbCard { messageRow(item) } }
                        } else { Button { Task { await read(item.Id) } } label: { BmbCard { messageRow(item) } } }
                    }
                    HStack {
                        Button(t("Previous", "上一页")) { Task { await load(page - 1) } }.disabled(page == 1)
                        Spacer()
                        Button(t("Next", "下一页")) { Task { await load(page + 1) } }.disabled(page * 20 >= total)
                    }
                }
                if preferences != nil {
                    BmbCard { VStack(alignment: .leading, spacing: 12) { Text(t("Email preferences", "邮件通知设置")).font(.headline)
                        Text(t("Turn off a category to unsubscribe from those emails. In-app messages remain available. The daily digest arrives at 09:00 in your time zone.", "关闭某类邮件即可退订；站内消息仍会保留。互动摘要每天当地时间 09:00 发送。"))
                        if preferences?.HasEmail != true { Text(t("Verify an email in Account first.", "请先在账号中绑定并验证邮箱。")) }
                        Toggle(t("Daily digest", "互动摘要"), isOn: binding(\.DigestEmail)).disabled(preferences?.HasEmail != true)
                        Toggle(t("Followed results", "关注的最终结果"), isOn: binding(\.ResultEmail)).disabled(preferences?.HasEmail != true)
                        Toggle(t("Review reminders", "复看提醒"), isOn: binding(\.ReminderEmail)).disabled(preferences?.HasEmail != true)
                        Picker(t("Language", "邮件语言"), selection: binding(\.Language)) { Text("English").tag("en"); Text("简体中文").tag("zh") }
                        TextField(t("Time zone", "时区"), text: binding(\.TimeZone)).textInputAutocapitalization(.never)
                        Button(t("Use local time zone", "使用本地时区")) { preferences?.TimeZone = TimeZone.current.identifier }
                        Button(savingPreferences ? t("Saving…", "保存中…") : t("Save preferences", "保存设置")) { Task { await save() } }
                            .disabled(savingPreferences)
                    } }
                }
            }
            if let error { Text(error).foregroundStyle(.orange) }
            }.padding(20)
        }.background(BmbTheme.paper).navigationBarHidden(!preferencesOnly)
            .navigationTitle(preferencesOnly ? t("Email notifications", "邮件通知") : "")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: session.token) {
                await session.restoreSession()
                await load()
            }.refreshable {
                await session.restoreSession()
                await load()
            }
    }
    private func binding<T>(_ key: WritableKeyPath<BmbPreferences, T>) -> Binding<T> {
        Binding(get: { preferences![keyPath: key] }, set: { preferences?[keyPath: key] = $0 })
    }
    private func messageRow(_ item: BmbMessage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(item.IsRead ? "" : "● ")\(BmbEngagementCopy.message(item.Type))\(item.EventCount > 1 ? " · \(item.EventCount)" : "")")
            Text(BmbEngagementCopy.date(item.CreateTime)).font(.caption).foregroundStyle(.secondary)
            if !item.Available { Text(t("Content unavailable", "内容已不可访问")).font(.caption) }
        }
    }
    private func load(_ next: Int = 1) async {
        guard let token = session.token else { return }
        do {
            if !preferencesOnly {
                let data: BmbMessagePage = try await session.api.call("/notifications?page=\(next)", token: token)
                items = data.Items; total = data.Total; page = next
            }
            preferences = try await session.api.call("/notifications/preferences", token: token)
        } catch { self.error = error.localizedDescription }
    }
    private func read(_ id: String?) async {
        guard let token = session.token else { return }
        do {
            let _: BmbAcknowledgement = try await session.api.call(id.map { "/notifications/\($0)/read" } ?? "/notifications/read-all", method: "POST", body: [:], token: token)
            await load(page)
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        guard let token = session.token, let p = preferences, !savingPreferences else { return }
        savingPreferences = true
        defer { savingPreferences = false }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/notifications/preferences", method: "PUT", body: ["DigestEmail": p.DigestEmail, "ResultEmail": p.ResultEmail, "ReminderEmail": p.ReminderEmail, "Language": p.Language, "TimeZone": p.TimeZone], token: token)
            error = t("Settings saved", "设置已保存")
        } catch { self.error = error.localizedDescription }
    }
}

struct BmbDecisionTools: View {
    let item: BmbDecision
    let reload: () async -> Void
    @EnvironmentObject private var session: BmbSession
    @State private var date = Date().addingTimeInterval(86400)
    @State private var bodyText = ""
    @State private var selected = "a"
    @State private var message: String?
    private func t(_ en: String, _ zh: String) -> String { BmbEngagementCopy.text(en, zh) }
    var body: some View {
        BmbCard {
            VStack(alignment: .leading, spacing: 14) {
                if item.IsWaiting == true { Text(t("Taking a pause; votes remain open", "暂缓中，继续听听大家的意见")); if let at = item.ReviewAt { Text(BmbEngagementCopy.date(at)).font(.caption) } }
                if !item.IsOwner {
                    BmbActionRow(
                        title: t(item.IsFollowing == true ? "Unfollow result" : "Follow the result",
                                 item.IsFollowing == true ? "取消关注结果" : "关注最终结果"),
                        systemImage: item.IsFollowing == true ? "bell.slash" : "bell",
                        trailingSymbol: item.IsFollowing == true ? "checkmark.circle.fill" : "chevron.right"
                    ) {
                        Task { await send("/follow", method: item.IsFollowing == true ? "DELETE" : "PUT") }
                    }
                }
                if item.IsOwner && (item.Status == "open" || item.FinalChoice == "waiting") {
                    Text(t("Revisit later", "等等再决定")).font(.headline)
                    HStack { ForEach([1,3,7], id: \.self) { days in Button(t("In \(days) days", "\(days) 天后")) { Task { await remind(Date().addingTimeInterval(Double(days) * 86400)) } } } }
                    DatePicker(t("Review time", "复看时间"), selection: $date, in: Date()...)
                    Button(t("Set reminder", "设置提醒")) { Task { await remind(date) } }
                    Button(t("Pause without reminder", "暂缓，不设提醒")) { Task { await remind(nil) } }
                    Button(t("Cancel pause and reminder / Resume", "取消暂缓与提醒 / 恢复征求意见")) { Task { await remind(nil, waiting: false) } }
                    NavigationLink(t("Email reminder settings", "邮件提醒设置")) { BmbNotificationsView() }
                }
                if item.IsOwner && item.Status == "open" {
                    Text(t("Record your final decision", "记录最终决定")).font(.headline)
                    TextField(t("Reason (optional, reviewed before sharing)", "最终理由（可选，审核后展示）"), text: $bodyText, axis: .vertical).textFieldStyle(.roundedBorder)
                    if item.Mode == "pick_one" { Picker(t("Purchased option", "购买选项"), selection: $selected) { Text("A").tag("a"); Text("B").tag("b") }.pickerStyle(.segmented) }
                    HStack { ForEach(["bought","passed","switched"], id: \.self) { choice in
                        Button(LocalizedStringKey(choice == "bought" ? "Bought" : choice == "passed" ? "Passed" : "Switched")) {
                            Task { await send("/final-choice", body: ["Choice": choice, "Reason": bodyText, "SelectedOption": choice == "bought" && item.Mode == "pick_one" ? selected as Any : NSNull()]) }
                        }
                    } }
                }
                ForEach(item.Feedback ?? []) { feedback in Text(feedback.Body); if feedback.Status == "pending" { Text(t("Awaiting review", "等待审核")).font(.caption) } }
                if item.IsOwner && item.Status == "closed" && item.FinalChoice != "waiting" {
                    TextField(t("Share your experience", "补充购买感受或最终理由"), text: $bodyText, axis: .vertical).textFieldStyle(.roundedBorder)
                    Button(t("Submit feedback for review", "提交反馈，等待审核")) { Task { await send("/feedback", body: ["Body": bodyText]) } }.disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            }
        }
    }
    private func remind(_ at: Date?, waiting: Bool = true) async {
        await send("/reminder", method: "PUT", body: ["IsWaiting": waiting, "ReviewAt": at.map { ISO8601DateFormatter().string(from: $0) } as Any? ?? NSNull()])
    }
    private func send(_ path: String, method: String = "POST", body: sending [String: Any]? = nil) async {
        guard let token = session.token else { session.showLogin = true; return }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/d/\(item.ShareToken)\(path)", method: method, body: body, token: token)
            message = t("Saved", "已保存"); await reload()
        } catch { message = error.localizedDescription }
    }
}
