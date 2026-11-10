import SwiftUI

struct DineWiseWeatherView: View {
    @Environment(\.colorScheme) private var colorScheme
    let token: String?
    let storeLatitude: Double?
    let storeLongitude: Double?
    let storeTimeZone: String?

    @StateObject private var location = DineWiseLocationProvider()
    @State private var forecast: DineWiseWeatherForecast?
    @State private var message = ""
    @State private var loading = false
    @State private var activeScopeKey = ""
    @State private var scopeGeneration = 0
    @State private var requestGeneration = 0
    @State private var locationRequestScopeGeneration: Int?
    private let api = DineWiseAPI()

    private var requestScopeKey: String {
        let latitude = storeLatitude.map { String($0) } ?? "unset"
        let longitude = storeLongitude.map { String($0) } ?? "unset"
        return "\(token ?? "guest"):\(latitude):\(longitude)"
    }

    private var validStoreCoordinates: (latitude: Double, longitude: Double)? {
        guard let latitude = storeLatitude, let longitude = storeLongitude,
              isValidCoordinate(latitude, longitude) else { return nil }
        return (latitude, longitude)
    }

    private var hasPartialStoreCoordinates: Bool {
        storeLatitude != nil || storeLongitude != nil
    }

    private func isValidCoordinate(_ latitude: Double, _ longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("附近天气").font(.headline)
                Spacer()
                Text("未来三天").font(.caption).foregroundStyle(.secondary)
            }
            Text(validStoreCoordinates != nil
                ? "点按后可按已保存的门店位置查看区域预报；改用当前位置时才会请求定位。"
                : hasPartialStoreCoordinates
                    ? "门店位置数据不完整或无效；可改用当前位置，或更新门店档案。"
                    : "按当前位置查看区域预报；需要您允许定位。")
                .font(.footnote).foregroundStyle(.secondary)
            Text("仅在您点按后获取附近天气；使用当前位置时需要您允许定位。坐标按约 10 公里范围处理，同一区域每天最多请求一次上游预报。")
                .font(.footnote).foregroundStyle(.secondary)
            if let coordinates = validStoreCoordinates {
                Button(loading ? "获取中…" : forecast == nil ? "查看门店附近天气" : "再次查看门店附近天气") {
                    fetch(latitude: coordinates.latitude, longitude: coordinates.longitude)
                }
            }
            Button(loading ? "获取中…" : validStoreCoordinates == nil ? "查看附近天气" : "改用当前位置") {
                requestCurrentLocation()
            }.disabled(loading)
            if !message.isEmpty {
                Text(message).font(.footnote)
                    .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
            }
            if let forecast {
                Text(forecast.Area).font(.subheadline.bold())
                Text("更新时间：\(dineWiseFormatTimestamp(forecast.UpdatedAtUtc, timeZoneID: storeTimeZone))")
                    .font(.caption).foregroundStyle(.secondary)
                Text("来源：\(forecast.Source)")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(forecast.Days) { day in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(String(day.Date.suffix(5))).font(.caption.bold())
                            Text(day.Condition).font(.caption)
                            Text("\(day.MinC, specifier: "%.0f")–\(day.MaxC, specifier: "%.0f")℃")
                                .font(.caption.bold())
                            Text("降雨 \(day.RainChance)%").font(.caption2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(DineWiseTheme.accent(for: colorScheme).opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 11))
                    }
                }
                Text("天气预报仅供一般参考，可能与您所在位置或时刻的实际天气不同；人身安全、航空、海上导航及应急决策不可仅据此判断，请以官方气象机构及有关部门信息为准。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .onChange(of: location.latitude) { _, _ in fetchIfLocated() }
        .onChange(of: location.longitude) { _, _ in fetchIfLocated() }
        .onChange(of: location.error) { _, error in
            guard !error.isEmpty,
                  locationRequestScopeGeneration == scopeGeneration else { return }
            locationRequestScopeGeneration = nil
            message = error
            loading = false
        }
        .onChange(of: requestScopeKey, initial: true) { _, scopeKey in
            activeScopeKey = scopeKey
            scopeGeneration += 1
            requestGeneration += 1
            forecast = nil; message = ""
            loading = false
            locationRequestScopeGeneration = nil
        }
    }

    private func requestCurrentLocation() {
        guard activeScopeKey == requestScopeKey else { return }
        forecast = nil
        message = ""
        loading = true
        locationRequestScopeGeneration = scopeGeneration
        location.clear()
        location.request()
        if !location.error.isEmpty,
           locationRequestScopeGeneration == scopeGeneration {
            locationRequestScopeGeneration = nil
            message = location.error
            loading = false
        }
    }

    private func fetchIfLocated() {
        guard let locationRequestScopeGeneration,
              locationRequestScopeGeneration == scopeGeneration,
              let latitude = location.latitude, let longitude = location.longitude else { return }
        self.locationRequestScopeGeneration = nil
        fetch(latitude: latitude, longitude: longitude,
             expectedScopeGeneration: locationRequestScopeGeneration)
    }

    private func fetch(latitude: Double, longitude: Double,
                       expectedScopeGeneration: Int? = nil) {
        guard activeScopeKey == requestScopeKey,
              expectedScopeGeneration == nil || expectedScopeGeneration == scopeGeneration else { return }
        guard isValidCoordinate(latitude, longitude) else {
            forecast = nil
            message = "位置坐标无效，请重新获取位置或检查门店档案。"
            loading = false
            return
        }
        let scopeKey = activeScopeKey
        let requestScopeGeneration = scopeGeneration
        let requestToken = token
        requestGeneration += 1
        let generation = requestGeneration
        forecast = nil
        loading = true; message = ""
        Task {
            defer {
                if isCurrentRequest(scopeKey: scopeKey, scopeGeneration: requestScopeGeneration,
                                    requestGeneration: generation) { loading = false }
            }
            do {
                let result: DineWiseWeatherForecast
                do {
                    result = try await api.weather(token: requestToken,
                        latitude: latitude, longitude: longitude)
                } catch {
                    guard isCurrentRequest(scopeKey: scopeKey,
                        scopeGeneration: requestScopeGeneration,
                        requestGeneration: generation) else { return }
                    guard case let DineWiseAPIError.failed(failureMessage) = error,
                          failureMessage == "该区域天气仍在获取中，请稍后再次查看。" else { throw error }
                    message = "天气服务仍在获取，5 秒后自动重试。"
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    guard isCurrentRequest(scopeKey: scopeKey,
                        scopeGeneration: requestScopeGeneration,
                        requestGeneration: generation) else { return }
                    result = try await api.weather(token: requestToken,
                        latitude: latitude, longitude: longitude)
                }
                guard isCurrentRequest(scopeKey: scopeKey, scopeGeneration: requestScopeGeneration,
                                       requestGeneration: generation) else { return }
                forecast = result
            } catch {
                guard isCurrentRequest(scopeKey: scopeKey, scopeGeneration: requestScopeGeneration,
                                       requestGeneration: generation) else { return }
                message = error.localizedDescription
            }
        }
    }

    private func isCurrentRequest(scopeKey: String, scopeGeneration: Int,
                                  requestGeneration: Int) -> Bool {
        activeScopeKey == scopeKey && self.scopeGeneration == scopeGeneration
            && self.requestGeneration == requestGeneration
    }
}
