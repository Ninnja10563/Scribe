import Foundation

public struct InlineImage: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var data: Data
    public var fileExtension: String
    public var width: Double
    public var height: Double
    public var altText: String
    public init(data: Data, fileExtension: String, width: Double, height: Double, altText: String = "") {
        self.data = data; self.fileExtension = fileExtension; self.width = width; self.height = height; self.altText = altText
    }
}

public struct TableCellReference: Codable, Equatable, Sendable {
    public var tableID: UUID
    public var row: Int
    public var column: Int
    public init(tableID: UUID, row: Int, column: Int) { self.tableID = tableID; self.row = row; self.column = column }
}

/// Cell text remains in the document flow, anchored to its semantic table and cell.
/// Multiple adjacent paragraphs can belong to one cell.
public struct DocumentTable: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var rows: Int
    public var columnWidths: [Double]
    public var padding = 6.0
    public var borderWidth = 0.5
    public var borderColor = "#B8BCC2"
    public var headerBackground = "#EFF1F3"
    public var firstRowIsHeader = true
    public var cellStyles: [TableCellStyle]?
    public var minimumRowHeights: [Double?]?
    public init(rows: Int, columns: Int, width: Double) {
        self.rows = rows; columnWidths = Array(repeating: width / Double(max(1, columns)), count: max(1, columns))
    }
}

