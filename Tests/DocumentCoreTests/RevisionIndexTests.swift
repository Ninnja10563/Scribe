import Foundation
import XCTest
@testable import DocumentCore

final class RevisionIndexTests: XCTestCase {
    private let author = RevisionAuthor(name: "Writer")

    func testRichPasteIsOneNavigableDecisionAndGroupIDResolvesIt() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs = [Paragraph("AB")]
        let original = document
        var title = Paragraph(); title.styleID = "title"
        var quote = Paragraph(); quote.styleID = "quote"
        _ = try document.replaceTrackedRange(.init(paragraphID: document.paragraphs[0].id, offset: 1, length: 0),
            withLines: [[TextRun("X")], [TextRun("Y")]],
            paragraphProperties: [ParagraphRevisionState(title), ParagraphRevisionState(quote)], author: author)
        let index = RevisionIndex(document: document)
        XCTAssertEqual(index.changes.count, 1)
        let change = try XCTUnwrap(index.changes.first)
        XCTAssertEqual(change.componentIDs.count, 2)
        XCTAssertFalse(change.componentIDs.contains(change.id))
        XCTAssertEqual(Set(change.componentIDs), Set(document.pendingRevisionIDs))
        XCTAssertEqual(change.locations.filter(\.isParagraphSeparator).map(\.range), [NSRange(location: 2, length: 1)])
        var accepted = document; try accepted.resolveRevision(change.id, accepting: true)
        XCTAssertFalse(accepted.hasPendingRevisions)
        XCTAssertEqual(accepted.paragraphs.map(\.text), ["AX", "YB"])
        try document.resolveRevision(change.id, accepting: false)
        XCTAssertEqual(document.paragraphs, original.paragraphs)
        XCTAssertTrue(RevisionIndex(document: document).changes.isEmpty)
    }

    func testUnicodeRunExtentsCoalesceWithoutIncludingGeneratedListMarkers() {
        let identity = RevisionIdentity(author: author)
        var review = RunReview(); review.insertion = identity
        var first = TextRun("🙂"); first.review = review
        var second = TextRun("e\u{301}"); second.review = review; second.format.bold = true
        var paragraph = Paragraph("prefix")
        paragraph.list = .init(kind: .decimal, start: 12)
        paragraph.runs += [first, second, TextRun("tail")]
        var document = ScribeDocument(); document.sections[0].paragraphs = [paragraph]
        let change = RevisionIndex(document: document).changes[0]
        XCTAssertEqual(change.locations.count, 1)
        XCTAssertEqual(change.locations[0].range, NSRange(location: 6, length: 4))
        XCTAssertEqual(change.locations[0].paragraphID, paragraph.id)
        XCTAssertNil(change.locations[0].noteID)
    }

    func testAcceptedHistoryIsHiddenAndNotesHaveIndependentLocations() {
        let pending = RevisionIdentity(author: author), accepted = RevisionIdentity(author: author)
        var format = TextFormatting(); format.bold = true
        var later = FormattingRevision(identity: accepted, before: TextFormatting(), after: format); later.accepted = true
        var review = RunReview(); review.formattingBase = TextFormatting()
        review.formatting = [FormattingRevision(identity: pending, before: TextFormatting(), after: format), later]
        var run = TextRun("body", format: format); run.review = review
        var document = ScribeDocument(); document.sections[0].paragraphs[0].runs = [run]
        let deletion = RevisionIdentity(author: author)
        var note = DocumentNote(kind: .footnote, text: "deleted")
        var noteReview = RunReview(); noteReview.deletion = deletion
        note.paragraphs[0].runs[0].review = noteReview; document.notes = [note]
        let index = RevisionIndex(document: document)
        XCTAssertEqual(index.changes.map(\.id), [pending.id, deletion.id])
        XCTAssertEqual(index.changes[1].locations[0].noteID, note.id)
        XCTAssertEqual(index.changes[1].locations[0].paragraphID, note.paragraphs[0].id)
        XCTAssertEqual(index.changes[1].locations[0].kind, .deletion)
        XCTAssertEqual(index.adjacent(to: nil)?.id, pending.id)
        XCTAssertEqual(index.adjacent(to: pending.id, backwards: true)?.id, deletion.id)
        XCTAssertEqual(index.adjacent(to: deletion.id)?.id, pending.id)
        XCTAssertEqual(index.adjacent(to: accepted.id)?.id, pending.id)
        XCTAssertEqual(index.adjacent(to: UUID(), backwards: true)?.id, deletion.id)
        XCTAssertNil(RevisionIndex(document: ScribeDocument()).adjacent(to: nil))
    }

    func testGroupIDCannotAliasAComponentDecision() throws {
        var document = ScribeDocument()
        let first = RevisionIdentity(author: author)
        var second = RevisionIdentity(author: author, groupID: first.id)
        var one = RunReview(); one.insertion = first
        var two = RunReview(); two.insertion = second
        var a = TextRun("a"), b = TextRun("b"); a.review = one; b.review = two
        document.sections[0].paragraphs[0].runs = [a, b]
        XCTAssertThrowsError(try NativeFormat.validate(document))
        second.groupID = second.id; two.insertion = second
        document.sections[0].paragraphs[0].runs[1].review = two
        XCTAssertThrowsError(try NativeFormat.validate(document))
    }
}
