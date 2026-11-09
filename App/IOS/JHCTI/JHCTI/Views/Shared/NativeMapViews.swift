import SwiftUI
import MapKit
import CoreLocation

// MapKit 使用 WGS84；未知坐标系按原始经纬度显示，确保已有坐标的详情页仍能展示地图。
enum MapCoordinate {
    static func gcj02(fromWgs84 coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        toGCJ(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    static func bd09(fromWgs84 coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let gcj = gcj02(fromWgs84: coordinate)
        let x = gcj.longitude, y = gcj.latitude
        let radius = sqrt(x * x + y * y) + 0.00002 * sin(y * .pi * 3000 / 180)
        let angle = atan2(y, x) + 0.000003 * cos(x * .pi * 3000 / 180)
        return .init(latitude: radius * sin(angle) + 0.006, longitude: radius * cos(angle) + 0.0065)
    }

    static func wgs84(latitude: Double, longitude: Double, system: String) -> CLLocationCoordinate2D? {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let normalizedSystem = system.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalizedSystem.isEmpty || normalizedSystem == "UNKNOWN" || normalizedSystem == "WGS84" {
            return .init(latitude: latitude, longitude: longitude)
        }
        var lat = latitude
        var lon = longitude
        if normalizedSystem == "BD09" {
            let x = lon - 0.0065, y = lat - 0.006
            let radius = sqrt(x * x + y * y) - 0.00002 * sin(y * .pi * 3000 / 180)
            let angle = atan2(y, x) - 0.000003 * cos(x * .pi * 3000 / 180)
            lon = radius * cos(angle); lat = radius * sin(angle)
        } else if normalizedSystem != "GCJ02" { return nil }
        for _ in 0..<6 {
            let shifted = toGCJ(latitude: lat, longitude: lon)
            lat += latitudeForGCJ(system: system, latitude: latitude, longitude: longitude) - shifted.latitude
            lon += longitudeForGCJ(system: system, latitude: latitude, longitude: longitude) - shifted.longitude
        }
        return .init(latitude: lat, longitude: lon)
    }

    private static func latitudeForGCJ(system: String, latitude: Double, longitude: Double) -> Double {
        if system.uppercased() != "BD09" { return latitude }
        let x = longitude - 0.0065, y = latitude - 0.006
        let radius = sqrt(x * x + y * y) - 0.00002 * sin(y * .pi * 3000 / 180)
        let angle = atan2(y, x) - 0.000003 * cos(x * .pi * 3000 / 180)
        return radius * sin(angle)
    }

    private static func longitudeForGCJ(system: String, latitude: Double, longitude: Double) -> Double {
        if system.uppercased() != "BD09" { return longitude }
        let x = longitude - 0.0065, y = latitude - 0.006
        let radius = sqrt(x * x + y * y) - 0.00002 * sin(y * .pi * 3000 / 180)
        let angle = atan2(y, x) - 0.000003 * cos(x * .pi * 3000 / 180)
        return radius * cos(angle)
    }

    private static func toGCJ(latitude: Double, longitude: Double) -> CLLocationCoordinate2D {
        if longitude < 72.004 || longitude > 137.8347 || latitude < 0.8293 || latitude > 55.8271 {
            return .init(latitude: latitude, longitude: longitude)
        }
        let x = longitude - 105, y = latitude - 35
        var latOffset = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        latOffset += (20*sin(6*x * .pi) + 20*sin(2*x * .pi)) * 2/3
        latOffset += (20*sin(y * .pi) + 40*sin(y/3 * .pi)) * 2/3
        latOffset += (160*sin(y/12 * .pi) + 320*sin(y * .pi/30)) * 2/3
        var lonOffset = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        lonOffset += (20*sin(6*x * .pi) + 20*sin(2*x * .pi)) * 2/3
        lonOffset += (20*sin(x * .pi) + 40*sin(x/3 * .pi)) * 2/3
        lonOffset += (150*sin(x/12 * .pi) + 300*sin(x/30 * .pi)) * 2/3
        let radians = latitude / 180 * Double.pi
        let eccentricity = 0.00669342162296594323
        let magic = 1 - eccentricity * pow(sin(radians), 2)
        let root = sqrt(magic)
        latOffset = latOffset * 180 / ((6378245 * (1-eccentricity)) / (magic*root) * .pi)
        lonOffset = lonOffset * 180 / (6378245 / root * cos(radians) * .pi)
        return .init(latitude: latitude + latOffset, longitude: longitude + lonOffset)
    }
}

struct NativeCoordinateMapCard: View {
    let title: String
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let coordinateSystem: String

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return MapCoordinate.wgs84(latitude: latitude, longitude: longitude, system: coordinateSystem)
    }

    var body: some View {
        if let coordinate {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline).foregroundStyle(Brand.ink)
                NativeInteractiveMapView(pins: [.init(id: "\(name):\(coordinate.latitude):\(coordinate.longitude)",
                    name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)], title: title)
                if let address, !address.isEmpty { Text(address).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

func nativeCoordinateNumber(_ values: [String: Any], keys: [String]) -> Double? {
    for key in keys {
        if let number = values[key] as? NSNumber { return number.doubleValue }
        if let text = values[key] as? String,
           let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return number
        }
    }
    return nil
}
