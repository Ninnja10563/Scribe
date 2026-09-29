#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum ReviewEditValidation {
    /// A short insertion without flow controls or objects cannot remove existing
    /// identities, split paragraphs or change reference ownership. Validate its
    /// new semantic content without recapturing the rest of the document.
    static func validate(_ replacement: NSAttributedString, replacing range: NSRange, in editor: PaginatedEditor) throws -> Int {
        guard let owner = editor.owner else { throw DocumentError.invalid("the document is no longer available") }
        if range.length == 0, replacement.length > 0, replacement.length <= 128,
           !replacement.string.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || [0x2028, 0x2029, 0xfffc].contains($0.value) }),
           !containsObject(replacement) {
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
    private static func containsObject(_ value: NSAttributedString) -> Bool {
        var found = false
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, _, stop in
            if attributes[.attachment] != nil || attributes[.scribeImage] != nil || attributes[.scribeEquation] != nil || attributes[.scribeNote] != nil {
                found = true; stop.pointee = true
            }
        }
        return found
    }
}
#endif
