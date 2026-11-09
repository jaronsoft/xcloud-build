import SwiftUI
import VisionKit

struct NativeActivityQrScanner: UIViewControllerRepresentable {
    var inputLabel = "签到码"
    let onCode: (String) -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        do { try scanner.startScanning() }
        catch { context.coordinator.onFailure("无法启动相机扫码，请检查相机权限后手动输入\(inputLabel)。") }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(inputLabel: inputLabel, onCode: onCode, onFailure: onFailure) }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        private let inputLabel: String
        let onFailure: (String) -> Void
        private var didReturnCode = false

        init(inputLabel: String, onCode: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.inputLabel = inputLabel
            self.onCode = onCode
            self.onFailure = onFailure
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            guard !didReturnCode else { return }
            onFailure("相机扫码暂不可用，请手动输入\(inputLabel)。")
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !didReturnCode,
                  let value = addedItems.compactMap({ item -> String? in
                      guard case .barcode(let barcode) = item else { return nil }
                      return barcode.payloadStringValue
                  }).first else { return }
            didReturnCode = true
            scanner.stopScanning()
            onCode(value)
        }
    }
}
