import CoreFoundation
import Foundation
import SwiftUI

func nativeCartID(_ value: Any?) -> String? {
    guard let value = value as? String, let number = Int64(value), number > 0, String(number) == value else { return nil }
    return value
}

private func nativeCartNumber(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
    return number.doubleValue
}

private func nativeCartSelectableIDs(_ items: [[String: Any]]) -> [String] {
    items.compactMap { item in
        guard let id = nativeCartID(item["Id"]), nativeCartID(item["SkuId"]) != nil,
              let valid = item["IsValid"] as? NSNumber, CFGetTypeID(valid) == CFBooleanGetTypeID(), valid.boolValue,
              let quantity = nativeCartNumber(item["Quantity"]), quantity.rounded() == quantity, (1...99).contains(quantity),
              let stock = nativeCartNumber(item["AvailableStock"]), stock.rounded() == stock, stock >= quantity,
              let price = nativeCartNumber(item["CurrentPrice"]), (0...999999999).contains(price) else { return nil }
        return id
    }
}

private func nativeCartSelection(_ items: [[String: Any]], previous: Set<String>?) -> Set<String> {
    Set(nativeCartSelectableIDs(items).filter { previous?.contains($0) ?? true }.prefix(100))
}

private func nativeCartCanIncrease(_ item: [String: Any]) -> Bool {
    guard let id = nativeCartID(item["Id"]), nativeCartSelectableIDs([item]).contains(id),
          let quantity = nativeCartNumber(item["Quantity"]), quantity.rounded() == quantity,
          quantity >= 1, quantity <= 98, let stock = nativeCartNumber(item["AvailableStock"]),
          stock.rounded() == stock, stock > quantity else { return false }
    return true
}

private func nativeCartSnapshot(_ value: [String: Any]?) -> [[String: Any]]? {
    guard let items = value?["Items"] as? [[String: Any]] else { return nil }
    let ids = items.compactMap { nativeCartID($0["Id"]) }
    guard ids.count == items.count, Set(ids).count == ids.count else { return nil }
    return items
}

