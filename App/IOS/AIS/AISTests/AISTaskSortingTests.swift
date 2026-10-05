import XCTest
@testable import AIS

final class AISTaskSortingTests: XCTestCase {
    func testNewestComparisonUsesParsedCreationDate() throws {
        let older = try task(
            id: "999999999999999999",
            createTime: "2026-07-24 10:00:00"
        )
        let newer = try task(
            id: "100000000000000000",
            createTime: "2026-07-25T09:00:00Z"
        )

        XCTAssertTrue(newer.isNewer(than: older))
        XCTAssertFalse(older.isNewer(than: newer))
    }

    func testNewestComparisonFallsBackToSnowflakeID() throws {
        let older = try task(id: "100", createTime: nil)
        let newer = try task(id: "1000", createTime: nil)

        XCTAssertTrue(newer.isNewer(than: older))
        XCTAssertFalse(older.isNewer(than: newer))
    }

    private func task(id: String, createTime: String?) throws -> AISTaskJob {
        var object: [String: Any] = [
            "Id": id,
            "JobType": "image_generate",
            "Status": "succeeded",
            "Progress": 100,
            "PointCost": 100,
            "GalleryTitle": "测试任务",
            "UserRequirement": ""
        ]
        object["CreateTime"] = createTime
        return try JSONDecoder().decode(
            AISTaskJob.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}
