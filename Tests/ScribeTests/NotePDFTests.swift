#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NotePDFTests: XCTestCase {
    func testPDFContainsNoteTextAndBidirectionalLinksIncludingPartialExports() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument()
        let heading = Paragraph("Source heading", style: "heading1")
        var foot = DocumentNote(kind: .footnote, text: "Read the source heading.")
        foot.paragraphs[0].runs[0].link = DocumentLink.paragraph(heading.id)
        var end = DocumentNote(kind: .endnote, text: "External source.")
        end.paragraphs[0].runs[0].link = "https://example.org/source"
        document.model.notes = [foot, end]
        var paragraph = Paragraph("Body with references ")
        for note in document.model.notes {
            var reference = TextRun("\u{fffc}"); reference.noteID = note.id; paragraph.runs.append(reference)
        }
        document.model.sections[0].paragraphs = [heading, paragraph]
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        XCTAssertNil(editor.outputWarning); XCTAssertEqual(editor.canvas.pageCount, 2)
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("NativeNotes.pdf"), partial = directory.appendingPathComponent("NativeNotes-partial.pdf")
        let renderer = PrintRenderer(editor: editor)
        try renderer.exportPDF(to: url, title: "Notes", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertTrue(pdf.string?.contains("Read the source heading.") == true)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("External source.") == true)
        let first = try XCTUnwrap(pdf.page(at: 0)), second = try XCTUnwrap(pdf.page(at: 1))
        func destination(_ annotation: PDFAnnotation) -> PDFDestination? { annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination }
        XCTAssertTrue(first.annotations.contains { destination($0)?.page === second }, "Body reference must navigate to its endnote")
        XCTAssertTrue(second.annotations.contains { destination($0)?.page === first }, "Endnote label must navigate back to the body reference")
        XCTAssertTrue(first.annotations.contains { destination($0)?.page === first }, "Footnotes and their internal source links remain navigable")
        XCTAssertTrue(second.annotations.contains { ($0.action as? PDFActionURL)?.url?.absoluteString == "https://example.org/source" })
        XCTAssertFalse((first.annotations + second.annotations).contains { ($0.action as? PDFActionURL)?.url?.scheme == "scribe" })
        try renderer.exportPDF(to: partial, title: "Body only", author: "", pages: [0])
        let selected = try XCTUnwrap(PDFDocument(url: partial)?.page(at: 0))
        XCTAssertFalse(selected.annotations.contains { destination($0)?.page == nil && ($0.action as? PDFActionURL) == nil })
        XCTAssertEqual(document.snapshot().notes, [foot, end])
    }
}
#endif
