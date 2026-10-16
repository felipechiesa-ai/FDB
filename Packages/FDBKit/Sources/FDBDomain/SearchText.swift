import Foundation

/// Matching keys only. Display text is stored unchanged, and identity never depends on these keys.
public enum SearchText {
    /// Lowercased, diacritic-free form: "José Núñez" becomes "jose nunez".
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension String {
    /// Whitespace and newlines removed from both ends.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
