import Foundation
import SwiftUI

struct MerchantActivityWorkView: View {
    @ObservedObject var store: SessionStore
    let merchantID: String
    @State private var rows: [[String: Any]] = []
    @State private var total = 0
    @State private var page = 1
    @State private var loading = false
    @State private var saving = false
    @State private var submittingID = ""
    @State private var error: String?
    @State private var notice: String?
    @State private var editing: [String: Any]?
    @State private var name = ""
    @State private var description = ""
    @State private var venue = ""
    @State private var organizer = ""
    @State private var contactPhone = ""
    @State private var imageURLs = ""
    @State private var signupStart = ""
    @State private var signupEnd = ""
    @State private var activityStart = ""
    @State private var activityEnd = ""
    @State private var capacity = "100"
    @State private var revision = 0
    @State private var requestSequence = 0

    private var principal: String? { nativeTourismPrincipal(store.session?.accessToken) }
    private var isReadOnly: Bool { Self.intValue(editing?["ReviewStatus"] ?? editing?["reviewStatus"], fallback: -1) == 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("仅商户管理员可维护本商户主办活动；发布时间、推荐配置和审核结果由平台管理。")
                    .font(.caption).foregroundStyle(Brand.muted)
                if let notice { Text(notice).font(.caption).foregroundStyle(Brand.primary) }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                if let resource = editing {
                    activityEditor(resource)
                } else {
                    HStack {
                        Button("新建活动") { openNew() }.buttonStyle(.borderedProminent).tint(Brand.primary)
                        Button("刷新") { Task { await load(page: 1) } }.buttonStyle(.bordered).disabled(loading)
                    }
                    if loading && rows.isEmpty { ProgressView("正在读取活动…") }
                    if !loading && error == nil && rows.isEmpty { Text("当前商户暂无经营活动。").foregroundStyle(Brand.muted) }
                    ForEach(rows.indices, id: \.self) { index in activityCard(rows[index]) }
                    if !loading && rows.count < total {
                        Button(page >= (total + 19) / 20 ? "返回第一页" : "下一页") {
                            Task { await load(page: page >= (total + 19) / 20 ? 1 : page + 1) }
                        }.buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(loading)
                    }
                }
            }
            .padding(16)
        }
        .background(Brand.background)
        .navigationTitle(editing == nil ? "经营活动" : (Self.text(editing?["Id"]) == "0" ? "新建经营活动" : "编辑活动"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(revision)-\(merchantID)-\(principal ?? "")") { if editing == nil { await load(page: 1) } }
        .onChange(of: principal) { _, _ in
            requestSequence += 1; rows = []; total = 0; editing = nil; resetDraft()
            error = nil; notice = nil; loading = false; saving = false; submittingID = ""
        }
        .onDisappear { requestSequence += 1; editing = nil; resetDraft() }
    }

    private func activityCard(_ row: [String: Any]) -> some View {
        let id = Self.text(row["Id"] ?? row["id"])
        let status = Self.intValue(row["ReviewStatus"] ?? row["reviewStatus"], fallback: -1)
        let publication = Self.text(row["PublicationStatus"] ?? row["publicationStatus"])
        let remark = Self.text(row["ReviewRemark"] ?? row["reviewRemark"])
        return VStack(alignment: .leading, spacing: 8) {
            Text(Self.text(row["Name"] ?? row["name"]).isEmpty ? "未命名活动" : Self.text(row["Name"] ?? row["name"]))
                .font(.system(size: NativeTypography.size(16), weight: .semibold))
            Text("审核状态：\(Self.reviewLabel(status))\(publication.isEmpty ? "" : " · \(publication)")")
                .font(.caption).foregroundStyle(Brand.muted)
            if !remark.isEmpty { Text("审核意见：\(remark)").font(.caption).foregroundStyle(Brand.muted) }
            HStack(spacing: 10) {
                Button(status == 1 ? "审核中" : "编辑资料") { Task { await openEditor(row: row) } }
                    .buttonStyle(.bordered).disabled(status == 1)
                if status == 0 || status == 3 {
                    Button(submittingID == id ? "提交中…" : "提交审核") { Task { await submit(id: id) } }
                        .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(!submittingID.isEmpty)
                }
            }
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder private func activityEditor(_ resource: [String: Any]) -> some View {
        Group {
            field("活动名称", text: $name, limit: 160)
            field("活动介绍", text: $description, limit: 4000, multiline: true)
            field("举办地点", text: $venue, limit: 200)
            field("主办方", text: $organizer, limit: 160)
            field("联系电话", text: $contactPhone, limit: 24)
            field("图片地址（每行一个）", text: $imageURLs, limit: 4000, multiline: true)
            field("报名开始（北京时间）", text: $signupStart, limit: 16, placeholder: "YYYY-MM-DD HH:mm")
            field("报名截止（北京时间）", text: $signupEnd, limit: 16, placeholder: "YYYY-MM-DD HH:mm")
            if Self.array(resource["Sessions"] ?? resource["sessions"]).isEmpty {
                field("活动开始（北京时间）", text: $activityStart, limit: 16, placeholder: "YYYY-MM-DD HH:mm")
                field("活动结束（北京时间）", text: $activityEnd, limit: 16, placeholder: "YYYY-MM-DD HH:mm")
                field("报名名额", text: $capacity, limit: 7)
            } else {
                Text("此活动已配置场次；保存时会保留场次、报名字段和名额。如需调整场次，请在管理端处理。")
                    .font(.caption).foregroundStyle(Brand.muted)
            }
        }
        .disabled(isReadOnly)
        Text("保存会将活动置为草稿；地图、报名字段、已有场次和平台推荐配置会保留。")
            .font(.caption).foregroundStyle(Brand.muted)
        if isReadOnly {
            Text("活动正在审核中，当前只能查看。").font(.caption).foregroundStyle(Brand.muted)
        } else {
            Button(saving ? "正在保存…" : "保存草稿") { Task { await saveDraft(resource: resource) } }
                .buttonStyle(.borderedProminent).tint(Brand.primary)
                .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("取消") { editing = nil; error = nil }.buttonStyle(.bordered)
        }
    }

    private func field(_ title: String, text: Binding<String>, limit: Int, multiline: Bool = false, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(Brand.muted)
            if multiline {
                TextEditor(text: text).frame(minHeight: 86).padding(5)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: text.wrappedValue) { _, value in if value.count > limit { text.wrappedValue = String(value.prefix(limit)) } }
            } else {
                TextField(placeholder.isEmpty ? title : placeholder, text: text).textFieldStyle(.roundedBorder)
                    .onChange(of: text.wrappedValue) { _, value in if value.count > limit { text.wrappedValue = String(value.prefix(limit)) } }
            }
        }
    }

    @MainActor private func load(page targetPage: Int) async {
        guard Int64(merchantID).map({ $0 > 0 }) == true,
              let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token), principal == requestedPrincipal else {
            rows = []; total = 0; error = "当前账号或商户范围无效，请返回工作台重新进入。"; loading = false; return
        }
        requestSequence += 1; let sequence = requestSequence
        loading = true; error = nil; notice = nil
        do {
            guard let response = try await MobileAPI(store: store).get(
                "/api/JHCTIActivity/GetMyMerchantActivityPage?merchantId=\(merchantID)&page=\(targetPage)&pageSize=20", authenticated: true,
                expectedPrincipal: requestedPrincipal
            ) as? [String: Any],
            let loaded = response["data"] as? [[String: Any]] ?? response["Data"] as? [[String: Any]] else {
                throw MobileAPIError.unavailable("活动列表响应格式异常，请重试。")
            }
            let count = Self.intValue(response["dataCount"] ?? response["DataCount"], fallback: -1)
            guard loaded.count <= 20, count >= loaded.count, count >= 0,
                  loaded.allSatisfy({ Int64(Self.text($0["Id"] ?? $0["id"])).map({ $0 > 0 }) == true }) else {
                throw MobileAPIError.unavailable("活动分页数据无效，请刷新重试。")
            }
            guard requestSequence == sequence, nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            rows = loaded; total = count; page = targetPage
        } catch is CancellationError {
            // 页面离开或刷新替换请求时，不把取消显示成活动读取故障。
        } catch {
            guard requestSequence == sequence, nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            self.error = error.localizedDescription
        }
        if requestSequence == sequence { loading = false }
    }

    private func openNew() {
        resetDraft()
        editing = ["Id": "0", "Version": 0, "ReviewStatus": 0, "ImageUrls": [String](), "Sessions": [[String: Any]](), "SignupFields": [[String: Any]]()]
        error = nil; notice = nil
    }

    @MainActor private func openEditor(row: [String: Any]) async {
        let id = Self.text(row["Id"] ?? row["id"])
        guard !id.isEmpty, let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token), principal == requestedPrincipal else {
            error = "账号已变化，请返回工作台重新进入。"; return
        }
        do {
            guard let resource = try await MobileAPI(store: store).get(
                "/api/JHCTIActivity/GetMyMerchantActivity?merchantId=\(merchantID)&id=\(id)", authenticated: true,
                expectedPrincipal: requestedPrincipal
            ) as? [String: Any] else { throw MobileAPIError.unavailable("活动资料响应格式异常，请重试。") }
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            editing = resource; name = Self.text(resource["Name"] ?? resource["name"])
            description = Self.text(resource["Description"] ?? resource["description"])
            venue = Self.text(resource["Venue"] ?? resource["venue"]); organizer = Self.text(resource["Organizer"] ?? resource["organizer"])
            contactPhone = Self.text(resource["ContactPhone"] ?? resource["contactPhone"])
            imageURLs = Self.array(resource["ImageUrls"] ?? resource["imageUrls"]).compactMap { $0 as? String }.joined(separator: "\n")
            signupStart = Self.businessInput(resource["SignupStartTime"] ?? resource["signupStartTime"])
            signupEnd = Self.businessInput(resource["SignupEndTime"] ?? resource["signupEndTime"])
            activityStart = Self.businessInput(resource["ActivityStartTime"] ?? resource["activityStartTime"])
            activityEnd = Self.businessInput(resource["ActivityEndTime"] ?? resource["activityEndTime"])
            capacity = String(Self.intValue(resource["Capacity"] ?? resource["capacity"], fallback: 100))
            error = nil; notice = nil
        } catch is CancellationError {
            // 关闭编辑页或切换账号时，忽略已取消的活动详情读取。
        } catch {
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            self.error = error.localizedDescription
        }
    }

    @MainActor private func saveDraft(resource: [String: Any]) async {
        guard !saving, !isReadOnly, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token), principal == requestedPrincipal else {
            error = "账号已变化或活动名称为空，未保存。"; return
        }
        let hasSessions = !Self.array(resource["Sessions"] ?? resource["sessions"]).isEmpty
        let imageList = imageURLs.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let phoneDigits = contactPhone.filter { $0 >= "0" && $0 <= "9" }.count
        guard imageList.count <= 20, imageList.allSatisfy(Self.isSafeImageURL) else {
            error = "活动图片最多 20 张，且仅支持 HTTPS 或站内相对地址。"; return
        }
        guard contactPhone.trimmingCharacters(in: .whitespaces).isEmpty ||
                (phoneDigits >= 7 && phoneDigits <= 20 && contactPhone.allSatisfy({ ($0 >= "0" && $0 <= "9") || "+- ()".contains($0) })) else {
            error = "联系电话格式无效，请检查数字和符号。"; return
        }
        guard let signupStartValue = Self.businessPayload(signupStart),
              let signupEndValue = Self.businessPayload(signupEnd),
              hasSessions || (Self.businessPayload(activityStart) != nil && Self.businessPayload(activityEnd) != nil) else {
            error = "请按 YYYY-MM-DD HH:mm 填写有效的北京时间。"; return
        }
        let capacityValue = Int(capacity)
        guard hasSessions || (capacityValue.map { (1...1_000_000).contains($0) } == true) else {
            error = "活动名额须为 1 至 1000000 的整数。"; return
        }
        saving = true; error = nil; notice = nil
        var payload = resource
        payload["Name"] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        payload["Description"] = description; payload["Venue"] = venue; payload["Organizer"] = organizer
        payload["ContactPhone"] = contactPhone
        payload["ImageUrls"] = imageList
        payload["SignupStartTime"] = signupStartValue; payload["SignupEndTime"] = signupEndValue
        payload["ActivityStartTime"] = hasSessions ? NSNull() : Self.businessPayload(activityStart)
        payload["ActivityEndTime"] = hasSessions ? NSNull() : Self.businessPayload(activityEnd)
        payload["Capacity"] = hasSessions ? Self.intValue(resource["Capacity"] ?? resource["capacity"]) : (capacityValue ?? 0)
        var committed = false
        do {
            _ = try await MobileAPI(store: store).post(
                "/api/JHCTIActivity/SaveMyMerchantActivity?merchantId=\(merchantID)", body: payload, authenticated: true,
                expectedPrincipal: requestedPrincipal
            )
            committed = true
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else {
                editing = nil; error = "账号已变化，保存结果请返回工作台确认。"; return
            }
            editing = nil; notice = "经营活动已保存为草稿"; revision += 1
        } catch is CancellationError {
            if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal {
                self.error = committed
                    ? "服务端已确认活动保存，但页面状态更新被取消；请重新读取确认当前状态。"
                    : "活动保存结果未确认；请重新读取活动资料核对后再操作。"
            }
        } catch {
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            self.error = error.localizedDescription
        }
        if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal { saving = false }
    }

    @MainActor private func submit(id: String) async {
        guard !id.isEmpty, submittingID.isEmpty, let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token), principal == requestedPrincipal else {
            error = "账号已变化，请返回工作台重新进入。"; return
        }
        submittingID = id; error = nil; notice = nil
        var committed = false
        do {
            _ = try await MobileAPI(store: store).post(
                "/api/JHCTIActivity/SubmitMyMerchantActivityReview?merchantId=\(merchantID)&id=\(id)", body: [:], authenticated: true,
                expectedPrincipal: requestedPrincipal
            )
            committed = true
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            notice = "已提交平台审核"; revision += 1
        } catch is CancellationError {
            if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal {
                self.error = committed
                    ? "服务端已确认审核申请，但页面状态更新被取消；请重新读取审核状态。"
                    : "审核申请结果未确认；请刷新活动审核状态后再操作。"
            }
        } catch {
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            self.error = error.localizedDescription
        }
        if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal { submittingID = "" }
    }

    private func resetDraft() {
        name = ""; description = ""; venue = ""; organizer = ""; contactPhone = ""; imageURLs = ""
        signupStart = ""; signupEnd = ""; activityStart = ""; activityEnd = ""; capacity = "100"
    }

    private static func text(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return value as? String ?? String(describing: value)
    }
    private static func array(_ value: Any?) -> [Any] { value as? [Any] ?? [] }
    private static func isSafeImageURL(_ value: String) -> Bool {
        let url = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasPrefix("/"), !url.hasPrefix("//"), !url.contains("\\"),
           url.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) { return true }
        guard let components = URLComponents(string: url), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty else { return false }
        return true
    }
    private static func intValue(_ value: Any?, fallback: Int = 0) -> Int {
        guard let value, !(value is NSNull) else { return fallback }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? fallback }
        return fallback
    }
    private static func reviewLabel(_ status: Int) -> String {
        switch status { case 0: "草稿"; case 1: "待审核"; case 2: "已通过"; case 3: "已驳回"; default: "待确认" }
    }
    private static func businessInput(_ value: Any?) -> String {
        let raw = text(value)
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: raw) {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: date)
        }
        return String(raw.replacingOccurrences(of: "T", with: " ").prefix(16))
    }
    private static func businessPayload(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "T")
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.isLenient = false
        guard let date = formatter.date(from: normalized), formatter.string(from: date) == normalized else { return nil }
        return "\(normalized):00"
    }
}

