#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NativeParagraphFormattingReviewTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func document(_ paragraphs: [Paragraph]) -> ScribeFileDocument {
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs = paragraphs
        document.makeWindowControllers(); document.editorController!.editor.reviewEditing.author = .init(name: "Reviewer")
        document.undoManager?.removeAllActions()
        return document
    }
    func testNativeAlignmentAndSpacingKeepIndependentDecisionsThroughUndo() async throws {
        let document = document([Paragraph("Body")]); defer { document.close() }
        let editor = document.editorController!.editor
        editor.select(NSRange(location: 0, length: 4)); editor.activeTextView.alignCenter(nil)
        let first = document.snapshot(), alignment = try XCTUnwrap(first.pendingRevisionIDs.first)
        XCTAssertEqual(first.paragraphs[0].formatting?.alignment, .center)
        try await Task.sleep(nanoseconds: 30_000_000) // Separate user commands arrive in separate events.
        try document.editorController!.applyParagraphGeometry([14, 0, 8, 0, 0, 0])
        try await Task.sleep(nanoseconds: 30_000_000)
        let both = document.snapshot(); XCTAssertEqual(both.pendingRevisionIDs.count, 2)
        try NativeFormat.validate(both)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs[0].formattingReview, first.paragraphs[0].formattingReview)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs[0].formattingReview, both.paragraphs[0].formattingReview)
        var rejected = both; try rejected.resolveRevision(alignment, accepting: false)
        XCTAssertEqual(rejected.paragraphs[0].formatting?.alignment, .left)
        XCTAssertEqual(rejected.paragraphs[0].formatting?.lineSpacing, 14)
    }
    func testListProjectionKeepsSemanticFormattingAndTypingHistory() throws {
        let document = document([Paragraph("Body")]); defer { document.close() }
        let editor = document.editorController!.editor
        editor.applyList(.init(kind: .decimal, level: 1))
        let listModel = document.snapshot()
        XCTAssertNil(listModel.paragraphs[0].formatting)
        XCTAssertEqual(listModel.paragraphs[0].list?.level, 1)
        try NativeFormat.validate(listModel)
        let id = try XCTUnwrap(listModel.pendingRevisionIDs.first)
        editor.select(NSRange(location: editor.storage.length, length: 0))
        editor.activeTextView.insertText("!", replacementRange: editor.activeTextView.selectedRange())
        var model = document.snapshot(); try NativeFormat.validate(model)
        XCTAssertEqual(model.pendingRevisionIDs.count, 2)
        try model.resolveRevision(id, accepting: false)
        XCTAssertNil(model.paragraphs[0].list); XCTAssertEqual(model.paragraphs[0].text, "Body!")
        XCTAssertEqual(model.pendingRevisionIDs.count, 1)
    }
    func testEmptyParagraphStyleHistorySurvivesSaveAndNativeUndo() throws {
        let document = document([Paragraph("")]); defer { document.close() }
        let editor = document.editorController!.editor
        editor.applyStyle("heading1")
        let changed = document.snapshot()
        XCTAssertEqual(changed.paragraphs[0].styleID, "heading1")
        XCTAssertEqual(changed.pendingRevisionIDs.count, 1)
        let saved = try NativeFormat.decode(document.data(ofType: ScribeFileDocument.typeName))
        XCTAssertEqual(saved.paragraphs[0].formattingReview, changed.paragraphs[0].formattingReview)
        document.undoManager?.undo(); XCTAssertFalse(document.snapshot().hasPendingRevisions)
        XCTAssertEqual(document.snapshot().paragraphs[0].styleID, "normal")
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs[0].formattingReview, changed.paragraphs[0].formattingReview)
    }
    func testSameTextRichPasteKeepsDestinationParagraphHistory() throws {
        let document = document([Paragraph("Body")]); defer { document.close() }
        let editor = document.editorController!.editor
        editor.applyStyle("heading1")
        let before = document.snapshot()
        editor.select(NSRange(location: 0, length: 4))
        let incoming = NSAttributedString(string: "Body", attributes: [
            .font: NSFont.systemFont(ofSize: 15), .scribeStyle: "normal",
            .scribeParagraphID: UUID().uuidString, .paragraphStyle: NSParagraphStyle.default])
        editor.activeTextView.replaceSelection(incoming, action: "Paste")
        let after = document.snapshot(); try NativeFormat.validate(after)
        XCTAssertEqual(after.paragraphs[0].id, before.paragraphs[0].id)
        XCTAssertEqual(after.paragraphs[0].styleID, "heading1")
        XCTAssertEqual(after.paragraphs[0].formattingReview, before.paragraphs[0].formattingReview)
        XCTAssertEqual(after.paragraphs[0].runs.first?.format.fontSize, 15)
        XCTAssertEqual(after.pendingRevisionIDs.count, 2)
    }
    func testMultiParagraphAlignmentUsesOneRevisionIdentity() throws {
        let document = document([Paragraph("First"), Paragraph("Second")]); defer { document.close() }
        let editor = document.editorController!.editor
        editor.select(NSRange(location: 0, length: editor.storage.length)); editor.activeTextView.alignRight(nil)
        var model = document.snapshot(); try NativeFormat.validate(model)
        XCTAssertEqual(model.pendingRevisionIDs.count, 1)
        XCTAssertTrue(model.paragraphs.allSatisfy { $0.formatting?.alignment == .right })
        try model.resolveAllRevisions(accepting: false)
        XCTAssertTrue(model.paragraphs.allSatisfy { $0.formatting == nil })
        XCTAssertEqual(model.paragraphs.map(\.text), ["First", "Second"])
    }
}
#endif
