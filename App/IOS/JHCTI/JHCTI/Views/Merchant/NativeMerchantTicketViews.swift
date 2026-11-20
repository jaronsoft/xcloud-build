import AVFoundation
import Foundation
import SwiftUI
import VisionKit

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
    @State private var outcomeUnknown = false
    @State private var checkInWindowUnavailableFor = ""
    @State private var resolvingOutcome = false
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
            rows = []; total = 0; credentialCode = ""; identityNumber = ""; outcomeUnknown = false; checkInWindowUnavailableFor = ""; resolvingOutcome = false
            receipt = nil; error = nil; loading = false; checkingIn = false; scannerOpen = false; scannerSessionToken = ""
        }
        .onChange(of: merchantID) { _, newMerchantID in
            activeMerchantID = newMerchantID
            checkInOperation += 1
            scannerOperation += 1
            requestSequence += 1
            reservationPageTask?.cancel(); reservationPageTask = nil
            rows = []; total = 0; page = 1; loading = false
            checkingIn = false; resolvingOutcome = false; outcomeUnknown = false; checkInWindowUnavailableFor = ""; confirmingCheckIn = false
            credentialCode = ""; identityNumber = ""; receipt = nil; error = nil
            scannerOpen = false; scannerSessionToken = ""; scannerMerchantID = ""
        }
        .onChange(of: status) { _, _ in
            requestSequence += 1
            reservationPageTask?.cancel(); reservationPageTask = nil
            rows = []; total = 0; page = 1; loading = false; error = nil; outcomeUnknown = false; checkInWindowUnavailableFor = ""; resolvingOutcome = false
        }
        .onChange(of: store.session?.accessToken) { _, _ in
            scannerOperation += 1
            scannerOpen = false; scannerSessionToken = ""; scannerMerchantID = ""; credentialCode = ""; identityNumber = ""; receipt = nil
            outcomeUnknown = false; checkInWindowUnavailableFor = ""; resolvingOutcome = false
        }
        .onDisappear {
            scannerOperation += 1
            requestSequence += 1
            reservationPageTask?.cancel(); reservationPageTask = nil
            rows = []; total = 0; page = 1; loading = false; error = nil
            credentialCode = ""; identityNumber = ""; receipt = nil; scannerOpen = false; scannerSessionToken = ""; scannerMerchantID = ""
            outcomeUnknown = false; checkInWindowUnavailableFor = ""; resolvingOutcome = false
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
                if (10...40).contains(value.count) { credentialCode = value; checkInWindowUnavailableFor = ""; error = nil; receipt = nil }
                else { credentialCode = ""; checkInWindowUnavailableFor = ""; receipt = nil; error = "二维码内容不是有效的预约凭证码，请手动核对。" }
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
                    .frame(maxWidth: .infinity).disabled(checkingIn || outcomeUnknown || resolvingOutcome)
            } else {
                Text("当前设备不支持二维码扫描，请手动输入凭证码。")
                    .font(.caption).foregroundStyle(Brand.muted)
            }
            TextField("预约凭证码（10 至 40 个字符）", text: $credentialCode)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).disabled(checkingIn || outcomeUnknown || resolvingOutcome)
                .onChange(of: credentialCode) { _, value in
                    if checkInWindowUnavailableFor != value.trimmingCharacters(in: .whitespacesAndNewlines) { checkInWindowUnavailableFor = "" }
                    receipt = nil
                }
            TextField("现场身份证号（实名预约填写）", text: $identityNumber)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).disabled(checkingIn || outcomeUnknown || resolvingOutcome)
                .onChange(of: identityNumber) { _, value in
                    let normalized = String(value.filter { $0.isASCII && $0.isLetter || $0.isASCII && $0.isNumber }.prefix(18))
                    if normalized != value { identityNumber = normalized }
                    receipt = nil
                }
            if let error { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red) }
            if outcomeUnknown || checkInWindowUnavailableFor == credentialCode.trimmingCharacters(in: .whitespacesAndNewlines) {
                Button(resolvingOutcome ? "正在查询…" : outcomeUnknown ? "查询预约当前状态" : "重新查询预约状态") { Task { await resolveCheckInOutcome() } }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(resolvingOutcome)
            }
            Button(checkingIn ? "正在核验…" : "核验入园") { confirmingCheckIn = true }
                .buttonStyle(.borderedProminent).tint(Brand.primary)
                .frame(maxWidth: .infinity)
                .disabled(checkingIn || outcomeUnknown || resolvingOutcome || !(10...40).contains(credentialCode.trimmingCharacters(in: .whitespacesAndNewlines).count)
                    || checkInWindowUnavailableFor == credentialCode.trimmingCharacters(in: .whitespacesAndNewlines))
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
            .disabled(checkingIn || outcomeUnknown || resolvingOutcome)
    }

    private func switchMode(_ verify: Bool) {
        guard verifyMode != verify, !checkingIn, !outcomeUnknown, !resolvingOutcome else { return }
        requestSequence += 1
        reservationPageTask?.cancel(); reservationPageTask = nil
        loading = false
        verifyMode = verify; error = nil; credentialCode = ""; identityNumber = ""; receipt = nil
        outcomeUnknown = false; checkInWindowUnavailableFor = ""; resolvingOutcome = false
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
              let requestedPrincipal = nativeTourismPrincipal(token), principal == requestedPrincipal,
              !checkingIn, !outcomeUnknown, !resolvingOutcome else { return }
        guard checkInWindowUnavailableFor != code else { error = "该预约当前不可核验，请先重新查询状态；若持续不可核验，请联系商户管理员。"; return }
        let requestedMerchantID = merchantID
        checkInOperation += 1
        let operation = checkInOperation
        checkingIn = true; outcomeUnknown = false; error = nil; receipt = nil
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
                    self.outcomeUnknown = true
                    self.error = "核验结果无法确认：\(error.localizedDescription)。请先查询凭证状态，不要重复提交。"
                } else {
                    self.error = error.localizedDescription
                }
            }
        }
        guard checkInOperation == operation, activeMerchantID == requestedMerchantID,
              nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
        checkingIn = false; confirmingCheckIn = false
    }

    @MainActor private func resolveCheckInOutcome() async {
        let code = credentialCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (outcomeUnknown || checkInWindowUnavailableFor == code), !resolvingOutcome, (10...40).contains(code.count), canVerify,
              let token = store.session?.accessToken,
              let requestedPrincipal = nativeTourismPrincipal(token), principal == requestedPrincipal else { return }
        let requestedMerchantID = merchantID
        checkInOperation += 1
        let operation = checkInOperation
        resolvingOutcome = true; error = "正在查询预约当前状态…"
        do {
            guard let response = try await MobileAPI(store: store).post(
                "/api/JHCTITourismReservation/GetMerchantCheckInStatus?merchantId=\(requestedMerchantID)",
                body: ["CredentialCode": code], authenticated: true, expectedPrincipal: requestedPrincipal
            ) as? [String: Any] else { throw MobileAPIError.unavailable("状态查询回执无效。") }
            guard checkInOperation == operation, activeMerchantID == requestedMerchantID,
                  nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
            let status = Self.consistentString(response, "Status") ?? ""
            let canCheckInNow = response["CanCheckInNow"] as? Bool
            guard Self.positiveStringID(Self.consistentString(response, "Id")) != nil,
                  !(Self.consistentString(response, "ResourceName") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !(Self.consistentString(response, "SessionName") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Self.isValidReservationDate(Self.consistentString(response, "ReservationDate")),
                  ["Reserved", "CheckedIn", "Cancelled"].contains(status),
                  status != "Reserved" || canCheckInNow != nil else {
                throw MobileAPIError.unavailable("状态查询回执不完整。")
            }
            switch status {
            case "CheckedIn":
                outcomeUnknown = false; checkInWindowUnavailableFor = ""; credentialCode = ""; identityNumber = ""; receipt = response
                error = "查询确认该预约已核验入园。"
            case "Reserved":
                outcomeUnknown = false
                if canCheckInNow == false {
                    checkInWindowUnavailableFor = code
                    error = "查询确认该预约仍未核验，但服务端当前不允许核验。请稍后重新查询；若持续不可核验，请联系商户管理员。"
                } else {
                    checkInWindowUnavailableFor = ""
                    error = "查询确认该预约仍未核验。核对游客凭证及所需身份证后，可重新提交核验。"
                }
            default:
                outcomeUnknown = false; checkInWindowUnavailableFor = ""; credentialCode = ""; identityNumber = ""; receipt = nil
                error = "该预约已取消，不能核验入园。"
            }
        } catch is CancellationError {
            // 页面离开或请求取消时保留原状态，不把主动取消呈现为查询失败。
        } catch {
            if checkInOperation == operation, activeMerchantID == requestedMerchantID,
               nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal {
                self.error = "\(error.localizedDescription)。请稍后重试查询，不要重复提交核验。"
            }
        }
        guard checkInOperation == operation, activeMerchantID == requestedMerchantID,
              nativeTourismPrincipal(store.session?.accessToken) == requestedPrincipal else { return }
        resolvingOutcome = false
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
