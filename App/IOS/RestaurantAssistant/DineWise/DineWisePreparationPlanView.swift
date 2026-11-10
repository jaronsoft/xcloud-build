import SwiftUI
import UIKit

private struct DineWisePreparationDraftItem: Identifiable {
    let id = UUID()
    var name = ""
    var unit = "kg"
    var minimum = ""
    var maximum = ""
    var basis = ""

    init() {}

    init(_ item: DineWisePreparationPlanItem) {
        name = item.IngredientName
        unit = item.Unit
        minimum = NSDecimalNumber(decimal: item.MinimumQuantity).stringValue
        maximum = NSDecimalNumber(decimal: item.MaximumQuantity).stringValue
        basis = item.Basis
    }
}

private struct DineWisePurchaseDraftItem: Identifiable {
    let id = UUID()
    var name: String
    var unit: String
    var quantity: String
    var currentStock = ""
    var inTransit = ""
    var reserved = ""
    var inventory = ""
    var supplier = ""
    var packageSpecification = ""
    var quantityReason = ""

    init(_ item: DineWisePreparationPlanItem) {
        name = item.IngredientName; unit = item.Unit; quantity = ""
    }

    init(_ item: DineWisePurchasePlanItem) {
        name = item.IngredientName; unit = item.Unit
        quantity = NSDecimalNumber(decimal: item.OrderQuantity).stringValue
        currentStock = item.CurrentStockQuantity.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        inTransit = item.InTransitQuantity.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        reserved = item.ReservedQuantity.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        inventory = item.InventoryCheck; supplier = item.SupplierName
        packageSpecification = item.PackageSpecification
        quantityReason = item.QuantityReason
    }
}

