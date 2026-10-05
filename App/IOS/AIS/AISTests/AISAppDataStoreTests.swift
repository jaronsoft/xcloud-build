import Foundation
import Testing
@testable import AIS

struct AISAppDataStoreTests {
    @Test(
        arguments: [
            """
            {
              "Email": "user@example.com",
              "DisplayName": "AIS User",
              "CountryCode": "US",
              "EffectiveMembershipLevel": "pro",
              "EffectiveMembershipBenefitCode": "pro",
              "EffectiveMembershipBenefitName": "Pro"
            }
            """,
            """
            {
              "email": "user@example.com",
              "displayName": "AIS User",
              "countryCode": "US",
              "effectiveMembershipLevel": "pro",
              "effectiveMembershipBenefitCode": "pro",
              "effectiveMembershipBenefitName": "Pro"
            }
            """
        ]
    )
    func decodesAccountProfileFromSupportedKeyStyles(_ json: String) throws {
        let profile = try JSONDecoder().decode(
            AISAccountProfile.self,
            from: Data(json.utf8)
        )

        #expect(profile.email == "user@example.com")
        #expect(profile.displayName == "AIS User")
        #expect(profile.countryCode == "US")
        #expect(profile.effectiveMembershipLevel == "pro")
        #expect(profile.effectiveMembershipBenefitCode == "pro")
        #expect(profile.effectiveMembershipBenefitName == "Pro")
    }

    @Test
    @MainActor
    func startsWithoutGenerationPermission() {
        let store = AISAppDataStore()

        #expect(store.userDataState == .idle)
        #expect(store.isGenerationReady == false)
        #expect(store.isRefreshingUserData == false)
    }
}
