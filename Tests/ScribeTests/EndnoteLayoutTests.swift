#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class EndnoteLayoutTests: XCTestCase {
    func testLongEndnotesFlowAfterBodyAndDisappearWhenReferencesAreDeleted() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument()
        var note = DocumentNote(kind: .endnote)
        note.paragraphs = (1...90).map { Paragraph("EndnoteToken\($0) " + String(repeating: "A detailed source explanation. ", count: 6)) }
        document.model.notes = [note]
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        document.model.sections[0].paragraphs[0].runs = [TextRun("Main body text."), reference]
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        XCTAssertNil(editor.layoutWarning)
        XCTAssertEqual(editor.textViews.count, 1)
        XCTAssertGreaterThan(editor.canvas.pageCount, 4)
        let total = editor.canvas.pageCount
        let renderer = PrintRenderer(editor: editor), combined = PDFDocument()
        for index in 0..<total {
            let data = renderer.dataWithPDF(inside: renderer.rectForPage(index + 1))
            let pdf = try XCTUnwrap(PDFDocument(data: data))
            combined.insert(try XCTUnwrap(pdf.page(at: 0)), at: combined.pageCount)
            if index == 0 { XCTAssertFalse(pdf.string?.contains("EndnoteToken") == true) }
        }
        let text = try XCTUnwrap(combined.string)
        for index in 1...90 { XCTAssertTrue(text.contains("EndnoteToken\(index) "), "Missing endnote paragraph \(index)") }
        XCTAssertEqual(document.snapshot().notes, [note])
        if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try XCTUnwrap(combined.dataRepresentation()).write(to: url.appendingPathComponent("EndnotePagination.pdf"))
        }
        editor.select(NSRange(location: ("Main body text." as NSString).length, length: 1))
        editor.activeTextView.replaceSelection(NSAttributedString(string: ""), action: "Delete Endnote")
        editor.paginate()
        XCTAssertEqual(editor.canvas.pageCount, 1); XCTAssertNil(editor.canvas.endnotes)
        document.undoManager?.undo(); editor.paginate()
        XCTAssertEqual(editor.canvas.pageCount, total)
        XCTAssertEqual(document.snapshot().notes, [note])
    }
    func testEndnotesRespectPageBudget() throws {
        _ = NSApplication.shared
        var note = DocumentNote(kind: .endnote)
        note.paragraphs = (0..<100).map { Paragraph("Paragraph \($0) " + String(repeating: "Long source text. ", count: 10)) }
        let numbered = try NoteNumbering.resolve(referenceIDs: [note.id], notes: [note])
        XCTAssertThrowsError(try EndnoteLayout(notes: numbered, styles: ParagraphStyle.defaults, page: PageSettings(), maximumPages: 1))
    }
}
#endif
