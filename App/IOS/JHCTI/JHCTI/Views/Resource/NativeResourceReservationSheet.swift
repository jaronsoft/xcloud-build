import SwiftUI

struct NativeResourceReservationSheet: View {
    let item: ResourceItem
    let reservationDates: [[String: Any]]
    let reservationSessions: [[String: Any]]
    let hasReservationSessions: Bool
    let selectedReservationSession: [String: Any]?
    let reservationBusy: Bool
    let reservationRecoveryAvailable: Bool
    let reservationRecoveryChecked: Bool
    let reservationRecoveryBlocked: Bool
    let reservationError: String?
    let reservationReceipt: [String: Any]?
    let identityNumberValid: Bool
    let hasPendingReservation: (String, String) -> Bool
    let reservationStatus: ([String: Any]) -> String
    let onRecoverPendingReservation: () async -> Void
    let onSubmitReservation: () async -> Void

    @Binding var isPresented: Bool
    @Binding var reservationDate: String
    @Binding var reservationSessionId: String
    @Binding var reservationIdentityNumber: String
    @Binding var reservationIdentityConsent: Bool

    private var canSubmit: Bool {
        !reservationRecoveryChecked || reservationBusy || reservationRecoveryBlocked || reservationDate.isEmpty
            || (reservationRecoveryAvailable && !hasPendingReservation(hasReservationSessions ? reservationSessionId : "0", reservationDate))
            || (hasReservationSessions && !hasPendingReservation(reservationSessionId, reservationDate)
                && (selectedReservationSession == nil || (selectedReservationSession?["Available"] as? Int ?? 0) < 1))
            || (selectedReservationSession?["RequireIdentityNumber"] as? Bool == true
                && (!identityNumberValid || !reservationIdentityConsent))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let reservationReceipt {
                    let status = reservationReceipt["Status"] as? String ?? "Reserved"
                    let expired = isExpiredNativeTourismReservation(reservationReceipt)
                    Section(status == "Cancelled" ? "预约已取消" : status == "CheckedIn" ? "预约已核验" : "预约记录已确认") {
                        Text(reservationReceipt["ResourceName"] as? String ?? item.name).font(.headline)
                        Text("\(reservationReceipt["ReservationDate"] as? String ?? reservationDate) · \(reservationReceipt["SessionName"] as? String ?? "当日预约")")
                        Text("状态：\(reservationStatus(reservationReceipt))")
                        Text("预约记录已保存到“行程”。入园凭证可在行程页查看。")
                        Text(status == "Cancelled" ? "已取消 · 不可用于入园" : status == "CheckedIn" ? "已完成入园核验" : expired ? "预约已过期 · 入园凭证已失效" : "预约有效 · 入园凭证可在“行程”查看")
                    }
                } else {
                    Section("选择预约日期") {
                        if reservationDates.isEmpty { Text("当前没有可预约日期，请稍后刷新景点详情。") }
                        else {
                            Picker("预约日期", selection: $reservationDate) {
                                ForEach(Array(reservationDates.enumerated()), id: \.offset) { _, row in
                                    let date = row["Date"] as? String ?? ""
                                    Text("\(date) · \((row["IsReserved"] as? Bool == true) ? "已预约" : "余 \(row["Available"] as? Int ?? 0) 名")")
                                        .tag(date)
                                }
                            }
                            .disabled(reservationBusy)
                        }
                    }
                    if hasReservationSessions {
                        Section("选择预约场次") {
                            if reservationSessions.isEmpty { Text("所选日期暂无预约场次。") }
                            ForEach(Array(reservationSessions.enumerated()), id: \.offset) { _, session in
                                let sessionId = session["Id"] as? String ?? ""
                                let available = session["Available"] as? Int ?? 0
                                Button {
                                    reservationSessionId = sessionId
                                    reservationIdentityNumber = ""; reservationIdentityConsent = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(session["Name"] as? String ?? "预约场次")
                                            Text("\(session["StartTime"] as? String ?? "") · 剩余 \(available) 名")
                                                .font(.caption).foregroundStyle(Brand.muted)
                                        }
                                        Spacer(); if sessionId == reservationSessionId { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.primary) }
                                    }
                                }.disabled(!hasPendingReservation(sessionId, reservationDate)
                                    && (session["IsEnabled"] as? Bool == false || session["IsReserved"] as? Bool == true || available < 1))
                            }
                        }
                    }
                    if selectedReservationSession?["RequireIdentityNumber"] as? Bool == true {
                        Section("实名预约") {
                            Text("身份证号码将加密保存，并仅向本人展示脱敏信息。")
                                .font(.caption).foregroundStyle(Brand.muted)
                            TextField("18 位身份证号码", text: $reservationIdentityNumber)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled().keyboardType(.asciiCapable)
                                .disabled(reservationBusy)
                            Toggle("我同意将身份证号码用于本次预约和入园核验", isOn: $reservationIdentityConsent)
                                .disabled(reservationBusy)
                        }
                    }
                    if reservationRecoveryAvailable {
                        Section { Text("原预约结果尚未确认；请先选择原日期和场次核对，不能另建预约。").font(.caption) }
                    }
                    if let reservationError { Section { Text(reservationError).foregroundStyle(.red) } }
                    Section {
                        Button(reservationBusy ? "正在确认预约…" : "确认预约") { Task { await onSubmitReservation() } }
                            .disabled(canSubmit)
                    }
                }
            }
            .disabled(reservationBusy)
            .navigationTitle("免费预约")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(reservationReceipt == nil ? "关闭" : "完成") { isPresented = false }.disabled(reservationBusy) }
            }
        }
        .onChange(of: reservationDate) { _, _ in reservationSessionId = ""; reservationIdentityNumber = ""; reservationIdentityConsent = false }
        .interactiveDismissDisabled(reservationBusy)
        .task(id: isPresented) {
            if isPresented { await onRecoverPendingReservation() }
        }
    }

}
