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
}
#endif
