import SwiftUI

struct NativeHomeCatalogSection: View {
    let store: SessionStore
    let module: CatalogModule
    let rows: [[String: Any]]?
    let error: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                CatalogView(store: store, module: module)
            } label: { NativeHomeSectionHeader(title: module.title) }.buttonStyle(.plain)
            if let error {
                VStack(alignment: .leading, spacing: 5) {
                    Text(error).font(.system(size: NativeTypography.size(12))).foregroundStyle(.red)
                    Button("重试读取", action: onRetry).font(.system(size: NativeTypography.size(12)))
                }
            } else if let rows, !rows.isEmpty {
                if module.id == "articles" {
                    ForEach(rows.indices, id: \.self) { index in
                        NavigationLink {
                            ArticleDetailView(store: store, id: rows[index]["Id"] as? String ?? "",
                                              siteID: module.siteID)
                        } label: {
                            HStack(spacing: 10) {
                                catalogImage(catalogCover(rows[index]), height: 62)
                                    .frame(width: 82)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rows[index]["Title"] as? String ?? "文旅资讯")
                                        .font(.system(size: NativeTypography.size(13), weight: .semibold)).lineLimit(3)
                                    Text(rows[index]["HeadLine"] as? String ?? "")
                                        .font(.system(size: NativeTypography.size(10))).foregroundStyle(Brand.muted).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }.foregroundStyle(Brand.ink).padding(6)
                                .background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(rows.indices, id: \.self) { index in
                            NavigationLink {
                                if module.id == "products" {
                                    ProductDetailView(store: store, id: rows[index]["Id"] as? String ?? "",
                                                      fallbackCover: catalogCover(rows[index]))
                                } else if module.id == "activities" {
                                    ActivityDetailView(store: store, id: rows[index]["Id"] as? String ?? "")
                                } else if module.id == "hotels" {
                                    HotelPublicDetailView(store: store, id: rows[index]["Id"] as? String ?? "")
                                } else { CatalogView(store: store, module: module) }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    catalogImage(catalogCover(rows[index]), height: 100)
                                    Text(rows[index]["Name"] as? String ?? module.title)
                                        .font(.system(size: NativeTypography.size(13), weight: .semibold))
                                        .foregroundStyle(Brand.ink).lineLimit(1)
                                    if module.id == "products",
                                       let price = nativeProductPrice(rows[index]["MinPrice"]) {
                                        Text("¥\(price, specifier: "%.2f") 起")
                                            .font(.system(size: NativeTypography.size(12), weight: .semibold))
                                            .foregroundStyle(Color(red: 0.72, green: 0.27, blue: 0.20))
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("暂无已发布内容").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func catalogImage(_ path: String?, height: CGFloat) -> some View {
        GeometryReader { geometry in
            if let url = MobileAPI(store: store).mediaURL(path) {
                CachedRemoteImage(url: url) { imageFallback }
                    .frame(width: geometry.size.width, height: height).clipped()
            } else {
                imageFallback.frame(width: geometry.size.width, height: height).clipped()
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var imageFallback: some View {
        Color(red: 0.94, green: 0.96, blue: 0.95)
            .overlay { Image(systemName: "photo").foregroundStyle(Brand.muted) }
    }
}

struct NativeHomeSectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: NativeTypography.size(17), weight: .bold)).foregroundStyle(Brand.ink)
                Brand.primary.frame(width: 22, height: 2)
            }
            Spacer()
            Text("查看更多 ›").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
        }
    }
}
