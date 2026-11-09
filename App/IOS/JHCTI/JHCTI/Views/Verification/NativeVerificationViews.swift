import AVFoundation
import CoreFoundation
import Foundation
import SwiftUI
import VisionKit

struct ActivityVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SessionStore
    @FocusState private var credentialFieldFocused: Bool
    @State private var credentialCode = ""
    @State private var legacyScannedCredential = false
    @State private var checkingIn = false
    @State private var error: String?
    @State private var receipt: [String: Any]?
    @State private var checkInSequence = 0
    @State private var cameraSequence = 0
    @State private var requestingCamera = false
    @State private var scannerOpen = false
    @State private var cameraAvailable = false
    @State private var scannerSessionPrincipal = ""

    private func updateCredentialInput(_ value: String) {
        if legacyScannedCredential && value.range(of: "^[0-9A-Fa-f]{0,32}$", options: .regularExpression) != nil {
            credentialCode = value
            receipt = nil
            return
        }
        legacyScannedCredential = false
        receipt = nil
        guard value.count <= 8 else {
            credentialCode = value
            error = "签到码最多输入 8 位数字。"
            return
        }
        credentialCode = value
        error = value.contains(where: { !$0.isASCII || !$0.isNumber })
            ? "签到码仅支持数字，请检查输入内容。"
            : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("现场签到").font(.system(size: NativeTypography.size(16), weight: .semibold))
                        Text("扫描游客的签到二维码，或输入 8 位数字签到码；系统会根据唯一凭证自动识别活动，并由服务端核验账号权限。")
                            .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        if DataScannerViewController.isSupported {
                            Button("扫描游客签到二维码") { Task { await requestScannerAccess() } }
                                .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.primary)
                                .frame(maxWidth: .infinity).frame(height: 42)
                                .background(Brand.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                .disabled(checkingIn || requestingCamera || scannerOpen)
                            if !cameraAvailable {
                                Text("首次扫码会请求相机权限；拒绝后仍可手动输入签到码。")
                                    .font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                            }
                        } else {
                            Text("当前设备或相机权限不可用，请手动输入签到码。")
                                .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                        }
                        TextField("8 位数字签到码", text: Binding(
                            get: { credentialCode },
                            set: updateCredentialInput
                        ))
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .focused($credentialFieldFocused)
                            .disabled(checkingIn || requestingCamera || scannerOpen)
                            .padding(12).background(Brand.background, in: RoundedRectangle(cornerRadius: 9))
                        if let error {
                            Text(error).font(.system(size: NativeTypography.size(14))).foregroundStyle(.red)
                        }
                        Button(checkingIn ? "正在核验…" : "确认签到") { Task { await checkIn() } }
                            .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(Brand.primary, in: RoundedRectangle(cornerRadius: 10))
                            .disabled(checkingIn || requestingCamera || scannerOpen || !isValidCredential(credentialCode))
                        if let receipt {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("核验成功").font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.primary)
                                Text("\(receipt["ActivityName"] as? String ?? "活动") · \(receipt["SessionName"] as? String ?? "活动场次")")
                                    .font(.system(size: NativeTypography.size(14)))
                                Text("\(receipt["Quantity"] as? Int ?? 1) 人已签到")
                                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(16)
            }
            .background(Brand.background)
            .navigationTitle("活动现场核验").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(checkingIn ? "正在核验…" : "完成核验") {
                        credentialFieldFocused = false
                        Task { await checkIn() }
                    }
                    .disabled(checkingIn || requestingCamera || scannerOpen || !isValidCredential(credentialCode))
                }
            }
            .onAppear { cameraAvailable = DataScannerViewController.isAvailable }
            .sheet(isPresented: $scannerOpen) {
                let scannerOperation = cameraSequence
                let expectedScannerPrincipal = scannerSessionPrincipal
                NativeActivityQrScanner(onCode: { scanned in
                    guard scannerOperation == cameraSequence, !expectedScannerPrincipal.isEmpty,
                          nativeTourismPrincipal(store.session?.accessToken) == expectedScannerPrincipal else { return }
                    let value = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
                    if isValidCredential(value) {
                        credentialCode = value
                        legacyScannedCredential = value.range(of: "^[0-9A-Fa-f]{32}$", options: .regularExpression) != nil
                        error = nil
                    } else {
                        credentialCode = ""
                        legacyScannedCredential = false
                        receipt = nil
                        error = "二维码不是有效的活动签到凭证，请核对游客凭证。"
                    }
                    cameraSequence += 1
                    scannerOpen = false
                    scannerSessionPrincipal = ""
                }, onFailure: { message in
                    guard scannerOperation == cameraSequence, !expectedScannerPrincipal.isEmpty,
                          nativeTourismPrincipal(store.session?.accessToken) == expectedScannerPrincipal else { return }
                    error = message
                    cameraAvailable = false
                    cameraSequence += 1
                    scannerOpen = false
                    scannerSessionPrincipal = ""
                })
                .ignoresSafeArea()
            }
            .onChange(of: nativeTourismPrincipal(store.session?.accessToken)) { _, _ in
                checkInSequence += 1; cameraSequence += 1; requestingCamera = false
                scannerOpen = false; scannerSessionPrincipal = ""
                credentialCode = ""; legacyScannedCredential = false; receipt = nil; error = nil; checkingIn = false
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    credentialCode = ""; legacyScannedCredential = false; receipt = nil
                    checkInSequence += 1; cameraSequence += 1; checkingIn = false; requestingCamera = false
                    scannerOpen = false; scannerSessionPrincipal = ""
                }
            }
            .onDisappear { checkInSequence += 1; cameraSequence += 1; requestingCamera = false; checkingIn = false; scannerOpen = false; scannerSessionPrincipal = ""; credentialCode = ""; legacyScannedCredential = false; receipt = nil }
        }
    }

    @MainActor private func checkIn() async {
        let code = credentialCode
        guard !checkingIn, !requestingCamera, !scannerOpen else { return }
        guard isValidCredential(code) else { return }
        guard let token = store.session?.accessToken, !token.isEmpty,
              let principal = nativeTourismPrincipal(token) else {
            error = "请使用已授权的文旅工作人员账号登录后核验。"
            return
        }
        checkInSequence += 1; let operation = checkInSequence
        checkingIn = true; error = nil; receipt = nil
        defer {
            if operation == checkInSequence && nativeTourismPrincipal(store.session?.accessToken) == principal { checkingIn = false }
        }
        do {
            let response = try await MobileAPI(store: store).post(
                "/api/JHCTIActivity/CheckInByAssignedCredential",
                body: ["CredentialCode": code], authenticated: true, expectedPrincipal: principal
            ) as? [String: Any]
            guard operation == checkInSequence, nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
            guard let response, let verifiedReceipt = readActivityCheckInReceipt(response) else {
                throw MobileAPIError.unavailable("签到结果无法确认，请刷新报名状态后再核对")
            }
            receipt = verifiedReceipt; credentialCode = ""; legacyScannedCredential = false
        } catch {
            guard operation == checkInSequence && nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
            if let apiError = error as? MobileAPIError, case let .forbidden(message) = apiError {
                cameraSequence += 1; scannerOpen = false; scannerSessionPrincipal = ""
                credentialCode = ""; legacyScannedCredential = false; receipt = nil
                self.error = message.isEmpty ? "当前账号没有此活动的核验权限，请联系该活动管理员。" : message
            } else if isUnknownActivityCheckInOutcome(error) {
                credentialCode = ""; legacyScannedCredential = false; receipt = nil
                self.error = "签到结果暂未确认，请先联系活动管理员核对签到记录，避免重复提交。"
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    private func readActivityCheckInReceipt(_ response: [String: Any]) -> [String: Any]? {
        func stringField(_ pascal: String, _ camel: String) -> String? {
            let first = response[pascal] as? String
            let second = response[camel] as? String
            if response[pascal] != nil && first == nil || response[camel] != nil && second == nil { return nil }
            if first != nil && second != nil && first != second { return nil }
            return first ?? second
        }
        func rawField(_ pascal: String, _ camel: String) -> Any? {
            let first = response[pascal]
            let second = response[camel]
            if let first, let second,
               !((first as? NSObject)?.isEqual(second) ?? false) { return nil }
            return first ?? second
        }
        guard let registrationId = stringField("RegistrationId", "registrationId"),
              let parsedId = Int64(registrationId), parsedId > 0, String(parsedId) == registrationId,
              let activityName = stringField("ActivityName", "activityName")?.trimmingCharacters(in: .whitespacesAndNewlines), !activityName.isEmpty,
              let sessionName = stringField("SessionName", "sessionName")?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionName.isEmpty,
              let quantityNumber = rawField("Quantity", "quantity") as? NSNumber,
              CFGetTypeID(quantityNumber) != CFBooleanGetTypeID(),
              quantityNumber.doubleValue.isFinite, quantityNumber.doubleValue.rounded() == quantityNumber.doubleValue,
              quantityNumber.intValue > 0, Double(quantityNumber.intValue) == quantityNumber.doubleValue,
              let checkedInAt = stringField("CheckedInAt", "checkedInAt")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !checkedInAt.isEmpty, isValidActivityCheckInTimestamp(checkedInAt) else { return nil }
        return ["RegistrationId": registrationId, "ActivityName": activityName, "SessionName": sessionName,
                "Quantity": quantityNumber.intValue, "CheckedInAt": checkedInAt]
    }

    private func isValidActivityCheckInTimestamp(_ value: String) -> Bool {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if iso.date(from: value) != nil { return true }
        iso.formatOptions = [.withInternetDateTime]
        if iso.date(from: value) != nil { return true }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = pattern
            if formatter.date(from: value) != nil { return true }
        }
        return false
    }

    private func isValidCredential(_ value: String) -> Bool {
        value.range(of: "^(?:[0-9]{8}|[0-9A-Fa-f]{32})$", options: .regularExpression) != nil
    }

    private func isUnknownActivityCheckInOutcome(_ error: Error) -> Bool {
        guard let apiError = error as? MobileAPIError else { return true }
        if let status = apiError.httpStatusCode {
            return !(400..<500).contains(status) || status == 408 || status == 429
        }
        if case .forbidden(_) = apiError { return false }
        return true
    }

    @MainActor private func requestScannerAccess() async {
        guard !requestingCamera, !checkingIn, !scannerOpen else { return }
        guard let token = store.session?.accessToken, !token.isEmpty,
              let principal = nativeTourismPrincipal(token) else {
            error = "请使用已授权的文旅工作人员账号登录。"; return
        }
        guard DataScannerViewController.isSupported else {
            error = "当前设备不支持二维码扫描，请手动输入签到码。"; return
        }
        cameraSequence += 1; let operation = cameraSequence
        requestingCamera = true
        defer { if operation == cameraSequence { requestingCamera = false } }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        if status == .authorized { granted = true }
        else if status == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .video) }
        else { granted = false }
        guard operation == cameraSequence, nativeTourismPrincipal(store.session?.accessToken) == principal else { return }
        cameraAvailable = granted && DataScannerViewController.isAvailable
        if cameraAvailable {
            credentialCode = ""; legacyScannedCredential = false; receipt = nil
            scannerSessionPrincipal = principal; scannerOpen = true
        }
        else { error = "相机权限未开启或设备当前不可用，请手动输入签到码。" }
    }
}
