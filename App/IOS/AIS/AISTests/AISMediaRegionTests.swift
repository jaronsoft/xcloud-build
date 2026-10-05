import XCTest
@testable import AIS

final class AISMediaRegionTests: XCTestCase {
    func testContentLanguageDrivesTemplateCatalogAndAPIValue() {
        XCTAssertEqual(
            StyleTemplateMarketRegion.resolve(languageIdentifier: "zh-Hans"),
            .china
        )
        XCTAssertEqual(
            AISLocalization.apiValue(languageIdentifier: "zh-Hans"),
            "zh-CN"
        )
        XCTAssertEqual(
            StyleTemplateMarketRegion.resolve(languageIdentifier: "en-US"),
            .global
        )
        XCTAssertEqual(
            AISLocalization.apiValue(languageIdentifier: "en-US"),
            "en-US"
        )
    }

    func testStoreKitCountryCodeMatchesEffectiveRegion() {
        XCTAssertEqual(AISMediaRegion.china.storeKitCountryCode, "CN")
        XCTAssertEqual(AISMediaRegion.international.storeKitCountryCode, "US")
    }

    func testResolverUsesStorefrontBeforeAccountAndLocale() {
        XCTAssertEqual(
            AISMediaRegionResolver.resolve(
                storefrontCountryCode: "US",
                accountCountryCode: "CN",
                localeCountryCode: "CN"
            ),
            .international
        )
        XCTAssertEqual(
            AISMediaRegionResolver.resolve(
                storefrontCountryCode: "chn",
                accountCountryCode: "US",
                localeCountryCode: "US"
            ),
            .china
        )
    }

    func testResolverFallsBackToAccountThenLocale() {
        XCTAssertEqual(
            AISMediaRegionResolver.resolve(
                storefrontCountryCode: nil,
                accountCountryCode: "CN",
                localeCountryCode: "US"
            ),
            .china
        )
        XCTAssertEqual(
            AISMediaRegionResolver.resolve(
                storefrontCountryCode: nil,
                accountCountryCode: nil,
                localeCountryCode: "GB"
            ),
            .international
        )
    }

    func testResponseCacheKeySeparatesMediaRegions() {
        AISMediaRegionRequestContext.install(.china)
        let chinaKey = AISResponseCache.key(
            scope: "public",
            resource: "gallery"
        )
        AISMediaRegionRequestContext.install(.international)
        let internationalKey = AISResponseCache.key(
            scope: "public",
            resource: "gallery"
        )

        XCTAssertNotEqual(chinaKey, internationalKey)
        XCTAssertTrue(chinaKey.contains("mediaRegion=cn"))
        XCTAssertTrue(internationalKey.contains("mediaRegion=global"))
    }

    func testImageProxyRequestCarriesSelectedMediaRegion() {
        AISMediaRegionRequestContext.install(.china)
        let url = AppEnvironment.current.apiBaseURL.appending(
            path: "/api/ais/storage/assets/123/content"
        )
        let request = AISImageRequestBuilder.request(for: url)

        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Client-Platform"),
            "ios"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-AIS-Media-Region"),
            "cn"
        )
    }

    func testThirdPartyImageRequestDoesNotExposeMediaRegionHeaders() {
        AISMediaRegionRequestContext.install(.china)
        let request = AISImageRequestBuilder.request(
            for: URL(string: "https://example.com/image.png")!
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "X-Client-Platform"))
        XCTAssertNil(
            request.value(forHTTPHeaderField: "X-AIS-Media-Region")
        )
    }
}
