import AppKit
import ImageIO
import UniformTypeIdentifiers

enum PhotoLoader {
    static func load(url: URL, maxPixelSize: Int = 1600) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 40 * 1024 * 1024 else { throw PhotoError.tooLarge }
        return try prepare(Data(contentsOf: url), maxPixelSize: maxPixelSize)
    }
    /// Applies EXIF orientation, resizes, and re-encodes pixels to remove GPS and other source metadata.
    static func prepare(_ data: Data, maxPixelSize: Int = 1600) throws -> Data {
        guard data.count <= 40 * 1024 * 1024 else { throw PhotoError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw PhotoError.unreadable }
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
