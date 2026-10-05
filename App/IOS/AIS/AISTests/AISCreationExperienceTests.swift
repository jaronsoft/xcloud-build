import XCTest
@testable import AIS

@MainActor
final class AISCreationExperienceTests: XCTestCase {
    func testPricingRulesRetryPolicyRetriesOnlyTransientFailures() {
        XCTAssertEqual(AISPricingRulesRetryPolicy.maximumAttempts, 3)
        XCTAssertEqual(
            AISPricingRulesRetryPolicy.delayMilliseconds(
                afterFailedAttempt: 1
            ),
            300
        )
        XCTAssertEqual(
            AISPricingRulesRetryPolicy.delayMilliseconds(
                afterFailedAttempt: 2
            ),
            900
        )
        XCTAssertNil(
            AISPricingRulesRetryPolicy.delayMilliseconds(
                afterFailedAttempt: 3
            )
        )
        XCTAssertTrue(
            AISPricingRulesRetryPolicy.shouldRetry(
                APIError.server(status: 503, message: "Unavailable"),
                afterFailedAttempt: 1
            )
        )
        XCTAssertTrue(
            AISPricingRulesRetryPolicy.shouldRetry(
                URLError(.timedOut),
                afterFailedAttempt: 2
            )
        )
        XCTAssertFalse(
            AISPricingRulesRetryPolicy.shouldRetry(
                APIError.server(status: 401, message: "Unauthorized"),
                afterFailedAttempt: 1
            )
        )
        XCTAssertFalse(
            AISPricingRulesRetryPolicy.shouldRetry(
                APIError.rejected(message: "Rejected"),
                afterFailedAttempt: 1
            )
        )
        XCTAssertFalse(
            AISPricingRulesRetryPolicy.shouldRetry(
                APIError.invalidResponse,
                afterFailedAttempt: 3
            )
        )
    }

    func testResponsiveColumnsFollowAvailableWidth() {
        XCTAssertEqual(AISResponsiveLayout.templateColumns(for: 390), 2)
        XCTAssertEqual(AISResponsiveLayout.templateColumns(for: 559), 2)
        XCTAssertEqual(AISResponsiveLayout.templateColumns(for: 560), 3)
        XCTAssertEqual(AISResponsiveLayout.templateColumns(for: 799), 3)
        XCTAssertEqual(AISResponsiveLayout.templateColumns(for: 800), 4)
        XCTAssertEqual(AISResponsiveLayout.templateColumns(for: 1_099), 4)
        XCTAssertEqual(AISResponsiveLayout.templateColumns(for: 1_100), 5)

        XCTAssertEqual(
            AISResponsiveLayout.imageGalleryColumns(for: 390),
            1
        )
        XCTAssertEqual(
            AISResponsiveLayout.imageGalleryColumns(for: 760),
            2
        )
        XCTAssertEqual(
            AISResponsiveLayout.imageGalleryColumns(for: 1_120),
            3
        )
        XCTAssertFalse(
            AISResponsiveLayout.usesWideCreationLayout(for: 899)
        )
        XCTAssertTrue(
            AISResponsiveLayout.usesWideCreationLayout(for: 900)
        )
        XCTAssertTrue(
            AISResponsiveLayout.usesCompactCreationPickers(for: 699)
        )
        XCTAssertFalse(
            AISResponsiveLayout.usesCompactCreationPickers(for: 700)
        )

        XCTAssertEqual(
            AISResponsiveLayout.taskColumns(
                for: CGSize(width: 1_366, height: 1_024)
            ),
            2
        )
        XCTAssertEqual(
            AISResponsiveLayout.taskColumns(
                for: CGSize(width: 1_024, height: 1_366)
            ),
            1
        )
        XCTAssertEqual(
            AISResponsiveLayout.taskColumns(
                for: CGSize(width: 900, height: 700)
            ),
            1
        )
        XCTAssertEqual(
            AISResponsiveLayout.taskMaximumContentWidth(
                for: CGSize(width: 1_024, height: 1_366)
            ),
            860
        )
        XCTAssertTrue(
            AISResponsiveLayout.usesWideTemplateDetailLayout(
                for: CGSize(width: 1_366, height: 1_024)
            )
        )
        XCTAssertFalse(
            AISResponsiveLayout.usesWideTemplateDetailLayout(
                for: CGSize(width: 1_024, height: 1_366)
            )
        )
        XCTAssertFalse(
            AISResponsiveLayout.usesWideTemplateDetailLayout(
                for: CGSize(width: 900, height: 700)
            )
        )
    }

