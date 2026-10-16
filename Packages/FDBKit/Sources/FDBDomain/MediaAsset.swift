import Foundation

public enum MediaAssetTag {}
public typealias MediaAssetID = EntityID<MediaAssetTag>

/// A managed image. The stored file is named by its SHA-256, so the same image always maps to the same asset.
public struct MediaAsset: Identifiable, Hashable, Sendable {
    public let sha256: String
    public let fileExtension: String
    public let mimeType: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let byteSize: Int
    public let createdAt: Date

    public init(
        sha256: String,
        fileExtension: String,
        mimeType: String,
        pixelWidth: Int,
        pixelHeight: Int,
        byteSize: Int,
        createdAt: Date = Date()
    ) {
        self.sha256 = sha256
        self.fileExtension = fileExtension
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteSize = byteSize
        self.createdAt = createdAt
    }

    /// Identity follows the content: the first 16 bytes of the hash, written as a UUID.
    public var id: MediaAssetID {
        let hex = Array(sha256)
        let text = String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-" + String(hex[12..<16])
            + "-" + String(hex[16..<20]) + "-" + String(hex[20..<32])
        return MediaAssetID(rawValue: UUID(uuidString: text) ?? UUID())
    }

    /// The managed file name, relative to media/originals. It is never chosen by the user.
    public var fileName: String {
        "\(sha256).\(fileExtension)"
    }
}
