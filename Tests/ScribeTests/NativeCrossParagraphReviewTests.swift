#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NativeCrossParagraphReviewTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func document(_ paragraphs: [Paragraph]) -> ScribeFileDocument {
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs = paragraphs
        document.makeWindowControllers(); document.editorController!.editor.reviewEditing.author = .init(name: "Writer")
        return document
    }
    func testReplacementAcrossOriginalParagraphsRejectsAndAcceptsWithoutLosingText() throws {
        let document = document([Paragraph("Alpha"), Paragraph("Beta"), Paragraph("Gamma")]); defer { document.close() }
        let editor = document.editorController!.editor, original = document.snapshot()
        let range = NSRange(location: 2, length: 11)
        editor.select(range); document.undoManager?.removeAllActions()
        // Preflight errors are test failures, rather than a modal error panel.
        _ = try editor.reviewEditing.replacement(in: editor, range: range, with: NSAttributedString(string: "X", attributes: editor.activeTextView.typingAttributes))
        editor.activeTextView.insertText("X", replacementRange: range)
        let changed = document.snapshot(); try NativeFormat.validate(changed)
        var rejected = changed; try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual(rejected.paragraphs.map(\.text), original.paragraphs.map(\.text))
        XCTAssertEqual(rejected.paragraphs.map(\.id), original.paragraphs.map(\.id))
        var accepted = changed; try accepted.resolveAllRevisions(accepting: true)
        XCTAssertEqual(accepted.paragraphs.map(\.text), ["AlXmma"])
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, original.paragraphs)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs, changed.paragraphs)
    }
    func testFormattingAParagraphMarkDoesNotInsertAnotherParagraph() throws {
        let document = document([Paragraph("A"), Paragraph("B")]); defer { document.close() }
        let editor = document.editorController!.editor, original = document.snapshot()
        editor.select(NSRange(location: 1, length: 1)); editor.activeTextView.toggleBold(nil)
        XCTAssertEqual(document.snapshot().paragraphs, original.paragraphs)
        XCTAssertFalse(document.snapshot().hasPendingRevisions)
    }
    func testReturnAcrossOriginalParagraphsPreservesReviewAndCaret() throws {
        let document = document([Paragraph("Alpha"), Paragraph("Beta")]); defer { document.close() }
        let editor = document.editorController!.editor, original = document.snapshot()
        editor.select(NSRange(location: 2, length: 6)); editor.activeTextView.insertNewline(nil)
        let changed = document.snapshot(); try NativeFormat.validate(changed)
        XCTAssertEqual(changed.paragraphs.map(\.text), ["Alpha", "Be", "ta"])
        XCTAssertEqual(editor.activeTextView.selectedRange().location, editor.activeTextView.listContext()?.contentStart)
        var accepted = changed; try accepted.resolveAllRevisions(accepting: true)
        XCTAssertEqual(accepted.paragraphs.map(\.text), ["Al", "ta"])
        var rejected = changed; try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual(rejected.paragraphs, original.paragraphs)
    }
    func testReplacingAcrossOwnListSplitDoesNotTurnGeneratedNumberIntoAuthoredText() throws {
        var paragraph = Paragraph("ABCD"); paragraph.list = .init(kind: .decimal, start: 4, restart: true)
        let document = document([paragraph]); defer { document.close() }
        let editor = document.editorController!.editor
        editor.selectListContent(id: paragraph.id)
        let start = try XCTUnwrap(editor.activeTextView.listContext()?.contentStart)
        editor.select(NSRange(location: start + 2, length: 0)); editor.activeTextView.insertNewline(nil)
        let continuationStart = try XCTUnwrap(editor.activeTextView.listContext()?.contentStart)
        let range = NSRange(location: start + 1, length: continuationStart + 1 - (start + 1))
        editor.select(range)
        let beforeReplacement = document.snapshot()
        document.undoManager?.removeAllActions()
        _ = try editor.reviewEditing.replacement(in: editor, range: range, with: NSAttributedString(string: "X", attributes: editor.activeTextView.typingAttributes))
        editor.activeTextView.insertText("X", replacementRange: range)
        let changed = document.snapshot(); try NativeFormat.validate(changed)
        var rejected = changed; try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual(rejected.paragraphs.map(\.text), ["ABCD"])
        XCTAssertEqual(rejected.paragraphs.first?.list, paragraph.list)
        var accepted = changed; try accepted.resolveAllRevisions(accepting: true)
        XCTAssertEqual(accepted.paragraphs.map(\.text), ["AXD"])
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, beforeReplacement.paragraphs)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs, changed.paragraphs)
    }
}
#endif
