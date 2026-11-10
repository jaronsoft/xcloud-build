import SwiftUI

struct DineWiseWeeklyProblemView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: DineWiseStore
    let token: String
    let weekStart: String

    @State private var report: DineWiseWeeklyProblemReport?
    @State private var message = ""
    @State private var selectedEvidence: DineWiseProblemEvidence?
    @State private var sourceDetail: DineWiseSubmissionDetail?
    @State private var sourceMessage = ""
    @State private var saveRequest = 0
    @State private var saving = false
    private let api = DineWiseAPI()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本周现场问题与依据").font(.headline)
            Text("仅统计已确认的岗位反馈；记录条数不等于发生率，也不代表已经查明原因。")
                .font(.footnote).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).foregroundStyle(DineWiseTheme.danger(for: colorScheme)) }
            if let report {
                Text("规则版本 \(report.RuleVersion) · 待核对反馈 \(report.PendingReviewCount) 条")
                    .font(.caption).foregroundStyle(.secondary)
                Text(report.Snapshot.map {
                    "已保存第 \($0.Revision) 版 · \($0.Status == "current" ? "当前有效" : "来源变化，需重新生成")"
                } ?? "当前为预览，尚未保存报告版本。")
                    .font(.caption).foregroundStyle(.secondary)
                if let reason = report.Snapshot?.InvalidatedReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                Button(saving ? "正在保存…" : report.Snapshot == nil ? "保存本周摘要" : "重新生成并保存") {
                    saveRequest += 1
                }
                .disabled(saving || report.Snapshot?.Status == "current")
                if report.Findings.isEmpty {
                    Text("暂无已确认现场反馈，不能据此认定没有问题。")
                }
                ForEach(report.Findings) { finding in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(categoryName(finding.Category)) · \(finding.FindingText)")
                            .font(.subheadline.bold())
                        Text("可信度：\(finding.ConfidenceLevel == "medium" ? "中" : "低") · \(finding.ConfidenceReason)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("计算口径：\(finding.CalculationRule)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("假设：\(finding.Assumptions)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(finding.NextStep).font(.subheadline)
                        ForEach(finding.Evidence) { source in
                            Button("核对来源 #\(source.SubmissionId) · 版本 \(source.SourceVersion) · \(source.BusinessDate) · \(roleName(source.SubmittedRole))") {
                                sourceDetail = nil
                                sourceMessage = ""
                                selectedEvidence = source
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
                if let selectedEvidence {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("来源 #\(selectedEvidence.SubmissionId) · 版本 \(selectedEvidence.SourceVersion)")
                                .font(.subheadline.bold())
                            Spacer()
                            Button("关闭") {
                                sourceDetail = nil
                                sourceMessage = ""
                                self.selectedEvidence = nil
                            }
                        }
                        if !sourceMessage.isEmpty {
                            Text(sourceMessage).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                        }
                        if let sourceDetail {
                            Text("已确认 · 营业日期 \(sourceDetail.Submission.BusinessDate) · \(roleName(sourceDetail.Submission.SubmittedRole))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(sourceDetail.Submission.OriginalText)
                            if !sourceDetail.Files.isEmpty {
                                Text("附件 \(sourceDetail.Files.count) 份；可在资料页按权限核对。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else if sourceMessage.isEmpty {
                            Text("正在核对来源…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 10))
                }
                ForEach(report.MissingReasons, id: \.self) { reason in
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DineWiseTheme.inset,
                    in: RoundedRectangle(cornerRadius: 14))
        .task(id: "\(store.Id):\(token):\(weekStart)") {
            report = nil
            message = ""
            selectedEvidence = nil
            sourceDetail = nil
            sourceMessage = ""
            saving = false
            saveRequest = 0
            do {
                let result = try await api.weeklyProblems(storeID: store.Id,
                    weekStart: weekStart, token: token)
                guard !Task.isCancelled else { return }
                guard result.StoreId == store.Id, result.Mode == store.Mode,
                      result.WeekStart == weekStart else {
                    message = "周问题摘要范围不匹配，请重新读取。"
                    return
                }
                report = result
            } catch is CancellationError { }
            catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
        .task(id: "\(store.Id):\(token):\(weekStart):\(saveRequest)") {
            guard saveRequest > 0 else { return }
            saving = true
            message = ""
            selectedEvidence = nil
            defer { if !Task.isCancelled { saving = false } }
            do {
                let result = try await api.saveWeeklyProblems(storeID: store.Id,
                    weekStart: weekStart, token: token)
                guard !Task.isCancelled else { return }
                guard result.StoreId == store.Id, result.Mode == store.Mode,
                      result.WeekStart == weekStart else {
                    message = "摘要已保存，但返回范围不匹配，请刷新确认。"
                    return
                }
                report = result
            } catch is CancellationError { }
            catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
        .task(id: "\(store.Id):\(token):\(weekStart):\(selectedEvidence?.SubmissionId ?? ""):\(selectedEvidence?.SourceVersion ?? 0)") {
            sourceDetail = nil
            sourceMessage = ""
            guard let selectedEvidence else { return }
            do {
                let result = try await api.submissionDetail(storeID: store.Id,
                    submissionID: selectedEvidence.SubmissionId, token: token, role: "owner")
                guard !Task.isCancelled else { return }
                if result.Submission.Id != selectedEvidence.SubmissionId
                    || result.Submission.StoreId != store.Id
                    || result.Submission.Mode != store.Mode
                    || result.Submission.Status != "confirmed"
                    || result.Submission.Version != selectedEvidence.SourceVersion {
                    sourceMessage = "来源已撤回或版本发生变化，请刷新报告。"
                    return
                }
                sourceDetail = result
            } catch is CancellationError { }
            catch { if !Task.isCancelled { sourceMessage = error.localizedDescription } }
        }
    }

    private func categoryName(_ code: String) -> String {
        switch code {
        case "complaint": "客诉"
        case "return": "退菜"
        case "personnel": "人员"
        case "equipment": "设备"
        default: "其他"
        }
    }

    private func roleName(_ code: String) -> String {
        switch code {
        case "owner": "老板"
        case "manager": "店长"
        case "chef": "厨师长"
        case "purchaser": "采购"
        case "operator": "门店运营"
        default: "岗位成员"
        }
    }
}
