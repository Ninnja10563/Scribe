import Foundation

extension ScribeDocument {
    /// Named paragraph locations keep their identity through edits and renaming. A
    /// removed paragraph leaves a visible missing target; undo can restore it.
    public func destinationParagraphID(for link: String) -> UUID? {
        DocumentLinkResolver(self).paragraphID(for: link)
    }
    public func canNameBookmark(_ name: String, excluding id: UUID? = nil) -> Bool {
        guard name.range(of: "^[A-Za-z][A-Za-z0-9_]{0,39}$", options: .regularExpression) != nil,
              !name.lowercased().hasPrefix("scribe_") else { return false }
        return !bookmarks.contains { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
    @discardableResult public mutating func addParagraphBookmark(name: String, paragraphID: UUID) -> UUID? {
        guard canNameBookmark(name), paragraphs.contains(where: { $0.id == paragraphID }) else { return nil }
        let bookmark = Bookmark(name: name, anchor: TextAnchor(paragraphID: paragraphID, offset: 0, length: 0))
        bookmarks.append(bookmark); return bookmark.id
    }
    @discardableResult public mutating func renameBookmark(id: UUID, name: String) -> Bool {
        guard canNameBookmark(name, excluding: id), let index = bookmarks.firstIndex(where: { $0.id == id }) else { return false }
        bookmarks[index].name = name; return true
    }
}

/// Reuse one resolver for batches (PDF exports, link audits) to avoid scanning all
/// paragraphs for every link in a long document or table of contents.
public struct DocumentLinkResolver {
    private let paragraphIDs: Set<UUID>
    private let bookmarkParagraphs: [UUID: UUID]
    public init(_ document: ScribeDocument) {
        paragraphIDs = Set(document.paragraphs.map(\.id))
        bookmarkParagraphs = Dictionary(document.bookmarks.map { ($0.id, $0.anchor.paragraphID) }, uniquingKeysWith: { first, _ in first })
    }
    public func paragraphID(for link: String) -> UUID? {
        let id: UUID?
        if let paragraph = DocumentLink.paragraphID(link) { id = paragraph }
        else if let bookmark = DocumentLink.bookmarkID(link) { id = bookmarkParagraphs[bookmark] }
        else { return nil }
        return id.flatMap { paragraphIDs.contains($0) ? $0 : nil }
    }
}
