import Foundation

/// UTF-16 positions in semantic paragraph flow, independent of generated list markers or page breaks.
public struct DocumentTextIndex {
    public struct Entry {
        public let id: UUID
        public let start: Int
        public let length: Int
    }
    public let entries: [Entry]
    public let length: Int
    private let positions: [UUID: Int]
    private let strings: [String]
    public init(paragraphs: [Paragraph]) {
        var offset = 0, values: [Entry] = [], positions: [UUID: Int] = [:], strings: [String] = []
        for paragraph in paragraphs {
            let text = paragraph.text, length = (paragraph.text as NSString).length; strings.append(text)
            positions[paragraph.id] = values.count
            values.append(Entry(id: paragraph.id, start: offset, length: length))
            offset += length + 1
        }
        entries = values; length = max(0, offset - 1); self.positions = positions; self.strings = strings
    }
    public func range(for anchor: TextAnchor) -> NSRange? {
        guard let position = positions[anchor.paragraphID] else { return nil }
        let first = entries[position]
        guard (0...first.length).contains(anchor.offset), anchor.length >= 0 else { return nil }
        guard isScalarBoundary(anchor.offset, paragraph: position) else { return nil }
        let start = first.start + anchor.offset, end: Int
        if let id = anchor.endParagraphID, let offset = anchor.endOffset, let index = positions[id] {
            let last = entries[index]
            guard (0...last.length).contains(offset), isScalarBoundary(offset, paragraph: index) else { return nil }
            end = last.start + offset
        } else {
            guard anchor.endParagraphID == nil, anchor.endOffset == nil, anchor.length <= first.length - anchor.offset else { return nil }
            guard isScalarBoundary(anchor.offset + anchor.length, paragraph: position) else { return nil }
            end = start + anchor.length
        }
        guard end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }
    public func anchor(for range: NSRange) -> TextAnchor? {
        guard range.location >= 0, range.length >= 0, range.location <= length, range.length <= length - range.location,
              let first = entry(at: range.location), let last = entry(at: NSMaxRange(range)) else { return nil }
        var anchor = TextAnchor(paragraphID: first.id, offset: range.location - first.start, length: range.length)
        if first.id != last.id { anchor.endParagraphID = last.id; anchor.endOffset = NSMaxRange(range) - last.start }
        return self.range(for: anchor) == nil ? nil : anchor
    }
    private func isScalarBoundary(_ offset: Int, paragraph: Int) -> Bool {
        let text = strings[paragraph] as NSString
        guard offset > 0, offset < text.length else { return true }
        return !((0xD800...0xDBFF).contains(text.character(at: offset - 1)) && (0xDC00...0xDFFF).contains(text.character(at: offset)))
    }
    private func entry(at offset: Int) -> Entry? {
        // Binary search keeps navigation independent of document length.
        var low = 0, high = entries.count
        while low < high {
            let middle = (low + high) / 2
            if entries[middle].start <= offset { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        let entry = entries[low - 1]
        return offset <= entry.start + entry.length ? entry : nil
    }
}

extension ScribeDocument {
    /// A missing range is visible as a detached comment instead of silently deleting review text.
    public mutating func reconcileCommentAnchors() {
        let index = DocumentTextIndex(paragraphs: paragraphs)
        for i in comments.indices {
            if let range = index.range(for: comments[i].anchor) { comments[i].anchor.length = range.length }
            else { comments[i].isDetached = true }
        }
    }
    /// For semantic commands that replace text without passing through attributed-text editing.
    public mutating func transformCommentAnchors(from original: [Paragraph], replacing edit: NSRange, withLength inserted: Int) {
        let before = DocumentTextIndex(paragraphs: original), after = DocumentTextIndex(paragraphs: paragraphs)
        guard edit.location >= 0, edit.length >= 0, edit.location <= before.length, edit.length <= before.length - edit.location, inserted >= 0, inserted == after.length - (before.length - edit.length) else { return }
        func position(_ value: Int, trailing: Bool) -> Int {
            if value < edit.location { return value }
            if value > NSMaxRange(edit) { return value + inserted - edit.length }
            if value == NSMaxRange(edit), edit.length > 0 { return edit.location + inserted }
            return edit.location + (trailing ? inserted : 0)
        }
        for i in comments.indices where comments[i].isDetached != true {
            guard let range = before.range(for: comments[i].anchor) else { comments[i].isDetached = true; continue }
            if range.length > 0, edit.length > 0, edit.location <= range.location, NSMaxRange(edit) >= NSMaxRange(range) {
                comments[i].isDetached = true; continue
            }
            let start = position(range.location, trailing: true), end = position(NSMaxRange(range), trailing: false)
            guard let anchor = after.anchor(for: NSRange(location: start, length: max(0, end - start))) else { comments[i].isDetached = true; continue }
            comments[i].anchor = anchor
        }
    }
}
