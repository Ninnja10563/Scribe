#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NativeRichPasteReviewTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func document() -> ScribeFileDocument {
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs = [Paragraph("AB")]
        document.makeWindowControllers(); document.editorController!.editor.reviewEditing.author = .init(name: "Writer")
        return document
    }
    func testRichMultilinePasteGroupsParagraphStylesAndRestoresNativeUndo() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, original = document.snapshot()
        var source = ScribeDocument(), title = Paragraph("X"), quote = Paragraph("Y")
        title.styleID = "title"; quote.styleID = "quote"; source.sections[0].paragraphs = [title, quote]
        editor.select(NSRange(location: 1, length: 0)); document.undoManager?.removeAllActions()
        editor.activeTextView.replaceSelection(AttributedDocument.render(source), action: "Paste")
        let changed = document.snapshot(); try NativeFormat.validate(changed)
        XCTAssertEqual(changed.paragraphs.map(\.text), ["AX", "YB"])
        XCTAssertEqual(changed.paragraphs.map(\.styleID), ["title", "quote"])
        let insertion = try XCTUnwrap(changed.paragraphs[0].breakReview?.insertion)
        XCTAssertNotNil(insertion.groupID)
        var rejected = changed; try rejected.resolveRevision(insertion.id, accepting: false)
        XCTAssertEqual(rejected.paragraphs, original.paragraphs)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, original.paragraphs)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs, changed.paragraphs)
    }
    func testDeletingPastedBreakDoesNotFreezeOriginalTextFormatting() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, original = document.snapshot()
        var source = ScribeDocument(), title = Paragraph("X"), quote = Paragraph("Y")
        title.styleID = "title"; quote.styleID = "quote"; source.sections[0].paragraphs = [title, quote]
        editor.select(NSRange(location: 1, length: 0))
        editor.activeTextView.replaceSelection(AttributedDocument.render(source), action: "Paste")
        let pasted = document.snapshot()
        let insertion = try XCTUnwrap(pasted.paragraphs[0].breakReview?.insertion?.id)
        let separator = (editor.storage.string as NSString).range(of: "\n").location
        editor.select(NSRange(location: separator, length: 0)); document.undoManager?.removeAllActions()
        editor.activeTextView.deleteForward(nil)
        let joined = document.snapshot(); try NativeFormat.validate(joined)
        XCTAssertEqual(joined.paragraphs.map(\.text), ["AXYB"])
        var rejected = joined; try rejected.resolveRevision(insertion, accepting: false)
        XCTAssertEqual(rejected.paragraphs, original.paragraphs)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs, pasted.paragraphs)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs, joined.paragraphs)
    }
    func testActualRTFPastePreservesParagraphAlignmentAndRejectsAsAGroup() throws {
        let document = document(); defer { document.close() }
        let editor = document.editorController!.editor, original = document.snapshot()
        let center = NSMutableParagraphStyle(); center.alignment = .center
        let right = NSMutableParagraphStyle(); right.alignment = .right
        let value = NSMutableAttributedString(string: "X\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 18), .paragraphStyle: center])
        value.append(NSAttributedString(string: "Y", attributes: [.font: NSFont.systemFont(ofSize: 15), .paragraphStyle: right]))
        let data = try value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let board = NSPasteboard.general; board.clearContents(); defer { board.clearContents() }
        XCTAssertTrue(board.setData(data, forType: .rtf))
        editor.select(NSRange(location: 1, length: 0)); editor.activeTextView.paste(nil)
        let changed = document.snapshot(); try NativeFormat.validate(changed)
        XCTAssertEqual(changed.paragraphs.map(\.text), ["AX", "YB"])
        XCTAssertEqual(changed.paragraphs.map { $0.formatting?.alignment }, [.center, .right])
        let insertion = try XCTUnwrap(changed.paragraphs[0].breakReview?.insertion?.id)
        var rejected = changed; try rejected.resolveRevision(insertion, accepting: false)
        XCTAssertEqual(rejected.paragraphs, original.paragraphs)
        var accepted = changed; try accepted.resolveRevision(insertion, accepting: true)
        XCTAssertFalse(accepted.hasPendingRevisions)
        XCTAssertEqual(accepted.paragraphs.map { $0.formatting?.alignment }, [.center, .right])
        let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Scribe-RichPaste-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try NativeFormat.encode(changed).write(to: folder.appendingPathComponent("GroupedRichPaste.scribe"))
        try NativeFormat.encode(accepted).write(to: folder.appendingPathComponent("AcceptedRichPaste.scribe"))
        try NativeFormat.encode(rejected).write(to: folder.appendingPathComponent("RejectedRichPaste.scribe"))
        try PrintRenderer(editor: editor).exportPDF(to: folder.appendingPathComponent("GroupedRichPaste.pdf"), title: "Rich paste", author: "Scribe tests")
    }
}
#endif
