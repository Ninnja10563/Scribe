import Foundation

public enum TableVerticalAlignment: String, Codable, Sendable, CaseIterable { case top, center, bottom }

/// Sparse direct formatting; absent properties inherit the table definition.
public struct TableCellStyle: Codable, Equatable, Sendable {
    public var row: Int
    public var column: Int
    public var background: String?
    public var padding: Double?
    public var borderColor: String?
    public var borderWidth: Double?
    public var verticalAlignment: TableVerticalAlignment?
    public init(row: Int, column: Int) { self.row = row; self.column = column }
    public var isEmpty: Bool { background == nil && padding == nil && borderColor == nil && borderWidth == nil && verticalAlignment == nil }
}

extension DocumentTable {
    public func cellStyle(row: Int, column: Int) -> TableCellStyle? {
        cellStyles?.first { $0.row == row && $0.column == column }
    }
}
extension ScribeDocument {
    public mutating func setCellStyles(_ styles: [TableCellStyle], tableID: UUID) throws {
        guard let index = tables.firstIndex(where: { $0.id == tableID }) else { throw DocumentError.invalid("missing table") }
        var result = self, cells = tables[index].cellStyles ?? []
        for style in styles {
            cells.removeAll { $0.row == style.row && $0.column == style.column }
            if !style.isEmpty { cells.append(style) }
        }
        result.tables[index].cellStyles = cells.isEmpty ? nil : cells
        try NativeFormat.validate(result); self = result
    }
    public mutating func setMinimumRowHeight(_ height: Double?, row: Int, tableID: UUID) throws {
        guard let index = tables.firstIndex(where: { $0.id == tableID }), (0..<tables[index].rows).contains(row) else { throw DocumentError.invalid("missing table row") }
        if let height {
            let areas = sections.filter { $0.paragraphs.contains(where: { $0.tableCell?.tableID == tableID }) }.map { $0.page.contentHeight }
            if let limit = areas.min(), height > limit { throw DocumentError.invalid("minimum row height exceeds the page writing area") }
        }
        var result = self
        var heights = tables[index].minimumRowHeights ?? Array(repeating: nil, count: tables[index].rows)
        heights[row] = height
        result.tables[index].minimumRowHeights = heights.contains(where: { $0 != nil }) ? heights : nil
        try NativeFormat.validate(result); self = result
    }
}
