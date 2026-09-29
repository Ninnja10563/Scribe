import XCTest
@testable import DocumentCore

final class TableFormattingTests: XCTestCase {
    func testCellAndRowFormattingTracksInsertedAndDeletedCoordinates() throws {
        var document = ScribeDocument()
        document.insertTable(rows: 2, columns: 2, after: document.paragraphs[0].id)
        let id = document.tables[0].id
        var cell = TableCellStyle(row: 1, column: 1)
        cell.background = "#DDEEFF"; cell.padding = 9.5; cell.borderWidth = 2; cell.borderColor = "#112233"; cell.verticalAlignment = .bottom
        try document.setCellStyles([cell], tableID: id)
        try document.setMinimumRowHeight(100.5, row: 1, tableID: id)
        document.addTableRow(tableID: id, after: -1); document.addTableColumn(tableID: id, after: -1)
        XCTAssertEqual(document.tables[0].cellStyle(row: 2, column: 2)?.background, "#DDEEFF")
        XCTAssertEqual(document.tables[0].minimumRowHeights?[2], 100.5)
        document.deleteTableRow(tableID: id, row: 0); document.deleteTableColumn(tableID: id, column: 0)
        XCTAssertEqual(document.tables[0].cellStyle(row: 1, column: 1), cell)
        XCTAssertEqual(document.tables[0].minimumRowHeights?[1], 100.5)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
        document.deleteTableRow(tableID: id, row: 1)
        XCTAssertTrue(document.tables[0].cellStyles?.isEmpty == true)
        XCTAssertEqual(document.tables[0].minimumRowHeights?.count, 1)
        XCTAssertNoThrow(try NativeFormat.validate(document))
    }
    func testMinimumHeightFitsPageAndShrinksWithPageLayout() throws {
        var document = ScribeDocument()
        document.insertTable(rows: 1, columns: 1, after: document.paragraphs[0].id)
        let id = document.tables[0].id
        XCTAssertThrowsError(try document.setMinimumRowHeight(2000, row: 0, tableID: id))
        try document.setMinimumRowHeight(500, row: 0, tableID: id)
        var page = PageSettings(); page.height = 400
        try document.applyPageLayout(page, sectionID: document.sections[0].id)
        XCTAssertEqual(document.tables[0].minimumRowHeights?[0], page.contentHeight)
    }
    func testInvalidFormattingDoesNotChangeModelAndV6Migrates() throws {
        var document = ScribeDocument()
        document.insertTable(rows: 2, columns: 2, after: document.paragraphs[0].id)
        let original = document, id = document.tables[0].id
        var cell = TableCellStyle(row: 4, column: 1); cell.padding = 9
        XCTAssertThrowsError(try document.setCellStyles([cell], tableID: id))
        XCTAssertThrowsError(try document.setMinimumRowHeight(.nan, row: 0, tableID: id))
        XCTAssertEqual(document, original)
        var json = try JSONSerialization.jsonObject(with: NativeFormat.encode(document)) as! [String: Any]
        json["formatVersion"] = 6
        let migrated = try NativeFormat.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.formatVersion, ScribeDocument.currentVersion)
        XCTAssertNil(migrated.tables[0].cellStyles); XCTAssertNil(migrated.tables[0].minimumRowHeights)
        document.tables[0].rows = -1; document.tables[0].cellStyles = [cell]
        XCTAssertThrowsError(try NativeFormat.validate(document))
    }
}
