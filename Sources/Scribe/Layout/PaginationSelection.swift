#if canImport(AppKit)
import AppKit

extension PaginatedEditor {
    /// Linked views share text selection, but only the first responder draws
    /// the caret. Reflow can move that caret into a different page container.
    func restoreCaretAfterPagination(_ range: NSRange, typingAttributes: [NSAttributedString.Key: Any]) {
        guard range.length == 0, range.location <= storage.length,
              let current = canvas.window?.firstResponder as? ScribeTextView, current.editor === self else { return }
        let container: NSTextContainer?
        if storage.length == 0 { container = layout.textContainers.first }
        else if range.location == storage.length, let extra = layout.extraLineFragmentTextContainer { container = extra }
        else {
            let glyph = layout.glyphIndexForCharacter(at: min(range.location, storage.length - 1))
            container = layout.textContainer(forGlyphAt: glyph, effectiveRange: nil)
        }
        guard let target = textViews.first(where: { $0.textContainer === container }), target !== current else { return }
        rememberSelection(target)
        canvas.window?.makeFirstResponder(target)
        target.setSelectedRange(range); target.typingAttributes = typingAttributes
        target.scrollRangeToVisible(range)
    }
}
#endif
