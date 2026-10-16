import CoreGraphics
import CryptoKit
import FDBDomain
import Foundation
import ImageIO

public struct MediaLimits: Sendable {
    public var maxByteSize: Int
    public var maxPixelDimension: Int

    public init(maxByteSize: Int = 25_000_000, maxPixelDimension: Int = 6_000) {
        self.maxByteSize = maxByteSize
        self.maxPixelDimension = maxPixelDimension
    }
}

public enum MediaError: Error, Equatable, Sendable {
    case unreadable
    case unsupportedType
    case tooLarge
    case tooManyPixels
}

extension MediaError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreadable: "That file could not be read as an image."
        case .unsupportedType: "Choose a JPEG or PNG image."
        case .tooLarge: "The image is larger than 25 MB."
        case .tooManyPixels: "The image is larger than 6000 pixels on one side."
        }
    }
}

/// Validates a chosen image and stores a metadata-free copy in the managed originals folder.
public struct MediaImporter: Sendable {
    public let folder: LibraryFolder
    public let limits: MediaLimits

    public init(folder: LibraryFolder, limits: MediaLimits = MediaLimits()) {
        self.folder = folder
        self.limits = limits
    }

    public func importImage(from source: URL) throws -> MediaAsset {
        let size = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int) ?? 0
        guard size > 0 else { throw MediaError.unreadable }
        guard size <= limits.maxByteSize else { throw MediaError.tooLarge }

        let data = try Data(contentsOf: source)
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(imageSource) as String? else {
            throw MediaError.unreadable
        }
        guard type == "public.png" || type == "public.jpeg" else { throw MediaError.unsupportedType }
        guard let decoded = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw MediaError.unreadable
        }
        let largestSide = max(decoded.width, decoded.height)
        guard largestSide <= limits.maxPixelDimension else { throw MediaError.tooManyPixels }

        // Rendering with the orientation applied and re-encoding drops EXIF, GPS, and other metadata.
        let oriented = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: largestSide
        ] as CFDictionary) ?? decoded
        let isPNG = type == "public.png"
        let encoded = try Self.encode(oriented, asPNG: isPNG)
        let asset = MediaAsset(
            sha256: SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined(),
            fileExtension: isPNG ? "png" : "jpg",
            mimeType: isPNG ? "image/png" : "image/jpeg",
            pixelWidth: oriented.width,
            pixelHeight: oriented.height,
            byteSize: encoded.count
        )
        try store(encoded, as: asset.fileName)
        return asset
    }

    private static func encode(_ image: CGImage, asPNG: Bool) throws -> Data {
        let output = NSMutableData()
        let uniformType = (asPNG ? "public.png" : "public.jpeg") as CFString
        guard let destination = CGImageDestinationCreateWithData(output, uniformType, 1, nil) else {
            throw MediaError.unreadable
        }
        let options = asPNG ? nil : [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { throw MediaError.unreadable }
        return output as Data
    }

    /// Writes through a temporary file and then moves it into place. A file with the same hash is kept as it is.
    private func store(_ data: Data, as fileName: String) throws {
        let finalURL = folder.originalsURL.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: finalURL.path) else { return }
        let temporaryURL = folder.originalsURL.appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL)
        try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
    }
}