struct NativeCartView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var cart: [String: Any]?
    @State private var writable = false
    @State private var loading = false
    @State private var changing = false
    @State private var error: String?
    @State private var notice: String?
    @State private var ownerToken: String?
    @State private var selectedIDs: Set<String> = []
    @State private var hasPendingOrderRecovery = false
    @State private var selectionInitialized = false
    @State private var checkoutItems: [[String: Any]] = []
    @State private var checkoutOpen = false
    @State private var pageVisible = false
    @State private var needsRefresh = false
    @State private var readSequence = 0
    @State private var actionSequence = 0
    @State private var revision = 0

    private var items: [[String: Any]] { cart?["Items"] as? [[String: Any]] ?? [] }
    private var canInteract: Bool { pageVisible && !checkoutOpen && scenePhase == .active && !loading && !changing && !needsRefresh && cart != nil }
    private var canCheckout: Bool { canInteract && writable && !hasPendingOrderRecovery && !selectedIDs.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let notice {
                        Text(notice).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    } else if cart != nil && !writable {
                        Text("商品订购暂未开放；仍可查看和移除已有商品。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    }
                    if loading && cart == nil {
                        ProgressView("正在读取购物车…").frame(maxWidth: .infinity, alignment: .leading)
                    } else if cart != nil && items.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "cart").font(.system(size: 32)).foregroundStyle(Brand.primary)
                            Text("购物车还是空的").font(.system(size: NativeTypography.size(18), weight: .semibold)).foregroundStyle(Brand.ink)
                            Text("前往商品列表挑选喜欢的商品吧。")
                        }
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            .padding(28).frame(maxWidth: .infinity)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        ForEach(Array(items.enumerated()), id: \.offset) { entry in
                            cartItem(entry.element)
                        }
                    }
                    if hasPendingOrderRecovery {
                        Text("有一笔商城下单请求尚未确认。请先核对原请求，勿重新创建订单。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        Button {
                            checkoutItems = []; checkoutOpen = true
                        } label: {
                            Text("核对上次下单").font(.system(size: NativeTypography.size(16), weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .foregroundStyle(.white).background(Brand.primary, in: RoundedRectangle(cornerRadius: 10))
                        }.disabled(loading || changing)
                    }
                    if cart != nil {
                        Text("已选择 \(selectedIDs.count) 件商品；价格、配送和库存将在服务端重新核验。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        Button {
                            guard canCheckout else { return }
                            checkoutItems = items.filter {
                                guard let id = cartStringID($0["Id"]) else { return false }
                                return selectedIDs.contains(id) && nativeCartSelectableIDs([$0]).contains(id)
                            }
                            checkoutOpen = !checkoutItems.isEmpty
                        } label: {
                            Text("去结算").font(.system(size: NativeTypography.size(16), weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .foregroundStyle(.white).background(canCheckout ? Brand.primary : Color.gray.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(!canCheckout)
                    }
                    if needsRefresh && !changing {
                        Text("购物车状态待核对，请重新读取后继续。").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    }
                    if let error {
                        Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                    }
                    Button("重新读取购物车") { Task { await load() } }
                        .disabled(loading || changing)
                        .font(.system(size: NativeTypography.size(14), weight: .medium)).foregroundStyle(Brand.primary)
                }
                .padding(16)
            }
            .background(Brand.background)
            .navigationTitle("我的购物车")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .navigationDestination(isPresented: $checkoutOpen) {
                NativeTradeCheckoutView(store: store, cartItems: checkoutItems,
                    onRecoveryResolved: { hasPendingOrderRecovery = false })
            }
            .refreshable { await load() }
            .task(id: "\(store.session?.accessToken ?? "")-\(revision)") { await load() }
            .onAppear { pageVisible = true; revision += 1 }
            .onDisappear { pageVisible = false; invalidateCart() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { revision += 1 } else { invalidateCart() }
            }
        }
    }

    @ViewBuilder private func cartItem(_ item: [String: Any]) -> some View {
        let itemID = cartStringID(item["Id"])
        let skuID = cartStringID(item["SkuId"])
        let quantity = (item["Quantity"] as? NSNumber)?.intValue ?? 0
        let price = (item["CurrentPrice"] as? NSNumber)?.doubleValue
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                CachedRemoteImage(url: MobileAPI(store: store).mediaURL(item["ImageUrl"] as? String)) {
                    Image("Logo").resizable().scaledToFit()
                }
                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item["ProductName"] as? String ?? "商品")
                        .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
                    let specs = (item["Specs"] as? [String: String] ?? [:])
                        .sorted { $0.key < $1.key }.map { "\($0.key)：\($0.value)" }.joined(separator: " · ")
                    Text(specs.isEmpty ? "默认规格" : specs).font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                    Text(price.map { "¥\(String(format: "%.2f", $0)) × \(quantity)" } ?? "金额待确认 · \(quantity) 件")
                        .font(.system(size: NativeTypography.size(14), weight: .medium)).foregroundStyle(Brand.primary)
                    if let status = item["StatusMessage"] as? String, !status.isEmpty {
                        Text(status).font(.system(size: NativeTypography.size(12))).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            if let itemID {
                Button {
                    guard canInteract else { return }
                    selectionInitialized = true
                    if selectedIDs.contains(itemID) { selectedIDs.remove(itemID) }
                    else if nativeCartSelectableIDs([item]).contains(itemID) {
                        if selectedIDs.count < 100 { selectedIDs.insert(itemID) }
                        else { notice = "一次最多选择100件商品。" }
                    }
                } label: {
                    Label(selectedIDs.contains(itemID) ? "已选择" : "选择此商品",
                          systemImage: selectedIDs.contains(itemID) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: NativeTypography.size(14), weight: .medium)).foregroundStyle(Brand.primary)
                }
                .buttonStyle(.plain)
                .disabled(!canInteract || !nativeCartSelectableIDs([item]).contains(itemID))
            }
            HStack(spacing: 8) {
                Button("−") { Task { await mutate(item, remove: false, quantity: quantity - 1) } }
                    .disabled(!canInteract || !writable || skuID == nil || quantity <= 1
                        || (item["StatusCode"] as? String == "INVALID_PRICE"))
                Text(quantity > 0 ? "\(quantity) 件" : "数量异常")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
                if !(1...99).contains(quantity) || (item["StatusCode"] as? String == "INVALID_QUANTITY") {
                    Button("重置为1件") { Task { await mutate(item, remove: false, quantity: 1) } }
                        .disabled(!canInteract || !writable || skuID == nil
                            || ((item["AvailableStock"] as? NSNumber)?.intValue ?? 0) < 1)
                }
                Button("＋") { Task { await mutate(item, remove: false, quantity: quantity + 1) } }
                    .disabled(!canInteract || !writable || !nativeCartCanIncrease(item))
                Spacer()
                Button("移除", role: .destructive) { Task { await mutate(item, remove: true) } }
                    .disabled(!canInteract || itemID == nil)
            }
            .font(.system(size: NativeTypography.size(14), weight: .medium))
        }
        .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private func cartStringID(_ value: Any?) -> String? {
        nativeCartID(value)
    }

    private func invalidateCart() {
        readSequence += 1; cart = nil; writable = false; loading = false
        error = nil; notice = nil
    }

    @MainActor private func load() async {
        guard pageVisible, scenePhase == .active else { return }
        let principal = nativeTourismPrincipal(store.session?.accessToken)
        if ownerToken != principal {
            ownerToken = principal; invalidateCart(); selectedIDs = []; selectionInitialized = false
            actionSequence += 1; changing = false; needsRefresh = false
        }
        guard !changing else { return }
        guard let token = store.session?.accessToken else {
            invalidateCart(); error = "请先登录文旅账号，再查看购物车。"; return
        }
        readSequence += 1; let sequence = readSequence
        loading = true; cart = nil; error = nil; notice = nil; writable = false
        hasPendingOrderRecovery = NativeTradeRecoveryStore.read(nativeTradeRecoveryStorageKey(accessToken: token)).exists
            || NativeTradeRecoveryStore.read(nativeLegacyTradeRecoveryStorageKey(accessToken: token)).exists
        func isCurrent() -> Bool {
            !Task.isCancelled && pageVisible && scenePhase == .active && readSequence == sequence
                && store.session?.accessToken == token
        }
        do {
            let api = MobileAPI(store: store)
            let result = try await api.get("/api/JHCTICart/GetMyCart", authenticated: true,
                                           expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any]
            guard isCurrent() else { return }
            guard let rows = nativeCartSnapshot(result) else { throw MobileAPIError.unavailable("购物车回执格式异常，请重新读取。") }
            let enabled = await api.featureEnabled("F-ECOM-002")
            guard isCurrent() else { return }
            cart = result; writable = enabled; needsRefresh = false
            selectedIDs = nativeCartSelection(rows, previous: selectionInitialized ? selectedIDs : nil)
            selectionInitialized = true
            if !enabled { notice = "无法确认商品订购开关；数量修改和结算保持关闭。" }
        } catch {
            if isCurrent() { self.error = error.localizedDescription; needsRefresh = true }
        }
        if isCurrent() { loading = false }
    }

    @MainActor private func mutate(_ item: [String: Any], remove: Bool, quantity: Int = 1) async {
        guard canInteract, let token = store.session?.accessToken,
              ownerToken == nativeTourismPrincipal(token), let itemID = cartStringID(item["Id"]),
              let current = items.first(where: { cartStringID($0["Id"]) == itemID }),
              nativeCartNumber(current["Quantity"]) == nativeCartNumber(item["Quantity"]),
              cartStringID(current["SkuId"]) == cartStringID(item["SkuId"]) else { return }
        let skuID = cartStringID(current["SkuId"])
        guard remove || (writable && skuID != nil && (1...99).contains(quantity)) else { return }
        actionSequence += 1; let action = actionSequence; let sequence = readSequence
        changing = true; needsRefresh = true; error = nil; notice = nil
        func isCurrent() -> Bool {
            !Task.isCancelled && actionSequence == action && readSequence == sequence
                && pageVisible && scenePhase == .active && store.session?.accessToken == token
        }
        defer {
            if actionSequence == action {
                changing = false
                if pageVisible && scenePhase == .active && cart == nil { revision += 1 }
            }
        }
        do {
            let api = MobileAPI(store: store); let result: [String: Any]?
            if remove {
                result = try await api.delete("/api/JHCTICart/RemoveItem?id=\(itemID)", authenticated: true,
                    expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any]
            } else {
                let accessState = await api.featureAccessState("F-ECOM-002", forceRefresh: true)
                guard isCurrent() else { return }
                guard accessState == .open else {
                    writable = false
                    notice = accessState.message(featureName: "商品订购", action: "当前未修改购物车数量，仍可查看或移除商品。")
                    return
                }
                writable = true
                result = try await api.post("/api/JHCTICart/ChangeItem", body: [
                    "CartItemId": itemID, "SkuId": skuID!, "Quantity": quantity
                ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any]
            }
            guard isCurrent() else { return }
            guard let rows = nativeCartSnapshot(result) else { throw MobileAPIError.unavailable("购物车更新结果无法确认") }
            cart = result; selectedIDs = nativeCartSelection(rows, previous: selectedIDs); needsRefresh = false
        } catch {
            if isCurrent() { self.error = "更新结果尚未确认，请重新读取购物车后继续。" }
        }
    }
}

struct NativeTradeAddressBookView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var addresses: [[String: Any]] = []
    @State private var regions: [[String: Any]] = []
    @State private var addingAddress = false
    @State private var editingID = ""
    @State private var recipient = ""
    @State private var phone = ""
    @State private var detailAddress = ""
    @State private var selectedRegionCode = ""
    @State private var requestID = UUID().uuidString
    @State private var deletingID = ""
    @State private var confirmDelete = false
    @State private var ownerToken: String?
    @State private var loading = false
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?

    private var regionOptions: [[String: Any]] {
        var result = regions
        for address in addresses {
            let code = address["RegionCode"] as? String ?? ""
            guard !code.isEmpty, !result.contains(where: { ($0["RegionCode"] as? String) == code }) else { continue }
            result.append(["RegionCode": code, "RegionName": address["RegionName"] as? String ?? code])
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("地址仅对当前账号可见，并经过加密保存。每个账号最多保存 5 条。")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    if let notice { Text(notice).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted) }
                    if let error {
                        Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                        Button("重试") { Task { await load() } }.font(.system(size: NativeTypography.size(14)))
                    }
                    if loading && addresses.isEmpty { ProgressView("正在读取地址…") }
                    ForEach(addresses.indices, id: \.self) { index in
                        let address = addresses[index]
                        let id = nativeTradeAddressID(address["Id"]) ?? ""
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(address["RecipientName"] as? String ?? "")  \(address["PhoneNumber"] as? String ?? "")")
                                .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
                            Text("\(address["RegionName"] as? String ?? "") · \(address["DetailAddress"] as? String ?? "")")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            HStack {
                                Button("编辑") { beginEdit(address) }.disabled(busy)
                                Spacer()
                                Button("删除", role: .destructive) {
                                    deletingID = id; confirmDelete = true
                                }.disabled(busy || id.isEmpty)
                            }.font(.system(size: NativeTypography.size(14), weight: .medium))
                        }
                        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 11))
                    }
                    if addresses.isEmpty && !loading && error == nil {
                        Text("还没有收货地址。添加后可在支持的商品结算时选择。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 11))
                    }
                    if addingAddress || !editingID.isEmpty {
                        addressEditor
                    }
                    if addresses.count < 5 && regions.isEmpty {
                        Text("新增地址需要购物车中有可配送的实物商品，以便确认可用配送地区。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    }
                    if addingAddress || !editingID.isEmpty || (addresses.count < 5 && !regions.isEmpty) {
                        Button(addingAddress || !editingID.isEmpty ? "取消编辑" : "新增收货地址（\(addresses.count)/5）") {
                            if addingAddress || !editingID.isEmpty { clearEditor() } else { beginCreate() }
                        }.disabled(busy)
                    }
                }
                .padding(16)
            }
            .background(Brand.background)
            .navigationTitle("收货地址")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .task(id: store.session?.accessToken) { await load() }
            .confirmationDialog("删除这条收货地址？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除地址", role: .destructive) { Task { await deleteAddress() } }
                Button("取消", role: .cancel) { deletingID = "" }
            }
        }
    }

    private var addressEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(editingID.isEmpty ? "新增地址" : "编辑地址").font(.system(size: NativeTypography.size(14), weight: .semibold))
            TextField("收货人姓名", text: $recipient).textFieldStyle(.roundedBorder)
            TextField("联系电话", text: $phone).keyboardType(.phonePad).textFieldStyle(.roundedBorder)
            Picker("配送地区", selection: $selectedRegionCode) {
                ForEach(regionOptions.indices, id: \.self) { index in
                    let option = regionOptions[index]
                    Text(option["RegionName"] as? String ?? "请选择")
                        .tag(option["RegionCode"] as? String ?? "")
                }
            }.pickerStyle(.menu)
            TextField("街道、社区和门牌号", text: $detailAddress, axis: .vertical)
                .lineLimit(2...4).textFieldStyle(.roundedBorder)
            Button(busy ? "正在保存…" : (editingID.isEmpty ? "保存地址" : "保存地址修改")) {
                Task { await saveAddress() }
            }
            .disabled(busy || selectedRegionCode.isEmpty || recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || detailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 11))
    }

    @MainActor private func load() async {
        let token = store.session?.accessToken
        if ownerToken != token {
            ownerToken = token; addresses = []; regions = []; loading = false; busy = false
            deletingID = ""; confirmDelete = false; clearEditor()
        }
        error = nil; notice = nil
        guard let token else { error = "请先登录文旅账号，再管理收货地址。"; return }
        loading = true
        let api = MobileAPI(store: store)
        do {
            let accessState = await api.featureAccessState("F-ECOM-003")
            guard accessState == .open else {
                throw MobileAPIError.unavailable(accessState.message(featureName: "商城地址簿", action: "暂不能管理或保存收货地址。"))
            }
            guard let addressTask = try await api.get("/api/JHCTITradeOrder/GetMyAddresses", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)) as? [[String: Any]] else {
                throw MobileAPIError.unavailable("地址列表回执格式异常")
            }
            guard store.session?.accessToken == token else { loading = false; return }
            addresses = addressTask
            do {
                guard let cart = try await api.get("/api/JHCTICart/GetMyCart", authenticated: true,
                    expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any],
                      let items = cart["Items"] as? [[String: Any]] else {
                    throw MobileAPIError.unavailable("购物车回执格式异常")
                }
                let ids = items.filter { ($0["DeliveryType"] as? String ?? "Physical") == "Physical" }
                    .compactMap { nativeTradeAddressID($0["Id"]) }
                if !ids.isEmpty {
                    let value = try await api.postJSON("/api/JHCTICart/GetCheckoutRegions", body: ids, authenticated: true,
                        expectedPrincipal: nativeTourismPrincipal(token))
                    if store.session?.accessToken == token { regions = value as? [[String: Any]] ?? [] }
                }
                if regions.isEmpty { notice = "当前没有可用于新增地址的配送地区；已保存地址仍可查看和编辑。" }
            } catch { if store.session?.accessToken == token { notice = "配送地区暂不可用；已保存地址仍可查看和编辑。" } }
        } catch { if store.session?.accessToken == token { self.error = error.localizedDescription } }
        if store.session?.accessToken == token { loading = false }
    }

    private func beginCreate() {
        editingID = ""; recipient = ""; phone = ""; detailAddress = ""
        selectedRegionCode = regions.first?["RegionCode"] as? String ?? ""
        requestID = UUID().uuidString; addingAddress = true; error = nil
    }

    private func beginEdit(_ address: [String: Any]) {
        addingAddress = false
        editingID = nativeTradeAddressID(address["Id"]) ?? ""
        recipient = address["RecipientName"] as? String ?? ""; phone = address["PhoneNumber"] as? String ?? ""
        detailAddress = address["DetailAddress"] as? String ?? ""; selectedRegionCode = address["RegionCode"] as? String ?? ""
        error = nil
    }

    private func clearEditor() {
        addingAddress = false; editingID = ""; recipient = ""; phone = ""; detailAddress = ""; selectedRegionCode = ""
    }

    @MainActor private func saveAddress() async {
        guard !busy, let token = store.session?.accessToken,
              let region = regionOptions.first(where: { ($0["RegionCode"] as? String) == selectedRegionCode }) else { return }
        busy = true; error = nil
        do {
            var body: [String: Any] = ["RecipientName": recipient.trimmingCharacters(in: .whitespacesAndNewlines),
                "PhoneNumber": phone.trimmingCharacters(in: .whitespacesAndNewlines), "RegionCode": selectedRegionCode,
                "RegionName": region["RegionName"] as? String ?? selectedRegionCode,
                "DetailAddress": detailAddress.trimmingCharacters(in: .whitespacesAndNewlines)]
            if editingID.isEmpty { body["RequestId"] = requestID } else { body["Id"] = editingID }
            let result = try await MobileAPI(store: store).post("/api/JHCTITradeOrder/SaveMyAddress", body: body,
                authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any]
            guard store.session?.accessToken == token, nativeTradeAddressID(result?["Id"]) != nil else {
                throw MobileAPIError.unavailable("地址保存结果无法确认，请重新读取地址后继续。")
            }
            clearEditor(); requestID = UUID().uuidString; await load()
        } catch { if store.session?.accessToken == token { self.error = error.localizedDescription } }
        if store.session?.accessToken == token { busy = false }
    }

    @MainActor private func deleteAddress() async {
        guard !busy, let token = store.session?.accessToken, let id = nativeTradeAddressID(deletingID) else { return }
        busy = true; error = nil
        do {
            let result = try await MobileAPI(store: store).post("/api/JHCTITradeOrder/DeleteMyAddress", body: ["Id": id],
                authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? Bool
            guard store.session?.accessToken == token, result == true else { throw MobileAPIError.unavailable("地址删除结果无法确认，请重新读取。") }
            addresses.removeAll { nativeTradeAddressID($0["Id"]) == id }; deletingID = ""
            if editingID == id { clearEditor() }
        } catch { if store.session?.accessToken == token { self.error = error.localizedDescription } }
        if store.session?.accessToken == token { busy = false }
    }
}
