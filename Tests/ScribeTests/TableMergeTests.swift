#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class TableMergeTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testMergedCellProjectionUndoTabAndPDF() throws {
        let document = ScribeFileDocument()
        document.model.insertTable(rows: 3, columns: 3, after: document.model.paragraphs[0].id)
        for p in document.model.sections[0].paragraphs.indices {
            if let cell = document.model.sections[0].paragraphs[p].tableCell { document.model.sections[0].paragraphs[p].runs = [TextRun("Cell \(cell.row),\(cell.column)")] }
        }
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        let cell = TableCellReference(tableID: document.model.tables[0].id, row: 0, column: 0)
        document.undoManager?.removeAllActions()
        try controller.applyCellMerge(cell: cell, rows: 2, columns: 2)
        let location = (editor.storage.string as NSString).range(of: "Cell 1,1").location
        let style = try XCTUnwrap(editor.storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
        let block = try XCTUnwrap(style.textBlocks.first as? NSTextTableBlock)
        XCTAssertEqual(block.rowSpan, 2); XCTAssertEqual(block.columnSpan, 2)
        XCTAssertEqual(document.snapshot().tables[0].mergedCells?.count, 1)
        document.undoManager?.undo(); XCTAssertNil(document.snapshot().tables[0].mergedCells)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().tables[0].mergedCells?.count, 1)
        let first = try XCTUnwrap(document.model.paragraphs.first { $0.tableCell == cell })
        editor.jump(to: first.id)
        editor.activeTextView.insertTab(nil)
        XCTAssertEqual(controller.selectedTableCell?.column, 2)
        XCTAssertEqual(controller.selectedTableCell?.row, 0)
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("MergedTable.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Merged cells", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url)), page = try XCTUnwrap(pdf.page(at: 0))
        for row in 0..<3 { for column in 0..<3 { XCTAssertTrue(pdf.string?.contains("Cell \(row),\(column)") == true) } }
        let anchor = try XCTUnwrap(pdf.findString("Cell 0,0", withOptions: []).first)
        let right = try XCTUnwrap(pdf.findString("Cell 0,2", withOptions: []).first)
        XCTAssertGreaterThan(right.bounds(for: page).minX - anchor.bounds(for: page).minX, 200)
        let end = try XCTUnwrap(pdf.findString("Cell 1,1", withOptions: []).first)
        let following = try XCTUnwrap(pdf.findString("Cell 2,0", withOptions: []).first)
        XCTAssertGreaterThan(end.bounds(for: page).minY, following.bounds(for: page).maxY)
    }
}
#endif
