import Foundation
import SwiftUI

struct RestaurantWorkbenchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    @State private var restaurants: [[String: Any]] = []
    @State private var stores: [[String: Any]] = []
    @State private var roles: [[String: Any]] = []
    @State private var restaurantID = ""
    @State private var loading = true
    @State private var scopeLoading = false
    @State private var error: String?
    @State private var revision = 0
    @State private var reportOpen = false

    private let roleNames = ["RestaurantAdmin": "餐饮管理", "Order": "餐饮订单", "Product": "菜单管理",
                             "Verifier": "到店核销", "FinanceReadOnly": "经营数据只读"]

    private func diningRows(_ value: Any, label: String) throws -> [[String: Any]] {
        guard let rows = value as? [[String: Any]] else {
            throw MobileAPIError.unavailable("\(label)回执格式无效，请重试")
        }
        return rows
    }

    private func diningID(_ value: Any?, allowZero: Bool = false) throws -> String {
        guard let text = value as? String, let id = Int64(text), id >= 0,
              String(id) == text, allowZero || id > 0 else {
            throw MobileAPIError.unavailable("餐饮授权回执编号无效，请重试")
        }
        return text
    }

    private func diningRestaurants(_ value: Any) throws -> [[String: Any]] {
        try diningRows(value, label: "餐饮商家").map { row in
            _ = try diningID(row["Id"])
            guard let name = row["Name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MobileAPIError.unavailable("餐饮商家资料不完整，请重试")
            }
            return row
        }
    }

    private func diningRoles(_ value: Any, restaurantID: String? = nil) throws -> [[String: Any]] {
        try diningRows(value, label: "餐饮岗位").map { row in
            let rowRestaurantID = try diningID(row["RestaurantId"])
            _ = try diningID(row["StoreId"], allowZero: true)
            guard let code = row["RoleCode"] as? String, !code.isEmpty,
                  restaurantID == nil || restaurantID == rowRestaurantID else {
                throw MobileAPIError.unavailable("餐饮岗位资料不完整，请重试")
            }
            return row
        }
    }

    private func diningStores(_ value: Any, restaurantID: String) throws -> [[String: Any]] {
        try diningRows(value, label: "餐饮门店").map { row in
            _ = try diningID(row["Id"])
            let ownerID = try diningID(row["RestaurantId"])
            guard ownerID == restaurantID,
                  let name = row["Name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  row["IsEnabled"] as? Bool != nil else {
                throw MobileAPIError.unavailable("餐饮门店资料不完整，请重试")
            }
            return row
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("餐饮工作台").font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif))
                        Text("仅显示当前文旅账号获授权的餐饮商家、门店和岗位")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    .background(LinearGradient(colors: [Color(red: 0.86, green: 0.94, blue: 0.91), Brand.background],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 12))
                    StatusView(loading: loading, error: error) { revision += 1 }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("当前餐饮商家").font(.headline)
                        if restaurants.isEmpty {
                            Text(loading ? "正在核验餐饮授权…" : "当前账号没有可访问的餐饮工作范围。")
                                .foregroundStyle(Brand.muted)
                        } else {
                            Picker("选择餐饮商家", selection: $restaurantID) {
                                ForEach(restaurants.indices, id: \.self) { index in
                                    Text(restaurants[index]["Name"] as? String ?? "未命名商家")
                                        .tag(restaurants[index]["Id"] as? String ?? "")
                                }
                            }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.merchantCard()
                    if !restaurantID.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text("授权门店").font(.headline); Spacer(); Text("\(stores.count) 家").foregroundStyle(Brand.muted) }
                            if scopeLoading { ProgressView("正在读取门店范围…") }
                            else if stores.isEmpty { Text("当前商家没有已授权门店。请联系商家管理员检查岗位范围。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted) }
                            ForEach(stores.indices, id: \.self) { index in
                                let item = stores[index]
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(item["Name"] as? String ?? "未命名门店").font(.system(size: NativeTypography.size(16), weight: .semibold))
                                        Spacer()
                                        Text(item["IsEnabled"] as? Bool == false ? "已停用" : "已启用")
                                            .font(.caption).foregroundStyle(item["IsEnabled"] as? Bool == false ? Brand.muted : Brand.primary)
                                    }
                                    Text(item["Address"] as? String ?? "未填写地址")
                                        .font(.caption).foregroundStyle(Brand.muted)
                                    let storeID = item["Id"] as? String ?? ""
                                    let storeRoles = roles.filter {
                                        let scope = $0["StoreId"] as? String ?? "0"
                                        return scope == "0" || scope == storeID
                                    }
                                    if !storeRoles.isEmpty {
                                        Text(storeRoles.map { roleNames[$0["RoleCode"] as? String ?? ""] ?? "餐饮岗位" }
                                            .joined(separator: " · "))
                                            .font(.caption.weight(.medium)).foregroundStyle(Brand.primary)
                                    }
                                    if item["IsEnabled"] as? Bool != false,
                                       storeRoles.contains(where: { ["RestaurantAdmin", "Product"].contains($0["RoleCode"] as? String ?? "") }) {
                                        NavigationLink {
                                            RestaurantMenuManagementView(store: store,
                                                storeID: storeID,
                                                storeName: item["Name"] as? String ?? "餐饮门店")
                                        } label: {
                                            Label("菜单管理", systemImage: "fork.knife")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    if item["IsEnabled"] as? Bool != false,
                                       storeRoles.contains(where: { ["RestaurantAdmin", "Order"].contains($0["RoleCode"] as? String ?? "") }) {
                                        NavigationLink {
                                            RestaurantQueueManagementView(store: store,
                                                storeID: storeID,
                                                storeName: item["Name"] as? String ?? "餐饮门店")
                                        } label: {
                                            Label("排队叫号", systemImage: "person.3.sequence")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.bordered)
                                        NavigationLink {
                                            RestaurantReservationManagementView(store: store, storeID: storeID,
                                                storeName: item["Name"] as? String ?? "餐饮门店")
                                        } label: {
                                            Label("预订管理", systemImage: "calendar")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    if item["IsEnabled"] as? Bool != false,
                                       storeRoles.contains(where: { ["RestaurantAdmin", "Verifier"].contains($0["RoleCode"] as? String ?? "") }) {
                                        NavigationLink {
                                            RestaurantWorkbenchPages.packageVerification(store: store, restaurantID: restaurantID,
                                                storeID: storeID, storeName: item["Name"] as? String ?? "餐饮门店")
                                        } label: {
                                            Label("团购核销", systemImage: "qrcode.viewfinder")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
                            }
                            if !scopeLoading, roles.contains(where: {
                                ($0["RestaurantId"] as? String) == restaurantID
                                    && ["RestaurantAdmin", "FinanceReadOnly"].contains($0["RoleCode"] as? String ?? "")
                            }) {
                                Button { reportOpen = true } label: {
                                    Label("查看餐饮经营报表", systemImage: "chart.bar.xaxis")
                                        .font(.caption.weight(.semibold))
                                }.buttonStyle(.bordered)
                            }
                        }.merchantCard()
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text("我的餐饮岗位").font(.headline); Spacer(); Text("\(roles.count) 项").foregroundStyle(Brand.muted) }
                            if scopeLoading { ProgressView("正在读取岗位…") }
                            else if roles.isEmpty { Text("当前账号没有有效的餐饮岗位授权。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted) }
                            ForEach(roles.indices, id: \.self) { index in
                                let role = roles[index]
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(roleNames[role["RoleCode"] as? String ?? ""] ?? "餐饮岗位")
                                        let scopeID = role["StoreId"] as? String ?? "0"
                                        Text(scopeID == "0" ? "商家全部门店" : stores.first(where: { ($0["Id"] as? String) == scopeID })?["Name"] as? String ?? "指定门店")
                                            .font(.caption).foregroundStyle(Brand.muted)
                                    }
                                    Spacer(); Text("已授权").font(.caption).foregroundStyle(Brand.primary)
                                }
                                if index < roles.count - 1 { Divider() }
                            }
                        }.merchantCard()
                    }
                    Text("页面仅展示服务端返回的授权范围；门店业务操作仍由服务端逐次校验。")
                        .font(.caption).foregroundStyle(Brand.muted).padding(.horizontal, 4)
                }.padding(16)
            }
            .background(Brand.background)
            .toolbar { Button("返回个人使用") { dismiss() } }
            .sheet(isPresented: $reportOpen) {
                RestaurantWorkbenchPages.financialReport(store: store,
                    restaurantID: restaurantID,
                    restaurantName: restaurants.first(where: { ($0["Id"] as? String) == restaurantID })?["Name"] as? String ?? "餐饮商家")
            }
            .task(id: revision) { await loadRestaurants() }
            .task(id: "\(restaurantID)-\(revision)") { await loadScope() }
            .onChange(of: store.session?.accessToken) { _, _ in dismiss() }
        }
    }

    private func loadRestaurants() async {
        guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else { dismiss(); return }
        let requestedRevision = revision
        loading = true; error = nil
        defer {
            if store.session?.accessToken == token, revision == requestedRevision { loading = false }
        }
        do {
            let api = MobileAPI(store: store)
            let values = try diningRestaurants(await api.get("/api/JHCTIDining/GetRestaurants", authenticated: true,
                expectedPrincipal: principal))
            let grants = try diningRoles(await api.get("/api/JHCTIDining/GetMyWorkRoles", authenticated: true,
                expectedPrincipal: principal))
            guard store.session?.accessToken == token, revision == requestedRevision else { return }
            let ids = Set(grants.compactMap { $0["RestaurantId"] as? String })
            restaurants = values.filter { ids.contains($0["Id"] as? String ?? "") }
            let valid = Set(restaurants.compactMap { $0["Id"] as? String })
            roles = grants.filter { valid.contains($0["RestaurantId"] as? String ?? "") }
            if !valid.contains(restaurantID) { restaurantID = restaurants.first?["Id"] as? String ?? "" }
            if restaurants.isEmpty { error = "当前账号没有餐饮岗位授权，或授权已失效。" }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if store.session?.accessToken == token, revision == requestedRevision {
                restaurants = []; stores = []; roles = []; self.error = error.localizedDescription
            }
        }
    }

    private func loadScope() async {
        stores = []; roles = []; error = nil
        scopeLoading = false
        guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token), !restaurantID.isEmpty,
              restaurantID.allSatisfy(\.isNumber) else { return }
        let requested = restaurantID
        let requestedRevision = revision
        scopeLoading = true
        defer {
            if store.session?.accessToken == token, restaurantID == requested, revision == requestedRevision {
                scopeLoading = false
            }
        }
        do {
            let api = MobileAPI(store: store)
            let storeResponse = try await api.get(
                "/api/JHCTIDining/GetStores?restaurantId=\(requested)", authenticated: true, expectedPrincipal: principal)
            let roleResponse = try await api.get(
                "/api/JHCTIDining/GetMyWorkRoles?restaurantId=\(requested)", authenticated: true, expectedPrincipal: principal)
            let values = try diningStores(storeResponse, restaurantID: requested)
            let scopedRoles = try diningRoles(roleResponse, restaurantID: requested)
            guard store.session?.accessToken == token, restaurantID == requested,
                  revision == requestedRevision else { return }
            stores = values
            roles = scopedRoles
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if store.session?.accessToken == token, restaurantID == requested,
               revision == requestedRevision { self.error = error.localizedDescription }
        }
    }
}