    func testModelSelectionRequiresUseSelectAndOverridePermissions() {
        let available = model(canSelect: true, canUse: true)
        let templateLocked = model(canSelect: false, canUse: true)
        let membershipLocked = model(canSelect: true, canUse: false)

        XCTAssertTrue(
            AISGenerationModelSelection.canSelect(
                available,
                allowsSelection: true
            )
        )
        XCTAssertFalse(
            AISGenerationModelSelection.canSelect(
                templateLocked,
                allowsSelection: true
            )
        )
        XCTAssertFalse(
            AISGenerationModelSelection.canSelect(
                membershipLocked,
                allowsSelection: true
            )
        )
        XCTAssertFalse(
            AISGenerationModelSelection.canSelect(
                available,
                allowsSelection: false
            )
        )
    }

    func testLegacyEffectSelectionIsFilteredDeduplicatedAndLimited() {
        let normalized = AISCreationSelectionPolicy.normalizedEffectIDs(
            ["soft", "soft", "glow", "missing", "clean", "fourth"],
            availableIDs: ["soft", "glow", "clean", "fourth"],
            limit: 3
        )

        XCTAssertEqual(normalized, ["soft", "glow", "clean"])
        XCTAssertEqual(
            AISCreationSelectionPolicy.hiddenExtendedAttributeIDs,
            Set(["direction", "effect"])
        )
    }

    func testRequestAttributesIncludeConfiguredDirection() {
        let attributes = AISCreationSelectionPolicy.requestAttributes(
            from: ["camera": ["front_view"]],
            directionID: " product_detail "
        )

        XCTAssertEqual(attributes["camera"], ["front_view"])
        XCTAssertEqual(attributes["direction"], ["product_detail"])
        XCTAssertNil(
            AISCreationSelectionPolicy.requestAttributes(
                from: ["direction": ["legacy"]],
                directionID: " "
            )["direction"]
        )
    }

    func testPromptDirectionItemsMapToHomePresetsInSortOrder() throws {
        let data = Data(
            """
            {
              "MediaType": "image",
              "Groups": [
                {
                  "Id": "direction",
                  "MediaType": "image",
                  "NameZh": "视觉方向",
                  "NameEn": "Direction",
                  "Type": "single",
                  "MaxSelected": 1,
                  "Sort": 1,
                  "Items": [
                    {
                      "Id": "disabled_direction",
                      "NameZh": "已停用方向",
                      "NameEn": "Disabled Direction",
                      "Sort": 5,
                      "Multiplier": 1,
                      "IsAvailable": false
                    },
                    {
                      "Id": "product_detail",
                      "NameZh": "产品细节展示",
                      "NameEn": "Product Detail",
                      "DescriptionZh": "展示产品细节",
                      "DescriptionEn": "Show product details",
                      "Sort": 20,
                      "Multiplier": 1,
                      "IsAvailable": true
                    },
                    {
                      "Id": "studio_product",
                      "NameZh": "电商产品影棚",
                      "NameEn": "Studio Product",
                      "DescriptionZh": "影棚产品图",
                      "DescriptionEn": "Studio product image",
                      "Sort": 10,
                      "Multiplier": 1,
                      "IsAvailable": true
                    }
                  ]
                }
              ],
              "ModelOutputSpecs": []
            }
            """.utf8
        )
        let settings = try JSONDecoder().decode(
            AISPromptAttributeSettings.self,
            from: data
        )

        let presets = AISVisualPresetMapper.presets(
            from: settings,
            groupID: "DIRECTION"
        )

        XCTAssertEqual(presets.map(\.id), ["studio_product", "product_detail"])
        XCTAssertEqual(presets.last?.nameZh, "产品细节展示")
    }

