import Foundation

public struct Country: Identifiable, Hashable, Sendable {
    public var id: CountryID
    /// ISO 3166-1 alpha-2 code. An external code, never the identity.
    public var isoCode: String
    public var displayName: String

    public init(id: CountryID, isoCode: String, displayName: String) {
        self.id = id
        self.isoCode = isoCode
        self.displayName = displayName
    }
}
