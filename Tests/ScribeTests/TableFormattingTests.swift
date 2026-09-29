#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class TableFormattingTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testCellFormattingProjectionNativeUndoAndRenderedRowHeight() throws {
        let document = ScribeFileDocument()
        document.model.insertTable(rows: 2, columns: 2, after: document.model.paragraphs[0].id)
        for p in document.model.sections[0].paragraphs.indices {
            if let cell = document.model.sections[0].paragraphs[p].tableCell { document.model.sections[0].paragraphs[p].runs = [TextRun("Cell \(cell.row),\(cell.column)")] }
        }
        let tableID = document.model.tables[0].id, reference = TableCellReference(tableID: document.model.tables[0].id, row: 1, column: 1)
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        document.undoManager?.removeAllActions()
        var style = TableCellStyle(row: 1, column: 1)
        style.background = "#DDEEFF"; style.padding = 9; style.borderColor = "#224466"; style.borderWidth = 2; style.verticalAlignment = .bottom
        try controller.applyCellProperties(style, target: reference, scope: .row, alignment: .right)
        XCTAssertEqual(document.snapshot().tables[0].cellStyles?.count, 2)
        XCTAssertEqual(document.snapshot().paragraphs.first(where: { $0.text == "Cell 1,1" })?.formatting?.alignment, .right)
        let range = (editor.storage.string as NSString).range(of: "Cell 1,1")
        let paragraph = try XCTUnwrap(editor.storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
        let block = try XCTUnwrap(paragraph.textBlocks.first)
        XCTAssertEqual(block.backgroundColor?.hex, "#DDEEFF")
        XCTAssertEqual(block.verticalAlignment, .bottomAlignment)
        document.undoManager?.undo()
        XCTAssertNil(document.snapshot().tables[0].cellStyles)
        document.undoManager?.redo()
        var updated = document.snapshot()
        try updated.setMinimumRowHeight(110, row: 1, tableID: tableID)
        document.performEdit("Row Height") { $0 = updated }
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("StyledTable.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Cell formatting", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url)), page = try XCTUnwrap(pdf.page(at: 0))
        let top = try XCTUnwrap(pdf.findString("Cell 0,1", withOptions: []).first)
        let bottom = try XCTUnwrap(pdf.findString("Cell 1,1", withOptions: []).first)
        XCTAssertGreaterThan(top.bounds(for: page).minY - bottom.bounds(for: page).minY, 80)
        XCTAssertTrue(page.string?.contains("Cell 1,0") == true)
    }
    func testMinimumHeightStillGrowsForLongCellText() throws {
        let document = ScribeFileDocument()
        document.model.insertTable(rows: 2, columns: 2, after: document.model.paragraphs[0].id)
        let tableID = document.model.tables[0].id
        for p in document.model.sections[0].paragraphs.indices {
            guard let cell = document.model.sections[0].paragraphs[p].tableCell else { continue }
            let text = cell.row == 0 && cell.column == 0 ? String(repeating: "Content must remain visible as this cell grows. ", count: 12) + "Final cell sentence." : "Row \(cell.row) column \(cell.column)"
            document.model.sections[0].paragraphs[p].runs = [TextRun(text)]
        }
        try document.model.setMinimumRowHeight(40, row: 0, tableID: tableID)
        let editor = PaginatedEditor(document: document)
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("GrowingTable.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Growing cells", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url)), page = try XCTUnwrap(pdf.page(at: 0))
        let end = try XCTUnwrap(pdf.findString("Final cell sentence.", withOptions: []).first)
        let next = try XCTUnwrap(pdf.findString("Row 1 column 0", withOptions: []).first)
        XCTAssertTrue(end.pages.first === page)
        XCTAssertTrue(next.pages.first === page)
        XCTAssertGreaterThan(end.bounds(for: page).minY, next.bounds(for: page).maxY)
    }
    func testNativeCellDialogCanFormatAColumnAndUndo() throws {
        let document = ScribeFileDocument()
        document.model.insertTable(rows: 2, columns: 2, after: document.model.paragraphs[0].id)
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!
        let target = try XCTUnwrap(document.model.paragraphs.first(where: { $0.tableCell != nil }))
        controller.editor.jump(to: target.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            guard let content = NSApp.modalWindow?.contentView else { XCTFail("Missing cell dialog"); NSApp.abortModal(); return }
            let views = descendants(content)
            let menus = views.compactMap { $0 as? NSPopUpButton }
            menus.first(where: { $0.itemTitles.contains("This column") })?.selectItem(withTitle: "This column")
            menus.first(where: { $0.itemTitles.contains("Table default (top)") })?.selectItem(withTitle: "Bottom")
            views.compactMap { $0 as? NSButton }.first(where: { $0.title == "Custom background" })?.state = .on
            NativeDialogCapture.save(content, name: "CellPropertiesDialog")
            guard let apply = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Apply" }) else { XCTFail("Missing Apply"); NSApp.abortModal(); return }
            apply.performClick(nil)
        }
        controller.cellProperties()
        XCTAssertEqual(document.snapshot().tables[0].cellStyles?.count, 2)
        XCTAssertTrue(document.snapshot().tables[0].cellStyles?.allSatisfy { $0.column == 0 && $0.verticalAlignment == .bottom } == true)
        document.undoManager?.undo()
        XCTAssertNil(document.snapshot().tables[0].cellStyles)
    }
}
#endif
