#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum NoteClipboard {
    static func fallback(_ note: DocumentNote) -> String {
        "[\(note.kind == .footnote ? "Footnote" : "Endnote"): \(note.plainText)]"
    }
    static func external(_ value: NSAttributedString) throws -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: value)
        var replacements: [(NSRange, DocumentNote)] = []
        var failure: Error?
        value.enumerateAttribute(.scribeNote, in: NSRange(location: 0, length: value.length)) { data, range, _ in
            guard let data else { return }
            do {
                guard let data = data as? Data, range.length == 1 else { throw DocumentError.invalid("invalid copied note") }
                replacements.append((range, try JSONDecoder().decode(DocumentNote.self, from: data)))
            } catch { failure = error }
        }
        if let failure { throw failure }
        for (range, note) in replacements.reversed() {
            var attributes = result.attributes(at: range.location, effectiveRange: nil)
            for key in [NSAttributedString.Key.attachment, .scribeNote, .scribeNoteNumber] { attributes.removeValue(forKey: key) }
            result.replaceCharacters(in: range, with: NSAttributedString(string: fallback(note), attributes: attributes))
        }
        return result
    }
    /// Freeze the source appearance without importing conflicting named styles.
    static func normalized(_ note: DocumentNote, styles: [ParagraphStyle], targetStyles: [ParagraphStyle] = ParagraphStyle.defaults) -> DocumentNote {
        var isolated = ScribeDocument(); isolated.styles = styles; isolated.sections[0].paragraphs = note.paragraphs
        let projection = NSMutableAttributedString(attributedString: AttributedDocument.render(isolated))
        projection.removeAttribute(.scribeStyle, range: NSRange(location: 0, length: projection.length))
        var result = note
        var target = ScribeDocument(); target.styles = targetStyles
        result.paragraphs = AttributedDocument.capture(projection, preserving: target).paragraphs
        return result
    }
    static func newCopy(_ note: DocumentNote) -> DocumentNote {
        var result = note; result.id = UUID()
        for index in result.paragraphs.indices { result.paragraphs[index].id = UUID() }
        return result
    }
}
#endif
