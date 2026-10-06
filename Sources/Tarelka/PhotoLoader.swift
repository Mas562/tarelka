import AppKit
import ImageIO
import UniformTypeIdentifiers

enum PhotoLoader {
    private static let maxBytes = 40 * 1024 * 1024
    static func performAsync(_ work: @escaping @Sendable () throws -> Data) async throws -> Data {
        let worker = Task.detached(priority: .userInitiated, operation: work)
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }
    static func load(url: URL, maxPixelSize: Int = 1600) throws -> Data {
        try Task.checkCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw PhotoError.unreadable }
        guard let size = values.fileSize, size <= maxBytes else { throw PhotoError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try Task.checkCancellation()
        return try prepare(data, maxPixelSize: maxPixelSize)
    }
    /// Applies EXIF orientation, resizes, and re-encodes pixels to remove GPS and other source metadata.
    static func prepare(_ data: Data, maxPixelSize: Int = 1600) throws -> Data {
        try Task.checkCancellation()
        guard data.count <= maxBytes else { throw PhotoError.tooLarge }
        guard (256...4096).contains(maxPixelSize),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 12_000, height <= 12_000,
              Int64(width) * Int64(height) <= 60_000_000,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw PhotoError.unreadable }
        try Task.checkCancellation()
        // Draw onto opaque white so transparent PNGs have a predictable JPEG background.
        guard let context = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw PhotoError.unreadable }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard let image = context.makeImage() else { throw PhotoError.unreadable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw PhotoError.unreadable }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoError.unreadable }
        try Task.checkCancellation()
        return output as Data
    }
    enum PhotoError: LocalizedError {
        case tooLarge, unreadable
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "Фото слишком большое. Выберите файл до 40 МБ."
            case .unreadable: return "Не удалось открыть фото. Попробуйте JPEG, PNG или HEIC."
            }
        }
    }
}
