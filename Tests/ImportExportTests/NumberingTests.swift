import XCTest
import DocumentCore
@testable import ImportExport

final class NumberingTests: XCTestCase {
    private func markers(_ document: ScribeDocument) -> [String?] {
        var counter = ListNumbering()
        return document.paragraphs.map { counter.marker(for: $0.list) }
    }
    func testArbitraryIDsOverridesStylesAndContinuation() throws {
        let definitions = """
        <w:numbering xmlns:w="\(DOCX.wordNS)">
          <w:abstractNum w:abstractNumId="42">
            <w:lvl w:ilvl="0"><w:start w:val="3"/><w:numFmt w:val="upperRoman"/><w:lvlText w:val="%1."/></w:lvl>
            <w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="lowerLetter"/><w:lvlText w:val="%2."/></w:lvl>
          </w:abstractNum>
          <w:abstractNum w:abstractNumId="7"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/></w:lvl></w:abstractNum>
          <w:num w:numId="1"><w:abstractNumId w:val="42"/><w:lvlOverride w:ilvl="0"><w:startOverride w:val="5"/></w:lvlOverride></w:num>
          <w:num w:numId="88"><w:abstractNumId w:val="7"/></w:num>
        </w:numbering>
        """
        let styles = """
        <w:styles xmlns:w="\(DOCX.wordNS)">
          <w:style w:type="paragraph" w:styleId="ListBase"><w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr></w:style>
          <w:style w:type="paragraph" w:styleId="ListChild"><w:basedOn w:val="ListBase"/></w:style>
        </w:styles>
        """
        func p(_ properties: String) -> String { "<w:p><w:pPr>\(properties)</w:pPr><w:r><w:t>Item</w:t></w:r></w:p>" }
        let style = "<w:pStyle w:val=\"ListChild\"/>"
        let nested = "<w:numPr><w:numId w:val=\"1\"/><w:ilvl w:val=\"1\"/></w:numPr>"
        let body = p(style) + p(nested) + p("") + p(style) + p("<w:numPr><w:numId w:val=\"88\"/></w:numPr>") + p(style + "<w:numPr><w:numId w:val=\"0\"/></w:numPr>")
        let data = try ZipArchive.encode([
            "word/document.xml": Data("<w:document xmlns:w=\"\(DOCX.wordNS)\"><w:body>\(body)</w:body></w:document>".utf8),
            "word/numbering.xml": Data(definitions.utf8), "word/styles.xml": Data(styles.utf8)
        ])
        let result = try DOCX.decode(data)
        XCTAssertEqual(markers(result.document), ["V.", "a.", nil, "VI.", "•", nil])
        XCTAssertTrue(result.warnings.isEmpty, result.warnings.joined())
        XCTAssertEqual(markers(try DOCX.decode(DOCX.encode(result.document)).document), markers(result.document))
    }
    func testExportsIndependentListsAndExplicitRestarts() throws {
        var document = ScribeDocument(); let id = UUID()
        let lists: [ListDescriptor?] = [
            .init(kind: .decimal, start: 4, seriesID: id),
            .init(kind: .lowerAlpha, level: 1, seriesID: id),
            .init(kind: .lowerAlpha, level: 1, seriesID: id), nil,
            .init(kind: .decimal, start: 4, seriesID: id),
            .init(kind: .decimal, start: 8, seriesID: id, restart: true),
            .init(kind: .decimal, start: 8, seriesID: id), nil,
            .init(kind: .decimal), .init(kind: .decimal), nil, .init(kind: .decimal)
        ]
        document.sections[0].paragraphs = lists.map { var p = Paragraph("Item"); p.list = $0; return p }
        let exported = try DOCX.encode(document)
        let imported = try DOCX.decode(exported)
        XCTAssertTrue(imported.warnings.isEmpty)
        XCTAssertEqual(markers(imported.document), ["4.", "a.", "b.", nil, "5.", "8.", "9.", nil, "1.", "2.", nil, "1."])
        let parts = try ZipArchive.decode(exported)
        let xml = String(decoding: parts["word/numbering.xml"]!, as: UTF8.self)
        XCTAssertTrue(xml.contains("w:start w:val=\"8\""))
        XCTAssertLessThan(xml.range(of: "</w:abstractNum>", options: .backwards)!.lowerBound, xml.range(of: "<w:num ")!.lowerBound)
    }
    func testUnsupportedMarkerPatternDisclosesLoss() throws {
        let xml = "<w:numbering xmlns:w=\"\(DOCX.wordNS)\"><w:abstractNum w:abstractNumId=\"1\"><w:lvl w:ilvl=\"1\"><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1.%2)\"/></w:lvl></w:abstractNum></w:numbering>"
        let reader = DOCXNumberingReader(); try DOCX.parse(Data(xml.utf8), delegate: reader)
        XCTAssertEqual(reader.warnings.count, 1)
    }
}
