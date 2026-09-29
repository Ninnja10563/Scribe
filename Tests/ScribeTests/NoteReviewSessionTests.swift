#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NoteReviewSessionTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testDraftTracksEditsAndRejectsToOriginalForBothNoteKinds() throws {
        for kind in [DocumentNote.Kind.footnote, .endnote] {
            let original = DocumentNote(kind: kind, text: "Original citation")
            let session = NoteReviewSession(note: original, styles: ParagraphStyle.defaults, author: .init(name: "Writer"))
            defer { session.close() }
            session.editor.select(NSRange(location: 8, length: 0))
            session.editor.activeTextView.insertText("new ", replacementRange: NSRange(location: NSNotFound, length: 0))
            let edited = try session.note()
            XCTAssertEqual(edited.plainText, "Originalnew  citation")
            XCTAssertTrue(edited.paragraphs[0].runs.contains { $0.review?.insertion != nil })
            var snapshot = session.document.snapshot()
            try snapshot.resolveAllRevisions(accepting: false)
            XCTAssertEqual(snapshot.paragraphs, original.paragraphs)
            session.document.undoManager?.undo()
            XCTAssertEqual(try session.note().paragraphs, original.paragraphs)
            session.document.undoManager?.redo()
            XCTAssertEqual(try session.note(), edited)
        }
    }
    func testLongDraftFlowsAndRetainsCharacterFormattingReview() throws {
        var original = DocumentNote(kind: .endnote)
        original.paragraphs = (1...90).map { Paragraph("Citation \($0). " + String(repeating: "Source details. ", count: 8)) }
        let session = NoteReviewSession(note: original, styles: ParagraphStyle.defaults, author: .init(name: "Writer"))
        defer { session.close() }
        XCTAssertGreaterThan(session.editor.textViews.count, 2)
        XCTAssertEqual(try session.note().paragraphs, original.paragraphs)
        let end = session.editor.storage.length
        session.editor.select(NSRange(location: end - 8, length: 7))
        session.editor.activeTextView.toggleBold(nil)
        let formatted = try session.note()
        XCTAssertTrue(formatted.paragraphs.last!.runs.contains { !($0.review?.formatting.isEmpty ?? true) })
        session.document.undoManager?.undo()
        XCTAssertEqual(try session.note().paragraphs, original.paragraphs)
        session.document.undoManager?.redo()
        XCTAssertEqual(try session.note(), formatted)
        var rejected = session.document.snapshot()
        try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual(rejected.paragraphs, original.paragraphs)
    }
    func testApplyCommitsCompositionButCancelLeavesSourceUntouched() throws {
        let original = DocumentNote(kind: .footnote, text: "Citation")
        let session = NoteReviewSession(note: original, styles: ParagraphStyle.defaults, author: .init(name: "Writer"))
        session.editor.select(NSRange(location: 8, length: 0))
        session.editor.activeTextView.setMarkedText("語", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(session.document.snapshot().paragraphs, original.paragraphs)
        let committed = try session.note()
        XCTAssertEqual(committed.plainText, "Citation語")
        XCTAssertTrue(committed.paragraphs[0].runs.contains { $0.review?.insertion != nil })
        session.close()
        XCTAssertEqual(original.plainText, "Citation")
    }
    func testTrackedModalApplyCancelAndDocumentUndo() throws {
        let document = ScribeFileDocument()
        let original = DocumentNote(kind: .footnote, text: "Citation")
        var reference = TextRun("\u{fffc}"); reference.noteID = original.id
        document.model.notes = [original]; document.model.sections[0].paragraphs[0].runs = [reference]
        document.makeWindowControllers(); defer { document.close() }
        let owner = document.editorController!
        owner.editor.reviewEditing.author = .init(name: "Writer")
        func submit(_ title: String) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                guard let content = NSApp.modalWindow?.contentView,
                      let text = descendants(content).compactMap({ $0 as? ScribeTextView }).first(where: { $0.identifier?.rawValue == "Note Text" }),
                      let button = descendants(content).compactMap({ $0 as? NSButton }).first(where: { $0.title == title }) else {
                    XCTFail("Missing tracked note dialog controls"); NSApp.abortModal(); return
                }
                text.setSelectedRange(NSRange(location: 8, length: 0))
                text.insertText(" added", replacementRange: NSRange(location: NSNotFound, length: 0))
                NativeDialogCapture.save(content, name: "TrackedNoteDialog")
                button.performClick(nil)
            }
        }
        let before = document.snapshot()
        submit("Cancel"); owner.editNote()
        XCTAssertEqual(document.snapshot(), before)
        document.undoManager?.removeAllActions()
        submit("Apply"); owner.editNote()
        let applied = document.snapshot()
        XCTAssertEqual(applied.notes.first?.plainText, "Citation added")
        XCTAssertTrue(applied.hasPendingRevisions)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().notes, [original])
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().notes, applied.notes)
        var rejected = applied; try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual(rejected.notes, [original])
    }
}
#endif
