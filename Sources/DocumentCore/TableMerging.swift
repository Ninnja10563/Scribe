import Foundation

/// Rectangular merged cells retain their content at the top-left grid location.
public struct TableMerge: Codable, Equatable, Sendable {
    public var row: Int
    public var column: Int
    public var rowSpan: Int
    public var columnSpan: Int
    public init(row: Int, column: Int, rowSpan: Int, columnSpan: Int) {
        self.row = row; self.column = column; self.rowSpan = rowSpan; self.columnSpan = columnSpan
    }
    public func contains(row: Int, column: Int) -> Bool {
        row >= self.row && row - self.row < rowSpan && column >= self.column && column - self.column < columnSpan
    }
}

extension DocumentTable {
    public func merge(atRow row: Int, column: Int) -> TableMerge? {
        mergedCells?.first { $0.contains(row: row, column: column) }
    }
    public func anchor(row: Int, column: Int) -> TableCellReference {
        let merge = merge(atRow: row, column: column)
        return TableCellReference(tableID: id, row: merge?.row ?? row, column: merge?.column ?? column)
    }
    public var cellAnchors: [TableCellReference] {
        (0..<rows).flatMap { row in columnWidths.indices.compactMap { column in
            let cell = anchor(row: row, column: column)
            return cell.row == row && cell.column == column ? cell : nil
        } }
    }
}

extension ScribeDocument {
    public mutating func mergeTableCells(tableID: UUID, region: TableMerge) throws {
        guard let t = tables.firstIndex(where: { $0.id == tableID }) else { throw DocumentError.invalid("missing table") }
        let table = tables[t]
        guard region.row >= 0, region.column >= 0, region.rowSpan > 0, region.columnSpan > 0,
              region.rowSpan <= table.rows, region.columnSpan <= table.columnWidths.count,
              region.row <= table.rows - region.rowSpan, region.column <= table.columnWidths.count - region.columnSpan,
              region.rowSpan > 1 || region.columnSpan > 1 else { throw DocumentError.invalid("choose two or more cells inside the table") }
        for existing in table.mergedCells ?? [] {
            let overlaps = existing.row < region.row + region.rowSpan && region.row < existing.row + existing.rowSpan && existing.column < region.column + region.columnSpan && region.column < existing.column + existing.columnSpan
            if overlaps && !(region.contains(row: existing.row, column: existing.column) && region.contains(row: existing.row + existing.rowSpan - 1, column: existing.column + existing.columnSpan - 1)) {
                throw DocumentError.invalid("the selection cuts through an existing merged cell")
            }
        }
        var result = self
        var merges = table.mergedCells ?? []
        merges.removeAll { region.contains(row: $0.row, column: $0.column) }
        merges.append(region); result.tables[t].mergedCells = merges
        result.normalizeTableFlow(tableID: tableID)
        result.reconcileCommentAnchors()
        try NativeFormat.validate(result); self = result
    }
    public mutating func splitTableCell(tableID: UUID, row: Int, column: Int) throws {
        guard let t = tables.firstIndex(where: { $0.id == tableID }), let merge = tables[t].merge(atRow: row, column: column) else { throw DocumentError.invalid("choose a merged cell") }
        var result = self
        result.tables[t].mergedCells?.removeAll { $0 == merge }
        if result.tables[t].mergedCells?.isEmpty == true { result.tables[t].mergedCells = nil }
        // Split leaves all existing text in the first cell; the other cells start empty.
        result.normalizeTableFlow(tableID: tableID)
        try NativeFormat.validate(result); self = result
    }

    /// Group paragraphs by cell without replacing their IDs, runs or review anchors.
    /// Missing cells become empty paragraphs, including after split or grid edits.
    public mutating func normalizeTableFlow(tableID: UUID) {
        guard let table = tables.first(where: { $0.id == tableID }), (1...100).contains(table.rows), (1...20).contains(table.columnWidths.count) else { return }
        for s in sections.indices {
            guard let start = sections[s].paragraphs.firstIndex(where: { $0.tableCell?.tableID == tableID }) else { continue }
            var content: [Int: [Paragraph]] = [:]
            for var paragraph in sections[s].paragraphs where paragraph.tableCell?.tableID == tableID {
                let cell = paragraph.tableCell!, anchor = table.anchor(row: cell.row, column: cell.column)
                paragraph.tableCell = anchor
                content[anchor.row * table.columnWidths.count + anchor.column, default: []].append(paragraph)
            }
            let ordered = table.cellAnchors.flatMap { cell -> [Paragraph] in
                if let paragraphs = content[cell.row * table.columnWidths.count + cell.column] { return paragraphs }
                var paragraph = Paragraph(); paragraph.tableCell = cell; return [paragraph]
            }
            sections[s].paragraphs.removeAll { $0.tableCell?.tableID == tableID }
            sections[s].paragraphs.insert(contentsOf: ordered, at: start)
        }
    }

