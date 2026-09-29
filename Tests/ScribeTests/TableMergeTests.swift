#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class TableMergeTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testTallMergedCellBlocksClippedPDFWithoutOverwritingExistingOutput() throws {
        let document = ScribeFileDocument()
        document.model.insertTable(rows: 40, columns: 1, after: document.model.paragraphs[0].id)
        for p in document.model.sections[0].paragraphs.indices {
            if let cell = document.model.sections[0].paragraphs[p].tableCell {
                document.model.sections[0].paragraphs[p].runs = [TextRun("Tall-cell-line-\(cell.row)-end")]
            }
        }
        try document.model.mergeTableCells(tableID: document.model.tables[0].id, region: TableMerge(row: 0, column: 0, rowSpan: 40, columnSpan: 1))
        let projection = NSMutableAttributedString(attributedString: AttributedDocument.render(document.model))
        let id = document.model.tables[0].id.uuidString
        let references = [Data("{\"row\":0,\"column\":0,\"tableID\":\"\(id)\"}".utf8), Data("{\"tableID\":\"\(id)\",\"column\":0,\"row\":0}".utf8)]
        for row in 0..<40 {
            let range = (projection.string as NSString).range(of: "Tall-cell-line-\(row)-end")
            projection.addAttribute(.scribeCell, value: references[row % 2], range: (projection.string as NSString).paragraphRange(for: range))
        }
        XCTAssertTrue(TableLayoutValidation().hasOversizedCell(storage: projection, document: document.model, pageHeight: document.model.sections[0].page.contentHeight))
        let editor = PaginatedEditor(document: document)
        defer { editor.prepareForClose(); document.close() }
        XCTAssertNotNil(editor.layoutWarning)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let original = Data("Existing output must remain unchanged".utf8); try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try PrintRenderer(editor: editor).exportPDF(to: url, title: "Long merged cell", author: ""))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(document.model.plainText.contains("Tall-cell-line-39-end"))
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document.model)), document.model)
        // Splitting leaves the existing text in the first ordinary cell. The
        // same safety check must cover that cell, not just merged geometry.
        try document.model.splitTableCell(tableID: document.model.tables[0].id, row: 0, column: 0)
        editor.storage.setAttributedString(AttributedDocument.render(document.model)); editor.paginate()
        XCTAssertNotNil(editor.layoutWarning)
        document.model = ScribeDocument()
        editor.storage.setAttributedString(AttributedDocument.render(document.model)); editor.paginate()
        XCTAssertNil(editor.layoutWarning, "Removing overflowing content must clear the warning")
    }
    func testMergedTableFlowsAcrossPagesWithoutMissingCells() throws {
        let document = ScribeFileDocument()
        document.model.insertTable(rows: 40, columns: 2, after: document.model.paragraphs[0].id)
        let id = document.model.tables[0].id
        document.model.tables[0].minimumRowHeights = Array(repeating: 55, count: 40)
        for p in document.model.sections[0].paragraphs.indices {
            if let cell = document.model.sections[0].paragraphs[p].tableCell {
                document.model.sections[0].paragraphs[p].runs = [TextRun("Unique-\(cell.row)-\(cell.column)-end")]
            }
        }
        try document.model.mergeTableCells(tableID: id, region: TableMerge(row: 10, column: 0, rowSpan: 5, columnSpan: 1))
        let editor = PaginatedEditor(document: document)
        defer { editor.prepareForClose(); document.close() }
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("MergedTable-Pages.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Merged table pagination", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 3)
        let text = pdf.string ?? ""
        for row in 0..<40 { for column in 0..<2 {
            let token = "Unique-\(row)-\(column)-end"
            XCTAssertEqual(text.components(separatedBy: token).count - 1, 1, "Missing or duplicated cell \(row),\(column)")
            let selection = try XCTUnwrap(pdf.findString(token, withOptions: []).first)
            let page = try XCTUnwrap(selection.pages.first)
            XCTAssertTrue(page.bounds(for: .mediaBox).contains(selection.bounds(for: page)), "Cell text outside the physical page: \(token)")
        } }
    }
    func testMergeDialogAndSplitUndo() throws {
        let document = ScribeFileDocument()
        document.model.insertTable(rows: 2, columns: 2, after: document.model.paragraphs[0].id)
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!
        let first = try XCTUnwrap(document.model.paragraphs.first { $0.tableCell != nil })
        controller.editor.jump(to: first.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            guard let content = NSApp.modalWindow?.contentView else { XCTFail("Missing merge dialog"); NSApp.abortModal(); return }
            let views = descendants(content)
            for field in views.compactMap({ $0 as? NSTextField }).filter({ $0.isEditable }) { field.stringValue = "2" }
            NativeDialogCapture.save(content, name: "MergeCellsDialog")
            guard let button = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Merge" }) else { XCTFail("Missing Merge"); NSApp.abortModal(); return }
            button.performClick(nil)
        }
        controller.mergeCells()
        XCTAssertEqual(document.snapshot().tables[0].mergedCells, [TableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 2)])
        document.undoManager?.removeAllActions()
        controller.splitMergedCell()
        XCTAssertNil(document.snapshot().tables[0].mergedCells)
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().tables[0].mergedCells?.count, 1)
    }
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
