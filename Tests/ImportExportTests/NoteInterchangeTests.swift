import XCTest
import DocumentCore
@testable import ImportExport

final class NoteInterchangeTests: XCTestCase {
    func testIndependentNoteFixtureImportsNonSequentialIdentifiers() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "IndependentNotes", withExtension: "docx", subdirectory: "Fixtures"))
        let imported = try DOCX.decode(Data(contentsOf: url))
        XCTAssertTrue(imported.warnings.isEmpty, imported.warnings.joined(separator: "; "))
        XCTAssertEqual(imported.document.notes.map(\.kind), [.footnote, .endnote])
        XCTAssertEqual(imported.document.notes.map(\.plainText), ["Independent footnote résumé.", "Independent endnote source."])
        XCTAssertTrue(imported.document.notes.allSatisfy { $0.paragraphs.flatMap(\.runs).contains { $0.format.italic == true } })
        XCTAssertEqual(imported.document.paragraphs.flatMap(\.runs).compactMap(\.noteID), imported.document.notes.map(\.id))
    }
    func testFootnotesAndEndnotesUseSeparatePartsAndRetainRichContent() throws {
        var document = ScribeDocument()
        var footnote = DocumentNote(kind: .footnote, text: "Footnote citation — résumé.")
        footnote.paragraphs[0].runs[0].format.italic = true
        footnote.paragraphs.append(Paragraph("Second citation paragraph."))
        footnote.paragraphs[1].runs[0].link = "https://example.org/citation"
        var equation = TextRun("\u{fffc}"); equation.equation = try Equation(source: #"\frac{1}{2}"#)
        footnote.paragraphs[1].runs.append(equation)
        let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAKElEQVR4nGP4z8BAEiJNNRlo1IJRCwbAAlJ1/P/PQBIatWDUgiFgAQAk0H2fCntH2wAAAABJRU5ErkJggg==")!
        var image = TextRun("\u{fffc}"); image.image = InlineImage(data: imageData, fileExtension: "png", width: 32, height: 16, altText: "Citation figure")
        footnote.paragraphs[1].runs.append(image)
        let endnote = DocumentNote(kind: .endnote, text: "Endnote conclusion.")
        document.notes = [footnote, endnote]
        document.sections[0].paragraphs[0].runs = [TextRun("Body claim ")]
        for note in document.notes {
            var reference = TextRun("\u{fffc}"); reference.noteID = note.id
            document.sections[0].paragraphs[0].runs.append(reference)
        }
        let bytes = try DOCX.encode(document), parts = try ZipArchive.decode(bytes)
        for path in ["word/footnotes.xml", "word/endnotes.xml", "word/_rels/footnotes.xml.rels"] { XCTAssertNotNil(parts[path]) }
        let xml = String(decoding: try XCTUnwrap(parts["word/document.xml"]), as: UTF8.self)
        XCTAssertTrue(xml.contains("w:footnoteReference")); XCTAssertTrue(xml.contains("w:endnoteReference"))
        XCTAssertFalse(String(decoding: parts["word/_rels/document.xml.rels"]!, as: UTF8.self).contains("example.org/citation"))
        let loaded = try DOCX.decode(bytes)
        XCTAssertTrue(loaded.warnings.isEmpty, loaded.warnings.joined(separator: "; "))
        XCTAssertEqual(loaded.document.notes.map(\.kind), [.footnote, .endnote])
        func prose(_ note: DocumentNote) -> String {
            note.paragraphs.map { $0.runs.filter { $0.equation == nil }.map(\.text).joined() }.joined(separator: "\n")
        }
        XCTAssertEqual(loaded.document.notes.map(prose), document.notes.map(prose))
        let runs = loaded.document.notes[0].paragraphs.flatMap(\.runs)
        XCTAssertTrue(runs.contains { $0.format.italic == true && $0.text.contains("résumé") })
        XCTAssertTrue(runs.contains { $0.link == "https://example.org/citation" })
        XCTAssertEqual(runs.compactMap(\.equation).first?.expression, equation.equation?.expression)
        XCTAssertEqual(runs.compactMap(\.image).first?.data, imageData)
        XCTAssertEqual(runs.compactMap(\.image).first?.altText, "Citation figure")
        var relocated = parts
        relocated["word/annotations/footnotes.xml"] = relocated.removeValue(forKey: "word/footnotes.xml")
        let relations = try XCTUnwrap(relocated.removeValue(forKey: "word/_rels/footnotes.xml.rels"))
        relocated["word/annotations/_rels/footnotes.xml.rels"] = Data(String(decoding: relations, as: UTF8.self).replacingOccurrences(of: "Target=\"media/", with: "Target=\"../media/").utf8)
        relocated["word/_rels/document.xml.rels"] = Data(String(decoding: relocated["word/_rels/document.xml.rels"]!, as: UTF8.self).replacingOccurrences(of: "Target=\"footnotes.xml\"", with: "Target=\"annotations/footnotes.xml\"").utf8)
        let nestedPart = try DOCX.decode(ZipArchive.encode(relocated))
        XCTAssertEqual(nestedPart.document.notes[0].paragraphs.flatMap(\.runs).compactMap(\.image).first?.data, imageData)
        XCTAssertTrue(loaded.document.paragraphs.flatMap(\.runs).filter { $0.noteID != nil }.allSatisfy { $0.format.baseline == nil })
        try NativeFormat.validate(loaded.document)
        if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let directory = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try bytes.write(to: directory.appendingPathComponent("Notes.docx"))
        }
    }
    func testMissingDuplicateAndNestedReferencesAreRejected() throws {
        var document = ScribeDocument()
        let note = DocumentNote(kind: .footnote, text: "Content that must not disappear.")
        document.notes = [note]
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        document.sections[0].paragraphs[0].runs = [reference]
        let original = try ZipArchive.decode(DOCX.encode(document))
        var missing = original; missing.removeValue(forKey: "word/footnotes.xml")
        XCTAssertThrowsError(try DOCX.decode(ZipArchive.encode(missing)))
        var duplicate = original
        duplicate["word/document.xml"] = Data(String(decoding: original["word/document.xml"]!, as: UTF8.self).replacingOccurrences(of: "<w:footnoteReference w:id=\"1\"/>", with: "<w:footnoteReference w:id=\"1\"/><w:footnoteReference w:id=\"1\"/>").utf8)
        XCTAssertThrowsError(try DOCX.decode(ZipArchive.encode(duplicate)))
        var nested = original
        nested["word/footnotes.xml"] = Data(String(decoding: original["word/footnotes.xml"]!, as: UTF8.self).replacingOccurrences(of: "<w:footnoteRef/>", with: "<w:footnoteReference w:id=\"1\"/>").utf8)
        XCTAssertThrowsError(try DOCX.decode(ZipArchive.encode(nested)))
        var numbering = original
        numbering["word/document.xml"] = Data(String(decoding: original["word/document.xml"]!, as: UTF8.self).replacingOccurrences(of: "w:val=\"continuous\"", with: "w:val=\"eachPage\"").utf8)
        XCTAssertTrue(try DOCX.decode(ZipArchive.encode(numbering)).warnings.contains { $0.contains("continuous decimal") })
        var duplicateDefinition = original
        let duplicateXML = String(decoding: original["word/footnotes.xml"]!, as: UTF8.self).replacingOccurrences(of: "</w:footnotes>", with: "<w:footnote w:id=\"1\"><w:p/></w:footnote></w:footnotes>")
        duplicateDefinition["word/footnotes.xml"] = Data(duplicateXML.utf8)
        XCTAssertThrowsError(try DOCX.decode(ZipArchive.encode(duplicateDefinition)))
    }
    func testAlternateNotePartNamesAndNamespacePrefixesAreResolved() throws {
        var document = ScribeDocument()
        let note = DocumentNote(kind: .footnote, text: "Alternate namespace note.")
        document.notes = [note]
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        document.sections[0].paragraphs[0].runs = [reference]
        var parts = try ZipArchive.decode(DOCX.encode(document))
        let source = try XCTUnwrap(parts.removeValue(forKey: "word/footnotes.xml"))
        parts["word/citations.xml"] = Data(String(decoding: source, as: UTF8.self).replacingOccurrences(of: "w:", with: "q:").replacingOccurrences(of: "xmlns:w", with: "xmlns:q").utf8)
        parts["word/_rels/document.xml.rels"] = Data(String(decoding: parts["word/_rels/document.xml.rels"]!, as: UTF8.self).replacingOccurrences(of: "Target=\"footnotes.xml\"", with: "Target=\"citations.xml\"").utf8)
        XCTAssertEqual(try DOCX.decode(ZipArchive.encode(parts)).document.notes.first?.plainText, note.plainText)
    }
}
