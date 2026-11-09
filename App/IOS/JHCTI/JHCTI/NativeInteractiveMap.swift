import SwiftUI
import MapKit
import CoreLocation

struct NativeMapPin: Identifiable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

@MainActor
// 管理器在主线程创建，Core Location 通过该线程的 RunLoop 交付委托回调。
private final class NativeDetailLocator: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var point: CLLocation?
    @Published var busy = false
    @Published var message: String?
    @Published var permissionDenied = false
    private var manager: CLLocationManager?
    private var timeout: Timer?
    private var expiry: Timer?
    private var startedAt = Date()
    private var fixRequested = false

    func locate() {
        guard !busy else { return }
        stop()
        busy = true; message = nil; permissionDenied = false; startedAt = Date(); fixRequested = false
        let source = CLLocationManager()
        manager = source; source.delegate = self; source.desiredAccuracy = kCLLocationAccuracyHundredMeters
        timeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finish("定位超时，请检查定位服务后重试。") }
        }
        switch source.authorizationStatus {
        case .notDetermined: source.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: requestFix(source)
        case .denied, .restricted: permissionDenied = true; finish("定位权限未开启，可在系统设置中允许访问位置。")
        @unknown default: finish("定位暂不可用，请稍后重试。")
        }
    }

    func stop(clearPoint: Bool = true) {
        manager?.stopUpdatingLocation(); manager?.delegate = nil; manager = nil
        timeout?.invalidate(); timeout = nil; busy = false
        if clearPoint { expiry?.invalidate(); expiry = nil; point = nil; message = nil }
    }

    private func finish(_ error: String?) {
        manager?.stopUpdatingLocation(); manager?.delegate = nil; manager = nil
        timeout?.invalidate(); timeout = nil; busy = false; message = error
    }

    private func requestFix(_ source: CLLocationManager) {
        guard source === manager, !fixRequested, busy else { return }
        fixRequested = true; source.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ source: CLLocationManager) {
        guard source === manager, busy else { return }
        switch source.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: requestFix(source)
        case .denied, .restricted: permissionDenied = true; finish("定位权限未开启，可在系统设置中允许访问位置。")
        default: break
        }
    }

    func locationManager(_ source: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard source === manager, busy else { return }
        let now = Date()
        let usable = locations.filter {
            nativeMapLocationUsable(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                accuracy: $0.horizontalAccuracy, timestamp: $0.timestamp.timeIntervalSince1970,
                now: now.timeIntervalSince1970, requestedAfter: startedAt.timeIntervalSince1970)
        }.min { $0.horizontalAccuracy < $1.horizontalAccuracy }
        guard let usable else { finish("定位结果不够准确，请到开阔处重试。") ; return }
        finish(nil); point = usable
        let expiresAt = nativeMapLocationDisplayExpiresAt(sampleAt: usable.timestamp.timeIntervalSince1970,
                                                           receivedAt: now.timeIntervalSince1970)
        expiry = Timer.scheduledTimer(withTimeInterval: max(0.01, expiresAt - Date().timeIntervalSince1970), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.point = nil; self?.message = "位置信息已过期，请重新定位查看距离。"
            }
        }
    }

    func locationManager(_ source: CLLocationManager, didFailWithError error: Error) {
        guard source === manager, busy else { return }
        finish("暂时无法获取当前位置，请检查定位服务后重试。")
    }
}

private final class NativeMapAnnotation: MKPointAnnotation {
    let pinID: String
    init(_ pin: NativeMapPin) {
        pinID = pin.id
        super.init()
        title = pin.name; coordinate = pin.coordinate
    }
}

private struct NativeDetailMapCanvas: UIViewRepresentable {
    let pins: [NativeMapPin]
    @Binding var region: MKCoordinateRegion?
    @Binding var selectedID: String?
    let onBlankTap: (() -> Void)?
    let onFailure: () -> Void
    let onReady: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let view = MKMapView()
        view.delegate = context.coordinator
        view.isZoomEnabled = true; view.isScrollEnabled = true; view.isPitchEnabled = false
        view.showsScale = true; view.showsCompass = true
        view.addAnnotations(pins.map(NativeMapAnnotation.init))
        if let region { view.setRegion(region, animated: false) }
        else if pins.count == 1, let pin = pins.first {
            view.setRegion(.init(center: pin.coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)), animated: false)
        } else { view.showAnnotations(view.annotations, animated: false) }
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.blankTap(_:)))
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        single.numberOfTapsRequired = 1; double.numberOfTapsRequired = 2
        // 等待双击判定，且不取消 MapKit 的原生缩放、标记和拖动手势。
        single.require(toFail: double)
        for gesture in [single, double] {
            gesture.cancelsTouchesInView = false; gesture.delegate = context.coordinator; view.addGestureRecognizer(gesture)
        }
        return view
    }
    func updateUIView(_ view: MKMapView, context: Context) { context.coordinator.parent = self }
    static func dismantleUIView(_ view: MKMapView, coordinator: Coordinator) {
        coordinator.active = false; view.delegate = nil
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: NativeDetailMapCanvas
        var active = true
        init(_ parent: NativeDetailMapCanvas) { self.parent = parent }
        @objc func blankTap(_ gesture: UITapGestureRecognizer) {
            if active && gesture.state == .ended { parent.onBlankTap?() }
        }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) { }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var target = touch.view
            while let current = target {
                if current is MKAnnotationView || current is UIControl
                    || current.accessibilityTraits.contains(.link) || current.accessibilityTraits.contains(.button) { return false }
                target = current.superview
            }
            return true
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func mapView(_ view: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = view.region
            DispatchQueue.main.async { [weak self] in if self?.active == true { self?.parent.region = region } }
        }
        func mapView(_ view: MKMapView, didSelect annotation: MKAnnotationView) {
            if active, let pin = annotation.annotation as? NativeMapAnnotation { parent.selectedID = pin.pinID }
        }
        func mapViewDidFailLoadingMap(_ view: MKMapView, withError error: Error) {
            if active { parent.onFailure() }
        }
        func mapViewDidFinishLoadingMap(_ view: MKMapView) {
            if active { parent.onReady() }
        }
    }
}

