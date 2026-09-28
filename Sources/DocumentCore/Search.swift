import Foundation

public struct SearchOptions: Sendable {
    public var matchCase = false
    public var wholeWord = false
    public init(matchCase: Bool = false, wholeWord: Bool = false) {
        self.matchCase = matchCase; self.wholeWord = wholeWord
    }
}
public enum DocumentSearch {
    /// UTF-16 ranges match AppKit selection and attributed-string indexing.
    public static func matches(in text: String, query: String, options: SearchOptions = SearchOptions()) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let escaped = NSRegularExpression.escapedPattern(for: query)
        let pattern = options.wholeWord ? "(?<![\\p{L}\\p{M}\\p{N}_])(?:\(escaped))(?![\\p{L}\\p{M}\\p{N}_])" : escaped
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options.matchCase ? [] : [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)
    }
}
public struct DocumentStatistics: Equatable, Sendable {
    public let words: Int
    public let characters: Int
    public let charactersWithoutSpaces: Int
    public let paragraphs: Int
    public init(text: String) {
        characters = text.count
        charactersWithoutSpaces = text.filter { !$0.isWhitespace }.count
        paragraphs = text.isEmpty ? 0 : text.components(separatedBy: "\n").count
        let regex = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}][\\p{L}\\p{M}\\p{N}]*(?:[’'-][\\p{L}\\p{N}][\\p{L}\\p{M}\\p{N}]*)*")
        words = regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

public struct GrammarIssue: Sendable {
    public var anchor: TextAnchor
    public var message: String
    public var replacements: [String]
}
public protocol GrammarEngine: Sendable {
    func check(paragraph: Paragraph, language: String) async throws -> [GrammarIssue]
}
