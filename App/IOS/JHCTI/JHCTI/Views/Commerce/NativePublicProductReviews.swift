import SwiftUI

struct NativePublicProductReviews: View {
    @ObservedObject var store: SessionStore
    let productID: String
    let reviewCount: Int
    let averageRating: Double
    @State private var rows: [[String: Any]] = []
    @State private var page = 1
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var failedPage = 1
    @State private var retry = 0
    @State private var previewURL: URL?
    @State private var previewFailed = false
    @State private var previewRetry = 0
    private let pageSize = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("已审核评价\(reviewCount > 0 ? " · \(reviewCount)" : "")")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.ink)
            if reviewCount > 0 && averageRating.isFinite && (1...5).contains(averageRating) {
                Text(String(format: "%.1f 分 · %d 条已审核评价", averageRating, reviewCount))
                    .font(.system(size: 12)).foregroundStyle(Brand.muted)
            }
            if loading && rows.isEmpty { ProgressView("正在加载已审核评价…").font(.system(size: 12)) }
            if rows.isEmpty && !loading && error == nil {
                Text("暂无已审核评价").font(.system(size: 12)).foregroundStyle(Brand.muted)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { entry in reviewCard(entry.element) }
            if let error {
                HStack {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
                    Spacer()
                    Button("重试") { page = failedPage; retry += 1 }.disabled(loading)
                }
            }
            if !loading && error == nil && rows.count < total {
                Button("查看更多评价") { page += 1 }.disabled(loading)
                    .frame(maxWidth: .infinity).font(.system(size: 13, weight: .semibold)).tint(Brand.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .task(id: "\(productID)-\(page)-\(retry)") { await load(requestedPage: page) }
        .onChange(of: productID) { _, _ in rows = []; page = 1; total = 0; error = nil; failedPage = 1 }
        .onChange(of: previewURL) { _, _ in previewFailed = false; previewRetry = 0 }
        .fullScreenCover(isPresented: Binding(get: { previewURL != nil }, set: { if !$0 { previewURL = nil } })) {
            if let url = previewURL {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    CachedRemoteImage(url: url, onLoadResult: { loaded in previewFailed = !loaded }) {
                        Color.black.overlay {
                            if previewFailed {
                                VStack(spacing: 10) {
                                    Text("评价图片暂时无法加载").foregroundStyle(.white)
                                    Button("重试") { previewFailed = false; previewRetry += 1 }.foregroundStyle(.white)
                                }
                            }
                        }
                    }
                    .id(previewRetry).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    Button("关闭") { previewURL = nil }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(12).background(.black.opacity(0.55), in: Capsule()).padding(12)
                }.preferredColorScheme(.dark)
            }
        }
    }

    @ViewBuilder private func reviewCard(_ row: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text((row["UserName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "游客")
                    .font(.system(size: 12)).foregroundStyle(Brand.muted)
                Spacer()
                Text(reviewDate(row["CreateTime"] as? String))
                    .font(.system(size: 11)).foregroundStyle(Brand.muted)
            }
            let rating = max(1, min(5, row["Rating"] as? Int ?? 0))
            Text(String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating))
                .font(.system(size: 13)).foregroundStyle(Color(red: 0.82, green: 0.54, blue: 0.20))
            Text((row["Content"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "评价者未填写文字内容。")
                .font(.system(size: 13)).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
            let media = reviewMediaURLs(row["MediaUrls"] as? [String] ?? [])
            if !media.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(media.enumerated()), id: \.element) { index, url in
                            Button { previewURL = url } label: {
                                CachedRemoteImage(url: url) {
                                    Color(red: 0.92, green: 0.95, blue: 0.93)
                                        .overlay { Image(systemName: "photo").foregroundStyle(Brand.muted) }
                                }
                                .frame(width: 68, height: 68).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain).accessibilityLabel("查看评价图片 \(index + 1)，共 \(media.count) 张")
                        }
                    }
                }
            }
            if let reply = row["Reply"] as? String, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("商家回复：\(reply)").font(.system(size: 12)).foregroundStyle(Brand.primary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                    .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.background, in: RoundedRectangle(cornerRadius: 11))
    }

    @MainActor private func load(requestedPage: Int) async {
        guard let numericID = Int64(productID), numericID > 0,
              String(numericID) == productID else { error = "商品编号无效"; return }
        loading = true; error = nil
        defer { if !Task.isCancelled { loading = false } }
        do {
            let path = "/api/JHCTIProductReview/GetPublicPage?productId=\(productID)&page=\(requestedPage)&pageSize=\(pageSize)"
            guard let response = try await MobileAPI(store: store).get(path) as? [String: Any] else {
                throw MobileAPIError.unavailable("商品评价分页响应格式异常")
            }
            try Task.checkCancellation()
            let returnedPage = response["page"] as? Int ?? response["Page"] as? Int ?? -1
            let returnedSize = response["PageSize"] as? Int ?? response["pageSize"] as? Int ?? -1
            let returnedTotal = response["dataCount"] as? Int ?? response["DataCount"] as? Int ?? -1
            guard let received = response["data"] as? [[String: Any]] ?? response["Data"] as? [[String: Any]],
                  returnedPage == requestedPage, returnedSize == pageSize, returnedTotal >= 0,
                  let expectedRows = nativeReportExpectedRows(page: requestedPage, total: returnedTotal, pageSize: pageSize),
                  received.count == expectedRows else {
                throw MobileAPIError.unavailable("商品评价分页回执异常")
            }
            for row in received {
                guard Self.validReview(row) else { throw MobileAPIError.unavailable("商品评价字段异常") }
            }
            try Task.checkCancellation()
            rows = requestedPage == 1 ? received : rows + received
            total = returnedTotal
        } catch is CancellationError {
            return
        } catch {
            failedPage = requestedPage
            self.error = error.localizedDescription
        }
    }

    private static func validReview(_ row: [String: Any]) -> Bool {
        guard let id = row["Id"] as? String, let number = Int64(id), number > 0, String(number) == id,
              let rating = row["Rating"] as? Int, (1...5).contains(rating),
              let content = row["Content"] as? String, content.utf16.count <= 2000,
              let created = row["CreateTime"] as? String, !created.isEmpty else { return false }
        return true
    }

    private func reviewMediaURLs(_ values: [String]) -> [URL] {
        var seen = Set<String>()
        return Array(values.compactMap { value -> URL? in
            let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard raw.count <= 2048, !raw.hasPrefix("//"), !raw.contains("\\"),
                  raw.rangeOfCharacter(from: .controlCharacters) == nil,
                  let url = MobileAPI(store: store).mediaURL(raw), url.scheme?.lowercased() == "https",
                  seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }.prefix(9))
    }

    private func reviewDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        return bookingBusinessDateTime(raw.replacingOccurrences(of: " ", with: "T")).map { String($0.prefix(10)) } ?? "—"
    }
}
