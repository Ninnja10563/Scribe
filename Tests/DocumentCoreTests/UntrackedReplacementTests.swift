import Foundation
import XCTest
@testable import DocumentCore

final class UntrackedReplacementTests: XCTestCase {
    func testJoinRebasesBookmarkAndReturnsSemanticCaretWithoutNewReviews() throws {
        var document = ScribeDocument()
        document.sections[0].paragraphs = [Paragraph("First"), Paragraph("Second")]
        let first = document.paragraphs[0].id, second = document.paragraphs[1].id
        document.bookmarks = [Bookmark(name: "Source", anchor: TextAnchor(paragraphID: second, offset: 0, length: 0))]
        document.comments = [Comment(anchor: TextAnchor(paragraphID: second, offset: 0, length: 6), text: "Source detail", author: "Reviewer")]
        var anchor = TextAnchor(paragraphID: first, offset: 5, length: 0)
        anchor.endParagraphID = second; anchor.endOffset = 0
        let caret = try document.replaceUntrackedRange(anchor, withLines: [[]])
        XCTAssertEqual(document.paragraphs.map(\.text), ["FirstSecond"])
        XCTAssertEqual(caret.paragraphID, first); XCTAssertEqual(caret.offset, 5)
        XCTAssertEqual(document.bookmarks[0].anchor.paragraphID, first)
        XCTAssertEqual(document.comments[0].anchor.paragraphID, first)
        XCTAssertEqual(document.comments[0].anchor.offset, 5)
        XCTAssertEqual(document.comments[0].anchor.length, 6)
        XCTAssertFalse(document.hasPendingRevisions)
        try NativeFormat.validate(document)
    }
    func testUnicodeMultilineReplacementKeepsEarlierUnrelatedRevision() throws {
        var document = ScribeDocument()
        document.sections[0].paragraphs = [Paragraph("A😀B"), Paragraph("CDEF")]
        var review = RunReview(); review.insertion = RevisionIdentity(author: .init(name: "Earlier"))
        document.sections[0].paragraphs[1].runs = [TextRun("CD"), TextRun("EF")]
        document.sections[0].paragraphs[1].runs[1].review = review
        var anchor = TextAnchor(paragraphID: document.paragraphs[0].id, offset: 1, length: 0)
        anchor.endParagraphID = document.paragraphs[1].id; anchor.endOffset = 1
        let caret = try document.replaceUntrackedRange(anchor, withLines: [[TextRun("X")], [TextRun("語")]])
        XCTAssertEqual(document.paragraphs.map(\.text), ["AX", "語DEF"])
        XCTAssertEqual(caret.paragraphID, document.paragraphs[1].id); XCTAssertEqual(caret.offset, 1)
        XCTAssertEqual(document.pendingRevisionIDs, [review.insertion!.id])
        try document.resolveAllRevisions(accepting: false)
        XCTAssertEqual(document.paragraphs.map(\.text), ["AX", "語D"])
    }
    func testInvalidScalarBoundaryLeavesSourceUnchanged() {
        var document = ScribeDocument(); document.sections[0].paragraphs = [Paragraph("😀")]
        let before = document
        XCTAssertThrowsError(try document.replaceUntrackedRange(TextAnchor(paragraphID: document.paragraphs[0].id, offset: 1, length: 0), withLines: [[TextRun("X")]]))
        XCTAssertEqual(document, before)
    }
}
