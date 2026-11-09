import Foundation
import SwiftUI

struct MerchantFinancialReportView: View {
    let store: SessionStore
    let merchantID: String
    let roles: [[String: Any]]
    @State private var totals: [[String: Any]] = []
    @State private var items: [[String: Any]] = []
    @State private var couponReport: [String: Any] = [:]
    @State private var ticketReport: [String: Any] = [:]
    @State private var couponDetails: [[String: Any]] = []
    @State private var ticketDetails: [[String: Any]] = []
    @State private var couponDetailTotal = 0
    @State private var ticketDetailTotal = 0
    @State private var couponDetailLoading = false
    @State private var ticketDetailLoading = false
    @State private var activeReportMerchantID = ""
    @State private var reportRequestSequence = 0
    @State private var couponDetailsRequestSequence = 0
    @State private var ticketDetailsRequestSequence = 0
    @State private var loading = true
    @State private var error: String?
    @State private var revision = 0

    private func hasRole(_ codes: Set<String>, merchantWide: Bool = false) -> Bool {
        roles.contains {
            codes.contains($0["RoleCode"] as? String ?? "") &&
            (!merchantWide || ($0["StoreId"] as? String ?? "0") == "0")
        }
    }
    private var canReadSalesAndCoupons: Bool {
        hasRole(["MerchantAdmin", "ReportReadOnly"]) || hasRole(["FinanceReadOnly"], merchantWide: true)
    }
    private var canReadTicketReport: Bool {
        hasRole(["MerchantAdmin", "ReportReadOnly", "FinanceReadOnly"], merchantWide: true) ||
            hasRole(["TicketVerifier", "Verifier"])
    }

