import XCTest
@testable import AIS

final class AISImageURLBuilderTests: XCTestCase {
    private let configuration = AISImageDeliveryConfiguration(
        enabled: true,
        cacheSeconds: 3600,
        domains: ["cdn.jaronsoft.com"],
        presets: AISImageDeliveryPresets(
            ios: [
                "width200": "imageMogr2/thumbnail/200x",
                "width400": "imageMogr2/thumbnail/400x",
                "list": "imageMogr2/thumbnail/600x",
                "largeList": "imageMogr2/thumbnail/900x",
                "detail": "imageMogr2/thumbnail/1200x",
                "thumbnail": "imageMogr2/thumbnail/200x"
            ]
        )
    )

    private let cloudflareConfiguration = AISImageDeliveryConfiguration(
        enabled: true,
        provider: "cloudflare",
        mode: "presetQuery",
        region: "global",
        rulesVersion: "global-1",
        cacheSeconds: 3600,
        domains: ["www.get-free.net"],
        deliveryBaseUrl: "https://cdn.get-free.net",
        presets: AISImageDeliveryPresets(
            ios: [
                "width200": "w200",
                "width400": "w400",
                "list": "w600",
                "largeList": "w900",
                "detail": "detail1200",
                "thumbnail": "w200",
                "square": "square600"
            ]
        )
    )

    func testAddsListRuleToAISCDNURL() {
        let original = URL(
            string: "https://cdn.jaronsoft.com/ais/images/example.png"
        )

        XCTAssertEqual(
            AISImageURLBuilder.url(
                from: original,
                preset: .list,
                configuration: configuration
            )?.absoluteString,
            "https://cdn.jaronsoft.com/ais/images/example.png?imageMogr2/thumbnail/600x"
        )
    }

    func testUsesAmpersandWhenQueryAlreadyExists() {
        let original = URL(
            string: "https://cdn.jaronsoft.com/ais/images/example.png?version=2"
        )

        XCTAssertEqual(
            AISImageURLBuilder.url(
                from: original,
                preset: .thumbnail,
                configuration: configuration
            )?.absoluteString,
            "https://cdn.jaronsoft.com/ais/images/example.png?version=2&imageMogr2/thumbnail/200x"
        )
    }

    func testKeepsProcessedAndThirdPartyURLsUnchanged() {
        let processed = URL(
            string: "https://cdn.jaronsoft.com/ais/images/example.png?imageMogr2/thumbnail/600x"
        )
        let thirdParty = URL(string: "https://example.com/image.png")

        XCTAssertEqual(
            AISImageURLBuilder.url(
                from: processed,
                preset: .detail,
                configuration: configuration
            ),
            processed
        )
        XCTAssertEqual(
            AISImageURLBuilder.url(
                from: thirdParty,
                preset: .detail,
                configuration: configuration
            ),
            thirdParty
        )
    }

    func testKeepsURLUnchangedWithoutDownloadedConfiguration() {
        let original = URL(
            string: "https://cdn.jaronsoft.com/ais/images/example.png"
        )

        XCTAssertEqual(
            AISImageURLBuilder.url(
                from: original,
                preset: .list,
                configuration: nil
            ),
            original
        )
        XCTAssertEqual(
            AISImageURLBuilder.resolve(
                from: original,
                preset: .detail,
                configuration: nil
            )?.resourceKind,
            .original
        )
    }

    func testOriginalPresetNeverAddsCDNProcessingRule() {
        let original = URL(
            string: "https://cdn.jaronsoft.com/ais/images/example.png"
        )

        XCTAssertEqual(
            AISImageURLBuilder.url(
                from: original,
                preset: .original,
                configuration: configuration
            ),
            original
        )
    }

    func testOriginalPresetRemovesThumbnailRuleAndKeepsOtherQueryItems() {
        let processed = URL(
            string: "https://cdn.jaronsoft.com/ais/images/example.png?version=2&imageMogr2/thumbnail/400x&signature=opaque"
        )

        XCTAssertEqual(
            AISImageURLBuilder.url(
                from: processed,
                preset: .original,
                configuration: configuration
            )?.absoluteString,
            "https://cdn.jaronsoft.com/ais/images/example.png?version=2&signature=opaque"
        )
    }

    func testAdaptiveListChoosesSmallestSufficientConfiguredWidth() {
        let original = URL(
            string: "https://cdn.jaronsoft.com/ais/images/example.png"
        )

        let compact = AISImageURLBuilder.resolve(
            from: original,
            preset: .list,
            targetPixelWidth: 360,
            configuration: configuration
        )
        let regular = AISImageURLBuilder.resolve(
            from: original,
            preset: .list,
            targetPixelWidth: 540,
            configuration: configuration
        )
        let large = AISImageURLBuilder.resolve(
            from: original,
            preset: .list,
            targetPixelWidth: 760,
            configuration: configuration
        )

        XCTAssertEqual(compact?.pixelWidth, 400)
        XCTAssertEqual(regular?.pixelWidth, 600)
        XCTAssertEqual(large?.pixelWidth, 900)
        XCTAssertEqual(compact?.resourceKind, .thumbnail)
        XCTAssertTrue(compact?.transformed == true)
    }

