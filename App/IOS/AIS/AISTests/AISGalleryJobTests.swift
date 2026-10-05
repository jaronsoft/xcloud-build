import XCTest
@testable import AIS

final class AISGalleryJobTests: XCTestCase {
    func testTemplateShowcaseQueryUsesTemplateJobType() {
        let query = GalleryViewModel.requestQuery(
            page: 2,
            pageSize: 20,
            language: "zh",
            kind: .templateShowcase
        )
        let parameters = Dictionary(
            uniqueKeysWithValues: query.map { ($0.name, $0.value) }
        )

        XCTAssertEqual(parameters["page"], "2")
        XCTAssertEqual(parameters["size"], "20")
        XCTAssertEqual(parameters["language"], "zh")
        XCTAssertEqual(
            parameters["jobType"],
            "style_template_generate"
        )
        XCTAssertFalse(parameters.keys.contains("excludeStyleTemplates"))
    }

    func testImageShowcaseQueryExcludesTemplateWorks() {
        let query = GalleryViewModel.requestQuery(
            page: 1,
            pageSize: 20,
            language: "en",
            kind: .imageShowcase
        )
        let parameters = Dictionary(
            uniqueKeysWithValues: query.map { ($0.name, $0.value) }
        )

        XCTAssertEqual(parameters["excludeStyleTemplates"], "true")
        XCTAssertFalse(parameters.keys.contains("jobType"))
    }

    func testPaginationTriggerLoadsOnlyNearPageBottom() {
        XCTAssertFalse(
            GalleryPaginationTrigger.shouldLoadMore(
                sentinelMinY: 1_200,
                viewportHeight: 800,
                hasMore: true,
                isLoading: false,
                isLoadingMore: false,
                hasLoadMoreError: false
            )
        )
        XCTAssertTrue(
            GalleryPaginationTrigger.shouldLoadMore(
                sentinelMinY: 1_000,
                viewportHeight: 800,
                hasMore: true,
                isLoading: false,
                isLoadingMore: false,
                hasLoadMoreError: false
            )
        )
    }

    func testPaginationTriggerStopsWhileBusyOrAfterFailure() {
        XCTAssertFalse(
            GalleryPaginationTrigger.shouldLoadMore(
                sentinelMinY: 800,
                viewportHeight: 800,
                hasMore: true,
                isLoading: true,
                isLoadingMore: false,
                hasLoadMoreError: false
            )
        )
        XCTAssertFalse(
            GalleryPaginationTrigger.shouldLoadMore(
                sentinelMinY: 800,
                viewportHeight: 800,
                hasMore: true,
                isLoading: false,
                isLoadingMore: true,
                hasLoadMoreError: false
            )
        )
        XCTAssertFalse(
            GalleryPaginationTrigger.shouldLoadMore(
                sentinelMinY: 800,
                viewportHeight: 800,
                hasMore: true,
                isLoading: false,
                isLoadingMore: false,
                hasLoadMoreError: true
            )
        )
    }

    func testReadsStringTemplateIDFromInputJSON() throws {
        let job = try makeJob(
            input: [
                "styleTemplateId": "123456789012345678"
            ]
        )

        XCTAssertEqual(job.styleTemplateID, "123456789012345678")
    }

    func testReadsNumericTemplateIDFromNestedSnapshot() throws {
        let job = try makeJob(
            input: [
                "ClientSnapshot": [
                    "StyleTemplateId": 123456 as NSNumber
                ]
            ]
        )

        XCTAssertEqual(job.styleTemplateID, "123456")
    }

    func testPrefersTopLevelTemplateID() throws {
        let job = try makeJob(
            input: ["styleTemplateId": "input-template"],
            extraFields: ["StyleTemplateId": "top-level-template"]
        )

        XCTAssertEqual(job.styleTemplateID, "top-level-template")
    }

    func testReadsCurrentPublicGalleryTitleAndDescription() throws {
        let job = try makeJob(
            input: [:],
            extraFields: [
                "Title": "营养谷物海报",
                "Description": "清新热带田园风格"
            ]
        )

        XCTAssertEqual(job.title, "营养谷物海报")
        XCTAssertEqual(job.description, "清新热带田园风格")
    }

    func testUsesActualPixelRatioBeforeRequestedAspectRatio() throws {
        let job = try makeJob(
            input: [:],
            extraFields: [
                "AspectRatio": "9:16",
                "PixelWidth": 1024,
                "PixelHeight": 1536
            ]
        )

        XCTAssertEqual(
            job.mediaAspectRatio ?? 0,
            CGFloat(2.0 / 3.0),
            accuracy: 0.001
        )
    }

    func testFallsBackToTopLevelAspectRatioWithoutPixelDimensions() throws {
        let job = try makeJob(
            input: [:],
            extraFields: ["AspectRatio": "4:5"]
        )

        XCTAssertEqual(
            job.mediaAspectRatio ?? 0,
            CGFloat(4.0 / 5.0),
            accuracy: 0.001
        )
    }

