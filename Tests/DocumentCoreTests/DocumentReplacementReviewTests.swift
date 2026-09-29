import Foundation
import XCTest
@testable import DocumentCore

final class DocumentReplacementReviewTests: XCTestCase {
    private let author = RevisionAuthor(name: "Writer")
    private func selection(_ document: ScribeDocument, start: Int, end: Int) -> TextAnchor {
        var anchor = TextAnchor(paragraphID: document.paragraphs[0].id, offset: start, length: 0)
        anchor.endParagraphID = document.paragraphs.last!.id; anchor.endOffset = end; return anchor
    }
    func testReplacingAcrossOwnListSplitRetainsOnlyAuthoredText() throws {
        var document = ScribeDocument(), paragraph = Paragraph("ABCD")
        paragraph.list = .init(kind: .decimal, start: 4, restart: true)
        document.sections[0].paragraphs = [paragraph]
        _ = try document.splitTrackedListItem(id: paragraph.id, range: NSRange(location: 2, length: 0), author: author)
        let caret = try document.replaceTrackedRange(selection(document, start: 1, end: 1), with: [TextRun("X")], author: author)
        XCTAssertEqual(document.paragraphs.map(\.text), ["ABCXD"])
        XCTAssertEqual(caret.paragraphID, paragraph.id); XCTAssertEqual(caret.offset, 4)
        var accepted = document; try accepted.resolveAllRevisions(accepting: true)
        XCTAssertEqual(accepted.paragraphs.map(\.text), ["AXD"])
        try document.resolveAllRevisions(accepting: false)
        XCTAssertEqual(document.paragraphs, [paragraph])
    }
    func testOriginalBoundariesAndAnotherAuthorsInsertionRemainReviewable() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs = [Paragraph("Alpha"), Paragraph("Beta"), Paragraph("Gamma")]
        let other = RevisionIdentity(author: .init(name: "Other"))
        var review = RunReview(); review.insertion = other
        document.sections[0].paragraphs[0].breakReview = review
        let original = document
        _ = try document.replaceTrackedRange(selection(document, start: 2, end: 2), with: [TextRun("X")], author: author)
        XCTAssertEqual(document.paragraphs.count, 3)
        XCTAssertEqual(document.paragraphs[0].breakReview?.insertion, other)
        let decisions = document.pendingRevisionIDs.filter { $0 != other.id }
        for id in decisions.reversed() { try document.resolveRevision(id, accepting: false) }
        XCTAssertEqual(document.paragraphs, original.paragraphs)
    }
    func testOwnDraftRemovalRebasesCommentsAndBookmarksDuringJoin() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs = [Paragraph("ABCD")]
        let firstID = document.paragraphs[0].id
        let secondID = try document.splitTrackedParagraph(id: firstID, range: NSRange(location: 2, length: 0), author: author)
        var text = RevisionText(runs: document.paragraphs[0].runs)
        _ = try text.replace(NSRange(location: 1, length: 0), with: [TextRun("draft")], insertion: .init(author: author), deletion: .init(author: author))
        document.sections[0].paragraphs[0].runs = text.runs
        document.comments = [.init(anchor: .init(paragraphID: secondID, offset: 1, length: 1), text: "D", author: "Reader")]
        document.bookmarks = [.init(name: "End", anchor: .init(paragraphID: secondID, offset: 0, length: 0))]
        _ = try document.replaceTrackedRange(selection(document, start: 1, end: 1), with: [TextRun("X")], author: author)
        XCTAssertEqual(document.paragraphs.map(\.text), ["ABCXD"])
        XCTAssertEqual(document.comments[0].anchor, .init(paragraphID: firstID, offset: 4, length: 1))
        XCTAssertEqual(document.bookmarks[0].anchor.paragraphID, firstID)
        XCTAssertNotEqual(document.comments[0].isDetached, true)
    }
    func testUnrelatedParagraphFormattingIsProtectedAtomically() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs = [Paragraph("AB")]
        _ = try document.splitTrackedParagraph(id: document.paragraphs[0].id, range: NSRange(location: 1, length: 0), author: author)
        let beforeFormat = document
        document.sections[0].paragraphs[1].styleID = "heading1"
        try document.recordParagraphFormattingChanges(from: beforeFormat, identity: .init(author: .init(name: "Other")))
        let before = document
        XCTAssertThrowsError(try document.replaceTrackedRange(selection(document, start: 0, end: 1), with: [], author: author))
        XCTAssertEqual(document, before)
    }
    func testReturnReplacementOfEntireOwnDraftListStillCreatesASeparator() throws {
        var document = ScribeDocument(), paragraph = Paragraph("")
        paragraph.list = .init(kind: .decimal)
        document.sections[0].paragraphs = [paragraph]
        var text = RevisionText(runs: [])
        _ = try text.replace(NSRange(location: 0, length: 0), with: [TextRun("AB")], insertion: .init(author: author), deletion: .init(author: author))
        document.sections[0].paragraphs[0].runs = text.runs
        _ = try document.splitTrackedParagraph(id: paragraph.id, range: NSRange(location: 1, length: 0), author: author)
        let caret = try document.replaceTrackedRange(selection(document, start: 0, end: 1), with: [], author: author)
        _ = try document.splitTrackedParagraph(id: caret.paragraphID, range: NSRange(location: caret.offset, length: 0), author: author, allowEmptyListExit: false)
        XCTAssertEqual(document.paragraphs.map(\.text), ["", ""])
        XCTAssertTrue(document.paragraphs.allSatisfy { $0.list != nil })
        try document.resolveAllRevisions(accepting: false)
        XCTAssertEqual(document.paragraphs, [paragraph])
    }
    func testInsertedNoteSurvivesAcceptanceAndIsRemovedOnRejection() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs = [Paragraph("AB"), Paragraph("CD")]
        let original = document, note = DocumentNote(kind: .footnote, text: "Source")
        var reference = TextRun("\u{FFFC}"); reference.noteID = note.id
        _ = try document.replaceTrackedRange(selection(document, start: 1, end: 1), with: [reference], author: author, insertedNotes: [note])
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
        var rejected = document; try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual(rejected.paragraphs, original.paragraphs); XCTAssertTrue(rejected.notes.isEmpty)
        try document.resolveAllRevisions(accepting: true)
        XCTAssertEqual(document.paragraphs.map(\.text), ["A\u{FFFC}D"])
        XCTAssertEqual(document.notes, [note]); try NativeFormat.validate(document)
    }
    func testInvalidScalarBoundaryDoesNotMutateDocument() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs = [Paragraph("A😀"), Paragraph("B")]
        let before = document
        XCTAssertThrowsError(try document.replaceTrackedRange(selection(document, start: 2, end: 1), with: [], author: author))
        XCTAssertEqual(document, before)
    }
}
