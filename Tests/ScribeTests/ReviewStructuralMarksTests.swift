#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ReviewStructuralMarksTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func fixture() throws -> ScribeDocument {
        var document = ScribeDocument(); document.sections[0].paragraphs = [Paragraph(""), Paragraph("Middle"), Paragraph("")]
        let author = RevisionAuthor(name: "Writer"), before = document
        var formatting = ParagraphFormatting(); formatting.alignment = .center
        document.sections[0].paragraphs[0].formatting = formatting
        document.sections[0].paragraphs[2].formatting = formatting
        try document.recordParagraphFormattingChanges(from: before, identity: .init(author: author))
        var inserted = RunReview(); inserted.insertion = .init(author: author)
        var deleted = RunReview(); deleted.deletion = .init(author: author)
        document.sections[0].paragraphs[0].breakReview = inserted
        document.sections[0].paragraphs[1].breakReview = deleted
        return document
    }
    func testEmptyParagraphsAndBreaksHaveMarginMarksWithoutTextOrLayoutChanges() throws {
        let document = ScribeFileDocument(); document.model = try fixture(); document.makeWindowControllers()
        defer { document.close() }
        let editor = document.editorController!.editor, original = document.snapshot()
        let glyphs = editor.layout.glyphRange(for: editor.layout.textContainers[0])
        let marks = ReviewStructuralMarks.marks(storage: editor.storage, layout: editor.layout,
            container: editor.layout.textContainers[0], glyphs: glyphs, trailingReview: original.paragraphs.last?.formattingReview)
        XCTAssertEqual(marks.filter { $0.kind == .insertedBreak }.count, 1)
        XCTAssertEqual(marks.filter { $0.kind == .deletedBreak }.count, 1)
        XCTAssertEqual(marks.filter { $0.kind == .paragraphFormatting }.count, 2)
        XCTAssertEqual(Set(marks.map(\.y)).count, 3)
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try PrintRenderer(editor: editor, showsReviewMarkup: true).exportPDF(to: folder.appendingPathComponent("ReviewStructuralMarked.pdf"), title: "Structural review", author: "Writer")
            try PrintRenderer(editor: editor).exportPDF(to: folder.appendingPathComponent("ReviewStructuralPlain.pdf"), title: "Structural review", author: "Writer")
        }
        XCTAssertEqual(document.snapshot(), original)
        XCTAssertEqual(editor.layout.glyphRange(for: editor.layout.textContainers[0]), glyphs)
    }
    func testFootnoteAndEndnoteStructuralMarksIncludeEmptyFinalParagraphs() throws {
        let paragraphs = try fixture().paragraphs
        for kind in [DocumentNote.Kind.footnote, .endnote] {
            var document = ScribeDocument(), note = DocumentNote(kind: kind); note.paragraphs = paragraphs
            var reference = TextRun("\u{fffc}"); reference.noteID = note.id
            document.notes = [note]; document.sections[0].paragraphs[0].runs = [reference]
            let output = try ReviewOutputSession(source: document, mode: .marked); defer { output.close() }
            if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
                let folder = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try output.renderer.exportPDF(to: folder.appendingPathComponent("ReviewStructural-" + kind.rawValue + ".pdf"), title: "Structural note review", author: "Writer")
            }
            if let note = output.editor.canvas.footnotes.values.first?.notes.first?.note {
                let marks = ReviewStructuralMarks.marks(storage: note.storage, layout: note.layout, container: note.container, glyphs: note.glyphRange, trailingReview: note.trailingReview)
                XCTAssertEqual(marks.count, 4)
            } else { XCTAssertNotNil(output.editor.canvas.endnotes) }
        }
    }
    func testCompletelyEmptyDocumentStillShowsParagraphFormatting() throws {
        let document = ScribeFileDocument(), before = document.model
        var formatting = ParagraphFormatting(); formatting.alignment = .center
        document.model.sections[0].paragraphs[0].formatting = formatting
        try document.model.recordParagraphFormattingChanges(from: before, identity: .init(author: .init(name: "Writer")))
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor, container = editor.layout.textContainers[0]
        XCTAssertEqual(editor.storage.length, 0)
        let marks = ReviewStructuralMarks.marks(storage: editor.storage, layout: editor.layout, container: container,
            glyphs: editor.layout.glyphRange(for: container), trailingReview: document.model.paragraphs[0].formattingReview)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks.first?.kind, .paragraphFormatting)
    }
    func testNarrowMarginRefusesClippedMarksWithoutOverwritingOutput() throws {
        var source = try fixture(); source.sections[0].page.left = 10
        let marked = try ReviewOutputSession(source: source, mode: .marked); defer { marked.close() }
        let accepted = try ReviewOutputSession(source: source, mode: .accepted); defer { accepted.close() }
        let options = PDFExportAccessory(pageCount: marked.editor.canvas.pageCount, title: "Review", author: "Writer", hasPendingRevisions: true)
        options.validateReviewOutput = { try marked.renderer.validateReviewMargins() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Existing.pdf"), sentinel = Data("Original file".utf8)
        try sentinel.write(to: url)
        XCTAssertThrowsError(try options.panel(NSObject(), validate: url))
        XCTAssertThrowsError(try marked.renderer.exportPDF(to: url, title: "Review", author: "Writer"))
        XCTAssertEqual(try Data(contentsOf: url), sentinel)
        options.validateReviewOutput = { try accepted.renderer.validateReviewMargins() }
        XCTAssertNoThrow(try options.panel(NSObject(), validate: url))
    }
}
#endif