    func testAdaptiveListCapsSelectionAtNineHundredPixels() {
        let original = URL(
            string: "https://cdn.jaronsoft.com/ais/images/example.png"
        )

        let request = AISImageURLBuilder.resolve(
            from: original,
            preset: .list,
            targetPixelWidth: 1_500,
            maximumPixelWidth: 900,
            configuration: configuration
        )

        XCTAssertEqual(request?.pixelWidth, 900)
        XCTAssertEqual(
            request?.url.absoluteString,
            "https://cdn.jaronsoft.com/ais/images/example.png?imageMogr2/thumbnail/900x"
        )
    }

    func testAdaptiveSceneMaximumsKeepListRequestsCompact() {
        XCTAssertEqual(
            AISImageURLBuilder.maximumAdaptivePixelWidth(for: .thumbnail),
            400
        )
        XCTAssertEqual(
            AISImageURLBuilder.maximumAdaptivePixelWidth(for: .list),
            600
        )
        XCTAssertEqual(
            AISImageURLBuilder.maximumAdaptivePixelWidth(for: .largeList),
            900
        )

        let original = URL(
            string: "https://cdn.jaronsoft.com/ais/images/example.png"
        )
        let request = AISImageURLBuilder.resolve(
            from: original,
            preset: .list,
            targetPixelWidth: 900,
            maximumPixelWidth: AISImageURLBuilder
                .maximumAdaptivePixelWidth(for: .list),
            configuration: configuration
        )

        XCTAssertEqual(request?.pixelWidth, 600)
        XCTAssertEqual(
            request?.url.absoluteString,
            "https://cdn.jaronsoft.com/ais/images/example.png?imageMogr2/thumbnail/600x"
        )
    }

    func testExistingProcessedURLKeepsItsActualPixelWidth() {
        let processed = URL(
            string: "https://cdn.jaronsoft.com/ais/images/example.png?imageMogr2/thumbnail/400x"
        )

        let request = AISImageURLBuilder.resolve(
            from: processed,
            preset: .list,
            targetPixelWidth: 800,
            configuration: configuration
        )

        XCTAssertEqual(request?.url, processed)
        XCTAssertEqual(request?.pixelWidth, 400)
        XCTAssertEqual(request?.resourceKind, .thumbnail)
    }

    func testCloudflarePresetRewritesOnlyDeliveryOrigin() {
        let original = URL(
            string: "https://www.get-free.net/ais/images/example.png?v=2"
        )

        XCTAssertEqual(
            AISImageURLBuilder.url(
                from: original,
                preset: .list,
                configuration: cloudflareConfiguration
            )?.absoluteString,
            "https://cdn.get-free.net/ais/images/example.png?v=2&preset=w600"
        )
    }

    func testCloudflarePresetKeepsSignedOrUnknownQueryURLUnchanged() {
        let original = URL(
            string: "https://www.get-free.net/ais/images/example.png?signature=opaque"
        )

        XCTAssertEqual(
            AISImageURLBuilder.url(
                from: original,
                preset: .detail,
                configuration: cloudflareConfiguration
            ),
            original
        )
    }

    func testCloudflareAdaptivePresetUsesControlledWidth() {
        let original = URL(
            string: "https://www.get-free.net/ais/images/example.png"
        )
        let request = AISImageURLBuilder.resolve(
            from: original,
            preset: .list,
            targetPixelWidth: 720,
            configuration: cloudflareConfiguration
        )

        XCTAssertEqual(request?.pixelWidth, 900)
        XCTAssertEqual(
            request?.url.absoluteString,
            "https://cdn.get-free.net/ais/images/example.png?preset=w900"
        )
    }

    func testOriginalPresetRemovesCloudflarePresetParameter() {
        let processed = URL(
            string: "https://cdn.get-free.net/ais/images/example.png?version=2&preset=w400"
        )

        XCTAssertEqual(
            AISImageURLBuilder.url(
                from: processed,
                preset: .original,
                configuration: cloudflareConfiguration
            )?.absoluteString,
            "https://www.get-free.net/ais/images/example.png?version=2"
        )
    }

    func testLegacyConfigurationDecodesAsTencentQueryMode() throws {
        let data = Data(
            """
            {
              "enabled": true,
              "cacheSeconds": 3600,
              "domains": ["cdn.jaronsoft.com"],
              "presets": { "ios": { "list": "imageMogr2/thumbnail/600x" } }
            }
            """.utf8
        )
        let decoded = try JSONDecoder().decode(
            AISImageDeliveryConfiguration.self,
            from: data
        )

        XCTAssertEqual(decoded.provider, "tencent")
        XCTAssertEqual(decoded.mode, "query")
        XCTAssertEqual(decoded.rulesVersion, "1")
    }
}
