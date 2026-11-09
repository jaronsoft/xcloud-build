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
    let isSubmitting: Bool
    let isCancelling: Bool
    let reservationsLoading: Bool
    let reservations: [[String: Any]]
    let notice: String?
    let pendingCancelID: String
    let onDateChanged: () -> Void
    let onRetry: () -> Void
    let onSelectSlot: ([String: Any]) -> Void
    let onSubmit: () -> Void
    let onRequestCancel: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("到店预订").font(.headline).foregroundStyle(Brand.ink)
            Text("选择日期、时段和人数，提交后由门店确认；当前不收取预付款。")
                .font(.caption).foregroundStyle(Brand.muted)
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
                    if let notice { Text(notice).font(.caption).foregroundStyle(Brand.primary) }
                    Button(isSubmitting ? "正在提交…" : "提交预订申请", action: onSubmit)
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                        .disabled(isSubmitting || isLoading || !hasSelectedSlot)
                    Text("提交后为待确认申请；撤回待处理申请会释放名额。")
                        .font(.caption2).foregroundStyle(Brand.muted)
                }
            }
            if isAuthenticated { myReservations }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var myReservations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("我的本店预订").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
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
                        Button(isCancelling && pendingCancelID == reservationID ? "正在撤回…" : "撤回待处理申请", role: .destructive) {
                            onRequestCancel(reservationID)
                        }
                        .disabled(isCancelling)
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

    private static func statusName(_ value: String) -> String {
        ["Pending": "待商户确认", "Confirmed": "已确认", "Declined": "已拒绝", "Cancelled": "已撤回或取消"][value] ?? "状态更新中"
    }
}