    func testPointMultiplierTextRemovesTrailingZeros() {
        XCTAssertEqual(AISPointMultiplierFormatter.decimalText(1), "1")
        XCTAssertEqual(AISPointMultiplierFormatter.decimalText(1.3), "1.3")
        XCTAssertNil(AISPointMultiplierFormatter.visibleLabel(1))
        XCTAssertNotNil(AISPointMultiplierFormatter.visibleLabel(1.3))
    }

    func testEnterpriseMembershipBadgeUsesLocalizedBusinessName() {
        XCTAssertEqual(
            AISMembershipLabelFormatter.displayName(
                code: "enterprise",
                configuredName: "Enterprise"
            ),
            AISLocalization.isChinese ? "企业" : "Enterprise"
        )
        let value = AISMembershipLabelFormatter.availabilityLabel(
            code: "enterprise",
            configuredName: "Enterprise"
        )
        let expectedName = AISLocalization.isChinese ? "企业" : "Enterprise"

        XCTAssertTrue(value?.contains(expectedName) == true)
    }

    func testBillableActionsUseExpectedQuoteTypes() throws {
        let encoder = JSONEncoder()
        let understand = try jsonObject(
            encoder.encode(
                AISBillableActionQuoteRequest(action: .imageUnderstand)
            )
        )
        let optimize = try jsonObject(
            encoder.encode(
                AISBillableActionQuoteRequest(action: .promptOptimize)
            )
        )

        XCTAssertEqual(
            understand["generationType"] as? String,
            "image_understand"
        )
        XCTAssertEqual(understand["count"] as? Int, 1)
        XCTAssertEqual(
            optimize["generationType"] as? String,
            "prompt_optimize"
        )
        XCTAssertEqual(optimize["count"] as? Int, 1)
    }

    func testGenerationSuggestsPlanningWithoutActiveOptimizedPrompt() {
        XCTAssertTrue(
            AISCreationPreflight.requiresPlanningSuggestion(
                usesOptimizedPrompt: false,
                optimizedPrompt: "完整策划"
            )
        )
        XCTAssertTrue(
            AISCreationPreflight.requiresPlanningSuggestion(
                usesOptimizedPrompt: true,
                optimizedPrompt: " "
            )
        )
        XCTAssertFalse(
            AISCreationPreflight.requiresPlanningSuggestion(
                usesOptimizedPrompt: true,
                optimizedPrompt: "完整策划"
            )
        )
    }

    func testGenerationSubmissionStateReplacesButtonUntilTerminal() {
        XCTAssertEqual(
            AISCreationSubmissionState.resolve(
                isWorking: false,
                activeJobID: nil,
                activeJobIsActive: nil,
                progress: nil
            ),
            .idle
        )
        XCTAssertEqual(
            AISCreationSubmissionState.resolve(
                isWorking: true,
                activeJobID: nil,
                activeJobIsActive: nil,
                progress: nil
            ),
            .submitting
        )
        XCTAssertEqual(
            AISCreationSubmissionState.resolve(
                isWorking: true,
                activeJobID: "1",
                activeJobIsActive: nil,
                progress: nil
            ),
            .waitingForProgress
        )
        XCTAssertEqual(
            AISCreationSubmissionState.resolve(
                isWorking: false,
                activeJobID: "1",
                activeJobIsActive: true,
                progress: 35
            ),
            .generating(35)
        )
        XCTAssertEqual(
            AISCreationSubmissionState.resolve(
                isWorking: false,
                activeJobID: "1",
                activeJobIsActive: false,
                progress: 100
            ),
            .terminal
        )
    }

