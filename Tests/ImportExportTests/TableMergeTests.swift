import XCTest
import DocumentCore
@testable import ImportExport

final class TableMergeTests: XCTestCase {
    func testIndependentMergedTableFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "MergedTable", withExtension: "docx", subdirectory: "Fixtures"))
        let imported = try DOCX.decode(Data(contentsOf: url))
        XCTAssertEqual(imported.document.tables[0].mergedCells, [TableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 2), TableMerge(row: 2, column: 1, rowSpan: 2, columnSpan: 1)])
        for row in 0..<4 { for column in 0..<3 { XCTAssertTrue(imported.document.plainText.contains("Cell \(row),\(column): café 東京")) } }
        let second = try DOCX.decode(DOCX.encode(imported.document))
        XCTAssertEqual(second.document.paragraphs.map(\.text), imported.document.paragraphs.map(\.text))
        XCTAssertEqual(second.document.tables[0].mergedCells, imported.document.tables[0].mergedCells)
    }
    func testMergedRectangleUsesRealOfficeSpansAndRetainsText() throws {
        var document = ScribeDocument()
        document.insertTable(rows: 3, columns: 3, after: document.paragraphs[0].id)
        for p in document.sections[0].paragraphs.indices {
            if let cell = document.sections[0].paragraphs[p].tableCell { document.sections[0].paragraphs[p].runs = [TextRun("Cell \(cell.row),\(cell.column)")] }
        }
        let region = TableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 2)
        let reviewed = try XCTUnwrap(document.paragraphs.first { $0.text == "Cell 1,1" })
        document.comments = [Comment(anchor: TextAnchor(paragraphID: reviewed.id, offset: 0, length: 4), text: "Merged review", author: "Writer")]
        _ = document.addParagraphBookmark(name: "Reviewed_cell", paragraphID: reviewed.id)
        try document.mergeTableCells(tableID: document.tables[0].id, region: region)
        let bytes = try DOCX.encode(document), parts = try ZipArchive.decode(bytes)
        let xml = String(decoding: parts["word/document.xml"]!, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:gridSpan w:val=\"2\"/>"))
        XCTAssertTrue(xml.contains("<w:vMerge w:val=\"restart\"/>"))
        XCTAssertTrue(xml.contains("<w:vMerge w:val=\"continue\"/>"))
        let imported = try DOCX.decode(bytes)
        XCTAssertEqual(imported.document.tables[0].mergedCells, [region])
        XCTAssertEqual(imported.document.paragraphs.map(\.text), document.paragraphs.map(\.text))
        let comment = try XCTUnwrap(imported.document.comments.first)
        XCTAssertEqual(comment.text, "Merged review"); XCTAssertNotEqual(comment.isDetached, true)
        XCTAssertEqual(imported.document.paragraphs.first { $0.id == comment.anchor.paragraphID }?.text, "Cell 1,1")
        XCTAssertEqual(imported.document.bookmarks.first?.name, "Reviewed_cell")
        XCTAssertTrue(imported.warnings.isEmpty, imported.warnings.joined(separator: "\n"))
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.write(to: folder.appendingPathComponent("MergedTable.docx"))
        }
    }
    func testUnmatchedContinuationRetainsTextAndWarns() throws {
        let xml = "<w:document xmlns:w=\"\(DOCX.wordNS)\"><w:body><w:tbl><w:tblGrid><w:gridCol w:w=\"3000\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:vMerge/></w:tcPr><w:p><w:r><w:t>Keep this</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>"
        let imported = try DOCX.decode(ZipArchive.encode(["word/document.xml": Data(xml.utf8)]))
        XCTAssertTrue(imported.document.plainText.contains("Keep this"))
        XCTAssertTrue(imported.warnings.contains { $0.contains("no matching preceding") })
    }
    func testLeadingGridOffsetAndLegacyMergeDiscloseApproximation() throws {
        let xml = "<w:document xmlns:w=\"\(DOCX.wordNS)\"><w:body><w:tbl><w:tblGrid><w:gridCol w:w=\"1500\"/><w:gridCol w:w=\"1500\"/></w:tblGrid><w:tr><w:trPr><w:gridBefore w:val=\"1\"/></w:trPr><w:tc><w:tcPr><w:hMerge w:val=\"restart\"/></w:tcPr><w:p><w:r><w:t>Offset cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>"
        let imported = try DOCX.decode(ZipArchive.encode(["word/document.xml": Data(xml.utf8)]))
        XCTAssertEqual(imported.document.paragraphs.first { $0.text == "Offset cell" }?.tableCell?.column, 1)
        XCTAssertEqual(imported.document.paragraphs.first?.text, "")
        XCTAssertTrue(imported.warnings.contains { $0.contains("Legacy horizontal") })
        XCTAssertTrue(imported.warnings.contains { $0.contains("leading offsets") })
    }
}
