import Foundation

extension ScribeDocument {
    /// Return within one list item. UTF-16 offsets match native text selection.
    /// Leaves other paragraphs and every run's formatting/asset metadata intact.
    @discardableResult public mutating func splitListItem(id: UUID, range: NSRange) -> UUID? {
        guard paragraphs.first(where: { $0.id == id })?.list != nil else { return nil }
        return splitParagraph(id: id, range: range, emptyListCommand: true)
    }
    @discardableResult mutating func splitParagraph(id: UUID, range: NSRange, emptyListCommand: Bool) -> UUID? {
        guard let section = sections.firstIndex(where: { $0.paragraphs.contains { $0.id == id } }),
              let index = sections[section].paragraphs.firstIndex(where: { $0.id == id }) else { return nil }
        let original = sections[section].paragraphs[index]
        let length = (original.text as NSString).length
        guard range.location >= 0, range.length >= 0, range.location <= length, range.length <= length - range.location else { return nil }
        // Foundation's NSRange→Range bridge accepts surrogate interiors on some macOS
        // strings. Check extended grapheme boundaries explicitly before slicing UTF-16.
        var boundaries: Set<Int> = [0], offset = 0
        for character in original.text { offset += String(character).utf16.count; boundaries.insert(offset) }
        guard boundaries.contains(range.location), boundaries.contains(NSMaxRange(range)) else { return nil }
        if length == 0, emptyListCommand, var list = original.list {
            if list.level > 0 { list.level -= 1; list.restart = nil; sections[section].paragraphs[index].list = list }
            else { sections[section].paragraphs[index].list = nil }
            return id
        }
        func slice(_ range: NSRange) -> [TextRun] {
            var offset = 0, result: [TextRun] = []
            for run in original.runs {
                let size = (run.text as NSString).length
                let overlap = NSIntersectionRange(range, NSRange(location: offset, length: size))
                if overlap.length > 0 {
                    var fragment = run
                    fragment.text = (run.text as NSString).substring(with: NSRange(location: overlap.location - offset, length: overlap.length))
                    result.append(fragment)
                }
                offset += size
            }
            return result.isEmpty ? [TextRun("", format: original.runs.last?.format ?? TextFormatting())] : result
        }
        let before = paragraphs
        let originalRange = DocumentTextIndex(paragraphs: before).range(for: TextAnchor(paragraphID: id, offset: range.location, length: range.length))!
        var next = original; next.id = UUID(); next.pageBreakBefore = false; next.list?.restart = nil; next.toc = nil
        next.formattingReview = next.formattingReview?.paragraphContinuation()
        next.runs = slice(NSRange(location: NSMaxRange(range), length: length - NSMaxRange(range)))
        sections[section].paragraphs[index].runs = slice(NSRange(location: 0, length: range.location))
        sections[section].paragraphs[index].breakReview = nil
        sections[section].paragraphs.insert(next, at: index + 1)
        transformCommentAnchors(from: before, replacing: originalRange, withLength: 1)
        return next.id
    }
}
