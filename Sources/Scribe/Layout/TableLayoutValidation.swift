#if canImport(AppKit)
import AppKit
import DocumentCore

/// TextKit can omit over-tall table glyphs without reporting an oversized line.
/// Measure each cell's intrinsic text separately before trusting paginated output.
@MainActor final class TableLayoutValidation {
    private struct Measurement {
        let text: NSAttributedString
        let width: Double
        let height: Double
    }
    private var cache: [String: Measurement] = [:]
    func hasOversizedCell(storage: NSAttributedString, document: ScribeDocument, pageHeight: Double) -> Bool {
        guard !document.tables.isEmpty, storage.length > 0 else { cache.removeAll(); return false }
        let tables = Dictionary(uniqueKeysWithValues: document.tables.map { ($0.id, $0) })
        var present = Set<String>(), oversized = false
        var cells: [String: (TableCellReference, NSMutableAttributedString)] = [:]
        storage.enumerateAttribute(.scribeCell, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let data = value as? Data, let cell = try? JSONDecoder().decode(TableCellReference.self, from: data) else { return }
            // Equivalent JSON dictionaries can have different byte ordering, so
            // attribute runs are not reliable cell boundaries. Group decoded IDs.
            let key = "\(cell.tableID)-\(cell.row)-\(cell.column)"
            if let existing = cells[key] { existing.1.append(storage.attributedSubstring(from: range)) }
            else { cells[key] = (cell, NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))) }
        }
        for (key, (cell, source)) in cells {
            guard let table = tables[cell.tableID], table.columnWidths.indices.contains(cell.column) else { continue }
            let columns = table.merge(atRow: cell.row, column: cell.column)?.columnSpan ?? 1
            let style = table.cellStyle(row: cell.row, column: cell.column)
            let inset = 2 * ((style?.padding ?? table.padding) + (style?.borderWidth ?? table.borderWidth))
            let width = max(1, table.columnWidths[cell.column..<(cell.column + columns)].reduce(0, +) - inset)
            present.insert(key)
            let height: Double
            if let measurement = self.cache[key], measurement.width == width, measurement.text.isEqual(to: source) { height = measurement.height }
            else {
                let text = NSMutableAttributedString(attributedString: source)
                text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                    guard let value = value as? NSParagraphStyle else { return }
                    let paragraph = value.mutableCopy() as! NSMutableParagraphStyle
                    paragraph.textBlocks = []; text.addAttribute(.paragraphStyle, value: paragraph, range: range)
                }
                if text.string.hasSuffix("\n") { text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1)) }
                let contents = NSTextStorage(attributedString: text), layout = NSLayoutManager()
                let container = NSTextContainer(containerSize: NSSize(width: width, height: 1_000_000))
                container.lineFragmentPadding = 0; contents.addLayoutManager(layout); layout.addTextContainer(container)
                layout.ensureLayout(for: container)
                height = layout.usedRect(for: container).height
                self.cache[key] = Measurement(text: source, width: width, height: height)
            }
            if height + inset > pageHeight + 1 { oversized = true }
        }
        cache = cache.filter { present.contains($0.key) }
        return oversized
    }
}
#endif
