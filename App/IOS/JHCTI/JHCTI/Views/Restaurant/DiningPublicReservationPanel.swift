import SwiftUI

struct DiningPublicReservationPanel: View {
    let featureState: String
    let errorMessage: String?
    let slots: [[String: Any]]
    let unsupportedSlotCount: Int
    let isLoading: Bool
    @Binding var selectedDate: Date
    let businessCalendar: Calendar
    let businessTimeZone: TimeZone
    let dateText: String
    let selectedSlotID: String
    let hasSelectedSlot: Bool
    let guestBounds: ClosedRange<Int>
    @Binding var guestCount: Int
    @Binding var guestName: String
    @Binding var guestPhone: String
    @Binding var guestNote: String
    let isAuthenticated: Bool
    @ObservedObject var creation: NativeDiningCreation
    @ObservedObject var withdrawal: NativeDiningWithdrawal
    let reservationsLoading: Bool
    let reservations: [[String: Any]]
    let onDateChanged: () -> Void
    let onRetry: () -> Void
    let onSelectSlot: ([String: Any]) -> Void
    let onSubmit: () -> Void
    let onCheckCreation: (NativeDiningCreationAttempt) -> Void
    let onLocateCreation: (NativeDiningCreationAttempt) -> Void
    let onRequestCancel: (String) -> Void
    let onCheckWithdrawal: (NativeDiningReservationAttempt, Bool) -> Void
    private var isSubmitting: Bool { creation.busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("到店预订").font(.headline).foregroundStyle(Brand.ink)
            Text("选择日期、时段和人数，提交后由门店确认；当前不收取预付款。")
                .font(.caption).foregroundStyle(Brand.muted)
            if isAuthenticated { pendingCreations }
            if featureState == "loading" {
                ProgressView("正在读取预订开放状态…")
            } else if featureState == "closed" {
                Text("餐饮预订暂未开放。开放后可在这里查看时段并提交申请。")
                    .font(.subheadline).foregroundStyle(Brand.muted)
            } else if featureState == "error" {
                Text(errorMessage ?? "餐饮预订暂时无法读取").font(.subheadline).foregroundStyle(.red)
                Button("重试读取", action: onRetry).buttonStyle(.bordered)
            } else {
                DatePicker("预订日期", selection: $selectedDate,
                           in: businessCalendar.startOfDay(for: Date())...,
                           displayedComponents: .date)
                    .environment(\.calendar, businessCalendar)
                    .environment(\.timeZone, businessTimeZone)
                    .disabled(isSubmitting || isLoading)
                    .onChange(of: dateText) { _, _ in onDateChanged() }
                if isLoading { ProgressView("正在查询可订时段…") }
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                if unsupportedSlotCount > 0 {
                    Text("有 \(unsupportedSlotCount) 个时段的桌型人数配置超出线上预约范围（1–30 人），暂不可在线预约。")
                        .font(.caption).foregroundStyle(.red)
                }
                if slots.isEmpty && !isLoading && errorMessage == nil && unsupportedSlotCount == 0 {
                    Text("该日期暂无可预订时段，请更换日期。")
                        .font(.subheadline).foregroundStyle(Brand.muted)
                }
                ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                    let slotID = Self.string(slot["Id"] ?? slot["id"])
                    let start = slot["StartTime"] as? String ?? slot["startTime"] as? String ?? ""
                    let end = slot["EndTime"] as? String ?? slot["endTime"] as? String ?? ""
                    let typeName = slot["TableTypeName"] as? String ?? slot["tableTypeName"] as? String ?? "通用桌位"
                    let capacity = Self.int(slot["Capacity"] ?? slot["capacity"]) ?? 0
                    let reserved = Self.int(slot["ReservedCount"] ?? slot["reservedCount"]) ?? 0
                    Button { onSelectSlot(slot) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(start)–\(end) · \(typeName)").font(.subheadline.weight(.semibold))
                                Text("余 \(max(0, capacity - reserved)) 个名额 · \(Self.int(slot["MinSeats"] ?? slot["minSeats"]) ?? 1)–\(Self.int(slot["MaxSeats"] ?? slot["maxSeats"]) ?? 30) 人")
                                    .font(.caption).foregroundStyle(Brand.muted)
                            }
                            Spacer()
                            if selectedSlotID == slotID {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.primary)
                            }
                        }
                        .padding(12)
                        .background(selectedSlotID == slotID ? Brand.primary.opacity(0.09) : Brand.background,
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain).disabled(isSubmitting)
                }
                if !isAuthenticated {
                    Text("请先在“我的”页面登录文旅账号，再提交预约并查看本人记录。")
                        .font(.caption).foregroundStyle(Brand.muted)
                } else {
                    TextField("联系人姓名", text: $guestName).textContentType(.name)
                        .textFieldStyle(.roundedBorder).disabled(isSubmitting)
                    TextField("联系电话", text: $guestPhone).textContentType(.telephoneNumber)
                        .keyboardType(.phonePad).textFieldStyle(.roundedBorder).disabled(isSubmitting)
                    Stepper("就餐人数：\(guestCount) 人", value: $guestCount, in: guestBounds)
                        .disabled(isSubmitting || !hasSelectedSlot)
                    TextField("备注（选填）", text: $guestNote, axis: .vertical).lineLimit(2...4)
                        .textFieldStyle(.roundedBorder).disabled(isSubmitting)
                    Button(isSubmitting ? "正在处理…" : creation.retry?.slotID == selectedSlotID ? "重试原申请" : "提交预订申请",
                           action: onSubmit)
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                        .disabled(isLoading || !hasSelectedSlot || creation.blocked(selectedSlotID))
                    Text("提交后为待确认申请；撤回待处理申请会释放名额。")
                        .font(.caption2).foregroundStyle(Brand.muted)
                }
            }
            if isAuthenticated { myReservations }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var pendingCreations: some View {
        if let message = creation.message { Text(message).font(.caption).foregroundStyle(Brand.ink) }
        if creation.storageError {
            Text("无法读取本机提交记录，已暂停提交。").font(.caption).foregroundStyle(.red)
            Button("重新读取提交记录") { creation.restore() }
        }
        if !creation.attempts.isEmpty {
            Text("待核对的预订提交").font(.subheadline.weight(.semibold))
            ForEach(creation.attempts) { attempt in
                Text("\(attempt.date) · 时段 \(attempt.slotID)").font(.caption)
                Button("核对原申请") { onCheckCreation(attempt) }.disabled(creation.busy)
            }
            if let retry = creation.retry {
                Text("暂未查到已落库的原申请。若原时段仍可预订，请沿用原申请资料重试。")
                    .font(.caption).foregroundStyle(Brand.muted)
                if featureState == "open" {
                    Button("定位原时段") { onLocateCreation(retry) }.disabled(isLoading || creation.busy)
                }
            }
        }
    }

    @ViewBuilder private var myReservations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("我的本店预订").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
            if let message = withdrawal.message { Text(message).font(.caption).foregroundStyle(Brand.ink) }
            if withdrawal.storageError {
                Text("无法读取本机撤回核对记录，已暂停撤回。").font(.caption).foregroundStyle(.red)
                Button("重新读取核对记录") { withdrawal.restore() }
            }
            if !withdrawal.attempts.isEmpty {
                Text("待核对的撤回").font(.subheadline.weight(.semibold))
                ForEach(withdrawal.attempts) { attempt in
                    let release = withdrawal.releasable == attempt
                    Text("预订编号 \(attempt.id)").font(.caption)
                    Button(release ? "重新核对并允许撤回" : "核对原预订") { onCheckWithdrawal(attempt, release) }
                        .disabled(withdrawal.busy || withdrawal.storageError)
                }
            }
            if let retry = withdrawal.retryID, !reservationsLoading,
               !reservations.contains(where: { Self.string($0["Id"] ?? $0["id"]) == retry }) {
                Button("重新撤回原预订", role: .destructive) { onRequestCancel(retry) }
                    .disabled(withdrawal.blocked(retry))
            }
            if reservationsLoading {
                ProgressView("正在加载本人预订…")
            } else if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            } else if reservations.isEmpty {
                Text("暂无本店预订记录").font(.caption).foregroundStyle(Brand.muted)
            } else {
                ForEach(Array(reservations.enumerated()), id: \.offset) { _, item in
                    let status = item["Status"] as? String ?? item["status"] as? String ?? ""
                    let reservationID = Self.string(item["Id"] ?? item["id"])
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(String((item["ServiceDate"] as? String ?? item["serviceDate"] as? String ?? "").prefix(10)))　\(item["StartTime"] as? String ?? item["startTime"] as? String ?? "")–\(item["EndTime"] as? String ?? item["endTime"] as? String ?? "")")
                            .font(.caption.weight(.semibold))
                        Text("\(item["GuestName"] as? String ?? item["guestName"] as? String ?? "") · \(Self.int(item["GuestCount"] ?? item["guestCount"]) ?? 0) 人 · \(Self.statusName(status))")
                            .font(.caption).foregroundStyle(Brand.muted)
                        if let note = item["HandleNote"] as? String ?? item["handleNote"] as? String, !note.isEmpty {
                            Text("门店备注：\(note)").font(.caption2).foregroundStyle(Brand.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(Brand.background, in: RoundedRectangle(cornerRadius: 9))
                    if status == "Pending" {
                        Button("撤回待处理申请", role: .destructive) {
                            onRequestCancel(reservationID)
                        }
                        .disabled(withdrawal.blocked(reservationID))
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private static func string(_ value: Any?) -> String {
        (value as? String) ?? (value as? NSNumber)?.stringValue ?? ""
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? Int) ?? (value as? NSNumber)?.intValue
    }

    static func statusName(_ value: String) -> String {
        ["Pending": "待商户确认", "Confirmed": "已确认", "Declined": "已拒绝", "Cancelled": "已撤回或取消"][value] ?? "状态更新中"
    }
}

@MainActor final class NativeDiningWithdrawal: ObservableObject {
    @Published private(set) var attempts: [NativeDiningReservationAttempt] = []
    @Published private(set) var storageError = false
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var releasable: NativeDiningReservationAttempt?
    @Published private(set) var retryID: String?
    private var principal: String?
    private var storeID = ""
    private var task: Task<Void, Never>?
    private var generation = 0

    func configure(principal: String?, storeID: String) {
        stop()
        self.principal = principal
        self.storeID = storeID
        restore()
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        busy = false
        message = nil
        releasable = nil
        retryID = nil
    }

    func restore() {
        attempts = []
        storageError = false
        guard let principal else { return }
        do { attempts = try recovery(principal).read().filter { $0.storeID == storeID } }
        catch { storageError = true }
    }

    func blocked(_ id: String) -> Bool {
        principal == nil || busy || storageError || attempts.contains { $0.id == id }
    }

    func withdraw(_ id: String, store: SessionStore, onResolved: @escaping @MainActor () -> Void) {
        guard !blocked(id), let principal, currentPrincipal(store) == principal else { return }
        let attempt = NativeDiningReservationAttempt(id: id, storeID: storeID, previous: "Pending", target: "Cancelled")
        guard attempt.isValidForWithdrawal else { return }
        do {
            try recovery(principal).add(attempt)
            attempts.append(attempt)
        } catch {
            restore()
            message = "无法保存本次撤回核对记录，未发送请求。"
            return
        }
        run(store: store, principal: principal, failure: "撤回结果尚未确认，请核对原预订。") { generation in
            let path = "/api/JHCTIDining/CancelMyReservation?id=\(id)&expectedStoreId=\(attempt.storeID)"
            let response = try await MobileAPI(store: store).post(path, body: [:], authenticated: true,
                expectedPrincipal: principal, canRefresh: false, requireExplicitResponse: true)
            guard self.isCurrent(generation, store, principal) else { return }
            guard response as? String == id else { throw MobileAPIError.unavailable("撤回回执与原预订不符") }
            try self.finish(attempt, principal, message: "预订申请已撤回。", retry: false, onResolved: onResolved)
        }
    }

    func check(_ attempt: NativeDiningReservationAttempt, release: Bool, store: SessionStore, onResolved: @escaping @MainActor () -> Void) {
        guard let principal, currentPrincipal(store) == principal, !busy, !storageError,
              attempts.contains(attempt), !release || releasable == attempt else { return }
        run(store: store, principal: principal, failure: "暂时无法核对原预订，已保留待核对记录。") { generation in
            let path = "/api/JHCTIDining/GetMyReservationState?storeId=\(attempt.storeID)&id=\(attempt.id)"
            let response = try await MobileAPI(store: store).get(path, authenticated: true,
                expectedPrincipal: principal, requireExplicitResponse: true)
            guard self.isCurrent(generation, store, principal) else { return }
            guard let status = attempt.readStatus(response) else { throw MobileAPIError.unavailable("预订状态回执异常") }
            let message = "预订 \(attempt.id) 当前为\(DiningPublicReservationPanel.statusName(status))。"
            if status == "Pending" && !release {
                self.releasable = attempt
                self.message = message
            } else {
                try self.finish(attempt, principal, message: message, retry: status == "Pending", onResolved: onResolved)
            }
        }
    }

    private func run(store: SessionStore, principal: String, failure: String, operation: @escaping @MainActor (Int) async throws -> Void) {
        stop()
        busy = true
        let requestedGeneration = generation
        task = Task { @MainActor in
            defer { if self.generation == requestedGeneration { self.busy = false; self.task = nil } }
            guard self.isCurrent(requestedGeneration, store, principal) else { return }
            do { try await operation(requestedGeneration) }
            catch {
                if self.isCurrent(requestedGeneration, store, principal) { self.restore(); self.message = failure }
            }
        }
    }

    private func recovery(_ principal: String) throws -> NativeDiningReservationRecovery {
        try NativeDiningReservationRecovery(principal: principal, ownerWithdrawal: true)
    }

    private func currentPrincipal(_ store: SessionStore) -> String? {
        store.session.flatMap { nativeTourismPrincipal($0.accessToken) }
    }

    private func isCurrent(_ requestedGeneration: Int, _ store: SessionStore, _ principal: String) -> Bool {
        !Task.isCancelled && generation == requestedGeneration && currentPrincipal(store) == principal
    }

    private func finish(_ attempt: NativeDiningReservationAttempt, _ principal: String, message: String,
                        retry: Bool, onResolved: @MainActor () -> Void) throws {
        try recovery(principal).remove(attempt)
        restore()
        self.message = message
        retryID = retry ? attempt.id : nil
        onResolved()
    }
}
