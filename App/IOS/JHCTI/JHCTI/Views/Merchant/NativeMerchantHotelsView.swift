import Foundation
import CoreFoundation
import SwiftUI

private struct MerchantHotelDraft {
    var price = ""
    var roomCount = ""
    var isClosed = false
}

struct MerchantHotelsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let merchantID: String
    @State private var hotels: [[String: Any]] = []
    @State private var rooms: [[String: Any]] = []
    @State private var hotelID = ""
    @State private var roomID = ""
    @State private var stayDate = Calendar(identifier: .gregorian).startOfDay(for: Date())
    @State private var inventory: [String: Any]?
    @State private var loadedSelection: String?
    @State private var draft = MerchantHotelDraft()
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var revision = 0
    @State private var requestSequence = 0
    @State private var showingSaveConfirmation = false

    private var businessCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }
    private var businessToday: Date { businessCalendar.startOfDay(for: Date()) }
    private var selection: String { "\(hotelID):\(roomID):\(dateText)" }
    private var dateText: String {
        let formatter = DateFormatter()
        formatter.calendar = businessCalendar
        formatter.timeZone = businessCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: stayDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("维护授权酒店未来房价、房间总数和关闭状态；保存时服务端复核权限、版本及已预留数。")
                    .font(.caption).foregroundStyle(Brand.muted)
                VStack(alignment: .leading, spacing: 10) {
                    Text("酒店").font(.headline)
                    if hotels.isEmpty {
                        Text(loading ? "正在读取授权酒店…" : "当前商户暂无可维护酒店。")
                            .font(.subheadline).foregroundStyle(Brand.muted)
                    } else {
                        Picker("酒店", selection: $hotelID) {
                            ForEach(hotels.indices, id: \.self) { index in
                                Text(Self.text(hotels[index]["Name"] ?? hotels[index]["name"]).isEmpty ? "未命名酒店" : Self.text(hotels[index]["Name"] ?? hotels[index]["name"]))
                                    .tag(Self.text(hotels[index]["Id"] ?? hotels[index]["id"]))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Text("房型").font(.headline)
                    if rooms.isEmpty {
                        Text("读取酒店后显示；没有启用房型时请先在管理端维护。")
                            .font(.caption).foregroundStyle(Brand.muted)
                    } else {
                        Picker("房型", selection: $roomID) {
                            ForEach(rooms.indices, id: \.self) { index in
                                Text(Self.text(rooms[index]["Name"] ?? rooms[index]["name"]).isEmpty ? "未命名房型" : Self.text(rooms[index]["Name"] ?? rooms[index]["name"]))
                                    .tag(Self.text(rooms[index]["Id"] ?? rooms[index]["id"]))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    DatePicker("住宿日期", selection: $stayDate,
                               in: businessToday...businessCalendar.date(byAdding: .day, value: 29, to: businessToday)!,
                               displayedComponents: .date)
                        .environment(\.calendar, businessCalendar)
                }
                .merchantCard()
                .disabled(saving)
                StatusView(loading: loading, error: error) { revision += 1 }
                if !loading && error == nil && !rooms.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(selectedRoomName) · \(dateText)").font(.headline)
                        Text(inventory == nil ? "该日期尚无房态记录，保存后创建。" : "已预留 \(Self.intValue(inventory?["ReservedCount"] ?? inventory?["reservedCount"])) 间")
                            .font(.caption).foregroundStyle(Brand.muted)
                        TextField("每晚价格（元）", text: $draft.price)
                            .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).disabled(saving)
                        TextField("房间总数", text: $draft.roomCount)
                            .keyboardType(.numberPad).textFieldStyle(.roundedBorder).disabled(saving)
                        Toggle("关闭当日预订", isOn: $draft.isClosed).disabled(saving)
                        Text("关闭后游客无法预订此房型当晚。")
                            .font(.caption).foregroundStyle(Brand.muted)
                        Button(saving ? "保存中…" : "保存当日房态") { prepareSave() }
                            .buttonStyle(.borderedProminent).tint(Brand.primary)
                            .disabled(saving || roomID.isEmpty)
                    }
                    .merchantCard()
                }
            }
            .padding(16)
        }
        .background(Brand.background)
        .navigationTitle("酒店房态")
        .task(id: revision) { await load() }
        .onChange(of: store.session?.accessToken) { _, _ in dismiss() }
        .onChange(of: hotelID) { _, _ in Task { await load() } }
        .onChange(of: roomID) { _, _ in Task { await load() } }
        .onChange(of: stayDate) { _, _ in Task { await load() } }
        .confirmationDialog("保存酒店房态", isPresented: $showingSaveConfirmation, titleVisibility: .visible) {
            Button("确认保存") { Task { await save() } }.disabled(saving)
            Button("取消", role: .cancel) { showingSaveConfirmation = false }
        } message: {
            Text("确认保存“\(selectedHotelName) · \(selectedRoomName) · \(dateText)”的房价、房间总数和关闭状态？服务端会重新校验已预留数量和版本。")
        }
    }

    private var selectedHotelName: String {
        hotels.first(where: { Self.text($0["Id"] ?? $0["id"]) == hotelID }).map { Self.text($0["Name"] ?? $0["name"]) } ?? "酒店"
    }
    private var selectedRoomName: String {
        rooms.first(where: { Self.text($0["Id"] ?? $0["id"]) == roomID }).map { Self.text($0["Name"] ?? $0["name"]) } ?? "房型"
    }

    private func load() async {
        guard !merchantID.isEmpty, merchantID.allSatisfy(\.isNumber),
              let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else {
            error = "商户范围或登录状态无效，请返回工作台重新进入。"; loading = false; return
        }
        requestSequence += 1
        let sequence = requestSequence
        loading = true; error = nil; inventory = nil; loadedSelection = nil
        defer { if requestSequence == sequence { loading = false } }
        do {
            if hotels.isEmpty {
                guard let response = try await MobileAPI(store: store).get(
                    "/api/JHCTIHotel/GetPage?page=1&pageSize=100&merchantId=\(merchantID)", authenticated: true,
                    expectedPrincipal: expectedPrincipal) as? [String: Any],
                    let loaded = response["data"] as? [[String: Any]] ?? response["Data"] as? [[String: Any]] else {
                    throw MobileAPIError.unavailable("酒店分页响应格式异常，请重试。")
                }
                guard loaded.allSatisfy({ !Self.text($0["Id"] ?? $0["id"]).isEmpty }) else {
                    throw MobileAPIError.unavailable("酒店编号缺失，请刷新后重试。")
                }
                guard requestSequence == sequence, store.session?.accessToken == token else { return }
                hotels = loaded
                if hotelID.isEmpty || !loaded.contains(where: { Self.text($0["Id"] ?? $0["id"]) == hotelID }) {
                    hotelID = loaded.first.map { Self.text($0["Id"] ?? $0["id"]) } ?? ""
                }
            }
            guard let hotel = hotels.first(where: { Self.text($0["Id"] ?? $0["id"]) == hotelID }) else {
                rooms = []; error = "当前商户暂无可维护酒店。"; return
            }
            guard Self.validID(Self.field(hotel, "Id") as? String) else { throw MobileAPIError.unavailable("酒店编号无效。") }
            guard let detailResponse = try await MobileAPI(store: store).get(
                "/api/JHCTIHotel/GetById?id=\(hotelID)", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any] else {
                throw MobileAPIError.unavailable("酒店详情响应格式异常，请重试。")
            }
            let detail = detailResponse["data"] as? [String: Any] ?? detailResponse["Data"] as? [String: Any] ?? detailResponse
            guard Self.field(detail, "Id") as? String == hotelID,
                  Self.field(detail, "MerchantId") as? String == merchantID else {
                throw MobileAPIError.unavailable("酒店详情与所选商户不匹配。")
            }
            let loadedRooms = (detail["RoomTypes"] as? [[String: Any]] ?? detail["roomTypes"] as? [[String: Any]] ?? [])
                .filter { Self.boolValue($0["IsEnabled"] ?? $0["isEnabled"], default: true) }
            guard requestSequence == sequence, store.session?.accessToken == token else { return }
            rooms = loadedRooms
            if roomID.isEmpty || !loadedRooms.contains(where: { Self.text($0["Id"] ?? $0["id"]) == roomID }) {
                roomID = loadedRooms.first.map { Self.text($0["Id"] ?? $0["id"]) } ?? ""
            }
            guard !loadedRooms.isEmpty else { error = "该酒店暂无启用房型，请先在管理端维护房型。"; return }
            let date = dateText
            let selectedRoomID = roomID
            guard Self.validID(selectedRoomID) else { throw MobileAPIError.unavailable("房型编号无效。") }
            let selectedScope = selection
            let escapedDate = date.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? date
            let inventoryResponse = try await MobileAPI(store: store).get(
                "/api/JHCTIHotel/GetInventory?hotelId=\(hotelID)&from=\(escapedDate)&to=\(escapedDate)", authenticated: true,
                expectedPrincipal: expectedPrincipal)
            let inventoryDictionary = inventoryResponse as? [String: Any]
            guard let inventoryRows = inventoryResponse as? [[String: Any]]
                ?? inventoryDictionary?["data"] as? [[String: Any]] ?? inventoryDictionary?["Data"] as? [[String: Any]],
                inventoryRows.allSatisfy({ Self.validInventoryRow($0, date: date) }) else {
                throw MobileAPIError.unavailable("房态回执格式或日期异常，请重新读取。")
            }
            let matches = inventoryRows.filter { ($0["RoomTypeId"] ?? $0["roomTypeId"]) as? String == selectedRoomID }
            guard matches.count <= 1 else { throw MobileAPIError.unavailable("当日房态异常，请重新读取。") }
            let found = matches.first
            guard requestSequence == sequence, store.session?.accessToken == token, selection == selectedScope else { return }
            inventory = found
            loadedSelection = selectedScope
            draft = MerchantHotelDraft(price: found.map { Self.text($0["Price"] ?? $0["price"]) } ?? "",
                                       roomCount: found.map { Self.text($0["RoomCount"] ?? $0["roomCount"]) } ?? "",
                                       isClosed: found.map { Self.boolValue($0["IsClosed"] ?? $0["isClosed"]) } ?? false)
        } catch is CancellationError {
            return
        } catch {
            guard requestSequence == sequence, store.session?.accessToken == token else { return }
            self.error = error.localizedDescription
        }
    }

    private func prepareSave() {
        let priceText = draft.price.trimmingCharacters(in: .whitespacesAndNewlines)
        guard priceText.range(of: "^(0|[1-9][0-9]*)(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let price = Decimal(string: priceText), let maxPrice = Decimal(string: "99999999.99"), price >= 0, price <= maxPrice else {
            error = "请输入 0 至 99999999.99 元、最多两位小数的房价。"; return
        }
        let countText = draft.roomCount.trimmingCharacters(in: .whitespacesAndNewlines)
        let reserved = Self.intValue(inventory?["ReservedCount"] ?? inventory?["reservedCount"])
        guard countText.range(of: "^(0|[1-9][0-9]*)$", options: .regularExpression) != nil,
              let count = Int(countText), (0...2_000_000_000).contains(count), (0...2_000_000_000).contains(reserved), count >= reserved else {
            error = "房间总数须为 0 至 2000000000，且不低于已预留数 \(reserved)。"; return
        }
        showingSaveConfirmation = true
    }

    private func save() async {
        guard !saving, !loading, error == nil, loadedSelection == selection, let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token),
              let price = Decimal(string: draft.price.trimmingCharacters(in: .whitespacesAndNewlines)),
              let count = Int(draft.roomCount.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let selectedHotelID = hotelID
        let selectedRoomID = roomID
        let selectedScope = selection
        let sequence = requestSequence
        let body: [String: Any] = [
            "InventoryId": (inventory?["Id"] ?? inventory?["id"]) as? String ?? "0",
            "CreateOnly": inventory == nil,
            "RoomTypeId": roomID,
            "Version": inventory.flatMap(Self.inventoryVersion) ?? 0,
            "StayDate": dateText,
            "Price": NSDecimalNumber(decimal: price),
            "RoomCount": count,
            "IsClosed": draft.isClosed
        ]
        saving = true; error = nil
        defer { saving = false; showingSaveConfirmation = false }
        do {
            let receipt = try await MobileAPI(store: store).post("/api/JHCTIHotel/SaveInventory?hotelId=\(selectedHotelID)", body: body, authenticated: true,
                expectedPrincipal: expectedPrincipal)
            guard receipt as? String == selectedRoomID else { throw MobileAPIError.unavailable("保存回执与所选房型不匹配") }
            guard store.session?.accessToken == token, selection == selectedScope, requestSequence == sequence else { return }
            await load()
            if error != nil { error = "房态已保存，但刷新失败；请重新读取确认当前状态。" }
        } catch is CancellationError {
            if store.session?.accessToken == token, selection == selectedScope, requestSequence == sequence {
                error = "房态保存结果未确认；请重新读取版本后再操作。"
            }
        } catch {
            if store.session?.accessToken == token, selection == selectedScope, requestSequence == sequence {
                self.error = "\(error.localizedDescription)；请重新读取版本后再试。"
            }
        }
    }

    private static func validID(_ value: String?) -> Bool {
        guard let value, let number = Int64(value), number > 0 else { return false }
        return String(number) == value
    }
    private static func field(_ row: [String: Any], _ key: String) -> Any? {
        let camel = key.prefix(1).lowercased() + String(key.dropFirst())
        if let left = row[key], let right = row[camel] {
            let lhs = try? JSONSerialization.data(withJSONObject: left, options: [.fragmentsAllowed])
            let rhs = try? JSONSerialization.data(withJSONObject: right, options: [.fragmentsAllowed])
            if lhs == nil || lhs != rhs { return nil }
        }
        return row[key] ?? row[camel]
    }

    private static func validInventoryRow(_ row: [String: Any], date: String) -> Bool {
        guard validID(field(row, "Id") as? String), validID(field(row, "RoomTypeId") as? String),
              inventoryVersion(row) != nil,
              let price = field(row, "Price") as? NSNumber, CFGetTypeID(price) != CFBooleanGetTypeID(),
              let closed = field(row, "IsClosed") as? NSNumber, CFGetTypeID(closed) == CFBooleanGetTypeID(),
              let count = inventoryInteger(field(row, "RoomCount")), let reserved = inventoryInteger(field(row, "ReservedCount")),
              reserved <= count, count <= Int(Int32.max) else { return false }
        return bookingBusinessDateTime(field(row, "StayDate")).map { String($0.prefix(10)) } == date
    }

    private static func inventoryVersion(_ row: [String: Any]) -> Int? {
        inventoryInteger(field(row, "Version"))
    }

    private static func inventoryInteger(_ raw: Any?) -> Int? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue >= 0, value.doubleValue <= 9_007_199_254_740_991,
              value.doubleValue.rounded(.towardZero) == value.doubleValue else { return nil }
        return value.intValue
    }

    private static func text(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return value as? String ?? String(describing: value)
    }
    private static func intValue(_ value: Any?) -> Int {
        guard let value, !(value is NSNull) else { return 0 }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }
    private static func boolValue(_ value: Any?, default fallback: Bool = false) -> Bool {
        guard let value, !(value is NSNull) else { return fallback }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return (string as NSString).boolValue }
        return fallback
    }
}
