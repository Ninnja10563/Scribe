#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import ImportExport
@testable import Scribe

@MainActor final class ImportedReviewTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func importedDocument() throws -> ScribeDocument {
        var source = ScribeDocument()
        let author = RevisionAuthor(name: "Office reviewer")
        var before = TextFormatting(); before.fontFamily = "Helvetica"; before.fontSize = 14
        before.italic = true; before.foreground = "#123456"
        var formatted = RevisionText(runs: [TextRun("stable", format: before)])
        try formatted.format(NSRange(location: 0, length: 6), identity: .init(author: author)) { original in
            var result = original; result.bold = true; result.fontSize = 18; result.foreground = "#654321"; return result
        }
        var inserted = TextRun("New "), deleted = TextRun("Old ")
        var insertion = RunReview(), deletion = RunReview()
        insertion.insertion = .init(author: author); deletion.deletion = .init(author: author)
        inserted.review = insertion; deleted.review = deletion
        source.sections[0].paragraphs[0].runs = [deleted, inserted] + formatted.runs
        return try DOCX.decodePreservingRevisions(DOCXWriter(source, revisions: .runChanges).encode()).document
    }
    func testImportedRevisionSelectionAndDecisionHaveNativeUndo() throws {
        let document = ScribeFileDocument(); document.model = try importedDocument()
        document.makeWindowControllers(); defer { document.close() }
        document.undoManager?.removeAllActions()
        let original = document.snapshot()
        let controller = try XCTUnwrap(document.editorController)
        let deletion = try XCTUnwrap(original.paragraphs[0].runs[0].review?.deletion)
        XCTAssertTrue(controller.reviewNavigation.select(deletion.id))
        XCTAssertEqual(controller.editor.activeTextView.selectedRange(), NSRange(location: 0, length: 4))
        try controller.reviewNavigation.resolveCurrent(accepting: true)
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "New stable")
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().paragraphs, original.paragraphs)
        document.undoManager?.redo()
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "New stable")
    }
    func testImportedReviewRendersAllOutputDecisionsWithoutChangingSource() throws {
        let source = try importedDocument(), original = try NativeFormat.encode(source)
        for mode in ReviewOutputMode.allCases {
            let session = try ReviewOutputSession(source: source, mode: mode); defer { session.close() }
            if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
                let folder = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name: String
                switch mode { case .marked: name = "Marked"; case .accepted: name = "Accepted"; case .rejected: name = "Rejected" }
                try session.renderer.exportPDF(to: folder.appendingPathComponent("ImportedReview" + name + ".pdf"), title: name, author: "Office reviewer")
            }
            XCTAssertEqual(try NativeFormat.encode(source), original)
        }
    }
}
#endif
