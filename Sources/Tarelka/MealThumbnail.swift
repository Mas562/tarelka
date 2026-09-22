import SwiftUI
import ImageIO

/// Saved photos have unique filenames. Decode small previews off the main actor and reuse them while scrolling.
actor MealThumbnailCache {
    static let shared = MealThumbnailCache()
    private let images = NSCache<NSString, CGImage>()

    init() {
        images.countLimit = 128
        images.totalCostLimit = 32 * 1024 * 1024
    }

    func image(url: URL, pixels: Int) -> CGImage? {
        let key = "\(url.path)#\(pixels)" as NSString
        if let image = images.object(forKey: key) { return image }
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary), !Task.isCancelled else { return nil }
        images.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}

struct MealThumbnail: View {
    let url: URL?
    var symbol = "fork.knife"
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    private struct Request: Equatable {
        let url: URL?
        let pixels: Int
    }
    var body: some View {
        let request = Request(url: url, pixels: Int(ceil(84 * min(max(displayScale, 1), 4))))
        ZStack {
            Palette.mint.opacity(0.5)
            if let image {
                Image(decorative: image, scale: displayScale).resizable().scaledToFill()
            } else {
                Image(systemName: symbol).font(.system(size: 23, weight: .light)).foregroundStyle(Palette.green)
            }
        }.frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 13))
            .task(id: request) {
                image = nil
                guard let url = request.url else { return }
                let result = await MealThumbnailCache.shared.image(url: url, pixels: request.pixels)
                guard !Task.isCancelled else { return }
                image = result
            }
    }
}
