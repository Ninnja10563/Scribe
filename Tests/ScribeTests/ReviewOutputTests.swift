#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ReviewOutputTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func fixture() -> ScribeDocument {
        let author = RevisionAuthor(name: "Writer")
        func changed(_ text: String, insertion: Bool) -> TextRun {
            var run = TextRun(text), review = RunReview()
            if insertion { review.insertion = .init(author: author) } else { review.deletion = .init(author: author) }
            run.review = review; return run
        }
        var document = ScribeDocument(), note = DocumentNote(kind: .footnote)
        note.paragraphs[0].runs = [changed("Note old", insertion: false), changed("Note new", insertion: true)]
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        document.notes = [note]
        document.sections[0].paragraphs[0].runs = [changed("Old ", insertion: false), changed("New ", insertion: true), TextRun("stable"), reference]
        return document
    }
    func testAllReviewOutputModesKeepSourceAndRecoveryIdentityIndependent() throws {
        let source = fixture(), original = source
        for mode in ReviewOutputMode.allCases {
            let output = try ReviewOutputSession(source: source, mode: mode); defer { output.close() }
            XCTAssertNotEqual(output.editor.owner?.model.id, source.id)
            let projected = try XCTUnwrap(output.editor.owner?.model)
            switch mode {
            case .marked:
                XCTAssertTrue(projected.hasPendingRevisions)
                XCTAssertEqual(projected.notes[0].plainText, "Note oldNote new")
            case .accepted:
                XCTAssertFalse(projected.hasPendingRevisions)
                XCTAssertEqual(projected.paragraphs[0].text, "New stable\u{fffc}")
                XCTAssertEqual(projected.notes[0].plainText, "Note new")
            case .rejected:
                XCTAssertFalse(projected.hasPendingRevisions)
                XCTAssertEqual(projected.paragraphs[0].text, "Old stable\u{fffc}")
                XCTAssertEqual(projected.notes[0].plainText, "Note old")
            }
            if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
                let folder = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name: String
                switch mode { case .marked: name = "Marked"; case .accepted: name = "Accepted"; case .rejected: name = "Rejected" }
                try output.renderer.exportPDF(to: folder.appendingPathComponent("ReviewOutput" + name + ".pdf"), title: name, author: "Writer")
                XCTAssertFalse(output.editor.drawingReviewMarkup)
                for page in output.editor.canvas.footnotes.values {
                    for fragment in page.notes {
                        XCTAssertFalse((fragment.note.layout.delegate as? ScreenTextAttributes)?.includeReviewInOutput ?? true)
                    }
                }
            }
            XCTAssertEqual(source, original)
        }
    }
    func testPDFPageValidationFollowsChosenReviewLayout() throws {
        var source = ScribeDocument(), review = RunReview()
        review.deletion = .init(author: .init(name: "Writer"))
        var text = TextRun(String(repeating: "A paragraph of retained old content. ", count: 600)); text.review = review
        source.sections[0].paragraphs[0].runs = [text, TextRun("Final text")]
        let initial = try ReviewOutputSession(source: source, mode: .marked); defer { initial.close() }
        XCTAssertGreaterThan(initial.editor.canvas.pageCount, 1)
        let options = PDFExportAccessory(pageCount: initial.editor.canvas.pageCount, title: "Review", author: "Writer", hasPendingRevisions: true)
        options.onReviewModeChange = { mode in
            let output = try ReviewOutputSession(source: source, mode: mode); defer { output.close() }
            return output.editor.canvas.pageCount
        }
        options.pages.stringValue = "2"
        options.reviewChoice.selectItem(withTitle: ReviewOutputMode.accepted.rawValue); options.changeReviewMode()
        XCTAssertEqual(options.pageCount, 1)
        XCTAssertThrowsError(try options.selectedPages())
        options.pages.stringValue = ""; XCTAssertEqual(try options.selectedPages(), [0])
        options.layoutSubtreeIfNeeded(); NativeDialogCapture.save(options, name: "PDFReviewOptions")
    }
}
#endif
