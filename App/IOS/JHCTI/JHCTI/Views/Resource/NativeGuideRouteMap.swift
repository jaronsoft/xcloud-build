import SwiftUI
import MapKit
import CoreLocation

private struct NativeGuideRouteMapPoint: Identifiable {
    let id: String
    let order: Int
    let name: String
    let detail: String?
    let coordinate: CLLocationCoordinate2D
}

struct NativeGuideRouteMap: View {
    let route: [String: Any]
    let routeIndex: Int

    private var rawPoints: [[String: Any]] { route["Points"] as? [[String: Any]] ?? [] }
    private var points: [NativeGuideRouteMapPoint] {
        rawPoints.enumerated().compactMap { index, point in
            guard let latitude = (point["Latitude"] as? NSNumber)?.doubleValue,
                  let longitude = (point["Longitude"] as? NSNumber)?.doubleValue else { return nil }
            let system = (point["CoordinateSystem"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard ["WGS84", "GCJ02", "BD09"].contains(system.uppercased()),
                  let coordinate = MapCoordinate.wgs84(latitude: latitude, longitude: longitude, system: system) else { return nil }
            let name = (point["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = (point["Description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return NativeGuideRouteMapPoint(id: "\(route["Id"] as? String ?? "route-\(routeIndex)")-\(index)",
                order: index + 1, name: name.flatMap { $0.isEmpty ? nil : $0 } ?? "途经点 \(index + 1)",
                detail: detail.flatMap { $0.isEmpty ? nil : $0 }, coordinate: coordinate)
        }
    }

    private var region: MKCoordinateRegion {
        let latitudes = points.map { $0.coordinate.latitude }
        let longitudes = points.map { $0.coordinate.longitude }
        let latitudeSpan = max(0.004, ((latitudes.max() ?? 0) - (latitudes.min() ?? 0)) * 1.5)
        let longitudeSpan = max(0.004, ((longitudes.max() ?? 0) - (longitudes.min() ?? 0)) * 1.5)
        return MKCoordinateRegion(center: .init(latitude: ((latitudes.max() ?? 0) + (latitudes.min() ?? 0)) / 2,
            longitude: ((longitudes.max() ?? 0) + (longitudes.min() ?? 0)) / 2),
            span: .init(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(route["Name"] as? String ?? route["Title"] as? String ?? "路线 \(routeIndex + 1)")
                .font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.ink)
            if let description = route["Description"] as? String, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(description).font(.system(size: NativeTypography.size(12))).foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if points.isEmpty {
                Text("暂无可显示的路线坐标。").font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted)
            } else {
                ZStack(alignment: .bottom) {
                    Map(initialPosition: .region(region)) {
                        if points.count >= 2 && points.count == rawPoints.count {
                            MapPolyline(coordinates: points.map(\.coordinate)).stroke(Brand.primary.opacity(0.8), lineWidth: 4)
                        }
                        ForEach(points) { point in
                            Annotation("\(point.order). \(point.name)", coordinate: point.coordinate, anchor: .bottom) {
                                Text("\(point.order)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 24, height: 24).background(Brand.primary, in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                    }
                    .mapControlVisibility(.hidden)
                    if points.count < 2 || points.count != rawPoints.count {
                        Text(points.count != rawPoints.count ? "部分途经点缺少有效坐标，地图暂不连线。" : "路线至少需要2个有效途经点才能绘制路线。")
                            .font(.system(size: NativeTypography.size(10))).foregroundStyle(Brand.muted)
                            .frame(maxWidth: .infinity).padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.white.opacity(0.9))
                    }
                }
                .frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if rawPoints.isEmpty {
                Text("该路线尚未配置途经点。").font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted)
            } else {
                ForEach(Array(rawPoints.enumerated()), id: \.offset) { index, point in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.primary)
                            Text((point["Name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "途经点 \(index + 1)")
                                .font(.system(size: NativeTypography.size(12), weight: .medium)).foregroundStyle(Brand.ink)
                        }
                        if let detail = point["Description"] as? String, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(detail).font(.system(size: NativeTypography.size(11))).foregroundStyle(Brand.muted)
                                .fixedSize(horizontal: false, vertical: true).padding(.leading, 20)
                        }
                    }
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.97, green: 0.98, blue: 0.97), in: RoundedRectangle(cornerRadius: 12))
    }
}