struct NativeInteractiveMapView: View {
    let pins: [NativeMapPin]
    var title = "地图"
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locator = NativeDetailLocator()
    @State private var fullScreen = false
    @State private var region: MKCoordinateRegion?
    @State private var selectedID: String?
    @State private var failed = false
    @State private var loading = true
    @State private var revision = 0
    @State private var navigationError: String?

    private var selected: NativeMapPin? { pins.first { $0.id == selectedID } ?? (pins.count == 1 ? pins.first : nil) }
    private var distance: String? {
        guard let point = locator.point, let pin = selected else { return nil }
        return nativeMapDistanceMeters(fromLatitude: point.coordinate.latitude, fromLongitude: point.coordinate.longitude,
            toLatitude: pin.latitude, toLongitude: pin.longitude).flatMap(nativeMapDistanceText)
    }

    private func canvas(expand: Bool) -> some View {
        NativeDetailMapCanvas(pins: pins, region: $region, selectedID: $selectedID,
            onBlankTap: expand ? { loading = true; fullScreen = true } : nil, onFailure: { failed = true; loading = false }, onReady: { failed = false; loading = false })
            .id("\(revision)-\(expand)")
    }

    var body: some View {
        if !pins.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("双击或双指缩放，轻点空白处全屏查看").font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                    Spacer(minLength: 6)
                    Button { loading = true; fullScreen = true } label: { Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right").frame(minHeight: 44) }
                        .accessibilityLabel("全屏查看\(title)")
                }
                if fullScreen { Color.clear.frame(height: 220) }
                else { canvas(expand: true).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 10)) }
                actions
            }
            .fullScreenCover(isPresented: $fullScreen) {
                NavigationStack {
                    canvas(expand: false).ignoresSafeArea(edges: .bottom)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            actions
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.regularMaterial)
                        }
                        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { loading = true; fullScreen = false } } }
                        .onDisappear { locator.stop(clearPoint: false) }
                }
            }
            .onChange(of: pins) { _, _ in
                fullScreen = false; region = nil; selectedID = nil; failed = false; loading = true; navigationError = nil; revision += 1; locator.stop()
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { locator.stop() } }
            .onDisappear { if !fullScreen { locator.stop() } }
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if loading { ProgressView("正在加载地图…") }
            if failed {
                Text("地图暂时无法加载，可稍后重试或使用导航。")
                Button("重新加载地图") { failed = false; loading = true; revision += 1 }
            }
            if let selected {
                Text(selected.name).fontWeight(.semibold).lineLimit(2)
                if let distance { Text(distance).foregroundStyle(Brand.primary) }
                if let point = locator.point {
                    Text("定位精度约 \(Int(point.horizontalAccuracy.rounded())) 米；直线估算，实际路程以导航为准。")
                        .foregroundStyle(Brand.muted)
                }
                HStack(spacing: 16) {
                    Button(locator.busy ? "正在定位…" : "查看距我") { locator.locate() }.disabled(locator.busy)
                        .frame(minHeight: 44)
                    Button("开始导航") {
                        navigationError = nil
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: selected.coordinate)); item.name = selected.name
                        if !item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]) {
                            navigationError = "暂时无法打开系统导航，请稍后重试。"
                        }
                    }.frame(minHeight: 44)
                }
            } else { Text("轻点标记查看名称、距离和导航入口。") }
            if let message = locator.message { Text(message).foregroundStyle(Brand.muted) }
            if let navigationError { Text(navigationError).foregroundStyle(.red) }
            if locator.permissionDenied, let url = URL(string: UIApplication.openSettingsURLString) { Link("前往系统设置", destination: url) }
        }
        .font(.system(size: NativeTypography.size(12))).frame(maxWidth: .infinity, alignment: .leading)
    }
}
