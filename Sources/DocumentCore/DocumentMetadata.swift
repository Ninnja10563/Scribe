import Foundation

public enum DocumentMetadata {
    /// Canonical casing for common language/script/region identifiers. `und`
    /// requests automatic detection; this does not claim full registry validation.
    public static func languageIdentifier(_ value: String) throws -> String {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-").split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard value.utf8.count <= 63, let first = parts.first, (2...8).contains(first.count), first.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 8 && $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) } }) else { throw DocumentError.invalid("use a language identifier such as en-AU, fr or zh-Hant-TW") }
        return parts.enumerated().map { index, part in
            if index == 0 { return part.lowercased() }
            if part.count == 2 { return part.uppercased() }
            if part.count == 4 { return part.prefix(1).uppercased() + part.dropFirst().lowercased() }
            return part.lowercased()
        }.joined(separator: "-")
    }
    public static func validateText(_ value: String) throws {
        guard value.utf8.count <= 16_384, value.unicodeScalars.allSatisfy({ scalar in
            scalar.value == 9 || scalar.value == 10 || scalar.value == 13 || (scalar.value >= 32 && scalar.value != 0xFFFE && scalar.value != 0xFFFF)
        }) else { throw DocumentError.invalid("document properties are too long or contain unsupported control characters") }
    }
}
extension ScribeDocument {
    public mutating func setMetadata(title: String, author: String, language: String) throws {
        try DocumentMetadata.validateText(title); try DocumentMetadata.validateText(author)
        let identifier = try DocumentMetadata.languageIdentifier(language)
        self.title = title; self.author = author; self.language = identifier
    }
}
