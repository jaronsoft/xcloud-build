import SwiftUI
import CoreFoundation
import CryptoKit

struct TravelRouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    let store: SessionStore
    let id: String
    @State private var detail: [String: Any]?
    @State private var error: String?
    @State private var bookingNotice: String?
    @State private var loading = true
    @State private var availabilityStale = false
    @State private var bookingEnabled = false
    @State private var busy = false
    @State private var showOrders = false
    @State private var pendingIdempotencyKey: String?
    @State private var selectedSessionID = ""
    @State private var guestCount = 1
    @State private var pointsToUse = "0"
    @State private var pointsBalance: Int64?
    @State private var pointsDebt: Int64?
    @State private var pointsSummaryError = false
    @State private var pointsSummaryRevision = 0
    @State private var revision = 0
    @State private var selectedScenicResource: ResourceItem?

    private var sessions: [[String: Any]] { detail?["Sessions"] as? [[String: Any]] ?? [] }
    private var availableSessions: [[String: Any]] {
        sessions.filter { (($0["AvailableCount"] as? NSNumber)?.intValue ?? 0) > 0 }
    }
    private var selectedSession: [String: Any]? { availableSessions.first { $0["Id"] as? String == selectedSessionID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StatusView(loading: loading, error: error) { revision += 1 }
                if let detail {
                    NativeRouteThemeImage(store: store, path: catalogCover(detail))
                        .frame(maxWidth: .infinity).frame(height: 230).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    let destination = detail["Destination"] as? String ?? "扬州江都"
                    let durationDays = detail["DurationDays"] as? Int ?? 0
                    Text(destination + (durationDays > 0 ? " · \(durationDays) 日行程" : ""))
                        .font(.caption).foregroundStyle(Brand.primary)
                    Text(detail["Name"] as? String ?? "江都旅游线路")
                        .font(.title2.bold()).foregroundStyle(Brand.ink)
                    ShareLink(item: "https://travel.jiangdu.net/subpackages/route/index?id=\(id)&sessionId=\(selectedSessionID)&guests=\(guestCount)") {
                        Label("分享线路与当前班期", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(Brand.primary)
                            .background(Brand.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let summary = detail["Summary"] as? String, !summary.isEmpty { Text(summary) }
                    if let meeting = detail["MeetingPoint"] as? String, !meeting.isEmpty {
                        Text("集合地点：\(meeting)")
                    }
                    if let latitude = nativeCoordinateNumber(detail, keys: ["MeetingLatitude"]),
                       let longitude = nativeCoordinateNumber(detail, keys: ["MeetingLongitude"]),
                       let coordinate = MapCoordinate.wgs84(latitude: latitude, longitude: longitude,
                           system: detail["MeetingCoordinateSystem"] as? String ?? "") {
                        NativeCoordinateMapCard(title: "集合点位置", name: detail["Name"] as? String ?? "旅游线路集合点",
                            address: detail["MeetingPoint"] as? String, latitude: latitude, longitude: longitude,
                            coordinateSystem: detail["MeetingCoordinateSystem"] as? String ?? "")
                        Button {
                            var components = URLComponents()
                            components.scheme = "https"
                            components.host = "maps.apple.com"
                            components.queryItems = [
                                URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
                                URLQueryItem(name: "q", value: detail["MeetingPoint"] as? String ?? detail["Name"] as? String ?? "集合地点"),
                            ]
                            if let url = components.url { openURL(url) }
                        } label: {
                            Label("打开地图导航", systemImage: "arrow.triangle.turn.up.right.diamond")
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .foregroundStyle(Brand.primary)
                                .background(Brand.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    let introductionHtml = detail["ContentHtml"] as? String ?? ""
                    let introduction = plainTextFromHTML(introductionHtml)
                    let introductionHasImages = nativeHTMLBlocks(introductionHtml, api: MobileAPI(store: store)).contains {
                        if case .image = $0 { return true }; return false
                    }
                    if !introduction.isEmpty || introductionHasImages {
                        Text("线路介绍").font(.headline)
                        NativeHTMLContent(html: introductionHtml, store: store)
                    } else if let description = detail["Description"] as? String, !description.isEmpty {
                        Text("线路介绍").font(.headline)
                        Text(description)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("选择出行班期").font(.headline).foregroundStyle(Brand.ink)
                        if availabilityStale {
                            Text(loading ? "正在刷新线路场次与价格…" : "线路场次刷新失败，当前价格和余量仅供参考；刷新成功前不能预订。")
                                .font(.caption).foregroundStyle(.orange)
                            Button("重试刷新场次和价格") { revision += 1 }
                                .buttonStyle(.bordered).disabled(loading || busy || pendingIdempotencyKey != nil)
                        }
                        if bookingEnabled {
                            if !availabilityStale {
                                Button("刷新场次和价格") { revision += 1 }
                                    .buttonStyle(.bordered).disabled(loading || busy || pendingIdempotencyKey != nil)
                            }
                            let guestLimit = min(20, max(1, (selectedSession?["AvailableCount"] as? NSNumber)?.intValue ?? 20))
                            Stepper("出行人数：\(guestCount) 人", value: $guestCount, in: 1...guestLimit)
                                .disabled(busy || loading || availabilityStale || pendingIdempotencyKey != nil || selectedSession == nil)
                                .onChange(of: guestCount) { _, _ in pointsToUse = "0"; revision += 1 }
                            if availableSessions.isEmpty {
                                Text("当前人数暂无可预订班期，请调整人数或稍后刷新。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(Array(availableSessions.enumerated()), id: \.offset) { _, session in
                                let sessionID = session["Id"] as? String ?? ""
                                let seats = (session["AvailableCount"] as? NSNumber)?.intValue ?? 0
                                let unitPrice = nativeTravelRouteOrderAmount(session["Price"], guestCount: 1)
                                Button {
                                    selectedSessionID = sessionID
                                    guestCount = min(guestCount, min(20, max(1, seats)))
                                    pointsToUse = "0"
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(bookingBusinessDateTime(session["DepartureDate"]) ?? "出发日期待确认")
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(unitPrice.map { "¥\(String(format: "%.2f", $0))/人" } ?? "价格待确认")
                                                .foregroundStyle(Brand.primary).font(.subheadline.weight(.semibold))
                                        }
                                        Text("余位 \(seats) · 最低成团 \((session["MinGroupSize"] as? Int) ?? 0) 人 · \(session["GroupStatus"] as? String == "Ready" ? "已成团" : "至少 \((session["MinGroupSize"] as? Int) ?? 0) 人成团")")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text("报名截止：\(String((session["SaleEndTime"] as? String ?? "").replacingOccurrences(of: "T", with: " ").prefix(16)))")
                                            .font(.caption2).foregroundStyle(.secondary)
                                        let cancellation = session["CancellationMode"] as? String ?? ""
                                        Text(cancellation == "FreeBeforeDeparture"
                                            ? "免费取消截止：出发前 \((session["FreeCancellationBeforeHours"] as? Int) ?? 0) 小时；截止前可免费取消，逾期提交申请审核"
                                            : "取消申请由平台审核退款")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(11)
                                    .background(selectedSessionID == sessionID ? Brand.primary.opacity(0.08) : Brand.background,
                                        in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                        selectedSessionID == sessionID ? Brand.primary : Brand.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain).disabled(busy || loading || availabilityStale || pendingIdempotencyKey != nil)
                            }
                            if let session = selectedSession {
                                let orderAmount = nativeTravelRouteOrderAmount(session["Price"], guestCount: guestCount)
                                if let orderAmount {
                                    Text("订单金额以服务端创建回执为准；当前参考金额 ¥\(String(format: "%.2f", orderAmount))")
                                        .font(.caption).foregroundStyle(.secondary)
                                    TextField("本次使用积分（默认 0）", text: $pointsToUse)
                                        .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                        .disabled(busy || loading || availabilityStale || pendingIdempotencyKey != nil || pointsBalance == nil
                                            || (pointsDebt.map { $0 > 0 } ?? true) || pointsSummaryError)
                                        .onChange(of: pointsToUse) { _, value in pointsToUse = String(value.filter { $0 >= "0" && $0 <= "9" }.prefix(16)) }
                                    pointsStatusText
                                    Text("100 积分抵 1 元，最多抵订单金额的 50%；仅人民币订单可使用，余额和最终抵扣以服务端核验为准。")
                                        .font(.caption2).foregroundStyle(.secondary)
                                } else {
                                    Text("当前场次价格或订单金额暂不可确认，请重新查询。")
                                        .font(.caption).foregroundStyle(.orange)
                                    Button("刷新线路场次和价格") { revision += 1 }
                                        .buttonStyle(.bordered).disabled(busy || loading)
                                }
                                Button(busy ? "正在创建订单并准备支付…" : (store.session == nil ? "登录后预订" : "确认预订并支付")) {
                                    Task { await createRouteOrder() }
                                }
                                .buttonStyle(.borderedProminent).tint(Brand.primary)
                                .disabled(busy || pendingIdempotencyKey != nil || loading || availabilityStale || orderAmount == nil
                                    || guestCount > ((session["AvailableCount"] as? NSNumber)?.intValue ?? 0))
                            }
                        } else {
                            Text("旅游线路预订暂未开放；仍可浏览线路资料。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if bookingEnabled {
                            Text("下单后将预留名额 15 分钟；各班期按单独配置的取消/退款规则处理，订单会保存所选班期规则。")
                                .font(.caption2).foregroundStyle(.secondary)
                            Button("查看我的线路订单　›") { showOrders = true }
                                .buttonStyle(.bordered).tint(Brand.primary)
                                .accessibilityLabel("查看我的旅游线路订单")
                        }
                        if pendingIdempotencyKey != nil {
                            Text("上次预订结果尚未确认，请先核对本人旅游线路订单；确认前暂不能提交新请求。")
                                .font(.caption).foregroundStyle(.orange)
                            Button("重新核对上次预订") { revision += 1 }
                                .buttonStyle(.bordered).disabled(loading || busy)
                            Button("查看本人旅游线路订单") { showOrders = true }.buttonStyle(.bordered)
                        }
                        if let bookingNotice { Text(bookingNotice).font(.caption).foregroundStyle(Brand.primary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    ForEach(Array((detail["Days"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { index, day in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("第 \(day["DayNumber"] as? Int ?? index + 1) 天 · \(day["Title"] as? String ?? "行程安排")")
                                .font(.headline)
                            if let description = day["Description"] as? String, !description.isEmpty { Text(description) }
                            let dayDetails = [day["MealInfo"] as? String, day["StayInfo"] as? String]
                                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            if !dayDetails.isEmpty {
                                Text(dayDetails.joined(separator: " · ")).font(.subheadline).foregroundStyle(Brand.muted)
                            }
                            ForEach(Array((day["Stops"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { stopIndex, stop in
                                let stopName = stop["Name"] as? String ?? "行程点位"
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(stopIndex + 1). \(stopName)")
                                    if let description = stop["Description"] as? String, !description.isEmpty {
                                        Text(description).font(.subheadline).foregroundStyle(Brand.muted)
                                    }
                                    if let scenicID = stop["ScenicResourceId"] as? String,
                                       let numericID = Int64(scenicID), numericID > 0, String(numericID) == scenicID {
                                        Button("景点详情 ›") {
                                            selectedScenicResource = ResourceItem(["Id": scenicID, "Name": stopName])
                                        }
                                        .buttonStyle(.bordered).tint(Brand.primary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let includes = detail["IncludesText"] as? String, !includes.isEmpty {
                        Text("费用包含").font(.headline); Text(includes)
                    }
                    if let excludes = detail["ExcludesText"] as? String, !excludes.isEmpty {
                        Text("费用不含").font(.headline); Text(excludes)
                    }
                    if let notice = detail["NoticeText"] as? String, !notice.isEmpty {
                        Text("出行须知").font(.headline); Text(notice)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
        .background(Brand.background)
        .navigationTitle("线路详情")
        .navigationBarBackButtonHidden(true)
        .simultaneousGesture(DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard value.startLocation.x <= 32, horizontal >= 72,
                      horizontal > abs(vertical) * 1.25 else { return }
                dismiss()
            })
        .sheet(isPresented: $showOrders, onDismiss: { if pendingIdempotencyKey == nil { revision += 1 } }) {
            NativeBookingOrdersView(store: store, initialKind: "route")
        }
        .sheet(item: $selectedScenicResource) { item in
            NavigationStack { ResourceDetailView(store: store, item: item) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && detail != nil && pendingIdempotencyKey == nil { revision += 1 }
        }
        .onChange(of: store.session?.accessToken) { _, _ in
            pendingIdempotencyKey = nil; bookingNotice = nil; pointsToUse = "0"; busy = false; revision += 1
            pointsBalance = nil; pointsDebt = nil; pointsSummaryError = false
        }
        .task(id: "\(store.session?.accessToken ?? "")-\(pointsSummaryRevision)") { await loadPointsSummary() }
        .task(id: revision) {
            let hadCurrentDetail = detail != nil
            pointsToUse = "0"
            loading = true; error = nil
            if hadCurrentDetail { availabilityStale = true }
            if !hadCurrentDetail { bookingEnabled = false }
            do {
                guard !id.isEmpty, id.allSatisfy(\.isNumber) else { throw MobileAPIError.unavailable("线路编号无效") }
                guard await MobileAPI(store: store).featureEnabled("MODULE-TRAVEL-ROUTE") else {
                    throw MobileAPIError.unavailable("旅游线路暂未开放")
                }
                bookingEnabled = await MobileAPI(store: store).featureEnabled("F-DST-002")
                let loaded = try await MobileAPI(store: store).getPublicCached(
                    "/api/JHCTITravelRoute/GetPublicDetail?id=\(id)&guests=1", forceRefresh: revision > 0) as? [String: Any]
                guard let loaded, nativeTravelRouteDetailIsValid(loaded, expectedID: id) else {
                    throw MobileAPIError.unavailable("线路资料格式异常，请重试")
                }
                detail = loaded
                availabilityStale = false
                let available = (loaded["Sessions"] as? [[String: Any]] ?? []).filter {
                    (($0["AvailableCount"] as? NSNumber)?.intValue ?? 0) > 0
                }
                if !available.contains(where: { $0["Id"] as? String == selectedSessionID }) {
                    selectedSessionID = available.first?["Id"] as? String ?? ""
                }
                let seatLimit = (available.first { $0["Id"] as? String == selectedSessionID }?["AvailableCount"] as? NSNumber)?.intValue
                guestCount = min(guestCount, min(20, max(1, seatLimit ?? 1)))
                if let token = store.session?.accessToken {
                    let storageKey = Self.recoveryStorageKey(accessToken: token)
                    let savedAmountText = UserDefaults.standard.string(forKey: storageKey + ".amountCents")
                    let savedAmountCents = savedAmountText.flatMap(Int64.init).flatMap { $0 >= 0 ? $0 : nil }
                    let savedRequestSnapshot = UserDefaults.standard.string(forKey: storageKey + ".requestSnapshot")
                    if let saved = UserDefaults.standard.string(forKey: storageKey),
                       saved.range(of: "^[A-Za-z0-9._:-]{16,100}$", options: .regularExpression) != nil {
                        pendingIdempotencyKey = saved
                        do {
                            let recovered = try await MobileAPI(store: store).get(
                                "/api/JHCTITravelRouteBooking/GetMyOrderByIdempotencyKey?idempotencyKey=\(saved)", authenticated: true,
                                expectedPrincipal: nativeTourismPrincipal(token)
                            ) as? [String: Any]
                            guard store.session?.accessToken == token else { return }
                            let recoveryMatches: Bool
                            if let savedRequestSnapshot {
                                recoveryMatches = recovered.map { nativeTravelRouteOrderRecoverySnapshotMatches($0, snapshotText: savedRequestSnapshot) } ?? false
                            } else {
                                recoveryMatches = recovered.map {
                                    $0["RouteId"] as? String == id
                                        && nativePointsOrderSnapshotMatches($0, expectedAmountCents: savedAmountCents)
                                } ?? false
                            }
                            if (savedAmountText == nil || savedAmountCents != nil), let recovered,
                               Self.validID(recovered["Id"]) != nil, recoveryMatches {
                                UserDefaults.standard.removeObject(forKey: storageKey)
                                UserDefaults.standard.removeObject(forKey: storageKey + ".amountCents")
                                UserDefaults.standard.removeObject(forKey: storageKey + ".requestSnapshot")
                                pendingIdempotencyKey = nil; bookingNotice = "已找回上次线路订单，请核对本人订单状态。"; showOrders = true
                            } else if let recovered, Self.validID(recovered["Id"]) != nil {
                                bookingNotice = "上次线路订单与保存的预订内容不一致；恢复编号已保留，请核对本人线路订单后再继续。"
                                showOrders = true
                            }
                        } catch is CancellationError {
                            return
                        } catch {
                            guard store.session?.accessToken == token else { return }
                            bookingNotice = "上次线路预订结果仍待核对；请先查看本人订单，确认前暂不能提交新请求。"
                        }
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
                availabilityStale = hadCurrentDetail
            }
            loading = false
        }
    }

    @ViewBuilder private var pointsStatusText: some View {
        if store.session == nil {
            Text("登录后查看可用积分。").font(.caption).foregroundStyle(.secondary)
        } else if let pointsDebt, pointsDebt > 0 {
            Text("存在积分欠额（\(pointsDebt)），当前不能抵扣；后续积分奖励将优先抵扣欠额。")
                .font(.caption).foregroundStyle(.orange)
        } else if let pointsBalance, pointsDebt == 0 {
            Text("可用积分：\(pointsBalance)").font(.caption).foregroundStyle(.secondary)
        } else if pointsSummaryError {
            Text("积分余额暂时无法读取，当前不能使用积分；仍可按 0 积分预订。")
                .font(.caption).foregroundStyle(.secondary)
            Button("重新读取积分余额") { pointsSummaryRevision += 1 }
                .font(.caption).disabled(pendingIdempotencyKey != nil)
        } else {
            Text("正在读取积分余额…").font(.caption).foregroundStyle(.secondary)
        }
    }

    @MainActor private func loadPointsSummary() async {
        let requestRevision = pointsSummaryRevision
        pointsBalance = nil; pointsDebt = nil; pointsSummaryError = false
        guard let token = store.session?.accessToken else {
            pointsBalance = nil; pointsDebt = nil; pointsSummaryError = false; pointsToUse = "0"
            return
        }
        do {
            guard let summary = try await MobileAPI(store: store).get(
                "/api/JHCTIMemberProgram/GetMySummary", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any],
                  let balanceText = nativeMemberLedgerString(summary, "PointsBalance"),
                  let balance = Int64(balanceText), balance >= 0,
                  let debtText = nativeMemberLedgerString(summary, "PointsDebt"),
                  let debt = Int64(debtText), debt >= 0,
                  store.session?.accessToken == token, pointsSummaryRevision == requestRevision else {
                throw MobileAPIError.unavailable("积分摘要无效")
            }
            pointsBalance = debt > 0 ? 0 : balance
            pointsDebt = debt
            pointsSummaryError = false
            if debt > 0 { pointsToUse = "0" }
        } catch {
            guard store.session?.accessToken == token, pointsSummaryRevision == requestRevision else { return }
            pointsBalance = nil; pointsDebt = nil; pointsSummaryError = true; pointsToUse = "0"
        }
    }

    @MainActor private func createRouteOrder() async {
        guard !availabilityStale else {
            bookingNotice = "线路场次和价格尚未刷新成功，请重试后预订。"
            return
        }
        guard !busy, pendingIdempotencyKey == nil, bookingEnabled,
              let token = store.session?.accessToken, let session = selectedSession,
              let sessionID = Self.validID(session["Id"]), guestCount > 0,
              guestCount <= ((session["AvailableCount"] as? NSNumber)?.intValue ?? 0) else {
            bookingNotice = store.session == nil ? "请先在个人中心登录，再返回此页预订。" : "班期余量已变化，请刷新后重新选择。"
            return
        }
        guard let points = Int64(pointsToUse), points >= 0 else { error = "积分数量必须为非负整数。"; return }
        if points > 0 {
            guard !pointsSummaryError, let pointsBalance, let pointsDebt else {
                error = "积分余额尚未确认，当前不能使用积分。请刷新后重试。"; return
            }
            guard pointsDebt == 0 else { error = "存在积分欠额，当前不能抵扣；后续积分奖励将优先抵扣欠额。"; return }
            guard points <= pointsBalance else { error = "使用积分超过当前可用余额，请调整后重试。"; return }
        }
        guard let estimatedAmount = nativeTravelRouteOrderAmount(session["Price"], guestCount: guestCount),
              let expectedAmountCents = nativeMoneyCents(estimatedAmount) else {
            error = "当前班期价格无法安全核对，请刷新后重试。"; return
        }
        guard points == 0 || points <= maximumPointsForHalfAmount(estimatedAmount) else {
            error = "积分数量超出当前线路金额估算上限，请调整后重试。"; return
        }
        busy = true
        defer { busy = false }
        let latestBookingEnabled = await MobileAPI(store: store).featureEnabled("F-DST-002", forceRefresh: true)
        guard store.session?.accessToken == token else { bookingNotice = "登录账号已变化，请重新确认后预订。"; return }
        bookingEnabled = latestBookingEnabled
        guard latestBookingEnabled else {
            bookingNotice = "旅游线路预订已关闭或暂时无法确认，本次没有提交订单。"
            return
        }
        let key = UUID().uuidString
        let storageKey = Self.recoveryStorageKey(accessToken: token)
        let amountStorageKey = storageKey + ".amountCents"
        let requestSnapshotStorageKey = storageKey + ".requestSnapshot"
        let requestSnapshot: [String: Any] = [
            "RouteId": id, "SessionId": sessionID, "GuestCount": guestCount,
            "PointsToUse": String(points), "AmountCents": String(expectedAmountCents)
        ]
        guard let requestSnapshotData = try? JSONSerialization.data(withJSONObject: requestSnapshot, options: [.sortedKeys]),
              let requestSnapshotText = String(data: requestSnapshotData, encoding: .utf8) else {
            error = "无法保存订单恢复快照，本次未提交。"; return
        }
        UserDefaults.standard.set(key, forKey: storageKey)
        UserDefaults.standard.set(String(expectedAmountCents), forKey: amountStorageKey)
        UserDefaults.standard.set(requestSnapshotText, forKey: requestSnapshotStorageKey)
        guard UserDefaults.standard.string(forKey: storageKey) == key,
              UserDefaults.standard.string(forKey: amountStorageKey) == String(expectedAmountCents),
              UserDefaults.standard.string(forKey: requestSnapshotStorageKey) == requestSnapshotText else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: amountStorageKey)
            UserDefaults.standard.removeObject(forKey: requestSnapshotStorageKey)
            error = "无法保存订单恢复编号与价格快照，本次未提交。"; return
        }
        pendingIdempotencyKey = key; error = nil
        var orderCreated = false
        do {
            let response = try await MobileAPI(store: store).post("/api/JHCTITravelRouteBooking/CreateOrder", body: [
                "SessionId": sessionID, "GuestCount": guestCount, "PointsToUse": String(points), "IdempotencyKey": key
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any]
            guard store.session?.accessToken == token, let response,
                  Self.validID(response["Id"]) != nil, response["RouteId"] as? String == id,
                  response["SessionId"] as? String == sessionID,
                  nativeBookingReceiptIntegerMatches(response["GuestCount"], expected: guestCount),
                  response["Status"] as? String == "PendingPayment",
                  ((response["PointsUsed"] as? String).flatMap(Int64.init)
                    ?? (response["PointsUsed"] as? NSNumber)?.int64Value) == points,
                  nativePointsOrderSnapshotMatches(response, expectedPoints: points, expectedAmountCents: expectedAmountCents) else {
                throw MobileAPIError.unavailable("订单已提交但回执不完整；请先核对本人旅游线路订单。")
            }
            orderCreated = true
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: amountStorageKey)
            UserDefaults.standard.removeObject(forKey: requestSnapshotStorageKey); pendingIdempotencyKey = nil
            let orderID = response["Id"] as? String ?? ""
            guard let expectedCashCents = nativeMoneyCents(response["CashPayableAmount"]) else {
                throw MobileAPIError.unavailable("订单现金应付金额无法确认，已转至本人线路订单核对。")
            }
            guard let payment = try await MobileAPI(store: store).post(
                "/api/JHCTITravelRouteBooking/CreateOrderPayment", body: [
                    "OrderId": orderID, "Provider": "alipay", "Scene": "wap"
                ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any], store.session?.accessToken == token else {
                throw MobileAPIError.unavailable("支付回执无效或登录状态已变化，已转至本人线路订单继续处理。")
            }
            guard let approvalURL = nativeAlipayPaymentApprovalURL(
                payment, expectedCashCents: expectedCashCents, expectedCurrency: "CNY") else {
                throw MobileAPIError.unavailable("支付金额、状态或跳转地址回执无效，已转至本人线路订单核对。")
            }
            try requireNativePaymentLaunchDeadline(response["PaymentExpiresAt"])
            guard store.session?.accessToken == token else {
                throw MobileAPIError.unavailable("登录账号已变化，请在本人线路订单核对。")
            }
            let opened = await withCheckedContinuation { continuation in
                openURL(approvalURL) { accepted in continuation.resume(returning: accepted) }
            }
            guard opened else { throw MobileAPIError.unavailable("设备未能打开支付宝页面，请前往本人线路订单继续支付。") }
            bookingNotice = "已打开支付宝支付页面。完成后返回此页并刷新线路订单状态。"
        } catch is CancellationError {
            return
        } catch {
            guard store.session?.accessToken == token else { return }
            if orderCreated {
                bookingNotice = "订单已创建；支付暂未打开，请前往本人线路订单继续支付。"
                showOrders = true
                return
            }
            do {
                let recovered = try await MobileAPI(store: store).get(
                    "/api/JHCTITravelRouteBooking/GetMyOrderByIdempotencyKey?idempotencyKey=\(key)", authenticated: true,
                    expectedPrincipal: nativeTourismPrincipal(token)
                ) as? [String: Any]
                guard store.session?.accessToken == token else { return }
                if let recovered, Self.validID(recovered["Id"]) != nil,
                   nativeTravelRouteOrderRecoverySnapshotMatches(recovered, snapshotText: requestSnapshotText) {
                    UserDefaults.standard.removeObject(forKey: storageKey)
                    UserDefaults.standard.removeObject(forKey: amountStorageKey)
                    UserDefaults.standard.removeObject(forKey: requestSnapshotStorageKey); pendingIdempotencyKey = nil
                    bookingNotice = "已找回本次线路订单，请在本人旅游线路订单中继续。"; showOrders = true
                } else { self.error = "预订结果暂未确认；恢复编号已保留，请核对本人订单，勿重复提交。" }
            } catch { self.error = "预订结果暂未确认；恢复编号已保留，请稍后核对本人订单，勿重复提交。" }
        }
    }

    private static func validID(_ raw: Any?) -> String? {
        guard let value = raw as? String, let id = Int64(value), id > 0 else { return nil }
        return value
    }

    private static func recoveryStorageKey(accessToken: String) -> String {
        let parts = accessToken.split(separator: ".")
        var subject: String?
        if parts.count == 3 {
            var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            if let data = Data(base64Encoded: payload),
               let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                subject = (claims["sub"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            }
        }
        let principal = subject ?? SHA256.hash(data: Data(accessToken.utf8)).map { String(format: "%02x", $0) }.joined()
        let hash = SHA256.hash(data: Data(principal.utf8)).map { String(format: "%02x", $0) }.joined()
        return "jhcti.native.route-order-attempt.v1.\(hash)"
    }
}



private func nativeTravelRouteDetailIsValid(_ value: [String: Any], expectedID: String) -> Bool {
    func positiveID(_ raw: Any?) -> String? {
        guard let text = raw as? String, text.range(of: "^[1-9][0-9]*$", options: .regularExpression) != nil,
              let id = Int64(text), id > 0 else { return nil }
        return text
    }
    func optionalText(_ raw: Any?) -> Bool { raw == nil || raw is NSNull || raw is String }
    func integer(_ raw: Any?, minimum: Int, maximum: Int) -> Int? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value.rounded(.towardZero) == value,
              value >= Double(minimum), value <= Double(maximum) else { return nil }
        return Int(value)
    }
    func numeric(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    func cancellation(_ mode: Any?, _ hoursRaw: Any?) -> Bool {
        guard let hours = integer(hoursRaw, minimum: 0, maximum: 8760) else { return false }
        switch mode as? String {
        case "ManualReview": return hours == 0
        case "FreeBeforeDeparture": return hours > 0
        default: return false
        }
    }
    guard positiveID(expectedID) == expectedID, positiveID(value["Id"]) == expectedID,
          let name = value["Name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let destination = value["Destination"] as? String, !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          optionalText(value["Summary"]), optionalText(value["Description"]), optionalText(value["ContentHtml"]),
          value["MeetingPoint"] is String, optionalText(value["IncludesText"]), optionalText(value["ExcludesText"]),
          optionalText(value["NoticeText"]),
          let coordinateSystem = value["MeetingCoordinateSystem"] as? String,
          ["Unknown", "WGS84", "GCJ02", "BD09"].contains(coordinateSystem),
          let duration = integer(value["DurationDays"], minimum: 1, maximum: 30),
          cancellation(value["CancellationMode"], value["FreeCancellationBeforeHours"]),
          let media = value["MediaUrls"] as? [Any], (1...20).contains(media.count), media.allSatisfy({ $0 is String }),
          let days = value["Days"] as? [[String: Any]], days.count == duration,
          let sessions = value["Sessions"] as? [[String: Any]] else { return false }

    let longitudeRaw = value["MeetingLongitude"]
    let latitudeRaw = value["MeetingLatitude"]
    let longitudeNull = longitudeRaw == nil || longitudeRaw is NSNull
    let latitudeNull = latitudeRaw == nil || latitudeRaw is NSNull
    guard longitudeNull == latitudeNull else { return false }
    if !longitudeNull {
        guard let longitude = numeric(longitudeRaw), (-180...180).contains(longitude),
              let latitude = numeric(latitudeRaw), (-90...90).contains(latitude) else { return false }
    }

    var dayIDs = Set<String>()
    var dayNumbers = Set<Int>()
    var stopIDs = Set<String>()
    for day in days {
        guard let dayID = positiveID(day["Id"]), dayIDs.insert(dayID).inserted,
              let dayNumber = integer(day["DayNumber"], minimum: 1, maximum: duration), dayNumbers.insert(dayNumber).inserted,
              let title = day["Title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              optionalText(day["Description"]), optionalText(day["StayInfo"]), optionalText(day["MealInfo"]),
              let stops = day["Stops"] as? [[String: Any]] else { return false }
        for stop in stops {
            guard let stopID = positiveID(stop["Id"]), stopIDs.insert(stopID).inserted,
                  let scenicID = stop["ScenicResourceId"] as? String,
                  scenicID.range(of: "^(0|[1-9][0-9]*)$", options: .regularExpression) != nil,
                  Int64(scenicID) != nil, let stopName = stop["Name"] as? String,
                  !stopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  optionalText(stop["Description"]) else { return false }
        }
    }

    var sessionIDs = Set<String>()
    for session in sessions {
        guard let sessionID = positiveID(session["Id"]), sessionIDs.insert(sessionID).inserted,
              bookingBusinessDateTime(session["DepartureDate"]) != nil,
              bookingBusinessDateTime(session["SaleEndTime"]) != nil,
              let price = numeric(session["Price"]), (0...99_999_999.99).contains(price),
              integer(session["AvailableCount"], minimum: 0, maximum: Int(Int32.max)) != nil,
              integer(session["MinGroupSize"], minimum: 1, maximum: Int(Int32.max)) != nil,
              let status = session["GroupStatus"] as? String,
              ["Gathering", "Ready", "Confirmed", "Refunding", "Cancelled"].contains(status),
              cancellation(session["CancellationMode"], session["FreeCancellationBeforeHours"]) else { return false }
    }
    return true
}
