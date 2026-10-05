import XCTest
@testable import AIS

final class AISImageGalleryViewerTests: XCTestCase {
    func testGalleryItemsPutMainFirstAndSortUsableReferences() throws {
        let references = try decodeReferences([
            [
                "Index": 3,
                "Url": "https://example.com/third.jpg",
                "Available": true,
                "Kind": "input"
            ],
            [
                "Index": 1,
                "Url": "https://example.com/first.jpg",
                "Available": true,
                "Kind": "input"
            ],
            [
                "Index": 2,
                "Available": true,
                "Kind": "input"
            ],
            [
                "Index": 0,
                "Url": "https://example.com/unavailable.jpg",
                "Available": false,
                "Kind": "input"
            ]
        ])

        let items = AISMediaViewerCollection.galleryItems(
            resultURL: URL(string: "https://example.com/main.jpg"),
            resultKind: .image,
            posterURL: nil,
            title: "案例",
            references: references
        )

        XCTAssertEqual(
            items.map(\.id),
            ["main", "reference:input:1", "reference:input:3"]
        )
        XCTAssertEqual(items.first?.title, "案例")
        XCTAssertEqual(items.first?.kind, .image)
    }

    func testVideoItemKeepsOriginalAndPosterSeparated() {
        let resultURL = URL(string: "https://example.com/result.mp4")!
        let posterURL = URL(string: "https://example.com/poster.jpg")!

        let items = AISMediaViewerCollection.galleryItems(
            resultURL: resultURL,
            resultKind: .video,
            posterURL: posterURL,
            title: "视频案例",
            references: []
        )

        XCTAssertEqual(items.first?.kind, .video)
        XCTAssertEqual(items.first?.originalURL, resultURL)
        XCTAssertEqual(items.first?.thumbnailURL, posterURL)
    }

    func testGalleryItemsKeepSourceAndEditPreviewRoles() throws {
        let references = try decodeReferences([
            [
                "Index": 0,
                "Url": "https://example.com/source.jpg",
                "Available": true,
                "Kind": "source"
            ],
            [
                "Index": 1,
                "Url": "https://example.com/edit-preview.png",
                "Available": true,
                "Kind": "edit_preview"
            ]
        ])

        let items = AISMediaViewerCollection.galleryItems(
            resultURL: nil,
            resultKind: .image,
            posterURL: nil,
            title: nil,
            references: references
        )

        XCTAssertEqual(
            items.map(\.id),
            ["reference:source:0", "reference:edit_preview:1"]
        )
        XCTAssertEqual(items[0].title, references[0].galleryDisplayName)
        XCTAssertEqual(items[1].title, references[1].galleryDisplayName)
    }

    func testResolvedIDKeepsSelectionOrFallsBackAfterCollectionChange() {
        let items = [
            makeItem(id: "main"),
            makeItem(id: "reference:1")
        ]

        XCTAssertEqual(
            AISMediaViewerCollection.resolvedID(
                preferredID: "reference:1",
                items: items
            ),
            "reference:1"
        )
        XCTAssertEqual(
            AISMediaViewerCollection.resolvedID(
                preferredID: "removed",
                items: items
            ),
            "main"
        )
        XCTAssertNil(
            AISMediaViewerCollection.resolvedID(
                preferredID: "main",
                items: []
            )
        )
    }

    func testPositionUsesSelectedItemAndSafeFallback() {
        let items = [
            makeItem(id: "main"),
            makeItem(id: "reference:1"),
            makeItem(id: "reference:2")
        ]

        XCTAssertEqual(
            AISMediaViewerCollection.position(
                selectedID: "reference:1",
                items: items
            ),
            2
        )
        XCTAssertEqual(
            AISMediaViewerCollection.position(
                selectedID: "missing",
                items: items
            ),
            1
        )
        XCTAssertEqual(
            AISMediaViewerCollection.position(
                selectedID: nil,
                items: []
            ),
            0
        )
    }

    func testZoomScaleAndOffsetAreClamped() {
        XCTAssertFalse(AISZoomTransform.isZoomed(1))
        XCTAssertTrue(AISZoomTransform.isZoomed(1.01))
        XCTAssertEqual(AISZoomTransform.clampedScale(0.2), 1)
        XCTAssertEqual(AISZoomTransform.clampedScale(2), 2)
        XCTAssertEqual(AISZoomTransform.clampedScale(8), 5)

        XCTAssertEqual(
            AISZoomTransform.clampedOffset(
                CGSize(width: 400, height: -900),
                scale: 2,
                viewport: CGSize(width: 300, height: 600)
            ),
            CGSize(width: 150, height: -300)
        )
        XCTAssertEqual(
            AISZoomTransform.clampedOffset(
                CGSize(width: 40, height: 80),
                scale: 1,
                viewport: CGSize(width: 300, height: 600)
            ),
            .zero
        )
    }

    func testDismissGestureRequiresDownwardUnzoomedVerticalDrag() {
        XCTAssertTrue(
            AISMediaDismissalGesture.shouldDismiss(
                translation: CGSize(width: 8, height: 100),
                predictedTranslation: CGSize(width: 10, height: 120),
                isZoomed: false
            )
        )
        XCTAssertTrue(
            AISMediaDismissalGesture.shouldDismiss(
                translation: CGSize(width: 8, height: 70),
                predictedTranslation: CGSize(width: 10, height: 180),
                isZoomed: false
            )
        )
        XCTAssertFalse(
            AISMediaDismissalGesture.shouldDismiss(
                translation: CGSize(width: 130, height: 110),
                predictedTranslation: CGSize(width: 210, height: 200),
                isZoomed: false
            )
        )
        XCTAssertFalse(
            AISMediaDismissalGesture.shouldDismiss(
                translation: CGSize(width: 5, height: -120),
                predictedTranslation: CGSize(width: 5, height: -200),
                isZoomed: false
            )
        )
        XCTAssertFalse(
            AISMediaDismissalGesture.shouldDismiss(
                translation: CGSize(width: 5, height: 140),
                predictedTranslation: CGSize(width: 5, height: 220),
                isZoomed: true
            )
        )
    }

    private func makeItem(id: String) -> AISMediaViewerItem {
        AISMediaViewerItem(
            id: id,
            originalURL: URL(string: "https://example.com/\(id).jpg")!
        )
    }

    private func decodeReferences(
        _ objects: [[String: Any]]
    ) throws -> [AISSharedInputMaterial] {
        try JSONDecoder().decode(
            [AISSharedInputMaterial].self,
            from: JSONSerialization.data(withJSONObject: objects)
        )
    }
}
