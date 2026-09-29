#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class FootnotePaginationTests: XCTestCase {
    func testLivePagesReserveAndDrawNotesWithReferencesAcrossEdits() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument()
        var paragraphs: [Paragraph] = []
        for index in 0..<80 {
            var paragraph = Paragraph("Body paragraph \(index). " + String(repeating: "Words for native line wrapping. ", count: 4))
            if index % 7 == 0 {
                let note = DocumentNote(kind: .footnote, text: "CitationToken\(index) " + String(repeating: "Measured note content. ", count: 9))
                document.model.notes.append(note)
                var reference = TextRun("\u{fffc}"); reference.noteID = note.id
                paragraph.runs.append(reference)
            }
            paragraphs.append(paragraph)
        }
        document.model.sections[0].paragraphs = paragraphs
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        func check(_ phase: String) throws {
            editor.paginate(); XCTAssertNil(editor.layoutWarning)
            XCTAssertGreaterThan(editor.textViews.count, 3)
            var count = 0
            let renderer = PrintRenderer(editor: editor)
            let combined = PDFDocument()
            for (index, container) in editor.layout.textContainers.enumerated() {
                let glyphs = editor.layout.glyphRange(for: container)
                let characters = editor.layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                var expected: [String] = []
                editor.storage.enumerateAttribute(.scribeNote, in: characters) { value, _, _ in
                    if let data = value as? Data, let note = try? JSONDecoder().decode(DocumentNote.self, from: data) {
                        expected.append(note.plainText.components(separatedBy: " ")[0])
                    }
                }
                XCTAssertEqual(editor.canvas.footnotes[index]?.notes.count ?? 0, expected.count)
                let data = renderer.dataWithPDF(inside: renderer.rectForPage(index + 1))
                let pdf = try XCTUnwrap(PDFDocument(data: data))
                combined.insert(try XCTUnwrap(pdf.page(at: 0)), at: combined.pageCount)
                for token in expected { XCTAssertTrue(pdf.string?.contains(token) == true, "Missing \(token) on page \(index + 1)") }
                XCTAssertLessThanOrEqual(editor.layout.usedRect(for: container).maxY + (editor.canvas.footnotes[index]?.height ?? 0), editor.canvas.pageSettings.contentHeight + 0.5)
                count += expected.count
            }
            XCTAssertEqual(count, 12)
            if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
                let url = URL(fileURLWithPath: folder, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try XCTUnwrap(combined.dataRepresentation()).write(to: url.appendingPathComponent("Footnotes-\(phase).pdf"))
            }
        }
        try check("initial")
        editor.select(NSRange(location: 0, length: 0))
        editor.activeTextView.insertText(String(repeating: "New preceding material. ", count: 60), replacementRange: NSRange(location: 0, length: 0))
        try check("edited")
        document.undoManager?.undo(); try check("undo")
        let full = NSRange(location: 0, length: editor.storage.length)
        editor.storage.removeAttribute(.scribeNote, range: full)
        editor.paginate()
        XCTAssertTrue(editor.canvas.footnotes.isEmpty)
        XCTAssertTrue(editor.layout.textContainers.allSatisfy { $0.containerSize.height == editor.canvas.pageSettings.contentHeight })
    }
    func testLongFootnoteContinuesAcrossPagesWithoutTruncatingSemanticContent() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument()
        let note = DocumentNote(kind: .footnote, text: String(repeating: "Lengthy citation content. ", count: 1000))
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        document.model.notes = [note]; document.model.sections[0].paragraphs[0].runs = [reference]
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        XCTAssertNil(editor.layoutWarning)
        XCTAssertGreaterThan(editor.canvas.pageCount, 2)
        let renderer = PrintRenderer(editor: editor), combined = PDFDocument()
        for index in 0..<editor.canvas.pageCount {
            let data = renderer.dataWithPDF(inside: renderer.rectForPage(index + 1))
            let page = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0))
            combined.insert(page, at: combined.pageCount)
        }
        let text = (combined.string ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertEqual(text.components(separatedBy: "Lengthy citation content.").count - 1, 1000)
        if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try XCTUnwrap(combined.dataRepresentation()).write(to: url.appendingPathComponent("FootnoteContinuation.pdf"))
        }
        XCTAssertEqual(document.snapshot().notes, [note])
        XCTAssertNil(editor.outputWarning)
    }
}
#endif
