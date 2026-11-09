import SwiftUI

private struct ActivityRegistrationQrRetry: Equatable {
    let registrationID: String
    let title: String
    let token: String
    let message: String
}

struct ActivityRegistrationsView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [[String: Any]] = []
    @State private var filter = ""
    @State private var page = 1
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var pendingCancellation: [String: Any]?
    @State private var cancelBusyId = ""
    @State private var cancellationToken = ""
    @State private var cancelSequence = 0
    @State private var qrImage: Data?
    @State private var qrTitle = ""
    @State private var qrBusyId = ""
    @State private var qrRetry: ActivityRegistrationQrRetry?
    @State private var revision = 0
    @State private var requestSequence = 0
    @State private var loadedToken = ""
    @State private var credentialClock = Date()
    @State private var qrRegistrationId = ""
    @State private var qrCheckedIn = false
    @State private var qrStatusCountdown = 5
    @State private var qrSequence = 0
    @State private var pendingDeletion: [String: Any]?
    @State private var deletionToken = ""
    @State private var deleteBusyId = ""
    @State private var deleteSequence = 0
    @State private var expiredDeleteRetryItem: [String: Any]?
    @State private var expiredDeleteRetryToken = ""
    @State private var pageVisible = true
    @State private var canLoadMore = false
    @State private var cancellationNotice: String?

    private let filters = [("", "全部"), ("Registered", "已报名"), ("CheckedIn", "已签到"), ("Cancelled", "已取消")]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ActivityRegistrationSelfCheckIn(store: store) { revision += 1 }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.0) { item in
                            Button(item.1) { filter = item.0; revision += 1 }
                                .accessibilityLabel("筛选\(item.1)活动报名")
                                .accessibilityAddTraits(filter == item.0 ? .isSelected : [])
                                .disabled(!deleteBusyId.isEmpty || !cancelBusyId.isEmpty)
                                .font(.system(size: NativeTypography.size(14), weight: .semibold))
                                .foregroundStyle(filter == item.0 ? .white : Brand.primary)
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                .background(filter == item.0 ? Brand.primary : .white, in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("活动报名状态筛选")
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                List {
                    if rows.isEmpty {
                        let emptyStatusLabel = filter == "Registered" ? "已报名"
                            : filter == "CheckedIn" ? "已签到"
                            : filter == "Cancelled" ? "已取消" : ""
                        Group {
                            if loading { ProgressView("正在读取报名记录…").frame(maxWidth: .infinity).padding(.vertical, 40) }
                            else if let error {
                                VStack(spacing: 8) {
                                    ContentUnavailableView(error, systemImage: "exclamationmark.arrow.circlepath", description: Text("检查登录状态后点击重试。"))
                                    Button("重试") { Task { await load(reset: true) } }
                                        .disabled(loading)
                                }
                            }
                            else { ContentUnavailableView("暂无\(emptyStatusLabel)活动报名记录。", systemImage: "ticket", description: Text("报名成功后，签到凭证会显示在这里。")) }
                        }.listRowSeparator(.hidden).listRowBackground(Brand.background)
                    }
                    ForEach(rows.indices, id: \.self) { index in
                        registrationCard(rows[index])
                            .listRowInsets(EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Brand.background)
                    }
                    if !rows.isEmpty, error == nil {
                        Text("共 \(total) 条报名记录")
                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                            .frame(maxWidth: .infinity).listRowSeparator(.hidden)
                            .listRowBackground(Brand.background)
                    }
                    if canLoadMore {
                        Button(loading ? "正在加载…" : "加载更多") { Task { await load(reset: false) } }
                            .frame(maxWidth: .infinity).listRowBackground(Brand.background)
                            .disabled(loading)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Brand.background)
                .refreshable { await load(reset: true) }
                ActivityCancellationStatusBanner(message: cancellationNotice)
                if let expiredDeleteRetryItem, !expiredDeleteRetryToken.isEmpty {
                    Button(deleteBusyId.isEmpty ? "重试删除过期报名" : "正在删除…") {
                        guard store.session?.accessToken == expiredDeleteRetryToken else {
                            cancellationNotice = "登录账号已变化，请刷新报名记录后重试。"
                            self.expiredDeleteRetryItem = nil; self.expiredDeleteRetryToken = ""; return
                        }
                        Task { await deleteExpired(expiredDeleteRetryItem, expectedToken: expiredDeleteRetryToken) }
                    }
                    .disabled(loading || !deleteBusyId.isEmpty || store.session?.accessToken != expiredDeleteRetryToken)
                    .padding(.horizontal, 14).padding(.bottom, 6)
                }
                if let error, !rows.isEmpty {
                    VStack(spacing: 4) {
                        Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                        Button("重试") { Task { await load(reset: true) } }
                            .disabled(loading)
                    }.padding(8)
                }
            }
            .background(Brand.background)
            .navigationTitle("我的活动报名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("刷新") { revision += 1 }.disabled(loading || !cancelBusyId.isEmpty || !deleteBusyId.isEmpty) }
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .task(id: "\(store.session?.accessToken ?? "")-\(filter)-\(revision)") { await load(reset: true) }
            .task {
                while !Task.isCancelled {
                    refreshCredentialClock()
                    if !qrRegistrationId.isEmpty && !qrCheckedIn {
                        if qrStatusCountdown <= 1 {
                            qrStatusCountdown = 5
                            await load(reset: true, preserveQr: true)
                        } else { qrStatusCountdown -= 1 }
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshCredentialClock(); revision += 1 }
                else {
                    requestSequence += 1; clearQr(); rows = []; total = 0; loadedToken = ""; canLoadMore = false; loading = false
                    pendingCancellation = nil; pendingDeletion = nil
                    expiredDeleteRetryItem = nil; expiredDeleteRetryToken = ""
                }
            }
            .onChange(of: filter) { _, _ in
                clearQr(); pendingCancellation = nil; expiredDeleteRetryItem = nil; expiredDeleteRetryToken = ""
            }
            .onChange(of: store.session?.accessToken) { _, newToken in
                clearQr()
                cancelSequence += 1; cancelBusyId = ""; pendingCancellation = nil; cancellationToken = ""
                deleteSequence += 1; deleteBusyId = ""; pendingDeletion = nil; deletionToken = ""
                requestSequence += 1; rows = []; total = 0; loadedToken = newToken ?? ""; loading = false
                canLoadMore = false
                expiredDeleteRetryItem = nil; expiredDeleteRetryToken = ""
            }
            .sheet(isPresented: Binding(get: { qrImage != nil }, set: { if !$0 { closeQrAndRefresh() } })) {
                NavigationStack {
                    VStack(spacing: 12) {
                        Text(qrCheckedIn ? "活动签到成功" : qrTitle).font(.system(size: NativeTypography.size(18), weight: .semibold))
                        if qrCheckedIn {
                            Text("现场核验已完成，报名状态已更新为“已签到”。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                        } else if let qrImage, let image = UIImage(data: qrImage) {
                            Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                                .frame(maxWidth: 280, maxHeight: 280).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                            Text("\(qrStatusCountdown) 秒后自动查询核验状态")
                                .font(.system(size: NativeTypography.size(13))).foregroundStyle(Brand.primary)
                            Text("请向活动现场工作人员出示二维码；未核验时会继续查询。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
                        }
                    }
                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Brand.background)
                    .navigationTitle("活动签到二维码").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("关闭") { closeQrAndRefresh() } }
                }
            }
            .onDisappear {
                pageVisible = false; canLoadMore = false
                requestSequence += 1; rows = []; clearQr(); pendingCancellation = nil
                cancelSequence += 1; cancelBusyId = ""; cancellationToken = ""
                deleteSequence += 1; deleteBusyId = ""; pendingDeletion = nil; deletionToken = ""
                expiredDeleteRetryItem = nil; expiredDeleteRetryToken = ""
            }
            .onAppear { pageVisible = true }
            .overlay {
                if let pendingDeletion {
                    ZStack {
                        Color.black.opacity(0.48).ignoresSafeArea()
                            .onTapGesture { self.pendingDeletion = nil }
                        VStack(spacing: 0) {
                            Text("删除过期报名")
                                .font(.system(size: NativeTypography.size(17), weight: .semibold))
                                .foregroundStyle(Color(red: 0.15, green: 0.23, blue: 0.21))
                                .padding(.top, 22)
                            Text("该活动场次已结束，删除后将从报名记录中移除。")
                                .font(.system(size: NativeTypography.size(14)))
                                .foregroundStyle(Color(red: 0.54, green: 0.56, blue: 0.55))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 22).padding(.vertical, 16)
                            Rectangle().fill(Color(red: 0.91, green: 0.92, blue: 0.92)).frame(height: 1)
                            HStack(spacing: 0) {
                                Button("保留") { self.pendingDeletion = nil }
                                    .font(.system(size: NativeTypography.size(15), weight: .medium))
                                    .foregroundStyle(Color(red: 0.15, green: 0.23, blue: 0.21))
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                Rectangle().fill(Color(red: 0.91, green: 0.92, blue: 0.92)).frame(width: 1, height: 54)
                                Button(deleteBusyId == (pendingDeletion["Id"] as? String ?? "") ? "正在删除…" : "删除", role: .destructive) {
                                    let token = store.session?.accessToken ?? ""
                                    deletionToken = token
                                    Task { await deleteExpired(pendingDeletion, expectedToken: token) }
                                }
                                .font(.system(size: NativeTypography.size(15), weight: .semibold))
                                .foregroundStyle(Color(red: 0.70, green: 0.34, blue: 0.29))
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .disabled(!deleteBusyId.isEmpty)
                            }
                        }
                        .frame(maxWidth: 340)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 24)
                        .accessibilityElement(children: .contain)
                    }
                    .transition(.opacity)
                    .zIndex(100)
                } else if let pendingCancellation {
                    let rawActivityName = pendingCancellation["ActivityName"] as? String ?? ""
                    let activityName = rawActivityName.trimmingCharacters(in: .whitespacesAndNewlines)
                    ZStack {
                        Color.black.opacity(0.48).ignoresSafeArea()
                            .onTapGesture { if cancelBusyId.isEmpty { self.pendingCancellation = nil } }
                        VStack(spacing: 0) {
                            Text("取消活动报名")
                                .font(.system(size: NativeTypography.size(17), weight: .semibold))
                                .foregroundStyle(Color(red: 0.15, green: 0.23, blue: 0.21))
                                .padding(.top, 22)
                            Text("确定取消“\(activityName.isEmpty ? "文旅活动" : activityName)”的报名吗？取消后将按活动规则释放名额。")
                                .font(.system(size: NativeTypography.size(14)))
                                .foregroundStyle(Color(red: 0.54, green: 0.56, blue: 0.55))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 22).padding(.vertical, 16)
                            Rectangle().fill(Color(red: 0.91, green: 0.92, blue: 0.92)).frame(height: 1)
                            HStack(spacing: 0) {
                                Button("暂不取消") { self.pendingCancellation = nil }
                                    .font(.system(size: NativeTypography.size(15), weight: .medium))
                                    .foregroundStyle(Color(red: 0.15, green: 0.23, blue: 0.21))
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .disabled(!cancelBusyId.isEmpty)
                                Rectangle().fill(Color(red: 0.91, green: 0.92, blue: 0.92)).frame(width: 1, height: 54)
                                Button(cancelBusyId.isEmpty ? "确认取消" : "正在取消…", role: .destructive) {
                                    let token = cancellationToken
                                    Task { await cancel(pendingCancellation, expectedToken: token) }
                                }
                                .font(.system(size: NativeTypography.size(15), weight: .semibold))
                                .foregroundStyle(Color(red: 0.70, green: 0.34, blue: 0.29))
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .disabled(!cancelBusyId.isEmpty)
                            }
                        }
                        .frame(maxWidth: 340)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 24)
                        .accessibilityElement(children: .contain)
                    }
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
        }
    }

    private func closeQrAndRefresh() {
        let wasVisible = qrImage != nil
        clearQr()
        if wasVisible && pageVisible && scenePhase == .active { revision += 1 }
    }

    @ViewBuilder private func registrationCard(_ item: [String: Any]) -> some View {
        let id = item["Id"] as? String ?? ""
        let status = item["Status"] as? String ?? ""
        let expectedToken = store.session?.accessToken
        let expired = activityRegistrationExpired(item, now: credentialClock)
        let expiryUnknown = activityRegistrationExpiryUnknown(item)
        let credentialUnavailable = activityRegistrationCredentialUnavailable(item, now: credentialClock)
        let statusText = expired ? "已过期" : expiryUnknown ? "确认状态中" : status == "Registered" ? "已报名" : status == "CheckedIn" ? "已签到" : status == "Cancelled" ? "已取消" : "待核对"
        let statusColor: Color = expired ? Color(red: 0.70, green: 0.34, blue: 0.29)
            : expiryUnknown ? Color(red: 0.70, green: 0.47, blue: 0.10)
            : status == "Cancelled" ? .gray
            : status == "CheckedIn" ? Color(red: 0.16, green: 0.48, blue: 0.37)
            : Brand.primary
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(item["ActivityName"] as? String ?? "活动报名").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(statusText).font(.system(size: NativeTypography.size(12), weight: .semibold)).foregroundStyle(statusColor)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(statusColor.opacity(0.10), in: Capsule())
            }
            if let session = item["SessionName"] as? String, !session.isEmpty {
                Label(session, systemImage: "calendar")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
            }
            HStack(spacing: 14) {
                Label("\(item["Quantity"] as? Int ?? 1) 人", systemImage: "person.2")
                Label(activityRegistrationBusinessDateTime(item["CreateTime"]) ?? "—", systemImage: "clock")
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            if let participants = item["Participants"] as? [[String: Any]] {
                ForEach(Array(participants.enumerated()), id: \.offset) { index, participant in
                    let name = (participant["DisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                        ?? "参与者 \(participant["ParticipantNo"] as? Int ?? index + 1)"
                    let participantStatus = activityRegistrationParticipantStatus(participant["Status"])
                    let checkedInAt = activityRegistrationBusinessDateTime(participant["CheckedInAt"])
                    Text("\(name)：\(participantStatus)\(checkedInAt.map { " · \($0)" } ?? "")")
                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                }
            }
            if let cancelledAt = activityRegistrationBusinessDateTime(item["CancelledAt"]) {
                Text("取消时间：\(cancelledAt)").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            }
            if let checkedInAt = activityRegistrationBusinessDateTime(item["CheckedInAt"]) {
                Text("签到时间：\(checkedInAt)").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
            }
            if status == "Registered" && !credentialUnavailable {
                if let code = item["CredentialCode"] as? String, !code.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "ticket").foregroundStyle(Brand.primary)
                        Text("签到码").font(.system(size: NativeTypography.size(14), weight: .medium)).foregroundStyle(Brand.muted)
                        Text(code).font(.system(size: NativeTypography.size(14), weight: .semibold, design: .monospaced))
                            .foregroundStyle(Brand.primary).lineLimit(1).minimumScaleFactor(0.75).textSelection(.enabled)
                        Button("复制") {
                            guard pageVisible, scenePhase == .active,
                                  let expectedToken, !expectedToken.isEmpty,
                                  store.session?.accessToken == expectedToken, loadedToken == expectedToken,
                                  let currentItem = rows.first(where: { $0["Id"] as? String == id }),
                                  currentItem["Status"] as? String == "Registered",
                                  currentItem["CredentialCode"] as? String == code,
                                  !activityRegistrationCredentialUnavailable(currentItem, now: Date()) else {
                                cancellationNotice = "签到凭证已变化或过期，请刷新报名记录。"
                                revision += 1
                                return
                            }
                            UIPasteboard.general.string = code
                            cancellationNotice = "签到凭证已复制。"
                        }
                        .font(.system(size: NativeTypography.size(12), weight: .semibold))
                        .tint(Brand.primary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    HStack {
                        Button(qrBusyId == id ? "正在生成…" : "出示签到二维码") { Task { await showQr(id: id, title: item["ActivityName"] as? String ?? "活动报名") } }
                            .disabled(!qrBusyId.isEmpty)
                        Spacer()
                        if item["CanCancel"] as? Bool == true {
                            Button("取消报名", role: .destructive) {
                                cancellationToken = store.session?.accessToken ?? ""; pendingCancellation = item
                            }.disabled(loading || !cancelBusyId.isEmpty || !deleteBusyId.isEmpty)
                        }
                    }.font(.system(size: NativeTypography.size(14), weight: .semibold)).tint(Brand.primary)
                    if let qrRetry, qrRetry.registrationID == id, qrRetry.token == expectedToken {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(qrRetry.message).font(.system(size: NativeTypography.size(12))).foregroundStyle(.red)
                            Button("重试显示二维码") {
                                guard store.session?.accessToken == qrRetry.token else { self.qrRetry = nil; return }
                                Task { await showQr(id: qrRetry.registrationID, title: qrRetry.title) }
                            }
                            .accessibilityLabel("重试显示\(qrRetry.title)签到二维码")
                            .disabled(!qrBusyId.isEmpty)
                        }
                    }
                }
            } else if status == "Registered" && expired {
                Text("活动已结束，签到凭证已失效。")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                Button(deleteBusyId == id ? "正在删除…" : "删除记录", role: .destructive) {
                    deletionToken = store.session?.accessToken ?? ""
                    pendingDeletion = item
                }.disabled(loading || !deleteBusyId.isEmpty || !cancelBusyId.isEmpty)
            } else if status == "Registered" && expiryUnknown {
                Text("签到凭证有效期暂无法确认，请刷新报名状态。")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                Button("刷新状态") { revision += 1 }.disabled(loading)
            } else if status == "Registered" && item["CanCancel"] as? Bool != true {
                Text("已超过取消时限或已有参与者签到，不可取消")
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
            }
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    @MainActor private func load(reset: Bool, preserveQr: Bool = false) async {
        guard pageVisible, scenePhase == .active else { return }
        if !reset && (loading || !canLoadMore) { return }
        guard let token = store.session?.accessToken, !token.isEmpty,
              let expectedPrincipal = nativeTourismPrincipal(token) else {
            rows = []; total = 0; canLoadMore = false; loadedToken = ""; error = "请先登录文旅账号，再查看活动报名记录。"; loading = false; return
        }
        let requestedFilter = filter
        let queryFilter = requestedFilter
        if !reset && loadedToken != token { rows = []; total = 0; canLoadMore = false; error = "登录状态已变化，请刷新报名记录。"; return }
        let cursor = reset ? nil : rows.last?["Id"] as? String
        if !reset && cursor.flatMap({ Int64($0) }).map({ $0 > 0 && String($0) == cursor }) != true {
            canLoadMore = false; error = "报名记录游标无效，请刷新后继续。"; return
        }
        if !preserveQr { clearQr(); pendingCancellation = nil; pendingDeletion = nil }
        let targetPage = reset ? 1 : page + 1
        if reset && !preserveQr { rows = []; total = 0; page = 1; loadedToken = ""; canLoadMore = false }
        loading = true
        if !preserveQr { error = nil }
        let sequence = requestSequence + 1; requestSequence = sequence
        func isCurrent() -> Bool {
            !Task.isCancelled && sequence == requestSequence && store.session?.accessToken == token
                && filter == requestedFilter && pageVisible && scenePhase == .active
        }
        defer { if isCurrent() { loading = false } }
        do {
            if preserveQr {
                guard !qrRegistrationId.isEmpty else { return }
                guard let latestStatus = try await MobileAPI(store: store).get(
                    "/api/JHCTIActivity/GetMyRegistrationStatus?id=\(qrRegistrationId)", authenticated: true,
                    expectedPrincipal: expectedPrincipal) as? String,
                    isCurrent() else { return }
                switch latestStatus {
                case "CheckedIn": qrCheckedIn = true
                case "Registered": qrCheckedIn = false
                default: clearQr()
                }
                return
            }
            let encodedStatus = queryFilter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let before = cursor.map { "&beforeRegistrationId=\($0)" } ?? ""
            let value = try await MobileAPI(store: store).get("/api/JHCTIActivity/GetMyRegistrationsPage?page=\(targetPage)&pageSize=20&status=\(encodedStatus)\(before)", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [String: Any]
            guard isCurrent() else { return }
            guard let value,
                  let data = (value["data"] ?? value["Data"]) as? [[String: Any]] else {
                throw MobileAPIError.unavailable("报名记录响应格式异常")
            }
            guard let count = nativeActivityRegistrationPageTotal(value, rowCount: data.count) else {
                throw MobileAPIError.unavailable("报名数量异常，请刷新后重试。")
            }
            var receivedIds = Set<String>()
            guard data.allSatisfy({ item in
                guard let id = item["Id"] as? String, let number = Int64(id), number > 0, String(number) == id else { return false }
                return receivedIds.insert(id).inserted
            }) else { throw MobileAPIError.unavailable("报名记录编号异常，请刷新后重试。") }
            let existing = Set(rows.compactMap { $0["Id"] as? String })
            let additions = data.filter { !existing.contains($0["Id"] as? String ?? "") }
            if !reset && !data.isEmpty && additions.isEmpty {
                canLoadMore = false; throw MobileAPIError.unavailable("报名列表已变化，请刷新后继续。")
            }
            clearQr()
            rows = reset ? data : rows + additions
            total = max(count, rows.count); page = targetPage; loadedToken = token
            canLoadMore = data.count == 20 && rows.count < total
        } catch {
            if isCurrent() && !preserveQr { self.error = error.localizedDescription }
        }
    }

    @MainActor private func loadOutcomeSnapshot(id: String, throughPage: Int, expectedToken: String) async -> [[String: Any]]? {
        guard pageVisible, scenePhase == .active, store.session?.accessToken == expectedToken,
              let expectedPrincipal = nativeTourismPrincipal(expectedToken) else { return nil }
        let requestedFilter = filter
        clearQr(); pendingCancellation = nil; pendingDeletion = nil
        loading = true; error = nil
        let sequence = requestSequence + 1; requestSequence = sequence
        func isCurrent() -> Bool {
            !Task.isCancelled && sequence == requestSequence && store.session?.accessToken == expectedToken
                && filter == requestedFilter && pageVisible && scenePhase == .active
        }
        defer { if isCurrent() { loading = false } }
        var refreshedRows: [[String: Any]] = []
        var refreshedTotal = 0
        var cursor: String?
        var pagesRead = 0
        do {
            let encodedStatus = requestedFilter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            for requestedPage in 1...max(1, throughPage) {
                guard isCurrent() else { return nil }
                let before = cursor.map { "&beforeRegistrationId=\($0)" } ?? ""
                let value = try await MobileAPI(store: store).get(
                    "/api/JHCTIActivity/GetMyRegistrationsPage?page=\(requestedPage)&pageSize=20&status=\(encodedStatus)\(before)",
                    authenticated: true, expectedPrincipal: expectedPrincipal) as? [String: Any]
                guard isCurrent(), let value,
                      let data = (value["data"] ?? value["Data"]) as? [[String: Any]] else {
                    throw MobileAPIError.unavailable("报名记录响应格式异常")
                }
                var receivedIds = Set<String>()
                guard data.allSatisfy({ item in
                    guard let id = item["Id"] as? String, let number = Int64(id), number > 0, String(number) == id else { return false }
                    return receivedIds.insert(id).inserted
                }) else { throw MobileAPIError.unavailable("报名记录编号异常，请刷新后重试。") }
                guard let receivedTotal = nativeActivityRegistrationPageTotal(value, rowCount: data.count) else {
                    throw MobileAPIError.unavailable("报名数量异常，请刷新后重试。")
                }
                if requestedPage == 1 {
                    refreshedTotal = receivedTotal
                }
                refreshedRows.append(contentsOf: data)
                pagesRead = requestedPage
                if data.contains(where: { $0["Id"] as? String == id }) || data.count < 20 { break }
                guard let lastId = data.last?["Id"] as? String, let lastNumber = Int64(lastId), lastNumber > 0,
                      String(lastNumber) == lastId else { throw MobileAPIError.unavailable("报名记录游标无效，请刷新后继续。") }
                cursor = lastId
            }
            guard isCurrent() else { return nil }
            rows = refreshedRows
            total = max(refreshedTotal, refreshedRows.count)
            page = pagesRead
            loadedToken = expectedToken
            canLoadMore = rows.count < total
            return refreshedRows
        } catch {
            if isCurrent() { self.error = error.localizedDescription }
            return nil
        }
    }

    @MainActor private func cancel(_ item: [String: Any], expectedToken: String) async {
        guard cancelBusyId.isEmpty, deleteBusyId.isEmpty, !expectedToken.isEmpty, store.session?.accessToken == expectedToken,
              let id = item["Id"] as? String, let number = Int64(id), number > 0, String(number) == id,
              let current = rows.first(where: { $0["Id"] as? String == id }), current["CanCancel"] as? Bool == true,
              !activityRegistrationCredentialUnavailable(current) else { pendingCancellation = nil; return }
        cancelSequence += 1; let operation = cancelSequence
        requestSequence += 1; loading = false
        pendingCancellation = nil; cancelBusyId = id; error = nil; cancellationNotice = nil; clearQr()
        defer { if operation == cancelSequence { cancelBusyId = "" } }
        do {
            let value = try await MobileAPI(store: store).post("/api/JHCTIActivity/CancelRegistration?id=\(id)", body: [:], authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(expectedToken)) as? String
            guard operation == cancelSequence, store.session?.accessToken == expectedToken else { return }
            guard value == id else { throw MobileAPIError.unavailable("取消结果无法确认，请刷新报名状态") }
            // 已确认的取消立即收起旧凭证；读取仍由服务端刷新完整报名快照。
            requestSequence += 1
            if filter == "Registered" {
                rows.removeAll { $0["Id"] as? String == id }; total = max(0, total - 1)
            } else if let index = rows.firstIndex(where: { $0["Id"] as? String == id }) {
                rows[index]["Status"] = "Cancelled"; rows[index]["CanCancel"] = false
                rows[index]["CredentialCode"] = nil
            }
            revision += 1
        } catch {
            if operation == cancelSequence, store.session?.accessToken == expectedToken {
                if isUnknownActivityRegistrationMutationOutcome(error) {
                    let refreshedRows = await loadOutcomeSnapshot(id: id, throughPage: page, expectedToken: expectedToken)
                    guard operation == cancelSequence, store.session?.accessToken == expectedToken else { return }
                    if refreshedRows == nil || self.error != nil {
                        cancellationNotice = "取消结果暂未确认，报名记录未能刷新。请先重试刷新，再决定是否重新取消。"
                    } else if let refreshed = refreshedRows?.first(where: { $0["Id"] as? String == id }) {
                        switch refreshed["Status"] as? String {
                        case "Cancelled":
                            cancellationNotice = "取消已完成，最新报名记录已刷新。"
                        case "Registered":
                            let label = activityRegistrationStatusLabel(refreshed)
                            cancellationNotice = "取消结果暂未确认，报名仍显示“\(label)”。请核对后再决定是否重新取消。"
                        case "CheckedIn":
                            cancellationNotice = "报名状态已更新为“已签到”，取消操作未完成。请刷新核对后再操作。"
                        default:
                            cancellationNotice = "报名状态已变化或无法识别，当前状态：“\(activityRegistrationStatusLabel(refreshed))”。请刷新核对后再操作。"
                        }
                    } else {
                        cancellationNotice = "取消已完成，最新报名记录已刷新。"
                    }
                } else { self.error = error.localizedDescription }
            }
        }
    }

    @MainActor private func deleteExpired(_ item: [String: Any], expectedToken: String) async {
        guard deleteBusyId.isEmpty, cancelBusyId.isEmpty, !expectedToken.isEmpty, store.session?.accessToken == expectedToken,
              let id = item["Id"] as? String, let number = Int64(id), number > 0, String(number) == id,
              let current = rows.first(where: { $0["Id"] as? String == id }),
              current["Status"] as? String == "Registered", activityRegistrationExpired(current) else {
            pendingDeletion = nil; return
        }
        deleteSequence += 1; let operation = deleteSequence
        requestSequence += 1; loading = false
        pendingDeletion = nil; expiredDeleteRetryItem = nil; expiredDeleteRetryToken = ""
        deleteBusyId = id; error = nil; cancellationNotice = nil; clearQr()
        defer { if operation == deleteSequence { deleteBusyId = "" } }
        do {
            let receipt = try await MobileAPI(store: store).post(
                "/api/JHCTIActivity/DeleteExpiredMyRegistration?id=\(id)", body: [:], authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(expectedToken)) as? String
            guard operation == deleteSequence, store.session?.accessToken == expectedToken else { return }
            guard receipt == id else { throw MobileAPIError.unavailable("删除结果暂未确认，请刷新报名状态后重试。") }
            // 仅在回执匹配后移除当前记录，迟到的列表也不能重新回填该行。
            requestSequence += 1
            rows.removeAll { $0["Id"] as? String == id }; total = max(0, total - 1)
            expiredDeleteRetryItem = nil; expiredDeleteRetryToken = ""
            revision += 1
        } catch {
            if operation == deleteSequence, store.session?.accessToken == expectedToken {
                if isUnknownActivityRegistrationMutationOutcome(error) {
                    let refreshedRows = await loadOutcomeSnapshot(id: id, throughPage: page, expectedToken: expectedToken)
                    guard operation == deleteSequence, store.session?.accessToken == expectedToken else { return }
                    if refreshedRows == nil || self.error != nil {
                        cancellationNotice = "删除结果暂未确认，报名记录未能刷新。请先重试刷新，再决定是否重新删除。"
                        expiredDeleteRetryItem = nil; expiredDeleteRetryToken = ""
                    } else if let refreshed = refreshedRows?.first(where: { $0["Id"] as? String == id }) {
                        cancellationNotice = "删除结果暂未确认，记录仍在列表中，当前状态：“\(activityRegistrationStatusLabel(refreshed))”。请核对后再决定是否重试。"
                        if refreshed["Status"] as? String == "Registered" && activityRegistrationExpired(refreshed) {
                            expiredDeleteRetryItem = refreshed; expiredDeleteRetryToken = expectedToken
                        } else { expiredDeleteRetryItem = nil; expiredDeleteRetryToken = "" }
                    } else {
                        cancellationNotice = "过期报名已从列表移除，删除操作已完成。"
                        expiredDeleteRetryItem = nil; expiredDeleteRetryToken = ""
                    }
                } else {
                    expiredDeleteRetryItem = item; expiredDeleteRetryToken = expectedToken
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func clearQr() {
        qrSequence += 1; qrImage = nil; qrBusyId = ""; qrRegistrationId = ""; qrCheckedIn = false; qrRetry = nil
    }

    private func refreshCredentialClock() {
        credentialClock = Date()
        guard !qrRegistrationId.isEmpty else { return }
        if let item = rows.first(where: { $0["Id"] as? String == qrRegistrationId }),
           !activityRegistrationCredentialUnavailable(item, now: credentialClock) { return }
        clearQr()
    }

    @MainActor private func showQr(id: String, title: String) async {
        guard !id.isEmpty, qrBusyId.isEmpty, let token = store.session?.accessToken,
              let item = rows.first(where: { $0["Id"] as? String == id }) else { return }
        guard !activityRegistrationCredentialUnavailable(item) else {
            refreshCredentialClock(); revision += 1; return
        }
        qrSequence += 1; let operation = qrSequence
        qrRegistrationId = id
        qrCheckedIn = false
        qrStatusCountdown = 5
        qrBusyId = id; qrRetry = nil
        defer { if operation == qrSequence { qrBusyId = "" } }
        do {
            guard let value = try await MobileAPI(store: store).get("/api/JHCTIActivity/GetMyRegistrationQr?id=\(id)", authenticated: true,
                expectedPrincipal: nativeTourismPrincipal(token)) as? String,
                  let encoded = value.components(separatedBy: "base64,").last,
                  let data = Data(base64Encoded: encoded), store.session?.accessToken == token else {
                throw MobileAPIError.unavailable("活动二维码暂时无法显示")
            }
            guard operation == qrSequence, qrRegistrationId == id, store.session?.accessToken == token else { return }
            // 回包和图像处理可能跨过活动截止时间，展示前必须重新判定。
            guard !activityRegistrationCredentialUnavailable(item) else {
                clearQr(); credentialClock = Date(); revision += 1; return
            }
            qrTitle = title; qrImage = data
        } catch {
            if operation == qrSequence, qrRegistrationId == id, store.session?.accessToken == token {
                qrRetry = ActivityRegistrationQrRetry(
                    registrationID: id,
                    title: title,
                    token: token,
                    message: error.localizedDescription,
                )
            }
        }
    }
}

private func activityRegistrationStatusLabel(_ item: [String: Any]) -> String {
    switch item["Status"] as? String {
    case "Registered":
        if activityRegistrationExpired(item) { return "已过期" }
        if activityRegistrationExpiryUnknown(item) { return "确认状态中" }
        return "已报名"
    case "CheckedIn": return "已签到"
    case "Cancelled": return "已取消"
    default: return "状态待核对"
    }
}

private struct ActivityCancellationStatusBanner: View {
    let message: String?

    @ViewBuilder var body: some View {
        if let message {
            Text(message).font(.system(size: NativeTypography.size(13)))
                .foregroundStyle(Brand.primary).padding(.horizontal, 16).padding(.vertical, 8)
        }
    }
}

private func activityRegistrationBusinessDateTime(_ value: Any?) -> String? {
    bookingBusinessDateTime(value)
}

private func activityRegistrationParticipantStatus(_ value: Any?) -> String {
    switch value as? String {
    case "Registered": return "已报名"
    case "CheckedIn": return "已签到"
    case "Cancelled": return "已取消"
    default: return "待核对"
    }
}

private func isUnknownActivityRegistrationMutationOutcome(_ error: Error) -> Bool {
    guard let status = (error as? MobileAPIError)?.httpStatusCode else { return true }
    return status < 400 || status == 408 || status == 429 || status >= 500
}