    func testDraftEncodingDoesNotPersistGlobalPromoPreference() throws {
        let creation = CreationDraftState(
            prompt: "",
            optimizedPrompt: "",
            usesOptimizedPrompt: false,
            orientation: "landscape",
            aspectRatio: "16:9",
            resolution: "1536",
            selectedModelKey: "g2",
            selectedDirectionID: "industrial",
            selectedEffectIDs: [],
            selectedAttributes: [:],
            recommendToGallery: true
        )
        let template = TemplateDraftState(
            aspectRatio: "4:5",
            resolution: "1536",
            selectedModelKey: "g2",
            textValues: [:],
            additionalRequirement: "",
            recommendToGallery: true
        )

        XCTAssertNil(
            try jsonObject(JSONEncoder().encode(creation))[
                "promoMarkEnabled"
            ]
        )
        XCTAssertNil(
            try jsonObject(JSONEncoder().encode(template))[
                "promoMarkEnabled"
            ]
        )
    }

    func testLocalImagePricingCombinesCachedRules() throws {
        let price = AISLocalPricingCalculator.image(
            snapshot: try pricingRules(),
            orientation: "landscape",
            aspectRatio: "16:9",
            resolution: "4K",
            selectedAttributes: ["effect": ["soft"]],
            selectedModelKey: "g2",
            promoMarkEnabled: true
        )

        XCTAssertEqual(price.originalPoints, 567)
        XCTAssertEqual(price.points, 454)
        XCTAssertEqual(price.savedPoints, 113)
        XCTAssertEqual(price.effectiveDiscountPercent, 20)
        XCTAssertEqual(price.effectiveBenefitSource, "promo_mark")
        XCTAssertTrue(price.promoMarkApplied)
        let membershipSaved = AISLocalPricingCalculator
            .membershipSavedPoints(
                snapshot: try pricingRules(),
                originalPoints: price.originalPoints
            )
        XCTAssertEqual(membershipSaved, 56)
        XCTAssertEqual(price.savedPoints - membershipSaved, 57)
    }

    func testLocalPricingDoesNotApplyPromoMarkOnEqualDiscount() throws {
        let json = String(decoding: pricingRulesJSON(), as: UTF8.self)
            .replacingOccurrences(
                of: "\"PromoMarkDiscountPercent\": \"20\"",
                with: "\"PromoMarkDiscountPercent\": \"10\""
            )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rules = try decoder.decode(
            AISPricingRulesSnapshot.self,
            from: Data(json.utf8)
        )
        let price = AISLocalPricingCalculator.image(
            snapshot: rules,
            aspectRatio: "",
            resolution: "1024",
            promoMarkEnabled: true
        )

        XCTAssertEqual(price.points, 99)
        XCTAssertEqual(price.effectiveDiscountPercent, 10)
        XCTAssertFalse(price.promoMarkApplied)
        XCTAssertNotNil(price.promoMarkSuppressedReason)
    }

    func testLocalImagePricingUsesConfiguredResolutionWhenRuleKeyIsMissing()
        throws {
        let price = AISLocalPricingCalculator.image(
            snapshot: try pricingRules(),
            aspectRatio: "",
            resolution: "8K",
            fallbackResolutionMultiplier: 4
        )

        XCTAssertEqual(price.originalPoints, 440)
        XCTAssertEqual(price.points, 396)
        let membershipSaved = AISLocalPricingCalculator
            .membershipSavedPoints(
                snapshot: try pricingRules(),
                originalPoints: price.originalPoints
            )
        XCTAssertEqual(membershipSaved, 44)
        XCTAssertEqual(price.savedPoints - membershipSaved, 0)
    }

    func testTemplatePricingKeepsDefaultResolutionAtOneTimes() throws {
        let rules = try pricingRules()
        let defaultPrice = AISLocalPricingCalculator.template(
            snapshot: rules,
            basePoints: 80,
            defaultResolution: "4K",
            resolution: "4K",
            selectedModelKey: "g2"
        )
        let upgradedPrice = AISLocalPricingCalculator.template(
            snapshot: rules,
            basePoints: 80,
            defaultResolution: "1024",
            resolution: "4K",
            selectedModelKey: "g2"
        )

        XCTAssertEqual(defaultPrice.originalPoints, 115)
        XCTAssertEqual(defaultPrice.points, 104)
        XCTAssertEqual(upgradedPrice.originalPoints, 229)
        XCTAssertEqual(upgradedPrice.points, 207)
    }

