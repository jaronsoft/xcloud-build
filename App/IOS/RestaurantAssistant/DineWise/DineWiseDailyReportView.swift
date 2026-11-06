import SwiftUI

struct DineWiseDailyReportView: View {
    let store: DineWiseStore
    let token: String

    @State private var businessDate = ""
    @State private var report: DineWiseDailyReport?
    @State private var message = ""
    @State private var busy = false
    private let api = DineWiseAPI()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("经营日报 · 已确认事实").font(.title2.bold())
            Text("选择门店营业日期；重复或未核对资料不会合并成收入。")
                .font(.footnote).foregroundStyle(.secondary)
            TextField("营业日期 YYYY-MM-DD", text: $businessDate)
                .textFieldStyle(.roundedBorder)
                .onChange(of: businessDate) { _, _ in report = nil }
            Button("查看日报") { load() }
                .buttonStyle(.borderedProminent)
                .disabled(busy || businessDate.isEmpty)
            if !message.isEmpty { Text(message).foregroundStyle(.red) }
            if let report {
                Text("\(report.BusinessDate) · \(report.Mode == "demo" ? "演示数据" : "试用门店")")
                Text("营业额：\(money(report.RevenueYuan))")
                Text("订单：\(report.Orders.map(String.init) ?? "未核对") · 桌数：\(report.Tables.map(String.init) ?? "未核对")")
                Text("桌均：\(money(report.RevenuePerTableYuan))")
                if let source = report.SourceSubmissionId {
                    Text("来源资料：\(source) · 确认版本 \(report.SourceVersion ?? 0)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(report.MissingReasons, id: \.self) { reason in
                    Text("待补充：\(reason)").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: store.Id) { _, _ in
            businessDate = ""; report = nil; message = ""
        }
    }

    private func load() {
        let storeID = store.Id
        let date = businessDate
        busy = true; message = ""; report = nil
        Task {
            do {
                let result = try await api.dailyReport(storeID: storeID,
                    businessDate: date, token: token)
                if store.Id == storeID && businessDate == date { report = result }
            } catch {
                if store.Id == storeID { message = error.localizedDescription }
            }
            busy = false
        }
    }

    private func money(_ value: Decimal?) -> String {
        guard let value else { return "不可计算或未核对" }
        return "¥\(NSDecimalNumber(decimal: value).stringValue)"
    }
}
