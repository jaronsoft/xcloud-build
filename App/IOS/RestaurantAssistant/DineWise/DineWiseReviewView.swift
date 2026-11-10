import SwiftUI
import CryptoKit
import UIKit

private struct DineWiseReviewOption: Identifiable {
    let id: String
    let title: String
    let units: [(String, String)]
}

private struct DineWisePendingReviewRefresh {
    let scopeKey: String
    let action: String
    let reloadDetail: Bool
    let reloadFiles: Bool
}

private struct DineWisePurchaseQuantityComparisonView: View {
    let actual: Decimal
    let planned: Decimal
    let unit: String

    private var summary: String {
        let difference = actual - planned
        guard difference != 0 else { return "与拟订一致" }
        let absoluteDifference = difference > 0 ? difference : -difference
        let differenceText = NSDecimalNumber(decimal: absoluteDifference).stringValue
        let deviationText = percentDeviation(for: difference)
        let direction = difference > 0 ? "多" : "少"
        return "比拟订\(direction) \(differenceText) \(unit)（\(deviationText)%）"
    }

    private func percentDeviation(for difference: Decimal) -> String {
        guard planned > 0 else { return "—" }
        var value = difference / planned * Decimal(100)
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &value, 1, .plain)
        let sign = rounded > 0 ? "+" : ""
        return sign + NSDecimalNumber(decimal: rounded).stringValue
    }

    var body: some View {
        Text("实收 \(NSDecimalNumber(decimal: actual).stringValue) \(unit) · \(summary)")
    }
}

