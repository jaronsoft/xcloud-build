import SwiftUI

struct NativeResourceOverviewSection: View {
    @ObservedObject var store: SessionStore
    let item: ResourceItem
    let detail: [String: Any]
    let initialGuideRouteID: String?
    let ticketBookingEnabled: Bool
    let reservationUnavailable: Bool
    @Binding var selectedDetailTab: String
    @Binding var summaryExpanded: Bool
    let reviewForm: AnyView?
    let onFreeReservation: () -> Void
    let onTicketBooking: () -> Void

    private var isFacility: Bool { item.resourceType == "Facility" }

    private var facilityTypeLabel: String {
        switch detail["FacilityType"] as? String {
        case "Restroom": "卫生间"
        case "ParkingLot": "停车场"
        case "GasStation": "加油站"
        default: "公共设施"
        }
    }

    private var openStatusLabel: String {
        switch detail["OpenStatus"] as? String {
        case "Open": "正常开放"
        case "Closed": "暂未开放"
        case "TemporarilyClosed": "暂时关闭"
        default: ""
        }
    }

    private var admissionLabel: String {
        switch detail["AdmissionType"] as? String ?? item.admissionType {
        case "Free": "免费开放"
        case "FreeReservation": "免费预约"
        case "PaidReservation": "预约购票"
        default: "景区门票"
        }
    }