    func testReadsTemplateIDFromClientSnapshotJSON() throws {
        let snapshotData = try JSONSerialization.data(
            withJSONObject: ["styleTemplateId": "snapshot-template"]
        )
        let job = try makeJob(
            input: [:],
            extraFields: [
                "ClientSnapshotJson": String(
                    decoding: snapshotData,
                    as: UTF8.self
                )
            ]
        )

        XCTAssertEqual(job.styleTemplateID, "snapshot-template")
    }

    func testReadsNestedOutputDimensionsForPinAspectRatio() throws {
        let outputData = try JSONSerialization.data(
            withJSONObject: [
                "outputSpec": [
                    "TargetWidth": 1024,
                    "TargetHeight": 1536
                ]
            ]
        )
        let job = try makeJob(
            input: ["aspectRatio": "1:1"],
            extraFields: [
                "OutputJson": String(decoding: outputData, as: UTF8.self)
            ]
        )

        XCTAssertEqual(
            job.mediaAspectRatio ?? 0,
            CGFloat(2.0 / 3.0),
            accuracy: 0.001
        )
    }

    func testFallsBackToInputAspectRatioForPinLayout() throws {
        let job = try makeJob(input: ["aspectRatio": "9:16"])

        XCTAssertEqual(
            job.mediaAspectRatio ?? 0,
            CGFloat(9.0 / 16.0),
            accuracy: 0.001
        )
    }

    func testVideoUsesPosterForDisplayAndMP4ForPlayback() throws {
        let outputData = try JSONSerialization.data(
            withJSONObject: [
                "videoUrl": "https://example.com/result.mp4",
                "posterUrl": "https://example.com/poster.jpg"
            ]
        )
        let job = try makeJob(
            input: [:],
            extraFields: [
                "JobType": "video_generate",
                "OutputJson": String(decoding: outputData, as: UTF8.self)
            ]
        )

        XCTAssertEqual(job.creationKind, .video)
        XCTAssertEqual(
            job.mediaURL?.absoluteString,
            "https://example.com/poster.jpg"
        )
        XCTAssertEqual(
            job.videoURL?.absoluteString,
            "https://example.com/result.mp4"
        )
    }

    func testPrefersTopLevelCDNURLOverAssetProxy() throws {
        let job = try makeJob(
            input: [:],
            extraFields: [
                "ResultAssetId": "845088349798533",
                "ResultUrl": "https://cdn.jaronsoft.com/ais/images/example.png"
            ]
        )

        XCTAssertEqual(
            job.mediaURL?.absoluteString,
            "https://cdn.jaronsoft.com/ais/images/example.png"
        )
    }

    func testUsesInternationalGetFreeDeliveryURL() throws {
        let job = try makeJob(
            input: [:],
            extraFields: [
                "ResultAssetId": "845088349798533",
                "ResultUrl": "https://www.get-free.net/images/example.png"
            ]
        )

        XCTAssertEqual(
            job.mediaURL?.absoluteString,
            "https://www.get-free.net/images/example.png"
        )
    }

    func testDoesNotConstructAssetProxyWhenDirectURLIsMissing() throws {
        let imageJob = try makeJob(
            input: [:],
            extraFields: ["ResultAssetId": "845088349798533"]
        )
        let videoJob = try makeJob(
            input: [:],
            extraFields: [
                "JobType": "video_generate",
                "ResultAssetId": "845088349798533"
            ]
        )

        XCTAssertNil(imageJob.mediaURL)
        XCTAssertNil(videoJob.videoURL)
    }

    func testVideoUsesTopLevelResultAndPosterURLs() throws {
        let job = try makeJob(
            input: [:],
            extraFields: [
                "JobType": "video_generate",
                "ResultAssetId": "845088349798533",
                "ResultUrl": "https://cdn.jaronsoft.com/ais/videos/example.mp4",
                "PosterUrl": "https://cdn.jaronsoft.com/ais/images/poster.jpg"
            ]
        )

        XCTAssertEqual(
            job.mediaURL?.absoluteString,
            "https://cdn.jaronsoft.com/ais/images/poster.jpg"
        )
        XCTAssertEqual(
            job.videoURL?.absoluteString,
            "https://cdn.jaronsoft.com/ais/videos/example.mp4"
        )
    }

    func testCreationKindsUseRealBackendJobTypes() {
        XCTAssertEqual(
            AISCreationKind(jobType: "image_generate"),
            .image
        )
        XCTAssertEqual(AISCreationKind(jobType: "image_edit"), .imageEdit)
        XCTAssertEqual(AISCreationKind(jobType: "video_generate"), .video)
        XCTAssertEqual(
            AISCreationKind(jobType: "style_template_generate"),
            .template
        )
    }

    private func makeJob(
        input: [String: Any],
        extraFields: [String: Any] = [:]
    ) throws -> GalleryJob {
        let inputData = try JSONSerialization.data(withJSONObject: input)
        let inputJSON = String(decoding: inputData, as: UTF8.self)
        var object: [String: Any] = [
            "Id": "999",
            "JobType": "style_template_generate",
            "GalleryTitle": "模板案例",
            "GalleryDescription": "",
            "UserRequirement": "",
            "InputJson": inputJSON,
            "PointCost": 100
        ]
        for (key, value) in extraFields {
            object[key] = value
        }
        return try JSONDecoder().decode(
            GalleryJob.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}
