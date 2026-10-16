import CryptoKit
import Foundation

/// RFC 4122 version 5 UUIDs under a fixed FDB namespace. Seeded rows keep the same ID in every library.
enum DeterministicID {
    private static let namespace = UUID(uuidString: "3F8C2A7E-5B1D-4C9E-9A61-0D7E2B4F8A10")!

    static func countryUUID(isoCode: String) -> UUID {
        uuid(name: "iso3166-1:\(isoCode)")
    }

    static func uuid(name: String) -> UUID {
        var input = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        input.append(Data(name.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
