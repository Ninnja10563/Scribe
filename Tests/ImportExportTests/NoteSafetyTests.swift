import XCTest
import DocumentCore
@testable import ImportExport

final class NoteSafetyTests: XCTestCase {
    func testTextExportsRetainReferencesAndNoteContentWhileUnimplementedDOCXIsRejected() throws {
        var document = ScribeDocument()
        let note = DocumentNote(kind: .footnote, text: "Citation with résumé and Unicode 👩🏽‍💻.")
        document.notes = [note]
        var reference = TextRun("\u{FFFC}"); reference.noteID = note.id
        document.sections[0].paragraphs[0].runs = [TextRun("Statement"), reference]
        let markdown = TextFormats.exportMarkdown(document)
        XCTAssertTrue(markdown.contains("Statement[^footnote1]"))
        XCTAssertTrue(markdown.contains("[^footnote1]: Citation with résumé and Unicode 👩🏽‍💻."))
        XCTAssertFalse(markdown.contains("\u{FFFC}"))
        XCTAssertThrowsError(try DOCX.encode(document), "An incomplete exporter must not silently lose note content")
    }
}
