import Testing
import UIKit
@testable import AIS

struct AISOpaqueImageTests {
    @Test
    func removesPremultipliedAlphaFromShareArtwork() {
        let source = UIGraphicsImageRenderer(
            size: CGSize(width: 20, height: 30)
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }

        let sourceAlphaInfo = source.cgImage?.alphaInfo
        #expect(
            sourceAlphaInfo == .premultipliedFirst
                || sourceAlphaInfo == .premultipliedLast
        )

        let opaque = source.aisOpaqueImage()
        let alphaInfo = opaque.cgImage?.alphaInfo
        #expect(
            alphaInfo == CGImageAlphaInfo.none
                || alphaInfo == .noneSkipFirst
                || alphaInfo == .noneSkipLast
        )
        #expect(opaque.size == source.size)
        #expect(opaque.scale == source.scale)
    }

    @Test
    func shareArtworkFollowsOriginalImageAspectRatio() {
        #expect(
            AISShareArtworkLayout.imageHeight(
                width: 720,
                imageSize: CGSize(width: 1_600, height: 900)
            ) == 405
        )
        #expect(
            AISShareArtworkLayout.imageHeight(
                width: 720,
                imageSize: CGSize(width: 1_024, height: 1_536)
            ) == 1_080
        )
    }
}
