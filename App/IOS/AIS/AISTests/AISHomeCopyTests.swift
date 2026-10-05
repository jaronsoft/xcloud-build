import XCTest
@testable import AIS

final class AISHomeCopyTests: XCTestCase {
    func testLanguageResolutionUsesExactAndLanguageFallbacks() {
        let item = makeItem()

        XCTAssertEqual(
            AISHomeCopyPolicy.resolved(
                item: item,
                preferredLanguages: ["zh-Hans-CN"]
            )?.title,
            "中文标题"
        )
        XCTAssertEqual(
            AISHomeCopyPolicy.resolved(
                item: item,
                preferredLanguages: ["en-US"]
            )?.title,
            "English title"
        )
        XCTAssertEqual(
            AISHomeCopyPolicy.resolved(
                item: item,
                preferredLanguages: ["ja-JP"]
            )?.title,
            "English title"
        )
    }

    func testSelectionAvoidsPreviousItemWhenAlternativesExist() {
        let first = makeItem(id: "first")
        let second = makeItem(id: "second")

        let selected = AISHomeCopyPolicy.select(
            from: [first, second],
            excluding: "first",
            preferredLanguages: ["zh-Hans"],
            randomIndex: { _ in 0 }
        )

        XCTAssertEqual(selected?.id, "second")
    }

    func testValidationRejectsMissingRequiredLanguage() {
        let invalid = AISHomeCopyOptions(
            items: [
                AISHomeCopyItem(
                    id: "invalid",
                    sort: 10,
                    localizations: [
                        AISHomeCopyLocalization(
                            locale: "zh-Hans",
                            eyebrow: "眉题",
                            title: "标题",
                            subtitle: "副标题"
                        )
                    ]
                )
            ]
        )

        XCTAssertFalse(AISHomeCopyPolicy.isValid(invalid))
    }

    func testDayKeyUsesCalendarNaturalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let date = Date(timeIntervalSince1970: 1_786_420_800)

        XCTAssertEqual(
            AISHomeCopyPolicy.dayKey(for: date, calendar: calendar),
            "2026-08-11"
        )
    }

    private func makeItem(id: String = "home_copy") -> AISHomeCopyItem {
        AISHomeCopyItem(
            id: id,
            sort: 10,
            localizations: [
                AISHomeCopyLocalization(
                    locale: "zh-Hans",
                    eyebrow: "中文眉题",
                    title: "中文标题",
                    subtitle: "中文副标题"
                ),
                AISHomeCopyLocalization(
                    locale: "en",
                    eyebrow: "English eyebrow",
                    title: "English title",
                    subtitle: "English subtitle"
                )
            ]
        )
    }
}
