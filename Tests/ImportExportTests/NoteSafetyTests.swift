import XCTest
import DocumentCore
@testable import ImportExport

final class NoteSafetyTests: XCTestCase {
    func testTextExportsRetainReferencesAndNoteContent() throws {
        var document = ScribeDocument()
        let note = DocumentNote(kind: .footnote, text: "Citation with résumé and Unicode 👩🏽‍💻.")
        document.notes = [note]
        var reference = TextRun("\u{FFFC}"); reference.noteID = note.id
        document.sections[0].paragraphs[0].runs = [TextRun("Statement"), reference]
        let markdown = TextFormats.exportMarkdown(document)
        XCTAssertTrue(markdown.contains("Statement[^footnote1]"))
        XCTAssertTrue(markdown.contains("[^footnote1]: Citation with résumé and Unicode 👩🏽‍💻."))
        XCTAssertFalse(markdown.contains("\u{FFFC}"))
        XCTAssertEqual(try DOCX.decode(DOCX.encode(document)).document.notes.first?.plainText, note.plainText)
    }
}
