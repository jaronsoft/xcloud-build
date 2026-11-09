import SwiftUI
import CoreFoundation

private func nativeMemberLedgerValue(_ row: [String: Any], _ key: String) -> Any? {
    row[key] ?? row[key.prefix(1).lowercased() + key.dropFirst()]
}

func nativeMemberLedgerString(_ row: [String: Any], _ key: String) -> String? {
    nativeMemberLedgerValue(row, key) as? String
}

private func nativeMemberLedgerDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = nativeMemberLedgerBusinessTimeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

private let nativeMemberLedgerBusinessTimeZone =
    TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 60 * 60)!

private struct NativeMemberLedgerPageChangedError: LocalizedError {
    var errorDescription: String? { "账本数据已变化，正在重新读取第一页。" }
}

private var nativeMemberLedgerBusinessCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = nativeMemberLedgerBusinessTimeZone
    return calendar
}

struct NativeMemberLedgerView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "points"
    @State private var entries: [[String: Any]] = []
    @State private var balance = ""
    @State private var debt = "0"
    @State private var levelName = ""
    @State private var benefits: [String] = []
    @State private var levelBenefitVersion: Int?
    @State private var page = 1
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var failedPage: Int?
    @State private var requestSequence = 0
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var revision = 0
    @State private var loadedToken = ""
    @State private var entryType = ""
    @State private var fromDate = Date()
    @State private var toDate = Date()
    @State private var includesFromDate = false
    @State private var includesToDate = false

    private let pageSize = 20
    private let pointTypes: Set<String> = ["ManualEarn", "ManualDeduct", "Reversal", "OrderPaymentReward", "OrderRefundReversal", "OrderRedemption", "OrderRedemptionRefund", "OrderRedemptionRelease", "PointsExpired"]
    private let growthTypes: Set<String> = ["ManualIncrease", "ManualDecrease", "Reversal", "OrderPaymentReward", "OrderRefundReversal"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ledgerTab("积分", value: "points")
                    ledgerTab("成长值", value: "growth")
                }.padding(.horizontal, 16).padding(.vertical, 12)
                let typeOptions: [(String, String)] = kind == "points"
                    ? [("", "全部类型"), ("ManualEarn", "人工发放"), ("ManualDeduct", "人工扣减"), ("OrderPaymentReward", "订单奖励"), ("OrderRefundReversal", "订单退款冲回"), ("OrderRedemption", "积分抵扣"), ("OrderRedemptionRefund", "退款返还"), ("OrderRedemptionRelease", "关单返还"), ("PointsExpired", "积分过期"), ("Reversal", "冲正")]
                    : [("", "全部类型"), ("ManualIncrease", "人工增加"), ("ManualDecrease", "人工扣减"), ("OrderPaymentReward", "订单奖励"), ("OrderRefundReversal", "订单退款冲回"), ("Reversal", "冲正")]
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Menu {
                            ForEach(Array(typeOptions.enumerated()), id: \.offset) { _, option in
                                Button(option.1) { entryType = option.0 }
                            }
                        } label: {
                            Label(typeOptions.first(where: { $0.0 == entryType })?.1 ?? "全部类型", systemImage: "line.3.horizontal.decrease.circle")
                                .font(.system(size: NativeTypography.size(13)))
                        }
                        Toggle("开始", isOn: $includesFromDate).labelsHidden().accessibilityLabel("启用开始日期筛选")
                        DatePicker("开始日期", selection: $fromDate, displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.calendar, nativeMemberLedgerBusinessCalendar)
                            .environment(\.timeZone, nativeMemberLedgerBusinessTimeZone)
                            .disabled(!includesFromDate)
                    }
                    HStack {
                        Toggle("结束", isOn: $includesToDate).labelsHidden().accessibilityLabel("启用结束日期筛选")
                        DatePicker("结束日期", selection: $toDate, displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.calendar, nativeMemberLedgerBusinessCalendar)
                            .environment(\.timeZone, nativeMemberLedgerBusinessTimeZone)
                            .disabled(!includesToDate)
                        Spacer()
                        Button("清空") { entryType = ""; includesFromDate = false; includesToDate = false; applyLedgerFilters() }
                            .disabled(loading)
                        Button("查询") { applyLedgerFilters() }.fontWeight(.semibold).disabled(loading)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 8)
                if kind == "points" {
                    Text("仅 CNY 实付订单参与：每笔订单按实付金额整元向下取整，奖励 1 积分/元，不足 1 元不计；新入账积分满 12 个月到期，历史期初余额不追溯过期。退款按累计比例冲回，返还积分保留原到期日；已过期部分不恢复余额。退款冲回超过余额的部分记为欠额，由后续积分奖励优先抵扣。")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16).padding(.bottom, 10)
                } else {
                    Text("仅 CNY 实付订单参与：每笔订单按实付金额整元向下取整，奖励 1 成长值/元，不足 1 元不计；成长值永久有效，退款按累计比例冲回且可为负，后续奖励先抵扣负余额。等级随余额升降，门槛和权益调整即时生效。")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16).padding(.bottom, 10)
                }
                if !balance.isEmpty {
                    HStack(spacing: 12) {
                        summaryCard(kind == "points" ? "可用积分" : "成长值", value: balance)
                        if kind == "points" { summaryCard("积分欠额", value: debt) }
                    }.padding(.horizontal, 16).padding(.bottom, 10)
                        if kind == "growth", levelName.isEmpty, !loading, error == nil {
                            Text("当前成长值未达到已启用等级门槛")
                                .font(.system(size: NativeTypography.size(13))).foregroundStyle(Brand.muted)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8)
                        }
                    if kind == "growth", !levelName.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("当前等级：\(levelName)").font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
                            if let levelBenefitVersion {
                                Text("权益版本 V\(levelBenefitVersion)").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                            }
                            ForEach(benefits.indices, id: \.self) { index in
                                Text("• \(benefits[index])").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 16).padding(.bottom, 10)
                    }
                }
                if loading && entries.isEmpty { ProgressView("正在读取账本…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if let error, entries.isEmpty {
                    VStack(spacing: 12) {
                        ContentUnavailableView(error, systemImage: "exclamationmark.arrow.circlepath", description: Text("检查登录状态后重试。"))
                        Button("重试第 \(failedPage ?? 1) 页") {
                            let retryPage = failedPage ?? 1
                            loadMoreTask?.cancel()
                            loadMoreTask = Task { await load(reset: retryPage == 1, pageOverride: retryPage) }
                        }.disabled(loading)
                    }
                } else if entries.isEmpty {
                    ContentUnavailableView("暂无账本流水", systemImage: "list.bullet.rectangle", description: Text("订单奖励和权益变更会记录在这里。"))
                } else {
                    List {
                        ForEach(entries.indices, id: \.self) { index in entryCard(entries[index])
                            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                            .listRowSeparator(.hidden).listRowBackground(Brand.background)
                        }
                        if entries.count < total && error == nil {
                            Button(loading ? "正在加载…" : "加载更多") {
                                loadMoreTask?.cancel()
                                loadMoreTask = Task { await load(reset: false) }
                            }
                                .frame(maxWidth: .infinity).listRowBackground(Brand.background).disabled(loading)
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden).background(Brand.background)
                        .refreshable {
                            loadMoreTask?.cancel(); loadMoreTask = nil
                            await load(reset: true)
                        }
                }
                if let error, !entries.isEmpty {
                    VStack(spacing: 4) {
                        Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                        Button("重试第 \(failedPage ?? 1) 页") {
                            let retryPage = failedPage ?? 1
                            loadMoreTask?.cancel()
                            loadMoreTask = Task { await load(reset: retryPage == 1, pageOverride: retryPage) }
                        }.disabled(loading)
                    }.padding(8)
                }
            }
            .background(Brand.background)
            .navigationTitle("积分与成长值").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .task(id: "\(store.session?.accessToken ?? "")-\(kind)-\(revision)") { await load(reset: true) }
            .onChange(of: store.session?.accessToken) { _, token in
                requestSequence += 1; loadMoreTask?.cancel(); loadMoreTask = nil
                entries = []; balance = ""; debt = "0"; levelName = ""; levelBenefitVersion = nil; benefits = []; total = 0; page = 1
                loadedToken = token ?? ""; loading = false; error = token == nil ? "请先登录文旅账号。" : nil
            }
            .onDisappear {
                requestSequence += 1; loadMoreTask?.cancel(); loadMoreTask = nil
                entries = []; balance = ""; debt = "0"; levelName = ""; levelBenefitVersion = nil; benefits = []
                total = 0; page = 1; loadedToken = ""; loading = false; error = nil
            }
        }
    }

    private func ledgerTab(_ title: String, value: String) -> some View {
        Button {
            if kind != value {
                requestSequence += 1; loadMoreTask?.cancel(); loadMoreTask = nil
                loading = false; error = nil; balance = ""; debt = "0"; levelName = ""; levelBenefitVersion = nil; benefits = []
                kind = value; entryType = ""; page = 1; entries = []; revision += 1
            }
        } label: {
            Text(title).font(.system(size: NativeTypography.size(14), weight: .semibold))
                .foregroundStyle(kind == value ? .white : Brand.primary)
                .padding(.horizontal, 20).padding(.vertical, 9)
                .background(kind == value ? Brand.primary : .white, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func summaryCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            Text(value).font(.system(size: NativeTypography.size(20), weight: .bold)).foregroundStyle(Brand.primary).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
    }

    private func entryCard(_ entry: [String: Any]) -> some View {
        let type = nativeMemberLedgerString(entry, "EntryType") ?? ""
        let change = nativeMemberLedgerString(entry, "ChangeAmount") ?? "0"
        let isPositive = !change.hasPrefix("-")
        let amount = change.hasPrefix("-") ? change : "+\(change)"
        let reason = nativeMemberLedgerString(entry, "Reason") ?? "权益账本变更"
        let time = nativeMemberLedgerString(entry, "CreateTime") ?? "时间待确认"
        let balanceAfter = nativeMemberLedgerString(entry, "BalanceAfter") ?? "0"
        let debtChange = kind == "points" ? (nativeMemberLedgerString(entry, "DebtChange") ?? "0") : "0"
        let debtAfter = kind == "points" ? (nativeMemberLedgerString(entry, "DebtAfter") ?? "0") : "0"
        let expiredPoints = nativeMemberLedgerString(entry, "ExpiredPoints").flatMap(Int64.init) ?? 0
        let expiryTime = kind == "points" ? nativeMemberLedgerString(entry, "ExpiresAt").flatMap {
            bookingBusinessDateTime($0.replacingOccurrences(of: " ", with: "T"))
        } : nil
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(memberLedgerEntryLabel(type)).font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
                Spacer()
                Text(amount).font(.system(size: NativeTypography.size(16), weight: .bold)).foregroundStyle(isPositive ? Brand.primary : .orange)
            }
            Text(reason).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted).fixedSize(horizontal: false, vertical: true)
            if kind == "points", expiredPoints > 0 {
                Text("\(expiredPoints) 分已过期，未恢复到账户")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let expiryTime {
                Text("积分到期时间：\(expiryTime)")
                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(time).font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                Spacer()
            }
            Text("余额 \(balanceAfter)").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            if kind == "points", let parsedDebtChange = Int64(debtChange), let parsedDebtAfter = Int64(debtAfter),
               parsedDebtChange != 0 || parsedDebtAfter > 0 {
                HStack {
                    if parsedDebtChange != 0 {
                        let magnitude = debtChange.hasPrefix("-") ? String(debtChange.dropFirst()) : debtChange
                        Text("欠额\(parsedDebtChange < 0 ? "减少" : "增加") \(magnitude)")
                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(.orange)
                    }
                    Text(parsedDebtAfter > 0 ? "剩余 \(debtAfter)" : "欠额已结清")
                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(parsedDebtAfter > 0 ? .orange : Brand.muted)
                    Spacer(minLength: 0)
                }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
    }

    @MainActor private func load(reset: Bool, pageOverride: Int? = nil) async {
        guard let token = store.session?.accessToken, !token.isEmpty else {
            requestSequence += 1; entries = []; balance = ""; total = 0; error = "请先登录文旅账号，再查看个人账本。"; loading = false; return
        }
        guard let expectedPrincipal = nativeTourismPrincipal(token) else {
            requestSequence += 1; entries = []; error = "登录账号信息无效，请重新登录。"; loading = false; return
        }
        let target = pageOverride ?? (reset ? 1 : page + 1)
        if loadedToken != token { entries = []; page = 1; total = 0; balance = ""; debt = "0"; loadedToken = token }
        if target == 1 { entries = []; total = 0; balance = ""; debt = "0"; levelName = ""; levelBenefitVersion = nil; benefits = [] }
        requestSequence += 1; let sequence = requestSequence; loading = true; error = nil
        failedPage = nil
        var recoverFirstPage = false
        do {
            let endpoint = kind == "points" ? "GetMyPointsLedger" : "GetMyGrowthLedger"
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "page", value: String(target)), URLQueryItem(name: "pageSize", value: String(pageSize)),
                URLQueryItem(name: "entryType", value: entryType),
                URLQueryItem(name: "fromDate", value: includesFromDate ? nativeMemberLedgerDate(fromDate) : ""),
                URLQueryItem(name: "toDate", value: includesToDate ? nativeMemberLedgerDate(toDate) : "")]
            let query = components.percentEncodedQuery ?? "page=\(target)&pageSize=\(pageSize)"
            guard let result = try await MobileAPI(store: store).get("/api/JHCTIMemberProgram/\(endpoint)?\(query)", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any],
                  !Task.isCancelled, store.session?.accessToken == token, requestSequence == sequence else {
                throw MobileAPIError.unavailable("账本回执格式异常，请刷新重试。")
            }
            guard let rawPage = nativeMemberLedgerValue(result, "Page") as? Int,
                  let rawPageSize = nativeMemberLedgerValue(result, "PageSize") as? Int,
                  let rawTotal = nativeMemberLedgerValue(result, "Total") as? Int, rawTotal >= 0 else {
                throw MobileAPIError.unavailable("账本回执格式异常，请刷新重试。")
            }
            if target > max(1, Int(ceil(Double(rawTotal) / Double(pageSize)))) {
                throw NativeMemberLedgerPageChangedError()
            }
            guard rawPage == target, rawPageSize == pageSize,
                  let rows = nativeMemberLedgerValue(result, "Entries") as? [[String: Any]],
                  let expectedRows = nativeReportExpectedRows(page: target, total: rawTotal, pageSize: pageSize),
                  rows.count == expectedRows,
                  let rawBalance = nativeMemberLedgerString(result, "Balance"),
                  let parsedBalance = Int64(rawBalance), kind != "points" || parsedBalance >= 0 else {
                throw MobileAPIError.unavailable("账本回执格式异常，请刷新重试。")
            }
            let rawDebt = nativeMemberLedgerString(result, "Debt")
            if kind == "points", (rawDebt.flatMap(Int64.init).map { $0 >= 0 } != true) {
                throw MobileAPIError.unavailable("积分欠额回执异常，请刷新重试。")
            }
            var parsedLevelBenefitVersion: Int?
            var parsedBenefits: [String] = []
            if kind == "growth" {
                for field in ["CurrentLevelName", "CurrentLevelCode"] {
                    if let value = nativeMemberLedgerValue(result, field), !(value is NSNull), !(value is String) {
                        throw MobileAPIError.unavailable("会员等级回执格式异常，请刷新重试。")
                    }
                }
                if let value = nativeMemberLedgerValue(result, "CurrentLevelId"), !(value is NSNull),
                   (value as? String).flatMap(Int64.init).map({ $0 > 0 }) != true {
                    throw MobileAPIError.unavailable("会员等级编号格式异常，请刷新重试。")
                }
                if let value = nativeMemberLedgerValue(result, "CurrentLevelBenefitVersion"), !(value is NSNull) {
                    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                          number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
                          number.doubleValue > 0, number.doubleValue <= Double(Int32.max) else {
                        throw MobileAPIError.unavailable("会员权益版本格式异常，请刷新重试。")
                    }
                    parsedLevelBenefitVersion = number.intValue
                }
                if let value = nativeMemberLedgerValue(result, "CurrentLevelBenefits"), !(value is NSNull) {
                    guard let items = value as? [String], items.count <= 30, items.allSatisfy({ $0.utf16.count <= 240 }) else {
                        throw MobileAPIError.unavailable("会员权益列表格式异常，请刷新重试。")
                    }
                    parsedBenefits = items
                }
            }
            let allowed = kind == "points" ? pointTypes : growthTypes
            var ids = Set<String>()
            for row in rows {
                let reversedId = nativeMemberLedgerValue(row, "ReversesLedgerId")
                let reversedIdValid = reversedId == nil || reversedId is NSNull || (reversedId as? String).flatMap(Int64.init).map({ $0 > 0 }) == true
                let expiredValue = nativeMemberLedgerValue(row, "ExpiredPoints")
                let expiredPointsValid = kind != "points" || expiredValue == nil || expiredValue is NSNull ||
                    (expiredValue as? String).flatMap(Int64.init).map({ $0 >= 0 }) == true
                let expiryValue = nativeMemberLedgerValue(row, "ExpiresAt")
                let expiryTimeValid = expiryValue == nil || expiryValue is NSNull ||
                    (expiryValue as? String).flatMap { bookingBusinessDateTime($0.replacingOccurrences(of: " ", with: "T")) } != nil
                if let id = nativeMemberLedgerString(row, "Id"), ids.contains(id) {
                    throw NativeMemberLedgerPageChangedError()
                }
                guard let id = nativeMemberLedgerString(row, "Id"), Int64(id).map({ $0 > 0 }) == true, ids.insert(id).inserted,
                      let tenant = nativeMemberLedgerString(row, "TenantId"), tenant == "0" || Int64(tenant).map({ $0 > 0 }) == true,
                      let userId = nativeMemberLedgerString(row, "UserId"), Int64(userId).map({ $0 > 0 }) == true,
                      nativeMemberLedgerString(row, "UserIdentityType") == "Tourism",
                      let entryType = nativeMemberLedgerString(row, "EntryType"), allowed.contains(entryType),
                      let change = nativeMemberLedgerString(row, "ChangeAmount"), Int64(change) != nil,
                      let after = nativeMemberLedgerString(row, "BalanceAfter"), Int64(after) != nil,
                      let reason = nativeMemberLedgerString(row, "Reason"), !reason.isEmpty,
                      nativeMemberLedgerValue(row, "OperatorName") is String, nativeMemberLedgerValue(row, "IsDeleted") as? Bool == false,
                      let createTime = nativeMemberLedgerString(row, "CreateTime"), !createTime.isEmpty,
                      reversedIdValid, expiredPointsValid, expiryTimeValid,
                      (kind != "points" || (nativeMemberLedgerString(row, "DebtChange").flatMap(Int64.init) != nil && nativeMemberLedgerString(row, "DebtAfter").flatMap(Int64.init).map({ $0 >= 0 }) == true)) else {
                    throw MobileAPIError.unavailable("账本流水字段异常，请刷新重试。")
                }
            }
            if target > 1 {
                let loadedIds = Set(entries.compactMap { nativeMemberLedgerString($0, "Id") })
                let receivedIds = rows.compactMap { nativeMemberLedgerString($0, "Id") }
                if target != page + 1 || rawTotal != total || receivedIds.contains(where: { loadedIds.contains($0) }) {
                    throw NativeMemberLedgerPageChangedError()
                }
            }
            balance = rawBalance
            debt = kind == "points" ? rawDebt ?? "0" : "0"
            levelName = kind == "growth" ? (nativeMemberLedgerString(result, "CurrentLevelName") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
            levelBenefitVersion = kind == "growth" ? parsedLevelBenefitVersion : nil
            benefits = kind == "growth" ? parsedBenefits : []
            entries = target == 1 ? rows : entries + rows; total = rawTotal; page = target; failedPage = nil
        } catch {
            if !Task.isCancelled, store.session?.accessToken == token, requestSequence == sequence {
                if target > 1, error is NativeMemberLedgerPageChangedError {
                    entries = []; balance = ""; debt = "0"; total = 0; page = 1
                    levelName = ""; levelBenefitVersion = nil; benefits = []
                    self.error = nil; failedPage = nil; recoverFirstPage = true
                } else {
                    self.error = error.localizedDescription
                    failedPage = target
                }
            }
        }
        if requestSequence == sequence, !Task.isCancelled { loading = false }
        if recoverFirstPage, !Task.isCancelled, store.session?.accessToken == token {
            await load(reset: true)
        }
    }

    private func applyLedgerFilters() {
        guard !includesFromDate || !includesToDate || nativeMemberLedgerBusinessCalendar.startOfDay(for: fromDate) <= nativeMemberLedgerBusinessCalendar.startOfDay(for: toDate) else {
            error = "开始日期不能晚于结束日期。"
            return
        }
        requestSequence += 1; loadMoreTask?.cancel(); loadMoreTask = nil
        page = 1; entries = []; total = 0
        Task { await load(reset: true) }
    }
}

private func memberLedgerEntryLabel(_ type: String) -> String {
    ["ManualEarn": "人工发放", "ManualDeduct": "人工扣减", "ManualIncrease": "人工增加", "ManualDecrease": "人工扣减",
     "OrderPaymentReward": "订单奖励", "OrderRefundReversal": "退款冲回", "OrderRedemption": "订单积分抵扣",
     "OrderRedemptionRefund": "退款返还积分", "OrderRedemptionRelease": "关单返还积分", "PointsExpired": "积分过期", "Reversal": "冲正"][type] ?? "账本变更"
}
