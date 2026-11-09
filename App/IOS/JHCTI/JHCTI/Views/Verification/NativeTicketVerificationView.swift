import AVFoundation
import Foundation
import SwiftUI
import VisionKit

struct NativeTicketVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionStore
    @State private var points: [[String: Any]] = []
    @State private var records: [[String: Any]] = []
    @State private var selectedPointId = ""
    @State private var code = ""
    @State private var loading = true
    @State private var redeeming = false
    @State private var featureOpen = false
    @State private var error: String?
    @State private var receipt: [String: Any]?
    @State private var revision = 0
    @State private var sequence = 0
    @State private var scannerOpen = false
    @State private var cameraAvailable = false
    @State private var scannerPrincipal = ""
    @State private var cameraSequence = 0
    @State private var redeemSequence = 0
    @State private var requestingCamera = false
    @State private var uncertain = false
    @State private var unlockAfterRefresh = false
    @State private var confirmRedeem = false
    @State private var showFeatureStatus = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("授权检票点").font(.system(size: NativeTypography.size(16), weight: .semibold))
                        if loading && points.isEmpty { ProgressView("正在读取核销授权…") }
                        else if let error, points.isEmpty {
                            Button("读取失败：\(error) · 点击重试") { revision += 1 }
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                        } else if points.isEmpty {
                            Text(featureOpen ? "当前账号没有启用中的授权检票点，请联系平台管理员配置权限。" : "门票核销功能暂未开放。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            if !featureOpen {
                                Button("查看开放状态") { showFeatureStatus = true }
                                    .font(.system(size: NativeTypography.size(14), weight: .medium)).foregroundStyle(Brand.primary)
                                    .sheet(isPresented: $showFeatureStatus, onDismiss: { revision += 1 }) {
                                        NativeFeaturePendingView(store: store, featureId: "F-TKT-004")
                                    }
                            }
                        } else {
                            ForEach(points.indices, id: \.self) { index in
                                let point = points[index]
                                Button {
                                    selectedPointId = point["Id"] as? String ?? ""
                                    receipt = nil
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(point["Name"] as? String ?? "检票点")
                                                .font(.system(size: NativeTypography.size(14), weight: .medium))
                                            Text("授权场次：\(((point["Sessions"] as? [[String: Any]]) ?? []).compactMap { $0["Name"] as? String }.joined(separator: "、"))")
                                                .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                        }
                                        Spacer()
                                        if selectedPointId == (point["Id"] as? String) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.primary) }
                                    }
                                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Brand.background, in: RoundedRectangle(cornerRadius: 9))
                                }.buttonStyle(.plain).disabled(redeeming || requestingCamera || scannerOpen)
                            }
                        }
                    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 9) {
                        Text("现场核销").font(.system(size: NativeTypography.size(16), weight: .semibold))
                        Text("扫描或输入游客门票凭证码。点位授权、票券有效期及重复核销由服务端核验。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        Button("扫描门票二维码") { Task { await requestScannerAccess() } }
                            .disabled(!featureOpen || points.isEmpty || redeeming || requestingCamera || scannerOpen)
                            .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.primary)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(Brand.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        if !cameraAvailable { Text("相机扫码不可用时，可直接手动输入凭证码。首次扫码会请求相机权限。")
                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted) }
                        TextField("门票凭证码", text: $code).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().disabled(redeeming || requestingCamera || scannerOpen).padding(12)
                            .background(Brand.background, in: RoundedRectangle(cornerRadius: 9))
                            .onChange(of: code) { _, _ in if !redeeming { receipt = nil } }
                        if code.trimmingCharacters(in: .whitespacesAndNewlines).count > 128 {
                            Text("凭证码最多 128 个字符，请核对输入内容。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                        }
                        if let error { Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red) }
                        Button(redeeming ? "正在核对…" : ((receipt?["IsPreview"] as? Bool == true) ? (receipt?["TicketKind"] as? String == "Bundle" ? "确认整套核销" : "确认核销") : "核对凭证")) { confirmRedeem = true }
                            .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(Brand.primary, in: RoundedRectangle(cornerRadius: 10))
                            .disabled(redeeming || requestingCamera || scannerOpen || uncertain || !featureOpen || points.isEmpty || selectedPointId.isEmpty
                                || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || code.trimmingCharacters(in: .whitespacesAndNewlines).count > 128)
                        if uncertain {
                            Button("刷新核销记录后，我已核对结果并允许重试") { unlockAfterRefresh = true; revision += 1 }
                                .font(.system(size: NativeTypography.size(14)))
                                .disabled(loading || redeeming || requestingCamera || scannerOpen)
                        }
                        if let receipt {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(receipt["IsPreview"] as? Bool == true ? "凭证核对成功" : "核销成功").font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.primary)
                                Text("\(receipt["TicketName"] as? String ?? "门票") · \(receipt["SessionName"] as? String ?? "场次")").font(.system(size: NativeTypography.size(14)))
                                if receipt["TicketKind"] as? String == "Bundle" {
                                    let bundleItems = receipt["BundleItems"] as? [[String: Any]] ?? []
                                    let redemptions = receipt["BundleRedemptions"] as? [[String: Any]] ?? []
                                    if bundleItems.isEmpty {
                                        Text("套票项目快照缺失，需人工核对")
                                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(.orange)
                                    } else {
                                        Text(receipt["IsPreview"] as? Bool == true ? "确认后将一次核销以下全部项目：" : "整套已核销")
                                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                        if receipt["IsPreview"] as? Bool == true {
                                            ForEach(bundleItems.indices, id: \.self) { index in
                                                let redeemed = redemptions.contains { ($0["ItemIndex"] as? Int) == index }
                                                HStack {
                                                        VStack(alignment: .leading, spacing: 3) {
                                                            Text("\(bundleItems[index]["Name"] as? String ?? "套票项目") × \(bundleItems[index]["Quantity"] as? Int ?? 1)")
                                                                .lineLimit(1).truncationMode(.tail)
                                                            if let description = bundleItems[index]["Description"] as? String,
                                                               !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                                Text(description)
                                                                    .font(.system(size: NativeTypography.size(11)))
                                                                    .foregroundStyle(Brand.muted)
                                                                    .lineLimit(2).multilineTextAlignment(.leading)
                                                            }
                                                        }
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        Spacer()
                                                        Text(redeemed ? "已核销" : "本次包含")
                                                }.font(.system(size: NativeTypography.size(13))).foregroundStyle(redeemed ? Brand.muted : Brand.primary)
                                                    .padding(8).background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                    }
                                }
                                if receipt["IsPreview"] as? Bool != true {
                                    Text("\(receipt["VerificationPointName"] as? String ?? "检票点") · \(bookingBusinessDateTime(receipt["RedeemedAt"]) ?? "—")")
                                        .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("最近核销记录").font(.system(size: NativeTypography.size(16), weight: .semibold))
                            Spacer()
                            Button("刷新") { revision += 1 }
                                .font(.system(size: NativeTypography.size(14)))
                                .disabled(loading || redeeming || requestingCamera || scannerOpen)
                        }
                        if loading && records.isEmpty { ProgressView() }
                        else if records.isEmpty {
                            Text(error == nil ? "暂无核销记录" : "最近核销记录读取失败，请检查上方提示后重试。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(error == nil ? Brand.muted : .red)
                        }
                        ForEach(records.indices, id: \.self) { index in
                            let item = records[index]
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(item["TicketName"] as? String ?? "门票") · \(item["SessionName"] as? String ?? "场次")")
                                    .font(.system(size: NativeTypography.size(14), weight: .medium))
                                if item["TicketKind"] as? String == "Bundle" {
                                    if item["BundleRedeemedAsWhole"] as? Bool == true {
                                        Text("整套一次核销").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                    } else if let itemName = item["BundleItemName"] as? String, !itemName.isEmpty {
                                        Text("历史逐项核销：\(itemName) × \(item["BundleItemQuantity"] as? Int ?? 1)")
                                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                    }
                                    let bundleItems = item["BundleItems"] as? [[String: Any]] ?? []
                                    let summary = bundleItems.compactMap { bundleItem -> String? in
                                        guard let name = bundleItem["Name"] as? String, !name.isEmpty else { return nil }
                                        return "\(name) × \(bundleItem["Quantity"] as? Int ?? 1)"
                                    }.joined(separator: "、")
                                    if summary.isEmpty {
                                        Text("套票项目快照缺失，需人工核对")
                                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(.orange)
                                    } else {
                                        Text("套票包含（一张凭证一次核销全部项目）：\(summary)")
                                            .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                                    }
                                }
                                Text("\(item["VerificationPointName"] as? String ?? "检票点") · \(bookingBusinessDateTime(item["RedeemedAt"]) ?? "—")")
                                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
                }.padding(16)
            }
            .background(Brand.background)
            .navigationTitle("门票核销").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .confirmationDialog(receipt?["IsPreview"] as? Bool == true
                ? (receipt?["TicketKind"] as? String == "Bundle" ? "确认后整套一次核销全部项目。" : "确认后一次核销此门票凭证。")
                : "将先核对门票凭证状态。", isPresented: $confirmRedeem, titleVisibility: .visible) {
                Button(receipt?["IsPreview"] as? Bool == true ? (receipt?["TicketKind"] as? String == "Bundle" ? "确认整套核销" : "确认核销") : "核对凭证", role: .destructive) { Task { await redeem() } }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $scannerOpen) {
                let operation = cameraSequence
                let expectedPrincipal = scannerPrincipal
                NativeActivityQrScanner(inputLabel: "门票凭证码", onCode: { value in
                    guard operation == cameraSequence, !expectedPrincipal.isEmpty,
                          nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal else { return }
                    let scanned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !scanned.isEmpty && scanned.count <= 128 { code = scanned; error = nil; receipt = nil }
                    else { code = ""; receipt = nil; error = "二维码凭证码无效或超过 128 个字符，请手动核对。" }
                    cameraSequence += 1; scannerOpen = false; scannerPrincipal = ""
                }, onFailure: { message in
                    guard operation == cameraSequence, !expectedPrincipal.isEmpty,
                          nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal else { return }
                    error = message; cameraAvailable = false; cameraSequence += 1; scannerOpen = false; scannerPrincipal = ""
                })
                    .ignoresSafeArea()
            }
            .task(id: "\(nativeTourismPrincipal(store.session?.accessToken) ?? "")-\(revision)") { await loadData() }
            .onChange(of: nativeTourismPrincipal(store.session?.accessToken)) { _, _ in
                sequence += 1; redeemSequence += 1; cameraSequence += 1; requestingCamera = false; confirmRedeem = false; points = []; records = []; selectedPointId = ""; code = ""
                receipt = nil; error = nil; uncertain = false; unlockAfterRefresh = false
                loading = false; redeeming = false; scannerOpen = false; scannerPrincipal = ""
            }
            .onDisappear { sequence += 1; redeemSequence += 1; cameraSequence += 1; requestingCamera = false; redeeming = false; loading = false; confirmRedeem = false; code = ""; receipt = nil; scannerOpen = false; scannerPrincipal = "" }
        }
    }

    @MainActor private func loadData() async {
        guard let token = store.session?.accessToken, !token.isEmpty else {
            points = []; records = []; error = "请使用已获授权的文旅工作人员账号登录。"; loading = false; return
        }
        guard let expectedPrincipal = nativeTourismPrincipal(token) else {
            points = []; records = []; error = "登录账号信息无效，请重新登录。"; loading = false; return
        }
        sequence += 1; let current = sequence
        loading = true; error = nil; points = []; records = []
        do {
            guard let status = try await MobileAPI(store: store).get("/api/JHCTIFeatureAccess/GetPublicStatus?featureId=F-TKT-004") as? [String: Any],
                  let configured = status["IsConfigured"] as? Bool, let enabled = status["IsEnabled"] as? Bool,
                  nativeTourismPrincipal(store.session?.accessToken) == nativeTourismPrincipal(token), current == sequence else {
                throw MobileAPIError.unavailable("门票核销开放状态暂时无法确认，请重试")
            }
            featureOpen = configured && enabled
            guard featureOpen else { loading = false; return }
            guard let pointRows = try await MobileAPI(store: store).get("/api/JHCTITicket/GetMyVerificationPoints", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [[String: Any]],
                  nativeTourismPrincipal(store.session?.accessToken) == nativeTourismPrincipal(token), current == sequence else { throw MobileAPIError.unavailable("授权检票点回执无效，请重试") }
            guard pointRows.allSatisfy({ ($0["Id"] as? String).flatMap(Int64.init).map { $0 > 0 } == true && ($0["Name"] as? String)?.isEmpty == false && ($0["Sessions"] as? [[String: Any]]) != nil }) else {
                throw MobileAPIError.unavailable("授权检票点信息不完整，请刷新后重试")
            }
            points = pointRows.filter { $0["IsEnabled"] as? Bool == true }
            if !points.contains(where: { $0["Id"] as? String == selectedPointId }) { selectedPointId = points.first?["Id"] as? String ?? "" }
            let recordRows = try await MobileAPI(store: store).get("/api/JHCTITicket/GetMyVerificationRecords", authenticated: true,
                expectedPrincipal: expectedPrincipal) as? [[String: Any]]
            guard let recordRows, nativeTourismPrincipal(store.session?.accessToken) == nativeTourismPrincipal(token), current == sequence,
                  recordRows.allSatisfy({ ($0["Id"] as? String).flatMap(Int64.init).map { $0 > 0 } == true && ($0["CredentialId"] as? String).flatMap(Int64.init).map { $0 > 0 } == true }) else {
                throw MobileAPIError.unavailable("核销记录回执无效，请重试")
            }
            records = recordRows
            if unlockAfterRefresh { uncertain = false; unlockAfterRefresh = false }
        } catch is CancellationError {
            return
        } catch {
            if nativeTourismPrincipal(store.session?.accessToken) == nativeTourismPrincipal(token) && current == sequence { self.error = error.localizedDescription }
        }
        if nativeTourismPrincipal(store.session?.accessToken) == nativeTourismPrincipal(token) && current == sequence { loading = false }
    }

    @MainActor private func redeem() async {
        let submittedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard submittedCode.count <= 128, !submittedCode.isEmpty, !redeeming, !requestingCamera, !scannerOpen, !uncertain,
              let token = store.session?.accessToken, !selectedPointId.isEmpty else { return }
        let isPreviewConfirmation = receipt?["IsPreview"] as? Bool == true
        let pointId = selectedPointId
        let principal = nativeTourismPrincipal(token)
        redeemSequence += 1; let operation = redeemSequence
        redeeming = true; error = nil; receipt = nil
        defer { if operation == redeemSequence && nativeTourismPrincipal(store.session?.accessToken) == principal { redeeming = false } }
        do {
            var body: [String: Any] = ["VerificationPointId": pointId, "Code": submittedCode]
            if !isPreviewConfirmation { body["PreviewOnly"] = true }
            guard let result = try await MobileAPI(store: store).post("/api/JHCTITicket/Redeem", body: body, authenticated: true, expectedPrincipal: principal) as? [String: Any] else {
                throw MobileAPIError.unavailable("核销结果未确认，请刷新本人核销记录后核对")
            }
            guard operation == redeemSequence, nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
            guard (result["CredentialId"] as? String).flatMap(Int64.init).map({ $0 > 0 }) == true,
                  result["VerificationPointId"] as? String == pointId,
                  (result["TicketName"] as? String)?.isEmpty == false,
                  (result["SessionName"] as? String)?.isEmpty == false else {
                throw MobileAPIError.unavailable("核销结果无法确认，请刷新本人核销记录核对")
            }
            receipt = result; uncertain = false
            if result["IsPreview"] as? Bool != true {
                code = ""
                await loadData()
            }
        } catch is CancellationError {
            if operation == redeemSequence && nativeTourismPrincipal(store.session?.accessToken) == principal && isPreviewConfirmation {
                self.error = "核销结果未确认，请刷新本人核销记录核对。"
                uncertain = true
            }
        } catch {
            if operation == redeemSequence && nativeTourismPrincipal(store.session?.accessToken) == principal {
                self.error = error.localizedDescription
                uncertain = isPreviewConfirmation
            }
        }
    }

    @MainActor private func requestScannerAccess() async {
        guard !requestingCamera, !redeeming, !scannerOpen else { return }
        guard let token = store.session?.accessToken, !token.isEmpty else { error = "请使用已获授权的文旅工作人员账号登录。"; return }
        guard DataScannerViewController.isSupported else { error = "当前设备不支持扫码，请手动输入凭证码。"; return }
        cameraSequence += 1; let operation = cameraSequence
        let principal = nativeTourismPrincipal(token)
        requestingCamera = true
        defer { if operation == cameraSequence { requestingCamera = false } }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        if status == .authorized { granted = true }
        else if status == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .video) }
        else { granted = false }
        guard operation == cameraSequence, nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
        cameraAvailable = granted && DataScannerViewController.isAvailable
        scannerPrincipal = cameraAvailable ? principal ?? "" : ""
        if cameraAvailable { scannerOpen = true } else { error = "相机权限未开启或设备不可用，请手动输入凭证码。" }
    }
}
