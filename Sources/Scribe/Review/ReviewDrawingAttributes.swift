#if canImport(AppKit)
import AppKit
import DocumentCore

/// Decorations are computed only for the range being drawn. They never enter
/// NSTextStorage, native files, clipboard data or printed character formatting.
@MainActor final class ReviewDrawingAttributes {
    private struct Key: Hashable { let data: Data; let paragraph: Bool }
    private struct Marks { var insertion = false; var deletion = false; var formatting = false }
    private var cache: [Key: Marks] = [:]
    private var cachedBytes = 0
    private func marks(_ data: Data, paragraph: Bool) -> Marks {
        let key = Key(data: data, paragraph: paragraph)
        if let value = cache[key] { return value }
        var value = Marks()
        if data.count <= NativeFormat.maximumBytes {
            if paragraph, let history = try? JSONDecoder().decode(ParagraphFormattingReview.self, from: data) {
                value.formatting = !history.pendingIDs.isEmpty
            } else if !paragraph, let history = try? JSONDecoder().decode(RunReview.self, from: data) {
                value.insertion = history.insertion != nil; value.deletion = history.deletion != nil
                value.formatting = history.formatting.contains { !$0.accepted }
            }
        }
        if cache.count >= 256 || cachedBytes + data.count > 1_048_576 {
            cache.removeAll(keepingCapacity: true); cachedBytes = 0
        }
        if data.count <= 1_048_576 { cache[key] = value; cachedBytes += data.count }
        return value
    }
    func attributes(_ original: [NSAttributedString.Key: Any], storage: NSAttributedString?,
                    at index: Int, effectiveRange: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        guard let storage, index >= 0, index < storage.length else { return original }
        var extent = NSRange(location: 0, length: storage.length)
        func attribute(_ key: NSAttributedString.Key) -> Any? {
            var range = NSRange()
            let value = storage.attribute(key, at: index, effectiveRange: &range)
            extent = NSIntersectionRange(extent, range); return value
        }
        let label = attribute(.scribeNoteLabelID)
        var combined = Marks()
        for key in [NSAttributedString.Key.scribeReview, .scribeBreakReview, .scribeParagraphReview] {
            guard let data = attribute(key) as? Data else { continue }
            let value = marks(data, paragraph: key == .scribeParagraphReview)
            combined.insertion = combined.insertion || value.insertion
            combined.deletion = combined.deletion || value.deletion
            combined.formatting = combined.formatting || value.formatting
        }
        if let effectiveRange {
            effectiveRange.pointee = NSIntersectionRange(effectiveRange.pointee, extent)
        }
        guard label == nil, combined.insertion || combined.deletion || combined.formatting else { return original }
        var result = original
        let green = NSColor(srgbRed: 0.08, green: 0.40, blue: 0.23, alpha: 1)
        let red = NSColor(srgbRed: 0.68, green: 0.16, blue: 0.16, alpha: 1)
        let blue = NSColor(srgbRed: 0.16, green: 0.32, blue: 0.64, alpha: 1)
        if combined.insertion {
            result[.foregroundColor] = green; result[.underlineColor] = green
            result[.underlineStyle] = NSUnderlineStyle.single.rawValue
        } else if combined.formatting {
            result[.underlineColor] = blue
            result[.underlineStyle] = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue
        }
        if combined.deletion {
            result[.foregroundColor] = red; result[.strikethroughColor] = red
            result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return result
    }
}
#endif
