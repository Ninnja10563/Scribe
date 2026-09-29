import Foundation
import XCTest
@testable import DocumentCore

final class ParagraphReviewTests: XCTestCase {
    private func review(inserting: Bool) -> RunReview {
        var review = RunReview(); let identity = RevisionIdentity(author: .init(name: "Reviewer"))
        if inserting { review.insertion = identity } else { review.deletion = identity }
        return review
    }
    func testDeletedSeparatorRetainsParagraphsUntilAccepted() throws {
        var document = ScribeDocument(), first = Paragraph("First"), second = Paragraph("Second")
        first.breakReview = review(inserting: false)
        document.sections[0].paragraphs = [first, second]
        XCTAssertTrue(document.hasPendingRevisions); XCTAssertEqual(document.pendingRevisionIDs.count, 1)
        var rejected = document; try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual(rejected.paragraphs.map(\.text), ["First", "Second"])
        XCTAssertNil(rejected.paragraphs[0].breakReview)
        try document.resolveAllRevisions(accepting: true)
        XCTAssertEqual(document.paragraphs.map(\.text), ["FirstSecond"])
        XCTAssertEqual(document.paragraphs[0].id, first.id)
    }
    func testRejectInsertedSeparatorsJoinsChainAndRebasesCommentsAndBookmarks() throws {
        var document = ScribeDocument(), first = Paragraph("One"), second = Paragraph("Two"), third = Paragraph("Three")
        let revision = review(inserting: true)
        first.breakReview = revision; second.breakReview = revision
        document.sections[0].paragraphs = [first, second, third]
        document.comments = [Comment(anchor: .init(paragraphID: third.id, offset: 1, length: 3), text: "Third text", author: "Reviewer")]
        _ = document.addParagraphBookmark(name: "Third", paragraphID: third.id)
        try document.resolveAllRevisions(accepting: false)
        XCTAssertEqual(document.paragraphs.map(\.text), ["OneTwoThree"])
        XCTAssertEqual(document.comments[0].anchor.paragraphID, first.id)
        XCTAssertEqual(document.comments[0].anchor.offset, 7); XCTAssertEqual(document.comments[0].anchor.length, 3)
        XCTAssertEqual(document.bookmarks[0].anchor.paragraphID, first.id)
        XCTAssertFalse(document.hasPendingRevisions)
    }
    func testJoiningDifferentStylesPreservesCharacterAppearanceAndLaterReview() throws {
        var document = ScribeDocument(), first = Paragraph("Body "), second = Paragraph("Heading", style: "heading1")
        first.breakReview = review(inserting: false)
        let bold = RevisionIdentity(author: .init(name: "Reviewer"))
        var text = RevisionText(runs: second.runs)
        try text.format(NSRange(location: 0, length: 7), identity: bold) { var format = $0; format.italic = true; return format }
        second.runs = text.runs; document.sections[0].paragraphs = [first, second]
        try document.resolveRevision(first.breakReview!.deletion!.id, accepting: true)
        let joined = try XCTUnwrap(document.paragraphs[0].runs.last)
        XCTAssertEqual(joined.format.fontSize, 22); XCTAssertEqual(joined.format.bold, true)
        XCTAssertEqual(joined.format.italic, true)
        try document.resolveRevision(bold.id, accepting: false)
        XCTAssertEqual(document.paragraphs[0].runs.last?.format.fontSize, 22)
        XCTAssertEqual(document.paragraphs[0].runs.last?.format.bold, true)
        XCTAssertEqual(document.paragraphs[0].runs.last?.format.italic, false)
    }
    func testDecisionsCombineTextAndSeparatorDeletions() throws {
        var document = ScribeDocument(), first = Paragraph("AB"), second = Paragraph("CD")
        let mark = review(inserting: false)
        first.breakReview = mark; first.runs[0].review = mark; second.runs[0].review = mark
        document.sections[0].paragraphs = [first, second]
        try document.resolveAllRevisions(accepting: true)
        XCTAssertEqual(document.paragraphs.count, 1); XCTAssertEqual(document.paragraphs[0].text, "")
        try NativeFormat.validate(document)
    }
    func testBreaksInNotesPersistAndResolveWithoutChangingBody() throws {
        var document = ScribeDocument(), note = DocumentNote(kind: .endnote)
        var first = Paragraph("A"); first.breakReview = review(inserting: true)
        note.paragraphs = [first, Paragraph("B")]
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        document.notes = [note]; document.sections[0].paragraphs[0].runs = [reference]
        document = try NativeFormat.decode(NativeFormat.encode(document))
        try document.resolveAllRevisions(accepting: false)
        XCTAssertEqual(document.notes[0].paragraphs.map(\.text), ["AB"])
        XCTAssertEqual(document.paragraphs[0].runs[0].noteID, note.id)
    }
    func testLastParagraphAndCrossCellBreaksCannotBeTracked() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs[0].breakReview = review(inserting: false)
        XCTAssertThrowsError(try NativeFormat.validate(document))
        var first = Paragraph("A"), second = Paragraph("B")
        first.breakReview = review(inserting: true)
        second.tableCell = TableCellReference(tableID: UUID(), row: 0, column: 0)
        document.sections[0].paragraphs = [first, second]
        XCTAssertThrowsError(try NativeFormat.validate(document))
    }
}
