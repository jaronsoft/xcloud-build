import SwiftUI
import UIKit

struct JourneyView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SessionStore
    let onMap: () -> Void
    let onProfile: () -> Void
    @State private var reservations: [[String: Any]] = []
    @State private var reservationPage = 1
    @State private var reservationTotal = 0
    @State private var reservationLoadingMore = false
    @State private var reservationRequestSequence = 0
    @State private var routes: [[String: Any]] = []
    @State private var error: String?
    @State private var routeError: String?
    @State private var loading = false
    @State private var routeLoading = false
    @State private var revision = 0
    @State private var routeRevision = 0
    @State private var selectedReservation: [String: Any]?
    @State private var reservationDetailOpen = false
    @State private var reservationQrImage: UIImage?
    @State private var reservationQrLoading = false
    @State private var reservationQrSequence = 0
    @State private var reservationActionError: String?
    @State private var reservationCancelConfirm = false
    @State private var reservationDeleteConfirm = false
    @State private var reservationActionBusy = false
    @State private var reservationActionSequence = 0
    @State private var reservationClock = Date()
    @State private var favoritesOpen = false
    @State private var activityRegistrationsOpen = false
    @State private var loginPrompt = false
    @State private var pageVisible = true
    @State private var reservationOwner = ""
    @State private var reservationHasMore = false
    @State private var reservationDetailSequence = 0
    @State private var reservationNeedsRefresh = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("把江都慢慢逛一遍")
                            .font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif)).foregroundStyle(Brand.ink)
                        Text("从已发布的旅游线路、景点地图和个人收藏开始规划。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    }
                    .padding(.top, 12)

                    HStack(spacing: 8) {
                        journeyShortcut("打开文旅地图", note: "查看江都景点与设施", icon: "Tab3", action: onMap)
                        journeyShortcut("我的景点收藏", note: "查看已收藏的公开景点", symbol: "heart") {
                            if store.session != nil { favoritesOpen = true } else { loginPrompt = true }
                        }
                    }
                    journeyShortcut("我的活动报名", note: "查看报名记录、签到凭证与取消状态", icon: "Tab7") {
                        if store.session != nil { activityRegistrationsOpen = true } else { loginPrompt = true }
                    }

                    if store.session != nil { reservationSection }
                    routeSection

                    VStack(alignment: .leading, spacing: 5) {
                        Text("统一行程规划暂未开放").font(.system(size: NativeTypography.size(14), weight: .semibold))
                        Text("线路、地图和活动报名可分别查看；登录后可查看收藏，统一行程保存功能待开放。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.93, green: 0.96, blue: 0.95), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Brand.background)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: revision) { await loadReservations(reset: true) }
            .task(id: routeRevision) { await loadRoutes() }
            .task {
                var reservationStatusPollSeconds = 0
                while !Task.isCancelled {
                    self.refreshReservationClock()
                    if reservationQrImage != nil,
                       let item = selectedReservation,
                       item["Status"] as? String == "Reserved",
                       let id = item["Id"] as? String,
                       let token = store.session?.accessToken {
                        reservationStatusPollSeconds += 1
                        if reservationStatusPollSeconds >= 5 {
                            reservationStatusPollSeconds = 0
                            await self.refreshReservationQrStatus(id: id, token: token)
                        }
                    } else {
                        reservationStatusPollSeconds = 0
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    self.refreshReservationClock()
                    revision += 1
                default:
                    self.clearPrivateReservations()
                }
            }
            .onDisappear {
                pageVisible = false; clearPrivateReservations()
            }
            .onAppear { pageVisible = true; revision += 1 }
            .onChange(of: favoritesOpen) { _, open in if open { clearPrivateReservations() } else { revision += 1 } }
            .onChange(of: activityRegistrationsOpen) { _, open in if open { clearPrivateReservations() } else { revision += 1 } }
            .sheet(isPresented: $favoritesOpen) { NativeFavoritesView(store: store) }
            .sheet(isPresented: $activityRegistrationsOpen) { ActivityRegistrationsView(store: store) }
            .alert("请先登录文旅账号", isPresented: $loginPrompt) {
                Button("前往我的") { onProfile() }
                Button("取消", role: .cancel) {}
            } message: { Text("登录后可查看景点收藏和活动报名记录。") }
            .sheet(isPresented: $reservationDetailOpen, onDismiss: {
                closeReservationDetail()
            }) { reservationDetailSheet }
            .confirmationDialog("确认取消景点预约？", isPresented: $reservationCancelConfirm,
                                titleVisibility: .visible) {
                Button("确认取消", role: .destructive) {
                    let id = selectedReservation?["Id"] as? String ?? ""; let detail = reservationDetailSequence
                    Task { await cancelSelectedReservation(id: id, detail: detail) }
                }
                Button("返回", role: .cancel) {}
            } message: {
                Text("取消后将释放预约名额，是否继续？")
            }
            .onChange(of: store.session?.accessToken) { _, _ in
                reservationQrSequence += 1; reservationQrLoading = false
                reservationDetailOpen = false; reservationQrImage = nil
                selectedReservation = nil; reservationActionError = nil; reservationCancelConfirm = false
                reservationDeleteConfirm = false
                reservationActionSequence += 1; reservationActionBusy = false
                reservationOwner = ""; reservationHasMore = false; reservationNeedsRefresh = false; reservationDetailSequence += 1
                reservations = []; reservationPage = 1; reservationTotal = 0
                reservationRequestSequence += 1; error = nil; loading = false; revision += 1
            }
        }
    }

    private func closeReservationDetail(refresh: Bool = true) {
        let wasOpen = selectedReservation != nil
        reservationDetailSequence += 1; reservationDetailOpen = false; selectedReservation = nil
        reservationQrSequence += 1; reservationQrImage = nil; reservationQrLoading = false; reservationActionError = nil
        reservationCancelConfirm = false; reservationDeleteConfirm = false
        if refresh && wasOpen && pageVisible && scenePhase == .active { revision += 1 }
    }

    private func clearPrivateReservations() {
        reservationRequestSequence += 1; closeReservationDetail(refresh: false)
        reservations = []; reservationOwner = ""; reservationHasMore = false
        reservationPage = 1; reservationTotal = 0; loading = false; reservationLoadingMore = false; error = nil
    }

    private func journeyShortcut(_ title: String, note: String, icon: String? = nil,
                                 symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Brand.background)
                    if let icon {
                        Image(icon).resizable().scaledToFit().padding(6)
                    } else if let symbol {
                        Image(systemName: symbol).font(.system(size: NativeTypography.size(20), weight: .medium)).foregroundStyle(Brand.primary)
                    }
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink).lineLimit(1)
                    Text(note).font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("›").font(.system(size: NativeTypography.size(18))).foregroundStyle(Brand.muted)
            }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Brand.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var reservationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("我的景点预约\(reservations.isEmpty ? "" : "（\(reservations.count)）")")
                    .font(.system(size: NativeTypography.size(18), weight: .bold, design: .serif)).foregroundStyle(Brand.ink)
                Spacer()
                Button("刷新") { revision += 1 }.font(.system(size: NativeTypography.size(14)))
            }
            StatusView(loading: loading, error: error) { revision += 1 }
            ForEach(reservations.indices, id: \.self) { index in
                let item = reservations[index]
                let statusLabel = nativeTourismReservationStatus(item["Status"] as? String ?? "", expired: isExpiredReservation(item, now: reservationClock))
                Button {
                    guard !loading, !reservationLoadingMore, reservationOwner == store.session?.accessToken else { return }
                    reservationDetailSequence += 1
                    selectedReservation = item
                    reservationQrImage = nil; reservationActionError = nil
                    reservationDetailOpen = true
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item["ResourceName"] as? String ?? "景点预约")
                            .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
                        Text("\(item["ReservationDate"] as? String ?? "时间待确认") · \(item["SessionName"] as? String ?? "当日预约")")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        Text("\(statusLabel) · 查看凭证与操作 ›")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
            if reservationHasMore {
                Button(reservationLoadingMore ? "正在加载…" : "加载更多预约") {
                    Task { await loadReservations(reset: false) }
                }
                .font(.system(size: NativeTypography.size(14), weight: .semibold))
                .disabled(loading || reservationLoadingMore)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("江都旅游线路")
                    .font(.system(size: NativeTypography.size(18), weight: .bold, design: .serif)).foregroundStyle(Brand.ink)
                Spacer()
                NavigationLink("全部线路 ›") {
                    CatalogView(store: store, module: CatalogModule(id: "routes", title: "旅游线路",
                        path: "/api/JHCTITravelRoute/GetPublicPage", featureID: "MODULE-TRAVEL-ROUTE"))
                }
                .font(.system(size: NativeTypography.size(14)))
            }
            StatusView(loading: routeLoading, error: routeError) { routeRevision += 1 }
            if !routeLoading && routeError == nil && routes.isEmpty {
                VStack(spacing: 8) {
                    Text("暂无可浏览线路").font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
                    Text("线路发布后会显示在这里，也可以先从地图发现景点。")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
                    Button("重新查询线路") { routeRevision += 1 }
                    Button("去文旅地图看看　›", action: onMap)
                }
                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                .frame(maxWidth: .infinity).padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.border, lineWidth: 1))
            }
            ForEach(routes.indices, id: \.self) { index in
                let route = routes[index]
                NavigationLink {
                    TravelRouteDetailView(store: store, id: route["Id"] as? String ?? "")
                } label: {
                HStack(spacing: 10) {
                    Text((route["DurationDays"] as? Int ?? 0) > 0 ? "\(route["DurationDays"] as? Int ?? 0)日" : "线路")
                        .font(.system(size: NativeTypography.size(14), weight: .bold)).foregroundStyle(Brand.primary)
                        .frame(width: 40, height: 40).background(Brand.background, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route["Name"] as? String ?? "江都旅游线路")
                            .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
                        Text("\(route["Destination"] as? String ?? "扬州江都") · \(route["Summary"] as? String ?? route["MeetingPoint"] as? String ?? "查看线路安排")")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted).lineLimit(1)
                    }
                    Spacer()
                    Text("›").foregroundStyle(Brand.muted)
                }
                .padding(11).background(.white, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private var reservationDetailSheet: some View {
        NavigationStack {
            Form {
                if let item = selectedReservation {
                    Section("预约信息") {
                        Text(item["ResourceName"] as? String ?? "景点预约").font(.headline)
                        Text("\(item["ReservationDate"] as? String ?? "时间待确认") · \(item["SessionName"] as? String ?? "当日预约")")
                        Text("状态：\(nativeTourismReservationStatus(item["Status"] as? String ?? "", expired: isExpiredReservation(item, now: reservationClock)))")
                        if let masked = item["IdentityNumberMasked"] as? String, !masked.isEmpty {
                            Text("实名信息：\(masked)")
                        }
                    }
                    if isExpiredReservation(item, now: reservationClock) {
                        Section {
                            Button("删除过期预约", role: .destructive) { reservationDeleteConfirm = true }
                                .disabled(reservationActionBusy || reservationNeedsRefresh)
                            Text("场次已结束，入园凭证已失效。删除只会从本人预约列表中移除记录。")
                                .font(.caption).foregroundStyle(Brand.muted)
                        }
                    } else if item["Status"] as? String == "CheckedIn" {
                        Section("入园核验") {
                            Text("预约核验成功，已完成入园。")
                                .foregroundStyle(Brand.primary)
                        }
                    } else if item["Status"] as? String == "Reserved" {
                        Section("入园凭证") {
                            if reservationQrLoading { ProgressView("正在获取有效凭证…") }
                            else if let reservationQrImage {
                                Image(uiImage: reservationQrImage).resizable().interpolation(.none)
                                    .scaledToFit().frame(maxWidth: 240, maxHeight: 240)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Button("查看入园二维码") { Task { await loadReservationQr() } }.disabled(reservationActionBusy || reservationNeedsRefresh)
                            }
                            Text("二维码仅在预约有效时由服务端生成；请勿转发给他人。")
                                .font(.caption).foregroundStyle(Brand.muted)
                        }
                        if item["CanCancel"] as? Bool == true {
                            Section {
                                Button("取消预约", role: .destructive) { reservationCancelConfirm = true }
                                    .disabled(reservationActionBusy || reservationNeedsRefresh)
                            }
                        }
                    }
                    if let reservationActionError {
                        Section { Text(reservationActionError).foregroundStyle(.red) }
                    }
                    if reservationActionBusy { Section { ProgressView("正在处理预约…") } }
                    if reservationNeedsRefresh {
                        Section { Button("核对最新预约状态") { closeReservationDetail() }.disabled(reservationActionBusy) }
                    }
                }
            }
            .navigationTitle("我的景点预约")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { closeReservationDetail() } } }
            .overlay {
                if reservationDeleteConfirm, let item = selectedReservation {
                    ZStack {
                        Color.black.opacity(0.48).ignoresSafeArea()
                            .onTapGesture { if !reservationActionBusy { reservationDeleteConfirm = false } }
                        VStack(spacing: 0) {
                            Text("删除过期预约")
                                .font(.system(size: NativeTypography.size(17), weight: .semibold))
                                .foregroundStyle(Color(red: 0.15, green: 0.23, blue: 0.21))
                                .padding(.top, 22)
                            Text("该场次已结束，删除后将从预约列表中移除。")
                                .font(.system(size: NativeTypography.size(14)))
                                .foregroundStyle(Color(red: 0.54, green: 0.56, blue: 0.55))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 22).padding(.vertical, 16)
                            Rectangle().fill(Color(red: 0.91, green: 0.92, blue: 0.92)).frame(height: 1)
                            HStack(spacing: 0) {
                                Button("保留") { reservationDeleteConfirm = false }
                                    .font(.system(size: NativeTypography.size(15), weight: .medium))
                                    .foregroundStyle(Color(red: 0.15, green: 0.23, blue: 0.21))
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .disabled(reservationActionBusy)
                                Rectangle().fill(Color(red: 0.91, green: 0.92, blue: 0.92)).frame(width: 1, height: 54)
                                Button("删除", role: .destructive) {
                                    let id = item["Id"] as? String ?? ""
                                    let detail = reservationDetailSequence
                                    Task { await deleteExpiredReservation(id: id, detail: detail) }
                                }
                                .font(.system(size: NativeTypography.size(15), weight: .semibold))
                                .foregroundStyle(Color(red: 0.70, green: 0.34, blue: 0.29))
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .disabled(reservationActionBusy || reservationNeedsRefresh)
                            }
                        }
                        .frame(maxWidth: 340)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 24)
                        .accessibilityElement(children: .contain)
                    }
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
        }
    }

    private func refreshReservationClock() {
        reservationClock = Date()
        if let selectedReservation, isExpiredReservation(selectedReservation, now: reservationClock) {
            reservationQrSequence += 1; reservationQrLoading = false
            reservationQrImage = nil; reservationCancelConfirm = false
        }
    }

    private func loadReservationQr() async {
        guard !reservationQrLoading, !reservationActionBusy, !reservationNeedsRefresh else { return }
        guard let item = selectedReservation, let token = store.session?.accessToken,
              let id = item["Id"] as? String, !id.isEmpty else {
            reservationActionError = "请重新登录后查看预约凭证。"; return
        }
        guard item["Status"] as? String == "Reserved", !isExpiredReservation(item) else {
            refreshReservationClock(); return
        }
        reservationQrSequence += 1; let operation = reservationQrSequence
        reservationQrLoading = true; reservationActionError = nil
        defer { if operation == reservationQrSequence { reservationQrLoading = false } }
        do {
            guard let dataUri = try await MobileAPI(store: store).get(
                "/api/JHCTITourismReservation/GetMyQr?id=\(id)", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)) as? String,
                  dataUri.hasPrefix("data:image/png;base64,"),
                  let imageData = Data(base64Encoded: String(dataUri.dropFirst("data:image/png;base64,".count))),
                  let image = UIImage(data: imageData), store.session?.accessToken == token else {
                throw MobileAPIError.unavailable("预约凭证暂不可用，请刷新记录后重试")
            }
            guard operation == reservationQrSequence, reservationDetailOpen,
                  selectedReservation?["Id"] as? String == id, store.session?.accessToken == token else { return }
            // 接口及图片解码可能跨过结束时间，展示前重新核对，不能等待下一次页面时钟刷新。
            guard !isExpiredReservation(item) else {
                refreshReservationClock()
                reservationActionError = "该预约已过期，入园二维码不再显示。"; return
            }
            reservationQrImage = image
        } catch {
            if operation == reservationQrSequence, reservationDetailOpen,
               selectedReservation?["Id"] as? String == id, store.session?.accessToken == token {
                reservationActionError = error.localizedDescription
            }
        }
    }

    private func cancelSelectedReservation(id: String, detail: Int) async {
        await performReservationAction(deleting: false, expectedID: id, expectedDetail: detail)
    }

    private func isExpiredReservation(_ item: [String: Any], now: Date = Date()) -> Bool {
        guard item["Status"] as? String == "Reserved",
              let end = paymentDeadline(item["EndTime"]) else { return false }
        return end <= now
    }

    private func deleteExpiredReservation(id: String, detail: Int) async {
        await performReservationAction(deleting: true, expectedID: id, expectedDetail: detail)
    }

    private func performReservationAction(deleting: Bool, expectedID: String, expectedDetail: Int) async {
        guard !Task.isCancelled, !reservationActionBusy, !reservationNeedsRefresh, pageVisible, scenePhase == .active,
              !favoritesOpen, !activityRegistrationsOpen,
              reservationDetailSequence == expectedDetail,
              reservationDetailOpen, let item = selectedReservation,
              let token = store.session?.accessToken, !token.isEmpty, reservationOwner == token,
              let id = item["Id"] as? String, id == expectedID, let number = Int64(id), number > 0, String(number) == id,
              let current = reservations.first(where: { $0["Id"] as? String == id }),
              deleting ? isExpiredReservation(current) : (current["Status"] as? String == "Reserved"
                && current["CanCancel"] as? Bool == true && !isExpiredReservation(current)) else {
            return
        }
        reservationActionSequence += 1; let sequence = reservationActionSequence
        let detailSequence = reservationDetailSequence
        reservationRequestSequence += 1; loading = false; reservationLoadingMore = false
        reservationQrSequence += 1; reservationQrImage = nil; reservationQrLoading = false
        reservationCancelConfirm = false; reservationDeleteConfirm = false
        reservationNeedsRefresh = true
        reservationActionBusy = true; reservationActionError = nil
        defer { if reservationActionSequence == sequence { reservationActionBusy = false } }
        func isCurrent() -> Bool {
            !Task.isCancelled && reservationActionSequence == sequence && reservationDetailSequence == detailSequence
                && store.session?.accessToken == token && selectedReservation?["Id"] as? String == id
                && reservationDetailOpen && pageVisible && scenePhase == .active && !favoritesOpen && !activityRegistrationsOpen
        }
        do {
            let action = deleting ? "DeleteExpiredMine" : "CancelMine"
            let result = try await MobileAPI(store: store).post(
                "/api/JHCTITourismReservation/\(action)?id=\(id)", body: [:], authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)) as? String
            guard isCurrent() else { return }
            guard result == id else {
                throw MobileAPIError.unavailable("操作结果暂未确认")
            }
            reservations.removeAll { $0["Id"] as? String == id }; reservationHasMore = false
            reservationNeedsRefresh = false; closeReservationDetail()
        } catch {
            if isCurrent() {
                reservationActionError = "操作结果暂未确认，请核对最新预约状态后再继续。"
            }
        }
    }

    private func loadRoutes() async {
        routeLoading = true; routeError = nil
        do {
            guard await MobileAPI(store: store).featureEnabled("MODULE-TRAVEL-ROUTE") else {
                routes = []
                throw MobileAPIError.unavailable("旅游线路暂未开放")
            }
            let response = try await MobileAPI(store: store).getPublicCached(
                "/api/JHCTITravelRoute/GetPublicPage?page=1&pageSize=3&guests=1",
                forceRefresh: routeRevision > 0) as? [String: Any]
            routes = response?["data"] as? [[String: Any]] ?? response?["Data"] as? [[String: Any]] ?? []
        } catch { routeError = error.localizedDescription }
        routeLoading = false
    }

    private func refreshReservationQrStatus(id: String, token: String) async {
        guard let principal = nativeTourismPrincipal(token) else { return }
        guard reservationDetailOpen, reservationQrImage != nil,
              selectedReservation?["Id"] as? String == id,
              selectedReservation?["Status"] as? String == "Reserved",
              store.session?.accessToken == token else { return }
        do {
            let response = try await MobileAPI(store: store).get(
                "/api/JHCTITourismReservation/GetMinePage?page=1&pageSize=20",
                authenticated: true, expectedPrincipal: principal) as? [String: Any]
            guard reservationDetailOpen, reservationQrImage != nil,
                  selectedReservation?["Id"] as? String == id,
                  store.session?.accessToken == token,
                  let rows = (response?["data"] ?? response?["Data"]) as? [[String: Any]],
                  let latest = rows.first(where: { $0["Id"] as? String == id }) else { return }
            reservations = reservations.map { ($0["Id"] as? String == id) ? latest : $0 }
            selectedReservation = latest
        } catch {
            // 轮询失败时保留当前二维码和预约状态，下一轮继续核对。
        }
    }

    private func loadReservations(reset: Bool) async {
        guard pageVisible, scenePhase == .active, !favoritesOpen, !activityRegistrationsOpen else { return }
        if !reset && (loading || reservationLoadingMore || !reservationHasMore) { return }
        guard let token = store.session?.accessToken, !token.isEmpty,
              let principal = nativeTourismPrincipal(token) else {
            reservations = []; reservationPage = 1; reservationTotal = 0; loading = false
            reservationOwner = ""; reservationHasMore = false; reservationLoadingMore = false
            return
        }
        if !reset && reservationOwner != token {
            clearPrivateReservations(); error = "登录状态已变化，请刷新预约记录。"; return
        }
        let lastId = reset ? nil : reservations.last?["Id"] as? String
        if !reset && lastId.flatMap({ Int64($0) }).map({ $0 > 0 && String($0) == lastId }) != true {
            reservationHasMore = false; error = "预约记录游标无效，请刷新后重试。"; return
        }
        let targetPage = reset ? 1 : reservationPage + 1
        if reset {
            closeReservationDetail(refresh: false); reservationOwner = ""; reservationHasMore = false
            reservationPage = 1; reservationTotal = 0
            reservations = []; reservationLoadingMore = false
        }
        reservationRequestSequence += 1
        let sequence = reservationRequestSequence
        loading = reset; reservationLoadingMore = !reset; error = nil
        func isCurrent() -> Bool {
            !Task.isCancelled && store.session?.accessToken == token && reservationRequestSequence == sequence
                && pageVisible && scenePhase == .active && !favoritesOpen && !activityRegistrationsOpen
        }
        defer { if isCurrent() { loading = false; reservationLoadingMore = false } }
        do {
            let cursor = lastId.map { "&beforeReservationId=\($0)" } ?? ""
            let result = try await MobileAPI(store: store).get(
                "/api/JHCTITourismReservation/GetMinePage?page=\(targetPage)&pageSize=20\(cursor)",
                authenticated: true, expectedPrincipal: principal) as? [String: Any]
            guard isCurrent() else { return }
            guard let result,
                  let rows = (result["data"] ?? result["Data"]) as? [[String: Any]] else {
                throw MobileAPIError.unavailable("预约记录响应格式异常，请刷新后重试")
            }
            guard let total = nativeTourismReservationPageTotal(result, rowCount: rows.count) else {
                throw MobileAPIError.unavailable("预约记录分页数据异常，请刷新后重试")
            }
            var seen = Set<String>()
            guard rows.allSatisfy({ row in
                guard let id = row["Id"] as? String, let number = Int64(id), number > 0, String(number) == id else { return false }
                return seen.insert(id).inserted
            }) else { throw MobileAPIError.unavailable("预约记录编号异常，请刷新后重试。") }
            let existing = Set(reservations.compactMap { $0["Id"] as? String })
            let additions = rows.filter { !existing.contains($0["Id"] as? String ?? "") }
            if !reset && !rows.isEmpty && additions.isEmpty {
                reservationHasMore = false; throw MobileAPIError.unavailable("预约列表已变化，请刷新后继续。")
            }
            closeReservationDetail(refresh: false)
            reservations = reset ? rows : reservations + additions
            reservationTotal = max(total, reservations.count); reservationPage = targetPage; reservationOwner = token
            reservationHasMore = rows.count == 20 && reservations.count < reservationTotal
            if !reservationActionBusy { reservationNeedsRefresh = false }
        } catch {
            if isCurrent() { self.error = error.localizedDescription }
        }
    }
}
