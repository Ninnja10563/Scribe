#if canImport(AppKit)
import AppKit
import DocumentCore

extension EditorWindowController {
    @objc func insertFootnote() { noteDialog(editing: false) }
    @objc func insertEndnote() { noteDialog(editing: false, kind: .endnote) }
    @objc func editNote() { noteDialog(editing: true) }
    func openNote(id: UUID) {
        var found: NSRange?
        editor.storage.enumerateAttribute(.scribeNote, in: NSRange(location: 0, length: editor.storage.length)) { value, range, stop in
            if let data = value as? Data, let note = try? JSONDecoder().decode(DocumentNote.self, from: data), note.id == id { found = range; stop.pointee = true }
        }
        guard let found else { showStatus("The note reference is no longer in the document."); return }
        let viewport = editor.scrollView.contentView.bounds.origin
        noteDialog(editing: true, selection: found)
        editor.scrollView.contentView.scroll(to: viewport)
        editor.scrollView.reflectScrolledClipView(editor.scrollView.contentView)
    }
    private func noteDialog(editing: Bool, kind: DocumentNote.Kind = .footnote, selection: NSRange? = nil) {
        let model = fileDocument.snapshot()
        let range = selection ?? editor.activeTextView.selectedRange()
        let note: DocumentNote
        if editing {
            guard range.location < editor.storage.length,
                  let data = editor.storage.attribute(.scribeNote, at: range.location, effectiveRange: nil) as? Data,
                  let original = try? JSONDecoder().decode(DocumentNote.self, from: data) else { showStatus("Select a note reference first."); return }
            do { try validateNoteReferenceForEditing(NSRange(location: range.location, length: 1)) }
            catch { showStatus(error.localizedDescription); return }
            note = original
        } else { note = DocumentNote(kind: kind) }
        let originalStorage = NSAttributedString(attributedString: editor.storage)
        let options = NoteOptions(note: note, styles: model.styles), alert = NSAlert()
        defer { options.text.cancelSpellingCheck() }
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
    /// Retained deletions are review evidence, not an editable note reference.
    /// Reject before opening the dialog and again at commit for direct callers.
    private func validateNoteReferenceForEditing(_ range: NSRange) throws {
        guard range.length > 0, range.location >= 0, range.location < editor.storage.length else { return }
        let length = min(range.length, editor.storage.length - range.location)
        var deleted = false
        editor.storage.enumerateAttributes(in: NSRange(location: range.location, length: length)) { attributes, _, stop in
            guard attributes[.scribeNote] != nil,
                  let data = attributes[.scribeReview] as? Data,
                  let review = try? JSONDecoder().decode(RunReview.self, from: data), review.deletion != nil else { return }
            deleted = true; stop.pointee = true
        }
        if deleted { throw DocumentError.invalid("reject the note reference’s tracked deletion before editing or replacing the note") }
    }
    func applyNote(_ note: DocumentNote, replacing range: NSRange, action: String) throws {
        guard !isClosing, range.location >= 0, range.length >= 0,
              range.location <= editor.storage.length, range.length <= editor.storage.length - range.location else {
            throw DocumentError.invalid("the note selection is unavailable or its placement is not supported yet")
        }
        try validateNoteReferenceForEditing(range)
        let numbered = try NoteNumbering.resolve(referenceIDs: [note.id], notes: [note])[0]
        let model = fileDocument.snapshot()
        _ = try NoteTextLayout(note: numbered, styles: model.styles, width: editor.canvas.pageSettings.contentWidth)
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
