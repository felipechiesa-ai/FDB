import CoreGraphics
import Foundation
import FDBLibrary
import ImageIO

/// Writes a small solid-colour image for tests. No real photos are committed.
func writeTestImage(
    to url: URL,
    width: Int,
    height: Int,
    type: String = "public.png",
    properties: [CFString: Any] = [:]
) throws {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

/// A new, empty library folder in the system temporary directory.
func makeTestLibraryFolder() throws -> LibraryFolder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let folder = LibraryFolder(url: url)
    try folder.prepare()
    return folder
}
