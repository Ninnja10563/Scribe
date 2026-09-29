#if canImport(AppKit)
import AppKit
import DocumentCore

/// Internal command coordinator. The public review controls are added only
/// after the remaining editing paths preserve revisions reliably.
@MainActor final class ReviewNavigation {
    weak var owner: EditorWindowController?
    private(set) var selectedID: UUID?
    private(set) var selectedNotePage: Int?
    private var isRevealing = false
    func nativeSelectionChanged() { if !isRevealing { selectedNotePage = nil } }
    private let notes = NoteSearchPresentation()
    init(owner: EditorWindowController) { self.owner = owner }

    private func committedDocument() -> ScribeDocument? {
        guard let owner, !owner.isClosing else { return nil }
        for view in owner.editor.textViews where view.reviewComposition != nil { view.unmarkText() }
        owner.editor.reviewEditing.resetGrouping()
        return owner.fileDocument.snapshot()
    }
    @discardableResult func navigate(backwards: Bool = false) -> IndexedRevision? {
        guard let document = committedDocument() else { return nil }
        let change = RevisionIndex(document: document).adjacent(to: selectedID, backwards: backwards)
        selectedID = change?.id; selectedNotePage = nil
        if let change { reveal(change, document: document) }
        return change
    }
    @discardableResult func select(_ id: UUID) -> Bool {
        guard let document = committedDocument(),
              let change = RevisionIndex(document: document).changes.first(where: { $0.id == id || $0.componentIDs.contains(id) }) else { selectedID = nil; selectedNotePage = nil; return false }
        selectedID = change.id; reveal(change, document: document); return true
    }
    func resolveCurrent(accepting: Bool) throws {
        guard let document = committedDocument(), let owner, let selectedID else { return }
        let index = RevisionIndex(document: document)
        guard let position = index.changes.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = nil; selectedNotePage = nil; return // A stale selection must never decide another change.
        }
        var updated = document
        try updated.resolveRevision(selectedID, accepting: accepting)
        selectedNotePage = nil
        owner.fileDocument.applyReviewedStructure(updated, replacing: document, name: accepting ? "Accept Change" : "Reject Change")
        let remaining = RevisionIndex(document: updated).changes
        let surviving = Set(remaining.map(\.id))
        let following = Array(index.changes.dropFirst(position + 1)) + Array(index.changes.prefix(position))
        self.selectedID = following.first(where: { surviving.contains($0.id) })?.id
        if let next = remaining.first(where: { $0.id == self.selectedID }) { reveal(next, document: updated) }
    }
    func resolveAll(accepting: Bool) throws {
        guard let document = committedDocument(), let owner else { return }
        var updated = document; try updated.resolveAllRevisions(accepting: accepting)
        selectedNotePage = nil
        owner.fileDocument.applyReviewedStructure(updated, replacing: document, name: accepting ? "Accept All Changes" : "Reject All Changes")
        selectedID = nil; selectedNotePage = nil
    }
    private func reveal(_ change: IndexedRevision, document: ScribeDocument) {
        guard let owner, !owner.isClosing else { return }
        selectedNotePage = nil; owner.searchBar.clearNotePresentation(); isRevealing = true
        defer { isRevealing = false; owner.updateStatus() }
        for location in change.locations {
            guard let match = ReviewLocationProjection.match(for: location, in: owner.editor.storage, document: document) else { continue }
            switch match {
            case .body(let range): owner.editor.select(range)
            case .note: selectedNotePage = notes.reveal(match, in: owner.editor)
            }
            return
        }
    }
}
#endif
