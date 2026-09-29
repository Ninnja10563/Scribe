#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NoteProjectionTests: XCTestCase {
    func testReferenceProjectionRetainsNoteContentAfterTypingDeletionAndUndo() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument()
        let note = DocumentNote(kind: .footnote, text: "A citation with Unicode résumé.")
        var reference = TextRun("\u{FFFC}"); reference.noteID = note.id
        document.model.notes = [note]
        document.model.sections[0].paragraphs[0].runs = [TextRun("Body"), reference, TextRun(" after")]
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        XCTAssertEqual(document.snapshot().notes, [note])
        let cell = try XCTUnwrap((editor.storage.attribute(.attachment, at: 4, effectiveRange: nil) as? NSTextAttachment)?.attachmentCell)
        XCTAssertGreaterThan(cell.cellBaselineOffset().y, 0)
        editor.select(NSRange(location: 5, length: 0)); editor.activeTextView.insertText(" typed", replacementRange: NSRange(location: 5, length: 0))
        XCTAssertEqual(document.snapshot().notes, [note]); try NativeFormat.validate(document.snapshot())
        editor.select(NSRange(location: 4, length: 1)); editor.activeTextView.replaceSelection(NSAttributedString(string: ""), action: "Delete Reference")
        XCTAssertTrue(document.snapshot().notes.isEmpty)
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().notes, [note]); try NativeFormat.validate(document.snapshot())
    }
}
#endif
