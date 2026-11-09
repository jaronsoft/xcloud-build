import Foundation
import SwiftUI

private struct NativeMerchantStaffRole: Identifiable {
    let code: String
    let title: String
    var id: String { code }
}

struct MerchantStaffView: View {
    @ObservedObject var store: SessionStore
    let merchantID: String
    @State private var stores: [[String: Any]]
    @State private var roles: [[String: Any]]
    @State private var staff: [[String: Any]] = []
    @State private var candidates: [[String: Any]] = []
    @State private var candidate: [String: Any]?
    @State private var editing: [String: Any]?
    @State private var keyword = ""
    @State private var roleCode = "Order"
    @State private var storeID = ""
    @State private var loading = false
    @State private var searching = false
    @State private var saving = false
    @State private var writeOutcomeUnknown = false
    @State private var error: String?
    @State private var notice: String?
    @State private var pendingRevoke: [String: Any]?
    @State private var revision = 0
    @State private var requestSequence = 0

    private let roleChoices = [
        NativeMerchantStaffRole(code: "Order", title: "订单处理"),
        NativeMerchantStaffRole(code: "Product", title: "商品管理"),
        NativeMerchantStaffRole(code: "Verifier", title: "到店核销"),
        NativeMerchantStaffRole(code: "CouponVerifier", title: "平台消费券核销"),
        NativeMerchantStaffRole(code: "TicketVerifier", title: "门票核销"),
        NativeMerchantStaffRole(code: "ActivityVerifier", title: "活动核验员"),
        NativeMerchantStaffRole(code: "FinanceReadOnly", title: "财务只读"),
        NativeMerchantStaffRole(code: "ReportReadOnly", title: "报表只读")
    ]
    private let platformAssignedRoles: Set<String> = ["MerchantAdmin", "ActivityVerifier", "FinanceReadOnly", "ReportReadOnly"]

    init(store: SessionStore, merchantID: String, stores: [[String: Any]], roles: [[String: Any]]) {
        self.store = store
        self.merchantID = merchantID
        _stores = State(initialValue: stores)
        _roles = State(initialValue: roles)
    }

