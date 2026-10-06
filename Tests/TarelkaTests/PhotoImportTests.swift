import AppKit
import Foundation
import Testing
@testable import Tarelka

struct PhotoImportTests {
    @Test func oversizedFileIsRejectedBeforeDecoding() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: 40 * 1024 * 1024 + 1)
        try file.close()

        do {
            _ = try PhotoLoader.load(url: url)
            Issue.record("An oversized photo was accepted")
        } catch PhotoLoader.PhotoError.tooLarge {
            // The sparse file must be rejected by size, before ImageIO attempts to decode it.
        } catch {
            Issue.record("Expected the photo size error, got: \(error)")
        }
    }

    @Test func validImageIsNormalizedToJpeg() throws {
        let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                                  bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(image.representation(using: .png, properties: [:]))
        let result = try PhotoLoader.prepare(png)
        #expect(result.starts(with: [0xFF, 0xD8]))
        #expect(result.count < png.count + 10_000)
    }
}
