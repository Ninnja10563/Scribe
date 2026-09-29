#if canImport(AppKit)
import AppKit
import DocumentCore

/// A private native draft. Rich paste can introduce structure even when the
/// original note is plain, so all notes use the same semantic editing engine.
@MainActor final class NoteOptions {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
    private let session: NoteEditingSession
    var text: ScribeTextView { session.editor.activeTextView }
    let hasExistingRevisions: Bool
    init(note: DocumentNote, styles: [ParagraphStyle], author: RevisionAuthor? = nil) {
        session = NoteEditingSession(note: note, styles: styles, author: author)
        hasExistingRevisions = session.document.model.hasPendingRevisions
        session.editor.scrollView.frame = view.bounds
        session.editor.scrollView.autoresizingMask = [.width, .height]
        session.editor.scrollView.borderType = .bezelBorder
        view.addSubview(session.editor.scrollView)
        session.editor.resizeCanvas()
    }
    func close() { session.close() }
    func note() throws -> DocumentNote { try session.note() }
}
#endif
