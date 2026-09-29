#if canImport(AppKit)
import AppKit

extension ScribeTextView {
    /// Generated numbering belongs to paragraph layout. A native selection can
    /// include it, but inline editing starts at the semantic list-item content.
    func editableListRange(_ range: NSRange) -> NSRange {
        guard let storage = textStorage, range.location >= 0, range.length >= 0,
              range.location <= storage.length, range.length <= storage.length - range.location,
              storage.length > 0,
              storage.attribute(.scribeList, at: min(range.location, storage.length - 1), effectiveRange: nil) != nil else { return range }
        let text = storage.string as NSString
        let preceding = text.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: range.location))
        var start = preceding.location == NSNotFound ? 0 : NSMaxRange(preceding)
        if start < text.length, text.character(at: start) == 12 { start += 1 }
        guard start < text.length, text.character(at: start) == 9 else { return range }
        let tab = text.range(of: "\t", range: NSRange(location: start + 1, length: text.length - start - 1))
        guard tab.location != NSNotFound,
              text.range(of: "\n", range: NSRange(location: start, length: tab.location - start)).location == NSNotFound else { return range }
        let contentStart = NSMaxRange(tab)
        guard range.location < contentStart else { return range }
        let newline = text.range(of: "\n", range: NSRange(location: contentStart, length: text.length - contentStart))
        let paragraphEnd = newline.location == NSNotFound ? text.length : newline.location
        guard NSMaxRange(range) <= paragraphEnd else { return range }
        let end = max(contentStart, NSMaxRange(range))
        return NSRange(location: contentStart, length: end - contentStart)
    }
    func listContentReplacement(_ value: NSAttributedString, range: NSRange, formatting: Bool) -> (NSRange, NSAttributedString) {
        let adjusted = editableListRange(range)
        guard formatting, adjusted != range, let storage = textStorage,
              storage.attributedSubstring(from: range).string == value.string else { return (adjusted, value) }
        // A formatting command supplied the original text with new attributes.
        // Strip its generated prefix as well, so it cannot become authored text.
        let removed = min(value.length, adjusted.location - range.location)
        return (adjusted, value.attributedSubstring(from: NSRange(location: removed, length: value.length - removed)))
    }
}
#endif
