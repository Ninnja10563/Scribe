#if canImport(AppKit)
import AppKit
import DocumentCore

/// Replace only changed ordinary paragraphs in an existing native projection.
/// Context-dependent rendering keeps the full projection path until it can
/// supply an equivalent local range (lists, tables, notes and comment spans).
@MainActor enum DocumentProjectionUpdate {
    static func apply(from before: ScribeDocument, to after: ScribeDocument, storage: NSTextStorage) -> Int? {
        guard before.sections.count == 1, after.sections.count == 1,
              before.styles == after.styles, before.comments.isEmpty, after.comments.isEmpty,
              before.notes.isEmpty, after.notes.isEmpty, before.tables.isEmpty, after.tables.isEmpty,
              before.tablesOfContents.isEmpty, after.tablesOfContents.isEmpty else { return nil }
        var oldSection = before.sections[0], newSection = after.sections[0]
        let old = oldSection.paragraphs, new = newSection.paragraphs
        oldSection.paragraphs = []; newSection.paragraphs = []
        guard oldSection == newSection else { return nil }
        var start = 0
        while start < min(old.count, new.count), old[start] == new[start] { start += 1 }
        var oldEnd = old.count, newEnd = new.count
        while oldEnd > start, newEnd > start, old[oldEnd - 1] == new[newEnd - 1] { oldEnd -= 1; newEnd -= 1 }
        if start == oldEnd, start == newEnd { return 0 }
        let changedOld = Array(old[start..<oldEnd]), changedNew = Array(new[start..<newEnd])
        guard !changedNew.isEmpty,
              (changedOld + changedNew).allSatisfy({ $0.list == nil && $0.tableCell == nil && $0.toc == nil }) else { return nil }
        let text = storage.string as NSString
        var boundaries = [0], offset = 0
        while offset < text.length {
            let newline = text.range(of: "\n", range: NSRange(location: offset, length: text.length - offset))
            if newline.location == NSNotFound { break }
            offset = NSMaxRange(newline); boundaries.append(offset)
        }
        boundaries.append(text.length)
        guard boundaries.count == old.count + 1 else { return nil }
        let range = NSRange(location: boundaries[start], length: boundaries[oldEnd] - boundaries[start])
        let expected = changedOld.map { ($0.pageBreakBefore ? "\u{c}" : "") + $0.text }.joined(separator: "\n") + (oldEnd < old.count ? "\n" : "")
        guard text.substring(with: range) == expected else { return nil }
        var fragment = after
        fragment.sections[0].paragraphs = changedNew
        // Rendering a trailing empty sentinel includes the last real separator
        // with its actual style/identity/revision attributes, not guessed ones.
        if newEnd < new.count { fragment.sections[0].paragraphs.append(Paragraph()) }
        let replacement = AttributedDocument.render(fragment)
        storage.replaceCharacters(in: range, with: replacement)
        return range.length
    }
}
#endif
