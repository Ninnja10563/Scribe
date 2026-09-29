#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NativeParagraphSplitReviewTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func document(_ paragraph: Paragraph) -> ScribeFileDocument {
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs = [paragraph]
        document.makeWindowControllers(); document.editorController!.editor.reviewEditing.author = .init(name: "Writer")
        document.undoManager?.removeAllActions(); return document
    }
    func testReturnKeepsTrackedPageBreakOnlyOnFirstParagraph() throws {
        let document = document(Paragraph("Before after")); defer { document.close() }
        let editor = document.editorController!.editor
        document.performEdit("Page Break Before") { $0.sections[0].paragraphs[0].pageBreakBefore = true }
        let before = document.snapshot()
        editor.select(NSRange(location: 8, length: 0)); editor.activeTextView.insertNewline(nil)
        var model = document.snapshot(); try NativeFormat.validate(model)
        XCTAssertEqual(model.paragraphs.map(\.text), ["Before ", "after"])
        XCTAssertTrue(model.paragraphs[0].pageBreakBefore); XCTAssertFalse(model.paragraphs[1].pageBreakBefore)
        XCTAssertNil(model.paragraphs[1].formattingReview)
        let split = try XCTUnwrap(model.paragraphs[0].breakReview?.insertion?.id)
        try model.resolveRevision(split, accepting: false)
        XCTAssertEqual(model.paragraphs, before.paragraphs)
    }
    func testEmptyParagraphReturnPreservesTypingFormatAndNewIdentity() throws {
        var paragraph = Paragraph("", style: "caption"); paragraph.runs[0].format.italic = true
        let document = document(paragraph); defer { document.close() }
        let editor = document.editorController!.editor
        editor.activeTextView.insertNewline(nil)
        let empty = document.snapshot(); try NativeFormat.validate(empty)
        XCTAssertEqual(empty.paragraphs.count, 2); XCTAssertNotEqual(empty.paragraphs[0].id, empty.paragraphs[1].id)
        XCTAssertEqual(editor.activeTextView.selectedRange().location, editor.storage.length)
        XCTAssertEqual(empty.paragraphs[1].styleID, "caption")
        XCTAssertEqual(empty.paragraphs[1].runs[0].format.italic, true)
        editor.activeTextView.insertText("Next", replacementRange: editor.activeTextView.selectedRange())
        let typed = document.snapshot(); try NativeFormat.validate(typed)
        XCTAssertEqual(typed.paragraphs.map(\.text), ["", "Next"])
        XCTAssertEqual(typed.paragraphs[1].id, empty.paragraphs[1].id)
        XCTAssertEqual(typed.paragraphs[1].runs[0].format.italic, true)
    }
    func testNativeUndoRedoRestoresEmptyParagraphIdentityAndTypingMetadata() throws {
        let document = document(Paragraph("", style: "caption")); defer { document.close() }
        let editor = document.editorController!.editor, before = document.snapshot()
        editor.activeTextView.insertNewline(nil)
        let after = document.snapshot()
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().paragraphs, before.paragraphs)
        document.undoManager?.redo()
        XCTAssertEqual(document.snapshot().paragraphs, after.paragraphs)
        XCTAssertEqual(editor.activeTextView.selectedRange(), NSRange(location: 1, length: 0))
    }
    func testNativeUndoRedoRestoresMidParagraphCaret() throws {
        let document = document(Paragraph("ABC")); defer { document.close() }
        let editor = document.editorController!.editor
        editor.select(NSRange(location: 1, length: 0)); editor.activeTextView.insertNewline(nil)
        XCTAssertEqual(editor.activeTextView.selectedRange(), NSRange(location: 2, length: 0))
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "ABC")
        XCTAssertEqual(editor.activeTextView.selectedRange(), NSRange(location: 1, length: 0))
        document.undoManager?.redo()
        XCTAssertEqual(document.snapshot().paragraphs.map(\.text), ["A", "BC"])
        XCTAssertEqual(editor.activeTextView.selectedRange(), NSRange(location: 2, length: 0))
    }
    func testLocalReturnPreservesUncapturedEditsInOtherParagraphs() throws {
        let document = document(Paragraph("One")); defer { document.close() }
        document.performEdit("Fixture", recordReview: false) { $0.sections[0].paragraphs.append(Paragraph("Two")) }
        let editor = document.editorController!.editor
        editor.select(NSRange(location: editor.storage.length, length: 0))
        editor.activeTextView.insertText("X", replacementRange: editor.activeTextView.selectedRange())
        editor.select(NSRange(location: 1, length: 0)); editor.activeTextView.insertNewline(nil)
        var model = document.snapshot(); try NativeFormat.validate(model)
        XCTAssertEqual(model.paragraphs.map(\.text), ["O", "ne", "TwoX"])
        XCTAssertLessThan(editor.reviewEditing.lastParagraphValidationLength, editor.storage.length)
        try model.resolveAllRevisions(accepting: false)
        XCTAssertEqual(model.paragraphs.map(\.text), ["One", "Two"])
    }
    func testTrailingEmptyParagraphKeepsFocusAndTypingStyleAfterPageReflow() throws {
        let document = ScribeFileDocument(); defer { document.close() }
        var paragraph = Paragraph("Line\u{2028}Line\u{2028}Line\u{2028}Line")
        paragraph.runs[0].format.bold = true; paragraph.runs[0].format.italic = true
        document.model.sections[0].paragraphs = [paragraph]
        document.model.sections[0].page.height = 216
        document.makeWindowControllers()
        let editor = document.editorController!.editor
        editor.reviewEditing.author = .init(name: "Writer")
        editor.select(NSRange(location: editor.storage.length, length: 0))
        editor.activeTextView.insertNewline(nil); editor.paginate()
        XCTAssertGreaterThanOrEqual(editor.canvas.pageCount, 2)
        let extra = try XCTUnwrap(editor.layout.extraLineFragmentTextContainer)
        XCTAssertTrue(editor.activeTextView.textContainer === extra)
        XCTAssertEqual(editor.activeTextView.selectedRange().location, editor.storage.length)
        let empty = document.snapshot(); try NativeFormat.validate(empty)
        XCTAssertEqual(empty.paragraphs.last?.runs.first?.format.bold, true)
        XCTAssertEqual(empty.paragraphs.last?.runs.first?.format.italic, true)
        editor.activeTextView.insertText("X", replacementRange: editor.activeTextView.selectedRange())
        let typed = document.snapshot(); try NativeFormat.validate(typed)
        XCTAssertEqual(typed.paragraphs.last?.id, empty.paragraphs.last?.id)
        XCTAssertEqual(typed.paragraphs.last?.text, "X")
        XCTAssertEqual(typed.paragraphs.last?.runs.first?.format.bold, true)
    }
    func testPaginationDoesNotMoveAnActiveCompositionToAnotherInputClient() throws {
        let document = ScribeFileDocument(); defer { document.close() }
        document.model.sections[0].paragraphs = [Paragraph("Body")]
        document.model.sections[0].page.height = 216
        document.makeWindowControllers()
        let editor = document.editorController!.editor
        editor.reviewEditing.author = .init(name: "Writer")
        editor.select(NSRange(location: 4, length: 0))
        let view = editor.activeTextView, provisional = String(repeating: " provisional text", count: 60)
        view.setMarkedText(provisional, selectedRange: NSRange(location: provisional.utf16.count, length: 0), replacementRange: NSRange(location: 4, length: 0))
        editor.paginate()
        XCTAssertGreaterThan(editor.canvas.pageCount, 1)
        XCTAssertTrue(editor.canvas.window?.firstResponder === view)
        XCTAssertNotNil(view.reviewComposition)
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "Body")
        view.cancelOperation(nil)
        XCTAssertEqual(editor.storage.string, "Body")
        XCTAssertFalse(document.snapshot().hasPendingRevisions)
    }
    func testExplicitNewlineReplacementTreatsLiteralTabsAsContent() throws {
        let document = document(Paragraph("\tField\tvalue")); defer { document.close() }
        let editor = document.editorController!.editor
        editor.select(NSRange(location: editor.storage.length, length: 0))
        editor.activeTextView.insertText("\n", replacementRange: NSRange(location: 1, length: 5))
        var model = document.snapshot(); try NativeFormat.validate(model)
        XCTAssertEqual(model.paragraphs.map(\.text), ["\tField", "\tvalue"])
        XCTAssertEqual(model.pendingRevisionIDs.count, 2)
        try model.resolveAllRevisions(accepting: false)
        XCTAssertEqual(model.paragraphs[0].text, "\tField\tvalue")
    }
}
#endif
