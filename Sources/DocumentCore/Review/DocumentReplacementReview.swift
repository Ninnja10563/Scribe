import Foundation

public extension ScribeDocument {
    /// Replace a semantic range with inline content. Retained deletions and
    /// original paragraph boundaries remain independently reviewable; one's own
    /// draft boundaries are joined without ever exposing generated list labels.
    @discardableResult mutating func replaceTrackedRange(_ anchor: TextAnchor, with inserted: [TextRun],
                                                         author: RevisionAuthor, insertedNotes: [DocumentNote] = []) throws -> TextAnchor {
        try NativeFormat.validate(self)
        guard !inserted.contains(where: { $0.text.contains("\n") }),
              let section = sections.firstIndex(where: { $0.paragraphs.contains { $0.id == anchor.paragraphID } }),
              let first = sections[section].paragraphs.firstIndex(where: { $0.id == anchor.paragraphID }),
              let last = sections[section].paragraphs.firstIndex(where: { $0.id == (anchor.endParagraphID ?? anchor.paragraphID) }), first <= last else {
            throw DocumentError.invalid("the tracked replacement must remain within one section and contain inline text")
        }
        let source = paragraphs, index = DocumentTextIndex(paragraphs: source)
        guard let range = index.range(for: anchor),
              sections[section].paragraphs[first...last].allSatisfy({ $0.tableCell == sections[section].paragraphs[first].tableCell && $0.toc == nil }) else {
            throw DocumentError.invalid("the tracked selection crosses a table cell or generated content")
        }
        let endOffset = anchor.endOffset ?? (anchor.offset + anchor.length)
        let positions = Dictionary(uniqueKeysWithValues: index.entries.map { ($0.id, $0.start) })
        var candidate = self, removed: [NSRange] = []
        let insertion = RevisionIdentity(author: author), deletion = RevisionIdentity(author: author)
        let joinedBoundary = RevisionIdentity(author: author)
        var ownBoundaries = 0, insertionOffset = 0
        for position in first...last {
            let paragraph = sections[section].paragraphs[position]
            let start = position == first ? anchor.offset : 0
            let end = position == last ? endOffset : paragraph.text.utf16.count
            let selected = NSRange(location: start, length: end - start)
            var offset = 0
            for run in paragraph.runs {
                let extent = NSRange(location: offset, length: run.text.utf16.count)
                let overlap = NSIntersectionRange(selected, extent)
                if overlap.length > 0, run.review?.insertion?.author.id == author.id, run.review?.deletion == nil {
                    removed.append(NSRange(location: positions[paragraph.id]! + overlap.location, length: overlap.length))
                }
                offset += extent.length
            }
            var text = RevisionText(runs: paragraph.runs)
            let caret = try text.replace(selected, with: [], insertion: insertion, deletion: deletion)
            candidate.sections[section].paragraphs[position].runs = text.runs.isEmpty ? [TextRun("", format: paragraph.runs.first?.format ?? TextFormatting())] : text.runs
            if position == last { insertionOffset = caret }
            else {
                var review = paragraph.breakReview ?? RunReview()
                if review.insertion?.author.id == author.id, review.deletion == nil {
                    // Isolate only these boundaries, even if their original
                    // insertion identity is shared with untouched text.
                    review.insertion = joinedBoundary; ownBoundaries += 1
                } else if review.deletion == nil { review.deletion = deletion }
                candidate.sections[section].paragraphs[position].breakReview = review
            }
        }
        candidate.rebaseReviewComments(from: source, removing: removed)
        let beforeInsertion = candidate.paragraphs
        let insertionLocation = NSMaxRange(range) - removed.reduce(0) { $0 + $1.length }
        var text = RevisionText(runs: candidate.sections[section].paragraphs[last].runs)
        _ = try text.replace(NSRange(location: insertionOffset, length: 0), with: inserted, insertion: insertion, deletion: deletion)
        if !text.runs.isEmpty { candidate.sections[section].paragraphs[last].runs = text.runs }
        let insertedLength = inserted.reduce(0) { $0 + $1.text.utf16.count }
        candidate.transformCommentAnchors(from: beforeInsertion,
            replacing: NSRange(location: insertionLocation, length: 0), withLength: insertedLength)
        for note in insertedNotes {
            if let existing = candidate.notes.first(where: { $0.id == note.id }) {
                guard existing == note else { throw DocumentError.invalid("the inserted note identity conflicts with an existing note") }
            } else { candidate.notes.append(note) }
        }
        candidate.reconcileNotes()
        if ownBoundaries > 0 {
            // One atomic decision joins all selected draft boundaries. The
            // existing join guard protects unrelated paragraph-format history.
            try candidate.resolveRevision(joinedBoundary.id, accepting: false)
        }
        try NativeFormat.validate(candidate)
        let caret = insertionLocation + insertedLength - ownBoundaries
        guard let result = DocumentTextIndex(paragraphs: candidate.paragraphs).anchor(for: NSRange(location: caret, length: 0)) else {
            throw DocumentError.invalid("the tracked replacement caret is unavailable")
        }
        self = candidate
        return result
    }
}
