import SwiftUI
import AVFoundation
import VisionKit
import UIKit

struct ActivityRegistrationSelfCheckIn: View {
    @ObservedObject var store: SessionStore
    let onCompleted: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var active = true
    @State private var scanning = false
    @State private var scannerOpen = false
    @State private var scannerPrincipal = ""
    @State private var sequence = 0
    @State private var submittingParticipantID = ""
    @State private var checkInError: String?
    @State private var activityID = ""
    @State private var participants: [[String: Any]] = []

    private var principal: String? { nativeTourismPrincipal(store.session?.accessToken) }

    private func isValidIdentifier(_ value: String) -> Bool {
        guard value.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil else { return false }
        let maximum = "9223372036854775807"
        return value.count < maximum.count || value <= maximum
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(scanning ? "正在扫码…" : submittingParticipantID.isEmpty ? "现场扫码签到" : "正在提交签到…") {
                Task { await requestScannerAccess() }
            }
            .disabled(scanning || scannerOpen || !submittingParticipantID.isEmpty || scenePhase != .active)
            .accessibilityLabel("扫描活动现场二维码签到")
            if !participants.isEmpty {
                Text("请选择本次要签到的同行参与者")
                    .font(.system(size: NativeTypography.size(13), weight: .medium))
                ForEach(Array(participants.enumerated()), id: \.offset) { index, participant in
                    let participantID = participant["Id"] as? String ?? ""
                    let name = (participant["DisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                        ?? "参与者 \(participant["ParticipantNo"] as? Int ?? index + 1)"
                    Button(submittingParticipantID == participantID ? "正在签到…" : "为\(name)签到") {
                        Task { await submit(activityID: activityID, participant: participant) }
                    }
                    .disabled(!submittingParticipantID.isEmpty)
                    .accessibilityLabel("为\(name)签到")
                }
            }
            if let checkInError {
                Text(checkInError).font(.system(size: NativeTypography.size(12)))
                    .foregroundStyle(checkInError.hasSuffix("签到成功。") ? Brand.primary : .red)
            }
        }
        .sheet(isPresented: $scannerOpen) {
            let expectedPrincipal = scannerPrincipal
            NativeActivityQrScanner(inputLabel: "活动现场二维码", onCode: { scanned in
                guard !expectedPrincipal.isEmpty,
                      nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal else {
                    scannerOpen = false; scannerPrincipal = ""; return
                }
                scannerOpen = false; scannerPrincipal = ""
                Task { await resolve(scanned, expectedPrincipal: expectedPrincipal) }
            }, onFailure: { message in
                guard nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal else { return }
                checkInError = message; scannerOpen = false; scannerPrincipal = ""
            })
            .ignoresSafeArea()
        }
        .onChange(of: nativeTourismPrincipal(store.session?.accessToken)) { _, _ in
            sequence += 1; scanning = false; submittingParticipantID = ""
            scannerOpen = false; scannerPrincipal = ""; participants = []; activityID = ""
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                sequence += 1; scanning = false; submittingParticipantID = ""
                scannerOpen = false; scannerPrincipal = ""; participants = []; activityID = ""
            }
        }
        .onDisappear {
            active = false; sequence += 1; scanning = false; submittingParticipantID = ""
            scannerOpen = false; scannerPrincipal = ""; participants = []; activityID = ""
        }
        .onAppear { active = true }
    }

