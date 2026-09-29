#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NativeListReviewTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func document(_ text: String) -> ScribeFileDocument {
        let document = ScribeFileDocument(); var paragraph = Paragraph(text)
        paragraph.list = .init(kind: .decimal, start: 4, restart: true)
        document.model.sections[0].paragraphs = [paragraph]
        document.makeWindowControllers(); document.editorController!.editor.reviewEditing.author = .init(name: "Writer")
        document.undoManager?.removeAllActions(); return document
    }
    func testTypingInsideGeneratedMarkerTargetsContentAndUndoPreservesNumbering() throws {
        for value in ["X", "4"] {
            let document = document("Body"); defer { document.close() }
            let editor = document.editorController!.editor
            let before = document.snapshot()
            let marker = (editor.storage.string as NSString).range(of: "4")
            editor.select(marker)
            editor.activeTextView.insertText(value, replacementRange: marker)
            let changed = document.snapshot()
            XCTAssertEqual(changed.paragraphs[0].text, value + "Body")
            XCTAssertTrue(editor.storage.string.hasPrefix("\t4.\t"))
            XCTAssertEqual(changed.paragraphs[0].runs.filter { $0.review?.insertion != nil }.map(\.text).joined(), value)
            try NativeFormat.validate(changed)
            document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, before.paragraphs)
            document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs, changed.paragraphs)
        }
    }
    func testDeletingOnlyGeneratedMarkerDoesNotCreateRevision() throws {
        let document = document("Body"); defer { document.close() }
        let editor = document.editorController!.editor
        let before = document.snapshot()
        editor.select(NSRange(location: 1, length: 2))
        editor.activeTextView.deleteBackward(nil)
        XCTAssertEqual(document.snapshot(), before)
        XCTAssertFalse(document.undoManager?.canUndo ?? true)
        XCTAssertEqual(editor.activeTextView.selectedRange().location, 4)
    }
    func testFormattingSelectionIncludingMarkerTracksOnlyAuthoredContent() throws {
        let document = document("Body"); defer { document.close() }
        let editor = document.editorController!.editor
        editor.select(NSRange(location: 1, length: 5))
        editor.activeTextView.toggleBold(nil)
        let changed = document.snapshot()
        XCTAssertEqual(changed.paragraphs[0].text, "Body")
        XCTAssertEqual(changed.paragraphs[0].runs.filter { !($0.review?.formatting.isEmpty ?? true) }.map(\.text).joined(), "Bo")
        XCTAssertTrue(editor.storage.string.hasPrefix("\t4.\t"))
        try NativeFormat.validate(changed)
    }
    func testLiteralTabsInOrdinaryParagraphRemainEditableContent() throws {
        let document = document("\t4.\tBody"); defer { document.close() }
        document.performEdit("Remove List", recordReview: false) { $0.sections[0].paragraphs[0].list = nil }
        let editor = document.editorController!.editor
        editor.select(NSRange(location: 1, length: 1))
        editor.activeTextView.insertText("X", replacementRange: NSRange(location: 1, length: 1))
        var model = document.snapshot()
        try model.resolveAllRevisions(accepting: true)
        XCTAssertEqual(model.paragraphs[0].text, "\tX.\tBody")
    }
    func testMarkedInputInsideListMarkerPreservesNumberDuringComposeCommitAndCancel() throws {
        for commit in [false, true] {
            let document = document("Body"); defer { document.close() }
            let editor = document.editorController!.editor, before = document.snapshot()
            editor.select(NSRange(location: 1, length: 1))
            let view = editor.activeTextView
            view.setMarkedText("語", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertTrue(editor.storage.string.hasPrefix("\t4.\t"))
            XCTAssertEqual(document.snapshot(), before)
            if commit {
                view.unmarkText()
                let changed = document.snapshot()
                XCTAssertEqual(changed.paragraphs[0].text, "語Body")
                XCTAssertTrue(changed.hasPendingRevisions)
                try NativeFormat.validate(changed)
                document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, before.paragraphs)
            } else {
                view.cancelOperation(nil)
                XCTAssertEqual(document.snapshot(), before)
                XCTAssertFalse(document.undoManager?.canUndo ?? true)
            }
        }
    }
    func testNativeReturnTracksSeparatorWithoutNumberingTextAndUndoRestores() throws {
        let document = document("First second"); defer { document.close() }
        let editor = document.editorController!.editor, before = document.snapshot()
        editor.selectListContent(id: before.paragraphs[0].id)
        let start = try XCTUnwrap(editor.activeTextView.listContext()?.contentStart)
        editor.select(NSRange(location: start + 5, length: 1)); editor.activeTextView.insertNewline(nil)
        let changed = document.snapshot(); try NativeFormat.validate(changed)
        XCTAssertEqual(changed.paragraphs.map(\.text), ["First ", "second"])
        XCTAssertEqual(changed.pendingRevisionIDs.count, 2)
        XCTAssertEqual(editor.activeTextView.selectedRange().location, editor.activeTextView.listContext()?.contentStart)
        XCTAssertTrue(editor.storage.string.contains("\t5.\tsecond"))
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, before.paragraphs)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs, changed.paragraphs)
        var rejected = changed; try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual(rejected.paragraphs[0].text, "First second"); XCTAssertEqual(rejected.paragraphs.count, 1)
    }
    func testReturnAfterTrackedListFormattingKeepsBothHistories() throws {
        let document = document("AB"); defer { document.close() }
        let editor = document.editorController!.editor
        editor.applyList(.init(kind: .lowerRoman, level: 1))
        let format = try XCTUnwrap(document.snapshot().pendingRevisionIDs.first)
        editor.selectListContent(id: document.snapshot().paragraphs[0].id)
        let start = try XCTUnwrap(editor.activeTextView.listContext()?.contentStart)
        editor.select(NSRange(location: start + 1, length: 0)); editor.activeTextView.insertNewline(nil)
        var model = document.snapshot(); try NativeFormat.validate(model)
        XCTAssertEqual(model.pendingRevisionIDs.count, 2)
        let split = try XCTUnwrap(model.paragraphs[0].breakReview?.insertion?.id)
        try model.resolveRevision(split, accepting: false)
        XCTAssertEqual(model.paragraphs[0].text, "AB"); XCTAssertEqual(model.pendingRevisionIDs, [format])
    }
    func testForwardDeleteOwnListSeparatorRemovesGeneratedMarkerAndCanUndo() async throws {
        let document = document("AB"); defer { document.close() }
        let editor = document.editorController!.editor
        editor.selectListContent(id: document.model.paragraphs[0].id)
        let start = try XCTUnwrap(editor.activeTextView.listContext()?.contentStart)
        editor.select(NSRange(location: start + 1, length: 0)); editor.activeTextView.insertNewline(nil)
        let split = document.snapshot(); try NativeFormat.validate(split)
        try await Task.sleep(nanoseconds: 30_000_000)
        let separator = (editor.storage.string as NSString).range(of: "\n").location
        editor.select(NSRange(location: separator, length: 0)); editor.activeTextView.deleteForward(nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        let joined = document.snapshot(); try NativeFormat.validate(joined)
        XCTAssertEqual(joined.paragraphs.map(\.text), ["AB"])
        XCTAssertFalse(editor.storage.string.contains("\t5.\t"))
        XCTAssertFalse(joined.hasPendingRevisions)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, split.paragraphs)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs, joined.paragraphs)
    }
    func testRepeatedForwardDeleteSkipsGeneratedMarkerAfterRetainedBoundary() throws {
        let document = document("A"); defer { document.close() }
        let editor = document.editorController!.editor
        document.performEdit("Fixture", recordReview: false) { model in
            var next = Paragraph("B"); next.list = .init(kind: .decimal)
            model.sections[0].paragraphs.append(next)
        }
        let separator = (editor.storage.string as NSString).range(of: "\n").location
        editor.select(NSRange(location: separator, length: 0)); editor.activeTextView.deleteForward(nil)
        XCTAssertEqual(editor.activeTextView.selectedRange().location, editor.activeTextView.listContext()?.contentStart)
        editor.activeTextView.deleteForward(nil)
        var model = document.snapshot(); try NativeFormat.validate(model)
        XCTAssertEqual(model.paragraphs.map(\.text), ["A", "B"])
        XCTAssertEqual(model.pendingRevisionIDs.count, 2)
        XCTAssertEqual(RevisionText(runs: model.paragraphs[1].runs).finalText, "")
        try model.resolveAllRevisions(accepting: true)
        XCTAssertEqual(model.paragraphs.map(\.text), ["A"])
    }
    func testReturnThenBackspaceOutdentAndJoinEditsOwnDraftWithoutLosingUndo() async throws {
        let document = document("AB"); defer { document.close() }
        let editor = document.editorController!.editor
        editor.selectListContent(id: document.model.paragraphs[0].id)
        let start = try XCTUnwrap(editor.activeTextView.listContext()?.contentStart)
        editor.select(NSRange(location: start + 1, length: 0)); editor.activeTextView.insertNewline(nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        editor.activeTextView.deleteBackward(nil)
        let outdented = document.snapshot(); try NativeFormat.validate(outdented)
        XCTAssertNil(outdented.paragraphs[1].list); XCTAssertEqual(outdented.pendingRevisionIDs.count, 2)
        try await Task.sleep(nanoseconds: 30_000_000)
        editor.activeTextView.deleteBackward(nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        let joined = document.snapshot(); try NativeFormat.validate(joined)
        XCTAssertEqual(joined.paragraphs.map(\.text), ["AB"]); XCTAssertFalse(joined.hasPendingRevisions)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, outdented.paragraphs)
    }
    func testEmptyListReturnTracksExitAndUndo() throws {
        let document = document(""); defer { document.close() }
        let editor = document.editorController!.editor
        editor.selectListContent(id: document.model.paragraphs[0].id)
        editor.activeTextView.insertNewline(nil)
        var model = document.snapshot(); try NativeFormat.validate(model)
        XCTAssertNil(model.paragraphs[0].list); XCTAssertEqual(model.pendingRevisionIDs.count, 1)
        XCTAssertNil(model.paragraphs[0].formatting)
        let paragraphStyle = editor.activeTextView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(paragraphStyle?.headIndent, 0)
        try model.resolveAllRevisions(accepting: false); XCTAssertEqual(model.paragraphs[0].list?.start, 4)
        document.undoManager?.undo(); XCTAssertNotNil(document.snapshot().paragraphs[0].list)
    }
}
#endif
