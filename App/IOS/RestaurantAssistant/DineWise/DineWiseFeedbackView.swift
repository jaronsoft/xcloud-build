import SwiftUI

struct DineWiseFeedbackView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: DineWiseStore
    let token: String
    let role: String
    var onOpenSubmission: ((String) -> Void)? = nil

    @State private var day = ""
    @State private var overview: DineWiseFeedbackOverview?
    @State private var message = ""
    @State private var loading = false
    @State private var loadingMore = false
    @State private var requestVersion = 0
    @State private var selectedCategory = ""
    @State private var selectedStatus = ""
    @State private var selectedSubmitterRole = ""
    private let api = DineWiseAPI()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(role == "owner" ? "门店现场记录" : "现场记录").font(.title2.bold())
                Spacer()
                Button("刷新") { Task { await load(day.isEmpty ? nil : day) } }
                    .disabled(loading || loadingMore)
            }
            Text("只列出当前门店的岗位现场事实；剩余和沽清不自动判定为经营问题，待核对原话不能视为已证实结论。")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                DineWisePlaceholderField("营业日期 YYYY-MM-DD", isEmpty: day.isEmpty) {
                    TextField("", text: Binding(get: { day }, set: updateDay))
                        .textFieldStyle(.plain)
                }
                Button("查询") { Task { await load(day) } }
                    .disabled(loading || loadingMore || day.isEmpty)
            }
            HStack {
                Picker("类别", selection: Binding(get: { selectedCategory }, set: { value in
                    selectedCategory = value
                    Task { await load(day.isEmpty ? nil : day, category: value,
                        status: selectedStatus, submittedRole: selectedSubmitterRole) }
                })) {
                    Text("全部类别").tag("")
                    Text("客诉").tag("complaint")
                    Text("退菜").tag("return")
                    Text("人员").tag("personnel")
                    Text("设备").tag("equipment")
                    Text("其他").tag("other")
                    Text("备菜剩余").tag("leftover")
                    Text("菜品沽清").tag("sold_out")
                }
                .pickerStyle(.menu)
                Picker("核对状态", selection: Binding(get: { selectedStatus }, set: { value in
                    selectedStatus = value
                    Task { await load(day.isEmpty ? nil : day, category: selectedCategory,
                        status: value, submittedRole: selectedSubmitterRole) }
                })) {
                    Text("全部状态").tag("")
                    Text("待核对").tag("pending_review")
                    Text("已确认").tag("confirmed")
                }
                .pickerStyle(.menu)
                Picker("提交岗位", selection: Binding(get: { selectedSubmitterRole }, set: { value in
                    selectedSubmitterRole = value
                    Task { await load(day.isEmpty ? nil : day, category: selectedCategory,
                        status: selectedStatus, submittedRole: value) }
                })) {
                    Text("全部岗位").tag("")
                    Text("老板").tag("owner")
                    Text("店长").tag("manager")
                    Text("厨师长").tag("chef")
                    Text("采购").tag("purchaser")
                    Text("门店运营").tag("operator")
                }
                .pickerStyle(.menu)
            }
            if !message.isEmpty { Text(message).foregroundStyle(DineWiseTheme.danger(for: colorScheme)) }
            if let overview {
                Text("整日汇总：待核对 \(overview.PendingReviewCount) 条 · 已确认 \(overview.ConfirmedCount) 条")
                    .font(.subheadline.weight(.semibold))
                Text("当前筛选匹配 \(overview.FilteredCount ?? overview.PendingReviewCount + overview.ConfirmedCount) 条；筛选只影响下方清单与分页。")
                    .font(.footnote).foregroundStyle(.secondary)
                if !overview.Breakdowns.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("类别与岗位提交统计").font(.subheadline.weight(.semibold))
                        ForEach(overview.Breakdowns) { item in
                            Text("\(categoryName(item.Category)) · \(roleName(item.SubmittedRole)) · \(item.Status == "confirmed" ? "已确认" : "待核对") \(item.Count) 条")
                                .font(.footnote)
                        }
                        Text("仅统计资料条数，不代表问题发生率或个人责任。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if overview.Items.isEmpty {
                    Text(selectedCategory.isEmpty && selectedStatus.isEmpty
                        && selectedSubmitterRole.isEmpty
                        ? "该营业日暂无可见反馈。" : "没有符合当前筛选条件的现场反馈。")
                        .foregroundStyle(.secondary)
                }
                ForEach(overview.Items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(categoryName(item.Category)) · \(item.Status == "confirmed" ? "已确认" : "待核对")")
                            .font(.headline)
                        Text("\(roleName(item.SubmittedRole)) · \(item.OccurredAtUtc.map { dineWiseFormatTimestamp($0, timeZoneID: store.TimeZone) } ?? "发生时间待补") · 来源 #\(item.SubmissionId)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("文字来源：\(dineWiseTextOriginName(item.TextOrigin))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(item.OriginalText)
                        if role == "owner", let onOpenSubmission {
                            Button("查看原始资料") { onOpenSubmission(item.SubmissionId) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                    Divider()
                }
                if overview.HasMore == true, let cursor = overview.NextCursor {
                    Button(loadingMore ? "正在读取…" : "加载更早记录") {
                        Task { await load(day, before: cursor) }
                    }
                    .disabled(loading || loadingMore)
                } else if (overview.FilteredCount ?? overview.PendingReviewCount + overview.ConfirmedCount) > overview.Items.count {
                    Text("当前服务未提供更多记录入口；完整来源可到资料页核对。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .task(id: "\(store.Id):\(token):\(role)") {
            day = ""
            overview = nil
            message = ""
            selectedCategory = ""
            selectedStatus = ""
            selectedSubmitterRole = ""
            await load(nil, category: "", status: "", submittedRole: "")
        }
    }

    @MainActor
    private func load(_ selectedDay: String?, before cursor: String? = nil,
                      category requestedCategory: String? = nil,
                      status requestedStatus: String? = nil,
                      submittedRole requestedSubmitterRole: String? = nil) async {
        requestVersion += 1
        let version = requestVersion
        let requestStoreID = store.Id
        let requestToken = token
        let requestRole = role
        let category = requestedCategory ?? selectedCategory
        let status = requestedStatus ?? selectedStatus
        let submittedRole = requestedSubmitterRole ?? selectedSubmitterRole
        let normalizedDay = selectedDay?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedDay, !isValidBusinessDate(normalizedDay) {
            loading = false
            loadingMore = false
            overview = nil
            message = "请输入有效的营业日期（YYYY-MM-DD）。"
            return
        }
        if cursor == nil {
            loading = true
            loadingMore = false
        } else {
            loadingMore = true
        }
        message = ""
        if cursor == nil { overview = nil }
        defer {
            if version == requestVersion {
                if cursor == nil { loading = false } else { loadingMore = false }
            }
        }
        do {
            let result = try await api.feedback(storeID: requestStoreID, token: requestToken,
                role: requestRole, businessDate: normalizedDay,
                category: category.isEmpty ? nil : category,
                status: status.isEmpty ? nil : status,
                submittedRole: submittedRole.isEmpty ? nil : submittedRole, before: cursor)
            guard !Task.isCancelled, version == requestVersion,
                  store.Id == requestStoreID, token == requestToken,
                  role == requestRole, result.StoreId == requestStoreID else { return }
            if (!category.isEmpty || !status.isEmpty || !submittedRole.isEmpty)
                && result.SupportsListFilters != true {
                message = "当前服务端暂不支持此筛选，请更新服务端后重试。"
                overview = nil
                return
            }
            if cursor == nil {
                overview = result
            } else if let previous = overview {
                overview = DineWiseFeedbackOverview(StoreId: result.StoreId, Mode: result.Mode,
                    BusinessDate: result.BusinessDate, PendingReviewCount: result.PendingReviewCount,
                    ConfirmedCount: result.ConfirmedCount, FilteredCount: result.FilteredCount,
                    SupportsListFilters: result.SupportsListFilters,
                    Breakdowns: result.Breakdowns,
                    Items: previous.Items + result.Items, HasMore: result.HasMore,
                    NextCursor: result.NextCursor)
            }
            day = result.BusinessDate
        } catch is CancellationError { }
        catch {
            if !Task.isCancelled && version == requestVersion
                && store.Id == requestStoreID && token == requestToken && role == requestRole {
                message = error.localizedDescription
            }
        }
    }

    @MainActor
    private func updateDay(_ value: String) {
        requestVersion += 1
        day = value
        overview = nil
        message = ""
        loading = false
        loadingMore = false
    }

    private func isValidBusinessDate(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              !value.hasPrefix("0000") else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    private func categoryName(_ value: String) -> String {
        switch value {
        case "complaint": "客诉"
        case "return": "退菜"
        case "personnel": "人员"
        case "equipment": "设备"
        case "leftover": "备菜剩余"
        case "sold_out": "菜品沽清"
        default: "其他"
        }
    }

    private func roleName(_ value: String) -> String {
        switch value {
        case "manager": "店长"
        case "chef": "厨师长"
        case "operator": "门店运营"
        default: "岗位成员"
        }
    }

}
