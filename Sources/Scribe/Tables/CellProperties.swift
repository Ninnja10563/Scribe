#if canImport(AppKit)
import AppKit
import DocumentCore

enum TableFormattingScope: Int { case cell, row, column, table }

@MainActor final class CellPropertiesOptions {
    let scope = NSPopUpButton()
    let background = NSColorWell(), borderColor = NSColorWell()
    let customBackground = NSButton(checkboxWithTitle: "Custom background", target: nil, action: nil)
    let customBorder = NSButton(checkboxWithTitle: "Custom border", target: nil, action: nil)
    let padding: NSTextField, borderWidth: NSTextField
    let vertical = NSPopUpButton(), alignment = NSPopUpButton()
    let view = NSStackView()
    init(table: DocumentTable, cell: TableCellReference) {
        let style = table.cellStyle(row: cell.row, column: cell.column)
        padding = NSTextField(string: style?.padding.map { String($0) } ?? "")
        padding.placeholderString = "Table default"
        borderWidth = NSTextField(string: String(style?.borderWidth ?? table.borderWidth))
        background.color = NSColor(hex: style?.background ?? (cell.row == 0 && table.firstRowIsHeader ? table.headerBackground : "#FFFFFF"))
        borderColor.color = NSColor(hex: style?.borderColor ?? table.borderColor)
        customBackground.state = style?.background == nil ? .off : .on
        customBorder.state = style?.borderColor == nil && style?.borderWidth == nil ? .off : .on
        scope.addItems(withTitles: ["This cell", "This row", "This column", "Whole table"])
        vertical.addItems(withTitles: ["Table default (top)", "Top", "Centre", "Bottom"])
        vertical.selectItem(at: style?.verticalAlignment.map { TableVerticalAlignment.allCases.firstIndex(of: $0)! + 1 } ?? 0)
        alignment.addItems(withTitles: ["Keep paragraph alignment", "Left", "Centre", "Right", "Justified"])
        let rows: [(String, NSView)] = [("Apply to", scope), ("Background", NSStackView(views: [customBackground, background])),
            ("Border", NSStackView(views: [customBorder, borderColor])), ("Border width (pt)", borderWidth), ("Cell padding (pt)", padding),
            ("Vertical alignment", vertical), ("Text alignment", alignment)]
        let grid = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0), $0.1] })
        grid.columnSpacing = 12; grid.rowSpacing = 8
        for row in 0..<grid.numberOfRows { grid.row(at: row).height = 28 }
        grid.column(at: 0).width = 145; grid.column(at: 1).width = 255
        for (label, control) in rows { control.setAccessibilityLabel(label) }
        background.setAccessibilityLabel("Cell background colour"); borderColor.setAccessibilityLabel("Cell border colour")
        for well in [background, borderColor] { well.widthAnchor.constraint(equalToConstant: 44).isActive = true; well.heightAnchor.constraint(equalToConstant: 24).isActive = true }
        view.orientation = .vertical; view.alignment = .leading; view.addArrangedSubview(grid)
        view.frame = NSRect(x: 0, y: 0, width: 412, height: 250)
    }
    func style(for cell: TableCellReference) throws -> TableCellStyle {
        var style = TableCellStyle(row: cell.row, column: cell.column)
        if customBackground.state == .on { style.background = background.color.hex }
        if !padding.stringValue.isEmpty {
            guard let value = Double(padding.stringValue), value.isFinite, (0...50).contains(value) else { throw DocumentError.invalid("cell padding must be 0–50 points, or blank to inherit") }
            style.padding = value
        }
        if customBorder.state == .on {
            guard let value = Double(borderWidth.stringValue), value.isFinite, (0...10).contains(value) else { throw DocumentError.invalid("border width must be 0–10 points") }
            style.borderWidth = value; style.borderColor = borderColor.color.hex
        }
        if vertical.indexOfSelectedItem > 0 { style.verticalAlignment = TableVerticalAlignment.allCases[vertical.indexOfSelectedItem - 1] }
        return style
    }
}

extension EditorWindowController {
    @objc func cellProperties() {
        guard let cell = selectedTableCell, let table = fileDocument.model.tables.first(where: { $0.id == cell.tableID }) else { showStatus("Place the cursor inside a table cell."); return }
        let options = CellPropertiesOptions(table: table, cell: cell)
        let alert = NSAlert(); alert.messageText = "Cell Properties"
        alert.informativeText = "Apply the shown settings to a cell, row, column or table. Unchecked colours and blank padding inherit the table defaults."
        alert.accessoryView = options.view; alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                let alignment: Alignment? = options.alignment.indexOfSelectedItem > 0 ? Alignment.allCases[options.alignment.indexOfSelectedItem - 1] : nil
                try applyCellProperties(options.style(for: cell), target: cell, scope: TableFormattingScope(rawValue: options.scope.indexOfSelectedItem) ?? .cell, alignment: alignment)
                return
            } catch { alert.informativeText = error.localizedDescription }
        }
    }
    func applyCellProperties(_ style: TableCellStyle, target: TableCellReference, scope: TableFormattingScope, alignment: Alignment? = nil) throws {
        var updated = fileDocument.snapshot()
        guard let table = updated.tables.first(where: { $0.id == target.tableID }) else { return }
        var styles: [TableCellStyle] = []
        for row in 0..<table.rows { for column in table.columnWidths.indices {
            let matches = scope == .table || (scope == .row && row == target.row) || (scope == .column && column == target.column) || (row == target.row && column == target.column)
            if matches { var value = style; value.row = row; value.column = column; styles.append(value) }
        } }
        try updated.setCellStyles(styles, tableID: table.id)
        if let alignment {
            let coordinates = Set(styles.map { $0.row * table.columnWidths.count + $0.column })
            for section in updated.sections.indices { for p in updated.sections[section].paragraphs.indices {
                let paragraph = updated.sections[section].paragraphs[p]
                guard let cell = paragraph.tableCell, cell.tableID == table.id, coordinates.contains(cell.row * table.columnWidths.count + cell.column) else { continue }
                var formatting = paragraph.formatting ?? updated.style(for: paragraph).paragraph
                formatting.alignment = alignment; updated.sections[section].paragraphs[p].formatting = formatting
            } }
        }
        fileDocument.performEdit("Cell Properties") { $0 = updated }
    }
    @objc func rowProperties() {
        guard let cell = selectedTableCell, let table = fileDocument.model.tables.first(where: { $0.id == cell.tableID }) else { showStatus("Place the cursor inside a table row."); return }
        let value = table.minimumRowHeights?[cell.row]
        let height = NSTextField(string: value.map { String($0) } ?? "")
        height.placeholderString = "Automatic"; height.setAccessibilityLabel("Minimum row height in points")
        height.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        let alert = NSAlert(); alert.messageText = "Row Height"
        alert.informativeText = "Set a minimum height in points (72 points = 1 inch), or leave blank for automatic height. Rows can grow to fit their text."
        alert.accessoryView = height; alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                let number = height.stringValue.isEmpty ? nil : Double(height.stringValue)
                if !height.stringValue.isEmpty && number == nil { throw DocumentError.invalid("enter a numeric height or leave blank") }
                var updated = fileDocument.snapshot()
                try updated.setMinimumRowHeight(number, row: cell.row, tableID: table.id)
                fileDocument.performEdit("Row Height") { $0 = updated }; return
            } catch { alert.informativeText = error.localizedDescription }
        }
    }
}
#endif
