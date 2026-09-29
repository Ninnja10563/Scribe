#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NativeReviewCompositionTests: XCTestCase {
    private func document() -> ScribeFileDocument {
        _ = NSApplication.shared
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs = [Paragraph("Old text")]
        document.makeWindowControllers(); document.editorController!.editor.reviewEditing.author = .init(name: "Reviewer")
        return document
    }
    func testProvisionalInputDoesNotBecomeRevisionOrAutosavedDocument() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, view = editor.activeTextView
        editor.select(NSRange(location: 0, length: 3)); document.undoManager?.removeAllActions()
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.hasMarkedText()); XCTAssertEqual(editor.storage.string, "ni text")
        view.setMarkedText("日本", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(editor.storage.string, "日本 text")
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "Old text")
        XCTAssertFalse(document.snapshot().hasPendingRevisions)
        XCTAssertEqual(try NativeFormat.decode(document.data(ofType: ScribeFileDocument.typeName)).paragraphs[0].text, "Old text")
        XCTAssertFalse(document.undoManager?.canUndo ?? true)
        view.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0))
        let committed = document.snapshot()
        XCTAssertFalse(view.hasMarkedText()); XCTAssertNil(view.reviewComposition)
        XCTAssertEqual(committed.paragraphs[0].text, "Old日本 text")
        XCTAssertEqual(RevisionText(runs: committed.paragraphs[0].runs).finalText, "日本 text")
        XCTAssertEqual(committed.pendingRevisionIDs.count, 2)
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "Old text"); XCTAssertFalse(document.snapshot().hasPendingRevisions)
        document.undoManager?.redo()
        XCTAssertEqual(document.snapshot().paragraphs[0].runs, committed.paragraphs[0].runs)
    }
    func testCancelRestoresOriginalWithoutReviewOrUndoEntry() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, view = editor.activeTextView
        editor.select(NSRange(location: 0, length: 3)); document.undoManager?.removeAllActions()
        let original = NSAttributedString(attributedString: editor.storage)
        view.setMarkedText("draft", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.cancelOperation(nil)
        XCTAssertTrue(editor.storage.isEqual(to: original))
        XCTAssertFalse(view.hasMarkedText()); XCTAssertNil(view.reviewComposition)
        XCTAssertFalse(document.snapshot().hasPendingRevisions)
        XCTAssertFalse(document.undoManager?.canUndo ?? true)
        XCTAssertFalse(document.isDocumentEdited)
    }
    func testSnapshotKeepsUnrelatedEmptyParagraphStyleDuringComposition() throws {
        let document = document(); defer { document.close() }
        document.editorController!.editor.reviewEditing.author = nil
        document.performEdit("Set paragraphs") { $0.sections[0].paragraphs = [Paragraph("Title", style: "title"), Paragraph("", style: "caption")] }
        let editor = document.editorController!.editor, view = editor.activeTextView
        editor.reviewEditing.author = .init(name: "Reviewer")
        editor.select(NSRange(location: 0, length: 5))
        view.setMarkedText("Draft", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(document.snapshot().paragraphs.last?.styleID, "caption")
        XCTAssertEqual(document.snapshot().paragraphs.first?.text, "Title")
        view.cancelOperation(nil)
    }
    func testPartialMarkedReplacementKeepsUntouchedCompositionText() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, view = editor.activeTextView
        editor.select(NSRange(location: 0, length: 3))
        view.setMarkedText("abcdef", selectedRange: NSRange(location: 6, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.insertText("漢", replacementRange: NSRange(location: 2, length: 2))
        XCTAssertEqual(RevisionText(runs: document.snapshot().paragraphs[0].runs).finalText, "ab漢ef text")
        XCTAssertFalse(view.hasMarkedText())
    }
    func testExplicitReplacementOutsideCompositionCommitsBothAsOneUndo() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, view = editor.activeTextView
        editor.select(NSRange(location: 8, length: 0)); document.undoManager?.removeAllActions()
        view.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.insertText("New", replacementRange: NSRange(location: 0, length: 3))
        XCTAssertEqual(RevisionText(runs: document.snapshot().paragraphs[0].runs).finalText, "New text仮")
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs[0].text, "Old text")
        XCTAssertFalse(document.snapshot().hasPendingRevisions)
    }
    func testDocumentCommandCommitsCompositionBeforeChangingModel() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, view = editor.activeTextView
        editor.select(NSRange(location: 8, length: 0))
        view.setMarkedText("é", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        document.performEdit("Title") { $0.title = "Updated" }
        XCTAssertNil(view.reviewComposition)
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "Old texté")
        XCTAssertEqual(document.snapshot().title, "Updated")
    }
    func testUndoDuringCompositionCancelsPreviewBeforeUndoingPriorText() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, view = editor.activeTextView
        editor.select(NSRange(location: 8, length: 0)); document.undoManager?.removeAllActions()
        view.insertText("x", replacementRange: view.selectedRange()); view.breakUndoCoalescing()
        view.setMarkedText("draft", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        document.undoManager?.undo()
        XCTAssertNil(view.reviewComposition); XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "Old text")
        XCTAssertFalse(document.snapshot().hasPendingRevisions)
        document.undoManager?.redo()
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "Old textx")
        XCTAssertEqual(document.snapshot().pendingRevisionIDs.count, 1)
    }
    func testClosingClearsProvisionalCompositionWithoutCommittingIt() {
        let document = document()
        let editor = document.editorController!.editor, view = editor.activeTextView
        editor.select(NSRange(location: 8, length: 0))
        view.setMarkedText("draft", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        document.close()
        XCTAssertNil(view.reviewComposition)
        XCTAssertEqual(editor.storage.string, "Old text")
    }
    func testUnmarkCommitsCurrentCompositionOnce() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, view = editor.activeTextView
        editor.select(NSRange(location: 8, length: 0)); document.undoManager?.removeAllActions()
        view.setMarkedText("é", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.unmarkText()
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "Old texté")
        XCTAssertEqual(document.snapshot().pendingRevisionIDs.count, 1)
        XCTAssertNil(document.snapshot().paragraphs[0].runs.last?.format.underline, "IME decoration must not become authored underlining")
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs[0].text, "Old text")
    }
}
#endif
