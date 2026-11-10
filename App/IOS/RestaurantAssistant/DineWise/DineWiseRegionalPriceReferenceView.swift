import SwiftUI

struct DineWiseRegionalPriceReferenceView: View {
    @Environment(\.colorScheme) private var colorScheme
    let storeID: String
    let token: String
    let timeZoneID: String?

    @State private var expanded = false
    @State private var region = ""
    @State private var items: [DineWisePublicPriceReference] = []
    @State private var message = ""
    @State private var loaded = false
    @State private var loading = false
    @State private var requestGeneration = 0
    private let api = DineWiseAPI()

    var body: some View {
        DisclosureGroup("区域参考价 · 市场趋势", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("仅供市场参考，不代表本店进价。当前没有本店进价、配方和销量依据，因此不计算受影响菜品、成本或毛利。地区名称需与发布资料一致。")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("输入地区，例如：湖滨区", text: $region)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .disabled(loading)
                    Button(loading ? "查询中" : "查询") { load() }
                        .buttonStyle(.borderedProminent)
                        .disabled(loading || region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !message.isEmpty {
                    Text(message).font(.footnote)
                        .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                }
                if loaded && items.isEmpty {
                    Text("该地区暂无已核实并仍有效的参考价。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.ItemName).font(.subheadline.bold())
                            Spacer(minLength: 4)
                            Text("¥\(NSDecimalNumber(decimal: item.PriceYuan).stringValue) / \(item.Unit)")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                        }
                        Text("\(item.Category) · \(item.Specification) · \(item.RegionName)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("采集于 \(dineWiseFormatTimestamp(item.ObservedAtUtc, timeZoneID: timeZoneID))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let previous = item.PreviousPriceYuan,
                           let previousAt = item.PreviousObservedAtUtc {
                            let change = item.PriceChangePercent.map {
                                " · \($0 >= 0 ? "+" : "")\(NSDecimalNumber(decimal: $0).stringValue)%"
                            } ?? ""
                            Text("前次同规格/单位 ¥\(NSDecimalNumber(decimal: previous).stringValue) / \(item.Unit)\(change) · \(dineWiseFormatTimestamp(previousAt, timeZoneID: timeZoneID))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            if let sourceURL = URL(string: item.SourceUrl ?? ""),
                               sourceURL.scheme?.lowercased() == "https", sourceURL.host != nil {
                                Link("查看来源：\(item.SourceName)", destination: sourceURL)
                            } else {
                                Text("来源：\(item.SourceName)")
                            }
                            Text("· 有效至 \(dineWiseFormatTimestamp(item.ExpiresAtUtc, timeZoneID: timeZoneID))")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9)
                    .overlay(alignment: .top) { Rectangle().fill(.quaternary).frame(height: 1) }
                }
            }
            .padding(.top, 8)
        }
        .padding(12)
        .background(DineWiseTheme.inset, in: RoundedRectangle(cornerRadius: 14))
        .task(id: "\(storeID):\(token)") {
            requestGeneration += 1
            region = ""; items = []; message = ""; loaded = false; loading = false
        }
        .onChange(of: region) { _, _ in
            requestGeneration += 1
            items = []; message = ""; loaded = false; loading = false
        }
    }

    private func load() {
        let selectedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedRegion.isEmpty else { message = "请填写地区名称。"; return }
        requestGeneration += 1
        let generation = requestGeneration
        loading = true; loaded = false; items = []; message = ""
        Task {
            do {
                let result = try await api.publicPriceReferences(region: selectedRegion)
                guard generation == requestGeneration else { return }
                items = result; loaded = true
            } catch {
                guard generation == requestGeneration else { return }
                message = error.localizedDescription
            }
            if generation == requestGeneration { loading = false }
        }
    }
}
