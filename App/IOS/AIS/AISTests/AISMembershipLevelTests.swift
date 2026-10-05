import Testing
@testable import AIS

struct AISMembershipLevelTests {
    @Test(
        arguments: [
            ("vip" as String?, nil as String?, "MembershipLevel1"),
            ("plus" as String?, nil as String?, "MembershipLevel2"),
            ("pro" as String?, nil as String?, "MembershipLevel3"),
            ("student" as String?, nil as String?, "MembershipLevel4"),
            ("max" as String?, nil as String?, "MembershipLevel5"),
            ("enterprise" as String?, nil as String?, "MembershipLevel6"),
            (nil as String?, "企业" as String?, "MembershipLevel6"),
            ("custom" as String?, "普通用户" as String?, "MembershipLevel1")
        ]
    )
    func resolvesIcon(
        code: String?,
        name: String?,
        expected: String
    ) {
        #expect(AISMembershipLevel.iconName(code: code, name: name) == expected)
    }
}
