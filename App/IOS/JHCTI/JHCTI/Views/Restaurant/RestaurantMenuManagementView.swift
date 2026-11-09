import SwiftUI

private struct NativeDiningMenuSku: Identifiable {
    var id = UUID()
    var serverID = "0"
    var name = "标准份"
    var price = ""
    var isAvailable = true
}

private struct NativeDiningMenuDishDraft {
    var id = "0"
    var version = 0
    var categoryID = ""
    var name = ""
    var description = ""
    var imageURL: Any = NSNull()
    var sortOrder = 0
    var isAvailable = true
    var skus = [NativeDiningMenuSku()]
}

struct RestaurantMenuManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let storeID: String
    let storeName: String
    @State private var categories: [[String: Any]] = []
    @State private var dishes: [[String: Any]] = []
    @State private var page = 1
    @State private var total = 0
    @State private var loading = true
    @State private var loadingMore = false
    @State private var saving = false
    @State private var error: String?
    @State private var notice: String?
    @State private var revision = 0
    @State private var categoryEditor = false
    @State private var categoryID = "0"
    @State private var categoryVersion = 0
    @State private var categoryName = ""
    @State private var categorySort = "0"
    @State private var categoryEnabled = true
    @State private var dishEditor = false
    @State private var dishDraft = NativeDiningMenuDishDraft()
    @State private var pendingDelete: [String: Any]?

    private var availableCategories: [[String: Any]] {
        categories.filter { $0["IsEnabled"] as? Bool != false }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("菜单管理").font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif))
                    Text("\(storeName) · 维护分类、菜品、规格价格和可售状态")
                        .font(.caption).foregroundStyle(Brand.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(Brand.background, in: RoundedRectangle(cornerRadius: 12))
                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).foregroundStyle(.red)
                        Button("重试") { revision += 1 }.buttonStyle(.bordered)
                    }.merchantCard()
                }
                if let notice {
                    Text(notice).font(.caption).foregroundStyle(Brand.primary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
                }
                if loading { ProgressView("正在读取菜单…").frame(maxWidth: .infinity).padding(24) }
                if !loading && error == nil {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("菜品分类").font(.headline)
                            Spacer()
                            Button("新增分类") { beginCategoryEdit(nil) }.font(.caption.weight(.semibold))
                                .disabled(saving)
                        }
                        if categories.isEmpty { Text("暂无分类，先添加分类再创建菜品。")
                            .font(.caption).foregroundStyle(Brand.muted) }
                        ForEach(categories.indices, id: \.self) { index in
                            let category = categories[index]
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(category["Name"] as? String ?? "未命名分类")
                                    Text(category["IsEnabled"] as? Bool == false ? "已停用" : "已启用")
                                        .font(.caption).foregroundStyle(Brand.muted)
                                }
                                Spacer()
                                Button("编辑") { beginCategoryEdit(category) }.font(.caption)
                            }
                            if index < categories.count - 1 { Divider() }
                        }
                    }.merchantCard()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("菜品与规格").font(.headline)
                            Spacer()
                            Button("新增菜品") { beginDishEdit(nil) }
                                .font(.caption.weight(.semibold)).disabled(availableCategories.isEmpty || saving)
                        }
                        if availableCategories.isEmpty {
                            Text("请先启用一个分类，再创建菜品。")
                                .font(.caption).foregroundStyle(Brand.muted)
                        } else if dishes.isEmpty {
                            Text("暂无菜品。添加菜品和规格价格后可在公开菜单中展示。")
                                .font(.caption).foregroundStyle(Brand.muted)
                        }
                        ForEach(dishes.indices, id: \.self) { index in
                            let dish = dishes[index]
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(dish["Name"] as? String ?? "未命名菜品").fontWeight(.semibold)
                                        Text(categoryName(for: dish["CategoryId"]))
                                            .font(.caption).foregroundStyle(Brand.muted)
                                    }
                                    Spacer()
                                    Text((dish["IsAvailable"] as? Bool == false) ? "已停售" : "在售")
                                        .font(.caption).foregroundStyle(Brand.primary)
                                }
                                let skus = dish["Skus"] as? [[String: Any]] ?? []
                                ForEach(skus.indices, id: \.self) { skuIndex in
                                    let sku = skus[skuIndex]
                                    Text("\(sku["Name"] as? String ?? "规格")  ¥\(priceText(sku["Price"]))\(sku["IsAvailable"] as? Bool == false ? " · 停售" : "")")
                                        .font(.caption).foregroundStyle(Brand.muted)
                                }
                                HStack {
                                    Button("编辑") { beginDishEdit(dish) }.buttonStyle(.bordered)
                                    Button("删除", role: .destructive) { pendingDelete = dish }.buttonStyle(.bordered)
                                }.disabled(saving)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            if index < dishes.count - 1 { Divider() }
                        }
                        if dishes.count < total {
                            Button(loadingMore ? "正在加载…" : "加载更多") { Task { await load(page: page + 1) } }
                                .frame(maxWidth: .infinity).buttonStyle(.bordered).disabled(loadingMore)
                        }
                    }.merchantCard()
                }
            }.padding(16)
        }
        .background(Brand.background)
        .navigationTitle("菜单管理")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: revision) { await load(page: 1) }
        .onChange(of: store.session?.accessToken) { _, _ in dismiss() }
        .sheet(isPresented: $categoryEditor) { categoryForm }
        .sheet(isPresented: $dishEditor) { dishForm }
        .confirmationDialog("删除菜品？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let pendingDelete { Task { await deleteDish(pendingDelete) } } }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { Text(pendingDelete?["Name"] as? String ?? "此菜品将从菜单中删除") }
    }

    private var categoryForm: some View {
        NavigationStack {
            Form {
                TextField("分类名称", text: $categoryName).textInputAutocapitalization(.never)
                TextField("排序值", text: $categorySort).keyboardType(.numberPad)
                Toggle("启用分类", isOn: $categoryEnabled)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .navigationTitle(categoryID == "0" ? "新增分类" : "编辑分类")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { categoryEditor = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中…" : "保存") { Task { await saveCategory() } }
                        .disabled(saving || categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var dishForm: some View {
        NavigationStack {
            Form {
                TextField("菜品名称", text: $dishDraft.name)
                Picker("分类", selection: $dishDraft.categoryID) {
                    ForEach(availableCategories.indices, id: \.self) { index in
                        Text(availableCategories[index]["Name"] as? String ?? "分类")
                            .tag(availableCategories[index]["Id"] as? String ?? "")
                    }
                }
                TextField("菜品说明（选填）", text: $dishDraft.description, axis: .vertical).lineLimit(2...5)
                Toggle("公开菜单可售", isOn: $dishDraft.isAvailable)
                Section("规格与价格") {
                    ForEach($dishDraft.skus) { $sku in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("规格名称", text: $sku.name)
                            TextField("价格（元）", text: $sku.price).keyboardType(.decimalPad)
                            Toggle("此规格可售", isOn: $sku.isAvailable)
                            if dishDraft.skus.count > 1 {
                                Button("移除此规格", role: .destructive) {
                                    dishDraft.skus.removeAll { $0.id == sku.id }
                                }
                            }
                        }
                    }
                    Button("＋ 增加规格") { dishDraft.skus.append(NativeDiningMenuSku(name: "", price: "")) }
                        .disabled(dishDraft.skus.count >= 50)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .navigationTitle(dishDraft.id == "0" ? "新增菜品" : "编辑菜品")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dishEditor = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中…" : "保存") { Task { await saveDish() } }
                        .disabled(saving || dishDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dishDraft.skus.isEmpty)
                }
            }
        }
    }

    private func beginCategoryEdit(_ category: [String: Any]?) {
        categoryID = category?["Id"] as? String ?? "0"
        categoryVersion = int(category?["Version"])
        categoryName = category?["Name"] as? String ?? ""
        categorySort = String(int(category?["SortOrder"]))
        categoryEnabled = category?["IsEnabled"] as? Bool ?? true
        categoryEditor = true
    }

    private func beginDishEdit(_ dish: [String: Any]?) {
        if let dish {
            let rows = dish["Skus"] as? [[String: Any]] ?? []
            dishDraft = NativeDiningMenuDishDraft(id: dish["Id"] as? String ?? "0",
                version: int(dish["Version"]), categoryID: dish["CategoryId"] as? String ?? "",
                name: dish["Name"] as? String ?? "", description: dish["Description"] as? String ?? "",
                imageURL: dish["ImageUrl"] ?? NSNull(), sortOrder: int(dish["SortOrder"]),
                isAvailable: dish["IsAvailable"] as? Bool ?? true,
                skus: rows.map { row in NativeDiningMenuSku(serverID: row["Id"] as? String ?? "0",
                    name: row["Name"] as? String ?? "", price: priceText(row["Price"]),
                    isAvailable: row["IsAvailable"] as? Bool ?? true) })
            if dishDraft.skus.isEmpty { dishDraft.skus = [NativeDiningMenuSku()] }
        } else {
            dishDraft = NativeDiningMenuDishDraft(categoryID: availableCategories.first?["Id"] as? String ?? "")
        }
        dishEditor = true
    }

    private func load(page requestedPage: Int) async {
        guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else { dismiss(); return }
        if requestedPage == 1 { loading = true; error = nil; categories = []; dishes = []; total = 0 }
        else { loadingMore = true }
        defer { loading = false; loadingMore = false }
        do {
            let api = MobileAPI(store: store)
            let categoryResponse = try await api.get("/api/JHCTIDining/GetDishCategories?storeId=\(storeID)", authenticated: true,
                expectedPrincipal: principal)
            let dishResponse = try await api.get("/api/JHCTIDining/GetDishes?storeId=\(storeID)&page=\(requestedPage)&pageSize=50", authenticated: true,
                expectedPrincipal: principal)
            guard store.session?.accessToken == token else { return }
            guard let pageValue = dishResponse as? [String: Any],
                  let parsed = nativeDiningMenuPage(categoryResponse, dishResponse: pageValue, page: requestedPage,
                      pageSize: 50, storeID: storeID, existingDishes: requestedPage == 1 ? [] : dishes) else {
                throw MobileAPIError.unavailable("菜品或分类数据异常，请刷新重试")
            }
            categories = parsed.categories
            dishes = requestedPage == 1 ? parsed.dishes : dishes + parsed.dishes
            total = parsed.total
            page = requestedPage
        } catch {
            if store.session?.accessToken == token { self.error = error.localizedDescription }
        }
    }

    private func saveCategory() async {
        let trimmedName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !saving, let token = store.session?.accessToken,
              let principal = nativeTourismPrincipal(token),
              let sortOrder = Int(categorySort), sortOrder >= 0,
              !trimmedName.isEmpty, trimmedName.count <= 80 else { error = "分类名称需为 1–80 个字符，排序值需为非负整数"; return }
        saving = true; defer { saving = false }
        do {
            _ = try await MobileAPI(store: store).post("/api/JHCTIDining/SaveDishCategory", body: [
                "Id": categoryID, "Version": categoryVersion, "StoreId": storeID,
                "Name": trimmedName,
                "SortOrder": sortOrder, "IsEnabled": categoryEnabled
            ], authenticated: true, expectedPrincipal: principal)
            guard store.session?.accessToken == token else { return }
            categoryEditor = false; await load(page: 1)
            notice = nil
        } catch {
            if store.session?.accessToken == token {
                let reason = error.localizedDescription
                categoryEditor = false
                await load(page: 1)
                notice = "请求未获确认，列表已刷新；请核对分类是否已保存，再决定是否重试。\(reason)"
            }
        }
    }

    private func saveDish() async {
        let name = dishDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let skuValues = dishDraft.skus
        guard !saving, let token = store.session?.accessToken,
              let principal = nativeTourismPrincipal(token),
              !name.isEmpty, name.count <= 120, dishDraft.description.count <= 4000,
              !dishDraft.categoryID.isEmpty, !skuValues.isEmpty, skuValues.count <= 50,
              skuValues.allSatisfy({
                  let skuName = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                  return !skuName.isEmpty && skuName.count <= 80 && validPrice($0.price)
              }) else {
            error = "请检查菜品名称、说明、规格数量及价格（名称≤120字、说明≤4000字、规格1–50个、价格0–1,000,000且最多两位小数）"; return
        }
        saving = true; defer { saving = false }
        do {
            let skus: [[String: Any]] = skuValues.enumerated().map { index, sku in
                ["Id": sku.serverID, "Name": sku.name.trimmingCharacters(in: .whitespacesAndNewlines),
                 "Price": NSDecimalNumber(decimal: Decimal(string: sku.price) ?? 0), "SortOrder": index, "IsAvailable": sku.isAvailable]
            }
            _ = try await MobileAPI(store: store).post("/api/JHCTIDining/SaveDish", body: [
                "Id": dishDraft.id, "Version": dishDraft.version, "StoreId": storeID,
                "CategoryId": dishDraft.categoryID, "Name": name,
                "Description": dishDraft.description.trimmingCharacters(in: .whitespacesAndNewlines),
                "ImageUrl": dishDraft.imageURL, "SortOrder": dishDraft.sortOrder, "IsAvailable": dishDraft.isAvailable, "Skus": skus
            ], authenticated: true, expectedPrincipal: principal)
            guard store.session?.accessToken == token else { return }
            dishEditor = false; await load(page: 1)
            notice = nil
        } catch {
            if store.session?.accessToken == token {
                let reason = error.localizedDescription
                dishEditor = false
                await load(page: 1)
                notice = "请求未获确认，列表已刷新；请核对菜品是否已保存，再决定是否重试。\(reason)"
            }
        }
    }

    private func deleteDish(_ dish: [String: Any]) async {
        guard !saving, let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token),
              let id = dish["Id"] as? String, !id.isEmpty else { return }
        saving = true; defer { saving = false; pendingDelete = nil }
        do {
            _ = try await MobileAPI(store: store).delete("/api/JHCTIDining/DeleteDish?id=\(id)", authenticated: true,
                expectedPrincipal: principal)
            guard store.session?.accessToken == token else { return }
            await load(page: 1)
        } catch {
            if store.session?.accessToken == token {
                let reason = error.localizedDescription
                pendingDelete = nil
                await load(page: 1)
                notice = "删除请求未获确认，列表已刷新；请核对菜品状态，再决定是否重试。\(reason)"
            }
        }
    }

    private func categoryName(for value: Any?) -> String {
        let id = value.map { String(describing: $0) } ?? ""
        return categories.first(where: { ($0["Id"] as? String ?? "") == id })?["Name"] as? String ?? "未分类"
    }
    private func int(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) ?? 0 }
        return 0
    }
    private func priceText(_ value: Any?) -> String {
        guard let value else { return "价格待确认" }
        if let text = value as? String, let amount = Decimal(string: text) { return NSDecimalNumber(decimal: amount).stringValue }
        if let number = value as? NSNumber { return NSDecimalNumber(decimal: number.decimalValue).stringValue }
        return "价格待确认"
    }
    private func validPrice(_ text: String) -> Bool {
        guard let value = Decimal(string: text), value >= 0, value <= 1_000_000 else { return false }
        return text.range(of: #"^\d{1,7}(\.\d{1,2})?$"#, options: .regularExpression) != nil
    }
}
