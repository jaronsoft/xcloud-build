import SwiftUI

private enum DineWiseReportScopeError: LocalizedError {
    case mismatch

    var errorDescription: String? {
        "服务器返回的报告范围与当前选择不匹配，请重新读取。"
    }
}

struct DineWiseDailyReportView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: DineWiseStore
    let token: String
    let userID: String

    @State private var businessDate = ""
    @State private var datePickerDate = Date.now
    @State private var report: DineWiseDailyReport?
    @State private var weekly: DineWiseWeeklyReport?
    @State private var monthly: DineWiseMonthlyReport?
    @State private var calendar: DineWiseWeeklyCalendar?
    @State private var openDaysMask = 127
    @State private var pendingCalendarKey: String?
    @State private var period = "daily"
    @State private var priceScenarioRegion = ""
    @State private var message = ""
    @State private var busy = false
    @State private var focusedSource: DineWiseSubmission?
    @State private var requestGeneration = 0
    private let api = DineWiseAPI()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("经营报告 · 已确认事实").font(.title2.bold())
            Text("选择日期查看日报、自然周或自然月；重复来源不会计入小计。")
                .font(.footnote).foregroundStyle(.secondary)
            Picker("报告期间", selection: $period) {
                Text("日报").tag("daily")
                Text("周阶段摘要").tag("weekly")
                Text("月报").tag("monthly")
            }
            .pickerStyle(.segmented)
            .onChange(of: period) { _, _ in
                requestGeneration += 1; busy = false; report = nil; weekly = nil
                monthly = nil; calendar = nil; focusedSource = nil; pendingCalendarKey = nil
            }
            DineWiseRegionalPriceReferenceView(storeID: store.Id, token: token,
                                               timeZoneID: store.TimeZone)
            HStack(spacing: 8) {
                DineWisePlaceholderField("日期 YYYY-MM-DD", accessibilityLabel: "营业日期 YYYY-MM-DD",
                                         isEmpty: businessDate.isEmpty) {
                    TextField("", text: $businessDate)
                        .textFieldStyle(.plain)
                }
                DineWiseDateTimePickerField(title: "选择日期", selection: $datePickerDate,
                    displayedComponents: .date, calendar: businessCalendar,
                    timeZone: businessTimeZone)
            }
            .onChange(of: datePickerDate) { _, date in
                let selectedDate = formatBusinessDate(date)
                if businessDate != selectedDate { businessDate = selectedDate }
            }
            .onChange(of: businessDate) { _, _ in
                if let date = parseBusinessDate(businessDate) {
                    datePickerDate = date
                }
                requestGeneration += 1; busy = false; report = nil; weekly = nil
                monthly = nil; calendar = nil; focusedSource = nil; pendingCalendarKey = nil
            }
            if period == "monthly" {
                DineWisePlaceholderField("区域参考价地区（选填）", accessibilityLabel: "价格情景地区",
                                         isEmpty: priceScenarioRegion.isEmpty) {
                    TextField("", text: $priceScenarioRegion)
                        .textFieldStyle(.plain)
                        .onChange(of: priceScenarioRegion) { _, _ in
                            requestGeneration += 1; busy = false; monthly = nil
                        }
                }
                Text("仅按当前有效且已核验的同类别、名称、规格和公斤参考价计算；不会自动使用门店地址。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(period == "daily" ? "查看日报" : period == "weekly" ? "查看本周阶段摘要" : "查看本月报告") { load() }
                .buttonStyle(.borderedProminent)
                .disabled(busy || businessDate.isEmpty)
            if !message.isEmpty {
                Text(message).font(.footnote.weight(.medium))
                    .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
            }
            if let report {
                Text("\(report.BusinessDate) · \(report.Mode == "demo" ? "演示数据" : "试用门店")")
                if let snapshot = report.Snapshot {
                    Text(snapshot.Status == "current"
                        ? "已保存版本 \(snapshot.Revision) · \(dineWiseFormatTimestamp(snapshot.GeneratedAtUtc, timeZoneID: store.TimeZone))"
                        : snapshot.InvalidatedReason ?? "上次保存版本的来源已变化，请重新核对。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button(report.Snapshot?.Status == "current" ? "已保存当前日报" : "保存当前日报") {
                    saveDailySnapshot()
                }
                .buttonStyle(.bordered)
                .disabled(busy || report.Snapshot?.Status == "current")
                Text("营业额：\(money(report.RevenueYuan))")
                Text("订单：\(report.Orders.map(String.init) ?? "未核对") · 桌数：\(report.Tables.map(String.init) ?? "未核对")")
                Text("桌均：\(money(report.RevenuePerTableYuan))")
                if let source = report.SourceSubmissionId {
                    Button("打开来源资料 \(source) · 确认版本 \(report.SourceVersion ?? 0)") {
                        openSource(source, expectedVersion: report.SourceVersion,
                                   expectedBusinessDate: report.BusinessDate)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .disabled(busy)
                }
                duplicateSources(report.DuplicateSources, businessDate: report.BusinessDate)
                ForEach(report.MissingReasons, id: \.self) { reason in
                    Text("待补充：\(reason)").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let weekly {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(weekly.WeekStart) 至 \(weekly.WeekEnd) · \(weekly.Mode == "demo" ? "演示数据" : "试用门店")")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                    Text(money(weekly.ConfirmedRevenueSubtotalYuan))
                        .font(.largeTitle.bold()).foregroundStyle(Color(red: 0.91, green: 0.73, blue: 0.38))
                    Text("\(weekly.IsCompleteBusinessWeek ? "完整营业周营业额" : "已确认营业额阶段小计") · 覆盖 \(weekly.RevenueCoveredDays) 天")
                        .font(.subheadline.bold()).foregroundStyle(.white)
                    Text("计划营业 \(weekly.ScheduledOpenDays.map(String.init) ?? "未配置") 天 · 已过待补 \(weekly.MissingOpenDays.map(String.init) ?? "—") 天 · 尚未结束 \(weekly.PendingOpenDays.map(String.init) ?? "—") 天 · 休息日冲突 \(weekly.ClosedSourceDays.map(String.init) ?? "—") 天")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color(red: 0.10, green: 0.17, blue: 0.19), in: RoundedRectangle(cornerRadius: 18))
                if let calendar {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("本周营业安排 · \(calendar.Configured ? "版本 \(calendar.Version)" : "未配置")")
                            .font(.headline)
                        Text("未确认的周安排按门店常规时段预填，请按本周实际情况核对后确认。未设置常规时段时，请手动勾选营业日。要设置下周，请在上方输入下周任一天日期。")
                            .font(.footnote).foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 8) {
                            ForEach(0..<7, id: \.self) { index in
                                Button(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][index]) {
                                    openDaysMask ^= 1 << index
                                    pendingCalendarKey = nil
                                }
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle((openDaysMask & (1 << index)) != 0
                                    ? Color.white : Color.primary)
                                .background((openDaysMask & (1 << index)) != 0
                                    ? Color(red: 0.07, green: 0.36, blue: 0.25) : DineWiseTheme.card,
                                    in: RoundedRectangle(cornerRadius: 9))
                                .disabled(!calendar.CanEdit || busy)
                            }
                        }
                        if calendar.CanEdit {
                            Button("确认营业安排") { saveCalendar(calendar) }
                                .buttonStyle(.borderedProminent)
                                .disabled(busy || (calendar.Configured && openDaysMask == calendar.OpenDaysMask))
                        } else {
                            Text("本周已开始，营业安排已锁定。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(DineWiseTheme.inset,
                                in: RoundedRectangle(cornerRadius: 14))
                }
                ForEach(weekly.MissingReasons, id: \.self) { reason in
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(weekly.Days) { day in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("\(day.BusinessDate) · \(day.IsScheduledOpen.map { $0 ? "营业日" : "休息日" } ?? "未配置")")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(day.RevenueYuan.map { money($0) } ?? "营业额未能核对")
                                .font(.subheadline)
                        }
                        Text("已确认来源 \(day.ConfirmedOperatingCount) 份 · 订单 \(day.Orders.map(String.init) ?? "—") · 桌数 \(day.Tables.map(String.init) ?? "—")")
                            .font(.caption).foregroundStyle(.secondary)
                        if let source = day.SourceSubmissionId {
                            Button("打开来源资料 \(source) · 版本 \(day.SourceVersion ?? 0)") {
                                openSource(source, expectedVersion: day.SourceVersion,
                                           expectedBusinessDate: day.BusinessDate)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .disabled(busy)
                        }
                        duplicateSources(day.DuplicateSources, businessDate: day.BusinessDate)
                        ForEach(day.MissingReasons, id: \.self) { reason in
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
                DineWiseWeeklyProblemView(store: store, token: token,
                                          weekStart: weekly.WeekStart)
                    .id("\(store.Id):\(weekly.WeekStart):problems")
            }
            if let monthly {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(monthly.MonthStart) 至 \(monthly.MonthEnd) · \(monthly.Mode == "demo" ? "演示数据" : "试用门店")")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                    if let region = monthly.PriceScenarioRegion {
                        Text("\(region) 当前区域价格情景：将当前有效参考价替换最近实际进价，假设本月销量不变。差额不是本月已发生金额、毛利或利润。")
                            .font(.caption).foregroundStyle(.white.opacity(0.8))
                    }
                    Text(monthly.RevenueCoveredDays == 0 ? "暂无已核对营业额" :
                        money(monthly.CompleteMonthRevenueYuan ?? monthly.ConfirmedRevenueSubtotalYuan))
                        .font(.largeTitle.bold()).foregroundStyle(Color(red: 0.91, green: 0.73, blue: 0.38))
                    Text("\(monthly.IsCompleteBusinessMonth ? "完整经营月营业额" : "已确认营业额阶段小计") · 覆盖 \(monthly.RevenueCoveredDays) 天")
                        .font(.subheadline.bold()).foregroundStyle(.white)
                    Text("营业安排已配置 \(monthly.CalendarConfiguredDays)/\(monthly.Days.count) 天 · 计划营业 \(monthly.ScheduledOpenDays.map(String.init) ?? "未完整配置") 天")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                    Text("已过待补 \(monthly.MissingOpenDays.map(String.init) ?? "—") 天 · 尚未结束 \(monthly.PendingOpenDays.map(String.init) ?? "—") 天 · 休息日冲突 \(monthly.ClosedSourceDays.map(String.init) ?? "—") 天")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color(red: 0.10, green: 0.17, blue: 0.19), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 6) {
                    Text("采购记录金额 · \(monthly.PricedPurchaseSourceCount == 0 ? "暂无可计算金额" : money(monthly.ConfirmedPurchaseAmountSubtotalYuan))")
                        .font(.headline)
                    Text("可计算金额 \(monthly.PricedPurchaseSourceCount)/\(monthly.ConfirmedPurchaseSourceCount) 份 · 同规格单价可比 \(monthly.ComparablePurchasePriceCount) 份")
                        .font(.subheadline)
                    Text("按已确认数量与单价逐条计算；同店同名同规格只与近 90 天内最近的唯一来源比较。均不代表已付款、当期食材耗用或毛利。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 14))
                ForEach(monthly.Purchases) { purchase in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(purchase.BusinessDate) · \(purchase.IngredientName ?? "食材未核对")\(purchase.IngredientSpecification.map { " · \($0)" } ?? "")")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(purchase.PurchaseQuantityUnit == "piece"
                                ? "计件未计金额"
                                : purchase.RecordedAmountYuan.map { money($0) } ?? "金额待核对")
                                .font(.subheadline)
                        }
                        Text(purchase.PurchaseQuantityUnit == "piece"
                            ? "实际进货 \(purchase.PurchaseQuantity.map { NSDecimalNumber(decimal: $0).stringValue } ?? "—") 个 · 未换算为公斤"
                            : purchase.PurchaseQuantityUnit == "kg"
                                ? "数量 \(decimalText(purchase.QuantityKg)) 公斤 · 单价 \(decimalText(purchase.UnitPriceYuanPerKg)) 元/公斤"
                                : "采购数量单位未核对 · 单价 \(decimalText(purchase.UnitPriceYuanPerKg)) 元/公斤")
                            .font(.caption).foregroundStyle(.secondary)
                        if let supplier = purchase.SupplierName {
                            Text("供应商：\(supplier)").font(.caption).foregroundStyle(.secondary)
                        }
                        if let change = purchase.UnitPriceChangeYuanPerKg {
                            Text("同规格进价：上次 ¥\(decimalText(purchase.PreviousUnitPriceYuanPerKg))/公斤 → 本次 ¥\(decimalText(purchase.UnitPriceYuanPerKg))/公斤")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("较 \(purchase.PreviousComparableBusinessDate ?? "—") 同规格进价 \(change >= 0 ? "+" : "")\(decimalText(change)) 元/公斤\(purchase.UnitPriceChangePercent.map { "（\($0 >= 0 ? "+" : "")\(decimalText($0))%）" } ?? "") · 对比来源 \(purchase.PreviousComparableSourceId ?? "—") · 版本 \(purchase.PreviousComparableSourceVersion.map { String($0) } ?? "—")")
                                .font(.caption).foregroundStyle(.secondary)
                            if let previousSupplier = purchase.PreviousComparableSupplierName,
                               previousSupplier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                != purchase.SupplierName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                                Text("上一笔可比采购供应商：\(previousSupplier)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let source = purchase.PreviousComparableSourceId {
                                Button("打开对比来源资料 \(source)") {
                                    openSource(source,
                                        expectedVersion: purchase.PreviousComparableSourceVersion,
                                        expectedBusinessDate: purchase.PreviousComparableBusinessDate)
                                }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .disabled(busy)
                            }
                        }
                        if let note = purchase.PriceComparisonNote {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                        Button("打开来源资料 \(purchase.SourceSubmissionId) · 版本 \(purchase.SourceVersion)") {
                            openSource(purchase.SourceSubmissionId,
                                       expectedVersion: purchase.SourceVersion,
                                       expectedBusinessDate: purchase.BusinessDate)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .disabled(busy)
                        ForEach(purchase.MissingReasons, id: \.self) { reason in
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 12))
                }
                if let dishCosts = monthly.DishCosts, !dishCosts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("逐菜食材成本估算").font(.headline)
                        Text("仅对唯一已确认销量、当日生效的唯一配方版本及近 90 天内最近唯一同规格公斤进价齐备的菜品计算。公式：可用单份用量 ÷（1 − 损耗率）× 最近进价 × 售出份数。此估算不含盘点库存、报损、赠送等，不代表全店耗用、毛利或利润。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(dishCosts) { dish in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(dish.BusinessDate) · \(dish.DishName) · \(channelName(dish.ChannelCode ?? "")) · 配方 \(dish.RecipeVersion ?? "未确定")")
                                    .font(.subheadline.bold())
                                Text(dish.EstimatedIngredientCostYuan.map { "估算食材成本 \(money($0))" } ?? "成本暂不可估算")
                                if monthly.PriceScenarioRegion != nil {
                                    Text(dish.RegionalScenarioCostYuan.map {
                                        "区域参考价情景成本 \(money($0)) · 与最近实际进价差额 \(money(dish.RegionalScenarioImpactYuan))"
                                    } ?? "区域价格情景暂不可计算")
                                    ForEach(dish.RegionalScenarioMissingReasons, id: \.self) { reason in
                                        Text(reason).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Text("售出 \(dish.SoldPortions.map(String.init) ?? "未核对") 份 · 单份估算 \(money(dish.EstimatedIngredientCostPerServingYuan))")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let source = dish.SalesSourceId {
                                    Button("打开销量来源 \(source)") {
                                        openSource(source, expectedVersion: dish.SalesSourceVersion,
                                                   expectedBusinessDate: dish.BusinessDate)
                                    }
                                    .font(.caption).buttonStyle(.bordered).disabled(busy)
                                }
                                duplicateSources(dish.SalesSources, businessDate: dish.BusinessDate)
                                ForEach(dish.RecipeSources) { source in
                                    Button("打开配方来源 \(source.SourceSubmissionId) · 版本 \(source.SourceVersion)") {
                                        openSource(source.SourceSubmissionId,
                                            expectedVersion: source.SourceVersion,
                                            expectedBusinessDate: dish.BusinessDate,
                                            submittedRole: source.SubmittedRole)
                                    }
                                    .font(.caption).buttonStyle(.bordered).disabled(busy)
                                }
                                ForEach(dish.Ingredients) { line in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(line.IngredientName ?? "食材未核对")\(line.IngredientSpecification.map { " · \($0)" } ?? "")")
                                        Text(line.IsPieceQuantity ? "单份计件用量"
                                            : "单份可用量 \(decimalText(line.UsableQuantityKgPerServing)) 公斤 · 损耗 \(decimalText(line.TrimLossPercent))% · 最近进价 \(decimalText(line.UnitPriceYuanPerKg)) 元/公斤")
                                            .font(.caption).foregroundStyle(.secondary)
                                        if let amount = line.EstimatedCostYuan {
                                            Text("该食材估算 \(money(amount)) · 单份 \(money(line.EstimatedCostPerServingYuan))")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        if let reference = line.RegionalPriceReference {
                                            Text("\(reference.RegionName)参考价 \(reference.Category) · \(money(reference.PriceYuan))/\(reference.Unit)")
                                                .font(.caption).foregroundStyle(.secondary)
                                            if let url = reference.SourceUrl, let sourceURL = URL(string: url) {
                                                Link("来源：\(reference.SourceName)", destination: sourceURL)
                                                    .font(.caption)
                                            }
                                        }
                                        if let reason = line.RegionalScenarioMissingReason {
                                            Text(reason).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Button("打开配方行 \(line.RecipeSourceId) · 版本 \(line.RecipeSourceVersion)") {
                                            openSource(line.RecipeSourceId,
                                                expectedVersion: line.RecipeSourceVersion,
                                                expectedBusinessDate: dish.BusinessDate)
                                        }
                                        .font(.caption).buttonStyle(.bordered).disabled(busy)
                                        if let source = line.PurchaseSourceId {
                                            Button("打开进价来源 \(source) · \(line.PurchaseBusinessDate ?? "日期未知")") {
                                                openSource(source,
                                                    expectedVersion: line.PurchaseSourceVersion,
                                                    expectedBusinessDate: line.PurchaseBusinessDate)
                                            }
                                            .font(.caption).buttonStyle(.bordered).disabled(busy)
                                        }
                                        ForEach(line.MissingReasons, id: \.self) { reason in
                                            Text(reason).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(8)
                                    .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 10))
                                }
                                ForEach(dish.MissingReasons, id: \.self) { reason in
                                    Text(reason).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 14))
                }
                if let channels = monthly.Channels, !channels.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("渠道结算对照").font(.headline)
                        Text("仅用已确认资料。估算销售额 = 优惠前成交 − 退款 − 商家承担优惠；再扣抽点和推广费为“扣已列渠道费用后余额”。假设平台承担优惠由平台承担；余额未扣食材及其他成本，不是毛利或利润。仅比较已录入渠道都有唯一完整来源的共同日期，缺失渠道和日期不按零处理。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(channels) { channel in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(channelName(channel.ChannelCode)) · 已确认 \(channel.ConfirmedSourceCount) 份")
                                    .font(.subheadline.bold())
                                Text("唯一完整 \(channel.UniqueCompleteDays) 天 · 重复来源 \(channel.DuplicateDays) 天")
                                    .font(.caption).foregroundStyle(.secondary)
                                if channel.ComparableBusinessDays > 0 {
                                    Text("共同日期 \(channel.ComparableBusinessDays) 天 · 优惠前成交 \(money(channel.ComparableGrossSalesYuan))")
                                    Text("退款 \(money(channel.ComparableRefundsYuan)) · 商家优惠 \(money(channel.ComparableMerchantDiscountYuan)) · 平台优惠 \(money(channel.ComparablePlatformDiscountYuan))")
                                    Text("平台抽点 \(money(channel.ComparableCommissionYuan)) · 推广费 \(money(channel.ComparablePromotionFeeYuan)) · 订单 \(channel.ComparableOrders.map(String.init) ?? "—")")
                                    Text("估算销售额 \(money(channel.ComparableMerchantSalesYuan)) · 扣已列渠道费用后余额 \(money(channel.ComparableAfterChannelFeesYuan))")
                                        .font(.subheadline.bold())
                                } else {
                                    Text("没有可共同核对的日期，暂不汇总渠道对照金额。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(channel.Days) { day in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("\(day.BusinessDate) · 已确认来源 \(day.ConfirmedSourceCount) 份")
                                                .font(.caption.bold())
                                            if day.SourceSubmissionId != nil {
                                                Text("优惠前成交 \(money(day.GrossSalesYuan)) · 退款 \(money(day.RefundsYuan)) · 订单 \(day.Orders.map(String.init) ?? "—")")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            ForEach(day.MissingReasons, id: \.self) { reason in
                                                Text(reason).font(.caption).foregroundStyle(.secondary)
                                            }
                                            duplicateSources(day.DuplicateSources, businessDate: day.BusinessDate)
                                        }
                                        Spacer()
                                        if let source = day.SourceSubmissionId {
                                            Button("来源") {
                                                openSource(source, expectedVersion: day.SourceVersion,
                                                           expectedBusinessDate: day.BusinessDate)
                                            }
                                            .font(.caption)
                                            .buttonStyle(.bordered)
                                            .disabled(busy)
                                        }
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 14))
                }
                ForEach(monthly.MissingReasons, id: \.self) { reason in
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(monthly.Days) { day in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("\(day.BusinessDate) · \(day.IsScheduledOpen.map { $0 ? "营业日" : "休息日" } ?? "营业安排未配置")")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(day.RevenueYuan.map { money($0) } ?? "营业额未能核对")
                                .font(.subheadline)
                        }
                        Text("已确认来源 \(day.ConfirmedOperatingCount) 份 · 订单 \(day.Orders.map(String.init) ?? "—") · 桌数 \(day.Tables.map(String.init) ?? "—")")
                            .font(.caption).foregroundStyle(.secondary)
                        if let source = day.SourceSubmissionId {
                            Button("打开来源资料 \(source) · 版本 \(day.SourceVersion ?? 0)") {
                                openSource(source, expectedVersion: day.SourceVersion,
                                           expectedBusinessDate: day.BusinessDate)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .disabled(busy)
                        }
                        duplicateSources(day.DuplicateSources, businessDate: day.BusinessDate)
                        ForEach(day.MissingReasons, id: \.self) { reason in
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
            }
        }
        .padding()
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: store.Id) { _, _ in
            requestGeneration += 1; busy = false; businessDate = ""; report = nil
            priceScenarioRegion = ""
            datePickerDate = .now
            weekly = nil; monthly = nil; calendar = nil; pendingCalendarKey = nil; message = ""
            focusedSource = nil
        }
        .onChange(of: token) { _, _ in
            requestGeneration += 1; busy = false; businessDate = ""; report = nil
            priceScenarioRegion = ""
            datePickerDate = .now
            weekly = nil; monthly = nil; calendar = nil; pendingCalendarKey = nil; message = ""
            focusedSource = nil
        }
        .sheet(item: $focusedSource) { source in
            DineWiseReviewView(storeID: store.Id, submission: source, token: token,
                timeZone: store.TimeZone, role: "owner", userID: userID) {
                report = nil; weekly = nil; monthly = nil; calendar = nil
                message = "资料已变化，请重新读取报告核对汇总。"
                return true
            }
        }
    }

    @ViewBuilder
    private func duplicateSources(_ sources: [DineWiseReportSourceCandidate]?,
                                  businessDate: String) -> some View {
        if let sources, sources.count > 1 {
            VStack(alignment: .leading, spacing: 7) {
                Text("同日候选来源 · 请逐条核对").font(.subheadline.bold())
                Text("确认错误来源后可填写原因撤回，再重新读取报告；系统不会自动选择或相加。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(sources) { source in
                    Button("\(sourceRole(source.SubmittedRole)) · 来源 \(source.SourceSubmissionId) · 版本 \(source.SourceVersion)") {
                        openSource(source.SourceSubmissionId, expectedVersion: source.SourceVersion,
                                   expectedBusinessDate: businessDate,
                                   submittedRole: source.SubmittedRole)
                    }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(DineWiseTheme.inset,
                        in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func sourceRole(_ role: String) -> String {
        ["owner": "老板", "manager": "店长", "chef": "厨师长", "purchaser": "采购",
         "operator": "门店运营"][role] ?? "门店成员"
    }

    private func parseBusinessDate(_ value: String) -> Date? {
        let formatter = businessDateFormatter()
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
            return nil
        }
        return date
    }

    private func formatBusinessDate(_ date: Date) -> String {
        businessDateFormatter().string(from: date)
    }

    private func businessDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = businessTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    private var businessTimeZone: TimeZone {
        guard let identifier = store.TimeZone,
              let timeZone = TimeZone(identifier: identifier) else { return .gmt }
        return timeZone
    }

    private var businessCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = businessTimeZone
        return calendar
    }

    private func weekEnd(for weekStart: String) -> String? {
        guard let start = parseBusinessDate(weekStart) else { return nil }
        guard let end = businessCalendar.date(byAdding: .day, value: 6, to: start) else { return nil }
        return formatBusinessDate(end)
    }

    private func monthEnd(for monthStart: String) -> String? {
        guard let start = parseBusinessDate(monthStart) else { return nil }
        guard let nextMonth = businessCalendar.date(byAdding: .month, value: 1, to: start),
              let end = businessCalendar.date(byAdding: .day, value: -1, to: nextMonth) else { return nil }
        return formatBusinessDate(end)
    }

    private func openSource(_ sourceID: String, expectedVersion: Int? = nil,
                            expectedBusinessDate: String? = nil, submittedRole: String? = nil) {
        let storeID = store.Id
        let requestToken = token
        let selectedDate = self.businessDate
        let selectedPeriod = period
        requestGeneration += 1
        let generation = requestGeneration
        busy = true; message = ""
        Task {
            do {
                let detail = try await api.submissionDetail(storeID: storeID,
                    submissionID: sourceID, token: requestToken, role: "owner")
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    date: selectedDate, period: selectedPeriod, generation: generation) {
                    let source = detail.Submission
                    if source.Id == sourceID, source.StoreId == storeID,
                       source.Mode == store.Mode, source.Status == "confirmed",
                       expectedVersion == nil || source.Version == expectedVersion,
                       expectedBusinessDate == nil || source.BusinessDate == expectedBusinessDate,
                       submittedRole == nil || source.SubmittedRole == submittedRole {
                        focusedSource = source
                    } else {
                        message = "来源与报告中的门店、数据域、日期、岗位或版本不匹配，请刷新报告。"
                    }
                }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    date: selectedDate, period: selectedPeriod, generation: generation) {
                    message = error.localizedDescription
                }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken,
                date: selectedDate, period: selectedPeriod, generation: generation) { busy = false }
        }
    }

    private func load() {
        let storeID = store.Id
        let requestToken = token
        let date = businessDate
        let requestedPeriod = period
        requestGeneration += 1
        let generation = requestGeneration
        busy = true; message = ""; report = nil; weekly = nil; monthly = nil; calendar = nil; focusedSource = nil
        Task {
            do {
                if requestedPeriod == "weekly" {
                    guard let monday = weekStart(for: date) else {
                        if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                            period: requestedPeriod, generation: generation) {
                            message = "请输入有效的营业日期。"; busy = false
                        }
                        return
                    }
                    let result = try await api.weeklyReport(storeID: storeID,
                        weekStart: monday, token: requestToken)
                    guard result.StoreId == storeID, result.Mode == store.Mode,
                          result.WeekStart == monday,
                          result.WeekEnd == weekEnd(for: monday) else {
                        throw DineWiseReportScopeError.mismatch
                    }
                    if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                        period: requestedPeriod, generation: generation) {
                        weekly = result
                    }
                    let schedule = try await api.weeklyCalendar(storeID: storeID,
                        weekStart: monday, token: requestToken)
                    guard schedule.StoreId == storeID, schedule.Mode == store.Mode,
                          schedule.WeekStart == monday,
                          schedule.WeekEnd == weekEnd(for: monday) else {
                        throw DineWiseReportScopeError.mismatch
                    }
                    if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                        period: requestedPeriod, generation: generation) {
                        calendar = schedule
                        openDaysMask = schedule.Configured ? schedule.OpenDaysMask : schedule.DefaultOpenDaysMask ?? 0
                        pendingCalendarKey = nil
                    }
                } else if requestedPeriod == "monthly" {
                    guard weekStart(for: date) != nil else {
                        if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                            period: requestedPeriod, generation: generation) {
                            message = "请输入有效的营业日期。"; busy = false
                        }
                        return
                    }
                    let selectedRegion = priceScenarioRegion.trimmingCharacters(in: .whitespacesAndNewlines)
                    let result = try await api.monthlyReport(storeID: storeID,
                        month: String(date.prefix(7)), region: selectedRegion.isEmpty ? nil : selectedRegion,
                        token: requestToken)
                    let monthStart = "\(date.prefix(7))-01"
                    guard result.StoreId == storeID, result.Mode == store.Mode,
                          result.MonthStart == monthStart,
                          result.MonthEnd == monthEnd(for: monthStart),
                          result.PriceScenarioRegion == (selectedRegion.isEmpty ? nil : selectedRegion) else {
                        throw DineWiseReportScopeError.mismatch
                    }
                    if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                        period: requestedPeriod, generation: generation) {
                        monthly = result
                    }
                } else {
                    guard parseBusinessDate(date) != nil else {
                        if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                            period: requestedPeriod, generation: generation) {
                            message = "请输入有效的营业日期。"
                            busy = false
                        }
                        return
                    }
                    let result = try await api.dailyReport(storeID: storeID,
                        businessDate: date, token: requestToken)
                    guard result.StoreId == storeID, result.Mode == store.Mode,
                          result.BusinessDate == date else {
                        throw DineWiseReportScopeError.mismatch
                    }
                    if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                        period: requestedPeriod, generation: generation) {
                        report = result
                    }
                }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                    period: requestedPeriod, generation: generation) {
                    message = error.localizedDescription
                }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                period: requestedPeriod, generation: generation) { busy = false }
        }
    }

    private func saveCalendar(_ current: DineWiseWeeklyCalendar) {
        let storeID = store.Id
        let requestToken = token
        let date = businessDate
        let mask = openDaysMask
        requestGeneration += 1
        let generation = requestGeneration
        let key = pendingCalendarKey ?? UUID().uuidString
        pendingCalendarKey = key
        busy = true; message = ""
        Task {
            do {
                let saved = try await api.saveWeeklyCalendar(storeID: storeID,
                    weekStart: current.WeekStart, token: requestToken, mask: mask,
                    version: current.Version, key: key)
                guard saved.StoreId == storeID, saved.Mode == store.Mode,
                      saved.WeekStart == current.WeekStart,
                      saved.WeekEnd == weekEnd(for: current.WeekStart) else {
                    throw DineWiseReportScopeError.mismatch
                }
                let updated = try await api.weeklyReport(storeID: storeID,
                    weekStart: current.WeekStart, token: requestToken)
                guard updated.StoreId == storeID, updated.Mode == store.Mode,
                      updated.WeekStart == current.WeekStart,
                      updated.WeekEnd == weekEnd(for: current.WeekStart) else {
                    throw DineWiseReportScopeError.mismatch
                }
                if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                    period: "weekly", generation: generation) {
                    calendar = saved; weekly = updated; pendingCalendarKey = nil
                }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                    period: "weekly", generation: generation) {
                    message = error.localizedDescription
                }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                period: "weekly", generation: generation) { busy = false }
        }
    }

    private func saveDailySnapshot() {
        guard period == "daily", let current = report,
              current.Snapshot?.Status != "current", !busy else { return }
        let storeID = store.Id
        let requestToken = token
        let date = current.BusinessDate
        requestGeneration += 1
        let generation = requestGeneration
        busy = true; message = ""
        Task {
            do {
                let saved = try await api.saveDailyReportSnapshot(storeID: storeID,
                    businessDate: date, token: requestToken)
                guard saved.StoreId == storeID, saved.Mode == store.Mode,
                      saved.BusinessDate == date, saved.Snapshot?.Status == "current" else {
                    throw DineWiseReportScopeError.mismatch
                }
                if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                    period: "daily", generation: generation) { report = saved }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                    period: "daily", generation: generation) {
                    message = error.localizedDescription
                }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken, date: date,
                period: "daily", generation: generation) { busy = false }
        }
    }

    private func isCurrentRequest(storeID: String, token requestToken: String,
                                  date: String, period requestedPeriod: String,
                                  generation: Int) -> Bool {
        store.Id == storeID && token == requestToken && businessDate == date
            && period == requestedPeriod && requestGeneration == generation
    }

    private func money(_ value: Decimal?) -> String {
        guard let value else { return "不可计算或未核对" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return "¥\(formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—")"
    }

    private func channelName(_ code: String) -> String {
        guard !code.isEmpty else { return "未区分渠道" }
        return switch code {
        case "dine_in": "堂食"
        case "meituan": "美团"
        case "douyin": "抖音"
        case "private_domain": "私域会员"
        case "other": "其他"
        default: code
        }
    }

    private func decimalText(_ value: Decimal?) -> String {
        value.map { NSDecimalNumber(decimal: $0).stringValue } ?? "—"
    }

    private func weekStart(for text: String) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: text) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let daysSinceMonday = (calendar.component(.weekday, from: date) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: date) else { return nil }
        return formatter.string(from: monday)
    }
}
