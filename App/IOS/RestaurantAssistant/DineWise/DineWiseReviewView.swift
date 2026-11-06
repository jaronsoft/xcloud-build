import SwiftUI

private struct DineWiseReviewOption: Identifiable {
    let id: String
    let title: String
    let units: [(String, String)]
}

struct DineWiseReviewView: View {
    let storeID: String
    let submission: DineWiseSubmission
    let token: String
    let role: String
    let userID: String
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detail: DineWiseSubmissionDetail?
    @State private var fieldKey = ""
    @State private var value = ""
    @State private var unit = ""
    @State private var requestSignature = ""
    @State private var requestKey = ""
    @State private var busy = false
    @State private var error = ""
    @State private var showAbandon = false

    private let api = DineWiseAPI()

    private var options: [DineWiseReviewOption] {
        switch submission.Kind {
        case "operating": [
            .init(id: "revenue_yuan", title: "营业额", units: [("yuan", "元")]),
            .init(id: "orders", title: "订单数", units: [("count", "单")]),
            .init(id: "tables", title: "桌数", units: [("count", "桌")])
        ]
        case "purchase": [
            .init(id: "ingredient_name", title: "食材名称", units: [("", "无单位")]),
            .init(id: "purchase_quantity", title: "采购数量", units: [("jin", "斤"), ("kg", "公斤")]),
            .init(id: "unit_price_yuan_per_kg", title: "每公斤单价", units: [("yuan/kg", "元/公斤")])
        ]
        case "kitchen": [.init(id: "feedback", title: "后厨反馈", units: [("", "无单位")])]
        case "operations": [.init(id: "feedback", title: "运营反馈", units: [("", "无单位")])]
        default: []
        }
    }

    private var required: [String] {
        switch submission.Kind {
        case "operating": ["revenue_yuan"]
        case "purchase": ["ingredient_name", "purchase_quantity"]
        case "kitchen", "operations": ["feedback"]
        default: []
        }
    }

    private var canEdit: Bool {
        submission.SubmittedByUserId == userID && submission.SubmittedRole == role
    }

    private var missing: [String] {
        required.filter { key in !(detail?.Fields.contains { $0.FieldKey == key } ?? false) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("原始资料") {
                    Text(submission.OriginalText)
                    if let detail {
                        Text("版本 \(detail.Submission.Version) · \(statusName(detail.Submission.Status))")
                            .foregroundStyle(.secondary)
                    }
                    Button("刷新核对详情") { load() }.disabled(busy)
                }
                if let detail {
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
                            }
                            .font(.footnote)
                        }
                    }
                    if canEdit && detail.Submission.Status == "pending_review" {
                        Section("录入或更正") {
                            Picker("字段", selection: $fieldKey) {
                                ForEach(options) { option in Text(option.title).tag(option.id) }
                            }
                            .onChange(of: fieldKey) { _, key in
                                unit = options.first(where: { $0.id == key })?.units.first?.0 ?? ""
                                value = ""; requestSignature = ""
                            }
                            TextField("核对值", text: $value)
                                .onChange(of: value) { _, _ in requestSignature = "" }
                            Picker("单位", selection: $unit) {
                                ForEach(options.first(where: { $0.id == fieldKey })?.units ?? [], id: \.0) { item in
                                    Text(item.1).tag(item.0)
                                }
                            }
                            .onChange(of: unit) { _, _ in requestSignature = "" }
                            Button("保存核对字段") { saveField() }
                                .disabled(busy || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Section("完成核对") {
                            if !missing.isEmpty {
                                Text("确认前必填：\(missing.compactMap { key in options.first(where: { $0.id == key })?.title }.joined(separator: "、"))")
                            }
                            Button("确认资料") { finish("confirm") }
                                .disabled(busy || !missing.isEmpty)
                            Button("放弃资料", role: .destructive) { showAbandon = true }
                                .disabled(busy)
                        }
                    }
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red) }
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
            .task {
                fieldKey = options.first?.id ?? ""
                unit = options.first?.units.first?.0 ?? ""
                load()
            }
        }
    }

    private func key(for signature: String) -> String {
        if requestSignature != signature {
            requestSignature = signature
            requestKey = UUID().uuidString
        }
        return requestKey
    }

    private func load() {
        busy = true; error = ""
        Task {
            defer { busy = false }
            do { detail = try await api.submissionDetail(storeID: storeID,
                submissionID: submission.Id, token: token, role: role) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func saveField() {
        guard let detail else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = "\(detail.Submission.Version):\(fieldKey):\(trimmed):\(unit)"
        let idempotencyKey = key(for: signature)
        busy = true; error = ""
        Task {
            defer { busy = false }
            do {
                self.detail = try await api.reviewField(storeID: storeID,
                    submissionID: submission.Id, token: token, role: role,
                    version: detail.Submission.Version, fieldKey: fieldKey, value: trimmed,
                    unit: unit, idempotencyKey: idempotencyKey)
                value = ""; requestSignature = ""
                await onChanged()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func finish(_ action: String) {
        guard let detail else { return }
        let idempotencyKey = key(for: "\(action):\(detail.Submission.Version)")
        busy = true; error = ""
        Task {
            defer { busy = false }
            do {
                self.detail = try await api.finishReview(storeID: storeID,
                    submissionID: submission.Id, token: token, role: role,
                    version: detail.Submission.Version, action: action,
                    idempotencyKey: idempotencyKey)
                requestSignature = ""
                await onChanged()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func statusName(_ status: String) -> String {
        switch status {
        case "pending_review": "待核对"
        case "confirmed": "已确认"
        case "abandoned": "已放弃"
        default: status
        }
    }
}
