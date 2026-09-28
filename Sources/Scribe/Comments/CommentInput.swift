#if canImport(AppKit)
import AppKit

extension ScribeTextView {
    /// At range edges, typing belongs outside the comment. Within a range, both
    /// neighboring characters carry its ID and newly typed text joins the range.
    func commentIDs(forReplacement range: NSRange) -> [String] {
        guard let storage = textStorage, range.location >= 0, range.location <= storage.length,
              range.length >= 0, range.length <= storage.length - range.location else { return [] }
        func ids(_ position: Int) -> Set<String> {
            guard position >= 0, position < storage.length else { return [] }
            return Set(storage.attribute(.scribeComments, at: position, effectiveRange: nil) as? [String] ?? [])
        }
        if range.length > 0 { return ids(range.location).intersection(ids(NSMaxRange(range) - 1)).sorted() }
        return ids(range.location - 1).intersection(ids(range.location)).sorted()
    }
}
#endif
