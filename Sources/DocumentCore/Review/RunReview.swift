import Foundation

public struct RevisionAuthor: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

public struct RevisionIdentity: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var author: RevisionAuthor
    public var date: Date
    public init(id: UUID = UUID(), author: RevisionAuthor, date: Date = Date()) {
        self.id = id; self.author = author; self.date = date
    }
}

public struct FormattingRevision: Codable, Equatable, Sendable {
    public var identity: RevisionIdentity
    public var before: TextFormatting
    public var after: TextFormatting
    /// Accepted later edits remain in the sequence while earlier edits are pending.
    /// This lets rejecting an older change preserve the author's newer decision.
    public var accepted = false
    public init(identity: RevisionIdentity, before: TextFormatting, after: TextFormatting) {
        self.identity = identity; self.before = before; self.after = after
    }
}

public struct RunReview: Codable, Equatable, Sendable {
    public var insertion: RevisionIdentity?
    public var deletion: RevisionIdentity?
    public var formatting: [FormattingRevision] = []
    public var formattingBase: TextFormatting?
    public init() {}
    public var pendingIDs: [UUID] {
        [insertion?.id, deletion?.id].compactMap { $0 } + formatting.filter { !$0.accepted }.map { $0.identity.id }
    }
    /// Native text systems can normalize redundant attributes. Restore the
    /// semantic overrides when their rendered appearance is unchanged, so a
    /// future style-definition edit does not alter the meaning of old revisions.
    public func preservingFormatting(_ projected: TextFormatting, inheriting style: TextFormatting) -> TextFormatting {
        guard let base = formattingBase else { return projected }
        let expected = formatting.reduce(base) { $0.applyingDifference(from: $1.before, to: $1.after) }
        return expected.materialized(over: style) == projected.materialized(over: style) ? expected : projected
    }
    public var isEmpty: Bool { insertion == nil && deletion == nil && formatting.isEmpty }
}

extension TextFormatting {
    /// Replay only fields changed by this revision. A later size edit must not
    /// accidentally reapply an earlier bold edit that a reviewer has rejected.
    func applyingDifference(from before: TextFormatting, to after: TextFormatting) -> TextFormatting {
        var result = self
        if before.fontFamily != after.fontFamily { result.fontFamily = after.fontFamily }
        if before.fontFace != after.fontFace { result.fontFace = after.fontFace }
        if before.fontSize != after.fontSize { result.fontSize = after.fontSize }
        if before.bold != after.bold { result.bold = after.bold }
        if before.italic != after.italic { result.italic = after.italic }
        if before.underline != after.underline { result.underline = after.underline }
        if before.strikethrough != after.strikethrough { result.strikethrough = after.strikethrough }
        if before.baseline != after.baseline { result.baseline = after.baseline }
        if before.foreground != after.foreground { result.foreground = after.foreground }
        if before.highlight != after.highlight { result.highlight = after.highlight }
        if before.clearHighlight != after.clearHighlight { result.clearHighlight = after.clearHighlight }
        return result
    }
}

public extension ScribeDocument {
    var hasPendingRevisions: Bool {
        (paragraphs + notes.flatMap(\.paragraphs)).contains { paragraph in
            !(paragraph.breakReview?.pendingIDs.isEmpty ?? true) || paragraph.runs.contains { !($0.review?.pendingIDs.isEmpty ?? true) }
        }
    }
}
