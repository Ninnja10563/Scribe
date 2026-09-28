#if canImport(AppKit)
import AppKit
import DocumentCore

extension NSAttributedString.Key {
    static let scribeComments = NSAttributedString.Key("org.scribe.comments")
}

/// Semantic anchors are projected as inert text attributes, so native undo restores their
/// association along with the text. Review decoration never becomes document formatting.
@MainActor enum CommentProjection {
    private struct Span {
        let id: UUID
        let paragraphStart: Int
        let content: NSRange
        let semanticStart: Int
        let includesNewline: Bool
    }
    private static func spans(_ storage: NSAttributedString, document: ScribeDocument) -> [Span] {
        let components = storage.string.components(separatedBy: "\n"), paragraphs = document.paragraphs
        var result: [Span] = [], position = 0, semantic = 0
        for (i, component) in components.enumerated() where paragraphs.indices.contains(i) {
            let p = paragraphs[i], length = (component as NSString).length
            var prefix = component.hasPrefix("\u{c}") ? 1 : 0
            let rest = String(component.dropFirst(prefix))
            if p.list != nil, rest.hasPrefix("\t"), let end = rest.dropFirst().firstIndex(of: "\t") {
                prefix += (String(rest[...end]) as NSString).length
            }
            result.append(Span(id: p.id, paragraphStart: position, content: NSRange(location: position + prefix, length: max(0, length - prefix)), semanticStart: semantic, includesNewline: i + 1 < components.count))
            position += length + 1; semantic += (p.text as NSString).length + 1
        }
        return result
    }
    static func range(for anchor: TextAnchor, in storage: NSAttributedString, document: ScribeDocument) -> NSRange? {
        let positions = Dictionary(uniqueKeysWithValues: spans(storage, document: document).map { ($0.id, $0) })
        return projectedRange(anchor, length: storage.length, index: DocumentTextIndex(paragraphs: document.paragraphs), spans: positions)
    }
    private static func projectedRange(_ anchor: TextAnchor, length: Int, index: DocumentTextIndex, spans: [UUID: Span]) -> NSRange? {
        guard index.range(for: anchor) != nil, let first = spans[anchor.paragraphID],
              let last = spans[anchor.endParagraphID ?? anchor.paragraphID] else { return nil }
        let start = first.content.location + anchor.offset
        let end = last.content.location + (anchor.endOffset ?? (anchor.offset + anchor.length))
        guard start >= 0, end >= start, end <= length else { return nil }
        return NSRange(location: start, length: end - start)
    }
    static func anchor(for range: NSRange, in storage: NSAttributedString, document: ScribeDocument) -> TextAnchor? {
        guard range.location >= 0, range.length >= 0, range.location <= storage.length, range.length <= storage.length - range.location else { return nil }
        let spans = spans(storage, document: document)
        func offset(_ position: Int) -> Int? {
            // Prefix markers belong to the following paragraph, even before its first text character.
            guard let span = spans.last(where: { $0.paragraphStart <= position }) ?? spans.first else { return nil }
            return span.semanticStart + min(span.content.length, max(0, position - span.content.location))
        }
        guard let start = offset(range.location), let end = offset(NSMaxRange(range)) else { return nil }
        return DocumentTextIndex(paragraphs: document.paragraphs).anchor(for: NSRange(location: start, length: max(0, end - start)))
    }
    static func apply(to storage: NSMutableAttributedString, document: ScribeDocument) {
        guard !document.comments.isEmpty else { return }
        let positions = Dictionary(uniqueKeysWithValues: spans(storage, document: document).map { ($0.id, $0) })
        let index = DocumentTextIndex(paragraphs: document.paragraphs)
        for comment in document.comments where comment.isDetached != true {
            guard let range = projectedRange(comment.anchor, length: storage.length, index: index, spans: positions), range.length > 0 else { continue }
            var segments: [(NSRange, [String])] = []
            storage.enumerateAttribute(.scribeComments, in: range) { value, subrange, _ in
                var ids = value as? [String] ?? []; ids.append(comment.id.uuidString); segments.append((subrange, ids))
            }
            for (range, ids) in segments { storage.addAttribute(.scribeComments, value: ids, range: range) }
        }
    }
    static func capture(from storage: NSAttributedString, document: inout ScribeDocument) {
        guard !document.comments.isEmpty else { return }
        let index = DocumentTextIndex(paragraphs: document.paragraphs)
        let known = Set(document.comments.map { $0.id.uuidString })
        var ranges: [String: NSRange] = [:]
        for span in spans(storage, document: document) {
            let content = NSRange(location: span.content.location, length: span.content.length + (span.includesNewline ? 1 : 0))
            guard content.length > 0, NSMaxRange(content) <= storage.length else { continue }
            storage.enumerateAttribute(.scribeComments, in: content) { value, range, _ in
                for id in (value as? [String] ?? []) where known.contains(id) {
                    let semantic = NSRange(location: span.semanticStart + range.location - content.location, length: range.length)
                    ranges[id] = ranges[id].map { NSUnionRange($0, semantic) } ?? semantic
                }
            }
        }
        for i in document.comments.indices {
            if let range = ranges[document.comments[i].id.uuidString], let anchor = index.anchor(for: range) {
                document.comments[i].anchor = anchor; document.comments[i].isDetached = nil
            } else { document.comments[i].isDetached = true }
        }
    }
}
#endif
