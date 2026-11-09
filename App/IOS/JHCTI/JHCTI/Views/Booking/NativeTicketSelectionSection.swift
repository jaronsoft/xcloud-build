import SwiftUI

struct NativeTicketSelectionSection: View {
    let tickets: [[String: Any]]
    let sessions: [[String: Any]]
    let selectionLocked: Bool
    let pendingOrder: Bool
    let submitting: Bool
    let maximumQuantity: Int
    let dailyQuotaRemaining: Int?
    let dailyQuotaLoading: Bool
    let dailyQuotaError: String?
    let formatMoney: (Any?) -> String
    let formatDate: (String) -> String
    let onRetryDailyQuota: () -> Void

    @Binding var ticketId: String
    @Binding var sessionId: String
    @Binding var quantity: Int

    private var selectedTicket: [String: Any]? { tickets.first { $0["Id"] as? String == ticketId } }

    var body: some View {
        Group {
            Section("选择票种") {
                Picker("门票", selection: $ticketId) {
                    Text("请选择票种").tag("")
                    ForEach(Array(tickets.enumerated()), id: \.offset) { _, ticket in
                        let bundleItems = ticket["BundleItems"] as? [[String: Any]] ?? []
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(ticket["Name"] as? String ?? "景区门票") · ¥\(formatMoney(ticket["Price"]))")
                            Text("每单 \(ticket["MinPerOrder"] as? Int ?? 1)–\(ticket["MaxPerOrder"] as? Int ?? 1) 张 · 每人每日限购 \(ticket["MaxPerUserPerDay"] as? Int ?? 1) 张")
                                .font(.caption).foregroundStyle(.secondary)
                            if let description = ticket["Description"] as? String, !description.isEmpty {
                                Text(description).font(.caption).foregroundStyle(.secondary)
                            }
                            if ticket["TicketKind"] as? String == "Bundle", !bundleItems.isEmpty {
                                Text("套票包含项目 · 一张凭证一次核销全部项目")
                                    .font(.caption.weight(.semibold))
                                ForEach(Array(bundleItems.enumerated()), id: \.offset) { _, item in
                                    let name = item["Name"] as? String ?? "项目"
                                    let itemQuantity = item["Quantity"] as? Int ?? 1
                                    let itemDescription = item["Description"] as? String ?? ""
                                    Text("\(name) × \(itemQuantity)\(itemDescription.isEmpty ? "" : " · \(itemDescription)")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tag(ticket["Id"] as? String ?? "")
                    }
                }
                .disabled(selectionLocked)
                if let policy = selectedTicket?["RefundDescription"] as? String, !policy.isEmpty {
                    Text("退款说明：\(policy)").font(.footnote).foregroundStyle(.secondary)
                } else if let policy = selectedTicket?["RefundPolicy"] as? String, !policy.isEmpty {
                    Text("退款规则：\(policy)").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("选择入园场次") {
                if sessions.isEmpty { Text("当前票种没有可选场次，请切换票种或稍后刷新。") }
                else {
                    Picker("场次", selection: $sessionId) {
                        Text("请选择入园场次").tag("")
                        ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                            Text("\(session["Name"] as? String ?? "入园场次") · \(formatDate(session["StartTime"] as? String ?? ""))–\(formatDate(session["EndTime"] as? String ?? "")) · 余 \(session["RemainingInventory"] as? Int ?? 0)")
                                .tag(session["Id"] as? String ?? "")
                        }
                    }
                    .disabled(selectionLocked)
                    let configuredMinimum = selectedTicket?["MinPerOrder"] as? Int ?? 1
                    let minimum = max(1, configuredMinimum)
                    Stepper("数量：\(quantity)", value: $quantity,
                            in: minimum...max(minimum, maximumQuantity))
                        .disabled(selectionLocked || dailyQuotaRemaining == nil || maximumQuantity < configuredMinimum)
                    if !pendingOrder {
                        if dailyQuotaLoading { ProgressView("正在核对本人该入园日期的限购额度…") }
                        else if let remaining = dailyQuotaRemaining {
                            Text("本人该入园日期还可购 \(remaining) 张 · 每日限额 \(selectedTicket?["MaxPerUserPerDay"] as? Int ?? 0) 张")
                                .font(.footnote).foregroundStyle(Brand.muted)
                            if remaining < configuredMinimum {
                                Text("剩余限额不足最低购买数量，请更换票种或入园日期。")
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                        }
                        if let dailyQuotaError {
                            Text(dailyQuotaError).font(.footnote).foregroundStyle(.red)
                            Button("重新查询限购额度", action: onRetryDailyQuota).disabled(submitting)
                        }
                    }
                    let unitPrice = (selectedTicket?["Price"] as? NSNumber)?.doubleValue ?? 0
                    Text("单价 ¥\(formatMoney(selectedTicket?["Price"])) · 合计 ¥\(formatMoney(unitPrice * Double(quantity)))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}
