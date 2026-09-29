import Foundation
import DocumentCore

/// Resolves OOXML grid spans and vertical continuation cells before semantic validation.
final class DOCXTableMergingReader {
    var span = 1
    var vertical: String?
    private var paragraphStart = 0
    private var active: [Int: (index: Int, lastRow: Int, span: Int)] = [:]
    func startTable() { active = [:]; span = 1; vertical = nil }
    func startCell(paragraphCount: Int) { span = 1; vertical = nil; paragraphStart = paragraphCount }
    func finishCell(table: inout DocumentTable, row: Int, column: Int, paragraphs: inout [Paragraph], protectedIDs: Set<UUID>, warnings: inout Set<String>) {
        guard row >= 0, column >= 0, span > 0, span <= 20, column <= 20 - span else { return }
        while table.columnWidths.count < column + span { table.columnWidths.append(100) }
        if vertical == "continue", let previous = active[column], previous.lastRow == row - 1, previous.span == span,
           var merges = table.mergedCells, merges.indices.contains(previous.index) {
            merges[previous.index].rowSpan += 1
            let anchor = merges[previous.index]
            table.mergedCells = merges; active[column] = (previous.index, row, span)
            let tail = paragraphs[paragraphStart...].compactMap { value -> Paragraph? in
                // Word requires an empty paragraph in continuation cells. It has no
                // semantic text unless a bookmark or review range refers to it.
                if value.text.isEmpty && value.runs.allSatisfy({ $0.image == nil }) && !protectedIDs.contains(value.id) { return nil }
                var paragraph = value
                paragraph.tableCell = TableCellReference(tableID: table.id, row: anchor.row, column: anchor.column)
                if !value.text.isEmpty { warnings.insert("Text in a vertical merge continuation was retained in its merged cell.") }
                return paragraph
            }
            paragraphs.replaceSubrange(paragraphStart..., with: tail)
        } else {
            if vertical == "continue" { warnings.insert("A vertical cell continuation has no matching preceding cell; its content was retained as a separate cell.") }
            active[column] = nil
            if span > 1 || vertical == "restart" {
                var merges = table.mergedCells ?? []
                merges.append(TableMerge(row: row, column: column, rowSpan: 1, columnSpan: span))
                table.mergedCells = merges
                if vertical == "restart" { active[column] = (merges.count - 1, row, span) }
            }
        }
    }
    func finishTable(_ table: inout DocumentTable) {
        table.mergedCells = table.mergedCells?.filter { $0.rowSpan > 1 || $0.columnSpan > 1 }
        if table.mergedCells?.isEmpty == true { table.mergedCells = nil }
    }
}
