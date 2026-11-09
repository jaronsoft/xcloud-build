import SwiftUI

struct RestaurantReservationManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let storeID: String
    let storeName: String
    @State private var status = ""
    @State private var rows: [[String: Any]] = []
    @State private var total = 0
    @State private var page = 1
    @State private var loading = false
    @State private var error: String?
    @State private var revision = 0
    @State private var requestGeneration = 0
    @State private var pendingAction: (id: String, status: String, label: String)?
    @State private var actionBusy = false

    private let statuses = [("", "全部"), ("Pending", "待处理"), ("Confirmed", "已确认"),
                            ("Declined", "已拒绝"), ("Cancelled", "已取消")]

    var body: some View {
        List {
            Section {
                Text("当前门店：\(storeName)").font(.headline)
                Text("预订功能按平台开关开放；岗位和门店权限由服务端逐次复核。")
                    .font(.caption).foregroundStyle(Brand.muted)
            }
            Section("预订状态") {
                Picker("状态", selection: $status) {
                    ForEach(statuses, id: \.0) { Text($0.1).tag($0.0) }
                }.pickerStyle(.menu).onChange(of: status) { _, _ in rows = []; total = 0; page = 1; revision += 1 }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red); Button("重试") { revision += 1 } }
            }
            if loading && rows.isEmpty { Section { ProgressView("正在读取餐饮预订…") } }
            if !loading && rows.isEmpty && error == nil {
                Section { Text("暂无符合条件的预订").foregroundStyle(Brand.muted) }
            }
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                let id = reservationText(row["Id"])
                let state = reservationText(row["Status"])
                Section {
                    HStack { Text("\(reservationText(row["GuestName"], fallback: "顾客")) · \(reservationText(row["GuestCount"], fallback: "0")) 位").font(.headline); Spacer(); Text(statusName(state)).font(.caption).foregroundStyle(Brand.primary) }
                    Text("\(reservationText(row["ServiceDate"], fallback: "日期待确认")) · \(reservationText(row["StartTime"]))–\(reservationText(row["EndTime"]))")
                    Text("联系电话：\(maskedPhone(reservationText(row["GuestPhone"])))")
                    let guestNote = reservationText(row["GuestNote"])
                    if !guestNote.isEmpty { Text("顾客备注：\(guestNote)").font(.caption) }
                    let handleNote = reservationText(row["HandleNote"])
                    if !handleNote.isEmpty { Text("处理备注：\(handleNote)").font(.caption) }
                    if state == "Pending" {
                        HStack {
                            Button("拒绝", role: .destructive) { pendingAction = (id, "Declined", "拒绝") }
                            Button("确认预订") { pendingAction = (id, "Confirmed", "确认") }
                        }.disabled(actionBusy)
                    } else if state == "Confirmed" {
                        Button("取消预订", role: .destructive) { pendingAction = (id, "Cancelled", "取消") }.disabled(actionBusy)
                    }
                }
            }
            if total > 0 {
                Section {
                    HStack {
                        Button("上一页") { rows = []; page -= 1; revision += 1 }.disabled(page <= 1 || loading)
                        Spacer(); Text("第 \(page) 页 · 共 \(total) 条").font(.caption)
                        Spacer(); Button("下一页") { rows = []; page += 1; revision += 1 }
                            .disabled(page >= total / 20 + (total % 20 == 0 ? 0 : 1) || loading)
                    }
                }
            }
        }
        .navigationTitle("餐饮预订管理")
        .confirmationDialog("确认\(pendingAction?.label ?? "处理")此预订？", isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
                Button("确认", role: pendingAction?.status == "Declined" || pendingAction?.status == "Cancelled" ? .destructive : nil) {
                    Task { await handlePendingAction() }
                }
            }
        .task(id: "\(storeID)-\(status)-\(page)-\(revision)") { await loadReservations() }
        .onChange(of: store.session?.accessToken) { _, token in if token == nil { dismiss() } }
    }

    private func statusName(_ value: String) -> String {
        statuses.first(where: { $0.0 == value })?.1 ?? "状态待确认"
    }
    private func reservationText(_ value: Any?, fallback: String = "") -> String {
        guard let value, !(value is NSNull) else { return fallback }
        return String(describing: value)
    }
    private func maskedPhone(_ phone: String) -> String {
        guard phone.count >= 7 else { return "已保护" }
        return "\(phone.prefix(3))****\(phone.suffix(4))"
    }
    private func loadReservations() async {
        guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else { dismiss(); return }
        requestGeneration += 1
        let requestID = requestGeneration
        let requestedPage = page
        let requestedStatus = status
        loading = true; error = nil
        defer {
            if requestGeneration == requestID, store.session?.accessToken == token { loading = false }
        }
        do {
            let gate = try await MobileAPI(store: store).get("/api/JHCTIFeatureAccess/GetPublicStatus?featureId=F-FNB-002", authenticated: true,
                expectedPrincipal: principal)
            guard requestGeneration == requestID, store.session?.accessToken == token else { return }
            guard let gate = gate as? [String: Any],
                  let enabled = gate["IsEnabled"] as? Bool ?? gate["isEnabled"] as? Bool else {
                throw MobileAPIError.unavailable("无法确认餐饮预订功能状态")
            }
            if !enabled {
                rows = []; total = 0; error = "餐饮预订功能待平台开放。"; return
            }
            var path = "/api/JHCTIDining/GetReservations?storeId=\(storeID)&page=\(requestedPage)&pageSize=20"
            if !requestedStatus.isEmpty { path += "&status=\(requestedStatus)" }
            let response = try await MobileAPI(store: store).get(path, authenticated: true, expectedPrincipal: principal) as? [String: Any]
            guard requestGeneration == requestID, store.session?.accessToken == token, let response else { return }
            guard let parsed = nativeDiningReservationManagementPage(response, page: requestedPage, pageSize: 20, storeID: storeID) else {
                throw MobileAPIError.unavailable("餐饮预订列表数据异常，请刷新后重试")
            }
            guard requestGeneration == requestID, store.session?.accessToken == token else { return }
            rows = parsed.rows; total = parsed.total
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if requestGeneration == requestID, store.session?.accessToken == token {
                self.error = error.localizedDescription; rows = []; total = 0
            }
        }
    }
    private func handlePendingAction() async {
        guard let action = pendingAction, let token = store.session?.accessToken,
              let principal = nativeTourismPrincipal(token) else { return }
        actionBusy = true; error = nil
        defer { if store.session?.accessToken == token { actionBusy = false } }
        do {
            let path = "/api/JHCTIDining/HandleReservation?id=\(action.id)&status=\(action.status)"
            _ = try await MobileAPI(store: store).post(path, body: [:], authenticated: true, expectedPrincipal: principal)
            guard store.session?.accessToken == token else { return }
            pendingAction = nil; revision += 1
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if store.session?.accessToken == token { self.error = error.localizedDescription }
        }
    }
}
