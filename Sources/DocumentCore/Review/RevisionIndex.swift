import Foundation

/// A semantic location in the retained review projection. Offsets are UTF-16
/// within the paragraph, excluding generated list markers and page furniture.
public struct RevisionLocation: Equatable, Sendable {
    public enum Kind: String, Sendable { case insertion, deletion, characterFormatting, paragraphFormatting }
    public var paragraphID: UUID
    public var noteID: UUID?
    public var range: NSRange
    public var kind: Kind
    public var isParagraphSeparator: Bool
}

public struct IndexedRevision: Identifiable, Equatable, Sendable {
    /// The stable compound-edit ID, or the component ID for an ungrouped edit.
    public var id: UUID
    public var author: RevisionAuthor
    public var date: Date
    public var componentIDs: [UUID]
    public var locations: [RevisionLocation]
}

/// Rebuild after semantic edits or review decisions. Traversal follows body
/// order, then note registry order; it does not depend on pagination or dates.
/// Accepted history records are deliberately absent from this navigation index.
public struct RevisionIndex: Sendable {
    public private(set) var changes: [IndexedRevision] = []

    public init(document: ScribeDocument) {
        var indices: [UUID: Int] = [:]
        var components: [UUID: Set<UUID>] = [:]
        func record(_ identity: RevisionIdentity, location: RevisionLocation) {
            let key = identity.groupID ?? identity.id
            let index: Int
            if let existing = indices[key] { index = existing }
            else {
                index = changes.count; indices[key] = index
                changes.append(IndexedRevision(id: key, author: identity.author, date: identity.date,
                                               componentIDs: [], locations: []))
            }
            if components[key, default: []].insert(identity.id).inserted {
                changes[index].componentIDs.append(identity.id)
            }
            // Rich runs can split a single change thousands of times. Combine
            // touching text extents, but keep paragraph marks separately.
            if let last = changes[index].locations.last,
               last.paragraphID == location.paragraphID, last.noteID == location.noteID,
               last.kind == location.kind, !last.isParagraphSeparator, !location.isParagraphSeparator,
               NSMaxRange(last.range) == location.range.location {
                changes[index].locations[changes[index].locations.count - 1].range.length += location.range.length
            } else { changes[index].locations.append(location) }
        }
        func flow(_ paragraphs: [Paragraph], noteID: UUID?) {
            for paragraph in paragraphs {
                let length = paragraph.runs.reduce(0) { $0 + $1.text.utf16.count }
                func location(_ range: NSRange, _ kind: RevisionLocation.Kind, separator: Bool = false) -> RevisionLocation {
                    RevisionLocation(paragraphID: paragraph.id, noteID: noteID, range: range,
                                     kind: kind, isParagraphSeparator: separator)
                }
                for change in paragraph.formattingReview?.changes ?? [] where !change.accepted {
                    record(change.identity, location: location(NSRange(location: 0, length: length), .paragraphFormatting))
                }
                func review(_ value: RunReview?, range: NSRange, separator: Bool = false) {
                    guard let value else { return }
                    if let identity = value.insertion { record(identity, location: location(range, .insertion, separator: separator)) }
                    if let identity = value.deletion { record(identity, location: location(range, .deletion, separator: separator)) }
                    for change in value.formatting where !change.accepted {
                        record(change.identity, location: location(range, .characterFormatting, separator: separator))
                    }
                }
                var offset = 0
                for run in paragraph.runs {
                    let count = run.text.utf16.count
                    review(run.review, range: NSRange(location: offset, length: count)); offset += count
                }
                review(paragraph.breakReview, range: NSRange(location: length, length: 1), separator: true)
            }
        }
        for section in document.sections { flow(section.paragraphs, noteID: nil) }
        for note in document.notes { flow(note.paragraphs, noteID: note.id) }
    }

    /// A stale selection starts at the first/last change. Navigation wraps.
    public func adjacent(to id: UUID?, backwards: Bool = false) -> IndexedRevision? {
        guard !changes.isEmpty else { return nil }
        guard let id, let index = changes.firstIndex(where: { $0.id == id || $0.componentIDs.contains(id) }) else {
            return backwards ? changes.last : changes.first
        }
        return changes[(index + (backwards ? changes.count - 1 : 1)) % changes.count]
    }
}
