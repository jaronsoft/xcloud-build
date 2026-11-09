import SwiftUI

struct MerchantWorkbenchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    @State private var merchants: [[String: Any]] = []
    @State private var stores: [[String: Any]] = []
    @State private var roles: [[String: Any]] = []
    @State private var notices: [[String: Any]] = []
    @State private var unreadNoticeCount = 0
    @State private var noticeLoading = false
    @State private var noticeError: String?
    @State private var noticeAction = false
    @State private var noticeTotal = 0
    @State private var noticePage = 1
    @State private var noticeUnreadOnly = false
    @State private var noticeExpanded = false
    @State private var noticeRequestSequence = 0
    @State private var merchantID = ""
    @State private var loading = true
    @State private var contextLoading = false
    @State private var error: String?
    @State private var revision = 0

    private let roleNames = ["MerchantAdmin": "商户管理", "Order": "订单处理",
        "Verifier": "到店核销", "TicketVerifier": "门票核销", "ActivityVerifier": "活动核验员",
        "CouponVerifier": "平台消费券核销", "Product": "商品管理",
        "FinanceReadOnly": "财务只读", "ReportReadOnly": "报表只读"]

    private var activeRoles: [[String: Any]] { roles.filter { $0["StoreEnabled"] as? Bool != false } }
    private func hasRole(_ names: Set<String>, merchantWide: Bool = false) -> Bool {
        activeRoles.contains {
            names.contains($0["RoleCode"] as? String ?? "") &&
            (!merchantWide || ($0["StoreId"] as? String ?? "0") == "0")
        }
    }
    private func hasStoreRole(_ names: Set<String>, storeID: String) -> Bool {
        activeRoles.contains {
            names.contains($0["RoleCode"] as? String ?? "") &&
            ((($0["StoreId"] as? String) ?? "0") == "0" || ($0["StoreId"] as? String) == storeID)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("商户工作台").font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif))
                        Text("使用当前账号已获授权的商户与门店范围")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    .background(LinearGradient(colors: [Color(red: 0.86, green: 0.94, blue: 0.91), Brand.background],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 12))
                    StatusView(loading: loading, error: error) { revision += 1 }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("当前商户").font(.headline)
                        if merchants.isEmpty {
                            Text(loading ? "正在读取当前账号的商户授权…" : "当前账号没有可访问的商户工作范围。")
                                .foregroundStyle(Brand.muted)
                        } else {
                            Picker("选择商户", selection: $merchantID) {
                                ForEach(merchants.indices, id: \.self) { index in
                                    Text(merchants[index]["Name"] as? String ?? "未命名商户")
                                        .tag(merchants[index]["Id"] as? String ?? "")
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .merchantCard()
                    if !merchantID.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text("商户通知").font(.headline); Spacer(); Text("未读 \(unreadNoticeCount)").foregroundStyle(Brand.muted)
                                Button(noticeExpanded ? "收起" : "查看全部") { noticeExpanded.toggle(); if noticeExpanded { Task { await loadNotices(merchantID: merchantID, token: store.session?.accessToken ?? "", page: 1, unreadOnly: false) } } }
                            }
                            if noticeExpanded {
                                HStack {
                                    Button("全部通知") { Task { await loadNotices(merchantID: merchantID, token: store.session?.accessToken ?? "", page: 1, unreadOnly: false) } }
                                        .tint(noticeUnreadOnly ? Brand.muted : Brand.primary)
                                    Button("仅未读") { Task { await loadNotices(merchantID: merchantID, token: store.session?.accessToken ?? "", page: 1, unreadOnly: true) } }
                                        .tint(noticeUnreadOnly ? Brand.primary : Brand.muted)
                                }.buttonStyle(.bordered)
                            }
                            if unreadNoticeCount > 0 {
                                Button("全部标记已读") { Task { await markAllNoticesRead() } }
                                    .disabled(noticeAction).buttonStyle(.borderless)
                            }
                            if noticeLoading { ProgressView("正在加载商户通知…") }
                            else if let noticeError { Text(noticeError).foregroundStyle(.red) }
                            else if notices.isEmpty { Text("暂无站内通知").foregroundStyle(Brand.muted) }
                            ForEach(notices.indices, id: \.self) { index in
                                let notice = notices[index]
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(notice["Title"] as? String ?? "商户通知").font(.subheadline.weight(.semibold))
                                    Text(notice["Content"] as? String ?? "").font(.caption).foregroundStyle(Brand.muted)
                                    Text("\((notice["NoticeType"] as? String) == "Manual" ? "发送人：\(notice["SenderName"] as? String ?? "平台管理员")" : "系统通知") · \(notice["ReferenceNo"] as? String ?? "")")
                                        .font(.caption2).foregroundStyle(Brand.muted)
                                    HStack { Text(notice["CreateTime"] as? String ?? "").font(.caption2).foregroundStyle(Brand.muted); Spacer()
                                        if hasRole(["MerchantAdmin", "Order"], merchantWide: true), notice["NoticeType"] as? String == "OrderPaid" {
                                            NavigationLink("查看订单") {
                                                NativeMerchantOrdersView(store: store, merchantID: merchantID, initialOrderNo: notice["ReferenceNo"] as? String ?? "")
                                                    .task { if notice["IsRead"] as? Bool != true { await markNoticeRead(notice["Id"] as? String ?? "") } }
                                            }
                                                .font(.caption)
                                        }
                                        if hasRole(["MerchantAdmin", "Order"], merchantWide: true), ["AfterSaleOpened", "AfterSaleReturnInTransit", "AfterSaleReturnRequired", "AfterSaleApprovedForRefund", "AfterSaleRejected", "AfterSaleRefunded"].contains(notice["NoticeType"] as? String ?? "") {
                                            NavigationLink("查看售后") {
                                                MerchantAfterSalesView(store: store, merchantID: merchantID, initialAfterSaleID: notice["ReferenceId"] as? String ?? "")
                                                    .task { if notice["IsRead"] as? Bool != true { await markNoticeRead(notice["Id"] as? String ?? "") } }
                                            }
                                                .font(.caption)
                                        }
                                        if notice["IsRead"] as? Bool != true {
                                            Button("标记已读") { Task { await markNoticeRead(notice["Id"] as? String ?? "") } }
                                                .disabled(noticeAction).font(.caption)
                                        }
                                    }
                                }
                                if index < notices.count - 1 { Divider() }
                            }
                            if noticeExpanded && noticeTotal > 10 {
                                HStack {
                                    Button("上一页") { Task { await loadNotices(merchantID: merchantID, token: store.session?.accessToken ?? "", page: max(1, noticePage - 1), unreadOnly: noticeUnreadOnly) } }
                                        .disabled(noticeLoading || noticePage <= 1)
                                    Text("第 \(noticePage) / \(max(1, (noticeTotal + 9) / 10)) 页 · 共 \(noticeTotal) 条").font(.caption).foregroundStyle(Brand.muted)
                                    Button("下一页") { Task { await loadNotices(merchantID: merchantID, token: store.session?.accessToken ?? "", page: noticePage + 1, unreadOnly: noticeUnreadOnly) } }
                                        .disabled(noticeLoading || noticePage >= (noticeTotal + 9) / 10)
                                }
                            }
                        }.merchantCard()
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text("已授权门店").font(.headline); Spacer(); Text("\(stores.count) 家").foregroundStyle(Brand.muted) }
                            if contextLoading { ProgressView("正在读取范围…") }
                            else if stores.isEmpty { Text("当前商户暂无已授权门店。").foregroundStyle(Brand.muted) }
                            ForEach(stores.indices, id: \.self) { index in
                                let item = stores[index]
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item["Name"] as? String ?? "未命名门店")
                                    Text("\(item["StoreCode"] as? String ?? "门店")\(item["IsEnabled"] as? Bool == false ? " · 已停用" : "")")
                                        .font(.caption).foregroundStyle(Brand.muted)
                                }
                                if index < stores.count - 1 { Divider() }
                            }
                        }.merchantCard()
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text("我的角色与权限").font(.headline); Spacer(); Text("\(roles.count) 项").foregroundStyle(Brand.muted) }
                            if contextLoading { ProgressView("正在读取角色…") }
                            ForEach(roles.indices, id: \.self) { index in
                                let role = roles[index]
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(roleNames[role["RoleCode"] as? String ?? ""] ?? "商户岗位")
                                        Text((role["StoreId"] as? String ?? "0") == "0" ? "商户全部门店" :
                                             role["StoreName"] as? String ?? "指定门店")
                                            .font(.caption).foregroundStyle(Brand.muted)
                                    }
                                    Spacer()
                                    Text(role["StoreEnabled"] as? Bool == false ? "已停用" : "已授权")
                                        .font(.caption).foregroundStyle(Brand.primary)
                                }
                                if index < roles.count - 1 { Divider() }
                            }
                        }.merchantCard()
                        if !contextLoading && !roles.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("经营服务").font(.headline)
                                if hasRole(["MerchantAdmin", "Order"], merchantWide: true) {
                                    NavigationLink {
                                        NativeMerchantOrdersView(store: store, merchantID: merchantID)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("商户订单").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                                                Text("处理发货、自提及虚拟商品券码核验").font(.caption).foregroundStyle(Brand.muted)
                                            }
                                            Spacer(); Text("›").foregroundStyle(Brand.muted)
                                        }.padding(.vertical, 8)
                                    }.buttonStyle(.plain)
                                    NavigationLink {
                                        MerchantAfterSalesView(store: store, merchantID: merchantID)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("售后协同").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                                                Text("沟通顾客并处理退货进度，退款由平台客服处理").font(.caption).foregroundStyle(Brand.muted)
                                            }
                                            Spacer(); Text("›").foregroundStyle(Brand.muted)
                                        }.padding(.vertical, 8)
                                    }.buttonStyle(.plain)
                                }
                                if hasRole(["MerchantAdmin"]) {
                                    NavigationLink {
                                        MerchantTourismReservationsView(store: store, merchantID: merchantID,
                                            canView: true, canVerify: hasRole(["MerchantAdmin", "TicketVerifier"]), initialVerify: false)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("景点预约").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                                                Text("查看绑定到当前商户景点的预约与入园状态").font(.caption).foregroundStyle(Brand.muted)
                                            }
                                            Spacer(); Text("›").foregroundStyle(Brand.muted)
                                        }.padding(.vertical, 8)
                                    }.buttonStyle(.plain)
                                    NavigationLink {
                                        MerchantStaffView(store: store, merchantID: merchantID,
                                                          stores: stores, roles: activeRoles)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("员工授权").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                                                Text("搜索账号并维护门店岗位授权").font(.caption).foregroundStyle(Brand.muted)
                                            }
                                            Spacer(); Text("›").foregroundStyle(Brand.muted)
                                        }.padding(.vertical, 8)
                                    }.buttonStyle(.plain)
                                }
                                if hasRole(["MerchantAdmin", "TicketVerifier"]) {
                                    NavigationLink {
                                        MerchantTourismReservationsView(store: store, merchantID: merchantID,
                                            canView: hasRole(["MerchantAdmin"]), canVerify: true, initialVerify: true)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("预约检票").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                                                Text("扫描二维码或输入凭证码，核验景点预约入园").font(.caption).foregroundStyle(Brand.muted)
                                            }
                                            Spacer(); Text("›").foregroundStyle(Brand.muted)
                                        }.padding(.vertical, 8)
                                    }.buttonStyle(.plain)
                                }
                                if hasRole(["MerchantAdmin", "Product"]) {
                                    NavigationLink {
                                        MerchantScenicWorkView(store: store, merchantID: merchantID)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("景点经营资料").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                                                Text("维护已授权景点资料并提交平台审核").font(.caption).foregroundStyle(Brand.muted)
                                            }
                                            Spacer(); Text("›").foregroundStyle(Brand.muted)
                                        }.padding(.vertical, 8)
                                    }.buttonStyle(.plain)
                                }
                                if hasRole(["MerchantAdmin", "Product"]) {
                                    NavigationLink {
                                        MerchantProductsView(store: store, merchantID: merchantID)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("商品资料与价格").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                                                Text("维护商品介绍和 SKU 售价，提交审核并管理上下架")
                                                    .font(.caption).foregroundStyle(Brand.muted)
                                            }
                                            Spacer(); Text("›").foregroundStyle(Brand.muted)
                                        }.padding(.vertical, 8)
                                    }.buttonStyle(.plain)
                                }
                                if hasRole(["MerchantAdmin", "Product"], merchantWide: true) {
                                    NavigationLink {
                                        MerchantTicketsView(store: store, merchantID: merchantID)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("门票与场次").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                                                Text("维护授权商户票价与场次库存，保留已售和待支付数量")
                                                    .font(.caption).foregroundStyle(Brand.muted)
                                            }
                                            Spacer(); Text("›").foregroundStyle(Brand.muted)
                                        }.padding(.vertical, 8)
                                    }.buttonStyle(.plain)
                                }
                                if hasRole(["MerchantAdmin", "Product"], merchantWide: true) {
                                    NavigationLink {
                                        MerchantHotelsView(store: store, merchantID: merchantID)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("酒店房态").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                                                Text("维护授权酒店未来房价、可售房量和关闭状态").font(.caption).foregroundStyle(Brand.muted)
                                            }
                                            Spacer(); Text("›").foregroundStyle(Brand.muted)
                                        }.padding(.vertical, 8)
                                    }.buttonStyle(.plain)
                                }
                                ForEach(stores.indices.filter { hasStoreRole(["MerchantAdmin", "Product"], storeID: String(describing: stores[$0]["Id"] ?? "")) }, id: \.self) { index in
                                    let stockStore = stores[index]
                                    NavigationLink {
                                        MerchantStockView(store: store, merchantID: merchantID, stockStore: stockStore)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("门店库存 · \(stockStore["Name"] as? String ?? "授权门店")")
                                                    .font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                                                Text("查看并维护该门店 SKU 库存").font(.caption).foregroundStyle(Brand.muted)
                                            }
                                            Spacer(); Text("›").foregroundStyle(Brand.muted)
                                        }.padding(.vertical, 8)
                                    }.buttonStyle(.plain)
                                }
                                if hasRole(["MerchantAdmin"], merchantWide: true) {
                                    NavigationLink {
                                        MerchantActivityWorkView(store: store, merchantID: merchantID)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("经营活动").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                                                Text("维护本商户主办活动并提交平台审核").font(.caption).foregroundStyle(Brand.muted)
                                            }
                                            Spacer(); Text("›").foregroundStyle(Brand.muted)
                                        }.padding(.vertical, 8)
                                    }.buttonStyle(.plain)
                                }
                                if hasRole(["MerchantAdmin", "ReportReadOnly"]) || hasRole(["FinanceReadOnly"], merchantWide: true) ||
                                    hasRole(["TicketVerifier", "Verifier"]) {
                                    NavigationLink {
                                        MerchantFinancialReportView(store: store, merchantID: merchantID, roles: activeRoles)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("经营报表").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                                                Text("查看授权范围内的经营与核销汇总")
                                                    .font(.caption).foregroundStyle(Brand.muted)
                                            }
                                            Spacer(); Text("›").foregroundStyle(Brand.muted)
                                        }.padding(.vertical, 8)
                                    }.buttonStyle(.plain)
                                }
                            }.merchantCard()
                        }
                    }
                    Text("页面只显示服务端返回的授权范围；业务操作仍由服务端校验。")
                        .font(.caption).foregroundStyle(Brand.muted).padding(.horizontal, 4)
                }
                .padding(16)
            }
            .background(Brand.background)
            .toolbar { Button("返回个人使用") { dismiss() } }
            .task(id: revision) { await loadMerchants() }
            .task(id: "\(merchantID)-\(revision)") { await loadContext() }
            .onChange(of: store.session?.accessToken) { _, _ in dismiss() }
        }
    }

    private func moduleLink(_ title: String, note: String, path: String, paged: Bool = true) -> some View {
        NavigationLink {
            MerchantRecordsView(store: store, merchantID: merchantID, title: title, path: path, paged: paged)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                    Text(note).font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer(); Text("›").foregroundStyle(Brand.muted)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func loadMerchants() async {
        guard let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { dismiss(); return }
        loading = true; error = nil
        do {
            let result = try await MobileAPI(store: store).get(
                "/api/JHCTIMerchant/GetWorkbenchMerchantOptions", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [[String: Any]] ?? []
            try Task.checkCancellation()
            guard store.session?.accessToken == token else { return }
            merchants = result
            let ids = result.compactMap { $0["Id"] as? String }
            if !ids.contains(merchantID) { merchantID = ids.first ?? "" }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled && store.session?.accessToken == token {
                merchants = []; stores = []; roles = []; self.error = error.localizedDescription
            }
        }
        if !Task.isCancelled && store.session?.accessToken == token { loading = false }
    }

    private func loadContext() async {
        stores = []; roles = []; notices = []; unreadNoticeCount = 0; noticeTotal = 0
        noticePage = 1; noticeUnreadOnly = false; noticeExpanded = false; noticeLoading = false
        noticeError = nil; error = nil
        guard let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token), !merchantID.isEmpty,
              merchantID.allSatisfy(\.isNumber) else { return }
        let requestedMerchant = merchantID
        contextLoading = true
        do {
            let api = MobileAPI(store: store)
            let fetchedStores = try await api.get(
                "/api/JHCTIMerchant/GetWorkbenchStoreOptions?merchantId=\(requestedMerchant)", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [[String: Any]] ?? []
            let fetchedRoles = try await api.get(
                "/api/JHCTIMerchant/GetWorkbenchMyRoles?merchantId=\(requestedMerchant)", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [[String: Any]] ?? []
            try Task.checkCancellation()
            guard store.session?.accessToken == token, merchantID == requestedMerchant else { return }
            stores = fetchedStores; roles = fetchedRoles
            if fetchedRoles.isEmpty { error = "当前商户岗位已失效，请返回个人中心刷新授权。" }
            await loadNotices(merchantID: requestedMerchant, token: token)
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled, store.session?.accessToken == token, merchantID == requestedMerchant {
                self.error = error.localizedDescription
            }
        }
        if !Task.isCancelled, store.session?.accessToken == token, merchantID == requestedMerchant {
            contextLoading = false
        }
    }

    private func loadNotices(merchantID requestedMerchant: String, token: String, page: Int = 1, unreadOnly: Bool = false) async {
        guard let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        noticeRequestSequence += 1
        let sequence = noticeRequestSequence
        noticeLoading = true; noticeError = nil
        do {
            let api = MobileAPI(store: store)
            guard let response = try await api.get("/api/JHCTIMerchantOrder/GetNotices?merchantId=\(requestedMerchant)&page=\(page)&pageSize=10&unreadOnly=\(unreadOnly)", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any],
                  let rows = response["data"] as? [[String: Any]] ?? response["Data"] as? [[String: Any]],
                  let count = try await api.get("/api/JHCTIMerchantOrder/GetUnreadNoticeCount?merchantId=\(requestedMerchant)", authenticated: true,
                    expectedPrincipal: expectedPrincipal) as? Int else {
                throw MobileAPIError.unavailable("商户通知响应格式异常，请重试。")
            }
            let total = Int(String(describing: response["dataCount"] ?? response["DataCount"] ?? "-1")) ?? -1
            guard rows.count <= 10, total >= rows.count else { throw MobileAPIError.unavailable("商户通知分页数据无效，请刷新重试。") }
            try Task.checkCancellation()
            guard noticeRequestSequence == sequence, store.session?.accessToken == token,
                  merchantID == requestedMerchant else { return }
            notices = rows; unreadNoticeCount = count; noticeTotal = total; noticePage = page; noticeUnreadOnly = unreadOnly
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, noticeRequestSequence == sequence,
                  store.session?.accessToken == token, merchantID == requestedMerchant else { return }
            noticeError = error.localizedDescription
        }
        if !Task.isCancelled, noticeRequestSequence == sequence,
           store.session?.accessToken == token, merchantID == requestedMerchant { noticeLoading = false }
    }

    private func markNoticeRead(_ noticeID: String) async {
        guard !noticeAction, !noticeID.isEmpty, let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        let requestedMerchant = merchantID
        noticeAction = true
        defer { noticeAction = false }
        do {
            _ = try await MobileAPI(store: store).postJSON("/api/JHCTIMerchantOrder/MarkNoticeRead?merchantId=\(requestedMerchant)&noticeId=\(noticeID)", body: [:], authenticated: true,
                expectedPrincipal: expectedPrincipal)
            try Task.checkCancellation()
            guard store.session?.accessToken == token, merchantID == requestedMerchant else { return }
            await loadNotices(merchantID: requestedMerchant, token: token, page: noticePage, unreadOnly: noticeUnreadOnly)
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled, store.session?.accessToken == token, merchantID == requestedMerchant {
                noticeError = error.localizedDescription
            }
        }
    }

    private func markAllNoticesRead() async {
        guard !noticeAction, let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        let requestedMerchant = merchantID
        noticeAction = true
        defer { noticeAction = false }
        do {
            _ = try await MobileAPI(store: store).postJSON("/api/JHCTIMerchantOrder/MarkAllNoticesRead?merchantId=\(requestedMerchant)", body: [:], authenticated: true,
                expectedPrincipal: expectedPrincipal)
            try Task.checkCancellation()
            guard store.session?.accessToken == token, merchantID == requestedMerchant else { return }
            await loadNotices(merchantID: requestedMerchant, token: token, page: noticeUnreadOnly ? 1 : noticePage, unreadOnly: noticeUnreadOnly)
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled, store.session?.accessToken == token, merchantID == requestedMerchant {
                noticeError = error.localizedDescription
            }
        }
    }
}



private struct MerchantRecordsView: View {
    let store: SessionStore
    let merchantID: String
    let title: String
    let path: String
    let paged: Bool
    @State private var rows: [[String: Any]] = []
    @State private var loading = true
    @State private var error: String?
    @State private var revision = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                StatusView(loading: loading, error: error) { revision += 1 }
                if !loading && error == nil && rows.isEmpty { Text("暂无记录").foregroundStyle(Brand.muted) }
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row["Name"] as? String ?? row["ResourceName"] as? String ??
                             row["OrderNo"] as? String ?? row["Title"] as? String ??
                             row["DisplayName"] as? String ?? row["UserName"] as? String ?? "记录")
                            .font(.headline)
                        Text(row["Status"] as? String ?? row["OrderStatus"] as? String ??
                             row["MerchantOrderStatus"] as? String ?? row["StoreName"] as? String ?? "")
                            .font(.caption).foregroundStyle(Brand.muted)
                    }.merchantCard()
                }
            }.padding(16)
        }
        .background(Brand.background)
        .navigationTitle(title)
        .task(id: revision) {
            guard merchantID.allSatisfy(\.isNumber), let token = store.session?.accessToken,
                  let expectedPrincipal = nativeTourismPrincipal(token) else { return }
            loading = true; error = nil; rows = []
            do {
                let separator = path.contains("?") ? "&" : "?"
                let url = "\(path)\(separator)merchantId=\(merchantID)" + (paged ? "&page=1&pageSize=20" : "")
                let value = try await MobileAPI(store: store).get(url, authenticated: true,
                    expectedPrincipal: expectedPrincipal)
                try Task.checkCancellation()
                guard store.session?.accessToken == token else { return }
                if let array = value as? [[String: Any]] { rows = array }
                else if let page = value as? [String: Any] {
                    rows = page["data"] as? [[String: Any]] ?? page["Data"] as? [[String: Any]] ?? []
                }
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled && store.session?.accessToken == token {
                    self.error = error.localizedDescription
                }
            }
            guard !Task.isCancelled else { return }
            loading = false
        }
    }
}
