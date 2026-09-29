#if canImport(AppKit)
import AppKit
import DocumentCore

/// Measured, reusable native glyph layout for one note. Page reservation and the
/// screen/PDF renderers consume the same height and glyphs.
@MainActor final class NoteTextLayout {
    let storage: NSTextStorage
    let layout: NSLayoutManager
    let container: NSTextContainer
    let glyphRange: NSRange
    let height: CGFloat
    init(note: NumberedNote, styles: [ParagraphStyle], width: CGFloat) throws {
        guard width.isFinite, width >= 30, width <= 4000 else { throw DocumentError.invalid("invalid note writing width") }
        var model = ScribeDocument(); model.styles = styles; model.sections[0].paragraphs = note.note.paragraphs
        try NativeFormat.validate(model)
        let value = NSMutableAttributedString(attributedString: AttributedDocument.render(model))
        let base = AttributedDocument.editingAttributes(for: model.paragraphs[0], in: model)
        value.insert(NSAttributedString(string: "\(note.number).\t", attributes: base), at: 0)
        let full = NSRange(location: 0, length: value.length)
        value.enumerateAttribute(.paragraphStyle, in: full) { attributes, range, _ in
            let style = (attributes as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.headIndent += 18
            style.firstLineHeadIndent = range.location == 0 ? 0 : style.firstLineHeadIndent + 18
            style.tabStops.insert(NSTextTab(textAlignment: .left, location: 18), at: 0)
            value.addAttribute(.paragraphStyle, value: style, range: range)
        }
        let noteStorage = NSTextStorage(attributedString: value), manager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: NSSize(width: width, height: 1_000_000))
        textContainer.lineFragmentPadding = 0; textContainer.widthTracksTextView = false
        noteStorage.addLayoutManager(manager); manager.addTextContainer(textContainer)
        manager.ensureLayout(for: textContainer)
        let range = manager.glyphRange(for: textContainer)
        guard NSMaxRange(range) == manager.numberOfGlyphs else { throw DocumentError.invalid("note content exceeds the current layout limit") }
        let bounds = manager.usedRect(for: textContainer)
        guard bounds.maxX <= width + 1 else { throw DocumentError.invalid("a note object is wider than its writing area") }
        storage = noteStorage; layout = manager; container = textContainer; glyphRange = range
        height = max(1, ceil(bounds.maxY))
    }
    func draw(at origin: NSPoint) {
        layout.drawBackground(forGlyphRange: glyphRange, at: origin)
        layout.drawGlyphs(forGlyphRange: glyphRange, at: origin)
    }
}
#endif
