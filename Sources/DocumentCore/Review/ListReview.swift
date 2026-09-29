import Foundation

extension ParagraphFormattingReview {
    /// A continuation shares the original formatting decisions, but a restart
    /// and page-break-before belong only to the first item of a split.
    func listContinuation() -> ParagraphFormattingReview? {
        func projected(_ source: ParagraphRevisionState) -> ParagraphRevisionState {
            var state = source; state.pageBreakBefore = false; state.list?.restart = nil; return state
        }
        var review = self; review.base = projected(base)
        review.changes = changes.compactMap { source in
            var change = source; change.before = projected(source.before); change.after = projected(source.after)
            return change.before == change.after ? nil : change
        }
        return review.pendingIDs.isEmpty ? nil : review
    }
}

public extension ScribeDocument {
    /// Return in a list is a semantic split. Generated numbering never enters
    /// revision text, and selected original content is retained as a deletion.
    @discardableResult mutating func splitTrackedListItem(id: UUID, range: NSRange, author: RevisionAuthor) throws -> UUID {
        try NativeFormat.validate(self)
        guard let section = sections.firstIndex(where: { $0.paragraphs.contains { $0.id == id } }),
              let index = sections[section].paragraphs.firstIndex(where: { $0.id == id }),
              sections[section].paragraphs[index].list != nil else { throw DocumentError.invalid("the list item is unavailable") }
        let original = sections[section].paragraphs[index], length = original.text.utf16.count
        guard range.location >= 0, range.length >= 0, range.location <= length, range.length <= length - range.location else {
            throw DocumentError.invalid("the list selection is unavailable")
        }
        var boundaries: Set<Int> = [0], position = 0
        for character in original.text { position += character.utf16.count; boundaries.insert(position) }
        guard boundaries.contains(range.location), boundaries.contains(NSMaxRange(range)) else { throw DocumentError.invalid("the list selection splits a character") }
        var candidate = self
        if length == 0 {
            guard let target = candidate.splitListItem(id: id, range: range) else { throw DocumentError.invalid("the list cannot be changed") }
            try candidate.recordParagraphFormattingChanges(from: self, identity: .init(author: author))
            self = candidate; return target
        }
        let insertion = RevisionIdentity(author: author), deletion = RevisionIdentity(author: author)
        var text = RevisionText(runs: original.runs)
        let split = try text.replace(range, with: [], insertion: insertion, deletion: deletion)
        // Only removal of one's own draft changes markup coordinates. Original
        // selected content stays in place until its deletion is accepted.
        let start = DocumentTextIndex(paragraphs: paragraphs).range(for: .init(paragraphID: id, offset: 0, length: 0))!.location
        var removed: [NSRange] = [], offset = 0
        for run in original.runs {
            let extent = NSRange(location: offset, length: run.text.utf16.count)
            let overlap = NSIntersectionRange(range, extent)
            if overlap.length > 0, run.review?.insertion?.author.id == author.id, run.review?.deletion == nil {
                removed.append(NSRange(location: start + overlap.location, length: overlap.length))
            }
            offset += extent.length
        }
        candidate.sections[section].paragraphs[index].runs = text.runs.isEmpty ? [TextRun("", format: original.runs.first?.format ?? TextFormatting())] : text.runs
        candidate.rebaseReviewComments(from: paragraphs, removing: removed)
        // Even replacing an entire draft item with Return creates a paragraph
        // separator; the normal empty-item command would instead outdent it.
        let target: UUID
        if candidate.sections[section].paragraphs[index].text.isEmpty {
            let before = candidate.paragraphs
            var next = candidate.sections[section].paragraphs[index]
            next.id = UUID(); next.pageBreakBefore = false; next.list?.restart = nil; next.toc = nil
            next.formattingReview = next.formattingReview?.listContinuation()
            candidate.sections[section].paragraphs.insert(next, at: index + 1)
            target = next.id
            let location = DocumentTextIndex(paragraphs: before).range(for: .init(paragraphID: id, offset: 0, length: 0))!.location
            candidate.transformCommentAnchors(from: before, replacing: NSRange(location: location, length: 0), withLength: 1)
        } else {
            guard let next = candidate.splitListItem(id: id, range: NSRange(location: split, length: 0)) else { throw DocumentError.invalid("the list cannot be split") }
            target = next
        }
        var separator = RunReview(); separator.insertion = insertion
        candidate.sections[section].paragraphs[index].breakReview = separator
        candidate.reconcileNotes()
        try NativeFormat.validate(candidate)
        self = candidate
        return target
    }
}
