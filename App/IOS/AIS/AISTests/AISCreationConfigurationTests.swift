import XCTest
@testable import AIS

@MainActor
final class AISCreationConfigurationTests: XCTestCase {
    func testPromptConfigurationDecodesDynamicSpecsAndSelectionLimits() throws {
        let json = """
        {
          "MediaType": "image",
          "Groups": [{
            "Id": "lighting",
            "MediaType": "image",
            "NameZh": "光线",
            "NameEn": "Lighting",
            "Type": "multi",
            "MaxSelected": 2,
            "Sort": 10,
            "Items": [{
              "Id": "soft",
              "NameZh": "柔光",
              "NameEn": "Soft Light",
              "Sort": 1,
              "Multiplier": 1.1,
              "IsAvailable": true
            }]
          }],
          "ModelOutputSpecs": [{
            "Provider": "ais",
            "MediaType": "image",
            "SpecType": "resolution",
            "Value": "1536",
            "NameZh": "1536px 最大",
            "NameEn": "Up to 1536px",
            "Sort": 1,
            "Multiplier": 1,
            "IsAvailable": true
          }]
        }
        """

        let settings = try JSONDecoder().decode(
            AISPromptAttributeSettings.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(settings.groups.first?.maxSelected, 2)
        XCTAssertEqual(settings.groups.first?.items.first?.id, "soft")
        XCTAssertEqual(settings.modelOutputSpecs.first?.value, "1536")
    }

    func testOrientationFallbackUsesAspectRatio() {
        let store = AISCreationConfigurationStore()

        XCTAssertEqual(store.orientationForAspect("1:1"), "square")
        XCTAssertEqual(store.orientationForAspect("16:9"), "landscape")
        XCTAssertEqual(store.orientationForAspect("3:4"), "portrait")
    }

    func testEffectSelectionLimitUsesBackendGroupAndFallback() throws {
        let json = """
        {
          "MediaType": "image",
          "Groups": [{
            "Id": "effect",
            "MediaType": "image",
            "NameZh": "视觉效果",
            "NameEn": "Effect",
            "Type": "multiple",
            "MaxSelected": 3,
            "Sort": 1,
            "Items": []
          }],
          "ModelOutputSpecs": []
        }
        """
        let settings = try JSONDecoder().decode(
            AISPromptAttributeSettings.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(
            AISCreationConfigurationStore.resolveEffectSelectionLimit(
                in: settings.groups
            ),
            3
        )
        XCTAssertEqual(
            AISCreationConfigurationStore.resolveEffectSelectionLimit(in: []),
            3
        )
    }

    func testGenerationModelKeepsLockedAndRecommendedState() throws {
        let json = """
        [{
          "DisplayModelKey": "ais-premium",
          "NameZh": "高级模型",
          "NameEn": "Premium Model",
          "RequiredMembershipCode": "pro",
          "IsRecommended": true,
          "CanSelect": true,
          "CanUse": false,
          "ModelMarkupRate": 1.3
        }]
        """

        let models = try JSONDecoder().decode(
            [AISGenerationModelOption].self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(models.first?.requiredMembershipCode, "pro")
        XCTAssertEqual(models.first?.isRecommended, true)
        XCTAssertEqual(models.first?.canUse, false)
    }

    func testTemplateValidationCoversRequiredSlotsAndTextLength() throws {
        let template = try decodeTemplate()

        XCTAssertEqual(
            template.validationIssues(
                filledSlotKeys: [],
                textValues: ["headline": "123456"]
            ),
            [
                .requiredSlot("product"),
                .textTooLong("headline", maximum: 5)
            ]
        )
        XCTAssertTrue(
            template.validationIssues(
                filledSlotKeys: ["product"],
                textValues: ["headline": "AIS"]
            ).isEmpty
        )
    }

    func testTemplatePayloadContainsSlotMappingAndSelectedModel() throws {
        let request = StyleTemplateApplyRequest(
            sourceAssetId: "1001",
            referenceAssetIds: ["1001", "1002"],
            textValues: ["headline": "AIS"],
            entry: "ios_native",
            language: "zh",
            aspectRatio: "4:5",
            resolution: "1536",
            additionalRequirement: "保留产品结构",
            recommendToGallery: true,
            promoMarkEnabled: true,
            selectedDisplayModelKey: "g2",
            clientSnapshot: StyleTemplateClientSnapshot(
                templateKey: "poster",
                templateName: "海报",
                imageSlots: [
                    StyleTemplateSlotSnapshot(
                        slotKey: "product",
                        slotIndex: 1,
                        name: "产品",
                        description: nil,
                        assetId: "1001"
                    )
                ],
                textValues: ["headline": "AIS"],
                selectedAspectRatio: "4:5",
                selectedResolution: "1536",
                additionalRequirement: "保留产品结构",
                recommendToGallery: true,
                promoMarkEnabled: true,
                selectedDisplayModelKey: "g2"
            )
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(request)
            ) as? [String: Any]
        )
        XCTAssertEqual(object["selectedDisplayModelKey"] as? String, "g2")
        XCTAssertEqual(object["promoMarkEnabled"] as? Bool, true)
        let snapshot = try XCTUnwrap(
            object["clientSnapshot"] as? [String: Any]
        )
        let slots = try XCTUnwrap(snapshot["imageSlots"] as? [[String: Any]])
        XCTAssertEqual(slots.first?["slotKey"] as? String, "product")
        XCTAssertEqual(slots.first?["assetId"] as? String, "1001")
    }

    private func decodeTemplate() throws -> StyleTemplate {
        let json = """
        {
          "Id": "1",
          "TemplateKey": "poster",
          "TemplateType": "image",
          "NameZh": "海报",
          "NameEn": "Poster",
          "AspectRatios": ["4:5"],
          "DefaultAspectRatio": "4:5",
          "Resolutions": ["1536"],
          "DefaultResolution": "1536",
          "DefaultDisplayModelKey": "g2",
          "AllowUserOverrideModel": true,
          "BasePointCost": 150,
          "UsageCount": 0,
          "ImageSlots": [{
            "SlotKey": "product",
            "NameZh": "产品",
            "NameEn": "Product",
            "Required": true,
            "Sort": 1
          }],
          "TextFields": [{
            "FieldKey": "headline",
            "FieldType": "text",
            "NameZh": "标题",
            "NameEn": "Headline",
            "IsRequired": true,
            "MaxLength": 5,
            "Sort": 1,
            "Enabled": true
          }],
          "Attributes": []
        }
        """
        return try JSONDecoder().decode(
            StyleTemplate.self,
            from: Data(json.utf8)
        )
    }
}
