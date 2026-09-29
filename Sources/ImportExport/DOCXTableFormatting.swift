import Foundation
import DocumentCore

extension DOCX {
    static func cellProperties(_ table: DocumentTable, row: Int, column: Int) -> String {
        let style = table.cellStyle(row: row, column: column)
        var result = ""
        if style?.borderColor != nil || style?.borderWidth != nil {
            let width = style?.borderWidth ?? table.borderWidth, color = style?.borderColor ?? table.borderColor
            let attributes = width == 0 ? "w:val=\"nil\"" : "w:val=\"single\" w:sz=\"\(Int(width * 8))\" w:color=\"\(color.dropFirst())\""
            result += "<w:tcBorders>" + ["top", "left", "bottom", "right"].map { "<w:\($0) \(attributes)/>" }.joined() + "</w:tcBorders>"
        }
        if let color = style?.background ?? (row == 0 && table.firstRowIsHeader ? table.headerBackground : nil) {
            result += "<w:shd w:val=\"clear\" w:fill=\"\(color.dropFirst())\"/>"
        }
        if let padding = style?.padding {
            result += "<w:tcMar>" + ["top", "left", "bottom", "right"].map { "<w:\($0) w:w=\"\(Int(padding * 20))\" w:type=\"dxa\"/>" }.joined() + "</w:tcMar>"
        }
        if let alignment = style?.verticalAlignment { result += "<w:vAlign w:val=\"\(alignment.rawValue)\"/>" }
        return result
    }
    static func rowProperties(_ table: DocumentTable, row: Int) -> String {
        var result = ""
        if let heights = table.minimumRowHeights, heights.indices.contains(row), let height = heights[row] {
            result += "<w:trHeight w:val=\"\(Int(height * 20))\" w:hRule=\"atLeast\"/>"
        }
        if row == 0 && table.firstRowIsHeader { result += "<w:tblHeader/>" }
        return result.isEmpty ? "" : "<w:trPr>\(result)</w:trPr>"
    }
}

/// Keep table/cell property parsing out of text-run handling. Nonuniform edges are
/// explicitly approximated because the current model uses a uniform cell border/padding.
final class DOCXTableFormattingReader {
    private enum Scope: Equatable { case table, cell }
    private struct Border: Equatable { let width: Double; let color: String? }
    private var scope: Scope?
    private var container: String?
    private var cell: TableCellStyle?
    private var borders: [Border] = []
    private var padding: [Double] = []

    func start(_ name: String, _ attributes: [String: String], table: inout DocumentTable, row: Int, column: Int, warnings: inout Set<String>) {
        switch name {
        case "tbl": scope = nil; container = nil; cell = nil
        case "tc": cell = TableCellStyle(row: row, column: column)
        case "tblPr": scope = .table
        case "tcPr": scope = .cell
        case "tcBorders", "tblBorders": container = name; borders = []
        case "tcMar", "tblCellMar": container = name; padding = []
        case "top", "left", "bottom", "right", "start", "end", "insideH", "insideV":
            guard scope != nil else { return }
            if container == "tcBorders" || container == "tblBorders" {
                let kind = wordAttribute(attributes) ?? "single"
                let width = ["nil", "none"].contains(kind) ? 0 : min(10, max(0, (wordAttribute(attributes, "sz").flatMap(Double.init) ?? 4) / 8))
                if !["single", "nil", "none"].contains(kind) { warnings.insert("Patterned table borders are approximated with solid borders.") }
                borders.append(Border(width: width, color: color(wordAttribute(attributes, "color"))))
            } else if container == "tcMar" || container == "tblCellMar" {
                guard wordAttribute(attributes, "type") == nil || wordAttribute(attributes, "type") == "dxa", let points = wordAttribute(attributes, "w").flatMap(Double.init) else {
                    warnings.insert("Relative table cell padding is not imported."); return
                }
                padding.append(min(50, max(0, points / 20)))
            }
        case "shd":
            if scope == .cell { cell?.background = color(wordAttribute(attributes, "fill")) }
            else if scope == .table { warnings.insert("Table-wide shading is not imported; explicit cell shading is retained.") }
        case "vAlign": if scope == .cell { cell?.verticalAlignment = wordAttribute(attributes).flatMap(TableVerticalAlignment.init(rawValue:)) }
        case "trHeight":
            guard row >= 0, wordAttribute(attributes, "hRule") != "auto", let value = wordAttribute(attributes).flatMap(Double.init), value > 0 else { return }
            if wordAttribute(attributes, "hRule") == "exact" { warnings.insert("Fixed table row heights become minimum heights so text is not clipped.") }
            var heights = table.minimumRowHeights ?? []
            while heights.count <= row { heights.append(nil) }
            heights[row] = min(4000, max(1, value / 20)); table.minimumRowHeights = heights
        default: break
        }
    }
    func end(_ name: String, table: inout DocumentTable, warnings: inout Set<String>) {
        if name == "tcBorders" || name == "tblBorders" {
            if let first = borders.first {
                if borders.contains(where: { $0 != first }) { warnings.insert("Different cell-edge borders are approximated with one uniform border.") }
                if scope == .cell { cell?.borderWidth = first.width; cell?.borderColor = first.color }
                else if scope == .table { table.borderWidth = first.width; if let color = first.color { table.borderColor = color } }
            }
            container = nil
        } else if name == "tcMar" || name == "tblCellMar" {
            if let maximum = padding.max() {
                if padding.contains(where: { $0 != maximum }) { warnings.insert("Different cell-edge padding is approximated using the largest inset.") }
                if scope == .cell { cell?.padding = maximum } else if scope == .table { table.padding = maximum }
            }
            container = nil
        } else if name == "tcPr" {
            if let cell, !cell.isEmpty { table.cellStyles = (table.cellStyles ?? []) + [cell] }
            scope = nil
        } else if name == "tblPr" { scope = nil }
        else if name == "tbl", var heights = table.minimumRowHeights {
            while heights.count < table.rows { heights.append(nil) }
            table.minimumRowHeights = heights
        }
    }
    private func color(_ value: String?) -> String? {
        guard let value, value.count == 6, UInt32(value, radix: 16) != nil else { return nil }
        return "#" + value.uppercased()
    }
}
