#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class InlinePageBreakTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    func testInlineBreaksSurviveProjectionWithoutBecomingParagraphProperties() {
        var document = ScribeDocument()
        document.sections[0].paragraphs = [Paragraph("Before\u{c}After"), Paragraph("\u{c}Start\u{c}")]
        let captured = AttributedDocument.capture(AttributedDocument.render(document), preserving: document)
        XCTAssertEqual(captured.paragraphs.map(\.text), document.paragraphs.map(\.text))
        XCTAssertFalse(captured.paragraphs[1].pageBreakBefore)
    }

    func testInsertPageBreakUsesCaretPositionAndNativeUndo() {
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs = [Paragraph("BeforeAfter")]
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        editor.select(NSRange(location: 6, length: 0)); document.undoManager?.removeAllActions()
        editor.activeTextView.insertPageBreak(nil)
        XCTAssertEqual(document.snapshot().paragraphs.map(\.text), ["Before\u{c}After"])
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().paragraphs.map(\.text), ["BeforeAfter"])
        document.undoManager?.redo()
        XCTAssertEqual(document.snapshot().paragraphs.map(\.text), ["Before\u{c}After"])
    }

    func testInlineBreakMovesFollowingTextToNextPrintedPage() throws {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = [Paragraph("Before the break\u{c}After the break")]
        let editor = PaginatedEditor(document: document)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Inline break", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("Before the break") == true)
        XCTAssertFalse(pdf.page(at: 0)?.string?.contains("After the break") == true)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("After the break") == true)
    }
}
#endif
