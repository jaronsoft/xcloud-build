import SwiftUI
import UniformTypeIdentifiers

private struct NativeMerchantRegionOption: View {
    let region: [String: Any]
    @Binding var selection: String

    var body: some View {
        let identifier = region["Id"] as? String ?? ""
        let name = region["Name"] as? String ?? "街区"
        let code = region["Code"] as? String ?? ""
        Text(name + "（" + code + "）").tag(identifier)
    }
}

struct NativeMerchantOnboardingView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var applications: [[String: Any]] = []
    @State private var applicationsLoaded = false
    @State private var regions: [[String: Any]] = []
    @State private var total = 0
    @State private var page = 1
    @State private var histories: [String: [[String: Any]]] = [:]
    @State private var expandedHistoryID = ""
    @State private var merchantName = ""
    @State private var description = ""
    @State private var selectedRegionID = ""
    @State private var documents: [String: [[String: Any]]] = [:]
    @State private var documentsLoadingID = ""
    @State private var uploadingID = ""
    @State private var supplementSubmittingID = ""
    @State private var selectedSupplementData: Data?
    @State private var selectedSupplementName = ""
    @State private var documentName = ""
    @State private var documentCategory = "Other"
    @State private var fileImporterPresented = false
    @State private var loading = false
    @State private var submitting = false
    @State private var error: String?
    @State private var notice: String?
    @State private var requestSequence = 0
    @State private var documentReadSequence = 0
    @State private var applicationSubmitTask: Task<Void, Never>?
    @State private var documentUploadTask: Task<Void, Never>?
    @State private var supplementSubmitTask: Task<Void, Never>?
    @State private var applicationReadTask: Task<Void, Never>?
    @State private var documentReadTask: Task<Void, Never>?
    @State private var historyReadTask: Task<Void, Never>?

    private var token: String? { store.session?.accessToken }
    private var principal: String? { nativeTourismPrincipal(token) }
    private var hasOpenApplication: Bool {
        applications.contains { ["PendingReview", "SupplementRequired"].contains($0["Status"] as? String ?? "") }
    }
    private var latestRejected: [String: Any]? { applications.first { ($0["Status"] as? String) == "Rejected" } }

    var body: some View {
        NavigationStack {
            List {
                Section("申請说明") {
                    Text("商户申请关联当前文旅账号。街区内申请由所属街区管理员初审，街区外申请直接进入运营终审。平台审核通过后还需完成商户资料审核与发布，商户空间才会对游客开放。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if applicationsLoaded && !hasOpenApplication {
                    Section(latestRejected == nil ? "提交商户申请" : "重新提交商户申请") {
                        TextField("商户名称（必填）", text: $merchantName)
                            .textInputAutocapitalization(.never)
                            .disabled(submitting)
                        Picker("拟入驻街区", selection: $selectedRegionID) {
                            Text("街区外（运营终审）").tag("")
                            ForEach(regions.indices, id: \.self) { index in
                                NativeMerchantRegionOption(region: regions[index], selection: $selectedRegionID)
                            }
                        }.disabled(submitting)
                        TextField("经营内容说明（选填）", text: $description, axis: .vertical)
                            .lineLimit(3...6)
                            .disabled(submitting)
                        if let latestRejected {
                            Button("带入上次申请资料") {
                                merchantName = latestRejected["MerchantName"] as? String ?? ""
                                description = latestRejected["Description"] as? String ?? ""
                                selectedRegionID = latestRejected["RegionId"] as? String ?? ""
                            }.disabled(submitting)
                        }
                        Button(submitting ? "正在提交…" : latestRejected == nil ? "提交申请" : "重新提交审核") {
                            guard !submitting else { return }
                            submitting = true
                            applicationSubmitTask?.cancel()
                            applicationSubmitTask = Task { await submit() }
                        }.disabled(submitting || loading || merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("请勿在说明中填写身份证号、银行卡号或手机号。审核要求补件时，可按意见上传资料并提交复审。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section("申请状态") {
                        Text("当前有待处理申请。请在下方查看审核状态和意见，并按平台要求补充资料。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    if loading && applications.isEmpty { ProgressView("正在读取申请记录…") }
                    else if !applicationsLoaded { Text("暂时无法确认申请状态，请重试读取后再提交。").foregroundStyle(.secondary) }
                    else if applications.isEmpty { Text("暂无申请记录").foregroundStyle(.secondary) }
                    ForEach(applications.indices, id: \.self) { index in
                        let item = applications[index]
                        let id = item["Id"] as? String ?? ""
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(item["MerchantName"] as? String ?? "未命名商户").fontWeight(.semibold)
                                Spacer()
                                Text(statusName(item["Status"] as? String ?? ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let region = item["RegionName"] as? String, !region.isEmpty {
                                Text("拟入驻：\(region)").font(.footnote).foregroundStyle(.secondary)
                            }
                            if let comment = item["ReviewComment"] as? String, !comment.isEmpty {
                                Text("审核意见：\(comment)").font(.footnote)
                            }
                            Button(expandedHistoryID == id ? "收起审核记录" : "查看审核记录") {
                                historyReadTask?.cancel()
                                historyReadTask = Task { await toggleHistory(id) }
                            }.font(.footnote)
                            if expandedHistoryID == id {
                                ForEach((histories[id] ?? []).indices, id: \.self) { historyIndex in
                                    let history = (histories[id] ?? [])[historyIndex]
                                    Text("\(history["Action"] as? String ?? "审核") · \(history["Comment"] as? String ?? "无说明")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if (item["Status"] as? String) == "SupplementRequired" {
                                VStack(alignment: .leading, spacing: 9) {
                                    Text("补充审核资料").font(.subheadline.weight(.semibold))
                                    Text("支持 PDF、JPG、PNG，单个文件不超过 20 MB。文件会在服务端加密保存。请勿在资料名称或文件名中填写证件号、银行卡号或手机号。")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Picker("资料分类", selection: $documentCategory) {
                                        Text("主体资料").tag("Entity")
                                        Text("门店资料").tag("Store")
                                        Text("结算资料").tag("Settlement")
                                        Text("合规资料").tag("Compliance")
                                        Text("其他资料").tag("Other")
                                    }
                                    TextField("资料名称", text: $documentName).textInputAutocapitalization(.never)
                                    Button(selectedSupplementName.isEmpty ? "选择文件" : "已选：\(selectedSupplementName)") {
                                        fileImporterPresented = true
                                    }.disabled(uploadingID == id || supplementSubmittingID == id)
                                    Button(uploadingID == id ? "正在加密上传…" : "上传补充资料") {
                                        documentUploadTask?.cancel()
                                        documentUploadTask = Task { await uploadSupplement(item) }
                                    }.disabled(selectedSupplementData == nil || documentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                || uploadingID == id || supplementSubmittingID == id)
                                    Button(documentsLoadingID == id ? "正在读取已上传资料…" : "查看已上传资料") {
                                        documentReadTask?.cancel()
                                        documentReadTask = Task { await loadDocuments(id) }
                                    }.disabled(documentsLoadingID == id || uploadingID == id)
                                    ForEach((documents[id] ?? []).indices, id: \.self) { documentIndex in
                                        let document = (documents[id] ?? [])[documentIndex]
                                        let version = (document["ApplicationVersion"] as? NSNumber)?.stringValue
                                            ?? document["ApplicationVersion"] as? String ?? "—"
                                        Text(verbatim: "\(document["DocumentName"] as? String ?? "入驻资料") · \(document["FileName"] as? String ?? "文件") · V\(version)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    let currentVersion = (item["Version"] as? NSNumber)?.int64Value
                                        ?? Int64(item["Version"] as? String ?? "")
                                    let hasCurrentDocument = currentVersion.map { version in
                                        (documents[id] ?? []).contains { document in
                                            ((document["ApplicationVersion"] as? NSNumber)?.int64Value
                                                ?? Int64(document["ApplicationVersion"] as? String ?? "")) == version
                                        }
                                    } ?? false
                                    if !hasCurrentDocument {
                                        Text("请按本轮审核要求至少上传一份新资料后，再提交补件。")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                    Button(supplementSubmittingID == id ? "正在重新提交…" : "提交补件并重新审核") {
                                        supplementSubmitTask?.cancel()
                                        supplementSubmitTask = Task { await resubmitSupplement(item) }
                                    }.disabled(!hasCurrentDocument || uploadingID == id || supplementSubmittingID == id
                                                || documentsLoadingID == id)
                                }
                                .padding(.top, 8)
                            }
                        }.padding(.vertical, 4)
                    }
                    if applications.count < total {
                        Button("加载更多") { startApplicationRead(append: true) }
                    }
                } header: { Text("我的申请（\(total)）") }
                if let error { Section { Text(error).foregroundStyle(.red); Button("重新加载") { startApplicationRead() } } }
            }
            .navigationTitle("商户入驻申请")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("刷新") { startApplicationRead() }.disabled(loading) }
            }
            .task(id: principal) { await resetForSession() }
            .onChange(of: principal) { _, _ in cancelAllTasks() }
            .onDisappear { cancelAllTasks() }
            .fileImporter(isPresented: $fileImporterPresented,
                          allowedContentTypes: [.pdf, .jpeg, .png], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let values = try url.resourceValues(forKeys: [.fileSizeKey])
                        guard (values.fileSize ?? 0) <= 20 * 1024 * 1024 else { notice = "单个文件不能超过 20 MB。"; return }
                        let data = try Data(contentsOf: url)
                        guard data.count >= 8, data.count <= 20 * 1024 * 1024 else { notice = "所选文件无效或超过 20 MB。"; return }
                        selectedSupplementData = data
                        selectedSupplementName = url.lastPathComponent
                        if documentName.isEmpty { documentName = url.deletingPathExtension().lastPathComponent.prefix(120).description }
                    } catch { notice = "读取所选文件失败，请重新选择。" }
                case .failure:
                    notice = "选择文件失败，请重试。"
                }
            }
            .alert("提示", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("知道了", role: .cancel) { notice = nil }
            } message: { Text(notice ?? "") }
        }
    }

    @MainActor private func cancelWriteTasks() {
        applicationSubmitTask?.cancel(); applicationSubmitTask = nil
        documentUploadTask?.cancel(); documentUploadTask = nil
        supplementSubmitTask?.cancel(); supplementSubmitTask = nil
    }

    @MainActor private func cancelReadTasks() {
        applicationReadTask?.cancel(); applicationReadTask = nil
        documentReadTask?.cancel(); documentReadTask = nil
        historyReadTask?.cancel(); historyReadTask = nil
        requestSequence += 1
        documentReadSequence += 1
        documentsLoadingID = ""
    }

    @MainActor private func cancelAllTasks() {
        cancelWriteTasks()
        cancelReadTasks()
    }

    @MainActor private func startApplicationRead(append: Bool = false) {
        applicationReadTask?.cancel()
        applicationReadTask = Task { await load(append: append) }
    }

    @MainActor private func resetForSession() async {
        cancelAllTasks()
        requestSequence += 1
        applications = []; applicationsLoaded = false; regions = []; histories = [:]; expandedHistoryID = ""
        merchantName = ""; description = ""; selectedRegionID = ""
        documents = [:]; documentsLoadingID = ""; uploadingID = ""; supplementSubmittingID = ""
        selectedSupplementData = nil; selectedSupplementName = ""; documentName = ""
        page = 1; total = 0; submitting = false; notice = nil; error = nil
        guard principal != nil else { loading = false; error = "请先登录文旅账号。"; return }
        await load()
    }

    @MainActor private func loadDocuments(_ applicationId: String) async {
        guard Int64(applicationId).map({ $0 > 0 }) == true, let token else { return }
        let requestedPrincipal = nativeTourismPrincipal(token)
        documentReadSequence += 1
        let sequence = documentReadSequence
        documentsLoadingID = applicationId
        defer { if sequence == documentReadSequence && documentsLoadingID == applicationId { documentsLoadingID = "" } }
        do {
            let value = try await MobileAPI(store: store).get("/api/JHCTIMerchant/GetMyOnboardingDocuments?applicationId=\(applicationId)", authenticated: true, expectedPrincipal: requestedPrincipal)
            try Task.checkCancellation()
            guard sequence == documentReadSequence,
                  nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal,
                  let rows = value as? [[String: Any]] else { return }
            documents[applicationId] = rows
        } catch {
            if !Task.isCancelled, sequence == documentReadSequence,
               nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal { notice = error.localizedDescription }
        }
    }

    @MainActor private func uploadSupplement(_ application: [String: Any]) async {
        guard let token, let data = selectedSupplementData,
              let id = application["Id"] as? String,
              nativeTourismPrincipal(store.session?.accessToken) == nativeTourismPrincipal(token) else { return }
        let requestedPrincipal = nativeTourismPrincipal(token)
        let name = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120, data.count <= 20 * 1024 * 1024 else { notice = "请填写资料名称并选择 20 MB 以内的文件。"; return }
        uploadingID = id
        documentReadTask?.cancel(); documentReadTask = nil
        documentsLoadingID = ""
        documentReadSequence += 1
        defer { if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal { uploadingID = "" } }
        do {
            _ = try await MobileAPI(store: store).uploadMyOnboardingDocument(data, applicationId: id,
                category: documentCategory, documentName: name, fileName: selectedSupplementName)
            try Task.checkCancellation()
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            selectedSupplementData = nil; selectedSupplementName = ""; documentName = ""
            await loadDocuments(id)
            notice = "资料已加密上传。请核对资料后提交补件。"
        } catch {
            if !Task.isCancelled, nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal { notice = error.localizedDescription }
        }
    }

    @MainActor private func resubmitSupplement(_ application: [String: Any]) async {
        guard let token, let id = application["Id"] as? String,
              let version = application["Version"] as? Int,
              nativeTourismPrincipal(store.session?.accessToken) == nativeTourismPrincipal(token) else { return }
        let requestedPrincipal = nativeTourismPrincipal(token)
        let hasCurrentDocument = (documents[id] ?? []).contains { document in
            ((document["ApplicationVersion"] as? NSNumber)?.intValue
                ?? Int(document["ApplicationVersion"] as? String ?? "")) == version
        }
        guard hasCurrentDocument else { notice = "请先读取并上传本轮要求的资料。"; return }
        supplementSubmittingID = id
        defer { if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal { supplementSubmittingID = "" } }
        do {
            _ = try await MobileAPI(store: store).post("/api/JHCTIMerchant/SubmitOnboardingSupplement",
                body: ["Id": id, "Version": version], authenticated: true, expectedPrincipal: requestedPrincipal)
            try Task.checkCancellation()
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            await load()
            notice = "补充资料已提交审核。"
        } catch {
            if !Task.isCancelled, nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal { notice = error.localizedDescription }
        }
    }

    @MainActor private func load(append: Bool = false) async {
        guard let token else { applications = []; regions = []; loading = false; error = "请先登录文旅账号。"; return }
        let requestedPrincipal = nativeTourismPrincipal(token)
        requestSequence += 1
        let sequence = requestSequence
        if !append { applicationsLoaded = false }
        loading = true; error = nil
        do {
            let targetPage = append ? page + 1 : 1
            let pageValue = try await MobileAPI(store: store).get("/api/JHCTIMerchant/GetMyOnboardingApplications?page=\(targetPage)&pageSize=20", authenticated: true, expectedPrincipal: requestedPrincipal)
            let pageResponse = pageValue as? [String: Any]
            guard sequence == requestSequence, nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            guard let pageResponse,
                  let parsedPage = nativeMerchantOnboardingPage(pageResponse, page: targetPage, pageSize: 20) else {
                throw MobileAPIError.unavailable("商户申请分页或记录回执格式无效，请刷新后重试。")
            }
            let rows = parsedPage.rows
            let mergedRows: [[String: Any]]
            if append {
                let known = Set(applications.compactMap { $0["Id"] as? String })
                let incoming = rows.compactMap { $0["Id"] as? String }
                guard incoming.count == rows.count, incoming.allSatisfy({ !known.contains($0) }),
                      applications.count + rows.count <= parsedPage.total else {
                    throw MobileAPIError.unavailable("商户申请分页存在重复记录或总数不一致，请刷新后重试。")
                }
                mergedRows = applications + rows
            } else {
                mergedRows = rows
            }
            applications = mergedRows
            applicationsLoaded = true
            total = parsedPage.total
            self.page = targetPage
            do {
                let regionValue = try await MobileAPI(store: store).get("/api/JHCTIMerchant/GetOnboardingRegionOptions", authenticated: true, expectedPrincipal: requestedPrincipal)
                guard sequence == requestSequence, nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
                guard let regionRows = regionValue as? [[String: Any]] else { throw MobileAPIError.unavailable("街区选项回执格式无效") }
                regions = regionRows
            } catch {
                if !Task.isCancelled, sequence == requestSequence,
                   nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal {
                    self.error = "申请记录已加载，街区选项暂不可用：\(error.localizedDescription)"
                }
            }
        } catch {
            if !Task.isCancelled, sequence == requestSequence,
               nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal { self.error = error.localizedDescription }
        }
        if sequence == requestSequence { loading = false }
    }

    @MainActor private func submit() async {
        guard let token,
              nativeTourismPrincipal(store.session?.accessToken) == nativeTourismPrincipal(token) else {
            submitting = false; return
        }
        let requestedPrincipal = nativeTourismPrincipal(token)
        let name = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 160, detail.count <= 2000 else {
            submitting = false; notice = "商户名称必填且不超过160字，说明不超过2000字。"; return
        }
        do {
            var body: [String: Any] = ["MerchantName": name, "Description": detail.isEmpty ? NSNull() : detail as Any]
            if !selectedRegionID.isEmpty { body["RegionId"] = selectedRegionID }
            _ = try await MobileAPI(store: store).post("/api/JHCTIMerchant/SubmitOnboardingApplication", body: body, authenticated: true, expectedPrincipal: requestedPrincipal)
            try Task.checkCancellation()
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            merchantName = ""; description = ""; selectedRegionID = ""
            applicationsLoaded = false
            await load()
            notice = "申请已提交。可在此查看审核进度。"
        } catch {
            if !Task.isCancelled, nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal { notice = error.localizedDescription }
        }
        if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal { submitting = false }
    }

    @MainActor private func toggleHistory(_ id: String) async {
        guard id.allSatisfy(\.isNumber), !id.isEmpty else { return }
        if expandedHistoryID == id { expandedHistoryID = ""; return }
        expandedHistoryID = id
        if histories[id] != nil { return }
        guard let token else { return }
        let requestedPrincipal = nativeTourismPrincipal(token)
        do {
            let value = try await MobileAPI(store: store).get("/api/JHCTIMerchant/GetMyOnboardingReviewHistory?applicationId=\(id)", authenticated: true, expectedPrincipal: requestedPrincipal)
            try Task.checkCancellation()
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal, expandedHistoryID == id,
                  let rows = value as? [[String: Any]] else { return }
            histories[id] = rows
        } catch {
            if !Task.isCancelled, nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal { notice = error.localizedDescription }
        }
    }

    private func statusName(_ status: String) -> String {
        ["PendingReview": "审核中", "SupplementRequired": "待补件", "Approved": "已通过", "Rejected": "已驳回"][status] ?? "处理中"
    }
}
