import SwiftUI

struct DineWiseGuestHomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var priceRegion = ""
    @State private var publicPrices: [DineWisePublicPriceReference] = []
    @State private var priceMessage = ""
    @State private var pricesLoaded = false
    @State private var pricesLoading = false
    @State private var priceRequestGeneration = 0
    @State private var publicActivities: [DineWisePublicActivity] = []
    @State private var activityMessage = ""
    @State private var activitiesLoaded = false
    @State private var activitiesLoading = false
    @State private var activityRequestGeneration = 0
    private let api = DineWiseAPI()
    private let ink = Color(red: 0.11, green: 0.12, blue: 0.16)
    private var gold: Color { DineWiseTheme.gold(for: colorScheme) }
    private var green: Color { DineWiseTheme.accent(for: colorScheme) }
    private var red: Color { DineWiseTheme.danger(for: colorScheme) }
    private var bannerPrimary: Color { .primary }
    private var bannerSecondary: Color { .secondary }
    private var readableSecondary: Color { .secondary }
    private var bannerIconColor: Color {
        DineWiseTheme.surfaceGold(for: colorScheme)
    }
    private var bannerGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.25, green: 0.22, blue: 0.16),
                   Color(red: 0.19, green: 0.19, blue: 0.17)]
                : [Color(red: 1, green: 0.94, blue: 0.78),
                   Color(red: 0.99, green: 0.97, blue: 0.89)],
            startPoint: .leading, endPoint: .trailing)
    }
    private var softSurface: Color {
        colorScheme == .dark
            ? Color(uiColor: .tertiarySystemGroupedBackground)
            : Color(red: 0.96, green: 0.957, blue: 0.933)
    }

    private func limitedRegionInput(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        var utf16Length = 0
        for scalar in value.unicodeScalars {
            let scalarLength = scalar.value > 0xFFFF ? 2 : 1
            guard utf16Length + scalarLength <= 160 else { break }
            scalars.append(scalar)
            utf16Length += scalarLength
        }
        return String(scalars)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(bannerIconColor)
                    .frame(width: 30, height: 30)
                    .background(Color(uiColor: .systemBackground).opacity(0.65),
                                in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("先体验老板工作台")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(bannerPrimary)
                    Text("以下均为构造数据，不代表真实门店")
                        .font(.caption2)
                        .foregroundStyle(bannerSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .background(bannerGradient, in: RoundedRectangle(cornerRadius: 14))

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("云巷小馆")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("先处理重要的事，再看经营数字")
                        .font(.caption).foregroundStyle(readableSecondary)
                }
                Spacer()
                Label("演示门店", systemImage: "sparkles")
                    .font(.caption.bold()).foregroundStyle(green)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(green.opacity(0.09), in: Capsule())
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(gold)
                        Text("今天要处理").font(.system(size: 18, weight: .bold))
                    }
                    Spacer()
                    Text("3 件待办").font(.caption.weight(.semibold)).foregroundStyle(gold)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(gold.opacity(0.12), in: Capsule())
                }
                .padding(.bottom, 7)
                task("停", "采购进货单单位待核对", "确认后才能进入经营报告",
                     Color(red: 0.94, green: 0.43, blue: 0.48))
                task("建议", "周末备菜方案待决定", "老板确认后再分派岗位", gold)
                task("执行", "门店运营任务待回执", "负责人完成后提交结果",
                     Color(red: 0.44, green: 0.80, blue: 0.57))
            }
            .padding(17)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [ink, Color(red: 0.14, green: 0.17, blue: 0.23)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    HStack(spacing: 8) {
                        Capsule().fill(green).frame(width: 4, height: 18)
                        Text("昨日关键数字").font(.headline)
                    }
                    Spacer()
                    Text("示例数据").font(.caption).foregroundStyle(readableSecondary)
                }
                HStack(alignment: .top, spacing: 8) {
                    metric("¥12,860", "营业额", prominent: true)
                    metric("56 桌", "桌数")
                    metric("¥230", "桌均")
                }
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("近 7 日走势")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("仅展示构造样本")
                            .font(.caption2)
                            .foregroundStyle(readableSecondary)
                    }
                    Spacer(minLength: 4)
                    DineWiseGuestSparkline(color: green)
                        .frame(width: 112, height: 40)
                    .accessibilityLabel("近七日示例趋势")
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(softSurface, in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 12) {
                    summary("¥7,330", "估算毛利 57%", green, green.opacity(0.07))
                    summary("¥1,540", "平台成本 · 占 12%", red, red.opacity(0.06))
                }
            }
            .cardStyle()

            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("岗位完成情况").font(.headline)
                    Spacer()
                    Text("今日").font(.caption).foregroundStyle(readableSecondary)
                }
                HStack(spacing: 8) {
                    progress("厨师长", "2/3", 0.67)
                    progress("采购", "1/2", 0.5)
                    progress("运营", "3/3", 1)
                    progress("店长", "1/2", 0.5)
                }
                HStack(spacing: 5) {
                    Image(systemName: "clock.badge.exclamationmark")
                    Text("采购有 1 项超时待核对")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(red)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("本周会议事项").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("1/3 已完成").font(.caption.weight(.semibold)).foregroundStyle(green)
                    }
                    Text("构造示例 · 老板可查看岗位执行进度")
                        .font(.caption2).foregroundStyle(readableSecondary)
                    meetingTask("已完成", role: "店长", title: "确认周末排班方案", color: green)
                    meetingTask("执行中", role: "采购", title: "核对两家供应商报价", color: gold)
                    meetingTask("待接单", role: "店长", title: "更新门店营业时段", color: readableSecondary)
                }
                .padding(12)
                .background(softSurface, in: RoundedRectangle(cornerRadius: 14))
            }
            .cardStyle()

            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(green)
                    .frame(width: 40, height: 40)
                    .background(green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("待核对资料 2 份").font(.subheadline.bold())
                    Text("登录后查看自己门店的资料").font(.caption).foregroundStyle(readableSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18))

            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundStyle(green)
                Text("全部数字和待办均为构造示例，不代表真实门店。")
                    .font(.footnote).foregroundStyle(readableSecondary)
            }
            .padding(.horizontal, 4)
            publicPriceSection
            publicActivitySection
            DineWiseWeatherView(token: nil, storeLatitude: nil, storeLongitude: nil,
                                storeTimeZone: TimeZone.current.identifier)
        }
    }

    private var publicPriceSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("区域食材参考价").font(.headline)
                Spacer()
                Text("公开信息").font(.caption).foregroundStyle(green)
            }
            Text("仅展示后台已核实并发布、仍在有效期内的市场参考；不代表本店进价，不跨规格或单位比较。")
                .font(.caption).foregroundStyle(readableSecondary)
            HStack(spacing: 8) {
                TextField("输入地区，例如：湖滨区", text: Binding(
                    get: { priceRegion },
                    set: { priceRegion = limitedRegionInput($0) }
                ))
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)
                    .disabled(pricesLoading)
                    .onChange(of: priceRegion) {
                        publicPrices = []
                        pricesLoaded = false
                        priceMessage = ""
                        publicActivities = []
                        activitiesLoaded = false
                        activitiesLoading = false
                        activityMessage = ""
                        activityRequestGeneration += 1
                    }
                Button(pricesLoading ? "查询中" : "查询") { loadPublicPrices() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pricesLoading || priceRegion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !priceMessage.isEmpty {
                Text(priceMessage).font(.footnote)
                    .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
            }
            if pricesLoaded && publicPrices.isEmpty {
                Text("该地区暂无已发布且有效的参考价。")
                    .font(.footnote).foregroundStyle(readableSecondary)
            }
            ForEach(publicPrices) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.ItemName).font(.subheadline.weight(.bold))
                        Spacer(minLength: 4)
                        Text("¥\(NSDecimalNumber(decimal: item.PriceYuan).stringValue) / \(item.Unit)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(green)
                    }
                    Text("\(item.Category) · \(item.Specification) · \(item.RegionName)")
                        .font(.caption).foregroundStyle(readableSecondary)
                    if let previousPrice = item.PreviousPriceYuan,
                       let previousAt = item.PreviousObservedAtUtc {
                        let previousValue = NSDecimalNumber(decimal: previousPrice).stringValue
                        let change = item.PriceChangePercent.map {
                            " · \($0 >= 0 ? "+" : "")\(NSDecimalNumber(decimal: $0).stringValue)%"
                        } ?? ""
                        Text("近两周前次同口径参考价 ¥\(previousValue) / \(item.Unit)\(change) · \(dineWiseFormatTimestamp(previousAt, timeZoneID: nil))")
                            .font(.caption).foregroundStyle(readableSecondary)
                    }
                    Text("来源：\(item.SourceName) · 采集于 \(dineWiseFormatTimestamp(item.ObservedAtUtc, timeZoneID: nil))")
                        .font(.caption).foregroundStyle(readableSecondary)
                    HStack {
                        if let source = item.SourceUrl, let url = URL(string: source) {
                            Link("查看来源", destination: url).font(.caption)
                        }
                        Spacer()
                        Text("有效至 \(dineWiseFormatTimestamp(item.ExpiresAtUtc, timeZoneID: nil))")
                            .font(.caption2).foregroundStyle(readableSecondary)
                    }
                }
                .padding(12)
                .background(softSurface, in: RoundedRectangle(cornerRadius: 13))
            }
        }
        .cardStyle()
    }

    private var publicActivitySection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("地区周边活动").font(.headline)
                Spacer()
                Text("管理员核实").font(.caption).foregroundStyle(green)
            }
            Text("仅显示管理员明确公开、来源可查且仍在有效期内的活动；地区名称需与发布信息一致。")
                .font(.caption).foregroundStyle(readableSecondary)
            Button(activitiesLoading ? "查询中" : "查询该地区活动") { loadPublicActivities() }
                .buttonStyle(.borderedProminent)
                .disabled(activitiesLoading || priceRegion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !activityMessage.isEmpty {
                Text(activityMessage).font(.footnote)
                    .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
            }
            if activitiesLoaded && publicActivities.isEmpty {
                Text("该地区暂无已公开且有效的活动。")
                    .font(.footnote).foregroundStyle(readableSecondary)
            }
            ForEach(publicActivities) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.TitleZh).font(.subheadline.bold())
                    Text(item.BodyZh).font(.subheadline)
                    Text("\(item.LocationName) · 来源：\(item.SourceName)")
                        .font(.caption).foregroundStyle(readableSecondary)
                    Text("核实于 \(dineWiseFormatTimestamp(item.VerifiedAtUtc, timeZoneID: nil)) · 有效至 \(dineWiseFormatTimestamp(item.ExpiresAtUtc, timeZoneID: nil))")
                        .font(.caption2).foregroundStyle(readableSecondary)
                    if let source = item.SourceUrl, let url = URL(string: source) {
                        Link("查看来源", destination: url).font(.caption)
                    }
                }
                .padding(12)
                .background(softSurface, in: RoundedRectangle(cornerRadius: 13))
            }
        }
        .cardStyle()
    }

    private func loadPublicPrices() {
        let region = priceRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !region.isEmpty else { return }
        priceRequestGeneration += 1
        let requestGeneration = priceRequestGeneration
        pricesLoading = true
        pricesLoaded = false
        priceMessage = ""
        publicPrices = []
        Task {
            do {
                let result = try await api.publicPriceReferences(region: region)
                guard requestGeneration == priceRequestGeneration else { return }
                publicPrices = result
                pricesLoaded = true
            } catch {
                guard requestGeneration == priceRequestGeneration else { return }
                priceMessage = error.localizedDescription
            }
            if requestGeneration == priceRequestGeneration { pricesLoading = false }
        }
    }

    private func loadPublicActivities() {
        let region = priceRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !region.isEmpty else { return }
        activityRequestGeneration += 1
        let requestGeneration = activityRequestGeneration
        activitiesLoading = true
        activitiesLoaded = false
        activityMessage = ""
        publicActivities = []
        Task {
            do {
                let result = try await api.publicActivities(region: region)
                guard requestGeneration == activityRequestGeneration else { return }
                publicActivities = result
                activitiesLoaded = true
            } catch {
                guard requestGeneration == activityRequestGeneration else { return }
                activityMessage = error.localizedDescription
            }
            if requestGeneration == activityRequestGeneration { activitiesLoading = false }
        }
    }

    private func metric(_ value: String, _ label: String, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(prominent ? green : .primary)
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(readableSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .padding(.horizontal, 9)
        .background(prominent ? green.opacity(0.09) : softSurface,
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func summary(_ value: String, _ label: String, _ color: Color,
                         _ background: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(readableSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(background, in: RoundedRectangle(cornerRadius: 12))
    }

    private func task(_ label: String, _ title: String, _ detail: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).font(.caption2.bold()).foregroundStyle(color)
                .frame(width: 38).padding(.vertical, 5)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.78))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Color.white.opacity(0.1).frame(height: 1) }
    }

    private func progress(_ title: String, _ value: String, _ fraction: CGFloat) -> some View {
        VStack(spacing: 7) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(fraction == 1 ? green : .primary)
            Text(title).font(.caption2).foregroundStyle(.secondary)
            GeometryReader { geometry in
                Capsule().fill(green.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(fraction == 1 ? green : gold)
                            .frame(width: geometry.size.width * fraction)
                    }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func meetingTask(_ status: String, role: String, title: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(status).font(.caption2.weight(.semibold)).foregroundStyle(color)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.primary)
                Text(role).font(.caption2).foregroundStyle(readableSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DineWiseGuestSparkline: View {
    let color: Color
    private let levels: [CGFloat] = [0.38, 0.47, 0.43, 0.56, 0.62, 0.76, 0.88]

    var body: some View {
        GeometryReader { geometry in
            let points = levels.enumerated().map { index, level in
                CGPoint(x: geometry.size.width * CGFloat(index) / CGFloat(levels.count - 1),
                        y: geometry.size.height * (1 - level))
            }
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            ForEach(points.indices, id: \.self) { index in
                Circle()
                    .fill(index == points.count - 1
                        ? color : Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(width: 5, height: 5)
                    .overlay(Circle().stroke(color, lineWidth: 1.5))
                    .position(points[index])
            }
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self.padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .stroke(Color.black.opacity(0.035), lineWidth: 1))
    }
}
