import Foundation
import SwiftUI

struct HotelCatalogView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SessionStore
    @State private var rows: [[String: Any]] = []
    @State private var page = 1
    @State private var lastPageCount = 0
    @State private var total: Int?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var error: String?
    @State private var retryPage = 1
    @State private var requestSequence = 0
    @State private var pageLoadTask: Task<Void, Never>?
    @State private var hasAppeared = false
    @State private var initialLoadStarted = false
    private let pageSize = 10

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                NativePageHeader(title: "江都住宿", subtitle: "发现舒适旅居，看看酒店与特色民宿")

                if loading && rows.isEmpty {
                    ProgressView("正在加载住宿…").frame(maxWidth: .infinity).padding(30)
                } else if let error, rows.isEmpty {
                    VStack(spacing: 10) {
                        Text(error).font(.subheadline).foregroundStyle(.red).multilineTextAlignment(.center)
                        Button("重试加载") { startPageLoad(page: retryPage) }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity).padding(24)
                } else if rows.isEmpty {
                    VStack(spacing: 8) {
                        Text("暂时还没有可浏览的住宿信息").font(.headline).foregroundStyle(Brand.ink)
                        Button("刷新列表") { startPageLoad(page: 1, forceRefresh: true) }
                            .buttonStyle(.bordered).tint(Brand.primary)
                    }.frame(maxWidth: .infinity).padding(24)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, hotel in
                        NavigationLink {
                            HotelPublicDetailView(store: store, id: hotelID(hotel) ?? "")
                        } label: {
                            hotelCard(hotel)
                        }
                        .buttonStyle(.plain)
                    }
                    if let error {
                        Button("\(error)　重试") { startPageLoad(page: retryPage) }
                            .font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity).padding(10)
                    } else if hasMore {
                        Button(loadingMore ? "正在加载…" : "加载更多住宿") {
                            startPageLoad(page: page + 1)
                        }
                        .disabled(loadingMore).buttonStyle(.bordered).tint(Brand.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                    } else {
                        Text("已显示全部住宿信息").font(.caption).foregroundStyle(Brand.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
                Text("选择酒店后，可在详情页查询指定日期的房型、价格与余量。")
                    .font(.caption).foregroundStyle(Brand.muted).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background(Brand.background)
        .navigationTitle("江都住宿")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .simultaneousGesture(edgeBackGesture { dismiss() })
        .refreshable { await load(page: 1, forceRefresh: true) }
        .onAppear {
            if hasAppeared { startPageLoad(page: 1, forceRefresh: true) }
            else { hasAppeared = true }
        }
        .onDisappear {
            requestSequence += 1
            pageLoadTask?.cancel(); pageLoadTask = nil
            loading = false; loadingMore = false
        }
        .task {
            guard !initialLoadStarted else { return }
            initialLoadStarted = true
            await load(page: 1)
        }
    }

    private var hasMore: Bool { total.map { page * pageSize < $0 } ?? (lastPageCount >= pageSize) }

    @MainActor private func startPageLoad(page: Int, forceRefresh: Bool = false) {
        requestSequence += 1
        pageLoadTask?.cancel()
        pageLoadTask = Task { await load(page: page, forceRefresh: forceRefresh) }
    }

    private func hotelID(_ hotel: [String: Any]) -> String? {
        let value = hotel["Id"] ?? hotel["id"]
        let id = (value as? String) ?? (value as? NSNumber)?.stringValue
        guard let id, Int64(id).map({ $0 > 0 }) == true else { return nil }
        return id
    }

    private func hotelCard(_ hotel: [String: Any]) -> some View {
        HStack(spacing: 12) {
            if let url = MobileAPI(store: store).mediaURL(catalogCover(hotel)) {
                CachedRemoteImage(url: url) { Image("Quick3").resizable().scaledToFill() }
                    .frame(width: 105, height: 90).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ZStack {
                    Image("Quick3").resizable().scaledToFill()
                }.frame(width: 105, height: 90).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(hotel["Name"] as? String ?? hotel["name"] as? String ?? "江都住宿")
                    .font(.system(size: NativeTypography.size(15), weight: .semibold)).foregroundStyle(Brand.ink).lineLimit(1)
                Text(hotel["Address"] as? String ?? hotel["address"] as? String ?? "查看住宿地址")
                    .font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted).lineLimit(2)
                let amenities = hotel["Amenities"] as? [String] ?? hotel["amenities"] as? [String] ?? []
                let amenitiesText = amenities.prefix(3).joined(separator: " · ")
                Text(amenitiesText.isEmpty ? "查看住宿设施" : amenitiesText)
                    .font(.system(size: NativeTypography.size(10))).foregroundStyle(Brand.muted).lineLimit(1)
                Text("选择日期查看房型与价格").font(.system(size: NativeTypography.size(10), weight: .medium)).foregroundStyle(Brand.primary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: NativeTypography.size(11), weight: .semibold)).foregroundStyle(Brand.muted)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.border.opacity(0.55), lineWidth: 1))
    }

    @MainActor private func load(page requestedPage: Int, forceRefresh: Bool = false) async {
        guard requestedPage == 1 || !loadingMore else { return }
        if requestedPage == 1 { requestSequence += 1 }
        let sequence = requestSequence
        retryPage = requestedPage
        if requestedPage == 1 { loading = true; rows = []; page = 1; total = nil; lastPageCount = 0; error = nil }
        else { loadingMore = true; error = nil }
        defer {
            if sequence == requestSequence { loading = false; loadingMore = false }
        }
        do {
            guard await MobileAPI(store: store).featureEnabled("MODULE-HOTEL") else {
                throw MobileAPIError.unavailable("住宿模块暂未开放")
            }
            let path = "/api/JHCTIHotel/GetPublicPage?page=\(requestedPage)&pageSize=\(pageSize)"
            let value = try await MobileAPI(store: store).getPublicCached(path, forceRefresh: forceRefresh) as? [String: Any]
            guard sequence == requestSequence else { return }
            guard let value,
                  let parsed = nativePublicCatalogPage(value, page: requestedPage, pageSize: pageSize) else {
                throw MobileAPIError.unavailable("住宿列表分页回执异常，请刷新后重试。")
            }
            let loaded = parsed.rows
            let ids = loaded.compactMap(hotelID)
            guard ids.count == loaded.count, Set(ids).count == ids.count else {
                throw MobileAPIError.unavailable("住宿编号异常，请刷新重试。")
            }
            if requestedPage > 1 {
                let existing = Set(rows.compactMap(hotelID))
                guard ids.allSatisfy({ !existing.contains($0) }) else {
                    throw MobileAPIError.unavailable("住宿分页重复，请刷新列表后重试。")
                }
            }
            rows = requestedPage == 1 ? loaded : rows + loaded
            page = requestedPage
            lastPageCount = loaded.count
            total = parsed.total
        } catch {
            if sequence == requestSequence { self.error = error.localizedDescription }
        }
    }
}
