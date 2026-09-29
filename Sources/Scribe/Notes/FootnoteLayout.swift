#if canImport(AppKit)
import AppKit
import DocumentCore

/// Resolves the live editing projection, including note content restored by native undo.
/// Page fitting uses real line fragments and verifies the result after TextKit reflows.
@MainActor final class FootnoteLayout {
    struct Page {
        let notes: [NoteTextLayout]
        let height: CGFloat
        func draw(at origin: NSPoint, width: CGFloat) {
            guard !notes.isEmpty else { return }
            NSColor.darkGray.setStroke()
            let rule = NSBezierPath(); rule.lineWidth = 0.5
            rule.move(to: origin); rule.line(to: NSPoint(x: origin.x + min(100, width), y: origin.y)); rule.stroke()
            var y = origin.y + 12
            for note in notes { note.draw(at: NSPoint(x: origin.x, y: y)); y += note.height + 6 }
        }
    }
    private let measured: [UUID: NoteTextLayout]
    private let references: [(range: NSRange, id: UUID)]
    init(storage: NSTextStorage, styles: [ParagraphStyle], width: CGFloat) throws {
        var references: [(range: NSRange, id: UUID)] = [], notes: [DocumentNote] = []
        var failure: Error?
        storage.enumerateAttribute(.scribeNote, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let value else { return }
            do {
                guard let data = value as? Data else { throw DocumentError.invalid("invalid note reference") }
                let note = try JSONDecoder().decode(DocumentNote.self, from: data)
                guard range.length == 1, (storage.string as NSString).substring(with: range) == "\u{fffc}" else {
                    throw DocumentError.invalid("invalid note reference range")
                }
                references.append((range, note.id)); notes.append(note)
            } catch { failure = error }
        }
        if let failure { throw failure }
        let numbered = try NoteNumbering.resolve(referenceIDs: references.map(\.id), notes: notes)
        var measured: [UUID: NoteTextLayout] = [:]
        for note in numbered where note.note.kind == .footnote {
            measured[note.id] = try NoteTextLayout(note: note, styles: styles, width: width)
        }
        self.references = references.filter { measured[$0.id] != nil }; self.measured = measured
    }
    func fit(layout: NSLayoutManager, container: NSTextContainer, pageHeight: CGFloat) throws -> Page {
        container.containerSize.height = pageHeight
        layout.textContainerChangedGeometry(container); layout.ensureLayout(for: container)
        var lines: [FootnotePagePlan.Line] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { rect, _, current, glyphs, _ in
            guard current === container else { return }
            let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            lines.append(.init(bottom: rect.maxY, noteIDs: self.ids(in: characters)))
        }
        let heights = measured.mapValues { Double($0.height + 6) }
        let plan = try FootnotePagePlan.choose(lines: lines, pageHeight: pageHeight, noteHeights: heights)
        guard !plan.needsContinuation, plan.lineCount > 0 || lines.isEmpty else {
            throw DocumentError.invalid("A footnote and its reference cannot fit on one page. Note continuation is not available yet.")
        }
        container.containerSize.height = max(1, plan.bodyHeight)
        layout.textContainerChangedGeometry(container); layout.ensureLayout(for: container)
        let characters = layout.characterRange(forGlyphRange: layout.glyphRange(for: container), actualGlyphRange: nil)
        guard ids(in: characters) == plan.noteIDs,
              layout.usedRect(for: container).maxY + plan.noteHeight <= pageHeight + 0.5 else {
            throw DocumentError.invalid("The footnote reference could not be kept with its note on this page.")
        }
        return Page(notes: plan.noteIDs.compactMap { measured[$0] }, height: plan.noteHeight)
    }
    private func ids(in range: NSRange) -> [UUID] {
        references.filter { NSIntersectionRange($0.range, range).length > 0 }.map(\.id)
    }
}
#endif
