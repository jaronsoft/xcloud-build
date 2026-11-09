import AVFoundation
import Foundation
import SwiftUI
import VisionKit

private struct NativeMerchantTicketDraft {
    var price: String
    var sessionInventories: [String: String]
}

struct MerchantTourismReservationsView: View {
    @ObservedObject var store: SessionStore
    let merchantID: String
    let canView: Bool
    let canVerify: Bool
    let initialVerify: Bool
    @State private var verifyMode = false
    @State private var status = ""
    @State private var rows: [[String: Any]] = []
    @State private var page = 1
    @State private var total = 0
    @State private var loading = false
    @State private var checkingIn = false
    @State private var scannerOpen = false
    @State private var cameraAvailable = false
    @State private var credentialCode = ""
    @State private var identityNumber = ""
    @State private var receipt: [String: Any]?
    @State private var error: String?
    @State private var revision = 0
    @State private var requestSequence = 0
    @State private var confirmingCheckIn = false
    @State private var scannerSessionToken = ""
    @State private var scannerMerchantID = ""
    @State private var scannerOperation = 0
    @State private var activeMerchantID = ""
    @State private var reservationPageTask: Task<Void, Never>?
    @State private var checkInOperation = 0

    private let statusOptions = [("", "全部"), ("Reserved", "已预约"), ("CheckedIn", "已入园"), ("Cancelled", "已取消")]
    private var principal: String? { nativeTourismPrincipal(store.session?.accessToken) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("仅显示当前商户绑定景点的预约摘要；凭证归属、有效时段与实名信息由服务端核验。")
                    .font(.caption).foregroundStyle(Brand.muted)
                if canView && canVerify {
                    HStack(spacing: 8) {
                        modeButton("预约记录", selected: !verifyMode) { switchMode(false) }
                        modeButton("预约检票", selected: verifyMode) { switchMode(true) }
                    }
                }
                if verifyMode { checkInPanel }
                else { reservationList }
            }
            .padding(16)
        }
        .background(Brand.background)
        .navigationTitle(verifyMode ? "预约检票" : "景点预约记录")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            activeMerchantID = merchantID
            verifyMode = initialVerify && canVerify
            cameraAvailable = DataScannerViewController.isAvailable
        }
        .task(id: "\(revision)-\(status)-\(verifyMode)-\(merchantID)-\(principal ?? "")") {
            if canView && !verifyMode { await loadReservations(page: 1) }
        }
        .onChange(of: principal) { _, _ in
            checkInOperation += 1
            requestSequence += 1
            reservationPageTask?.cancel(); reservationPageTask = nil
            rows = []; total = 0; credentialCode = ""; identityNumber = ""
            receipt = nil; error = nil; loading = false; checkingIn = false; scannerOpen = false; scannerSessionToken = ""
        }
        .onChange(of: merchantID) { _, newMerchantID in
            activeMerchantID = newMerchantID
            checkInOperation += 1
            scannerOperation += 1
            requestSequence += 1
            reservationPageTask?.cancel(); reservationPageTask = nil
            rows = []; total = 0; page = 1; loading = false
            checkingIn = false; confirmingCheckIn = false
            credentialCode = ""; identityNumber = ""; receipt = nil; error = nil
            scannerOpen = false; scannerSessionToken = ""; scannerMerchantID = ""
        }
        .onChange(of: status) { _, _ in
            requestSequence += 1
            reservationPageTask?.cancel(); reservationPageTask = nil
            rows = []; total = 0; page = 1; loading = false; error = nil
        }
        .onChange(of: store.session?.accessToken) { _, _ in
            scannerOperation += 1
            scannerOpen = false; scannerSessionToken = ""; scannerMerchantID = ""; credentialCode = ""; identityNumber = ""; receipt = nil
        }
        .onDisappear {
            scannerOperation += 1
            requestSequence += 1
            reservationPageTask?.cancel(); reservationPageTask = nil
            rows = []; total = 0; page = 1; loading = false; error = nil
            credentialCode = ""; identityNumber = ""; receipt = nil; scannerOpen = false; scannerSessionToken = ""; scannerMerchantID = ""
        }
        .sheet(isPresented: $scannerOpen) {
            let presentedMerchantID = scannerMerchantID
            let presentedToken = scannerSessionToken
            let presentedOperation = scannerOperation
            NativeActivityQrScanner(inputLabel: "预约凭证码", onCode: { scanned in
                guard scannerOperation == presentedOperation,
                      activeMerchantID == presentedMerchantID,
                      store.session?.accessToken == presentedToken else { return }
                let value = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
                if (10...40).contains(value.count) { credentialCode = value; error = nil; receipt = nil }
                else { credentialCode = ""; receipt = nil; error = "二维码内容不是有效的预约凭证码，请手动核对。" }
                scannerOpen = false; scannerSessionToken = ""; scannerMerchantID = ""
            }, onFailure: { message in
                guard scannerOperation == presentedOperation,
                      activeMerchantID == presentedMerchantID,
                      store.session?.accessToken == presentedToken else { return }
                error = message; cameraAvailable = false; scannerOpen = false; scannerSessionToken = ""; scannerMerchantID = ""
            }).ignoresSafeArea()
        }
        .confirmationDialog("确认核验入园", isPresented: $confirmingCheckIn, titleVisibility: .visible) {
            Button(checkingIn ? "正在核验…" : "确认核验", role: .destructive) { Task { await checkIn() } }.disabled(checkingIn)
            Button("取消", role: .cancel) { confirmingCheckIn = false }
        } message: {
            Text("将预约凭证提交服务端核验；成功后该预约不可重复入园。实名预约须核对游客现场出示的身份证。")
        }
    }

    private var checkInPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("核验游客预约").font(.headline)
            Text("扫码读取预约凭证，或手动输入凭证码。实名预约须核对现场证件；身份证号仅随本次核验请求发送。")
                .font(.caption).foregroundStyle(Brand.muted)
            if DataScannerViewController.isSupported {
                Button("扫描预约二维码") { Task { await requestScannerAccess() } }
                    .buttonStyle(.borderedProminent).tint(Brand.primary)
                    .frame(maxWidth: .infinity).disabled(checkingIn)
            } else {
                Text("当前设备不支持二维码扫描，请手动输入凭证码。")
                    .font(.caption).foregroundStyle(Brand.muted)
            }
            TextField("预约凭证码（10 至 40 个字符）", text: $credentialCode)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).disabled(checkingIn)
                .onChange(of: credentialCode) { _, _ in receipt = nil }
            TextField("现场身份证号（实名预约填写）", text: $identityNumber)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).disabled(checkingIn)
                .onChange(of: identityNumber) { _, value in
                    let normalized = String(value.filter { $0.isASCII && $0.isLetter || $0.isASCII && $0.isNumber }.prefix(18))
                    if normalized != value { identityNumber = normalized }
                    receipt = nil
                }
            if let error { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red) }
            Button(checkingIn ? "正在核验…" : "核验入园") { confirmingCheckIn = true }
                .buttonStyle(.borderedProminent).tint(Brand.primary)
                .frame(maxWidth: .infinity)
                .disabled(checkingIn || !(10...40).contains(credentialCode.trimmingCharacters(in: .whitespacesAndNewlines).count))
            if let receipt {
                VStack(alignment: .leading, spacing: 5) {
                    Text("预约核验成功").font(.system(size: NativeTypography.size(16), weight: .semibold)).foregroundStyle(Brand.primary)
                    Text("景点：\(receipt["ResourceName"] as? String ?? "景点")").font(.system(size: NativeTypography.size(14)))
                    Text("预约日期：\(receipt["ReservationDate"] as? String ?? "—") · \(receipt["SessionName"] as? String ?? "当日预约")")
                        .font(.system(size: NativeTypography.size(14)))
                    Text("状态：已入园").font(.system(size: NativeTypography.size(14)))
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private var reservationList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(statusOptions.indices, id: \.self) { index in
                        let option = statusOptions[index]
                        Button(option.1) { if status != option.0 { status = option.0; rows = []; total = 0; page = 1 } }
                            .font(.system(size: NativeTypography.size(14), weight: .medium))
                            .foregroundStyle(status == option.0 ? .white : Brand.ink)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(status == option.0 ? Brand.primary : .white, in: Capsule())
                    }
                    Button("刷新") {
                        requestSequence += 1
                        reservationPageTask?.cancel(); reservationPageTask = nil; revision += 1
                    }
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.primary)
                }
            }
            if loading && rows.isEmpty { ProgressView("正在读取预约记录…").frame(maxWidth: .infinity) }
            if let error {
                Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                Button("重试") { revision += 1 }.font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.primary)
            }
            if !loading && error == nil && rows.isEmpty { Text("暂无景点预约记录。").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted) }
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                let rowStatus = Self.text(row["Status"] ?? row["status"])
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(Self.text(row["ResourceName"] ?? row["resourceName"]).isEmpty ? "景点" : Self.text(row["ResourceName"] ?? row["resourceName"]))
                            .font(.system(size: NativeTypography.size(16), weight: .semibold))
                        Spacer()
                        Text(statusOptions.first(where: { $0.0 == rowStatus })?.1 ?? "状态未知")
                            .font(.system(size: NativeTypography.size(14), weight: .medium))
                            .foregroundStyle(rowStatus == "CheckedIn" ? Brand.primary : rowStatus == "Cancelled" ? Brand.muted : Color.orange)
                    }
                    Text("\(Self.text(row["ReservationDate"] ?? row["reservationDate"])) · \(Self.text(row["SessionName"] ?? row["sessionName"]).isEmpty ? "当日预约" : Self.text(row["SessionName"] ?? row["sessionName"]))")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.ink)
                    Text("预约时间：\(Self.dateText(row["ReservedAt"] ?? row["reservedAt"]))")
                        .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    let checked = Self.text(row["CheckedInAt"] ?? row["checkedInAt"])
                    if !checked.isEmpty { Text("入园时间：\(Self.dateText(checked))").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted) }
                }
                .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 11))
            }
            if !loading && error == nil && rows.count < total {
                Button(loading ? "正在加载…" : "加载更多（\(rows.count)/\(total)）") {
                    reservationPageTask?.cancel()
                    reservationPageTask = Task { await loadReservations(page: page + 1) }
                }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(loading)
            } else if !rows.isEmpty && rows.count >= total {
                Text("已显示全部 \(total) 条预约").font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted).frame(maxWidth: .infinity)
            }
        }
    }

    private func modeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action).font(.system(size: NativeTypography.size(14), weight: .semibold))
            .foregroundStyle(selected ? .white : Brand.primary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(selected ? Brand.primary : Brand.primary.opacity(0.08), in: Capsule())
            .disabled(checkingIn)
    }

    private func switchMode(_ verify: Bool) {
        guard verifyMode != verify, !checkingIn else { return }
        requestSequence += 1
        reservationPageTask?.cancel(); reservationPageTask = nil
        loading = false
        verifyMode = verify; error = nil; credentialCode = ""; identityNumber = ""; receipt = nil
    }

    @MainActor private func loadReservations(page targetPage: Int) async {
        let requestedMerchantID = merchantID
        let requestedStatus = status
        guard activeMerchantID == requestedMerchantID else { return }
        guard canView, targetPage > 0, Int64(requestedMerchantID).map({ $0 > 0 }) == true,
              let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token), principal == requestedPrincipal else {
            rows = []; total = 0; error = "当前账号或商户范围无效，请返回工作台重新进入。"; loading = false; return
        }
        requestSequence += 1
        let sequence = requestSequence
        let append = targetPage > 1
        loading = true; error = nil
        if !append { rows = []; total = 0; page = 1 }
        do {
            var path = "/api/JHCTITourismReservation/GetMerchantManagementPage?merchantId=\(requestedMerchantID)&page=\(targetPage)&pageSize=20"
            if !requestedStatus.isEmpty { path += "&status=\(requestedStatus)" }
            guard let response = try await MobileAPI(store: store).get(
                path, authenticated: true, expectedPrincipal: requestedPrincipal
            ) as? [String: Any],
                  !Task.isCancelled,
                  requestSequence == sequence,
                  activeMerchantID == requestedMerchantID,
                  status == requestedStatus,
                  nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal,
                  let loaded = response["data"] as? [[String: Any]] ?? response["Data"] as? [[String: Any]] else {
                throw MobileAPIError.unavailable("预约分页响应格式异常，请重试。")
            }
            guard let count = nativeTourismReservationPageTotal(response, rowCount: loaded.count) else {
                throw MobileAPIError.unavailable("预约分页总数格式异常，请刷新后重试。")
            }
            let reservationIDs = loaded.compactMap { row in
                Self.positiveStringID(Self.consistentString(row, "Id"))
            }
            let valid = loaded.allSatisfy { row in
                guard let statusValue = Self.consistentString(row, "Status"),
                      statusOptions.contains(where: { $0.0 == statusValue }),
                      let resourceName = Self.consistentString(row, "ResourceName"),
                      !resourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let sessionName = Self.consistentString(row, "SessionName"),
                      !sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                return Self.positiveStringID(Self.consistentString(row, "Id")) != nil
                    && Self.positiveStringID(Self.consistentString(row, "ResourceId")) != nil
                    && Self.isValidReservationDate(Self.consistentString(row, "ReservationDate"))
            }
            guard loaded.count <= 20, count >= loaded.count,
                  Set(reservationIDs).count == reservationIDs.count, valid else {
                throw MobileAPIError.unavailable("预约分页数据不完整，请刷新后重试。")
            }
            if append {
                let existingReservationIDs = Set(rows.compactMap { row in
                    Self.positiveStringID(Self.consistentString(row, "Id"))
                })
                guard reservationIDs.allSatisfy({ !existingReservationIDs.contains($0) }) else {
                    throw MobileAPIError.unavailable("预约分页记录发生重叠，请刷新列表后重试。")
                }
            }
            guard !Task.isCancelled, requestSequence == sequence,
                  activeMerchantID == requestedMerchantID, status == requestedStatus,
                  nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            if !append { rows = loaded }
            else { rows.append(contentsOf: loaded) }
            total = count; page = targetPage
        } catch {
            guard !Task.isCancelled, requestSequence == sequence,
                  activeMerchantID == requestedMerchantID, status == requestedStatus,
                  nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            self.error = error.localizedDescription
        }
        if requestSequence == sequence, !Task.isCancelled,
           activeMerchantID == requestedMerchantID, status == requestedStatus { loading = false }
    }

    @MainActor private func checkIn() async {
        let code = credentialCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canVerify, (10...40).contains(code.count), let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token), principal == requestedPrincipal, !checkingIn else { return }
        let requestedMerchantID = merchantID
        checkInOperation += 1
        let operation = checkInOperation
        checkingIn = true; error = nil; receipt = nil
        var body: [String: Any] = ["CredentialCode": code]
        let identity = identityNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identity.isEmpty { body["IdentityNumber"] = identity }
        do {
            guard let response = try await MobileAPI(store: store).post(
                "/api/JHCTITourismReservation/CheckInMerchant?merchantId=\(merchantID)", body: body,
                authenticated: true, expectedPrincipal: requestedPrincipal
            ) as? [String: Any] else { throw MobileAPIError.unavailable("核验回执无效，请刷新预约状态后核对。") }
            guard checkInOperation == operation, activeMerchantID == requestedMerchantID,
                  nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            guard Self.positiveStringID(Self.consistentString(response, "Id")) != nil,
                  !(Self.consistentString(response, "ResourceName") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !(Self.consistentString(response, "SessionName") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Self.isValidReservationDate(Self.consistentString(response, "ReservationDate")),
                  Self.consistentString(response, "Status") == "CheckedIn" else {
                throw MobileAPIError.unavailable("核验回执信息不完整，请刷新预约状态后核对，不要重复提交。")
            }
            receipt = response; credentialCode = ""; identityNumber = ""
        } catch {
            if checkInOperation == operation, activeMerchantID == requestedMerchantID,
               nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal {
                let statusCode = (error as? MobileAPIError)?.httpStatusCode
                let outcomeUnknown: Bool
                if let statusCode {
                    outcomeUnknown = !(400...499).contains(statusCode) || statusCode == 408 || statusCode == 429
                } else {
                    outcomeUnknown = true
                }
                if outcomeUnknown {
                    credentialCode = ""; identityNumber = ""
                    self.error = "核验结果无法确认：\(error.localizedDescription)。凭证已清除，请返回预约记录刷新核实后再重新扫码。"
                } else {
                    self.error = error.localizedDescription
                }
            }
        }
        guard checkInOperation == operation, activeMerchantID == requestedMerchantID,
              nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
        checkingIn = false; confirmingCheckIn = false
    }

    @MainActor private func requestScannerAccess() async {
        guard let token = store.session?.accessToken, !token.isEmpty else { error = "请使用已授权的文旅工作人员账号登录。"; return }
        let requestedMerchantID = merchantID
        scannerOperation += 1
        let operation = scannerOperation
        guard DataScannerViewController.isSupported else { error = "当前设备不支持二维码扫描，请手动输入凭证码。"; return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        if status == .authorized { granted = true }
        else if status == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .video) }
        else { granted = false }
        guard scannerOperation == operation, activeMerchantID == requestedMerchantID else { return }
        guard store.session?.accessToken == token else {
            scannerOpen = false; scannerSessionToken = ""; scannerMerchantID = ""; credentialCode = ""; identityNumber = ""
            error = "登录账号已变化，请重新读取授权后扫码。"; return
        }
        cameraAvailable = granted && DataScannerViewController.isAvailable
        scannerSessionToken = cameraAvailable ? token : ""
        scannerMerchantID = cameraAvailable ? requestedMerchantID : ""
        if cameraAvailable { scannerOpen = true }
        else { error = "相机权限未开启或设备当前不可用，请手动输入凭证码。" }
    }

    private static func text(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return value as? String ?? String(describing: value)
    }
    private static func positiveStringID(_ value: Any?) -> String? {
        guard let raw = value as? String, let id = Int64(raw), id > 0, String(id) == raw else { return nil }
        return raw
    }
    private static func consistentString(_ payload: [String: Any], _ pascalKey: String) -> String? {
        let camelKey = String(pascalKey.prefix(1)).lowercased() + String(pascalKey.dropFirst())
        let pascalValue = payload[pascalKey]
        let camelValue = payload[camelKey]
        if let pascalValue, let camelValue {
            guard let pascalString = pascalValue as? String,
                  let camelString = camelValue as? String,
                  pascalString == camelString else { return nil }
            return pascalString
        }
        return (pascalValue ?? camelValue) as? String
    }
    private static func isValidReservationDate(_ value: Any?) -> Bool {
        guard let raw = value as? String,
              raw.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil else { return false }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: raw) else { return false }
        return formatter.string(from: date) == raw
    }
    private static func dateText(_ value: Any?) -> String {
        let raw = text(value).replacingOccurrences(of: "T", with: " ")
        return String(raw.prefix(16)).isEmpty ? "—" : String(raw.prefix(16))
    }
}