    private func businessDateRange() -> (from: String, to: String) {
        let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 60 * 60)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -29, to: end) ?? end
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: start), formatter.string(from: end))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("最近 30 天 · 按币种分别统计，不跨币种合计")
                    .font(.caption).foregroundStyle(Brand.muted)
                StatusView(loading: loading, error: error) { revision += 1 }
                if canReadSalesAndCoupons {
                    Text("销售与退款").font(.headline)
                }
                if canReadSalesAndCoupons && !loading && error == nil && totals.isEmpty {
                    Text("所选周期暂无已支付订单汇总。").foregroundStyle(Brand.muted)
                }
                ForEach(canReadSalesAndCoupons ? totals.indices : 0..<0, id: \.self) { index in
                    let row = totals[index]
                    VStack(alignment: .leading, spacing: 7) {
                        Text(row["Currency"] as? String ?? "—")
                            .font(.headline).foregroundStyle(Brand.primary)
                        Text("已支付订单  \(row["PaidOrderCount"] as? Int ?? 0) 笔")
                        Text("应付金额  \(String(describing: row["PayableAmount"] ?? "0.00"))")
                        Text("退款金额  \(String(describing: row["RefundedAmount"] ?? "0.00"))")
                        Text("订单净额  \(String(describing: row["NetPayableAmount"] ?? "0.00"))").fontWeight(.semibold)
                    }.font(.system(size: NativeTypography.size(14))).merchantCard()
                }
                if canReadSalesAndCoupons && !items.isEmpty {
                    Text("门店明细").font(.headline)
                    ForEach(items.indices, id: \.self) { index in
                        let row = items[index]
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row["StoreName"] as? String ?? "未归属门店")
                                .font(.system(size: NativeTypography.size(16), weight: .semibold))
                            Text("\(row["Currency"] as? String ?? "—") · \(row["PaidOrderCount"] as? Int ?? 0) 笔订单")
                                .font(.caption).foregroundStyle(Brand.muted)
                            Text("应付 \(String(describing: row["PayableAmount"] ?? "0.00"))  /  退款 \(String(describing: row["RefundedAmount"] ?? "0.00"))  /  净额 \(String(describing: row["NetPayableAmount"] ?? "0.00"))")
                                .font(.caption)
                        }.merchantCard()
                    }
                }
                if canReadSalesAndCoupons && !couponReport.isEmpty {
                    let summary = couponReport["Totals"] as? [String: Any] ?? couponReport["totals"] as? [String: Any] ?? [:]
                    Text("消费券核销").font(.headline)
                    VStack(alignment: .leading, spacing: 7) {
                        reportLine("核销", "\(summary["RedemptionCount"] ?? 0) 笔 · 优惠 \(summary["DiscountAmount"] ?? "0.00")")
                        reportLine("撤销", "\(summary["ReversalCount"] ?? 0) 笔 · 金额 \(summary["ReversalAmount"] ?? "0.00")")
                        reportLine("净值", "\(summary["NetRedemptionCount"] ?? 0) 笔 · 优惠 \(summary["NetDiscountAmount"] ?? "0.00")")
                    }.font(.system(size: NativeTypography.size(14))).merchantCard()
                    Button(couponDetails.isEmpty ? "查看消费券核销明细" : "刷新消费券核销明细") {
                        Task { await loadCouponDetails(reset: true) }
                    }.font(.caption)
                    ForEach(couponDetails.indices, id: \.self) { index in
                        let row = couponDetails[index]
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row["CampaignName"] as? String ?? row["campaignName"] as? String ?? "消费券核销")
                                .font(.system(size: NativeTypography.size(14), weight: .semibold))
                            Text("\(row["StoreName"] as? String ?? row["storeName"] as? String ?? "门店") · 优惠 \(String(describing: row["DiscountAmount"] ?? row["discountAmount"] ?? "0.00"))")
                                .font(.caption)
                            Text("\(row["RedeemedAt"] as? String ?? row["redeemedAt"] as? String ?? "") · \(row["RedeemedByName"] as? String ?? row["redeemedByName"] as? String ?? "")")
                                .font(.caption2).foregroundStyle(Brand.muted)
                            if let reversed = row["ReversedAt"] ?? row["reversedAt"], !(reversed is NSNull) {
                                Text("已冲正 · \(row["ReversalReason"] as? String ?? row["reversalReason"] as? String ?? "")")
                                    .font(.caption2).foregroundStyle(Brand.muted)
                            }
                        }.merchantCard()
                    }
                    if couponDetails.count < couponDetailTotal {
                        Button(couponDetailLoading ? "加载中…" : "加载更多消费券明细") {
                            Task { await loadCouponDetails(reset: false) }
                        }.disabled(couponDetailLoading).font(.caption)
                    }
                }
                if canReadTicketReport && !ticketReport.isEmpty {
                    Text("门票核销").font(.headline)
                    Text("授权范围内共核验 \(String(describing: ticketReport["TotalVerificationCount"] ?? ticketReport["totalVerificationCount"] ?? 0)) 张")
                        .font(.caption).foregroundStyle(Brand.muted)
                    ForEach((ticketReport["Items"] as? [[String: Any]] ?? ticketReport["items"] as? [[String: Any]] ?? []).indices, id: \.self) { index in
                        let rows = ticketReport["Items"] as? [[String: Any]] ?? ticketReport["items"] as? [[String: Any]] ?? []
                        let row = rows[index]
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row["MerchantName"] as? String ?? "当前商户").font(.subheadline.weight(.semibold))
                            Text("门票核验 \(String(describing: row["VerificationCount"] ?? 0)) 张").font(.caption)
                        }.merchantCard()
                    }
                    Button(ticketDetails.isEmpty ? "查看门票核验明细" : "刷新门票核验明细") {
                        Task { await loadTicketDetails(reset: true) }
                    }.font(.caption)
                    ForEach(ticketDetails.indices, id: \.self) { index in
                        let row = ticketDetails[index]
                        let bundleItems = row["BundleItems"] as? [[String: Any]]
                            ?? row["bundleItems"] as? [[String: Any]] ?? []
                        let bundleSummary = bundleItems.compactMap { item -> String? in
                            guard let name = item["Name"] as? String ?? item["name"] as? String,
                                  !name.isEmpty else { return nil }
                            let quantity = item["Quantity"] as? Int ?? item["quantity"] as? Int ?? 1
                            return "\(name) × \(quantity)"
                        }.joined(separator: "、")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row["TicketName"] as? String ?? row["ticketName"] as? String ?? "门票")
                                .font(.system(size: NativeTypography.size(14), weight: .semibold))
                            Text("\(row["SessionName"] as? String ?? row["sessionName"] as? String ?? "") · \(row["VerificationPointName"] as? String ?? row["verificationPointName"] as? String ?? "未指定检票点")")
                                .font(.caption)
                            if row["OrderItemSnapshotMissing"] as? Bool == true {
                                Text("订单项快照缺失，需人工核对")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            if (row["TicketKind"] as? String ?? row["ticketKind"] as? String) == "Bundle",
                               !bundleSummary.isEmpty {
                                Text("套票包含（一张凭证一次核销全部项目）：\(bundleSummary)")
                                    .font(.caption)
                            }
                            Text("订单 \(row["OrderNo"] as? String ?? row["orderNo"] as? String ?? "") · \(row["OperatorName"] as? String ?? row["operatorName"] as? String ?? "") · \(row["RedeemedAt"] as? String ?? row["redeemedAt"] as? String ?? "")")
                                .font(.caption2).foregroundStyle(Brand.muted)
                        }.merchantCard()
                    }
                    if ticketDetails.count < ticketDetailTotal {
                        Button(ticketDetailLoading ? "加载中…" : "加载更多门票明细") {
                            Task { await loadTicketDetails(reset: false) }
                        }.disabled(ticketDetailLoading).font(.caption)
                    }
                }
                if canReadSalesAndCoupons {
                    Text("订单收退款为观察口径，不代表平台结算或最终应收；消费券核销金额也不代表最终结算额。")
                        .font(.caption).foregroundStyle(Brand.muted)
                }
                if canReadTicketReport {
                    Text("门票核验按实际核验时间统计，票数不等同于结算金额。")
                        .font(.caption).foregroundStyle(Brand.muted)
                }
            }.padding(16)
        }
        .background(Brand.background)
        .navigationTitle("经营报表")
        .task(id: "\(merchantID)-\(revision)-\(store.session?.accessToken ?? "")") {
            guard let token = store.session?.accessToken,
                  let expectedPrincipal = nativeTourismPrincipal(token) else {
                activeReportMerchantID = ""
                reportRequestSequence += 1
                couponDetailsRequestSequence += 1
                ticketDetailsRequestSequence += 1
                couponDetailLoading = false; ticketDetailLoading = false; loading = false
                totals = []; items = []; couponReport = [:]; ticketReport = [:]
                couponDetails = []; ticketDetails = []; couponDetailTotal = 0; ticketDetailTotal = 0
                error = "登录后可查看经营报表"
                return
            }
            guard merchantID.allSatisfy(\.isNumber) else { return }
            let requestedMerchantID = merchantID
            activeReportMerchantID = requestedMerchantID
            reportRequestSequence += 1
            let requestSequence = reportRequestSequence
            couponDetailsRequestSequence += 1
            ticketDetailsRequestSequence += 1
            couponDetailLoading = false
            ticketDetailLoading = false
            loading = true; error = nil; totals = []; items = []; couponReport = [:]; ticketReport = [:]
            couponDetails = []; ticketDetails = []; couponDetailTotal = 0; ticketDetailTotal = 0
            let dateRange = businessDateRange()
            let range = "from=\(dateRange.from)T00%3A00%3A00&to=\(dateRange.to)T23%3A59%3A59&merchantId=\(requestedMerchantID)&page=1&pageSize=50"
            do {
                let api = MobileAPI(store: store)
                if canReadSalesAndCoupons {
                    let sales = try await api.get("/api/JHCTIReport/GetMyMerchantFinancialReport?\(range)", authenticated: true,
                        expectedPrincipal: expectedPrincipal) as? [String: Any] ?? [:]
                    guard store.session?.accessToken == token, activeReportMerchantID == requestedMerchantID,
                          reportRequestSequence == requestSequence else { return }
                    guard let salesData = nativeMerchantReportPage(sales, page: 1, pageSize: 50) else {
                        throw MobileAPIError.unavailable("销售报表分页回执无效")
                    }
                    totals = salesData["Totals"] as? [[String: Any]] ?? salesData["totals"] as? [[String: Any]] ?? []
                    items = salesData["Items"] as? [[String: Any]] ?? salesData["items"] as? [[String: Any]] ?? []
                    let coupon = try await api.get("/api/JHCTIReport/GetMyCouponRedemptionReport?\(range)", authenticated: true,
                        expectedPrincipal: expectedPrincipal) as? [String: Any] ?? [:]
                    guard store.session?.accessToken == token, activeReportMerchantID == requestedMerchantID,
                          reportRequestSequence == requestSequence else { return }
                    guard let couponData = nativeMerchantReportPage(coupon, page: 1, pageSize: 50) else {
                        throw MobileAPIError.unavailable("消费券报表分页回执无效")
                    }
                    couponReport = couponData
                }
                if canReadTicketReport {
                    let tickets = try await api.get("/api/JHCTIReport/GetMyTicketVerificationReport?\(range)", authenticated: true,
                        expectedPrincipal: expectedPrincipal) as? [String: Any] ?? [:]
                    guard store.session?.accessToken == token, activeReportMerchantID == requestedMerchantID,
                          reportRequestSequence == requestSequence else { return }
                    guard let ticketData = nativeMerchantReportPage(tickets, page: 1, pageSize: 50) else {
                        throw MobileAPIError.unavailable("门票核验报表分页回执无效")
                    }
                    ticketReport = ticketData
                }
                guard store.session?.accessToken == token, activeReportMerchantID == requestedMerchantID,
                      reportRequestSequence == requestSequence else { return }
            } catch {
                if store.session?.accessToken == token && activeReportMerchantID == requestedMerchantID
                    && reportRequestSequence == requestSequence { self.error = error.localizedDescription }
            }
            if store.session?.accessToken == token && activeReportMerchantID == requestedMerchantID
                && reportRequestSequence == requestSequence { loading = false }
        }
    }

    private func reportLine(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(Brand.muted); Spacer(); Text(value) }
    }

    private func detailRange(page: Int, merchantID: String) -> String {
        let dateRange = businessDateRange()
        return "from=\(dateRange.from)T00%3A00%3A00&to=\(dateRange.to)T23%3A59%3A59&merchantId=\(merchantID)&page=\(page)&pageSize=20"
    }

    private func loadCouponDetails(reset: Bool) async {
        guard !couponDetailLoading, let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        let requestedMerchantID = merchantID
        couponDetailsRequestSequence += 1
        let requestSequence = couponDetailsRequestSequence
        couponDetailLoading = true
        defer {
            if couponDetailsRequestSequence == requestSequence && activeReportMerchantID == requestedMerchantID {
                couponDetailLoading = false
            }
        }
        do {
            let page = reset ? 1 : couponDetails.count / 20 + 1
            let response = try await MobileAPI(store: store).get("/api/JHCTIReport/GetMyCouponRedemptionDetails?\(detailRange(page: page, merchantID: requestedMerchantID))", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any] ?? [:]
            guard store.session?.accessToken == token, activeReportMerchantID == requestedMerchantID,
                  couponDetailsRequestSequence == requestSequence else { return }
            let data = response["Data"] as? [String: Any] ?? response["data"] as? [String: Any] ?? response
            guard let rows = data["Items"] as? [[String: Any]] ?? data["items"] as? [[String: Any]],
                  (data["Page"] as? Int ?? data["page"] as? Int) == page,
                  (data["PageSize"] as? Int ?? data["pageSize"] as? Int) == 20,
                  let total = data["Total"] as? Int ?? data["total"] as? Int,
                  let expectedRows = nativeReportExpectedRows(page: page, total: total, pageSize: 20),
                  rows.count == expectedRows else {
                throw MobileAPIError.unavailable("消费券明细分页回执无效")
            }
            couponDetails = reset ? rows : couponDetails + rows
            couponDetailTotal = total
        } catch {
            if store.session?.accessToken == token && activeReportMerchantID == requestedMerchantID
                && couponDetailsRequestSequence == requestSequence { self.error = error.localizedDescription }
        }
    }

    private func loadTicketDetails(reset: Bool) async {
        guard !ticketDetailLoading, let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        let requestedMerchantID = merchantID
        ticketDetailsRequestSequence += 1
        let requestSequence = ticketDetailsRequestSequence
        ticketDetailLoading = true
        defer {
            if ticketDetailsRequestSequence == requestSequence && activeReportMerchantID == requestedMerchantID {
                ticketDetailLoading = false
            }
        }
        do {
            let page = reset ? 1 : ticketDetails.count / 20 + 1
            let response = try await MobileAPI(store: store).get("/api/JHCTIReport/GetMyTicketVerificationDetails?\(detailRange(page: page, merchantID: requestedMerchantID))", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any] ?? [:]
            guard store.session?.accessToken == token, activeReportMerchantID == requestedMerchantID,
                  ticketDetailsRequestSequence == requestSequence else { return }
            let data = response["Data"] as? [String: Any] ?? response["data"] as? [String: Any] ?? response
            guard let rows = data["Items"] as? [[String: Any]] ?? data["items"] as? [[String: Any]],
                  (data["Page"] as? Int ?? data["page"] as? Int) == page,
                  (data["PageSize"] as? Int ?? data["pageSize"] as? Int) == 20,
                  let total = data["Total"] as? Int ?? data["total"] as? Int,
                  let expectedRows = nativeReportExpectedRows(page: page, total: total, pageSize: 20),
                  rows.count == expectedRows else {
                throw MobileAPIError.unavailable("门票明细分页回执无效")
            }
            ticketDetails = reset ? rows : ticketDetails + rows
            ticketDetailTotal = total
        } catch {
            if store.session?.accessToken == token && activeReportMerchantID == requestedMerchantID
                && ticketDetailsRequestSequence == requestSequence { self.error = error.localizedDescription }
        }
    }
}
