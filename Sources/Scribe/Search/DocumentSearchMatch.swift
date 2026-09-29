#if canImport(AppKit)
import Foundation

/// Body locations stay in native UTF-16 coordinates. Note ranges address the
/// note's semantic paragraphs, independent of its current page fragments.
enum DocumentSearchMatch: Equatable, Sendable {
    case body(NSRange)
    case note(id: UUID, range: NSRange, reference: NSRange)
    var sourceLocation: Int {
        switch self { case .body(let range): return range.location; case .note(_, _, let reference): return reference.location }
    }
    var noteRange: NSRange? {
        if case .note(_, let range, _) = self { return range }; return nil
    }
}
#endif
