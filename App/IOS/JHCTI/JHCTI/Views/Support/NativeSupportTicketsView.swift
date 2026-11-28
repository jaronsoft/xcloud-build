import SwiftUI
import PhotosUI
import UIKit
import ImageIO
import CoreFoundation

struct NativeSupportTicketPhoto: Transferable {
    static let maximumOriginalSize = 25 * 1024 * 1024

    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let values = try received.file.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size > 0, size <= maximumOriginalSize else {
                throw MobileAPIError.unavailable("图片读取失败或文件过大，请重新选择")
            }
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("jhcti-support-photo-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return NativeSupportTicketPhoto(url: destination)
        }
    }
}

private func nativeSupportTicketId(_ value: Any?) -> String? {
    guard let text = value as? String, !text.isEmpty,
          text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          let number = Int64(text), number > 0, String(number) == text else { return nil }
    return text
}

private struct NativeSupportTicketAttempt: NativeMerchantRecoveryRecord {
    let key: String

    var valid: Bool {
        key.utf8.count == 32 && key.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    func readReceipt(_ response: Any) throws -> String? {
        guard let row = response as? [String: Any], trackingField(row, "IdempotencyKey") as? String == key,
              let ticketID = trackingField(row, "TicketId") else {
            throw MobileAPIError.unavailable("工单回执与原请求不匹配，请重新核对。")
        }
        if ticketID is NSNull { return nil }
        guard let id = nativeSupportTicketId(ticketID) else {
            throw MobileAPIError.unavailable("工单编号无效，请重新核对。")
        }
        return id
    }

    func readReplyReceipt(_ response: Any, ticketID: String) throws -> String? {
        guard valid, nativeSupportTicketId(ticketID) != nil, let row = response as? [String: Any],
              trackingField(row, "TicketId") as? String == ticketID,
              trackingField(row, "IdempotencyKey") as? String == key,
              let messageID = trackingField(row, "MessageId") else {
            throw MobileAPIError.unavailable("留言回执与原请求不匹配，请重新核对。")
        }
        if messageID is NSNull { return nil }
        guard let id = nativeSupportTicketId(messageID) else {
            throw MobileAPIError.unavailable("留言编号无效，请重新核对。")
        }
        return id
    }
}

struct NativeSupportTicketsView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var rows: [[String: Any]] = []
    @State private var page = 1
    @State private var total = 0
    @State private var failedPage: Int?
    @State private var loading = false
    @State private var loadingMore = false
    @State private var submitting = false
    @State private var error: String?
    @State private var mode: Mode = .list
    @State private var detail: [String: Any]?
    @State private var detailId: String?
    @State private var detailLoading = false
    @State private var category = "Other"
    @State private var title = ""
    @State private var content = ""
    @State private var reply = ""
    @State private var createRecovery: NativeMerchantRecoveryState<NativeSupportTicketAttempt> = .unavailable
    @State private var createRetry: NativeSupportTicketAttempt?
    @State private var createNotice: String?
    @State private var createTask: Task<Void, Never>?
    @State private var checkingCreate = false
    @State private var refreshListAfterWrite = false
    @State private var displayedPrincipal: String?
    @State private var replyRecovery: NativeMerchantRecoveryState<NativeSupportTicketAttempt> = .unavailable
    @State private var replyRetry: NativeSupportTicketAttempt?
    @State private var replyNotice: String?
    @State private var replyTask: Task<Void, Never>?
    @State private var checkingReply = false
    @State private var ticketAttachments: [String] = []
    @State private var replyAttachments: [String] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoPickerPresented = false
    @State private var photoPickerTarget: AttachmentTarget = .ticket
    @State private var photoPickerPrincipal: String?
    @State private var photoPickerTicketId: String?
    @State private var previewAttachment: URL?
    @State private var previewImage: UIImage?
    @State private var previewLoading = false
    @State private var uploading = false
    @State private var uploadTask: Task<Void, Never>?
    @State private var detailTask: Task<Void, Never>?
    @State private var requestSequence = 0
    @State private var writeSequence = 0
    @State private var uploadSequence = 0

    private enum Mode: Equatable { case list, create, detail }
    private enum AttachmentTarget: Equatable { case ticket, reply }
    private let pageSize = 20
    private let categories = ["Order", "Payment", "Account", "Resource", "Data", "Security", "Other"]

