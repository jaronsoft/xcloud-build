import Foundation

func nativeMapDistanceMeters(fromLatitude: Double, fromLongitude: Double, toLatitude: Double, toLongitude: Double) -> Double? {
    guard [fromLatitude, fromLongitude, toLatitude, toLongitude].allSatisfy(\.isFinite),
          abs(fromLatitude) <= 90, abs(toLatitude) <= 90, abs(fromLongitude) <= 180, abs(toLongitude) <= 180 else { return nil }
    let radians = Double.pi / 180
    let latitude = (toLatitude - fromLatitude) * radians
    let longitude = (toLongitude - fromLongitude) * radians
    let value = pow(sin(latitude / 2), 2) + cos(fromLatitude * radians) * cos(toLatitude * radians) * pow(sin(longitude / 2), 2)
    return 6_371_008.8 * 2 * asin(sqrt(min(1, max(0, value))))
}

func nativeMapDistanceText(_ meters: Double) -> String? {
    guard meters.isFinite, meters >= 0, meters <= Double.pi * 6_371_008.8 + 1 else { return nil }
    let rounded = meters.rounded()
    if rounded < 1000 { return "直线距离约 \(Int(rounded)) 米" }
    return String(format: "直线距离约 %.1f 公里", locale: Locale(identifier: "en_US_POSIX"), meters / 1000)
}

func nativeMapLocationDisplayExpiresAt(sampleAt: Date, receivedAt: Date) -> Date {
    min(sampleAt, receivedAt).addingTimeInterval(30)
}

// 仅接受本次主动定位的新鲜结果，避免缓存、过期位置或低精度点造成误导。
func nativeMapLocationUsable(latitude: Double, longitude: Double, accuracy: Double, timestamp: Double, now: Double, requestedAfter: Double) -> Bool {
    guard [latitude, longitude, accuracy, timestamp, now, requestedAfter].allSatisfy(\.isFinite),
          abs(latitude) <= 90, abs(longitude) <= 180, (0...1000).contains(accuracy) else { return false }
    return timestamp >= requestedAfter - 1 && timestamp >= now - 30 && timestamp <= now + 5
}

func nativeMapLocationDisplayExpiresAt(sampleAt: Double, receivedAt: Double) -> Double {
    min(sampleAt, receivedAt) + 30
}
