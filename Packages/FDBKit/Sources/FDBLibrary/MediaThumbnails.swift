import CoreGraphics
import Foundation
import ImageIO

/// Thumbnails generated from managed originals and cached by content hash. The cache is derived and can be rebuilt.
public struct MediaThumbnails: Sendable {
    public let folder: LibraryFolder

    public init(folder: LibraryFolder) {
        self.folder = folder
    }

    public func thumbnail(fileName: String, maxPixelSize: Int) throws -> CGImage {
        let cacheURL = folder.thumbnailsURL.appendingPathComponent("\(fileName)-\(maxPixelSize).png")
        if let cached = Self.readImage(at: cacheURL) {
            return cached
        }
        let originalURL = folder.originalsURL.appendingPathComponent(fileName)
        guard let source = CGImageSourceCreateWithURL(originalURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
              ] as CFDictionary) else {
            throw MediaError.unreadable
        }
        Self.writeImage(image, to: cacheURL)
        return image
    }

    private static func readImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Best effort: a missing cache entry only costs a re-render.
    private static func writeImage(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
    }
}
