#if canImport(AppKit)
import AppKit
import DocumentCore

extension ScribeTextView {
    /// Removing an author's own draft separator is a semantic join. Deleting
    /// just its native newline would leave the next list's generated marker
    /// embedded in the preceding paragraph as ordinary text.
    func removeOwnTrackedSeparator(in range: NSRange) -> Bool {
        guard range.length == 1, let editor, let owner = editor.owner,
              let author = editor.reviewEditing.author, range.location >= 0,
              range.location < editor.storage.length,
              (editor.storage.string as NSString).character(at: range.location) == 10,
              let value = editor.storage.attribute(.scribeParagraphID, at: range.location, effectiveRange: nil) as? String,
              let id = UUID(uuidString: value) else { return false }
        do {
            var model = owner.snapshot()
            guard try model.removeOwnInsertedSeparator(after: id, authorID: author.id) else { return false }
            owner.performEdit("Delete", recordReview: false) { $0 = model }
            editor.reviewEditing.resetGrouping()
            editor.select(NSRange(location: min(range.location, editor.storage.length), length: 0))
        } catch { presentError(error) }
        return true
    }
}
#endif
