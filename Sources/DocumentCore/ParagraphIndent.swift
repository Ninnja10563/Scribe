import Foundation

public enum ParagraphIndent: String, CaseIterable, Sendable {
    case firstLine, left, right
    public var label: String {
        switch self { case .firstLine: return "First line indent"; case .left: return "Left indent"; case .right: return "Right indent" }
    }
    public func value(in format: ParagraphFormatting) -> Double {
        switch self { case .firstLine: return format.firstLineIndent; case .left: return format.headIndent; case .right: return format.tailIndent }
    }
    public func maximum(in format: ParagraphFormatting, width: Double) -> Double {
        max(0, min(4000, width - 30 - (self == .right ? max(format.firstLineIndent, format.headIndent) : format.tailIndent)))
    }
    func apply(_ value: Double, to format: inout ParagraphFormatting) {
        switch self { case .firstLine: format.firstLineIndent = value; case .left: format.headIndent = value; case .right: format.tailIndent = value }
    }
}

public extension ScribeDocument {
    /// Changes only one indent, retaining each paragraph's other geometry and text.
    /// Validate the whole selection before mutating any paragraph.
    mutating func setParagraphIndent(_ indent: ParagraphIndent, to value: Double, paragraphIDs: Set<UUID>) throws {
        guard value.isFinite, value >= 0, !paragraphIDs.isEmpty else { throw DocumentError.invalid("choose a non-negative paragraph indent") }
        var changes: [(Int, Int, ParagraphFormatting)] = []
        for s in sections.indices {
            for p in sections[s].paragraphs.indices where paragraphIDs.contains(sections[s].paragraphs[p].id) {
                let paragraph = sections[s].paragraphs[p]
                guard paragraph.list == nil, paragraph.tableCell == nil, paragraph.toc == nil else {
                    throw DocumentError.invalid("use list or table controls for this paragraph")
                }
                var format = paragraph.formatting ?? style(for: paragraph).paragraph
                guard value <= indent.maximum(in: format, width: sections[s].page.contentWidth) else {
                    throw DocumentError.invalid("the indent must leave at least 30 points of writing width")
                }
                indent.apply(value, to: &format)
                guard max(format.firstLineIndent, format.headIndent) + format.tailIndent <= sections[s].page.contentWidth - 30 else {
                    throw DocumentError.invalid("the paragraph must leave at least 30 points of writing width")
                }
                if indent.value(in: paragraph.formatting ?? style(for: paragraph).paragraph) != value { changes.append((s, p, format)) }
            }
        }
        guard sections.flatMap(\.paragraphs).filter({ paragraphIDs.contains($0.id) }).count == paragraphIDs.count else { throw DocumentError.invalid("the selected paragraph no longer exists") }
        for (s, p, format) in changes { sections[s].paragraphs[p].formatting = format }
    }
}
