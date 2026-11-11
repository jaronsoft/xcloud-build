import SwiftUI
import CryptoKit

private func dialableHotelPhoneURL(_ value: String) -> URL? {
    let normalized = value.replacingOccurrences(of: "[\\s()（）-]", with: "", options: .regularExpression)
    guard normalized.range(of: "^\\+?[0-9]{5,20}$", options: .regularExpression) != nil else { return nil }
    return URL(string: "tel:\(normalized)")
}

private enum HotelBusinessDate {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }

    static func offset(_ days: Int, from date: Date? = nil) -> Date {
        let value = calendar
        let start = value.startOfDay(for: date ?? Date())
        return value.date(byAdding: .day, value: days, to: start) ?? start
    }
}

private struct HotelDateField: View {
    let title: String
    @Binding var selection: Date
    let range: ClosedRange<Date>
    @State private var isPickerPresented = false

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = HotelBusinessDate.timeZone
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: selection)
    }

    var body: some View {
        Button { isPickerPresented = true } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(title).foregroundStyle(Brand.ink)
                    Spacer(minLength: 8)
                    Text(formattedDate).fontWeight(.medium).foregroundStyle(Brand.primary)
                        .lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
                    Image(systemName: "calendar").foregroundStyle(Brand.muted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption).foregroundStyle(Brand.muted)
                    HStack {
                        Text(formattedDate).fontWeight(.medium).foregroundStyle(Brand.primary)
                        Spacer()
                        Image(systemName: "calendar").foregroundStyle(Brand.muted)
                    }
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPickerPresented) {
            NavigationStack {
                DatePicker(title, selection: $selection, in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.calendar, HotelBusinessDate.calendar)
                    .environment(\.timeZone, HotelBusinessDate.timeZone)
                    .padding()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { isPickerPresented = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct HotelPublicDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let store: SessionStore
    let id: String
    @State private var detail: [String: Any]?
    @State private var error: String?
    @State private var bookingNotice: String?
    @State private var loading = true
    @State private var revision = 0
    @State private var checkIn = HotelBusinessDate.offset(1)
    @State private var checkOut = HotelBusinessDate.offset(2)
    @State private var guestCount = 1
    @State private var roomCounts: [String: Int] = [:]
    @State private var pointsByRoom: [String: String] = [:]
    @State private var pointsBalance: Int64?
    @State private var pointsDebt: Int64?
    @State private var pointsSummaryError = false
    @State private var pointsSummaryRevision = 0
    @State private var contactName = ""
    @State private var contactPhone = ""
    @State private var bookingEnabled = false
    @State private var busyRoomId = ""
    @State private var showOrders = false
    @State private var pendingIdempotencyKey: String?
    @State private var loadedQueryKey = ""

    private var checkInText: String { Self.businessDate(checkIn) }
    private var checkOutText: String { Self.businessDate(checkOut) }
    private var currentQueryKey: String { "\(checkInText)|\(checkOutText)|\(guestCount)" }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let detail {
                            NativeProductGallery(store: store, detail: detail, fallback: catalogCover(detail),
                                                 imageLabel: "酒店", height: 320,
                                                 fallbackAsset: "Quick3", fallbackLabel: "江都住宿主题插画")
                            .overlay(alignment: .top) {
                                LinearGradient(colors: [.white.opacity(0.68), .white.opacity(0)],
                                               startPoint: .top, endPoint: .bottom)
                                    .frame(height: 150).allowsHitTesting(false)
                            }
                            .padding(.horizontal, -16)
                            .padding(.top, -16)
                            Text(detail["Name"] as? String ?? "酒店民宿")
                        .font(.title2.bold()).foregroundStyle(Brand.ink)
                    if let summary = detail["Description"] as? String, !summary.isEmpty {
                        Text(plainTextFromHTML(summary)).foregroundStyle(.secondary)
                    }
                    if let address = detail["Address"] as? String, !address.isEmpty {
                        detailCard("地址", address)
                    }
                    NativeCoordinateMapCard(title: "酒店位置", name: detail["Name"] as? String ?? "酒店民宿",
                        address: detail["Address"] as? String,
                        latitude: (detail["Latitude"] as? NSNumber)?.doubleValue,
                        longitude: (detail["Longitude"] as? NSNumber)?.doubleValue,
                        coordinateSystem: detail["CoordinateSystem"] as? String ?? "")
                    let hotelCheckInTime = detail["CheckInTime"] as? String ?? "14:00"
                    let hotelCheckOutTime = detail["CheckOutTime"] as? String ?? "12:00"
                    detailCard("入住与离店", "\(hotelCheckInTime) 入住 · \(hotelCheckOutTime) 离店")
                    if let phone = detail["Phone"] as? String, !phone.isEmpty {
                        HStack {
                            Text("联系电话").foregroundStyle(Brand.muted)
                            Spacer()
                            if let url = dialableHotelPhoneURL(phone) {
                                Link("\(phone)　拨打 ›", destination: url).foregroundStyle(Brand.primary)
                                    .accessibilityLabel("拨打住宿联系电话 \(phone)")
                            } else {
                                Text(phone).foregroundStyle(Brand.ink).textSelection(.enabled)
                            }
                        }
                        .font(.system(size: NativeTypography.size(14)))
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    let trimmedHotelName = (detail["Name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let normalizedHotelName = trimmedHotelName.isEmpty ? "江都住宿" : trimmedHotelName
                    let shareTitle = trimmedHotelName.isEmpty ? normalizedHotelName : "\(trimmedHotelName)｜江都文旅"
                    let shareStayQuery = bookingEnabled
                        ? "&checkIn=\(checkInText)&checkOut=\(checkOutText)&guests=\(guestCount)" : ""
                    ShareLink(
                        item: "https://travel.jiangdu.net/subpackages/hotel/index?id=\(id)\(shareStayQuery)",
                        subject: Text(shareTitle),
                        message: Text("查看住宿：\(normalizedHotelName)")
                    ) {
                        Label(bookingEnabled ? "分享住宿与当前查询条件" : "分享住宿", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(Brand.primary)
                            .background(Brand.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("查询房态与价格").font(.headline).foregroundStyle(Brand.ink)
                        if bookingEnabled {
                            HotelDateField(title: "入住日期", selection: $checkIn,
                                range: HotelBusinessDate.offset(0)...HotelBusinessDate.offset(365))
                                .onChange(of: checkIn) { _, value in
                                    pointsByRoom = [:]
                                    if value >= checkOut {
                                        checkOut = HotelBusinessDate.offset(1, from: value)
                                    } else if (HotelBusinessDate.calendar.dateComponents([.day], from: value, to: checkOut).day ?? 0) > 30 {
                                        checkOut = HotelBusinessDate.offset(30, from: value)
                                    }
                                    revision += 1
                                }
                            HotelDateField(title: "离店日期", selection: $checkOut,
                                range: HotelBusinessDate.offset(1, from: checkIn)...HotelBusinessDate.offset(30, from: checkIn))
                                .onChange(of: checkOut) { _, _ in pointsByRoom = [:]; revision += 1 }
                            HStack(spacing: 10) {
                                Text("入住人数").foregroundStyle(Brand.ink).lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: 8)
                                Button { guestCount = max(1, guestCount - 1); pointsByRoom = [:] } label: {
                                    Image(systemName: "minus").frame(width: 36, height: 36)
                                }
                                .buttonStyle(.bordered).disabled(guestCount <= 1)
                                Text("\(guestCount) 位").monospacedDigit().frame(minWidth: 42)
                                Button { guestCount = min(20, guestCount + 1); pointsByRoom = [:] } label: {
                                    Image(systemName: "plus").frame(width: 36, height: 36)
                                }
                                .buttonStyle(.bordered).disabled(guestCount >= 20)
                            }
                            .onChange(of: guestCount) { _, _ in pointsByRoom = [:]; revision += 1 }
                            Button(loading ? "正在查询…" : "查询所选日期") { revision += 1 }
                                .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(loading)
                            if store.session == nil {
                                Text("请先在个人中心登录并完成手机号验证，再提交预订。")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                TextField("入住联系人姓名", text: $contactName).textContentType(.name)
                                    .textFieldStyle(.roundedBorder).disabled(pendingIdempotencyKey != nil)
                                TextField("联系电话（可含 + 国际区号）", text: $contactPhone).textContentType(.telephoneNumber)
                                    .keyboardType(.phonePad).textFieldStyle(.roundedBorder).disabled(pendingIdempotencyKey != nil)
                            }
                        } else {
                            Text("酒店预订暂未开放；仍可浏览住宿资料。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if pendingIdempotencyKey != nil {
                            Text("上次预订结果尚未确认，请先通过本人住宿订单核对；确认前暂不能提交新请求。")
                                .font(.caption).foregroundStyle(.orange)
                            Button("重新核对上次预订") { revision += 1 }
                                .buttonStyle(.bordered).disabled(loading || !busyRoomId.isEmpty)
                            Button("查看本人住宿订单") { showOrders = true }
                                .buttonStyle(.bordered)
                        }
                        if let bookingNotice { Text(bookingNotice).font(.caption).foregroundStyle(Brand.primary) }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    let amenities = detail["Amenities"] as? [String] ?? []
                    if !amenities.isEmpty { detailCard("配套设施", amenities.joined(separator: " · ")) }
                    if let html = detail["ContentHtml"] as? String {
                        let hasContent = !plainTextFromHTML(html).isEmpty || nativeHTMLBlocks(html, api: MobileAPI(store: store)).contains {
                            if case .image = $0 { return true }; return false
                        }
                        if hasContent {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("住宿介绍").font(.headline).foregroundStyle(Brand.ink)
                                NativeHTMLContent(html: html, store: store)
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    let rooms = detail["RoomTypes"] as? [[String: Any]] ?? []
                    if !rooms.isEmpty {
                        Text("房型信息").font(.headline).foregroundStyle(Brand.ink)
                        ForEach(Array(rooms.enumerated()), id: \.offset) { entry in
                            let room = entry.element
                            VStack(alignment: .leading, spacing: 7) {
                                if let cover = MobileAPI(store: store).mediaURL(catalogCover(room)) {
                                    CachedRemoteImage(url: cover) { Image("Quick3").resizable().scaledToFill() }
                                        .frame(maxWidth: .infinity).frame(height: 150).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    NativeThemeCover(imageName: "Quick3", label: "江都住宿主题插画")
                                        .frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Text(room["Name"] as? String ?? "房型").font(.headline)
                                let facts = [room["BedType"] as? String,
                                             (room["AreaSqm"] as? NSNumber).map { "\($0)㎡" },
                                             (room["MaxGuests"] as? Int).map { "最多入住 \($0) 人" },
                                             (room["BreakfastCount"] as? Int).map { "含早 \($0) 份" }].compactMap { $0 }.filter { !$0.isEmpty }
                                if !facts.isEmpty { Text(facts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                                if let description = room["Description"] as? String, !description.isEmpty {
                                    Text(plainTextFromHTML(description)).font(.subheadline)
                                }
                                if let price = room["MinPrice"] as? NSNumber, price.doubleValue >= 0 {
                                    Text("参考起价 ¥\(price.stringValue)/晚").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.primary)
                                }
                                let roomId = Self.validID(room["Id"])
                                let available = (room["AvailableRooms"] as? NSNumber)?.intValue ?? 0
                                let stayNights = Calendar.current.dateComponents([.day], from: checkIn, to: checkOut).day ?? 0
                                let hasStayPrice = room["TotalStayPrice"] != nil && !(room["TotalStayPrice"] is NSNull)
                                let stayPrice = hasStayPrice
                                    ? nativeMoneyCents(room["TotalStayPrice"]).map { Double($0) / 100 }
                                    : (room["MinPrice"] as? NSNumber).flatMap { price in
                                        guard price.doubleValue >= 0, stayNights > 0 else { return nil }
                                        return nativeMoneyCents(price.doubleValue * Double(stayNights)).map { Double($0) / 100 }
                                    }
                                let roomCount = min(max(1, roomId.flatMap { roomCounts[$0] } ?? 1), min(10, max(0, available)))
                                let estimatedStayPrice = stayPrice.flatMap { perRoom in
                                    nativeMoneyCents(perRoom * Double(roomCount)).map { Double($0) / 100 }
                                }
                                if bookingEnabled {
                                    if available <= 0 {
                                        Text("所选日期暂无可订房间").font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text("所选日期可订 \(available) 间").font(.caption).foregroundStyle(.secondary)
                                    }
                                    if available > 0, stayNights > 0, let stayPrice, let estimatedStayPrice {
                                        Text("入住 \(stayNights) 晚 · 每间 ¥\(stayPrice, specifier: "%.2f") × \(roomCount) 间，预计 ¥\(estimatedStayPrice, specifier: "%.2f")\(hasStayPrice ? "" : "（按起价估算）")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else if available > 0 {
                                        Text("所选日期总价暂不可估算，请刷新房态后重试。")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if let roomId, available > 0, bookingEnabled {
                                    Stepper("预订间数：\(min(max(1, roomCounts[roomId] ?? 1), min(10, available))) 间",
                                        value: Binding(get: { min(max(1, roomCounts[roomId] ?? 1), min(10, available)) },
                                            set: { roomCounts[roomId] = $0; pointsByRoom[roomId] = "0" }), in: 1...min(10, available))
                                    let capacity = max(1, (room["MaxGuests"] as? NSNumber)?.intValue ?? 1)
                                    Text("本房型最多接待 \(capacity * min(max(1, roomCounts[roomId] ?? 1), min(10, available))) 位")
                                        .font(.caption).foregroundStyle(.secondary)
                                    TextField("本次使用积分（默认 0）", text: Binding(
                                        get: { pointsByRoom[roomId] ?? "0" },
                                        set: { pointsByRoom[roomId] = String($0.filter { $0 >= "0" && $0 <= "9" }.prefix(16)) }))
                                        .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                        .disabled(store.session == nil || pointsBalance == nil || (pointsDebt.map { $0 > 0 } ?? true)
                                            || pointsSummaryError || pendingIdempotencyKey != nil || loadedQueryKey != currentQueryKey)
                                    pointsStatusText
                                    Text("100 积分抵 1 元，最多抵订单金额的 50%；仅人民币订单可使用，余额和最终抵扣以服务端核验为准。")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Button(busyRoomId == roomId ? "正在创建订单并准备支付…" : "确认预订并支付") {
                                        Task { await createHotelOrder(room: room) }
                                    }
                                    .buttonStyle(.borderedProminent).tint(Brand.primary)
                                    .disabled(loading || loadedQueryKey != currentQueryKey || pendingIdempotencyKey != nil || busyRoomId.isEmpty == false
                                        || guestCount > capacity * min(max(1, roomCounts[roomId] ?? 1), min(10, available)))
                                } else if bookingEnabled {
                                    Text("所选日期暂无可订房间").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    let cancellationMode = detail["CancellationMode"] as? String ?? ""
                    let cancellationPolicy = detail["CancellationPolicy"] as? String
                    if (cancellationPolicy?.isEmpty == false) || !cancellationMode.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("取消政策").font(.headline).foregroundStyle(Brand.ink)
                            let freeBeforeCheckIn = cancellationMode == "FreeBeforeCheckIn"
                            Text(freeBeforeCheckIn
                                ? "按结构化规则，免费取消截止时间为入住前 \((detail["FreeCancellationBeforeHours"] as? NSNumber)?.intValue ?? 0) 小时；截止前可申请免费取消，并按原支付渠道全额退款。"
                                : "按结构化规则，取消需联系酒店或平台客服，由酒店人工确认；系统不会自动取消或退款。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let policy = cancellationPolicy, !policy.isEmpty {
                                Text(freeBeforeCheckIn ? "酒店补充说明（实际处理以结构化规则为准）"
                                     : "酒店补充说明（仅供参考，须联系酒店确认）")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(plainTextFromHTML(policy)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                            Text("当前页面仅展示已发布住宿资料；房态、价格与预订以开放的服务端功能为准。")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            StatusView(loading: loading, error: error) { revision += 1 }
                        }
                    }
                    .padding(16).frame(width: geometry.size.width, alignment: .leading)
                }
                .background(Brand.background)
                .ignoresSafeArea(edges: .top)

            }
        }
        .background(Brand.background)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .simultaneousGesture(DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard !showOrders, value.startLocation.x <= 32,
                      horizontal >= 72, horizontal > abs(vertical) * 1.25 else { return }
                dismiss()
            })
        .sheet(isPresented: $showOrders) { NativeBookingOrdersView(store: store, initialKind: "hotel") }
        .onChange(of: store.session?.accessToken) { _, _ in
            contactName = ""; contactPhone = ""; pendingIdempotencyKey = nil; roomCounts = [:]; pointsByRoom = [:]; busyRoomId = ""
            pointsBalance = nil; pointsDebt = nil; pointsSummaryError = false
            revision += 1
        }
        .task(id: "\(store.session?.accessToken ?? "")-\(pointsSummaryRevision)") { await loadPointsSummary() }
        .task(id: "\(currentQueryKey)-\(revision)") {
            loading = true; error = nil; detail = nil
            do {
                guard !id.isEmpty, id.allSatisfy(\.isNumber) else { throw MobileAPIError.unavailable("住宿编号无效") }
                guard await MobileAPI(store: store).featureEnabled("MODULE-HOTEL") else {
                    throw MobileAPIError.unavailable("住宿模块暂未开放")
                }
                bookingEnabled = await MobileAPI(store: store).featureEnabled("F-DST-001", forceRefresh: true)
                let api = MobileAPI(store: store)
                let availability: [String: Any]?
                if bookingEnabled {
                    let availabilityPath = "/api/JHCTIHotel/GetPublicDetail?id=\(id)&checkIn=\(checkInText)T00:00:00&checkOut=\(checkOutText)T00:00:00&guests=\(guestCount)"
                    do {
                        availability = try await api.getPublicCached(availabilityPath, forceRefresh: true) as? [String: Any]
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        availability = nil
                    }
                } else {
                    availability = nil
                }
                let value: [String: Any]?
                if let availability { value = availability }
                else {
                    value = try await api.getPublicCached(
                        "/api/JHCTIHotel/GetPublicDetail?id=\(id)&guests=\(guestCount)", forceRefresh: true) as? [String: Any]
                }
                guard let value, value["Id"] as? String == id else { throw MobileAPIError.unavailable("住宿不存在、已下线或详情回执无效") }
                detail = value
                loadedQueryKey = availability == nil ? "" : currentQueryKey
                if let token = store.session?.accessToken {
                    let recoveryKey = Self.recoveryStorageKey(accessToken: token)
                    let savedAmountText = UserDefaults.standard.string(forKey: recoveryKey + ".amountCents")
                    let savedAmountCents = savedAmountText.flatMap(Int64.init).flatMap { $0 >= 0 ? $0 : nil }
                    let savedRequestSnapshot = UserDefaults.standard.string(forKey: recoveryKey + ".requestSnapshot")
                    if let saved = UserDefaults.standard.string(forKey: recoveryKey),
                   saved.range(of: "^[A-Za-z0-9._:-]{16,80}$", options: .regularExpression) != nil {
                        pendingIdempotencyKey = saved
                        do {
                            let recovered = try await MobileAPI(store: store).get(
                                "/api/JHCTIHotelBooking/GetMyOrderByIdempotencyKey?idempotencyKey=\(saved)", authenticated: true,
                                expectedPrincipal: nativeTourismPrincipal(token)
                            ) as? [String: Any]
                            guard store.session?.accessToken == token else { return }
                            let recoveryMatches: Bool
                            if let savedRequestSnapshot {
                                recoveryMatches = recovered.map { nativeHotelOrderRecoverySnapshotMatches($0, snapshotText: savedRequestSnapshot) } ?? false
                            } else {
                                recoveryMatches = recovered.map {
                                    $0["HotelId"] as? String == id
                                        && nativePointsOrderSnapshotMatches($0, expectedAmountCents: savedAmountCents)
                                } ?? false
                            }
                            if (savedAmountText == nil || savedAmountCents != nil), let recovered,
                               Self.validID(recovered["Id"]) != nil, recoveryMatches {
                                UserDefaults.standard.removeObject(forKey: recoveryKey)
                                UserDefaults.standard.removeObject(forKey: recoveryKey + ".amountCents")
                                UserDefaults.standard.removeObject(forKey: recoveryKey + ".requestSnapshot")
                                pendingIdempotencyKey = nil; bookingNotice = "已找回上次住宿订单，显示本人订单状态。"; showOrders = true
                            } else if let recovered, Self.validID(recovered["Id"]) != nil {
                                bookingNotice = "上次住宿订单与保存的预订内容不一致；恢复编号已保留，请核对本人住宿订单后再继续。"
                                showOrders = true
                            }
                        } catch is CancellationError {
                            return
                        } catch {
                            guard store.session?.accessToken == token else { return }
                            bookingNotice = "上次预订结果仍待核对；请先查看本人住宿订单，确认前暂不能提交新的预订。"
                        }
                    }
                }
            } catch is CancellationError {
                return
            } catch { self.error = error.localizedDescription }
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
            pointsBalance = nil; pointsDebt = nil; pointsSummaryError = false
            pointsByRoom = pointsByRoom.mapValues { _ in "0" }
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
            if debt > 0 { pointsByRoom = pointsByRoom.mapValues { _ in "0" } }
        } catch is CancellationError {
            return
        } catch {
            guard store.session?.accessToken == token, pointsSummaryRevision == requestRevision else { return }
            pointsBalance = nil; pointsDebt = nil; pointsSummaryError = true
            pointsByRoom = pointsByRoom.mapValues { _ in "0" }
        }
    }

    @MainActor private func createHotelOrder(room: [String: Any]) async {
        guard busyRoomId.isEmpty, bookingEnabled, loadedQueryKey == currentQueryKey,
              pendingIdempotencyKey == nil, let token = store.session?.accessToken,
              let roomId = Self.validID(room["Id"]), let available = (room["AvailableRooms"] as? NSNumber)?.intValue,
              available > 0 else { error = "请登录后重新查询有效房态。"; return }
        let roomCount = min(max(1, roomCounts[roomId] ?? 1), min(10, available))
        let capacity = max(1, (room["MaxGuests"] as? NSNumber)?.intValue ?? 1) * roomCount
        let name = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        guard name.count <= 80, !name.isEmpty, phone.range(of: "^\\+?[0-9]{6,24}$", options: .regularExpression) != nil,
              guestCount <= capacity, checkOut > checkIn,
              Calendar.current.dateComponents([.day], from: checkIn, to: checkOut).day.map({ (1...30).contains($0) }) == true else {
            error = "请检查联系人、联系电话、入住人数和 1 至 30 晚的入住日期。"; return
        }
        let pointsText = pointsByRoom[roomId] ?? "0"
        guard let points = Int64(pointsText), points >= 0 else { error = "积分数量必须为非负整数。"; return }
        if points > 0 {
            guard !pointsSummaryError, let pointsBalance, let pointsDebt else {
                error = "积分余额尚未确认，当前不能使用积分。请刷新后重试。"; return
            }
            guard pointsDebt == 0 else { error = "存在积分欠额，当前不能抵扣；后续积分奖励将优先抵扣欠额。"; return }
            guard points <= pointsBalance else { error = "使用积分超过当前可用余额，请调整后重试。"; return }
        }
        let nights = Calendar.current.dateComponents([.day], from: checkIn, to: checkOut).day ?? 0
        let perRoom = (room["TotalStayPrice"] as? NSNumber)?.doubleValue
            ?? ((room["MinPrice"] as? NSNumber)?.doubleValue ?? 0) * Double(max(0, nights))
        let estimatedAmount = perRoom * Double(roomCount)
        guard let expectedAmountCents = nativeMoneyCents(estimatedAmount, roundToCents: true) else {
            error = "当前房价无法安全核对，请刷新房态后重试。"; return
        }
        guard points == 0 || points <= maximumPointsForHalfAmount(estimatedAmount) else {
            error = "积分数量超出当前房价估算上限，请调整后重试。"; return
        }
        busyRoomId = roomId
        defer { busyRoomId = "" }
        let latestBookingEnabled = await MobileAPI(store: store).featureEnabled("F-DST-001", forceRefresh: true)
        guard store.session?.accessToken == token else { error = "登录账号已变化，请重新确认后预订。"; return }
        bookingEnabled = latestBookingEnabled
        guard latestBookingEnabled else {
            error = "酒店预订服务已关闭或暂时无法确认，本次没有提交订单。"
            return
        }
        let key = pendingIdempotencyKey ?? UUID().uuidString
        let storageKey = Self.recoveryStorageKey(accessToken: token)
        let amountStorageKey = storageKey + ".amountCents"
        let requestSnapshotStorageKey = storageKey + ".requestSnapshot"
        let requestSnapshot: [String: Any] = [
            "HotelId": id, "RoomTypeId": roomId, "CheckIn": checkInText, "CheckOut": checkOutText,
            "RoomCount": roomCount, "GuestCount": guestCount, "PointsToUse": String(points),
            "AmountCents": String(expectedAmountCents)
        ]
        guard let requestSnapshotData = try? JSONSerialization.data(withJSONObject: requestSnapshot, options: [.sortedKeys]),
              let requestSnapshotText = String(data: requestSnapshotData, encoding: .utf8) else {
            error = "无法保存预订恢复快照，本次未提交订单。"; return
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
            error = "无法保存预订恢复编号与价格快照，本次未提交订单。"; return
        }
        pendingIdempotencyKey = key; error = nil
        var orderCreated = false
        do {
            let response = try await MobileAPI(store: store).post("/api/JHCTIHotelBooking/CreateOrder", body: [
                "RoomTypeId": roomId, "CheckIn": "\(checkInText)T00:00:00", "CheckOut": "\(checkOutText)T00:00:00",
                "RoomCount": roomCount, "GuestCount": guestCount, "ContactName": name, "ContactPhone": phone,
                "PointsToUse": String(points), "IdempotencyKey": key
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any]
            guard store.session?.accessToken == token, let response,
                  Self.validID(response["Id"]) != nil, response["HotelId"] as? String == id,
                  response["RoomTypeId"] as? String == roomId,
                  Self.datePrefix(response["CheckIn"]) == checkInText,
                  Self.datePrefix(response["CheckOut"]) == checkOutText,
                  nativeBookingReceiptIntegerMatches(response["RoomCount"], expected: roomCount),
                  nativeBookingReceiptIntegerMatches(response["GuestCount"], expected: guestCount),
                  response["Status"] as? String == "PendingPayment",
                  ((response["PointsUsed"] as? String).flatMap(Int64.init)
                    ?? (response["PointsUsed"] as? NSNumber)?.int64Value) == points,
                  nativePointsOrderSnapshotMatches(response, expectedPoints: points, expectedAmountCents: expectedAmountCents) else {
                throw MobileAPIError.unavailable("订单已提交但回执不完整；请先核对本人住宿订单。")
            }
            orderCreated = true
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: amountStorageKey)
            UserDefaults.standard.removeObject(forKey: requestSnapshotStorageKey); pendingIdempotencyKey = nil
            guard let cashCents = nativeMoneyCents(response["CashPayableAmount"]) else {
                throw MobileAPIError.unavailable("订单现金应付金额无法确认，已转至本人住宿订单核对。")
            }
            guard let payment = try await MobileAPI(store: store).post("/api/JHCTIHotelBooking/CreateOrderPayment", body: [
                "OrderId": response["Id"] as? String ?? "", "Provider": "alipay", "Scene": "wap"
            ], authenticated: true, expectedPrincipal: nativeTourismPrincipal(token)) as? [String: Any],
                  store.session?.accessToken == token else {
                throw MobileAPIError.unavailable("支付回执无效或登录状态已变化，已转至本人住宿订单继续处理。")
            }
            guard let paymentURL = nativeAlipayPaymentApprovalURL(payment, expectedCashCents: cashCents,
                expectedCurrency: response["Currency"] as? String ?? "") else {
                throw MobileAPIError.unavailable("支付回执金额、状态或跳转地址不匹配，已转至本人住宿订单核对。")
            }
            try requireNativePaymentLaunchDeadline(response["PaymentExpiresAt"])
            guard store.session?.accessToken == token else {
                throw MobileAPIError.unavailable("登录账号已变化，请在本人住宿订单核对。")
            }
            let opened = await withCheckedContinuation { continuation in
                openURL(paymentURL) { accepted in continuation.resume(returning: accepted) }
            }
            guard opened else { throw MobileAPIError.unavailable("设备未能打开支付宝页面，请前往本人住宿订单继续支付。") }
            bookingNotice = "已打开支付宝支付页面。完成后返回此页并刷新住宿订单状态。"
        } catch is CancellationError {
            return
        } catch {
            guard store.session?.accessToken == token else { return }
            if orderCreated {
                bookingNotice = "订单已创建；支付暂未打开，请前往本人住宿订单继续支付。"
                showOrders = true
                return
            }
            do {
                let recovered = try await MobileAPI(store: store).get(
                    "/api/JHCTIHotelBooking/GetMyOrderByIdempotencyKey?idempotencyKey=\(key)", authenticated: true,
                    expectedPrincipal: nativeTourismPrincipal(token)
                ) as? [String: Any]
                guard store.session?.accessToken == token else { return }
                if let recovered, Self.validID(recovered["Id"]) != nil,
                   nativeHotelOrderRecoverySnapshotMatches(recovered, snapshotText: requestSnapshotText) {
                    UserDefaults.standard.removeObject(forKey: storageKey)
                    UserDefaults.standard.removeObject(forKey: amountStorageKey)
                    UserDefaults.standard.removeObject(forKey: requestSnapshotStorageKey); pendingIdempotencyKey = nil
                    bookingNotice = "已找回本次预订订单，请在本人住宿订单中继续。"; showOrders = true
                } else { self.error = "预订结果暂未确认；恢复编号已保留，请稍后重试核对，勿重复提交其他预订。" }
            } catch {
                self.error = "预订结果暂未确认；恢复编号已保留，请稍后重试核对，勿重复提交其他预订。"
            }
        }
    }

    private static func businessDate(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }

    private static func validID(_ raw: Any?) -> String? {
        guard let value = raw as? String, let id = Int64(value), id > 0 else { return nil }; return value
    }

    private static func datePrefix(_ raw: Any?) -> String? {
        guard let value = raw as? String, value.count >= 10 else { return nil }
        return String(value.prefix(10))
    }

    private static func recoveryStorageKey(accessToken: String) -> String {
        let parts = accessToken.split(separator: ".")
        var subject: String?
        var identityType = "SiteServer"
        if parts.count == 3 {
            var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            if let data = Data(base64Encoded: payload),
               let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                subject = (claims["sub"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                if claims["TourismIdentity"] as? String == "Tourism" { identityType = "Tourism" }
            }
        }
        let principal = subject.map { "\(identityType):\($0)" }
            ?? SHA256.hash(data: Data(accessToken.utf8)).map { String(format: "%02x", $0) }.joined()
        let hash = SHA256.hash(data: Data(principal.utf8)).map { String(format: "%02x", $0) }.joined()
        return "jhcti.native.hotel-order-attempt.v1.\(hash)"
    }

    private func detailCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
            Text(value).font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}
