#if canImport(AppKit)
import AppKit

/// Provisional input stays native and visible, but is not a sequence of author
/// revisions. The pre-composition projection also remains available to autosave.
@MainActor final class ReviewComposition {
    let originalStorage: NSAttributedString
    let original: NSAttributedString
    let originalRange: NSRange
    let typingAttributes: [NSAttributedString.Key: Any]
    var markedRange: NSRange
    init?(storage: NSAttributedString, range: NSRange, typingAttributes: [NSAttributedString.Key: Any]) {
        guard range.location >= 0, range.length >= 0, range.location <= storage.length,
              range.length <= storage.length - range.location else { return nil }
        originalStorage = NSAttributedString(attributedString: storage)
        original = storage.attributedSubstring(from: range); originalRange = range
        markedRange = range; self.typingAttributes = typingAttributes
    }
}
#endif
