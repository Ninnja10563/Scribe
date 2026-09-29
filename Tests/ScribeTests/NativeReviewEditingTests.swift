#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NativeReviewEditingTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func document(_ text: String) -> ScribeFileDocument {
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs = [Paragraph(text)]
        document.makeWindowControllers(); document.editorController!.editor.reviewEditing.author = RevisionAuthor(name: "Reviewer")
        return document
    }
    func testNativeReplacementRetainsDeletedContentAndUndoRedoRestoresMetadata() throws {
        let document = document("Old text"); defer { document.close() }
        let editor = document.editorController!.editor
        document.undoManager?.removeAllActions()
        editor.activeTextView.insertText("New", replacementRange: NSRange(location: 0, length: 3))
        let changed = document.snapshot()
        XCTAssertEqual(changed.paragraphs[0].text, "OldNew text")
        XCTAssertEqual(RevisionText(runs: changed.paragraphs[0].runs).finalText, "New text")
        XCTAssertEqual(changed.pendingRevisionIDs.count, 2)
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "Old text"); XCTAssertFalse(document.snapshot().hasPendingRevisions)
        document.undoManager?.redo()
        XCTAssertEqual(document.snapshot().paragraphs[0].runs, changed.paragraphs[0].runs)
        try NativeFormat.validate(document.snapshot())
    }
    func testNativeTypingGroupsRevisionIdentityAndOwnDeletionRemovesDraft() throws {
        let document = document("Body "); defer { document.close() }
        let editor = document.editorController!.editor, view = editor.activeTextView
        editor.select(NSRange(location: editor.storage.length, length: 0))
        for character in ["d", "r", "a", "f", "t"] { view.insertText(character, replacementRange: view.selectedRange()) }
        XCTAssertEqual(document.snapshot().pendingRevisionIDs.count, 1)
        for _ in 0..<5 { view.deleteBackward(nil) }
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "Body ")
        XCTAssertFalse(document.snapshot().hasPendingRevisions)
    }
    func testRepeatedNativeBackspaceMovesAcrossRetainedDeletions() throws {
        let document = document("ABCD"); defer { document.close() }
        let editor = document.editorController!.editor, view = editor.activeTextView
        editor.select(NSRange(location: 4, length: 0))
        view.deleteBackward(nil); view.deleteBackward(nil)
        XCTAssertEqual(view.selectedRange().location, 2)
        let model = document.snapshot()
        XCTAssertEqual(model.paragraphs[0].text, "ABCD")
        XCTAssertEqual(RevisionText(runs: model.paragraphs[0].runs).finalText, "AB")
    }
    func testNativeInsertedParagraphBreakCanBeRejected() throws {
        let document = document("AB"); defer { document.close() }
        let editor = document.editorController!.editor
        editor.activeTextView.insertText("\n", replacementRange: NSRange(location: 1, length: 0))
        var model = document.snapshot()
        XCTAssertEqual(model.paragraphs.map(\.text), ["A", "B"])
        XCTAssertNotNil(model.paragraphs[0].breakReview?.insertion)
        try model.resolveAllRevisions(accepting: false)
        XCTAssertEqual(model.paragraphs.map(\.text), ["AB"])
    }
    func testReplacementProjectionKeepsRichRunsAndReferenceData() throws {
        let author = RevisionAuthor(name: "Reviewer")
        var model = ScribeDocument(); let note = DocumentNote(kind: .footnote, text: "Source")
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        model.notes = [note]; model.sections[0].paragraphs[0].runs = [reference]
        let original = AttributedDocument.render(model)
        let changed = try ReviewTextProjection.replacing(original, with: NSAttributedString(string: ""), insertion: .init(author: author), deletion: .init(author: author))
        let captured = AttributedDocument.capture(changed, preserving: model)
        XCTAssertEqual(captured.notes, model.notes)
        XCTAssertEqual(captured.paragraphs[0].runs[0].noteID, note.id)
        XCTAssertNotNil(captured.paragraphs[0].runs[0].review?.deletion)
        try NativeFormat.validate(captured)
    }
}
#endif