    /// Shared axis transform keeps spans and their anchor content intact through grid edits.
    mutating func editTableGrid(tableID: UUID, rowAxis: Bool, position: Int, inserting: Bool) {
        guard let t = tables.firstIndex(where: { $0.id == tableID }) else { return }
        let old = tables[t], count = rowAxis ? old.rows : old.columnWidths.count
        guard position >= 0, position < count + (inserting ? 1 : 0) else { return }
        if !inserting && count == 1 { deleteTable(id: tableID); return }
        if inserting && (count >= (rowAxis ? 100 : 20) || (!rowAxis && old.columnWidths.reduce(0, +) / Double(count + 1) < 12)) { return }
        var merges: [TableMerge] = []
        for var merge in old.mergedCells ?? [] {
            var start = rowAxis ? merge.row : merge.column, span = rowAxis ? merge.rowSpan : merge.columnSpan
            if inserting {
                if position <= start { start += 1 }
                else if position < start + span { span += 1 }
            } else {
                if position < start { start -= 1 }
                else if position < start + span { span -= 1 }
            }
            guard span > 0 else { continue }
            if rowAxis { merge.row = start; merge.rowSpan = span } else { merge.column = start; merge.columnSpan = span }
            if merge.rowSpan > 1 || merge.columnSpan > 1 { merges.append(merge) }
        }
        for s in sections.indices {
            sections[s].paragraphs = sections[s].paragraphs.compactMap { value in
                guard var cell = value.tableCell, cell.tableID == tableID else { return value }
                let coordinate = rowAxis ? cell.row : cell.column
                var updated = coordinate
                if inserting { if coordinate >= position { updated += 1 } }
                else if coordinate == position {
                    let merge = old.merge(atRow: cell.row, column: cell.column)
                    guard let merge, (rowAxis ? merge.rowSpan : merge.columnSpan) > 1 else { return nil }
                    // The first surviving row/column takes over the merged anchor.
                } else if coordinate > position { updated -= 1 }
                if rowAxis { cell.row = updated } else { cell.column = updated }
                var paragraph = value; paragraph.tableCell = cell; return paragraph
            }
        }
        tables[t].mergedCells = merges.isEmpty ? nil : merges
        tables[t].cellStyles = old.cellStyles?.compactMap { value in
            var style = value
            let coordinate = rowAxis ? style.row : style.column
            var updated = coordinate
            if inserting { if coordinate >= position { updated += 1 } }
            else if coordinate == position { return nil }
            else if coordinate > position { updated -= 1 }
            if rowAxis { style.row = updated } else { style.column = updated }; return style
        }
        // Preserve the visual style when a deleted grid line contained a surviving anchor.
        if !inserting {
            for merge in old.mergedCells ?? [] where (rowAxis ? merge.row : merge.column) == position && (rowAxis ? merge.rowSpan : merge.columnSpan) > 1 {
                if let style = old.cellStyle(row: merge.row, column: merge.column) {
                    tables[t].cellStyles = (tables[t].cellStyles ?? []).filter { $0.row != style.row || $0.column != style.column } + [style]
                }
            }
        }
        if rowAxis {
            tables[t].rows += inserting ? 1 : -1
            if inserting { tables[t].minimumRowHeights?.insert(nil, at: position) }
            else { tables[t].minimumRowHeights?.remove(at: position) }
        } else {
            tables[t].columnWidths = Array(repeating: old.columnWidths.reduce(0, +) / Double(count + (inserting ? 1 : -1)), count: count + (inserting ? 1 : -1))
        }
        normalizeTableFlow(tableID: tableID); reconcileCommentAnchors()
    }
}