    private var principal: String? { nativeTourismPrincipal(store.session?.accessToken) }
    private var loadTaskID: String { [String(revision), merchantID, principal ?? ""].joined(separator: "-") }
    private var managerScopes: [[String: Any]] {
        roles.filter { Self.text($0["RoleCode"]) == "MerchantAdmin" && $0["StoreEnabled"] as? Bool != false }
    }
    private var hasMerchantWideAdmin: Bool { managerScopes.contains { Self.text($0["StoreId"]) == "0" } }
    private var writableStoreIDs: Set<String> { Set(managerScopes.map { Self.text($0["StoreId"]) }.filter { $0 != "0" }) }
    private var writableStores: [[String: Any]] {
        hasMerchantWideAdmin ? stores : stores.filter { writableStoreIDs.contains(Self.text($0["Id"])) }
    }
    private var availableRoles: [NativeMerchantStaffRole] {
        roleChoices.filter { !platformAssignedRoles.contains($0.code) }
    }
    private var selectedRole: NativeMerchantStaffRole? { availableRoles.first { $0.code == roleCode } }
    private var storeOptions: [[String: Any]] { writableStores }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
        Text("仅商户管理员可维护员工岗位。员工授权须指定门店；商户级及平台专属岗位由平台管理。")
                    .font(.caption).foregroundStyle(Brand.muted)
                if let notice { Text(notice).font(.caption).foregroundStyle(Brand.primary) }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                editorCard
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("当前授权").font(.headline); Spacer(); Text("\(staff.count) 项").font(.caption).foregroundStyle(Brand.muted) }
                    if loading && staff.isEmpty { ProgressView("正在读取员工授权…") }
                    else if staff.isEmpty { Text("当前授权范围内没有员工记录。").font(.caption).foregroundStyle(Brand.muted) }
                    ForEach(staff.indices, id: \.self) { index in staffCard(staff[index]) }
                }.merchantCard()
            }.padding(16)
        }
        .background(Brand.background)
        .navigationTitle("员工授权")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadTaskID) { await load() }
        .onAppear {
            if store.hasUnknownMerchantStaffMutation(for: merchantID) { writeOutcomeUnknown = true }
        }
        .onChange(of: principal) { _, _ in
            requestSequence += 1; staff = []; candidates = []; candidate = nil; editing = nil
            keyword = ""; roleCode = "Order"; storeID = ""; error = nil; notice = nil
            loading = false; searching = false; saving = false
        }
        .onChange(of: roleCode) { _, next in adjustStoreScope(for: next) }
        .onDisappear { requestSequence += 1; candidates = []; candidate = nil; editing = nil; keyword = "" }
        .alert("确认撤销员工授权？", isPresented: Binding(
            get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } }
        )) {
            Button("撤销授权", role: .destructive) {
                if let pendingRevoke { Task { await revoke(pendingRevoke) } }
            }
            Button("取消", role: .cancel) { pendingRevoke = nil }
        } message: {
            Text("撤销后该员工将无法继续使用对应岗位权限。")
        }
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(editing == nil ? "添加员工岗位" : "修改员工岗位").font(.headline)
            if let candidate {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Self.text(candidate["RealName"]).isEmpty ? Self.text(candidate["UserName"]) : Self.text(candidate["RealName"]))
                            .font(.system(size: NativeTypography.size(16), weight: .semibold))
                        Text("\(identityLabel(candidate)) · \(Self.text(candidate["UserName"]))")
                            .font(.caption).foregroundStyle(Brand.muted)
                    }
                    Spacer()
                    if editing == nil {
                        Button("更换") { self.candidate = nil; candidates = [] }
                            .buttonStyle(.bordered).disabled(saving)
                    }
                }
            } else {
                TextField("输入姓名或账号关键词", text: $keyword)
                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
                    .disabled(saving).onSubmit { Task { await searchCandidates() } }
                Button(searching ? "搜索中…" : "搜索可授权账号") { Task { await searchCandidates() } }
                    .buttonStyle(.bordered).disabled(searching || saving || writeOutcomeUnknown || keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ForEach(candidates.indices, id: \.self) { index in
                    let item = candidates[index]
                    Button {
                        candidate = item; candidates = []; error = nil
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.text(item["RealName"]).isEmpty ? Self.text(item["UserName"]) : Self.text(item["RealName"]))
                                    .foregroundStyle(Brand.ink)
                                Text("\(identityLabel(item)) · \(Self.text(item["UserName"]))")
                                    .font(.caption).foregroundStyle(Brand.muted)
                            }
                            Spacer(); Text("选择").font(.caption).foregroundStyle(Brand.primary)
                        }.padding(9).background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }
            Picker("业务岗位", selection: $roleCode) {
                ForEach(availableRoles) { role in Text(role.title).tag(role.code) }
            }.pickerStyle(.menu)
            Picker("授权范围", selection: $storeID) {
                ForEach(storeOptions.indices, id: \.self) { index in
                    Text(Self.text(storeOptions[index]["Name"]).isEmpty ? "授权门店" : Self.text(storeOptions[index]["Name"]))
                        .tag(Self.text(storeOptions[index]["Id"]))
                }
            }.pickerStyle(.menu).disabled(storeOptions.isEmpty || saving)
            if !hasMerchantWideAdmin {
                Text("门店管理员只能为本人可管理的门店授权非管理员岗位。")
                    .font(.caption).foregroundStyle(Brand.muted)
            }
            if storeOptions.isEmpty { Text("当前账号没有可授权的门店范围。").font(.caption).foregroundStyle(Brand.muted) }
            HStack {
                Button(saving ? "正在保存…" : editing == nil ? "添加授权" : "保存修改") { Task { await save() } }
                    .buttonStyle(.borderedProminent).tint(Brand.primary)
                    .disabled(saving || writeOutcomeUnknown || candidate == nil || storeID.isEmpty || selectedRole == nil)
                if editing != nil { Button("取消修改") { clearEditor() }.buttonStyle(.bordered).disabled(saving) }
                Spacer()
                Button("刷新") { revision += 1 }.buttonStyle(.bordered).disabled(loading || saving)
            }
        }.merchantCard()
    }

    private func staffCard(_ row: [String: Any]) -> some View {
        let role = Self.text(row["RoleCode"])
        let scope = Self.text(row["StoreId"]) == "0" ? "商户全部门店" :
            stores.first { Self.text($0["Id"]) == Self.text(row["StoreId"]) }.map { Self.text($0["Name"]) } ?? "授权门店"
        let identity = identityLabel(row)
        let enabled = row["GrantEnabled"] as? Bool != false
        let userEnabled = row["UserEnabled"] as? Bool != false
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.text(row["RealName"]).isEmpty ? Self.text(row["UserName"]) : Self.text(row["RealName"]))
                        .font(.system(size: NativeTypography.size(16), weight: .semibold))
                    Text("\(identity) · \(Self.text(row["UserName"]))")
                        .font(.caption).foregroundStyle(Brand.muted)
                    if let phone = row["MaskedPhoneNumber"] as? String, !phone.isEmpty {
                        Text(phone).font(.caption2).foregroundStyle(Brand.muted)
                    }
                }
                Spacer()
                Text(!enabled ? "已撤销" : !userEnabled ? "账号已停用" : "已启用")
                    .font(.caption).foregroundStyle(enabled && userEnabled ? Brand.primary : Brand.muted)
            }
            Text("\(scope) · \(roleChoices.first { $0.code == role }?.title ?? "未识别岗位")")
                .font(.caption).foregroundStyle(Brand.muted)
            if role != "MerchantAdmin" && Self.text(row["StoreId"]) != "0" {
                HStack {
                    Button("修改") { startEdit(row) }.buttonStyle(.bordered).disabled(saving || writeOutcomeUnknown)
                    if enabled { Button("撤销", role: .destructive) { pendingRevoke = row }.buttonStyle(.bordered).disabled(saving || writeOutcomeUnknown) }
                    Spacer()
                }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
    }

    private func load() async {
        guard store.session?.accessToken != nil, let principal,
              Int64(merchantID).map({ $0 > 0 }) == true else {
            staff = []; error = "登录状态或商户范围无效，请返回工作台重新进入。"; return
        }
        requestSequence += 1; let sequence = requestSequence
        loading = true; error = nil; notice = nil
        do {
            let api = MobileAPI(store: store)
            let staffResult = try await api.get("/api/JHCTIMerchant/GetStaff?merchantId=\(merchantID)", authenticated: true,
                expectedPrincipal: principal)
            let storeResult = try await api.get("/api/JHCTIMerchant/GetWorkbenchStoreOptions?merchantId=\(merchantID)", authenticated: true,
                expectedPrincipal: principal)
            let roleResult = try await api.get("/api/JHCTIMerchant/GetWorkbenchMyRoles?merchantId=\(merchantID)", authenticated: true,
                expectedPrincipal: principal)
            guard sequence == requestSequence, store.session.map({ nativeTourismPrincipalFromToken($0.accessToken) }) == Optional(principal) else { return }
            staff = staffResult as? [[String: Any]] ?? []
            let currentStores = storeResult as? [[String: Any]] ?? []
            let currentRoles = roleResult as? [[String: Any]] ?? []
            stores = currentStores; roles = currentRoles
            let manager = currentRoles.filter { Self.text($0["RoleCode"]) == "MerchantAdmin" && $0["StoreEnabled"] as? Bool != false }
            let hasWide = manager.contains { Self.text($0["StoreId"]) == "0" }
            let writableIDs = Set(manager.map { Self.text($0["StoreId"]) }.filter { $0 != "0" })
            let allowedStores = hasWide ? currentStores : currentStores.filter { writableIDs.contains(Self.text($0["Id"])) }
            let allowedStoreIDs = Set(allowedStores.map { Self.text($0["Id"]) })
            if !manager.isEmpty && staff.contains(where: {
                let target = Self.text($0["StoreId"])
                return target != "0" && !allowedStoreIDs.contains(target)
            }) { throw MobileAPIError.unavailable("员工列表超出当前授权门店范围，请刷新授权后重试。") }
            if !manager.contains(where: { Self.text($0["StoreId"]) == "0" }) && staff.contains(where: { Self.text($0["RoleCode"]) == "MerchantAdmin" }) {
                throw MobileAPIError.unavailable("服务端返回了超出当前门店管理范围的商户管理员授权。")
            }
            if !allowedStoreIDs.contains(storeID) { storeID = allowedStores.first.map { Self.text($0["Id"]) } ?? "" }
            if writeOutcomeUnknown || store.hasUnknownMerchantStaffMutation(for: merchantID) {
                guard store.clearUnknownMerchantStaffMutation(for: merchantID) else {
                    writeOutcomeUnknown = true
                    throw MobileAPIError.unavailable("授权范围已刷新，但本机核对标记未能清理，请重试刷新。")
                }
                writeOutcomeUnknown = false
                clearEditor()
                notice = "员工授权列表已刷新，请核对最新状态后再继续操作。"
            }
        } catch is CancellationError {
            // 页面离开或刷新任务取消时，不把取消显示成接口故障。
        } catch {
            if sequence == requestSequence { self.error = error.localizedDescription }
        }
        if sequence == requestSequence { loading = false }
    }

    private func searchCandidates() async {
        guard !writeOutcomeUnknown else { error = "请先刷新员工授权列表，确认上次操作结果。"; return }
        guard !searching, let token = store.session?.accessToken,
              let principal, nativeTourismPrincipalFromToken(token) == principal else { return }
        let term = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, term.count <= 80 else { error = "请输入不超过 80 个字符的姓名或账号关键词。"; return }
        searching = true; error = nil; candidates = []
        do {
            let result = try await MobileAPI(store: store).post("/api/JHCTIMerchant/SearchStaffCandidates", body: [
                "MerchantId": merchantID, "Keyword": term
            ], authenticated: true, expectedPrincipal: principal) as? [[String: Any]] ?? []
            guard store.session.map({ nativeTourismPrincipalFromToken($0.accessToken) }) == Optional(principal) else { return }
            candidates = result
            if result.isEmpty { error = "没有找到可授权的有效账号。" }
        } catch is CancellationError {
            // 搜索被取消时保留当前输入，允许用户重新搜索。
        } catch { if store.session.map({ nativeTourismPrincipalFromToken($0.accessToken) }) == Optional(principal) { self.error = error.localizedDescription } }
        searching = false
    }

    private func startEdit(_ row: [String: Any]) {
        guard !writeOutcomeUnknown else { error = "请先刷新员工授权列表，确认上次操作结果。"; return }
        let role = Self.text(row["RoleCode"])
        guard role != "MerchantAdmin" else { return }
        editing = row
        candidate = ["Id": Self.text(row["UserId"]), "UserIdentityType": Self.text(row["UserIdentityType"]),
                     "UserName": Self.text(row["UserName"]), "RealName": Self.text(row["RealName"])]
        roleCode = role; storeID = Self.text(row["StoreId"]); candidates = []; error = nil
    }

    private func clearEditor() {
        editing = nil; candidate = nil; candidates = []; keyword = ""; error = nil
        roleCode = "Order"; adjustStoreScope(for: roleCode)
    }

    private func markStaffWriteOutcomeUnknown() -> Bool {
        writeOutcomeUnknown = true
        return store.markUnknownMerchantStaffMutation(for: merchantID)
    }

    private func adjustStoreScope(for _: String) {
        let options = writableStores
        if !options.contains(where: { Self.text($0["Id"]) == storeID }) {
            storeID = options.first.map { Self.text($0["Id"]) } ?? ""
        }
    }

    private func save() async {
        guard !saving, !writeOutcomeUnknown, let candidate, let role = selectedRole,
              storeOptions.contains(where: { Self.text($0["Id"]) == storeID }),
              let token = store.session?.accessToken, let principal,
              nativeTourismPrincipalFromToken(token) == principal else { error = "登录身份或授权范围已变化，请刷新后重试。"; return }
        if storeID == "0" || (!hasMerchantWideAdmin && !writableStoreIDs.contains(storeID)) {
            error = "员工授权必须指定当前管理员可管理的门店。"; return
        }
        saving = true; error = nil; notice = nil
        var committed = false
        do {
            var body: [String: Any] = [
                "Id": editing.map { Self.text($0["Id"]) } ?? "0",
                "Version": editing.map { Self.integer($0["Version"]) } ?? 0,
                "MerchantId": merchantID, "StoreId": storeID,
                "UserIdentityType": Self.text(candidate["UserIdentityType"]),
                "UserId": Self.text(candidate["Id"]), "RoleCode": role.code,
                "IsEnabled": true, "Reason": "通过原生商户工作台维护员工授权"
            ]
            if let editing { body["Id"] = Self.text(editing["Id"]) }
            _ = try await MobileAPI(store: store).post("/api/JHCTIMerchant/SaveStaff", body: body, authenticated: true,
                expectedPrincipal: principal)
            committed = true
            guard store.session.map({ nativeTourismPrincipalFromToken($0.accessToken) }) == Optional(principal) else {
                self.error = "账号已变化，保存结果请返回工作台确认。"; return
            }
            notice = editing == nil ? "员工授权已添加。" : "员工授权已更新。"
            clearEditor(); revision += 1
        } catch is CancellationError {
            let persisted = markStaffWriteOutcomeUnknown()
            if store.session.map({ nativeTourismPrincipalFromToken($0.accessToken) }) == Optional(principal) {
                error = persisted
                    ? (committed ? "服务端已确认员工授权保存；请先刷新授权列表核对，再继续操作。"
                        : "员工授权保存结果未确认；已暂停写入，请先刷新授权列表核对。")
                    : "员工授权结果未知，且本机保护标记未能保存。请勿退出应用；先刷新并核对授权状态。"
            }
        } catch {
            let statusCode = (error as? MobileAPIError)?.httpStatusCode
            let outcomeUnknown = statusCode.map { !(400...499).contains($0) || $0 == 408 || $0 == 429 } ?? true
            let persisted = outcomeUnknown ? markStaffWriteOutcomeUnknown() : true
            if store.session.map({ nativeTourismPrincipalFromToken($0.accessToken) }) == Optional(principal) {
                if outcomeUnknown {
                    self.error = persisted
                        ? "员工授权保存结果未确认：\(error.localizedDescription)；已暂停写入，请先刷新授权列表核对。"
                        : "员工授权结果未知，且本机保护标记未能保存。请勿退出应用；先刷新并核对授权状态。"
                } else { self.error = error.localizedDescription }
            }
        }
        saving = false
    }

    private func revoke(_ row: [String: Any]) async {
        guard !saving, !writeOutcomeUnknown, Self.text(row["RoleCode"]) != "MerchantAdmin",
              let token = store.session?.accessToken, let principal,
              nativeTourismPrincipalFromToken(token) == principal else { error = "登录身份已变化，请刷新后重试。"; return }
        saving = true; error = nil
        var components = URLComponents()
        components.path = "/api/JHCTIMerchant/RevokeStaff"
        components.queryItems = [
            URLQueryItem(name: "merchantId", value: merchantID),
            URLQueryItem(name: "staffId", value: Self.text(row["Id"])),
            URLQueryItem(name: "version", value: String(Self.integer(row["Version"]))),
            URLQueryItem(name: "reason", value: "通过原生商户工作台撤销")
        ]
        var committed = false
        do {
            _ = try await MobileAPI(store: store).post(components.string ?? "/api/JHCTIMerchant/RevokeStaff", body: [:], authenticated: true,
                expectedPrincipal: principal)
            committed = true
            guard store.session.map({ nativeTourismPrincipalFromToken($0.accessToken) }) == Optional(principal) else {
                self.error = "账号已变化，撤销结果请返回工作台确认。"; return
            }
            notice = "员工授权已撤销。"; revision += 1
        } catch is CancellationError {
            let persisted = markStaffWriteOutcomeUnknown()
            if store.session.map({ nativeTourismPrincipalFromToken($0.accessToken) }) == Optional(principal) {
                error = persisted
                    ? (committed ? "服务端已确认撤销；请先刷新授权列表核对，再继续操作。"
                        : "员工授权撤销结果未确认；已暂停写入，请先刷新授权列表核对。")
                    : "员工授权撤销结果未知，且本机保护标记未能保存。请勿退出应用；先刷新并核对授权状态。"
            }
        } catch {
            let statusCode = (error as? MobileAPIError)?.httpStatusCode
            let outcomeUnknown = statusCode.map { !(400...499).contains($0) || $0 == 408 || $0 == 429 } ?? true
            let persisted = outcomeUnknown ? markStaffWriteOutcomeUnknown() : true
            if store.session.map({ nativeTourismPrincipalFromToken($0.accessToken) }) == Optional(principal) {
                if outcomeUnknown {
                    self.error = persisted
                        ? "员工授权撤销结果未确认：\(error.localizedDescription)；已暂停写入，请先刷新授权列表核对。"
                        : "员工授权撤销结果未知，且本机保护标记未能保存。请勿退出应用；先刷新并核对授权状态。"
                } else { self.error = error.localizedDescription }
            }
        }
        saving = false; pendingRevoke = nil
    }

    private func identityLabel(_ value: [String: Any]) -> String {
        Self.text(value["UserIdentityType"]) == "Tourism" ? "文旅账号" : "系统账号"
    }

    private static func text(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return (value as? String) ?? String(describing: value)
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return Int(text(value)) ?? 0
    }
}