    func testPriceChangePayloadCarriesLatestRules() throws {
        let rulesObject = try JSONDecoder().decode(
            JSONValue.self,
            from: pricingRulesJSON()
        )
        let payload = AISPriceChangePayload(
            details: .object([
                "localCalculatedPoints": .number(179),
                "points": .number(233),
                "originalPoints": .number(260),
                "savedPoints": .number(27),
                "latestPricingRules": rulesObject
            ])
        )

        XCTAssertEqual(payload?.localCalculatedPoints, 179)
        XCTAssertEqual(payload?.points, 233)
        XCTAssertEqual(payload?.latestPricingRules?.version, "rules-test")
        XCTAssertEqual(
            payload?.latestPricingRules?.imageResolutionMultipliers["4K"],
            "2"
        )
    }

    private func model(
        canSelect: Bool,
        canUse: Bool
    ) -> AISGenerationModelOption {
        AISGenerationModelOption(
            displayModelKey: "g2",
            nameZh: "G2",
            nameEn: "G2",
            descriptionZh: nil,
            descriptionEn: nil,
            requiredMembershipCode: nil,
            isRecommended: true,
            canSelect: canSelect,
            canUse: canUse,
            upgradePromptZh: nil,
            upgradePromptEn: nil,
            modelMarkupRate: 1
        )
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func pricingRules() throws -> AISPricingRulesSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            AISPricingRulesSnapshot.self,
            from: pricingRulesJSON()
        )
    }

    private func pricingRulesJSON() -> Data {
        Data(
            """
            {
              "Version": "rules-test",
              "GeneratedAt": "2026-07-29T04:00:00Z",
              "ExpiresAt": "2099-01-01T00:00:00Z",
              "Token": null,
              "ImageBasePoints": 100,
              "VideoBasePoints": 500,
              "VideoPerSecondPoints": 100,
              "VideoAllowedDurationSeconds": [4, 6, 8],
              "PromptOptimizeBasePoints": 50,
              "ImageUnderstandBasePoints": 50,
              "ResultAnalysisBasePoints": 100,
              "TemplateBasePoints": 80,
              "ImageOrientationMultipliers": {
                "Landscape": "1.2"
              },
              "ImageAspectRatioMultipliers": {
                "16:9": "1.5"
              },
              "ImageResolutionMultipliers": {
                "1024": "1",
                "4K": "2"
              },
              "ImageAttributeMultipliers": {
                "Effect": {
                  "Soft": "1.1"
                }
              },
              "ImageModelMultipliers": {
                "G2": "1.3"
              },
              "VideoAspectRatioMultipliers": {},
              "VideoResolutionMultipliers": {},
              "CountryMultiplier": "1.1",
              "MembershipDiscountPercent": "10",
              "MembershipBenefitCode": "pro",
              "MembershipBenefitName": "Pro",
              "RechargeMembershipDiscountPercent": "10",
              "RechargeMembershipBenefitName": "Pro",
              "RechargeMembershipBenefitSource": "recharge",
              "SubscriptionDiscountPercent": "0",
              "SubscriptionBenefitName": null,
              "EffectiveDiscountPercent": "10",
              "EffectiveBenefitCode": "pro",
              "EffectiveBenefitName": "Pro",
              "EffectiveBenefitSource": "recharge",
              "DiscountPolicy": "max",
              "EffectiveMembershipLevel": "pro",
              "PromoMarkEnabled": true,
              "PromoMarkDiscountPercent": "20",
              "PromoMarkCode": "ais_mark",
              "PromoMarkName": "AIS Mark",
              "PromoMarkVersion": "1",
              "ImageEdit": {
                "LocalAiEditRate": "0.5",
                "LocalAiEditMinPoints": 100,
                "AiEditRate": "0.6",
                "AiEditMinPoints": 120,
                "AiFusionRate": "0.75",
                "AiFusionMinPoints": 160,
                "RoundTo": 10
              }
            }
            """.utf8
        )
    }
}
