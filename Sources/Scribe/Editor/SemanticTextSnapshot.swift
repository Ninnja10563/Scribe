#if canImport(AppKit)
import AppKit
import DocumentCore

/// Search/statistics read document content, excluding generated list and page-break
/// prefixes. Segments map UTF-16 matches back to native selection coordinates.
struct SemanticTextSnapshot: Sendable {
    private struct Segment: Sendable {
        let source: NSRange
        let content: NSRange
    }
    let text: String
    let statisticsText: String
    private struct NoteText: Sendable { let id: UUID; let text: String; let reference: NSRange }
    private let notes: [NoteText]
    private let segments: [Segment]
    private let sourceLength: Int

    @MainActor init(_ storage: NSAttributedString) {
        sourceLength = storage.length
        var result = "", spans: [Segment] = [], sourceOffset = 0, contentOffset = 0
        let components = storage.string.components(separatedBy: "\n")
        for (index, component) in components.enumerated() {
            let value = component as NSString
            var prefix = component.hasPrefix("\u{c}") ? 1 : 0
            if sourceOffset < storage.length {
                var labelRange = NSRange()
                if storage.attribute(.scribeNoteLabelID, at: sourceOffset, effectiveRange: &labelRange) != nil {
                    prefix = min(value.length, NSMaxRange(labelRange) - sourceOffset)
                }
            }
            if sourceOffset < storage.length,
               storage.attribute(.scribeList, at: sourceOffset, effectiveRange: nil) != nil {
                let remaining = value.substring(from: prefix) as NSString
                if remaining.hasPrefix("\t"), remaining.length > 1 {
                    let end = remaining.range(of: "\t", range: NSRange(location: 1, length: remaining.length - 1))
                    if end.location != NSNotFound { prefix += end.location + 1 }
                }
            }
            let content = value.substring(from: prefix) + (index + 1 < components.count ? "\n" : "")
            let length = (content as NSString).length
            if length > 0 {
                spans.append(Segment(source: NSRange(location: sourceOffset + prefix, length: length),
                                     content: NSRange(location: contentOffset, length: length)))
                result += content; contentOffset += length
            }
            sourceOffset += value.length + 1
        }
        var noteText: [NoteText] = [], seen = Set<UUID>()
        storage.enumerateAttribute(.scribeNote, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let data = value as? Data, data.count <= NativeFormat.maximumBytes,
                  let note = try? JSONDecoder().decode(DocumentNote.self, from: data), seen.insert(note.id).inserted else { return }
            noteText.append(NoteText(id: note.id, text: note.paragraphs.map(\.text).joined(separator: "\n"), reference: range))
        }
        notes = noteText
        statisticsText = ([result] + noteText.map(\.text)).joined(separator: "\n")
        text = result; segments = spans
    }

    func matches(query: String, options: SearchOptions = SearchOptions()) -> [NSRange] {
        DocumentSearch.matches(in: text, query: query, options: options).compactMap { sourceRange($0) }
    }
    func sourceRange(forContentRange range: NSRange) -> NSRange? {
        if range.length == 0 {
            guard range.location >= 0, range.location <= text.utf16.count else { return nil }
            if range.location == text.utf16.count { return NSRange(location: sourceLength, length: 0) }
            guard let span = segment(containing: range.location) else { return nil }
            return NSRange(location: span.source.location + range.location - span.content.location, length: 0)
        }
        return sourceRange(range)
    }
    private func sourceRange(_ range: NSRange) -> NSRange? {
        guard range.length > 0, let first = segment(containing: range.location),
              let last = segment(containing: NSMaxRange(range) - 1) else { return nil }
        let start = first.source.location + range.location - first.content.location
        let end = last.source.location + NSMaxRange(range) - last.content.location
        return NSRange(location: start, length: end - start)
    }
    func documentMatches(query: String, options: SearchOptions = SearchOptions()) -> [DocumentSearchMatch] {
        var result = matches(query: query, options: options).map(DocumentSearchMatch.body)
        for note in notes {
            result += DocumentSearch.matches(in: note.text, query: query, options: options).map { .note(id: note.id, range: $0, reference: note.reference) }
        }
        return result.sorted { left, right in
            if left.sourceLocation != right.sourceLocation { return left.sourceLocation < right.sourceLocation }
            return (left.noteRange?.location ?? -1) < (right.noteRange?.location ?? -1)
        }
    }

    /// Authored ranges exclude generated numbering and running note labels.
    func contentSourceRanges(in range: NSRange) -> [NSRange] {
        segments.map { NSIntersectionRange($0.source, range) }.filter { $0.length > 0 }
    }

    func text(inSourceRange range: NSRange) -> String {
        let value = text as NSString
        return segments.compactMap { segment -> String? in
            let overlap = NSIntersectionRange(segment.source, range)
            guard overlap.length > 0 else { return nil }
            return value.substring(with: NSRange(location: segment.content.location + overlap.location - segment.source.location,
                                                  length: overlap.length))
        }.joined()
    }

    private func segment(containing offset: Int) -> Segment? {
        var lower = 0, upper = segments.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if NSMaxRange(segments[middle].content) <= offset { lower = middle + 1 }
            else { upper = middle }
        }
        guard lower < segments.count, offset >= segments[lower].content.location else { return nil }
        return segments[lower]
    }
}
#endif
