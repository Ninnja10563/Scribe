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
    private let segments: [Segment]

    @MainActor init(_ storage: NSAttributedString) {
        var result = "", spans: [Segment] = [], sourceOffset = 0, contentOffset = 0
        let components = storage.string.components(separatedBy: "\n")
        for (index, component) in components.enumerated() {
            let value = component as NSString
            var prefix = component.hasPrefix("\u{c}") ? 1 : 0
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
        var noteText: [String] = [], seen = Set<UUID>()
        storage.enumerateAttribute(.scribeNote, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let data = value as? Data, data.count <= NativeFormat.maximumBytes,
                  let note = try? JSONDecoder().decode(DocumentNote.self, from: data), seen.insert(note.id).inserted else { return }
            noteText.append(note.paragraphs.map(\.text).joined(separator: "\n"))
        }
        statisticsText = ([result] + noteText).joined(separator: "\n")
        text = result; segments = spans
    }

    func matches(query: String, options: SearchOptions = SearchOptions()) -> [NSRange] {
        DocumentSearch.matches(in: text, query: query, options: options).compactMap { range in
            guard let first = segment(containing: range.location),
                  let last = segment(containing: NSMaxRange(range) - 1) else { return nil }
            let start = first.source.location + range.location - first.content.location
            let end = last.source.location + NSMaxRange(range) - last.content.location
            return NSRange(location: start, length: end - start)
        }
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
