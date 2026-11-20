import SwiftUI

@MainActor
extension HomeView {
    func load(forceRefresh: Bool = false, allowStale: Bool = false) async {
        let hasVisibleContent = !components.isEmpty
        loading = !hasVisibleContent
        error = nil
        if !allowStale { nextComponentChangeDelayMs = nil }
        var nextChangeDeadline: Date?
        do {
            let api = MobileAPI(store: store)
            let value = try await api.getPublicCached("/api/JHCTIHomePage/GetPublicHome", forceRefresh: forceRefresh,
                                                      allowStale: allowStale) as? [String: Any]
            if !allowStale, let delay = (value?["NextComponentChangeAfterMilliseconds"] as? NSNumber
                ?? value?["nextComponentChangeAfterMilliseconds"] as? NSNumber)?.int64Value,
               delay > 0 { nextChangeDeadline = Date().addingTimeInterval(Double(delay) / 1000) }
            let componentRows = value?["Components"] as? [[String: Any]] ?? value?["components"] as? [[String: Any]] ?? []
            components = componentRows.map { canonicalHomeComponent($0) as? [String: Any] ?? $0 }
            let configuredQuickEntries = components.filter {
                ($0["ComponentType"] as? String ?? $0["componentType"] as? String ?? "").lowercased() == "quickentry"
                    && ($0["IsEnabled"] as? Bool ?? $0["isEnabled"] as? Bool ?? true)
            }.sorted {
                ($0["SortOrder"] as? Int ?? $0["sortOrder"] as? Int ?? 0)
                    < ($1["SortOrder"] as? Int ?? $1["sortOrder"] as? Int ?? 0)
            }
            let validQuickEntries = configuredQuickEntries.filter(isValidHomeQuickEntryTarget)
            let hasConfiguredQuickEntries = components.contains {
                ($0["ComponentType"] as? String ?? $0["componentType"] as? String ?? "").lowercased() == "quickentry"
            }
            quickEntriesConfigured = hasConfiguredQuickEntries
            var availableQuickEntries: [[String: Any]] = []
            for entry in validQuickEntries {
                if availableQuickEntries.count >= 8 { break }
                let targetType = (entry["TargetType"] as? String ?? entry["targetType"] as? String ?? "").lowercased()
                let pageKey = (entry["InternalPageKey"] as? String ?? entry["internalPageKey"] as? String ?? "").lowercased()
                let title = entry["Title"] as? String ?? entry["title"] as? String ?? ""
                let targetPath = entry["TargetPath"] as? String ?? entry["targetPath"] as? String ?? ""
                let featureID = homeModuleIdForTarget(targetType, pageKey, title, targetPath)
                let featureOpen: Bool
                if featureID.isEmpty { featureOpen = true }
                else {
                    featureOpen = await api.featureEnabled(featureID,
                        allowStale: allowStale, forceRefresh: forceRefresh)
                }
                guard !Task.isCancelled else { loading = false; return }
                if featureOpen {
                    availableQuickEntries.append(entry)
                    quickEntryItems = availableQuickEntries
                }
            }
            let fallbackShortcutFeatures = [
                "F-TKT-002", "MODULE-SCENIC", "MODULE-DINING", "MODULE-HOTEL",
                "MODULE-ACTIVITY", "MODULE-GUIDE", "MODULE-GUIDE", "MODULE-TRAVEL-ROUTE"
            ]
            var visibleFallbackShortcuts: [Int] = []
            if !hasConfiguredQuickEntries {
                for (index, featureID) in fallbackShortcutFeatures.enumerated() {
                    let featureOpen = await api.featureEnabled(featureID, allowStale: allowStale, forceRefresh: forceRefresh)
                    guard !Task.isCancelled else { loading = false; return }
                    if featureOpen {
                        visibleFallbackShortcuts.append(index)
                    }
                }
            }
            fallbackShortcutIndices = visibleFallbackShortcuts
            var visibleOperations: [[String: Any]] = []
            for item in components {
                let componentType = (item["ComponentType"] as? String ?? item["componentType"] as? String ?? "").lowercased()
                guard ["servicestatus", "noticebar", "promobanner"].contains(componentType),
                      item["IsEnabled"] as? Bool ?? item["isEnabled"] as? Bool ?? true else { continue }
                let targetType = (item["TargetType"] as? String ?? item["targetType"] as? String ?? "").lowercased()
                let pageKey = (item["InternalPageKey"] as? String ?? item["internalPageKey"] as? String ?? "").lowercased()
                let title = item["Title"] as? String ?? item["title"] as? String ?? ""
                let targetPath = item["TargetPath"] as? String ?? item["targetPath"] as? String ?? ""
                let featureID = homeModuleIdForTarget(targetType, pageKey, title, targetPath)
                let targetOpen = featureID.isEmpty ? true : await api.featureEnabled(featureID,
                    allowStale: allowStale, forceRefresh: forceRefresh)
                guard !Task.isCancelled else { loading = false; return }
                if targetOpen { visibleOperations.append(item) }
            }
            operationComponents = visibleOperations.enumerated().sorted { left, right in
                let leftOrder = left.element["SortOrder"] as? Int ?? left.element["sortOrder"] as? Int ?? 0
                let rightOrder = right.element["SortOrder"] as? Int ?? right.element["sortOrder"] as? Int ?? 0
                return leftOrder == rightOrder ? left.offset < right.offset : leftOrder < rightOrder
            }.map(\.element)
            quickEntriesConfigured = hasConfiguredQuickEntries
            loading = false
            let rawModules = value?["AppModules"] as? [[String: Any]] ?? value?["appModules"] as? [[String: Any]] ?? [
                ["Key": "featured", "Title": "精选推荐", "IsEnabled": true, "SortOrder": 0],
                ["Key": "activities", "Title": "最新活动", "IsEnabled": true, "SortOrder": 1]
            ]
            let moduleKeyCounts = Dictionary(grouping: rawModules.compactMap { row in
                (row["Key"] as? String ?? row["key"] as? String)?.lowercased()
            }, by: { $0 }).mapValues(\.count)
            let uniqueModules = rawModules.filter { row in
                guard let key = row["Key"] as? String ?? row["key"] as? String else { return false }
                return moduleKeyCounts[key.lowercased()] == 1
            }
            let candidates = uniqueModules.compactMap(CatalogModule.init).sorted { $0.sortOrder < $1.sortOrder }
            var enabled: [CatalogModule] = []
            var published: [String: [[String: Any]]] = [:]
            var catalogErrors: [String: String] = [:]
            for module in candidates {
                let featureEnabled = module.featureID.isEmpty ? true : await api.featureEnabled(module.featureID,
                    allowStale: allowStale, forceRefresh: forceRefresh)
                guard !Task.isCancelled else { loading = false; return }
                guard featureEnabled else { continue }
                enabled.append(module)
                let pageSize = min(4, module.displayCount)
                do {
                    guard let page = try await api.getPublicCached(module.listPath(pageSize: pageSize),
                        forceRefresh: forceRefresh, allowStale: allowStale) as? [String: Any] else {
                        if module.id == "articles" { catalogErrors[module.id] = "首页文旅资讯分页回执异常，请刷新后重试。" }
                        continue
                    }
                    if module.id == "articles" {
                        guard let parsed = nativePublicCatalogPage(page, page: 1, pageSize: pageSize) else {
                            catalogErrors[module.id] = "首页文旅资讯分页回执异常，请刷新后重试。"
                            continue
                        }
                        guard nativePublicArticleRows(parsed.rows) else {
                            catalogErrors[module.id] = "首页文旅资讯编号无效或重复，请重试。"
                            continue
                        }
                        published[module.id] = parsed.rows
                    } else {
                        published[module.id] = page["data"] as? [[String: Any]] ?? page["Data"] as? [[String: Any]] ?? page["Items"] as? [[String: Any]] ?? []
                    }
                } catch is CancellationError {
                    loading = false
                    return
                } catch {
                    if module.id == "articles" { catalogErrors[module.id] = "首页文旅资讯暂时无法加载，请重试。" }
                }
            }
            catalogs = enabled
            moduleRows = published
            moduleErrors = catalogErrors
            let featuredModule = uniqueModules.first {
                ($0["Key"] as? String ?? $0["key"] as? String) == "featured"
                    && ($0["IsEnabled"] as? Bool ?? $0["isEnabled"] as? Bool ?? false)
            }
            featuredSortOrder = featuredModule?["SortOrder"] as? Int ?? featuredModule?["sortOrder"] as? Int ?? 0
            configuredOrder = uniqueModules.enumerated().filter {
                $0.element["IsEnabled"] as? Bool ?? $0.element["isEnabled"] as? Bool ?? false
            }
                .sorted { left, right in
                    let leftOrder = left.element["SortOrder"] as? Int ?? left.element["sortOrder"] as? Int ?? 0
                    let rightOrder = right.element["SortOrder"] as? Int ?? right.element["sortOrder"] as? Int ?? 0
                    return leftOrder == rightOrder ? left.offset < right.offset : leftOrder < rightOrder
                }
                .compactMap { $0.element["Key"] as? String ?? $0.element["key"] as? String }
                .filter { key in key == "featured" || enabled.contains(where: { $0.id == key }) }
            featuredTitle = (featuredModule?["Title"] as? String ?? featuredModule?["title"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 } ?? "精选推荐"
            let scenicEnabled = await api.featureEnabled("MODULE-SCENIC", allowStale: allowStale, forceRefresh: forceRefresh)
            guard !Task.isCancelled else { loading = false; return }
            let excludedRecommendationTypes = Set(["banner", "quickentry", "servicestatus", "noticebar", "promobanner"])
            let configuredRecommendations = components.filter { item in
                let type = (item["ComponentType"] as? String ?? item["componentType"] as? String ?? "").lowercased()
                let enabled = item["IsEnabled"] as? Bool ?? item["isEnabled"] as? Bool ?? true
                return !type.isEmpty && !excludedRecommendationTypes.contains(type) && enabled
            }
            var visibleRecommendations: [[String: Any]] = []
            for item in configuredRecommendations {
                guard let typeValue = homeRecommendationTargetType(item) else { continue }
                let type = typeValue.lowercased()
                guard ["internalpage", "scenicspot", "ticket", "article", "activity", "product", "hotel", "travelroute", "diningstore"].contains(type) else { continue }
                if type == "internalpage" {
                    guard homeRecommendationInternalPageKey(item) != nil else { continue }
                } else {
                    guard isValidHomeRecommendationTargetID(homeRecommendationTargetID(item)) else { continue }
                }
                let pageKey = (item["InternalPageKey"] as? String ?? item["internalPageKey"] as? String ?? "").lowercased()
                let title = item["Title"] as? String ?? item["title"] as? String ?? ""
                let targetPath = item["TargetPath"] as? String ?? item["targetPath"] as? String ?? ""
                let featureID = homeModuleIdForTarget(type, pageKey, title, targetPath)
                let targetModuleOpen = featureID.isEmpty ? true : await api.featureEnabled(
                    featureID, allowStale: allowStale, forceRefresh: forceRefresh)
                guard !Task.isCancelled else { loading = false; return }
                if targetModuleOpen {
                    visibleRecommendations.append(item)
                }
            }
            if !visibleRecommendations.isEmpty {
                featured = visibleRecommendations
            } else if featuredModule != nil && scenicEnabled {
                let response: [String: Any]?
                do {
                    response = try await api.getPublicCached("/api/JHCTITourismResource/GetPublicPage?page=1&pageSize=8",
                        forceRefresh: forceRefresh, allowStale: allowStale) as? [String: Any]
                } catch is CancellationError {
                    loading = false
                    return
                } catch {
                    response = nil
                }
                featured = response?["data"] as? [[String: Any]] ?? response?["Data"] as? [[String: Any]] ?? []
            } else { featured = [] }
        } catch is CancellationError {
            loading = false
            return
        } catch {
            if !hasVisibleContent { self.error = error.localizedDescription }
        }
        guard !Task.isCancelled else { loading = false; return }
        if !allowStale {
            nextComponentChangeDelayMs = nextChangeDeadline.map {
                max(1, Int64(($0.timeIntervalSinceNow * 1000).rounded(.up)))
            }
        }
        loading = false
        if !initialLoadCompleted {
            initialLoadCompleted = true
            onInitialLoadComplete()
        }
    }
}
