import XCTest
@testable import DocumentCore

final class TableMergeTests: XCTestCase {
    private func sample() -> ScribeDocument {
        var document = ScribeDocument()
        document.insertTable(rows: 3, columns: 3, after: document.paragraphs[0].id)
        for p in document.sections[0].paragraphs.indices {
            if let cell = document.sections[0].paragraphs[p].tableCell {
                document.sections[0].paragraphs[p].runs = [TextRun("Cell \(cell.row),\(cell.column) café 東京")]
            }
        }
        return document
    }
    func testMergeSplitRetainsTextIDsCommentsAndBookmarks() throws {
        var document = sample(); let before = document.paragraphs, id = document.tables[0].id
        let source = before.first { $0.tableCell?.row == 1 && $0.tableCell?.column == 1 }!
        document.comments = [Comment(anchor: TextAnchor(paragraphID: source.id, offset: 0, length: 4), text: "Keep review", author: "Writer")]
        _ = document.addParagraphBookmark(name: "Inside", paragraphID: source.id)
        try document.mergeTableCells(tableID: id, region: TableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 2))
        XCTAssertEqual(document.tables[0].cellAnchors.count, 6)
        XCTAssertEqual(Set(document.paragraphs.map(\.id)), Set(before.map(\.id)))
        let merged = document.paragraphs.filter { $0.tableCell?.row == 0 && $0.tableCell?.column == 0 }
        XCTAssertEqual(merged.count, 4)
        XCTAssertEqual(merged.map(\.text), [before[1].text, before[2].text, before[4].text, before[5].text])
        XCTAssertNotEqual(document.comments[0].isDetached, true)
        let roundtrip = try NativeFormat.decode(NativeFormat.encode(document)); XCTAssertEqual(roundtrip, document)
        try document.splitTableCell(tableID: id, row: 1, column: 1)
        XCTAssertEqual(document.tables[0].cellAnchors.count, 9)
        XCTAssertEqual(document.paragraphs.filter { $0.tableCell?.row == 0 && $0.tableCell?.column == 0 }.count, 4)
        XCTAssertEqual(document.paragraphs.filter { $0.tableCell?.row == 1 && $0.tableCell?.column == 1 }.first?.text, "")
        XCTAssertEqual(document.bookmarks[0].anchor.paragraphID, source.id)
        XCTAssertNotEqual(document.comments[0].isDetached, true)
    }
    func testGridEditsThroughMergedAnchorsPreserveContent() throws {
        for rowAxis in [true, false] {
            var document = sample(); let id = document.tables[0].id
            try document.mergeTableCells(tableID: id, region: TableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 2))
            let texts = document.paragraphs.map(\.text).filter { !$0.isEmpty }.sorted()
            if rowAxis { document.addTableRow(tableID: id, after: 0) } else { document.addTableColumn(tableID: id, after: 0) }
            let expanded = try XCTUnwrap(document.tables[0].mergedCells?.first)
            XCTAssertEqual(rowAxis ? expanded.rowSpan : expanded.columnSpan, 3)
            XCTAssertEqual(document.paragraphs.map(\.text).filter { !$0.isEmpty }.sorted(), texts)
            try NativeFormat.validate(document)
            // Delete its original anchor grid line, retaining all text inside the surviving merge.
            let mergedIDs = Set(document.paragraphs.filter { $0.tableCell?.row == 0 && $0.tableCell?.column == 0 }.map(\.id))
            if rowAxis { document.deleteTableRow(tableID: id, row: 0) } else { document.deleteTableColumn(tableID: id, column: 0) }
            XCTAssertTrue(mergedIDs.isSubset(of: Set(document.paragraphs.map(\.id))))
            XCTAssertEqual(rowAxis ? document.tables[0].mergedCells?.first?.rowSpan : document.tables[0].mergedCells?.first?.columnSpan, 2)
            try NativeFormat.validate(document)
        }
    }
    func testRejectedPartialMergeIsTransactionalAndV7Migrates() throws {
        var document = sample(); let id = document.tables[0].id
        let legacy = try NativeFormat.encode(document)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any]); json["formatVersion"] = 7
        let migrated = try NativeFormat.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.formatVersion, ScribeDocument.currentVersion); XCTAssertNil(migrated.tables[0].mergedCells)
        try document.mergeTableCells(tableID: id, region: TableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 2))
        let before = document
        XCTAssertThrowsError(try document.mergeTableCells(tableID: id, region: TableMerge(row: 1, column: 1, rowSpan: 2, columnSpan: 2)))
        XCTAssertEqual(document, before)
        document.tables[0].mergedCells?.append(TableMerge(row: 0, column: 0, rowSpan: Int.max, columnSpan: 2))
        XCTAssertThrowsError(try NativeFormat.validate(document))
    }
}
