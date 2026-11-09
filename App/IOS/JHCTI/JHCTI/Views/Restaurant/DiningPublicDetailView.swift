import SwiftUI

struct NativeDiningThemeImage: View {
    let store: SessionStore
    let path: String?
    let width: CGFloat?
    let height: CGFloat
    @State private var imageLoaded = false

    private var url: URL? { MobileAPI(store: store).mediaURL(path) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let url {
                CachedRemoteImage(url: url, onLoadResult: { imageLoaded = $0 }) { illustration }
            } else {
                illustration
            }
            if !imageLoaded {
                Text("江都主题插画").font(.system(size: width == nil ? 11 : 8)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule()).padding(5)
            }
        }
        .frame(maxWidth: width ?? .infinity, minHeight: height, maxHeight: height)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(imageLoaded ? "餐饮图片" : "江都餐饮主题插画")
    }

    private var illustration: some View {
        Image("Quick2").resizable().scaledToFill()
    }
}

struct DiningPublicDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let store: SessionStore
    let id: String
    @State private var menu: [String: Any]?
    @State private var packages: [[String: Any]] = []
    @State private var packageLoading = true
    @State private var packagePending = false
    @State private var packageError: String?
    @State private var selectedDiningPackage: [String: Any]?
    @State private var showDiningPackageOrders = false
    @State private var packageRecoveryAvailable = false
    @State private var packageRecoveryBusy = false
    @State private var packageRecoveryMessage: String?
    @State private var slots: [[String: Any]] = []
    @State private var unsupportedSlotCount = 0
    @State private var reservations: [[String: Any]] = []
    @State private var selectedSlotID = ""
    @State private var selectedDate = Date()
    @State private var guestCount = 2
    @State private var guestName = ""
    @State private var guestPhone = ""
    @State private var guestNote = ""
    @State private var featureState = "loading"
    @State private var loading = true
    @State private var reservationsLoading = false
    @State private var submitting = false
    @State private var cancelling = false
    @State private var error: String?
    @State private var reservationError: String?
    @State private var queueState = "loading"
    @State private var queueSession: [String: Any]?
    @State private var queueEntries: [[String: Any]] = []
    @State private var queueRequestSequence = 0
    @State private var queueEntriesRequestSequence = 0
    @State private var queueError: String?
    @State private var queueName = ""
    @State private var queuePhone = ""
    @State private var queueCount = 2
    @State private var queueBusy = false
    @State private var queueCancelID = ""
    @State private var showQueueCancelConfirmation = false
    @State private var notice: String?
    @State private var pendingCancelID = ""
    @State private var showCancelConfirmation = false
    @State private var requestSequence = 0
    @State private var packageRequestSequence = 0
    @State private var reservationSequence = 0
    private let businessTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private var businessCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = businessTimeZone
        return calendar
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.calendar = businessCalendar
        formatter.timeZone = businessTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: selectedDate)
    }

    private var selectedSlot: [String: Any]? {
        slots.first { Self.string($0["Id"] ?? $0["id"]) == selectedSlotID }
    }

    private var guestBounds: ClosedRange<Int> {
        let minimum = max(1, Self.int(selectedSlot?["MinSeats"] ?? selectedSlot?["minSeats"]) ?? 1)
        let maximum = min(30, Self.int(selectedSlot?["MaxSeats"] ?? selectedSlot?["maxSeats"]) ?? 30)
        return minimum...max(minimum, maximum)
    }

    private func isBookableDiningSlot(_ slot: [String: Any]) -> Bool {
        let minimum = max(1, Self.int(slot["MinSeats"] ?? slot["minSeats"]) ?? 1)
        let maximum = Self.int(slot["MaxSeats"] ?? slot["maxSeats"]) ?? 30
        return minimum <= 30 && maximum >= minimum
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading && menu == nil {
                    ProgressView("正在加载餐厅…").frame(maxWidth: .infinity).padding(30)
                } else if let error, menu == nil {
                    VStack(spacing: 10) {
                        Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
                        Button("重试") { Task { await load() } }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity).padding(24)
                } else if let menu {
                    NativeDiningThemeImage(store: store, path: catalogCover(menu), width: nil, height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(menu["StoreName"] as? String ?? "餐饮门店")
                            .font(.system(size: NativeTypography.size(22), weight: .bold, design: .serif)).foregroundStyle(Brand.ink)
                        if let address = menu["Address"] as? String, !address.isEmpty { Text(address).font(.subheadline).foregroundStyle(Brand.muted) }
                        if let hours = menu["BusinessHours"] as? String, !hours.isEmpty { Text("营业时间：\(hours)").font(.caption).foregroundStyle(Brand.muted) }
                        if let phone = menu["Phone"] as? String, !phone.isEmpty {
                            Button {
                                let number = phone.filter { $0.isNumber || "+*#".contains($0) }
                                if !number.isEmpty, let url = URL(string: "tel:\(number)") { openURL(url) }
                            } label: {
                                Text("联系门店　\(phone) ›")
                                    .font(.caption.weight(.semibold)).foregroundStyle(Brand.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))

                    NativeRestaurantShare(storeID: id, storeName: menu["StoreName"] as? String ?? "餐饮门店")

                    NativeCoordinateMapCard(title: "餐厅位置", name: menu["StoreName"] as? String ?? "餐饮门店",
                        address: menu["Address"] as? String,
                        latitude: (menu["Latitude"] as? NSNumber)?.doubleValue,
                        longitude: (menu["Longitude"] as? NSNumber)?.doubleValue,
                        coordinateSystem: menu["CoordinateSystem"] as? String ?? "")

                    DiningPublicMenuSection(store: store, menu: menu)
                    DiningPublicPackagesSection(
                        store: store,
                        packages: packages,
                        isLoading: packageLoading,
                        isPending: packagePending,
                        errorMessage: packageError,
                        recoveryAvailable: packageRecoveryAvailable,
                        recoveryBusy: packageRecoveryBusy,
                        recoveryMessage: packageRecoveryMessage,
                        onRetry: { Task { await loadDiningPackages() } },
                        onBuy: { selectedDiningPackage = $0 },
                        onRecover: { Task { await recoverPendingPackageOrder() } }
                    )
                    Text("菜单与价格来自门店当前公开信息；团购订单以服务端确认价格和状态为准。")
                        .font(.caption2).foregroundStyle(Brand.muted)
                    if queueState != "loading" {
                        DiningPublicQueuePanel(
                            state: queueState,
                            errorMessage: queueError,
                            session: queueSession,
                            entries: queueEntries,
                            isAuthenticated: store.session != nil,
                            name: $queueName,
                            phone: $queuePhone,
                            guestCount: $queueCount,
                            isBusy: queueBusy,
                            cancellingEntryID: queueCancelID,
                            onRefresh: { Task { await loadQueue() } },
                            onRetryEntries: { Task { _ = await loadQueueEntries() } },
                            onJoin: { Task { await submitQueue() } },
                            onRequestCancel: { entryID in
                                queueCancelID = entryID
                                showQueueCancelConfirmation = true
                            }
                        )
                    }
                    DiningPublicReservationPanel(
                        featureState: featureState,
                        errorMessage: reservationError,
                        slots: slots,
                        unsupportedSlotCount: unsupportedSlotCount,
                        isLoading: loading,
                        selectedDate: $selectedDate,
                        businessCalendar: businessCalendar,
                        businessTimeZone: businessTimeZone,
                        dateText: dateText,
                        selectedSlotID: selectedSlotID,
                        hasSelectedSlot: selectedSlot != nil,
                        guestBounds: guestBounds,
                        guestCount: $guestCount,
                        guestName: $guestName,
                        guestPhone: $guestPhone,
                        guestNote: $guestNote,
                        isAuthenticated: store.session != nil,
                        isSubmitting: submitting,
                        isCancelling: cancelling,
                        reservationsLoading: reservationsLoading,
                        reservations: reservations,
                        notice: notice,
                        pendingCancelID: pendingCancelID,
                        onDateChanged: {
                            loading = true
                            Task {
                                await loadSlots()
                                loading = false
                            }
                        },
                        onRetry: { Task { await load() } },
                        onSelectSlot: { slot in
                            selectedSlotID = Self.string(slot["Id"] ?? slot["id"])
                            guestCount = min(guestBounds.upperBound, max(guestBounds.lowerBound, guestCount))
                        },
                        onSubmit: { Task { await submitReservation() } },
                        onRequestCancel: { reservationID in
                            pendingCancelID = reservationID
                            showCancelConfirmation = true
                        }
                    )
                }
            }
            .padding(16)
        }
        .background(Brand.background)
        .navigationTitle("餐厅详情")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .simultaneousGesture(DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard value.startLocation.x <= 32, horizontal >= 72,
                      horizontal > abs(vertical) * 1.25 else { return }
                dismiss()
            })
        .sheet(isPresented: Binding(get: { selectedDiningPackage != nil || showDiningPackageOrders }, set: { if !$0 { selectedDiningPackage = nil; showDiningPackageOrders = false } })) {
            if showDiningPackageOrders {
                NativeDiningPackageOrdersView(store: store)
            } else if let selectedDiningPackage {
                NativeDiningPackageCheckoutView(store: store, storeID: id, package: selectedDiningPackage)
            }
        }
        .refreshable { await load() }
        .onChange(of: selectedDiningPackage != nil) { _, presented in
            if !presented { refreshPendingPackageRecoveryAvailability() }
        }
        .task(id: store.session?.accessToken) {
            queueRequestSequence += 1
            queueEntriesRequestSequence += 1
            queueState = "loading"; queueError = nil
            reservations = []; reservationsErrorReset()
            queueEntries = []; queueError = nil; queueSession = nil
            guestName = ""; guestPhone = ""; guestNote = ""
            queueName = ""; queuePhone = ""
            await load()
        }
        .confirmationDialog(showQueueCancelConfirmation ? "取消排队" : "撤回预订申请",
                            isPresented: Binding(get: { showCancelConfirmation || showQueueCancelConfirmation }, set: { presented in
                                if !presented { showCancelConfirmation = false; showQueueCancelConfirmation = false }
                            }), titleVisibility: .visible) {
            if showQueueCancelConfirmation {
                Button("确认取消", role: .destructive) { Task { await cancelQueueEntry(queueCancelID) } }
                Button("暂不取消", role: .cancel) { queueCancelID = "" }
            } else {
                Button("确认撤回", role: .destructive) { Task { await cancelReservation(pendingCancelID) } }
                Button("暂不撤回", role: .cancel) { pendingCancelID = "" }
            }
        } message: {
            Text(showQueueCancelConfirmation ? "确认取消当前等待号码吗？" : "撤回待处理申请后，门店会收到释放的预订名额。")
        }
    }

    @MainActor private func loadQueue() async {
        queueRequestSequence += 1
        let requestSequence = queueRequestSequence
        let sessionToken = store.session?.accessToken
        guard Int64(id).map({ $0 > 0 }) == true else {
            if requestSequence == queueRequestSequence { queueState = "error"; queueError = "门店编号无效" }
            return
        }
        queueState = "loading"; queueError = nil; queueSession = nil
        do {
            let access = try await MobileAPI(store: store).get("/api/JHCTIFeatureAccess/GetPublicStatus?featureId=F-FNB-003") as? [String: Any]
            guard requestSequence == queueRequestSequence, store.session?.accessToken == sessionToken else { return }
            guard let access else { throw MobileAPIError.unavailable("排队功能状态响应格式异常") }
            guard access["IsConfigured"] as? Bool == true, access["IsEnabled"] as? Bool == true else {
                queueState = "disabled"
                if store.session != nil { _ = await loadQueueEntries() }
                return
            }
            let result = try await MobileAPI(store: store).get("/api/JHCTIDining/GetOpenQueueStatus?storeId=\(id)")
            guard requestSequence == queueRequestSequence, store.session?.accessToken == sessionToken else { return }
            if result is NSNull { queueSession = nil }
            else if let value = result as? [String: Any], Self.string(value["StoreId"] ?? value["storeId"]) == id {
                queueSession = value
            } else { throw MobileAPIError.unavailable("排队状态数据与当前门店不匹配") }
            queueState = "open"
            if store.session != nil { _ = await loadQueueEntries() }
        } catch is CancellationError {
            return
        } catch {
            guard requestSequence == queueRequestSequence, store.session?.accessToken == sessionToken else { return }
            queueState = "error"; queueError = error.localizedDescription
        }
    }

    @MainActor private func loadQueueEntries() async -> [[String: Any]]? {
        queueEntriesRequestSequence += 1
        let requestSequence = queueEntriesRequestSequence
        guard let session = store.session else {
            if requestSequence == queueEntriesRequestSequence { queueEntries = []; queueError = nil }
            return []
        }
        queueError = nil
        do {
            let value = try await MobileAPI(store: store).get("/api/JHCTIDining/GetMyQueueEntries?storeId=\(id)", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(session.accessToken))
            guard requestSequence == queueEntriesRequestSequence,
                  store.session?.accessToken == session.accessToken else { return nil }
            guard let rows = value as? [[String: Any]], rows.allSatisfy({
                Self.string($0["StoreId"] ?? $0["storeId"]) == id
                    && Int64(Self.string($0["Id"] ?? $0["id"])).map({ $0 > 0 }) == true
                    && ["Waiting", "Called", "Completed", "Missed", "Cancelled"].contains($0["Status"] as? String ?? $0["status"] as? String ?? "")
            }) else { throw MobileAPIError.unavailable("本人排队记录格式异常，请刷新重试") }
            queueEntries = rows
            return rows
        } catch is CancellationError {
            return nil
        } catch {
            if requestSequence == queueEntriesRequestSequence,
               store.session?.accessToken == session.accessToken { queueError = error.localizedDescription }
            return nil
        }
    }

    @MainActor private func submitQueue() async {
        guard !queueBusy, let session = store.session,
              let queueSession, queueSession["IsOpen"] as? Bool == true || queueSession["isOpen"] as? Bool == true else { return }
        let name = queueName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = queuePhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, phone.count <= 40,
              phone.range(of: "^\\+?[0-9()\\-\\s]{6,40}$", options: .regularExpression) != nil else {
            queueError = "请填写有效的联系人姓名和联系电话"; return
        }
        queueBusy = true; queueError = nil
        defer { queueBusy = false }
        let latestQueueEnabled = await MobileAPI(store: store).featureEnabled("F-FNB-003", forceRefresh: true)
        guard store.session?.accessToken == session.accessToken else { queueError = "登录账号已变化，请重新确认后取号。"; return }
        guard latestQueueEnabled else {
            queueState = "disabled"; self.queueSession = nil
            queueError = "餐饮排队已关闭或暂时无法确认，本次没有取号。"
            return
        }
        var mutationConfirmed = false
        let queueAccess = await MobileAPI(store: store).featureAccessState("F-FNB-003", forceRefresh: true)
        guard store.session?.accessToken == session.accessToken else { return }
        guard queueAccess == .open else {
            self.queueSession = nil
            queueState = queueAccess == .closed || queueAccess == .pendingConfirmation ? "disabled" : "error"
            queueError = queueAccess.message(featureName: "餐饮排队功能", action: "暂不取号")
            return
        }
        do {
            let value = try await MobileAPI(store: store).post("/api/JHCTIDining/JoinQueue", body: [
                "StoreId": id, "GuestName": name, "GuestPhone": phone, "GuestCount": queueCount
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(session.accessToken))
            guard store.session?.accessToken == session.accessToken,
                  let receipt = value as? [String: Any],
                  Self.string(receipt["StoreId"] ?? receipt["storeId"]) == id,
                  Int64(Self.string(receipt["Id"] ?? receipt["id"])).map({ $0 > 0 }) == true,
                  (Self.int(receipt["QueueNumber"] ?? receipt["queueNumber"]) ?? 0) > 0,
                  (receipt["Status"] as? String ?? receipt["status"] as? String) == "Waiting" else {
                throw MobileAPIError.unavailable("取号回执无法确认，请刷新本人排队记录")
            }
            mutationConfirmed = true
            queueName = ""; queuePhone = ""
        } catch is CancellationError {
            if !mutationConfirmed, store.session?.accessToken == session.accessToken {
                queueError = "取号请求已取消，结果可能已提交；请刷新本人排队记录核对。"
            }
            return
        } catch {
            if Task.isCancelled {
                if !mutationConfirmed, store.session?.accessToken == session.accessToken {
                    queueError = "取号请求已取消，结果可能已提交；请刷新本人排队记录核对。"
                }
                return
            }
            guard store.session?.accessToken == session.accessToken else { return }
            let refreshed = await loadQueueEntries()
            guard store.session?.accessToken == session.accessToken else { return }
            if refreshed?.contains(where: {
                Self.string($0["StoreId"] ?? $0["storeId"]) == id
                    && ["Waiting", "Called"].contains($0["Status"] as? String ?? $0["status"] as? String ?? "")
            }) == true { queueError = nil }
            else if refreshed == nil { queueError = "取号结果暂无法确认，请刷新本人排队记录" }
            else { queueError = error.localizedDescription }
        }
        if store.session?.accessToken == session.accessToken { await loadQueue() }
    }

    @MainActor private func cancelQueueEntry(_ entryID: String) async {
        guard !queueBusy, let session = store.session, Int64(entryID).map({ $0 > 0 }) == true else { return }
        queueBusy = true; queueError = nil
        defer { queueBusy = false; queueCancelID = "" }
        var mutationConfirmed = false
        do {
            let value = try await MobileAPI(store: store).post("/api/JHCTIDining/CancelMyQueueEntry?id=\(entryID)", body: [:],
                authenticated: true, expectedPrincipal: nativeTourismPrincipal(session.accessToken))
            guard store.session?.accessToken == session.accessToken, Self.string(value) == entryID else {
                throw MobileAPIError.unavailable("取消回执无法确认，请刷新本人排队记录")
            }
            mutationConfirmed = true
        } catch is CancellationError {
            if !mutationConfirmed, store.session?.accessToken == session.accessToken {
                queueError = "取消请求已取消，结果可能已提交；请刷新本人排队记录核对。"
            }
            return
        } catch {
            if Task.isCancelled {
                if !mutationConfirmed, store.session?.accessToken == session.accessToken {
                    queueError = "取消请求已取消，结果可能已提交；请刷新本人排队记录核对。"
                }
                return
            }
            guard store.session?.accessToken == session.accessToken else { return }
            let refreshed = await loadQueueEntries()
            guard store.session?.accessToken == session.accessToken else { return }
            let stillWaiting = refreshed?.contains {
                Self.string($0["Id"] ?? $0["id"]) == entryID
                    && ($0["Status"] as? String ?? $0["status"] as? String ?? "") == "Waiting"
            } == true
            queueError = refreshed == nil ? "取消结果暂无法确认，请刷新本人排队记录" : stillWaiting ? error.localizedDescription : nil
            return
        }
        guard store.session?.accessToken == session.accessToken else { return }
        _ = await loadQueueEntries()
    }

    @MainActor private func load() async {
        refreshPendingPackageRecoveryAvailability()
        guard Int64(id).map({ $0 > 0 }) == true else { error = "门店编号无效"; loading = false; return }
        requestSequence += 1
        let sequence = requestSequence
        packageRequestSequence += 1
        queueRequestSequence += 1
        queueEntriesRequestSequence += 1
        loading = true; error = nil; reservationError = nil; menu = nil
        packageLoading = true; packagePending = false; packageError = nil; packages = []
        queueState = "loading"; queueSession = nil; queueEntries = []; queueError = nil
        Task { await loadQueue() }
        unsupportedSlotCount = 0
        do {
            guard await MobileAPI(store: store).featureEnabled("MODULE-DINING") else {
                packageLoading = false; slots = []; reservations = []; queueEntries = []
                throw MobileAPIError.unavailable("特色美食模块暂未开放")
            }
            guard sequence == requestSequence else { return }
            guard let value = try await MobileAPI(store: store).getPublicCached("/api/JHCTIDining/GetPublicMenu?storeId=\(id)", forceRefresh: true) as? [String: Any],
                  Self.string(value["StoreId"] ?? value["storeId"]) == id else {
                throw MobileAPIError.unavailable("餐厅详情回执无效，请刷新重试")
            }
            guard sequence == requestSequence else { return }
            menu = value
            packageRequestSequence += 1
            let packageSequence = packageRequestSequence
            Task { await loadDiningPackages(sequence: packageSequence) }
            if await MobileAPI(store: store).featureEnabled("F-FNB-002") {
                featureState = "open"
                await loadSlots(sequence: sequence)
                _ = await loadReservations()
            } else {
                featureState = "closed"; slots = []; unsupportedSlotCount = 0
                _ = await loadReservations()
            }
        } catch {
            if sequence == requestSequence {
                packageLoading = false
                self.error = error.localizedDescription; featureState = "error"
                _ = await loadReservations()
            }
        }
        if sequence == requestSequence { loading = false }
    }

    @MainActor private func loadDiningPackages(sequence: Int? = nil) async {
        if sequence == nil { packageRequestSequence += 1 }
        let requestID = sequence ?? packageRequestSequence
        packageLoading = true; packageError = nil; packagePending = false; packages = []
        defer { if requestID == packageRequestSequence { packageLoading = false } }
        do {
            let value = try await MobileAPI(store: store).get("/api/JHCTIDiningPackage/GetPublicPackages?storeId=\(id)")
            guard requestID == packageRequestSequence else { return }
            guard let rows = value as? [[String: Any]], rows.allSatisfy({
                let items = $0["Items"] as? [[String: Any]] ?? $0["items"] as? [[String: Any]] ?? []
                let price = Self.decimal($0["SalePrice"] ?? $0["salePrice"]) ?? -1
                return Int64(Self.string($0["Id"] ?? $0["id"])).map { $0 > 0 } == true
                    && !String(describing: $0["Name"] ?? $0["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && price > 0 && price <= 1_000_000
                    && !items.isEmpty && items.allSatisfy { (Self.int($0["Quantity"] ?? $0["quantity"]) ?? 0) > 0 }
            }), Set(rows.map { Self.string($0["Id"] ?? $0["id"]) }).count == rows.count else {
                throw MobileAPIError.unavailable("团购套餐信息格式无效")
            }
            packages = rows
        } catch {
            guard requestID == packageRequestSequence else { return }
            if error is CancellationError { return }
            if error.localizedDescription.contains("功能待开放") { packagePending = true }
            else { packageError = error.localizedDescription }
        }
    }

    private func pendingPackageRecoveryRecords() -> [(String, String, [String: Any])] {
        guard let token = store.session?.accessToken else { return [] }
        let prefixes = [nativeTradeRecoveryStorageKey(accessToken: token), nativeLegacyTradeRecoveryStorageKey(accessToken: token)]
            .map { "\($0).dining-package.\(id)." }
        return UserDefaults.standard.dictionaryRepresentation().compactMap { key, value -> (String, String, [String: Any])? in
            guard let prefix = prefixes.first(where: { key.hasPrefix($0) }) else { return nil }
            let packageID = String(key.dropFirst(prefix.count))
            let attempt = value as? [String: Any] ?? [:]
            return (key, packageID, attempt)
        }.sorted { $0.0 < $1.0 }
    }

    @MainActor private func refreshPendingPackageRecoveryAvailability() {
        packageRecoveryAvailable = !pendingPackageRecoveryRecords().isEmpty
        packageRecoveryMessage = nil
    }

    @MainActor private func recoverPendingPackageOrder() async {
        guard let token = store.session?.accessToken else {
            packageRecoveryMessage = "请先登录文旅账号，再核对团购订单。"
            return
        }
        packageRecoveryBusy = true; packageRecoveryMessage = nil
        defer { packageRecoveryBusy = false }
        let records = pendingPackageRecoveryRecords()
        guard !records.isEmpty else {
            packageRecoveryAvailable = false
            packageRecoveryMessage = "当前账号没有可核对的团购恢复记录。"
            return
        }
        do {
            for (key, packageID, attempt) in records {
                guard store.session?.accessToken == token else { return }
                let requestID = attempt["IdempotencyKey"] as? String ?? ""
                let quantity = attempt["Quantity"] as? Int ?? -1
                let points = (attempt["PointsToUse"] as? String).flatMap(Int64.init)
                let expectedAmountCents = (attempt["ExpectedAmountCents"] as? String).flatMap(Int64.init)
                guard Int64(packageID).map({ $0 > 0 }) == true,
                      requestID.range(of: "^[A-Za-z0-9._:-]{16,100}$", options: .regularExpression) != nil,
                      quantity > 0 && quantity <= 10, let points, points >= 0,
                      attempt["ExpectedAmountCents"] == nil || expectedAmountCents != nil else {
                    packageRecoveryMessage = "订单恢复标记无法安全读取；请先核对本人团购券，不会创建新订单。"
                    return
                }
                let response = try await MobileAPI(store: store).get(
                    "/api/JHCTIDiningPackage/GetMyOrderByIdempotencyKey?idempotencyKey=\(requestID)", authenticated: true,
                    expectedPrincipal: nativeTourismPrincipal(token)
                )
                guard store.session?.accessToken == token else { return }
                if let order = response as? [String: Any] {
                    guard Int64(Self.string(order["Id"])).map({ $0 > 0 }) == true,
                          Self.string(order["StoreId"]) == id, Self.string(order["PackageId"]) == packageID,
                          Self.int(order["Quantity"]) == quantity,
                          Int64(Self.string(order["PointsUsed"])) == points,
                          nativePointsOrderSnapshotMatches(order, expectedPoints: points, expectedAmountCents: expectedAmountCents) else {
                        packageRecoveryMessage = "找到团购订单，但订单快照与本机恢复记录不一致；请前往我的团购券核对。"
                        return
                    }
                    UserDefaults.standard.removeObject(forKey: key)
                    packageRecoveryAvailable = false
                    packageRecoveryMessage = "已找到上次提交的团购订单，正在打开本人团购券。"
                    showDiningPackageOrders = true
                    return
                }
                guard response is NSNull else {
                    packageRecoveryMessage = "团购订单回执无法确认；恢复记录已保留，请前往我的团购券核对。"
                    return
                }
            }
            packageRecoveryMessage = "暂未查到已创建订单。恢复记录已保留；团购关闭时不会新建订单。"
        } catch is CancellationError {
            packageRecoveryMessage = "订单核对已取消；恢复记录已保留，可以稍后重试。"
        } catch {
            guard store.session?.accessToken == token else { return }
            packageRecoveryMessage = "团购订单暂时无法核对，恢复记录已保留；请稍后重试或前往我的团购券查看。"
        }
    }

    @MainActor private func loadSlots(sequence: Int? = nil) async {
        let requestID = sequence ?? requestSequence
        reservationError = nil; slots = []; selectedSlotID = ""; unsupportedSlotCount = 0
        do {
            let path = "/api/JHCTIDining/GetAvailableReservationSlots?storeId=\(id)&date=\(dateText)"
            let value = try await MobileAPI(store: store).get(path)
            guard requestID == requestSequence else { return }
            guard let rows = value as? [[String: Any]], rows.allSatisfy({
                Int64(Self.string($0["Id"] ?? $0["id"])) .map({ $0 > 0 }) == true
                    && (Self.int($0["Capacity"] ?? $0["capacity"]) ?? -1) >= 0
                    && (Self.int($0["ReservedCount"] ?? $0["reservedCount"]) ?? -1) >= 0
            }) else { throw MobileAPIError.unavailable("可预订时段数据格式异常") }
            let usableRows = rows.filter(isBookableDiningSlot)
            unsupportedSlotCount = rows.count - usableRows.count
            slots = usableRows
            if let first = usableRows.first {
                selectedSlotID = Self.string(first["Id"] ?? first["id"])
                guestCount = min(guestBounds.upperBound, max(guestBounds.lowerBound, guestCount))
            }
        } catch {
            if requestID == requestSequence { reservationError = error.localizedDescription }
        }
    }

    @MainActor private func loadReservations() async -> [[String: Any]]? {
        guard let session = store.session else { reservations = []; reservationsLoading = false; return [] }
        reservationSequence += 1
        let sequence = reservationSequence
        reservationsLoading = true; reservationError = nil
        defer { if sequence == reservationSequence { reservationsLoading = false } }
        do {
            let value = try await MobileAPI(store: store).get("/api/JHCTIDining/GetMyReservations?storeId=\(id)", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(session.accessToken))
            guard store.session?.accessToken == session.accessToken, sequence == reservationSequence else { return nil }
            guard let rows = value as? [[String: Any]], rows.allSatisfy({
                Self.string($0["StoreId"] ?? $0["storeId"]) == id
                    && Int64(Self.string($0["SlotId"] ?? $0["slotId"])) .map({ $0 > 0 }) == true
                    && ["Pending", "Confirmed", "Declined", "Cancelled"].contains($0["Status"] as? String ?? $0["status"] as? String ?? "")
            }) else { throw MobileAPIError.unavailable("本人预订回执格式异常，请刷新重试") }
            reservations = rows
            return rows
        } catch {
            if store.session?.accessToken == session.accessToken && sequence == reservationSequence {
                reservationError = error.localizedDescription
            }
            return nil
        }
    }

    @MainActor private func submitReservation() async {
        guard !submitting, let session = store.session, let slot = selectedSlot,
              !guestName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              guestName.count <= 80,
              !guestPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              guestPhone.count <= 40, guestNote.count <= 500,
              guestBounds.contains(guestCount) else {
            reservationError = "请检查联系人、联系电话、人数和所选时段"; return
        }
        let slotID = Self.string(slot["Id"] ?? slot["id"])
        submitting = true; reservationError = nil; notice = nil
        defer { submitting = false }
        let latestReservationEnabled = await MobileAPI(store: store).featureEnabled("F-FNB-002", forceRefresh: true)
        guard store.session?.accessToken == session.accessToken else { reservationError = "登录账号已变化，请重新确认后提交。"; return }
        featureState = latestReservationEnabled ? "open" : "closed"
        guard latestReservationEnabled else {
            slots = []
            reservationError = "餐饮预订已关闭或暂时无法确认，本次没有提交申请。"
            return
        }
        var mutationConfirmed = false
        do {
            let latestReservationEnabled = await MobileAPI(store: store).featureEnabled("F-FNB-002", forceRefresh: true)
            guard store.session?.accessToken == session.accessToken else { return }
            featureState = latestReservationEnabled ? "open" : "closed"
            guard latestReservationEnabled else {
                reservationError = "餐饮预订服务已关闭或暂时无法确认，本次没有提交申请。"
                return
            }
            let result = try await MobileAPI(store: store).post("/api/JHCTIDining/CreateReservation", body: [
                "SlotId": slotID,
                "GuestName": guestName.trimmingCharacters(in: .whitespacesAndNewlines),
                "GuestPhone": guestPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                "GuestCount": guestCount,
                "GuestNote": guestNote.trimmingCharacters(in: .whitespacesAndNewlines)
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(session.accessToken))
            guard store.session?.accessToken == session.accessToken,
                  Int64(Self.string(result)).map({ $0 > 0 }) != nil else {
                throw MobileAPIError.unavailable("预约回执无法确认，请刷新本人预订记录")
            }
            mutationConfirmed = true
            notice = "预订申请已提交，等待门店确认。"
            guestNote = ""
        } catch is CancellationError {
            if !mutationConfirmed, store.session?.accessToken == session.accessToken {
                reservationError = "提交请求已取消，结果可能已提交；请刷新本人预订记录核对。"
            }
            return
        } catch {
            if Task.isCancelled {
                if !mutationConfirmed, store.session?.accessToken == session.accessToken {
                    reservationError = "提交请求已取消，结果可能已提交；请刷新本人预订记录核对。"
                }
                return
            }
            guard store.session?.accessToken == session.accessToken else { return }
            let refreshed = await loadReservations()
            guard store.session?.accessToken == session.accessToken else { return }
            await loadSlots()
            guard store.session?.accessToken == session.accessToken else { return }
            if refreshed?.contains(where: {
                Self.string($0["SlotId"] ?? $0["slotId"]) == slotID
                    && ($0["Status"] as? String ?? $0["status"] as? String ?? "").lowercased() == "pending"
            }) == true {
                mutationConfirmed = true
                notice = "该时段的预订申请已提交，请查看本人记录。"; guestNote = ""
            } else if refreshed == nil {
                reservationError = "提交结果暂无法确认，请刷新本人预订记录后再试。"
            } else { reservationError = error.localizedDescription }
        }
        if store.session?.accessToken == session.accessToken {
            await loadSlots()
            _ = await loadReservations()
        }
    }

    @MainActor private func cancelReservation(_ reservationID: String) async {
        guard !cancelling, let session = store.session, Int64(reservationID).map({ $0 > 0 }) == true else { return }
        cancelling = true; reservationError = nil
        defer { cancelling = false; pendingCancelID = "" }
        var mutationConfirmed = false
        do {
            let result = try await MobileAPI(store: store).post("/api/JHCTIDining/CancelMyReservation?id=\(reservationID)", body: [:],
                authenticated: true, expectedPrincipal: nativeTourismPrincipal(session.accessToken))
            guard store.session?.accessToken == session.accessToken, Self.string(result) == reservationID else {
                throw MobileAPIError.unavailable("撤回回执无法确认，请刷新本人预订记录")
            }
            mutationConfirmed = true
            notice = "预订申请已撤回，名额已释放。"
        } catch is CancellationError {
            if !mutationConfirmed, store.session?.accessToken == session.accessToken {
                reservationError = "撤回请求已取消，结果可能已提交；请刷新本人预订记录核对。"
            }
            return
        } catch {
            if Task.isCancelled {
                if !mutationConfirmed, store.session?.accessToken == session.accessToken {
                    reservationError = "撤回请求已取消，结果可能已提交；请刷新本人预订记录核对。"
                }
                return
            }
            if store.session?.accessToken == session.accessToken { reservationError = error.localizedDescription }
        }
        guard store.session?.accessToken == session.accessToken else { return }
        if featureState == "open" { await loadSlots() }
        _ = await loadReservations()
    }

    private func reservationsErrorReset() { reservationError = nil }
    private static func string(_ value: Any?) -> String { (value as? String) ?? (value as? NSNumber)?.stringValue ?? "" }
    private static func int(_ value: Any?) -> Int? { (value as? Int) ?? (value as? NSNumber)?.intValue }
    private static func decimal(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue ?? (value as? Double) ?? (value as? String).flatMap(Double.init) }
}
