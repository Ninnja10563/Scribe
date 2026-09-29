import Foundation

public extension ScribeDocument {
    /// Apply an ordinary semantic replacement through the same annotation and
    /// paragraph transaction as tracked editing. Only revisions introduced by
    /// this transaction are resolved; earlier review evidence stays pending.
    @discardableResult mutating func replaceUntrackedRange(_ anchor: TextAnchor, withLines lines: [[TextRun]],
                                                           paragraphProperties: [ParagraphRevisionState]? = nil,
                                                           insertedNotes: [DocumentNote] = []) throws -> TextAnchor {
        var candidate = self
        let existing = Set(pendingRevisionIDs)
        let projectedCaret = try candidate.replaceTrackedRange(anchor, withLines: lines,
            paragraphProperties: paragraphProperties, author: RevisionAuthor(name: "Untracked edit"), insertedNotes: insertedNotes)
        let introduced = Set(candidate.pendingRevisionIDs).subtracting(existing)
        guard let caret = DocumentTextIndex(paragraphs: candidate.paragraphs).range(for: projectedCaret)?.location else {
            throw DocumentError.invalid("the replacement caret is unavailable")
        }
        var offset = 0, removedBeforeCaret = 0
        for paragraph in candidate.paragraphs {
            for run in paragraph.runs {
                let length = run.text.utf16.count
                if let deletion = run.review?.deletion, introduced.contains(deletion.id), offset < caret {
                    removedBeforeCaret += min(length, caret - offset)
                }
                offset += length
            }
            if let deletion = paragraph.breakReview?.deletion, introduced.contains(deletion.id), offset < caret {
                removedBeforeCaret += 1
            }
            offset += 1
        }
        try candidate.resolveRevisions(introduced, accepting: true)
        guard let result = DocumentTextIndex(paragraphs: candidate.paragraphs).anchor(for: NSRange(location: caret - removedBeforeCaret, length: 0)) else {
            throw DocumentError.invalid("the resolved replacement caret is unavailable")
        }
        try NativeFormat.validate(candidate)
        self = candidate
        return result
    }
}
