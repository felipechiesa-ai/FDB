import Foundation

/// Rule violations the user can fix. Each case maps to one clear message.
public enum DomainError: Error, Equatable, Sendable {
    case emptyName
    case emptyTeamName
    case invalidHeight
    case invalidInterval
    case invalidShirtNumber
    case duplicatePosition
    case multiplePrimaryPositions
    case duplicateCitizenship
    case overlappingMembership
}

extension DomainError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a name."
        case .emptyTeamName: "Enter a team name."
        case .invalidHeight: "Height must be between 50 and 260 cm."
        case .invalidInterval: "The end date must be after the start date."
        case .invalidShirtNumber: "Shirt numbers must be between 1 and 99."
        case .duplicatePosition: "A position can be listed only once."
        case .multiplePrimaryPositions: "A player can have only one primary position."
        case .duplicateCitizenship: "A citizenship can be listed only once."
        case .overlappingMembership: "This player already has a membership in this team for those dates."
        }
    }
}
