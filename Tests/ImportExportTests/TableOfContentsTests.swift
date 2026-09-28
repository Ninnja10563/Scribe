import XCTest
import DocumentCore
@testable import ImportExport

final class TableOfContentsTests: XCTestCase {
    func testExportContainsActualTOCFieldAndImportRetainsItsCache() throws {
        var document = ScribeDocument()
        let heading = Paragraph("A linked heading", style: "heading2")
        document.sections[0].paragraphs = [Paragraph("Cover"), heading]
        _ = document.insertTableOfContents(after: document.paragraphs[0].id, pages: [heading.id: "iv"])
        let bytes = try DOCX.encode(document), files = try ZipArchive.decode(bytes)
        let xml = String(data: files["word/document.xml"]!, encoding: .utf8)!
        XCTAssertTrue(xml.contains(" TOC \\o &quot;1-3&quot; \\h"))
        for marker in ["begin", "separate", "end"] { XCTAssertTrue(xml.contains("w:fldCharType=\"\(marker)\"")) }
        XCTAssertTrue(xml.contains("<w:tabs><w:tab w:val=\"right\""))
        let imported = try DOCX.decode(bytes)
        XCTAssertEqual(imported.document.plainText, document.plainText)
        XCTAssertTrue(imported.warnings.contains(where: { $0.contains("cached text") }))
        XCTAssertTrue(imported.document.tablesOfContents.isEmpty)
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try bytes.write(to: url.appendingPathComponent("TableOfContents.docx"), options: .atomic)
        }
    }
}
