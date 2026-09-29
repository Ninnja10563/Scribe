#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ReviewSidebarTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testKeyboardSelectionDecisionsFocusAndRenderedPanel() throws {
        let document = ScribeFileDocument()
        let author = RevisionAuthor(name: "Alex Morgan")
        var inserted = TextRun("New introduction"), deleted = TextRun("Earlier wording")
        var insertion = RunReview(); insertion.insertion = RevisionIdentity(author: author)
        var deletion = RunReview(); deletion.deletion = RevisionIdentity(author: author)
        inserted.review = insertion; deleted.review = deletion
        document.model.sections[0].paragraphs[0].runs = [inserted, TextRun(" — "), deleted]
        document.makeWindowControllers(); defer { document.close() }
        let owner = document.editorController!, panel = owner.reviewSidebar
        owner.window?.makeKeyAndOrderFront(nil)
        panel.isHidden = false; panel.reload(document.snapshot())
        owner.window?.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.table.numberOfRows, 2)
        XCTAssertFalse(panel.accept.isEnabled)
        panel.nextChange()
        XCTAssertEqual(panel.selectedChange?.id, insertion.insertion?.id)
        XCTAssertTrue(panel.accept.isEnabled)
        XCTAssertTrue(panel.detail.stringValue.contains(author.name))
        XCTAssertTrue(panel.detail.stringValue.hasSuffix("New introduction"))
        XCTAssertTrue(owner.window?.firstResponder === panel.table)
        owner.window?.contentView?.layoutSubtreeIfNeeded()
        NativeDialogCapture.save(panel, name: "ReviewSidebar")
        owner.toggleFocus(); XCTAssertTrue(panel.isHidden)
        owner.toggleFocus(); XCTAssertFalse(panel.isHidden)
        document.undoManager?.removeAllActions()
        panel.rejectChange()
        XCTAssertEqual(document.snapshot().paragraphs[0].text, " — Earlier wording")
        XCTAssertEqual(panel.table.numberOfRows, 1)
        XCTAssertEqual(panel.selectedChange?.id, deletion.deletion?.id)
        XCTAssertTrue(owner.window?.firstResponder === panel.table)
        panel.acceptChange()
        XCTAssertEqual(panel.table.numberOfRows, 0)
        XCTAssertFalse(panel.accept.isEnabled); XCTAssertFalse(panel.reject.isEnabled)
        XCTAssertEqual(panel.detail.stringValue, "No pending changes.")
        document.undoManager?.undo()
        XCTAssertGreaterThan(panel.table.numberOfRows, 0)
        panel.rejectAllChanges()
        XCTAssertEqual(panel.table.numberOfRows, 0)
        XCTAssertFalse(document.snapshot().hasPendingRevisions)
    }
}
#endif
