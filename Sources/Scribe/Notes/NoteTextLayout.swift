#if canImport(AppKit)
import AppKit
import DocumentCore

/// Measured, reusable native glyph layout for one note. Page reservation and the
/// screen/PDF renderers consume the same height and glyphs.
@MainActor final class NoteTextLayout {
    let noteID: UUID
    let label: String
    private let screenAttributes = ScreenTextAttributes()
    let storage: NSTextStorage
    let layout: NSLayoutManager
    let container: NSTextContainer
    let glyphRange: NSRange
    let height: CGFloat
    init(note: NumberedNote, styles: [ParagraphStyle], width: CGFloat) throws {
        noteID = note.id; label = "\(note.note.kind == .footnote ? "Footnote" : "Endnote") \(note.number)"
        guard width.isFinite, width >= 30, width <= 4000 else { throw DocumentError.invalid("invalid note writing width") }
        var model = ScribeDocument(); model.styles = styles; model.sections[0].paragraphs = note.note.paragraphs
        try NativeFormat.validate(model)
        let value = NSMutableAttributedString(attributedString: AttributedDocument.render(model))
        let base = AttributedDocument.editingAttributes(for: model.paragraphs[0], in: model)
        value.insert(NSAttributedString(string: "\(note.number).\t", attributes: base), at: 0)
        value.addAttribute(.scribeNoteContentID, value: note.id.uuidString, range: NSRange(location: 0, length: value.length))
        value.addAttribute(.scribeNoteLabelID, value: note.id.uuidString, range: NSRange(location: 0, length: ("\(note.number).\t" as NSString).length))
        let text = value.string as NSString
        var location = 0
        while location < value.length {
            let range = text.paragraphRange(for: NSRange(location: location, length: 0))
            let attributes = value.attribute(.paragraphStyle, at: location, effectiveRange: nil)
            let style = (attributes as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.headIndent += 18
            style.firstLineHeadIndent = location == 0 ? 0 : style.firstLineHeadIndent + 18
            style.tabStops = [NSTextTab(textAlignment: .left, location: 18)] + style.tabStops.filter { $0.location > 18 }
            value.addAttribute(.paragraphStyle, value: style, range: range)
            location = NSMaxRange(range)
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
        manager.delegate = screenAttributes
    }
    @MainActor struct Fragment {
        let note: NoteTextLayout
        let glyphs: NSRange
        let top: CGFloat
        let height: CGFloat
        func draw(at origin: NSPoint) {
            let offset = NSPoint(x: origin.x, y: origin.y - top)
            note.layout.drawBackground(forGlyphRange: glyphs, at: offset)
            note.layout.drawGlyphs(forGlyphRange: glyphs, at: offset)
        }
    }
    var fullFragment: Fragment { Fragment(note: self, glyphs: glyphRange, top: 0, height: height) }
    func minimumFragmentHeight(from start: Int) -> CGFloat {
        guard start < NSMaxRange(glyphRange) else { return 0 }
        let line = layout.lineFragmentRect(forGlyphAt: start, effectiveRange: nil)
        return ceil(line.maxY - (start == 0 ? 0 : line.minY))
    }
    func fragment(from start: Int, fitting available: CGFloat) -> Fragment? {
        guard start >= 0, start < NSMaxRange(glyphRange), available > 0 else { return nil }
        let top = start == 0 ? 0 : layout.lineFragmentRect(forGlyphAt: start, effectiveRange: nil).minY
        var end = start, bottom = top
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: start, length: NSMaxRange(glyphRange) - start)) { rect, _, _, range, stop in
            guard ceil(rect.maxY - top) <= available else { stop.pointee = true; return }
            end = NSMaxRange(range); bottom = rect.maxY
        }
        guard end > start else { return nil }
        if end == NSMaxRange(glyphRange) { bottom = min(bottom, height) }
        return Fragment(note: self, glyphs: NSRange(location: start, length: end - start), top: top, height: max(1, ceil(bottom - top)))
    }
    func draw(at origin: NSPoint) {
        layout.drawBackground(forGlyphRange: glyphRange, at: origin)
        layout.drawGlyphs(forGlyphRange: glyphRange, at: origin)
    }
}
#endif
