import Foundation

/// Paragraph properties have their own history; text and object payloads are
/// deliberately excluded so rejecting formatting cannot restore deleted text.
public struct ParagraphRevisionState: Codable, Equatable, Sendable {
    public var styleID: String
    public var formatting: ParagraphFormatting?
    public var list: ListDescriptor?
    public var pageBreakBefore: Bool
    public init(_ paragraph: Paragraph) {
        styleID = paragraph.styleID; formatting = paragraph.formatting
        list = paragraph.list; pageBreakBefore = paragraph.pageBreakBefore
    }
    public func apply(to paragraph: inout Paragraph) {
        paragraph.styleID = styleID; paragraph.formatting = formatting
        paragraph.list = list; paragraph.pageBreakBefore = pageBreakBefore
    }
}

public struct ParagraphFormattingRevision: Codable, Equatable, Sendable {
    public var identity: RevisionIdentity
    public var before: ParagraphRevisionState
    public var after: ParagraphRevisionState
    /// Freeze the comparison defaults, not the named style itself. Otherwise a
    /// later style-definition edit would change which fields this edit changed.
    public var inheritedBefore: ParagraphFormatting
    public var inheritedAfter: ParagraphFormatting
    public var accepted = false
    public init(identity: RevisionIdentity, before: ParagraphRevisionState, after: ParagraphRevisionState,
                inheritedBefore: ParagraphFormatting, inheritedAfter: ParagraphFormatting) {
        self.identity = identity; self.before = before; self.after = after
        self.inheritedBefore = inheritedBefore; self.inheritedAfter = inheritedAfter
    }
}

public struct ParagraphFormattingReview: Codable, Equatable, Sendable {
    public var base: ParagraphRevisionState
    public var inheritedBase: ParagraphFormatting
    public var changes: [ParagraphFormattingRevision] = []
    public init(base: ParagraphRevisionState, inherited: ParagraphFormatting) {
        self.base = base; inheritedBase = inherited
    }
    public var pendingIDs: [UUID] { changes.filter { !$0.accepted }.map { $0.identity.id } }
    public var state: ParagraphRevisionState {
        var value = base, inherited = inheritedBase
        for change in changes {
            if change.before.styleID != change.after.styleID {
                value.styleID = change.after.styleID; inherited = change.inheritedAfter
            }
            if change.before.formatting != change.after.formatting {
                if let after = change.after.formatting {
                    let before = change.before.formatting ?? change.inheritedBefore
                    let defaults = value.styleID == change.before.styleID ? change.inheritedBefore : inherited
                    value.formatting = (value.formatting ?? defaults).applyingDifference(from: before, to: after)
                } else { value.formatting = nil }
            }
            if change.before.list != change.after.list { value.list = change.after.list }
            if change.before.pageBreakBefore != change.after.pageBreakBefore { value.pageBreakBefore = change.after.pageBreakBefore }
        }
        return value
    }
    public mutating func resolve(_ id: UUID, accepting: Bool) {
        guard let index = changes.firstIndex(where: { $0.identity.id == id && !$0.accepted }) else { return }
        if accepting { changes[index].accepted = true } else { changes.remove(at: index) }
    }
}

extension ParagraphFormatting {
    public func applyingDifference(from before: ParagraphFormatting, to after: ParagraphFormatting) -> ParagraphFormatting {
        var result = self
        if before.alignment != after.alignment { result.alignment = after.alignment }
        if before.lineSpacing != after.lineSpacing { result.lineSpacing = after.lineSpacing }
        if before.lineHeight != after.lineHeight { result.lineHeight = after.lineHeight }
        if before.spaceBefore != after.spaceBefore { result.spaceBefore = after.spaceBefore }
        if before.spaceAfter != after.spaceAfter { result.spaceAfter = after.spaceAfter }
        if before.firstLineIndent != after.firstLineIndent { result.firstLineIndent = after.firstLineIndent }
        if before.headIndent != after.headIndent { result.headIndent = after.headIndent }
        if before.tailIndent != after.tailIndent { result.tailIndent = after.tailIndent }
        return result
    }
}

public extension Paragraph {
    mutating func recordFormattingChange(from original: Paragraph, identity: RevisionIdentity,
                                         inheritedBefore: ParagraphFormatting, inheritedAfter: ParagraphFormatting) throws {
        let before = ParagraphRevisionState(original), after = ParagraphRevisionState(self)
        guard before != after else { return }
        var review = original.formattingReview ?? ParagraphFormattingReview(base: before, inherited: inheritedBefore)
        guard review.changes.count < 1024, !review.changes.contains(where: { $0.identity.id == identity.id }) else {
            throw DocumentError.invalid("too many or duplicate paragraph formatting revisions")
        }
        guard review.state == before else { throw DocumentError.invalid("paragraph formatting history is inconsistent") }
        review.changes.append(.init(identity: identity, before: before, after: after,
                                    inheritedBefore: inheritedBefore, inheritedAfter: inheritedAfter))
        guard review.state == after else { throw DocumentError.invalid("paragraph formatting change cannot be represented without loss") }
        formattingReview = review
    }
}

public extension ScribeDocument {
    /// Match stable paragraph identities across a semantic transaction. New or
    /// removed paragraphs belong to structural review, not formatting history.
    mutating func recordParagraphFormattingChanges(from original: ScribeDocument, identity: RevisionIdentity) throws {
        try NativeFormat.validate(original)
        let old = Dictionary(uniqueKeysWithValues: (original.paragraphs + original.notes.flatMap(\.paragraphs)).map { ($0.id, $0) })
        var candidate = self
        func recording(_ source: [Paragraph]) throws -> [Paragraph] {
            try source.map { paragraph in
                guard let before = old[paragraph.id] else { return paragraph }
                var after = paragraph
                try after.recordFormattingChange(from: before, identity: identity,
                    inheritedBefore: original.style(for: before).paragraph, inheritedAfter: style(for: after).paragraph)
                return after
            }
        }
        for index in candidate.sections.indices { candidate.sections[index].paragraphs = try recording(candidate.sections[index].paragraphs) }
        for index in candidate.notes.indices { candidate.notes[index].paragraphs = try recording(candidate.notes[index].paragraphs) }
        try NativeFormat.validate(candidate)
        self = candidate
    }
}