    @MainActor private func requestScannerAccess() async {
        guard let token = store.session?.accessToken, !token.isEmpty,
              let currentPrincipal = nativeTourismPrincipal(token) else {
            checkInError = "请先登录后再进行活动签到。"
            return
        }
        guard active, scenePhase == .active, !scanning, !scannerOpen, submittingParticipantID.isEmpty else { return }
        sequence += 1; scanning = true; checkInError = nil; participants = []; activityID = ""
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        if status == .authorized { granted = true }
        else if status == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .video) }
        else { granted = false }
        guard active, scenePhase == .active, nativeTourismPrincipal(store.session?.accessToken) == currentPrincipal else {
            scanning = false; return
        }
        guard granted && DataScannerViewController.isSupported && DataScannerViewController.isAvailable else {
            scanning = false; checkInError = "相机权限未开启或设备不可用，请检查相机权限后重试。"; return
        }
        scannerPrincipal = currentPrincipal; scanning = false; scannerOpen = true
    }

    @MainActor private func resolve(_ rawCode: String, expectedPrincipal: String) async {
        guard let token = store.session?.accessToken, nativeTourismPrincipal(token) == expectedPrincipal else { return }
        sequence += 1; let operation = sequence
        scanning = true; checkInError = nil
        func isCurrent() -> Bool {
            active && scenePhase == .active && sequence == operation
                && nativeTourismPrincipal(store.session?.accessToken) == expectedPrincipal
        }
        defer { if isCurrent() { scanning = false } }
        do {
            let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let queryAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))
            guard let encodedCode = code.addingPercentEncoding(withAllowedCharacters: queryAllowed),
                  let route = try await MobileAPI(store: store).get("/api/JHCTIScan/Resolve?code=\(encodedCode)") as? [String: Any], isCurrent() else {
                throw NSError(domain: "ActivitySelfCheckIn", code: 1, userInfo: [NSLocalizedDescriptionKey: "活动二维码无效"])
            }
            let available = route["IsAvailable"] as? Bool ?? route["isAvailable"] as? Bool ?? false
            let resultCode = route["ResultCode"] as? String ?? route["resultCode"] as? String ?? ""
            let scene = route["SceneType"] as? String ?? route["sceneType"] as? String ?? ""
            // 自助签到只接受已就绪的活动场景码，避免近似类型或异常回执进入参与者查询。
            guard available, resultCode == "Ready", scene == "Activity" else {
                throw NSError(domain: "ActivitySelfCheckIn", code: 2, userInfo: [NSLocalizedDescriptionKey: route["Message"] as? String ?? "请扫描活动现场二维码"])
            }
            let resolvedID = route["Id"] as? String ?? route["id"] as? String ?? ""
            guard isValidIdentifier(resolvedID) else {
                throw NSError(domain: "ActivitySelfCheckIn", code: 3, userInfo: [NSLocalizedDescriptionKey: "活动二维码无效"])
            }
            let options = try await MobileAPI(store: store).get("/api/JHCTIActivity/GetSelfCheckInOptions?activityId=\(resolvedID)", authenticated: true, expectedPrincipal: expectedPrincipal) as? [String: Any]
            guard isCurrent(), let options, let values = options["Participants"] as? [[String: Any]], !values.isEmpty else {
                throw NSError(domain: "ActivitySelfCheckIn", code: 4, userInfo: [NSLocalizedDescriptionKey: "当前活动时段没有可签到的本人报名参与者"])
            }
            guard values.allSatisfy({ ($0["Id"] as? String).map(isValidIdentifier) == true }) else {
                throw NSError(domain: "ActivitySelfCheckIn", code: 5, userInfo: [NSLocalizedDescriptionKey: "签到参与者编号无效，请刷新报名记录后重试"])
            }
            activityID = resolvedID; participants = values
            if values.count == 1 {
                scanning = false
                await submit(activityID: resolvedID, participant: values[0], expectedPrincipal: expectedPrincipal)
            }
        } catch {
            if isCurrent() { checkInError = error.localizedDescription }
        }
    }

    @MainActor private func submit(activityID: String, participant: [String: Any], expectedPrincipal: String? = nil) async {
        let expected = expectedPrincipal ?? principal
        guard let expected, let token = store.session?.accessToken,
              nativeTourismPrincipal(token) == expected,
              isValidIdentifier(activityID),
              let participantID = participant["Id"] as? String,
              isValidIdentifier(participantID),
              active, scenePhase == .active, submittingParticipantID.isEmpty else { return }
        sequence += 1; let operation = sequence
        submittingParticipantID = participantID; checkInError = nil
        func isCurrent() -> Bool {
            active && scenePhase == .active && sequence == operation
                && nativeTourismPrincipal(store.session?.accessToken) == expected
        }
        defer { if isCurrent() { submittingParticipantID = "" } }
        do {
            _ = try await MobileAPI(store: store).post("/api/JHCTIActivity/SelfCheckIn",
                body: ["ActivityId": activityID, "ParticipantId": participantID],
                authenticated: true, expectedPrincipal: expected)
            guard isCurrent() else { return }
            let name = participant["DisplayName"] as? String ?? "参与者"
            checkInError = "\(name)签到成功。"; participants = []; self.activityID = ""
            onCompleted()
        } catch { if isCurrent() { checkInError = error.localizedDescription } }
    }
}
