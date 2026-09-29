#if canImport(AppKit)
import AppKit
import DocumentCore

/// A private native draft. Applying returns semantic note paragraphs; cancelling
/// closes the draft without touching the source document or its recovery slot.
@MainActor final class NoteEditingSession {
    let document: ScribeFileDocument
    let editor: PaginatedEditor
    private let original: DocumentNote
    init(note: DocumentNote, styles: [ParagraphStyle], author: RevisionAuthor?) {
        original = note
        document = ScribeFileDocument(); document.isTransientEditingSession = true
        document.model.styles = styles
        document.model.sections[0].paragraphs = note.paragraphs
        var page = PageSettings()
        page.width = 440; page.height = 600
        page.left = 32; page.right = 32; page.top = 24; page.bottom = 24
        document.model.sections[0].page = page
        editor = PaginatedEditor(document: document)
        document.embeddedEditor = editor
        editor.reviewEditing.author = author
        editor.scrollView.rulersVisible = false
        editor.scrollView.hasHorizontalScroller = false
        editor.scrollView.allowsMagnification = false
        editor.onChange = { [weak document] in document?.didEdit() }
        editor.onLayout = { [weak editor] in
            for text in editor?.textViews ?? [] {
                text.setAccessibilityLabel("Note text")
                text.identifier = NSUserInterfaceItemIdentifier("Note Text")
            }
        }
        editor.onLayout?()
    }
    func note() throws -> DocumentNote {
        for text in editor.textViews where text.reviewComposition != nil || text.hasMarkedText() { text.unmarkText() }
        var result = original
        result.paragraphs = document.snapshot().paragraphs
        var check = ScribeDocument(); check.styles = document.model.styles; check.notes = [result]
        var reference = TextRun("\u{fffc}"); reference.noteID = result.id
        check.sections[0].paragraphs[0].runs = [reference]
        try NativeFormat.validate(check)
        return result
    }
    func close() { document.close() }
}
#endif
