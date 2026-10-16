import Foundation

/// The on-disk layout of one library: database, managed originals, thumbnail cache, and manifest.
public struct LibraryFolder: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var databaseURL: URL {
        url.appendingPathComponent("database.sqlite")
    }

    public var manifestURL: URL {
        url.appendingPathComponent("manifest.json")
    }

    public var originalsURL: URL {
        url.appendingPathComponent("media/originals", isDirectory: true)
    }

    public var thumbnailsURL: URL {
        url.appendingPathComponent("media/thumbnails", isDirectory: true)
    }

    /// Creates the folders and, the first time, the manifest.
    public func prepare() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: originalsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: manifestURL.path) {
            let manifest = LibraryManifest(
                formatVersion: LibraryManifest.currentFormatVersion,
                libraryID: UUID(),
                createdAt: Date()
            )
            try manifest.write(to: manifestURL)
        }
    }
}

/// Identifies a library and its on-disk format.
public struct LibraryManifest: Codable, Sendable, Equatable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var libraryID: UUID
    public var createdAt: Date

    public init(formatVersion: Int, libraryID: UUID, createdAt: Date) {
        self.formatVersion = formatVersion
        self.libraryID = libraryID
        self.createdAt = createdAt
    }

    public func write(to url: URL) throws {
        try JSONCoding.encoder().encode(self).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> LibraryManifest {
        try JSONCoding.decoder().decode(LibraryManifest.self, from: Data(contentsOf: url))
    }
}

/// Shared JSON settings: ISO 8601 dates, sorted keys, and readable output.
enum JSONCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
