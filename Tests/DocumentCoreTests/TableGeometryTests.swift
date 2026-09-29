import XCTest
@testable import DocumentCore

final class TableGeometryTests: XCTestCase {
    func testColumnOperationsNeverMakeNarrowTablesInvalid() throws {
        var document = ScribeDocument()
        document.sections[0].page.width = 216 // 72-point writing area.
        let anchor = document.paragraphs[0].id
        document.insertTable(rows: 1, columns: 7, after: anchor)
        XCTAssertTrue(document.tables.isEmpty)
        document.insertTable(rows: 1, columns: 6, after: anchor)
        let before = document
        document.addTableColumn(tableID: document.tables[0].id, after: 0)
        XCTAssertEqual(document, before)
        XCTAssertNoThrow(try NativeFormat.validate(document))
    }
    func testInsertRowBeforeFirstPreservesExistingCells() throws {
        var document = ScribeDocument()
        document.insertTable(rows: 1, columns: 2, after: document.paragraphs[0].id)
        let table = document.tables[0]
        let originalCells = document.paragraphs.filter { $0.tableCell?.tableID == table.id }
        document.addTableRow(tableID: table.id, after: -1)
        XCTAssertEqual(document.tables[0].rows, 2)
        let cells = document.paragraphs.filter { $0.tableCell?.tableID == table.id }
        XCTAssertEqual(cells.count, 4)
        XCTAssertEqual(cells.prefix(2).map { $0.tableCell!.row }, [0, 0])
        XCTAssertEqual(cells.suffix(2).map(\.id), originalCells.map(\.id))
        XCTAssertEqual(cells.suffix(2).map { $0.tableCell!.row }, [1, 1])
        XCTAssertNoThrow(try NativeFormat.validate(document))
    }
}