    private func dialablePhoneURL(_ value: String) -> URL? {
        let normalized = value.replacingOccurrences(of: "[\\s()（）-]", with: "", options: .regularExpression)
        guard normalized.range(of: "^\\+?[0-9]{5,20}$", options: .regularExpression) != nil else { return nil }
        return URL(string: "tel:\(normalized)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isFacility ? "\(facilityTypeLabel)　\(openStatusLabel)" : "\(detail["Region"] as? String ?? "江都")　\(openStatusLabel)")
                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                .padding(.bottom, 6)
            Text(detail["Name"] as? String ?? item.name)
                .font(.system(size: NativeTypography.size(24), weight: .bold, design: .serif)).foregroundStyle(Brand.ink)
                .padding(.bottom, 10)
            let tags = detail["Tags"] as? [String] ?? []
            let theme = detail["Theme"] as? String ?? ""
            if !theme.isEmpty || !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        if !theme.isEmpty { taxonomyBadge("主题 · \(theme)") }
                        ForEach(tags, id: \.self) { taxonomyBadge($0) }
                    }
                }
                .padding(.bottom, 12)
            }
            if let hours = detail["OpeningHours"] as? String, !hours.isEmpty, isFacility {
                HStack(alignment: .top, spacing: 10) {
                    Text("开放时间").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    Text(hours).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
                }
                .padding(.vertical, 11)
                Divider()
            } else if let hours = detail["OpeningHours"] as? String, !hours.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    admissionBadge()
                    Text("开放时间").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    Text(hours).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
                }
                .padding(.vertical, 11)
                Divider()
            } else if !isFacility {
                admissionBadge().padding(.bottom, 12)
            }
            if item.resourceType == "ScenicSpot",
               (detail["AdmissionType"] as? String ?? item.admissionType) == "FreeReservation" {
                Button(action: onFreeReservation) {
                    HStack { Image(systemName: "calendar.badge.plus"); Text("免费预约") }
                        .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Brand.primary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain).disabled(reservationUnavailable).padding(.vertical, 12)
            } else if ticketBookingEnabled, item.resourceType == "ScenicSpot",
                      ["Paid", "PaidReservation"].contains(detail["AdmissionType"] as? String ?? item.admissionType) {
                Button(action: onTicketBooking) {
                    Label("选择门票", systemImage: "ticket")
                        .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Brand.primary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain).padding(.vertical, 12)
            }

            let introductionHtml = detail["ContentHtml"] as? String ?? ""
            let introductionHasContent = !introductionHtml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let notice = detail["Notice"] as? String ?? ""
            HStack(spacing: 20) {
                detailTab(isFacility ? "设施详情" : "景点详情", key: "details")
                if !notice.isEmpty { detailTab(isFacility ? "现场须知" : "游览须知", key: "notice") }
                if introductionHasContent { detailTab("图文介绍", key: "introduction") }
            }
            .padding(.top, 12)
            Divider()
            NativeCoordinateMapCard(title: isFacility ? "设施位置" : "景点位置",
                name: detail["Name"] as? String ?? item.name,
                address: detail["Address"] as? String,
                latitude: (detail["Latitude"] as? NSNumber)?.doubleValue,
                longitude: (detail["Longitude"] as? NSNumber)?.doubleValue,
                coordinateSystem: detail["CoordinateSystem"] as? String ?? "")
            if selectedDetailTab == "notice" && !notice.isEmpty {
                Text(notice).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
                    .lineSpacing(5).padding(.vertical, 16)
            } else if selectedDetailTab == "introduction" && introductionHasContent {
                NativeHTMLContent(html: introductionHtml, store: store).padding(.vertical, 16)
            } else {
                if isFacility {
                    Text(facilityTypeLabel + "信息").font(.system(size: NativeTypography.size(18), weight: .semibold))
                        .foregroundStyle(Brand.ink).padding(.top, 14)
                }
                let summary = (detail["Description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (isFacility ? "该设施暂未补充更多信息。" : "查看景点介绍与出行信息。")
                let longSummary = summary.utf16.count > 180 || summary.components(separatedBy: "\n").count > 5
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
                        .lineSpacing(5).lineLimit(longSummary && !summaryExpanded ? 5 : nil)
                        .textSelection(.enabled)
                    if longSummary {
                        Button(summaryExpanded ? "收起介绍 ↑" : "展开完整介绍 ↓") { summaryExpanded.toggle() }
                            .frame(minHeight: 44).foregroundStyle(Brand.primary)
                            .font(.system(size: NativeTypography.size(13)))
                            .accessibilityLabel(summaryExpanded ? "收起介绍" : "展开完整介绍")
                            .accessibilityValue(summaryExpanded ? "已展开" : "已收起")
                    }
                }.padding(.vertical, 16)
                if !isFacility {
                    NativeResourceFacilitiesSection(rows: detail["Facilities"] as? [[String: Any]] ?? [])
                }
                if let address = detail["Address"] as? String, !address.isEmpty {
                    HStack(spacing: 12) {
                        Text(isFacility ? "\(facilityTypeLabel)位置" : "地址").foregroundStyle(Brand.muted)
                        Text(address).foregroundStyle(Brand.primary)
                        Spacer(minLength: 0)
                        if let latitude = (detail["Latitude"] as? NSNumber)?.doubleValue,
                           let longitude = (detail["Longitude"] as? NSNumber)?.doubleValue,
                           let coordinate = MapCoordinate.wgs84(latitude: latitude, longitude: longitude,
                               system: detail["CoordinateSystem"] as? String ?? ""),
                           let url = URL(string: "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)") {
                            Link("导航 ▥", destination: url).foregroundStyle(Brand.primary)
                        }
                    }
                    .font(.system(size: NativeTypography.size(14))).padding(.vertical, 13)
                    Divider()
                }
                if let phone = detail["ContactPhone"] as? String, !phone.isEmpty {
                    HStack(spacing: 12) {
                        Text("联系电话").foregroundStyle(Brand.muted)
                        Text(phone).foregroundStyle(Brand.ink).textSelection(.enabled)
                        Spacer(minLength: 0)
                        if let url = dialablePhoneURL(phone) {
                            Link("拨打 ›", destination: url).foregroundStyle(Brand.primary)
                        }
                    }
                    .font(.system(size: NativeTypography.size(14))).padding(.vertical, 13)
                    Divider()
                }
                let routes = detail["Routes"] as? [[String: Any]] ?? []
                if let initialGuideRouteID, !routes.contains(where: { $0["Id"] as? String == initialGuideRouteID }) {
                    Text("搜索到的导览路线已不可查看，可能已更新或下线。请返回搜索后重试。")
                        .font(.system(size: NativeTypography.size(13))).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                }
                if !isFacility && !routes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("导览路线").font(.system(size: NativeTypography.size(18), weight: .semibold))
                            .foregroundStyle(Brand.ink)
                        ForEach(Array(routes.enumerated()), id: \.offset) { routeIndex, route in
                            let routeID = route["Id"] as? String ?? ""
                            VStack(alignment: .leading, spacing: 5) {
                                if routeID == initialGuideRouteID {
                                    Text("搜索到的导览路线").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.primary)
                                }
                                NativeGuideRouteMap(route: route, routeIndex: routeIndex)
                            }
                            .padding(routeID == initialGuideRouteID ? 8 : 0)
                            .background(routeID == initialGuideRouteID ? Brand.primary.opacity(0.08) : .clear,
                                in: RoundedRectangle(cornerRadius: 10))
                            .id("guide-route-\(routeID.isEmpty ? String(routeIndex) : routeID)")
                        }
                    }
                    .padding(.vertical, 14)
                }
                if !isFacility {
                    let reviewPresentation = nativeTourismReviewPresentation(detail)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("游客评价").font(.system(size: NativeTypography.size(18), weight: .semibold))
                            .foregroundStyle(Brand.ink)
                        Text("\(reviewPresentation.count) 条已审核")
                            .font(.system(size: NativeTypography.size(13))).foregroundStyle(Brand.muted)
                        if reviewPresentation.count > 0 {
                            Text("平均评分 \(reviewPresentation.averageText)")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                        }
                        if reviewPresentation.rows.isEmpty {
                            Text(reviewPresentation.count > 0 ? "暂无可展示的近期评价。" : "暂无已审核的游客评价。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                    ForEach(Array(reviewPresentation.rows.enumerated()), id: \.offset) { _, row in
                        NativeTourismReviewCard(title: row.title, rating: row.rating,
                            content: row.content, reply: row.reply,
                            avatarURL: MobileAPI(store: store).mediaURL(row.avatarURL))
                    }
                    if reviewPresentation.count > reviewPresentation.rows.count {
                        Text("显示最近 \(reviewPresentation.rows.count) 条已审核评价，共 \(reviewPresentation.count) 条。")
                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                    if let reviewForm { reviewForm }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
        .padding(.top, -12)
    }

    private func admissionBadge() -> some View {
        Text(admissionLabel).font(.system(size: NativeTypography.size(14), weight: .semibold))
            .foregroundStyle(Brand.primary).padding(.horizontal, 8).padding(.vertical, 3)
            .background(Brand.background, in: Capsule())
    }

    private func taxonomyBadge(_ title: String) -> some View {
        Text(title).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Brand.background, in: Capsule())
    }

    private func detailTab(_ title: String, key: String) -> some View {
        Button { selectedDetailTab = key } label: {
            VStack(spacing: 0) {
                Text(title).font(.system(size: NativeTypography.size(14), weight: selectedDetailTab == key ? .semibold : .regular))
                    .foregroundStyle(selectedDetailTab == key ? Brand.primary : Brand.muted)
                    .frame(height: 42)
                Rectangle().fill(selectedDetailTab == key ? Brand.primary : .clear).frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }
}
