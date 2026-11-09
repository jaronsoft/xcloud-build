import Foundation

struct ResourceItem: Identifiable {
    let id: String
    let name: String
    let region: String
    let address: String
    let description: String
    let admissionType: String
    let resourceType: String
    let facilityType: String
    let openStatus: String
    let coverURL: String
    let latitude: Double?
    let longitude: Double?
    let distanceKm: Double?
    let locationIsApproximate: Bool

    init?(_ value: [String: Any]) {
        guard let id = nativeCartID(value["Id"]) else { return nil }
        self.id = id
        name = value["Name"] as? String ?? "景点"
        region = value["Region"] as? String ?? ""
        address = value["Address"] as? String ?? ""
        description = value["Description"] as? String ?? ""
        admissionType = value["AdmissionType"] as? String ?? ""
        resourceType = value["ResourceType"] as? String ?? "ScenicSpot"
        facilityType = value["FacilityType"] as? String ?? "Other"
        openStatus = value["OpenStatus"] as? String ?? ""
        coverURL = (value["ImageUrls"] as? [String])?.first
            ?? value["CoverUrl"] as? String ?? value["ImageUrl"] as? String ?? ""
        if let rawLatitude = (value["Latitude"] as? NSNumber)?.doubleValue,
           let rawLongitude = (value["Longitude"] as? NSNumber)?.doubleValue,
           let coordinate = MapCoordinate.wgs84(latitude: rawLatitude, longitude: rawLongitude,
                                               system: value["CoordinateSystem"] as? String ?? "") {
            latitude = coordinate.latitude
            longitude = coordinate.longitude
        } else { latitude = nil; longitude = nil }
        let rawDistance = value["DistanceKm"]
        let parsedDistance = (rawDistance as? NSNumber)?.doubleValue
            ?? (rawDistance as? String).flatMap(Double.init)
        distanceKm = parsedDistance.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        locationIsApproximate = value["LocationIsApproximate"] as? Bool ?? false
    }

    var facilityTypeLabel: String {
        switch facilityType {
        case "Restroom": "卫生间"
        case "ParkingLot": "停车场"
        case "GasStation": "加油站"
        default: "其他设施"
        }
    }

    var openStatusLabel: String {
        switch openStatus {
        case "Open": "正常开放"
        case "Closed": "暂未开放"
        case "TemporarilyClosed": "暂时关闭"
        default: "状态待核实"
        }
    }

    var admissionCardLabel: String {
        switch admissionType {
        case "Paid": "收费"
        case "Free": "免费"
        case "FreeReservation": "预约·免费"
        case "PaidReservation": "预约·收费"
        default: "入园方式待确认"
        }
    }

    var cardOpenStatusLabel: String {
        switch openStatus {
        case "Open": "正常开放"
        case "Closed": "暂未开放"
        case "TemporarilyClosed": "暂时关闭"
        default: "开放状态待核实"
        }
    }
}
