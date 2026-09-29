#if canImport(AppKit)
import AppKit
import DocumentCore

extension EditorWindowController {
    var selectedParagraphIndex: Int {
        let position = min(editor.activeTextView.selectedRange().location, editor.storage.length)
        return (editor.storage.string as NSString).substring(to: position).components(separatedBy: "\n").count - 1
    }
    var selectedTableCell: TableCellReference? {
        let model = fileDocument.snapshot(), index = selectedParagraphIndex
        return model.paragraphs.indices.contains(index) ? model.paragraphs[index].tableCell : nil
    }
    @objc func insertTable() {
        let model = fileDocument.snapshot(), index = selectedParagraphIndex
        guard model.paragraphs.indices.contains(index), model.paragraphs[index].tableCell == nil else { NSSound.beep(); return }
        let alert = NSAlert(); alert.messageText = "Insert Table"
        let rows = NSTextField(string: "3"), columns = NSTextField(string: "3")
        let stack = NSStackView(views: [NSTextField(labelWithString: "Rows (1–100)"), rows, NSTextField(labelWithString: "Columns (1–20)"), columns])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 240, height: 120); alert.accessoryView = stack
        alert.addButton(withTitle: "Insert"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let r = Int(rows.stringValue), let c = Int(columns.stringValue), (1...100).contains(r), (1...20).contains(c) else { return }
        guard Double(c) * 12 <= editor.canvas.pageSettings.contentWidth else { showStatus("This page is too narrow for that many columns."); return }
        let id = model.paragraphs[index].id
        fileDocument.performEdit("Insert Table") { $0.insertTable(rows: r, columns: c, after: id) }
        if let first = fileDocument.model.paragraphs.first(where: { $0.tableCell?.tableID == fileDocument.model.tables.last?.id }) { editor.jump(to: first.id) }
    }
    @objc func addTableRow() {
        guard let cell = selectedTableCell else { NSSound.beep(); return }
        fileDocument.performEdit("Add Table Row") { $0.addTableRow(tableID: cell.tableID, after: cell.row) }
    }
    @objc func deleteTableRow() {
        guard let cell = selectedTableCell else { NSSound.beep(); return }
        fileDocument.performEdit("Delete Table Row") { $0.deleteTableRow(tableID: cell.tableID, row: cell.row) }
    }
    @objc func addTableColumn() {
        guard let cell = selectedTableCell else { NSSound.beep(); return }
        guard let table = fileDocument.model.tables.first(where: { $0.id == cell.tableID }),
              table.columnWidths.count < 20, table.columnWidths.reduce(0, +) / Double(table.columnWidths.count + 1) >= 12 else {
            showStatus("Widen the table before adding another column (maximum 20 columns)."); return
        }
        fileDocument.performEdit("Add Table Column") { $0.addTableColumn(tableID: cell.tableID, after: cell.column) }
    }
    @objc func deleteTableColumn() {
        guard let cell = selectedTableCell else { NSSound.beep(); return }
        fileDocument.performEdit("Delete Table Column") { $0.deleteTableColumn(tableID: cell.tableID, column: cell.column) }
    }
    @objc func deleteTable() {
        guard let cell = selectedTableCell else { NSSound.beep(); return }
        fileDocument.performEdit("Delete Table") { $0.deleteTable(id: cell.tableID) }
    }
    @objc func tableProperties() {
        guard let cell = selectedTableCell, let table = fileDocument.model.tables.first(where: { $0.id == cell.tableID }) else { NSSound.beep(); return }
        let alert = NSAlert(); alert.messageText = "Table Properties"
        alert.informativeText = "Column widths are in points, separated by commas. The table must fit inside the page margins."
        let widths = NSTextField(string: table.columnWidths.map { String($0) }.joined(separator: ", "))
        let padding = NSTextField(string: String(table.padding)), border = NSTextField(string: String(table.borderWidth))
        let heading = NSButton(checkboxWithTitle: "Shade the first row", target: nil, action: nil); heading.state = table.firstRowIsHeader ? .on : .off
        let stack = NSStackView(views: [NSTextField(labelWithString: "Column widths"), widths, NSTextField(labelWithString: "Cell padding"), padding, NSTextField(labelWithString: "Border thickness"), border, heading])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        widths.widthAnchor.constraint(equalToConstant: 320).isActive = true
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 205); alert.accessoryView = stack
        alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let values = widths.stringValue.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == table.columnWidths.count, values.allSatisfy({ (12...4000).contains($0) }), values.reduce(0, +) <= editor.canvas.pageSettings.contentWidth,
              let p = Double(padding.stringValue), (0...20).contains(p), let b = Double(border.stringValue), (0...10).contains(b) else { return }
        fileDocument.performEdit("Table Properties") { model in
            guard let index = model.tables.firstIndex(where: { $0.id == table.id }) else { return }
            model.tables[index].columnWidths = values; model.tables[index].padding = p; model.tables[index].borderWidth = b; model.tables[index].firstRowIsHeader = heading.state == .on
        }
    }
}
#endif
