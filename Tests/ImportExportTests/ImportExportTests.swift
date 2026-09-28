import XCTest
import DocumentCore
@testable import ImportExport

final class ImportExportTests: XCTestCase {
    func testIndependentDeflatedFixture() throws {
        let url = Bundle.module.url(forResource: "WordprocessingML", withExtension: "docx", subdirectory: "Fixtures")!
        let result = try DOCX.decode(Data(contentsOf: url))
        XCTAssertEqual(result.document.paragraphs[0].text, "Interoperability fixture")
        XCTAssertEqual(result.document.outline.first?.level, 1)
        XCTAssertTrue(result.document.plainText.contains("café 東京"))
        XCTAssertTrue(result.document.plainText.contains("42"))
        XCTAssertEqual(result.document.tables.count, 1)
        XCTAssertEqual(result.document.tables[0].rows, 2)
        XCTAssertEqual(result.document.sections[0].header, "Fixture header")
    }
    func testDOCXIsAnActualOPCPackage() throws {
        var doc = ScribeDocument()
        var p = Paragraph("Research & <evidence>", style: "heading1")
        p.runs[0].format.bold = true
        var linked = Paragraph(); linked.runs = [TextRun("Open reference", link: "https://example.com/?a=1&b=2")]
        doc.sections[0].paragraphs = [p, linked, Paragraph("Unicode: café 東京 👩🏽‍💻")]
        let data = try DOCX.encode(doc)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
        let files = try ZipArchive.decode(data)
        XCTAssertNotNil(files["[Content_Types].xml"]); XCTAssertNotNil(files["word/document.xml"])
        let result = try DOCX.decode(data)
        XCTAssertEqual(result.document.plainText, doc.plainText)
        XCTAssertEqual(result.document.paragraphs[0].styleID, "heading1")
        XCTAssertEqual(result.document.paragraphs[0].runs[0].format.bold, true)
        XCTAssertEqual(result.document.paragraphs[1].runs[0].link, linked.runs[0].link)
        XCTAssertEqual(result.document.sections[0].page.width, doc.sections[0].page.width, accuracy: 0.05)
        XCTAssertTrue(result.warnings.isEmpty)
    }
    func testCorruptAndUnsafeArchivesAreRejected() throws {
        XCTAssertThrowsError(try ZipArchive.decode(Data("not a zip".utf8)))
        let unsafe = try ZipArchive.encode(["../escape": Data("bad".utf8)])
        XCTAssertThrowsError(try ZipArchive.decode(unsafe))
        var data = try ZipArchive.encode(["content": Data("unique payload".utf8)])
        let range = data.range(of: Data("unique payload".utf8))!; data[range.lowerBound] ^= 0xff
        XCTAssertThrowsError(try ZipArchive.decode(data))
    }
    func testUnsupportedDOCXFeaturesAreReported() throws {
        let xml = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p><w:r><w:drawing/></w:r></w:p></w:body></w:document>"
        let result = try DOCX.decode(ZipArchive.encode(["word/document.xml": Data(xml.utf8)]))
        XCTAssertEqual(result.warnings.count, 1); XCTAssertTrue(result.document.plainText.contains("Cell"))
    }
    func testTablesImagesAndRunningContentRoundTrip() throws {
        var document = ScribeDocument()
        document.insertTable(rows: 2, columns: 2, after: document.paragraphs[0].id)
        document.sections[0].paragraphs[1].runs = [TextRun("Heading cell")]
        var image = TextRun("\u{FFFC}")
        image.image = InlineImage(data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNwSev4DwAEVgIy41TneAAAAABJRU5ErkJggg==")!, fileExtension: "png", width: 30, height: 30, altText: "Sample")
        document.sections[0].paragraphs.append(Paragraph())
        document.sections[0].paragraphs[document.paragraphs.count - 1].runs = [image]
        document.sections[0].header = "Research"
        document.sections[0].footer = "Confidential"
        let bytes = try DOCX.encode(document)
        let files = try ZipArchive.decode(bytes)
        XCTAssertTrue(files.keys.contains(where: { $0.hasPrefix("word/media/") }))
        let result = try DOCX.decode(bytes)
        XCTAssertEqual(result.document.tables.count, 1)
        XCTAssertEqual(result.document.tables[0].columnWidths.count, 2)
        XCTAssertTrue(result.document.paragraphs.contains(where: { $0.tableCell != nil && $0.text == "Heading cell" }))
        let loadedImage = result.document.paragraphs.flatMap(\.runs).compactMap(\.image).first
        XCTAssertEqual(loadedImage?.data, image.image?.data)
        XCTAssertEqual(loadedImage?.altText, "Sample")
        XCTAssertEqual(result.document.sections[0].header, "Research")
        XCTAssertEqual(result.document.sections[0].footer, "Confidential")
    }
    func testNamespaceRebindingCannotMasqueradeAsWordAttributesAndCDATAIsPreserved() throws {
        let xml = """
        <doc:document xmlns:doc="\(DOCX.wordNS)" xmlns:w="urn:unrelated">
          <doc:body><doc:p><doc:pPr><doc:pStyle w:val="heading1"/></doc:pPr>
            <doc:r><doc:t><![CDATA[<kept> & café 東京]]></doc:t></doc:r>
          </doc:p></doc:body>
        </doc:document>
        """
        let result = try DOCX.decode(ZipArchive.encode(["word/document.xml": Data(xml.utf8)]))
        XCTAssertEqual(result.document.plainText, "<kept> & café 東京")
        XCTAssertEqual(result.document.paragraphs[0].styleID, "normal")
    }
    func testMalformedXMLFails() throws {
        let data = try ZipArchive.encode(["word/document.xml": Data("<document>".utf8)])
        XCTAssertThrowsError(try DOCX.decode(data))
    }
    func testMarkdownAndPlainText() {
        let doc = TextFormats.markdown("# Heading\n- **Bold** and *italic*\n> Quote\n[Link](https://example.com)")
        XCTAssertEqual(doc.paragraphs[0].styleID, "heading1")
        XCTAssertEqual(doc.paragraphs[1].list?.kind, .bullet)
        XCTAssertEqual(doc.paragraphs[1].runs[0].format.bold, true)
        XCTAssertEqual(doc.paragraphs[2].styleID, "quote")
        XCTAssertEqual(doc.paragraphs[3].runs[0].link, "https://example.com")
        XCTAssertEqual(TextFormats.plainText("one\r\ntwo\rthree\n").paragraphs.count, 4)
    }
}
