import SwiftUI
import MapKit
import CoreLocation

private struct ScreenTitle: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .foregroundStyle(Brand.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ResourceView: View {
    @Environment(\.scenePhase) private var scenePhase
    let store: SessionStore
    let mapMode: Bool
    let initialKeyword: String
    let backRequest: Int
    @Binding var detailActive: Bool
    let mapActive: Bool
    @State private var navigationPath: [String] = []
    @State private var resources: [ResourceItem] = []
    @State private var nearbyActivities: [[String: Any]] = []
    @State private var nearbyActivitiesLoading = false
    @State private var nearbyActivitiesError: String?
    @State private var nearbyActivityFailedCoordinateSystems: Set<String> = []
    @State private var nearbyResourceWarning: String?
    @State private var nearbyResourceFailedCoordinateSystems: Set<String> = []
    @State private var nearbyResourceRetryError: String?
    @State private var nearbyResourceRetryLoading = false
    @State private var nearbyResourceRetrySequence = 0
    @State private var nearbyResourceRetryTask: Task<Void, Never>?
    @State private var nearbyResultsKeyword = ""
    @State private var nearbyResourceType = "ScenicSpot"
    @State private var nearbyActivitiesSequence = 0
    @State private var manualRegions: [String] = []
    @State private var manualRegionsLoading = false
    @State private var manualRegionsError: String?
    @State private var manualRegionsSequence = 0
    @State private var manualRegionsTask: Task<Void, Never>?
    @State private var manualRegionSearchTask: Task<Void, Never>?
    @State private var selectedManualRegion = ""
    @State private var keyword = ""
    @State private var revision = 0
    @State private var loading = true
    @State private var error: String?
    @State private var position: MapCameraPosition = .automatic
    @State private var loadSequence = 0
    @State private var nearbyResultsActive = false
    @State private var nearbyResourceTask: Task<Void, Never>?
    @State private var nearbyActivityTask: Task<Void, Never>?
    @StateObject private var locator = NearbyLocator()

    @State private var selectedFilter = "全部"

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if mapMode {
                        NativeResourceBrowseMapControlsSection(
                            locatorMessage: locator.message,
                            locatorBusy: locator.busy,
                            loading: loading,
                            nearbyResourceWarning: nearbyResourceWarning,
                            nearbyResourceRetryLoading: nearbyResourceRetryLoading,
                            nearbyResourceRetryError: nearbyResourceRetryError,
                            nearbyResourceTitle: nearbyResourceTitle,
                            error: error,
                            manualRegions: manualRegions,
                            manualRegionsLoading: manualRegionsLoading,
                            manualRegionsError: manualRegionsError,
                            nearbyResourceType: nearbyResourceType,
                            onOpenLocationSettings: {
                                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(settingsURL)
                                }
                            },
                            onRetryNearbyResources: retryNearbyResources,
                            onSelectFilter: { filter in
                                cancelManualRegionsLoad()
                                selectedFilter = filter
                                if filter == "全部" || filter == "景点" {
                                    if selectedManualRegion.isEmpty { revision += 1 }
                                } else {
                                    selectedManualRegion = ""
                                    expireNearbyLocation(nil)
                                }
                            },
                            onStartNearbySearch: { resourceType in
                                nearbyResourceType = resourceType
                                if resourceType == "Facility" { selectedFilter = "全部" }
                                startNearbySearch()
                            },
                            onLoadRegions: startManualRegionsLoad,
                            onExpireNearbyLocation: { expireNearbyLocation(nil, reloadMap: false) },
                            onSearchRegion: startManualRegionSearch,
                            selectedFilter: $selectedFilter,
                            selectedManualRegion: $selectedManualRegion)
                    }
                    if !mapMode { ScreenTitle(title: "发现") }
                    HStack {
                        TextField(mapMode ? "搜索景点或设施名称" : "搜索江都文旅内容", text: $keyword)
                            .font(.system(size: NativeTypography.size(14))).submitLabel(.search).onSubmit { searchResources() }
                        Button("搜索") { searchResources() }
                            .font(.system(size: NativeTypography.size(14), weight: .semibold))
                            .foregroundStyle(.white).padding(.horizontal, 15).frame(height: 34)
                            .background(Brand.primary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 10))
                    if loading || error != nil || resources.isEmpty {
                        resourceState
                    }
                    if mapMode && !loading && error == nil && resources.contains(where: { !$0.locationIsApproximate && $0.latitude != nil && $0.longitude != nil }) {
                        Map(position: $position) {
                            ForEach(resources) { item in
                                if !item.locationIsApproximate, let latitude = item.latitude, let longitude = item.longitude {
                                    Annotation(item.name, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.title).foregroundStyle(Brand.primary)
                                    }
                                }
                            }
                        }
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if mapMode && nearbyResourceType == "ScenicSpot" && locator.location != nil && selectedManualRegion.isEmpty
                        && (selectedFilter == "全部" || selectedFilter == "景点") {
                        NearbyActivitySection(
                            store: store,
                            activities: nearbyActivities,
                            isLoading: nearbyActivitiesLoading,
                            error: nearbyActivitiesError,
                            onRetry: {
                                guard let location = locator.location else { return }
                                nearbyActivityTask?.cancel()
                                nearbyActivityTask = Task { await loadNearbyActivities(location, clearResults: false) }
                            },
                            onOpen: { navigationPath.append("activity:\($0)") })
                            .padding(14)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if !resources.isEmpty && !loading && error == nil {
                        NativeResourceBrowseResultsSection(
                            store: store,
                            resources: resources,
                            mapMode: mapMode,
                            nearbyResultsActive: nearbyResultsActive,
                            nearbyResourceType: nearbyResourceType,
                            selectedManualRegion: selectedManualRegion,
                            selectedFilter: selectedFilter)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .navigationDestination(for: String.self) { id in
                if id.hasPrefix("activity:"), let activityID = id.split(separator: ":", maxSplits: 1).last.map(String.init) {
                    ActivityDetailView(store: store, id: activityID)
                } else if let item = resources.first(where: { $0.id == id }) {
                    ResourceDetailView(store: store, item: item)
                }
            }
            .background(Brand.background)
            .refreshable { await load() }
            .task(id: revision) { await load() }
            .task(id: locator.location?.timestamp) {
                guard mapMode, let location = locator.location else { return }
                let receivedAt = Date()
                let expiresAt = nativeMapLocationDisplayExpiresAt(sampleAt: location.timestamp, receivedAt: receivedAt)
                let remaining = expiresAt.timeIntervalSince(receivedAt)
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
                guard !Task.isCancelled, locator.location?.timestamp == location.timestamp else { return }
                expireNearbyLocation("附近结果已过期，请重新查找附近\(nearbyResourceTitle)。")
            }
            .task(id: locator.message ?? error) {
                guard mapMode, nearbyResourceType == "ScenicSpot", locator.message != nil || error != nil,
                      manualRegions.isEmpty, !manualRegionsLoading else { return }
                startManualRegionsLoad()
            }
            .onChange(of: initialKeyword) { _, value in keyword = value; revision += 1 }
            .onReceive(locator.$location) { location in
                guard mapMode, let location else { return }
                position = .region(MKCoordinateRegion(center: location.coordinate,
                                                       latitudinalMeters: 30_000, longitudinalMeters: 30_000))
                if selectedFilter == "全部" || selectedFilter == "景点" {
                    cancelNearbyReads()
                    nearbyResourceTask = Task { await loadNearby(location) }
                    if nearbyResourceType == "ScenicSpot" {
                        nearbyActivityTask = Task { await loadNearbyActivities(location) }
                    } else {
                        nearbyActivities = []; nearbyActivitiesLoading = false; nearbyActivitiesError = nil
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: backRequest) { _, _ in
            if !navigationPath.isEmpty { navigationPath.removeLast() }
        }
        .onChange(of: navigationPath) { _, path in
            detailActive = !path.isEmpty
            if path.isEmpty, mapMode, mapActive, scenePhase == .active, !selectedManualRegion.isEmpty {
                startManualRegionSearch(selectedManualRegion)
            }
            if mapMode, !path.isEmpty { cancelManualRegionsLoad() }
        }
        .onChange(of: mapActive) { _, active in
            guard mapMode else { return }
            if active {
                if resumeNearbySearchAfterPermissionSettings() { return }
                if navigationPath.isEmpty, !selectedManualRegion.isEmpty { startManualRegionSearch(selectedManualRegion) }
                return
            }
            cancelManualRegionsLoad()
            if locator.location != nil || locator.busy {
                expireNearbyLocation("离开地图后附近结果已清除，请重新查找附近\(nearbyResourceTitle)。")
            } else {
                cancelNearbyReads()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard mapMode else { return }
            if phase == .active {
                if resumeNearbySearchAfterPermissionSettings() { return }
                if mapActive, navigationPath.isEmpty, !selectedManualRegion.isEmpty { startManualRegionSearch(selectedManualRegion) }
                return
            }
            cancelManualRegionsLoad()
            if locator.location != nil || locator.busy {
                expireNearbyLocation("离开地图后附近结果已清除，请重新查找附近\(nearbyResourceTitle)。")
            } else {
                cancelNearbyReads()
            }
        }
        .onDisappear {
            cancelManualRegionsLoad()
            cancelNearbyReads()
        }
        .onChange(of: store.session?.accessToken) { _, _ in cancelManualRegionsLoad() }
    }

    private func expireNearbyLocation(_ message: String?, reloadMap: Bool = true) {
        locator.expire(message)
        cancelNearbyReads()
        nearbyResourceWarning = nil
        nearbyResourceRetryError = nil
        nearbyActivities = []; nearbyActivitiesError = nil; nearbyActivitiesLoading = false
        nearbyActivityFailedCoordinateSystems = []; nearbyResourceFailedCoordinateSystems = []
        resources = []; nearbyResultsActive = false
        if reloadMap { revision += 1 }
    }

    private func cancelNearbyReads() {
        loadSequence += 1
        nearbyActivitiesSequence += 1
        nearbyResourceRetrySequence += 1
        nearbyResourceTask?.cancel()
        nearbyActivityTask?.cancel()
        nearbyResourceRetryTask?.cancel()
        manualRegionSearchTask?.cancel()
        nearbyResourceTask = nil
        nearbyActivityTask = nil
        nearbyResourceRetryTask = nil
        manualRegionSearchTask = nil
        nearbyResourceWarning = nil
        nearbyResourceRetryError = nil
        nearbyResourceRetryLoading = false
        loading = false
        nearbyActivitiesLoading = false
        nearbyActivityFailedCoordinateSystems = []; nearbyResourceFailedCoordinateSystems = []
    }

    private func startManualRegionSearch(_ region: String) {
        guard mapMode, mapActive, scenePhase == .active, !region.isEmpty else { return }
        cancelNearbyReads()
        manualRegionSearchTask = Task { await loadNearby(region: region) }
    }

    private func startNearbySearch() {
        cancelManualRegionsLoad()
        selectedManualRegion = ""
        nearbyResourceWarning = nil
        nearbyResourceFailedCoordinateSystems = []
        nearbyResourceRetryError = nil
        locator.locate()
    }

    private var nearbyResourceTitle: String { nearbyResourceType == "Facility" ? "服务设施" : "景点" }

    private func resumeNearbySearchAfterPermissionSettings() -> Bool {
        guard mapMode, mapActive, scenePhase == .active, navigationPath.isEmpty,
              locator.refreshPermissionAfterSettings() else { return false }
        startNearbySearch()
        return true
    }

    private var resourceState: some View {
        VStack(spacing: 14) {
            Image(systemName: loading ? "map" : error != nil ? "wifi.exclamationmark" : "map.circle")
                .font(.system(size: 44)).foregroundStyle(Brand.primary)
                .padding(20).background(Brand.primary.opacity(0.08), in: Circle())
            if loading {
                ProgressView().tint(Brand.primary)
                Text("正在加载景点与设施…").foregroundStyle(Brand.ink)
            } else {
                Text(error != nil ? "暂时无法加载" : "暂未找到相关内容")
                    .font(.system(size: NativeTypography.size(18), weight: .semibold)).foregroundStyle(Brand.ink)
                Text(error ?? (!selectedManualRegion.isEmpty
                    ? (!keyword.isEmpty
                        ? "所选区域没有名称包含“\(keyword)”的已发布景点。"
                        : "所选区域暂无已发布景点。")
                    : (keyword.isEmpty && selectedFilter == "全部" && nearbyResourceType == "Facility"
                        ? "附近暂无已发布服务设施。"
                        : keyword.isEmpty && selectedFilter == "全部"
                        ? "已发布的景点与设施会显示在这里，稍后再来看看吧。"
                        : "试试其他分类，或清空关键词后重新搜索。")))
                    .font(.system(size: NativeTypography.size(14))).foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
                Button(!selectedManualRegion.isEmpty ? "刷新所选区域" : error != nil ? "重新加载" : "刷新内容") {
                    searchResources()
                }
                    .buttonStyle(.borderedProminent).tint(Brand.primary)
                if !keyword.isEmpty || selectedFilter != "全部" {
                    Button("查看全部") {
                        keyword = ""; selectedFilter = "全部"; selectedManualRegion = ""; revision += 1
                    }
                        .foregroundStyle(Brand.primary)
                }
            }
        }
        .padding(24).frame(maxWidth: .infinity, minHeight: 300)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func searchResources() {
        if mapMode && !selectedManualRegion.isEmpty {
            let region = selectedManualRegion
            startManualRegionSearch(region)
        } else {
            revision += 1
        }
    }

    private func loadNearby(_ location: CLLocation) async {
        loadSequence += 1
        let sequence = loadSequence
        let requestKeyword = keyword
        let resourceType = nearbyResourceType
        loading = true; error = nil; nearbyResultsActive = false
        nearbyResourceWarning = nil
        nearbyResourceRetryError = nil
        nearbyResourceRetryLoading = false
        do {
            let (items, failedSystems) = try await fetchNearbyResources(location, keyword: requestKeyword, resourceType: resourceType)
            guard sequence == loadSequence, !Task.isCancelled else { return }
            resources = items
            nearbyResultsKeyword = requestKeyword
            nearbyResultsActive = true
            nearbyResourceFailedCoordinateSystems = failedSystems
            if !failedSystems.isEmpty {
                nearbyResourceWarning = "部分坐标系查询未完成，附近\(resourceType == "Facility" ? "服务设施" : "景点")结果可能不完整。"
            }
        } catch {
            guard sequence == loadSequence, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        if sequence == loadSequence { loading = false }
    }

    private func fetchNearbyResources(_ location: CLLocation, keyword requestKeyword: String,
                                      resourceType: String? = nil, coordinateSystems: Set<String>? = nil,
                                      allowEmptyResults: Bool = false) async throws -> ([ResourceItem], Set<String>) {
        let coordinate = location.coordinate
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#")
        let encodedKeyword = requestKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let keywordQuery = encodedKeyword.isEmpty ? "" : "&keyword=\(encodedKeyword)"
        let selectedResourceType = resourceType ?? nearbyResourceType
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

    private func mergeNearbyResources(_ existing: [ResourceItem], _ incoming: [ResourceItem]) -> [ResourceItem] {
        var unique: [String: (index: Int, item: ResourceItem, distance: Double)] = [:]
        for (index, item) in (existing + incoming).enumerated() {
            let distance = item.distanceKm ?? .infinity
            if let current = unique[item.id] {
                if distance < current.distance {
                    unique[item.id] = (current.index, item, distance)
                }
            } else {
                unique[item.id] = (index, item, distance)
            }
        }
        return unique.values.sorted {
            $0.distance == $1.distance ? $0.index < $1.index : $0.distance < $1.distance
        }.prefix(20).map(\.item)
    }

    private func retryNearbyResources() {
        guard mapMode, mapActive, scenePhase == .active,
              !locator.busy, !loading, !nearbyResourceRetryLoading,
              selectedManualRegion.isEmpty, let location = locator.location else { return }
        nearbyResourceRetrySequence += 1
        let sequence = nearbyResourceRetrySequence
        let requestKeyword = keyword
        let resourceType = nearbyResourceType
        let previousItems = resources
        let failedSystems = nearbyResourceFailedCoordinateSystems
        guard !failedSystems.isEmpty else { return }
        nearbyResourceRetryLoading = true
        nearbyResourceRetryError = nil
        nearbyResourceRetryTask = Task {
            @MainActor
            func retryRequestStillCurrent() -> Bool {
                let isRequestCancelled = Task.isCancelled
                let isSequenceCurrent = sequence == nearbyResourceRetrySequence
                let isLocationCurrent = locator.location?.timestamp == location.timestamp
                let now = Date()
                let isLocationFresh = now < nativeMapLocationDisplayExpiresAt(sampleAt: location.timestamp, receivedAt: now)
                let isMapVisible = mapActive && scenePhase == .active
                let isManualRegionClear = selectedManualRegion.isEmpty
                return !isRequestCancelled && isSequenceCurrent && isLocationCurrent
                    && isLocationFresh && isMapVisible && isManualRegionClear
            }
            defer {
                if sequence == nearbyResourceRetrySequence {
                    nearbyResourceRetryLoading = false
                    nearbyResourceRetryTask = nil
                }
            }
            do {
                let (items, remainingFailedSystems) = try await fetchNearbyResources(location, keyword: requestKeyword,
                    resourceType: resourceType, coordinateSystems: failedSystems, allowEmptyResults: true)
                guard NativeNearbyCallbackGate.applyIfCurrent({ retryRequestStillCurrent() }, update: {
                    resources = !remainingFailedSystems.isEmpty && nearbyResultsKeyword == requestKeyword
                        ? mergeNearbyResources(previousItems, items) : items
                    nearbyResultsKeyword = requestKeyword
                    nearbyResultsActive = true
                    nearbyResourceFailedCoordinateSystems = remainingFailedSystems
                    nearbyResourceWarning = !remainingFailedSystems.isEmpty
                        ? "部分坐标系查询未完成，附近\(resourceType == "Facility" ? "服务设施" : "景点")结果可能不完整。" : nil
                }) else { return }
            } catch {
                _ = NativeNearbyCallbackGate.applyIfCurrent({ retryRequestStillCurrent() }, update: {
                    nearbyResourceRetryError = error.localizedDescription
                })
            }
        }
    }

    private func startManualRegionsLoad() {
        guard !manualRegionsLoading else { return }
        manualRegionsSequence += 1
        let sequence = manualRegionsSequence
        manualRegionsLoading = true; manualRegionsError = nil
        manualRegionsTask = Task {
            do {
                let value = try await MobileAPI(store: store).get("/api/JHCTITourismResource/GetPublicRegions")
                guard !Task.isCancelled, sequence == manualRegionsSequence else { return }
                let rows = value as? [String]
                    ?? ((value as? [String: Any])?["Data"] as? [String])
                    ?? ((value as? [String: Any])?["data"] as? [String])
                guard let rows else { throw MobileAPIError.unavailable("区域列表暂时无法读取") }
                manualRegions = Array(Set(rows.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty })).sorted()
                if manualRegions.isEmpty { manualRegionsError = "当前没有可手动选择的已发布景点区域。" }
            } catch {
                guard !Task.isCancelled, sequence == manualRegionsSequence else { return }
                manualRegionsError = error.localizedDescription
            }
            guard sequence == manualRegionsSequence else { return }
            manualRegionsLoading = false
            manualRegionsTask = nil
        }
    }

    private func cancelManualRegionsLoad() {
        guard manualRegionsLoading else { return }
        manualRegionsSequence += 1
        manualRegionsTask?.cancel()
        manualRegionsTask = nil
        manualRegionsLoading = false
        manualRegionsError = "区域列表读取已停止，请重试。"
    }

    private func loadNearby(region: String) async {
        loadSequence += 1
        let sequence = loadSequence
        defer {
            if sequence == loadSequence { manualRegionSearchTask = nil }
        }
        loading = true; error = nil; nearbyResultsActive = false
        nearbyActivities = []; nearbyActivitiesError = nil
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#")
        let encodedRegion = region.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let encodedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let keywordQuery = encodedKeyword.isEmpty ? "" : "&keyword=\(encodedKeyword)"
        let path = "/api/JHCTITourismResource/GetNearby?region=\(encodedRegion)&radiusKm=30&limit=20&includeDetails=false\(keywordQuery)"
        do {
            let value = try await MobileAPI(store: store).get(path)
            guard sequence == loadSequence, !Task.isCancelled else { return }
            guard let rows = value as? [[String: Any]] else {
                throw MobileAPIError.unavailable("区域景点暂时无法读取")
            }
            let items = rows.compactMap(ResourceItem.init)
            guard items.count == rows.count else {
                throw MobileAPIError.unavailable("区域景点数据暂时无法读取，请重试。")
            }
            resources = items
        } catch {
            guard sequence == loadSequence, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        if sequence == loadSequence { loading = false }
    }

    private func loadNearbyActivities(_ location: CLLocation, clearResults: Bool = true) async {
        nearbyActivitiesSequence += 1
        let sequence = nearbyActivitiesSequence
        nearbyActivitiesLoading = true; nearbyActivitiesError = nil
        if clearResults {
            nearbyActivities = []
            nearbyActivityFailedCoordinateSystems = []
        }
        let wgs = location.coordinate
        guard wgs.longitude.isFinite, (-180...180).contains(wgs.longitude),
              wgs.latitude.isFinite, (-90...90).contains(wgs.latitude) else {
            nearbyActivitiesError = "当前位置无效，请重新定位后再查找附近活动。"
            nearbyActivitiesLoading = false
            return
        }
        let gcj = MapCoordinate.gcj02(fromWgs84: wgs)
        let bd09 = MapCoordinate.bd09(fromWgs84: wgs)
        let coordinates: [(CLLocationCoordinate2D, String)] = [(wgs, "WGS84"), (gcj, "GCJ02"), (bd09, "BD09")]
        let allSystems = Set(coordinates.map { $0.1 })
        let requestedSystems = !clearResults && !nearbyActivityFailedCoordinateSystems.isEmpty
            ? nearbyActivityFailedCoordinateSystems : allSystems
        let api = MobileAPI(store: store)
        func read(_ coordinate: CLLocationCoordinate2D, system: String) async throws -> Data? {
            let path = "/api/JHCTIActivity/GetPublicPage?page=1&pageSize=5&onlyUpcoming=true&includeSessions=false&includeDetails=false&longitude=\(coordinate.longitude)&latitude=\(coordinate.latitude)&coordinateSystem=\(system)&radiusKm=30"
            do {
                let value = try await api.get(path)
                guard let page = value as? [String: Any],
                      let rows = nativeNearbyActivityRows(page, page: 1, pageSize: 5) else { return nil }
                return try JSONSerialization.data(withJSONObject: rows, options: [.fragmentsAllowed])
            }
            catch is CancellationError { throw CancellationError() }
            catch { return nil }
        }
        func readIfRequested(_ index: Int) async throws -> Data? {
            let (coordinate, system) = coordinates[index]
            guard requestedSystems.contains(system) else { return nil }
            return try await read(coordinate, system: system)
        }
        async let first = readIfRequested(0)
        async let second = readIfRequested(1)
        async let third = readIfRequested(2)
        let results: [Data?]
        do {
            results = try await [first, second, third]
        } catch is CancellationError {
            NativeNearbyCallbackGate.applyIfCurrent({ sequence == nearbyActivitiesSequence }) {
                nearbyActivitiesLoading = false
            }
            return
        } catch {
            NativeNearbyCallbackGate.applyIfCurrent({ sequence == nearbyActivitiesSequence }) {
                nearbyActivitiesError = "附近活动暂时无法加载，请稍后重试。"
                nearbyActivitiesLoading = false
            }
            return
        }
        let now = Date()
        _ = NativeNearbyCallbackGate.applyIfCurrent({
            sequence == nearbyActivitiesSequence && !Task.isCancelled
                && locator.location?.timestamp == location.timestamp
                && now < nativeMapLocationDisplayExpiresAt(sampleAt: location.timestamp, receivedAt: now)
                && mapActive && scenePhase == .active && selectedManualRegion.isEmpty
        }) {
        let failedSystems = Set(coordinates.indices.compactMap { index -> String? in
            requestedSystems.contains(coordinates[index].1) && results[index] == nil ? coordinates[index].1 : nil
        })
        nearbyActivityFailedCoordinateSystems = failedSystems
        let successful = results.enumerated().compactMap { index, data -> (Int, [[String: Any]])? in
            guard let data, let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
            return (index, rows)
        }
        guard !successful.isEmpty || !clearResults else {
            nearbyActivitiesError = "附近活动暂时无法加载，请稍后重试。"
            nearbyActivitiesLoading = false
            return
        }
        var uniqueActivities: [String: (activity: [String: Any], distance: Double, index: Int)] = [:]
        let existingActivities = clearResults ? [] : nearbyActivities
        let refreshedActivities = successful.flatMap { queryIndex, rows in
            rows.enumerated().map { index, activity in (queryIndex * 100 + index, activity) }
        }
        let candidates = existingActivities.enumerated().map { ($0.offset, $0.element) } + refreshedActivities
        for (index, activity) in candidates {
            guard let id = nativeCartID(activity["Id"] ?? activity["id"]) else { continue }
            let distance = ((activity["DistanceKm"] ?? activity["distanceKm"]) as? NSNumber)?.doubleValue ?? .infinity
            if let current = uniqueActivities[id] {
                if distance < current.distance { uniqueActivities[id] = (activity, distance, current.index) }
            } else {
                uniqueActivities[id] = (activity, distance, index)
            }
        }
        guard !successful.isEmpty else {
                nearbyActivitiesError = "附近活动暂时无法加载，请稍后重试。"
                nearbyActivitiesLoading = false
                return
        }
        nearbyActivities = uniqueActivities.values.sorted {
            $0.distance == $1.distance ? $0.index < $1.index : $0.distance < $1.distance
        }.prefix(5).map(\.activity)
        nearbyActivitiesError = failedSystems.isEmpty ? nil : "部分活动坐标查询失败，结果可能不完整。"
        nearbyActivitiesLoading = false
        }
    }

    private func load() async {
        cancelManualRegionsLoad()
        loadSequence += 1
        let sequence = loadSequence
        loading = true; error = nil; nearbyResultsActive = false
        do {
            // 开关查询失败应提示重试，不能把网络异常解释为模块关闭或空数据。
            let status = try await MobileAPI(store: store).getPublicCached(
                "/api/JHCTIFeatureAccess/GetPublicStatus?featureId=MODULE-SCENIC") as? [String: Any]
            try Task.checkCancellation()
            guard sequence == loadSequence else { return }
            guard let status else { throw MobileAPIError.unavailable("内容状态暂时无法获取，请重试") }
            guard status["IsConfigured"] as? Bool == true && status["IsEnabled"] as? Bool == true else {
                resources = []
                throw MobileAPIError.unavailable("景点模块暂未开放")
            }
            let path: String
            if mapMode {
                let query = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let filters = ["", "&resourceType=ScenicSpot", "&resourceType=Facility&facilityType=Restroom",
                               "&resourceType=Facility&facilityType=ParkingLot",
                               "&resourceType=Facility&facilityType=GasStation",
                               "&resourceType=Facility&facilityType=Other"]
                let selected = ["全部", "景点", "卫生间", "停车场", "加油站", "其他设施"].firstIndex(of: selectedFilter) ?? 0
                path = "/api/JHCTITourismResource/GetPublicMapPoints?page=1&pageSize=50&keyword=\(query)\(filters[selected])"
            } else {
                let query = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                path = "/api/JHCTITourismResource/GetPublicPage?page=1&pageSize=30&keyword=\(query)"
            }
            let result = try await MobileAPI(store: store).get(path)
            guard sequence == loadSequence, !Task.isCancelled else { return }
            let rows: [[String: Any]]
            if let array = result as? [[String: Any]] { rows = array }
            else if let page = result as? [String: Any] {
                guard let values = page["data"] as? [[String: Any]] ?? page["Data"] as? [[String: Any]] else {
                    throw MobileAPIError.unavailable("内容数据暂时无法读取，请重试")
                }
                rows = values
            } else { throw MobileAPIError.unavailable("内容数据暂时无法读取，请重试") }
            let items = rows.compactMap(ResourceItem.init)
            guard items.count == rows.count else {
                throw MobileAPIError.unavailable("内容数据暂时无法读取，请重试")
            }
            resources = items
        } catch {
            guard sequence == loadSequence, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}
