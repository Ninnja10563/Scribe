#if canImport(AppKit)
import AppKit

extension ScribeTextView {
    /// Generated numbering belongs to paragraph layout. A native selection can
    /// include it, but inline editing starts at the semantic list-item content.
    func editableListRange(_ range: NSRange) -> NSRange {
        guard let storage = textStorage, range.location >= 0, range.length >= 0,
              range.location <= storage.length, range.length <= storage.length - range.location,
              let context = listContext(for: range), context.start < storage.length,
              storage.attribute(.scribeList, at: context.start, effectiveRange: nil) != nil,
              NSMaxRange(range) <= context.end, range.location < context.contentStart else { return range }
        let end = max(context.contentStart, NSMaxRange(range))
        return NSRange(location: context.contentStart, length: end - context.contentStart)
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
