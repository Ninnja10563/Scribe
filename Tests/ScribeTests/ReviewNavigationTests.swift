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
}
#endif
