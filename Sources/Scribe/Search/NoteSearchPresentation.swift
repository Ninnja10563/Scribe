#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class NoteSearchPresentation {
    private struct RenderedNote {
        let storage: NSTextStorage
        let layout: NSLayoutManager
        let offset: Int
        let semantic: SemanticTextSnapshot
        func sourceRange(_ range: NSRange) -> NSRange? {
            guard let value = semantic.sourceRange(forContentRange: range) else { return nil }
            return NSRange(location: offset + value.location, length: value.length)
        }
    }
    private var highlighted: [(NSLayoutManager, NSRange)] = []
    func clear() {
        for (layout, range) in highlighted {
            guard let storage = layout.textStorage else { continue }
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSIntersectionRange(range, NSRange(location: 0, length: storage.length)))
        }
        highlighted.removeAll()
    }
    private func renderedNotes(in editor: PaginatedEditor) -> [UUID: RenderedNote] {
        var result: [UUID: RenderedNote] = [:]
        for page in editor.canvas.footnotes.values {
            for fragment in page.notes where result[fragment.note.noteID] == nil {
                let note = fragment.note
                result[note.noteID] = RenderedNote(storage: note.storage, layout: note.layout, offset: 0, semantic: SemanticTextSnapshot(note.storage))
            }
        }
        if let notes = editor.canvas.endnotes {
            notes.storage.enumerateAttribute(.scribeNoteContentID, in: NSRange(location: 0, length: notes.storage.length)) { value, range, _ in
                guard let value = value as? String, let id = UUID(uuidString: value) else { return }
                result[id] = RenderedNote(storage: notes.storage, layout: notes.layout, offset: range.location, semantic: SemanticTextSnapshot(notes.storage.attributedSubstring(from: range)))
            }
        }
        return result
    }
    func highlight(_ matches: [DocumentSearchMatch], in editor: PaginatedEditor) {
        clear()
        let notes = renderedNotes(in: editor)
        let color = NSColor.systemYellow.withAlphaComponent(0.4)
        for match in matches {
            let layout: NSLayoutManager, range: NSRange
            switch match {
            case .body(let body): layout = editor.layout; range = body
            case .note(let id, let semantic, _):
                guard let note = notes[id], let source = note.sourceRange(semantic) else { continue }
                layout = note.layout; range = source
            }
            layout.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
            highlighted.append((layout, range))
        }
        editor.canvas.needsDisplay = true
    }
    /// Returns the physical page shown, including a note continuation page.
    func reveal(_ match: DocumentSearchMatch, in editor: PaginatedEditor) -> Int? {
        guard case .note(let id, let semantic, let reference) = match else { return nil }
        editor.select(reference, focus: false)
        let p = editor.canvas.pageSettings
        guard let note = renderedNotes(in: editor)[id], let range = note.sourceRange(semantic) else { return nil }
        // An empty paragraph has no searchable extent. Use its caret line,
        // including the extra line after a final newline, for navigation.
        let caret = range.length == 0
        let extraContainer = caret && range.location == note.storage.length ? note.layout.extraLineFragmentTextContainer : nil
        let drawable = caret ? NSRange(location: min(range.location, max(0, note.storage.length - 1)), length: min(1, note.storage.length)) : range
        let glyphs = note.layout.glyphRange(forCharacterRange: drawable, actualCharacterRange: nil)
        for index in editor.canvas.footnotes.keys.sorted() {
            guard let page = editor.canvas.footnotes[index] else { continue }
            let rect = editor.canvas.pageRect(index)
            var y = rect.maxY - p.bottom - page.height + 12
            for fragment in page.notes {
                let overlap = NSIntersectionRange(fragment.glyphs, glyphs)
                if fragment.note.noteID == id, overlap.length > 0 {
                    let bounds = extraContainer === fragment.note.container ? note.layout.extraLineFragmentRect
                        : (caret ? note.layout.lineFragmentRect(forGlyphAt: overlap.location, effectiveRange: nil)
                                 : note.layout.boundingRect(forGlyphRange: overlap, in: fragment.note.container))
                    editor.canvas.scrollToVisible(NSRect(x: rect.minX + p.left + bounds.minX, y: y - fragment.top + bounds.minY, width: bounds.width, height: bounds.height).insetBy(dx: -12, dy: -12))
                    return index + 1
                }
                y += fragment.height + 6
            }
        }
        if let endnotes = editor.canvas.endnotes, endnotes.storage === note.storage {
            for (index, container) in endnotes.containers.enumerated() {
                let overlap = NSIntersectionRange(endnotes.layout.glyphRange(for: container), glyphs)
                guard extraContainer.map({ $0 === container }) ?? (overlap.length > 0) else { continue }
                let rect = editor.canvas.pageRect(editor.canvas.bodyPageCount + index)
                let bounds = extraContainer === container ? note.layout.extraLineFragmentRect
                    : (caret ? note.layout.lineFragmentRect(forGlyphAt: overlap.location, effectiveRange: nil)
                             : note.layout.boundingRect(forGlyphRange: overlap, in: container))
                editor.canvas.scrollToVisible(NSRect(x: rect.minX + p.left + bounds.minX, y: rect.minY + p.top + bounds.minY, width: bounds.width, height: bounds.height).insetBy(dx: -12, dy: -12))
                return editor.canvas.bodyPageCount + index + 1
            }
        }
        return nil
    }
}
#endif
