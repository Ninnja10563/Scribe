#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum ReviewEditValidation {
    /// Short text edits without flow controls or objects leave paragraph and
    /// reference identities intact. Validate their new semantic content without
    /// recapturing unrelated paragraphs. Retained deletions remain rich runs.
    static func validate(_ replacement: NSAttributedString, replacing range: NSRange, in editor: PaginatedEditor) throws -> Int {
        guard let owner = editor.owner else { throw DocumentError.invalid("the document is no longer available") }
        let original = editor.storage.attributedSubstring(from: range)
        if range.length <= 128, replacement.length <= 256,
           isInlineText(original), isInlineText(replacement) {
            let fragment = NSMutableAttributedString(attributedString: replacement)
            let full = NSRange(location: 0, length: fragment.length)
            for key in [NSAttributedString.Key.scribeCell, .scribeTOC, .scribeList, .scribePageBreakMarker, .scribeBreakReview] {
                fragment.removeAttribute(key, range: full)
            }
            var isolated = ScribeDocument(); isolated.styles = owner.model.styles
            try NativeFormat.validate(AttributedDocument.capture(fragment, preserving: isolated))
            return fragment.length
        }
        let proposed = NSMutableAttributedString(attributedString: editor.storage)
        proposed.replaceCharacters(in: range, with: replacement)
        try NativeFormat.validate(AttributedDocument.capture(proposed, preserving: owner.snapshot()))
        return proposed.length
    }
    private static func isInlineText(_ value: NSAttributedString) -> Bool {
        guard !value.string.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || [0x2028, 0x2029, 0xfffc].contains($0.value) }) else { return false }
        var found = false
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, _, stop in
            if attributes[.attachment] != nil || attributes[.scribeImage] != nil || attributes[.scribeEquation] != nil || attributes[.scribeNote] != nil {
                found = true; stop.pointee = true
            }
        }
        return !found
    }
}
#endif
