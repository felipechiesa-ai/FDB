import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FDBLibrary

@Suite struct MediaImporterTests {
    @Test func importsPNGAndKeepsAManagedCopy() throws {
        let folder = try makeTestLibraryFolder()
        let source = folder.url.appendingPathComponent("source.png")
        try writeTestImage(to: source, width: 40, height: 30)

        let asset = try MediaImporter(folder: folder).importImage(from: source)

        #expect(asset.mimeType == "image/png")
        #expect(asset.pixelWidth == 40)
        #expect(asset.pixelHeight == 30)
        #expect(FileManager.default.fileExists(atPath: folder.originalsURL.appendingPathComponent(asset.fileName).path))
    }

    @Test func rejectsFilesThatAreNotImages() throws {
        let folder = try makeTestLibraryFolder()
        let source = folder.url.appendingPathComponent("fake.png")
        try Data("not an image".utf8).write(to: source)

        #expect(throws: MediaError.unreadable) {
            try MediaImporter(folder: folder).importImage(from: source)
        }
    }

    @Test func rejectsUnsupportedFormats() throws {
        let folder = try makeTestLibraryFolder()
        let source = folder.url.appendingPathComponent("animation.gif")
        try writeTestImage(to: source, width: 10, height: 10, type: "com.compuserve.gif")

        #expect(throws: MediaError.unsupportedType) {
            try MediaImporter(folder: folder).importImage(from: source)
        }
    }

    @Test func rejectsImagesOverThePixelLimit() throws {
        let folder = try makeTestLibraryFolder()
        let source = folder.url.appendingPathComponent("wide.png")
        try writeTestImage(to: source, width: 200, height: 50)
        let importer = MediaImporter(folder: folder, limits: MediaLimits(maxByteSize: 25_000_000, maxPixelDimension: 100))

        #expect(throws: MediaError.tooManyPixels) {
            try importer.importImage(from: source)
        }
    }

    @Test func stripsGPSMetadataOnImport() throws {
        let folder = try makeTestLibraryFolder()
        let source = folder.url.appendingPathComponent("located.jpg")
        try writeTestImage(to: source, width: 20, height: 20, type: "public.jpeg", properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 34.6, kCGImagePropertyGPSLatitudeRef: "S"]
        ])

        let asset = try MediaImporter(folder: folder).importImage(from: source)

        let stored = folder.originalsURL.appendingPathComponent(asset.fileName)
        let imageSource = try #require(CGImageSourceCreateWithURL(stored as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] ?? [:]
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func storingTheSameImageTwiceKeepsOneFile() throws {
        let folder = try makeTestLibraryFolder()
        let source = folder.url.appendingPathComponent("source.png")
        try writeTestImage(to: source, width: 16, height: 16)

        let first = try MediaImporter(folder: folder).importImage(from: source)
        let second = try MediaImporter(folder: folder).importImage(from: source)

        #expect(first.id == second.id)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.originalsURL.path)
        #expect(files.filter { $0.hasSuffix(".png") }.count == 1)
    }

    @Test func thumbnailsStillRenderAfterTheSourceFileIsRemoved() throws {
        let folder = try makeTestLibraryFolder()
        let source = folder.url.appendingPathComponent("source.png")
        try writeTestImage(to: source, width: 300, height: 200)
        let asset = try MediaImporter(folder: folder).importImage(from: source)

        try FileManager.default.removeItem(at: source)
        let thumbnail = try MediaThumbnails(folder: folder).thumbnail(fileName: asset.fileName, maxPixelSize: 120)

        #expect(max(thumbnail.width, thumbnail.height) <= 120)
    }
}
