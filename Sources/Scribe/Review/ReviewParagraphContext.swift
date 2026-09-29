#if canImport(AppKit)
import AppKit

extension ReviewTextProjection {
    /// Inline rich text contributes character formatting, not the source
    /// paragraph's identity, table cell or style association.
    static func preservingParagraphContext(_ incoming: NSAttributedString, original: NSAttributedString,
                                           range: NSRange, in editor: PaginatedEditor) -> NSAttributedString {
        guard !incoming.string.contains("\n"), !original.string.contains("\n"), incoming.length > 0 else { return incoming }
        let attributes: [NSAttributedString.Key: Any]
        if editor.storage.length == 0 || (range.location == editor.storage.length && editor.storage.string.hasSuffix("\n")) {
            attributes = editor.activeTextView.typingAttributes
        } else {
            let point = min(range.location, editor.storage.length - 1)
            let paragraph = (editor.storage.string as NSString).paragraphRange(for: NSRange(location: point, length: 0))
            attributes = editor.storage.attributes(at: paragraph.location, effectiveRange: nil)
        }
        let value = NSMutableAttributedString(attributedString: incoming), full = NSRange(location: 0, length: incoming.length)
        for key in [NSAttributedString.Key.scribeParagraphID, .scribeStyle, .scribeParagraphReview, .scribeList, .scribeCell, .scribeTOC, .paragraphStyle] {
            if let attribute = attributes[key] { value.addAttribute(key, value: attribute, range: full) }
            else { value.removeAttribute(key, range: full) }
        }
        value.removeAttribute(.scribePageBreakMarker, range: full)
        return value
    }
}
#endif
