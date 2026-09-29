#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class EmptyNoteReviewTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    private func fixture(kind: DocumentNote.Kind, preceding: Int) throws -> ScribeFileDocument {
        let document = ScribeFileDocument()
        var note = DocumentNote(kind: kind)
        note.paragraphs = (0..<preceding).map { Paragraph("Citation paragraph \($0) contains useful source information for this document.") } + [Paragraph("")]
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        document.model.notes = [note]; document.model.sections[0].paragraphs[0].runs = [reference]
        let before = document.model
        var format = ParagraphFormatting(); format.alignment = .center
        document.model.notes[0].paragraphs[preceding].formatting = format
        try document.model.recordParagraphFormattingChanges(from: before, identity: .init(author: .init(name: "Writer")))
        document.makeWindowControllers(); return document
    }
    func testEmptyAndTrailingNoteParagraphsNavigateToTheirPhysicalPage() throws {
        for kind in [DocumentNote.Kind.footnote, .endnote] {
            for preceding in [0, 1, 90] {
                let document = try fixture(kind: kind, preceding: preceding); defer { document.close() }
                let owner = document.editorController!, editor = owner.editor
                let before = document.snapshot()
                let change = try XCTUnwrap(RevisionIndex(document: before).changes.first)
                let location = try XCTUnwrap(change.locations.first)
                XCTAssertEqual(location.range.length, 0)
                let match = try XCTUnwrap(ReviewLocationProjection.match(for: location, in: editor.storage, document: before))
                let page = try XCTUnwrap(NoteSearchPresentation().reveal(match, in: editor))
                let expected = kind == .footnote ? (try XCTUnwrap(editor.canvas.footnotes.keys.max())) + 1 : editor.canvas.pageCount
                XCTAssertEqual(page, expected)
                if preceding == 90 { XCTAssertGreaterThan(page, 1) }
                owner.reviewSidebar.isHidden = false; owner.reviewSidebar.reload(before)
                owner.reviewSidebar.nextChange()
                XCTAssertEqual(owner.reviewNavigation.selectedNotePage, page)
                XCTAssertTrue(owner.status.stringValue.hasPrefix("Page \(page) of"))
                XCTAssertTrue(owner.reviewSidebar.detail.stringValue.contains("Note: Empty paragraph formatting"))
                XCTAssertEqual(document.snapshot(), before)
                editor.select(NSRange(location: 0, length: 0))
                XCTAssertNil(owner.reviewNavigation.selectedNotePage)
            }
        }
    }
    func testCollapsedSemanticPositionsExcludeGeneratedLabelsAndRejectInvalidOffsets() throws {
        var note = DocumentNote(kind: .footnote, text: "🙂")
        note.paragraphs.append(Paragraph(""))
        let numbered = try XCTUnwrap(NoteNumbering.resolve(referenceIDs: [note.id], notes: [note]).first)
        let layout = try NoteTextLayout(note: numbered, styles: ParagraphStyle.defaults, width: 450)
        let snapshot = SemanticTextSnapshot(layout.storage)
        XCTAssertEqual(snapshot.text, "🙂\n")
        XCTAssertEqual(snapshot.sourceRange(forContentRange: NSRange(location: 0, length: 0)), NSRange(location: 3, length: 0))
        XCTAssertEqual(snapshot.sourceRange(forContentRange: NSRange(location: 3, length: 0)), NSRange(location: layout.storage.length, length: 0))
        XCTAssertNil(snapshot.sourceRange(forContentRange: NSRange(location: -1, length: 0)))
        XCTAssertNil(snapshot.sourceRange(forContentRange: NSRange(location: 4, length: 0)))
        XCTAssertEqual(snapshot.matches(query: "🙂"), [NSRange(location: 3, length: 2)])
    }
    func testFindAndReviewClearEachOthersNotePagePresentation() throws {
        let document = try fixture(kind: .endnote, preceding: 90); defer { document.close() }
        let owner = document.editorController!
        owner.reviewSidebar.isHidden = false; owner.reviewSidebar.reload(document.snapshot()); owner.reviewSidebar.nextChange()
        XCTAssertEqual(owner.reviewNavigation.selectedNotePage, owner.editor.canvas.pageCount)
        let search = owner.searchBar; search.isHidden = false; search.query.stringValue = "Citation paragraph 0"
        search.next()
        XCTAssertNil(owner.reviewNavigation.selectedNotePage)
        XCTAssertEqual(search.selectedNotePage, owner.editor.canvas.bodyPageCount + 1)
        owner.reviewSidebar.nextChange()
        XCTAssertNil(search.selectedNotePage)
        XCTAssertEqual(owner.reviewNavigation.selectedNotePage, owner.editor.canvas.pageCount)
    }
}
#endif
