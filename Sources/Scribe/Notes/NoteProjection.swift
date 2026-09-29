#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum NoteProjection {
    /// Numbers are derived presentation, never an undoable mutation of note content.
    static func refreshNumbers(in storage: NSTextStorage) throws {
        var notes: [DocumentNote] = [], ranges: [NSRange] = []
        var failure: Error?
        storage.enumerateAttribute(.scribeNote, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let value else { return }
            do {
                guard let data = value as? Data, range.length == 1 else { throw DocumentError.invalid("invalid note reference") }
                notes.append(try JSONDecoder().decode(DocumentNote.self, from: data)); ranges.append(range)
            } catch { failure = error }
        }
        if let failure { throw failure }
        let numbered = try NoteNumbering.resolve(referenceIDs: notes.map(\.id), notes: notes)
        for (note, range) in zip(numbered, ranges) {
            let attributes = storage.attributes(at: range.location, effectiveRange: nil)
            let font = ScriptProjection.logicalFont(in: attributes) ?? .systemFont(ofSize: 12)
            let cell = (attributes[.attachment] as? NSTextAttachment)?.attachmentCell as? NoteReferenceCell
            guard attributes[.scribeNoteNumber] as? Int != note.number || cell?.baseFont != font else { continue }
            storage.addAttributes([.attachment: attachment(note, baseFont: font), .scribeNoteNumber: note.number], range: range)
        }
    }
    static func attachment(_ note: NumberedNote, baseFont: NSFont) -> NSTextAttachment {
        let font = NSFont(descriptor: baseFont.fontDescriptor, size: max(6, baseFont.pointSize * 0.7)) ?? .systemFont(ofSize: 8)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let number = String(note.number) as NSString
        let size = number.size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: ceil(size.width) + 1, height: ceil(size.height)), flipped: false) { rect in
            number.draw(at: rect.origin, withAttributes: attributes); return true
        }
        let label = "\(note.note.kind == .footnote ? "Footnote" : "Endnote") \(note.number)"
        image.accessibilityDescription = label
        let attachment = NSTextAttachment()
        let cell = NoteReferenceCell(imageCell: image); cell.rise = baseFont.pointSize * 0.3; cell.baseFont = baseFont
        cell.setAccessibilityLabel(label); attachment.attachmentCell = cell
        return attachment
    }
}
private final class NoteReferenceCell: NSTextAttachmentCell {
    var rise: CGFloat = 0
    var baseFont: NSFont?
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: rise) }
}
#endif
