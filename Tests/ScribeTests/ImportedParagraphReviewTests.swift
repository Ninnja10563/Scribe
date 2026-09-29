#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import ImportExport
@testable import Scribe

@MainActor final class ImportedParagraphReviewTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func importedDocument() throws -> ScribeDocument {
        let author = RevisionAuthor(name: "Paragraph reviewer")
        func flow(_ prefix: String) -> [Paragraph] {
            var first = Paragraph(prefix + " first"), review = RunReview()
            review.deletion = .init(author: author); first.breakReview = review
            return [first, Paragraph(prefix + " second")]
        }
        var source = ScribeDocument(), note = DocumentNote(kind: .footnote)
        source.sections[0].paragraphs = flow("Body")
        note.paragraphs = flow("Note"); source.notes = [note]
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        source.sections[0].paragraphs[1].runs.append(reference)
        return try DOCX.decodePreservingRevisions(DOCXWriter(source, revisions: .runChanges).encode()).document
    }
    func testImportedParagraphBoundaryNavigationAndUndo() throws {
        let document = ScribeFileDocument(); document.model = try importedDocument()
        document.makeWindowControllers(); defer { document.close() }
        document.undoManager?.removeAllActions()
        let before = document.snapshot(), controller = try XCTUnwrap(document.editorController)
        let id = try XCTUnwrap(before.paragraphs[0].breakReview?.deletion?.id)
        XCTAssertTrue(controller.reviewNavigation.select(id))
        XCTAssertEqual(controller.editor.activeTextView.selectedRange(), NSRange(location: 10, length: 1))
        try controller.reviewNavigation.resolveCurrent(accepting: true)
        XCTAssertEqual(document.snapshot().paragraphs.count, 1)
        XCTAssertTrue(document.snapshot().paragraphs[0].text.hasPrefix("Body firstBody second"))
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().paragraphs, before.paragraphs)
        document.undoManager?.redo()
        XCTAssertEqual(document.snapshot().paragraphs.count, 1)
    }
    func testBodyAndNoteBoundaryDecisionsRenderTheirActualParagraphFlow() throws {
        let source = try importedDocument()
        for mode in [ReviewOutputMode.accepted, .rejected] {
            let session = try ReviewOutputSession(source: source, mode: mode); defer { session.close() }
            XCTAssertNil(session.editor.layoutWarning)
            if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
                let folder = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = mode == .accepted ? "Accepted" : "Rejected"
                try session.renderer.exportPDF(to: folder.appendingPathComponent("ImportedParagraphReview" + name + ".pdf"), title: name, author: "Paragraph reviewer")
            }
        }
        XCTAssertEqual(source.paragraphs.count, 2)
        XCTAssertEqual(source.notes[0].paragraphs.count, 2)
        XCTAssertTrue(source.hasPendingRevisions)
    }
}
#endif
