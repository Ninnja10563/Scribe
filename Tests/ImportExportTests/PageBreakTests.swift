import XCTest
import DocumentCore
@testable import ImportExport

final class PageBreakTests: XCTestCase {
    func testInlinePageBreakRetainsItsPosition() throws {
        let xml = """
        <w:document xmlns:w="\(DOCX.wordNS)"><w:body>
        <w:p><w:r><w:t>Before</w:t><w:br w:type="page"/><w:t>After</w:t></w:r></w:p>
        <w:p><w:r><w:br w:type="page"/><w:t>Start</w:t><w:br w:type="page"/></w:r></w:p>
        </w:body></w:document>
        """
        let result = try DOCX.decode(ZipArchive.encode(["word/document.xml": Data(xml.utf8)]))
        XCTAssertEqual(result.document.paragraphs.map(\.text), ["Before\u{c}After", "\u{c}Start\u{c}"])
        XCTAssertFalse(result.document.paragraphs[0].pageBreakBefore)
        let exported = try DOCX.encode(result.document)
        let parts = try ZipArchive.decode(exported)
        let output = try XCTUnwrap(String(data: parts["word/document.xml"]!, encoding: .utf8))
        XCTAssertFalse(output.contains("\u{c}")) // XML 1.0 cannot contain literal form feeds.
        XCTAssertEqual(output.components(separatedBy: "<w:br w:type=\"page\"/>").count - 1, 3)
        XCTAssertEqual(try DOCX.decode(exported).document.paragraphs.map(\.text), result.document.paragraphs.map(\.text))
    }
}
