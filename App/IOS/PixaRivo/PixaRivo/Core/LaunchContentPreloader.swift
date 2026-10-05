import Foundation

/// 在首次进入产品时静默预热公开内容，让模板和案例页优先命中本地快照。
actor PixaLaunchContentPreloader {
    static let shared = PixaLaunchContentPreloader()

    private var inFlightKeys: Set<String> = []

    func preload() async {
        let key = [
            AppLanguage.apiValue,
            PixaMediaRegion.templateRegionValue,
            PixaMediaRegion.headerValue
        ].joined(separator: "|")
        guard inFlightKeys.insert(key).inserted else { return }
        defer { inFlightKeys.remove(key) }

        async let templates: Void = preloadTemplates()
        async let templateFilters: Void = preloadTemplateFilters()
        async let galleryCategories: Void = preloadGalleryCategories()
        async let gallery: Void = preloadGallery()
        _ = await (templates, templateFilters, galleryCategories, gallery)
    }

    private func preloadTemplates() async {
        let query = [
            URLQueryItem(name: "templateType", value: "image"),
            URLQueryItem(name: "region", value: PixaMediaRegion.templateRegionValue),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "size", value: "24"),
            URLQueryItem(name: "sort", value: "recommended"),
            URLQueryItem(name: "placement", value: "creation")
        ]
        let api = APIClient()
        let _: PageResponse<StyleTemplate>? = try? await api.getCached(
            "/api/ais/style-templates",
            query: query
        )
    }

    private func preloadTemplateFilters() async {
        let api = APIClient()
        let _: [StyleTemplateFilterGroup]? = try? await api.getCached(
            "/api/ais/style-templates/categories",
            query: [
                URLQueryItem(name: "templateType", value: "image"),
                URLQueryItem(name: "region", value: PixaMediaRegion.templateRegionValue)
            ]
        )
    }

    private func preloadGalleryCategories() async {
        let api = APIClient()
        let _: GalleryCategoryResponse? = try? await api.getCached(
            "/api/ais/gallery-categories"
        )
    }

    private func preloadGallery() async {
        let api = APIClient()
        let languages = AppLanguage.isChinese ? [AppLanguage.apiValue] : [AppLanguage.apiValue, "zh"]
        await withTaskGroup(of: Void.self) { group in
            for language in languages {
                group.addTask {
                    let _: PageResponse<GalleryJob>? = try? await api.getCached(
                        "/api/ais/jobs/gallery",
                        query: [
                            URLQueryItem(name: "page", value: "1"),
                            URLQueryItem(name: "size", value: "40"),
                            URLQueryItem(name: "language", value: language),
                            URLQueryItem(name: "jobType", value: "style_template_generate")
                        ]
                    )
                }
            }
        }
    }
}
