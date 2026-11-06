import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

struct ContentView: View {
    private let api = DineWiseAPI()
    @State private var email = ""
    @State private var code = ""
    @State private var storeName = ""
    @State private var token: String?
    @State private var sessionUserID = ""
    @State private var stores: [DineWiseStore] = []
    @State private var selectedStoreID = ""
    @State private var selectedRole = ""
    @State private var members: [DineWiseMember] = []
    @State private var memberEmail = ""
    @State private var memberRole = "manager"
    @State private var memberToRevoke: DineWiseMember?
    @State private var showRevokeAlert = false
    @State private var submissions: [DineWiseSubmission] = []
    @State private var reviewSubmission: DineWiseSubmission?
    @State private var filesBySubmission: [String: [DineWiseSubmissionFile]] = [:]
    @State private var uploadKeys: [String: String] = [:]
    @State private var exportDocument: DineWiseAttachmentDocument?
    @State private var exportName = ""
    @State private var showFileExporter = false
    @State private var fileTargetSubmissionID: String?
    @State private var showFileImporter = false
    @State private var submissionKind = "operating"
    @State private var submissionDate = ""
    @State private var originalText = ""
    @State private var pendingSubmissionKey: String?
    @State private var message = ""
    @State private var busy = false
    @State private var pendingKey: String?
    @State private var selectedTab = "preview"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(selectedTab == "preview" ? "今日" : selectedTab == "my" ? "我的" : roleName(selectedRole))
                            .font(.largeTitle.bold())
                        Spacer()
                        Text("餐有数 DineWise")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !message.isEmpty {
                        Text(message).foregroundStyle(.red)
                    }
                    if let token {
                        if selectedTab == "my" {
                            mySection(token: token)
                        } else {
                            storeSection(token: token)
                        }
                    } else if selectedTab == "my" {
                        loginSection
                    } else {
                        DineWiseGuestHomeView()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        }
        .alert("撤回岗位授权？", isPresented: $showRevokeAlert) {
            Button("撤回", role: .destructive) {
                guard let member = memberToRevoke, let token else { return }
                let storeID = selectedStoreID
                perform {
                    try await api.revokeMember(storeID: storeID, memberID: member.Id, token: token)
                    members = try await api.members(storeID: storeID, token: token)
                }
            }
            Button("取消", role: .cancel) { memberToRevoke = nil }
        } message: {
            Text("撤回后暂不能直接恢复，请确认操作。")
        }
        .sheet(item: $reviewSubmission) { item in
            if let token {
                let reviewStoreID = selectedStoreID
                let reviewRole = selectedRole
                DineWiseReviewView(storeID: reviewStoreID, submission: item, token: token,
                    role: reviewRole, userID: sessionUserID) {
                    let refreshed = try? await api.submissions(storeID: reviewStoreID,
                        token: token, role: reviewRole)
                    if let refreshed, selectedStoreID == reviewStoreID && selectedRole == reviewRole {
                        submissions = refreshed
                    }
                }
            }
        }
    }

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("登录自己的门店").font(.title2.bold())
            Text("使用餐有数账号，邮箱验证后查看已授权的门店。")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("邮箱").font(.subheadline.bold())
            TextField("邮箱", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            Button("获取验证码") {
                perform {
                    try await api.sendCode(email: email.trimmingCharacters(in: .whitespaces))
                    message = "验证码已发送，请查收邮箱。"
                }
            }
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(Color(red: 21 / 255, green: 92 / 255, blue: 57 / 255))
            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.45)))
            .opacity(busy || email.isEmpty ? 0.5 : 1)
            .disabled(busy || email.isEmpty)
            Text("验证码").font(.subheadline.bold())
            TextField("验证码", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .textFieldStyle(.plain)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            Button("登录并查看门店") {
                perform {
                    let session = try await api.login(
                        email: email.trimmingCharacters(in: .whitespaces), code: code
                    )
                    updateStores(try await api.stores(token: session.AccessToken))
                    token = session.AccessToken
                    sessionUserID = session.UserId
                    selectedTab = selectedRole.isEmpty ? "work" : selectedRole
                    code = ""
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(Color(red: 21 / 255, green: 92 / 255, blue: 57 / 255),
                        in: RoundedRectangle(cornerRadius: 12))
            .opacity(busy || email.isEmpty || code.isEmpty ? 0.5 : 1)
            .disabled(busy || email.isEmpty || code.isEmpty)
            Text("门店经营资料仅向获得授权的账号开放。")
                .font(.footnote).foregroundStyle(.secondary)
            NavigationLink("关于餐有数 · 查看版本") { DineWiseAboutView() }
                .font(.footnote)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            if token == nil {
                tabButton("预览", symbol: "house", value: "preview")
            } else if let store = stores.first(where: { $0.Id == selectedStoreID }),
                      !store.Roles.isEmpty {
                ForEach(store.Roles, id: \.self) { role in
                    tabButton(roleName(role), symbol: role == "owner" ? "house" : "checkmark.square",
                              value: role)
                }
            } else {
                tabButton("门店", symbol: "storefront", value: "work")
            }
            tabButton("我的", symbol: "person.crop.circle", value: "my")
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.white)
        .overlay(alignment: .top) { Color.black.opacity(0.07).frame(height: 1) }
    }

    private func tabButton(_ title: String, symbol: String, value: String) -> some View {
        Button {
            selectedTab = value
            if value != "my" && value != "preview" && value != "work" {
                selectedRole = value
                submissionKind = submissionKinds(for: value).first ?? "operating"
                submissions = []
                filesBySubmission = [:]
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 19))
                Text(title).font(.caption2)
            }
            .foregroundStyle(selectedTab == value ? Color(red: 0.11, green: 0.12, blue: 0.16) : .gray)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func mySection(token: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("我的").font(.title2.bold())
            Text(email).foregroundStyle(.secondary)
            Text("已获授权门店：\(stores.count) 家")
            NavigationLink("关于餐有数 · 查看版本") { DineWiseAboutView() }
            Button("退出登录") { signOut() }
                .foregroundStyle(.red)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func signOut() {
        token = nil
        sessionUserID = ""
        stores = []
        selectedStoreID = ""
        selectedRole = ""
        selectedTab = "preview"
        members = []
        submissions = []
        filesBySubmission = [:]
        uploadKeys = [:]
        exportDocument = nil
        showFileExporter = false
        message = ""
    }

    private func storeSection(token: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("我的门店").font(.title2.bold())
                Spacer()
                Button("刷新") {
                    perform { updateStores(try await api.stores(token: token)) }
                }
                .disabled(busy)
            }
            if stores.isEmpty {
                Text("暂无获授权门店，可先创建演示门店。")
                    .foregroundStyle(.secondary)
            }
            ForEach(stores) { store in
                Button {
                    selectedStoreID = store.Id
                    selectedRole = store.Roles.first ?? ""
                    selectedTab = selectedRole.isEmpty ? "work" : selectedRole
                    submissionKind = submissionKinds(for: selectedRole).first ?? "operating"
                    members = []
                    submissions = []
                    filesBySubmission = [:]
                    uploadKeys = [:]
                    exportDocument = nil
                    showFileExporter = false
                    memberRole = "manager"
                    memberEmail = ""
                    submissionDate = ""
                    originalText = ""
                    pendingSubmissionKey = nil
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.Name).font(.headline)
                        Text(store.Mode == "demo" ? "演示数据" : "试用门店")
                        Text(store.Roles.map(roleName).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(store.Id == selectedStoreID ? .green : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
            if let selected = stores.first(where: { $0.Id == selectedStoreID }) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("当前门店：\(selected.Name)").font(.headline)
                    Text(selected.Mode == "demo" ? "演示数据" : "试用门店")
                        .foregroundStyle(.secondary)
                    if let businessType = selected.BusinessType, !businessType.isEmpty {
                        Text("业态：\(businessType)")
                    }
                    if let address = selected.Address, !address.isEmpty {
                        Text("地址：\(address)")
                    }
                    if let introduction = selected.Introduction, !introduction.isEmpty {
                        Text(introduction)
                    }
                    if let paymentMethods = selected.PaymentMethods, !paymentMethods.isEmpty {
                        let names = ["wechat_pay": "微信支付", "alipay": "支付宝",
                                     "cash": "现金", "bank_card": "银行卡", "other": "其他"]
                        Text("顾客支付：\(paymentMethods.map { names[$0] ?? $0 }.joined(separator: "、"))")
                    }
                    if selected.HasPhoto == true { Text("已上传门店照片") }
                    Text("当前工作空间：\(roleName(selectedRole))")
                        .foregroundStyle(.secondary)
                }
                if selectedRole == "owner" {
                    memberSection(store: selected, token: token)
                    DineWiseDailyReportView(store: selected, token: token)
                }
                if !submissionKinds(for: selectedRole).isEmpty {
                    submissionSection(store: selected, token: token)
                } else if selectedRole == "marketer" {
                    Text("营销访谈将在 S5 接入；此岗位不能查看经营资料。")
                        .foregroundStyle(.secondary)
                }
                if selectedRole != "marketer" {
                    DineWiseDecisionTaskView(store: selected, token: token, role: selectedRole,
                        userID: sessionUserID, submissions: submissions, members: members)
                }
            }
            TextField("演示门店名称", text: $storeName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: storeName) { _, _ in pendingKey = nil }
            Button("创建演示门店") {
                perform {
                    let key = pendingKey ?? UUID().uuidString
                    pendingKey = key
                    try await api.createDemoStore(name: storeName, token: token, idempotencyKey: key)
                    updateStores(try await api.stores(token: token))
                    storeName = ""
                    pendingKey = nil
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || storeName.isEmpty)
        }
    }

    private func submissionSection(store: DineWiseStore, token: String) -> some View {
        let kinds = submissionKinds(for: selectedRole)
        let kind = kinds.contains(submissionKind) ? submissionKind : kinds.first ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("资料与反馈").font(.title2.bold())
                Spacer()
                Button("刷新") {
                    perform {
                        submissions = try await api.submissions(
                            storeID: store.Id, token: token, role: selectedRole
                        )
                    }
                }
                .disabled(busy)
            }
            Text("原始文字待核对确认后才能用于经营报告。图片和报表文件后续接入。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("资料类型", selection: $submissionKind) {
                ForEach(kinds, id: \.self) { item in
                    Text(kindName(item)).tag(item)
                }
            }
            .onChange(of: submissionKind) { _, _ in pendingSubmissionKey = nil }
            TextField("营业日期 YYYY-MM-DD", text: $submissionDate)
                .textFieldStyle(.roundedBorder)
                .onChange(of: submissionDate) { _, _ in pendingSubmissionKey = nil }
            TextEditor(text: $originalText)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))
                .onChange(of: originalText) { _, _ in pendingSubmissionKey = nil }
            Button("提交待核对资料") {
                perform {
                    let key = pendingSubmissionKey ?? UUID().uuidString
                    pendingSubmissionKey = key
                    try await api.submitText(storeID: store.Id, token: token,
                        role: selectedRole, kind: kind, businessDate: submissionDate,
                        originalText: originalText, idempotencyKey: key)
                    submissions = try await api.submissions(
                        storeID: store.Id, token: token, role: selectedRole
                    )
                    originalText = ""
                    pendingSubmissionKey = nil
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || submissionDate.isEmpty || originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ForEach(submissions) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(kindName(item.Kind)) · \(item.BusinessDate)").font(.headline)
                    Text("\(roleName(item.SubmittedRole)) · \(submissionStatus(item.Status))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.OriginalText)
                    Button("核对字段") { reviewSubmission = item }
                        .buttonStyle(.bordered)
                    HStack {
                        Button("查看附件") {
                            perform {
                                let files = try await api.files(storeID: store.Id,
                                    submissionID: item.Id, token: token, role: selectedRole)
                                if selectedStoreID == store.Id { filesBySubmission[item.Id] = files }
                            }
                        }
                        if item.Status == "pending_review" && item.SubmittedByUserId == sessionUserID
                            && item.SubmittedRole == selectedRole {
                            Button("上传附件") {
                                fileTargetSubmissionID = item.Id
                                showFileImporter = true
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    ForEach(filesBySubmission[item.Id] ?? []) { file in
                        Button("下载 \(file.FileName) · \(file.SizeBytes / 1024) KB") {
                            perform {
                                let data = try await api.downloadFile(storeID: store.Id,
                                    submissionID: item.Id, fileID: file.Id,
                                    token: token, role: selectedRole)
                                if selectedStoreID == store.Id {
                                    exportName = file.FileName
                                    exportDocument = DineWiseAttachmentDocument(data: data)
                                    showFileExporter = true
                                }
                            }
                        }
                        .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            if submissions.isEmpty {
                Text("暂无当前岗位可见的提交记录。")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .task(id: "\(store.Id):\(selectedRole)") {
            submissions = []
            filesBySubmission = [:]
            exportDocument = nil
            do {
                submissions = try await api.submissions(
                    storeID: store.Id, token: token, role: selectedRole
                )
            } catch { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            guard let submissionID = fileTargetSubmissionID else { return }
            fileTargetSubmissionID = nil
            switch result {
            case .success(let url):
                perform {
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
                    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    let uploadKey = "\(store.Id):\(submissionID):\(url.lastPathComponent):\(digest)"
                    let key = uploadKeys[uploadKey] ?? UUID().uuidString
                    uploadKeys[uploadKey] = key
                    try await api.uploadFile(storeID: store.Id, submissionID: submissionID,
                        token: token, role: selectedRole, fileName: url.lastPathComponent,
                        data: data, idempotencyKey: key)
                    uploadKeys[uploadKey] = nil
                    if selectedStoreID == store.Id {
                        filesBySubmission[submissionID] = try await api.files(
                            storeID: store.Id, submissionID: submissionID,
                            token: token, role: selectedRole)
                    }
                }
            case .failure(let error): message = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $showFileExporter, document: exportDocument,
                      contentType: .data, defaultFilename: exportName) { result in
            if case .failure(let error) = result { message = error.localizedDescription }
            exportDocument = nil
        }
    }

    private func submissionKinds(for role: String) -> [String] {
        switch role {
        case "owner": ["operating", "purchase"]
        case "manager": ["operating", "kitchen", "operations"]
        case "chef": ["kitchen"]
        case "purchaser": ["purchase"]
        case "operator": ["operations"]
        default: []
        }
    }

    private func kindName(_ kind: String) -> String {
        switch kind {
        case "operating": "经营资料"
        case "purchase": "采购资料"
        case "kitchen": "后厨反馈"
        case "operations": "运营反馈"
        default: kind
        }
    }

    private func submissionStatus(_ status: String) -> String {
        switch status {
        case "pending_review": "待核对"
        case "confirmed": "已确认"
        case "abandoned": "已放弃"
        default: "状态未知"
        }
    }

    private func memberSection(store: DineWiseStore, token: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("岗位授权").font(.title2.bold())
                Spacer()
                Button("刷新") {
                    perform { members = try await api.members(storeID: store.Id, token: token) }
                }
                .disabled(busy)
            }
            Text("成员须先用该邮箱登录餐有数。撤回后暂不能直接恢复。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(members) { member in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(member.Email ?? "账号已停用")
                        Text("\(roleName(member.Role)) · \(member.Enabled ? "有效" : "已撤回")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if member.Enabled && member.Role != "owner" {
                        Button("撤回", role: .destructive) {
                            memberToRevoke = member
                            showRevokeAlert = true
                        }
                        .disabled(busy)
                    }
                }
                .padding(.vertical, 5)
            }
            if members.isEmpty {
                Text("暂无成员记录，或正在加载。")
                    .foregroundStyle(.secondary)
            }
            TextField("成员邮箱", text: $memberEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
            Picker("授予岗位", selection: $memberRole) {
                ForEach(["manager", "chef", "purchaser", "operator"]
                    + (store.Mode == "demo" ? ["marketer"] : []), id: \.self) { role in
                    Text(roleName(role)).tag(role)
                }
            }
            Button("授予岗位") {
                perform {
                    try await api.grantMember(storeID: store.Id, email: memberEmail
                        .trimmingCharacters(in: .whitespaces), role: memberRole, token: token)
                    members = try await api.members(storeID: store.Id, token: token)
                    memberEmail = ""
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || memberEmail.isEmpty)
        }
        .padding()
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .task(id: store.Id) {
            members = []
            do { members = try await api.members(storeID: store.Id, token: token) }
            catch { message = error.localizedDescription }
        }
    }

    private func updateStores(_ updated: [DineWiseStore]) {
        stores = updated
        if !updated.contains(where: { $0.Id == selectedStoreID }) {
            selectedStoreID = updated.first?.Id ?? ""
            selectedRole = updated.first?.Roles.first ?? ""
            members = []
            submissions = []
            filesBySubmission = [:]
            uploadKeys = [:]
            exportDocument = nil
            showFileExporter = false
            submissionDate = ""
            originalText = ""
            pendingSubmissionKey = nil
        } else if let selected = updated.first(where: { $0.Id == selectedStoreID }),
                  !selected.Roles.contains(selectedRole) {
            selectedRole = selected.Roles.first ?? ""
            members = []
            submissions = []
            filesBySubmission = [:]
            uploadKeys = [:]
            exportDocument = nil
            showFileExporter = false
        }
    }

    private func roleName(_ role: String) -> String {
        switch role {
        case "owner": "老板"
        case "manager": "店长"
        case "chef": "厨师长"
        case "purchaser": "采购"
        case "operator": "门店运营"
        case "marketer": "营销"
        default: role.isEmpty ? "未授权" : role
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        busy = true
        message = ""
        Task { @MainActor in
            defer { busy = false }
            do { try await action() }
            catch { message = error.localizedDescription }
        }
    }
}
