import Foundation
import SwiftUI

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
        do {
            _ = try await MobileAPI(store: store).post(
                "/api/JHCTITourismResource/SaveMyScenic?merchantId=\(merchantID)", body: payload, authenticated: true,
                expectedPrincipal: requestedPrincipal
            )
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else {
                editing = nil; error = "账号已变化，资料保存结果请返回工作台确认。"; return
            }
            editing = nil; notice = "景点资料已保存为草稿"; revision += 1
        } catch is CancellationError {
            if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal {
                self.error = "景点资料保存结果未确认；请重新读取资料核对后再操作。"
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
        do {
            _ = try await MobileAPI(store: store).post(
                "/api/JHCTITourismResource/SubmitMyScenicReview?merchantId=\(merchantID)&resourceId=\(resourceID)",
                body: [:], authenticated: true, expectedPrincipal: requestedPrincipal
            )
            guard nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            notice = "已提交平台审核"; revision += 1
        } catch is CancellationError {
            if nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal {
                self.error = "审核申请结果未确认；请刷新景点审核状态后再操作。"
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
