import SwiftUI

struct NativeHomeOperationComponent: View {
    let store: SessionStore
    let item: [String: Any]
    let serviceStatusClock: Date
    let onOpen: () -> Void

    private var type: String {
        (item["ComponentType"] as? String ?? item["componentType"] as? String ?? "").lowercased()
    }

    private var targetType: String {
        item["TargetType"] as? String ?? item["targetType"] as? String ?? "None"
    }

    var body: some View {
        Group {
            if type == "noticebar" {
                Button { if targetType.lowercased() != "none" { onOpen() } } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Text(item["Title"] as? String ?? item["title"] as? String ?? "公告")
                            .font(.system(size: NativeTypography.size(11), weight: .bold)).foregroundStyle(Color.orange)
                        NoticeTicker(content: item["Subtitle"] as? String ?? item["subtitle"] as? String ?? "")
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Color(red: 1, green: 0.97, blue: 0.93), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                }.buttonStyle(.plain)
            } else if type == "servicestatus" {
                serviceStatus
            } else if type == "promobanner" {
                Button { if targetType.lowercased() != "none" { onOpen() } } label: {
                    ZStack(alignment: .leading) {
                        remoteImage(item["ImageUrl"] as? String ?? item["imageUrl"] as? String, height: 112)
                        RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.32))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item["Title"] as? String ?? item["title"] as? String ?? "")
                                .font(.system(size: NativeTypography.size(16), weight: .bold)).foregroundStyle(.white)
                            Text(item["Subtitle"] as? String ?? item["subtitle"] as? String ?? "")
                                .font(.system(size: NativeTypography.size(12))).foregroundStyle(.white).lineLimit(2)
                        }.padding(.horizontal, 16)
                    }.frame(height: 112).clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 16)
                }.buttonStyle(.plain)
            }
        }
    }

    private var serviceStatus: some View {
        let opening = item["OpeningTime"] as? String ?? item["openingTime"] as? String ?? ""
        let closing = item["ClosingTime"] as? String ?? item["closingTime"] as? String ?? ""
        let hoursEnabled = (item["NoticeType"] as? String ?? item["noticeType"] as? String ?? "")
            .localizedCaseInsensitiveContains("openinghours")
        let openMinute = noticeMinute(opening)
        let closeMinute = noticeMinute(closing)
        let now = Calendar.current.dateComponents(in: TimeZone(identifier: "Asia/Shanghai") ?? .current,
                                                 from: serviceStatusClock)
        let currentMinute = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let openNow: Bool = {
            guard let openMinute, let closeMinute else { return false }
            if openMinute < closeMinute { return currentMinute >= openMinute && currentMinute < closeMinute }
            return openMinute > closeMinute && (currentMinute >= openMinute || currentMinute < closeMinute)
        }()
        let detail = {
            if hoursEnabled, let openMinute, let closeMinute {
                return "\(opening)–\(openMinute > closeMinute ? "次日" : "")\(closing)\(openNow ? "" : " · 当前非开放时段")"
            }
            return item["Subtitle"] as? String ?? item["subtitle"] as? String ?? ""
        }()

        return HStack(spacing: 10) {
            Text("i").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.primary)
                .frame(width: 24, height: 24).background(Brand.background, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(item["Title"] as? String ?? item["title"] as? String ?? "服务信息")
                    .font(.system(size: NativeTypography.size(12), weight: .semibold)).foregroundStyle(Brand.ink)
                if !detail.isEmpty { Text(detail).font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted) }
            }
            Spacer(minLength: 0)
        }
        .padding(12).background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
    }

    private func noticeMinute(_ value: String) -> Int? {
        guard value.range(of: "^(?:[01]\\d|2[0-3]):[0-5]\\d$", options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    @ViewBuilder
    private func remoteImage(_ path: String?, height: CGFloat) -> some View {
        GeometryReader { geometry in
            if let url = MobileAPI(store: store).mediaURL(path) {
                CachedRemoteImage(url: url) { imageFallback("Hero") }
                    .frame(width: geometry.size.width, height: height).clipped()
            } else {
                imageFallback("Hero").frame(width: geometry.size.width, height: height).clipped()
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func imageFallback(_ name: String?) -> some View {
        if let name {
            Image(name).resizable().scaledToFill()
        } else {
            Color(red: 0.94, green: 0.96, blue: 0.95)
                .overlay { Image(systemName: "photo").foregroundStyle(Brand.muted) }
        }
    }
}
