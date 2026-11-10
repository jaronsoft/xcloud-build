import SwiftUI

struct DineWiseNoticeView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: DineWiseStore
    let token: String
    let role: String
    let userID: String

    @State private var items: [DineWiseNotice] = []
    @State private var message = ""
    @State private var hasLoaded = false
    @State private var busyNoticeID: String?
    @State private var savedRatings: [String: String] = [:]
    @State private var requestGeneration = 0
    @State private var reloadCount = 0
    private let api = DineWiseAPI()
    private var accent: Color { DineWiseTheme.accent(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("经营提醒").font(.headline.weight(.bold))
                    Text("只展示当前门店已核实且仍有效的信息")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("门店动态")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(accent.opacity(0.08), in: Capsule())
            }
            if !message.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                    Button("重试读取提醒") { reloadCount += 1 }
                        .font(.caption.weight(.semibold))
                }
            }
            if !hasLoaded && message.isEmpty {
                ProgressView("正在读取提醒…").font(.footnote).foregroundStyle(.secondary)
            } else if message.isEmpty && items.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 38, height: 38)
                        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("暂无有效提醒").font(.subheadline.bold())
                        Text("当前门店没有仍在有效期内的核实信息。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(DineWiseTheme.inset, in: RoundedRectangle(cornerRadius: 14))
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 7) {
                            Image(systemName: "bell.fill")
                                .font(.caption2.weight(.semibold))
                            Text(categoryName(item.Category))
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(accent.opacity(0.09), in: Capsule())
                        Spacer(minLength: 0)
                        if item.Mode == "demo" {
                            Text("演示数据").font(.caption2.weight(.semibold))
                                .foregroundStyle(DineWiseTheme.surfaceGold(for: colorScheme))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(DineWiseTheme.gold(for: colorScheme).opacity(0.12), in: Capsule())
                        }
                    }
                    Text(item.TitleZh).font(.subheadline.weight(.bold))
                    Text(item.BodyZh).font(.subheadline)
                    Text("\(item.LocationName) · 来源：\(item.SourceName)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("采集于 \(dineWiseFormatTimestamp(item.ObservedAtUtc, timeZoneID: store.TimeZone))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.VerifiedAtUtc.map {
                        "管理员核实于 \(dineWiseFormatTimestamp($0, timeZoneID: store.TimeZone))"
                    } ?? "核实记录缺失")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("有效至 \(dineWiseFormatTimestamp(item.ExpiresAtUtc, timeZoneID: store.TimeZone))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let source = item.SourceUrl, let url = URL(string: source) {
                        Link("查看来源", destination: url).font(.caption)
                    }
                    if role == "owner" {
                        if let rating = savedRatings[item.Id] ?? item.MyRating {
                            Text("我的反馈：\(ratingName(rating))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            ForEach(["useful", "inaccurate", "handled"], id: \.self) { rating in
                                Button(ratingName(rating)) { sendFeedback(item, rating: rating) }
                                    .buttonStyle(.bordered)
                                    .disabled(busyNoticeID != nil || (savedRatings[item.Id] ?? item.MyRating) == rating)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(DineWiseTheme.inset, in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(accent)
                        .frame(width: 3).padding(.vertical, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.07), lineWidth: 1))
        .task(id: "\(store.Id):\(role):\(token):\(reloadCount)") {
            requestGeneration += 1
            let requestGeneration = requestGeneration
            let requestStoreID = store.Id
            let requestToken = token
            let requestRole = role
            items = []; message = ""; hasLoaded = false; busyNoticeID = nil; savedRatings = [:]
            do {
                let result = try await api.notices(storeID: requestStoreID,
                    token: requestToken, role: requestRole)
                if isCurrentRequest(storeID: requestStoreID, token: requestToken,
                    role: requestRole, generation: requestGeneration) { items = result; hasLoaded = true }
            } catch {
                if isCurrentRequest(storeID: requestStoreID, token: requestToken,
                    role: requestRole, generation: requestGeneration) {
                    message = error.localizedDescription
                    hasLoaded = true
                }
            }
        }
    }

    private func categoryName(_ code: String) -> String {
        ["price": "价格", "weather": "天气", "event": "周边活动", "calendar": "日历"][code] ?? code
    }

    private func ratingName(_ code: String) -> String {
        ["useful": "有用", "inaccurate": "不准", "handled": "已处理"][code] ?? code
    }

    private func sendFeedback(_ item: DineWiseNotice, rating: String) {
        let storeID = store.Id
        let requestToken = token
        let requestRole = role
        requestGeneration += 1
        let generation = requestGeneration
        let retry = pendingWriteRetryKey(
            scope: "\(userID):\(storeID):notice:\(item.Id):feedback",
            payload: ["Version": String(item.Version), "Rating": rating])
        busyNoticeID = item.Id
        message = ""
        Task { @MainActor in
            var feedbackSaved = false
            defer {
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    role: requestRole, generation: generation) { busyNoticeID = nil }
            }
            do {
                try await api.noticeFeedback(storeID: storeID, noticeID: item.Id,
                    token: requestToken, version: item.Version, rating: rating, idempotencyKey: retry.key)
                clearPendingWriteRetryKey(retry)
                feedbackSaved = true
                guard isCurrentRequest(storeID: storeID, token: requestToken,
                    role: requestRole, generation: generation) else { return }
                savedRatings[item.Id] = rating
                let refreshed = try await api.notices(storeID: storeID,
                    token: requestToken, role: requestRole)
                guard isCurrentRequest(storeID: storeID, token: requestToken,
                    role: requestRole, generation: generation) else { return }
                items = refreshed
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    role: requestRole, generation: generation) {
                    message = feedbackSaved
                        ? "反馈已保存，但提醒列表刷新失败；可重试读取提醒。"
                        : error.localizedDescription
                }
            }
        }
    }

    private func isCurrentRequest(storeID: String, token requestToken: String,
                                  role requestRole: String, generation: Int) -> Bool {
        store.Id == storeID && token == requestToken && role == requestRole
            && requestGeneration == generation
    }
}
