#if canImport(AppKit)
import AppKit
import DocumentCore

/// Native, accessible hit targets over the shared page drawing. Editing uses a
/// separate rich-text session, so a cancelled edit cannot alter pagination.
@MainActor final class PageNoteControls: NSObject {
    weak var editor: PaginatedEditor?
    private(set) var buttons: [String: NSButton] = [:]
    func update(in canvas: PageCanvas) {
        let p = canvas.pageSettings
        var retained = Set<String>()
        func region(id: UUID, page: Int, rect: NSRect, label: String, text: String) {
            let key = "\(page):\(id.uuidString)"
            retained.insert(key)
            let button = buttons[key] ?? NSButton()
            if buttons[key] == nil {
                button.isBordered = false; button.isTransparent = true
                button.setButtonType(.momentaryPushIn)
                button.target = self; button.action = #selector(edit(_:))
                button.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
                canvas.addSubview(button); buttons[key] = button
            }
            button.title = "Edit " + label; button.frame = rect
            button.setAccessibilityLabel("Edit " + label)
            button.setAccessibilityValue(text)
            button.setAccessibilityHelp("Opens the note in a rich text editor. Cancel preserves the document.")
            button.toolTip = "Edit " + label
        }
        for (index, page) in canvas.footnotes {
            let rect = canvas.pageRect(index)
            var y = rect.maxY - p.bottom - page.height + 12
            for fragment in page.notes {
                let range = fragment.note.layout.characterRange(forGlyphRange: fragment.glyphs, actualGlyphRange: nil)
                let text = fragment.note.storage.attributedSubstring(from: range).string
                region(id: fragment.note.noteID, page: index, rect: NSRect(x: rect.minX + p.left, y: y, width: p.contentWidth, height: fragment.height), label: fragment.note.label + (fragment.glyphs.location > 0 ? " continued" : ""), text: text)
                y += fragment.height + 6
            }
        }
        if let notes = canvas.endnotes {
            for (index, container) in notes.containers.enumerated() {
                let glyphs = notes.layout.glyphRange(for: container)
                let characters = notes.layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                notes.storage.enumerateAttribute(.scribeNoteContentID, in: characters) { value, range, _ in
                    guard let value = value as? String, let id = UUID(uuidString: value) else { return }
                    let page = canvas.bodyPageCount + index, rect = canvas.pageRect(page)
                    let noteGlyphs = NSIntersectionRange(glyphs, notes.layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil))
                    let bounds = notes.layout.boundingRect(forGlyphRange: noteGlyphs, in: container)
                    region(id: id, page: page, rect: NSRect(x: rect.minX + p.left, y: rect.minY + p.top + bounds.minY, width: p.contentWidth, height: bounds.height), label: notes.labels[id] ?? "Endnote", text: notes.storage.attributedSubstring(from: range).string)
                }
            }
        }
        for key in Array(buttons.keys) where !retained.contains(key) {
            buttons.removeValue(forKey: key)?.removeFromSuperview()
        }
    }
    @objc private func edit(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        editor?.owner?.editorController?.editNote(id: id)
    }
    func clear() {
        for button in buttons.values { button.target = nil; button.removeFromSuperview() }
        buttons.removeAll(); editor = nil
    }
}
#endif
