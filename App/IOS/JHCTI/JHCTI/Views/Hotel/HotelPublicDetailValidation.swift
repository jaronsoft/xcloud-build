import Foundation
import CoreFoundation

private func nativeHotelCancellationRuleIsValid(_ mode: Any?, _ hoursRaw: Any?) -> Bool {
    guard let mode = mode as? String,
          let number = hoursRaw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
    let value = number.doubleValue
    guard value.isFinite, value.rounded(.towardZero) == value, value >= 0, value <= 8760 else { return false }
    switch mode {
    case "ManualReview": return value == 0
    case "FreeBeforeCheckIn": return value >= 1
    default: return false
    }
}

func nativeHotelDetailIsValid(_ value: [String: Any], expectedID: String) -> Bool {
    func positiveID(_ raw: Any?) -> String? {
        guard let id = raw as? String, let number = Int64(id), number > 0, String(number) == id else { return nil }
        return id
    }
    func optionalText(_ raw: Any?) -> Bool { raw == nil || raw is NSNull || raw is String }
    func integer(_ raw: Any?, minimum: Int, maximum: Int) -> Int? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let amount = number.doubleValue
        guard amount.isFinite, amount.rounded(.towardZero) == amount,
              amount >= Double(minimum), amount <= Double(maximum) else { return nil }
        return Int(amount)
    }
    func optionalAmount(_ raw: Any?, maximum: Double) -> Bool {
        guard let raw, !(raw is NSNull) else { return true }
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
        return number.doubleValue.isFinite && number.doubleValue >= 0 && number.doubleValue <= maximum
    }
    func validMedia(_ raw: Any?) -> Bool {
        guard let url = raw as? String, !url.isEmpty, url.utf8.count <= 2048,
              !url.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }),
              !url.contains("\\") else { return false }
        if url.hasPrefix("/") { return !url.hasPrefix("//") }
        guard let components = URLComponents(string: url) else { return false }
        return components.scheme?.lowercased() == "https" && !(components.host ?? "").isEmpty
    }
    func validTime(_ raw: Any?) -> Bool {
        guard let value = raw as? String else { return false }
        return value.range(of: "^(?:[01]\\d|2[0-3]):[0-5]\\d(?::[0-5]\\d)?$", options: .regularExpression) != nil
    }

    guard positiveID(expectedID) == expectedID, positiveID(value["Id"]) == expectedID,
          let name = value["Name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let address = value["Address"] as? String, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          optionalText(value["Description"]), optionalText(value["ContentHtml"]), optionalText(value["Phone"]),
          optionalText(value["CancellationPolicy"]), validTime(value["CheckInTime"]), validTime(value["CheckOutTime"]),
          nativeHotelCancellationRuleIsValid(value["CancellationMode"], value["FreeCancellationBeforeHours"]),
          let media = value["MediaUrls"] as? [Any], media.count <= 20, media.allSatisfy(validMedia),
          let amenities = value["Amenities"] as? [Any], amenities.allSatisfy({ $0 is String }),
          let rooms = value["RoomTypes"] as? [[String: Any]] else { return false }
    let latitudeRaw = value["Latitude"]
    let longitudeRaw = value["Longitude"]
    let latitudeNull = latitudeRaw == nil || latitudeRaw is NSNull
    let longitudeNull = longitudeRaw == nil || longitudeRaw is NSNull
    guard latitudeNull == longitudeNull else { return false }
    if !latitudeNull {
        guard let latitudeNumber = latitudeRaw as? NSNumber, CFGetTypeID(latitudeNumber) != CFBooleanGetTypeID(),
              let longitudeNumber = longitudeRaw as? NSNumber, CFGetTypeID(longitudeNumber) != CFBooleanGetTypeID() else { return false }
        let latitude = latitudeNumber.doubleValue
        let longitude = longitudeNumber.doubleValue
        guard latitude.isFinite, (-90...90).contains(latitude), longitude.isFinite, (-180...180).contains(longitude) else { return false }
    }
    guard ["Unknown", "WGS84", "GCJ02", "BD09"].contains(value["CoordinateSystem"] as? String ?? "") else { return false }

    var roomIDs = Set<String>()
    return rooms.allSatisfy { room in
        guard let roomID = positiveID(room["Id"]), roomIDs.insert(roomID).inserted,
              let roomName = room["Name"] as? String, !roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              optionalText(room["Description"]), optionalText(room["BedType"]),
              optionalAmount(room["AreaSqm"], maximum: Double.greatestFiniteMagnitude),
              let maximumGuests = integer(room["MaxGuests"], minimum: 1, maximum: 20), maximumGuests > 0,
              integer(room["BreakfastCount"], minimum: 0, maximum: Int(Int32.max)) != nil,
              let roomMedia = room["MediaUrls"] as? [Any], roomMedia.count <= 20, roomMedia.allSatisfy(validMedia),
              optionalAmount(room["MinPrice"], maximum: 99_999_999.99),
              optionalAmount(room["TotalStayPrice"], maximum: 99_999_999.99 * 30),
              integer(room["AvailableRooms"], minimum: 0, maximum: Int(Int32.max)) != nil else { return false }
        return true
    }
}
