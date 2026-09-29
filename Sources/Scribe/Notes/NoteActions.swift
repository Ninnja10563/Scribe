#if canImport(AppKit)
import AppKit
import DocumentCore

extension EditorWindowController {
    @objc func insertFootnote() { noteDialog(editing: false) }
    @objc func insertEndnote() { noteDialog(editing: false, kind: .endnote) }
    @objc func editNote() { noteDialog(editing: true) }
    private func noteDialog(editing: Bool, kind: DocumentNote.Kind = .footnote) {
        let model = fileDocument.snapshot()
        let range = editor.activeTextView.selectedRange()
        let note: DocumentNote
        if editing {
            guard range.location < editor.storage.length,
                  let data = editor.storage.attribute(.scribeNote, at: range.location, effectiveRange: nil) as? Data,
                  let original = try? JSONDecoder().decode(DocumentNote.self, from: data) else { showStatus("Select a note reference first."); return }
            note = original
        } else { note = DocumentNote(kind: kind) }
        let originalStorage = NSAttributedString(attributedString: editor.storage)
        let options = NoteOptions(note: note, styles: model.styles), alert = NSAlert()
        alert.messageText = editing ? "Edit Note" : (kind == .footnote ? "Insert Footnote" : "Insert Endnote")
        alert.informativeText = "The note number follows its reference in the document."
        alert.accessoryView = options.view
        alert.addButton(withTitle: editing ? "Apply" : "Insert"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = options.text
        while !isClosing {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            do {
                guard originalStorage.isEqual(to: editor.storage) else { throw DocumentError.invalid("the document changed while the note was being edited; reopen the note dialog") }
                try applyNote(options.note(), replacing: editing ? NSRange(location: range.location, length: 1) : range, action: editing ? "Edit Note" : (kind == .footnote ? "Insert Footnote" : "Insert Endnote"))
                return
            } catch { alert.informativeText = error.localizedDescription }
        }
    }
    func applyNote(_ note: DocumentNote, replacing range: NSRange, action: String) throws {
        guard !isClosing, range.location >= 0, range.length >= 0,
              range.location <= editor.storage.length, range.length <= editor.storage.length - range.location else {
            throw DocumentError.invalid("the note selection is unavailable or its placement is not supported yet")
        }
        let numbered = try NoteNumbering.resolve(referenceIDs: [note.id], notes: [note])[0]
        let model = fileDocument.snapshot()
        let measurement = try NoteTextLayout(note: numbered, styles: model.styles, width: editor.canvas.pageSettings.contentWidth)
        guard note.kind == .endnote || measurement.height + 40 < editor.canvas.pageSettings.contentHeight else {
            throw DocumentError.invalid("this note requires continuation onto another page, which is not available yet")
        }
        var attributes = range.length > 0 ? editor.storage.attributes(at: range.location, effectiveRange: nil) : editor.activeTextView.typingAttributes
        for key in [NSAttributedString.Key.attachment, .scribeImage, .scribeEquation, .scribeNoteNumber] { attributes.removeValue(forKey: key) }
        attributes[.scribeNote] = try JSONEncoder().encode(note)
        attributes[.scribeNoteNumber] = 1
        attributes[.attachment] = NoteProjection.attachment(numbered, baseFont: ScriptProjection.logicalFont(in: attributes) ?? .systemFont(ofSize: 12))
        let value = NSAttributedString(string: "\u{fffc}", attributes: attributes)
        let proposed = NSMutableAttributedString(attributedString: editor.storage)
        proposed.replaceCharacters(in: range, with: value)
        try NativeFormat.validate(AttributedDocument.capture(proposed, preserving: model))
        editor.select(range); editor.activeTextView.replaceSelection(value, action: action)
        for key in [NSAttributedString.Key.attachment, .scribeImage, .scribeEquation, .scribeNote, .scribeNoteNumber] { editor.activeTextView.typingAttributes.removeValue(forKey: key) }
        editor.paginate()
    }
}
#endif
