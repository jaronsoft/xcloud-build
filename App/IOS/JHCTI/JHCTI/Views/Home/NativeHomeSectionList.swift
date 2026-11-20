import SwiftUI

struct NativeHomeSectionList: View {
    let store: SessionStore
    let showsShortcuts: Bool
    let shortcutOrder: Int?
    let shortcutContent: AnyView
    let operationComponents: [[String: Any]]
    let configuredOrder: [String]
    let catalogs: [CatalogModule]
    let featuredTitle: String
    let featuredRows: [[String: Any]]
    let featuredSortOrder: Int
    let moduleRows: [String: [[String: Any]]]
    let moduleErrors: [String: String]
    let serviceStatusClock: Date
    let onBrowse: () -> Void
    let onOpenRecommendation: ([String: Any]) -> Void
    let onRetry: () -> Void

    private var orderedSections: [HomeSectionView] {
        var sections: [HomeSectionView] = []
        var sourceOrder = 0
        if showsShortcuts {
            sections.append(HomeSectionView(id: "shortcuts", sortOrder: (shortcutOrder ?? 0) + 1,
                sourceOrder: sourceOrder, content: shortcutContent))
            sourceOrder += 1
        }

        for (index, item) in operationComponents.enumerated() {
            let sortOrder = item["SortOrder"] as? Int ?? item["sortOrder"] as? Int ?? 0
            sections.append(HomeSectionView(id: "operation-\(index)", sortOrder: sortOrder + 1,
                sourceOrder: sourceOrder, content: AnyView(NativeHomeOperationComponent(
                    store: store, item: item, serviceStatusClock: serviceStatusClock,
                    onOpen: { onOpenRecommendation(item) }))))
            sourceOrder += 1
        }

        let moduleSourceOrder: (String) -> Int = { key in
            switch key {
            case "featured": return 0
            case "articles": return 1
            case "activities": return 2
            default: return 3 + (configuredOrder.firstIndex(of: key) ?? configuredOrder.count)
            }
        }
        for key in configuredOrder.sorted(by: { moduleSourceOrder($0) < moduleSourceOrder($1) }) {
            if key == "featured" {
                sections.append(HomeSectionView(id: "module-featured", sortOrder: featuredSortOrder + 1,
                    sourceOrder: sourceOrder, content: AnyView(NativeHomeFeaturedSection(store: store,
                        title: featuredTitle, rows: featuredRows, onBrowse: onBrowse, onOpen: onOpenRecommendation))))
            } else if let module = catalogs.first(where: { $0.id == key }) {
                sections.append(HomeSectionView(id: "module-\(key)", sortOrder: module.sortOrder + 1,
                    sourceOrder: sourceOrder, content: AnyView(NativeHomeCatalogSection(store: store, module: module,
                        rows: moduleRows[module.id], error: moduleErrors[module.id], onRetry: onRetry))))
            }
            sourceOrder += 1
        }

        return sections.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.sourceOrder < $1.sourceOrder
        }
    }

    var body: some View {
        ForEach(orderedSections) { section in section.content }
    }
}
