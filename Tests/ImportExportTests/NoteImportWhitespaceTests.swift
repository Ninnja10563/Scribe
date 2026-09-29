import Foundation
import XCTest
import DocumentCore
@testable import ImportExport

final class NoteImportWhitespaceTests: XCTestCase {
    private func package(_ content: String) throws -> Data {
        var document = ScribeDocument()
        let note = DocumentNote(kind: .footnote)
        document.notes = [note]
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        document.sections[0].paragraphs[0].runs = [reference]
        var parts = try ZipArchive.decode(DOCX.encode(document))
        parts["word/footnotes.xml"] = Data("<w:footnotes xmlns:w=\"\(DOCX.wordNS)\"><w:footnote w:id=\"1\"><w:p>\(content)</w:p></w:footnote></w:footnotes>".utf8)
        return try ZipArchive.encode(parts)
    }
    func testUnlabelledNoteKeepsAuthoredLeadingSpaces() throws {
        let bytes = try package("<w:r><w:t xml:space=\"preserve\">  Leading note</w:t></w:r>")
        XCTAssertEqual(try DOCX.decode(bytes).document.notes[0].plainText, "  Leading note")
    }
    func testLabelSeparatorDoesNotConsumeAdditionalAuthoredSpaces() throws {
        let bytes = try package("<w:r><w:footnoteRef/></w:r><w:r><w:t xml:space=\"preserve\"> </w:t></w:r><w:r><w:t xml:space=\"preserve\">  Leading note</w:t></w:r>")
        XCTAssertEqual(try DOCX.decode(bytes).document.notes[0].plainText, "  Leading note")
    }
    func testUnlabelledRevisedWhitespaceRemainsAValidRevision() throws {
        let bytes = try package("<w:ins w:id=\"7\" w:author=\"Editor\" w:date=\"2023-11-14T22:13:20Z\"><w:r><w:t xml:space=\"preserve\"> </w:t></w:r></w:ins>")
        let document = try DOCX.decodePreservingRevisions(bytes).document
        XCTAssertEqual(document.notes[0].plainText, " ")
        XCTAssertEqual(document.notes[0].paragraphs[0].runs[0].review?.insertion?.author.name, "Editor")
        try NativeFormat.validate(document)
    }
}
