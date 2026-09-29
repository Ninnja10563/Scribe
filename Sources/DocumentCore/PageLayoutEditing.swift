import Foundation

extension ScribeDocument {
    /// Change geometry transactionally. Objects that exceed the new writing area
    /// shrink without modifying their underlying image data or table contents.
    public mutating func applyPageLayout(_ settings: PageSettings, sectionID: UUID) throws {
        guard settings.isValid, let section = sections.firstIndex(where: { $0.id == sectionID }) else {
            throw DocumentError.invalid("page dimensions and margins must leave at least 72 points of writing space")
        }
        var result = self
        let tableIDs = Set(sections[section].paragraphs.compactMap { $0.tableCell?.tableID })
        for i in result.tables.indices where tableIDs.contains(result.tables[i].id) {
            let widths = result.tables[i].columnWidths, minimum = Double(widths.count) * 12
            guard minimum <= settings.contentWidth else { throw DocumentError.invalid("this page is too narrow for the document's tables") }
            let total = widths.reduce(0, +)
            if total > settings.contentWidth {
                // Reserve the minimum for every column before distributing remaining
                // space. Pure proportional scaling can produce invalid narrow cells.
                let scale = (settings.contentWidth - minimum) / (total - minimum)
                result.tables[i].columnWidths = widths.map { 12 + ($0 - 12) * scale }
            }
        }
        result.sections[section].page = settings
        for p in result.sections[section].paragraphs.indices {
            for r in result.sections[section].paragraphs[p].runs.indices {
                guard var image = result.sections[section].paragraphs[p].runs[r].image else { continue }
                let scale = min(1, settings.contentWidth / image.width, (settings.contentHeight - 24) / image.height)
                image.width *= scale; image.height *= scale
                result.sections[section].paragraphs[p].runs[r].image = image
            }
        }
        try NativeFormat.validate(result)
        self = result
    }
}
