import Foundation

public extension ScribeDocument {
    /// Replace a semantic range with inline content. Retained deletions and
    /// original paragraph boundaries remain independently reviewable; one's own
    /// draft boundaries are joined without ever exposing generated list labels.
    @discardableResult mutating func replaceTrackedRange(_ anchor: TextAnchor, with inserted: [TextRun],
                                                         author: RevisionAuthor, insertedNotes: [DocumentNote] = []) throws -> TextAnchor {
        try replaceTrackedRange(anchor, withLines: [inserted], author: author, insertedNotes: insertedNotes)
    }

    /// Multiline typing/plain-text paste inherits the destination paragraph's
    /// properties. All new text and boundaries form one insertion revision.
    @discardableResult mutating func replaceTrackedRange(_ anchor: TextAnchor, withLines lines: [[TextRun]],
                                                         paragraphProperties: [ParagraphRevisionState]? = nil,
                                                         author: RevisionAuthor, insertedNotes: [DocumentNote] = []) throws -> TextAnchor {
        try NativeFormat.validate(self)
        guard !lines.isEmpty, paragraphProperties == nil || paragraphProperties?.count == lines.count,
              !lines.joined().contains(where: { $0.text.contains("\n") }),
              let section = sections.firstIndex(where: { $0.paragraphs.contains { $0.id == anchor.paragraphID } }),
              let first = sections[section].paragraphs.firstIndex(where: { $0.id == anchor.paragraphID }),
              let last = sections[section].paragraphs.firstIndex(where: { $0.id == (anchor.endParagraphID ?? anchor.paragraphID) }), first <= last else {
            throw DocumentError.invalid("the tracked replacement must remain within one section and use separate paragraph fragments")
        }
        let source = paragraphs, index = DocumentTextIndex(paragraphs: source)
        guard let range = index.range(for: anchor),
              sections[section].paragraphs[first...last].allSatisfy({ $0.tableCell == sections[section].paragraphs[first].tableCell && $0.toc == nil }) else {
            throw DocumentError.invalid("the tracked selection crosses a table cell or generated content")
        }
        let endOffset = anchor.endOffset ?? (anchor.offset + anchor.length)
        let positions = Dictionary(uniqueKeysWithValues: index.entries.map { ($0.id, $0.start) })
        var candidate = self, removed: [NSRange] = []
        let group: UUID? = paragraphProperties == nil ? nil : UUID()
        let insertion = RevisionIdentity(author: author, groupID: group), deletion = RevisionIdentity(author: author)
        let paragraphInsertion = RevisionIdentity(author: author, date: insertion.date, groupID: group)
        let joinedBoundary = RevisionIdentity(author: author)
        var ownBoundaries = 0
        var groupedJoins: [(Int, RevisionIdentity)] = []
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
            _ = try text.replace(selected, with: [], insertion: insertion, deletion: deletion)
            candidate.sections[section].paragraphs[position].runs = text.runs.isEmpty ? [TextRun("", format: paragraph.runs.first?.format ?? TextFormatting())] : text.runs
            if position < last {
                var review = paragraph.breakReview ?? RunReview()
                if review.insertion?.author.id == author.id, review.deletion == nil {
                    // Isolate only these boundaries, even if their original
                    // insertion identity is shared with untouched text.
                    if let original = review.insertion, original.groupID != nil { groupedJoins.append((position, original)) }
                    review.insertion = joinedBoundary; ownBoundaries += 1
                } else if review.deletion == nil { review.deletion = deletion }
                candidate.sections[section].paragraphs[position].breakReview = review
            }
        }
        for (position, identity) in groupedJoins {
            try candidate.prepareGroupedDraftJoin(section: section, index: position, insertion: identity)
        }
        candidate.rebaseReviewComments(from: source, removing: removed)
        candidate.reconcileNotes()
        if ownBoundaries > 0 {
            // Resolve draft joins before adding the paste's formatting history.
            // Existing, unrelated paragraph review remains protected.
            try candidate.resolveRevision(joinedBoundary.id, accepting: false)
        }
        let beforeInsertion = candidate.paragraphs
        let insertionLocation = NSMaxRange(range) - removed.reduce(0) { $0 + $1.length } - ownBoundaries
        guard let insertionAnchor = DocumentTextIndex(paragraphs: beforeInsertion).anchor(for: NSRange(location: insertionLocation, length: 0)),
              let insertionIndex = candidate.sections[section].paragraphs.firstIndex(where: { $0.id == insertionAnchor.paragraphID }) else {
            throw DocumentError.invalid("the tracked insertion location is unavailable")
        }
        let destination = candidate.sections[section].paragraphs[insertionIndex]
        let originalDestination = sections[section].paragraphs[last]
        let parts = try RevisionText(runs: destination.runs).partition(at: insertionAnchor.offset)
        var additions: [Paragraph] = []
        for (line, content) in lines.enumerated() {
            var paragraph = destination
            if line > 0 {
                paragraph.id = UUID(); paragraph.pageBreakBefore = false; paragraph.list?.restart = nil
                paragraph.formattingReview = paragraph.formattingReview?.paragraphContinuation()
            }
            if let properties = paragraphProperties?[line] {
                let before = paragraph
                properties.apply(to: &paragraph)
                try paragraph.recordFormattingChange(from: before, identity: paragraphInsertion,
                    inheritedBefore: candidate.style(for: before).paragraph,
                    inheritedAfter: candidate.style(for: paragraph).paragraph)
            }
            let inserted = content.filter { !$0.text.isEmpty }.map { source -> TextRun in
                var run = source
                if paragraphProperties == nil, destination.styleID != originalDestination.styleID {
                    run = run.materializingReviewFormatting(over: style(for: originalDestination).text)
                }
                var review = RunReview(); review.insertion = insertion; run.review = review; return run
            }
            paragraph.runs = RevisionText.coalescing((line == 0 ? parts.before : []) + inserted + (line == lines.count - 1 ? parts.after : []))
            if paragraph.runs.isEmpty {
                let format = lines.count > 1 ? content.first?.format : nil
                paragraph.runs = [TextRun("", format: format ?? destination.runs.first?.format ?? TextFormatting())]
            }
            if line < lines.count - 1 {
                var review = RunReview(); review.insertion = insertion; paragraph.breakReview = review
            }
            additions.append(paragraph)
        }
        candidate.sections[section].paragraphs.replaceSubrange(insertionIndex...insertionIndex, with: additions)
        let insertedLength = lines.joined().reduce(lines.count - 1) { $0 + $1.text.utf16.count }
        candidate.transformCommentAnchors(from: beforeInsertion,
            replacing: NSRange(location: insertionLocation, length: 0), withLength: insertedLength)
        for note in insertedNotes {
            if let existing = candidate.notes.first(where: { $0.id == note.id }) {
                guard existing == note else { throw DocumentError.invalid("the inserted note identity conflicts with an existing note") }
            } else { candidate.notes.append(note) }
        }
        candidate.reconcileNotes()
        try NativeFormat.validate(candidate)
        let caret = insertionLocation + insertedLength
        guard let result = DocumentTextIndex(paragraphs: candidate.paragraphs).anchor(for: NSRange(location: caret, length: 0)) else {
            throw DocumentError.invalid("the tracked replacement caret is unavailable")
        }
        self = candidate
        return result
    }
}
