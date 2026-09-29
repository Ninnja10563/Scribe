#if canImport(AppKit)
import AppKit
import DocumentCore

/// Internal integration stage: enabled by native regressions until the complete
/// review interaction and input-method paths are ready for the public command.
@MainActor final class NativeReviewEditing {
    var author: RevisionAuthor? { didSet { if author != oldValue { resetGrouping() } } }
    func resetGrouping() { lastInsertion = nil }
    private(set) var lastValidationLength = 0
    private var lastInsertion: (identity: RevisionIdentity, caret: Int, date: Date)?
    func replacement(in editor: PaginatedEditor, range: NSRange, with value: NSAttributedString) throws -> NSAttributedString? {
        guard let author else { return nil }
        guard range.location >= 0, range.length >= 0, range.location <= editor.storage.length,
              range.length <= editor.storage.length - range.location else { throw DocumentError.invalid("the revision selection is unavailable") }
        let source = editor.storage.string as NSString
        for point in [range.location, NSMaxRange(range)] where point > 0 && point < source.length {
            guard !(0xD800...0xDBFF).contains(source.character(at: point - 1)) || !(0xDC00...0xDFFF).contains(source.character(at: point)) else { throw DocumentError.invalid("the revision selection splits a Unicode scalar") }
        }
        let now = Date(), insertion: RevisionIdentity
        if range.length == 0, let previous = lastInsertion, previous.caret == range.location,
           previous.identity.author.id == author.id, now.timeIntervalSince(previous.date) < 2,
           !value.string.contains("\n") { insertion = previous.identity }
        else { insertion = RevisionIdentity(author: author, date: now) }
        let original = editor.storage.attributedSubstring(from: range)
        let contextual = ReviewTextProjection.preservingParagraphContext(value, original: original, range: range, in: editor)
        let replacement: NSAttributedString
        if original.string == value.string {
            replacement = try ReviewTextProjection.formatting(original, as: contextual, identity: insertion, styles: editor.owner?.model.styles ?? ParagraphStyle.defaults)
        } else {
            replacement = try ReviewTextProjection.replacing(original, with: contextual, insertion: insertion, deletion: RevisionIdentity(author: author, date: now))
        }
        lastValidationLength = try ReviewEditValidation.validate(replacement, replacing: range, in: editor)
        lastInsertion = range.length == 0 && value.length > 0 && !value.string.contains("\n") ? (insertion, range.location + replacement.length, now) : nil
        return replacement
    }
}
#endif
