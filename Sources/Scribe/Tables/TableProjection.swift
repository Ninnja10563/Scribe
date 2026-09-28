#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor final class TableProjection {
    private var tables: [UUID: NSTextTable] = [:]
    private var blocks: [String: NSTextTableBlock] = [:]
    private let definitions: [UUID: DocumentTable]
    init(document: ScribeDocument) { definitions = Dictionary(uniqueKeysWithValues: document.tables.map { ($0.id, $0) }) }
    func apply(_ reference: TableCellReference, to attributes: inout [NSAttributedString.Key: Any]) {
        guard let definition = definitions[reference.tableID], definition.columnWidths.indices.contains(reference.column) else { return }
        let table: NSTextTable
        if let cached = tables[reference.tableID] { table = cached }
        else {
            table = NSTextTable(); table.numberOfColumns = definition.columnWidths.count
            table.layoutAlgorithm = .fixedLayoutAlgorithm; table.collapsesBorders = true; table.hidesEmptyCells = false
            table.setContentWidth(definition.columnWidths.reduce(0, +), type: .absoluteValueType)
            tables[reference.tableID] = table
        }
        let key = "\(reference.tableID)-\(reference.row)-\(reference.column)"
        let block: NSTextTableBlock
        if let cached = blocks[key] { block = cached }
        else {
            block = NSTextTableBlock(table: table, startingRow: reference.row, rowSpan: 1, startingColumn: reference.column, columnSpan: 1)
            block.setContentWidth(max(1, definition.columnWidths[reference.column] - definition.padding * 2 - definition.borderWidth * 2), type: .absoluteValueType)
            block.setWidth(definition.padding, type: .absoluteValueType, for: .padding)
            block.setWidth(definition.borderWidth, type: .absoluteValueType, for: .border)
            block.setBorderColor(NSColor(hex: definition.borderColor))
            block.verticalAlignment = .topAlignment
            if definition.firstRowIsHeader && reference.row == 0 { block.backgroundColor = NSColor(hex: definition.headerBackground) }
            blocks[key] = block
        }
        let style = (attributes[.paragraphStyle] as? NSParagraphStyle ?? .default).mutableCopy() as! NSMutableParagraphStyle
        style.textBlocks = [block]
        attributes[.paragraphStyle] = style
        attributes[.scribeCell] = try? JSONEncoder().encode(reference)
    }
}
#endif
