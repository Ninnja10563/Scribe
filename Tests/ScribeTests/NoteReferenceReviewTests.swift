#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NoteReferenceReviewTests: XCTestCase {
    func testDeletedNoteReferenceRefusesEditsWithoutChangingContentOrUndo() throws {
        _ = NSApplication.shared
        for kind in [DocumentNote.Kind.footnote, .endnote] {
            for tracking in [false, true] {
                let document = ScribeFileDocument()
                let note = DocumentNote(kind: kind, text: "Original citation")
                let deletion = RevisionIdentity(author: .init(name: "Reviewer"))
                var review = RunReview(); review.deletion = deletion
                var reference = TextRun("\u{fffc}"); reference.noteID = note.id; reference.review = review
                document.model.notes = [note]
                document.model.sections[0].paragraphs[0].runs = [reference]
                document.makeWindowControllers()
                defer { document.close() }
                let owner = document.editorController!
                owner.editor.reviewEditing.author = tracking ? .init(name: "Writer") : nil
                document.undoManager?.removeAllActions()
                let before = document.snapshot()
                var changed = note; changed.paragraphs = [Paragraph("Changed citation")]
                XCTAssertThrowsError(try owner.applyNote(changed, replacing: NSRange(location: 0, length: 1), action: "Edit Note")) { error in
                    XCTAssertTrue(error.localizedDescription.contains("tracked deletion"))
                }
                XCTAssertEqual(document.snapshot(), before)
                XCTAssertFalse(document.undoManager?.canUndo ?? true)
                XCTAssertTrue(owner.reviewNavigation.select(deletion.id))
                try owner.reviewNavigation.resolveCurrent(accepting: false)
                try owner.applyNote(changed, replacing: NSRange(location: 0, length: 1), action: "Edit Note")
                XCTAssertEqual(document.snapshot().notes.first?.plainText, "Changed citation")
                document.undoManager?.undo()
                XCTAssertEqual(document.snapshot().notes, [note])
            }
        }
    }
}
#endif
