import XCTest
import DocumentCore
@testable import ImportExport

final class InternalLinkTests: XCTestCase {
    func testInternalLinkUsesOfficeBookmarkWithoutExternalRelationship() throws {
        var document = ScribeDocument()
        let heading = Paragraph("Destination", style: "heading1")
        var link = Paragraph("Read the destination")
        link.runs[0].link = DocumentLink.paragraph(heading.id)
        document.sections[0].paragraphs = [link, heading]
        let bytes = try DOCX.encode(document), parts = try ZipArchive.decode(bytes)
        let xml = String(data: parts["word/document.xml"]!, encoding: .utf8)!
        XCTAssertTrue(xml.contains("w:anchor=\"\(DocumentLink.officeBookmark(heading.id))\""))
        XCTAssertTrue(xml.contains("<w:bookmarkStart"))
        XCTAssertFalse(String(data: parts["word/_rels/document.xml.rels"]!, encoding: .utf8)!.contains("scribe://"))
        let imported = try DOCX.decode(bytes)
        XCTAssertTrue(imported.warnings.isEmpty)
        XCTAssertEqual(DocumentLink.paragraphID(imported.document.paragraphs[0].runs[0].link!), imported.document.paragraphs[1].id)
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try bytes.write(to: url.appendingPathComponent("InternalLinks.docx"), options: .atomic)
        }
    }
    func testMissingBookmarkPreservesTextWithWarning() throws {
        let xml = "<w:document xmlns:w=\"\(DOCX.wordNS)\"><w:body><w:p><w:hyperlink w:anchor=\"Missing\"><w:r><w:t>Retained text</w:t></w:r></w:hyperlink></w:p></w:body></w:document>"
        let result = try DOCX.decode(ZipArchive.encode(["word/document.xml": Data(xml.utf8)]))
        XCTAssertEqual(result.document.plainText, "Retained text")
        XCTAssertNil(result.document.paragraphs[0].runs[0].link)
        XCTAssertEqual(result.warnings.count, 1)
    }
}
