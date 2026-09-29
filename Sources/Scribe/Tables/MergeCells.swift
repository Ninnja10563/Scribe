#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class MergeCellsOptions {
    let rows = NSTextField(string: "1"), columns = NSTextField(string: "2")
    let view: NSGridView
    init() {
        rows.setAccessibilityLabel("Rows to merge"); columns.setAccessibilityLabel("Columns to merge")
        view = NSGridView(views: [[NSTextField(labelWithString: "Rows"), rows], [NSTextField(labelWithString: "Columns"), columns]])
        view.columnSpacing = 24; view.rowSpacing = 12
        view.column(at: 0).width = 100; view.column(at: 1).width = 120
        view.frame = NSRect(x: 0, y: 0, width: 244, height: 64)
    }
}
extension EditorWindowController {
    @objc func mergeCells() {
        guard let cell = selectedTableCell else { showStatus("Place the cursor in the top-left cell to merge."); return }
        let options = MergeCellsOptions(), alert = NSAlert()
        alert.messageText = "Merge Cells"
        alert.informativeText = "Merge a rectangle starting at the current cell. All text is retained in reading order; the first cell’s formatting is used."
        alert.accessoryView = options.view; alert.addButton(withTitle: "Merge"); alert.addButton(withTitle: "Cancel")
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                guard let rows = Int(options.rows.stringValue), let columns = Int(options.columns.stringValue) else { throw DocumentError.invalid("enter whole numbers for rows and columns") }
                try applyCellMerge(cell: cell, rows: rows, columns: columns); return
            } catch { alert.informativeText = error.localizedDescription }
        }
    }
    func applyCellMerge(cell: TableCellReference, rows: Int, columns: Int) throws {
        var updated = fileDocument.snapshot()
        try updated.mergeTableCells(tableID: cell.tableID, region: TableMerge(row: cell.row, column: cell.column, rowSpan: rows, columnSpan: columns))
        fileDocument.performEdit("Merge Cells") { $0 = updated }
        if let first = updated.paragraphs.first(where: { $0.tableCell == cell }) { editor.jump(to: first.id) }
    }
    @objc func splitMergedCell() {
        guard let cell = selectedTableCell else { showStatus("Place the cursor in a merged cell."); return }
        do {
            var updated = fileDocument.snapshot()
            try updated.splitTableCell(tableID: cell.tableID, row: cell.row, column: cell.column)
            fileDocument.performEdit("Split Cell") { $0 = updated }
            showStatus("Cell split. Existing text stays in the first cell.")
        } catch { showStatus(error.localizedDescription) }
    }
}
#endif
