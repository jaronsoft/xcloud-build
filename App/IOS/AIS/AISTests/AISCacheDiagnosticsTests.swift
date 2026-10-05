import CryptoKit
import UIKit
import XCTest
@testable import AIS

final class AISCacheDiagnosticsTests: XCTestCase {
    func testCancellationClassifierCoversSwiftAndURLCancellation() {
        XCTAssertTrue(
            AISErrorClassifier.isCancellation(CancellationError())
        )
        XCTAssertTrue(
            AISErrorClassifier.isCancellation(URLError(.cancelled))
        )
        XCTAssertFalse(
            AISErrorClassifier.isCancellation(URLError(.timedOut))
        )
    }

    func testCancelledQuoteGuardPreventsStaleResultApplication() {
        var appliedStaleQuote = false

        XCTAssertThrowsError(
            try AISRequestResultGuard.ensureCurrent(isCancelled: true)
        ) { error in
            XCTAssertTrue(AISErrorClassifier.isCancellation(error))
        }
        if (try? AISRequestResultGuard.ensureCurrent(isCancelled: true)) != nil {
            appliedStaleQuote = true
        }

        XCTAssertFalse(appliedStaleQuote)
        XCTAssertNoThrow(
            try AISRequestResultGuard.ensureCurrent(isCancelled: false)
        )
    }

    func testRegionScopedImageCacheIsTaggedWithoutDuplicatingPhysicalFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = try XCTUnwrap(
            URL(string: "https://cdn.jaronsoft.com/ais/test-cache.png")
        )
        AISMediaRegionRequestContext.install(.international)
        let cacheKey = "global|\(url.absoluteString)"
        let filename = SHA256.hash(data: Data(cacheKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 4, height: 3)
        ).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        }
        try XCTUnwrap(image.pngData()).write(
            to: directory.appending(path: filename)
        )

        let cache = AISImageCache(cacheDirectory: directory)
        _ = try await cache.data(
            for: url,
            module: .tasks,
            preset: .thumbnail
        )
        _ = try await cache.data(
            for: url,
            module: .galleryTemplates,
            preset: .thumbnail
        )

        let statistics = await cache.statistics()
        XCTAssertEqual(statistics.fileCount, 1)
        XCTAssertGreaterThan(statistics.physicalByteCount, 0)
        XCTAssertEqual(
            statistics.modules.first { $0.module == .tasks }?.fileCount,
            1
        )
        XCTAssertEqual(
            statistics.modules.first {
                $0.module == .galleryTemplates
            }?.fileCount,
            1
        )

        await cache.clear(module: .tasks)
        let sharedStatistics = await cache.statistics()
        XCTAssertEqual(sharedStatistics.fileCount, 1)
        XCTAssertEqual(
            sharedStatistics.modules.first { $0.module == .tasks }?.fileCount,
            0
        )

        await cache.clear(module: .galleryTemplates)
        let emptyStatistics = await cache.statistics()
        XCTAssertEqual(emptyStatistics.fileCount, 0)
    }

    @MainActor
    func testDiagnosticSanitizationRemovesCredentialsAndEmail() {
        let value = NetworkDiagnosticsStore.sanitizedMessage(
            "Bearer secret.token.value user@example.com"
        )

        XCTAssertFalse(value.contains("secret.token.value"))
        XCTAssertFalse(value.contains("user@example.com"))
        XCTAssertTrue(value.contains("[REDACTED]"))
        XCTAssertTrue(value.contains("[REDACTED_EMAIL]"))
    }

    @MainActor
    func testExportedDiagnosticLogUsesConsoleFriendlyTextFormat() async throws {
        let generatedURL = await NetworkDiagnosticsStore.shared
            .generateLogFile()
        let fileURL = try XCTUnwrap(generatedURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertEqual(fileURL.pathExtension, "log")
        XCTAssertTrue(
            fileURL.lastPathComponent.hasPrefix("ais_diagnostics_")
        )
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("Generated At:"))
        XCTAssertTrue(content.contains("[SECTION 4: IMAGE CACHE EVENTS"))
        XCTAssertTrue(content.contains("[SECTION 5: NETWORK REQUEST LOGS"))
        XCTAssertFalse(content.contains("Bearer secret"))
    }
}