public extension ScribeDocument {
    mutating func insertTable(rows: Int, columns: Int, after paragraphID: UUID) {
        guard (1...100).contains(rows), (1...20).contains(columns) else { return }
        guard let section = sections.firstIndex(where: { $0.paragraphs.contains(where: { $0.id == paragraphID }) }),
              let index = sections[section].paragraphs.firstIndex(where: { $0.id == paragraphID }),
              sections[section].paragraphs[index].tableCell == nil else { return }
        guard Double(columns) * 12 <= sections[section].page.contentWidth else { return }
        let table = DocumentTable(rows: rows, columns: columns, width: sections[section].page.contentWidth)
        tables.append(table)
        var cells: [Paragraph] = []
        for row in 0..<rows {
            for column in 0..<columns {
                var paragraph = Paragraph()
                paragraph.tableCell = TableCellReference(tableID: table.id, row: row, column: column)
                cells.append(paragraph)
            }
        }
        cells.append(Paragraph())
        sections[section].paragraphs.insert(contentsOf: cells, at: index + 1)
    }
    mutating func addTableRow(tableID: UUID, after row: Int) {
        guard let t = tables.firstIndex(where: { $0.id == tableID }), tables[t].rows < 100 else { return }
        let insertionRow = max(0, min(tables[t].rows, row + 1))
        for s in sections.indices {
            let insertionIndex: Int?
            if insertionRow == 0 { insertionIndex = sections[s].paragraphs.firstIndex(where: { $0.tableCell?.tableID == tableID }) }
            else { insertionIndex = sections[s].paragraphs.lastIndex(where: { $0.tableCell?.tableID == tableID && $0.tableCell!.row < insertionRow }).map { $0 + 1 } }
            guard let insertionIndex else { continue }
            for p in sections[s].paragraphs.indices {
                if let cell = sections[s].paragraphs[p].tableCell, cell.tableID == tableID, cell.row >= insertionRow { sections[s].paragraphs[p].tableCell?.row += 1 }
            }
            var newRow: [Paragraph] = []
            for column in tables[t].columnWidths.indices {
                var p = Paragraph(); p.tableCell = TableCellReference(tableID: tableID, row: insertionRow, column: column); newRow.append(p)
            }
            sections[s].paragraphs.insert(contentsOf: newRow, at: insertionIndex)
        }
        tables[t].cellStyles = tables[t].cellStyles?.map { value in
            var style = value; if style.row >= insertionRow { style.row += 1 }; return style
        }
        tables[t].minimumRowHeights?.insert(nil, at: insertionRow)
        tables[t].rows += 1
    }
    mutating func deleteTableRow(tableID: UUID, row: Int) {
        defer { reconcileCommentAnchors() }
        guard let t = tables.firstIndex(where: { $0.id == tableID }) else { return }
        if tables[t].rows == 1 { deleteTable(id: tableID); return }
        guard (0..<tables[t].rows).contains(row) else { return }
        for s in sections.indices {
            sections[s].paragraphs.removeAll { $0.tableCell?.tableID == tableID && $0.tableCell?.row == row }
            for p in sections[s].paragraphs.indices {
                if let cell = sections[s].paragraphs[p].tableCell, cell.tableID == tableID, cell.row > row { sections[s].paragraphs[p].tableCell?.row -= 1 }
            }
        }
        tables[t].cellStyles = tables[t].cellStyles?.filter { $0.row != row }.map { value in
            var style = value; if style.row > row { style.row -= 1 }; return style
        }
        tables[t].minimumRowHeights?.remove(at: row)
        tables[t].rows -= 1
    }
    mutating func addTableColumn(tableID: UUID, after column: Int) {
        guard let t = tables.firstIndex(where: { $0.id == tableID }), tables[t].columnWidths.count < 20 else { return }
        let insertion = max(0, min(tables[t].columnWidths.count, column + 1))
        let total = tables[t].columnWidths.reduce(0, +)
        guard total / Double(tables[t].columnWidths.count + 1) >= 12 else { return }
        for s in sections.indices {
            for p in sections[s].paragraphs.indices {
                if let cell = sections[s].paragraphs[p].tableCell, cell.tableID == tableID, cell.column >= insertion { sections[s].paragraphs[p].tableCell?.column += 1 }
            }
            for row in (0..<tables[t].rows).reversed() {
                let rowIndices = sections[s].paragraphs.indices.filter { sections[s].paragraphs[$0].tableCell?.tableID == tableID && sections[s].paragraphs[$0].tableCell?.row == row }
                guard let last = rowIndices.last else { continue }
                let index = rowIndices.first { sections[s].paragraphs[$0].tableCell!.column > insertion } ?? (last + 1)
                var p = Paragraph(); p.tableCell = TableCellReference(tableID: tableID, row: row, column: insertion)
                sections[s].paragraphs.insert(p, at: index)
            }
        }
        tables[t].cellStyles = tables[t].cellStyles?.map { value in
            var style = value; if style.column >= insertion { style.column += 1 }; return style
        }
        tables[t].columnWidths = Array(repeating: total / Double(tables[t].columnWidths.count + 1), count: tables[t].columnWidths.count + 1)
    }
    mutating func deleteTableColumn(tableID: UUID, column: Int) {
        defer { reconcileCommentAnchors() }
        guard let t = tables.firstIndex(where: { $0.id == tableID }), tables[t].columnWidths.indices.contains(column) else { return }
        if tables[t].columnWidths.count == 1 { deleteTable(id: tableID); return }
        for s in sections.indices {
            sections[s].paragraphs.removeAll { $0.tableCell?.tableID == tableID && $0.tableCell?.column == column }
            for p in sections[s].paragraphs.indices {
                if let cell = sections[s].paragraphs[p].tableCell, cell.tableID == tableID, cell.column > column { sections[s].paragraphs[p].tableCell?.column -= 1 }
            }
        }
        let total = tables[t].columnWidths.reduce(0, +)
        tables[t].cellStyles = tables[t].cellStyles?.filter { $0.column != column }.map { value in
            var style = value; if style.column > column { style.column -= 1 }; return style
        }
        tables[t].columnWidths = Array(repeating: total / Double(tables[t].columnWidths.count - 1), count: tables[t].columnWidths.count - 1)
    }
    mutating func deleteTable(id: UUID) {
        defer { reconcileCommentAnchors() }
        tables.removeAll { $0.id == id }
        for s in sections.indices {
            sections[s].paragraphs.removeAll { $0.tableCell?.tableID == id }
            if sections[s].paragraphs.isEmpty { sections[s].paragraphs = [Paragraph()] }
        }
    }
}