struct MerchantTicketsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    let merchantID: String
    @State private var rows: [[String: Any]] = []
    @State private var drafts: [String: NativeMerchantTicketDraft] = [:]
    @State private var keyword = ""
    @State private var page = 1
    @State private var total = 0
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var revision = 0
    @State private var requestSequence = 0
    @State private var pendingTicket: [String: Any]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("维护票价与场次库存；已售和待支付数量由服务端保护，场次新增及其他票务规则请在管理端维护。")
                    .font(.caption).foregroundStyle(Brand.muted)
                HStack {
                    TextField("搜索门票名称", text: $keyword)
                        .textFieldStyle(.roundedBorder).submitLabel(.search)
                        .onSubmit { Task { await load(page: 1) } }
                    Button("搜索") { Task { await load(page: 1) } }
                        .buttonStyle(.borderedProminent).tint(Brand.primary)
                }
                StatusView(loading: loading, error: error) { revision += 1 }
                if !loading && error == nil && rows.isEmpty {
                    Text("当前商户暂无可维护门票。").foregroundStyle(Brand.muted)
                }
                ForEach(rows.indices, id: \.self) { index in ticketCard(rows[index]) }
                if !loading && error == nil && rows.count < total {
                    Button(loading ? "正在加载…" : "加载更多（\(rows.count)/\(total)）") {
                        Task { await load(page: page + 1) }
                    }
                    .disabled(loading).frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .background(Brand.background)
        .navigationTitle("门票与场次")
        .task(id: revision) { await load(page: 1) }
        .onChange(of: store.session?.accessToken) { _, _ in dismiss() }
        .confirmationDialog("保存门票与场次", isPresented: Binding(
            get: { pendingTicket != nil }, set: { if !$0 { pendingTicket = nil } }), titleVisibility: .visible) {
            Button("确认保存") {
                guard let pendingTicket else { return }
                Task { await save(pendingTicket) }
            }.disabled(saving)
            Button("取消", role: .cancel) { pendingTicket = nil }
        } message: {
            Text("确认保存“\(pendingTicket?["Name"] as? String ?? "该门票")”的票价和场次库存？服务端会重新校验票务版本、已售和待支付数量。")
        }
    }

    @ViewBuilder private func ticketCard(_ row: [String: Any]) -> some View {
        let id = Self.idString(row["Id"] ?? row["id"])
        let draft = drafts[id] ?? NativeMerchantTicketDraft(price: Self.idString(row["Price"] ?? row["price"]), sessionInventories: [:])
        let sessions = row["Sessions"] as? [[String: Any]] ?? row["sessions"] as? [[String: Any]] ?? []
        VStack(alignment: .leading, spacing: 8) {
            Text(row["Name"] as? String ?? row["name"] as? String ?? "未命名门票").font(.headline)
            Text("\(row["ResourceName"] as? String ?? row["resourceName"] as? String ?? "景点") · \(Self.boolValue(row["IsEnabled"] ?? row["isEnabled"], default: true) ? "销售中" : "已停用") · 当前 ¥\(Self.idString(row["Price"] ?? row["price"]))")
                .font(.caption).foregroundStyle(Brand.muted)
            TextField("票价（元）", text: Binding(get: { draft.price }, set: { setDraft(id, price: $0) }))
                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            if sessions.isEmpty {
                Text("暂无场次资料；请在管理端维护场次。").font(.caption).foregroundStyle(Brand.muted)
            }
            ForEach(sessions.indices, id: \.self) { index in
                let session = sessions[index]
                let sessionID = Self.idString(session["Id"] ?? session["id"])
                let inventory = draft.sessionInventories[sessionID] ?? Self.idString(session["Inventory"] ?? session["inventory"])
                VStack(alignment: .leading, spacing: 5) {
                    Text(session["Name"] as? String ?? session["name"] as? String ?? "未命名场次").font(.subheadline.weight(.semibold))
                    Text("已售 \(Self.intValue(session["SoldCount"] ?? session["soldCount"])) · 待支付 \(Self.intValue(session["ReservedCount"] ?? session["reservedCount"]))\(Self.boolValue(session["IsEnabled"] ?? session["isEnabled"], default: true) ? "" : " · 已停用")")
                        .font(.caption).foregroundStyle(Brand.muted)
                    TextField("场次库存（最多 10000000）", text: Binding(get: { inventory }, set: { setDraft(id, sessionID: sessionID, inventory: $0) }))
                        .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                }
                .padding(10).background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
            }
            Button(saving ? "保存中…" : "保存票价与库存") { prepareSave(row) }
                .buttonStyle(.borderedProminent).tint(Brand.primary).disabled(saving || id.isEmpty)
        }
        .merchantCard()
    }

    private func setDraft(_ id: String, price: String? = nil, sessionID: String? = nil, inventory: String? = nil) {
        var draft = drafts[id] ?? NativeMerchantTicketDraft(price: "", sessionInventories: [:])
        if let price { draft.price = String(price.filter { $0.isNumber || $0 == "." }.prefix(12)) }
        if let sessionID, let inventory {
            draft.sessionInventories[sessionID] = String(inventory.filter(\.isNumber).prefix(8))
        }
        drafts[id] = draft
        error = nil
    }

    private func prepareSave(_ row: [String: Any]) {
        let id = Self.idString(row["Id"] ?? row["id"])
        guard !id.isEmpty else { error = "门票编号缺失，请刷新后重试。"; return }
        let draft = drafts[id] ?? NativeMerchantTicketDraft(price: "", sessionInventories: [:])
        let rawPrice = draft.price.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawPrice.range(of: "^(0|[1-9][0-9]*)(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let price = Decimal(string: rawPrice), let maxPrice = Decimal(string: "99999999.99"),
              price > 0, price <= maxPrice else {
            error = "请输入大于 0、最多两位小数的有效票价。"; return
        }
        let sessions = row["Sessions"] as? [[String: Any]] ?? row["sessions"] as? [[String: Any]] ?? []
        for session in sessions {
            let sessionID = Self.idString(session["Id"] ?? session["id"])
            let raw = (draft.sessionInventories[sessionID] ?? Self.idString(session["Inventory"] ?? session["inventory"]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sold = Self.intValue(session["SoldCount"] ?? session["soldCount"])
            let reserved = Self.intValue(session["ReservedCount"] ?? session["reservedCount"])
            guard (0...10_000_000).contains(sold), (0...10_000_000).contains(reserved) else {
                error = "场次已售或待支付数量异常，请刷新后重试。"
                return
            }
            let committed = sold + reserved
            guard raw.range(of: "^(0|[1-9][0-9]*)$", options: .regularExpression) != nil,
                  let inventory = Int(raw), (0...10_000_000).contains(inventory), committed <= inventory else {
                error = "场次“\(session["Name"] as? String ?? "未命名")”库存须为 0 至 10000000，且不低于已售和待支付数量 \(committed)。"
                return
            }
        }
        pendingTicket = row
    }

    private func save(_ row: [String: Any]) async {
        guard !saving else { return }
        let id = Self.idString(row["Id"] ?? row["id"])
        guard let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else { error = "登录已失效，请重新登录。"; return }
        let draft = drafts[id] ?? NativeMerchantTicketDraft(price: "", sessionInventories: [:])
        guard let price = Decimal(string: draft.price.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "票价格式无效，请重新输入。"; return
        }
        let sessions = row["Sessions"] as? [[String: Any]] ?? row["sessions"] as? [[String: Any]] ?? []
        let sessionPayload: [[String: Any]] = sessions.map { session in
            let sessionID = Self.idString(session["Id"] ?? session["id"])
            return [
                "Id": sessionID,
                "Version": Self.intValue(session["Version"] ?? session["version"]),
                "Name": session["Name"] as? String ?? session["name"] as? String ?? "",
                "StartTime": session["StartTime"] ?? session["startTime"] ?? NSNull(),
                "EndTime": session["EndTime"] ?? session["endTime"] ?? NSNull(),
                "Inventory": Int(draft.sessionInventories[sessionID] ?? Self.idString(session["Inventory"] ?? session["inventory"])) ?? 0,
                "ReservedCount": Self.intValue(session["ReservedCount"] ?? session["reservedCount"]),
                "IsEnabled": Self.boolValue(session["IsEnabled"] ?? session["isEnabled"], default: true),
                "SortOrder": Self.intValue(session["SortOrder"] ?? session["sortOrder"])
            ]
        }
        let body: [String: Any] = [
            "Id": id,
            "Version": Self.intValue(row["Version"] ?? row["version"]),
            "ResourceId": Self.idString(row["ResourceId"] ?? row["resourceId"]),
            "MerchantId": merchantID,
            "Name": row["Name"] ?? row["name"] ?? "",
            "Description": row["Description"] ?? row["description"] ?? NSNull(),
            "Price": NSDecimalNumber(decimal: price),
            "OriginalPrice": row["OriginalPrice"] ?? row["originalPrice"] ?? NSNull(),
            "SaleStartTime": row["SaleStartTime"] ?? row["saleStartTime"] ?? NSNull(),
            "SaleEndTime": row["SaleEndTime"] ?? row["saleEndTime"] ?? NSNull(),
            "MinPerOrder": Self.intValue(row["MinPerOrder"] ?? row["minPerOrder"], fallback: 1),
            "MaxPerOrder": Self.intValue(row["MaxPerOrder"] ?? row["maxPerOrder"], fallback: 5),
            "MaxPerUserPerDay": Self.intValue(row["MaxPerUserPerDay"] ?? row["maxPerUserPerDay"], fallback: 5),
            "RefundPolicy": row["RefundPolicy"] ?? row["refundPolicy"] ?? "ManualReview",
            "RefundBeforeHours": Self.intValue(row["RefundBeforeHours"] ?? row["refundBeforeHours"]),
            "RefundDescription": row["RefundDescription"] ?? row["refundDescription"] ?? NSNull(),
            "RealNameFields": row["RealNameFields"] ?? row["realNameFields"] ?? [],
            "IsEnabled": Self.boolValue(row["IsEnabled"] ?? row["isEnabled"], default: true),
            "SortOrder": Self.intValue(row["SortOrder"] ?? row["sortOrder"]),
            "Sessions": sessionPayload
        ]
        saving = true; error = nil
        do {
            _ = try await MobileAPI(store: store).post("/api/JHCTITicket/SaveMerchantManagement", body: body, authenticated: true,
                expectedPrincipal: expectedPrincipal)
            guard store.session?.accessToken == token else { return }
            await load(page: 1)
            if error != nil { error = "票务修改已提交，但列表刷新失败；请重新加载确认当前状态。" }
        } catch is CancellationError {
            if store.session?.accessToken == token {
                error = "票务保存结果未确认；请重新读取并核对版本后再操作。"
            }
        } catch {
            if store.session?.accessToken == token {
                self.error = "\(error.localizedDescription)；请重新读取并核对版本后再操作。"
            }
        }
        saving = false; pendingTicket = nil
    }

    private func load(page targetPage: Int) async {
        guard !merchantID.isEmpty, merchantID.allSatisfy(\.isNumber),
              let token = store.session?.accessToken,
              let expectedPrincipal = nativeTourismPrincipal(token) else {
            error = "商户范围或登录状态无效，请返回工作台重新进入。"; loading = false; return
        }
        requestSequence += 1
        let sequence = requestSequence
        let append = targetPage > 1
        loading = true; error = nil
        if !append { rows = []; drafts = [:]; total = 0 }
        do {
            let escaped = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))) ?? ""
            guard let response = try await MobileAPI(store: store).get(
                "/api/JHCTITicket/GetMerchantManagementPage?merchantId=\(merchantID)&page=\(targetPage)&pageSize=20&keyword=\(escaped)",
                authenticated: true, expectedPrincipal: expectedPrincipal) as? [String: Any],
                  let loaded = response["data"] as? [[String: Any]] ?? response["Data"] as? [[String: Any]] else {
                throw MobileAPIError.unavailable("门票分页响应格式异常，请重试。")
            }
            let count = Self.intValue(response["dataCount"] ?? response["DataCount"], fallback: -1)
            let validTickets = loaded.allSatisfy { row in
                guard !Self.idString(row["Id"] ?? row["id"]).isEmpty,
                      let sessions = row["Sessions"] as? [[String: Any]] ?? row["sessions"] as? [[String: Any]] else { return false }
                let sessionIDs = sessions.map { Self.idString($0["Id"] ?? $0["id"]) }
                return sessionIDs.allSatisfy { !$0.isEmpty } && Set(sessionIDs).count == sessionIDs.count
            }
            guard loaded.count <= 20, count >= loaded.count, count >= 0, validTickets else {
                throw MobileAPIError.unavailable("门票分页数据不完整，请刷新后重试。")
            }
            guard requestSequence == sequence, store.session?.accessToken == token else { return }
            var next = append ? rows : []
            for row in loaded {
                let id = Self.idString(row["Id"] ?? row["id"])
                if let index = next.firstIndex(where: { Self.idString($0["Id"] ?? $0["id"]) == id }) { next[index] = row }
                else { next.append(row) }
                let sessions = row["Sessions"] as? [[String: Any]] ?? row["sessions"] as? [[String: Any]] ?? []
                drafts[id] = NativeMerchantTicketDraft(
                    price: Self.idString(row["Price"] ?? row["price"]),
                    sessionInventories: Dictionary(uniqueKeysWithValues: sessions.map {
                        (Self.idString($0["Id"] ?? $0["id"]), Self.idString($0["Inventory"] ?? $0["inventory"]))
                    })
                )
            }
            rows = next; total = count; page = targetPage
        } catch is CancellationError {
            if requestSequence == sequence { loading = false }
        } catch {
            guard requestSequence == sequence, store.session?.accessToken == token else { return }
            self.error = error.localizedDescription
        }
        if requestSequence == sequence { loading = false }
    }

    private static func idString(_ value: Any?, fallback: String = "") -> String {
        guard let value, !(value is NSNull) else { return fallback }
        return value as? String ?? String(describing: value)
    }
    private static func intValue(_ value: Any?, fallback: Int = 0) -> Int {
        guard let value, !(value is NSNull) else { return fallback }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? fallback }
        return fallback
    }
    private static func boolValue(_ value: Any?, default fallback: Bool = false) -> Bool {
        guard let value, !(value is NSNull) else { return fallback }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return (string as NSString).boolValue }
        return fallback
    }
}
