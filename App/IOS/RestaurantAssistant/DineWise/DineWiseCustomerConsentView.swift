import SwiftUI
import UIKit

private struct DineWiseCustomerConsentFilter: Equatable {
    var purpose = ""
    var birthdayFrom = ""
    var birthdayTo = ""
    var lastVisitBeforeBusinessDate = ""
}

struct DineWiseCustomerConsentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    let store: DineWiseStore
    let token: String
    let role: String
    let userID: String

    private let api = DineWiseAPI()
    private let noticeVersion = "dinewise-private-domain-v2"
    private let consentNotice = "门店将使用会员引用号和您单独选择的生日月日、最近到店营业日或经营效果记录，由门店员工人工开展对应工作。经营效果记录仅保存顾客到店 POS 小票号或平台核销编号，供门店老板人工核对；不会据此推断收入或平台送达。您可联系门店停止相应用途；许可撤回后会清除会员引用号、日期、触达草稿和效果凭证。资料保存至门店明确填写的最后保留营业日。请先按门店现有流程向顾客说明并取得明确同意，再登记。"

    @State private var items: [DineWiseCustomerConsent] = []
    @State private var nextBeforeID: String?
    @State private var loading = false
    @State private var loadingMore = false
    @State private var saving = false
    @State private var error = ""
    @State private var message = ""
    @State private var requestGeneration = 0
    @State private var draftFilter = DineWiseCustomerConsentFilter()
    @State private var appliedFilter = DineWiseCustomerConsentFilter()

    @State private var customerReference = ""
    @State private var birthdayEnabled = false
    @State private var birthdayMonthDay = ""
    @State private var reengagementEnabled = false
    @State private var lastVisitBusinessDate = ""
    @State private var effectTrackingEnabled = false
    @State private var retainUntilBusinessDate = ""
    @State private var consentSource = "in_person"
    @State private var consentConfirmed = false
    @State private var recordToRevoke: DineWiseCustomerConsent?
    @State private var touchConsentID: String?
    @State private var touchDrafts: [DineWiseCustomerTouchDraft] = []
    @State private var touchPurpose = "birthday"
    @State private var touchContent = ""
    @State private var touchSaving = false
    @State private var editingTouchID: String?
    @State private var editingTouchContent = ""
    @State private var outcomesByDraft: [String: [DineWiseCustomerTouchOutcome]] = [:]
    @State private var touchRequestGeneration = 0
    @State private var outcomeBusinessDate = ""
    @State private var outcomeEvidenceReference = ""
    @State private var outcomeBusy = false
    @State private var outcomeReviewTarget: DineWiseCustomerTouchOutcome?
    @State private var outcomeReviewDraftID = ""

    private var purposes: [String] {
        [birthdayEnabled ? "birthday" : nil,
         reengagementEnabled ? "reengagement" : nil,
         effectTrackingEnabled ? "effect_tracking" : nil].compactMap { $0 }
    }

    private var canSave: Bool {
        !saving && !loading && !loadingMore && consentConfirmed && !purposes.isEmpty
            && !customerReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validDate(retainUntilBusinessDate, format: "yyyy-MM-dd")
            && (!birthdayEnabled || validDate("2000-\(birthdayMonthDay)", format: "yyyy-MM-dd"))
            && (!reengagementEnabled || validDate(lastVisitBusinessDate, format: "yyyy-MM-dd"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            privacyCard
            registrationCard
            filterCard
            consentList
        }
        .task(id: "\(store.Id):\(store.Mode):\(token):\(role)") {
            if outcomeBusinessDate.isEmpty { outcomeBusinessDate = currentStoreBusinessDate() }
            await refresh(reset: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refresh(reset: true) }
            } else {
                clearSensitiveState()
            }
        }
        .confirmationDialog("撤回顾客许可？", isPresented: Binding(
            get: { recordToRevoke != nil },
            set: { if !$0 { recordToRevoke = nil } }
        ), titleVisibility: .visible) {
            Button("撤回并清除识别信息", role: .destructive) {
                guard let item = recordToRevoke else { return }
                recordToRevoke = nil
                Task { await revoke(item) }
            }
            Button("取消", role: .cancel) { recordToRevoke = nil }
        } message: {
            Text("撤回后会立即清除会员引用号、日期、触达草稿和效果凭证，操作不可恢复。")
        }
        .confirmationDialog("核对原始到店或核销凭证", isPresented: Binding(
            get: { outcomeReviewTarget != nil },
            set: { if !$0 { outcomeReviewTarget = nil; outcomeReviewDraftID = "" } }
        ), titleVisibility: .visible) {
            if let item = outcomeReviewTarget {
                Button("已独立核对，计入汇总") {
                    Task { await reviewOutcome(item, draftID: outcomeReviewDraftID,
                        action: "verified") }
                }
                Button("凭证不存在", role: .destructive) {
                    Task { await reviewOutcome(item, draftID: outcomeReviewDraftID,
                        action: "rejected", reasonCode: "evidence_not_found") }
                }
                Button("凭证与记录不符", role: .destructive) {
                    Task { await reviewOutcome(item, draftID: outcomeReviewDraftID,
                        action: "rejected", reasonCode: "evidence_mismatch") }
                }
            }
            Button("取消", role: .cancel) { outcomeReviewTarget = nil; outcomeReviewDraftID = "" }
        } message: {
            Text("核对 POS/平台原始凭证后才能确认。未核验或员工自报数据不会计入效果汇总。")
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("顾客许可与资料保护", systemImage: "hand.raised.fill")
                .font(.headline).foregroundStyle(DineWiseTheme.accent(for: colorScheme))
            Text(consentNotice).font(.subheadline).foregroundStyle(.secondary)
            Text("仅录入门店会员引用号，不要填写姓名、手机号、邮箱或支付资料。生日仅保存月日；每项用途分别确认。经营效果记录限 POS 小票号或平台核销编号，老板需独立核对。保存期限必须按门店已取得的许可约定填写，本页不会自动设定期限。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var registrationCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("登记新许可").font(.headline)
            TextField("门店会员引用号", text: $customerReference)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Toggle("生日关怀", isOn: $birthdayEnabled)
            if birthdayEnabled {
                TextField("生日月日，例如 05-18", text: $birthdayMonthDay)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("久未到店关怀", isOn: $reengagementEnabled)
            if reengagementEnabled {
                TextField("最近到店营业日，例如 2026-11-01", text: $lastVisitBusinessDate)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("到店与核销效果记录", isOn: $effectTrackingEnabled)
            TextField("最后保留营业日，例如 2026-12-31", text: $retainUntilBusinessDate)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
            Picker("取得许可方式", selection: $consentSource) {
                Text("当面告知").tag("in_person")
                Text("纸面记录").tag("written_form")
                Text("数字表单").tag("digital_form")
            }
            Toggle("已先向顾客说明所选用途并取得明确同意", isOn: $consentConfirmed)
                .font(.subheadline)
            Button {
                Task { await save() }
            } label: {
                HStack {
                    if saving { ProgressView().tint(.white) }
                    Text(saving ? "正在保存…" : "登记顾客许可")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
            if !error.isEmpty {
                Text(error).font(.footnote).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
            }
            if !message.isEmpty {
                Text(message).font(.footnote).foregroundStyle(DineWiseTheme.accent(for: colorScheme))
            }
        }
        .font(.subheadline)
        .padding(16)
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var consentList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("有效许可").font(.headline)
                Spacer()
                Button("刷新") { Task { await refresh(reset: true) } }
                    .disabled(loading || loadingMore || saving)
            }
            if loading && items.isEmpty { ProgressView("正在读取许可…") }
            if !error.isEmpty && items.isEmpty {
                Text(error).font(.footnote).foregroundStyle(DineWiseTheme.danger(for: .light))
                Button("重试") { Task { await refresh(reset: true) } }
                    .buttonStyle(.bordered)
            }
            if !loading && error.isEmpty && items.isEmpty {
                ContentUnavailableView("暂无有效许可", systemImage: "person.crop.circle.badge.checkmark",
                    description: Text("取得顾客明确同意后，可登记单独授权的用途。"))
            }
            ForEach(items) { item in consentRow(item) }
            if nextBeforeID != nil {
                Button(loadingMore ? "正在加载…" : "加载更早记录") {
                    Task { await refresh(reset: false) }
                }
                .buttonStyle(.bordered)
                .disabled(loadingMore || saving)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("筛选获许可名单").font(.headline)
            Picker("许可用途", selection: $draftFilter.purpose) {
                Text("全部用途").tag("")
                Text("生日关怀").tag("birthday")
                Text("久未到店").tag("reengagement")
                Text("效果记录").tag("effect_tracking")
            }
            .pickerStyle(.segmented)
            if draftFilter.purpose == "birthday" {
                HStack {
                    TextField("起始月日 MM-DD", text: $draftFilter.birthdayFrom)
                    TextField("结束月日 MM-DD", text: $draftFilter.birthdayTo)
                }
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                Text("可留空查看全部生日许可；范围包含起止日期，支持跨年。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if draftFilter.purpose == "reengagement" {
                TextField("最近到店不晚于营业日（可留空）", text: $draftFilter.lastVisitBeforeBusinessDate)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                Text("需由门店人员明确选择截止日；系统不预设“久未到店”天数。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("应用筛选") {
                    appliedFilter = draftFilter
                    Task { await refresh(reset: true) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(loading || loadingMore || saving || !canApplyFilter)
                Button("清除") {
                    draftFilter = DineWiseCustomerConsentFilter()
                    appliedFilter = DineWiseCustomerConsentFilter()
                    Task { await refresh(reset: true) }
                }
                .buttonStyle(.bordered)
                .disabled(loading || loadingMore || saving)
            }
            if !canApplyFilter {
                Text("请填写完整且有效的筛选日期。")
                    .font(.caption).foregroundStyle(DineWiseTheme.danger(for: colorScheme))
            }
        }
        .padding(16)
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var canApplyFilter: Bool {
        switch draftFilter.purpose {
        case "":
            return true
        case "birthday":
            if draftFilter.birthdayFrom.isEmpty && draftFilter.birthdayTo.isEmpty { return true }
            return validDate("2000-\(draftFilter.birthdayFrom)", format: "yyyy-MM-dd")
                && validDate("2000-\(draftFilter.birthdayTo)", format: "yyyy-MM-dd")
        case "reengagement":
            return draftFilter.lastVisitBeforeBusinessDate.isEmpty
                || validDate(draftFilter.lastVisitBeforeBusinessDate, format: "yyyy-MM-dd")
        case "effect_tracking":
            return true
        default:
            return false
        }
    }

    private func consentRow(_ item: DineWiseCustomerConsent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("会员引用号").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(item.CustomerReference).font(.subheadline.weight(.semibold)).textSelection(.enabled)
            }
            Text("用途：\(purposeNames(item.Purposes))")
            if let birthday = item.BirthdayMonthDay { Text("生日月日：\(birthday)") }
            if let lastVisit = item.LastVisitBusinessDate { Text("最近到店：\(lastVisit)") }
            Text("许可来源：\(sourceName(item.ConsentSource)) · 告知版本：\(item.ConsentNoticeVersion == "dinewise-private-domain-v2" ? "第二版" : "第一版")")
            Text("最后保留营业日：\(item.RetainUntilBusinessDate)")
            HStack {
                Text("许可时间：\(formattedTime(item.ConsentedAtUtc))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("撤回许可", role: .destructive) { recordToRevoke = item }
                    .font(.caption.weight(.semibold))
                    .disabled(loading || loadingMore || saving)
            }
            if item.Status == "active"
                && item.Purposes.contains(where: { $0 == "birthday" || $0 == "reengagement" }) {
                Button(touchConsentID == item.Id ? "收起人工触达草稿" : "准备人工触达") {
                    Task { await openTouchDrafts(for: item) }
                }
                .buttonStyle(.bordered)
                .disabled(saving || touchSaving || loading || loadingMore)
            }
            if touchConsentID == item.Id { touchDraftSection(for: item) }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 13))
    }

    @ViewBuilder
    private func touchDraftSection(for consent: DineWiseCustomerConsent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("人工触达草稿").font(.subheadline.weight(.semibold))
                Spacer()
                Button("收起") {
                    touchConsentID = nil
                    touchDrafts = []
                    touchContent = ""
                    editingTouchID = nil
                    editingTouchContent = ""
                    outcomesByDraft = [:]
                    outcomeEvidenceReference = ""
                }
                .font(.caption)
            }
            Text("本应用不发送消息。复制后请在外部平台人工执行；“已人工发送”仅记录员工自报，不是平台回执。")
                .font(.caption).foregroundStyle(.secondary)
            Picker("授权用途", selection: $touchPurpose) {
                ForEach(consent.Purposes.filter { $0 == "birthday" || $0 == "reengagement" }, id: \.self) { purpose in
                    Text(purpose == "birthday" ? "生日关怀" : "久未到店关怀").tag(purpose)
                }
            }
            .pickerStyle(.segmented)
            TextField("拟发送内容", text: $touchContent, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .disabled(touchSaving)
            Button(touchSaving ? "正在保存…" : "保存草稿") {
                Task { await saveTouchDraft(for: consent) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(touchSaving || touchContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if touchDrafts.isEmpty && !touchSaving {
                Text("暂无草稿").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(touchDrafts) { draft in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(draft.Purpose == "birthday" ? "生日关怀" : "久未到店关怀") · \(draft.Status == "draft" ? "待人工执行" : "员工自报已执行")")
                        .font(.caption.weight(.semibold))
                    if editingTouchID == draft.Id {
                        TextField("修改草稿内容", text: $editingTouchContent, axis: .vertical)
                            .lineLimit(3...6).textFieldStyle(.roundedBorder)
                        HStack {
                            Button("保存修改") { Task { await updateTouchDraft(draft, consent: consent) } }
                                .buttonStyle(.borderedProminent)
                            Button("放弃修改") { editingTouchID = nil; editingTouchContent = "" }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        Text(draft.Content.isEmpty ? "草稿内容已清除。" : draft.Content)
                            .font(.subheadline).textSelection(.enabled)
                    }
                    if draft.Status == "draft" && editingTouchID != draft.Id {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                            Button("复制内容") { UIPasteboard.general.string = draft.Content; message = "内容已复制；请自行到外部平台发送。复制不代表发送成功。" }
                                .buttonStyle(.bordered)
                            Button("编辑") { editingTouchID = draft.Id; editingTouchContent = draft.Content }
                                .buttonStyle(.bordered)
                            Button("确认人工已发送") { Task { await actOnTouchDraft(draft, consent: consent, action: "report-sent") } }
                                .buttonStyle(.borderedProminent)
                            Button("取消") { Task { await actOnTouchDraft(draft, consent: consent, action: "cancel") } }
                                .buttonStyle(.bordered).tint(DineWiseTheme.danger(for: colorScheme))
                        }
                        .disabled(touchSaving)
                    }
                    if draft.Status == "reported_sent" {
                        Text("员工自报时间：\(draft.ReportedSentAtUtc ?? draft.CreatedAtUtc)；平台结果未核验。")
                            .font(.caption).foregroundStyle(.secondary)
                        if consent.Purposes.contains("effect_tracking") {
                            outcomeSection(for: draft, consent: consent)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(11)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 13))
    }

    @ViewBuilder
    private func outcomeSection(for draft: DineWiseCustomerTouchDraft,
                                consent: DineWiseCustomerConsent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("到店 / 核销凭证（待老板核对）")
                .font(.caption.weight(.semibold))
            TextField("门店营业日，例如 2026-11-10", text: $outcomeBusinessDate)
                .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
            TextField("POS 小票号或平台核销编号", text: $outcomeEvidenceReference)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(outcomeBusy ? "正在提交…" : "提交到店小票") {
                    Task { await createOutcome(draft, consent: consent, outcomeType: "visit") }
                }
                .buttonStyle(.borderedProminent)
                Button(outcomeBusy ? "正在提交…" : "提交核销编号") {
                    Task { await createOutcome(draft, consent: consent, outcomeType: "redemption") }
                }
                .buttonStyle(.bordered)
            }
            .disabled(outcomeBusy || outcomeEvidenceReference.trimmingCharacters(in: .whitespacesAndNewlines).count < 3
                || !validDate(outcomeBusinessDate, format: "yyyy-MM-dd"))
            Text("只填凭证编号，不要填顾客姓名、电话或自由文本。系统不会发送消息或自动关联收入。")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(outcomesByDraft[draft.Id] ?? []) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(item.OutcomeType == "visit" ? "到店" : "核销") · \(item.OccurredBusinessDate) · \(item.EvidenceReference)")
                    Text(item.Status == "pending_review" ? "待老板核对"
                        : item.Status == "verified" ? "老板已核对"
                        : "未通过核对（\(item.ReviewReasonCode == "evidence_not_found" ? "凭证不存在" : "凭证不符")）")
                        .font(.caption).foregroundStyle(.secondary)
                    if role == "owner" && item.Status == "pending_review" {
                        Button("核对凭证") {
                            outcomeReviewTarget = item
                            outcomeReviewDraftID = draft.Id
                        }.buttonStyle(.bordered)
                    }
                }
                .font(.caption)
            }
        }
        .padding(9)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    @MainActor
    private func refresh(reset: Bool) async {
        let requestedStoreID = store.Id
        let requestedMode = store.Mode
        let requestedToken = token
        let requestedRole = role
        requestGeneration += 1
        let generation = requestGeneration
        if reset {
            items = []
            nextBeforeID = nil
            error = ""
            loading = true
        } else {
            loadingMore = true
        }
        defer {
            if isCurrent(storeID: requestedStoreID, mode: requestedMode,
                         token: requestedToken, role: requestedRole, generation: generation) {
                loading = false
                loadingMore = false
            }
        }
        do {
            let page = try await api.customerConsents(storeID: requestedStoreID,
                token: requestedToken, role: requestedRole,
                beforeID: reset ? nil : nextBeforeID,
                purpose: appliedFilter.purpose.isEmpty ? nil : appliedFilter.purpose,
                birthdayFrom: appliedFilter.purpose == "birthday" && !appliedFilter.birthdayFrom.isEmpty
                    ? appliedFilter.birthdayFrom : nil,
                birthdayTo: appliedFilter.purpose == "birthday" && !appliedFilter.birthdayTo.isEmpty
                    ? appliedFilter.birthdayTo : nil,
                lastVisitBeforeBusinessDate: appliedFilter.purpose == "reengagement"
                    && !appliedFilter.lastVisitBeforeBusinessDate.isEmpty
                    ? appliedFilter.lastVisitBeforeBusinessDate : nil)
            try Task.checkCancellation()
            guard isCurrent(storeID: requestedStoreID, mode: requestedMode,
                token: requestedToken, role: requestedRole, generation: generation),
                page.Items.allSatisfy({ Int64($0.Id).map({ $0 > 0 }) == true }) else { return }
            let knownIDs = Set(items.map(\.Id))
            items.append(contentsOf: page.Items.filter { !knownIDs.contains($0.Id) })
            nextBeforeID = page.NextBeforeId
            error = ""
        } catch {
            guard isCurrent(storeID: requestedStoreID, mode: requestedMode,
                token: requestedToken, role: requestedRole, generation: generation) else { return }
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        guard canSave else { return }
        let requestedStoreID = store.Id
        let requestedMode = store.Mode
        let requestedToken = token
        let requestedRole = role
        let reference = customerReference.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedPurposes = purposes
        let birthday = birthdayEnabled ? birthdayMonthDay.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let lastVisit = reengagementEnabled
            ? lastVisitBusinessDate.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let retainUntil = retainUntilBusinessDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = consentSource
        let payload: [String: String] = [
            "CustomerReference": reference,
            "Purposes": selectedPurposes.joined(separator: ","),
            "BirthdayMonthDay": birthday ?? "",
            "LastVisitBusinessDate": lastVisit ?? "",
            "RetainUntilBusinessDate": retainUntil,
            "ConsentSource": source,
            "ConsentNoticeVersion": noticeVersion
        ]
        let retry = pendingWriteRetryKey(
            scope: "\(userID):\(requestedStoreID):\(requestedRole):customer-consent",
            payload: payload)
        let generation = requestGeneration
        saving = true
        error = ""
        message = ""
        defer {
            if isCurrent(storeID: requestedStoreID, mode: requestedMode,
                token: requestedToken, role: requestedRole, generation: generation) { saving = false }
        }
        do {
            let item = try await api.createCustomerConsent(storeID: requestedStoreID,
                token: requestedToken, role: requestedRole, customerReference: reference,
                purposes: selectedPurposes, noticeVersion: noticeVersion, consentSource: source,
                birthdayMonthDay: birthday, lastVisitBusinessDate: lastVisit,
                retainUntilBusinessDate: retainUntil, idempotencyKey: retry.key)
            clearPendingWriteRetryKey(retry)
            try Task.checkCancellation()
            guard isCurrent(storeID: requestedStoreID, mode: requestedMode,
                token: requestedToken, role: requestedRole, generation: generation),
                item.Status == "active", item.Purposes == selectedPurposes else { return }
            customerReference = ""
            birthdayMonthDay = ""
            lastVisitBusinessDate = ""
            retainUntilBusinessDate = ""
            birthdayEnabled = false
            reengagementEnabled = false
            effectTrackingEnabled = false
            consentConfirmed = false
            saving = false
            message = "顾客许可已登记；引用号只在本页读取期间显示。"
            await refresh(reset: true)
        } catch {
            guard isCurrent(storeID: requestedStoreID, mode: requestedMode,
                token: requestedToken, role: requestedRole, generation: generation) else { return }
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func revoke(_ item: DineWiseCustomerConsent) async {
        let requestedStoreID = store.Id
        let requestedMode = store.Mode
        let requestedToken = token
        let requestedRole = role
        let generation = requestGeneration
        error = ""
        message = ""
        do {
            let revoked = try await api.revokeCustomerConsent(storeID: requestedStoreID,
                consentID: item.Id, token: requestedToken, role: requestedRole,
                version: item.Version, reason: "顾客撤回营销用途许可")
            try Task.checkCancellation()
            guard isCurrent(storeID: requestedStoreID, mode: requestedMode,
                token: requestedToken, role: requestedRole, generation: generation),
                revoked.Status == "revoked", revoked.CustomerReference.isEmpty else { return }
            items.removeAll { $0.Id == item.Id }
            if touchConsentID == item.Id {
                touchConsentID = nil; touchDrafts = []; touchContent = ""
                touchSaving = false; editingTouchID = nil; editingTouchContent = ""
                outcomesByDraft = [:]; outcomeEvidenceReference = ""
            }
            message = "许可已撤回，客户识别信息已清除。"
        } catch {
            guard isCurrent(storeID: requestedStoreID, mode: requestedMode,
                token: requestedToken, role: requestedRole, generation: generation) else { return }
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func openTouchDrafts(for consent: DineWiseCustomerConsent) async {
        touchRequestGeneration += 1
        let touchGeneration = touchRequestGeneration
        if touchConsentID == consent.Id {
            touchConsentID = nil; touchDrafts = []; touchContent = ""
            editingTouchID = nil; editingTouchContent = ""
            outcomesByDraft = [:]; outcomeEvidenceReference = ""
            outcomeBusy = false
            return
        }
        let generation = requestGeneration
        touchConsentID = consent.Id
        touchDrafts = []
        touchContent = ""
        outcomesByDraft = [:]
        outcomeEvidenceReference = ""
        outcomeBusy = false
        touchPurpose = ["birthday", "reengagement"].first(where: consent.Purposes.contains) ?? ""
        editingTouchID = nil
        error = ""
        touchSaving = true
        defer { if isCurrent(storeID: store.Id, mode: store.Mode, token: token,
            role: role, generation: generation) { touchSaving = false } }
        do {
            let page = try await api.customerTouchDrafts(storeID: store.Id,
                consentID: consent.Id, token: token, role: role)
            try Task.checkCancellation()
            guard isCurrent(storeID: store.Id, mode: store.Mode, token: token,
                role: role, generation: generation), touchConsentID == consent.Id,
                touchRequestGeneration == touchGeneration else { return }
            touchDrafts = page.Items
            outcomesByDraft = [:]
            if consent.Purposes.contains("effect_tracking") {
                for draft in page.Items where draft.Status == "reported_sent" {
                    let outcomePage = try await api.customerTouchOutcomes(storeID: store.Id,
                        consentID: consent.Id, draftID: draft.Id, token: token, role: role)
                    try Task.checkCancellation()
                    guard isCurrent(storeID: store.Id, mode: store.Mode, token: token,
                        role: role, generation: generation), touchConsentID == consent.Id,
                        touchRequestGeneration == touchGeneration else { return }
                    outcomesByDraft[draft.Id] = outcomePage.Items
                }
            }
        } catch {
            guard isCurrent(storeID: store.Id, mode: store.Mode, token: token,
                role: role, generation: generation), touchRequestGeneration == touchGeneration else { return }
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func saveTouchDraft(for consent: DineWiseCustomerConsent) async {
        let content = touchContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, consent.Purposes.contains(touchPurpose), !touchSaving else { return }
        let generation = requestGeneration
        let purpose = touchPurpose
        let retry = pendingWriteRetryKey(scope: "\(userID):\(store.Id):\(role):\(consent.Id):customer-touch",
            payload: ["Purpose": purpose, "Content": content])
        touchSaving = true; error = ""; message = ""
        defer { if isCurrent(storeID: store.Id, mode: store.Mode, token: token,
            role: role, generation: generation) { touchSaving = false } }
        do {
            let created = try await api.createCustomerTouchDraft(storeID: store.Id,
                consentID: consent.Id, token: token, role: role, purpose: purpose,
                content: content, idempotencyKey: retry.key)
            clearPendingWriteRetryKey(retry)
            try Task.checkCancellation()
            guard isCurrent(storeID: store.Id, mode: store.Mode, token: token,
                role: role, generation: generation), touchConsentID == consent.Id else { return }
            touchDrafts.insert(created, at: 0)
            touchContent = ""
            message = "草稿已保存；请复制后到外部平台人工发送。"
        } catch {
            guard isCurrent(storeID: store.Id, mode: store.Mode, token: token,
                role: role, generation: generation) else { return }
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func updateTouchDraft(_ draft: DineWiseCustomerTouchDraft,
                                  consent: DineWiseCustomerConsent) async {
        let content = editingTouchContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !touchSaving else { return }
        let generation = requestGeneration
        touchSaving = true; error = ""
        defer { if isCurrent(storeID: store.Id, mode: store.Mode, token: token,
            role: role, generation: generation) { touchSaving = false } }
        do {
            let updated = try await api.updateCustomerTouchDraft(storeID: store.Id,
                consentID: consent.Id, draftID: draft.Id, token: token, role: role,
                version: draft.Version, content: content)
            guard isCurrent(storeID: store.Id, mode: store.Mode, token: token,
                role: role, generation: generation), touchConsentID == consent.Id else { return }
            touchDrafts = touchDrafts.map { $0.Id == updated.Id ? updated : $0 }
            editingTouchID = nil; editingTouchContent = ""
            message = "草稿已更新。"
        } catch {
            guard isCurrent(storeID: store.Id, mode: store.Mode, token: token,
                role: role, generation: generation) else { return }
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func actOnTouchDraft(_ draft: DineWiseCustomerTouchDraft,
                                 consent: DineWiseCustomerConsent, action: String) async {
        guard !touchSaving else { return }
        let generation = requestGeneration
        touchSaving = true; error = ""
        defer { if isCurrent(storeID: store.Id, mode: store.Mode, token: token,
            role: role, generation: generation) { touchSaving = false } }
        do {
            let updated = try await api.actOnCustomerTouchDraft(storeID: store.Id,
                consentID: consent.Id, draftID: draft.Id, action: action,
                token: token, role: role, version: draft.Version)
            guard isCurrent(storeID: store.Id, mode: store.Mode, token: token,
                role: role, generation: generation), touchConsentID == consent.Id else { return }
            if action == "cancel" {
                touchDrafts.removeAll { $0.Id == draft.Id }
                outcomesByDraft[draft.Id] = nil
            }
            else { touchDrafts = touchDrafts.map { $0.Id == updated.Id ? updated : $0 } }
            message = action == "cancel" ? "草稿已取消并清除内容。" : "已记录员工自报；这不是平台发送凭证。"
        } catch {
            guard isCurrent(storeID: store.Id, mode: store.Mode, token: token,
                role: role, generation: generation) else { return }
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func createOutcome(_ draft: DineWiseCustomerTouchDraft,
                               consent: DineWiseCustomerConsent,
                               outcomeType: String) async {
        let reference = outcomeEvidenceReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !outcomeBusy, consent.Purposes.contains("effect_tracking"),
              draft.Status == "reported_sent", reference.count >= 3,
              validDate(outcomeBusinessDate, format: "yyyy-MM-dd") else { return }
        let payload = ["OutcomeType": outcomeType,
                       "OccurredBusinessDate": outcomeBusinessDate,
                       "EvidenceReference": reference]
        let retry = pendingWriteRetryKey(
            scope: "\(userID):\(store.Id):\(role):\(consent.Id):\(draft.Id):customer-outcome",
            payload: payload)
        let generation = requestGeneration
        let requestedStoreID = store.Id
        let requestedMode = store.Mode
        let requestedToken = token
        let requestedRole = role
        let touchGeneration = touchRequestGeneration
        outcomeBusy = true
        error = ""
        defer {
            if requestGeneration == generation && touchRequestGeneration == touchGeneration {
                outcomeBusy = false
            }
        }
        do {
            let created = try await api.createCustomerTouchOutcome(storeID: store.Id,
                consentID: consent.Id, draftID: draft.Id, token: token, role: role,
                outcomeType: outcomeType, occurredBusinessDate: outcomeBusinessDate,
                evidenceReference: reference, idempotencyKey: retry.key)
            clearPendingWriteRetryKey(retry)
            guard isCurrent(storeID: requestedStoreID, mode: requestedMode,
                token: requestedToken, role: requestedRole, generation: generation),
                touchConsentID == consent.Id, touchRequestGeneration == touchGeneration else { return }
            outcomesByDraft[draft.Id, default: []].insert(created, at: 0)
            outcomeEvidenceReference = ""
            message = "凭证已提交，待门店老板独立核对；核对前不计入效果汇总。"
        } catch {
            guard isCurrent(storeID: requestedStoreID, mode: requestedMode,
                token: requestedToken, role: requestedRole, generation: generation),
                touchConsentID == consent.Id, touchRequestGeneration == touchGeneration else { return }
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func reviewOutcome(_ outcome: DineWiseCustomerTouchOutcome, draftID: String,
                               action: String, reasonCode: String? = nil) async {
        guard role == "owner", !outcomeBusy, let consentID = touchConsentID else { return }
        let generation = requestGeneration
        let requestedStoreID = store.Id
        let requestedMode = store.Mode
        let requestedToken = token
        let requestedRole = role
        let touchGeneration = touchRequestGeneration
        outcomeBusy = true
        outcomeReviewTarget = nil
        error = ""
        defer {
            if requestGeneration == generation && touchRequestGeneration == touchGeneration {
                outcomeBusy = false
                outcomeReviewDraftID = ""
            }
        }
        do {
            let updated = try await api.reviewCustomerTouchOutcome(storeID: store.Id,
                consentID: consentID, draftID: draftID, outcomeID: outcome.Id,
                token: token, version: outcome.Version, action: action, reasonCode: reasonCode)
            guard isCurrent(storeID: requestedStoreID, mode: requestedMode,
                token: requestedToken, role: requestedRole, generation: generation),
                touchConsentID == consentID, touchRequestGeneration == touchGeneration else { return }
            outcomesByDraft[draftID] = (outcomesByDraft[draftID] ?? []).map {
                $0.Id == updated.Id ? updated : $0
            }
            message = action == "verified" ? "凭证已核对，将计入门店效果汇总。" : "凭证已标记为未通过核对。"
        } catch {
            guard isCurrent(storeID: requestedStoreID, mode: requestedMode,
                token: requestedToken, role: requestedRole, generation: generation),
                touchConsentID == consentID, touchRequestGeneration == touchGeneration else { return }
            self.error = error.localizedDescription
        }
    }

    private func isCurrent(storeID: String, mode: String, token: String,
                           role: String, generation: Int) -> Bool {
        store.Id == storeID && store.Mode == mode && self.token == token
            && self.role == role && requestGeneration == generation
    }

    private func clearSensitiveState() {
        requestGeneration += 1
        touchRequestGeneration += 1
        items = []
        nextBeforeID = nil
        customerReference = ""
        birthdayMonthDay = ""
        lastVisitBusinessDate = ""
        retainUntilBusinessDate = ""
        birthdayEnabled = false
        reengagementEnabled = false
        effectTrackingEnabled = false
        consentConfirmed = false
        touchConsentID = nil
        touchDrafts = []
        outcomesByDraft = [:]
        touchContent = ""
        outcomeEvidenceReference = ""
        outcomeBusy = false
        outcomeReviewTarget = nil
        touchSaving = false
        editingTouchID = nil
        editingTouchContent = ""
        error = ""
        message = ""
        draftFilter = DineWiseCustomerConsentFilter()
        appliedFilter = DineWiseCustomerConsentFilter()
        loading = false
        loadingMore = false
        saving = false
    }

    private func validDate(_ value: String, format: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatter.isLenient = false
        guard let parsed = formatter.date(from: value) else { return false }
        return formatter.string(from: parsed) == value
    }

    private func purposeNames(_ values: [String]) -> String {
        values.map { $0 == "birthday" ? "生日关怀" : $0 == "reengagement" ? "久未到店关怀" : $0 == "effect_tracking" ? "到店与核销效果记录" : "其他" }
            .joined(separator: "、")
    }

    private func currentStoreBusinessDate() -> String {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZone = store.TimeZone.flatMap(TimeZone.init(identifier:)) {
            calendar.timeZone = timeZone
        }
        let cutoff = TimeInterval(store.BusinessDayCutoffMinutes ?? 0) * 60
        let date = calendar.startOfDay(for: Date().addingTimeInterval(-cutoff))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func sourceName(_ value: String) -> String {
        ["in_person": "当面告知", "written_form": "纸面记录", "digital_form": "数字表单"][value] ?? "其他"
    }

    private func formattedTime(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) ?? fractionalFormatter.date(from: value) else { return value }
        let output = DateFormatter()
        output.locale = Locale(identifier: "zh_CN")
        output.timeZone = .current
        output.dateFormat = "yyyy-MM-dd HH:mm"
        return output.string(from: date)
    }
}
