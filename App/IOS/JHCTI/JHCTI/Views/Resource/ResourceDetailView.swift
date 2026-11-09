import SwiftUI
import CryptoKit

struct ResourceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SessionStore
    let item: ResourceItem
    let onVisibilityChange: ((Bool) -> Void)?
    var initialGuideRouteID: String? = nil
    @StateObject private var reviewRuntime: ResourceDetailReviewRuntime
    @State private var detail: [String: Any]?
    @State private var loading = true
    @State private var error: String?
    @State private var revision = 0
    @State private var detailSequence = 0
    @State private var selectedDetailTab = "details"
    @State private var imagePage = 0
    @State private var summaryExpanded = false
    @State private var reservationOpen = false
    @State private var reservationDate = ""
    @State private var reservationSessionId = ""
    @State private var reservationIdentityNumber = ""
    @State private var reservationIdentityConsent = false
    @State private var reservationBusy = false
    @State private var reservationRecoveryAvailable = false
    @State private var reservationRecoveryChecked = false
    @State private var reservationRecoveryBlocked = false
    @State private var reservationSequence = 0
    @State private var reservationError: String?
    @State private var reservationReceipt: [String: Any]?
    @State private var scenicRecoveryPending = false
    @State private var scenicRecoveryChecking = false
    @State private var scenicRecoverySequence = 0
    @State private var scenicRecoveryLegacy = false
    @State private var scenicRecoveryResults: [[String: Any]] = []
    @State private var scenicRecoveryMessage: String?
    @State private var scenicRecoveryClear: (String, String?, String)?
    @State private var scenicJourneyOpen = false
    @State private var ticketBookingOpen = false
    @State private var ticketBookingEnabled = false
    @State private var isFavorited = false
    @State private var favoriteBusy = false
    @State private var favoriteError: String?
    @State private var favoriteRequestSequence = 0

    init(store: SessionStore, item: ResourceItem, onVisibilityChange: ((Bool) -> Void)? = nil,
         initialGuideRouteID: String? = nil) {
        self.store = store
        self.item = item
        self.onVisibilityChange = onVisibilityChange
        self.initialGuideRouteID = initialGuideRouteID
        _reviewRuntime = StateObject(wrappedValue: ResourceDetailReviewRuntime(store: store, resourceID: item.id))
    }

    private var images: [String] {
        let urls = detail?["ImageUrls"] as? [String] ?? []
        return urls.isEmpty && !item.coverURL.isEmpty ? [item.coverURL] : urls
    }

    private var isFacility: Bool { item.resourceType == "Facility" }
    private var guideRouteScrollTaskID: String {
        let routeIDs = (detail?["Routes"] as? [[String: Any]] ?? [])
            .compactMap { $0["Id"] as? String }.joined(separator: ",")
        return [item.id, String(revision), initialGuideRouteID ?? "", routeIDs].joined(separator: "-")
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if detail == nil { scenicRecoveryPanel.padding(.top, 64) }
                if loading { ProgressView(isFacility ? "正在加载设施详情…" : "正在加载景区详情…").frame(maxWidth: .infinity).padding(36) }
                if let error {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).foregroundStyle(.red)
                        Button("重试加载") { revision += 1 }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
                if let detail {
                    if !images.isEmpty {
                        ZStack(alignment: .bottomTrailing) {
                            TabView(selection: $imagePage) {
                                ForEach(Array(images.enumerated()), id: \.offset) { index, path in
                                    Group {
                                        if let url = MobileAPI(store: store).mediaURL(path) {
                                            CachedRemoteImage(url: url) { Image("Quick7").resizable().scaledToFill() }
                                        } else { Image("Quick7").resizable().scaledToFill() }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                                    .tag(index)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
                            .frame(height: 240)
                            if images.count > 1 {
                                Text(String(format: "%d / %d", imagePage + 1, images.count))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(.black.opacity(0.6), in: Capsule())
                                    .padding(12)
                            }
                        }
                        .frame(height: 240)
                        .onChange(of: images) { _, _ in imagePage = 0 }
                    } else {
                        NativeThemeCover(imageName: "Quick7", label: "江都主题插画")
                            .frame(height: 240)
                    }
                    scenicRecoveryPanel
                    NativeResourceOverviewSection(store: store, item: item, detail: detail,
                        initialGuideRouteID: initialGuideRouteID,
                        ticketBookingEnabled: ticketBookingEnabled,
                        reservationUnavailable: scenicRecoveryPending || scenicRecoveryChecking,
                        selectedDetailTab: $selectedDetailTab, summaryExpanded: $summaryExpanded,
                        reviewForm: isFacility ? nil : AnyView(reviewForm),
                        onFreeReservation: {
                            reservationDate = (detail["ReservationDates"] as? [[String: Any]])?.first?["Date"] as? String ?? Self.todayDate
                            reservationSessionId = ""
                            reservationIdentityNumber = ""
                            reservationIdentityConsent = false
                            reservationError = nil
                            reservationReceipt = nil
                            reservationOpen = true
                        },
                        onTicketBooking: { ticketBookingOpen = true })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)
        }
        .background(.white)
        .ignoresSafeArea(edges: .top)
        .task(id: guideRouteScrollTaskID) {
            guard let initialGuideRouteID,
                  (detail?["Routes"] as? [[String: Any]])?.contains(where: { $0["Id"] as? String == initialGuideRouteID }) == true else { return }
            await Task.yield()
            withAnimation { scrollProxy.scrollTo("guide-route-\(initialGuideRouteID)", anchor: .center) }
        }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isFacility {
                VStack(spacing: 6) {
                    if let favoriteError {
                        Text(favoriteError).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Button {
                            Task { await toggleFavorite() }
                        } label: {
                            Text(favoriteBusy ? "处理中…" : isFavorited ? "♥ 已收藏" : "♡ 收藏景点")
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .overlay(Capsule().stroke(Brand.border, lineWidth: 1))
                        }
                        .disabled(favoriteBusy || detail == nil)
                        ShareLink(item: "https://travel.jiangdu.net/subpackages/resource/index?id=\(item.id)") {
                            Text("分享").frame(minWidth: 48, minHeight: 36)
                                .overlay(Capsule().stroke(Brand.border, lineWidth: 1))
                        }
                    }
                    .font(.system(size: NativeTypography.size(14), weight: .medium))
                    .foregroundStyle(Brand.primary)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.white)
                .overlay(alignment: .top) { Brand.border.frame(height: 1) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .simultaneousGesture(DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard value.startLocation.x <= 32,
                      horizontal >= 72, horizontal > abs(vertical) * 1.25 else { return }
                dismiss()
            })
        .task(id: "\(item.id)-\(revision)-\(store.session?.accessToken ?? "")") { await load() }
        .task(id: item.id + "-" + (store.session?.accessToken ?? "")) {
            if !isFacility {
                reviewRuntime.updateResource(id: item.id)
                await reviewRuntime.load()
            }
        }
        .task(id: "recovery-\(item.id)-\(revision)-\(store.session?.accessToken ?? "")") { await recoverScenicReservations() }
        .onAppear { onVisibilityChange?(true) }
        .onDisappear {
            invalidateDetail(); reservationSequence += 1; reservationBusy = false; reservationOpen = false
            invalidateScenicRecovery()
            reservationRecoveryAvailable = false; reservationRecoveryChecked = false; reservationRecoveryBlocked = false
            reservationIdentityNumber = ""; reservationIdentityConsent = false; onVisibilityChange?(false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { revision += 1 }
            else { invalidateDetail(); invalidateScenicRecovery() }
        }
        .onChange(of: store.session?.accessToken) { oldToken, newToken in
            if nativeTourismPrincipal(oldToken) != nativeTourismPrincipal(newToken) {
                reservationSequence += 1; reservationBusy = false; reservationOpen = false
                reservationDate = ""; reservationSessionId = ""
                reservationReceipt = nil; reservationRecoveryAvailable = false
                reservationRecoveryChecked = false; reservationRecoveryBlocked = false; reservationError = nil
                reservationIdentityNumber = ""; reservationIdentityConsent = false
                favoriteRequestSequence += 1; favoriteBusy = false; favoriteError = nil; isFavorited = false
                reviewRuntime.resetForAccountChange()
                invalidateScenicRecovery()
            }
            invalidateDetail(); revision += 1
        }
        .sheet(isPresented: $reservationOpen) { reservationSheet }
        .sheet(isPresented: $scenicJourneyOpen) {
            NavigationStack {
                JourneyView(store: store, onMap: { scenicJourneyOpen = false }, onProfile: { scenicJourneyOpen = false })
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("返回景点") { scenicJourneyOpen = false; revision += 1 } } }
            }
        }
        .onChange(of: scenicJourneyOpen) { _, open in
            if open { invalidateScenicRecovery() } else { revision += 1 }
        }
        .overlay {
            NativeScenicRecoveryConfirmation(isPresented: scenicRecoveryClear != nil,
                onKeep: { scenicRecoveryClear = nil }, onConfirmClear: { clearScenicRecoveryIndex() })
        }
        .navigationDestination(isPresented: $ticketBookingOpen) {
            NativeTicketBookingView(store: store, resourceId: item.id,
                                    resourceName: detail?["Name"] as? String ?? item.name,
                                    admissionType: detail?["AdmissionType"] as? String ?? item.admissionType)
                .toolbar(.visible, for: .navigationBar)
        }
    }

    @ViewBuilder private var scenicRecoveryPanel: some View {
        NativeScenicRecoveryPanel(pending: scenicRecoveryPending, legacy: scenicRecoveryLegacy,
            checking: scenicRecoveryChecking, busy: reservationBusy, message: scenicRecoveryMessage,
            results: scenicRecoveryResults, reservationStatus: Self.reservationStatus,
            onCheck: { Task { await recoverScenicReservations(includeLegacy: true) } },
            onOpenJourney: { scenicJourneyOpen = true },
            onRequestClear: {
                guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else { return }
                let key = Self.reservationRecoveryIndexKey(token: token, resourceID: item.id)
                guard let snapshot = UserDefaults.standard.string(forKey: key) else {
                    scenicRecoveryMessage = "无法读取本机预约索引，请先在行程中核对预约。"; return
                }
                scenicRecoveryClear = (key, snapshot, principal)
            })
    }

    private func invalidateScenicRecovery() {
        scenicRecoverySequence += 1; scenicRecoveryChecking = false
        scenicRecoveryResults = []; scenicRecoveryMessage = nil; scenicRecoveryClear = nil
        scenicRecoveryPending = false; scenicRecoveryLegacy = false
    }

    private func recoverScenicReservations(includeLegacy: Bool = false) async {
        guard item.resourceType == "ScenicSpot", scenePhase == .active, !reservationBusy, !scenicRecoveryChecking,
              let resourceNumber = Int64(item.id), resourceNumber > 0, String(resourceNumber) == item.id,
              let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else { return }
        let indexKey = Self.reservationRecoveryIndexKey(token: token, resourceID: item.id)
        let snapshot = UserDefaults.standard.string(forKey: indexKey)
        scenicRecoveryPending = UserDefaults.standard.object(forKey: indexKey) != nil
        let allLegacy = UserDefaults.standard.dictionaryRepresentation().compactMap { key, value -> (String, String)? in
            guard key.range(of: "^jhcti\\.reservation\\.[0-9a-f]{64}$", options: .regularExpression) != nil,
                  let request = value as? String, request.range(of: "^[A-Za-z0-9._:-]{8,80}$", options: .regularExpression) != nil else { return nil }
            return (key, request)
        }.sorted { $0.0 < $1.0 }
        scenicRecoveryLegacy = !allLegacy.isEmpty
        var candidates: [(String, String)] = []
        if let snapshot {
            let parts = snapshot.components(separatedBy: "|")
            guard parts.count == 2, parts[0].range(of: "^jhcti\\.reservation\\.([0-9a-f]{64}|v2\\.[0-9a-f]{64}\\.[1-9][0-9]*\\.[0-9]+\\.[0-9]{4}-[0-9]{2}-[0-9]{2})$", options: .regularExpression) != nil,
                  parts[1].range(of: "^[A-Za-z0-9._:-]{8,80}$", options: .regularExpression) != nil else {
                scenicRecoveryMessage = "预约恢复索引异常，请先核对行程，确认后可清理索引。"; return
            }
            candidates = [(parts[0], parts[1])]
        } else if scenicRecoveryPending {
            scenicRecoveryMessage = "无法读取本机预约恢复索引，请先在行程中核对记录。"; return
        }
        if includeLegacy && snapshot == nil {
            guard allLegacy.count <= 100 else { scenicRecoveryMessage = "本机旧记录较多，请先在行程中核对本人预约。旧标记已保留。"; return }
            candidates += allLegacy.filter { legacy in !candidates.contains { $0.0 == legacy.0 } }
        }
        guard !candidates.isEmpty else { return }
        scenicRecoverySequence += 1; let operation = scenicRecoverySequence
        scenicRecoveryChecking = true; scenicRecoveryResults = []; scenicRecoveryMessage = "正在核对原请求，无需重新选择日期或场次。"
        func current() -> Bool {
            operation == scenicRecoverySequence && scenePhase == .active && !reservationBusy
                && nativeTourismPrincipal(store.session?.accessToken) == principal
                && UserDefaults.standard.string(forKey: indexKey) == snapshot
        }
        defer { if operation == scenicRecoverySequence { scenicRecoveryChecking = false } }
        var confirmed: [[String: Any]] = []
        var resolved: [(String, String)] = []
        do {
            for (storageKey, key) in candidates {
                guard current() else { return }
                let value = try await MobileAPI(store: store).get("/api/JHCTITourismReservation/GetMineByIdempotencyKey?resourceId=\(item.id)&idempotencyKey=\(key)",
                    authenticated: true, expectedPrincipal: principal)
                guard current() else { return }
                // 旧哈希键无法归属账号或景点；必须由本人查询结果反算原键，才能确认并清理。
                guard var result = value as? [String: Any], Self.scenicRecoveryMatches(result, token: token, resourceID: item.id, storageKey: storageKey) else { continue }
                let stored = UserDefaults.standard.string(forKey: storageKey)
                guard stored == key || (stored == nil && snapshot == storageKey + "|" + key) else { continue }
                result["CredentialCode"] = ""; result["IdentityNumberMasked"] = nil
                confirmed.append(result); resolved.append((storageKey, key))
            }
            guard current() else { return }
            for (storageKey, key) in resolved {
                if UserDefaults.standard.string(forKey: storageKey) == key { UserDefaults.standard.removeObject(forKey: storageKey) }
                if snapshot == storageKey + "|" + key, UserDefaults.standard.string(forKey: storageKey) == nil {
                    UserDefaults.standard.removeObject(forKey: indexKey)
                }
            }
            scenicRecoveryResults = confirmed
            scenicRecoveryPending = UserDefaults.standard.object(forKey: indexKey) != nil
            scenicRecoveryLegacy = allLegacy.contains { UserDefaults.standard.string(forKey: $0.0) != nil }
            scenicRecoveryMessage = scenicRecoveryPending ? "上次预约仍待确认，暂未查到不代表未提交。请保留标记，稍后重试或核对行程。"
                : confirmed.isEmpty ? "未查到与此账号、景点和原请求键匹配的预约。旧标记可能属于其他账号或景点，已保留；请先核对行程。"
                : "已核对原预约。入园二维码及最新状态请在行程中查看。未匹配的旧标记已保留。"
        } catch {
            if current() { scenicRecoveryMessage = "暂时无法核对原预约，恢复标记已保留，请稍后重试。" }
        }
    }

    private func clearScenicRecoveryIndex() {
        guard let target = scenicRecoveryClear, !reservationBusy, !scenicRecoveryChecking, scenePhase == .active,
              nativeTourismPrincipal(store.session?.accessToken) == target.2,
              let snapshot = target.1, UserDefaults.standard.string(forKey: target.0) == snapshot else { return }
        scenicRecoverySequence += 1
        UserDefaults.standard.removeObject(forKey: target.0)
        scenicRecoveryPending = UserDefaults.standard.object(forKey: target.0) != nil
        scenicRecoveryClear = nil
        scenicRecoveryMessage = scenicRecoveryPending ? "本机索引尚未清理，请稍后重试。" : "本机索引已清理，原请求键仍保留，不会取消服务端预约。"
    }

    private static func scenicRecoveryMatches(_ result: [String: Any], token: String, resourceID: String, storageKey: String) -> Bool {
        guard let id = result["Id"] as? String, let number = Int64(id), number > 0, String(number) == id,
              result["ResourceId"] as? String == resourceID, let session = result["SessionId"] as? String,
              let sessionNumber = Int64(session), sessionNumber >= 0, String(sessionNumber) == session,
              let date = result["ReservationDate"] as? String, let instant = paymentDeadline(date + " 00:00:00"),
              ["Reserved", "Cancelled", "CheckedIn"].contains(result["Status"] as? String ?? ""),
              !(result["SessionName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: instant) == date
            && (reservationStorageKey(token: token, resourceID: resourceID, sessionID: session, date: date) == storageKey
                || legacyReservationStorageKey(token: token, resourceID: resourceID, sessionID: session, date: date) == storageKey)
    }

    private static func reservationStatus(_ result: [String: Any]) -> String {
        if result["Status"] as? String == "Cancelled" { return "已取消" }
        if result["Status"] as? String == "CheckedIn" { return "已入园" }
        guard let text = result["EndTime"] as? String, !text.hasPrefix("0001-01-01"),
              let end = paymentDeadline(text) else { return "已预约（时间待核对）" }
        return end <= Date() ? "已过期" : "已预约"
    }

    private static var todayDate: String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private var reservationDates: [[String: Any]] { detail?["ReservationDates"] as? [[String: Any]] ?? [] }
    private var reservationSessions: [[String: Any]] {
        (detail?["ReservationSessions"] as? [[String: Any]] ?? []).filter { ($0["StartTime"] as? String ?? "").hasPrefix(reservationDate) }
    }
    private var hasReservationSessions: Bool { detail?["HasConfiguredReservationSessions"] as? Bool ?? !((detail?["ReservationSessions"] as? [[String: Any]] ?? []).isEmpty) }
    private var selectedReservationSession: [String: Any]? { reservationSessions.first { $0["Id"] as? String == reservationSessionId } }

    private var reservationSheet: some View {
        NativeResourceReservationSheet(item: item, reservationDates: reservationDates,
            reservationSessions: reservationSessions, hasReservationSessions: hasReservationSessions,
            selectedReservationSession: selectedReservationSession, reservationBusy: reservationBusy,
            reservationRecoveryAvailable: reservationRecoveryAvailable, reservationRecoveryChecked: reservationRecoveryChecked,
            reservationRecoveryBlocked: reservationRecoveryBlocked, reservationError: reservationError,
            reservationReceipt: reservationReceipt, identityNumberValid: Self.isValidIdentityNumber(reservationIdentityNumber),
            hasPendingReservation: { hasPendingReservation(sessionID: $0, date: $1) },
            reservationStatus: Self.reservationStatus,
            onRecoverPendingReservation: { await recoverPendingReservationOnOpen() },
            onSubmitReservation: { await submitReservation() },
            isPresented: $reservationOpen, reservationDate: $reservationDate,
            reservationSessionId: $reservationSessionId, reservationIdentityNumber: $reservationIdentityNumber,
            reservationIdentityConsent: $reservationIdentityConsent)
    }

    private func recoverPendingReservationOnOpen() async {
        reservationRecoveryChecked = false
        reservationRecoveryBlocked = false
        guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else {
            reservationRecoveryAvailable = false
            reservationRecoveryChecked = true
            return
        }
        let legacyCandidates: [(sessionId: String, date: String)]
        if hasReservationSessions {
            legacyCandidates = (detail?["ReservationSessions"] as? [[String: Any]] ?? []).compactMap { session in
                guard let sessionID = session["Id"] as? String,
                      let start = session["StartTime"] as? String, start.count >= 10 else { return nil }
                return (sessionID, String(start.prefix(10)))
            }
        } else {
            legacyCandidates = reservationDates.compactMap { row in
                guard let date = row["Date"] as? String else { return nil }
                return ("0", date)
            }
        }
        guard let markers = Self.reservationAttemptMarkers(token: token, resourceID: item.id,
            legacyCandidates: legacyCandidates) else {
            reservationRecoveryAvailable = true
            reservationRecoveryChecked = true
            reservationRecoveryBlocked = true
            reservationError = "本机预约恢复标记异常，已保留原信息；请到行程中核对预约记录。"
            return
        }
        guard markers.count <= 1 else {
            reservationRecoveryAvailable = true
            reservationRecoveryChecked = true
            reservationError = "检测到多条待核对预约请求，已保留全部信息；请到行程中逐条核对。"
            return
        }
        guard let marker = markers.first else {
            reservationRecoveryAvailable = false
            reservationRecoveryChecked = true
            return
        }
        reservationRecoveryAvailable = true
        reservationRecoveryChecked = true
        reservationSequence += 1
        let operation = reservationSequence
        reservationBusy = true
        reservationError = nil
        defer {
            if operation == reservationSequence, nativeTourismPrincipal(store.session?.accessToken) == principal {
                reservationBusy = false
            }
        }
        do {
            let encodedKey = marker.idempotencyKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                ?? marker.idempotencyKey
            let recovered = try await MobileAPI(store: store).get(
                "/api/JHCTITourismReservation/GetMineByIdempotencyKey?idempotencyKey=\(encodedKey)",
                authenticated: true, expectedPrincipal: principal
            ) as? [String: Any]
            guard reservationOpen, operation == reservationSequence,
                  nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
            guard let recovered else {
                reservationError = "暂未找到预约记录，恢复请求已保留；请在行程中核对后再操作。"
                return
            }
            guard recovered["ResourceId"] as? String == item.id,
                  recovered["SessionId"] as? String == marker.sessionId,
                  recovered["ReservationDate"] as? String == marker.reservationDate,
                  let id = recovered["Id"] as? String, let number = Int64(id), number > 0, String(number) == id,
                  hasCompleteNativeTourismReservationReceipt(recovered),
                  UserDefaults.standard.string(forKey: marker.storageKey) == marker.idempotencyKey else {
                reservationError = "预约查询回执不完整或与本机请求不匹配，恢复标记已保留。"
                return
            }
            UserDefaults.standard.removeObject(forKey: marker.storageKey)
            guard UserDefaults.standard.string(forKey: marker.storageKey) == nil else {
                reservationError = "已找回预约记录，但本机恢复标记尚未清理；请稍后重试。"
                return
            }
            reservationDate = marker.reservationDate
            reservationSessionId = marker.sessionId
            reservationReceipt = recovered
            reservationRecoveryAvailable = false
            reservationIdentityNumber = ""
            reservationIdentityConsent = false
        } catch {
            if reservationOpen, operation == reservationSequence,
               nativeTourismPrincipal(store.session?.accessToken) == principal {
                reservationError = "暂时无法核对预约结果，恢复标记已保留；请稍后重试。"
            }
        }
    }

    private func submitReservation() async {
        guard !reservationBusy else { return }
        guard !scenicRecoveryChecking else { reservationError = "正在核对上次预约结果，请稍候。"; return }
        guard !reservationRecoveryBlocked else {
            reservationError = "本机预约恢复标记异常，已保留原信息；请到行程中核对预约记录。"
            return
        }
        guard let token = store.session?.accessToken, let principal = nativeTourismPrincipal(token) else {
            reservationError = "请先登录并验证手机号后预约。"; return
        }
        let daily = !hasReservationSessions
        let sessionId = daily ? "0" : reservationSessionId
        let requestedDate = reservationDate
        let identityRequired = selectedReservationSession?["RequireIdentityNumber"] as? Bool == true
        let consent = reservationIdentityConsent
        guard !requestedDate.isEmpty, daily || !sessionId.isEmpty else { reservationError = "请选择预约日期和场次。"; return }
        let identityNumber = identityRequired
            ? Self.normalizedIdentityNumber(reservationIdentityNumber) : nil
        if identityRequired && (identityNumber == nil || !consent) {
            reservationError = "请填写有效身份证号码并确认本次预约用途。"; return
        }
        reservationSequence += 1; let operation = reservationSequence
        reservationBusy = true; reservationError = nil
        defer { if operation == reservationSequence, nativeTourismPrincipal(store.session?.accessToken) == principal { reservationBusy = false } }
        let currentStorageKey = Self.reservationStorageKey(token: token, resourceID: item.id, sessionID: sessionId, date: requestedDate)
        let legacyStorageKey = Self.legacyReservationStorageKey(token: token, resourceID: item.id, sessionID: sessionId, date: requestedDate)
        let storageKey = UserDefaults.standard.string(forKey: currentStorageKey) != nil ? currentStorageKey
            : (UserDefaults.standard.string(forKey: legacyStorageKey) != nil ? legacyStorageKey : currentStorageKey)
        let storedKey = UserDefaults.standard.string(forKey: storageKey)
        do {
            if storedKey == nil {
                guard let refreshed = try await MobileAPI(store: store).get("/api/JHCTITourismResource/GetPublicDetail?id=\(item.id)", authenticated: true,
                    expectedPrincipal: principal) as? [String: Any],
                      refreshed["Id"] as? String == item.id else { throw MobileAPIError.unavailable("无法确认预约场次最新余量，请刷新后重试。") }
                guard operation == reservationSequence, nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
                guard refreshed["AdmissionType"] as? String == "FreeReservation" else {
                    throw MobileAPIError.unavailable("景点接待方式已更新，请关闭后刷新景点详情。")
                }
                if daily {
                    let row = (refreshed["ReservationDates"] as? [[String: Any]] ?? []).first { $0["Date"] as? String == requestedDate }
                    guard row?["IsReserved"] as? Bool != true, (row?["Available"] as? Int ?? 0) > 0 else {
                        throw MobileAPIError.unavailable("所选日期已预约或名额已满，请刷新后选择其他日期。")
                    }
                } else {
                    let row = (refreshed["ReservationSessions"] as? [[String: Any]] ?? []).first { $0["Id"] as? String == sessionId }
                    guard row?["IsEnabled"] as? Bool == true, row?["IsReserved"] as? Bool != true,
                          (row?["Available"] as? Int ?? 0) > 0,
                          let start = paymentDeadline(row?["StartTime"]), start > Date() else {
                        throw MobileAPIError.unavailable("所选场次已开始、已预约或名额已满，请重新选择。")
                    }
                    guard (row?["RequireIdentityNumber"] as? Bool == true) == identityRequired else {
                        throw MobileAPIError.unavailable("场次实名要求已更新，请刷新后重新填写预约信息。")
                    }
                }
            }
            guard operation == reservationSequence, nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
            let key = UserDefaults.standard.string(forKey: storageKey) ?? storedKey ?? "native-\(UUID().uuidString.lowercased())"
            guard key.range(of: "^[A-Za-z0-9._:-]{8,80}$", options: .regularExpression) != nil else {
                throw MobileAPIError.unavailable("本机预约恢复标记异常，请先在行程中核对预约记录。")
            }
            let indexKey = Self.reservationRecoveryIndexKey(token: token, resourceID: item.id)
            let marker = storageKey + "|" + key
            guard UserDefaults.standard.object(forKey: indexKey) == nil || UserDefaults.standard.string(forKey: indexKey) == marker else {
                scenicRecoveryPending = true
                throw MobileAPIError.unavailable("本机存在另一笔待确认预约，请先核对行程。")
            }
            UserDefaults.standard.set(marker, forKey: indexKey)
            guard UserDefaults.standard.string(forKey: indexKey) == marker else {
                throw MobileAPIError.unavailable("设备无法保存预约恢复索引，本次预约尚未提交。")
            }
            scenicRecoveryPending = true
            UserDefaults.standard.set(key, forKey: storageKey)
            guard UserDefaults.standard.string(forKey: storageKey) == key else {
                throw MobileAPIError.unavailable("设备暂时无法保存预约请求，本次预约尚未提交。")
            }
            if storedKey != nil {
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let recovered = try await MobileAPI(store: store).get(
                    "/api/JHCTITourismReservation/GetMineByIdempotencyKey?idempotencyKey=\(encodedKey)",
                    authenticated: true, expectedPrincipal: principal
                ) as? [String: Any]
                guard operation == reservationSequence, nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
                if let recovered {
                    guard recovered["ResourceId"] as? String == item.id,
                          recovered["SessionId"] as? String == sessionId,
                          recovered["ReservationDate"] as? String == requestedDate,
                          let id = recovered["Id"] as? String, let number = Int64(id), number > 0, String(number) == id,
                          hasCompleteNativeTourismReservationReceipt(recovered),
                          UserDefaults.standard.string(forKey: storageKey) == key else {
                        throw MobileAPIError.unavailable("预约查询回执不完整或与本机请求不匹配，恢复标记已保留。")
                    }
                    UserDefaults.standard.removeObject(forKey: storageKey)
                    reservationReceipt = recovered
                    reservationRecoveryAvailable = false
                    reservationRecoveryBlocked = false
                    reservationIdentityNumber = ""; reservationIdentityConsent = false
                    return
                }
            }
            var body: [String: Any] = ["ResourceId": item.id, "SessionId": sessionId,
                "ReservationDate": requestedDate, "IdempotencyKey": key]
            if let identityNumber { body["IdentityNumber"] = identityNumber; body["IdentityConsent"] = consent }
            let result = try await MobileAPI(store: store).post("/api/JHCTITourismReservation/Create", body: body,
                authenticated: true, expectedPrincipal: principal) as? [String: Any]
            guard operation == reservationSequence, nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
            guard let result,
                  result["ResourceId"] as? String == item.id, result["SessionId"] as? String == sessionId,
                  result["ReservationDate"] as? String == requestedDate,
                  let id = result["Id"] as? String, let number = Int64(id), number > 0, String(number) == id,
                  hasCompleteNativeTourismReservationReceipt(result),
                  UserDefaults.standard.string(forKey: storageKey) == key else {
                throw MobileAPIError.unavailable("预约回执暂未确认，请先在行程中核对；重试将沿用原请求号。")
            }
            UserDefaults.standard.removeObject(forKey: storageKey)
            if UserDefaults.standard.string(forKey: indexKey) == marker { UserDefaults.standard.removeObject(forKey: indexKey) }
            scenicRecoveryPending = UserDefaults.standard.string(forKey: indexKey) != nil
            reservationReceipt = result
            reservationRecoveryAvailable = false
            reservationRecoveryBlocked = false
            reservationIdentityNumber = ""; reservationIdentityConsent = false
        } catch {
            if operation == reservationSequence, nativeTourismPrincipal(store.session?.accessToken) == principal {
                reservationError = "\(error.localizedDescription)；重试将继续核对原预约请求。"
            }
        }
    }

    private func hasPendingReservation(sessionID: String, date: String) -> Bool {
        guard let token = store.session?.accessToken else { return false }
        return UserDefaults.standard.string(forKey: Self.reservationStorageKey(token: token, resourceID: item.id, sessionID: sessionID, date: date)) != nil
            || UserDefaults.standard.string(forKey: Self.legacyReservationStorageKey(token: token, resourceID: item.id, sessionID: sessionID, date: date)) != nil
    }

    private static func reservationStorageKey(token: String, resourceID: String, sessionID: String, date: String) -> String {
        let principalHash = SHA256.hash(data: Data(reservationPrincipal(token).utf8)).map { String(format: "%02x", $0) }.joined()
        return "jhcti.reservation.v2.\(principalHash).\(resourceID).\(sessionID).\(date)"
    }

    private static func legacyReservationStorageKey(token: String, resourceID: String, sessionID: String, date: String) -> String {
        let fingerprint = "\(reservationPrincipal(token))|\(resourceID)|\(sessionID)|\(date)"
        return "jhcti.reservation." + SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func reservationRecoveryIndexKey(token: String, resourceID: String) -> String {
        "jhcti.reservation-index.v1." + legacyReservationStorageKey(token: token, resourceID: resourceID, sessionID: "0", date: "").replacingOccurrences(of: "jhcti.reservation.", with: "")
    }

    // 新版标记保留可枚举的预约坐标，供冷启动按账号和景点安全查回原请求。
    private static func reservationAttemptMarkers(token: String, resourceID: String,
        legacyCandidates: [(sessionId: String, date: String)])
        -> [(storageKey: String, sessionId: String, reservationDate: String, idempotencyKey: String)]? {
        let principalHash = SHA256.hash(data: Data(reservationPrincipal(token).utf8)).map { String(format: "%02x", $0) }.joined()
        let prefix = "jhcti.reservation.v2.\(principalHash).\(resourceID)."
        let keys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        var markers: [(storageKey: String, sessionId: String, reservationDate: String, idempotencyKey: String)] = []
        for storageKey in keys {
            let parts = storageKey.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, let sessionNumber = Int64(parts[0]), sessionNumber >= 0,
                  parts[1].range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil,
                  let requestKey = UserDefaults.standard.string(forKey: storageKey),
                  requestKey.range(of: "^[A-Za-z0-9._:-]{8,80}$", options: .regularExpression) != nil else { return nil }
            markers.append((storageKey, parts[0], parts[1], requestKey))
        }
        for candidate in legacyCandidates {
            guard let sessionNumber = Int64(candidate.sessionId), sessionNumber >= 0,
                  candidate.date.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil else { continue }
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.calendar = Calendar(identifier: .gregorian)
            dateFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.isLenient = false
            guard let date = dateFormatter.date(from: candidate.date),
                  dateFormatter.string(from: date) == candidate.date else { continue }
            let storageKey = legacyReservationStorageKey(token: token, resourceID: resourceID,
                sessionID: candidate.sessionId, date: candidate.date)
            guard let requestKey = UserDefaults.standard.string(forKey: storageKey) else { continue }
            guard requestKey.range(of: "^[A-Za-z0-9._:-]{8,80}$", options: .regularExpression) != nil else { return nil }
            if !markers.contains(where: { $0.storageKey == storageKey }) {
                markers.append((storageKey, candidate.sessionId, candidate.date, requestKey))
            }
        }
        return markers
    }

    private static func normalizedIdentityNumber(_ value: String, now: Date = Date()) -> String? {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.range(of: "^[1-9][0-9]{16}[0-9X]$", options: .regularExpression) != nil else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.isLenient = false
        let birthDate = String(code.dropFirst(6).prefix(8))
        guard let date = dateFormatter.date(from: birthDate), dateFormatter.string(from: date) == birthDate,
              birthDate <= dateFormatter.string(from: now) else { return nil }
        let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
        let checks = Array("10X98765432")
        let sum = zip(code.prefix(17).compactMap(\.wholeNumberValue), weights).reduce(0) { $0 + $1.0 * $1.1 }
        return checks[sum % 11] == code.last ? code : nil
    }

    private static func isValidIdentityNumber(_ value: String) -> Bool { normalizedIdentityNumber(value) != nil }

    // 仅用 JWT 主体隔离本机恢复键；预约身份和资格仍由服务端验证。
    private static func reservationPrincipal(_ token: String) -> String {
        let parts = token.split(separator: ".")
        if parts.count == 3 {
            var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            if let data = Data(base64Encoded: payload),
               let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let subject = claims["sub"] as? String, !subject.isEmpty { return subject }
        }
        return SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private var reviewForm: some View {
        ResourceDetailReviewForm(isLoggedIn: store.session?.accessToken != nil,
            isLoading: reviewRuntime.isLoadingCurrentContext(resourceID: item.id),
            featureState: reviewRuntime.featureState,
            error: reviewRuntime.error, review: reviewRuntime.reviewForCurrentContext(resourceID: item.id),
            reviewBusy: reviewRuntime.reviewBusy, appealBusy: reviewRuntime.appealBusy,
            rating: $reviewRuntime.rating,
            content: Binding(
                get: { reviewRuntime.content },
                set: { reviewRuntime.content = ResourceDetailReviewRuntime.limitedText($0) }),
            appealContent: Binding(
                get: { reviewRuntime.appealContent },
                set: { reviewRuntime.appealContent = ResourceDetailReviewRuntime.limitedText($0) }),
            onRetry: { Task { await reviewRuntime.load() } },
            onSubmitReview: { Task { await reviewRuntime.submitReview() } },
            onSubmitAppeal: { Task { await reviewRuntime.submitAppeal() } })
    }

    private func invalidateDetail() {
        detailSequence += 1; detail = nil; loading = true; isFavorited = false; ticketBookingEnabled = false
        if !reservationBusy { reservationOpen = false; reservationIdentityNumber = ""; reservationIdentityConsent = false }
    }

    private func load() async {
        detailSequence += 1; let operation = detailSequence
        let token = store.session?.accessToken
        loading = true; error = nil; detail = nil; isFavorited = false; selectedDetailTab = "details"; summaryExpanded = false
        do {
            guard await MobileAPI(store: store).featureEnabled("MODULE-SCENIC") else {
                throw MobileAPIError.unavailable("景点模块暂未开放")
            }
            guard operation == detailSequence, store.session?.accessToken == token else { return }
            guard let number = Int64(item.id), number > 0, String(number) == item.id else {
                throw MobileAPIError.unavailable("景点编号无效")
            }
            let endpoint = item.resourceType == "Facility" ? "GetPublicFacilityDetail" : "GetPublicDetail"
            guard let result = try await MobileAPI(store: store)
                .get("/api/JHCTITourismResource/\(endpoint)?id=\(item.id)",
                     authenticated: token != nil) as? [String: Any],
                operation == detailSequence, store.session?.accessToken == token,
                result["Id"] as? String == item.id else {
                throw MobileAPIError.unavailable("景点详情数据异常，请重试")
            }
            detail = result
            isFavorited = result["IsFavorited"] as? Bool ?? false
            let ticketEnabled = await MobileAPI(store: store).featureEnabled("F-TKT-002", forceRefresh: true)
            guard operation == detailSequence, store.session?.accessToken == token else { return }
            ticketBookingEnabled = ticketEnabled
        } catch {
            if operation == detailSequence, store.session?.accessToken == token { self.error = error.localizedDescription }
        }
        if operation == detailSequence { loading = false }
    }

    @MainActor private func toggleFavorite() async {
        guard let token = store.session?.accessToken, !token.isEmpty,
              let principal = nativeTourismPrincipal(token) else { favoriteError = "请先登录文旅账号，再收藏景点。"; return }
        guard !favoriteBusy else { return }
        favoriteRequestSequence += 1
        let requestSequence = favoriteRequestSequence
        favoriteBusy = true; favoriteError = nil
        do {
            let value: Any = isFavorited
                ? try await MobileAPI(store: store).delete("/api/JHCTITourismResource/RemoveFavorite?resourceId=\(item.id)",
                    authenticated: true, expectedPrincipal: principal)
                : try await MobileAPI(store: store).post("/api/JHCTITourismResource/SetFavorite",
                    body: ["ResourceId": item.id], authenticated: true, expectedPrincipal: principal)
            guard store.session?.accessToken == token, favoriteRequestSequence == requestSequence else { return }
            guard value as? String == item.id else {
                throw MobileAPIError.unavailable("收藏结果无法确认，请刷新详情后重试")
            }
            isFavorited.toggle()
        } catch {
            if store.session?.accessToken == token, favoriteRequestSequence == requestSequence {
                favoriteError = error.localizedDescription
            }
        }
        if favoriteRequestSequence == requestSequence { favoriteBusy = false }
    }
}