struct DineWiseReviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    let storeID: String
    let submission: DineWiseSubmission
    let token: String
    let timeZone: String?
    let role: String
    let userID: String
    var uploadRevision = 0
    var onFilesChanged: (() async -> Bool)? = nil
    let onChanged: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var detail: DineWiseSubmissionDetail?
    @State private var fieldKey = ""
    @State private var value = ""
    @State private var unit = ""
    @State private var busy = false
    @State private var error = ""
    @State private var showAbandon = false
    @State private var showWithdraw = false
    @State private var withdrawReason = ""
    @State private var showAttachmentImporter = false
    @State private var showAttachmentCamera = false
    @State private var attachAsRecognitionOriginal = false
    @State private var exportDocument: DineWiseAttachmentDocument?
    @State private var exportName = ""
    @State private var showFileExporter = false
    @State private var fileToDelete: DineWiseSubmissionFile?
    @State private var showDeleteAttachment = false
    @State private var showEvents = false
    @State private var events: [DineWiseSubmissionReviewEvent] = []
    @State private var nextEventID: String?
    @State private var eventsBusy = false
    @State private var eventsError = ""
    @State private var eventsGeneration = 0
    @State private var activeScopeKey = ""
    @State private var activeScopeGeneration = 0
    @State private var loadGeneration = 0
    @State private var pendingRefresh: DineWisePendingReviewRefresh?
    @State private var exportScopeKey = ""
    @State private var exportScopeGeneration = 0

    private let api = DineWiseAPI()

    private var jinKilogramPreview: String? {
        guard fieldKey == "purchase_quantity", unit == "jin",
              let quantity = Decimal(string: value.trimmingCharacters(in: .whitespacesAndNewlines),
                                     locale: Locale(identifier: "en_US_POSIX")),
              quantity > 0, quantity <= Decimal(1_000_000) else { return nil }
        var source = quantity
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &source, 3, .plain)
        guard rounded == quantity else { return nil }
        return NSDecimalNumber(decimal: quantity / Decimal(2)).stringValue
    }

    private var requestScopeKey: String {
        "\(storeID)|\(submission.Id)|\(role)|\(userID)|\(token)"
    }

    private var options: [DineWiseReviewOption] {
        switch submission.Kind {
        case "operating": return [
            .init(id: "revenue_yuan", title: "营业额", units: [("yuan", "元")]),
            .init(id: "orders", title: "订单数", units: [("count", "单")]),
            .init(id: "tables", title: "桌数", units: [("count", "桌")])
        ]
        case "channel_settlement": return [
            .init(id: "channel_code", title: "渠道（堂食/美团/抖音/私域会员/其他）", units: [("", "无单位")]),
            .init(id: "gross_sales_yuan", title: "优惠前成交额", units: [("yuan", "元")]),
            .init(id: "refunds_yuan", title: "退款", units: [("yuan", "元")]),
            .init(id: "merchant_discount_yuan", title: "商家承担优惠", units: [("yuan", "元")]),
            .init(id: "platform_discount_yuan", title: "平台承担优惠", units: [("yuan", "元")]),
            .init(id: "commission_yuan", title: "平台抽点", units: [("yuan", "元")]),
            .init(id: "promotion_fee_yuan", title: "推广费", units: [("yuan", "元")]),
            .init(id: "orders", title: "订单数", units: [("count", "单")])
        ]
        case "recipe": return [
            .init(id: "dish_name", title: "菜品名称", units: [("", "无单位")]),
            .init(id: "recipe_version", title: "配方版本（同一版本的各食材行请填写相同值）", units: [("", "无单位")]),
            .init(id: "ingredient_name", title: "食材名称", units: [("", "无单位")]),
            .init(id: "ingredient_category", title: "食材类别（区域价格情景匹配用，可选）", units: [("", "无单位")]),
            .init(id: "ingredient_specification", title: "食材规格（需与采购资料一致）", units: [("", "无单位")]),
            .init(id: "recipe_quantity_per_serving", title: "单份用量", units: [("kg", "公斤"), ("g", "克"), ("jin", "斤"), ("piece", "个")]),
            .init(id: "trim_loss_percent", title: "备料损耗率", units: [("percent", "%")])
        ]
        case "dish_sales": return [
            .init(id: "dish_name", title: "菜品名称", units: [("", "无单位")]),
            .init(id: "sold_portions", title: "售出份数", units: [("portion", "份")]),
            .init(id: "channel_code", title: "渠道（堂食/美团/抖音/私域会员/其他，可选）", units: [("", "无单位")])
        ]
        case "purchase":
            var fields: [DineWiseReviewOption] = [
                .init(id: "ingredient_name", title: "食材名称", units: [("", "无单位")]),
                .init(id: "ingredient_specification", title: "食材规格（用于同规格比价）", units: [("", "无单位")]),
                .init(id: "supplier_name", title: "供应商", units: [("", "无单位")]),
                .init(id: "purchase_quantity", title: "采购数量", units: [("jin", "斤"), ("kg", "公斤"), ("piece", "个")]),
                .init(id: "unit_price_yuan_per_kg", title: "每公斤单价", units: [("yuan/kg", "元/公斤")])
            ]
            if purchaseQuantityUnit == "piece" {
                fields.removeAll { $0.id == "unit_price_yuan_per_kg" }
            }
            return fields
        case "kitchen":
            return [.init(id: "feedback", title: "后厨反馈", units: [("", "无单位")])]
            + (submission.FeedbackCategory == "leftover" ? [
                .init(id: "dish_name", title: "菜品名称", units: [("", "无单位")]),
                .init(id: "outcome_quantity", title: "剩余数量", units: [("portion", "份"),
                    ("piece", "个"), ("kg", "公斤")])
            ] : submission.FeedbackCategory == "sold_out" ? [
                .init(id: "dish_name", title: "菜品名称", units: [("", "无单位")])
            ] : [])
        case "operations": return [.init(id: "feedback", title: "运营反馈", units: [("", "无单位")])]
        default: return []
        }
    }

    private var purchaseQuantityUnit: String? {
        guard let unit = detail?.Fields.first(where: { $0.FieldKey == "purchase_quantity" })?.NormalizedUnit
        else { return nil }
        return unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var required: [String] {
        if let keys = detail?.RequiredFieldKeys { return keys }
        switch submission.Kind {
        case "operating": return ["revenue_yuan"]
        case "channel_settlement": return ["channel_code", "gross_sales_yuan", "refunds_yuan",
            "merchant_discount_yuan", "platform_discount_yuan", "commission_yuan",
            "promotion_fee_yuan", "orders"]
        case "recipe": return ["dish_name", "recipe_version", "ingredient_name",
            "ingredient_specification", "recipe_quantity_per_serving", "trim_loss_percent"]
        case "dish_sales": return ["dish_name", "sold_portions"]
        case "purchase" where submission.PurchasePlanId != nil && purchaseQuantityUnit != "piece":
            return ["ingredient_name", "ingredient_specification", "purchase_quantity",
             "unit_price_yuan_per_kg", "supplier_name"]
        case "purchase" where submission.PurchasePlanId != nil:
            return ["ingredient_name", "ingredient_specification", "purchase_quantity", "supplier_name"]
        case "purchase": return ["ingredient_name", "purchase_quantity"]
        case "kitchen": return ["feedback"] + (submission.FeedbackCategory == "leftover"
            ? ["dish_name", "outcome_quantity"]
            : submission.FeedbackCategory == "sold_out" ? ["dish_name"] : [])
        case "operations": return ["feedback"]
        default: return []
        }
    }

    private var missingRecognitionOriginal: Bool {
        guard submission.RecognitionFailureCode != nil else { return false }
        return !(detail?.Files ?? []).contains { $0.IsRecognitionOriginal == true }
    }

    private var canEdit: Bool {
        submission.SubmittedByUserId == userID && submission.SubmittedRole == role
    }

    private var missing: [String] {
        required.filter { key in !(detail?.Fields.contains { $0.FieldKey == key } ?? false) }
    }

    private var missingAttachment: Bool {
        submission.PurchasePlanId != nil && (detail?.Files.isEmpty ?? true)
    }

    private func preparationPlanUnavailableMessage(_ reason: String, status: String) -> String {
        let isConfirmed = status == "confirmed"
        switch reason {
        case "plan_missing":
            return !isConfirmed
                ? "这条旧资料没有关联备菜单，无法确认。请放弃该资料后重新提交，并选择同一营业日的有效备菜单。"
                : "这条历史现场事实未关联备菜单，事实记录仍保留；后续提交剩余或沽清资料时需关联同一营业日的有效备菜单。"
        case "reassignment_review": return isConfirmed
            ? "备菜单正在等待厨师长完成改派复核；已确认现场事实仍保留。"
            : "备菜单正在等待厨师长完成改派复核；复核后刷新资料。"
        case "assignee_changed": return isConfirmed
            ? "任务已改派；已确认现场事实仍保留，后续关联记录由现任厨师长提交。"
            : "任务已改派，原指派厨师提交的资料无法继续核对。请放弃该资料，再由现任厨师长重新提交现场事实。"
        case "business_date_mismatch": return isConfirmed
            ? "已确认现场事实仍保留，但备菜单营业日不同，请核对历史关联。"
            : "备菜单营业日与本条现场事实日期不一致，请放弃后按实际营业日重新提交。"
        default: return !isConfirmed
            ? "关联备菜单或来源已失效，当前资料无法继续确认。请放弃后重新提交，并选择同日有效的备菜单。"
            : "关联备菜单或来源已失效；已确认现场事实仍保留，请核对关联记录。"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("原始资料") {
                    if detail?.Submission.Status == "withdrawn" || submission.Status == "withdrawn" {
                        Text("资料已撤回，原文、字段和附件停止展示。")
                            .foregroundStyle(.secondary)
                    } else {
                        if let detail { Text(detail.Submission.OriginalText) }
                        else { ProgressView("正在读取资料详情") }
                    }
                    if let detail {
                        if detail.Submission.Status != "withdrawn" {
                            Text("文字来源：\(dineWiseTextOriginName(detail.Submission.TextOrigin))")
                                .font(.footnote).foregroundStyle(.secondary)
                            if (detail.Submission.Status == "pending_review" || detail.Submission.Status == "confirmed"),
                               let reason = detail.LinkedPreparationPlanUnavailableReason {
                                Text(preparationPlanUnavailableMessage(reason, status: detail.Submission.Status))
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                        }
                        Text("版本 \(detail.Submission.Version) · \(statusName(detail.Submission.Status))")
                            .foregroundStyle(.secondary)
                    }
                    Button("刷新核对详情") { load() }.disabled(busy)
                }
                if let detail {
                    if detail.Submission.Status != "withdrawn",
                       let purchasePlanID = detail.Submission.PurchasePlanId {
                        Section("关联订货计划 · \(purchasePlanID)") {
                            Text("以下是拟订参考，实际进货以本条资料的核对字段和附件为准。")
                                .foregroundStyle(.secondary)
                            let actualIngredient = detail.Fields.first(where: { $0.FieldKey == "ingredient_name" })?
                                .CurrentValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            let actualSpecification = detail.Fields.first(where: { $0.FieldKey == "ingredient_specification" })?
                                .CurrentValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            let actualSupplier = detail.Fields.first(where: { $0.FieldKey == "supplier_name" })?
                                .CurrentValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            let actualQuantityUnit = detail.Fields.first(where: { $0.FieldKey == "purchase_quantity" })?
                                .NormalizedUnit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                            let actualQuantityValue = detail.Fields.first(where: { $0.FieldKey == "purchase_quantity" })?
                                .NormalizedValue.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
                            if let linkedItems = detail.LinkedPurchasePlanItems {
                                let items = linkedItems.filter { $0.OrderQuantity > 0 }
                                if items.isEmpty {
                                    Text(detail.LinkedPurchasePlanUnavailableReason == "reassignment_review"
                                        ? "厨师长正在复核改派，计划明细暂不可用；请稍后刷新，实际进货资料仍可独立核对。"
                                        : "计划来源已失效或不可用，计划明细已隐藏；实际进货资料仍可独立核对。")
                                        .foregroundStyle(.secondary)
                                } else {
                                    let ingredientIndexes = items.indices.filter { index in
                                        guard let actualIngredient, !actualIngredient.isEmpty else { return false }
                                        return items[index].IngredientName
                                            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == actualIngredient
                                    }
                                    let unitIndexes = actualQuantityUnit.isEmpty ? []
                                        : ingredientIndexes.filter { index in
                                            items[index].Unit.trimmingCharacters(in: .whitespacesAndNewlines)
                                                .lowercased() == actualQuantityUnit
                                        }
                                    let specificationIndexes = actualSpecification.map { specification in
                                        unitIndexes.filter { index in
                                            items[index].PackageSpecification
                                                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == specification
                                        }
                                    } ?? []
                                    let matchedPlanItemIndex = unitIndexes.count == 1 ? unitIndexes[0]
                                        : specificationIndexes.count == 1 ? specificationIndexes[0] : nil
                                    let linkedPlanItemAmbiguous = unitIndexes.count > 1
                                        && specificationIndexes.count != 1
                                    if detail.Submission.Status == "pending_review",
                                       let actualIngredient, !actualIngredient.isEmpty,
                                       ingredientIndexes.isEmpty {
                                        Text("当前核对的食材未匹配订货计划明细；请核对食材名称或关联计划后再确认。")
                                            .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                                    }
                                    if detail.Submission.Status == "pending_review",
                                       let actualIngredient, !actualIngredient.isEmpty,
                                       !ingredientIndexes.isEmpty, actualQuantityUnit.isEmpty {
                                        Text("实收单位尚未核对，暂无法匹配订货计划明细；请先核对数量单位再确认。")
                                            .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                                    }
                                    if detail.Submission.Status == "pending_review",
                                       !actualQuantityUnit.isEmpty, !ingredientIndexes.isEmpty,
                                       unitIndexes.isEmpty {
                                        Text("该食材的计划单位与实收单位不一致；请核对进货单和关联计划，必要时放弃本条资料并重新提交。")
                                            .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                                    }
                                    if detail.Submission.Status == "pending_review", linkedPlanItemAmbiguous {
                                        Text("计划中有多条同名同单位食材；请核对实收规格，使其与其中一项计划规格完全一致。")
                                            .foregroundStyle(.secondary)
                                    }
                                    ForEach(Array(items.enumerated()), id: \.offset) { entry in
                                        let item = entry.element
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(item.IngredientName) · 拟订 \(NSDecimalNumber(decimal: item.OrderQuantity).stringValue) \(item.Unit)").bold()
                                            if entry.offset == matchedPlanItemIndex {
                                                Text("对应本条实际采购食材").foregroundStyle(.tint)
                                                if actualQuantityUnit == "kg" || actualQuantityUnit == "piece",
                                                   let actualQuantityValue {
                                                    DineWisePurchaseQuantityComparisonView(
                                                        actual: actualQuantityValue,
                                                        planned: item.OrderQuantity,
                                                        unit: actualQuantityUnit == "piece" ? "个" : "kg")
                                                    if actualQuantityUnit == "piece" {
                                                        Text("计件采购不换算为公斤，也不计入按公斤单价计算的采购金额。")
                                                            .font(.footnote).foregroundStyle(.secondary)
                                                    }
                                                }
                                                if let actualSpecification, !actualSpecification.isEmpty,
                                                   !item.PackageSpecification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                                   item.PackageSpecification.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != actualSpecification {
                                                    Text("实收规格与计划参考不同，请按进货单核实。").foregroundStyle(.orange)
                                                }
                                                if let actualSupplier, !actualSupplier.isEmpty,
                                                   !item.SupplierName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                                   item.SupplierName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != actualSupplier {
                                                    Text("实际供应商与拟选供应商不同，请按进货单核实。").foregroundStyle(.orange)
                                                }
                                            }
                                            if !item.PackageSpecification.isEmpty { Text("规格：\(item.PackageSpecification)") }
                                            if !item.SupplierName.isEmpty { Text("拟选供应商：\(item.SupplierName)") }
                                        }
                                    }
                                }
                            } else {
                                Text("当前服务未返回计划明细；实际进货资料仍可独立核对。")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("已核对字段") {
                        if detail.Fields.isEmpty { Text("尚无核对字段，可按原始资料人工录入。") }
                        ForEach(detail.Fields) { field in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(options.first(where: { $0.id == field.FieldKey })?.title
                                     ?? field.FieldKey).bold()
                                Text("原值：\(field.OriginalValue ?? "未识别") \(field.OriginalUnit ?? "")")
                                Text("核对：\(field.CurrentValue) \(field.CurrentUnit ?? "")")
                                if let normalized = field.NormalizedValue {
                                    Text("统一口径：\(normalized) \(field.NormalizedUnit ?? "")")
                                }
                                if field.FieldKey == "purchase_quantity",
                                   field.CurrentUnit?.lowercased() == "jin" {
                                    Text("换算依据：1 斤 = 0.5 公斤；原核对值仍保留。")
                                        .foregroundStyle(.secondary)
                                }
                                if field.FieldKey == "unit_price_yuan_per_kg", purchaseQuantityUnit == "piece" {
                                    Text("这是切换为计件前保存的单价，仅保留历史，不参与月报金额或公斤单价趋势。")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.footnote)
                        }
                    }
                    if detail.Submission.Status != "withdrawn" {
                        Section("核对轨迹") {
                            Button(showEvents ? "收起核对轨迹" : "查看核对轨迹") {
                                showEvents.toggle()
                            }
                            if showEvents {
                                ForEach(events) { event in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("版本 \(event.Version) · \(eventTitle(event))").bold()
                                        Text("\(dineWiseFormatTimestamp(event.ActedAt, timeZoneID: timeZone)) · \(event.ActorUserId == userID ? "本人" : "账号 \(event.ActorUserId)")")
                                        if event.Action == "field" {
                                            Text("\(event.PreviousValue ?? "未录入") \(event.PreviousUnit ?? "") → \(event.NewValue ?? "") \(event.NewUnit ?? "")")
                                        }
                                        if let reason = event.Reason { Text("原因：\(reason)") }
                                    }
                                    .font(.footnote)
                                }
                                if !eventsError.isEmpty {
                                    Text(eventsError).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                                }
                                if events.isEmpty && !eventsBusy && eventsError.isEmpty {
                                    Text("暂无核对轨迹。").foregroundStyle(.secondary)
                                }
                                if let nextEventID {
                                    Button("加载更早轨迹") { loadEvents(beforeID: nextEventID) }
                                        .disabled(eventsBusy)
                                }
                                if eventsBusy { ProgressView("正在读取核对轨迹") }
                            }
                        }
                    }
                    if detail.Submission.Status != "withdrawn" && !detail.Files.isEmpty {
                        Section("核对附件") {
                            ForEach(detail.Files) { file in
                                VStack(alignment: .leading) {
                                    Text("\(file.FileName)\(file.IsRecognitionOriginal == true ? " · 识别原图" : "") · \(file.SizeBytes / 1024) KB")
                                        .font(.footnote)
                                    HStack {
                                        Button("授权下载") { download(file) }
                                        if canEdit && detail.Submission.Status == "pending_review" {
                                            Button("撤销附件", role: .destructive) {
                                                fileToDelete = file
                                                showDeleteAttachment = true
                                            }
                                        }
                                    }
                                }
                                .disabled(busy)
                            }
                        }
                    }
                    if canEdit && detail.Submission.Status == "pending_review" {
                        Section("录入或更正") {
                            Picker("字段", selection: $fieldKey) {
                                ForEach(options) { option in Text(option.title).tag(option.id) }
                            }
                            .onChange(of: fieldKey) { _, key in
                                unit = options.first(where: { $0.id == key })?.units.first?.0 ?? ""
                                value = ""
                            }
                            if purchaseQuantityUnit == "piece" {
                                Text("计件采购无需填写每公斤单价；月报不会按公斤估价或比价。")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            if let jinKilogramPreview {
                                Text("预计统一口径：\(jinKilogramPreview) 公斤（1 斤 = 0.5 公斤）；原核对值仍保留。")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            TextField("核对值", text: $value)
                            Picker("单位", selection: $unit) {
                                ForEach(options.first(where: { $0.id == fieldKey })?.units ?? [], id: \.0) { item in
                                    Text(item.1).tag(item.0)
                                }
                            }
                            Button("保存核对字段") { saveField() }
                                .disabled(busy || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .onChange(of: purchaseQuantityUnit) { _, nextUnit in
                            if nextUnit == "piece", fieldKey == "unit_price_yuan_per_kg" {
                                fieldKey = "purchase_quantity"
                                unit = "piece"
                                value = ""
                            }
                        }
                        Section("完成核对") {
                            if missingRecognitionOriginal {
                                Text("识别失败资料需先上传并标记原始图片，普通附件不能代替。")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Toggle("将所选图片标记为识别失败原图", isOn: $attachAsRecognitionOriginal)
                                if attachAsRecognitionOriginal {
                                    Text("请尽量选择提交时识别的同一张原图；若本资料保存了摘要，服务端会比对。")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            if !missing.isEmpty {
                                Text("确认前必填：\(missing.compactMap { key in options.first(where: { $0.id == key })?.title }.joined(separator: "、"))")
                            }
                            let linkedPurchase = submission.PurchasePlanId != nil
                            Button(linkedPurchase ? "上传进货单附件" : "上传资料附件") {
                                showAttachmentImporter = true
                            }.disabled(busy)
                            Button(linkedPurchase ? "拍摄进货单" : "拍摄资料") {
                                guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                                    error = "当前设备不支持相机拍摄，请从相册选择或上传文件。"
                                    return
                                }
                                showAttachmentCamera = true
                            }.disabled(busy)
                            Text("已上传 \(detail.Files.count) 份\(linkedPurchase ? "；确认前至少需要一份。" : "。")")
                            Button("确认资料") { finish("confirm") }
                                .disabled(busy || !missing.isEmpty || missingAttachment || missingRecognitionOriginal)
                            Button("放弃资料", role: .destructive) { showAbandon = true }
                                .disabled(busy)
                        }
                    }
                    if (role == "owner" || canEdit) && detail.Submission.Status == "confirmed" {
                        Section("撤回已确认资料") {
                            Text("撤回后关联建议与任务将失效，执行人须等待老板重新决策。")
                                .font(.footnote).foregroundStyle(.secondary)
                            TextField("撤回原因", text: $withdrawReason, axis: .vertical)
                                .lineLimit(2...4)
                            Button("撤回资料", role: .destructive) { showWithdraw = true }
                                .disabled(busy || withdrawReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                if !error.isEmpty {
                    Section {
                        Text(error).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                        if pendingRefresh?.scopeKey == requestScopeKey {
                            Button("重试刷新") { retryRefresh() }.disabled(busy)
                        }
                    }
                }
            }
            .navigationTitle("资料核对")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") { dismiss() }
            } }
            .alert("放弃这条资料？", isPresented: $showAbandon) {
                Button("放弃资料", role: .destructive) { finish("abandon") }
                Button("取消", role: .cancel) {}
            } message: { Text("放弃后不能继续核对。") }
            .alert("撤回已确认资料？", isPresented: $showWithdraw) {
                Button("确认撤回", role: .destructive) { withdraw() }
                Button("取消", role: .cancel) {}
            } message: { Text("关联建议和任务将失效，请让老板基于新资料重新决策。") }
            .confirmationDialog("撤销附件？", isPresented: $showDeleteAttachment) {
                Button("撤销附件", role: .destructive) {
                    if let fileToDelete { deleteAttachment(fileToDelete) }
                }
            } message: { Text("撤销后需重新上传。") }
            .fileImporter(isPresented: $showAttachmentImporter,
                          allowedContentTypes: attachAsRecognitionOriginal ? [.image] : [.item]) { result in
                uploadAttachment(result)
            }
            .sheet(isPresented: $showAttachmentCamera) {
                DineWiseCameraPicker { image in
                    showAttachmentCamera = false
                    uploadCapturedPhoto(image)
                }
            }
            .fileExporter(isPresented: $showFileExporter, document: exportDocument,
                          contentType: .data, defaultFilename: exportName) { result in
                guard !exportScopeKey.isEmpty,
                      isCurrentScope(exportScopeKey, generation: exportScopeGeneration) else { return }
                if case .failure(let error) = result,
                   (error as? CocoaError)?.code != .userCancelled {
                    self.error = error.localizedDescription
                }
                exportDocument = nil
            }
            .onChange(of: requestScopeKey, initial: true) { _, scopeKey in
                activeScopeKey = scopeKey
                activeScopeGeneration += 1
                loadGeneration += 1
                eventsGeneration += 1
                detail = nil
                events = []; nextEventID = nil
                error = ""; eventsError = ""
                value = ""; withdrawReason = ""
                exportDocument = nil; exportName = ""; exportScopeKey = ""
                exportScopeGeneration = activeScopeGeneration
                showFileExporter = false; showEvents = false
                showAbandon = false; showWithdraw = false; showDeleteAttachment = false
                showAttachmentImporter = false; showAttachmentCamera = false; fileToDelete = nil
                attachAsRecognitionOriginal = false
                busy = false; eventsBusy = false
                fieldKey = options.first?.id ?? ""
                unit = options.first?.units.first?.0 ?? ""
                load()
            }
            .onChange(of: uploadRevision) { _, _ in load() }
            .onChange(of: showEvents) { _, visible in
                if visible { loadEvents() }
                else { eventsGeneration += 1; eventsBusy = false }
            }
            .onChange(of: detail?.Submission.Version) { _, _ in
                if showEvents { loadEvents() }
            }
        }
    }

    private func isCurrentScope(_ scopeKey: String, generation: Int? = nil) -> Bool {
        activeScopeKey == scopeKey
            && (generation == nil || activeScopeGeneration == generation)
    }

    private func load() {
        let scopeKey = requestScopeKey
        let requestStoreID = storeID
        let requestSubmissionID = submission.Id
        let requestToken = token
        let requestRole = role
        let scopeGeneration = activeScopeGeneration
        loadGeneration += 1
        let generation = loadGeneration
        busy = true; error = ""
        Task {
            defer {
                if isCurrentScope(scopeKey, generation: scopeGeneration), generation == loadGeneration {
                    busy = false
                }
            }
            do {
                let result = try await api.submissionDetail(storeID: requestStoreID,
                    submissionID: requestSubmissionID, token: requestToken, role: requestRole)
                guard isCurrentScope(scopeKey, generation: scopeGeneration),
                      generation == loadGeneration else { return }
                detail = result
            } catch {
                guard isCurrentScope(scopeKey, generation: scopeGeneration),
                      generation == loadGeneration else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func loadEvents(beforeID: String? = nil) {
        let scopeKey = requestScopeKey
        let requestStoreID = storeID
        let requestSubmissionID = submission.Id
        let requestToken = token
        let requestRole = role
        let scopeGeneration = activeScopeGeneration
        guard isCurrentScope(scopeKey) else { return }
        if beforeID == nil { eventsGeneration += 1 }
        let generation = eventsGeneration
        guard detail?.Submission.Status != "withdrawn" else {
            events = []; nextEventID = nil; eventsBusy = false; return
        }
        eventsBusy = true; eventsError = ""
        Task {
            defer {
                if isCurrentScope(scopeKey, generation: scopeGeneration),
                   generation == eventsGeneration { eventsBusy = false }
            }
            do {
                let page = try await api.submissionReviewEvents(storeID: requestStoreID,
                    submissionID: requestSubmissionID, token: requestToken, role: requestRole,
                    beforeID: beforeID)
                guard isCurrentScope(scopeKey, generation: scopeGeneration), showEvents,
                      generation == eventsGeneration else { return }
                events = beforeID == nil ? page.Items : events + page.Items
                nextEventID = page.NextBeforeId
            } catch {
                if isCurrentScope(scopeKey, generation: scopeGeneration),
                   generation == eventsGeneration {
                    eventsError = error.localizedDescription
                }
            }
        }
    }

    private func eventTitle(_ event: DineWiseSubmissionReviewEvent) -> String {
        if event.Action == "field" {
            let title = event.FieldKey == "unit_price_yuan_per_kg"
                ? "每公斤单价"
                : options.first(where: { $0.id == event.FieldKey })?.title ?? event.FieldKey ?? "字段"
            return "更正\(title)"
        }
        switch event.Action {
        case "upload_file": return "上传附件"
        case "delete_file": return "撤销附件"
        case "confirm": return "确认资料"
        case "abandon": return "放弃资料"
        case "withdraw": return "撤回资料"
        default: return event.Action
        }
    }

    private func saveField() {
        guard let detail else { return }
        let scopeKey = requestScopeKey
        let requestStoreID = storeID
        let requestSubmissionID = submission.Id
        let requestToken = token
        let requestRole = role
        let scopeGeneration = activeScopeGeneration
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = ["Version": String(detail.Submission.Version), "FieldKey": fieldKey,
                    "Value": trimmed, "Unit": unit]
        let retry = pendingWriteRetryKey(
            scope: "\(userID):\(requestStoreID):\(requestRole):\(requestSubmissionID):review-field",
            payload: body)
        let idempotencyKey = retry.key
        busy = true; error = ""
        Task {
            defer { if isCurrentScope(scopeKey, generation: scopeGeneration) { busy = false } }
            do {
                let result = try await api.reviewField(storeID: requestStoreID,
                    submissionID: requestSubmissionID, token: requestToken, role: requestRole,
                    version: detail.Submission.Version, fieldKey: fieldKey, value: trimmed,
                    unit: unit, idempotencyKey: idempotencyKey)
                clearPendingWriteRetryKey(retry)
                guard isCurrentScope(scopeKey, generation: scopeGeneration) else { return }
                self.detail = result
                value = ""
                await refreshAfterWrite("核对字段", scopeKey: scopeKey,
                    generation: scopeGeneration)
            } catch {
                guard isCurrentScope(scopeKey, generation: scopeGeneration) else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func uploadAttachment(_ result: Result<URL, Error>) {
        let scopeKey = requestScopeKey
        guard isCurrentScope(scopeKey) else { return }
        guard canEdit, detail?.Submission.Status == "pending_review" else { return }
        switch result {
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                self.error = error.localizedDescription
            }
        case .success(let url):
            let requestStoreID = storeID
            let requestSubmissionID = submission.Id
            let requestToken = token
            let requestRole = role
            let scopeGeneration = activeScopeGeneration
            let isRecognitionOriginal = attachAsRecognitionOriginal && missingRecognitionOriginal
            busy = true; error = ""
            Task {
                defer { if isCurrentScope(scopeKey, generation: scopeGeneration) { busy = false } }
                do {
                    guard url.startAccessingSecurityScopedResource() else {
                        throw DineWiseAPIError.failed("无法读取所选文件。")
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                       size > 10 * 1024 * 1024 {
                        throw DineWiseAPIError.failed("单个附件不能超过 10 MB。")
                    }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    var data = Data()
                    while data.count <= 10 * 1024 * 1024 {
                        let chunk = try handle.read(upToCount:
                            min(8192, 10 * 1024 * 1024 + 1 - data.count)) ?? Data()
                        if chunk.isEmpty { break }
                        data.append(chunk)
                    }
                    if data.count > 10 * 1024 * 1024 {
                        throw DineWiseAPIError.failed("单个附件不能超过 10 MB。")
                    }
                    try await saveAttachment(fileName: url.lastPathComponent, data: data,
                        scopeKey: scopeKey, storeID: requestStoreID,
                        submissionID: requestSubmissionID, token: requestToken, role: requestRole,
                        generation: scopeGeneration, isRecognitionOriginal: isRecognitionOriginal)
                } catch {
                    guard isCurrentScope(scopeKey, generation: scopeGeneration) else { return }
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func uploadCapturedPhoto(_ image: UIImage) {
        let scopeKey = requestScopeKey
        guard isCurrentScope(scopeKey) else { return }
        guard canEdit, detail?.Submission.Status == "pending_review" else { return }
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            error = "无法处理拍摄的照片。"
            return
        }
        guard data.count <= 10 * 1024 * 1024 else {
            error = "单个附件不能超过 10 MB。"
            return
        }
        let requestStoreID = storeID
        let requestSubmissionID = submission.Id
        let requestToken = token
        let requestRole = role
        let scopeGeneration = activeScopeGeneration
        let isRecognitionOriginal = attachAsRecognitionOriginal && missingRecognitionOriginal
        busy = true; error = ""
        Task {
            defer { if isCurrentScope(scopeKey, generation: scopeGeneration) { busy = false } }
            do {
                try await saveAttachment(fileName: "submission-photo.jpg", data: data,
                    scopeKey: scopeKey, storeID: requestStoreID,
                    submissionID: requestSubmissionID, token: requestToken, role: requestRole,
                    generation: scopeGeneration, isRecognitionOriginal: isRecognitionOriginal)
            } catch {
                guard isCurrentScope(scopeKey, generation: scopeGeneration) else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func saveAttachment(fileName: String, data: Data, scopeKey: String,
                                storeID: String, submissionID: String,
                                token: String, role: String, generation: Int,
                                isRecognitionOriginal: Bool) async throws {
        guard isCurrentScope(scopeKey, generation: generation) else { return }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let retry = pendingWriteRetryKey(
            scope: "\(userID):\(storeID):\(role):\(submissionID):file",
            payload: ["Operation": "upload_file", "FileName": fileName,
                      "SizeBytes": String(data.count), "Sha256": digest,
                      "IsRecognitionOriginal": String(isRecognitionOriginal)])
        try await api.uploadFile(storeID: storeID, submissionID: submissionID,
            token: token, role: role, fileName: fileName,
            data: data, idempotencyKey: retry.key,
            isRecognitionOriginal: isRecognitionOriginal)
        clearPendingWriteRetryKey(retry)
        guard isCurrentScope(scopeKey, generation: generation) else { return }
        await refreshAfterWrite("附件", scopeKey: scopeKey, generation: generation,
            reloadDetail: true, reloadFiles: true)
    }

    private func deleteAttachment(_ file: DineWiseSubmissionFile) {
        guard let detail, canEdit, detail.Submission.Status == "pending_review" else { return }
        let scopeKey = requestScopeKey
        guard isCurrentScope(scopeKey) else { return }
        let requestStoreID = storeID
        let requestSubmissionID = submission.Id
        let requestToken = token
        let requestRole = role
        let scopeGeneration = activeScopeGeneration
        let version = detail.Submission.Version
        let retry = pendingWriteRetryKey(
            scope: "\(userID):\(requestStoreID):\(requestRole):\(requestSubmissionID):delete-file",
            payload: ["Version": String(version), "FileId": file.Id])
        let key = retry.key
        busy = true; error = ""
        Task {
            defer { if isCurrentScope(scopeKey, generation: scopeGeneration) { busy = false } }
            do {
                try await api.deleteFile(storeID: requestStoreID, submissionID: requestSubmissionID,
                    fileID: file.Id, version: version, token: requestToken, role: requestRole,
                    idempotencyKey: key)
                clearPendingWriteRetryKey(retry)
                clearPendingWriteRetries(
                    scopePrefix: "\(userID):\(requestStoreID):\(requestRole):\(requestSubmissionID):file")
                guard isCurrentScope(scopeKey, generation: scopeGeneration) else { return }
                await refreshAfterWrite("附件撤销", scopeKey: scopeKey,
                    generation: scopeGeneration, reloadDetail: true, reloadFiles: true)
            } catch {
                guard isCurrentScope(scopeKey, generation: scopeGeneration) else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func download(_ file: DineWiseSubmissionFile) {
        let scopeKey = requestScopeKey
        guard isCurrentScope(scopeKey) else { return }
        let requestStoreID = storeID
        let requestSubmissionID = submission.Id
        let requestToken = token
        let requestRole = role
        let scopeGeneration = activeScopeGeneration
        busy = true; error = ""
        Task {
            defer { if isCurrentScope(scopeKey, generation: scopeGeneration) { busy = false } }
            do {
                let data = try await api.downloadFile(storeID: requestStoreID,
                    submissionID: requestSubmissionID, fileID: file.Id,
                    token: requestToken, role: requestRole)
                guard isCurrentScope(scopeKey, generation: scopeGeneration) else { return }
                exportName = file.FileName
                exportDocument = DineWiseAttachmentDocument(data: data)
                exportScopeKey = scopeKey
                exportScopeGeneration = scopeGeneration
                showFileExporter = true
            } catch {
                guard isCurrentScope(scopeKey, generation: scopeGeneration) else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func finish(_ action: String) {
        guard let detail else { return }
        let scopeKey = requestScopeKey
        guard isCurrentScope(scopeKey) else { return }
        let requestStoreID = storeID
        let requestSubmissionID = submission.Id
        let requestToken = token
        let requestRole = role
        let scopeGeneration = activeScopeGeneration
        let version = detail.Submission.Version
        let retry = pendingWriteRetryKey(
            scope: "\(userID):\(requestStoreID):\(requestRole):\(requestSubmissionID):review-\(action)",
            payload: ["Version": String(version)])
        let idempotencyKey = retry.key
        busy = true; error = ""
        Task {
            defer { if isCurrentScope(scopeKey, generation: scopeGeneration) { busy = false } }
            do {
                let result = try await api.finishReview(storeID: requestStoreID,
                    submissionID: requestSubmissionID, token: requestToken, role: requestRole,
                    version: version, action: action,
                    idempotencyKey: idempotencyKey)
                clearPendingWriteRetryKey(retry)
                guard isCurrentScope(scopeKey, generation: scopeGeneration) else { return }
                self.detail = result
                await refreshAfterWrite(action == "confirm" ? "资料确认" : "资料放弃",
                    scopeKey: scopeKey, generation: scopeGeneration)
            } catch {
                guard isCurrentScope(scopeKey, generation: scopeGeneration) else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func withdraw() {
        guard let detail, detail.Submission.Status == "confirmed" else { return }
        let scopeKey = requestScopeKey
        guard isCurrentScope(scopeKey) else { return }
        let requestStoreID = storeID
        let requestSubmissionID = submission.Id
        let requestToken = token
        let requestRole = role
        let scopeGeneration = activeScopeGeneration
        let reason = withdrawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }
        let version = detail.Submission.Version
        let retry = pendingWriteRetryKey(
            scope: "\(userID):\(requestStoreID):\(requestRole):\(requestSubmissionID):review-withdraw",
            payload: ["Version": String(version), "Reason": reason])
        let idempotencyKey = retry.key
        busy = true; error = ""
        Task {
            defer { if isCurrentScope(scopeKey, generation: scopeGeneration) { busy = false } }
            do {
                let result = try await api.withdrawSubmission(storeID: requestStoreID,
                    submissionID: requestSubmissionID, token: requestToken, role: requestRole,
                    version: version, reason: reason,
                    idempotencyKey: idempotencyKey)
                clearPendingWriteRetryKey(retry)
                guard isCurrentScope(scopeKey, generation: scopeGeneration) else { return }
                self.detail = result
                withdrawReason = ""
                await refreshAfterWrite("资料撤回", scopeKey: scopeKey,
                    generation: scopeGeneration)
            } catch {
                guard isCurrentScope(scopeKey, generation: scopeGeneration) else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func refreshAfterWrite(_ action: String, scopeKey: String, generation: Int,
                                   reloadDetail: Bool = false,
                                   reloadFiles: Bool = false) async {
        var failures: [String] = []
        if reloadDetail {
            do {
                let refreshed = try await api.submissionDetail(storeID: storeID,
                    submissionID: submission.Id, token: token, role: role)
                guard isCurrentScope(scopeKey, generation: generation) else { return }
                detail = refreshed
            } catch {
                failures.append("核对详情：\(error.localizedDescription)")
            }
        }
        if reloadFiles, let onFilesChanged, !(await onFilesChanged()) {
            failures.append("附件列表刷新失败")
        }
        if !(await onChanged()) {
            failures.append("资料列表刷新失败")
        }
        guard isCurrentScope(scopeKey, generation: generation) else { return }
        if failures.isEmpty {
            pendingRefresh = nil
            error = ""
        } else {
            pendingRefresh = DineWisePendingReviewRefresh(scopeKey: scopeKey, action: action,
                reloadDetail: reloadDetail, reloadFiles: reloadFiles)
            error = "\(action)已保存，但刷新未完成（\(failures.joined(separator: "；"))）。可稍后重试刷新。"
        }
    }

    private func retryRefresh() {
        guard let pendingRefresh, pendingRefresh.scopeKey == requestScopeKey else { return }
        let scopeKey = pendingRefresh.scopeKey
        let generation = activeScopeGeneration
        busy = true; error = ""
        Task {
            defer { if isCurrentScope(scopeKey, generation: generation) { busy = false } }
            await refreshAfterWrite(pendingRefresh.action, scopeKey: scopeKey,
                generation: generation, reloadDetail: pendingRefresh.reloadDetail,
                reloadFiles: pendingRefresh.reloadFiles)
        }
    }

    private func statusName(_ status: String) -> String {
        switch status {
        case "pending_review": "待核对"
        case "confirmed": "已确认"
        case "abandoned": "已放弃"
        case "withdrawn": "已撤回"
        default: status
        }
    }
}