struct MerchantScenicWorkView: View {
    @ObservedObject var store: SessionStore
    let merchantID: String
    @State private var rows: [[String: Any]] = []
    @State private var total = 0
    @State private var page = 1
    @State private var loading = false
    @State private var saving = false
    @State private var submitting = false
    @State private var error: String?
    @State private var notice: String?
    @State private var editing: [String: Any]?
    @State private var name = ""
    @State private var description = ""
    @State private var address = ""
    @State private var openingHours = ""
    @State private var contactPhone = ""
    @State private var visitorNotice = ""
    @State private var imageURLs = ""
    @State private var revision = 0
    @State private var requestSequence = 0

    private var principal: String? { nativeTourismPrincipal(store.session?.accessToken) }
    private var readOnly: Bool { Self.intValue(editing?["ReviewStatus"] ?? editing?["reviewStatus"], fallback: -1) == 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("仅维护已授权景点的基础经营资料；经营归属、预约场次和平台推荐配置由平台管理。")
                    .font(.caption).foregroundStyle(Brand.muted)
                if let notice { Text(notice).font(.caption).foregroundStyle(Brand.primary) }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }

                if let resource = editing {
                    editor(resource)
                } else {
                    Button("刷新景点") { Task { await load(page: 1) } }
                        .buttonStyle(.bordered).disabled(loading)
                    StatusView(loading: loading, error: error) { revision += 1 }
                    if !loading && error == nil && rows.isEmpty {
                        Text("当前商户下暂无获授权景点。").foregroundStyle(Brand.muted)
                    }
                    ForEach(rows.indices, id: \.self) { index in resourceCard(rows[index]) }
                    if !loading && rows.count < total {
                        Button(page >= (total + 19) / 20 ? "返回第一页" : "下一页") {
                            Task { await load(page: page >= (total + 19) / 20 ? 1 : page + 1) }
                        }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(loading)
                    }
                }
            }
            .padding(16)
        }
        .background(Brand.background)
        .navigationTitle(editing == nil ? "景点经营资料" : "编辑景点资料")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(revision)-\(merchantID)-\(principal ?? "")") {
            if editing == nil { await load(page: 1) }
        }
        .onChange(of: principal) { _, _ in
            requestSequence += 1
            rows = []; total = 0; editing = nil; name = ""; description = ""; address = ""
            openingHours = ""; contactPhone = ""; visitorNotice = ""; imageURLs = ""
            error = nil; notice = nil; loading = false; saving = false; submitting = false
        }
        .onDisappear {
            requestSequence += 1
            editing = nil; name = ""; description = ""; address = ""
            openingHours = ""; contactPhone = ""; visitorNotice = ""; imageURLs = ""
        }
    }

    private func resourceCard(_ row: [String: Any]) -> some View {
        let id = Self.text(row["Id"] ?? row["id"])
        let status = Self.intValue(row["ReviewStatus"] ?? row["reviewStatus"], fallback: -1)
        let statusName = Self.reviewLabel(status)
        let remark = Self.text(row["ReviewRemark"] ?? row["reviewRemark"])
        return VStack(alignment: .leading, spacing: 8) {
            Text(Self.text(row["Name"] ?? row["name"]).isEmpty ? "未命名景点" : Self.text(row["Name"] ?? row["name"]))
                .font(.system(size: NativeTypography.size(16), weight: .semibold))
            Text("审核状态：\(statusName)\(remark.isEmpty ? "" : " · \(remark)")")
                .font(.caption).foregroundStyle(Brand.muted)
            HStack(spacing: 10) {
                Button(status == 1 ? "查看资料" : "编辑资料") { Task { await openEditor(id: id) } }
                    .buttonStyle(.bordered)
                if status == 0 || status == 3 {
                    Button("提交审核") { Task { await submit(resourceID: id) } }
                        .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(submitting)
                }
            }
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder private func editor(_ resource: [String: Any]) -> some View {
        Group {
            field("景点名称", text: $name, limit: 120)
            field("景点简介", text: $description, limit: 2000, multiline: true)
            field("地址", text: $address, limit: 300)
            field("开放时间", text: $openingHours, limit: 300)
            field("联系电话", text: $contactPhone, limit: 50)
            field("游览须知", text: $visitorNotice, limit: 2000, multiline: true)
            field("图片地址（每行一个）", text: $imageURLs, limit: 4000, multiline: true)
        }
        .disabled(readOnly)
        Text("保存仅更新经营资料并进入草稿；地图、预约方式、场次与推荐设置会保留。")
            .font(.caption).foregroundStyle(Brand.muted)
        if readOnly {
            Text("资料正在审核中，当前只能查看。").font(.caption).foregroundStyle(Brand.muted)
        } else {
            Button(saving ? "正在保存…" : "保存草稿") { Task { await saveDraft(resource: resource) } }
                .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("取消编辑") { editing = nil; error = nil }
                .buttonStyle(.bordered)
        }
    }

    private func field(_ title: String, text: Binding<String>, limit: Int, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(Brand.muted)
            if multiline {
                TextEditor(text: text).frame(minHeight: 86).padding(5)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: text.wrappedValue) { _, value in
                        if value.count > limit { text.wrappedValue = String(value.prefix(limit)) }
                    }
            } else {
                TextField(title, text: text).textFieldStyle(.roundedBorder)
                    .onChange(of: text.wrappedValue) { _, value in
                        if value.count > limit { text.wrappedValue = String(value.prefix(limit)) }
                    }
            }
        }
    }

    @MainActor private func load(page targetPage: Int) async {
        guard Int64(merchantID).map({ $0 > 0 }) == true,
              let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token), principal == requestedPrincipal else {
            rows = []; total = 0; error = "当前账号或商户范围无效，请返回工作台重新进入。"; loading = false; return
        }
        requestSequence += 1
        let sequence = requestSequence
        loading = true; error = nil; notice = nil
        do {
            guard let response = try await MobileAPI(store: store).get(
                "/api/JHCTITourismResource/GetMyScenicPage?merchantId=\(merchantID)&page=\(targetPage)&pageSize=20",
                authenticated: true, expectedPrincipal: requestedPrincipal
            ) as? [String: Any],
            let loaded = response["data"] as? [[String: Any]] ?? response["Data"] as? [[String: Any]] else {
                throw MobileAPIError.unavailable("景点列表响应格式异常，请重试。")
            }
            let count = Self.intValue(response["dataCount"] ?? response["DataCount"], fallback: -1)
            guard loaded.count <= 20, count >= loaded.count, count >= 0,
                  loaded.allSatisfy({ Int64(Self.text($0["Id"] ?? $0["id"])).map({ $0 > 0 }) == true }) else {
                throw MobileAPIError.unavailable("景点分页数据无效，请刷新重试。")
            }
            guard requestSequence == sequence, nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            rows = loaded; total = count; page = targetPage
        } catch is CancellationError {
            // 页面离开或刷新替换请求时，不把取消显示成景点读取故障。
        } catch {
            guard requestSequence == sequence, nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            self.error = error.localizedDescription
        }
        if requestSequence == sequence { loading = false }
    }

    @MainActor private func openEditor(id: String) async {
        guard !id.isEmpty, let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token), principal == requestedPrincipal else {
            error = "账号已变化，请返回工作台重新进入。"; return
        }
        do {
            guard let resource = try await MobileAPI(store: store).get(
                "/api/JHCTITourismResource/GetMyScenic?merchantId=\(merchantID)&resourceId=\(id)",
                authenticated: true, expectedPrincipal: requestedPrincipal
            ) as? [String: Any] else { throw MobileAPIError.unavailable("景点资料响应格式异常，请重试。") }
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            editing = resource
            name = Self.text(resource["Name"] ?? resource["name"])
            description = Self.text(resource["Description"] ?? resource["description"])
            address = Self.text(resource["Address"] ?? resource["address"])
            openingHours = Self.text(resource["OpeningHours"] ?? resource["openingHours"])
            contactPhone = Self.text(resource["ContactPhone"] ?? resource["contactPhone"])
            visitorNotice = Self.text(resource["Notice"] ?? resource["notice"])
            let urls = resource["ImageUrls"] as? [String] ?? resource["imageUrls"] as? [String] ?? []
            imageURLs = urls.joined(separator: "\n")
            error = nil; notice = nil
        } catch is CancellationError {
            // 关闭编辑页或切换账号时，忽略已取消的详情读取。
        } catch {
            if !Task.isCancelled, nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal {
                self.error = error.localizedDescription
            }
        }
    }

    @MainActor private func saveDraft(resource: [String: Any]) async {
        guard !saving, !readOnly, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token), principal == requestedPrincipal else {
            error = "账号已变化或景点名称为空，未保存。"; return
        }
        saving = true; error = nil; notice = nil
        var payload = resource
        payload["Name"] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        payload["Description"] = description
        payload["Address"] = address
        payload["OpeningHours"] = openingHours
        payload["ContactPhone"] = contactPhone
        payload["Notice"] = visitorNotice
        payload["ImageUrls"] = imageURLs.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var committed = false
        do {
            _ = try await MobileAPI(store: store).post(
                "/api/JHCTITourismResource/SaveMyScenic?merchantId=\(merchantID)", body: payload, authenticated: true,
                expectedPrincipal: requestedPrincipal
            )
            committed = true
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else {
                editing = nil; error = "账号已变化，资料保存结果请返回工作台确认。"; return
            }
            editing = nil; notice = "景点资料已保存为草稿"; revision += 1
        } catch is CancellationError {
            if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal {
                self.error = committed
                    ? "服务端已确认景点资料保存，但页面状态更新被取消；请重新读取确认当前状态。"
                    : "景点资料保存结果未确认；请重新读取资料核对后再操作。"
            }
        } catch {
            if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal {
                self.error = error.localizedDescription
            }
        }
        if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal { saving = false }
    }

    @MainActor private func submit(resourceID: String) async {
        guard !submitting, !resourceID.isEmpty, let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token), principal == requestedPrincipal else {
            error = "账号已变化，请返回工作台重新进入。"; return
        }
        submitting = true
        error = nil; notice = nil
        var committed = false
        do {
            _ = try await MobileAPI(store: store).post(
                "/api/JHCTITourismResource/SubmitMyScenicReview?merchantId=\(merchantID)&resourceId=\(resourceID)",
                body: [:], authenticated: true, expectedPrincipal: requestedPrincipal
            )
            committed = true
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            notice = "已提交平台审核"; revision += 1
        } catch is CancellationError {
            if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal {
                self.error = committed
                    ? "服务端已确认审核申请，但页面状态更新被取消；请重新读取审核状态。"
                    : "审核申请结果未确认；请刷新景点审核状态后再操作。"
            }
        } catch { self.error = error.localizedDescription }
        if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal { submitting = false }
    }

    private static func text(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return value as? String ?? String(describing: value)
    }
    private static func intValue(_ value: Any?, fallback: Int = 0) -> Int {
        guard let value, !(value is NSNull) else { return fallback }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? fallback }
        return fallback
    }
    private static func reviewLabel(_ value: Int) -> String {
        switch value { case 0: "草稿"; case 1: "待审核"; case 2: "已通过"; case 3: "已驳回"; default: "待确认" }
    }
}
