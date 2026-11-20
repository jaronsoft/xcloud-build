import Foundation
import CoreLocation

@MainActor
func nativeFetchNearbyResources(store: SessionStore, location: CLLocation, keyword requestKeyword: String,
                                resourceType selectedResourceType: String,
                                coordinateSystems: Set<String>? = nil,
                                allowEmptyResults: Bool = false) async throws -> ([ResourceItem], Set<String>) {
    let coordinate = location.coordinate
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&=+#")
    let encodedKeyword = requestKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        .addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    let keywordQuery = encodedKeyword.isEmpty ? "" : "&keyword=\(encodedKeyword)"
    let typeQuery = selectedResourceType == "Facility"
        ? "&resourceType=Facility&includeParentLocationFacilities=true" : "&resourceType=ScenicSpot"
    let gcj = MapCoordinate.gcj02(fromWgs84: coordinate)
    let bd09 = MapCoordinate.bd09(fromWgs84: coordinate)
    let coordinates: [(CLLocationCoordinate2D, String)] = [(coordinate, "WGS84"), (gcj, "GCJ02"), (bd09, "BD09")]
    let requestedSystems = coordinateSystems ?? Set(coordinates.map { $0.1 })
    let api = MobileAPI(store: store)
    func read(_ point: CLLocationCoordinate2D, system: String) async throws -> Data? {
        let path = "/api/JHCTITourismResource/GetNearby?longitude=\(point.longitude)&latitude=\(point.latitude)&coordinateSystem=\(system)&radiusKm=30&limit=20&includeDetails=false\(typeQuery)\(keywordQuery)"
        do {
            let value = try await api.get(path)
            guard let rows = value as? [[String: Any]], rows.allSatisfy({
                ResourceItem($0) != nil && ($0["ResourceType"] as? String) == selectedResourceType
            }) else { return nil }
            return try JSONSerialization.data(withJSONObject: rows)
        }
        catch is CancellationError { throw CancellationError() }
        catch { return nil }
    }
    func readIfRequested(_ index: Int) async throws -> Data? {
        let (point, system) = coordinates[index]
        guard requestedSystems.contains(system) else { return nil }
        return try await read(point, system: system)
    }
    async let first = readIfRequested(0)
    async let second = readIfRequested(1)
    async let third = readIfRequested(2)
    let results = try await [first, second, third]
    try Task.checkCancellation()
    let failedSystems = Set(coordinates.indices.compactMap { index -> String? in
        requestedSystems.contains(coordinates[index].1) && results[index] == nil ? coordinates[index].1 : nil
    })
    let successful = results.enumerated().compactMap { index, data -> (Int, [[String: Any]])? in
        guard let data, let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return (index, rows)
    }
    guard !successful.isEmpty || allowEmptyResults else {
        throw MobileAPIError.unavailable("附近\(selectedResourceType == "Facility" ? "服务设施" : "景点")暂时无法加载，请稍后重试。")
    }
    var unique: [String: (index: Int, row: [String: Any], distance: Double)] = [:]
    for (queryIndex, rows) in successful {
        for (rowIndex, row) in rows.enumerated() {
            guard let item = ResourceItem(row) else {
                throw MobileAPIError.unavailable("附近\(selectedResourceType == "Facility" ? "服务设施" : "景点")数据暂时无法读取，请重试。")
            }
            let index = queryIndex * 100 + rowIndex
            let distance = item.distanceKm ?? .infinity
            if let current = unique[item.id] {
                if distance < current.distance { unique[item.id] = (current.index, row, distance) }
            } else {
                unique[item.id] = (index, row, distance)
            }
        }
    }
    let items = unique.values.sorted {
        $0.distance == $1.distance ? $0.index < $1.index : $0.distance < $1.distance
    }.prefix(20).compactMap { ResourceItem($0.row) }
    return (items, failedSystems)
}
