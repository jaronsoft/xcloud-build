import SwiftUI
import CoreLocation

@MainActor
final class NearbyLocator: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var message: String?
    @Published var busy = false
    private let manager = CLLocationManager()
    private var timeout: Timer?
    private var fixRequested = false
    private var requestedAt = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func locate() {
        guard !busy else { return }
        busy = true; location = nil; message = nil; fixRequested = false
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finish("定位响应超时，请检查设备定位服务和网络后重试。") }
        }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: requestFix()
        case .denied, .restricted: finish("定位权限未开启，请在系统设置中允许访问位置。")
        @unknown default: finish("定位暂不可用，请稍后重试。")
        }
    }

    func expire(_ message: String? = nil) {
        manager.stopUpdatingLocation()
        timeout?.invalidate(); timeout = nil
        fixRequested = false
        busy = false
        location = nil
        self.message = message
    }

    func refreshPermissionAfterSettings() -> Bool {
        guard message?.contains("定位权限未开启") == true,
              (manager.authorizationStatus == .authorizedAlways
                || manager.authorizationStatus == .authorizedWhenInUse) else { return false }
        message = nil
        return true
    }

    private func requestFix() {
        guard busy, !fixRequested else { return }
        fixRequested = true
        requestedAt = Date()
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard busy else { return }
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            requestFix()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            finish("定位权限未开启，请在系统设置中允许访问位置。")
        }
    }

    private func finish(_ error: String?) {
        manager.stopUpdatingLocation()
        timeout?.invalidate(); timeout = nil
        busy = false
        message = error
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard busy else { return }
        let now = Date().timeIntervalSince1970
        let usable = locations.filter {
            nativeMapLocationUsable(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                accuracy: $0.horizontalAccuracy, timestamp: $0.timestamp.timeIntervalSince1970,
                now: now, requestedAfter: requestedAt.timeIntervalSince1970)
        }.min { $0.horizontalAccuracy < $1.horizontalAccuracy }
        guard let usable else {
            finish("定位结果不够准确或已过期，请到开阔处重试。")
            return
        }
        location = usable
        finish(nil)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard busy else { return }
        finish("暂时无法获取当前位置，请检查定位服务后重试。")
    }
}

struct NearbyActivityCover: View {
    let store: SessionStore
    let imagePath: String?
    @State private var imageLoaded = false

    private var imageURL: URL? { MobileAPI(store: store).mediaURL(imagePath) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let imageURL {
                CachedRemoteImage(url: imageURL, onLoadResult: { imageLoaded = $0 }) {
                    Image("Quick4").resizable().scaledToFill()
                }
            } else {
                Image("Quick4").resizable().scaledToFill()
            }
            if !imageLoaded {
                Text("主题插画").font(.system(size: 8)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(Color.black.opacity(0.55), in: Capsule()).padding(4)
            }
        }
        .frame(width: 76, height: 58).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: imagePath) { _, _ in imageLoaded = false }
    }
}
