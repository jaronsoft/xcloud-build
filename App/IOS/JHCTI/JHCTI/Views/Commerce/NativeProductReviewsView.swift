import SwiftUI

struct NativeProductReviewsView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [[String: Any]] = []
    @State private var page = 1
    @State private var total = 0
    @State private var loading = false
    @State private var loadingMore = false
    @State private var error: String?
    @State private var failedPage: Int?
    @State private var appealId: String?
    @State private var appealText = ""
    @State private var submittingId = ""
    @State private var requestSequence = 0
    @State private var loadedToken = ""
    @State private var appealTask: Task<Void, Never>?
    @State private var previewingMediaURL: URL?

    private let pageSize = 20

    var body: some View {
        NavigationStack {
            Group {
                if loading && rows.isEmpty {
                    ProgressView("正在读取商品评价…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, rows.isEmpty {
                    VStack(spacing: 12) {
                        ContentUnavailableView(error, systemImage: "exclamationmark.arrow.circlepath",
                            description: Text("检查登录状态后重试。"))
                        Button("重试第 \(failedPage ?? 1) 页") {
                            let retryPage = failedPage ?? 1
                            Task { await load(reset: retryPage == 1, pageOverride: retryPage) }
                        }.disabled(loading || loadingMore)
                    }
                } else if rows.isEmpty {
                    ContentUnavailableView("暂无商品评价", systemImage: "text.bubble",
                        description: Text("已购商品评价提交后会显示在这里。"))
                } else {
                    List {
                        ForEach(rows.indices, id: \.self) { index in
                            reviewCard(rows[index])
                                .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                                .listRowSeparator(.hidden).listRowBackground(Brand.background)
                        }
                        if rows.count < total && error == nil {
                            Button(loadingMore ? "正在加载…" : "加载更多") { Task { await load(reset: false) } }
                                .frame(maxWidth: .infinity).listRowBackground(Brand.background).disabled(loadingMore)
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden).background(Brand.background)
                    .refreshable { await load(reset: true) }
                }
            }
            .background(Brand.background)
            .navigationTitle("我的商品评价").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .fullScreenCover(isPresented: Binding(
                get: { previewingMediaURL != nil },
                set: { if !$0 { previewingMediaURL = nil } }
            )) {
                if let url = previewingMediaURL {
                    ZStack(alignment: .topTrailing) {
                        Color.black.ignoresSafeArea()
                        CachedRemoteImage(url: url) { Color.black }
                            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                        Button("关闭") { previewingMediaURL = nil }
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.top, 12).padding(.trailing, 14)
                    }
                    .preferredColorScheme(.dark)
                }
            }
            .task(id: store.session?.accessToken ?? "") { await load(reset: true) }
            .onChange(of: store.session?.accessToken) { _, token in
                requestSequence += 1; appealTask?.cancel(); appealTask = nil
                submittingId = ""; rows = []; page = 1; total = 0; failedPage = nil; loading = false; loadingMore = false
                loadedToken = token ?? ""; error = token == nil ? "请先登录文旅账号，再查看商品评价。" : nil
            }
            .onDisappear {
                requestSequence += 1; appealTask?.cancel(); appealTask = nil
                rows = []; appealId = nil; appealText = ""
            }
            .alert("申诉提交结果未确认", isPresented: Binding(
                get: { error?.hasPrefix("申诉提交结果未确认") == true },
                set: { if !$0 { error = nil } }
            )) {
                Button("刷新核对") { Task { await load(reset: true) } }
                Button("关闭", role: .cancel) { error = nil }
            } message: { Text(error ?? "请刷新列表核对申诉状态，避免重复提交。") }
            .safeAreaInset(edge: .bottom) {
                if let error, !rows.isEmpty, !error.hasPrefix("申诉提交结果未确认") {
                    HStack {
                        Text(error).font(.system(size: 12)).foregroundStyle(.red).lineLimit(2)
                        Spacer()
                        Button(failedPage.map { "重试第 \($0) 页" } ?? "刷新并核对") {
                            let retryPage = failedPage
                            Task { await load(reset: retryPage == nil || retryPage == 1, pageOverride: retryPage) }
                        }.disabled(loading || loadingMore)
                    }.padding(10).background(.white)
                }
            }
        }
    }

    private func reviewCard(_ row: [String: Any]) -> some View {
        let id = Self.string(row, "Id") ?? ""
        let reviewStatus = Self.integer(row, "ReviewStatus") ?? -1
        let appealStatus = Self.integer(row, "AppealStatus") ?? -1
        let canAppeal = (reviewStatus == 2 || reviewStatus == 3) && [0, 2, 3].contains(appealStatus)
        let rating = max(0, min(5, Self.integer(row, "Rating") ?? 0))
        let mediaURLs = Self.mediaURLs(row, store: store)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(Self.string(row, "ProductName") ?? "商品")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text([0: "待审核", 1: "已通过", 2: "已拒绝", 3: "已隐藏"][reviewStatus] ?? "状态未知")
                    .font(.system(size: 12)).foregroundStyle(reviewStatus == 1 ? Brand.primary : Brand.muted)
            }
            Text(String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating))
                .font(.system(size: 14)).foregroundStyle(Color.orange)
            Text(Self.string(row, "Content") ?? "未填写评价内容")
                .font(.system(size: 14)).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
            if !mediaURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(mediaURLs.enumerated()), id: \.element) { index, url in
                            Button { previewingMediaURL = url } label: {
                                CachedRemoteImage(url: url) {
                                    Color(red: 0.92, green: 0.95, blue: 0.93)
                                        .overlay { Image(systemName: "photo").foregroundStyle(Brand.muted) }
                                }
                                .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("查看评价图片 \(index + 1)，共 \(mediaURLs.count) 张")
                        }
                    }
                }
            }
            if let reason = Self.string(row, "ModerationReason"), !reason.isEmpty {
                Text("处理说明：\(reason)").font(.system(size: 13)).foregroundStyle(Brand.muted)
            }
            Text("提交时间：\(Self.date(row, "CreateTime") ?? "—") · 申诉：\([0: "未申诉", 1: "待处理", 2: "申诉成立", 3: "申诉未通过"][appealStatus] ?? "状态未知")")
                .font(.system(size: 11)).foregroundStyle(Brand.muted).fixedSize(horizontal: false, vertical: true)
            if let content = Self.string(row, "AppealContent"), !content.isEmpty {
                Text("我的申诉：\(content)").font(.system(size: 13)).foregroundStyle(Brand.muted)
            }
            if let response = Self.string(row, "AppealResponse"), !response.isEmpty {
                Text("处理回复：\(response)").font(.system(size: 13)).foregroundStyle(Brand.muted)
            }
            if let reply = Self.string(row, "Reply"), !reply.isEmpty {
                Text("商户回复：\(reply)").font(.system(size: 13)).foregroundStyle(Brand.primary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(9).background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
            }
            if canAppeal && appealId != id {
                Button("提交申诉") { appealId = id; appealText = "" }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.primary)
                    .disabled(!submittingId.isEmpty)
            }
            if canAppeal && appealId == id {
                TextEditor(text: Binding(
                    get: { appealText },
                    set: { appealText = nativeLimitUtf16Text($0, maximum: 2000) }
                )).frame(minHeight: 100).padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.border))
                HStack {
                    Text("\(appealText.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count)/2000")
                        .font(.system(size: 11)).foregroundStyle(Brand.muted)
                    Spacer()
                    Button("取消") { appealId = nil; appealText = "" }.disabled(!submittingId.isEmpty)
                    Button(submittingId == id ? "提交中…" : "提交申诉") {
                        appealTask?.cancel()
                        appealTask = Task { await submitAppeal(id) }
                    }
                        .disabled(appealText.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count < 5
                            || appealText.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 2000
                            || !submittingId.isEmpty)
                }.font(.system(size: 13))
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 11))
    }

    @MainActor private func load(reset: Bool, pageOverride: Int? = nil) async {
        guard let token = store.session?.accessToken, !token.isEmpty else {
            requestSequence += 1; rows = []; total = 0; failedPage = nil; error = "请先登录文旅账号，再查看商品评价。"; loading = false; return
        }
        guard let requestedPrincipal = nativeTourismPrincipal(token) else {
            requestSequence += 1; rows = []; total = 0; failedPage = nil; error = "登录状态无效，请重新登录后查看商品评价。"; loading = false; return
        }
        let identityChanged = loadedToken != token
        let target = identityChanged ? 1 : (pageOverride ?? (reset ? 1 : page + 1))
        if identityChanged { rows = []; page = 1; total = 0; loadedToken = token; failedPage = nil }
        let replacesLoadedRows = target == 1
        if replacesLoadedRows { rows = []; total = 0 }
        requestSequence += 1; let sequence = requestSequence
        loading = replacesLoadedRows; loadingMore = !replacesLoadedRows; error = nil
        do {
            let path = "/api/JHCTIProductReview/GetMinePage?page=\(target)&pageSize=\(pageSize)"
            guard let result = try await MobileAPI(store: store).get(path, authenticated: true, expectedPrincipal: requestedPrincipal) as? [String: Any],
                  !Task.isCancelled, store.session?.accessToken == token, requestSequence == sequence,
                  let parsedPage = nativePublicCatalogPage(result, page: target, pageSize: pageSize) else {
                throw MobileAPIError.unavailable("商品评价回执格式异常，请刷新重试。")
            }
            let rawTotal = parsedPage.total
            let pageRows = parsedPage.rows
            var ids = Set<String>()
            for row in pageRows {
                guard ["Id", "ProductId", "OrderId", "OrderItemId"].allSatisfy({ Self.positiveId(row, $0) != nil }),
                      let id = Self.positiveId(row, "Id"), ids.insert(id).inserted,
                      let reviewStatus = Self.integer(row, "ReviewStatus"), (0...3).contains(reviewStatus),
                      let appealStatus = Self.integer(row, "AppealStatus"), appealStatus >= 0,
                      let content = Self.string(row, "Content"), content.utf16.count <= 2000,
                      let createTime = Self.date(row, "CreateTime"), !createTime.isEmpty else {
                    throw MobileAPIError.unavailable("商品评价字段异常，请刷新重试。")
                }
            }
            if target > 1 {
                let existingIDs = Set(rows.compactMap { Self.string($0, "Id") })
                guard pageRows.allSatisfy({ row in Self.string(row, "Id").map { !existingIDs.contains($0) } == true }) else {
                    throw MobileAPIError.unavailable("商品评价分页重复，请刷新后重试。")
                }
            }
            rows = replacesLoadedRows ? pageRows : rows + pageRows
            total = rawTotal; page = target; failedPage = nil
        } catch is CancellationError {
            return
        } catch {
            if store.session?.accessToken == token, requestSequence == sequence { failedPage = target; self.error = error.localizedDescription }
        }
        if requestSequence == sequence { loading = false; loadingMore = false }
    }

    @MainActor private func submitAppeal(_ id: String) async {
        let content = appealText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = store.session?.accessToken, Int64(id).map({ $0 > 0 }) == true,
              let requestedPrincipal = nativeTourismPrincipal(token),
              (5...2000).contains(content.utf16.count), submittingId.isEmpty else { return }
        submittingId = id; error = nil
        do {
            _ = try await MobileAPI(store: store).post("/api/JHCTIProductReview/SubmitAppeal",
                body: ["Id": id, "Content": content], authenticated: true, expectedPrincipal: requestedPrincipal)
            try Task.checkCancellation()
            guard store.session?.accessToken == token else { return }
            submittingId = ""; appealId = nil; appealText = ""
            await load(reset: true)
        } catch is CancellationError {
            if store.session?.accessToken == token { error = "申诉提交结果未确认，请刷新列表核对状态，避免重复提交。" }
            submittingId = ""
        } catch {
            if store.session?.accessToken == token { self.error = "申诉提交结果未确认：\(error.localizedDescription)；请刷新列表核对状态，避免重复提交。" }
            submittingId = ""
        }
    }

    private static func value(_ row: [String: Any], _ key: String) -> Any? {
        row[key] ?? row.first(where: { $0.key.lowercased() == key.lowercased() })?.value
    }

    private static func positiveId(_ row: [String: Any], _ key: String) -> String? {
        guard let raw = value(row, key) as? String, let number = Int64(raw), number > 0,
              String(number) == raw else { return nil }
        return raw
    }

    private static func string(_ row: [String: Any], _ key: String) -> String? {
        value(row, key) as? String
    }

    private static func integer(_ row: [String: Any], _ key: String) -> Int? {
        if let value = value(row, key) as? Int { return value }
        if let value = value(row, key) as? NSNumber { return value.intValue }
        return nil
    }

    private static func date(_ row: [String: Any], _ key: String) -> String? {
        guard let raw = string(row, key) else { return nil }
        return bookingBusinessDateTime(raw.replacingOccurrences(of: " ", with: "T"))
    }

    private static func mediaURLs(_ row: [String: Any], store: SessionStore) -> [URL] {
        let paths = (value(row, "MediaUrls") as? [String] ?? []).compactMap { raw -> URL? in
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.hasPrefix("//"), !path.contains("\\"), path.count <= 2048,
                  path.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
            return MobileAPI(store: store).mediaURL(path)
        }
        var seen = Set<String>()
        return Array(paths.filter { seen.insert($0.absoluteString).inserted }.prefix(9))
    }
}
