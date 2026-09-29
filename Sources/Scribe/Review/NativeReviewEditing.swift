#if canImport(AppKit)
import AppKit
import DocumentCore

/// Internal integration stage: enabled by native regressions until the complete
/// review interaction and input-method paths are ready for the public command.
@MainActor final class NativeReviewEditing {
    var author: RevisionAuthor?
    private var lastInsertion: (identity: RevisionIdentity, caret: Int, date: Date)?
    func replacement(in editor: PaginatedEditor, range: NSRange, with value: NSAttributedString) throws -> NSAttributedString? {
        guard let author else { return nil }
        guard range.location >= 0, range.length >= 0, range.location <= editor.storage.length,
              range.length <= editor.storage.length - range.location else { throw DocumentError.invalid("the revision selection is unavailable") }
        let now = Date(), insertion: RevisionIdentity
        if range.length == 0, let previous = lastInsertion, previous.caret == range.location,
           previous.identity.author.id == author.id, now.timeIntervalSince(previous.date) < 2,
           !value.string.contains("\n") { insertion = previous.identity }
        else { insertion = RevisionIdentity(author: author, date: now) }
        let original = editor.storage.attributedSubstring(from: range)
        let replacement = try ReviewTextProjection.replacing(original, with: value, insertion: insertion, deletion: RevisionIdentity(author: author, date: now))
        let proposed = NSMutableAttributedString(attributedString: editor.storage)
        proposed.replaceCharacters(in: range, with: replacement)
        guard let owner = editor.owner else { return nil }
        try NativeFormat.validate(AttributedDocument.capture(proposed, preserving: owner.snapshot()))
        lastInsertion = range.length == 0 && value.length > 0 && !value.string.contains("\n") ? (insertion, range.location + replacement.length, now) : nil
        return replacement
    }
}
#endif
