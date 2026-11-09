import SwiftUI

struct NativeProfileIdentitySection: View {
    let displayName: String
    let avatarURL: URL?
    let subtitle: String?
    let isAuthenticated: Bool
    let memberLevel: String
    let workAccess: [String]
    let onOpenProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                CachedRemoteImage(url: avatarURL) { Image("Logo").resizable().scaledToFit() }
                    .frame(width: 58, height: 58).clipShape(Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName).font(.system(size: NativeTypography.size(18), weight: .semibold))
                    if let subtitle {
                        Text(subtitle).font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            if isAuthenticated {
                HStack(spacing: 8) {
                    Text("👤 \(memberLevel)")
                    ForEach(workAccess.prefix(2), id: \.self) { title in
                        let badge: String = switch title {
                        case "商户工作台": "🏪 商户"
                        case "平台消费券核销": "🎟️ 平台券核销"
                        default: "🎫 核销"
                        }
                        Text(badge)
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 14)).foregroundStyle(Brand.primary)
                .lineLimit(1).minimumScaleFactor(0.85)
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [Color(red: 0.86, green: 0.94, blue: 0.92),
                                            Color(red: 0.94, green: 0.97, blue: 0.95)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 11))
        .onTapGesture(perform: onOpenProfile)
    }
}
struct NativeProfileWorkAccessSection: View {
    let workAccess: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("用户场景").font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.muted)
            Text("个人使用").font(.system(size: NativeTypography.size(18), weight: .semibold)).foregroundStyle(Brand.ink)
            Text("不同场景会显示不同功能，账号权限不变。")
                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(workAccess, id: \.self) { title in
                    Button { onSelect(title) } label: {
                        Text(title)
                            .font(.system(size: NativeTypography.size(13), weight: .medium))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .padding(.horizontal, 6).padding(.vertical, 5)
                            .background(Brand.primary, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 11))
    }
}

struct NativeProfileCommonServicesSection: View {
    let onSelect: (String) -> Void
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("常用服务").font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.muted)
            HStack(spacing: 6) {
                service("我的订单", note: "商城与预订")
                service("我的票券", note: "门票与凭证")
                service("消费券", note: "领券与券包")
            }
            Button(action: onShowAll) {
                HStack {
                    Text("全部服务").fontWeight(.semibold)
                    Spacer()
                    Text("按类别查看 ›").foregroundStyle(Brand.muted)
                }
                .font(.system(size: 14)).foregroundStyle(Brand.ink)
                .padding(.top, 10)
                .overlay(alignment: .top) { Brand.border.frame(height: 1) }
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(.white, in: RoundedRectangle(cornerRadius: 11))
    }

    private func service(_ title: String, note: String) -> some View {
        Button { onSelect(title) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.system(size: NativeTypography.size(14), weight: .semibold))
                        .foregroundStyle(Brand.ink).lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    Text("›").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                }
                Text(note).font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(Brand.ink)
            .padding(8).frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct NativeProfileAccountSettingsHeader: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack {
                Text("账号设置与协议")
                Spacer()
                Text("管理账号、查看协议 ›").font(.system(size: 12)).foregroundStyle(Brand.muted)
            }
            .font(.system(size: 14, weight: .medium)).foregroundStyle(Brand.ink)
            .padding(13).background(.white, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}
