import XCTest
@testable import AIS

final class AISTaskDetailMetadataTests: XCTestCase {
    func testDecodesDetailMetadataWithoutConvertingSnowflakeID() throws {
        let task = try decode([
            "Id": "1987654321098765432",
            "JobType": "image_generate",
            "Status": "succeeded",
            "Progress": 100,
            "PointCost": 180,
            "AspectRatio": "16:9",
            "Resolution": "1536",
            "FileSizeBytes": 2_558_525,
            "PixelWidth": 1536,
            "PixelHeight": 864,
            "GenerationDurationSeconds": 115
        ])

        XCTAssertEqual(task.id, "1987654321098765432")
        XCTAssertEqual(task.aspectRatio, "16:9")
        XCTAssertEqual(task.resolution, "1536")
        XCTAssertEqual(task.fileSizeBytes, 2_558_525)
        XCTAssertEqual(task.pixelWidth, 1536)
        XCTAssertEqual(task.pixelHeight, 864)
        XCTAssertEqual(task.generationDurationSeconds, 115)
    }

    func testKeepsHistoricalTaskResponseCompatible() throws {
        let task = try decode([
            "Id": "30113605",
            "JobType": "image_generate",
            "Status": "succeeded",
            "Progress": 100,
            "PointCost": 180
        ])

        XCTAssertNil(task.aspectRatio)
        XCTAssertNil(task.resolution)
        XCTAssertNil(task.fileSizeBytes)
        XCTAssertNil(task.pixelWidth)
        XCTAssertNil(task.pixelHeight)
        XCTAssertNil(task.generationDurationSeconds)
    }

    func testDecodesLowerCamelCaseMetadata() throws {
        let task = try decode([
            "id": "30113605",
            "jobType": "image_generate",
            "status": "succeeded",
            "progress": 100,
            "pointCost": 180,
            "aspectRatio": "4:3",
            "resolution": "1024",
            "fileSizeBytes": 1024,
            "generationDurationSeconds": 59
        ])

        XCTAssertEqual(task.aspectRatio, "4:3")
        XCTAssertEqual(task.resolution, "1024")
        XCTAssertEqual(task.fileSizeBytes, 1024)
        XCTAssertEqual(task.generationDurationSeconds, 59)
    }

    func testResultAvailabilityOnlyAcceptsSuccessfulTerminalStatuses() throws {
        let succeeded = try decode([
            "Id": "30113606",
            "JobType": "image_generate",
            "Status": "succeeded",
            "Progress": 100,
            "PointCost": 180
        ])
        let completed = try decode([
            "Id": "30113607",
            "JobType": "image_generate",
            "Status": "completed",
            "Progress": 100,
            "PointCost": 180
        ])
        let failed = try decode([
            "Id": "30113608",
            "JobType": "image_generate",
            "Status": "failed",
            "Progress": 100,
            "PointCost": 180
        ])

        XCTAssertTrue(succeeded.isSuccessful)
        XCTAssertTrue(completed.isSuccessful)
        XCTAssertFalse(failed.isSuccessful)
    }

    func testVideoSeparatesDisplayPosterFromResultFile() throws {
        let outputData = try JSONSerialization.data(
            withJSONObject: [
                "videoUrl": "https://example.com/result.mp4",
                "generatedImageUrl": "https://example.com/cover.jpg"
            ]
        )
        let task = try decode([
            "Id": "30113609",
            "JobType": "video_generate",
            "Status": "succeeded",
            "Progress": 100,
            "PointCost": 180,
            "OutputJson": String(decoding: outputData, as: UTF8.self)
        ])

        XCTAssertEqual(task.creationKind, .video)
        XCTAssertEqual(
            task.resultMediaURL?.absoluteString,
            "https://example.com/result.mp4"
        )
        XCTAssertEqual(
            task.mediaURL?.absoluteString,
            "https://example.com/cover.jpg"
        )
    }

    func testExplicitPosterTakesPriorityForVideoDisplay() throws {
        let task = try decode([
            "Id": "30113610",
            "JobType": "video_generate",
            "Status": "succeeded",
            "Progress": 100,
            "PointCost": 180,
            "ResultUrl": "https://example.com/result.mp4",
            "PosterUrl": "https://example.com/poster.jpg"
        ])

        XCTAssertEqual(
            task.resultMediaURL?.absoluteString,
            "https://example.com/result.mp4"
        )
        XCTAssertEqual(
            task.mediaURL?.absoluteString,
            "https://example.com/poster.jpg"
        )
    }

    func testMissingDirectURLDoesNotConstructAssetProxy() throws {
        let task = try decode([
            "Id": "30113612",
            "JobType": "image_generate",
            "Status": "succeeded",
            "Progress": 100,
            "PointCost": 180,
            "ResultAssetId": "840656451555590"
        ])

        XCTAssertNil(task.resultMediaURL)
        XCTAssertNil(task.mediaURL)
    }

    func testSharedVideoDecodesPlaybackAndPosterURLs() throws {
        let shared = try JSONDecoder().decode(
            AISSharedJob.self,
            from: JSONSerialization.data(
                withJSONObject: [
                    "Id": "30113611",
                    "Type": "video",
                    "Title": "视频案例",
                    "Description": "",
                    "PointCost": 180,
                    "MediaUrl": "https://example.com/result.mp4",
                    "PosterUrl": "https://example.com/poster.jpg"
                ]
            )
        )

        XCTAssertEqual(shared.mediaKind, .video)
        XCTAssertEqual(
            shared.mediaURL?.absoluteString,
            "https://example.com/result.mp4"
        )
        XCTAssertEqual(
            shared.displayURL?.absoluteString,
            "https://example.com/poster.jpg"
        )
    }

    private func decode(_ object: [String: Any]) throws -> AISTaskJob {
        try JSONDecoder().decode(
            AISTaskJob.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}
