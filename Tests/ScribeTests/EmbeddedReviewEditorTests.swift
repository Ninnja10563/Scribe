#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class EmbeddedReviewEditorTests: XCTestCase {
    func testWindowlessEditorCapturesTrackedTypingAndStructuralUndo() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument()
        document.isTransientEditingSession = true
        document.model.sections[0].paragraphs = [Paragraph("AB")]
        let editor = PaginatedEditor(document: document)
        document.embeddedEditor = editor
        editor.onChange = { [weak document] in document?.didEdit() }
        defer { document.close() }
        editor.reviewEditing.author = .init(name: "Writer")
        editor.select(NSRange(location: 1, length: 0))
        editor.activeTextView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        let typed = document.snapshot()
        XCTAssertEqual(typed.paragraphs[0].text, "AXB")
        XCTAssertTrue(typed.hasPendingRevisions)
        document.undoManager?.removeAllActions()
        editor.activeTextView.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
        let split = document.snapshot()
        XCTAssertEqual(split.paragraphs.map(\.text), ["AX", "B"])
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().paragraphs, typed.paragraphs)
        document.undoManager?.redo()
        XCTAssertEqual(document.snapshot().paragraphs, split.paragraphs)
        XCTAssertNil(document.editorController)
        XCTAssertTrue(document.windowControllers.isEmpty)
    }
    func testCloseDetachesEmbeddedEditor() {
        _ = NSApplication.shared
        let document = ScribeFileDocument(); document.isTransientEditingSession = true
        let editor = PaginatedEditor(document: document); document.embeddedEditor = editor
        document.close()
        XCTAssertNil(document.embeddedEditor)
        XCTAssertNil(editor.owner)
        XCTAssertTrue(editor.textViews.allSatisfy { $0.editor == nil && $0.delegate == nil })
    }
}
#endif
