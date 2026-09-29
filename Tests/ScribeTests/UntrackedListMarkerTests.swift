#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class UntrackedListMarkerTests: XCTestCase {
    private func fixture() -> ScribeFileDocument {
        _ = NSApplication.shared
        let document = ScribeFileDocument(); var paragraph = Paragraph("Body")
        paragraph.list = .init(kind: .decimal, start: 4, restart: true)
        document.model.sections[0].paragraphs = [paragraph]
        document.makeWindowControllers(); document.undoManager?.removeAllActions()
        return document
    }
    func testTypingIntoMarkerPreservesNumberAndNativeUndo() throws {
        let document = fixture(); defer { document.close() }
        let editor = document.editorController!.editor, before = document.snapshot()
        editor.select(NSRange(location: 1, length: 1))
        editor.activeTextView.insertText("4", replacementRange: NSRange(location: NSNotFound, length: 0))
        let changed = document.snapshot()
        XCTAssertEqual(changed.paragraphs[0].text, "4Body")
        XCTAssertTrue(editor.storage.string.hasPrefix("\t4.\t"))
        XCTAssertFalse(changed.hasPendingRevisions)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, before.paragraphs)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs, changed.paragraphs)
    }
    func testDeletionAndFormattingExcludeNumbering() throws {
        let document = fixture(); defer { document.close() }
        let editor = document.editorController!.editor, before = document.snapshot()
        editor.select(NSRange(location: 1, length: 2)); editor.activeTextView.deleteBackward(nil)
        XCTAssertEqual(document.snapshot(), before)
        XCTAssertFalse(document.undoManager?.canUndo ?? true)
        editor.select(NSRange(location: 1, length: 5)); editor.activeTextView.toggleBold(nil)
        let bold = document.snapshot()
        XCTAssertEqual(bold.paragraphs[0].text, "Body")
        XCTAssertEqual(bold.paragraphs[0].runs.filter { $0.format.bold == true }.map(\.text).joined(), "Bo")
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, before.paragraphs)
        editor.select(NSRange(location: 1, length: 5)); editor.activeTextView.deleteBackward(nil)
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "dy")
        XCTAssertTrue(editor.storage.string.hasPrefix("\t4.\t"))
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, before.paragraphs)
    }
    func testUntrackedMarkedInputKeepsGeneratedNumberIntact() throws {
        let document = fixture(); defer { document.close() }
        let editor = document.editorController!.editor
        editor.select(NSRange(location: 1, length: 1))
        let text = editor.activeTextView
        text.setMarkedText("語", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.storage.string.hasPrefix("\t4.\t"))
        text.insertText("語", replacementRange: NSRange(location: NSNotFound, length: 0))
        let changed = document.snapshot()
        XCTAssertEqual(changed.paragraphs[0].text, "語Body")
        XCTAssertFalse(changed.hasPendingRevisions)
        try NativeFormat.validate(changed)
    }
}
#endif
