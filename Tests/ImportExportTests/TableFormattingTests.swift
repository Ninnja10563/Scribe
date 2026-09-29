import XCTest
import DocumentCore
@testable import ImportExport

final class TableFormattingTests: XCTestCase {
    func testCellAndRowPropertiesRoundTripThroughRealOfficeElements() throws {
        var document = ScribeDocument()
        document.insertTable(rows: 2, columns: 2, after: document.paragraphs[0].id)
        let id = document.tables[0].id
        var style = TableCellStyle(row: 1, column: 1)
        style.background = "#DDEEFF"; style.padding = 9.5; style.borderWidth = 2.5; style.borderColor = "#112233"; style.verticalAlignment = .bottom
        try document.setCellStyles([style], tableID: id)
        try document.setMinimumRowHeight(100.5, row: 1, tableID: id)
        document.tables[0].padding = 7.5; document.tables[0].borderColor = "#224466"
        let bytes = try DOCX.encode(document)
        let imported = try DOCX.decode(bytes)
        XCTAssertTrue(imported.warnings.isEmpty)
        let table = try XCTUnwrap(imported.document.tables.first)
        XCTAssertEqual(table.cellStyle(row: 1, column: 1), style)
        XCTAssertEqual(table.padding, 7.5); XCTAssertEqual(table.borderColor, "#224466")
        XCTAssertEqual(table.minimumRowHeights?[1], 100.5)
        let parts = try ZipArchive.decode(bytes), xml = String(decoding: parts["word/document.xml"]!, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:trHeight w:val=\"2010\" w:hRule=\"atLeast\"/>"))
        XCTAssertTrue(xml.contains("<w:vAlign w:val=\"bottom\"/>"))
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.write(to: folder.appendingPathComponent("TableFormatting.docx"))
        }
    }
    func testIndependentStyledTableFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "TableFormatting", withExtension: "docx", subdirectory: "Fixtures"))
        let imported = try DOCX.decode(Data(contentsOf: url))
        let table = try XCTUnwrap(imported.document.tables.first)
        XCTAssertEqual(table.cellStyle(row: 0, column: 0)?.background, "#DDEEFF")
        XCTAssertEqual(table.cellStyle(row: 0, column: 0)?.verticalAlignment, .center)
        XCTAssertEqual(table.cellStyle(row: 1, column: 1)?.padding, 8)
        XCTAssertEqual(table.cellStyle(row: 1, column: 1)?.borderWidth, 1.5)
        XCTAssertEqual(table.cellStyle(row: 1, column: 1)?.borderColor, "#336699")
        XCTAssertEqual(table.minimumRowHeights?[1], 90)
        XCTAssertTrue(imported.document.plainText.contains("Cell 1,1: café 東京"))
        XCTAssertTrue(imported.warnings.contains { $0.contains("minimum heights") })
    }
    func testExactRowsAndAsymmetricPaddingDiscloseTheirApproximation() throws {
        let xml = "<w:document xmlns:w=\"\(DOCX.wordNS)\"><w:body><w:tbl><w:tblGrid><w:gridCol w:w=\"3000\"/></w:tblGrid><w:tr><w:trPr><w:trHeight w:val=\"1200\" w:hRule=\"exact\"/></w:trPr><w:tc><w:tcPr><w:tcMar><w:top w:w=\"80\" w:type=\"dxa\"/><w:left w:w=\"160\" w:type=\"dxa\"/></w:tcMar></w:tcPr><w:p><w:r><w:t>Retained cell text</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>"
        let imported = try DOCX.decode(ZipArchive.encode(["word/document.xml": Data(xml.utf8)]))
        XCTAssertEqual(imported.document.tables[0].minimumRowHeights?[0], 60)
        XCTAssertEqual(imported.document.tables[0].cellStyle(row: 0, column: 0)?.padding, 8)
        XCTAssertTrue(imported.warnings.contains { $0.contains("minimum heights") })
        XCTAssertTrue(imported.warnings.contains { $0.contains("largest inset") })
        XCTAssertEqual(imported.document.plainText, "Retained cell text")
    }
}
