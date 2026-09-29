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
    public var mergedCells: [TableMerge]?
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
        guard let table = tables.first(where: { $0.id == tableID }) else { return }
        editTableGrid(tableID: tableID, rowAxis: true, position: max(-1, min(table.rows - 1, row)) + 1, inserting: true)
    }
    mutating func deleteTableRow(tableID: UUID, row: Int) {
        editTableGrid(tableID: tableID, rowAxis: true, position: row, inserting: false)
    }
    mutating func addTableColumn(tableID: UUID, after column: Int) {
        guard let table = tables.first(where: { $0.id == tableID }) else { return }
        editTableGrid(tableID: tableID, rowAxis: false, position: max(-1, min(table.columnWidths.count - 1, column)) + 1, inserting: true)
    }
    mutating func deleteTableColumn(tableID: UUID, column: Int) {
        editTableGrid(tableID: tableID, rowAxis: false, position: column, inserting: false)
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
