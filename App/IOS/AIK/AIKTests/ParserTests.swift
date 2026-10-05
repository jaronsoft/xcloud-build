import Foundation
import XCTest
@testable import AIK

final class ParserTests: XCTestCase {
    func testInviteLinkVariants() {
        XCTAssertEqual(
            InviteLinkParser.parse("aik://tenant/123456/CODE2026"),
            InviteReference(tenantID: "123456", code: "CODE2026", accessCode: nil)
        )
        XCTAssertEqual(
            InviteLinkParser.parse("https://app.jaronsoft.com/123456?code=ABCDEFGH"),
            InviteReference(tenantID: "123456", code: "ABCDEFGH", accessCode: nil)
        )
        XCTAssertEqual(
            InviteLinkParser.parse("ABCDEFGH"),
            InviteReference(tenantID: nil, code: "ABCDEFGH", accessCode: nil)
        )
        XCTAssertEqual(
            InviteLinkParser.parse("https://ai.jaronsoft.com/s/483726"),
            InviteReference(tenantID: nil, code: nil, accessCode: "483726")
        )
        XCTAssertEqual(
            InviteLinkParser.parse("483726"),
            InviteReference(tenantID: nil, code: nil, accessCode: "483726")
        )
        XCTAssertNil(InviteLinkParser.parse("not a valid invitation"))
    }

    func testSSEHandlesFragmentedAndCoalescedPackets() {
        var parser = SSEParser()
        XCTAssertTrue(parser.feed(Data("data: hel".utf8)).isEmpty)

        let events = parser.feed(
            Data((
                "lo\n\n"
                    + "data: __METADATA__{\"id\":9223372036854775806,"
                    + "\"sessionId\":\"7\",\"logDate\":\"now\"}\n\n"
                    + "data: [DONE]\n\n"
            ).utf8)
        )

        XCTAssertEqual(events.count, 3)
        guard events.count == 3 else { return }
        XCTAssertEqual(events[0], .content("hello"))
        XCTAssertEqual(
            events[1],
            .metadata(
                messageID: "9223372036854775806",
                sessionID: "7",
                logDate: "now"
            )
        )
        XCTAssertEqual(events[2], .done)
    }

    func testSSEStatusAndErrorPackets() {
        var parser = SSEParser()
        let events = parser.feed(
            Data((
                "data: __STATUS__{\"msg\":\"正在检索\"}\n\n"
                    + "data: __ERROR__{\"message\":\"无权限\"}\n\n"
            ).utf8)
        )
        XCTAssertEqual(events, [.status("正在检索"), .failure("无权限")])
    }

    func testSSEPreservesMultilineMarkdownEvent() {
        var parser = SSEParser()
        let events = parser.feed(
            Data("data: 第一行\ndata: \ndata: - 第二行\n\n".utf8)
        )
        XCTAssertEqual(events, [.content("第一行\n\n- 第二行")])
    }

    func testMarkdownImageAndLinkSegmentation() {
        let segments = MarkdownContentParser.parse(
            "请看[文档](https://example.com/doc) ![示意图](/uploads/a.png)",
            baseURL: URL(string: "https://app.jaronsoft.com/api")!
        )

        XCTAssertEqual(segments.count, 2)
        guard case let .image(alt, url) = segments[1] else {
            return XCTFail("第二段应为图片")
        }
        XCTAssertEqual(alt, "示意图")
        XCTAssertEqual(
            url.absoluteString,
            "https://app.jaronsoft.com/uploads/a.png"
        )
    }

    func testMarkdownBlockSyntaxDoesNotLeakIntoRenderedText() {
        let markdown = """
        ### 核心能力
        - 多模态知识整合
        - 语义精准检索

        ### 典型应用场景
        1. 政务知识中枢
        2. 警务实战支撑
        """

        let rendered = String(
            MarkdownContentParser.attributedText(markdown).characters
        )

        XCTAssertFalse(rendered.contains("###"))
        XCTAssertFalse(rendered.contains("- 多模态"))
        XCTAssertTrue(rendered.contains("核心能力"))
        XCTAssertTrue(rendered.contains("多模态知识整合"))
        XCTAssertTrue(rendered.contains("典型应用场景"))
        XCTAssertTrue(rendered.contains("政务知识中枢"))
    }

    func testMarkdownRenderedTextPreservesSourceLineBreaks() {
        let markdown = """
        Delivery details.
        To provide accurate information.

        ### Core Operating Principles
        **No Hallucination:** I will not guess.
        """

        let rendered = String(
            MarkdownContentParser.attributedText(markdown).characters
        )

        XCTAssertEqual(
            rendered,
            """
            Delivery details.
            To provide accurate information.

            Core Operating Principles
            No Hallucination: I will not guess.
            """
        )
    }
}
