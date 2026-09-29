#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import ImportExport
@testable import Scribe

@MainActor final class ImportedObjectReviewTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testObjectDecisionsRenderImportedPayloads() throws {
        var source = ScribeDocument()
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAKElEQVR4nGP4z8BAEiJNNRlo1IJRCwbAAlJ1/P/PQBIatWDUgiFgAQAk0H2fCntH2wAAAABJRU5ErkJggg==")!
        let author = RevisionAuthor(name: "Office reviewer")
        var insertion = RunReview(), deletion = RunReview()
        insertion.insertion = .init(author: author); deletion.deletion = .init(author: author)
        var picture = TextRun("\u{fffc}"); picture.image = InlineImage(data: bytes, fileExtension: "png", width: 64, height: 32); picture.review = insertion
        var equation = TextRun("\u{fffc}"); equation.equation = try Equation(source: #"\frac{1}{2}"#); equation.review = deletion
        let note = DocumentNote(kind: .footnote, text: "Reviewed note payload")
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id; reference.review = deletion
        source.notes = [note]
        source.sections[0].paragraphs[0].runs = [TextRun("Objects "), picture, equation, reference]
        let imported = try DOCX.decodePreservingRevisions(DOCXWriter(source, revisions: .runChanges).encode()).document
        for mode in [ReviewOutputMode.accepted, .rejected] {
            let session = try ReviewOutputSession(source: imported, mode: mode); defer { session.close() }
            XCTAssertNil(session.editor.layoutWarning)
            if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
                let folder = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = mode == .accepted ? "Accepted" : "Rejected"
                try session.renderer.exportPDF(to: folder.appendingPathComponent("ImportedObjectReview" + name + ".pdf"), title: name, author: author.name)
            }
        }
        XCTAssertTrue(imported.hasPendingRevisions)
        XCTAssertEqual(imported.notes[0].plainText, note.plainText)
    }
}
#endif
