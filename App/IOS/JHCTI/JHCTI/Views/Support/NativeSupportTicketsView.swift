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

struct NativeSupportTicketsView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
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
    @State private var createRequestKeys: [String: String] = [:]
    @State private var replyRequestKeys: [String: String] = [:]
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
                        }
                    }
                }
                if mode == .list {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("提交问题") { mode = .create; error = nil }
                            .disabled(token == nil)
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
        .task(id: token) {
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
            createRequestKeys.removeAll(); replyRequestKeys.removeAll()
            photoPickerPrincipal = nil; photoPickerTicketId = nil
            previewAttachment = nil; previewImage = nil; previewLoading = false
            error = nil
            guard token != nil else { error = "请先登录文旅账号，再提交问题或查看处理进度。"; return }
            await load(reset: true)
        }
    }

    private var ticketList: some View {
        List {
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
        .refreshable { await load(reset: true) }
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
                Button(submitting ? "正在提交…" : "提交给客服") { Task { await submitTicket() } }
                    .disabled(submitting || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var ticketDetail: some View {
        Group {
            if detailLoading { ProgressView("正在加载工单详情…") }
            else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(categoryName(detail["Category"] as? String ?? "Other")) · \(statusName(detail["Status"] as? String ?? ""))")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            Text(detail["Title"] as? String ?? "客服工单").font(.system(size: NativeTypography.size(20), weight: .bold))
                            Text("\(detail["TicketNo"] as? String ?? "") · 提交于 \(bookingBusinessDateTime(detail["CreateTime"]) ?? "时间未知")")
                                .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(Brand.background, in: RoundedRectangle(cornerRadius: 12))
                        ForEach(Array((detail["Messages"] as? [[String: Any]] ?? [])
                            .filter { $0["IsInternal"] as? Bool == false
                                && ["User", "Support"].contains($0["SenderType"] as? String ?? "") }
                            .enumerated()), id: \.offset) { _, message in
                            VStack(alignment: .leading, spacing: 7) {
                                Text("\((message["SenderType"] as? String) == "User" ? "我" : "客服") · \(bookingBusinessDateTime(message["CreateTime"]) ?? "时间未知")")
                                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                Text(message["Content"] as? String ?? "").font(.system(size: NativeTypography.size(14)))
                                ForEach(Array((message["Attachments"] as? [String] ?? []).enumerated()), id: \.offset) { index, path in
                                    if let url = MobileAPI(store: store).mediaURL(path) {
                                        HStack(spacing: 8) {
                                            Button { previewAttachment = url } label: {
                                                CachedRemoteImage(url: url) { Color.gray.opacity(0.15) }
                                                    .frame(width: 88, height: 88)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("预览附件图片 \(index + 1)")
                                            Link("在浏览器打开", destination: url)
                                                .font(.system(size: NativeTypography.size(14))).tint(Brand.primary)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background((message["SenderType"] as? String) == "User" ? Color(red: 0.91, green: 0.96, blue: 0.94) : Brand.background,
                                        in: RoundedRectangle(cornerRadius: 12))
                        }
                        if let error { Text(error).foregroundStyle(.red).font(.system(size: NativeTypography.size(14))) }
                        if (detail["Status"] as? String) != "Closed" {
                            TextField("补充说明或回复客服", text: $reply, axis: .vertical)
                                .lineLimit(4...8).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10))
                                .onChange(of: reply) { _, value in
                                    let limited = nativeLimitUtf16Text(value, maximum: 4000)
                                    if limited != value { reply = limited }
                                }
                            Text("\(reply.utf16.count)/4000").font(.system(size: NativeTypography.size(12)))
                                .foregroundStyle(Brand.muted).frame(maxWidth: .infinity, alignment: .trailing)
                            attachmentPicker(target: .reply, urls: replyAttachments)
                            Button(submitting ? "正在发送…" : "发送留言") { Task { await submitReply() } }
                                .buttonStyle(.borderedProminent).tint(Brand.primary)
                                .disabled(submitting || uploading || (reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && replyAttachments.isEmpty))
                        } else {
                            Text("工单已关闭，如仍需帮助，请重新提交问题。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted).frame(maxWidth: .infinity).padding()
                        }
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 10) {
                    ContentUnavailableView("无法读取工单", systemImage: "message", description: Text(error ?? "请返回列表后重试。"))
                    if let detailId { Button("重试") { startDetailLoad(["Id": detailId]) } }
                }
            }
        }
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
                  store.session?.accessToken == token,
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
            if requestID == requestSequence && store.session?.accessToken == token {
                rows = replacesLoadedRows ? loaded : rows + loaded
                total = max(count, rows.count); page = target; failedPage = nil; error = nil
            }
        } catch {
            if requestID == requestSequence, !Task.isCancelled { failedPage = target; self.error = error.localizedDescription }
        }
    }

    private func startDetailLoad(_ row: [String: Any]) {
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
        }
        requestSequence += 1
        let requestID = requestSequence
        mode = .detail; detail = nil; detailId = id; detailLoading = true; error = nil; reply = ""
        defer { if requestID == requestSequence { detailLoading = false } }
        do {
            guard let value = try await MobileAPI(store: store).get("/api/JHCTISupportTicket/GetMyDetail?id=\(id)", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any],
                  store.session?.accessToken == token,
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

    private func submitTicket() async {
        guard let token, !submitting, !uploading else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, cleanTitle.utf16.count <= 160,
              !cleanContent.isEmpty, cleanContent.utf16.count <= 4000 else {
            error = "请填写问题标题和详细描述，标题最多 160 字、描述最多 4000 字。"; return
        }
        writeSequence += 1
        let writeID = writeSequence
        submitting = true; error = nil
        defer { if writeID == writeSequence { submitting = false } }
        do {
            var body: [String: Any] = ["Category": category, "Title": cleanTitle, "Content": cleanContent,
                                       "Attachments": ticketAttachments]
            let signature = supportTicketRequestSignature(body)
            let requestKey = createRequestKeys[signature] ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            createRequestKeys[signature] = requestKey
            body["IdempotencyKey"] = requestKey
            let value = try await MobileAPI(store: store).post("/api/JHCTISupportTicket/CreateMyTicket",
                body: body, authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)) as? String
            guard writeID == writeSequence, store.session?.accessToken == token else { return }
            guard store.session?.accessToken == token, let id = nativeSupportTicketId(value) else {
                throw MobileAPIError.unavailable("提交结果无法确认，请返回列表刷新核对。")
            }
            createRequestKeys.removeAll()
            title = ""; content = ""; category = "Other"; ticketAttachments = []; mode = .list
            await load(reset: true)
        } catch let requestError {
            if writeID == writeSequence, store.session?.accessToken == token { self.error = requestError.localizedDescription }
        }
    }

    private func submitReply() async {
        guard let detail, let token, !submitting, let id = nativeSupportTicketId(detail["Id"]) else { return }
        let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.utf16.count <= 4000, !clean.isEmpty || !replyAttachments.isEmpty, !uploading else {
            error = clean.utf16.count > 4000 ? "留言最多 4000 字。" : "请填写留言内容或添加图片。"; return
        }
        writeSequence += 1
        let writeID = writeSequence
        submitting = true; error = nil
        defer { if writeID == writeSequence { submitting = false } }
        do {
            var body: [String: Any] = ["TicketId": id, "Content": clean.isEmpty ? "补充图片" : clean,
                                       "Attachments": replyAttachments]
            let signature = supportTicketRequestSignature(body)
            let requestKey = replyRequestKeys[signature] ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            replyRequestKeys[signature] = requestKey
            body["IdempotencyKey"] = requestKey
            let receipt = try await MobileAPI(store: store).post("/api/JHCTISupportTicket/AddMyMessage",
                body: body, authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)) as? String
            guard writeID == writeSequence, store.session?.accessToken == token else { return }
            guard nativeSupportTicketId(receipt) == id else {
                throw MobileAPIError.unavailable("留言结果无法确认，请重新打开工单核对。")
            }
            replyRequestKeys.removeAll()
            if mode == .detail, detailId == id {
                reply = ""; replyAttachments = []
                await openDetail(["Id": id])
                await load(reset: true)
            } else if mode == .list {
                await load(reset: true)
            }
        } catch let requestError {
            if writeID == writeSequence, store.session?.accessToken == token { self.error = requestError.localizedDescription }
        }
    }

    private func supportTicketRequestSignature(_ body: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return UUID().uuidString }
        return data.base64EncodedString()
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
