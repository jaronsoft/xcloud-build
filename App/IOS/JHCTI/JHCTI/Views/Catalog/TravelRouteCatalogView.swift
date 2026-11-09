import Foundation
import SwiftUI

struct TravelRouteCatalogView: View {
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
    @State private var bookingStatusTask: Task<Void, Never>?
    @State private var hasAppeared = false
    @State private var initialLoadStarted = false
    @State private var bookingNote = "正在确认预订服务状态…"
    @State private var bookingStatus = "loading"
    private let pageSize = 10

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                NativePageHeader(title: "旅游线路", subtitle: "仅展示平台已审核发布且当前可浏览的线路")

                if loading && rows.isEmpty {
                    ProgressView("正在加载线路…").frame(maxWidth: .infinity).padding(30)
                } else if let error, rows.isEmpty {
                    VStack(spacing: 10) {
                        Text(error).font(.subheadline).foregroundStyle(.red).multilineTextAlignment(.center)
                        Button("重试加载") { startPageLoad(page: retryPage) }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity).padding(24)
                } else if rows.isEmpty {
                    VStack(spacing: 8) {
                        Text("暂无可浏览的旅游线路").font(.headline).foregroundStyle(Brand.ink)
                        Text("线路发布后会显示在这里，稍后可以重新查询。")
                            .font(.caption).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
                        Button("刷新列表") { startPageLoad(page: 1, forceRefresh: true) }
                            .buttonStyle(.bordered).tint(Brand.primary)
                    }.frame(maxWidth: .infinity).padding(24)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, route in
                        NavigationLink {
                            TravelRouteDetailView(store: store, id: route["Id"] as? String ?? "")
                        } label: {
                            routeCard(route)
                        }
                        .buttonStyle(.plain)
                    }
                    if let error {
                        Button("\(error)　重试") { startPageLoad(page: retryPage) }
                            .font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity).padding(10)
                    } else if hasMore {
                        Button(loadingMore ? "正在加载…" : "加载更多线路") {
                            startPageLoad(page: page + 1)
                        }
                        .disabled(loadingMore).buttonStyle(.bordered).tint(Brand.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                    } else {
                        Text("已显示全部线路").font(.caption).foregroundStyle(Brand.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Text(bookingNote).font(.caption).foregroundStyle(bookingStatus == "open" ? Brand.primary : Brand.muted)
                    if bookingStatus == "unavailable" {
                        Button("重试") { startBookingStatusLoad() }.font(.caption).tint(Brand.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(bookingStatus == "open" ? Color.green.opacity(0.08) : Brand.background,
                    in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(16)
        }
        .background(Brand.background)
        .navigationTitle("旅游线路")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .simultaneousGesture(edgeBackGesture { dismiss() })
        .refreshable {
            async let list: Void = load(page: 1, forceRefresh: true)
            async let access: Void = loadBookingStatus()
            _ = await (list, access)
        }
        .onAppear {
            if hasAppeared {
                startPageLoad(page: 1, forceRefresh: true)
                startBookingStatusLoad()
            } else { hasAppeared = true }
        }
        .onDisappear {
            requestSequence += 1
            pageLoadTask?.cancel(); pageLoadTask = nil
            bookingStatusTask?.cancel(); bookingStatusTask = nil
            loading = false; loadingMore = false
        }
        .task {
            guard !initialLoadStarted else { return }
            initialLoadStarted = true
            async let list: Void = load(page: 1)
            async let access: Void = loadBookingStatus()
            _ = await (list, access)
        }
    }

    private var hasMore: Bool { total.map { page * pageSize < $0 } ?? (lastPageCount >= pageSize) }

    @MainActor private func startPageLoad(page: Int, forceRefresh: Bool = false) {
        requestSequence += 1
        pageLoadTask?.cancel()
        pageLoadTask = Task { await load(page: page, forceRefresh: forceRefresh) }
    }

    @MainActor private func startBookingStatusLoad() {
        bookingStatusTask?.cancel()
        bookingStatusTask = Task { await loadBookingStatus() }
    }

    private func routeCard(_ route: [String: Any]) -> some View {
        HStack(spacing: 12) {
            NativeRouteThemeImage(store: store, path: catalogCover(route))
                .frame(width: 105, height: 84).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(route["Name"] as? String ?? "江都旅游线路").font(.system(size: NativeTypography.size(15), weight: .semibold))
                    .foregroundStyle(Brand.ink).lineLimit(1)
                let destination = route["Destination"] as? String ?? "扬州江都"
                let days = (route["DurationDays"] as? Int) ?? 0
                Text("\(destination) · \(days > 0 ? "\(days) 日行程" : "查看行程安排")")
                    .font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted).lineLimit(1)
                Text(route["Summary"] as? String ?? route["MeetingPoint"] as? String ?? "查看线路介绍与每日安排")
                    .font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted).lineLimit(2)
                if let session = (route["Sessions"] as? [[String: Any]])?.first {
                    let date = bookingBusinessDateTime(session["DepartureDate"]) ?? "出发日期待确认"
                    let price = (session["Price"] as? NSNumber)?.doubleValue
                    let availability = (session["AvailableCount"] as? NSNumber)?.intValue ?? 0
                    Text("\(date) · 余位 \(availability) · \(price.map { "¥\(String(format: "%.2f", $0))/人 起" } ?? "查看班期")")
                        .font(.system(size: NativeTypography.size(10), weight: .medium)).foregroundStyle(Brand.primary).lineLimit(1)
                }
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
            guard await MobileAPI(store: store).featureEnabled("MODULE-TRAVEL-ROUTE") else {
                throw MobileAPIError.unavailable("旅游线路暂未开放")
            }
            let path = "/api/JHCTITravelRoute/GetPublicPage?page=\(requestedPage)&pageSize=\(pageSize)&guests=1"
            let value = try await MobileAPI(store: store).getPublicCached(path, forceRefresh: true) as? [String: Any]
            guard sequence == requestSequence else { return }
            guard let value,
                  let parsed = nativePublicCatalogPage(value, page: requestedPage, pageSize: pageSize) else {
                throw MobileAPIError.unavailable("线路列表分页回执异常，请刷新后重试。")
            }
            let loaded = parsed.rows
            let ids = loaded.compactMap { $0["Id"] as? String }
            guard ids.count == loaded.count, ids.allSatisfy({ Int64($0).map { $0 > 0 } == true }),
                  Set(ids).count == ids.count else { throw MobileAPIError.unavailable("线路编号异常，请刷新重试。") }
            if requestedPage > 1 {
                let existing = Set(rows.compactMap { $0["Id"] as? String })
                guard ids.allSatisfy({ !existing.contains($0) }) else {
                    throw MobileAPIError.unavailable("线路分页重复，请刷新列表后重试。")
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

    @MainActor private func loadBookingStatus() async {
        bookingStatus = "loading"; bookingNote = "正在确认预订服务状态…"
        do {
            guard let value = try await MobileAPI(store: store).get("/api/JHCTIFeatureAccess/GetPublicStatus?featureId=F-DST-002") as? [String: Any] else {
                throw MobileAPIError.unavailable("服务状态响应格式异常")
            }
            let configured = value["IsConfigured"] as? Bool ?? value["isConfigured"] as? Bool ?? false
            let enabled = value["IsEnabled"] as? Bool ?? value["isEnabled"] as? Bool ?? false
            bookingStatus = configured && enabled ? "open" : "closed"
            bookingNote = configured && enabled
                ? "预订服务已开放；可订班期以线路详情实时信息为准，订单可在“我的旅游线路”查看。"
                : "当前仅提供线路浏览，预订与支付暂未开放。"
        } catch is CancellationError {
            return
        } catch {
            bookingStatus = "unavailable"; bookingNote = "暂时无法确认预订服务状态；仍可浏览线路，详情页会再次核验。"
        }
    }
}
