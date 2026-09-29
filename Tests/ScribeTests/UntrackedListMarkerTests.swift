#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
import ImportExport
@testable import Scribe

@MainActor final class UntrackedListMarkerTests: XCTestCase {
    private func fixture(_ texts: [String] = ["Body"]) -> ScribeFileDocument {
        _ = NSApplication.shared
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = texts.enumerated().map { index, text in
            var paragraph = Paragraph(text)
            paragraph.list = .init(kind: .decimal, start: 4, restart: index == 0 ? true : nil)
            return paragraph
        }
        document.makeWindowControllers(); document.undoManager?.removeAllActions()
        return document
    }
    func testDeletingListBoundaryDoesNotSaveGeneratedNumberAsText() throws {
        let document = fixture(["First", "Second"]); defer { document.close() }
        let editor = document.editorController!.editor, before = document.snapshot()
        let separator = (editor.storage.string as NSString).range(of: "\n").location
        editor.select(NSRange(location: separator, length: 0))
        editor.activeTextView.deleteForward(nil)
        let joined = document.snapshot()
        XCTAssertEqual(joined.paragraphs.map(\.text), ["FirstSecond"])
        try NativeFormat.validate(joined)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(joined)), joined)
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try NativeFormat.encode(joined).write(to: folder.appendingPathComponent("JoinedList.scribe"))
            try DOCX.encode(joined).write(to: folder.appendingPathComponent("JoinedList.docx"))
            try PrintRenderer(editor: editor).exportPDF(to: folder.appendingPathComponent("JoinedList.pdf"), title: "Joined list", author: "Scribe tests")
        }
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, before.paragraphs)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs, joined.paragraphs)
    }
    func testReplacingAcrossListItemsUsesSemanticCaretAndPreservesUndo() throws {
        for inserted in ["X", "X\n語"] {
            let document = fixture(["First", "Second"]); defer { document.close() }
            let editor = document.editorController!.editor, before = document.snapshot()
            let text = editor.storage.string as NSString
            let start = text.range(of: "First").location + 2
            let end = text.range(of: "Second").location + 2
            editor.select(NSRange(location: start, length: end - start))
            editor.activeTextView.insertText(inserted, replacementRange: NSRange(location: NSNotFound, length: 0))
            let changed = document.snapshot()
            XCTAssertEqual(changed.paragraphs.map(\.text), inserted.contains("\n") ? ["FiX", "語cond"] : ["FiXcond"])
            XCTAssertFalse(changed.hasPendingRevisions)
            let context = try XCTUnwrap(editor.activeTextView.listContext())
            XCTAssertEqual(editor.activeTextView.selectedRange().location - context.contentStart, inserted.contains("\n") ? 1 : 3)
            try NativeFormat.validate(changed)
            document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, before.paragraphs)
            document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs, changed.paragraphs)
        }
    }
    func testCompositionAcrossListItemsCommitsSemanticallyOrCancelsWithoutMutation() throws {
        for commit in [false, true] {
            let document = fixture(["First", "Second"]); defer { document.close() }
            let editor = document.editorController!.editor, before = document.snapshot()
            let source = editor.storage.string as NSString
            let start = source.range(of: "First").location + 2
            let end = source.range(of: "Second").location + 2
            editor.select(NSRange(location: start, length: end - start))
            let text = editor.activeTextView
            text.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertNotNil(text.reviewComposition)
            XCTAssertEqual(document.snapshot(), before)
            text.setMarkedText("語", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual(document.snapshot(), before)
            if commit {
                text.unmarkText()
                let changed = document.snapshot()
                XCTAssertEqual(changed.paragraphs.map(\.text), ["Fi語cond"])
                XCTAssertFalse(changed.hasPendingRevisions)
                try NativeFormat.validate(changed)
                document.undoManager?.undo(); XCTAssertEqual(document.snapshot(), before)
                document.undoManager?.redo(); XCTAssertEqual(document.snapshot(), changed)
            } else {
                text.cancelOperation(nil)
                XCTAssertEqual(document.snapshot(), before)
                XCTAssertFalse(document.undoManager?.canUndo ?? true)
            }
        }
    }
    func testCompositionEndingInsideNextMarkerHasCleanPreviewAndCanCancel() throws {
        let document = fixture(["First", "Second"]); defer { document.close() }
        let editor = document.editorController!.editor, before = document.snapshot()
        let source = editor.storage.string as NSString
        let start = source.range(of: "First").location + 2
        let end = source.range(of: "Second").location - 2
        editor.select(NSRange(location: start, length: end - start))
        let text = editor.activeTextView
        text.setMarkedText("語", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(editor.storage.string, "\t4.\tFi語Second")
        XCTAssertEqual(document.snapshot(), before)
        text.cancelOperation(nil)
        XCTAssertEqual(document.snapshot(), before)
        XCTAssertFalse(document.undoManager?.canUndo ?? true)
    }
    func testUndoDuringCrossListCompositionCancelsPreviewBeforeUndoingPriorEdit() throws {
        let document = fixture(["First", "Second"]); defer { document.close() }
        let editor = document.editorController!.editor, original = document.snapshot()
        editor.select(NSRange(location: editor.storage.length, length: 0))
        editor.activeTextView.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        let source = editor.storage.string as NSString
        let start = source.range(of: "First").location + 2
        let end = source.range(of: "Second").location + 2
        editor.select(NSRange(location: start, length: end - start))
        editor.activeTextView.setMarkedText("語", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        document.undoManager?.undo()
        XCTAssertNil(editor.activeTextView.reviewComposition)
        XCTAssertEqual(document.snapshot(), original)
        document.undoManager?.redo()
        XCTAssertEqual(document.snapshot().paragraphs.map(\.text), ["First", "Second!"])
        XCTAssertFalse(document.snapshot().hasPendingRevisions)
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
