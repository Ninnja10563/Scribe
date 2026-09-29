#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ReviewNavigationTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func fixture() -> (ScribeFileDocument, UUID, UUID) {
        let document = ScribeFileDocument(), author = RevisionAuthor(name: "Writer")
        let first = RevisionIdentity(author: author), second = RevisionIdentity(author: author)
        var a = TextRun("first"), b = TextRun("second")
        var one = RunReview(); one.insertion = first
        var two = RunReview(); two.insertion = second
        a.review = one; b.review = two
        document.model.sections[0].paragraphs[0].runs = [a, TextRun(" between "), b]
        document.makeWindowControllers(); document.undoManager?.removeAllActions()
        return (document, first.id, second.id)
    }
    func testNavigationWrapsAndDecisionsHaveNativeUndoRedo() throws {
        let (document, first, second) = fixture(); defer { document.close() }
        let owner = document.editorController!, navigation = owner.reviewNavigation
        let original = document.snapshot()
        XCTAssertEqual(navigation.navigate()?.id, first)
        XCTAssertEqual(owner.editor.activeTextView.selectedRange(), NSRange(location: 0, length: 5))
        XCTAssertEqual(navigation.navigate(backwards: true)?.id, second)
        XCTAssertEqual(owner.editor.activeTextView.selectedRange(), NSRange(location: 14, length: 6))
        XCTAssertEqual(navigation.navigate()?.id, first)
        try navigation.resolveCurrent(accepting: false)
        XCTAssertEqual(document.snapshot().paragraphs[0].text, " between second")
        XCTAssertEqual(navigation.selectedID, second)
        XCTAssertEqual(document.undoManager?.undoActionName, "Reject Change")
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, original.paragraphs)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs[0].text, " between second")
        document.undoManager?.removeAllActions()
        try navigation.resolveCurrent(accepting: true)
        XCTAssertFalse(document.snapshot().hasPendingRevisions)
        XCTAssertNil(navigation.selectedID)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().pendingRevisionIDs, [second])
    }
    func testStaleSelectionCannotResolveAnUnrelatedChangeAndAllIsUndoable() throws {
        let (document, first, second) = fixture(); defer { document.close() }
        let navigation = document.editorController!.reviewNavigation
        XCTAssertTrue(navigation.select(first))
        let before = document.snapshot(); var external = before
        try external.resolveRevision(first, accepting: true)
        document.applyReviewedStructure(external, replacing: before, name: "External Decision")
        try navigation.resolveCurrent(accepting: false)
        XCTAssertEqual(document.snapshot().pendingRevisionIDs, [second])
        XCTAssertNil(navigation.selectedID)
        document.undoManager?.removeAllActions()
        try navigation.resolveAll(accepting: false)
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "first between ")
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, external.paragraphs)
        document.undoManager?.redo(); XCTAssertFalse(document.snapshot().hasPendingRevisions)
    }
    func testCommandsAfterCloseDoNothing() throws {
        let (document, _, _) = fixture()
        let navigation = document.editorController!.reviewNavigation
        document.close()
        XCTAssertNil(navigation.navigate()); XCTAssertFalse(navigation.select(UUID()))
        XCTAssertNoThrow(try navigation.resolveAll(accepting: true))
    }
    func testGroupedPasteDecisionRestoresOriginalWithOneNativeUndo() throws {
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs = [Paragraph("AB")]
        let original = document.model
        var title = Paragraph(); title.styleID = "title"
        var quote = Paragraph(); quote.styleID = "quote"
        _ = try document.model.replaceTrackedRange(.init(paragraphID: original.paragraphs[0].id, offset: 1, length: 0),
            withLines: [[TextRun("X")], [TextRun("Y")]],
            paragraphProperties: [ParagraphRevisionState(title), ParagraphRevisionState(quote)], author: .init(name: "Writer"))
        document.makeWindowControllers(); defer { document.close() }
        let pasted = document.snapshot(), navigation = document.editorController!.reviewNavigation
        let change = try XCTUnwrap(navigation.navigate())
        XCTAssertEqual(change.componentIDs.count, 2)
        document.undoManager?.removeAllActions()
        try navigation.resolveCurrent(accepting: false)
        XCTAssertEqual(document.snapshot().paragraphs, original.paragraphs)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, pasted.paragraphs)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs, original.paragraphs)
    }
    func testNoteDecisionUpdatesRenderedNoteAndNativeUndo() throws {
        let document = ScribeFileDocument()
        var note = DocumentNote(kind: .footnote, text: "retained")
        var review = RunReview(); review.deletion = RevisionIdentity(author: .init(name: "Reviewer"))
        note.paragraphs[0].runs[0].review = review
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        document.model.notes = [note]; document.model.sections[0].paragraphs[0].runs = [TextRun("body"), reference]
        document.makeWindowControllers(); defer { document.close() }
        let original = document.snapshot(), owner = document.editorController!
        let change = try XCTUnwrap(owner.reviewNavigation.navigate())
        XCTAssertEqual(change.locations[0].noteID, note.id)
        XCTAssertEqual(owner.editor.activeTextView.selectedRange(), NSRange(location: 4, length: 1))
        document.undoManager?.removeAllActions()
        try owner.reviewNavigation.resolveCurrent(accepting: true)
        XCTAssertEqual(document.snapshot().notes[0].plainText, "")
        XCTAssertFalse(document.snapshot().hasPendingRevisions)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().notes, original.notes)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().notes[0].plainText, "")
    }
}
#endif
