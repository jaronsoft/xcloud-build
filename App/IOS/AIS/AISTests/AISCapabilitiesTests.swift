import XCTest
@testable import AIS

final class AISCapabilitiesTests: XCTestCase {
    func testIOSCapabilitiesDecodeAndRegionGate() throws {
        let json = """
        {
          "enabled": true,
          "minimumVersion": "1.0",
          "allowedRegions": ["US", "GB"],
          "loginMethods": ["apple"],
          "storeKitEnabled": true,
          "videoEnabled": false,
          "publicContentEnabled": true,
          "pushNotificationsEnabled": false,
          "rulesVersion": "20260725.1"
        }
        """
        let value = try JSONDecoder().decode(
            AISIOSCapabilities.self,
            from: Data(json.utf8)
        )

        XCTAssertTrue(value.allows(region: "us"))
        XCTAssertFalse(value.allows(region: "CN"))
        XCTAssertTrue(value.storeKitEnabled)
        XCTAssertFalse(value.videoEnabled)
    }

    func testRechargePackageKeepsStableStoreKitMetadata() throws {
        let json = """
        {
          "PackageKey": "points_1000",
          "AppleProductId": "com.wekarepartners.studio.points.us.starter.v1",
          "IosEnabled": true,
          "Regions": ["US"],
          "Sort": 10,
          "RuleVersion": "1",
          "Amount": 9.99,
          "Points": 1000
        }
        """
        let value = try JSONDecoder().decode(
            AISRechargePackage.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(value.packageKey, "points_1000")
        XCTAssertEqual(value.points, 1000)
        XCTAssertEqual(value.regions, ["US"])
        XCTAssertEqual(
            value.appleProductId,
            "com.wekarepartners.studio.points.us.starter.v1"
        )
    }

    func testStoreKitPricingDecodesRegionSpecificPackages() throws {
        let json = """
        {
          "CountryCode": "US",
          "PresetPackages": [
            {
              "PackageKey": "us_starter",
              "AppleProductId": "com.wekarepartners.studio.points.us.starter.v1",
              "IosEnabled": true,
              "Regions": ["US"],
              "Sort": 10,
              "RuleVersion": "1",
              "Amount": 4.99,
              "Points": 1000
            }
          ]
        }
        """
        let value = try JSONDecoder().decode(
            AISStoreKitPricingResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(value.countryCode, "US")
        XCTAssertEqual(value.presetPackages.map(\.packageKey), ["us_starter"])
        XCTAssertEqual(value.presetPackages.first?.regions, ["US"])
    }

    func testStoreKitPricingAcceptsCamelCaseEnvelope() throws {
        let json = """
        {
          "countryCode": "US",
          "presetPackages": []
        }
        """
        let value = try JSONDecoder().decode(
            AISStoreKitPricingResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(value.countryCode, "US")
        XCTAssertTrue(value.presetPackages.isEmpty)
    }

    func testStoreKitVerificationAcceptsBothResponseKeyStyles() throws {
        let responses = [
            #"{"Success":true,"Response":{"Credited":true}}"#,
            #"{"success":true,"response":{"credited":true}}"#
        ]
        for json in responses {
            let envelope = try JSONDecoder().decode(
                APIEnvelope<AISStoreKitVerificationResponse>.self,
                from: Data(json.utf8)
            )
            XCTAssertEqual(envelope.response?.credited, true)
        }
    }

    @MainActor
    func testStoreKitRequestRegionPrefersStorefront() {
        XCTAssertEqual(
            StoreKitPurchaseViewModel.requestedRegion(
                storefrontCountryCode: " ca ",
                fallbackRegion: "US"
            ),
            "CA"
        )
        XCTAssertEqual(
            StoreKitPurchaseViewModel.requestedRegion(
                storefrontCountryCode: nil,
                fallbackRegion: "cn"
            ),
            "CN"
        )
        XCTAssertEqual(
            StoreKitPurchaseViewModel.requestedRegion(
                storefrontCountryCode: nil,
                fallbackRegion: nil
            ),
            "US"
        )
    }

    @MainActor
    func testStoreKitPackageFilteringUsesSelectedRegion() {
        let capabilities = AISIOSCapabilities(
            enabled: true,
            minimumVersion: "1.0",
            allowedRegions: ["CN", "US"],
            loginMethods: ["apple"],
            storeKitEnabled: true,
            videoEnabled: true,
            publicContentEnabled: true,
            pushNotificationsEnabled: true,
            rulesVersion: "1"
        )
        let packages = [
            AISRechargePackage(
                packageKey: "cn_starter",
                appleProductId: "com.wekarepartners.studio.points.cn.starter.v1",
                iosEnabled: true,
                regions: ["CN"],
                sort: 10,
                ruleVersion: "1",
                amount: 12,
                points: 1_000
            ),
            AISRechargePackage(
                packageKey: "us_starter",
                appleProductId: "com.wekarepartners.studio.points.us.starter.v1",
                iosEnabled: true,
                regions: ["US"],
                sort: 10,
                ruleVersion: "1",
                amount: 4.99,
                points: 1_000
            )
        ]

        let result = StoreKitPurchaseViewModel.eligiblePackages(
            packages,
            region: "CN",
            capabilities: capabilities
        )

        XCTAssertEqual(result.map(\.packageKey), ["cn_starter"])
    }

    @MainActor
    func testStoreKitPackageWithoutExplicitRegionsUsesPricingRegion() {
        let capabilities = AISIOSCapabilities(
            enabled: true,
            minimumVersion: "1.0",
            allowedRegions: ["US"],
            loginMethods: ["apple"],
            storeKitEnabled: true,
            videoEnabled: true,
            publicContentEnabled: true,
            pushNotificationsEnabled: true,
            rulesVersion: "1"
        )
        let package = AISRechargePackage(
            packageKey: "us_starter",
            appleProductId: "com.wekarepartners.studio.points.us.starter.v1",
            iosEnabled: true,
            regions: [],
            sort: 10,
            ruleVersion: "1",
            amount: 4.99,
            points: 1_000
        )

        let result = StoreKitPurchaseViewModel.eligiblePackages(
            [package],
            region: "US",
            capabilities: capabilities
        )

        XCTAssertEqual(result.map(\.packageKey), ["us_starter"])
    }
}