struct DineWisePreparationPlanView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: DineWiseStore
    let token: String
    let role: String
    let userID: String
    let onRecordPurchase: ((DineWisePurchasePlan) -> Void)?
    let onRecordOutcome: ((DineWisePreparationPlan) -> Void)?
    let onViewOutcomes: ((DineWisePreparationPlan) -> Void)?
    let onViewPurchases: ((DineWisePurchasePlan) -> Void)?

    @State private var tasks: [DineWiseTask] = []
    @State private var hasOlderTasks = false
    @State private var plans: [DineWisePreparationPlan] = []
    @State private var hasOlderPlans = false
    @State private var purchases: [DineWisePurchasePlan] = []
    @State private var hasOlderPurchases = false
    @State private var purchaseEditingID = ""
    @State private var purchaseVersion = 0
    @State private var orderItems: [DineWisePurchaseDraftItem] = []
    @State private var purchaseReason = ""
    @State private var purchasePreview: DineWisePurchaseSuggestionPreview?
    @State private var purchasePreviewSignature = ""
    @State private var taskID = ""
    @State private var editingID = ""
    @State private var version = 0
    @State private var businessDate = ""
    @State private var items = [DineWisePreparationDraftItem()]
    @State private var copiedTemplateDate = ""
    @State private var reason = ""
    @State private var busy = false
    @State private var message = ""
    @State private var messageIsError = false
    @State private var listsLoaded = false
    @State private var listLoadFailed = false
    @State private var pendingSignature = ""
    @State private var pendingKey = ""
    @State private var confirming: DineWisePreparationPlan?
    @State private var showConfirm = false
    @State private var confirmingPurchase: DineWisePurchasePlan?
    @State private var showPurchaseConfirm = false
    @State private var requestGeneration = 0
    private let api = DineWiseAPI()
    private var accent: Color { DineWiseTheme.accent(for: colorScheme) }

    private func purchaseUnavailableMessage(_ reason: String?) -> String {
        switch reason {
        case "reassignment_review":
            return "厨师长改派后尚未复核备菜单，采购核对已暂停；请等待新负责人完成复核后刷新计划。"
        case "source_unavailable":
            return "计划来源已失效或不可用，不能继续使用当前订货明细；请老板确认来源状态，必要时基于新的有效任务重新生成计划。"
        default:
            return "计划来源当前不可用；请刷新并联系老板核对来源状态。"
        }
    }

    private var availableTasks: [DineWiseTask] {
        tasks.filter { task in
            task.TargetRole == "chef" && task.AssignedUserId == userID
                && task.SourceInvalidatedAt == nil
                && ["pending_execution", "in_progress"].contains(task.Status)
                && !plans.contains(where: { $0.TaskId == task.Id && $0.Id != editingID })
        }
    }
    private var copyablePlans: [DineWisePreparationPlan] {
        plans.filter { $0.Status == "confirmed" && !$0.SourceInvalidated
            && $0.WasReassigned != true && !$0.Items.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "basket.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("人工备菜与采购草稿").font(.headline.weight(.bold))
                    Text("备菜范围由厨师长填写，订货量由采购核对")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button("刷新") { load() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .disabled(busy)
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                Text("确认计划不会扣库存或向供应商下单。")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(accent)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(accent.opacity(0.08), in: Capsule())
            if !message.isEmpty {
                Text(message).font(.footnote.weight(.medium))
                    .foregroundStyle(messageIsError ? DineWiseTheme.danger(for: colorScheme) : DineWiseTheme.accent(for: colorScheme))
            }
            if !listsLoaded {
                ProgressView("正在读取备菜与采购计划…").font(.footnote).foregroundStyle(.secondary)
            }
            if role == "chef" { editor }
            if role == "chef" || role == "owner" { preparationList }
            if role == "purchaser" || role == "owner" { purchaseList }
            if role == "purchaser",
               let plan = purchases.first(where: { $0.Id == purchaseEditingID }),
               plan.SourceInvalidated {
                Text(purchaseUnavailableMessage(plan.UnavailableReason))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
            }
            if role == "purchaser",
               let plan = purchases.first(where: { $0.Id == purchaseEditingID }),
               !busy, !listLoadFailed, !plan.SourceInvalidated { purchaseEditor }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .task(id: "\(store.Id):\(token):\(role):\(userID)") {
            requestGeneration += 1; busy = false; message = ""; messageIsError = false
            listsLoaded = false; listLoadFailed = false
            tasks = []; plans = []; purchases = []
            hasOlderTasks = false; hasOlderPlans = false; hasOlderPurchases = false
            resetEditor(); resetPurchaseEditor()
            confirming = nil; confirmingPurchase = nil
            showConfirm = false; showPurchaseConfirm = false
            load()
        }
        .alert("确认备菜单？", isPresented: $showConfirm) {
            Button("确认并生成采购草稿") {
                if let confirming { confirm(confirming) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("采购仍需人工核对。生成草稿不会扣库存或向供应商下单。")
        }
        .confirmationDialog("确认人工订货计划？", isPresented: $showPurchaseConfirm) {
            Button("确认计划") {
                if let confirmingPurchase, canConfirmPurchase(confirmingPurchase) {
                    confirmPurchase(confirmingPurchase)
                }
            }
            .disabled(confirmingPurchase.map { !canConfirmPurchase($0) } ?? true)
        } message: {
            Text("确认计划不会扣库存，也不代表已向供应商下单。")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(editingID.isEmpty ? "新建备菜单" : "逐项修改备菜单").font(.headline)
            if editingID.isEmpty {
                Menu {
                    ForEach(copyablePlans) { plan in
                        Button("\(plan.BusinessDate) · \(plan.Items.count) 项\(plan.WasReassigned == true ? " · 曾改派" : "")") {
                            copyAsNewDraft(plan)
                        }
                    }
                } label: {
                    Label("从已确认备菜单复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(busy || copyablePlans.isEmpty || availableTasks.isEmpty)
                if listsLoaded && !listLoadFailed && availableTasks.isEmpty {
                    Text("暂无尚未建立备菜单的有效已指派任务。")
                        .font(.caption).foregroundStyle(.secondary)
                } else if listsLoaded && !listLoadFailed && copyablePlans.isEmpty {
                    Text("暂无可复制的有效已确认备菜单。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !copiedTemplateDate.isEmpty {
                Label("已带入 \(copiedTemplateDate) 的食材和范围；请填写新营业日与任务，并重新核对数量和依据。",
                    systemImage: "doc.on.doc")
                    .font(.footnote).foregroundStyle(DineWiseTheme.surfaceGold(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("已指派任务", selection: $taskID) {
                Text("请选择").tag("")
                ForEach(availableTasks) { task in
                    Text(task.Title).tag(task.Id)
                }
            }
            .disabled(!editingID.isEmpty)
            if editingID.isEmpty && hasOlderTasks {
                Button("加载更早的已指派任务") { loadOlderTasks() }
                    .buttonStyle(.bordered).disabled(busy)
            }
            DineWisePlaceholderField("目标营业日 YYYY-MM-DD", isEmpty: businessDate.isEmpty) {
                TextField("", text: $businessDate)
                    .textFieldStyle(.plain)
            }
            ForEach($items) { $item in
                VStack(alignment: .leading, spacing: 7) {
                    Text("备菜项目").font(.subheadline.bold())
                    TextField("食材名称", text: $item.name).textFieldStyle(.roundedBorder)
                    Picker("单位", selection: $item.unit) {
                        Text("公斤").tag("kg")
                        Text("件").tag("piece")
                        Text("份").tag("portion")
                    }
                    HStack {
                        TextField("最少", text: $item.minimum)
                            .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        Text("—")
                        TextField("最多", text: $item.maximum)
                            .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    }
                    TextField("人工依据，例如预订与上周实际消耗", text: $item.basis)
                        .textFieldStyle(.roundedBorder)
                    if items.count > 1 {
                        Button("移除项目") { items.removeAll { $0.id == item.id } }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(9)
                .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            Button("添加项目") { items.append(DineWisePreparationDraftItem()) }
                .buttonStyle(.bordered).disabled(items.count >= 30)
            if !editingID.isEmpty {
                TextField("修改原因", text: $reason, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                Button("取消编辑") { resetEditor() }.buttonStyle(.bordered)
            }
            Text("日期须为有效 YYYY-MM-DD；名称最长 80 字、依据最长 240 字；数量范围为 0 < 最少 ≤ 最多 ≤ 100000，最多三位小数，同一食材与单位不能重复。")
                .font(.footnote).foregroundStyle(.secondary)
            Button(editingID.isEmpty ? "保存人工备菜单" : "保存修改") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(busy || !preparationDraftIsValid)
        }
    }

    private func planSectionHeading(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Capsule().fill(accent).frame(width: 4, height: 18)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
            Text(title).font(.headline.weight(.bold))
        }
        .padding(.top, 4)
    }

    private func planEmptyState(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DineWiseTheme.inset, in: RoundedRectangle(cornerRadius: 14))
    }

    private var preparationList: some View {
        VStack(alignment: .leading, spacing: 9) {
            planSectionHeading("备菜单", symbol: "leaf")
            if listsLoaded && !listLoadFailed && plans.isEmpty {
                planEmptyState("暂无备菜单", detail: role == "owner"
                    ? "厨师长提交备菜计划后，会在这里核对执行状态。"
                    : "收到可执行任务后，可以从这里填写并提交备菜范围。",
                    symbol: "leaf")
            }
            ForEach(plans) { plan in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(plan.BusinessDate) · \(plan.Status == "confirmed" ? "已确认" : "草稿")")
                        .font(.subheadline.bold())
                    Text("来源任务 \(plan.TaskId) · 版本 \(plan.Version)")
                        .font(.caption).foregroundStyle(.secondary)
                    if role == "chef" && plan.WasReassigned == true {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("任务曾改派，请先复核前序备菜内容再执行。")
                                .font(.caption).foregroundStyle(DineWiseTheme.surfaceGold(for: colorScheme))
                            Button("已复核前序备菜内容") { reviewReassignment(plan) }
                                .buttonStyle(.bordered).disabled(busy)
                        }
                    }
                    if plan.SourceInvalidated {
                        Text("来源已失效，备菜数量停止展示。")
                    } else {
                        ForEach(Array(plan.Items.enumerated()), id: \.offset) { _, item in
                            Text("\(item.IngredientName)：\(quantity(item.MinimumQuantity))—\(quantity(item.MaximumQuantity)) \(unitName(item.Unit)) · \(item.Basis)")
                        }
                    }
                    if let purchaseID = plan.PurchasePlanId {
                        Text("采购草稿 \(purchaseID) · 待采购核对")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("关联后厨结果：待核对 \(plan.KitchenOutcomePendingCount) 份 · 已确认 \(plan.KitchenOutcomeConfirmedCount) 份")
                        .font(.caption).foregroundStyle(.secondary)
                    if plan.KitchenOutcomePendingCount + plan.KitchenOutcomeConfirmedCount > 0 {
                        Button(role == "owner" ? "查看关联后厨记录" : "查看本人关联记录") {
                            onViewOutcomes?(plan)
                        }.buttonStyle(.bordered)
                    }
                    if role == "chef" && plan.Status == "confirmed" && !plan.SourceInvalidated
                        && plan.WasReassigned != true {
                        Button("记录剩余或沽清") { onRecordOutcome?(plan) }
                            .buttonStyle(.borderedProminent).disabled(busy)
                    }
                    if role == "chef" && plan.Status == "draft" && !plan.SourceInvalidated {
                        HStack {
                            Button("逐项修改") { edit(plan) }.buttonStyle(.bordered)
                            if plan.WasReassigned != true {
                                Button("确认并生成草稿") {
                                    confirming = plan; showConfirm = true
                                }.buttonStyle(.borderedProminent)
                            }
                        }.disabled(busy)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            if hasOlderPlans {
                Button("加载更早的备菜单") { loadOlderPlans() }
                    .buttonStyle(.bordered).disabled(busy)
            }
        }
    }

    private var purchaseList: some View {
        VStack(alignment: .leading, spacing: 9) {
            planSectionHeading("采购订货计划", symbol: "shippingbox")
            if listsLoaded && !listLoadFailed && purchases.isEmpty {
                planEmptyState("暂无采购草稿", detail: role == "owner"
                    ? "备菜单确认后，采购草稿会显示在这里供采购岗位核对。"
                    : "确认后的备菜单会生成采购草稿，核对后再确认订货计划。",
                    symbol: "shippingbox")
            }
            ForEach(purchases) { plan in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(plan.BusinessDate) · \(plan.Status == "confirmed" ? "计划已确认" : "待采购核对")")
                        .font(.subheadline.bold())
                    Text("来源备菜单 \(plan.PreparationPlanId) · 版本 \(plan.Version)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("关联进货资料：待核对 \(plan.ActualPurchasePendingCount) 份 · 已确认 \(plan.ActualPurchaseConfirmedCount) 份")
                        .font(.caption).foregroundStyle(.secondary)
                    if plan.SourceInvalidated {
                        Text(purchaseUnavailableMessage(plan.UnavailableReason))
                            .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                    } else {
                        ForEach(Array(plan.Items.enumerated()), id: \.offset) { _, item in
                            Text("\(item.IngredientName)：备菜 \(quantity(item.MinimumQuantity))—\(quantity(item.MaximumQuantity)) \(unitName(item.Unit))")
                        }
                        ForEach(Array(plan.OrderItems.enumerated()), id: \.offset) { _, item in
                            Text("\(item.IngredientName)：拟订 \(quantity(item.OrderQuantity)) \(unitName(item.Unit)) · \(item.SupplierName) \(item.PackageSpecification)")
                            if item.CurrentStockQuantity != nil || item.InTransitQuantity != nil
                                || item.ReservedQuantity != nil {
                                Text("库存核对数量：现有 \(item.CurrentStockQuantity.map(quantity) ?? "未记录") · 在途 \(item.InTransitQuantity.map(quantity) ?? "未记录") · 预留 \(item.ReservedQuantity.map(quantity) ?? "未记录") \(unitName(item.Unit))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("库存核对：\(item.InventoryCheck)\(item.QuantityReason.isEmpty ? "" : "；调整原因：\(item.QuantityReason)")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("未扣库存 · 未向供应商下单；实际采购和进货单需另行记录。")
                        .font(.caption).foregroundStyle(.secondary)
                    if role == "purchaser" && plan.Status == "draft" && !plan.SourceInvalidated {
                        if !canConfirmPurchase(plan) {
                            Text("请先核对并保存完整的订货草稿，再确认计划。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button(purchaseEditingID == plan.Id && purchaseVersion != plan.Version
                                ? "载入最新版（放弃未保存内容）" : "核对或修改") {
                                editPurchase(plan)
                            }.buttonStyle(.bordered)
                            if !plan.OrderItems.isEmpty {
                                Button("确认订货计划") {
                                    confirmingPurchase = plan; showPurchaseConfirm = true
                                }.buttonStyle(.borderedProminent)
                                    .disabled(!canConfirmPurchase(plan)
                                        || purchaseEditingID == plan.Id && purchaseVersion != plan.Version)
                            }
                        }.disabled(busy)
                    }
                    if role == "purchaser" && plan.Status == "confirmed" && !plan.SourceInvalidated
                        && plan.OrderItems.contains(where: { $0.OrderQuantity > 0 }) {
                        HStack {
                            Button("复制订货内容") { copyPurchase(plan) }.buttonStyle(.bordered)
                            Button("记录实际进货") { onRecordPurchase?(plan) }
                                .buttonStyle(.borderedProminent)
                        }.disabled(busy)
                    }
                    if plan.ActualPurchasePendingCount + plan.ActualPurchaseConfirmedCount > 0 {
                        Button(role == "owner" ? "查看关联进货资料" : "查看本人关联资料") {
                            onViewPurchases?(plan)
                        }.buttonStyle(.bordered)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            if hasOlderPurchases {
                Button("加载更早的订货计划") { loadOlderPurchases() }
                    .buttonStyle(.bordered).disabled(busy)
            }
        }
    }

    private func purchaseItemsAreValid(_ orderItems: [DineWisePurchasePlanItem],
                                       preparationItems: [DineWisePreparationPlanItem]) -> Bool {
        guard !orderItems.isEmpty, preparationItems.count == orderItems.count else { return false }
        return zip(orderItems, preparationItems).allSatisfy { pair in
            let (item, sourceItem) = pair
            return purchaseItemIsValid(quantity: item.OrderQuantity,
                inventory: item.InventoryCheck, supplier: item.SupplierName,
                packageSpecification: item.PackageSpecification, quantityReason: item.QuantityReason,
                currentStock: item.CurrentStockQuantity.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
                inTransit: item.InTransitQuantity.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
                reserved: item.ReservedQuantity.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
                source: sourceItem)
        }
    }

    private var preparationDraftIsValid: Bool {
        guard !taskID.isEmpty, isValidBusinessDate(businessDate), !items.isEmpty,
              items.count <= 30, reason.utf16.count <= 1000,
              editingID.isEmpty || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        var keys = Set<String>()
        return items.allSatisfy { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let basis = item.basis.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let minimum = Decimal(string: item.minimum, locale: Locale(identifier: "en_US_POSIX")),
                  let maximum = Decimal(string: item.maximum, locale: Locale(identifier: "en_US_POSIX")) else {
                return false
            }
            var minimumToRound = minimum
            var roundedMinimum = Decimal.zero
            NSDecimalRound(&roundedMinimum, &minimumToRound, 3, .plain)
            var maximumToRound = maximum
            var roundedMaximum = Decimal.zero
            NSDecimalRound(&roundedMaximum, &maximumToRound, 3, .plain)
            let key = "\(name.lowercased())\u{0}\(item.unit)"
            return (1...80).contains(name.utf16.count) && (1...240).contains(basis.utf16.count)
                && ["kg", "piece", "portion"].contains(item.unit)
                && minimum > 0 && maximum >= minimum && maximum <= 100000
                && roundedMinimum == minimum && roundedMaximum == maximum
                && keys.insert(key).inserted
        }
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

    private var purchaseEditorHasVersionConflict: Bool {
        guard let source = purchases.first(where: { $0.Id == purchaseEditingID }) else { return false }
        return purchaseVersion != source.Version
    }

    private var purchaseEditorItemsValid: Bool {
        guard let source = purchases.first(where: { $0.Id == purchaseEditingID }) else { return false }
        guard !orderItems.isEmpty, source.Items.count == orderItems.count else { return false }
        return zip(orderItems, source.Items).allSatisfy { pair in
            let (item, sourceItem) = pair
            guard let quantity = Decimal(string: item.quantity, locale: Locale(identifier: "en_US_POSIX"))
            else { return false }
            return purchaseItemIsValid(quantity: quantity, inventory: item.inventory,
                supplier: item.supplier, packageSpecification: item.packageSpecification,
                quantityReason: item.quantityReason, currentStock: item.currentStock,
                inTransit: item.inTransit, reserved: item.reserved, source: sourceItem)
        }
    }

    private var purchaseInventorySignature: String {
        orderItems.map { "\($0.name)|\($0.unit)|\($0.currentStock)|\($0.inTransit)|\($0.reserved)" }
            .joined(separator: "\u{1e}")
    }

    private var purchaseInventoryIsComplete: Bool {
        !orderItems.isEmpty && orderItems.allSatisfy { item in
            [item.currentStock, item.inTransit, item.reserved].allSatisfy { value in
                !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && validOptionalInventoryQuantity(value)
            }
        }
    }

    private func purchaseItemIsValid(quantity: Decimal, inventory: String, supplier: String,
                                     packageSpecification: String, quantityReason: String,
                                     currentStock: String, inTransit: String, reserved: String,
                                     source: DineWisePreparationPlanItem) -> Bool {
        guard quantity >= 0 && quantity <= 100000 else { return false }
        var quantityToRound = quantity
        var roundedQuantity = Decimal.zero
        NSDecimalRound(&roundedQuantity, &quantityToRound, 3, .plain)
        let outsidePreparationRange = quantity < source.MinimumQuantity
            || quantity > source.MaximumQuantity
        return roundedQuantity == quantity
            && [currentStock, inTransit, reserved].allSatisfy(validOptionalInventoryQuantity)
            && !inventory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && inventory.utf16.count <= 240 && supplier.utf16.count <= 120
            && packageSpecification.utf16.count <= 120 && quantityReason.utf16.count <= 240
            && (!outsidePreparationRange
                || !quantityReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (quantity == 0 || !supplier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !packageSpecification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func validOptionalInventoryQuantity(_ value: String) -> Bool {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return true }
        guard let quantity = Decimal(string: input, locale: Locale(identifier: "en_US_POSIX")),
              quantity >= 0 && quantity <= 100000 else { return false }
        var valueToRound = quantity
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &valueToRound, 3, .plain)
        return rounded == quantity
    }

    private func optionalInventoryQuantity(_ value: String) -> Decimal? {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return input.isEmpty ? nil : Decimal(string: input, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func canConfirmPurchase(_ plan: DineWisePurchasePlan) -> Bool {
        plan.Version >= 2 && !plan.SourceInvalidated
            && purchaseItemsAreValid(plan.OrderItems, preparationItems: plan.Items)
    }

    private var purchaseEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("逐项核对订货计划").font(.headline)
            if purchaseEditorHasVersionConflict,
               let latest = purchases.first(where: { $0.Id == purchaseEditingID }) {
                Text("此计划已更新至版本 \(latest.Version)。当前输入尚未同步，保存已停用；可复制需要的内容，再从计划列表载入最新版。")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
            }
            ForEach($orderItems) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    let source = purchases.first { $0.Id == purchaseEditingID }?.Items.first {
                        $0.IngredientName == item.name && $0.Unit == item.unit
                    }
                    Text("\(item.name) · 备菜 \(source.map { quantity($0.MinimumQuantity) } ?? "—")—\(source.map { quantity($0.MaximumQuantity) } ?? "—") \(unitName(item.unit))")
                        .font(.subheadline.bold())
                    TextField("拟订数量，可填 0", text: $item.quantity)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    Text("库存数量按本项单位填写；可以留空保存草稿，但全计划每项的现有、在途和预留数量都填齐后才能试算。")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("现有库存数量", text: $item.currentStock)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    TextField("在途数量", text: $item.inTransit)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    TextField("预留数量", text: $item.reserved)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    TextField("现有、在途和预留库存核对说明", text: $item.inventory, axis: .vertical)
                        .lineLimit(2...3).textFieldStyle(.roundedBorder)
                    TextField("拟选供应商", text: $item.supplier)
                        .textFieldStyle(.roundedBorder)
                    TextField("包装或交付规格", text: $item.packageSpecification)
                        .textFieldStyle(.roundedBorder)
                    TextField("超出备菜范围的原因", text: $item.quantityReason)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(9)
                .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            Button("试算采购范围") { previewPurchase() }
                .buttonStyle(.bordered)
                .disabled(busy || purchaseEditorHasVersionConflict || !purchaseInventoryIsComplete)
            if !purchaseInventoryIsComplete {
                Text("补齐全部食材的库存数量后，才可试算整张采购计划。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let preview = purchasePreview,
               preview.Version == purchaseVersion,
               purchasePreviewSignature == purchaseInventorySignature {
                VStack(alignment: .leading, spacing: 6) {
                    Text("服务端试算 · 仅供人工核对").font(.subheadline.bold())
                    Text(preview.Formula).font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(preview.Items.enumerated()), id: \.offset) { entry in
                        let item = entry.element
                        Text(item.CanCalculate
                            ? "\(item.IngredientName)：可用于本计划 \(item.AvailableForPlanQuantity.map(quantity) ?? "—") \(unitName(item.Unit))；建议补足 \(item.SuggestedMinimumQuantity.map(quantity) ?? "—")—\(item.SuggestedMaximumQuantity.map(quantity) ?? "—") \(unitName(item.Unit))"
                            : "\(item.IngredientName)：现有库存、在途或预留数量未填全，暂不试算")
                            .font(.footnote)
                    }
                    Text(preview.Limitation).font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            TextField("本次核对或修改原因", text: $purchaseReason, axis: .vertical)
                .lineLimit(2...4).textFieldStyle(.roundedBorder)
            Text("订货量须在 0–100000 且最多三位小数；超出备菜范围需填写原因，正数订货须填写供应商和规格。")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("保存核对结果") { savePurchase() }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || purchaseReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || purchaseReason.utf16.count > 1000 || !purchaseEditorItemsValid
                        || purchaseEditorHasVersionConflict)
                Button("取消") { resetPurchaseEditor() }.buttonStyle(.bordered)
            }
        }
    }

    private func unitName(_ unit: String) -> String {
        ["kg": "公斤", "piece": "件", "portion": "份"][unit] ?? unit
    }

    private func quantity(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func edit(_ plan: DineWisePreparationPlan) {
        editingID = plan.Id; taskID = plan.TaskId; version = plan.Version
        businessDate = plan.BusinessDate
        items = plan.Items.map(DineWisePreparationDraftItem.init)
        copiedTemplateDate = ""
        reason = ""; pendingSignature = ""; pendingKey = ""
    }

    private func copyAsNewDraft(_ plan: DineWisePreparationPlan) {
        guard role == "chef", plan.Status == "confirmed", !plan.SourceInvalidated,
              !plan.Items.isEmpty, !availableTasks.isEmpty else { return }
        editingID = ""; taskID = ""; version = 0; businessDate = ""
        items = plan.Items.map(DineWisePreparationDraftItem.init)
        copiedTemplateDate = plan.BusinessDate
        reason = ""; pendingSignature = ""; pendingKey = ""
        message = "已复制历史备菜项目；保存前请补充新的任务和营业日并复核数量。"
        messageIsError = false
    }

    private func resetEditor() {
        editingID = ""; taskID = ""; version = 0; businessDate = ""
        items = [DineWisePreparationDraftItem()]; reason = ""
        copiedTemplateDate = ""
        pendingSignature = ""; pendingKey = ""
    }

    private func editPurchase(_ plan: DineWisePurchasePlan) {
        purchaseEditingID = plan.Id; purchaseVersion = plan.Version
        purchasePreview = nil; purchasePreviewSignature = ""
        orderItems = plan.OrderItems.isEmpty
            ? plan.Items.map(DineWisePurchaseDraftItem.init)
            : plan.OrderItems.map(DineWisePurchaseDraftItem.init)
        purchaseReason = ""; pendingSignature = ""; pendingKey = ""
    }

    private func resetPurchaseEditor() {
        purchaseEditingID = ""; purchaseVersion = 0; orderItems = []
        purchaseReason = ""; purchasePreview = nil; purchasePreviewSignature = ""
        pendingSignature = ""; pendingKey = ""
    }

    private func previewPurchase() {
        guard !purchaseEditingID.isEmpty, purchaseInventoryIsComplete else { return }
        let inputs = orderItems.map { item in
            DineWisePurchaseInventoryInput(IngredientName: item.name, Unit: item.unit,
                CurrentStockQuantity: optionalInventoryQuantity(item.currentStock),
                InTransitQuantity: optionalInventoryQuantity(item.inTransit),
                ReservedQuantity: optionalInventoryQuantity(item.reserved))
        }
        let requestedSignature = purchaseInventorySignature
        let storeID = store.Id; let requestToken = token; let requestRole = role
        let requestUserID = userID; let planID = purchaseEditingID; let currentVersion = purchaseVersion
        requestGeneration += 1; let generation = requestGeneration
        busy = true; message = ""; messageIsError = false
        purchasePreview = nil; purchasePreviewSignature = ""
        Task {
            do {
                let result = try await api.previewPurchaseSuggestion(storeID: storeID,
                    planID: planID, token: requestToken, role: requestRole,
                    version: currentVersion, items: inputs)
                if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                    userID: requestUserID, generation: generation),
                   purchaseEditingID == planID, purchaseVersion == currentVersion,
                   purchaseInventorySignature == requestedSignature {
                    if result.Items.count != inputs.count || result.Items.contains(where: { !$0.CanCalculate }) {
                        message = "服务端未返回完整试算结果，请刷新后重试。"
                        messageIsError = true
                    } else {
                        purchasePreview = result; purchasePreviewSignature = requestedSignature
                    }
                }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                    userID: requestUserID, generation: generation) {
                    message = error.localizedDescription; messageIsError = true
                }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                userID: requestUserID, generation: generation) { busy = false }
        }
    }

    private func key(for signature: String) -> String {
        if pendingSignature != signature {
            pendingSignature = signature; pendingKey = UUID().uuidString
        }
        return pendingKey
    }

    private func load(afterWrite successMessage: String? = nil) {
        let storeID = store.Id
        let requestToken = token
        let requestRole = role
        let requestUserID = userID
        requestGeneration += 1
        let generation = requestGeneration
        busy = true; message = ""; messageIsError = false
        Task {
            do {
                if requestRole == "chef" {
                    let nextTasks = try await api.tasks(storeID: storeID, token: requestToken,
                        role: requestRole, preparationAvailable: requestRole == "chef")
                    let nextPlans = try await api.preparationPlans(storeID: storeID,
                        token: requestToken, role: requestRole)
                    if isCurrentRequest(storeID: storeID, token: requestToken,
                        role: requestRole, userID: requestUserID, generation: generation) {
                        tasks = nextTasks; plans = nextPlans
                        hasOlderTasks = nextTasks.count == 100
                        hasOlderPlans = nextPlans.count == 100
                    }
                } else if requestRole == "owner" {
                    let nextPlans = try await api.preparationPlans(storeID: storeID,
                        token: requestToken, role: requestRole)
                    let nextPurchases = try await api.purchasePlans(storeID: storeID,
                        token: requestToken, role: requestRole)
                    if isCurrentRequest(storeID: storeID, token: requestToken,
                        role: requestRole, userID: requestUserID, generation: generation) {
                        plans = nextPlans; purchases = nextPurchases
                        hasOlderPlans = nextPlans.count == 100
                        hasOlderPurchases = nextPurchases.count == 100
                    }
                } else {
                    let nextPurchases = try await api.purchasePlans(storeID: storeID,
                        token: requestToken, role: requestRole)
                    if isCurrentRequest(storeID: storeID, token: requestToken,
                        role: requestRole, userID: requestUserID, generation: generation) {
                        purchases = nextPurchases
                        hasOlderPurchases = nextPurchases.count == 100
                    }
                }
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    role: requestRole, userID: requestUserID, generation: generation) {
                    listsLoaded = true
                    listLoadFailed = false
                }
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    role: requestRole, userID: requestUserID, generation: generation),
                    let successMessage {
                    message = successMessage
                    messageIsError = false
                }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    role: requestRole, userID: requestUserID, generation: generation) {
                    message = successMessage.map {
                        "\($0)，但列表刷新失败：\(error.localizedDescription)"
                    } ?? error.localizedDescription
                    messageIsError = true
                    listsLoaded = true
                    listLoadFailed = true
                }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken,
                role: requestRole, userID: requestUserID, generation: generation) { busy = false }
        }
    }

    private func loadOlderPurchases() {
        guard let cursor = purchases.last?.Id, hasOlderPurchases, !busy else { return }
        let storeID = store.Id
        let requestToken = token
        let requestRole = role
        let requestUserID = userID
        requestGeneration += 1
        let generation = requestGeneration
        busy = true; message = ""; messageIsError = false
        Task {
            do {
                let older = try await api.purchasePlans(storeID: storeID, token: requestToken,
                    role: requestRole, beforeID: cursor)
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    role: requestRole, userID: requestUserID, generation: generation) {
                    let known = Set(purchases.map(\.Id))
                    purchases += older.filter { !known.contains($0.Id) }
                    hasOlderPurchases = older.count == 100
                }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    role: requestRole, userID: requestUserID, generation: generation) {
                    message = error.localizedDescription
                    messageIsError = true
                }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken,
                role: requestRole, userID: requestUserID, generation: generation) { busy = false }
        }
    }

    private func loadOlderPlans() {
        guard let cursor = plans.last?.Id, hasOlderPlans, !busy else { return }
        let storeID = store.Id
        let requestToken = token
        let requestRole = role
        let requestUserID = userID
        requestGeneration += 1
        let generation = requestGeneration
        busy = true; message = ""; messageIsError = false
        Task {
            do {
                let older = try await api.preparationPlans(storeID: storeID, token: requestToken,
                    role: requestRole, beforeID: cursor)
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    role: requestRole, userID: requestUserID, generation: generation) {
                    let known = Set(plans.map(\.Id))
                    plans += older.filter { !known.contains($0.Id) }
                    hasOlderPlans = older.count == 100
                }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    role: requestRole, userID: requestUserID, generation: generation) {
                    message = error.localizedDescription
                    messageIsError = true
                }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken,
                role: requestRole, userID: requestUserID, generation: generation) { busy = false }
        }
    }

    private func loadOlderTasks() {
        guard let cursor = tasks.last?.Id, hasOlderTasks, !busy else { return }
        let storeID = store.Id
        let requestToken = token
        let requestRole = role
        let requestUserID = userID
        requestGeneration += 1
        let generation = requestGeneration
        busy = true; message = ""; messageIsError = false
        Task {
            do {
                let older = try await api.tasks(storeID: storeID, token: requestToken,
                    role: requestRole, beforeID: cursor, preparationAvailable: true)
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    role: requestRole, userID: requestUserID, generation: generation) {
                    guard older.allSatisfy({ $0.StoreId == storeID && $0.Mode == store.Mode }) else {
                        throw DineWiseAPIError.failed("更早任务与当前门店数据范围不匹配，请刷新确认。")
                    }
                    let known = Set(tasks.map(\.Id))
                    tasks += older.filter { !known.contains($0.Id) }
                    hasOlderTasks = older.count == 100
                }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken,
                    role: requestRole, userID: requestUserID, generation: generation) {
                    message = error.localizedDescription
                    messageIsError = true
                }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken,
                role: requestRole, userID: requestUserID, generation: generation) { busy = false }
        }
    }

    private func copyPurchase(_ plan: DineWisePurchasePlan) {
        guard plan.Status == "confirmed" && !plan.SourceInvalidated
            && plan.OrderItems.contains(where: { $0.OrderQuantity > 0 }) else { return }
        UIPasteboard.general.string = purchaseCopyText(plan)
        message = "当前展示的订货计划参考已复制；发送前请核对最新状态。"
        messageIsError = false
    }

    private func purchaseCopyText(_ plan: DineWisePurchasePlan) -> String {
        var lines = ["订货计划参考（尚未下单）", "计划营业日期：\(plan.BusinessDate)"]
        for (index, item) in plan.OrderItems.filter({ $0.OrderQuantity > 0 }).enumerated() {
            var line = "\(index + 1). \(item.IngredientName)：拟订 \(quantity(item.OrderQuantity)) \(unitName(item.Unit))"
            if !item.PackageSpecification.isEmpty { line += "；规格：\(item.PackageSpecification)" }
            if !item.SupplierName.isEmpty { line += "；拟选供应商：\(item.SupplierName)" }
            lines.append(line)
        }
        lines.append("发送前请核对最新计划；复制不代表已下单、付款或扣减库存。")
        return lines.joined(separator: "\n")
    }

    private func save() {
        let normalized = items.compactMap { item -> DineWisePreparationPlanItem? in
            guard let minimum = Decimal(string: item.minimum,
                      locale: Locale(identifier: "en_US_POSIX")),
                  let maximum = Decimal(string: item.maximum,
                      locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            return DineWisePreparationPlanItem(
                IngredientName: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                Unit: item.unit, MinimumQuantity: minimum, MaximumQuantity: maximum,
                Basis: item.basis.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard normalized.count == items.count else { message = "请输入有效的数量。"; messageIsError = true; return }
        let signature = "save:\(editingID):\(taskID):\(businessDate):\(version):\(items.map { "\($0.name):\($0.unit):\($0.minimum):\($0.maximum):\($0.basis)" }.joined(separator: "|")):\(reason)"
        let requestKey = key(for: signature)
        let storeID = store.Id
        let requestToken = token
        let requestRole = role
        let requestUserID = userID
        let requestTaskID = taskID
        let requestDate = businessDate
        let requestVersion = version
        let requestReason = reason
        let requestPlanID = editingID.isEmpty ? nil : editingID
        requestGeneration += 1
        let generation = requestGeneration
        busy = true; message = ""; messageIsError = false
        Task {
            do {
                _ = try await api.savePreparationPlan(storeID: storeID,
                    planID: requestPlanID, token: requestToken, role: requestRole,
                    taskID: requestTaskID, businessDate: requestDate, version: requestVersion,
                    items: normalized, reason: requestReason, idempotencyKey: requestKey)
                if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                    userID: requestUserID, generation: generation) {
                    resetEditor()
                    load(afterWrite: "人工备菜范围已保存；确认前不会生成采购草稿")
                }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                    userID: requestUserID, generation: generation) { message = error.localizedDescription; messageIsError = true }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                userID: requestUserID, generation: generation) { busy = false }
        }
    }

    private func confirm(_ plan: DineWisePreparationPlan) {
        let storeID = store.Id
        let requestToken = token
        let requestRole = role
        let requestUserID = userID
        requestGeneration += 1
        let generation = requestGeneration
        let requestKey = key(for: "confirm:\(plan.Id):\(plan.Version)")
        busy = true; message = ""; messageIsError = false
        Task {
            do {
                _ = try await api.confirmPreparationPlan(storeID: storeID,
                    planID: plan.Id, token: requestToken, role: requestRole,
                    version: plan.Version, idempotencyKey: requestKey)
                if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                    userID: requestUserID, generation: generation) {
                    resetEditor()
                    load(afterWrite: "备菜单已确认，采购待核对草稿已生成")
                }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                    userID: requestUserID, generation: generation) { message = error.localizedDescription; messageIsError = true }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                userID: requestUserID, generation: generation) { busy = false }
        }
    }

    private func reviewReassignment(_ plan: DineWisePreparationPlan) {
        let storeID = store.Id
        let requestToken = token
        let requestRole = role
        let requestUserID = userID
        let signature = "review-reassignment:\(plan.Id):\(plan.Version)"
        let requestKey = key(for: signature)
        requestGeneration += 1
        let generation = requestGeneration
        busy = true; message = ""; messageIsError = false
        Task {
            do {
                _ = try await api.reviewReassignedPreparationPlan(storeID: storeID,
                    planID: plan.Id, token: requestToken, role: requestRole,
                    version: plan.Version, idempotencyKey: requestKey)
                if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                    userID: requestUserID, generation: generation) {
                    pendingSignature = ""; pendingKey = ""
                    load(afterWrite: "已记录复核；如计划再次改派会重新提示。")
                }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                    userID: requestUserID, generation: generation) {
                    message = error.localizedDescription; messageIsError = true
                }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                userID: requestUserID, generation: generation) { busy = false }
        }
    }

    private func savePurchase() {
        let normalized = orderItems.compactMap { item -> DineWisePurchasePlanItem? in
            guard let value = Decimal(string: item.quantity,
                locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            return DineWisePurchasePlanItem(IngredientName: item.name, Unit: item.unit,
                OrderQuantity: value,
                CurrentStockQuantity: optionalInventoryQuantity(item.currentStock),
                InTransitQuantity: optionalInventoryQuantity(item.inTransit),
                ReservedQuantity: optionalInventoryQuantity(item.reserved),
                InventoryCheck: item.inventory,
                SupplierName: item.supplier, PackageSpecification: item.packageSpecification,
                QuantityReason: item.quantityReason)
        }
        guard normalized.count == orderItems.count else {
            message = "请输入有效的拟订数量。"; messageIsError = true; return
        }
        let signature = "purchase:\(purchaseEditingID):\(purchaseVersion):\(orderItems.map { "\($0.name):\($0.unit):\($0.quantity):\($0.currentStock):\($0.inTransit):\($0.reserved):\($0.inventory):\($0.supplier):\($0.packageSpecification):\($0.quantityReason)" }.joined(separator: "|")):\(purchaseReason)"
        let requestKey = key(for: signature)
        let storeID = store.Id
        let requestToken = token
        let requestRole = role
        let requestUserID = userID
        let planID = purchaseEditingID
        let currentVersion = purchaseVersion
        let currentReason = purchaseReason
        requestGeneration += 1
        let generation = requestGeneration
        busy = true; message = ""; messageIsError = false
        Task {
            do {
                _ = try await api.savePurchasePlan(storeID: storeID, planID: planID,
                    token: requestToken, role: requestRole, version: currentVersion, items: normalized,
                    reason: currentReason, idempotencyKey: requestKey)
                if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                    userID: requestUserID, generation: generation) {
                    resetPurchaseEditor()
                    load(afterWrite: "订货计划已保存，确认前仍是待核对草稿")
                }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                    userID: requestUserID, generation: generation) { message = error.localizedDescription; messageIsError = true }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                userID: requestUserID, generation: generation) { busy = false }
        }
    }

    private func confirmPurchase(_ plan: DineWisePurchasePlan) {
        guard canConfirmPurchase(plan) else { return }
        let storeID = store.Id
        let requestToken = token
        let requestRole = role
        let requestUserID = userID
        requestGeneration += 1
        let generation = requestGeneration
        let requestKey = key(for: "purchase-confirm:\(plan.Id):\(plan.Version)")
        busy = true; message = ""; messageIsError = false
        Task {
            do {
                _ = try await api.confirmPurchasePlan(storeID: storeID, planID: plan.Id,
                    token: requestToken, role: requestRole, version: plan.Version,
                    idempotencyKey: requestKey)
                if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                    userID: requestUserID, generation: generation) {
                    resetPurchaseEditor()
                    load(afterWrite: "订货计划已人工确认；实际下单和采购仍需另行记录")
                }
            } catch {
                if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                    userID: requestUserID, generation: generation) { message = error.localizedDescription; messageIsError = true }
            }
            if isCurrentRequest(storeID: storeID, token: requestToken, role: requestRole,
                userID: requestUserID, generation: generation) { busy = false }
        }
    }

    private func isCurrentRequest(storeID: String, token requestToken: String,
                                  role requestRole: String, userID requestUserID: String,
                                  generation: Int) -> Bool {
        store.Id == storeID && token == requestToken && role == requestRole
            && userID == requestUserID && requestGeneration == generation
    }
}
