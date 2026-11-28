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
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SessionStore
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
    @StateObject private var creation = NativeDiningCreation()
    @State private var preferredCreationSlotID: String?
    @StateObject private var withdrawal = NativeDiningWithdrawal()
    @State private var error: String?
    @State private var reservationError: String?
    @State var queueState = "loading"
    @State var queueSession: [String: Any]?
    @State var queueEntries: [[String: Any]] = []
    @State var queueRequestSequence = 0
    @State var queueEntriesRequestSequence = 0
    @State var queueError: String?
    @State var queueName = ""
    @State var queuePhone = ""
    @State var queueCount = 2
    @State var queueBusy = false
    @State var queueCancelID = ""
    @State private var showQueueCancelConfirmation = false
    @State private var pendingCancelID = ""
    @State private var showCancelConfirmation = false
    @State private var requestSequence = 0
    @State private var slotRequestSequence = 0
    @State private var packageRequestSequence = 0
    @State private var reservationSequence = 0
    private let businessTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private var reservationPrincipal: String? {
        store.session.flatMap { nativeTourismPrincipal($0.accessToken) }
    }

    private var businessCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = businessTimeZone
        return calendar
    }

    private var businessDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = businessCalendar
        formatter.timeZone = businessTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private var dateText: String { businessDateFormatter.string(from: selectedDate) }

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

    private func isValidDiningContactPhone(_ value: String) -> Bool {
        let ignoredCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-"))
        let normalized = value.unicodeScalars.filter { !ignoredCharacters.contains($0) }.map(String.init).joined()
        let digits = normalized.hasPrefix("+") ? String(normalized.dropFirst()) : normalized
        return (6...24).contains(digits.count) && digits.unicodeScalars.allSatisfy { (48...57).contains(Int($0.value)) }
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
                        creation: creation,
                        withdrawal: withdrawal,
                        reservationsLoading: reservationsLoading,
                        reservations: reservations,
                        onDateChanged: {
                            let preferred = preferredCreationSlotID
                            preferredCreationSlotID = nil
                            loading = true
                            Task {
                                await loadSlots(preferredSlotID: preferred)
                                loading = false
                            }
                        },
                        onRetry: { Task { await load() } },
                        onSelectSlot: { slot in
                            selectedSlotID = Self.string(slot["Id"] ?? slot["id"])
                            guestCount = min(guestBounds.upperBound, max(guestBounds.lowerBound, guestCount))
                        },
                        onSubmit: submitReservation,
                        onCheckCreation: { attempt in
                            guard scenePhase == .active else { return }
                            creation.check(attempt, store: store, onResolved: refreshAfterCreation)
                        },
                        onLocateCreation: locateCreation,
                        onRequestCancel: { reservationID in
                            guard canWithdraw(reservationID) else { return }
                            pendingCancelID = reservationID
                            showCancelConfirmation = true
                        },
                        onCheckWithdrawal: { attempt, release in
                            guard scenePhase == .active else { return }
                            withdrawal.check(attempt, release: release, store: store, onResolved: refreshAfterWithdrawal)
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
        .onAppear { configureReservationRecovery() }
        .onDisappear {
            withdrawal.configure(principal: nil, storeID: id)
            creation.configure(principal: nil, storeID: id)
            showCancelConfirmation = false
        }
        .onChange(of: scenePhase) { _, _ in configureReservationRecovery() }
        .onChange(of: reservationPrincipal) { _, _ in configureReservationRecovery() }
        .onChange(of: id) { _, _ in configureReservationRecovery() }
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
                Button("确认撤回", role: .destructive) {
                    let reservationID = pendingCancelID
                    pendingCancelID = ""
                    guard canWithdraw(reservationID) else { return }
                    withdrawal.withdraw(reservationID, store: store, onResolved: refreshAfterWithdrawal)
                }
                Button("暂不撤回", role: .cancel) { pendingCancelID = "" }
            }
        } message: {
            Text(showQueueCancelConfirmation ? "确认取消当前等待号码吗？" : "撤回待处理申请后，门店会收到释放的预订名额。")
        }
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
            let diningAccess = await MobileAPI(store: store).featureAccessState("MODULE-DINING", forceRefresh: true)
            try Task.checkCancellation()
            switch diningAccess {
            case .open:
                break
            case .closed, .pendingConfirmation:
                packageLoading = false; slots = []; reservations = []; queueEntries = []
                throw MobileAPIError.unavailable("特色美食模块暂未开放")
            case .unavailable:
                throw MobileAPIError.unavailable("特色美食模块开放状态暂时无法确认，请重试")
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
            let reservationAccess = await MobileAPI(store: store).featureAccessState("F-FNB-002", forceRefresh: true)
            try Task.checkCancellation()
            guard sequence == requestSequence else { return }
            switch reservationAccess {
            case .open:
                featureState = "open"
                await loadSlots(sequence: sequence)
                _ = await loadReservations()
            case .closed, .pendingConfirmation:
                featureState = "closed"; slots = []; unsupportedSlotCount = 0
                _ = await loadReservations()
            case .unavailable:
                throw MobileAPIError.unavailable("餐饮预订开放状态暂时无法确认，请重试")
            }
        } catch is CancellationError {
            return
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

    @MainActor private func loadSlots(sequence: Int? = nil, preferredSlotID: String? = nil) async {
        let requestID = sequence ?? requestSequence
        slotRequestSequence += 1
        let slotRequest = slotRequestSequence
        let requestedDate = dateText
        reservationError = nil; slots = []; selectedSlotID = ""; unsupportedSlotCount = 0
        do {
            let path = "/api/JHCTIDining/GetAvailableReservationSlots?storeId=\(id)&date=\(requestedDate)"
            let value = try await MobileAPI(store: store).get(path)
            guard requestID == requestSequence, slotRequest == slotRequestSequence, dateText == requestedDate else { return }
            guard let rows = value as? [[String: Any]], rows.allSatisfy({
                Int64(Self.string($0["Id"] ?? $0["id"])) .map({ $0 > 0 }) == true
                    && (Self.int($0["Capacity"] ?? $0["capacity"]) ?? -1) >= 0
                    && (Self.int($0["ReservedCount"] ?? $0["reservedCount"]) ?? -1) >= 0
            }) else { throw MobileAPIError.unavailable("可预订时段数据格式异常") }
            let usableRows = rows.filter(isBookableDiningSlot)
            unsupportedSlotCount = rows.count - usableRows.count
            slots = usableRows
            let first = preferredSlotID.flatMap { preferred in
                usableRows.first { Self.string($0["Id"] ?? $0["id"]) == preferred }
            } ?? (preferredSlotID == nil ? usableRows.first : nil)
            if let first {
                selectedSlotID = Self.string(first["Id"] ?? first["id"])
                guestCount = min(guestBounds.upperBound, max(guestBounds.lowerBound, guestCount))
            } else if preferredSlotID != nil { reservationError = "原时段当前不在可预订列表。" }
        } catch {
            if requestID == requestSequence && slotRequest == slotRequestSequence && dateText == requestedDate {
                reservationError = error.localizedDescription
            }
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

    @MainActor private func submitReservation() {
        guard scenePhase == .active, !creation.blocked(selectedSlotID), selectedSlot != nil,
              !guestName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              guestName.count <= 80,
              isValidDiningContactPhone(guestPhone), guestNote.count <= 500,
              guestBounds.contains(guestCount) else {
            reservationError = "请检查联系人、有效联系电话、人数和所选时段"; return
        }
        reservationError = nil
        creation.submit(slotID: selectedSlotID, date: dateText, form: [
            "GuestName": guestName.trimmingCharacters(in: .whitespacesAndNewlines),
            "GuestPhone": guestPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            "GuestCount": guestCount, "GuestNote": guestNote.trimmingCharacters(in: .whitespacesAndNewlines)
        ], store: store, onAccess: { access in
            switch access {
            case .open: featureState = "open"
            case .closed, .pendingConfirmation: featureState = "closed"; slots = []
            case .unavailable: featureState = "error"; slots = []
            }
        }, onResolved: refreshAfterCreation)
    }

    @MainActor private func locateCreation(_ attempt: NativeDiningCreationAttempt) {
        guard featureState == "open", creation.retry == attempt,
              let targetDate = businessDateFormatter.date(from: attempt.date),
              targetDate >= businessCalendar.startOfDay(for: Date()) else {
            reservationError = "原时段当前不在可预订列表。"
            return
        }
        if dateText != attempt.date {
            preferredCreationSlotID = attempt.slotID
            selectedDate = targetDate
        } else {
            loading = true
            Task { await loadSlots(preferredSlotID: attempt.slotID); loading = false }
        }
    }

    @MainActor private func refreshAfterCreation() {
        guestNote = ""
        refreshAfterWithdrawal()
    }

    @MainActor private func configureReservationRecovery() {
        showCancelConfirmation = false
        pendingCancelID = ""
        withdrawal.configure(principal: scenePhase == .active ? reservationPrincipal : nil, storeID: id)
        creation.configure(principal: scenePhase == .active ? reservationPrincipal : nil, storeID: id)
    }

    @MainActor private func canWithdraw(_ reservationID: String) -> Bool {
        guard scenePhase == .active, NativeDiningReservationAttempt.validID(reservationID),
              !withdrawal.blocked(reservationID) else { return false }
        if let row = reservations.first(where: { ($0["Id"] ?? $0["id"]) as? String == reservationID }) {
            return (row["Status"] ?? row["status"]) as? String == "Pending"
        }
        return withdrawal.retryID == reservationID
    }

    @MainActor private func refreshAfterWithdrawal() {
        Task {
            _ = await loadReservations()
            if featureState == "open" { await loadSlots() }
        }
    }

    private func reservationsErrorReset() { reservationError = nil }
    static func string(_ value: Any?) -> String { (value as? String) ?? (value as? NSNumber)?.stringValue ?? "" }
    static func int(_ value: Any?) -> Int? { (value as? Int) ?? (value as? NSNumber)?.intValue }
    private static func decimal(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue ?? (value as? Double) ?? (value as? String).flatMap(Double.init) }
}