    private var token: String? { store.session?.accessToken }
    private var principal: String? { nativeTourismPrincipal(token) }
    private var canEditReply: Bool {
        replyRecovery == .ready || replyRetry.map { replyRecovery == .pending($0) } == true
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .list: ticketList
                case .create: createForm
                case .detail: ticketDetail
                }
            }
            .navigationTitle(mode == .list ? "客服与反馈" : mode == .create ? "提交问题" : "工单详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(mode == .list ? "关闭" : "返回") {
                        cancelCreateWork()
                        cancelReplyWork()
                        if mode == .list {
                            uploadTask?.cancel()
                            detailTask?.cancel()
                            writeSequence += 1
                            submitting = false
                            dismiss()
                        } else {
                            detailTask?.cancel()
                            detailTask = nil
                            requestSequence += 1
                            writeSequence += 1
                            submitting = false
                            mode = .list; detail = nil; detailId = nil; error = nil
                            if refreshListAfterWrite {
                                refreshListAfterWrite = false
                                Task { await load(reset: true) }
                            }
                        }
                    }
                }
                if mode == .list && createRecovery == .ready {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("提交问题") {
                            guard displayedPrincipal == principal, refreshCreateRecovery() == .ready else { return }
                            mode = .create; error = nil; createNotice = nil
                        }
                        .disabled(submitting || checkingCreate)
                    }
                }
            }
        }
        .photosPicker(isPresented: $photoPickerPresented, selection: $selectedPhotos,
                      maxSelectionCount: 8, matching: .images)
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            uploadTask?.cancel()
            uploadTask = Task { await uploadSelectedPhotos(items) }
        }
        .onChange(of: mode) { _, _ in
            uploadTask?.cancel()
            uploadTask = nil
            uploadSequence += 1
            uploading = false
            selectedPhotos = []
            photoPickerPrincipal = nil
            photoPickerTicketId = nil
        }
        .sheet(isPresented: Binding(get: { previewAttachment != nil }, set: { if !$0 { previewAttachment = nil } })) {
            NavigationStack {
                Group {
                    if let previewImage {
                        Image(uiImage: previewImage).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
                    } else if previewLoading {
                        ProgressView("正在加载图片…").frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
                    } else {
                        VStack(spacing: 12) {
                            Text("图片暂时无法预览").foregroundStyle(.white)
                            if let previewAttachment { Link("在浏览器打开", destination: previewAttachment).tint(.white) }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") { previewAttachment = nil }
                    }
                }
            }
        }
        .task(id: previewAttachment) {
            let requestedURL = previewAttachment
            let requestedToken = token
            previewImage = nil
            previewLoading = requestedURL != nil
            let image = await NativePublicCache.shared.image(for: requestedURL)
            guard token == requestedToken, previewAttachment == requestedURL else { return }
            previewImage = image
            previewLoading = false
        }
        .onChange(of: scenePhase) { _, next in
            if next == .background, createTask != nil || mode != .create { cancelCreateWork() }
            if next == .background, replyTask != nil { cancelReplyWork() }
            if next == .active {
                let recovery = refreshCreateRecovery()
                if mode == .detail, let detailId { refreshReplyRecovery(detailId) }
                if mode == .create && recovery != .ready && createRetry.map({ recovery == .pending($0) }) != true {
                    mode = .list
                }
            }
        }
        .onDisappear { cancelCreateWork(); cancelReplyWork() }
        .task(id: principal) {
            uploadTask?.cancel()
            uploadTask = nil
            detailTask?.cancel()
            detailTask = nil
            requestSequence += 1
            writeSequence += 1
            uploadSequence += 1
            rows = []; total = 0; page = 1; failedPage = nil; detail = nil; detailId = nil; mode = .list
            submitting = false
            ticketAttachments = []; replyAttachments = []; selectedPhotos = []; uploading = false
            cancelCreateWork()
            cancelReplyWork()
            replyRecovery = .unavailable
            refreshListAfterWrite = false
            title = ""; content = ""; category = "Other"; reply = ""
            displayedPrincipal = principal
            photoPickerPrincipal = nil; photoPickerTicketId = nil
            previewAttachment = nil; previewImage = nil; previewLoading = false
            error = nil
            refreshCreateRecovery()
            guard token != nil else { error = "请先登录文旅账号，再提交问题或查看处理进度。"; return }
            await load(reset: true)
        }
    }

    private var ticketList: some View {
        List {
            if case .pending(let attempt) = createRecovery {
                Section("建单待核对") {
                    if let createNotice { Text(createNotice).foregroundStyle(Brand.muted) }
                    Button(checkingCreate ? "查询中…" : "查询原工单") { startCreateCheck() }
                        .disabled(checkingCreate || submitting)
                    if createRetry == attempt {
                        Button("用原请求号继续提交") {
                            guard displayedPrincipal == principal, refreshCreateRecovery() == .pending(attempt) else { return }
                            mode = .create; error = nil
                        }
                        .disabled(checkingCreate || submitting)
                    }
                }
            } else if token != nil && createRecovery != .ready {
                Section {
                    Text(createNotice ?? "无法读取待核对记录，暂不能提交工单。").foregroundStyle(Brand.muted)
                    Button("重新读取") { refreshCreateRecovery() }
                }
            }
            Section {
                Text("提交问题后可在这里查看处理进度，并继续与客服沟通。")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                if loading && rows.isEmpty { ProgressView("正在加载工单…") }
                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).foregroundStyle(.red)
                        if token != nil {
                            let retryPage = failedPage ?? 1
                            Button("重试第 \(retryPage) 页") { Task { await load(reset: retryPage == 1, pageOverride: retryPage) } }
                                .disabled(loading || loadingMore)
                        }
                    }
                }
                if !loading && error == nil && rows.isEmpty { Text("还没有提交过问题") }
            }
            Section("我的工单 · \(total)") {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Button { startDetailLoad(row) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(categoryName(row["Category"] as? String ?? "Other"))
                                    .font(.system(size: NativeTypography.size(14), weight: .medium)).foregroundStyle(Brand.primary)
                                Spacer()
                                Text(statusName(row["Status"] as? String ?? ""))
                                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            }
                            Text(row["Title"] as? String ?? "客服工单")
                                .font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                            let updatedAt = bookingBusinessDateTime(row["ModifyTime"])
                                ?? bookingBusinessDateTime(row["CreateTime"]) ?? "时间未知"
                            Text("\(row["TicketNo"] as? String ?? "工单编号生成中") · \(updatedAt)")
                                .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                if rows.count < total && error == nil {
                    Button(loadingMore ? "正在加载…" : "加载更多") { Task { await load(reset: false) } }
                        .disabled(loadingMore || loading)
                }
            }
        }
        .refreshable { refreshCreateRecovery(); await load(reset: true) }
    }

    private var createForm: some View {
        Form {
            Section("问题类型") {
                Picker("类型", selection: $category) {
                    ForEach(categories, id: \.self) { Text(categoryName($0)).tag($0) }
                }
            }
            Section("问题内容") {
                TextField("请简要描述遇到的问题", text: $title)
                    .textInputAutocapitalization(.never)
                    .onChange(of: title) { _, value in
                        let limited = nativeLimitUtf16Text(value, maximum: 160)
                        if limited != value { title = limited }
                    }
                Text("\(title.utf16.count)/160").font(.system(size: NativeTypography.size(12)))
                    .foregroundStyle(Brand.muted).frame(maxWidth: .infinity, alignment: .trailing)
                TextEditor(text: $content).frame(minHeight: 170)
                    .onChange(of: content) { _, value in
                        let limited = nativeLimitUtf16Text(value, maximum: 4000)
                        if limited != value { content = limited }
                    }
                Text("\(content.utf16.count)/4000").font(.system(size: NativeTypography.size(12)))
                    .foregroundStyle(Brand.muted).frame(maxWidth: .infinity, alignment: .trailing)
                Text("请说明问题发生经过，避免填写银行卡密码等敏感信息。图片为选填，每条最多 8 张、单张不超过 5 MB。")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                attachmentPicker(target: .ticket, urls: ticketAttachments)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Button(submitting ? "正在提交…" : createRetry == nil ? "提交给客服" : "用原请求号提交") {
                    guard createTask == nil else { return }
                    createTask = Task { await submitTicket() }
                }
                .disabled(submitting || checkingCreate || uploading || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var ticketDetail: some View {
        NativeSupportTicketDetailView(
            store: store,
            isLoading: detailLoading,
            detail: detail,
            error: error,
            detailId: detailId,
            reply: $reply,
            replyAttachments: replyAttachments,
            isSubmitting: submitting,
            isUploading: uploading,
            canEditReply: canEditReply,
            replyPending: replyRecovery != .ready,
            replyLookupLabel: checkingReply ? "查询中…" : replyLookupLabel,
            replyNotice: replyNotice ?? (replyRecovery == .ready ? nil : replyLookupLabel == "查询原留言"
                ? "这张工单有一条留言待核对。" : "无法读取待核对记录，暂不能发送留言。"),
            checkingReply: checkingReply,
            retryOriginalReply: replyRetry != nil,
            previewAttachment: $previewAttachment,
            replyAttachmentPicker: AnyView(attachmentPicker(target: .reply, urls: replyAttachments)),
            onRetry: { if let detailId { startDetailLoad(["Id": detailId]) } },
            onCheckReply: startReplyCheck,
            onSubmitReply: {
                guard replyTask == nil else { return }
                replyTask = Task { await submitReply() }
            }
        )
    }

    private func load(reset: Bool, pageOverride: Int? = nil) async {
        guard let token else { error = "请先登录文旅账号。"; rows = []; total = 0; return }
        guard let expectedPrincipal = nativeTourismPrincipal(token) else { error = "登录账号信息无效，请重新登录。"; return }
        let target = pageOverride ?? (reset ? 1 : page + 1)
        let replacesLoadedRows = target == 1
        let requestID = requestSequence
        if replacesLoadedRows { loading = true; error = nil } else { loadingMore = true; error = nil }
        defer { if requestID == requestSequence { loading = false; loadingMore = false } }
        do {
            guard let result = try await MobileAPI(store: store).get("/api/JHCTISupportTicket/GetMyPage?page=\(target)&pageSize=\(pageSize)", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any],
                  principal == expectedPrincipal,
                  let expectedUserId = nativeTourismPrincipal(token)?.split(separator: ":").first.map(String.init),
                  nativeSupportTicketId(expectedUserId) != nil,
                  let responsePage = result["page"] as? Int, responsePage == target,
                  let responsePageCount = result["pageCount"] as? Int,
                  let responsePageSize = result["PageSize"] as? Int, responsePageSize == pageSize,
                  let count = (result["dataCount"] ?? result["DataCount"]) as? Int, count >= 0,
                  let loaded = (result["data"] ?? result["Data"]) as? [[String: Any]], loaded.count <= pageSize else {
                throw MobileAPIError.unavailable("工单列表响应无效，请刷新重试。")
            }
            guard responsePageCount == (count + pageSize - 1) / pageSize else {
                throw MobileAPIError.unavailable("工单分页回执无效，请刷新重试。")
            }
            let categories: Set<String> = ["Order", "Payment", "Account", "Resource", "Data", "Security", "Other"]
            let statuses: Set<String> = ["Open", "Assigned", "PendingUser", "Resolved", "Closed"]
            let priorities: Set<String> = ["Normal", "High", "Urgent"]
            let identityTypes: Set<String> = ["SiteServer", "Tourism"]
            var ids: [String] = []
            for row in loaded {
                guard let id = nativeSupportTicketId(row["Id"]),
                      let userId = nativeSupportTicketId(row["UserId"]), userId == expectedUserId,
                      let identityType = row["UserIdentityType"] as? String, identityTypes.contains(identityType), identityType == "Tourism",
                      let ticketNo = row["TicketNo"] as? String, !ticketNo.isEmpty,
                      let category = row["Category"] as? String, categories.contains(category),
                      let priority = row["Priority"] as? String, priorities.contains(priority),
                      let status = row["Status"] as? String, statuses.contains(status),
                      row["Title"] is String, row["CreateTime"] is String, row["ModifyTime"] is String,
                      row["AssigneeId"] == nil, row["assigneeId"] == nil,
                      row["DueAt"] == nil, row["dueAt"] == nil,
                      row["IsEscalated"] == nil, row["isEscalated"] == nil,
                      row["EscalationReason"] == nil, row["escalationReason"] == nil else {
                    throw MobileAPIError.unavailable("工单列表内容无效，请刷新重试。")
                }
                ids.append(id)
            }
            guard Set(ids).count == ids.count, count >= loaded.count else {
                throw MobileAPIError.unavailable("工单列表回执无效，请刷新重试。")
            }
            let existing = Set(rows.compactMap { nativeSupportTicketId($0["Id"]) })
            guard count >= loaded.count, replacesLoadedRows || (!loaded.isEmpty && ids.allSatisfy { !existing.contains($0) } && count >= rows.count + loaded.count) else {
                throw MobileAPIError.unavailable("工单分页回执无效。")
            }
            if requestID == requestSequence && principal == expectedPrincipal {
                rows = replacesLoadedRows ? loaded : rows + loaded
                total = max(count, rows.count); page = target; failedPage = nil; error = nil
            }
        } catch {
            if requestID == requestSequence, !Task.isCancelled { failedPage = target; self.error = error.localizedDescription }
        }
    }

    private func startDetailLoad(_ row: [String: Any]) {
        cancelCreateWork()
        cancelReplyWork()
        detailTask?.cancel()
        writeSequence += 1
        submitting = false
        detailTask = Task { await openDetail(row) }
    }

    private func openDetail(_ row: [String: Any]) async {
        guard let id = nativeSupportTicketId(row["Id"]), let token else { return }
        guard let expectedPrincipal = nativeTourismPrincipal(token) else { error = "登录账号信息无效，请重新登录。"; return }
        if detailId != id {
            uploadSequence += 1
            uploading = false
            selectedPhotos = []
            photoPickerPrincipal = nil
            photoPickerTicketId = nil
            replyAttachments = []
            reply = ""
        }
        refreshReplyRecovery(id)
        requestSequence += 1
        let requestID = requestSequence
        mode = .detail; detail = nil; detailId = id; detailLoading = true; error = nil
        defer { if requestID == requestSequence { detailLoading = false } }
        do {
            guard let value = try await MobileAPI(store: store).get("/api/JHCTISupportTicket/GetMyDetail?id=\(id)", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any],
                  principal == expectedPrincipal,
                  nativeSupportTicketId(value["Id"]) == id else {
                throw MobileAPIError.unavailable("工单详情与所选编号不一致。")
            }
            guard let expectedUserId = nativeTourismPrincipal(token)?.split(separator: ":").first.map(String.init),
                  nativeSupportTicketId(expectedUserId) != nil,
                  isValidPublicSupportTicketDetail(value, expectedId: id, expectedUserId: expectedUserId) else {
                throw MobileAPIError.unavailable("工单详情回执无效，请刷新重试。")
            }
            if requestID == requestSequence { detail = value }
        } catch { if requestID == requestSequence, !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func isValidPublicSupportTicketDetail(_ value: [String: Any], expectedId: String, expectedUserId: String) -> Bool {
        let categories: Set<String> = ["Order", "Payment", "Account", "Resource", "Data", "Security", "Other"]
        let priorities: Set<String> = ["Normal", "High", "Urgent"]
        let statuses: Set<String> = ["Open", "Assigned", "PendingUser", "Resolved", "Closed"]
        guard nativeSupportTicketId(expectedId) != nil,
              nativeSupportTicketId(expectedUserId) != nil,
              nativeSupportTicketId(value["Id"]) == expectedId,
              nativeSupportTicketId(value["UserId"]) == expectedUserId,
              value["UserIdentityType"] as? String == "Tourism",
              let category = value["Category"] as? String, categories.contains(category),
              let priority = value["Priority"] as? String, priorities.contains(priority),
              let status = value["Status"] as? String, statuses.contains(status),
              value["AssigneeId"] == nil, value["assigneeId"] == nil,
              value["DueAt"] == nil, value["dueAt"] == nil,
              value["IsEscalated"] == nil, value["isEscalated"] == nil,
              value["EscalationReason"] == nil, value["escalationReason"] == nil,
              value["Title"] is String, value["TicketNo"] is String,
              value["CreateTime"] is String, value["ModifyTime"] is String,
              let messages = value["Messages"] as? [[String: Any]] else { return false }
        var messageIds = Set<String>()
        for message in messages {
            guard let id = nativeSupportTicketId(message["Id"]),
                  messageIds.insert(id).inserted,
                  let sender = message["SenderType"] as? String, ["User", "Support"].contains(sender),
                  message["IsInternal"] as? Bool == false,
                  message["Content"] is String, message["CreateTime"] is String,
                  let attachments = message["Attachments"] as? [String], attachments.count <= 8 else { return false }
            var attachmentUrls = Set<String>()
            for attachment in attachments {
                guard !attachment.isEmpty, attachment.utf16.count <= 1024, attachment == attachment.trimmingCharacters(in: .whitespacesAndNewlines),
                      attachment.rangeOfCharacter(from: .controlCharacters) == nil, !attachment.contains("\\"),
                      attachmentUrls.insert(attachment).inserted else { return false }
                if attachment.hasPrefix("/") {
                    guard !attachment.hasPrefix("//") else { return false }
                } else {
                    guard let components = URLComponents(string: attachment), components.scheme == "https",
                          let host = components.host, !host.isEmpty, components.user == nil, components.password == nil else { return false }
                }
            }
        }
        return true
    }

    private func ticketStorage(for principal: String, ticketID: String? = nil) -> NativeMerchantRecoveryStore<NativeSupportTicketAttempt>? {
        let parts = principal.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let userID = nativeSupportTicketId(String(parts[0])) else { return nil }
        if let ticketID {
            guard nativeSupportTicketId(ticketID) != nil else { return nil }
            return NativeMerchantRecoveryStore(directoryName: "jhcti-support-ticket-reply", principal: principal, scopeID: ticketID)
        }
        return NativeMerchantRecoveryStore(directoryName: "jhcti-support-ticket-create", principal: principal, scopeID: userID)
    }

    @discardableResult
    private func refreshCreateRecovery() -> NativeMerchantRecoveryState<NativeSupportTicketAttempt> {
        let recovery = principal.flatMap { ticketStorage(for: $0) }?.read() ?? .unavailable
        createRecovery = recovery
        return recovery
    }

    private func cancelCreateWork() {
        if let createTask {
            createTask.cancel()
            writeSequence += 1
            submitting = false
        }
        createTask = nil
        checkingCreate = false
        createRetry = nil
        createNotice = nil
    }

    private func ticketWriteIsCurrent(_ expectedPrincipal: String, _ writeID: Int) -> Bool {
        !Task.isCancelled && scenePhase == .active && writeID == writeSequence && principal == expectedPrincipal
    }

    private func startCreateCheck() {
        guard scenePhase == .active, !submitting, createTask == nil, let principal, principal == displayedPrincipal,
              case let .pending(attempt) = refreshCreateRecovery() else { return }
        writeSequence += 1
        let writeID = writeSequence
        checkingCreate = true
        createRetry = nil; createNotice = nil
        createTask = Task {
            await verifyCreate(attempt, principal: principal, writeID: writeID)
            if writeID == writeSequence { createTask = nil; checkingCreate = false }
        }
    }

    private func verifyCreate(_ attempt: NativeSupportTicketAttempt, principal expectedPrincipal: String,
                              writeID: Int, submittedID: String? = nil) async {
        guard ticketWriteIsCurrent(expectedPrincipal, writeID) else { return }
        do {
            let value = try await MobileAPI(store: store).get("/api/JHCTISupportTicket/GetMyCreateReceipt?idempotencyKey=\(attempt.key)",
                authenticated: true, expectedPrincipal: expectedPrincipal, requireExplicitResponse: true)
            guard ticketWriteIsCurrent(expectedPrincipal, writeID), refreshCreateRecovery() == .pending(attempt) else { return }
            let ticketID = try attempt.readReceipt(value)
            if let ticketID, submittedID == nil || ticketID == submittedID {
                let cleared = ticketStorage(for: expectedPrincipal)?.clear(.pending(attempt)) == true
                refreshCreateRecovery()
                createNotice = cleared ? nil : "已找到原工单，但未能清除待核对记录。"
                title = ""; content = ""; category = "Other"; ticketAttachments = []
                refreshListAfterWrite = true
                await openDetail(["Id": ticketID])
            } else if ticketID == nil && submittedID == nil {
                createRetry = attempt
                createNotice = "暂未查到已提交的工单。可用原请求号继续提交。"
            } else {
                createNotice = "提交结果待核对，请查询原工单。"
            }
        } catch {
            if ticketWriteIsCurrent(expectedPrincipal, writeID) { createNotice = error.localizedDescription }
        }
    }

    private func submitTicket() async {
        defer { if !Task.isCancelled { createTask = nil } }
        guard createTask != nil, !Task.isCancelled, scenePhase == .active, mode == .create,
              let principal, principal == displayedPrincipal, let storage = ticketStorage(for: principal), !submitting, !uploading else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, cleanTitle.utf16.count <= 160,
              !cleanContent.isEmpty, cleanContent.utf16.count <= 4000 else {
            error = "请填写问题标题和详细描述，标题最多 160 字、描述最多 4000 字。"; return
        }
        writeSequence += 1
        let writeID = writeSequence
        let attempt: NativeSupportTicketAttempt
        switch refreshCreateRecovery() {
        case .ready:
            attempt = NativeSupportTicketAttempt(key: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
            guard storage.save(attempt) else {
                if refreshCreateRecovery() != .ready { mode = .list; createNotice = "无法保存待核对记录，工单未发送。" }
                else { error = "无法保存待核对记录，工单未发送。" }
                return
            }
        case .pending(let pending) where pending == createRetry:
            attempt = pending
        default:
            mode = .list
            return
        }
        refreshCreateRecovery()
        createRetry = nil; createNotice = nil
        submitting = true; error = nil; mode = .list
        defer { if writeID == writeSequence { submitting = false } }
        do {
            let value = try await MobileAPI(store: store).post("/api/JHCTISupportTicket/CreateMyTicket",
                body: ["Category": category, "Title": cleanTitle, "Content": cleanContent,
                       "Attachments": ticketAttachments, "IdempotencyKey": attempt.key],
                authenticated: true, expectedPrincipal: principal, canRefresh: false, requireExplicitResponse: true)
            guard ticketWriteIsCurrent(principal, writeID) else { return }
            guard let id = nativeSupportTicketId(value) else {
                throw MobileAPIError.unavailable("建单回执格式异常。")
            }
            await verifyCreate(attempt, principal: principal, writeID: writeID, submittedID: id)
        } catch {
            if ticketWriteIsCurrent(principal, writeID) { createNotice = "提交结果待核对，请查询原工单。" }
        }
    }

    private var replyLookupLabel: String {
        if case .pending = replyRecovery { return "查询原留言" }
        return "重新读取"
    }

    @discardableResult
    private func refreshReplyRecovery(_ ticketID: String) -> NativeMerchantRecoveryState<NativeSupportTicketAttempt> {
        let recovery = principal.flatMap { ticketStorage(for: $0, ticketID: ticketID) }?.read() ?? .unavailable
        replyRecovery = recovery
        return recovery
    }

    private func cancelReplyWork() {
        if let replyTask {
            replyTask.cancel()
            writeSequence += 1
            submitting = false
        }
        replyTask = nil
        checkingReply = false
        replyRetry = nil
        replyNotice = nil
    }

    private func startReplyCheck() {
        guard scenePhase == .active, mode == .detail, let detail, let id = detailId,
              let principal, principal == displayedPrincipal, !submitting, !uploading, replyTask == nil else { return }
        let recovery = refreshReplyRecovery(id)
        replyRetry = nil; replyNotice = nil
        guard case let .pending(attempt) = recovery else { return }
        writeSequence += 1
        let writeID = writeSequence
        checkingReply = true
        let closed = (detail["Status"] as? String) == "Closed"
        replyTask = Task {
            await verifyReply(attempt, ticketID: id, principal: principal, writeID: writeID, closed: closed)
            if writeID == writeSequence { replyTask = nil; checkingReply = false }
        }
    }

    private func verifyReply(_ attempt: NativeSupportTicketAttempt, ticketID: String, principal expectedPrincipal: String,
                             writeID: Int, closed: Bool, afterSend: Bool = false) async {
        func isCurrent() -> Bool {
            ticketWriteIsCurrent(expectedPrincipal, writeID) && mode == .detail && detailId == ticketID
        }
        guard isCurrent() else { return }
        do {
            let receipt = try await MobileAPI(store: store).get(
                "/api/JHCTISupportTicket/GetMyMessageReceipt?ticketId=\(ticketID)&idempotencyKey=\(attempt.key)",
                authenticated: true, expectedPrincipal: expectedPrincipal, requireExplicitResponse: true)
            guard isCurrent(), refreshReplyRecovery(ticketID) == .pending(attempt) else { return }
            if try attempt.readReplyReceipt(receipt, ticketID: ticketID) != nil {
                let cleared = ticketStorage(for: expectedPrincipal, ticketID: ticketID)?.clear(.pending(attempt)) == true
                refreshReplyRecovery(ticketID)
                replyNotice = cleared ? "已确认原留言送达。" : "已确认原留言送达，但未能清除待核对记录。"
                reply = ""; replyAttachments = []; refreshListAfterWrite = true
                await openDetail(["Id": ticketID])
            } else if afterSend {
                replyNotice = "留言待核对，请查询原请求。"
            } else if closed {
                replyNotice = "暂未查到已提交的留言。此工单已关闭。"
            } else {
                replyRetry = attempt
                replyNotice = "暂未查到已提交的留言。可用原请求号继续发送。"
            }
        } catch {
            if isCurrent() { replyNotice = error.localizedDescription }
        }
    }

    private func submitReply() async {
        defer { if !Task.isCancelled { replyTask = nil } }
        guard !Task.isCancelled, scenePhase == .active, mode == .detail, let detail,
              (detail["Status"] as? String) != "Closed", let id = nativeSupportTicketId(detail["Id"]), detailId == id,
              let principal, principal == displayedPrincipal, !submitting, !uploading,
              let storage = ticketStorage(for: principal, ticketID: id) else { return }
        let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.utf16.count <= 4000, !clean.isEmpty || !replyAttachments.isEmpty else {
            error = clean.utf16.count > 4000 ? "留言最多 4000 字。" : "请填写留言内容或添加图片。"; return
        }
        let attempt: NativeSupportTicketAttempt
        switch refreshReplyRecovery(id) {
        case .ready:
            attempt = NativeSupportTicketAttempt(key: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
            guard storage.save(attempt) else {
                refreshReplyRecovery(id)
                replyNotice = "无法保存待核对记录，留言未发送。"
                return
            }
        case .pending(let pending) where pending == replyRetry:
            attempt = pending
        default: return
        }
        refreshReplyRecovery(id)
        replyRetry = nil; replyNotice = nil
        writeSequence += 1
        let writeID = writeSequence
        submitting = true; error = nil
        defer { if writeID == writeSequence { submitting = false } }
        do {
            let receipt = try await MobileAPI(store: store).post("/api/JHCTISupportTicket/AddMyMessage",
                body: ["TicketId": id, "Content": clean.isEmpty ? "补充图片" : clean,
                       "Attachments": replyAttachments, "IdempotencyKey": attempt.key],
                authenticated: true, expectedPrincipal: principal, canRefresh: false, requireExplicitResponse: true)
            guard ticketWriteIsCurrent(principal, writeID), mode == .detail, detailId == id else { return }
            guard nativeSupportTicketId(receipt) == id else {
                throw MobileAPIError.unavailable("留言回执格式异常。")
            }
            await verifyReply(attempt, ticketID: id, principal: principal, writeID: writeID, closed: false, afterSend: true)
        } catch {
            if ticketWriteIsCurrent(principal, writeID), mode == .detail, detailId == id {
                replyNotice = "留言结果待核对，请查询原留言。"
            }
        }
    }

    @ViewBuilder
    private func attachmentPicker(target: AttachmentTarget, urls: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("图片附件 · \(urls.count)/8").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                Spacer()
                Button(uploading ? "上传中…" : "添加图片") {
                    photoPickerTarget = target
                    photoPickerPrincipal = token.map { nativeTradeRecoveryStorageKey(accessToken: $0) }
                    photoPickerTicketId = detailId
                    selectedPhotos = []
                    photoPickerPresented = true
                }
                .disabled(uploading || submitting || urls.count >= 8)
            }
            ForEach(Array(urls.enumerated()), id: \.offset) { index, path in
                HStack {
                    if let url = MobileAPI(store: store).mediaURL(path) { Link("查看图片 \(index + 1)", destination: url) }
                    Button("移除") { removeAttachment(path, target: target) }
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                }
                .font(.system(size: NativeTypography.size(14)))
            }
        }
    }

    private func removeAttachment(_ path: String, target: AttachmentTarget) {
        switch target {
        case .ticket: ticketAttachments.removeAll { $0 == path }
        case .reply: replyAttachments.removeAll { $0 == path }
        }
    }

    private func uploadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard let token, !uploading, !submitting else { selectedPhotos = []; return }
        let identity = nativeTradeRecoveryStorageKey(accessToken: token)
        let target = photoPickerTarget
        let requestedTicketId = target == .reply ? detailId : nil
        guard photoPickerPrincipal == identity,
              target != .reply || photoPickerTicketId == requestedTicketId else {
            selectedPhotos = []
            return
        }
        guard (target == .ticket && mode == .create)
                || (target == .reply && mode == .detail && Int64(requestedTicketId ?? "").map({ $0 > 0 }) == true) else {
            selectedPhotos = []
            return
        }
        let currentCount = target == .ticket ? ticketAttachments.count : replyAttachments.count
        let selected = Array(items.prefix(max(0, 8 - currentCount)))
        uploadSequence += 1
        let requestedSequence = uploadSequence
        uploading = true; error = nil
        func isCurrentUpload() -> Bool {
            guard uploadSequence == requestedSequence,
                  identity == nativeTradeRecoveryStorageKey(accessToken: store.session?.accessToken ?? "") else { return false }
            switch target {
            case .ticket: return mode == .create
            case .reply: return mode == .detail && detailId == requestedTicketId
            }
        }
        defer {
            if uploadSequence == requestedSequence {
                uploading = false
                selectedPhotos = []
                photoPickerPrincipal = nil
                photoPickerTicketId = nil
            }
        }
        do {
            for item in selected {
                guard isCurrentUpload() else { return }
                let resized = try await prepareSupportTicketPhoto(item)
                guard isCurrentUpload() else { return }
                let objectNo = target == .ticket ? "0" : requestedTicketId ?? ""
                let path = try await MobileAPI(store: store).uploadSupportTicketAttachment(resized, objectNo: objectNo)
                guard isCurrentUpload() else { return }
                switch target {
                case .ticket: if !ticketAttachments.contains(path) { ticketAttachments.append(path) }
                case .reply: if !replyAttachments.contains(path) { replyAttachments.append(path) }
                }
            }
        } catch {
            if !Task.isCancelled, isCurrentUpload() { self.error = error.localizedDescription }
        }
    }

    private func prepareSupportTicketPhoto(_ item: PhotosPickerItem) async throws -> Data {
        guard let photo = try await item.loadTransferable(type: NativeSupportTicketPhoto.self) else {
            throw MobileAPIError.unavailable("图片读取失败或文件过大，请重新选择")
        }
        defer { try? FileManager.default.removeItem(at: photo.url) }

        let values = try photo.url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize > 0,
              fileSize <= NativeSupportTicketPhoto.maximumOriginalSize,
              let source = CGImageSourceCreateWithURL(photo.url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1920
              ] as CFDictionary) else {
            throw MobileAPIError.unavailable("图片读取失败或文件过大，请重新选择")
        }

        let image = UIImage(cgImage: thumbnail)
        let size = CGSize(width: max(1, image.size.width), height: max(1, image.size.height))
        let renderer = UIGraphicsImageRenderer(size: size)
        var quality: CGFloat = 0.82
        var resized = renderer.jpegData(withCompressionQuality: quality) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        while resized.count > 5 * 1024 * 1024 && quality > 0.5 {
            quality -= 0.08
            resized = renderer.jpegData(withCompressionQuality: quality) { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard resized.count <= 5 * 1024 * 1024 else {
            throw MobileAPIError.unavailable("图片压缩后仍超过 5 MB，请选择较小图片")
        }
        return resized
    }

    private func categoryName(_ value: String) -> String {
        ["Order": "订单问题", "Payment": "支付问题", "Account": "账号问题", "Resource": "景点与服务",
         "Data": "资料问题", "Security": "安全问题", "Other": "其他"][value] ?? "其他"
    }

    private func statusName(_ value: String) -> String {
        ["Open": "待处理", "Assigned": "处理中", "PendingUser": "待回复", "Resolved": "已解决", "Closed": "已关闭"][value] ?? "处理中"
    }
}
